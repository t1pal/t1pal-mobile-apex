// SPDX-License-Identifier: AGPL-3.0-or-later
//
// T1PalErrorProtocol.swift
// T1PalCore
//
// Unified error protocol for consistent error handling across all T1Pal packages.
// Provides categorization, recovery hints, and user-facing messages.
// Trace: PROD-HARDEN-033

import Foundation

// MARK: - Error Domain

/// Error domain categories for T1Pal errors
public enum T1PalErrorDomain: String, Sendable, CaseIterable {
    /// Bluetooth/BLE errors
    case ble = "BLE"
    /// CGM sensor errors
    case cgm = "CGM"
    /// Insulin pump errors
    case pump = "Pump"
    /// Algorithm/dosing errors
    case algorithm = "Algorithm"
    /// Network/API errors
    case network = "Network"
    /// Authentication/identity errors
    case auth = "Auth"
    /// Data persistence errors
    case storage = "Storage"
    /// Configuration errors
    case config = "Config"
    /// Unknown/other errors
    case unknown = "Unknown"
}

// MARK: - Error Severity

/// Severity levels for T1Pal errors
public enum T1PalErrorSeverity: String, Sendable, Comparable {
    /// Informational - not a true error
    case info = "info"
    /// Warning - operation completed with issues
    case warning = "warning"
    /// Error - operation failed, may be recoverable
    case error = "error"
    /// Critical - operation failed, requires intervention
    case critical = "critical"
    
    public static func < (lhs: T1PalErrorSeverity, rhs: T1PalErrorSeverity) -> Bool {
        let order: [T1PalErrorSeverity] = [.info, .warning, .error, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

// MARK: - Recovery Action

/// Suggested recovery actions for errors
public enum T1PalRecoveryAction: String, Sendable {
    /// Retry the operation
    case retry = "retry"
    /// Wait and retry later
    case waitAndRetry = "wait_and_retry"
    /// Reconnect the device
    case reconnect = "reconnect"
    /// Re-authenticate
    case reauthenticate = "reauthenticate"
    /// Check network connection
    case checkNetwork = "check_network"
    /// Contact support
    case contactSupport = "contact_support"
    /// Check device
    case checkDevice = "check_device"
    /// Update app
    case updateApp = "update_app"
    /// No action available
    case none = "none"
}

// MARK: - T1Pal Error Protocol

/// Protocol for all T1Pal domain errors.
/// Provides consistent categorization, logging, and user presentation.
///
/// Conforming types should:
/// 1. Provide a unique error code within their domain
/// 2. Categorize errors appropriately
/// 3. Suggest recovery actions when possible
/// 4. Provide user-friendly descriptions
public protocol T1PalErrorProtocol: Error, Sendable, LocalizedError {
    /// Error domain (BLE, CGM, Pump, etc.)
    var domain: T1PalErrorDomain { get }
    
    /// Unique error code within the domain
    var code: String { get }
    
    /// Error severity level
    var severity: T1PalErrorSeverity { get }
    
    /// Suggested recovery action
    var recoveryAction: T1PalRecoveryAction { get }
    
    /// Whether this error is recoverable
    var isRecoverable: Bool { get }
    
    /// Technical description for logging
    var technicalDescription: String { get }
    
    /// User-friendly description
    var userDescription: String { get }
    
    /// Recovery suggestion for the user
    var recoverySuggestion: String? { get }
}

// MARK: - Default Implementations

public extension T1PalErrorProtocol {
    /// Default severity is error
    var severity: T1PalErrorSeverity { .error }
    
    /// Default recovery action based on domain
    var recoveryAction: T1PalRecoveryAction {
        switch domain {
        case .ble, .cgm, .pump:
            return .reconnect
        case .network:
            return .checkNetwork
        case .auth:
            return .reauthenticate
        default:
            return .retry
        }
    }
    
    /// Most errors are recoverable by default
    var isRecoverable: Bool { severity != .critical }
    
    /// Default technical description uses the code
    var technicalDescription: String {
        "[\(domain.rawValue)-\(code)] \(userDescription)"
    }
    
    /// LocalizedError conformance
    var errorDescription: String? { userDescription }
    
    /// LocalizedError conformance
    var failureReason: String? { technicalDescription }
    
    /// LocalizedError conformance - recovery suggestion
    var recoverySuggestion: String? {
        switch recoveryAction {
        case .retry:
            return "Try the operation again."
        case .waitAndRetry:
            return "Wait a moment and try again."
        case .reconnect:
            return "Check your device connection and try reconnecting."
        case .reauthenticate:
            return "Please sign in again."
        case .checkNetwork:
            return "Check your network connection."
        case .contactSupport:
            return "Please contact support for assistance."
        case .checkDevice:
            return "Check that your device is nearby and powered on."
        case .updateApp:
            return "Please update to the latest version."
        case .none:
            return nil
        }
    }
}

// MARK: - Error Logging Helper

/// Helper for consistent error logging
public struct T1PalErrorLogger {
    /// Log an error with domain context
    public static func log(_ error: any T1PalErrorProtocol, file: String = #file, function: String = #function, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let logMessage = "[\(error.domain.rawValue)] [\(error.severity.rawValue.uppercased())] \(error.technicalDescription) (\(filename):\(line))"
        
        // Use os.Logger in production
        #if DEBUG
        T1PalCoreLogger.general.error("\(logMessage)")
        #endif
    }
}

// MARK: - Error Wrapper

/// Wrapper to convert any Error to T1PalErrorProtocol
public struct T1PalWrappedError: T1PalErrorProtocol {
    public let domain: T1PalErrorDomain
    public let code: String
    public let underlyingError: Error
    public let severity: T1PalErrorSeverity
    
    public var userDescription: String {
        (underlyingError as? LocalizedError)?.errorDescription ?? underlyingError.localizedDescription
    }
    
    public var technicalDescription: String {
        "[\(domain.rawValue)-\(code)] \(String(describing: type(of: underlyingError))): \(userDescription)"
    }
    
    public init(wrapping error: Error, domain: T1PalErrorDomain = .unknown, code: String = "WRAPPED", severity: T1PalErrorSeverity = .error) {
        self.underlyingError = error
        self.domain = domain
        self.code = code
        self.severity = severity
    }
}

