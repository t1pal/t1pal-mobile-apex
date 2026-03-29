// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TransmitterID.swift
// CGMKit - DexcomG6
//
// Dexcom transmitter ID parsing and generation detection.
// Trace: PRD-008 REQ-BLE-007

import Foundation

/// Dexcom transmitter generation
public enum DexcomGeneration: String, Sendable, Codable {
    case g5
    case g6
    case g6Plus  // Firefly
    case unknown
}

/// Dexcom transmitter ID with generation detection
public struct TransmitterID: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The 6-character transmitter ID
    public let id: String
    
    /// Detected transmitter generation
    public var generation: DexcomGeneration {
        guard id.count == 6 else { return .unknown }
        
        let firstChar = id.prefix(1)
        let secondChar = id.dropFirst().prefix(1)
        
        // G6+ (Firefly) transmitters start with 8G, 8H, 8J, 8K, 8L, 8M, 8N, 8P
        if firstChar == "8" {
            let fireflySecondChars = ["G", "H", "J", "K", "L", "M", "N", "P"]
            if fireflySecondChars.contains(String(secondChar)) {
                return .g6Plus
            }
        }
        
        // G6 transmitters start with 80, 81
        if firstChar == "8" {
            return .g6
        }
        
        // G5 transmitters start with 4, 5, 6
        if ["4", "5", "6"].contains(String(firstChar)) {
            return .g5
        }
        
        return .unknown
    }
    
    /// Whether this transmitter uses the G6 authentication protocol
    public var usesG6Auth: Bool {
        switch generation {
        case .g6, .g6Plus:
            return true
        case .g5, .unknown:
            return false
        }
    }
    
    /// Whether this transmitter requires encryption (G6+)
    public var requiresEncryption: Bool {
        generation == .g6Plus
    }
    
    /// Create from a transmitter ID string
    /// - Parameter id: 6-character transmitter ID
    public init?(_ id: String) {
        let cleaned = id.uppercased().trimmingCharacters(in: .whitespaces)
        guard cleaned.count == 6 else { return nil }
        guard cleaned.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        self.id = cleaned
    }
    
    /// String representation
    public var description: String { id }
}

// MARK: - Transmitter ID Validation

extension TransmitterID {
    /// Valid characters for transmitter IDs
    private static let validCharacters = CharacterSet(charactersIn: "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    
    /// Check if a string is a valid transmitter ID format
    public static func isValid(_ id: String) -> Bool {
        let cleaned = id.uppercased().trimmingCharacters(in: .whitespaces)
        guard cleaned.count == 6 else { return false }
        return cleaned.unicodeScalars.allSatisfy { validCharacters.contains($0) }
    }
}
