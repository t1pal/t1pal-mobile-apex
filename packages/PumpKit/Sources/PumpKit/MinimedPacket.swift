// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MinimedPacket.swift
// PumpKit
//
// 4b6b encoding/decoding and CRC for Medtronic RF packets.
// Ported from Loop's MinimedKit/Radio/ (LoopKit Authors).
// Trace: RL-PROTO-001
//
// Usage:
//   let packet = MinimedPacket(outgoingData: data)
//   let encoded = packet.encodedData()  // Send this over RF
//   let decoded = MinimedPacket(encodedData: received)  // Parse response

import Foundation

// MARK: - 4b6b Encoding Lookup Tables

/// 4b6b encoding lookup (nibble → 6-bit code)
/// Each 4-bit nibble maps to a 6-bit code with guaranteed transitions
private let encode4b6bTable: [Int] = [
    21, 49, 50, 35, 52, 37, 38, 22, 26, 25, 42, 11, 44, 13, 14, 28
]

/// 4b6b decoding lookup (6-bit code → nibble)
private let decode4b6bTable: [Int: UInt8] = Dictionary(
    uniqueKeysWithValues: encode4b6bTable.enumerated().map { ($1, UInt8($0)) }
)

// MARK: - CRC8 Lookup Table

/// CRC-8/MAXIM lookup table for fast CRC calculation
/// Polynomial: 0x31, init: 0x00, refIn/refOut: true
private let crc8Table: [UInt8] = [
    0x00, 0x9B, 0xAD, 0x36, 0xC1, 0x5A, 0x6C, 0xF7,
    0x19, 0x82, 0xB4, 0x2F, 0xD8, 0x43, 0x75, 0xEE,
    0x32, 0xA9, 0x9F, 0x04, 0xF3, 0x68, 0x5E, 0xC5,
    0x2B, 0xB0, 0x86, 0x1D, 0xEA, 0x71, 0x47, 0xDC,
    0x64, 0xFF, 0xC9, 0x52, 0xA5, 0x3E, 0x08, 0x93,
    0x7D, 0xE6, 0xD0, 0x4B, 0xBC, 0x27, 0x11, 0x8A,
    0x56, 0xCD, 0xFB, 0x60, 0x97, 0x0C, 0x3A, 0xA1,
    0x4F, 0xD4, 0xE2, 0x79, 0x8E, 0x15, 0x23, 0xB8,
    0xC8, 0x53, 0x65, 0xFE, 0x09, 0x92, 0xA4, 0x3F,
    0xD1, 0x4A, 0x7C, 0xE7, 0x10, 0x8B, 0xBD, 0x26,
    0xFA, 0x61, 0x57, 0xCC, 0x3B, 0xA0, 0x96, 0x0D,
    0xE3, 0x78, 0x4E, 0xD5, 0x22, 0xB9, 0x8F, 0x14,
    0xAC, 0x37, 0x01, 0x9A, 0x6D, 0xF6, 0xC0, 0x5B,
    0xB5, 0x2E, 0x18, 0x83, 0x74, 0xEF, 0xD9, 0x42,
    0x9E, 0x05, 0x33, 0xA8, 0x5F, 0xC4, 0xF2, 0x69,
    0x87, 0x1C, 0x2A, 0xB1, 0x46, 0xDD, 0xEB, 0x70,
    0x0B, 0x90, 0xA6, 0x3D, 0xCA, 0x51, 0x67, 0xFC,
    0x12, 0x89, 0xBF, 0x24, 0xD3, 0x48, 0x7E, 0xE5,
    0x39, 0xA2, 0x94, 0x0F, 0xF8, 0x63, 0x55, 0xCE,
    0x20, 0xBB, 0x8D, 0x16, 0xE1, 0x7A, 0x4C, 0xD7,
    0x6F, 0xF4, 0xC2, 0x59, 0xAE, 0x35, 0x03, 0x98,
    0x76, 0xED, 0xDB, 0x40, 0xB7, 0x2C, 0x1A, 0x81,
    0x5D, 0xC6, 0xF0, 0x6B, 0x9C, 0x07, 0x31, 0xAA,
    0x44, 0xDF, 0xE9, 0x72, 0x85, 0x1E, 0x28, 0xB3,
    0xC3, 0x58, 0x6E, 0xF5, 0x02, 0x99, 0xAF, 0x34,
    0xDA, 0x41, 0x77, 0xEC, 0x1B, 0x80, 0xB6, 0x2D,
    0xF1, 0x6A, 0x5C, 0xC7, 0x30, 0xAB, 0x9D, 0x06,
    0xE8, 0x73, 0x45, 0xDE, 0x29, 0xB2, 0x84, 0x1F,
    0xA7, 0x3C, 0x0A, 0x91, 0x66, 0xFD, 0xCB, 0x50,
    0xBE, 0x25, 0x13, 0x88, 0x7F, 0xE4, 0xD2, 0x49,
    0x95, 0x0E, 0x38, 0xA3, 0x54, 0xCF, 0xF9, 0x62,
    0x8C, 0x17, 0x21, 0xBA, 0x4D, 0xD6, 0xE0, 0x7B
]

