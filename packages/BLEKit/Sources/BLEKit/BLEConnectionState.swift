// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLEConnectionState.swift
// BLEKit
//
// Unified connection state for BLE devices.
// Trace: COMPL-DUP-001, PRD-008 REQ-BLE-001

import Foundation

// MARK: - Unified Connection State

/// Unified connection state for BLE devices
///
/// This enum provides a common vocabulary for BLE connection states
/// across all device managers. Device-specific managers may have
/// additional states (e.g., `pairing`, `tuning`) that map to these
/// common states via `BLEConnectionStateConvertible`.
///
/// Usage:
/// ```swift
/// let state: BLEConnectionState = g7Manager.connectionState.bleConnectionState
/// if state.isConnected {
///     // Device is ready
/// }
/// ```
///
/// Trace: COMPL-DUP-001
public enum BLEConnectionState: String, Sendable, Codable, CaseIterable, Equatable {
    /// Not connected, not attempting to connect
    case disconnected
    
    /// Scanning for device
    case scanning
    
    /// Connecting to device
    case connecting
    
    /// Connected and ready for communication
    case connected
    
    /// Connection error occurred
    case error
    
    // MARK: - Computed Properties
    
    /// Whether the device is connected
    public var isConnected: Bool {
        self == .connected
    }
    
    /// Whether actively connecting (scanning or connecting)
    public var isConnecting: Bool {
        self == .scanning || self == .connecting
    }
    
    /// Whether in an idle/error state (can start new connection)
    public var canConnect: Bool {
        self == .disconnected || self == .error
    }
    
    // MARK: - Display
    
    /// Human-readable display string
    public var displayString: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }
    
    /// SF Symbol name for state
    public var symbolName: String {
        switch self {
        case .disconnected: return "antenna.radiowaves.left.and.right.slash"
        case .scanning: return "magnifyingglass"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Convertible Protocol

/// Protocol for converting device-specific connection states to common state
///
/// Device managers with specialized connection states (e.g., `pairing`, `tuning`)
/// conform to this protocol to provide a unified state for UI and logging.
///
/// Example:
/// ```swift
/// extension G7ConnectionState: BLEConnectionStateConvertible {
///     public var bleConnectionState: BLEConnectionState {
///         switch self {
///         case .idle: return .disconnected
///         case .scanning: return .scanning
///         case .connecting, .pairing, .authenticating: return .connecting
///         case .streaming, .passive: return .connected
///         case .disconnecting: return .connecting
///         case .error: return .error
///         }
///     }
/// }
/// ```
///
/// Trace: COMPL-DUP-001
public protocol BLEConnectionStateConvertible: Sendable {
    /// Convert to unified connection state
    var bleConnectionState: BLEConnectionState { get }
}

// MARK: - BLEConnectionState Self-Conformance

extension BLEConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState { self }
}
