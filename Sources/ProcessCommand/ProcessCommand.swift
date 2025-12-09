// The Swift Programming Language
// https://docs.swift.org/swift-book
// ProcessCommandModule/Sources/ProcessCommandModule/ProcessCommand.swift

import Foundation
import OSLog

public enum CommandError: LocalizedError {
    case executableNotFound
    case invalidExecutablePath(String)
    case processLaunchFailed(Error)
    case outputEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Command executable not found. Please verify the command path."
        case let .invalidExecutablePath(path):
            "Invalid command executable path: \(path)"
        case let .processLaunchFailed(error):
            "Failed to launch rsync process: \(error.localizedDescription)"
        case .outputEncodingFailed:
            "Failed to decode rsync output as UTF-8"
        }
    }
}

/// A module for executing and managing system processes with async output handling
@MainActor
public final class ProcessCommand {
    // Process handlers
    let handlers: ProcessHandlersCommand

    // MARK: - Public Properties

    /// The command to execute
    public var command: String?
    /// Arguments for the command
    public var arguments: [String]?
    /// Accumulated output from the process
    public private(set) var output = [String]()
    /// Whether an error was discovered during execution
    public private(set) var errordiscovered: Bool = false

    // MARK: - Private Properties

    private var oneargumentisjsonordump: [Bool]?
    private var sequenceFileHandlerTask: Task<Void, Never>?
    private var sequenceTerminationTask: Task<Void, Never>?
    private var input: String?
    private var syncmode: String?

    private var strings: SharedStrings {
        SharedStrings()
    }

    // MARK: - Public Initializers

    /// Initialize with full configuration
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Command arguments
    ///   - syncmode: Optional sync mode configuration
    ///   - input: Optional immediate input
    ///   - processtermination: Callback for process termination
    public init(
        command: String?,
        arguments: [String]?,
        handlers: ProcessHandlersCommand,
        syncmode: String? = nil,
        input: String? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.handlers = handlers
        self.syncmode = syncmode
        self.input = input
        oneargumentisjsonordump = arguments?.compactMap { line in
            line.contains("--json") || line.contains("dump") ? true : nil
        }
    }

    /// Convenience initializer with default termination handler
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Command arguments
    public convenience init(
        command: String?,
        arguments: [String]?,
        handlers: ProcessHandlersCommand
    ) {
        self.init(
            command: command,
            arguments: arguments,
            handlers: handlers,
            syncmode: nil,
            input: nil
        )
    }

    deinit {
        Logger.process.debugmesseageonly("ProcessHandlers: DEINIT")
    }

    // MARK: - Public Methods

    /// Execute the configured process
    public func executeProcess() throws {
        guard let command, let arguments, !arguments.isEmpty else {
            Logger.process.warning("ProcessCommand: Missing command or arguments")
            return
        }
        let executableURL = URL(fileURLWithPath: command)
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CommandError.invalidExecutablePath(command)
        }

        let task = Process()
        task.executableURL = executableURL
        task.arguments = arguments

        // Pipe for stdin
        let inputPipe = Pipe()
        task.standardInput = inputPipe

        // Pipe for stdout/stderr
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        let outHandle = outputPipe.fileHandleForReading
        outHandle.waitForDataInBackgroundAndNotify()

        let sequencefilehandler = NotificationCenter.default.notifications(
            named: NSNotification.Name.NSFileHandleDataAvailable,
            object: outHandle
        )
        let sequencetermination = NotificationCenter.default.notifications(
            named: Process.didTerminateNotification,
            object: task
        )

        sequenceFileHandlerTask = Task {
            Logger.process.debugtthreadonly("ProcessCommand: sequenceFileHandlerTask")
            for await _ in sequencefilehandler {
                if handlers.rsyncui {
                    await self.datahandle(outputPipe)
                } else {
                    await self.datahandlejottaui(outputPipe, inputPipe)
                }
            }
            Logger.process.debugmesseageonly("ProcessCommand: sequenceFileHandlerTask completed")
        }

