// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Libre2Crypto.swift
// CGMKit
//
// Libre 2 encryption/decryption for BLE and FRAM data.
// Ported from LibreTransmitter (LoopKit).
// Trace: PRD-004 REQ-CGM-002 CGM-020

import Foundation

// MARK: - Libre2Crypto

/// Libre 2 encryption and decryption utilities.
/// Uses XOR-based stream cipher with sensor UID as key seed.
public enum Libre2Crypto {
    
    // MARK: - Key Constants
    
    /// Crypto key constants used in processCrypto
    static let key: [UInt16] = [0xA0C5, 0x6860, 0x0000, 0x14C6]
    
    // MARK: - BLE Decryption
    
    /// Decrypts Libre 2 BLE notification payload
    /// - Parameters:
    ///   - sensorUID: 8-byte sensor UID from NFC
    ///   - data: Encrypted BLE notification data (46 bytes)
    /// - Returns: Decrypted data
    /// - Throws: `Libre2CryptoError.crcMismatch` if decryption failed
    public static func decryptBLE(sensorUID: [UInt8], data: [UInt8]) throws -> [UInt8] {
        guard sensorUID.count >= 6 else {
            throw Libre2CryptoError.invalidSensorUID
        }
        guard data.count >= 4 else {
            throw Libre2CryptoError.dataTooShort
        }
        
        let d = usefulFunction(id: sensorUID, x: 0x1b, y: 0x1b6a)
        let x = UInt16(d[1], d[0]) ^ UInt16(d[3], d[2]) | 0x63
        let y = UInt16(data[1], data[0]) ^ 0x63
        
        var keyStream = [UInt8]()
        var initialKey = processCrypto(input: prepareVariables(id: sensorUID, x: x, y: y))
        
        for _ in 0..<8 {
            keyStream.append(UInt8(truncatingIfNeeded: initialKey[0]))
            keyStream.append(UInt8(truncatingIfNeeded: initialKey[0] >> 8))
            keyStream.append(UInt8(truncatingIfNeeded: initialKey[1]))
            keyStream.append(UInt8(truncatingIfNeeded: initialKey[1] >> 8))
            keyStream.append(UInt8(truncatingIfNeeded: initialKey[2]))
            keyStream.append(UInt8(truncatingIfNeeded: initialKey[2] >> 8))
            keyStream.append(UInt8(truncatingIfNeeded: initialKey[3]))
            keyStream.append(UInt8(truncatingIfNeeded: initialKey[3] >> 8))
            initialKey = processCrypto(input: initialKey)
        }
        
        let result = data[2...].enumerated().map { i, value in
            value ^ keyStream[i]
        }
        
        guard CRC16.hasValidCrc16InLastTwoBytes(Array(result)) else {
            throw Libre2CryptoError.crcMismatch
        }
        
        return Array(result)
    }
    
    // MARK: - FRAM Decryption
    
    /// Sensor type for FRAM decryption
    public enum SensorType {
        case libre2
        case libreUS14day
    }
    
