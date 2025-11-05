import Testing
@testable import ProcessCommand
import Foundation

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
            logfile! += stringoutput.joined(separator: "\n")
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

@MainActor
@Suite("ProcessCommand Tests")
struct ProcessCommandTests {
    
    // MARK: - Helper Class for Test State
    
    @MainActor
    final class TestState {
        var mockOutput: [String]?
        var errorDiscovered: Bool = false
        var processUpdateCalled: Bool = false
        var errorPropagated: Error?
        var loggerCalled: Bool = false
        var loggedCommand: String?
        var loggedOutput: [String]?
        
        func reset() {
            mockOutput = nil
            errorDiscovered = false
            processUpdateCalled = false
            errorPropagated = nil
            loggerCalled = false
            loggedCommand = nil
            loggedOutput = nil
        }
    }
    
    // MARK: - Helper Methods
    
    func createMockHandlers(
        rsyncui: Bool = false,
        shouldThrowError: Bool = false,
        state: TestState
    ) -> ProcessHandlersCommand {
        ProcessHandlersCommand(
            processtermination: { output, errorDiscovered in
                state.mockOutput = output
                state.errorDiscovered = errorDiscovered
            },
            checklineforerror: { line in
                if shouldThrowError && line.contains("error") {
                    throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock error"])
                }
            },
            updateprocess: { process in
                state.processUpdateCalled = true
            },
            propogateerror: { error in
                state.errorPropagated = error
            },
            logger: { command, output in
                _ = await ActorToFile(command, output)
            },
            rsyncui: rsyncui
        )
    }
    
    // MARK: - Initialization Tests
    
    @Test("ProcessCommand full initialization")
    func fullInitialization() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        
        let process = ProcessCommand(
            command: "/bin/echo",
            arguments: ["hello", "world"],
            handlers: handlers,
            syncmode: "full",
            input: "yes"
        )
        
