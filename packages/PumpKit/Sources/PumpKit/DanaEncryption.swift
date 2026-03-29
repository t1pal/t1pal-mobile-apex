// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaEncryption.swift
// PumpKit
//
// Dana pump encryption implementation supporting 3 modes:
// - Legacy (Dana-R): enhancedEncryption = 0
// - RSv3 (Dana-RS): enhancedEncryption = 1
// - BLE5 (Dana-i): enhancedEncryption = 2
//
// Trace: DANA-IMPL-002, PRD-005
// Reference: Trio/DanaKit/Encryption/

import Foundation

// MARK: - Dana CRC16

/// Dana CRC16 calculation with encryption-mode variants.
/// Different shift patterns are used depending on encryption type and command type.
public enum DanaCRC16 {
    
    /// Generate Dana CRC16 checksum.
    ///
    /// - Parameters:
    ///   - data: Data to checksum
    ///   - encryptionType: The encryption type (affects CRC algorithm)
    ///   - isEncryptionCommand: Whether this is an encryption/pairing command
    /// - Returns: CRC16 checksum value
    public static func calculate(
        _ data: Data,
        encryptionType: DanaEncryptionType,
        isEncryptionCommand: Bool = false
    ) -> UInt16 {
        var crc: UInt16 = 0
        
        for byte in data {
            var result = ((crc >> 8) | (crc << 8)) ^ UInt16(byte)
            result ^= (result & 0xFF) >> 4
            result ^= (result << 12)
            
            // Shift pattern depends on encryption type
            switch encryptionType {
            case .legacy:
                // Legacy Dana-R: same shift for all commands
                let tmp = ((result & 0xFF) << 3) | (((result & 0xFF) >> 2) << 5)
                result ^= tmp
                
            case .rsv3:
                // RSv3 Dana-RS: different shift for encryption vs normal commands
                let tmp: UInt16
                if isEncryptionCommand {
                    tmp = ((result & 0xFF) << 3) | (((result & 0xFF) >> 2) << 5)
                } else {
                    tmp = ((result & 0xFF) << 5) | (((result & 0xFF) >> 4) << 2)
                }
                result ^= tmp
                
            case .ble5:
                // BLE5 Dana-i: different shift for encryption vs normal commands
                let tmp: UInt16
                if isEncryptionCommand {
                    tmp = ((result & 0xFF) << 3) | (((result & 0xFF) >> 2) << 5)
                } else {
                    tmp = ((result & 0xFF) << 4) | (((result & 0xFF) >> 3) << 2)
                }
                result ^= tmp
            }
            
            crc = result
        }
        
        return crc
    }
    
    /// Append CRC16 to data (big-endian).
    public static func append(to data: inout Data, encryptionType: DanaEncryptionType, isEncryptionCommand: Bool = false) {
        let crc = calculate(data, encryptionType: encryptionType, isEncryptionCommand: isEncryptionCommand)
        data.append(UInt8((crc >> 8) & 0xFF))  // CRC high byte
        data.append(UInt8(crc & 0xFF))          // CRC low byte
    }
    
    /// Verify CRC16 at end of packet.
    public static func verify(_ data: Data, encryptionType: DanaEncryptionType, isEncryptionCommand: Bool = false) -> Bool {
        guard data.count >= 2 else { return false }
        
        let payload = data.dropLast(2)
        let expectedCRC = calculate(Data(payload), encryptionType: encryptionType, isEncryptionCommand: isEncryptionCommand)
        let actualCRC = UInt16(data[data.count - 2]) << 8 | UInt16(data[data.count - 1])
        
        return expectedCRC == actualCRC
    }
}

// MARK: - Packet Markers

/// Packet framing markers per encryption type.
public struct DanaPacketMarkers {
    public let start: Data
    public let end: Data
    
    /// Legacy Dana-R markers
    public static let legacy = DanaPacketMarkers(
        start: Data([0xA5, 0xA5]),
        end: Data([0x5A, 0x5A])
    )
    
    /// RSv3 Dana-RS markers (second-level encryption applied)
    public static let rsv3 = DanaPacketMarkers(
        start: Data([0x7A, 0x7A]),
        end: Data([0x2E, 0x2E])
    )
    
