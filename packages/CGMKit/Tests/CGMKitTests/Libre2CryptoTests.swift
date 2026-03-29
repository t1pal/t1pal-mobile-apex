// SPDX-License-Identifier: MIT
//
// Libre2CryptoTests.swift
// CGMKit
//
// Tests for Libre 2 encryption/decryption.
// Trace: PRD-004 REQ-CGM-002 CGM-020

import Testing
import Foundation
@testable import CGMKit

@Suite("Libre2 Crypto Tests")
struct Libre2CryptoTests {
    
    // MARK: - Test Data (from LibreTransmitter examples)
    
    static let exampleSensorUID: [UInt8] = [0x2f, 0xe7, 0xb1, 0x00, 0x00, 0xa4, 0x07, 0xe0]
    static let exampleBLEData: [UInt8] = [
        0xb1, 0x94, 0xfa, 0xed, 0x2c, 0xde, 0xa1, 0x69,
        0x46, 0x57, 0xcf, 0xd0, 0xd8, 0x5a, 0xaa, 0xf1,
        0xe2, 0x89, 0x1c, 0xe9, 0xac, 0x82, 0x16, 0xfb,
        0x67, 0xa1, 0xd3, 0xb6, 0x3f, 0x91, 0xcd, 0x18,
        0x4b, 0x95, 0x31, 0x6c, 0x04, 0x5f, 0xe1, 0x96,
        0xc4, 0xfd, 0x14, 0xfc, 0x68, 0xe0
    ]
    
    // MARK: - CRC16 Tests
    
