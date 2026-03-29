// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ErrorClassifier.swift
// BLEKit
//
// Created for T1Pal - BLE-CONN-002
// Classifies BLE errors for retry decision making

import Foundation

// MARK: - Error Classification

/// Categories for BLE error handling decisions
public enum BLEErrorCategory: String, Sendable, CaseIterable {
    /// Transient errors that should be retried with backoff
    /// Examples: timeout, temporary disconnect, RSSI too weak
    case transient
    
    /// Errors that require user action before retry
    /// Examples: not paired, authorization needed, Bluetooth off
    case recoverable
    
    /// Permanent errors that should not be retried
    /// Examples: unsupported device, hardware failure
    case permanent
    
    /// Unknown errors - use conservative retry strategy
    case unknown
}

/// Recommended action for error recovery
public enum RecoveryAction: String, Sendable, CaseIterable {
    /// Retry immediately with backoff
    case retry
    
    /// Retry after user enables Bluetooth
    case waitForBluetooth
    
    /// Retry after user grants permission
    case requestAuthorization
    
    /// Retry after pairing completes
    case initiatePairing
    
    /// Retry after moving closer to device
    case moveCloser
    
    /// Do not retry - operation cannot succeed
    case abort
    
    /// Unknown - apply default retry policy
    case unknown
}

// MARK: - Classification Result

/// Result of error classification with retry guidance
public struct ErrorClassification: Sendable, Equatable {
    /// The category of the error
    public let category: BLEErrorCategory
    
    /// Recommended recovery action
    public let action: RecoveryAction
    
    /// Whether retry is recommended
    public let shouldRetry: Bool
    
    /// Recommended retry policy preset
    public let suggestedPolicy: RetryPolicy
    
    /// User-facing message explaining the error
    public let userMessage: String
    
    /// Technical details for logging
    public let technicalDetails: String
    
    public init(
        category: BLEErrorCategory,
        action: RecoveryAction,
        shouldRetry: Bool,
        suggestedPolicy: RetryPolicy,
        userMessage: String,
        technicalDetails: String
    ) {
        self.category = category
        self.action = action
        self.shouldRetry = shouldRetry
        self.suggestedPolicy = suggestedPolicy
        self.userMessage = userMessage
        self.technicalDetails = technicalDetails
    }
}

// MARK: - Error Classifier

/// Classifies BLE errors and provides retry recommendations
public struct ErrorClassifier: Sendable {
    
    /// Classification matrix for known BLE errors
    private static let classificationMatrix: [String: (BLEErrorCategory, RecoveryAction)] = [
        // Transient errors - retry with backoff
        "connectionTimeout": (.transient, .retry),
        "disconnected": (.transient, .retry),
        "readFailed": (.transient, .retry),
        "writeFailed": (.transient, .retry),
        "notificationFailed": (.transient, .retry),
        "scanFailed": (.transient, .retry),
        
        // Recoverable errors - require action
        "notPoweredOn": (.recoverable, .waitForBluetooth),
        "unauthorized": (.recoverable, .requestAuthorization),
        
        // Permanent errors - do not retry
        "unsupported": (.permanent, .abort),
        "notSupported": (.permanent, .abort),
    ]
    
    public init() {}
    