    /// BLE5 Dana-i markers (second-level encryption applied)
    public static let ble5 = DanaPacketMarkers(
        start: Data([0xAA, 0xAA]),
        end: Data([0xEE, 0xEE])
    )
    
    /// Get markers for encryption type
    public static func markers(for encryptionType: DanaEncryptionType) -> DanaPacketMarkers {
        switch encryptionType {
        case .legacy: return .legacy
        case .rsv3: return .rsv3
        case .ble5: return .ble5
        }
    }
}

// MARK: - Encryption Keys

/// Dana encryption key state.
/// Keys are established during the pairing process.
public struct DanaEncryptionKeys: Sendable {
    /// Time-based encryption secret (6 bytes)
    public var timeSecret: Data
    
    /// Password secret (2 bytes)
    public var passwordSecret: Data
    
    /// Passkey secret (2 bytes)
    public var passKeySecret: Data
    
    /// Pairing key (6 bytes) - RSv3/BLE5
    public var pairingKey: Data
    
    /// Random pairing key (3 bytes) - RSv3
    public var randomPairingKey: Data
    
    /// Random sync key - RSv3
    public var randomSyncKey: UInt8
    
    /// BLE5 random keys (3 bytes)
    public var ble5Keys: (UInt8, UInt8, UInt8)
    
    public init() {
        self.timeSecret = Data(count: 6)
        self.passwordSecret = Data(count: 2)
        self.passKeySecret = Data(count: 2)
        self.pairingKey = Data(count: 6)
        self.randomPairingKey = Data(count: 3)
        self.randomSyncKey = 0
        self.ble5Keys = (0, 0, 0)
    }
    
    public init(
        timeSecret: Data = Data(count: 6),
        passwordSecret: Data = Data(count: 2),
        passKeySecret: Data = Data(count: 2),
        pairingKey: Data = Data(count: 6),
        randomPairingKey: Data = Data(count: 3),
        randomSyncKey: UInt8 = 0,
        ble5Keys: (UInt8, UInt8, UInt8) = (0, 0, 0)
    ) {
        self.timeSecret = timeSecret
        self.passwordSecret = passwordSecret
        self.passKeySecret = passKeySecret
        self.pairingKey = pairingKey
        self.randomPairingKey = randomPairingKey
        self.randomSyncKey = randomSyncKey
        self.ble5Keys = ble5Keys
    }
}

// MARK: - Second Level Encryption Lookup Table

