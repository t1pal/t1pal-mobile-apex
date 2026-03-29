//
//  Libre3Keys.swift
//  CGMKit
//
//  ECDH keys and certificates for Libre 3 authentication.
//  Ported from Juggluco ECDHCrypto.java under GPLv3.
//
//  Original source: externals/Juggluco/Common/src/libre3/java/tk/glucodata/ECDHCrypto.java
//  Copyright (C) 2021 Jaap Korthals Altes <jaapkorthalsaltes@gmail.com>
//
//  This file is part of Juggluco, an Android app to receive and display
//  glucose values from Freestyle Libre 2 and 3 sensors.
//
//  Juggluco is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//

import Foundation

// MARK: - Security Version

/// Security version selects which key set to use during authentication
public enum Libre3SecurityVersion: Int, Sendable {
    case version0 = 0  // Security level 0x00
    case version1 = 1  // Security level 0x03
    
    /// Maximum number of key versions
    static let maxKeys = 2
}

// MARK: - App Certificates (162 bytes each)

/// App certificates sent to sensor during authentication handshake.
/// Format: [version(1)][security(1)][serial(16)][flags(2)][public_key(65)][signature(64)]
public enum Libre3AppCertificates {
    
    /// Certificate for security version 0 (level 0x00)
    public static let certificate0: Data = Data([
        // Header: version=0x03, security=0x00, serial=01-10, flags=00 01
        0x03, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e,
        0x0f, 0x10, 0x00, 0x01, 0x5f, 0x14, 0x9f, 0xe1, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00,
        // Public key (65 bytes, uncompressed P-256 point starting with 0x04)
        0x04, 0x27, 0x51, 0xfd, 0x1e, 0xf4, 0x2b, 0x14, 0x5a, 0x52, 0xc5, 0x93, 0xae, 0x6b, 0x5a, 0x75,
        0x58, 0x8a, 0x9f, 0x7e, 0xaf, 0x1c, 0x0f, 0x99, 0x85, 0xf9, 0x93, 0xd5, 0x8f, 0x14, 0x7b, 0xb8,
        0x41, 0x68, 0x42, 0x24, 0x49, 0x96, 0x37, 0x92, 0xdc, 0x43, 0xf3, 0x84, 0x47, 0xef, 0xeb, 0xbb,
        0xeb, 0x4a, 0x53, 0xb3, 0x25, 0x5c, 0x0b, 0xe0, 0xfe, 0x1f, 0x23, 0x58, 0x44, 0xa3, 0xd3, 0x29,
        0x9e,
        // Signature (64 bytes)
        0xba, 0x97, 0xb8, 0xe6, 0xc3, 0x17, 0x09, 0x39, 0xf2, 0x77, 0x8f, 0x64, 0x86, 0x6f, 0x06, 0x6d,
        0xeb, 0x91, 0x5d, 0xd6, 0x62, 0x9e, 0xee, 0x47, 0x30, 0xa1, 0xe1, 0x4c, 0xab, 0x75, 0xc1, 0x8c,
        0x4f, 0xec, 0x53, 0xf8, 0x85, 0x4c, 0x87, 0x64, 0x3a, 0x76, 0x4f, 0x40, 0x87, 0xae, 0xc0, 0x39,
        0x4c, 0x21, 0x0c, 0x18, 0x86, 0x5a, 0x8f, 0xf4, 0x5a, 0xdc, 0x37, 0x27, 0xf4, 0x8b, 0x53, 0xa7
    ])
    
    /// Certificate for security version 1 (level 0x03)
    public static let certificate1: Data = Data([
        // Header: version=0x03, security=0x03, serial=01-10, flags=00 01
        0x03, 0x03, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e,
        0x0f, 0x10, 0x00, 0x01, 0x61, 0x89, 0x76, 0x55, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00,
        // Public key (65 bytes)
        0x04, 0x82, 0x42, 0xbe, 0x33, 0xf1, 0xa3, 0x30, 0x88, 0x01, 0x12, 0xfa, 0x62, 0xcc, 0x48, 0x42,
        0xa4, 0x3d, 0x12, 0x04, 0x92, 0x2a, 0xd2, 0x01, 0xd8, 0x77, 0x5b, 0xb2, 0x26, 0xf6, 0x11, 0xf7,
        0x5b, 0x0e, 0xf3, 0xd5, 0xbc, 0x6c, 0xc4, 0x31, 0x7c, 0xaa, 0x45, 0x75, 0x84, 0xab, 0x00, 0x3f,
        0x17, 0x12, 0x33, 0x60, 0x89, 0xd3, 0xa4, 0xf2, 0x98, 0x38, 0xed, 0x0d, 0xc6, 0x66, 0xde, 0xae,
        0xa2,
        // Signature (64 bytes)
        0xd6, 0x5a, 0x00, 0xdf, 0xff, 0x5d, 0x7b, 0xca, 0xe2, 0x16, 0x55, 0xe3, 0x02, 0xe3, 0x45, 0x8e,
        0x77, 0x4d, 0xaa, 0xaa, 0xca, 0x87, 0xaf, 0x75, 0xf1, 0xb8, 0x78, 0x84, 0xb1, 0x8d, 0x4c, 0xe8,
        0x75, 0xd0, 0xd1, 0x08, 0xc9, 0x03, 0xa8, 0x34, 0x47, 0x1a, 0x4f, 0xf6, 0x74, 0xb2, 0xd3, 0x0b,
        0xcb, 0xa0, 0x62, 0x37, 0x30, 0x14, 0xb7, 0x78, 0x6e, 0x44, 0x37, 0xb1, 0x77, 0xae, 0xc3, 0xc8
    ])
    
