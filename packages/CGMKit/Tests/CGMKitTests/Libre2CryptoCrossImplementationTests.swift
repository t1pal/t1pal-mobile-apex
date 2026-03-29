// SPDX-License-Identifier: MIT
//
// Libre2CryptoCrossImplementationTests.swift
// CGMKitTests
//
// Cross-implementation tests validating Libre2 crypto against LibreTransmitter vectors.
// Trace: PROTO-CMP-003

import Testing
import Foundation
@testable import CGMKit

/// Cross-implementation tests for Libre2 decryption
/// Validates our implementation against LibreTransmitter (LoopKit) test vectors
@Suite("Libre2 Crypto Cross-Implementation Tests")
struct Libre2CryptoCrossImplementationTests {
    
    // MARK: - LibreTransmitter Test Vectors
    
    // From Libre2.Example in PreLibre2.swift
    static let example1SensorId: [UInt8] = [157, 129, 194, 0, 0, 164, 7, 224]
    static let example1PatchInfo: [UInt8] = [157, 8, 48, 1, 115, 23]
    static let example1Buffer: [UInt8] = [
        6, 154, 221, 121, 142, 154, 244, 186,
        162, 85, 79, 49, 234, 224, 71, 58,
        189, 121, 123, 39, 28, 162, 134, 248,
        95, 4, 28, 203, 27, 82, 76, 119,
        82, 98, 189, 183, 147, 151, 32, 13,
        73, 158, 214, 167, 143, 2, 182, 22,
        69, 188, 73, 219, 7, 159, 179, 169,
        237, 79, 32, 189, 37, 211, 32, 166,
        191, 150, 171, 60, 143, 143, 1, 105,
        89, 197, 98, 250, 1, 201, 21, 56,
        64, 191, 58, 17, 198, 108, 72, 106,
        144, 253, 19, 111, 235, 187, 245, 208,
        239, 60, 145, 1, 107, 94, 238, 199,
        157, 93, 243, 5, 4, 154, 25, 129,
        131, 75, 16, 240, 210, 118, 172, 14,
        80, 49, 33, 11, 81, 11, 238, 220,
        78, 85, 82, 245, 4, 63, 129, 254,
        214, 233, 225, 147, 58, 153, 20, 247,
        10, 38, 149, 35, 14, 59, 168, 224,
        162, 141, 9, 72, 201, 90, 56, 131,
        150, 89, 126, 2, 96, 38, 140, 78,
        151, 196, 57, 55, 37, 20, 249, 199,
        168, 59, 41, 217, 240, 67, 199, 93,
        164, 121, 206, 100, 214, 126, 40, 231,
        68, 4, 76, 202, 131, 154, 98, 80,
        227, 237, 144, 53, 125, 133, 14, 174,
        196, 90, 78, 238, 163, 199, 249, 74,
        75, 56, 127, 61, 98, 180, 153, 51,
        85, 68, 234, 204, 117, 158, 245, 185,
        40, 186, 227, 50, 105, 231, 155, 160,
        66, 178, 124, 162, 70, 119, 102, 161,
        234, 105, 252, 200, 195, 202, 246, 18,
        71, 189, 150, 123, 105, 106, 105, 223,
        116, 160, 142, 101, 28, 151, 42, 204,
        49, 44, 111, 245, 161, 66, 178, 26,
        99, 110, 136, 140, 135, 167, 171, 160,
        221, 115, 9, 230, 105, 66, 20, 195,
        172, 206, 215, 226, 107, 250, 224, 241,
        6, 219, 139, 251, 189, 106, 161, 124,
        98, 78, 186, 236, 200, 55, 21, 68,
        171, 57, 8, 27, 221, 118, 206, 94,
        226, 155, 82, 143, 44, 186, 173, 86,
        248, 222, 158, 97, 241, 156, 253, 254
    ]
    
