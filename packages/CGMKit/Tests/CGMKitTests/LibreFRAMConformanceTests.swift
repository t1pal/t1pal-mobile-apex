// SPDX-License-Identifier: MIT
//
// LibreFRAMConformanceTests.swift
// CGMKitTests
//
// Fixture-based conformance tests for Libre FRAM parsing.
// Validates against fixture_libre_fram.json vectors.
// Trace: LIBRE-SYNTH-001

import Testing
import Foundation
@testable import CGMKit

/// Conformance tests for Libre FRAM parsing using fixture vectors
@Suite("Libre FRAM Conformance Tests")
struct LibreFRAMConformanceTests {
    
    // MARK: - Fixture Loading
    
    struct LibreFRAMFixture: Codable {
        let _comment: String
        let _source: String
        let _task: String
        let fram_vectors: [FRAMVector]
        let ble_vectors: [BLEVector]
        let sensor_types: [String: SensorTypeInfo]
        let crypto_constants: CryptoConstants
        let fram_structure: FRAMStructure
        let sensor_states: [String: String]
        
        struct FRAMVector: Codable {
            let id: String
            let description: String
            let source: String
            let sensorType: String
            let sensorUID: [UInt8]
            let sensorUIDHex: String
            let patchInfo: [UInt8]
            let patchInfoHex: String
            let encrypted: [UInt8]
            let encryptedSize: Int
            let notes: String
            let sensorName: String?
        }
        
        struct BLEVector: Codable {
            let id: String
            let description: String
            let source: String
            let sensorUID: [UInt8]
            let sensorUIDHex: String
            let encrypted: [UInt8]
            let encryptedSize: Int
            let notes: String
        }
        
        struct SensorTypeInfo: Codable {
            let patchInfoByte0: String
            let description: String
            let argXor: String?
            let headerFooterArg: String?
        }
        
        struct CryptoConstants: Codable {
            let key: [UInt16]
            let keyHex: [String]
            let xorMagic1: String
            let xorMagic2: String
            let prepareVariablesMagic: String
            let usefulFunctionX: String
            let usefulFunctionY: String
            let activateParamsByte0: String
        }
        
        struct FRAMStructure: Codable {
            let header: BlockInfo
            let body: BlockInfo
            let footer: BlockInfo
            
            struct BlockInfo: Codable {
                let offset: Int
                let size: Int
                let fields: [String: String]
            }
        }
    }
    
    static func loadFixture() throws -> LibreFRAMFixture {
        let fixtureURL = Bundle.module.url(
            forResource: "fixture_libre_fram",
            withExtension: "json",
            subdirectory: "Fixtures/libre2"
        )!
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(LibreFRAMFixture.self, from: data)
    }
    
    // MARK: - Crypto Constants Validation
    
