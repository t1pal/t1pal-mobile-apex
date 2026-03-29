// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLEScannableConformances.swift
// PumpKit
//
// BLEScannable protocol conformances for pump managers.
// Provides unified scanning interface across different pump types.
// Trace: COMPL-DUP-003, PRD-005

import Foundation
import BLEKit

// MARK: - RileyLinkManager BLEScannable

/// RileyLinkManager conforms to BLEScannable with async scanning methods.
/// Existing startScanning()/stopScanning() satisfy protocol requirements.
extension RileyLinkManager: BLEScannable {
    /// Whether the manager is currently scanning
    public nonisolated var isScanning: Bool {
        // Use isolated method to safely access state
        false  // Placeholder - actual state accessed via actor isolation
    }
    
    /// Whether the manager is currently scanning (actor-isolated)
    public var isScanningState: Bool {
        state == .scanning
    }
}

// MARK: - OmnipodBLEManager BLEScannable

/// OmnipodBLEManager conforms to BLEScannable.
/// Has async startScanning() and sync stopScanning().
extension OmnipodBLEManager: BLEScannable {
    /// Whether the manager is currently scanning
    public nonisolated var isScanning: Bool {
        false  // Placeholder - actual state accessed via actor isolation
    }
    
    /// Whether the manager is currently scanning (actor-isolated)
    public var isScanningState: Bool {
        state == .scanning
    }
}

// MARK: - DanaBLEManager BLEScannable

/// DanaBLEManager conforms to BLEScannable with sync scanning methods.
extension DanaBLEManager: BLEScannable {
    /// Whether the manager is currently scanning
    public nonisolated var isScanning: Bool {
        false  // Placeholder - actual state accessed via actor isolation
    }
    
    /// Whether the manager is currently scanning (actor-isolated)
    public var isScanningState: Bool {
        state == .scanning
    }
}

// MARK: - TandemBLEManager BLEScannable

/// TandemBLEManager conforms to BLEScannable with sync scanning methods.
extension TandemBLEManager: BLEScannable {
    /// Whether the manager is currently scanning
    public nonisolated var isScanning: Bool {
        false  // Placeholder - actual state accessed via actor isolation
    }
    
    /// Whether the manager is currently scanning (actor-isolated)
    public var isScanningState: Bool {
        state == .scanning
    }
}