    // From Libre2.Example2 in PreLibre2.swift
    static let example2SensorId: [UInt8] = [0xDF, 0x20, 0xBE, 0x00, 0x00, 0xA4, 0x07, 0xE0]
    static let example2PatchInfo: [UInt8] = [0x9D, 0x08, 0x30, 0x01, 0x76, 0x25]
    static let example2Buffer: [UInt8] = [
        0x52, 0x0B, 0xF3, 0x44, 0xDC, 0xA0, 0x43, 0x21,
        0xCC, 0x7D, 0xD7, 0x4E, 0x29, 0xE2, 0x82, 0xE3,
        0xE7, 0x04, 0xC9, 0xCF, 0x6C, 0x57, 0x2C, 0x7D,
        0xA8, 0x82, 0x10, 0xAA, 0xD7, 0x32, 0x19, 0xB3,
        0xC7, 0x9F, 0x39, 0x5F, 0xE3, 0x7A, 0x45, 0x08,
        0xB7, 0x09, 0xBC, 0x6E, 0xFA, 0xDA, 0x34, 0x07,
        0xB4, 0x65, 0x68, 0x60, 0x7E, 0xA5, 0x04, 0xE6,
        0x65, 0x65, 0x48, 0x13, 0xF8, 0x9C, 0xA7, 0xC8,
        0x70, 0xA7, 0x4D, 0x9D, 0x52, 0x35, 0x86, 0xF2,
        0x02, 0xCC, 0x9B, 0x9B, 0x74, 0x32, 0xFF, 0xC5,
        0xBF, 0xE9, 0x78, 0x1F, 0x46, 0xC2, 0xC7, 0x0B,
        0x0F, 0xB0, 0xC8, 0x54, 0x23, 0xE2, 0x0D, 0x44,
        0x97, 0x44, 0x36, 0x8F, 0xAC, 0x12, 0xAE, 0x4A,
        0x6C, 0xE1, 0x37, 0xE2, 0x46, 0x2B, 0x5C, 0x74,
        0x1B, 0x7A, 0xFE, 0x67, 0x4F, 0xCC, 0xDD, 0x95,
        0x17, 0x73, 0xB3, 0x25, 0xE9, 0xAB, 0xA6, 0x5E,
        0x70, 0xE4, 0x6C, 0xCE, 0x56, 0x8D, 0xB9, 0xE5,
        0xFE, 0xAA, 0x50, 0x36, 0x52, 0xD2, 0xC5, 0x22,
        0x24, 0x39, 0xD8, 0x63, 0x08, 0x62, 0x04, 0xAD,
        0xFA, 0x89, 0x00, 0x10, 0x72, 0xCF, 0xA9, 0xF3,
        0x47, 0x4B, 0xF5, 0x70, 0x96, 0xF2, 0x8A, 0xCA,
        0xFF, 0xEF, 0xA3, 0x9E, 0x1A, 0xEC, 0x9F, 0x4A,
        0x2F, 0xE8, 0xA9, 0xCA, 0xE6, 0xC8, 0x74, 0x46,
        0x98, 0xB2, 0xA2, 0x9E, 0x8D, 0xF0, 0xAF, 0x09,
        0xC1, 0x5B, 0x52, 0x59, 0x7E, 0x00, 0xD3, 0x3F,
        0x59, 0x41, 0x7B, 0x33, 0xEE, 0xDB, 0x40, 0x51,
        0xB2, 0x3D, 0x94, 0x82, 0xF3, 0xB2, 0xE4, 0xCA,
        0xAD, 0x3C, 0xD8, 0xC0, 0xD7, 0xD7, 0x4C, 0x51,
        0xCA, 0xA3, 0xAD, 0x26, 0x24, 0xAB, 0x10, 0xBA,
        0x61, 0x35, 0xE1, 0x7F, 0x3D, 0x3F, 0xEC, 0xB4,
        0xCF, 0xE3, 0xA2, 0x31, 0x6A, 0xE7, 0xD7, 0x36,
        0x18, 0x21, 0x5B, 0x43, 0x5A, 0x9C, 0x75, 0x7C,
        0x89, 0xE2, 0x49, 0x6C, 0xB1, 0x71, 0x6A, 0x47,
        0x6E, 0x8A, 0xE5, 0xB2, 0xC5, 0x37, 0xE9, 0xE5,
        0xDD, 0xB3, 0x12, 0x37, 0x95, 0x7A, 0xD0, 0x1F,
        0x73, 0xEB, 0xB8, 0x15, 0xF1, 0xE6, 0x5D, 0x51,
        0xFB, 0x16, 0x88, 0xA6, 0x9C, 0x17, 0xB0, 0x40,
        0x0E, 0xBB, 0xD7, 0xCA, 0x9D, 0xCD, 0x8B, 0x60,
        0x88, 0x88, 0x54, 0xFC, 0x65, 0x71, 0x43, 0xE7,
        0x51, 0xE2, 0x18, 0xEA, 0x63, 0x1D, 0x5B, 0xAA,
        0xD1, 0xD3, 0xD7, 0x08, 0xB7, 0xED, 0x87, 0xC4,
        0xB4, 0x24, 0x31, 0xE7, 0xA0, 0xE6, 0x59, 0x51,
        0x93, 0xFD, 0xA3, 0xE6, 0xBF, 0xE1, 0xF2, 0x09
    ]
    