        sequenceTerminationTask = Task {
            Logger.process.debugtthreadonly("sequenceTerminationTask: sequenceFileHandlerTask")
            for await _ in sequencetermination {
                Logger.process.debugmesseageonly("ProcessCommand: Process terminated - starting drain")

                sequenceFileHandlerTask?.cancel()
                try? await Task.sleep(nanoseconds: 50_000_000)

                var totalDrained = 0
                while true {
                    let data: Data = outputPipe.fileHandleForReading.availableData
                    if data.isEmpty {
                        Logger.process.debugmesseageonly("ProcessCommand: Drain complete - \(totalDrained) bytes total")
                        break
                    }

                    totalDrained += data.count
                    Logger.process.debugmesseageonly("ProcessCommand: Draining \(data.count) bytes")

                    if let text = String(data: data, encoding: .utf8) {
                        Logger.process.debugmesseageonly("ProcessCommand: Drained text available")
                        self.output.append(text)
                    }
                }

                await self.termination()
            }
        }

        // Update current process task
        handlers.updateprocess(task)

        do {
            try task.run()
            if let launchPath = task.launchPath, let arguments = task.arguments {
                Logger.process.debugmesseageonly("ProcessCommand: command - \(launchPath)")
                Logger.process.debugmesseageonly("ProcessCommand: arguments - \(arguments.joined(separator: "\n"))")
            }
        } catch let err {
            let error = err
            // SharedReference.shared.errorobject?.alert(error: error)
            handlers.propogateerror(error)
        }
    }

    // MARK: - Private Methods

    private func datahandle(_ pipe: Pipe) async {
        let outHandle = pipe.fileHandleForReading
        let data = outHandle.availableData
        if data.count > 0 {
            if let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
                str.enumerateLines { line, _ in
                    self.output.append(line)

                    if self.errordiscovered == false {
                        do {
                            try self.handlers.checklineforerror(line)
                        } catch let err {
                            self.errordiscovered = true
                            let error = err
                            self.handlers.propogateerror(error)
                        }
                    }
                }
            }
            outHandle.waitForDataInBackgroundAndNotify()
        }
    }

    private func datahandlejottaui(_ pipe: Pipe, _ inputPipe: Pipe) async {
        let outHandle = pipe.fileHandleForReading
        let data = outHandle.availableData

        guard data.count > 0 else { return }

        if let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
            str.enumerateLines { line, _ in
                self.output.append(line)
                // Handle interactive prompts
                self.handleInteractivePrompts(line: line, inputPipe: inputPipe)

                if self.errordiscovered == false, self.oneargumentisjsonordump?.count == 0 {
                    do {
                        try self.handlers.checklineforerror(line)
                    } catch let err {
                        self.errordiscovered = true
                        let error = err
                        self.handlers.propogateerror(error)
                    }
                }
            }
        }
        outHandle.waitForDataInBackgroundAndNotify()
    }

    // For JottaUI
    private func handleInteractivePrompts(line: String, inputPipe: Pipe) {
        if line.contains(strings.continueSyncSetup) {
            let reply = input ?? "yes"
            if let data = (reply + "\n").data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
        }

        if line.contains(strings.chooseErrorReportingMode) {
            let reply = syncmode ?? "full"
            if let data = (reply + "\n").data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
        }

        if line.contains(strings.continueSyncReset) {
            let reply = input ?? "y"
            if let data = (reply + "\n").data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
        }

        if line.contains(strings.theExistingSyncFolderOnJottacloudCom) {
            let reply = input ?? "n"
            if let data = (reply + "\n").data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
        }
    }

    private func termination() async {
        Logger.process.debugtthreadonly("ProcessCommand: process = nil and termination discovered")
        handlers.processtermination(output, errordiscovered)
        // Log error in rsync output to file
        if errordiscovered, let command {
            Task {
                await handlers.logger(command, output)
            }
        }
        // Set current process to nil
        handlers.updateprocess(nil)
        // Cancel Tasks
        sequenceFileHandlerTask?.cancel()
        sequenceTerminationTask?.cancel()
        sequenceFileHandlerTask = nil
        sequenceTerminationTask = nil
    }
}

// Prefer positive checks with #if canImport(...) so the "normal" (module-present) path is first.
// If the module exists it will be imported; otherwise a clear fallback is provided.

#if canImport(SharedStrings)
    import SharedStrings
#else
    /// Fallback for SharedStrings — implement or replace with real strings
    struct SharedStrings {
        static let shared = SharedStrings()
        let continueSyncSetup = "continue sync setup"
        let chooseErrorReportingMode = "choose error reporting mode"
        let continueSyncReset = "continue sync reset"
        let theExistingSyncFolderOnJottacloudCom = "existing sync folder"
    }
#endif
