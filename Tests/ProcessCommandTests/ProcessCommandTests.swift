import Testing
@testable import ProcessCommand
import Foundation

@MainActor
struct ProcessCommandTests {
    // Actor-based mock to safely handle state from asynchronous callbacks.
    @MainActor
    class MockHandlers {
        private(set) var terminationOutput: [String]?
        private(set) var terminationErrorDiscovered: Bool?
        private(set) var propagatedError: Error?

        private var terminationContinuation: CheckedContinuation<Void, Never>?
        private var errorContinuation: CheckedContinuation<Void, Never>?

        // Asynchronously waits until the process termination callback is fired.
        func expectTermination() async {
            if terminationOutput != nil { return } // Already terminated
            await withCheckedContinuation { self.terminationContinuation = $0 }
        }

        // Asynchronously waits until the error propagation callback is fired.
        func expectError() async {
            if propagatedError != nil { return } // Already errored
            await withCheckedContinuation { self.errorContinuation = $0 }
        }
        
        // Creates the ProcessHandlersCommand struct with closures that message back to this actor.
        func createHandlers() -> ProcessHandlersCommand {
            return ProcessHandlersCommand(
                processtermination: { output, error in
                    Task { self.didTerminate(output: output, error: error) }
                },
                checklineforerror: { line in
                    // For testing, throw a specific error if a line contains "fail".
                    if line.contains("fail") {
                        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated error"])
                    }
                },
                updateprocess: { _ in
                    // No-op for these tests.
                },
                propogateerror: { error in
                    Task { self.didPropagateError(error) }
                },
                rsyncui: false // Use the `jottaui` path for more comprehensive testing.
            )
        }

        // Safely updates actor state when the process terminates.
        private func didTerminate(output: [String]?, error: Bool) {
            self.terminationOutput = output
            self.terminationErrorDiscovered = error
            terminationContinuation?.resume()
            terminationContinuation = nil
        }

        // Safely updates actor state when an error is propagated.
        private func didPropagateError(_ error: Error) {
            self.propagatedError = error
            errorContinuation?.resume()
            errorContinuation = nil
        }
    }

    @Test("Successful process execution")
    func successfulProcessExecution() async throws {
        // 1. Arrange
        let mockHandlers = MockHandlers()
        let processCommand =  ProcessCommand(
            command: "/bin/echo",
            arguments: ["Hello", "World"],
            handlers: mockHandlers.createHandlers()
        )

        // 2. Act
        try processCommand.executeProcess()
        await mockHandlers.expectTermination()

        // 3. Assert
        let output = mockHandlers.terminationOutput
        let errorDiscovered = mockHandlers.terminationErrorDiscovered
        let propagatedError = mockHandlers.propagatedError
        
        #expect(output?.count == 1)
        #expect(output?.first == "Hello World")
        #expect(errorDiscovered == false)
        #expect(propagatedError == nil)
    }

    @Test("Invalid command path throws error")
    func invalidCommandPathThrowsError() async {
        // 1. Arrange
        let mockHandlers = MockHandlers()
        let processCommand = ProcessCommand(
            command: "/invalid/path/to/command",
            arguments: ["arg1"],
            handlers: mockHandlers.createHandlers()
        )

        // 2. Act & Assert
        #expect(throws: CommandError.self) {
            try processCommand.executeProcess()
        }
    }

    @Test("Error propagation from line check")
    func errorPropagation() async throws {
        // 1. Arrange
        let mockHandlers = MockHandlers()
        let processCommand = ProcessCommand(
            command: "/bin/sh",
            arguments: ["-c", "echo 'this will fail'"],
            handlers: mockHandlers.createHandlers()
        )
        
        // 2. Act
        try processCommand.executeProcess()
        await mockHandlers.expectError()
        await mockHandlers.expectTermination()

        // 3. Assert
        let errorDiscovered = mockHandlers.terminationErrorDiscovered
        let propagatedError = mockHandlers.propagatedError

        #expect(errorDiscovered == true)
        #expect(propagatedError != nil)
        let nsError = try #require(propagatedError as? NSError)
        #expect(nsError.domain == "TestError")
    }
    
    @Test("Interactive prompt handling")
    func interactivePromptHandling() async throws {
        // 1. Arrange
        let mockHandlers = MockHandlers()
        let script = """
        #!/bin/sh
        echo "continue sync setup"
        read response
        if [ "$response" = "yes" ]; then
            exit 0
        else
            exit 1
        fi
        """
        
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_script.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        
        let processCommand = ProcessCommand(
            command: scriptURL.path,
            arguments: [],
            handlers: mockHandlers.createHandlers(),
            input: "yes"
        )
        
        // 2. Act
        try processCommand.executeProcess()
        await mockHandlers.expectTermination()
        
        // 3. Assert
        let errorDiscovered =  mockHandlers.terminationErrorDiscovered
        #expect(errorDiscovered == false, "The script should have exited cleanly.")
    }
}