    /// Classify a BLEError and get retry recommendations
    public func classify(_ error: BLEError) -> ErrorClassification {
        switch error {
        case .connectionTimeout:
            return transientClassification(
                userMessage: "Connection timed out. Retrying...",
                technicalDetails: "BLEError.connectionTimeout"
            )
            
        case .disconnected:
            return transientClassification(
                userMessage: "Device disconnected. Reconnecting...",
                technicalDetails: "BLEError.disconnected"
            )
            
        case .readFailed(let reason):
            return transientClassification(
                userMessage: "Communication error. Retrying...",
                technicalDetails: "BLEError.readFailed: \(reason)"
            )
            
        case .writeFailed(let reason):
            return transientClassification(
                userMessage: "Communication error. Retrying...",
                technicalDetails: "BLEError.writeFailed: \(reason)"
            )
            
        case .notificationFailed(let reason):
            return transientClassification(
                userMessage: "Notification setup failed. Retrying...",
                technicalDetails: "BLEError.notificationFailed: \(reason)"
            )
            
        case .scanFailed(let reason):
            return transientClassification(
                userMessage: "Scanning for devices. Please wait...",
                technicalDetails: "BLEError.scanFailed: \(reason)"
            )
            
        case .connectionFailed(let reason):
            // Analyze reason string for more specific classification
            return classifyConnectionFailure(reason: reason)
            
        case .notPoweredOn:
            return recoverableClassification(
                action: .waitForBluetooth,
                userMessage: "Please turn on Bluetooth",
                technicalDetails: "BLEError.notPoweredOn"
            )
            
        case .unauthorized:
            return recoverableClassification(
                action: .requestAuthorization,
                userMessage: "Bluetooth permission required",
                technicalDetails: "BLEError.unauthorized"
            )
            
        case .unsupported:
            return permanentClassification(
                userMessage: "Bluetooth is not supported on this device",
                technicalDetails: "BLEError.unsupported"
            )
            
        case .notSupported(let feature):
            return permanentClassification(
                userMessage: "This feature is not available",
                technicalDetails: "BLEError.notSupported: \(feature)"
            )
            
        case .serviceNotFound(let uuid):
            // Service not found could be wrong device or connection issue
            return transientClassification(
                userMessage: "Device not responding correctly. Retrying...",
                technicalDetails: "BLEError.serviceNotFound: \(uuid.description)"
            )
            
        case .characteristicNotFound(let uuid):
            return transientClassification(
                userMessage: "Device not responding correctly. Retrying...",
                technicalDetails: "BLEError.characteristicNotFound: \(uuid.description)"
            )
            
        case .invalidState(let reason):
            return classifyInvalidState(reason: reason)
        }
    }
    
    /// Classify any Error type (not just BLEError)
    public func classifyAny(_ error: Error) -> ErrorClassification {
        if let bleError = error as? BLEError {
            return classify(bleError)
        }
        
        // For unknown errors, use conservative approach
        return ErrorClassification(
            category: .unknown,
            action: .unknown,
            shouldRetry: true,
            suggestedPolicy: .conservative,
            userMessage: "An error occurred. Retrying...",
            technicalDetails: String(describing: error)
        )
    }
    
    // MARK: - Private Helpers
    
    private func transientClassification(
        userMessage: String,
        technicalDetails: String
    ) -> ErrorClassification {
        ErrorClassification(
            category: .transient,
            action: .retry,
            shouldRetry: true,
            suggestedPolicy: .bleDefault,
            userMessage: userMessage,
            technicalDetails: technicalDetails
        )
    }
    
    private func recoverableClassification(
        action: RecoveryAction,
        userMessage: String,
        technicalDetails: String
    ) -> ErrorClassification {
        ErrorClassification(
            category: .recoverable,
            action: action,
            shouldRetry: false, // Don't auto-retry, wait for user action
            suggestedPolicy: .noRetry,
            userMessage: userMessage,
            technicalDetails: technicalDetails
        )
    }
    
    private func permanentClassification(
        userMessage: String,
        technicalDetails: String
    ) -> ErrorClassification {
        ErrorClassification(
            category: .permanent,
            action: .abort,
            shouldRetry: false,
            suggestedPolicy: .noRetry,
            userMessage: userMessage,
            technicalDetails: technicalDetails
        )
    }
    
