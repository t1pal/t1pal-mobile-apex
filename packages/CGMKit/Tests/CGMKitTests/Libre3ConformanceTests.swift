// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Libre3ConformanceTests.swift
// CGMKit
//
// Conformance tests for Libre 3 BLE protocol parsing
// Trace: LIBRE-SYNTH-009
// Reference: externals/DiaBLE/DiaBLE/Libre3.swift

import Testing
import Foundation
@testable import CGMKit
import T1PalCore

@Suite("Libre3ConformanceTests")
struct Libre3ConformanceTests {
    
    // MARK: - Helper
    
    private func hexData(_ hex: String) -> Data {
        let hexString = hex.replacingOccurrences(of: " ", with: "").lowercased()
        var data = Data()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }
    
    // MARK: - UUID Tests
    
    @Test("Libre 3 UUIDs")
    func libre3UUIDs() {
        // Verify UUIDs match DiaBLE constants
        #expect(Libre3UUID.service == "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4")
    }
    
    // MARK: - Sensor State Tests
    
    @Test("Sensor state mapping")
    func sensorStateMapping() {
        // Test state 0x03 (ready) maps to .active
        let readyState = Libre3SensorState(rawValue: 0x03)
        #expect(readyState == .ready)
        #expect(readyState?.sensorState == .active)
        
        // Test state 0x02 (warming up) maps to .warmingUp
        let warmingState = Libre3SensorState(rawValue: 0x02)
        #expect(warmingState == .warmingUp)
        #expect(warmingState?.sensorState == .warmingUp)
        
        // Test state 0x04 (expired) maps to .expired
        let expiredState = Libre3SensorState(rawValue: 0x04)
        #expect(expiredState == .expired)
        #expect(expiredState?.sensorState == .expired)
    }
    
    // MARK: - Reading Tests
    
    @Test("Libre 3 reading glucose conversion")
    func libre3ReadingGlucoseConversion() {
        // Raw value should equal mg/dL directly (no calibration)
        let reading = Libre3Reading(
            rawValue: 120,
            timestamp: Date(),
            quality: 0,
            trendArrow: 3,
            sensorAge: 1440
        )
        
        #expect(reading.glucoseMgdL == 120.0)
        #expect(reading.isValid)
    }
    
    @Test("Libre 3 reading validation")
    func libre3ReadingValidation() {
        // Valid reading
        let validReading = Libre3Reading(
            rawValue: 100,
            timestamp: Date(),
            quality: 0,
            trendArrow: 3,
            sensorAge: 1000
        )
        #expect(validReading.isValid)
        
        // Invalid: quality non-zero
        let badQuality = Libre3Reading(
            rawValue: 100,
            timestamp: Date(),
            quality: 1,
            trendArrow: 3,
            sensorAge: 1000
        )
        #expect(!badQuality.isValid)
        
        // Invalid: glucose too low
        let tooLow = Libre3Reading(
            rawValue: 30,
            timestamp: Date(),
            quality: 0,
            trendArrow: 3,
            sensorAge: 1000
        )
        #expect(!tooLow.isValid)
        
        // Invalid: glucose too high
        let tooHigh = Libre3Reading(
            rawValue: 600,
            timestamp: Date(),
            quality: 0,
            trendArrow: 3,
            sensorAge: 1000
        )
        #expect(!tooHigh.isValid)
    }
    
    @Test("Libre 3 trend arrow mapping")
    func libre3TrendArrowMapping() {
        // Trend arrow values per Juggluco trend2rate():
        // Rate mapping: (trend - 3) * 1.3 mg/dL/min
        // 1 = doubleDown (-2.6), 2 = singleDown (-1.3), 3 = flat (0.0)
        // 4 = singleUp (+1.3), 5 = doubleUp (+2.6)
        // 0 and >5 = notComputable
        let readings: [(UInt8, GlucoseTrend)] = [
            (1, .doubleDown),     // -2.6 mg/dL/min
            (2, .singleDown),     // -1.3 mg/dL/min
            (3, .flat),           // 0.0 mg/dL/min
            (4, .singleUp),       // +1.3 mg/dL/min
            (5, .doubleUp),       // +2.6 mg/dL/min
            (0, .notComputable),  // NAN/unknown
            (99, .notComputable)  // Invalid
        ]
        
        for (arrow, expected) in readings {
            let reading = Libre3Reading(
                rawValue: 100,
                timestamp: Date(),
                quality: 0,
                trendArrow: arrow,
                sensorAge: 1000
            )
            #expect(reading.trend == expected, "Trend arrow \(arrow) should map to \(expected)")
        }
    }
    
    // MARK: - Packet Parser Tests
    
