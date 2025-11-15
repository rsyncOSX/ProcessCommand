//
//  PackageLogger.swift
//  ProcessCommand
//
//  Created by Thomas Evensen on 15/11/2025.
//


import OSLog

internal extension Logger {
    nonisolated static let process = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "unknown",
        category: "process"
    )
}