/// Lookup table for RSv3 second-level encryption.
/// From Trio/DanaKit/Encryption/EncryptionTables.swift
private let secondLevelLookup: [UInt8] = [
    0x55, 0xAA, 0x69, 0x96, 0xC3, 0x3C, 0xF0, 0x0F,
    0x5A, 0xA5, 0x6C, 0x99, 0x95, 0x56, 0xCC, 0x33,
    0x78, 0x87, 0x36, 0xC9, 0x66, 0x99, 0xA5, 0x5A,
    0x5C, 0xA3, 0x6E, 0x91, 0xC5, 0x3A, 0xF2, 0x0D,
    0x5E, 0xA1, 0x6B, 0x94, 0xC0, 0x3F, 0xF5, 0x0A,
    0x52, 0xAD, 0x6F, 0x90, 0xC4, 0x3B, 0xF1, 0x0E,
    0x7A, 0x85, 0x34, 0xCB, 0x64, 0x9B, 0xA7, 0x58,
    0x7E, 0x81, 0x30, 0xCF, 0x60, 0x9F, 0xA3, 0x5C,
    0x56, 0xA9, 0x63, 0x9C, 0xC7, 0x38, 0xF6, 0x09,
    0x7C, 0x83, 0x32, 0xCD, 0x62, 0x9D, 0xA1, 0x5E,
    0x54, 0xAB, 0x65, 0x9A, 0xC1, 0x3E, 0xF4, 0x0B,
    0x58, 0xA7, 0x61, 0x9E, 0xC6, 0x39, 0xF3, 0x0C,
    0x76, 0x89, 0x38, 0xC7, 0x68, 0x97, 0xAB, 0x54,
    0x72, 0x8D, 0x3C, 0xC3, 0x6C, 0x93, 0xAF, 0x50,
    0x74, 0x8B, 0x3A, 0xC5, 0x6A, 0x95, 0xA9, 0x56,
    0x70, 0x8F, 0x3E, 0xC1, 0x6E, 0x91, 0xAD, 0x52,
    0x51, 0xAE, 0x6D, 0x92, 0xC2, 0x3D, 0xF7, 0x08,
    0x79, 0x86, 0x37, 0xC8, 0x67, 0x98, 0xA4, 0x5B,
    0x5D, 0xA2, 0x6A, 0x95, 0xC3, 0x3C, 0xF0, 0x0F,
    0x7D, 0x82, 0x33, 0xCC, 0x63, 0x9C, 0xA0, 0x5F,
    0x53, 0xAC, 0x69, 0x96, 0xC5, 0x3A, 0xF2, 0x0D,
    0x77, 0x88, 0x39, 0xC6, 0x69, 0x96, 0xAA, 0x55,
    0x5F, 0xA0, 0x6C, 0x93, 0xC0, 0x3F, 0xF5, 0x0A,
    0x7B, 0x84, 0x35, 0xCA, 0x65, 0x9A, 0xA6, 0x59,
    0x57, 0xA8, 0x62, 0x9D, 0xC6, 0x39, 0xF3, 0x0C,
    0x73, 0x8C, 0x3D, 0xC2, 0x6D, 0x92, 0xAE, 0x51,
    0x59, 0xA6, 0x60, 0x9F, 0xC7, 0x38, 0xF6, 0x09,
    0x7F, 0x80, 0x31, 0xCE, 0x61, 0x9E, 0xA2, 0x5D,
    0x75, 0x8A, 0x3B, 0xC4, 0x6B, 0x94, 0xA8, 0x57,
    0x71, 0x8E, 0x3F, 0xC0, 0x6F, 0x90, 0xAC, 0x53,
    0x50, 0xAF, 0x6E, 0x91, 0xC1, 0x3E, 0xF4, 0x0B,
    0x7A, 0x85, 0x34, 0xCB, 0x64, 0x9B, 0xA7, 0x58
]

// MARK: - Dana Encryption Engine

/// Dana encryption/decryption engine supporting all 3 encryption modes.
public struct DanaEncryption {
    
    /// Current encryption type
    public let encryptionType: DanaEncryptionType
    
    /// Whether encryption mode is active (vs pairing mode)
    public var isEncryptionMode: Bool
    
    /// Encryption keys
    public var keys: DanaEncryptionKeys
    
    public init(encryptionType: DanaEncryptionType, keys: DanaEncryptionKeys = DanaEncryptionKeys()) {
        self.encryptionType = encryptionType
        self.isEncryptionMode = false
        self.keys = keys
    }
    
    // MARK: - Encrypt
    
    /// Encrypt a command packet for transmission.
    /// - Parameters:
    ///   - data: Raw packet data with A5A5/5A5A markers
    ///   - isEncryptionCommand: Whether this is an encryption/pairing command
    /// - Returns: Encrypted packet data
    public mutating func encrypt(_ data: Data, isEncryptionCommand: Bool = false) -> Data {
        var buffer = data
        
        switch encryptionType {
        case .legacy:
            // Legacy: apply time/password/passkey encryption
            if !isEncryptionCommand {
                encryptLegacy(&buffer)
            }
            
        case .rsv3:
            // RSv3: apply second-level encryption if keys established
            if keys.pairingKey.count == 6 && keys.randomPairingKey.count == 3 {
                encryptRSv3(&buffer)
            }
            
        case .ble5:
            // BLE5: apply BLE5 encryption if keys established
            if keys.ble5Keys != (0, 0, 0) {
                encryptBLE5(&buffer)
            }
        }
        
        return buffer
    }
    