    @Test("CRC16 produces consistent output")
    func crc16Consistent() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let crc1 = CRC16.crc16(data)
        let crc2 = CRC16.crc16(data)
        #expect(crc1 == crc2)
    }
    
    @Test("CRC16 different data produces different CRC")
    func crc16DifferentData() {
        let data1 = Data([0x01, 0x02, 0x03])
        let data2 = Data([0x01, 0x02, 0x04])
        let crc1 = CRC16.crc16(data1)
        let crc2 = CRC16.crc16(data2)
        #expect(crc1 != crc2)
    }
    
    @Test("CRC16 validation with valid last bytes")
    func crc16ValidLastBytes() {
        // Create data with valid CRC in last two bytes
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let crc = CRC16.crc16(payload)
        var dataWithCRC = Array(payload)
        dataWithCRC.append(UInt8((crc >> 8) & 0xFF))
        dataWithCRC.append(UInt8(crc & 0xFF))
        
        #expect(CRC16.hasValidCrc16InLastTwoBytes(dataWithCRC))
    }
    
    @Test("CRC16 validation fails with invalid bytes")
    func crc16InvalidBytes() {
        let invalidData: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x00, 0x00]
        #expect(!CRC16.hasValidCrc16InLastTwoBytes(invalidData))
    }
    
    @Test("CRC16 handles empty data")
    func crc16EmptyData() {
        #expect(!CRC16.hasValidCrc16InLastTwoBytes([]))
        #expect(!CRC16.hasValidCrc16InLastTwoBytes([0x01]))
    }
    
    // MARK: - ProcessCrypto Tests
    
    @Test("processCrypto produces consistent output")
    func processCryptoConsistent() {
        let input: [UInt16] = [0x1234, 0x5678, 0x9ABC, 0xDEF0]
        let result1 = Libre2Crypto.processCrypto(input: input)
        let result2 = Libre2Crypto.processCrypto(input: input)
        #expect(result1 == result2)
    }
    
    @Test("processCrypto returns 4 elements")
    func processCryptoReturnsCorrectLength() {
        let input: [UInt16] = [0x1234, 0x5678, 0x9ABC, 0xDEF0]
        let result = Libre2Crypto.processCrypto(input: input)
        #expect(result.count == 4)
    }
    
    @Test("processCrypto different input produces different output")
    func processCryptoDifferentInputs() {
        let input1: [UInt16] = [0x1234, 0x5678, 0x9ABC, 0xDEF0]
        let input2: [UInt16] = [0x1235, 0x5678, 0x9ABC, 0xDEF0]
        let result1 = Libre2Crypto.processCrypto(input: input1)
        let result2 = Libre2Crypto.processCrypto(input: input2)
        #expect(result1 != result2)
    }
    
    // MARK: - PrepareVariables Tests
    
    @Test("prepareVariables returns 4 elements")
    func prepareVariablesLength() {
        let result = Libre2Crypto.prepareVariables(id: Self.exampleSensorUID, x: 0x1b, y: 0x1b6a)
        #expect(result.count == 4)
    }
    
    @Test("prepareVariables is deterministic")
    func prepareVariablesDeterministic() {
        let result1 = Libre2Crypto.prepareVariables(id: Self.exampleSensorUID, x: 0x1b, y: 0x1b6a)
        let result2 = Libre2Crypto.prepareVariables(id: Self.exampleSensorUID, x: 0x1b, y: 0x1b6a)
        #expect(result1 == result2)
    }
    
    // MARK: - Activation Parameters Tests
    
    @Test("activateParameters returns 5 bytes")
    func activateParametersLength() {
        let params = Libre2Crypto.activateParameters(sensorUID: Self.exampleSensorUID)
        #expect(params.count == 5)
    }
    
    @Test("activateParameters starts with 0x1b")
    func activateParametersStartByte() {
        let params = Libre2Crypto.activateParameters(sensorUID: Self.exampleSensorUID)
        #expect(params[0] == 0x1b)
    }
    
    @Test("activateParameters is deterministic")
    func activateParametersDeterministic() {
        let params1 = Libre2Crypto.activateParameters(sensorUID: Self.exampleSensorUID)
        let params2 = Libre2Crypto.activateParameters(sensorUID: Self.exampleSensorUID)
        #expect(params1 == params2)
    }
    
    // MARK: - Streaming Unlock Payload Tests
    
    @Test("streamingUnlockPayload returns 12 bytes")
    func unlockPayloadLength() {
        let sensorUID = Data(Self.exampleSensorUID)
        let patchInfo = Data([0x9D, 0x08, 0x30, 0x01, 0x76, 0x25])
        let payload = Libre2Crypto.streamingUnlockPayload(
            sensorUID: sensorUID,
            patchInfo: patchInfo,
            enableTime: 1000000,
            unlockCount: 1
        )
        #expect(payload.count == 12)
    }
    
    @Test("streamingUnlockPayload changes with unlock count")
    func unlockPayloadChangesWithCount() {
        let sensorUID = Data(Self.exampleSensorUID)
        let patchInfo = Data([0x9D, 0x08, 0x30, 0x01, 0x76, 0x25])
        
        let payload1 = Libre2Crypto.streamingUnlockPayload(
            sensorUID: sensorUID,
            patchInfo: patchInfo,
            enableTime: 1000000,
            unlockCount: 1
        )
        let payload2 = Libre2Crypto.streamingUnlockPayload(
            sensorUID: sensorUID,
            patchInfo: patchInfo,
            enableTime: 1000000,
            unlockCount: 2
        )
        
        #expect(payload1 != payload2)
    }
    
    // MARK: - BLE Decryption Error Tests
    
    @Test("decryptBLE throws on invalid sensor UID")
    func decryptBLEInvalidUID() async throws {
        let shortUID: [UInt8] = [0x01, 0x02, 0x03]
        
        #expect(throws: Libre2CryptoError.invalidSensorUID) {
            _ = try Libre2Crypto.decryptBLE(sensorUID: shortUID, data: Self.exampleBLEData)
        }
    }
    
    @Test("decryptBLE throws on short data")
    func decryptBLEShortData() async throws {
        let shortData: [UInt8] = [0x01, 0x02]
        
        #expect(throws: Libre2CryptoError.dataTooShort) {
            _ = try Libre2Crypto.decryptBLE(sensorUID: Self.exampleSensorUID, data: shortData)
        }
    }
    
    // MARK: - FRAM Decryption Error Tests
    
    @Test("decryptFRAM throws on invalid sensor UID")
    func decryptFRAMInvalidUID() async throws {
        let shortUID: [UInt8] = [0x01, 0x02, 0x03]
        let patchInfo = Data([0x9D, 0x08, 0x30, 0x01, 0x76, 0x25])
        let data = [UInt8](repeating: 0, count: 344)
        
        #expect(throws: Libre2CryptoError.invalidSensorUID) {
            _ = try Libre2Crypto.decryptFRAM(type: .libre2, sensorUID: shortUID, patchInfo: patchInfo, data: data)
        }
    }
    
    @Test("decryptFRAM throws on invalid patch info")
    func decryptFRAMInvalidPatchInfo() async throws {
        let shortPatchInfo = Data([0x01, 0x02])
        let data = [UInt8](repeating: 0, count: 344)
        
        #expect(throws: Libre2CryptoError.invalidPatchInfo) {
            _ = try Libre2Crypto.decryptFRAM(type: .libre2, sensorUID: Self.exampleSensorUID, patchInfo: shortPatchInfo, data: data)
        }
    }
    
    @Test("decryptFRAM throws on short data")
    func decryptFRAMShortData() async throws {
        let patchInfo = Data([0x9D, 0x08, 0x30, 0x01, 0x76, 0x25])
        let shortData = [UInt8](repeating: 0, count: 100)
        
        #expect(throws: Libre2CryptoError.dataTooShort) {
            _ = try Libre2Crypto.decryptFRAM(type: .libre2, sensorUID: Self.exampleSensorUID, patchInfo: patchInfo, data: shortData)
        }
    }
    
    @Test("decryptFRAM returns correct length")
    func decryptFRAMReturnsCorrectLength() throws {
        let patchInfo = Data([0x9D, 0x08, 0x30, 0x01, 0x76, 0x25])
        let data = [UInt8](repeating: 0, count: 344)
        
        let result = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: Self.exampleSensorUID,
            patchInfo: patchInfo,
            data: data
        )
        
        #expect(result.count == 344)
    }
    
    // MARK: - Sensor Type Tests
    
    @Test("Libre2 sensor type decrypts differently than US14day")
    func sensorTypesProduceDifferentResults() throws {
        let patchInfo = Data([0x9D, 0x08, 0x30, 0x01, 0x76, 0x25])
        let data = [UInt8](repeating: 0xAB, count: 344)
        
        let libre2Result = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: Self.exampleSensorUID,
            patchInfo: patchInfo,
            data: data
        )
        
        let us14dayResult = try Libre2Crypto.decryptFRAM(
            type: .libreUS14day,
            sensorUID: Self.exampleSensorUID,
            patchInfo: patchInfo,
            data: data
        )
        
        #expect(libre2Result != us14dayResult)
    }
    
    // MARK: - UInt16 Extension Tests
    
    @Test("UInt16 init from bytes")
    func uint16InitFromBytes() {
        let value = UInt16(0x12, 0x34)
        #expect(value == 0x1234)
    }
    
    @Test("UInt16 init zero bytes")
    func uint16InitZeroBytes() {
        let value = UInt16(0x00, 0x00)
        #expect(value == 0x0000)
    }
    
    @Test("UInt16 init max bytes")
    func uint16InitMaxBytes() {
        let value = UInt16(0xFF, 0xFF)
        #expect(value == 0xFFFF)
    }
}
