// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpResponsePoller.swift
// PumpKit
//
// Async utilities for polling pump command responses.
// Trace: PROD-HARDEN-021
//
// Wraps the poll-until-change pattern with proper timeout handling.
// Uses withTimeout from BLEKit for structured concurrency.

import Foundation
import BLEKit

// MARK: - Pump Timeout Error

/// Error thrown when a pump operation times out
public struct PumpTimeoutError: Error, CustomStringConvertible {
    public let operation: String
    public let timeout: TimeInterval
    public let detail: String?
    
    public init(operation: String, timeout: TimeInterval, detail: String? = nil) {
        self.operation = operation
        self.timeout = timeout
        self.detail = detail
    }
    
    public var description: String {
        var msg = "Pump operation '\(operation)' timed out after \(String(format: "%.1f", timeout))s"
        if let detail = detail {
            msg += ": \(detail)"
        }
        return msg
    }
}

// MARK: - Response Poller

/// Utility for polling pump response characteristics with timeout.
///
/// Wraps the common pattern of:
/// 1. Read initial value from characteristic
/// 2. Poll until value changes
/// 3. Timeout if no change within limit
///
/// Example:
/// ```swift
/// let changed = try await PumpResponsePoller.pollUntilChanged(
///     timeout: 5.0,
///     pollInterval: PumpTimingConstants.responseCountPollInterval,
///     operation: "responseCount",
///     readValue: { try await peripheral.readValue(for: rcChar) },
///     hasChanged: { data in data.first != initialValue }
/// )
/// ```
public enum PumpResponsePoller {
    
    /// Poll a value until it changes, with timeout.
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait in seconds
    ///   - pollInterval: Time between polls in seconds
    ///   - operation: Name of the operation for error messages
    ///   - readValue: Async closure to read current value
    ///   - hasChanged: Closure to check if value has changed
    /// - Returns: The final value after change detected
    /// - Throws: `PumpTimeoutError` if timeout expires
    public static func pollUntilChanged<T: Sendable>(
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        operation: String,
        readValue: @escaping @Sendable () async throws -> T,
        hasChanged: @escaping @Sendable (T) -> Bool
    ) async throws -> T {
        let startTime = Date()
        
        while Date().timeIntervalSince(startTime) < timeout {
            let value = try await readValue()
            if hasChanged(value) {
                return value
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        
        throw PumpTimeoutError(
            operation: operation,
            timeout: timeout,
            detail: "value unchanged after \(Int(timeout / pollInterval)) polls"
        )
    }
    
    /// Poll a value until it changes, with timeout in nanoseconds.
    ///
    /// Convenience overload for nanosecond-based timing.
    public static func pollUntilChanged<T: Sendable>(
        timeoutNanos: UInt64,
        pollIntervalNanos: UInt64,
        operation: String,
        readValue: @escaping @Sendable () async throws -> T,
        hasChanged: @escaping @Sendable (T) -> Bool
    ) async throws -> T {
        try await pollUntilChanged(
            timeout: Double(timeoutNanos) / 1_000_000_000,
            pollInterval: Double(pollIntervalNanos) / 1_000_000_000,
            operation: operation,
            readValue: readValue,
            hasChanged: hasChanged
        )
    }
    
    /// Poll for a specific response code from data characteristic.
    ///
    /// Commonly used for RileyLink data characteristic polling where
    /// we wait for response codes like 0xDD (success), 0xAA, 0xBB, 0xCC.
    ///
    /// - Parameters:
    ///   - timeout: Maximum time to wait in seconds
    ///   - pollInterval: Time between polls in seconds
    ///   - operation: Name of the operation for error messages
    ///   - validCodes: Set of response codes that indicate success
    ///   - readValue: Async closure to read data characteristic
    /// - Returns: The response data when a valid code is received
    /// - Throws: `PumpTimeoutError` if timeout expires without valid code
    public static func pollForResponseCode(
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        operation: String,
        validCodes: Set<UInt8> = [0xDD, 0xAA, 0xBB, 0xCC],
        readValue: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let startTime = Date()
        var lastSeenCode: UInt8 = 0
        var pollCount = 0
        
        while Date().timeIntervalSince(startTime) < timeout {
            let data = try await readValue()
            pollCount += 1
            
            if data.count > 0 {
                let code = data[0]
                lastSeenCode = code
                if validCodes.contains(code) {
                    return data
                }
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        
        throw PumpTimeoutError(
            operation: operation,
            timeout: timeout,
            detail: "stuck on 0x\(String(format: "%02X", lastSeenCode)) after \(pollCount) polls"
        )
    }
    
    /// Poll responseCount characteristic until it changes from initial value.
    ///
    /// Specialized helper for the common RileyLink responseCount pattern.
    ///
    /// - Parameters:
    ///   - initialValue: The initial responseCount value
    ///   - timeout: Maximum time to wait in seconds
    ///   - pollInterval: Time between polls (default: PumpTimingConstants.responseCountPollInterval)
    ///   - readValue: Async closure to read responseCount characteristic
    /// - Returns: The new responseCount value
    /// - Throws: `PumpTimeoutError` if timeout expires
    public static func pollResponseCount(
        initialValue: UInt8,
        timeout: TimeInterval,
        pollInterval: TimeInterval = PumpTimingConstants.responseCountPollInterval,
        readValue: @escaping @Sendable () async throws -> Data
    ) async throws -> UInt8 {
        let result = try await pollUntilChanged(
            timeout: timeout,
            pollInterval: pollInterval,
            operation: "responseCount",
            readValue: readValue,
            hasChanged: { data in
                guard data.count > 0 else { return false }
                return data[0] != initialValue
            }
        )
        return result.first ?? initialValue
    }
}

// MARK: - Retry Helper

/// Execute an async operation with retry logic and backoff.
///
/// - Parameters:
///   - maxAttempts: Maximum number of attempts (default: 3)
///   - backoff: Delay between retries (default: PumpTimingConstants.responseCountPollInterval)
///   - operation: Name of the operation for error messages
///   - work: The async work to perform
/// - Returns: The result of the work if successful
/// - Throws: The last error if all attempts fail
public func withRetry<T>(
    maxAttempts: Int = 3,
    backoff: TimeInterval = PumpTimingConstants.responseCountPollInterval,
    operation: String,
    work: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            return try await work()
        } catch {
            lastError = error
            if attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
    }
    
    throw lastError ?? PumpTimeoutError(
        operation: operation,
        timeout: Double(maxAttempts) * backoff,
        detail: "all \(maxAttempts) attempts failed"
    )
}
