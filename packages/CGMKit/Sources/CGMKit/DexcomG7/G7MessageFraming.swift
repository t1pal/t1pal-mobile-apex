// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7MessageFraming.swift
// CGMKit - DexcomG7
//
// J-PAKE message framing and BLE chunking.
// Extracted from G7ECOperations.swift (CODE-020)
//
// Trace: JPAKE-MSG-001

import Foundation

// MARK: - Message Framing (JPAKE-MSG-001)

/// J-PAKE message framing variants for BLE packet serialization
/// Reference: xDrip Packet.java - 160 bytes per round packet
/// Format: Point1 (64) + Point2 (64) + Hash (32) = 160 bytes
public enum MessageFraming: String, CaseIterable, Sendable {
    /// xDrip format: uncompressed points (X||Y), no length prefix
    /// Total: 160 bytes = 2×(32+32) + 32
    case xdripUncompressed = "xdrip_uncompressed"
    
    /// Compressed points (33 bytes each), no length prefix
    /// Total: 98 bytes = 2×33 + 32
    case compressed = "compressed"
    
    /// Uncompressed with 2-byte length prefix (big-endian)
    /// Total: 162 bytes
    case lengthPrefixed = "length_prefixed"
    
    /// Compressed with 1-byte length prefix
    /// Total: 99 bytes
    case compressedLengthPrefixed = "compressed_length_prefixed"
    
    /// SEC1 uncompressed format (0x04 prefix per point)
    /// Total: 162 bytes = 2×65 + 32
    case sec1Uncompressed = "sec1_uncompressed"
    
    /// SEC1 compressed format (0x02/0x03 prefix per point)
    /// Total: 98 bytes = 2×33 + 32
    case sec1Compressed = "sec1_compressed"
    
    // MARK: - Constants
    
    /// Field size in bytes (P-256)
    public static let fieldSize = 32
    
    /// Uncompressed point size (X + Y)
    public static let uncompressedPointSize = 64
    
    /// Compressed point size (prefix + X)
    public static let compressedPointSize = 33
    
    /// SEC1 uncompressed point size (0x04 + X + Y)
    public static let sec1UncompressedPointSize = 65
    
    /// xDrip packet size
    public static let xdripPacketSize = 160
    
    // MARK: - Serialization
    
    /// Serialize a J-PAKE round packet
    /// - Parameters:
    ///   - point1: First EC point (public key or generator product)
    ///   - point2: Second EC point (ZKP commitment or second public key)
    ///   - hash: 32-byte hash/scalar (ZKP challenge or proof)
    /// - Returns: Serialized packet data
    public func serialize(point1: Data, point2: Data, hash: Data) -> Data {
        switch self {
        case .xdripUncompressed:
            return serializeXDripUncompressed(point1: point1, point2: point2, hash: hash)
        case .compressed:
            return serializeCompressed(point1: point1, point2: point2, hash: hash)
        case .lengthPrefixed:
            return serializeLengthPrefixed(point1: point1, point2: point2, hash: hash)
        case .compressedLengthPrefixed:
            return serializeCompressedLengthPrefixed(point1: point1, point2: point2, hash: hash)
        case .sec1Uncompressed:
            return serializeSEC1Uncompressed(point1: point1, point2: point2, hash: hash)
        case .sec1Compressed:
            return serializeSEC1Compressed(point1: point1, point2: point2, hash: hash)
        }
    }
    
    /// Parse a J-PAKE round packet
    /// - Parameter data: Serialized packet data
    /// - Returns: Tuple of (point1, point2, hash) or nil if invalid
    public func parse(_ data: Data) -> (point1: Data, point2: Data, hash: Data)? {
        switch self {
        case .xdripUncompressed:
            return parseXDripUncompressed(data)
        case .compressed:
            return parseCompressed(data)
        case .lengthPrefixed:
            return parseLengthPrefixed(data)
        case .compressedLengthPrefixed:
            return parseCompressedLengthPrefixed(data)
        case .sec1Uncompressed:
            return parseSEC1Uncompressed(data)
        case .sec1Compressed:
            return parseSEC1Compressed(data)
        }
    }
    
    /// Expected packet size for this framing format
    public var packetSize: Int {
        switch self {
        case .xdripUncompressed:
            return 160  // 2×64 + 32
        case .compressed:
            return 98   // 2×33 + 32
        case .lengthPrefixed:
            return 162  // 2 + 2×64 + 32
        case .compressedLengthPrefixed:
            return 99   // 1 + 2×33 + 32
        case .sec1Uncompressed:
            return 162  // 2×65 + 32
        case .sec1Compressed:
            return 98   // 2×33 + 32
        }
    }
    