    /// Decrypts 43 blocks of Libre 2 FRAM data
    /// - Parameters:
    ///   - type: Sensor type (.libre2 or .libreUS14day)
    ///   - sensorUID: 8-byte sensor UID from NFC
    ///   - patchInfo: 6-byte patch info from NFC command 0xa1
    ///   - data: Encrypted FRAM data (344 bytes = 43 blocks × 8 bytes)
    /// - Returns: Decrypted FRAM data
    public static func decryptFRAM(
        type: SensorType,
        sensorUID: [UInt8],
        patchInfo: Data,
        data: [UInt8]
    ) throws -> [UInt8] {
        guard sensorUID.count >= 6 else {
            throw Libre2CryptoError.invalidSensorUID
        }
        guard patchInfo.count >= 6 else {
            throw Libre2CryptoError.invalidPatchInfo
        }
        guard data.count >= 344 else {
            throw Libre2CryptoError.dataTooShort
        }
        
        func getArg(block: Int) -> UInt16 {
            switch type {
            case .libreUS14day:
                if block < 3 || block >= 40 {
                    return 0xcadc
                }
                return UInt16(patchInfo[5], patchInfo[4])
            case .libre2:
                return UInt16(patchInfo[5], patchInfo[4]) ^ 0x44
            }
        }
        
        var result = [UInt8]()
        
        for i in 0..<43 {
            let input = prepareVariables(id: sensorUID, x: UInt16(i), y: getArg(block: i))
            let blockKey = processCrypto(input: input)
            
            result.append(data[i * 8 + 0] ^ UInt8(truncatingIfNeeded: blockKey[0]))
            result.append(data[i * 8 + 1] ^ UInt8(truncatingIfNeeded: blockKey[0] >> 8))
            result.append(data[i * 8 + 2] ^ UInt8(truncatingIfNeeded: blockKey[1]))
            result.append(data[i * 8 + 3] ^ UInt8(truncatingIfNeeded: blockKey[1] >> 8))
            result.append(data[i * 8 + 4] ^ UInt8(truncatingIfNeeded: blockKey[2]))
            result.append(data[i * 8 + 5] ^ UInt8(truncatingIfNeeded: blockKey[2] >> 8))
            result.append(data[i * 8 + 6] ^ UInt8(truncatingIfNeeded: blockKey[3]))
            result.append(data[i * 8 + 7] ^ UInt8(truncatingIfNeeded: blockKey[3] >> 8))
        }
        
        return result
    }
    
    // MARK: - Streaming Unlock Payload
    
    /// Generates the unlock payload for BLE streaming
    /// - Parameters:
    ///   - sensorUID: 8-byte sensor UID from NFC
    ///   - patchInfo: 6-byte patch info from NFC command 0xa1
    ///   - enableTime: Timestamp when sensor was enabled
    ///   - unlockCount: Counter for unlock attempts
    /// - Returns: 12-byte unlock payload to write to F001 characteristic
    public static func streamingUnlockPayload(
        sensorUID: Data,
        patchInfo: Data,
        enableTime: UInt32,
        unlockCount: UInt16
    ) -> [UInt8] {
        let time = enableTime + UInt32(unlockCount)
        let b: [UInt8] = [
            UInt8(time & 0xFF),
            UInt8((time >> 8) & 0xFF),
            UInt8((time >> 16) & 0xFF),
            UInt8((time >> 24) & 0xFF)
        ]
        
        let ad = usefulFunction(sensorUID: sensorUID, x: 0x1b, y: 0x1b6a)
        let ed = usefulFunction(
            sensorUID: sensorUID,
            x: 0x1e,
            y: UInt16(enableTime & 0xFFFF) ^ UInt16(patchInfo[5], patchInfo[4])
        )
        
        let t11 = UInt16(ed[1], ed[0]) ^ UInt16(b[3], b[2])
        let t12 = UInt16(ad[1], ad[0])
        let t13 = UInt16(ed[3], ed[2]) ^ UInt16(b[1], b[0])
        let t14 = UInt16(ad[3], ad[2])
        
        let t2 = processCrypto(input: prepareVariables(
            sensorUID: sensorUID,
            i1: t11, i2: t12, i3: t13, i4: t14
        ))
        
        let t31 = CRC16.crc16(Data([
            0xc1, 0xc4, 0xc3, 0xc0, 0xd4, 0xe1, 0xe7, 0xba,
            UInt8(t2[0] & 0xFF), UInt8((t2[0] >> 8) & 0xFF)
        ])).byteSwapped
        let t32 = CRC16.crc16(Data([
            UInt8(t2[1] & 0xFF), UInt8((t2[1] >> 8) & 0xFF),
            UInt8(t2[2] & 0xFF), UInt8((t2[2] >> 8) & 0xFF),
            UInt8(t2[3] & 0xFF), UInt8((t2[3] >> 8) & 0xFF)
        ])).byteSwapped
        let t33 = CRC16.crc16(Data([ad[0], ad[1], ad[2], ad[3], ed[0], ed[1]])).byteSwapped
        let t34 = CRC16.crc16(Data([ed[2], ed[3], b[0], b[1], b[2], b[3]])).byteSwapped
        
        let t4 = processCrypto(input: prepareVariables(
            sensorUID: sensorUID,
            i1: t31, i2: t32, i3: t33, i4: t34
        ))
        
        let res = [
            UInt8(t4[0] & 0xFF), UInt8((t4[0] >> 8) & 0xFF),
            UInt8(t4[1] & 0xFF), UInt8((t4[1] >> 8) & 0xFF),
            UInt8(t4[2] & 0xFF), UInt8((t4[2] >> 8) & 0xFF),
            UInt8(t4[3] & 0xFF), UInt8((t4[3] >> 8) & 0xFF)
        ]
        
        return [b[0], b[1], b[2], b[3], res[0], res[1], res[2], res[3], res[4], res[5], res[6], res[7]]
    }
    
