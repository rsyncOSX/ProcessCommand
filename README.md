## Hi there 👋

This code may be used to test the handling of input like answer to prompts like “yes” or “no”.

Compile with: `swiftc main.swift -o processtest` and put the compiled command line app in ../tmp catalog on your root.

```
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
print("This is a test app for checking input during running the command line app")
print("After termination you should see all lines the command line app produces")
print("========================================================================")

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

```

The actual test is located at the bottom of the test code. The test generates data that are processed by the AsyncSequence, which reads the output from the datahandle. The `processtest` also requires input to continue. The ProcessCommand recognizes the input and writes the answer to an inputhandle. Additionally, the ProcessCommand checks if there are words *error* or *Error* in the output and takes appropriate action. The final print statement in `processtest` outputs a line containing *error*, prompting the ProcessCommand to utilize the `logger`, which simply prints all input to the console.  This test verify that the ProcessCommand act on input.

```
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
```

# ProcessCommand

A Swift package for executing and managing system processes with async output handling, interactive prompt support, and comprehensive error detection.

## Features

- **Async/Await Process Execution**: Modern Swift concurrency for process management
- **Real-time Output Capture**: Stream process output as it happens
- **Interactive Prompt Handling**: Automatically respond to interactive prompts
- **Error Detection**: Monitor output for errors during execution
- **Output Draining**: Ensures all process output is captured before termination
- **Flexible Configuration**: Support for various command-line tools and workflows
- **Thread-Safe**: Designed with @MainActor for safe concurrent access
- **OSLog Integration**: Built-in logging for debugging and monitoring

## Requirements

- Swift 5.9+
- macOS 13.0+ / iOS 16.0+
- Foundation framework
- OSLog for logging

## Usage

### Basic Command Execution

```swift
import ProcessCommand

// Create process handlers
let handlers = ProcessHandlersCommand(
    processtermination: { output, errorDiscovered in
        print("Process completed")
        print("Lines of output: \(output?.count ?? 0)")
        if errorDiscovered {
            print("Errors were detected during execution")
        }
    },
    checklineforerror: { line in
        if line.contains("error") || line.contains("failed") {
            throw NSError(domain: "command", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: line])
        }
    },
    updateprocess: { process in
        // Store or manage process reference
    },
    propogateerror: { error in
        print("Error: \(error.localizedDescription)")
    },
    logger: { command, output in
        // Log output asynchronously
        print("Logging output for: \(command)")
    },
    rsyncui: true
)

// Execute a command
let processCommand = ProcessCommand(
    command: "/usr/bin/ls",
    arguments: ["-la", "/Users"],
    handlers: handlers
)

try await processCommand.executeProcess()

// Access output
for line in processCommand.output {
    print(line)
}
```

### Interactive Command Execution

For commands that require interactive input (like setup wizards):

```swift
let handlers = ProcessHandlersCommand(
    processtermination: { output, errorDiscovered in
        print("Setup completed")
    },
    checklineforerror: { _ in },
    updateprocess: { _ in },
    propogateerror: { error in
        print("Error: \(error)")
    },
    logger: { _, _ in },
    rsyncui: false  // Enable interactive mode
)

let processCommand = ProcessCommand(
    command: "/usr/local/bin/jotta-cli",
    arguments: ["sync", "setup"],
    handlers: handlers,
    syncmode: "full",      // Response for sync mode prompt
    input: "yes"           // Response for confirmation prompts
)

try await processCommand.executeProcess()
```

### With Custom Error Detection

```swift
enum MyCommandError: Error {
    case networkError
    case permissionDenied
    case unknownError(String)
}

let handlers = ProcessHandlersCommand(
    processtermination: { output, errorDiscovered in
        if errorDiscovered {
            print("Command failed - check logs")
        }
    },
    checklineforerror: { line in
        if line.contains("Connection refused") {
            throw MyCommandError.networkError
        } else if line.contains("Permission denied") {
            throw MyCommandError.permissionDenied
        } else if line.lowercased().contains("error") {
            throw MyCommandError.unknownError(line)
        }
    },
    updateprocess: { _ in },
    propogateerror: { error in
        if let myError = error as? MyCommandError {
            switch myError {
            case .networkError:
                print("Network connection failed")
            case .permissionDenied:
                print("Insufficient permissions")
            case .unknownError(let message):
                print("Unknown error: \(message)")
            }
        }
    },
    logger: { command, output in
        // Custom logging
    },
    rsyncui: true
)

let processCommand = ProcessCommand(
    command: "/usr/bin/curl",
    arguments: ["-f", "https://example.com"],
    handlers: handlers
)

try await processCommand.executeProcess()
```

