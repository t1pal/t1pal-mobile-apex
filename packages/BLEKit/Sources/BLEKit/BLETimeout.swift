// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLETimeout.swift
// BLEKit
//
// Async timeout utilities for BLE operations.
// Trace: PROD-HARDEN-020
//
// Replaces ad-hoc Task.sleep patterns with reusable timeout wrapper.

import Foundation

// MARK: - Timeout Error

/// Error thrown when an operation times out
public struct BLETimeoutError: Error, CustomStringConvertible {
    public let operation: String
    public let timeout: TimeInterval
    
    public init(operation: String, timeout: TimeInterval) {
        self.operation = operation
        self.timeout = timeout
    }
    
    public var description: String {
        "BLE operation '\(operation)' timed out after \(String(format: "%.1f", timeout))s"
    }
}

// MARK: - Timeout Wrapper

/// Execute an async operation with a timeout.
///
/// Uses structured concurrency to race the operation against a sleep task.
/// The losing task is cancelled when the winner completes.
///
/// - Parameters:
///   - timeout: Maximum time to wait in seconds
///   - operation: Name of the operation for error messages
///   - work: The async work to perform
/// - Returns: The result of the work if completed within timeout
/// - Throws: `BLETimeoutError` if timeout expires, or any error from work
///
/// Example:
/// ```swift
/// let services = try await withTimeout(seconds: 5, operation: "service discovery") {
///     try await peripheral.discoverServices(nil)
/// }
/// ```
public func withTimeout<T: Sendable>(
    seconds timeout: TimeInterval,
    operation: String,
    work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Task 1: The actual work
        group.addTask {
            try await work()
        }
        
        // Task 2: Timeout sentinel
        group.addTask {
            try await Task.sleep(for: .seconds(timeout))
            throw BLETimeoutError(operation: operation, timeout: timeout)
        }
        
        // Return first successful result, cancel the other
        if let result = try await group.next() {
            group.cancelAll()
            return result
        }
        
        // Should never reach here
        throw BLETimeoutError(operation: operation, timeout: timeout)
    }
}

/// Execute an async operation with a timeout using nanoseconds.
///
/// Convenience overload for operations that use nanosecond timing.
///
/// - Parameters:
///   - timeout: Maximum time to wait in nanoseconds
///   - operation: Name of the operation for error messages
///   - work: The async work to perform
/// - Returns: The result of the work if completed within timeout
/// - Throws: `BLETimeoutError` if timeout expires, or any error from work
public func withTimeout<T: Sendable>(
    nanoseconds timeout: UInt64,
    operation: String,
    work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Task 1: The actual work
        group.addTask {
            try await work()
        }
        
        // Task 2: Timeout sentinel
        group.addTask {
            try await Task.sleep(nanoseconds: timeout)
            throw BLETimeoutError(operation: operation, timeout: Double(timeout) / 1_000_000_000)
        }
        
        // Return first successful result, cancel the other
        if let result = try await group.next() {
            group.cancelAll()
            return result
        }
        
        // Should never reach here
        throw BLETimeoutError(operation: operation, timeout: Double(timeout) / 1_000_000_000)
    }
}

// MARK: - Optional Timeout Wrapper

/// Execute an async operation with an optional timeout.
///
/// If timeout is nil, the operation runs without time limit.
///
/// - Parameters:
///   - timeout: Maximum time to wait in seconds, or nil for no timeout
///   - operation: Name of the operation for error messages
///   - work: The async work to perform
/// - Returns: The result of the work
/// - Throws: `BLETimeoutError` if timeout expires, or any error from work
public func withOptionalTimeout<T: Sendable>(
    seconds timeout: TimeInterval?,
    operation: String,
    work: @escaping @Sendable () async throws -> T
) async throws -> T {
    if let timeout = timeout {
        return try await withTimeout(seconds: timeout, operation: operation, work: work)
    } else {
        return try await work()
    }
}
