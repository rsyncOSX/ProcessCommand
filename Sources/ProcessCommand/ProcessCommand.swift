// The Swift Programming Language
// https://docs.swift.org/swift-book
// ProcessCommandModule/Sources/ProcessCommandModule/ProcessCommand.swift

import Foundation
import OSLog

/// A module for executing and managing system processes with async output handling
@MainActor
public final class ProcessCommand {
    
    // MARK: - Public Properties
    
    /// Callback executed when process terminates
    public var processtermination: ([String]?, Bool) -> Void
    
    /// The command to execute
    public var command: String?
    
    /// Arguments for the command
    public var arguments: [String]?
    
    /// Accumulated output from the process
    public private(set) var output = [String]()
    
    /// Whether an error was discovered during execution
    public private(set) var errordiscovered: Bool = false
    
    // MARK: - Private Properties
    
    private var checkforerror = CheckForError()
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
        syncmode: String? = nil,
        input: String? = nil,
        processtermination: @escaping ([String]?, Bool) -> Void
    ) {
        self.command = command
        self.arguments = arguments
        self.syncmode = syncmode
        self.input = input
        self.processtermination = processtermination
        self.oneargumentisjsonordump = arguments?.compactMap { line in
            line.contains("--json") || line.contains("dump") ? true : nil
        }
    }
    
    /// Convenience initializer with default termination handler
    /// - Parameters:
    ///   - command: The command to execute
    ///   - arguments: Command arguments
    public convenience init(
        command: String?,
        arguments: [String]?
    ) {
        let processtermination: ([String]?, Bool) -> Void = { _, _ in
            Logger.process.info("ProcessCommand: Process terminated with default handler")
        }
        self.init(
            command: command,
            arguments: arguments,
            syncmode: nil,
            input: nil,
            processtermination: processtermination
        )
    }
    
    // MARK: - Public Methods
    
    /// Execute the configured process
    public func executeProcess() {
        guard let command, let arguments, !arguments.isEmpty else {
            Logger.process.warning("ProcessCommand: Missing command or arguments")
            return
        }
        
        let task = Process()
        task.launchPath = command
        task.arguments = arguments
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        let outHandle = pipe.fileHandleForReading
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
            for await _ in sequencefilehandler {
                await self.datahandle(pipe)
            }
            Logger.process.info("ProcessCommand: sequenceFileHandlerTask completed")
        }
        
        sequenceTerminationTask = Task {
            for await _ in sequencetermination {
                Logger.process.info("ProcessCommand: Process terminated - starting drain")
                sequenceFileHandlerTask?.cancel()
                try? await Task.sleep(nanoseconds: 50_000_000)
                
                var totalDrained = 0
                while true {
                    let data: Data = pipe.fileHandleForReading.availableData
                    if data.isEmpty {
                        Logger.process.info("ProcessCommand: Drain complete - \(totalDrained) bytes total")
                        break
                    }
                    
                    totalDrained += data.count
                    Logger.process.info("ProcessCommand: Draining \(data.count) bytes")
                    
                    if let text = String(data: data, encoding: .utf8) {
                        Logger.process.info("ProcessCommand: Drained text available")
                        self.output.append(text)
                    }
                }
                
                await self.termination()
            }
        }
        
        SharedReference.shared.process = task
        
        do {
            try task.run()
            if let launchPath = task.launchPath, let arguments = task.arguments {
                Logger.process.info("ProcessCommand: command - \(launchPath, privacy: .public)")
                Logger.process.info("ProcessCommand: arguments - \(arguments.joined(separator: "\n"), privacy: .public)")
            }
        } catch {
            propogateerror(error: error)
        }
    }
    
    // MARK: - Private Methods
    
    private func datahandle(_ pipe: Pipe) async {
        let outHandle = pipe.fileHandleForReading
        let data = outHandle.availableData
        
        guard data.count > 0 else { return }
        
        if let str = NSString(data: data, encoding: String.Encoding.utf8.rawValue) {
            str.enumerateLines { line, _ in
                if self.errordiscovered == false, self.oneargumentisjsonordump?.count == 0 {
                    do {
                        try self.checkforerror.checkforerror(line)
                    } catch {
                        self.errordiscovered = true
                        self.propogateerror(error: error)
                    }
                }
                
                self.output.append(line)
                
                // Handle interactive prompts
                self.handleInteractivePrompts(line: line, pipe: pipe)
            }
        }
        outHandle.waitForDataInBackgroundAndNotify()
    }
    
    private func handleInteractivePrompts(line: String, pipe: Pipe) {
        if line.contains(strings.continueSyncSetup) {
            let reply = input ?? "yes"
            pipe.fileHandleForWriting.write((reply + "\n").data(using: .utf8)!)
        }
        
        if line.contains(strings.chooseErrorReportingMode) {
            let reply = syncmode ?? "full"
            pipe.fileHandleForWriting.write((reply + "\n").data(using: .utf8)!)
        }
        
        if line.contains(strings.continueSyncReset) {
            let reply = input ?? "y"
            pipe.fileHandleForWriting.write((reply + "\n").data(using: .utf8)!)
        }
        
        if line.contains(strings.theExistingSyncFolderOnJottacloudCom) {
            let reply = input ?? "n"
            pipe.fileHandleForWriting.write((reply + "\n").data(using: .utf8)!)
        }
    }
    
    private func termination() async {
        processtermination(output, errordiscovered)
        
        if errordiscovered, let command {
            Task {
                await ActorJottaUILogToFile(command: command, stringoutput: output)
            }
        }
        
        SharedReference.shared.process = nil
        sequenceFileHandlerTask?.cancel()
        sequenceTerminationTask?.cancel()
        Logger.process.info("ProcessCommand: process = nil and termination discovered")
    }
    
    private func propogateerror(error: Error) {
        SharedReference.shared.errorobject?.alert(error: error)
    }
    
    deinit {
        Logger.process.info("ProcessCommand: DEINIT")
    }
}

// MARK: - Supporting Types

/// Logger extension for process-related logging
extension Logger {
    static let process = Logger(subsystem: "com.processcommand", category: "process")
}

// Prefer positive checks with #if canImport(...) so the "normal" (module-present) path is first.
// If the module exists it will be imported; otherwise a clear fallback is provided.

#if canImport(CheckForError)
import CheckForError
#else
/// Fallback for CheckForError — implement as needed
struct CheckForError {
    func checkforerror(_ line: String) throws {
        if line.lowercased().contains("error") {
            throw ProcessError.errorDetected(line)
        }
    }
}
#endif

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

#if canImport(SharedReference)
import SharedReference
#else
/// Fallback for SharedReference — lightweight placeholder
@MainActor final class SharedReference {
    @MainActor static let shared = SharedReference()
    var process: Process?
    var errorobject: ErrorHandler?
    private init() {}
}
#endif

#if canImport(ErrorHandler)
import ErrorHandler
#else
/// Fallback for ErrorHandler — simple alert-style logger
final class ErrorHandler {
    func alert(error: Error) {
        print("Error: \(error)")
    }
}
#endif

#if canImport(ActorJottaUILogToFile)
import ActorJottaUILogToFile
#else
/// Fallback logger function for environments without the actor
func ActorJottaUILogToFile(command: String, stringoutput: [String]) async {
    print("[ActorJottaUILogToFile] \(command):")
    for line in stringoutput { print(line) }
}
#endif

#if canImport(ProcessError)
import ProcessError
#else
/// Process errors
public enum ProcessError: Error {
    case errorDetected(String)
    case commandNotFound
    case executionFailed
}
#endif