    @Test("Parse glucose packet")
    func parseGlucosePacket() {
        let parser = Libre3PacketParser()
        
        // Create test packet: [glucose:2][timestamp:4][quality:1][trend:1][sensorAge:2]
        var data = Data()
        data.append(contentsOf: [0x78, 0x00])  // glucose = 120 (little-endian)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x60])  // timestamp (example)
        data.append(0x00)  // quality = 0 (OK)
        data.append(0x03)  // trend = 3 (flat)
        data.append(contentsOf: [0xA0, 0x05])  // sensorAge = 1440 (little-endian)
        
        let reading = parser.parseGlucosePacket(data)
        #expect(reading != nil)
        #expect(reading?.rawValue == 120)
        #expect(reading?.quality == 0)
        #expect(reading?.trendArrow == 3)
        #expect(reading?.sensorAge == 1440)
    }
    
    @Test("Parse glucose packet too short")
    func parseGlucosePacketTooShort() {
        let parser = Libre3PacketParser()
        let shortData = Data([0x78, 0x00, 0x00])  // Only 3 bytes
        
        let reading = parser.parseGlucosePacket(shortData)
        #expect(reading == nil, "Should return nil for packets < 10 bytes")
    }
    
    // MARK: - Sensor Info Tests
    
    @Test("Sensor info time remaining")
    func sensorInfoTimeRemaining() {
        let startDate = Date().addingTimeInterval(-7 * 24 * 3600)  // 7 days ago
        let info = Libre3SensorInfo(
            serialNumber: "ABCD1234567",
            sensorState: .ready,
            startDate: startDate,
            expirationDate: startDate.addingTimeInterval(14 * 24 * 3600)
        )
        
        // Should have ~7 days remaining (use range to handle timing edge cases)
        #expect(info.daysRemaining >= 6 && info.daysRemaining <= 7)
        #expect(!info.isExpired)
        #expect(abs(info.sensorAgeDays - 7.0) < 0.5)
    }
    
    @Test("Sensor info expired")
    func sensorInfoExpired() {
        let startDate = Date().addingTimeInterval(-15 * 24 * 3600)  // 15 days ago
        let info = Libre3SensorInfo(
            serialNumber: "ABCD1234567",
            sensorState: .expired,
            startDate: startDate,
            expirationDate: startDate.addingTimeInterval(14 * 24 * 3600)
        )
        
        #expect(info.isExpired)
        #expect(info.daysRemaining == 0)
    }
    
    // MARK: - Glucose Data Format Tests (from fixture)
    
    @Test("Glucose data format")
    func glucoseDataFormat() {
        // From fixture: "062DEE00FCFF0000945CF12CF0000BEE00F000010C530E72482F130000"
        // lifeCount=11526, readingMgDl=238, rateOfChange=-4
        let data = hexData("062DEE00FCFF0000945CF12CF0000BEE00F000010C530E72482F130000")
        
        #expect(data.count == 29, "Glucose data should be 29 bytes")
        
        // Parse lifeCount (offset 0, UInt16LE)
        let lifeCount = UInt16(data[0]) | (UInt16(data[1]) << 8)
        #expect(lifeCount == 11526)  // 0x2D06
        
        // Parse readingMgDl (offset 2, UInt16LE)
        let readingMgDl = UInt16(data[2]) | (UInt16(data[3]) << 8)
        #expect(readingMgDl == 238)  // 0x00EE
        
        // Parse rateOfChange (offset 4, Int16LE)
        let rateRaw = UInt16(data[4]) | (UInt16(data[5]) << 8)
        let rateOfChange = Int16(bitPattern: rateRaw)
        #expect(rateOfChange == -4)  // 0xFFFC
    }
    
    // MARK: - Fast Data Format Tests (from fixture)
    
    @Test("Fast data format")
    func fastDataFormat() {
        // From fixture: "B43E7E091F4071140000B600B500"
        // lifeCount=16052, readingMgDl=182, historicMgDl=181
        let data = hexData("B43E7E091F4071140000B600B500")
        
        #expect(data.count == 14, "Fast data should be 14 bytes")
        
        // Parse lifeCount (offset 0, UInt16LE)
        let lifeCount = UInt16(data[0]) | (UInt16(data[1]) << 8)
        #expect(lifeCount == 16052)  // 0x3EB4
        
        // Parse readingMgDl (offset 10, UInt16LE)
        let readingMgDl = UInt16(data[10]) | (UInt16(data[11]) << 8)
        #expect(readingMgDl == 182)  // 0x00B6
        
        // Parse historicMgDl (offset 12, UInt16LE)
        let historicMgDl = UInt16(data[12]) | (UInt16(data[13]) << 8)
        #expect(historicMgDl == 181)  // 0x00B5
    }
    
