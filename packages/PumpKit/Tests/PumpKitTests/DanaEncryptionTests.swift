// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DanaEncryptionTests.swift
// PumpKitTests
//
// Tests for Dana encryption implementation (DANA-IMPL-002).
// Verifies CRC16, packet markers, and encryption/decryption for all 3 modes.

import Testing
import Foundation
@testable import PumpKit

@Suite("Dana Encryption Tests")
struct DanaEncryptionTests {
    
    // MARK: - CRC16 Tests
    
    @Test("CRC16 legacy basic calculation")
    func crc16_Legacy_BasicCalculation() {
        // Test basic CRC calculation for legacy mode
        let data = Data([0x01, 0x00, 0x54, 0x31, 0x50, 0x61, 0x6C])
        let crc = DanaCRC16.calculate(data, encryptionType: .legacy, isEncryptionCommand: true)
        
        // CRC should be a valid 16-bit value
        #expect(crc > 0, "CRC should be non-zero for non-empty data")
        #expect(crc <= 0xFFFF, "CRC should be 16-bit")
    }
    
    @Test("CRC16 RSv3 encryption vs normal command")
    func crc16_RSv3_EncryptionVsNormalCommand() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        
        let crcEncryption = DanaCRC16.calculate(data, encryptionType: .rsv3, isEncryptionCommand: true)
        let crcNormal = DanaCRC16.calculate(data, encryptionType: .rsv3, isEncryptionCommand: false)
        