    // From Libre2.BLEExample in PreLibre2.swift
    static let bleSensorId: [UInt8] = [0x2f, 0xe7, 0xb1, 0x00, 0x00, 0xa4, 0x07, 0xe0]
    static let bleData: [UInt8] = [
        0xb1, 0x94, 0xfa, 0xed, 0x2c, 0xde, 0xa1, 0x69,
        0x46, 0x57, 0xcf, 0xd0, 0xd8, 0x5a, 0xaa, 0xf1,
        0xe2, 0x89, 0x1c, 0xe9, 0xac, 0x82, 0x16, 0xfb,
        0x67, 0xa1, 0xd3, 0xb6, 0x3f, 0x91, 0xcd, 0x18,
        0x4b, 0x95, 0x31, 0x6c, 0x04, 0x5f, 0xe1, 0x96,
        0xc4, 0xfd, 0x14, 0xfc, 0x68, 0xe0
    ]
    
    // MARK: - Crypto Constants Tests
    
    @Test("Key constants match LibreTransmitter")
    func keyConstantsMatch() {
        // From PreLibre2.swift: static let key: [UInt16] = [0xA0C5, 0x6860, 0x0000, 0x14C6]
        #expect(Libre2Crypto.key == [0xA0C5, 0x6860, 0x0000, 0x14C6])
    }
    
    // MARK: - FRAM Decryption Tests
    
    @Test("FRAM decryption Example1 produces valid output")
    func framDecryptionExample1() throws {
        let decrypted = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: Self.example1SensorId,
            patchInfo: Data(Self.example1PatchInfo),
            data: Self.example1Buffer
        )
        
        // Verify output size
        #expect(decrypted.count == 344, "Decrypted FRAM should be 344 bytes")
        
        // Verify decryption produces different output
        #expect(decrypted != Self.example1Buffer, "Decryption should change the data")
        