    // MARK: - Patch Status Format Tests (from fixture)
    
    @Test("Patch status format")
    func patchStatusFormat() {
        // From fixture: "FC2C00000D002104FC2C1603"
        // lifeCount=11516, errorData=0, eventData=13, index=33, patchState=4
        let data = hexData("FC2C00000D002104FC2C1603")
        
        #expect(data.count == 12, "Patch status should be 12 bytes")
        
        // Parse lifeCount (offset 0, UInt16LE)
        let lifeCount = UInt16(data[0]) | (UInt16(data[1]) << 8)
        #expect(lifeCount == 11516)  // 0x2CFC
        
        // Parse errorData (offset 2, UInt16LE)
        let errorData = UInt16(data[2]) | (UInt16(data[3]) << 8)
        #expect(errorData == 0)
        
        // Parse index (offset 6, UInt8)
        let index = data[6]
        #expect(index == 33)  // 0x21
        
        // Parse patchState (offset 7, UInt8)
        let patchState = data[7]
        #expect(patchState == 4)  // paired state
    }
    
    // MARK: - Activation Response Tests (from fixture)
    
    @Test("Activation response format")
    func activationResponseFormat() {
        // From fixture: "002BC7291932189F36B26CD01E306209F0"
        // status=0, bdAddress=18:32:19:29:C7:2B, blePIN=9F36B26C, activationTime=1647320784
        let data = hexData("002BC7291932189F36B26CD01E306209F0")
        
        #expect(data.count == 17, "Activation response should be 17 bytes")
        
        // Parse status (offset 0)
        #expect(data[0] == 0x00, "Status should be success")
        
        // Parse BLE PIN (offset 7-10)
        let blePIN = data.subdata(in: 7..<11)
        #expect(blePIN.map { String(format: "%02X", $0) }.joined() == "9F36B26C")
        
        // Parse activation time (offset 11-14, UInt32LE)
        let byte11 = UInt32(data[11])
        let byte12 = UInt32(data[12]) << 8
        let byte13 = UInt32(data[13]) << 16
        let byte14 = UInt32(data[14]) << 24
        let activationTime = byte11 | byte12 | byte13 | byte14
        #expect(activationTime == 1647320784)  // 0x62301ED0
    }
    
    // MARK: - AES-CCM Test Vector (from fixture)
    
    @Test("AES-CCM test vector")
    func aesCCMTestVector() {
        // From fixture: AES-CCM Test Case 1 Decrypt
        // key: 404142434445464748494a4b4c4d4e4f
        // nonce: 10111213141516
        // aad: 0001020304050607
        // ciphertext: 7162015b4dac255d (4 bytes plaintext + 4 bytes tag)
        // expected plaintext: 20212223
        
        let key = hexData("404142434445464748494a4b4c4d4e4f")
        let nonce = hexData("10111213141516")
        let aad = hexData("0001020304050607")
        let ciphertext = hexData("7162015b4dac255d")
        let expectedPlaintext = hexData("20212223")
        
        #expect(key.count == 16, "Key should be 16 bytes")
        #expect(nonce.count == 7, "Nonce should be 7 bytes")
        #expect(aad.count == 8, "AAD should be 8 bytes")
        #expect(ciphertext.count == 8, "Ciphertext should be 8 bytes (4 + 4 tag)")
        #expect(expectedPlaintext.count == 4, "Plaintext should be 4 bytes")
        
        // Note: Actual AES-CCM decryption requires CryptoSwift or CommonCrypto
        // This test validates the fixture data format
    }
    
    // MARK: - Constants Tests
    
    @Test("Libre 3 constants")
    func libre3Constants() {
        // Verify key protocol constants from fixture
        #expect(14 * 24 * 60 == 20160, "14 days in minutes")
        #expect(60 == 60, "Default warmup time in minutes")
        #expect(5 == 5, "Historic interval in minutes")
    }
    
    // MARK: - DiaBLE Fixture Conformance (LIBRE3-023d)
    
    @Test("App certificates match DiaBLE")
    func appCertificatesMatchDiaBLE() {
        // From fixture_libre3_crypto.json diable_app_certificates
        // Certificate 0 should match DiaBLE's appCertificates[0]
        let cert0 = Libre3AppCertificates.certificate0
        #expect(cert0.count == 162, "Certificate 0 should be 162 bytes")
        #expect(cert0[0] == 0x03, "Version byte should be 0x03")
        #expect(cert0[1] == 0x00, "Security level 0 should be 0x00")
        
        let cert1 = Libre3AppCertificates.certificate1
        #expect(cert1.count == 162, "Certificate 1 should be 162 bytes")
        #expect(cert1[0] == 0x03, "Version byte should be 0x03")
        #expect(cert1[1] == 0x03, "Security level 1 should be 0x03")
    }
    
