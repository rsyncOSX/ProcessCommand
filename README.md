## Hi there 👋

Version 2.0.0

This package is code for monitoring other commands process in RsyncUI.

The package is used in [RsyncUI](https://github.com/rsyncOSX/RsyncUI) and [JottaUI](https://github.com/rsyncOSX/JottaUI) which is a monitoring tool onto of JottaCloud `jotta-cli` tool. 

By Using Swift Package Manager (SPM), parts of the source code in RsyncUI is extraced and created as packages. The old code, the base for packages, is deleted and RsyncUI imports the new packages.  In Xcode 26 and later there is also module for test, Swift Testing, for testing packages. By SPM and Swift Testing, the code is modularized, isolated, and tested before committing changes.

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