    /// Get certificate for security version
    public static func certificate(for version: Libre3SecurityVersion) -> Data {
        switch version {
        case .version0: return certificate0
        case .version1: return certificate1
        }
    }
}

// MARK: - App Private Keys (165 bytes each, whiteCryption SKB format)

/// App private keys for ECDH key agreement.
///
/// **WARNING**: These are in whiteCryption Secure Key Box (SKB) format — NOT raw P-256 scalars.
/// The private key scalar is encrypted/obfuscated within the SKB container and cannot be
/// extracted without the native `liblibre3extension.so` library.
///
/// **Structure** (165 bytes):
/// ```
/// [0-3]     Magic/checksum (unique per key)
/// [4-7]     Type flags: 0x02000000
/// [8-11]    Security flags: 0x01000001
/// [12-16]   Padding (zeros)
/// [17-32]   SKB header (identical across keys)
/// [33-64]   Obfuscated key material 1 (32 bytes)
/// [65-68]   Separator: 0x00000001
/// [69-92]   Obfuscated key material 2 (24 bytes)
/// [93-96]   Length marker: 0x00000020 (32)
/// [97-128]  Obfuscated key material 3 (32 bytes)
/// [129-144] Padding (16 zeros)
/// [145-164] Trailing MAC/checksum (20 bytes)
/// ```
///
/// **Usage**: For pure Swift implementation, use ephemeral ECDH keys instead.
/// The sensor provides session keys (`kEnc`, `ivEnc`) after challenge-response.
///
/// See: `docs/protocols/LIBRE3-NATIVE-LIB-ANALYSIS.md` for full analysis.
public enum Libre3AppPrivateKeys {
    
    /// Private key for security version 0
    public static let privateKey0: Data = Data([
        0x43, 0xF2, 0xC5, 0x3D, 0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x96, 0x95, 0x77, 0x4B, 0x9A, 0x04, 0x53, 0x51, 0xFB, 0x16, 0x0B, 0xEC, 0x5F, 0x49, 0xDB,
        0xDF, 0x57, 0x45, 0x48, 0x50, 0x67, 0x78, 0x6C, 0xDE, 0x13, 0x08, 0x83, 0xD8, 0x3D, 0xF6, 0x96,
        0x81, 0x4E, 0xA4, 0x1E, 0xA7, 0xD2, 0xF8, 0xD2, 0x30, 0x84, 0x76, 0xB4, 0x9A, 0x01, 0x2C, 0x4E,
        0xBB, 0x00, 0x00, 0x00, 0x01, 0x7D, 0x4D, 0x61, 0x51, 0x06, 0x81, 0xBF, 0x22, 0x31, 0x67, 0x6B,
        0x90, 0x3B, 0x17, 0xED, 0x53, 0x98, 0x0D, 0x98, 0xFE, 0x68, 0x2E, 0xE4, 0x4B, 0x00, 0x00, 0x00,
        0x20, 0x5B, 0x7B, 0x96, 0xAA, 0xE3, 0xFF, 0x22, 0x2D, 0x4D, 0x37, 0x1E, 0x7A, 0xA6, 0x2C, 0xFA,
        0xA0, 0x9B, 0xF8, 0x42, 0x1C, 0xC1, 0xDA, 0x7B, 0x7B, 0x0D, 0xF9, 0x34, 0x33, 0xCC, 0x49, 0xFB,
        0x0E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x96, 0x9E, 0xDB, 0x28, 0xBF, 0x6F, 0xC0, 0xFF, 0x76, 0x0A, 0xF0, 0x95, 0x92, 0x1D, 0x9F,
        0x1E, 0x3B, 0x16, 0x77, 0xB5
    ])
    