    @Test("Crypto key constants match fixture")
    func cryptoKeyConstants() throws {
        let fixture = try Self.loadFixture()
        
        #expect(Libre2Crypto.key == fixture.crypto_constants.key,
               "Implementation key should match fixture")
    }
    
    @Test("Crypto key has correct length")
    func cryptoKeyLength() {
        #expect(Libre2Crypto.key.count == 4, "Key should have 4 elements")
    }
    
    // MARK: - FRAM Decryption Tests
    
    @Test("All FRAM vectors decrypt successfully")
    func framDecryptionAllVectors() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.fram_vectors {
            // Skip partial FRAM (less than 344 bytes)
            guard vector.encryptedSize == 344 else { continue }
            
            let sensorType: Libre2Crypto.SensorType = vector.sensorType == "libre2" ? .libre2 : .libreUS14day
            
            do {
                let decrypted = try Libre2Crypto.decryptFRAM(
                    type: sensorType,
                    sensorUID: vector.sensorUID,
                    patchInfo: Data(vector.patchInfo),
                    data: vector.encrypted
                )
                
                #expect(decrypted.count == 344,
                       "Vector \(vector.id): Decrypted FRAM should be 344 bytes")
                #expect(decrypted != vector.encrypted,
                       "Vector \(vector.id): Decryption should change data")
                
            } catch {
                Issue.record("Vector \(vector.id) failed: \(error)")
            }
        }
    }
    
    @Test("FRAM decryption produces deterministic output")
    func framDecryptionDeterministic() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.fram_vectors.first(where: { $0.encryptedSize == 344 }) else {
            Issue.record("No 344-byte FRAM vector found")
            return
        }
        
        let decrypted1 = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: vector.sensorUID,
            patchInfo: Data(vector.patchInfo),
            data: vector.encrypted
        )
        
        let decrypted2 = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: vector.sensorUID,
            patchInfo: Data(vector.patchInfo),
            data: vector.encrypted
        )
        
        #expect(decrypted1 == decrypted2, "Same input should produce same output")
    }
    
    @Test("Different sensors produce different decryption")
    func framDecryptionDifferentSensors() throws {
        let fixture = try Self.loadFixture()
        let fullVectors = fixture.fram_vectors.filter { $0.encryptedSize == 344 }
        
        guard fullVectors.count >= 2 else {
            Issue.record("Need at least 2 full FRAM vectors")
            return
        }
        
        let decrypted1 = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: fullVectors[0].sensorUID,
            patchInfo: Data(fullVectors[0].patchInfo),
            data: fullVectors[0].encrypted
        )
        
        let decrypted2 = try Libre2Crypto.decryptFRAM(
            type: .libre2,
            sensorUID: fullVectors[1].sensorUID,
            patchInfo: Data(fullVectors[1].patchInfo),
            data: fullVectors[1].encrypted
        )
        
        #expect(decrypted1 != decrypted2, "Different sensors should produce different output")
    }
    
    // MARK: - BLE Decryption Tests
    
    @Test("All BLE vectors decrypt successfully")
    func bleDecryptionAllVectors() throws {
        let fixture = try Self.loadFixture()
        
        for vector in fixture.ble_vectors {
            do {
                let decrypted = try Libre2Crypto.decryptBLE(
                    sensorUID: vector.sensorUID,
                    data: vector.encrypted
                )
                
                #expect(decrypted.count == 44,
                       "Vector \(vector.id): Decrypted BLE should be 44 bytes")
                
            } catch {
                Issue.record("BLE Vector \(vector.id) failed: \(error)")
            }
        }
    }
    
    @Test("BLE decryption fails with wrong sensor ID")
    func bleDecryptionWrongSensor() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.ble_vectors.first else {
            Issue.record("No BLE vector found")
            return
        }
        
        // Use a different sensor ID
        let wrongSensorUID: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0xe0]
        
        do {
            _ = try Libre2Crypto.decryptBLE(
                sensorUID: wrongSensorUID,
                data: vector.encrypted
            )
            Issue.record("Should have failed CRC check")
        } catch let error as Libre2CryptoError {
            #expect(error == .crcMismatch, "Should fail with CRC mismatch")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
    
    // MARK: - FRAM Structure Validation
    
    @Test("FRAM structure sizes match fixture")
    func framStructureSizes() throws {
        let fixture = try Self.loadFixture()
        
        let headerSize = fixture.fram_structure.header.size
        let bodySize = fixture.fram_structure.body.size
        let footerSize = fixture.fram_structure.footer.size
        
        #expect(headerSize == 24, "Header should be 24 bytes")
        #expect(bodySize == 296, "Body should be 296 bytes")
        #expect(footerSize == 24, "Footer should be 24 bytes")
        #expect(headerSize + bodySize + footerSize == 344, "Total should be 344 bytes")
    }
    
    @Test("FRAM offsets are correct")
    func framOffsets() throws {
        let fixture = try Self.loadFixture()
        
        #expect(fixture.fram_structure.header.offset == 0)
        #expect(fixture.fram_structure.body.offset == 24)
        #expect(fixture.fram_structure.footer.offset == 320)
    }
    
    // MARK: - Sensor Type Detection
    
    @Test("Sensor types have correct patch info byte")
    func sensorTypePatchInfo() throws {
        let fixture = try Self.loadFixture()
        
        if let libre2Info = fixture.sensor_types["libre2"] {
            #expect(libre2Info.patchInfoByte0 == "0x9D", "Libre2 should have 0x9D")
        }
        
        if let us14dayInfo = fixture.sensor_types["libreUS14day"] {
            #expect(us14dayInfo.patchInfoByte0 == "0xA2", "US14day should have 0xA2")
        }
    }
    
    // MARK: - Activation Parameters
    
    @Test("Activation parameters start with correct byte")
    func activationParametersFormat() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.fram_vectors.first else { return }
        
        let params = Libre2Crypto.activateParameters(sensorUID: vector.sensorUID)
        
        #expect(params.count == 5, "Activation params should be 5 bytes")
        #expect(params[0] == 0x1b, "First byte should be 0x1b")
    }
    
    @Test("Activation parameters differ per sensor")
    func activationParametersUnique() throws {
        let fixture = try Self.loadFixture()
        let fullVectors = fixture.fram_vectors.filter { $0.encryptedSize == 344 }
        guard fullVectors.count >= 2 else { return }
        
        let params1 = Libre2Crypto.activateParameters(sensorUID: fullVectors[0].sensorUID)
        let params2 = Libre2Crypto.activateParameters(sensorUID: fullVectors[1].sensorUID)
        
        #expect(params1 != params2, "Different sensors should have different activation params")
    }
    
    // MARK: - Streaming Unlock Payload
    
    @Test("Streaming unlock payload has correct length")
    func streamingUnlockLength() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.fram_vectors.first else { return }
        
        let payload = Libre2Crypto.streamingUnlockPayload(
            sensorUID: Data(vector.sensorUID),
            patchInfo: Data(vector.patchInfo),
            enableTime: 1000000,
            unlockCount: 1
        )
        
        #expect(payload.count == 12, "Unlock payload should be 12 bytes")
    }
    
    @Test("Streaming unlock payload changes with unlock count")
    func streamingUnlockChanges() throws {
        let fixture = try Self.loadFixture()
        guard let vector = fixture.fram_vectors.first else { return }
        
        let payload1 = Libre2Crypto.streamingUnlockPayload(
            sensorUID: Data(vector.sensorUID),
            patchInfo: Data(vector.patchInfo),
            enableTime: 1000000,
            unlockCount: 1
        )
        
        let payload2 = Libre2Crypto.streamingUnlockPayload(
            sensorUID: Data(vector.sensorUID),
            patchInfo: Data(vector.patchInfo),
            enableTime: 1000000,
            unlockCount: 2
        )
        
        #expect(payload1 != payload2, "Different unlock counts should produce different payloads")
    }
}