    /// Generates activation parameters for sensor
    /// - Parameter sensorUID: 8-byte sensor UID
    /// - Returns: 5-byte activation command
    public static func activateParameters(sensorUID: [UInt8]) -> Data {
        let d = usefulFunction(id: sensorUID, x: 0x1b, y: 0x1b6a)
        return Data([0x1b, d[0], d[1], d[2], d[3]])
    }
    
    // MARK: - Core Crypto Functions
    
    /// Core crypto processing function
    static func processCrypto(input: [UInt16]) -> [UInt16] {
        func op(_ value: UInt16) -> UInt16 {
            var res = value >> 2
            if value & 1 != 0 {
                res = res ^ key[1]
            }
            if value & 2 != 0 {
                res = res ^ key[0]
            }
            return res
        }
        
        let r0 = op(input[0]) ^ input[3]
        let r1 = op(r0) ^ input[2]
        let r2 = op(r1) ^ input[1]
        let r3 = op(r2) ^ input[0]
        let r4 = op(r3)
        let r5 = op(r4 ^ r0)
        let r6 = op(r5 ^ r1)
        let r7 = op(r6 ^ r2)
        
        let f1 = r0 ^ r4
        let f2 = r1 ^ r5
        let f3 = r2 ^ r6
        let f4 = r3 ^ r7
        
        return [f4, f3, f2, f1]
    }
    
    /// Prepares variables for crypto from sensor UID and 4 input values
    static func prepareVariables(sensorUID: Data, i1: UInt16, i2: UInt16, i3: UInt16, i4: UInt16) -> [UInt16] {
        let s1 = UInt16(truncatingIfNeeded: UInt(UInt16(sensorUID[5], sensorUID[4])) + UInt(i1))
        let s2 = UInt16(truncatingIfNeeded: UInt(UInt16(sensorUID[3], sensorUID[2])) + UInt(i2))
        let s3 = UInt16(truncatingIfNeeded: UInt(UInt16(sensorUID[1], sensorUID[0])) + UInt(i3) + UInt(key[2]))
        let s4 = UInt16(truncatingIfNeeded: UInt(i4) + UInt(key[3]))
        return [s1, s2, s3, s4]
    }
    
    /// Prepares variables for crypto from id array and x/y values
    static func prepareVariables(id: [UInt8], x: UInt16, y: UInt16) -> [UInt16] {
        let s1 = UInt16(truncatingIfNeeded: UInt(UInt16(id[5], id[4])) + UInt(x) + UInt(y))
        let s2 = UInt16(truncatingIfNeeded: UInt(UInt16(id[3], id[2])) + UInt(key[2]))
        let s3 = UInt16(truncatingIfNeeded: UInt(UInt16(id[1], id[0])) + UInt(x) * 2)
        let s4 = 0x241a ^ key[3]
        return [s1, s2, s3, s4]
    }
    