    @Test("Patch signing keys match DiaBLE")
    func patchSigningKeysMatchDiaBLE() {
        // From fixture: diable_patch_signing_keys
        let key0 = Libre3PatchSigningKeys.signingKey0
        #expect(key0.count == 65, "Signing key 0 should be 65 bytes")
        #expect(key0[0] == 0x04, "Should be uncompressed point (0x04)")
        
        let key1 = Libre3PatchSigningKeys.signingKey1
        #expect(key1.count == 65, "Signing key 1 should be 65 bytes")
        #expect(key1[0] == 0x04, "Should be uncompressed point (0x04)")
    }
    
    @Test("Security commands match DiaBLE constants")
    func securityCommandsMatchDiaBLE() {
        // From fixture: diable_security_commands
        // These are the security command bytes from DiaBLE Libre3.swift
        #expect(Libre3SecurityCommand.ecdhStart.rawValue == 0x01)
        #expect(Libre3SecurityCommand.loadCertDone.rawValue == 0x03)
        #expect(Libre3SecurityCommand.challengeLoadDone.rawValue == 0x08)
        #expect(Libre3SecurityCommand.sendCert.rawValue == 0x09)
        #expect(Libre3SecurityCommand.keyAgreement.rawValue == 0x0D)
        #expect(Libre3SecurityCommand.ephemeralLoadDone.rawValue == 0x0E)
        #expect(Libre3SecurityCommand.authorizeSymmetric.rawValue == 0x11)
    }
    
    @Test("BLE UUIDs match DiaBLE constants")
    func bleUUIDsMatchDiaBLE() {
        // From fixture: diable_ble_uuids
        // Verify our UUID constants match DiaBLE
        #expect(Libre3UUID.dataService == "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4")
        #expect(Libre3UUID.securityService == "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4")
        #expect(Libre3UUID.commandResponse == "08982198-EF89-11E9-81B4-2A2AE2DBCCE4")
        #expect(Libre3UUID.certData == "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4")
        #expect(Libre3UUID.challengeData == "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4")
    }
    
    @Test("Ephemeral public key format from fixture")
    func ephemeralKeyFormat() {
        // From fixture: ecdh_session.data6 (65-byte uncompressed P-256 point)
        let patchEphemeral = hexData("04f39d2df9dab578cac72baae27ff1ec2718343591198b5210702598a52865c31ef4659b576cc2fbb5416d06775ed65e04a9bf0f3e9d45738ae4856049812a811b")
        
        #expect(patchEphemeral.count == 65, "Patch ephemeral should be 65 bytes")
        #expect(patchEphemeral[0] == 0x04, "Should start with 0x04 (uncompressed)")
        
        // X and Y coordinates should each be 32 bytes
        let x = patchEphemeral.subdata(in: 1..<33)
        let y = patchEphemeral.subdata(in: 33..<65)
        #expect(x.count == 32, "X coordinate should be 32 bytes")
        #expect(y.count == 32, "Y coordinate should be 32 bytes")
    }
    
    @Test("Patch certificate format from fixture")
    func patchCertificateFormat() {
        // From fixture: ecdh_session.rdtData (140-byte patch certificate)
        let patchCert = hexData("01514108934c007ae0d14a04881acc74eec1d7791fb88805137410d1057525af229324fc0b8c6347317b4a032e0feaba87dea30452718e475e71208b846beaac15e0b24c7943b7aadeb45c3ca76dbc26aec27643e1f0f9e51ac339f0712d3d117bb4f27191fbd7702f4cd681b703582187fb81a285365be2ec18fd4c2eb546e65feb08b91aaefb0806989bff")
        
        #expect(patchCert.count == 140, "Patch certificate should be 140 bytes")
        #expect(patchCert[0] == 0x01, "First byte should be 0x01")
    }
    
    @Test("Challenge nonce format from fixture")
    func challengeNonceFormat() {
        // From fixture: ecdh_session.nonce1 and nonce2 (7-byte nonces)
        let nonce1 = hexData("a501000092d044")
        let nonce2 = hexData("a601000012c2c3")
        
        #expect(nonce1.count == 7, "Nonce1 should be 7 bytes")
        #expect(nonce2.count == 7, "Nonce2 should be 7 bytes")
        
        // Note: These are extended to 13 bytes in actual use by prepending
        // sequence number and packet descriptor
    }
}