    /// Private key for security version 1
    public static let privateKey1: Data = Data([
        0x1D, 0x85, 0x8F, 0x06, 0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x96, 0x95, 0x77, 0x4B, 0x9A, 0x04, 0x53, 0x51, 0xFB, 0x16, 0x0B, 0xEC, 0x5F, 0x49, 0xDB,
        0xDF, 0x0D, 0xC0, 0xCE, 0x52, 0xFB, 0x56, 0x5F, 0x84, 0xE6, 0x13, 0xB8, 0x19, 0xAE, 0xD3, 0xDF,
        0x91, 0x9C, 0xE3, 0x0A, 0x3D, 0xD4, 0xC0, 0x12, 0xEA, 0xEA, 0x70, 0xC8, 0xCC, 0xE2, 0x89, 0x58,
        0x40, 0x00, 0x00, 0x00, 0x01, 0x9B, 0xC7, 0x79, 0x12, 0x3D, 0x86, 0x60, 0xB3, 0x7E, 0x99, 0xB4,
        0xBF, 0x10, 0xC1, 0xC4, 0x2C, 0x11, 0x35, 0xB3, 0x02, 0x5B, 0xC9, 0xB2, 0xEF, 0x00, 0x00, 0x00,
        0x20, 0xE3, 0xA1, 0xFB, 0x17, 0x80, 0xA1, 0x63, 0x80, 0x2A, 0xA0, 0xFE, 0xB1, 0xF2, 0x00, 0xAC,
        0x26, 0x9A, 0x42, 0xB2, 0x29, 0x03, 0x8C, 0xA6, 0xE1, 0x4D, 0x40, 0xEF, 0xBC, 0x6B, 0x7B, 0x6A,
        0xE8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0xCE, 0xC6, 0x67, 0xE6, 0xC0, 0x9D, 0x20, 0xF5, 0xC0, 0x33, 0xD0, 0x61, 0xB5, 0xFC, 0xA1,
        0x8B, 0x39, 0x92, 0x06, 0x8B
    ])
    
    /// Get private key for security version
    public static func privateKey(for version: Libre3SecurityVersion) -> Data {
        switch version {
        case .version0: return privateKey0
        case .version1: return privateKey1
        }
    }
}

// MARK: - Patch Signing Public Keys (65 bytes each, uncompressed P-256)

/// Sensor (patch) public keys for certificate verification.
/// Format: [0x04][X(32)][Y(32)] - uncompressed EC point
public enum Libre3PatchSigningKeys {
    
    /// Signing key 0
    public static let signingKey0: Data = Data([
        0x04,
        // X coordinate (32 bytes)
        0xB6, 0x9D, 0x17, 0x34, 0xF5, 0xE4, 0x25, 0xBC, 0xC0, 0x57, 0x6A, 0xD1, 0xF7, 0x27, 0xC1, 0x31,
        0x1C, 0x90, 0xB6, 0xEA, 0x98, 0x6F, 0x00, 0x6E, 0x7E, 0x9F, 0x90, 0x96, 0xF6, 0xA8, 0x28, 0x4F,
        // Y coordinate (32 bytes)
        0x12, 0xBF, 0x7D, 0xDF, 0xE1, 0x54, 0xA3, 0xF1, 0xD4, 0x5A, 0x0F, 0x27, 0x34, 0xEC, 0xAB, 0xCA,
        0x6B, 0x9E, 0xB5, 0x6E, 0xE4, 0xEC, 0xCA, 0x87, 0x85, 0x3A, 0xD8, 0x53, 0xB6, 0xA6, 0x41, 0x80
    ])
    
    /// Signing key 1
    public static let signingKey1: Data = Data([
        0x04,
        // X coordinate (32 bytes)
        0xA2, 0xD8, 0x47, 0x89, 0x90, 0x94, 0x5F, 0x70, 0xA9, 0x57, 0x0A, 0xDE, 0x07, 0xB1, 0x55, 0xBC,
        0x90, 0x4D, 0x2D, 0x38, 0x06, 0x47, 0x58, 0x7B, 0x12, 0x39, 0x17, 0x01, 0x30, 0x9B, 0xD1, 0x0B,
        // Y coordinate (32 bytes)
        0x59, 0x90, 0xC4, 0xC4, 0x7C, 0x47, 0xF1, 0xF0, 0x80, 0x46, 0xCB, 0x6F, 0x2D, 0xE0, 0x74, 0x8D,
        0x1F, 0xA7, 0xF7, 0x37, 0x90, 0xEC, 0x9D, 0x8D, 0xD6, 0x37, 0x21, 0x27, 0x78, 0x52, 0x88, 0x38
    ])
    
