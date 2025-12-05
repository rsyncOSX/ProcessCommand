//
//  PackageLogger.swift
//  ProcessCommand
//
//  Created by Thomas Evensen on 15/11/2025.
//

import OSLog

extension Logger {
    nonisolated static let process = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "unknown",
        category: "process"
    )

    nonisolated func debugmesseageonly(_ message: String) {
        #if DEBUG
            debug("\(message)")
        #endif
    }

    nonisolated func debugtthreadonly(_ message: String) {
        #if DEBUG
            if Thread.checkIsMainThread() {
                debug("\(message) Running on main thread")
            } else {
                debug("\(message) NOT on main thread, currently on \(Thread.current)")
            }
        #endif
    }
}