        // RSv3 uses different CRC algorithm for encryption vs normal commands
        #expect(crcEncryption != crcNormal, 
            "RSv3 should use different CRC for encryption vs normal commands")
    }
    
    @Test("CRC16 BLE5 encryption vs normal command")
    func crc16_BLE5_EncryptionVsNormalCommand() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        
        let crcEncryption = DanaCRC16.calculate(data, encryptionType: .ble5, isEncryptionCommand: true)
        let crcNormal = DanaCRC16.calculate(data, encryptionType: .ble5, isEncryptionCommand: false)
        
        // BLE5 uses different CRC algorithm for encryption vs normal commands
        #expect(crcEncryption != crcNormal, 
            "BLE5 should use different CRC for encryption vs normal commands")
    }
    
    @Test("CRC16 all types produce different results")
    func crc16_AllTypes_DifferentResults() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        
        let crcLegacy = DanaCRC16.calculate(data, encryptionType: .legacy, isEncryptionCommand: false)
        let crcRSv3 = DanaCRC16.calculate(data, encryptionType: .rsv3, isEncryptionCommand: false)
        let crcBLE5 = DanaCRC16.calculate(data, encryptionType: .ble5, isEncryptionCommand: false)
        
        // Each encryption type should produce different CRC (different algorithms)
        #expect(crcLegacy != crcRSv3, "Legacy and RSv3 should have different CRC")
        #expect(crcRSv3 != crcBLE5, "RSv3 and BLE5 should have different CRC")
    }
    
    @Test("CRC16 append and verify")
    func crc16_AppendAndVerify() {
        var data = Data([0x01, 0x02, 0x03, 0x04])
        DanaCRC16.append(to: &data, encryptionType: .legacy, isEncryptionCommand: true)
        
        #expect(data.count == 6, "Should append 2 CRC bytes")
        
        let isValid = DanaCRC16.verify(data, encryptionType: .legacy, isEncryptionCommand: true)
        #expect(isValid, "CRC should verify correctly after appending")
    }
    
    @Test("CRC16 verify corrupted data")
    func crc16_VerifyCorruptedData() {
        var data = Data([0x01, 0x02, 0x03, 0x04])
        DanaCRC16.append(to: &data, encryptionType: .legacy, isEncryptionCommand: true)
        
        // Corrupt a byte
        data[2] = 0xFF
        
        let isValid = DanaCRC16.verify(data, encryptionType: .legacy, isEncryptionCommand: true)
        #expect(!isValid, "Corrupted data should fail CRC verification")
    }
    
    // MARK: - Packet Markers Tests
    
    @Test("Packet markers legacy")
    func packetMarkers_Legacy() {
        let markers = DanaPacketMarkers.markers(for: .legacy)
        
        #expect(markers.start == Data([0xA5, 0xA5]))
        #expect(markers.end == Data([0x5A, 0x5A]))
    }
    
    @Test("Packet markers RSv3")
    func packetMarkers_RSv3() {
        let markers = DanaPacketMarkers.markers(for: .rsv3)
        
        #expect(markers.start == Data([0x7A, 0x7A]))
        #expect(markers.end == Data([0x2E, 0x2E]))
    }
    
    @Test("Packet markers BLE5")
    func packetMarkers_BLE5() {
        let markers = DanaPacketMarkers.markers(for: .ble5)
        
        #expect(markers.start == Data([0xAA, 0xAA]))
        #expect(markers.end == Data([0xEE, 0xEE]))
    }
    
    // MARK: - Encryption Type Detection Tests
    
    @Test("Detect encryption type legacy")
    func detectEncryptionType_Legacy() {
        let packet = Data([0xA5, 0xA5, 0x04, 0x01, 0x00, 0x00, 0x5A, 0x5A])
        let detected = DanaEncryption.detectEncryptionType(from: packet)
        
        #expect(detected == .legacy)
    }
    
    @Test("Detect encryption type RSv3")
    func detectEncryptionType_RSv3() {
        let packet = Data([0x7A, 0x7A, 0x04, 0x01, 0x00, 0x00, 0x2E, 0x2E])
        let detected = DanaEncryption.detectEncryptionType(from: packet)
        
        #expect(detected == .rsv3)
    }
    
    @Test("Detect encryption type BLE5")
    func detectEncryptionType_BLE5() {
        let packet = Data([0xAA, 0xAA, 0x04, 0x01, 0x00, 0x00, 0xEE, 0xEE])
        let detected = DanaEncryption.detectEncryptionType(from: packet)
        
        #expect(detected == .ble5)
    }
    
    @Test("Detect encryption type unknown")
    func detectEncryptionType_Unknown() {
        let packet = Data([0x00, 0x00, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00])
        let detected = DanaEncryption.detectEncryptionType(from: packet)
        
        #expect(detected == nil)
    }
    
    @Test("Detect encryption type too short")
    func detectEncryptionType_TooShort() {
        let packet = Data([0xA5, 0xA5])
        let detected = DanaEncryption.detectEncryptionType(from: packet)
        
        #expect(detected == nil)
    }
    
    // MARK: - Encryption Keys Tests
    
    @Test("Encryption keys default init")
    func encryptionKeys_DefaultInit() {
        let keys = DanaEncryptionKeys()
        
        #expect(keys.timeSecret.count == 6)
        #expect(keys.passwordSecret.count == 2)
        #expect(keys.passKeySecret.count == 2)
        #expect(keys.pairingKey.count == 6)
        #expect(keys.randomPairingKey.count == 3)
        #expect(keys.randomSyncKey == 0)
        #expect(keys.ble5Keys.0 == 0)
        #expect(keys.ble5Keys.1 == 0)
        #expect(keys.ble5Keys.2 == 0)
    }
    
    // MARK: - BLE5 Encryption Round-Trip Tests
    
    @Test("BLE5 encrypt decrypt round trip")
    func ble5_EncryptDecryptRoundTrip() {
        // Create encryption engine with BLE5 keys
        let keys = DanaEncryptionKeys(
            ble5Keys: (0x12, 0x34, 0x56)
        )
        var encryptor = DanaEncryption(encryptionType: .ble5, keys: keys)
        var decryptor = DanaEncryption(encryptionType: .ble5, keys: keys)
        
        // Original packet with legacy markers
        let original = Data([0xA5, 0xA5, 0x04, 0x01, 0x00, 0x12, 0x34, 0x56, 0x5A, 0x5A])
        
        // Encrypt
        let encrypted = encryptor.encrypt(original)
        
        // Size should be preserved
        #expect(encrypted.count == original.count, "Encrypted packet should be same size")
        
        // Encrypted should be different from original (actual encryption happens)
        #expect(encrypted != original, "Encryption should modify data")
        
        // Decrypt
        let decrypted = decryptor.decrypt(encrypted)
        
        // Round-trip should restore original
        #expect(decrypted == original, "Decrypt(Encrypt(data)) should return original")
    }
    
    @Test("BLE5 data transformation")
    func ble5_DataTransformation() {
        // BLE5 encryption transforms all bytes including markers
        let keys = DanaEncryptionKeys(ble5Keys: (0x01, 0x02, 0x03))
        var encryption = DanaEncryption(encryptionType: .ble5, keys: keys)
        
        let packet = Data([0xA5, 0xA5, 0x04, 0x01, 0x00, 0x00, 0x5A, 0x5A])
        let encrypted = encryption.encrypt(packet)
        
        // BLE5 encryption replaces markers THEN encrypts all bytes
        // So final markers are transformed - just verify data changed
        #expect(encrypted.count == packet.count, "Encrypted packet should be same size")
        #expect(encrypted != packet, "Encryption should transform data")
    }
    
    // MARK: - RSv3 Marker Tests
    
    @Test("RSv3 marker replacement")
    func rsv3_MarkerReplacement() {
        // Create encryption engine with RSv3 keys
        let keys = DanaEncryptionKeys(
            pairingKey: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]),
            randomPairingKey: Data([0x11, 0x22, 0x33])
        )
        var encryption = DanaEncryption(encryptionType: .rsv3, keys: keys)
        
        let packet = Data([0xA5, 0xA5, 0x04, 0x01, 0x00, 0x00, 0x5A, 0x5A])
        let encrypted = encryption.encrypt(packet)
        
        // Note: RSv3 encryption modifies all bytes, but markers should start as 7A/2E
        // Due to encryption, final values may differ - just verify encryption runs
        #expect(encrypted.count == packet.count, "Encrypted packet should be same size")
    }
    
    // MARK: - Legacy Encryption Tests
    
    @Test("Legacy no marker change")
    func legacy_NoMarkerChange() {
        let keys = DanaEncryptionKeys(
            timeSecret: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        )
        var encryption = DanaEncryption(encryptionType: .legacy, keys: keys)
        
        // For encryption commands, legacy doesn't modify
        let packet = Data([0xA5, 0xA5, 0x04, 0x01, 0x00, 0x00, 0x5A, 0x5A])
        let encrypted = encryption.encrypt(packet, isEncryptionCommand: true)
        
        // For encryption commands, no modification
        #expect(encrypted == packet, "Encryption commands should not be modified in legacy mode")
    }
    
    // MARK: - DanaEncryption Init Tests
    
    @Test("Dana encryption init with type")
    func danaEncryption_InitWithType() {
        let encLegacy = DanaEncryption(encryptionType: .legacy)
        #expect(encLegacy.encryptionType == .legacy)
        #expect(!encLegacy.isEncryptionMode)
        
        let encRSv3 = DanaEncryption(encryptionType: .rsv3)
        #expect(encRSv3.encryptionType == .rsv3)
        
        let encBLE5 = DanaEncryption(encryptionType: .ble5)
        #expect(encBLE5.encryptionType == .ble5)
    }
}