    /// Get signing key by index
    public static func signingKey(at index: Int) -> Data? {
        switch index {
        case 0: return signingKey0
        case 1: return signingKey1
        default: return nil
        }
    }
    
    /// Signing key 1 X coordinate (for direct use in EC operations)
    public static let signingKey1X: Data = Data([
        0xA2, 0xD8, 0x47, 0x89, 0x90, 0x94, 0x5F, 0x70, 0xA9, 0x57, 0x0A, 0xDE, 0x07, 0xB1, 0x55, 0xBC,
        0x90, 0x4D, 0x2D, 0x38, 0x06, 0x47, 0x58, 0x7B, 0x12, 0x39, 0x17, 0x01, 0x30, 0x9B, 0xD1, 0x0B
    ])
    
    /// Signing key 1 Y coordinate (for direct use in EC operations)
    public static let signingKey1Y: Data = Data([
        0x59, 0x90, 0xC4, 0xC4, 0x7C, 0x47, 0xF1, 0xF0, 0x80, 0x46, 0xCB, 0x6F, 0x2D, 0xE0, 0x74, 0x8D,
        0x1F, 0xA7, 0xF7, 0x37, 0x90, 0xEC, 0x9D, 0x8D, 0xD6, 0x37, 0x21, 0x27, 0x78, 0x52, 0x88, 0x38
    ])
}

// MARK: - Security Commands

/// BLE security commands for Libre 3 authentication handshake
public enum Libre3SecurityCommand: UInt8, Sendable {
    case ecdhStart              = 0x01
    case loadCertData           = 0x02
    case loadCertDone           = 0x03
    case certAccepted           = 0x04
    case authorized             = 0x05
    case authorizeECDSA         = 0x06
    case authorizationChallenge = 0x07
    case challengeLoadDone      = 0x08
    case sendCert               = 0x09
    case certReady              = 0x0A
    case ivAuthenticatedSend    = 0x0B
    case ivReady                = 0x0C
    case keyAgreement           = 0x0D
    case ephemeralLoadDone      = 0x0E
    case ephemeralKeyReady      = 0x0F
    case ecdhComplete           = 0x10
    case authorizeSymmetric     = 0x11
    case modeSwitch             = 0x12
    case verificationFailure    = 0x13
}

// MARK: - Packet Descriptors (for nonce construction)

/// Packet type descriptors used in AES-CCM nonce construction
public enum Libre3PacketDescriptor {
    /// Control packets (type 0)
    public static let control: [UInt8] = [0x24, 0x40, 0x00]
    
    /// Data packets (type 1)
    public static let data: [UInt8] = [0x29, 0x40, 0x00]
    
    /// Type 2 packets
    public static let type2: [UInt8] = [0x25, 0x00, 0x00]
    
    /// Get descriptor for packet type
    public static func descriptor(for type: Int) -> [UInt8] {
        switch type {
        case 0: return control
        case 1: return data
        case 2: return type2
        default: return control
        }
    }
}

// MARK: - BLE Data Structures

/// Libre 3 patch state from BLE PatchStatus (raw BLE values)
/// Different from Libre3SensorState which is higher-level app state
/// Source: DiaBLE Libre3.swift, docs/protocols/LIBRE3-KEY-DERIVATION.md
public enum Libre3PatchState: UInt8, Sendable, CustomStringConvertible {
    case manufacturing      = 0
    case storage            = 1  // Out of package, not activated
    case insertionDetection = 2
    case insertionFailed    = 3
    case paired             = 4  // Active and advertising
    case expired            = 5  // Still advertising 24h after expiry
    case terminated         = 6  // Shutdown command sent
    case error              = 7  // Fell off or failed
    case errorTerminated    = 8
    
    public var description: String {
        switch self {
        case .manufacturing:      return "Manufacturing"
        case .storage:            return "Not activated"
        case .insertionDetection: return "Insertion detection"
        case .insertionFailed:    return "Insertion failed"
        case .paired:             return "Paired"
        case .expired:            return "Expired"
        case .terminated:         return "Terminated"
        case .error:              return "Error"
        case .errorTerminated:    return "Terminated (error)"
        }
    }
    
    /// Whether sensor is in an active/readable state
    public var isActive: Bool {
        self == .paired
    }
}