        #expect(process.command == "/bin/echo")
        #expect(process.arguments == ["hello", "world"])
        #expect(process.output.isEmpty)
        #expect(process.errordiscovered == false)
    }
    
    @Test("ProcessCommand convenience initializer")
    func convenienceInitializer() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        
        let process = ProcessCommand(
            command: "/bin/ls",
            arguments: ["-la"],
            handlers: handlers
        )
        
        #expect(process.command == "/bin/ls")
        #expect(process.arguments == ["-la"])
        #expect(process.output.isEmpty)
    }
    
    @Test("ProcessCommand with JSON argument detection")
    func jsonArgumentDetection() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        
        let process = ProcessCommand(
            command: "/usr/bin/some-tool",
            arguments: ["--json", "output.json"],
            handlers: handlers
        )
        
        #expect(process.command == "/usr/bin/some-tool")
        #expect(process.arguments?.contains("--json") == true)
    }
    
    @Test("ProcessCommand with dump argument detection")
    func dumpArgumentDetection() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        
        let process = ProcessCommand(
            command: "/usr/bin/tool",
            arguments: ["dump", "data"],
            handlers: handlers
        )
        
        #expect(process.arguments?.contains("dump") == true)
    }
    
    // MARK: - Error Tests
    
    @Test("CommandError.executableNotFound description")
    func executableNotFoundDescription() {
        let error = CommandError.executableNotFound
        #expect(error.errorDescription == "Command executable not found. Please verify the command path.")
    }
    
    @Test("CommandError.invalidExecutablePath description")
    func invalidExecutablePathDescription() {
        let error = CommandError.invalidExecutablePath("/invalid/path")
        #expect(error.errorDescription == "Invalid command executable path: /invalid/path")
    }
    
    @Test("CommandError.processLaunchFailed description")
    func processLaunchFailedDescription() {
        let testError = NSError(domain: "test", code: 1, userInfo: nil)
        let error = CommandError.processLaunchFailed(testError)
        #expect(error.errorDescription?.contains("Failed to launch rsync process") == true)
    }
    
    @Test("CommandError.outputEncodingFailed description")
    func outputEncodingFailedDescription() {
        let error = CommandError.outputEncodingFailed
        #expect(error.errorDescription == "Failed to decode rsync output as UTF-8")
    }
    
    @Test("Execute process with invalid executable path throws error")
    func invalidExecutablePathThrows() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: "/nonexistent/command",
            arguments: ["arg1"],
            handlers: handlers
        )
        
        #expect(throws: CommandError.self) {
            try process.executeProcess()
        }
    }
    
    @Test("Execute process with nil command does not throw")
    func nilCommandDoesNotThrow() throws {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: nil,
            arguments: ["arg1"],
            handlers: handlers
        )
        
        // Should return early without throwing
        try process.executeProcess()
        #expect(process.output.isEmpty)
    }
    
    @Test("Execute process with empty arguments does not throw")
    func emptyArgumentsDoesNotThrow() throws {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: "/bin/echo",
            arguments: [],
            handlers: handlers
        )
        
        // Should return early without throwing
        try process.executeProcess()
        #expect(process.output.isEmpty)
    }
    
    // MARK: - ProcessHandlersCommand Tests
    
    @Test("ProcessHandlersCommand initialization")
    func handlersInitialization() {
        var terminationCalled = false
        var errorCheckCalled = false
        var updateCalled = false
        var errorPropagatedCalled = false
        
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in terminationCalled = true },
            checklineforerror: { _ in errorCheckCalled = true },
            updateprocess: { _ in updateCalled = true },
            propogateerror: { _ in errorPropagatedCalled = true },
            logger: { command, output in
                _ = await ActorToFile(command, output)
            },
            rsyncui: true
        )
        
        handlers.processtermination(nil, false)
        try? handlers.checklineforerror("test")
        handlers.updateprocess(nil)
        handlers.propogateerror(NSError(domain: "test", code: 1))
        Task { await handlers.logger("test", []) }
        
        #expect(terminationCalled)
        #expect(errorCheckCalled)
        #expect(updateCalled)
        #expect(errorPropagatedCalled)
        #expect(handlers.rsyncui == true)
    }
    
    @Test("ProcessHandlersCommand with rsyncui false")
    func handlersWithRsyncuiFalse() {
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in },
            checklineforerror: { _ in },
            updateprocess: { _ in },
            propogateerror: { _ in },
            logger: { command, output in
                _ = await ActorToFile(command, output)
            },
            rsyncui: false
        )
        
        #expect(handlers.rsyncui == false)
    }
    
    // MARK: - Output Tests
    
    @Test("Output starts empty")
    func outputStartsEmpty() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: "/bin/echo",
            arguments: ["test"],
            handlers: handlers
        )
        
        #expect(process.output.isEmpty)
    }
    
    @Test("Error discovered flag starts false")
    func errorDiscoveredStartsFalse() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: "/bin/echo",
            arguments: ["test"],
            handlers: handlers
        )
        
        #expect(process.errordiscovered == false)
    }
    
    // MARK: - Thread Safety Tests
    
    @Test("ThreadUtils detects main thread")
    func threadUtilsIsMain() async {
        let isMainThread = await MainActor.run {
            ThreadUtils.isMain
        }
        #expect(isMainThread == true)
    }
    
    // MARK: - Integration Tests
    
    @Test("Execute echo command", .enabled(if: FileManager.default.fileExists(atPath: "/bin/echo")))
    func executeEchoCommand() async throws {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: "/bin/echo",
            arguments: ["Hello", "World"],
            handlers: handlers
        )
        
        try process.executeProcess()
        
        // Give process time to complete
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        #expect(state.processUpdateCalled == true)
        #expect(state.mockOutput != nil)
    }
    
    @Test("Execute ls command", .enabled(if: FileManager.default.fileExists(atPath: "/bin/ls")))
    func executeLsCommand() async throws {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: "/bin/ls",
            arguments: ["-la", "/tmp"],
            handlers: handlers
        )
        
        try process.executeProcess()
        
        // Give process time to complete
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        #expect(state.processUpdateCalled == true)
        #expect(state.errorDiscovered == false)
    }
    
    // MARK: - Sync Mode Tests
    
    @Test("ProcessCommand with full sync mode")
    func fullSyncMode() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: "/bin/echo",
            arguments: ["test"],
            handlers: handlers,
            syncmode: "full"
        )
        
        #expect(process.command != nil)
    }
    
    @Test("ProcessCommand with input parameter")
    func withInputParameter() {
        let state = TestState()
        let handlers = createMockHandlers(state: state)
        let process = ProcessCommand(
            command: "/bin/cat",
            arguments: ["-"],
            handlers: handlers,
            syncmode: nil,
            input: "test input"
        )
        
        #expect(process.command != nil)
    }
    
    // MARK: - Memory Management Tests
    
    @Test("ProcessCommand deallocates properly")
    func processDeinit() {
        let state = TestState()
        var process: ProcessCommand? = ProcessCommand(
            command: "/bin/echo",
            arguments: ["test"],
            handlers: createMockHandlers(state: state)
        )
        
        weak var weakProcess = process
        process = nil
        
        #expect(weakProcess == nil)
    }
}

