//
//  ProcessHandlersCommand.swift
//  ProcessCommand
//
//  Created by Thomas Evensen on 15/11/2025.
//
import Foundation

/// Handlers for process execution callbacks
public struct ProcessHandlersCommand {
    /// Called when process terminates with output and hiddenID
    public var processtermination: ([String]?, Bool) -> Void
    /// Checks a line for errors and throws if found
    public var checklineforerror: (String) throws -> Void
    /// Updates the current process reference
    public var updateprocess: (Process?) -> Void
    /// Propagates errors to error handler
    public var propogateerror: (Error) -> Void
    // Async logger
    public var logger: (String, [String]) async -> Void
    /// Flag for version 3.x of rsync or not
    public var rsyncui: Bool = true
    /// Initialize ProcessHandlers with all required closures
    public init(
        processtermination: @escaping ([String]?, Bool) -> Void,
        checklineforerror: @escaping (String) throws -> Void,
        updateprocess: @escaping (Process?) -> Void,
        propogateerror: @escaping (Error) -> Void,
        logger: @escaping (String, [String]) async -> Void,
        rsyncui: Bool
    ) {
        self.processtermination = processtermination
        self.checklineforerror = checklineforerror
        self.updateprocess = updateprocess
        self.propogateerror = propogateerror
        self.logger = logger
        self.rsyncui = rsyncui
    }
}
