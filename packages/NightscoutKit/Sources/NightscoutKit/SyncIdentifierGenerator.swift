// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SyncIdentifierGenerator.swift
// NightscoutKit
//
// Sync identifier generation for Nightscout deduplication
// Extracted from NightscoutClient.swift (NS-REFACTOR-003)
// Requirements: REQ-NS-003, REQ-NS-004, REQ-NS-005

import Foundation

// MARK: - Sync Identifier Generator

/// Utility for generating sync identifiers matching Loop/Trio deduplication pattern
/// Used to prevent duplicate entries when multiple apps upload to the same Nightscout
public enum SyncIdentifierGenerator {
    
    /// Generate sync identifier for a glucose entry
    /// Pattern: "{device}:{type}:{timestamp}"
    public static func forEntry(date: Double, type: String, device: String?) -> String {
        let devicePart = device ?? "T1Pal"
        return "\(devicePart):\(type):\(Int64(date))"
    }
    
    /// Generate sync identifier for a treatment
    /// Pattern: "{enteredBy}:{eventType}:{timestamp}"
    public static func forTreatment(createdAt: String, eventType: String, enteredBy: String?) -> String {
        let sourcePart = enteredBy ?? "T1Pal"
        return "\(sourcePart):\(eventType):\(createdAt)"
    }
    
    /// Generate sync identifier for a device status
    /// Pattern: "{device}:{timestamp}"
    public static func forDeviceStatus(device: String?, createdAt: String) -> String {
        let devicePart = device ?? "T1Pal"
        return "\(devicePart):devicestatus:\(createdAt)"
    }
    
    /// Generate a unique sync identifier with UUID
    public static func unique(prefix: String = "T1Pal") -> String {
        "\(prefix):\(UUID().uuidString)"
    }
}