// MARK: - Additional Test Suites

@Suite("CommandError Tests")
struct CommandErrorTests {
    
    @Test("All error cases have descriptions")
    func allErrorsHaveDescriptions() {
        let errors: [CommandError] = [
            .executableNotFound,
            .invalidExecutablePath("/test/path"),
            .processLaunchFailed(NSError(domain: "test", code: 1)),
            .outputEncodingFailed
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
    
    @Test("Error descriptions are unique")
    func errorDescriptionsAreUnique() {
        let errors: [CommandError] = [
            .executableNotFound,
            .invalidExecutablePath("/test"),
            .processLaunchFailed(NSError(domain: "test", code: 1)),
            .outputEncodingFailed
        ]
        
        let descriptions = errors.compactMap { $0.errorDescription }
        let uniqueDescriptions = Set(descriptions)
        
        #expect(descriptions.count == uniqueDescriptions.count)
    }
}

@Suite("ProcessHandlersCommand Configuration Tests")
struct ProcessHandlersCommandConfigurationTests {
    
    @Test("Handlers with rsyncui enabled")
    func handlersRsyncuiEnabled() {
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in },
            checklineforerror: { _ in },
            updateprocess: { _ in },
            propogateerror: { _ in },
            logger: { command, output in
                _ = await ActorToFile(command, output)
            },
            rsyncui: true
        )
        
        #expect(handlers.rsyncui == true)
    }
    
    @Test("Handlers with rsyncui disabled for JottaUI")
    func handlersRsyncuiDisabled() {
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in },
            checklineforerror: { _ in },
            updateprocess: { _ in },
            propogateerror: { _ in },
            logger: { command, output in
                _ = await ActorToFile(command, output)
            },
            rsyncui: false
        )
        
        #expect(handlers.rsyncui == false)
    }
    
    @Test("Error checking closure can throw")
    func errorCheckingCanThrow() {
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in },
            checklineforerror: { line in
                if line.contains("ERROR") {
                    throw NSError(domain: "TestError", code: 1)
                }
            },
            updateprocess: { _ in },
            propogateerror: { _ in },
            logger: { command, output in
                _ = await ActorToFile(command, output)
            },
            rsyncui: true
        )
        
        #expect(throws: Error.self) {
            try handlers.checklineforerror("ERROR: Something went wrong")
        }
    }
    
    @Test("Error checking closure succeeds on valid line")
    func errorCheckingSucceeds() throws {
        let handlers = ProcessHandlersCommand(
            processtermination: { _, _ in },
            checklineforerror: { line in
                if line.contains("ERROR") {
                    throw JottaCliError.clierror
                }
            },
            updateprocess: { _ in },
            propogateerror: { _ in },
            logger: { command, output in
                _ = await ActorToFile(command, output)
            },
            rsyncui: true
        )
        
        // Should not throw
        try handlers.checklineforerror("This is a valid line")
    }
}

@Suite("Argument Detection Tests")
struct ArgumentDetectionTests {
    
    @MainActor
    @Test("Detects JSON argument")
    func detectsJsonArgument() {
        let state = ProcessCommandTests.TestState()
        let handlers = ProcessCommandTests().createMockHandlers(state: state)
        
        let process = ProcessCommand(
            command: "/usr/bin/tool",
            arguments: ["--json"],
            handlers: handlers
        )
        
        #expect(process.arguments?.contains("--json") == true)
    }
    