/// Real-time glucose reading from BLE oneMinuteReading characteristic (29 bytes)
/// Source: DiaBLE Libre3.swift GlucoseData struct
/// Trace: LIBRE3-025a
public struct Libre3GlucoseData: Sendable, Equatable {
    /// Expected raw data size
    public static let dataSize = 29
    
    /// Sensor lifetime in minutes
    public let lifeCount: UInt16
    
    /// Current glucose in mg/dL
    public let readingMgDl: UInt16
    
    /// Rate of change (signed, mg/dL/min scaled)
    public let rateOfChange: Int16
    
    /// Early Signal Attenuation duration (minutes)
    public let esaDuration: UInt16
    
    /// Projected glucose (scaled value)
    public let projectedGlucose: UInt16
    
    /// Historical reading lifeCount
    public let historicalLifeCount: UInt16
    
    /// Historical glucose in mg/dL
    public let historicalReading: UInt16
    
    /// Raw bitfield: [7:3]=trend, [2:0]=other flags
    public let bitfields: UInt8
    
    /// Uncapped current glucose
    public let uncappedCurrentMgDl: UInt16
    
    /// Uncapped historical glucose
    public let uncappedHistoricMgDl: UInt16
    
    /// Raw temperature value
    public let temperature: UInt16
    
    /// Fast data blob (8 bytes)
    public let fastData: Data
    
    /// Trend arrow value (0-5, extracted from bitfields)
    public var trendArrow: UInt8 {
        (bitfields >> 3) & 0x07
    }
    
    /// Other flags (bits 0-2 of bitfields)
    public var flags: UInt8 {
        bitfields & 0x07
    }
    
    /// Parse from 29-byte BLE data
    /// - Parameter data: Raw BLE data from oneMinuteReading characteristic
    /// - Returns: Parsed glucose data, or nil if data is invalid
    public static func parse(_ data: Data) -> Libre3GlucoseData? {
        guard data.count >= dataSize else { return nil }
        
        return Libre3GlucoseData(
            lifeCount: UInt16(data[0]) | (UInt16(data[1]) << 8),
            readingMgDl: UInt16(data[2]) | (UInt16(data[3]) << 8),
            rateOfChange: Int16(bitPattern: UInt16(data[4]) | (UInt16(data[5]) << 8)),
            esaDuration: UInt16(data[6]) | (UInt16(data[7]) << 8),
            projectedGlucose: UInt16(data[8]) | (UInt16(data[9]) << 8),
            historicalLifeCount: UInt16(data[10]) | (UInt16(data[11]) << 8),
            historicalReading: UInt16(data[12]) | (UInt16(data[13]) << 8),
            bitfields: data[14],
            uncappedCurrentMgDl: UInt16(data[15]) | (UInt16(data[16]) << 8),
            uncappedHistoricMgDl: UInt16(data[17]) | (UInt16(data[18]) << 8),
            temperature: UInt16(data[19]) | (UInt16(data[20]) << 8),
            fastData: data.subdata(in: 21..<29)
        )
    }
    
    /// Full initializer for testing
    public init(
        lifeCount: UInt16,
        readingMgDl: UInt16,
        rateOfChange: Int16,
        esaDuration: UInt16,
        projectedGlucose: UInt16,
        historicalLifeCount: UInt16,
        historicalReading: UInt16,
        bitfields: UInt8,
        uncappedCurrentMgDl: UInt16,
        uncappedHistoricMgDl: UInt16,
        temperature: UInt16,
        fastData: Data
    ) {
        self.lifeCount = lifeCount
        self.readingMgDl = readingMgDl
        self.rateOfChange = rateOfChange
        self.esaDuration = esaDuration
        self.projectedGlucose = projectedGlucose
        self.historicalLifeCount = historicalLifeCount
        self.historicalReading = historicalReading
        self.bitfields = bitfields
        self.uncappedCurrentMgDl = uncappedCurrentMgDl
        self.uncappedHistoricMgDl = uncappedHistoricMgDl
        self.temperature = temperature
        self.fastData = fastData
    }
}

/// Sensor status from BLE patchStatus characteristic (12 bytes)
/// Source: DiaBLE Libre3.swift PatchStatus struct
/// Trace: LIBRE3-025b
public struct Libre3PatchStatus: Sendable, Equatable {
    /// Expected raw data size
    public static let dataSize = 12
    
    /// Sensor lifetime in minutes
    public let lifeCount: UInt16
    
    /// Error code (0 = no error)
    public let errorData: UInt16
    
    /// Event data
    public let eventData: UInt16
    
    /// Event index (255 = no data)
    public let index: UInt8
    