    /// Prepares variables for crypto from sensor UID Data and x/y values
    static func prepareVariables(sensorUID: Data, x: UInt16, y: UInt16) -> [UInt16] {
        let s1 = UInt16(truncatingIfNeeded: UInt(UInt16(sensorUID[5], sensorUID[4])) + UInt(x) + UInt(y))
        let s2 = UInt16(truncatingIfNeeded: UInt(UInt16(sensorUID[3], sensorUID[2])) + UInt(key[2]))
        let s3 = UInt16(truncatingIfNeeded: UInt(UInt16(sensorUID[1], sensorUID[0])) + UInt(x) * 2)
        let s4 = 0x241a ^ key[3]
        return [s1, s2, s3, s4]
    }
    
    /// Utility function for key derivation
    static func usefulFunction(sensorUID: Data, x: UInt16, y: UInt16) -> [UInt8] {
        let blockKey = processCrypto(input: prepareVariables(sensorUID: sensorUID, x: x, y: y))
        let low = blockKey[0]
        let high = blockKey[1]
        let r1 = low ^ 0x4163
        let r2 = high ^ 0x4344
        return [
            UInt8(truncatingIfNeeded: r1),
            UInt8(truncatingIfNeeded: r1 >> 8),
            UInt8(truncatingIfNeeded: r2),
            UInt8(truncatingIfNeeded: r2 >> 8)
        ]
    }
    
    /// Utility function for key derivation (array version)
    static func usefulFunction(id: [UInt8], x: UInt16, y: UInt16) -> [UInt8] {
        let blockKey = processCrypto(input: prepareVariables(id: id, x: x, y: y))
        let low = blockKey[0]
        let high = blockKey[1]
        let r1 = low ^ 0x4163
        let r2 = high ^ 0x4344
        return [
            UInt8(truncatingIfNeeded: r1),
            UInt8(truncatingIfNeeded: r1 >> 8),
            UInt8(truncatingIfNeeded: r2),
            UInt8(truncatingIfNeeded: r2 >> 8)
        ]
    }
    
    // MARK: - Libre 2 US / US14day GetArg (LIBRE-SYNTH-008)
    
    /// Calculates getArg for Libre 2 US and libreUS14day sensors
    /// - Parameters:
    ///   - block: Block index (0-42)
    ///   - patchInfo: 6-byte patchInfo from NFC command 0xA1
    /// - Returns: getArg value for the specified block
    ///
    /// Header blocks (0-2) and footer blocks (40-42) use fixed constant 0xcadc.
    /// Data blocks (3-39) use UInt16(patchInfo[5], patchInfo[4]).
    ///
    /// This differs from Libre 2 EU which uses UInt16(info[5], info[4]) ^ 0x44 for all blocks.
    public static func getArgUS14day(block: Int, patchInfo: [UInt8]) -> UInt16 {
        if block < 3 || block >= 40 {
            // Header (0-2) and footer (40-42) use fixed constant
            return 0xcadc
        }
        // Data blocks (3-39) use patchInfo value
        return UInt16(patchInfo[5], patchInfo[4])
    }
}

// MARK: - Errors

/// Libre2 crypto errors
public enum Libre2CryptoError: Error, Sendable {
    case invalidSensorUID
    case invalidPatchInfo
    case dataTooShort
    case crcMismatch
    case unsupportedSensorType
}

// MARK: - CRC16

/// CRC16 implementation for Libre data validation
public enum CRC16 {
    
