// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ShareError.swift
// CGMKitShare
//
// Error types for cloud CGM data services

import Foundation

/// Error types for Share/cloud CGM services
public enum ShareError: Error, Sendable, LocalizedError, Equatable {
    /// Connection to cloud service failed
    case connectionFailed
    /// Cloud data is unavailable (no readings, expired session, etc.)
    case dataUnavailable
    /// Authentication with cloud service failed
    case unauthorized
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to cloud service"
        case .dataUnavailable:
            return "Cloud data is unavailable"
        case .unauthorized:
            return "Cloud service access not authorized"
        }
    }
}