    /// Raw patch state (0-8)
    public let patchStateRaw: UInt8
    
    /// Current lifeCount (may differ from lifeCount during transitions)
    public let currentLifeCount: UInt16
    
    /// Stack disconnect reason
    public let stackDisconnectReason: UInt8
    
    /// App disconnect reason
    public let appDisconnectReason: UInt8
    
    /// Parsed patch state enum
    public var patchState: Libre3PatchState? {
        Libre3PatchState(rawValue: patchStateRaw)
    }
    
    /// Whether there's an error condition
    public var hasError: Bool {
        errorData != 0
    }
    
    /// Whether event data is available
    public var hasEventData: Bool {
        index != 255
    }
    
    /// Parse from 12-byte BLE data
    /// - Parameter data: Raw BLE data from patchStatus characteristic
    /// - Returns: Parsed status, or nil if data is invalid
    public static func parse(_ data: Data) -> Libre3PatchStatus? {
        guard data.count >= dataSize else { return nil }
        
        return Libre3PatchStatus(
            lifeCount: UInt16(data[0]) | (UInt16(data[1]) << 8),
            errorData: UInt16(data[2]) | (UInt16(data[3]) << 8),
            eventData: UInt16(data[4]) | (UInt16(data[5]) << 8),
            index: data[6],
            patchStateRaw: data[7],
            currentLifeCount: UInt16(data[8]) | (UInt16(data[9]) << 8),
            stackDisconnectReason: data[10],
            appDisconnectReason: data[11]
        )
    }
    
    /// Full initializer for testing
    public init(
        lifeCount: UInt16,
        errorData: UInt16,
        eventData: UInt16,
        index: UInt8,
        patchStateRaw: UInt8,
        currentLifeCount: UInt16,
        stackDisconnectReason: UInt8,
        appDisconnectReason: UInt8
    ) {
        self.lifeCount = lifeCount
        self.errorData = errorData
        self.eventData = eventData
        self.index = index
        self.patchStateRaw = patchStateRaw
        self.currentLifeCount = currentLifeCount
        self.stackDisconnectReason = stackDisconnectReason
        self.appDisconnectReason = appDisconnectReason
    }
}

// MARK: - Control Commands

/// Command types for Libre 3 patchControl characteristic
/// Source: DiaBLE Libre3.swift ControlCommand enum
/// Trace: LIBRE3-025c
public enum Libre3ControlCommandType: UInt8, Sendable {
    /// Request historical data from lifeCount
    case historic = 1
    /// Request clinical data (backfill)
    case backfill = 2
    /// Request event log
    case eventLog = 3
    /// Request factory data
    case factoryData = 4
    /// Shutdown sensor
    case shutdown = 5
}

/// Builder for 13-byte control commands sent to patchControl characteristic
/// Format: [kind(2)][arg(1)][from(4)] + 6 bytes padding/sequence
/// Source: DiaBLE Libre3.swift, docs/protocols/LIBRE3-KEY-DERIVATION.md
/// Trace: LIBRE3-025c
public struct Libre3ControlCommand: Sendable, Equatable {
    /// Total command size
    public static let dataSize = 13
    
    /// Command type
    public let type: Libre3ControlCommandType
    
    /// Starting lifeCount for data requests
    public let fromLifeCount: UInt32
    
    /// Sequence number (appended to command)
    public let sequenceNumber: UInt16
    
    /// Build command for historical data request
    /// - Parameters:
    ///   - fromLifeCount: Request data starting from this lifeCount
    ///   - sequence: Command sequence number (starts at 1)
    public static func historic(from fromLifeCount: UInt32, sequence: UInt16 = 1) -> Libre3ControlCommand {
        Libre3ControlCommand(type: .historic, fromLifeCount: fromLifeCount, sequenceNumber: sequence)
    }
    
    /// Build command for clinical data backfill
    /// - Parameters:
    ///   - fromLifeCount: Request data starting from this lifeCount
    ///   - sequence: Command sequence number
    public static func backfill(from fromLifeCount: UInt32, sequence: UInt16 = 1) -> Libre3ControlCommand {
        Libre3ControlCommand(type: .backfill, fromLifeCount: fromLifeCount, sequenceNumber: sequence)
    }
    
    /// Build command for event log request
    /// - Parameter sequence: Command sequence number
    public static func eventLog(sequence: UInt16 = 1) -> Libre3ControlCommand {
        Libre3ControlCommand(type: .eventLog, fromLifeCount: 0, sequenceNumber: sequence)
    }
    