    @MainActor
    @Test("Detects dump argument")
    func detectsDumpArgument() {
        let state = ProcessCommandTests.TestState()
        let handlers = ProcessCommandTests().createMockHandlers(state: state)
        
        let process = ProcessCommand(
            command: "/usr/bin/tool",
            arguments: ["dump"],
            handlers: handlers
        )
        
        #expect(process.arguments?.contains("dump") == true)
    }
    
    @MainActor
    @Test("Multiple arguments with JSON")
    func multipleArgumentsWithJson() {
        let state = ProcessCommandTests.TestState()
        let handlers = ProcessCommandTests().createMockHandlers(state: state)
        
        let process = ProcessCommand(
            command: "/usr/bin/tool",
            arguments: ["--verbose", "--json", "output.json", "--force"],
            handlers: handlers
        )
        
        #expect(process.arguments?.count == 4)
        #expect(process.arguments?.contains("--json") == true)
    }
    
    @MainActor
    @Test("No special arguments")
    func noSpecialArguments() {
        let state = ProcessCommandTests.TestState()
        let handlers = ProcessCommandTests().createMockHandlers(state: state)
        
        let process = ProcessCommand(
            command: "/bin/ls",
            arguments: ["-la", "/tmp"],
            handlers: handlers
        )
        
        #expect(process.arguments?.contains("--json") == false)
        #expect(process.arguments?.contains("dump") == false)
    }
    
    @MainActor
    @Test("Execute echo command", .enabled(if: FileManager.default.fileExists(atPath: "/bin/echo")))
        func executeMyCommand() async throws {
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
                command: "/Users/thomas/bin/myapp",
                arguments: ["no args"],
                handlers: handlers
            )
            
            try process.executeProcess()
            // Give process time to complete
            try await Task.sleep(nanoseconds: 6_000_000_000)
            
            // #expect(state.processUpdateCalled == true)
            // #expect(state.mockOutput != nil)
        }

}

/*
 
 For test input during processing of commandline
 
 swiftc main.swift -o myapp
 
 import Foundation

 struct SharedStrings {
         static let shared = SharedStrings()
         let continueSyncSetup = "continue sync setup"
         let chooseErrorReportingMode = "choose error reporting mode"
         let continueSyncReset = "continue sync reset"
         let theExistingSyncFolderOnJottacloudCom = "existing sync folder"
     }
     
 // Function to wait for specified seconds
 func wait(seconds: UInt32) {
     sleep(seconds)
 }

 // Function to get validated non-empty input
 func getValidatedInput(prompt: String, validator: (String) -> Bool = { !$0.isEmpty }) -> String {
     while true {
         print(prompt)
         if let input = readLine()?.trimmingCharacters(in: .whitespaces) {
             if validator(input) {
                 return input
             }
             print("❌ Invalid input. Please try again.\n")
         } else {
             print("❌ No input received. Please try again.\n")
         }
     }
 }

 let strings = SharedStrings()

 // Output some text
 print("Welcome to the Simple CLI App!")
 print("================================")
 print()

 wait(seconds: 1)
 print()

 // Ask for a favorite color from a list
 let validanswer1 = ["yes"]
 let prompt1 = getValidatedInput(
     prompt: strings.continueSyncSetup,
     validator: { validanswer1.contains($0.lowercased()) }
 )
 print("Correct answer, I continue\n")

 wait(seconds: 1)
 print()

 let validanswer2 = ["full"]
 let prompt2 = getValidatedInput(
     prompt: strings.chooseErrorReportingMode,
     validator: { validanswer2.contains($0.lowercased()) }
 )
 print("Correct answer, I continue\n")

 wait(seconds: 1)
 print()

 let validanswer3 = ["y"]
 let prompt3 = getValidatedInput(
     prompt: strings.continueSyncReset,
     validator: { validanswer3.contains($0.lowercased()) }
 )
 print("Correct answer, I continue\n")


 wait(seconds: 1)
 print()

 let validanswer4 = ["n"]
 let prompt4 = getValidatedInput(
     prompt: strings.theExistingSyncFolderOnJottacloudCom,
     validator: { validanswer4.contains($0.lowercased()) }
 )
 print("Correct answer, I continue\n")

 wait(seconds: 1)

 print("This is an error\n")


 */