    /// CRC16 lookup table
    static let table: [UInt16] = [
        0, 4489, 8978, 12955, 17956, 22445, 25910, 29887,
        35912, 40385, 44890, 48851, 51820, 56293, 59774, 63735,
        4225, 264, 13203, 8730, 22181, 18220, 30135, 25662,
        40137, 36160, 49115, 44626, 56045, 52068, 63999, 59510,
        8450, 12427, 528, 5017, 26406, 30383, 17460, 21949,
        44362, 48323, 36440, 40913, 60270, 64231, 51324, 55797,
        12675, 8202, 4753, 792, 30631, 26158, 21685, 17724,
        48587, 44098, 40665, 36688, 64495, 60006, 55549, 51572,
        16900, 21389, 24854, 28831, 1056, 5545, 10034, 14011,
        52812, 57285, 60766, 64727, 34920, 39393, 43898, 47859,
        21125, 17164, 29079, 24606, 5281, 1320, 14259, 9786,
        57037, 53060, 64991, 60502, 39145, 35168, 48123, 43634,
        25350, 29327, 16404, 20893, 9506, 13483, 1584, 6073,
        61262, 65223, 52316, 56789, 43370, 47331, 35448, 39921,
        29575, 25102, 20629, 16668, 13731, 9258, 5809, 1848,
        65487, 60998, 56541, 52564, 47595, 43106, 39673, 35696,
        33800, 38273, 42778, 46739, 49708, 54181, 57662, 61623,
        2112, 6601, 11090, 15067, 20068, 24557, 28022, 31999,
        38025, 34048, 47003, 42514, 53933, 49956, 61887, 57398,
        6337, 2376, 15315, 10842, 24293, 20332, 32247, 27774,
        42250, 46211, 34328, 38801, 58158, 62119, 49212, 53685,
        10562, 14539, 2640, 7129, 28518, 32495, 19572, 24061,
        46475, 41986, 38553, 34576, 62383, 57894, 53437, 49460,
        14787, 10314, 6865, 2904, 32743, 28270, 23797, 19836,
        50700, 55173, 58654, 62615, 32808, 37281, 41786, 45747,
        19012, 23501, 26966, 30943, 3168, 7657, 12146, 16123,
        54925, 50948, 62879, 58390, 37033, 33056, 46011, 41522,
        23237, 19276, 31191, 26718, 7393, 3432, 16371, 11898,
        59150, 63111, 50204, 54677, 41258, 45219, 33336, 37809,
        27462, 31439, 18516, 23005, 11618, 15595, 3696, 8185,
        63375, 58886, 54429, 50452, 45483, 40994, 37561, 33584,
        31687, 27214, 22741, 18780, 15843, 11370, 7921, 3960
    ]
    
    /// Calculates CRC16 for Libre data
    /// - Parameters:
    ///   - data: Data to calculate CRC for
    ///   - seed: Initial seed (default 0xFFFF)
    /// - Returns: CRC16 value
    public static func crc16(_ data: Data, seed: UInt16 = 0xFFFF) -> UInt16 {
        var crc = seed
        
        for byte in data {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt16(byte)) & 0xFF)]
        }
        
        // Reverse bits
        var reverseCrc: UInt16 = 0
        var tempCrc = crc
        for _ in 0..<16 {
            reverseCrc = reverseCrc << 1 | tempCrc & 1
            tempCrc >>= 1
        }
        
        return reverseCrc.byteSwapped
    }
    
    /// Validates CRC16 in last two bytes
    public static func hasValidCrc16InLastTwoBytes(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2 else { return false }
        let data = Array(bytes.dropLast(2))
        let calculatedCrc = crc16(Data(data))
        let suffix = Array(bytes.suffix(2))
        let enclosedCrc = (UInt16(suffix[0]) << 8) | UInt16(suffix[1])
        return calculatedCrc == enclosedCrc
    }
    
    /// Validates CRC16 in first two bytes
    public static func hasValidCrc16InFirstTwoBytes(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 2 else { return false }
        let data = Array(bytes.dropFirst(2))
        let calculatedCrc = crc16(Data(data))
        let enclosedCrc = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        return calculatedCrc == enclosedCrc
    }
}

// MARK: - UInt16 Extension

extension UInt16 {
    /// Create UInt16 from two bytes (high, low)
    init(_ high: UInt8, _ low: UInt8) {
        self = UInt16(high) << 8 + UInt16(low)
    }
}