    /// Build command for factory data request
    /// - Parameter sequence: Command sequence number
    public static func factoryData(sequence: UInt16 = 1) -> Libre3ControlCommand {
        Libre3ControlCommand(type: .factoryData, fromLifeCount: 0, sequenceNumber: sequence)
    }
    
    /// Build command to shutdown sensor
    /// - Parameter sequence: Command sequence number
    public static func shutdown(sequence: UInt16 = 1) -> Libre3ControlCommand {
        Libre3ControlCommand(type: .shutdown, fromLifeCount: 0, sequenceNumber: sequence)
    }
    
    /// Build the 13-byte command data for BLE transmission
    /// Format: [opcode(3)][lifeCount(4)][padding(4)][sequence(2)]
    public func build() -> Data {
        var data = Data(count: Self.dataSize)
        
        // Bytes 0-2: Opcode based on type
        switch type {
        case .historic:
            data[0] = 0x01; data[1] = 0x00; data[2] = 0x01  // 010001
        case .backfill:
            data[0] = 0x01; data[1] = 0x01; data[2] = 0x01  // 010101
        case .eventLog:
            data[0] = 0x04; data[1] = 0x01; data[2] = 0x00  // 040100
        case .factoryData:
            data[0] = 0x06; data[1] = 0x00; data[2] = 0x00  // 060000
        case .shutdown:
            data[0] = 0x05; data[1] = 0x00; data[2] = 0x00  // 050000
        }
        
        // Bytes 3-6: lifeCount (little-endian)
        data[3] = UInt8(fromLifeCount & 0xFF)
        data[4] = UInt8((fromLifeCount >> 8) & 0xFF)
        data[5] = UInt8((fromLifeCount >> 16) & 0xFF)
        data[6] = UInt8((fromLifeCount >> 24) & 0xFF)
        
        // Bytes 7-10: padding (zeros)
        // Already zero from Data(count:)
        
        // Bytes 11-12: sequence number (little-endian)
        data[11] = UInt8(sequenceNumber & 0xFF)
        data[12] = UInt8((sequenceNumber >> 8) & 0xFF)
        
        return data
    }
    
    /// Full initializer
    public init(type: Libre3ControlCommandType, fromLifeCount: UInt32, sequenceNumber: UInt16) {
        self.type = type
        self.fromLifeCount = fromLifeCount
        self.sequenceNumber = sequenceNumber
    }
}

// MARK: - BLE Security Events

/// Security events notified from characteristic 2198
/// These are status responses from the sensor during authentication
/// Matches DiaBLE SecurityEvent enum
public enum Libre3SecurityEvent: UInt8, Sendable {
    case unknown = 0x00
    case certificateAccepted = 0x04
    case challengeLoadDone = 0x08
    case certificateReady = 0x0A
    case ephemeralReady = 0x0F
    
    public var description: String {
        switch self {
        case .unknown: return "unknown"
        case .certificateAccepted: return "certificate accepted"
        case .challengeLoadDone: return "challenge load done"
        case .certificateReady: return "certificate ready"
        case .ephemeralReady: return "ephemeral ready"
        }
    }
}

// MARK: - BLE Connection State Machine

/// Authentication phases during BLE connection/activation
public enum Libre3AuthPhase: String, Sendable, CaseIterable {
    // Activation-only phases (first pairing)
    case sendingCertificate         // Write 162-byte certificate to 23FA
    case receivingPatchCertificate  // Receive 140-byte patch certificate
    case sendingEphemeral           // Write 65-byte ephemeral key
    case receivingPatchEphemeral    // Receive 65-byte ephemeral key
    
    // Connection phases (activation and reconnection)
    case sendingChallenge           // Write 0x11, receive 23-byte challenge
    case sendingResponse            // Write 40-byte challenge response
    case receivingKAuth             // Receive 67-byte encrypted KAuth
    
    public var description: String {
        switch self {
        case .sendingCertificate: return "Sending app certificate"
        case .receivingPatchCertificate: return "Receiving patch certificate"
        case .sendingEphemeral: return "Sending ephemeral key"
        case .receivingPatchEphemeral: return "Receiving patch ephemeral key"
        case .sendingChallenge: return "Sending challenge request"
        case .sendingResponse: return "Sending challenge response"
        case .receivingKAuth: return "Receiving KAuth"
        }
    }
}

/// Error conditions during BLE authentication
public enum Libre3AuthError: Sendable, Equatable {
    case bluetoothUnavailable
    case deviceNotFound
    case connectionFailed
    case authenticationFailed(reason: String)
    case cryptoError(String)
    case timeout
    case invalidResponse(expected: Int, received: Int)
    case patchError(patchState: UInt8)
    