    // MARK: - Serialization Implementations
    
    /// xDrip format: X1||Y1||X2||Y2||Hash (160 bytes)
    private func serializeXDripUncompressed(point1: Data, point2: Data, hash: Data) -> Data {
        var packet = Data()
        // Point1: ensure 64 bytes (X + Y)
        packet.append(padOrTruncate(point1, to: 64))
        // Point2: ensure 64 bytes
        packet.append(padOrTruncate(point2, to: 64))
        // Hash: 32 bytes
        packet.append(padOrTruncate(hash, to: 32))
        return packet
    }
    
    /// Compressed points format (98 bytes)
    private func serializeCompressed(point1: Data, point2: Data, hash: Data) -> Data {
        var packet = Data()
        // Point1: compress to 33 bytes if needed
        packet.append(compressPoint(point1))
        // Point2: compress to 33 bytes
        packet.append(compressPoint(point2))
        // Hash: 32 bytes
        packet.append(padOrTruncate(hash, to: 32))
        return packet
    }
    
    /// Length-prefixed uncompressed (162 bytes)
    private func serializeLengthPrefixed(point1: Data, point2: Data, hash: Data) -> Data {
        let payload = serializeXDripUncompressed(point1: point1, point2: point2, hash: hash)
        var packet = Data()
        // 2-byte big-endian length
        let length = UInt16(payload.count)
        packet.append(UInt8(length >> 8))
        packet.append(UInt8(length & 0xFF))
        packet.append(payload)
        return packet
    }
    
    /// Compressed with 1-byte length prefix (99 bytes)
    private func serializeCompressedLengthPrefixed(point1: Data, point2: Data, hash: Data) -> Data {
        let payload = serializeCompressed(point1: point1, point2: point2, hash: hash)
        var packet = Data()
        packet.append(UInt8(payload.count))
        packet.append(payload)
        return packet
    }
    
    /// SEC1 uncompressed: 0x04||X||Y for each point (162 bytes)
    private func serializeSEC1Uncompressed(point1: Data, point2: Data, hash: Data) -> Data {
        var packet = Data()
        // Point1: 0x04 prefix + X + Y = 65 bytes
        packet.append(toSEC1Uncompressed(point1))
        // Point2: 65 bytes
        packet.append(toSEC1Uncompressed(point2))
        // Hash: 32 bytes
        packet.append(padOrTruncate(hash, to: 32))
        return packet
    }
    
    /// SEC1 compressed: 0x02/0x03||X for each point (98 bytes)
    private func serializeSEC1Compressed(point1: Data, point2: Data, hash: Data) -> Data {
        var packet = Data()
        // Point1: 0x02/0x03 prefix + X = 33 bytes
        packet.append(toSEC1Compressed(point1))
        // Point2: 33 bytes
        packet.append(toSEC1Compressed(point2))
        // Hash: 32 bytes
        packet.append(padOrTruncate(hash, to: 32))
        return packet
    }
    
    // MARK: - Parsing Implementations
    
    private func parseXDripUncompressed(_ data: Data) -> (point1: Data, point2: Data, hash: Data)? {
        guard data.count >= 160 else { return nil }
        let point1 = Data(data[0..<64])
        let point2 = Data(data[64..<128])
        let hash = Data(data[128..<160])
        return (point1, point2, hash)
    }
    
    private func parseCompressed(_ data: Data) -> (point1: Data, point2: Data, hash: Data)? {
        guard data.count >= 98 else { return nil }
        let point1 = Data(data[0..<33])
        let point2 = Data(data[33..<66])
        let hash = Data(data[66..<98])
        return (point1, point2, hash)
    }
    
    private func parseLengthPrefixed(_ data: Data) -> (point1: Data, point2: Data, hash: Data)? {
        guard data.count >= 162 else { return nil }
        // Skip 2-byte length prefix
        return parseXDripUncompressed(Data(data[2...]))
    }
    
    private func parseCompressedLengthPrefixed(_ data: Data) -> (point1: Data, point2: Data, hash: Data)? {
        guard data.count >= 99 else { return nil }
        // Skip 1-byte length prefix
        return parseCompressed(Data(data[1...]))
    }
    
    private func parseSEC1Uncompressed(_ data: Data) -> (point1: Data, point2: Data, hash: Data)? {
        guard data.count >= 162 else { return nil }
        // Each point is 65 bytes (0x04 + X + Y)
        let point1 = Data(data[0..<65])
        let point2 = Data(data[65..<130])
        let hash = Data(data[130..<162])
        return (point1, point2, hash)
    }
    