    /// Apply legacy encryption (Dana-R).
    private func encryptLegacy(_ buffer: inout Data) {
        // XOR with time secret
        for i in 0..<min(buffer.count, keys.timeSecret.count) {
            buffer[i] ^= keys.timeSecret[i % keys.timeSecret.count]
        }
        
        // XOR with password secret
        for i in 0..<min(buffer.count, keys.passwordSecret.count) {
            buffer[i] ^= keys.passwordSecret[i % keys.passwordSecret.count]
        }
        
        // XOR with passkey secret
        for i in 0..<min(buffer.count, keys.passKeySecret.count) {
            buffer[i] ^= keys.passKeySecret[i % keys.passKeySecret.count]
        }
    }
    
    /// Apply RSv3 second-level encryption (Dana-RS).
    private mutating func encryptRSv3(_ buffer: inout Data) {
        guard buffer.count >= 4 else { return }
        
        // Replace markers
        if buffer[0] == 0xA5 && buffer[1] == 0xA5 {
            buffer[0] = 0x7A
            buffer[1] = 0x7A
        }
        if buffer[buffer.count - 2] == 0x5A && buffer[buffer.count - 1] == 0x5A {
            buffer[buffer.count - 2] = 0x2E
            buffer[buffer.count - 1] = 0x2E
        }
        
        // Apply byte-level encryption
        var syncKey = keys.randomSyncKey
        for i in 0..<buffer.count {
            buffer[i] ^= keys.pairingKey[0]
            buffer[i] &-= syncKey
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            
            buffer[i] &+= keys.pairingKey[1]
            buffer[i] ^= keys.pairingKey[2]
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            
            buffer[i] &-= keys.pairingKey[3]
            buffer[i] ^= keys.pairingKey[4]
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            
            buffer[i] ^= keys.pairingKey[5]
            buffer[i] ^= syncKey
            
            // Apply lookup table transformations
            buffer[i] ^= secondLevelLookup[Int(keys.pairingKey[0])]
            buffer[i] &+= secondLevelLookup[Int(keys.pairingKey[1])]
            buffer[i] &-= secondLevelLookup[Int(keys.pairingKey[2])]
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            
            buffer[i] ^= secondLevelLookup[Int(keys.pairingKey[3])]
            buffer[i] &+= secondLevelLookup[Int(keys.pairingKey[4])]
            buffer[i] &-= secondLevelLookup[Int(keys.pairingKey[5])]
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            
            buffer[i] ^= secondLevelLookup[Int(keys.randomPairingKey[0])]
            buffer[i] &+= secondLevelLookup[Int(keys.randomPairingKey[1])]
            buffer[i] &-= secondLevelLookup[Int(keys.randomPairingKey[2])]
            
            syncKey = buffer[i]
        }
        keys.randomSyncKey = syncKey
    }
    
    /// Apply BLE5 encryption (Dana-i).
    private func encryptBLE5(_ buffer: inout Data) {
        guard buffer.count >= 4 else { return }
        
        // Replace markers
        if buffer[0] == 0xA5 && buffer[1] == 0xA5 {
            buffer[0] = 0xAA
            buffer[1] = 0xAA
        }
        if buffer[buffer.count - 2] == 0x5A && buffer[buffer.count - 1] == 0x5A {
            buffer[buffer.count - 2] = 0xEE
            buffer[buffer.count - 1] = 0xEE
        }
        
        // Apply byte-level encryption
        for i in 0..<buffer.count {
            buffer[i] &+= keys.ble5Keys.0
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            
            buffer[i] &-= keys.ble5Keys.1
            buffer[i] ^= keys.ble5Keys.2
        }
    }
    
    // MARK: - Decrypt
    
    /// Decrypt a received packet.
    /// - Parameters:
    ///   - data: Encrypted packet data
    ///   - isEncryptionCommand: Whether this is an encryption/pairing response
    /// - Returns: Decrypted packet data
    public mutating func decrypt(_ data: Data, isEncryptionCommand: Bool = false) -> Data {
        var buffer = data
        
        switch encryptionType {
        case .legacy:
            if !isEncryptionCommand {
                decryptLegacy(&buffer)
            }
            
        case .rsv3:
            if keys.pairingKey.count == 6 && keys.randomPairingKey.count == 3 {
                decryptRSv3(&buffer)
            }
            
        case .ble5:
            if keys.ble5Keys != (0, 0, 0) {
                decryptBLE5(&buffer)
            }
        }
        
        return buffer
    }
    