// MARK: - Sequence Extensions

public extension Sequence where Element == UInt8 {
    /// Decode 4b6b encoded data back to raw bytes
    /// Returns nil if decoding fails (invalid 6-bit codes)
    func decode4b6b() -> [UInt8]? {
        var buffer = [UInt8]()
        var availBits = 0
        var bitAccumulator = 0
        
        for byte in self {
            // Zero byte marks end of packet
            if byte == 0 {
                break
            }
            
            bitAccumulator = (bitAccumulator << 8) + Int(byte)
            availBits += 8
            
            // Extract two nibbles when we have 12+ bits
            if availBits >= 12 {
                guard let hiNibble = decode4b6bTable[bitAccumulator >> (availBits - 6)],
                      let loNibble = decode4b6bTable[(bitAccumulator >> (availBits - 12)) & 0b111111]
                else {
                    return nil  // Invalid 6-bit code
                }
                let decoded = UInt8((hiNibble << 4) + loNibble)
                buffer.append(decoded)
                availBits -= 12
                bitAccumulator = bitAccumulator & (0xFFFF >> (16 - availBits))
            }
        }
        
        return buffer
    }
    
    /// Encode raw bytes using 4b6b encoding
    /// Each byte becomes 12 bits (two 6-bit codes)
    func encode4b6b() -> [UInt8] {
        var buffer = [UInt8]()
        var bitAccumulator = 0
        var bitcount = 0
        
        for byte in self {
            // Encode high nibble
            bitAccumulator <<= 6
            bitAccumulator |= encode4b6bTable[Int(byte >> 4)]
            bitcount += 6
            
            // Encode low nibble
            bitAccumulator <<= 6
            bitAccumulator |= encode4b6bTable[Int(byte & 0x0F)]
            bitcount += 6
            
            // Extract complete bytes
            while bitcount >= 8 {
                buffer.append(UInt8(bitAccumulator >> (bitcount - 8)) & 0xFF)
                bitcount -= 8
                bitAccumulator &= (0xFFFF >> (16 - bitcount))
            }
        }
        
        // Flush remaining bits (left-padded with zeros)
        if bitcount > 0 {
            bitAccumulator <<= (8 - bitcount)
            buffer.append(UInt8(bitAccumulator) & 0xFF)
        }
        
        return buffer
    }
    
    /// Calculate CRC-8/MAXIM checksum using lookup table
    func crc8() -> UInt8 {
        var crc: UInt8 = 0
        for byte in self {
            crc = crc8Table[Int((crc ^ byte) & 0xFF)]
        }
        return crc
    }
}

// MARK: - MinimedPacket

/// Medtronic RF packet with 4b6b encoding and CRC
public struct MinimedPacket: Sendable, Equatable {
    /// Raw packet data (without CRC)
    public let data: Data
    
    // MARK: - Init for Outgoing Packets
    
    /// Create packet from raw outgoing data
    public init(outgoingData: Data) {
        self.data = outgoingData
    }
    
    // MARK: - Init for Incoming Packets
    
    /// Decode incoming 4b6b-encoded packet
    /// Returns nil if decoding fails or CRC is invalid
    public init?(encodedData: Data) {
        guard let decoded = encodedData.decode4b6b() else {
            return nil  // Could not decode 4b6b
        }
        
        guard decoded.count >= 2 else {
            return nil  // Too short (need at least 1 byte + CRC)
        }
        
        // Verify CRC (last byte)
        let message = decoded.prefix(upTo: decoded.count - 1)
        let expectedCRC = decoded.last!
        let calculatedCRC = message.crc8()
        
        guard calculatedCRC == expectedCRC else {
            return nil  // CRC mismatch
        }
        
        self.data = Data(message)
    }
    
    // MARK: - Encoding
    
    /// Encode packet for RF transmission
    /// Appends CRC, 4b6b encodes, and adds null terminator
    public func encodedData() -> Data {
        var dataWithCRC = data
        dataWithCRC.append(data.crc8())
        
        var encoded = dataWithCRC.encode4b6b()
        encoded.append(0)  // Null terminator
        
        return Data(encoded)
    }
    
    // MARK: - Packet Fields
    
    /// Pump address from packet (bytes 0-2)
    public var pumpAddress: Data? {
        guard data.count >= 3 else { return nil }
        return data.subdata(in: 0..<3)
    }
    
    /// Message type (byte 3)
    public var messageType: UInt8? {
        guard data.count >= 4 else { return nil }
        return data[3]
    }
    
    /// Message body (bytes 4+)
    public var messageBody: Data? {
        guard data.count > 4 else { return nil }
        return data.subdata(in: 4..<data.count)
    }
}

// MARK: - Debug Description

extension MinimedPacket: CustomStringConvertible {
    public var description: String {
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "MinimedPacket(\(data.count) bytes: \(hex))"
    }
}