## Core Components

### ProcessCommand

Main class for executing system commands with async output handling.

**Properties:**
- `command: String?` - The command to execute
- `arguments: [String]?` - Command arguments
- `output: [String]` - Accumulated output lines (read-only)
- `errordiscovered: Bool` - Whether an error was detected (read-only)

**Initialization:**
```swift
// Full initialization
init(
    command: String?,
    arguments: [String]?,
    handlers: ProcessHandlersCommand,
    syncmode: String? = nil,
    input: String? = nil
)

// Convenience initialization
init(
    command: String?,
    arguments: [String]?,
    handlers: ProcessHandlersCommand
)
```

**Methods:**
- `executeProcess()` - Execute the configured command

### ProcessHandlersCommand

Configuration struct for process event handlers.

**Properties:**
- `processtermination: ([String]?, Bool) -> Void` - Called when process completes
- `checklineforerror: (String) throws -> Void` - Validates output lines for errors
- `updateprocess: (Process?) -> Void` - Updates process reference
- `propogateerror: (Error) -> Void` - Error propagation handler
- `logger: (String, [String]) async -> Void` - Async logging handler
- `rsyncui: Bool` - Determines data handling mode (true for standard, false for interactive)

## Interactive Prompt Support

ProcessCommand can automatically respond to interactive prompts. This is useful for commands that require user input during execution:

### Supported Prompts

When `rsyncui: false`, the following prompts are automatically handled:

1. **Continue Sync Setup** - Responds with `input` parameter (default: "yes")
2. **Choose Error Reporting Mode** - Responds with `syncmode` parameter (default: "full")
3. **Continue Sync Reset** - Responds with `input` parameter (default: "y")
4. **Existing Sync Folder** - Responds with `input` parameter (default: "n")

### Example: Automated Setup

```swift
let processCommand = ProcessCommand(
    command: "/usr/local/bin/setup-tool",
    arguments: ["configure"],
    handlers: handlers,
    syncmode: "verbose",   // For error reporting prompts
    input: "yes"           // For all other prompts
)

try await processCommand.executeProcess()
```

## Error Handling

### CommandError Types

```swift
public enum CommandError: LocalizedError {
    case executableNotFound           // Command not found
    case invalidExecutablePath(String) // Invalid path
    case processLaunchFailed(Error)   // Launch failed
    case outputEncodingFailed         // UTF-8 decoding failed
}
```

### Error Detection in Output

Implement custom error detection logic:

```swift
let handlers = ProcessHandlersCommand(
    // ... other handlers ...
    checklineforerror: { line in
        // Define what constitutes an error
        let errorPatterns = ["error:", "failed:", "fatal:"]
        
        for pattern in errorPatterns {
            if line.lowercased().contains(pattern) {
                throw NSError(
                    domain: "com.myapp.command",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Command error: \(line)"]
                )
            }
        }
    },
    propogateerror: { error in
        // Handle the error appropriately
        Logger.process.error("Command error: \(error.localizedDescription)")
    },
    // ...
)
```

## Advanced Features

### Output Draining

ProcessCommand automatically drains all remaining output when a process terminates, ensuring no data is lost:

```swift
// Automatically captures all output, even after termination signal
let processCommand = ProcessCommand(
    command: "/usr/bin/some-command",
    arguments: ["--verbose"],
    handlers: handlers
)

try await processCommand.executeProcess()

// All output is guaranteed to be captured
print("Total lines: \(processCommand.output.count)")
```

### JSON and Dump Detection

ProcessCommand automatically detects `--json` or `dump` arguments and adjusts error checking behavior:

```swift
// Error checking is disabled for JSON output
let processCommand = ProcessCommand(
    command: "/usr/bin/tool",
    arguments: ["status", "--json"],
    handlers: handlers
)

try await processCommand.executeProcess()

// Parse JSON from output
let jsonData = processCommand.output.joined(separator: "\n").data(using: .utf8)
```

### Process Management

Track and manage running processes:

```swift
var currentProcess: Process?

let handlers = ProcessHandlersCommand(
    processtermination: { output, errorDiscovered in
        print("Process finished")
    },
    checklineforerror: { _ in },
    updateprocess: { process in
        currentProcess = process
        if let pid = process?.processIdentifier {
            print("Process started with PID: \(pid)")
        }
    },
    propogateerror: { _ in },
    logger: { _, _ in },
    rsyncui: true
)

let processCommand = ProcessCommand(
    command: "/usr/bin/long-running-task",
    arguments: ["--verbose"],
    handlers: handlers
)

try await processCommand.executeProcess()

// Can terminate process if needed
if let process = currentProcess, process.isRunning {
    process.terminate()
}
```

## SwiftUI Integration

### Progress View with Output

```swift
import SwiftUI
import ProcessCommand

struct CommandOutputView: View {
    @State private var processCommand: ProcessCommand?
    @State private var isRunning = false
    @State private var output: [String] = []
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(output, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding()
            }
            
            Button(isRunning ? "Running..." : "Execute") {
                Task {
                    await executeCommand()
                }
            }
            .disabled(isRunning)
        }
    }
    
    func executeCommand() async {
        isRunning = true
        errorMessage = nil
        output = []
        
        let handlers = ProcessHandlersCommand(
            processtermination: { [self] cmdOutput, errorDiscovered in
                output = cmdOutput ?? []
                isRunning = false
                if errorDiscovered {
                    errorMessage = "Command completed with errors"
                }
            },
            checklineforerror: { line in
                if line.contains("error") {
                    throw NSError(
                        domain: "command",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: line]
                    )
                }
            },
            updateprocess: { _ in },
            propogateerror: { [self] error in
                errorMessage = error.localizedDescription
            },
            logger: { _, _ in },
            rsyncui: true
        )
        
        processCommand = ProcessCommand(
            command: "/bin/ls",
            arguments: ["-la", FileManager.default.homeDirectoryForCurrentUser.path],
            handlers: handlers
        )
        
        do {
            try await processCommand?.executeProcess()
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
        }
    }
}
```

## Best Practices

1. **Always use try-await** when calling `executeProcess()` to handle potential errors
2. **Implement error checking** via `checklineforerror` for domain-specific error detection
3. **Handle interactive prompts** by setting `rsyncui: false` and providing `input`/`syncmode`
4. **Check `errordiscovered`** in termination handler to determine success/failure
5. **Use async logger** for non-blocking file operations
6. **Store process reference** via `updateprocess` if you need to terminate early
7. **Access output after termination** - the output array is guaranteed complete

## Common Use Cases

### Running Git Commands

```swift
let handlers = ProcessHandlersCommand(
    processtermination: { output, _ in
        print("Git command completed")
    },
    checklineforerror: { line in
        if line.contains("fatal:") {
            throw NSError(domain: "git", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: line])
        }
    },
    updateprocess: { _ in },
    propogateerror: { error in
        print("Git error: \(error)")
    },
    logger: { _, _ in },
    rsyncui: true
)

let gitCommand = ProcessCommand(
    command: "/usr/bin/git",
    arguments: ["status", "--porcelain"],
    handlers: handlers
)

try await gitCommand.executeProcess()
```

### Running Package Managers

```swift
let brewCommand = ProcessCommand(
    command: "/opt/homebrew/bin/brew",
    arguments: ["list", "--versions"],
    handlers: handlers
)

try await brewCommand.executeProcess()

// Parse output
for line in brewCommand.output {
    let components = line.split(separator: " ")
    if components.count >= 2 {
        print("Package: \(components[0]), Version: \(components[1])")
    }
}
```

## Logging

ProcessCommand uses OSLog for internal logging. Enable debug logging to see detailed execution information:

```swift
// In your app or debugging environment
import OSLog

let logger = Logger(subsystem: "com.yourapp", category: "process")
logger.debug("Starting process execution")
```

## License

MIT


## Author

Thomas Evensen