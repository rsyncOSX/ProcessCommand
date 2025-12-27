import Foundation
@testable import ProcessCommand
import Testing

enum JottaCliError: LocalizedError {
    case clierror

    var errorDescription: String? {
        switch self {
        case .clierror:
            "There are errors in output from Jotta-cli"
        }
    }
}

actor ActorToFile {
    private func logging(command _: String, stringoutput: [String]) async {
        var logfile: String?

        if logfile == nil {
            logfile = stringoutput.joined(separator: "\n")
        } else {
            logfile = (logfile ?? "") + stringoutput.joined(separator: "\n")
        }
        if let logfile {
            print(logfile)
        }
    }

    @discardableResult
    init(_ command: String, _ stringoutput: [String]?) async {
        if let stringoutput {
            await logging(command: command, stringoutput: stringoutput)
        }
    }
}

// Helper function to build the full path from the home directory.
// This makes the test code cleaner.
private func pathInHomeTmp(for file: String) -> String {
    let homePath = NSHomeDirectory()
    return "\(homePath)/tmp/\(file)"
}

@MainActor
@Suite("ProcessCommand Tests")
struct ProcessCommandTests {
    @MainActor
    @Test("Execute handling input - JottaUI")
    func executeMyCommand() async throws {
        let testAppPath = pathInHomeTmp(for: "processtest")
        // If not, skip the test.
        guard FileManager.default.fileExists(atPath: testAppPath) else {
            // Throws a Skip error, marking the test as "Skipped".
            // try Skip("Test executable not found at \(testAppPath)")
            return
        }
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in },
            checklineforerror: { line in
                let error = line.contains("Error") || line.contains("error")
                if error {
                    throw JottaCliError.clierror
                }
            },
            updateprocess: { _ in },
            propogateerror: { _ in },
            logger: { command, output in
                _ = await ActorToFile(command, output)
            },
            rsyncui: false
        )
        let process = ProcessCommand(
            command: testAppPath,
            arguments: ["no args"],
            handlers: handlers
        )

        try process.executeProcess()
        // Give process time to complete
        try await Task.sleep(nanoseconds: 6_000_000_000)

        // #expect(state.processUpdateCalled == true)
        // #expect(state.mockOutput != nil)
    }

    @MainActor
    @Test("Throws when command missing")
    func executeMissingCommandThrows() async {
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in },
            checklineforerror: { _ in },
            updateprocess: { _ in },
            propogateerror: { _ in },
            logger: { _, _ in },
            rsyncui: true
        )

        let process = ProcessCommand(
            command: nil,
            arguments: ["arg"],
            handlers: handlers
        )

        #expect(throws: CommandError.executableNotFound) {
            try process.executeProcess()
        }
    }

    @MainActor
    @Test("Invalid UTF8 output surfaces error")
    func executeInvalidUTF8() async throws {
        let printfPath = "/usr/bin/printf"
        guard FileManager.default.isExecutableFile(atPath: printfPath) else {
            return
        }

        var propagatedError: Error?
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in },
            checklineforerror: { _ in },
            updateprocess: { _ in },
            propogateerror: { error in
                propagatedError = error
            },
            logger: { _, _ in },
            rsyncui: true
        )

        // \xff is invalid UTF-8 on its own; printf will emit raw 0xFF
        let process = ProcessCommand(
            command: printfPath,
            arguments: ["\\xff"],
            handlers: handlers
        )

        try process.executeProcess()
        try await Task.sleep(nanoseconds: 1_000_000_000)

        #expect(propagatedError as? CommandError == CommandError.outputEncodingFailed)
    }
}