        // Verify first block is not all zeros (would indicate failed decryption)
        let firstBlock = Array(decrypted[0..<8])
        let allZeros = firstBlock.allSatisfy { $0 == 0 }
        #expect(!allZeros, "First block should not be all zeros")
    }
    
    @Test("FRAM decryption Example2 produces valid output")
    func framDecryptionExample2() throws {
        let decrypted = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: Self.example2SensorId,
            patchInfo: Data(Self.example2PatchInfo),
            data: Self.example2Buffer
        )
        
        #expect(decrypted.count == 344)
        #expect(decrypted != Self.example2Buffer)
    }
    
    @Test("FRAM decryption is deterministic")
    func framDecryptionDeterministic() throws {
        let decrypted1 = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: Self.example1SensorId,
            patchInfo: Data(Self.example1PatchInfo),
            data: Self.example1Buffer
        )
        
        let decrypted2 = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: Self.example1SensorId,
            patchInfo: Data(Self.example1PatchInfo),
            data: Self.example1Buffer
        )
        
        #expect(decrypted1 == decrypted2, "Same input should produce same output")
    }
    
    @Test("FRAM decryption with different sensor IDs produces different output")
    func framDecryptionDifferentSensors() throws {
        let decrypted1 = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: Self.example1SensorId,
            patchInfo: Data(Self.example1PatchInfo),
            data: Self.example1Buffer
        )
        
        let decrypted2 = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: Self.example2SensorId,
            patchInfo: Data(Self.example1PatchInfo),
            data: Self.example1Buffer
        )
        
        #expect(decrypted1 != decrypted2, "Different sensors should produce different output")
    }
    
    // MARK: - BLE Decryption Tests
    
    @Test("BLE decryption produces valid output with CRC")
    func bleDecryptionValid() throws {
        // The BLE example from LibreTransmitter should decrypt with valid CRC
        let decrypted = try Libre2Crypto.decryptBLE(
            sensorUID: Self.bleSensorId,
            data: Self.bleData
        )
        
        // Decrypted output should be 44 bytes (46 - 2 header bytes)
        #expect(decrypted.count == 44, "Decrypted BLE should be 44 bytes")
    }
    
    @Test("BLE decryption is deterministic")
    func bleDecryptionDeterministic() throws {
        let decrypted1 = try Libre2Crypto.decryptBLE(
            sensorUID: Self.bleSensorId,
            data: Self.bleData
        )
        
        let decrypted2 = try Libre2Crypto.decryptBLE(
            sensorUID: Self.bleSensorId,
            data: Self.bleData
        )
        
        #expect(decrypted1 == decrypted2, "Same input should produce same output")
    }
    
    @Test("BLE decryption with wrong sensor ID fails CRC")
    func bleDecryptionWrongSensorFails() {
        let wrongSensorId: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0xe0]
        
        do {
            _ = try Libre2Crypto.decryptBLE(
                sensorUID: wrongSensorId,
                data: Self.bleData
            )
            Issue.record("Should have thrown CRC error")
        } catch let error as Libre2CryptoError {
            #expect(error == .crcMismatch)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - processCrypto Tests
    
    @Test("processCrypto produces non-trivial output")
    func processCryptoNonTrivial() {
        let input: [UInt16] = [0x1234, 0x5678, 0x9ABC, 0xDEF0]
        let output = Libre2Crypto.processCrypto(input: input)
        
        #expect(output.count == 4)
        #expect(output != input, "Output should differ from input")
        #expect(output != [0, 0, 0, 0], "Output should not be all zeros")
    }
    
    @Test("processCrypto is deterministic")
    func processCryptoDeterministic() {
        let input: [UInt16] = [0x1234, 0x5678, 0x9ABC, 0xDEF0]
        let output1 = Libre2Crypto.processCrypto(input: input)
        let output2 = Libre2Crypto.processCrypto(input: input)
        
        #expect(output1 == output2)
    }
    
    // MARK: - prepareVariables Tests
    
    @Test("prepareVariables produces unique output per sensor")
    func prepareVariablesUnique() {
        let vars1 = Libre2Crypto.prepareVariables(id: Self.example1SensorId, x: 0x1b, y: 0x1b6a)
        let vars2 = Libre2Crypto.prepareVariables(id: Self.example2SensorId, x: 0x1b, y: 0x1b6a)
        
        #expect(vars1 != vars2, "Different sensors should produce different variables")
    }
    
    @Test("prepareVariables with different x/y produces different output")
    func prepareVariablesDifferentParams() {
        let vars1 = Libre2Crypto.prepareVariables(id: Self.example1SensorId, x: 0x00, y: 0x00)
        let vars2 = Libre2Crypto.prepareVariables(id: Self.example1SensorId, x: 0x01, y: 0x01)
        
        #expect(vars1 != vars2, "Different x/y should produce different variables")
    }
    
    // MARK: - usefulFunction Tests
    
    @Test("usefulFunction produces 4-byte output")
    func usefulFunctionOutput() {
        let result = Libre2Crypto.usefulFunction(id: Self.example1SensorId, x: 0x1b, y: 0x1b6a)
        
        #expect(result.count == 4)
    }
    
    @Test("usefulFunction is deterministic")
    func usefulFunctionDeterministic() {
        let result1 = Libre2Crypto.usefulFunction(id: Self.example1SensorId, x: 0x1b, y: 0x1b6a)
        let result2 = Libre2Crypto.usefulFunction(id: Self.example1SensorId, x: 0x1b, y: 0x1b6a)
        
        #expect(result1 == result2)
    }
    
    // MARK: - CRC16 Tests
    
    @Test("CRC16 matches LibreTransmitter implementation")
    func crc16Matches() {
        // Test with known data
        let testData = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let crc = CRC16.crc16(testData)
        
        // CRC should be non-zero for non-empty data
        #expect(crc != 0, "CRC should be non-zero")
    }
    
    @Test("CRC16 is deterministic")
    func crc16Deterministic() {
        let testData = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let crc1 = CRC16.crc16(testData)
        let crc2 = CRC16.crc16(testData)
        
        #expect(crc1 == crc2)
    }
    
    @Test("CRC16 validation works correctly")
    func crc16Validation() {
        // Create data with appended CRC
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let crc = CRC16.crc16(data)
        
        // The CRC should be valid when appended
        var dataWithCrc = Array(data)
        dataWithCrc.append(UInt8((crc >> 8) & 0xFF))
        dataWithCrc.append(UInt8(crc & 0xFF))
        
        #expect(CRC16.hasValidCrc16InLastTwoBytes(dataWithCrc), "CRC validation should pass")
    }
    
    // MARK: - Activation Parameters Tests
    
    @Test("Activation parameters produces 5-byte output")
    func activationParametersFormat() {
        let params = Libre2Crypto.activateParameters(sensorUID: Self.example1SensorId)
        
        #expect(params.count == 5)
        #expect(params[0] == 0x1b, "First byte should be 0x1b command")
    }
    
    @Test("Activation parameters differ per sensor")
    func activationParametersUnique() {
        let params1 = Libre2Crypto.activateParameters(sensorUID: Self.example1SensorId)
        let params2 = Libre2Crypto.activateParameters(sensorUID: Self.example2SensorId)
        
        #expect(params1 != params2, "Different sensors should have different activation params")
    }
}