    public var description: String {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable"
        case .deviceNotFound:
            return "Libre 3 sensor not found"
        case .connectionFailed:
            return "Connection failed"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .cryptoError(let msg):
            return "Crypto error: \(msg)"
        case .timeout:
            return "Connection timed out"
        case .invalidResponse(let expected, let received):
            return "Invalid response: expected \(expected) bytes, received \(received)"
        case .patchError(let state):
            return "Patch error state: \(state)"
        }
    }
}

/// BLE authentication state machine for Libre 3 sensor
/// Models the detailed authentication flow from DiaBLE
/// Note: Libre3ConnectionState (high-level) exists in Libre3Manager.swift
public enum Libre3BLEAuthState: Sendable, Equatable {
    /// Initial state - not connected
    case disconnected
    
    /// BLE connection established, enabling security notifications (2198, 23FA, 22CE)
    case connecting
    
    /// In authentication/activation process
    case authenticating(phase: Libre3AuthPhase)
    
    /// KAuth received, session keys derived (kEnc, ivEnc)
    case authenticated
    
    /// Enabling data notifications (1338, 1BEE, 195A, 1AB8, 1D24, 1482, 177A)
    case subscribing
    
    /// Fully connected and receiving glucose data
    case ready
    
    /// Error state - requires reconnection
    case error(Libre3AuthError)
    
    // MARK: - State Properties
    
    /// Whether the state machine is in a connected state
    public var isConnected: Bool {
        switch self {
        case .disconnected, .error:
            return false
        case .connecting, .authenticating, .authenticated, .subscribing, .ready:
            return true
        }
    }
    
    /// Whether we can receive glucose data in this state
    public var canReceiveGlucose: Bool {
        self == .ready
    }
    
    /// Whether we can send commands in this state
    public var canSendCommands: Bool {
        switch self {
        case .authenticated, .subscribing, .ready:
            return true
        default:
            return false
        }
    }
    
    // MARK: - State Transitions
    
    /// Valid next states from current state
    public var validNextStates: [Libre3BLEAuthState] {
        switch self {
        case .disconnected:
            return [.connecting]
            
        case .connecting:
            return [
                .authenticating(phase: .sendingCertificate),  // activation
                .authenticating(phase: .sendingChallenge),    // reconnection
                .error(.connectionFailed),
                .disconnected
            ]
            
        case .authenticating(let phase):
            return nextStatesFromAuth(phase: phase)
            
        case .authenticated:
            return [.subscribing, .error(.timeout), .disconnected]
            
        case .subscribing:
            return [.ready, .error(.timeout), .disconnected]
            
        case .ready:
            return [.disconnected, .error(.connectionFailed)]
            
        case .error:
            return [.disconnected, .connecting]
        }
    }
    
    private func nextStatesFromAuth(phase: Libre3AuthPhase) -> [Libre3BLEAuthState] {
        switch phase {
        case .sendingCertificate:
            return [
                .authenticating(phase: .receivingPatchCertificate),
                .error(.authenticationFailed(reason: "certificate rejected")),
                .disconnected
            ]
        case .receivingPatchCertificate:
            return [
                .authenticating(phase: .sendingEphemeral),
                .error(.authenticationFailed(reason: "invalid patch certificate")),
                .disconnected
            ]
        case .sendingEphemeral:
            return [
                .authenticating(phase: .receivingPatchEphemeral),
                .error(.authenticationFailed(reason: "ephemeral rejected")),
                .disconnected
            ]
        case .receivingPatchEphemeral:
            return [
                .authenticating(phase: .sendingChallenge),
                .error(.authenticationFailed(reason: "invalid patch ephemeral")),
                .disconnected
            ]
        case .sendingChallenge:
            return [
                .authenticating(phase: .sendingResponse),
                .error(.authenticationFailed(reason: "challenge failed")),
                .disconnected
            ]
        case .sendingResponse:
            return [
                .authenticating(phase: .receivingKAuth),
                .error(.authenticationFailed(reason: "response rejected")),
                .disconnected
            ]
        case .receivingKAuth:
            return [
                .authenticated,
                .error(.authenticationFailed(reason: "kAuth decryption failed")),
                .disconnected
            ]
        }
    }
    
    // MARK: - Connection Flow Helpers
    
    /// First auth phase for reconnection (already paired)
    public static var reconnectionStartPhase: Libre3AuthPhase {
        .sendingChallenge
    }
    
    /// First auth phase for activation (new pairing)
    public static var activationStartPhase: Libre3AuthPhase {
        .sendingCertificate
    }
}