    /// Decrypt legacy packet (same as encrypt - symmetric XOR).
    private func decryptLegacy(_ buffer: inout Data) {
        encryptLegacy(&buffer)  // XOR is symmetric
    }
    
    /// Decrypt RSv3 packet (reverse of encrypt).
    private mutating func decryptRSv3(_ buffer: inout Data) {
        guard buffer.count >= 4 else { return }
        
        var syncKey = keys.randomSyncKey
        for i in 0..<buffer.count {
            let savedByte = buffer[i]
            
            // Reverse the encryption operations
            buffer[i] &+= secondLevelLookup[Int(keys.randomPairingKey[2])]
            buffer[i] &-= secondLevelLookup[Int(keys.randomPairingKey[1])]
            buffer[i] ^= secondLevelLookup[Int(keys.randomPairingKey[0])]
            
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            buffer[i] &+= secondLevelLookup[Int(keys.pairingKey[5])]
            buffer[i] &-= secondLevelLookup[Int(keys.pairingKey[4])]
            buffer[i] ^= secondLevelLookup[Int(keys.pairingKey[3])]
            
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            buffer[i] &+= secondLevelLookup[Int(keys.pairingKey[2])]
            buffer[i] &-= secondLevelLookup[Int(keys.pairingKey[1])]
            buffer[i] ^= secondLevelLookup[Int(keys.pairingKey[0])]
            
            buffer[i] ^= syncKey
            buffer[i] ^= keys.pairingKey[5]
            
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            buffer[i] ^= keys.pairingKey[4]
            buffer[i] &+= keys.pairingKey[3]
            
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            buffer[i] ^= keys.pairingKey[2]
            buffer[i] &-= keys.pairingKey[1]
            
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            buffer[i] &+= syncKey
            buffer[i] ^= keys.pairingKey[0]
            
            syncKey = savedByte
        }
        keys.randomSyncKey = syncKey
        
        // Restore markers
        if buffer[0] == 0x7A && buffer[1] == 0x7A {
            buffer[0] = 0xA5
            buffer[1] = 0xA5
        }
        if buffer[buffer.count - 2] == 0x2E && buffer[buffer.count - 1] == 0x2E {
            buffer[buffer.count - 2] = 0x5A
            buffer[buffer.count - 1] = 0x5A
        }
    }
    
    /// Decrypt BLE5 packet (reverse of encrypt).
    private func decryptBLE5(_ buffer: inout Data) {
        guard buffer.count >= 4 else { return }
        
        for i in 0..<buffer.count {
            buffer[i] ^= keys.ble5Keys.2
            buffer[i] &+= keys.ble5Keys.1
            
            buffer[i] = ((buffer[i] >> 4) & 0x0F) | ((buffer[i] & 0x0F) << 4)
            buffer[i] &-= keys.ble5Keys.0
        }
        
        // Restore markers
        if buffer[0] == 0xAA && buffer[1] == 0xAA {
            buffer[0] = 0xA5
            buffer[1] = 0xA5
        }
        if buffer[buffer.count - 2] == 0xEE && buffer[buffer.count - 1] == 0xEE {
            buffer[buffer.count - 2] = 0x5A
            buffer[buffer.count - 1] = 0x5A
        }
    }
    
    // MARK: - Encryption Type Detection
    
    /// Detect encryption type from packet markers.
    /// - Parameter data: Received packet data
    /// - Returns: Detected encryption type, or nil if unknown
    public static func detectEncryptionType(from data: Data) -> DanaEncryptionType? {
        guard data.count >= 4 else { return nil }
        
        let startMarker = Data(data.prefix(2))
        let endMarker = Data(data.suffix(2))
        
        if startMarker == DanaPacketMarkers.legacy.start && endMarker == DanaPacketMarkers.legacy.end {
            return .legacy
        }
        if startMarker == DanaPacketMarkers.rsv3.start && endMarker == DanaPacketMarkers.rsv3.end {
            return .rsv3
        }
        if startMarker == DanaPacketMarkers.ble5.start && endMarker == DanaPacketMarkers.ble5.end {
            return .ble5
        }
        
        return nil
    }
}