    private func parseSEC1Compressed(_ data: Data) -> (point1: Data, point2: Data, hash: Data)? {
        guard data.count >= 98 else { return nil }
        let point1 = Data(data[0..<33])
        let point2 = Data(data[33..<66])
        let hash = Data(data[66..<98])
        return (point1, point2, hash)
    }
    
    // MARK: - Helper Methods
    
    /// Pad or truncate data to exact size
    private func padOrTruncate(_ data: Data, to size: Int) -> Data {
        if data.count >= size {
            return Data(data.prefix(size))
        }
        // Pad with leading zeros (big-endian)
        var padded = Data(repeating: 0, count: size - data.count)
        padded.append(data)
        return padded
    }
    
    /// Compress an EC point (assumes uncompressed X||Y format)
    private func compressPoint(_ point: Data) -> Data {
        if point.count == 33 {
            // Already compressed
            return point
        }
        if point.count == 65 && point[0] == 0x04 {
            // SEC1 uncompressed: 0x04 + X + Y → 0x02/0x03 + X
            let x = Data(point[1..<33])
            let yLsb = point[64] & 0x01
            var compressed = Data([yLsb == 0 ? 0x02 : 0x03])
            compressed.append(x)
            return compressed
        }
        if point.count >= 64 {
            // Raw X||Y format
            let x = Data(point[0..<32])
            let yLsb = point[63] & 0x01
            var compressed = Data([yLsb == 0 ? 0x02 : 0x03])
            compressed.append(x)
            return compressed
        }
        // Can't compress, return as-is padded
        return padOrTruncate(point, to: 33)
    }
    
    /// Convert to SEC1 uncompressed format (0x04 + X + Y)
    private func toSEC1Uncompressed(_ point: Data) -> Data {
        if point.count == 65 && point[0] == 0x04 {
            return point
        }
        if point.count >= 64 {
            var sec1 = Data([0x04])
            sec1.append(padOrTruncate(point, to: 64))
            return sec1
        }
        // Pad to 65 bytes
        var sec1 = Data([0x04])
        sec1.append(padOrTruncate(point, to: 64))
        return sec1
    }
    
    /// Convert to SEC1 compressed format (0x02/0x03 + X)
    private func toSEC1Compressed(_ point: Data) -> Data {
        return compressPoint(point)
    }
}

// MARK: - BLE Chunking (JPAKE-MSG-001)

/// BLE MTU-aware message chunking for J-PAKE packets
public enum BLEChunking: Sendable {
    
    /// Default BLE MTU (ATT_MTU - 3 for GATT header)
    public static let defaultMTU = 20
    
    /// Maximum iOS BLE MTU
    public static let maxMTU = 512
    
    /// Chunk a message for BLE transmission
    /// - Parameters:
    ///   - data: Data to chunk
    ///   - mtu: Maximum transmission unit
    ///   - includeSequence: Whether to include sequence numbers
    /// - Returns: Array of chunks
    public static func chunk(_ data: Data, mtu: Int = defaultMTU, includeSequence: Bool = false) -> [Data] {
        let effectiveMTU = includeSequence ? mtu - 1 : mtu
        guard effectiveMTU > 0 else { return [data] }
        
        var chunks: [Data] = []
        var offset = 0
        var sequence: UInt8 = 0
        
        while offset < data.count {
            let end = min(offset + effectiveMTU, data.count)
            var chunk = Data()
            
            if includeSequence {
                chunk.append(sequence)
                sequence = sequence &+ 1
            }
            
            chunk.append(data[offset..<end])
            chunks.append(chunk)
            offset = end
        }
        
        return chunks
    }
    
    /// Reassemble chunks into original message
    /// - Parameters:
    ///   - chunks: Array of chunks
    ///   - hasSequence: Whether chunks have sequence numbers
    /// - Returns: Reassembled data
    public static func reassemble(_ chunks: [Data], hasSequence: Bool = false) -> Data {
        var result = Data()
        
        let sortedChunks: [Data]
        if hasSequence {
            // Sort by sequence number
            sortedChunks = chunks.sorted { 
                guard let a = $0.first, let b = $1.first else { return false }
                return a < b
            }
        } else {
            sortedChunks = chunks
        }
        
        for chunk in sortedChunks {
            if hasSequence && !chunk.isEmpty {
                result.append(chunk.dropFirst())
            } else {
                result.append(chunk)
            }
        }
        
        return result
    }
    
    /// Calculate number of chunks needed for data
    public static func chunksNeeded(for dataSize: Int, mtu: Int = defaultMTU, includeSequence: Bool = false) -> Int {
        let effectiveMTU = includeSequence ? mtu - 1 : mtu
        guard effectiveMTU > 0 else { return 1 }
        return (dataSize + effectiveMTU - 1) / effectiveMTU
    }
}