    private func classifyConnectionFailure(reason: String) -> ErrorClassification {
        let lowerReason = reason.lowercased()
        
        // Check for pairing-related failures
        if lowerReason.contains("pair") || lowerReason.contains("bond") {
            return ErrorClassification(
                category: .recoverable,
                action: .initiatePairing,
                shouldRetry: false,
                suggestedPolicy: .noRetry,
                userMessage: "Device pairing required",
                technicalDetails: "BLEError.connectionFailed: \(reason)"
            )
        }
        
        // Check for RSSI/range issues
        if lowerReason.contains("rssi") || lowerReason.contains("range") || lowerReason.contains("signal") {
            return ErrorClassification(
                category: .recoverable,
                action: .moveCloser,
                shouldRetry: true,
                suggestedPolicy: .aggressive,
                userMessage: "Device may be out of range. Move closer.",
                technicalDetails: "BLEError.connectionFailed: \(reason)"
            )
        }
        
        // Check for authentication failures
        if lowerReason.contains("auth") || lowerReason.contains("encrypt") {
            return ErrorClassification(
                category: .recoverable,
                action: .initiatePairing,
                shouldRetry: false,
                suggestedPolicy: .noRetry,
                userMessage: "Authentication failed. Please re-pair device.",
                technicalDetails: "BLEError.connectionFailed: \(reason)"
            )
        }
        
        // Default: treat as transient
        return transientClassification(
            userMessage: "Connection failed. Retrying...",
            technicalDetails: "BLEError.connectionFailed: \(reason)"
        )
    }
    
    private func classifyInvalidState(reason: String) -> ErrorClassification {
        let lowerReason = reason.lowercased()
        
        // Check for recoverable states
        if lowerReason.contains("not connected") || lowerReason.contains("disconnected") {
            return transientClassification(
                userMessage: "Reconnecting to device...",
                technicalDetails: "BLEError.invalidState: \(reason)"
            )
        }
        
        // Default: transient with conservative retry
        return ErrorClassification(
            category: .transient,
            action: .retry,
            shouldRetry: true,
            suggestedPolicy: .conservative,
            userMessage: "Device in unexpected state. Retrying...",
            technicalDetails: "BLEError.invalidState: \(reason)"
        )
    }
}

// MARK: - Retry Integration

extension ErrorClassifier {
    /// Get a RetryExecutor configured for the given error
    public func retryExecutor(for error: BLEError) -> RetryExecutor {
        let classification = classify(error)
        return RetryExecutor(policy: classification.suggestedPolicy)
    }
    
    /// Check if an error should trigger retry
    public func shouldRetry(_ error: BLEError, attemptNumber: Int, maxAttempts: Int) -> Bool {
        let classification = classify(error)
        guard classification.shouldRetry else { return false }
        return attemptNumber < maxAttempts
    }
}

// MARK: - Aggregate Error Analysis

/// Tracks error patterns over time for circuit breaker decisions
public actor ErrorPatternTracker {
    private var recentErrors: [(error: BLEError, timestamp: Date)] = []
    private let windowDuration: TimeInterval
    private let classifier = ErrorClassifier()
    
    public init(windowDuration: TimeInterval = 300) { // 5 minute window
        self.windowDuration = windowDuration
    }
    
    /// Record an error occurrence
    public func record(_ error: BLEError) {
        let now = Date()
        recentErrors.append((error, now))
        pruneOldErrors(before: now)
    }
    
    /// Get count of errors by category in the window
    public func errorCounts() -> [BLEErrorCategory: Int] {
        let now = Date()
        pruneOldErrors(before: now)
        
        var counts: [BLEErrorCategory: Int] = [:]
        for (error, _) in recentErrors {
            let category = classifier.classify(error).category
            counts[category, default: 0] += 1
        }
        return counts
    }
    
    /// Check if circuit breaker should trip
    public func shouldTripCircuitBreaker(
        transientThreshold: Int = 10,
        permanentThreshold: Int = 3
    ) -> Bool {
        let counts = errorCounts()
        
        // Trip if too many permanent errors
        if (counts[.permanent] ?? 0) >= permanentThreshold {
            return true
        }
        
        // Trip if too many transient errors (indicates sustained issues)
        if (counts[.transient] ?? 0) >= transientThreshold {
            return true
        }
        
        return false
    }
    
    /// Clear error history
    public func reset() {
        recentErrors.removeAll()
    }
    
    private func pruneOldErrors(before now: Date) {
        let cutoff = now.addingTimeInterval(-windowDuration)
        recentErrors.removeAll { $0.timestamp < cutoff }
    }
}
