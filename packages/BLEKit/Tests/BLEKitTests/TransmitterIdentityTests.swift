// SPDX-License-Identifier: MIT
//
// TransmitterIdentityTests.swift
// BLEKitTests
//
// Unit tests for Dexcom transmitter identity types.
// Trace: PRD-007 REQ-SIM-002

import Testing
import Foundation
@testable import BLEKit

// MARK: - TransmitterType Tests

@Suite("TransmitterType Tests")
struct TransmitterTypeTests {
    
    @Test("All types have display names")
    func displayNames() {
        #expect(TransmitterType.g5.displayName == "Dexcom G5")
        #expect(TransmitterType.g6.displayName == "Dexcom G6")
        #expect(TransmitterType.g7.displayName == "Dexcom G7")
    }
    
    @Test("G5 and G6 use FEBC advertisement UUID")
    func g5g6AdvertisementUUID() {
        #expect(TransmitterType.g5.advertisementUUID == .dexcomAdvertisement)
        #expect(TransmitterType.g6.advertisementUUID == .dexcomAdvertisement)
    }
    
    // G7-COEX-FIX-006: G7 also uses FEBC (same as G6), verified against Loop/G7SensorKit
    @Test("G7 uses FEBC advertisement UUID (same as G6)")
    func g7AdvertisementUUID() {
        #expect(TransmitterType.g7.advertisementUUID == .dexcomG7Advertisement)
        #expect(TransmitterType.g7.advertisementUUID == .dexcomAdvertisement)  // Same UUID
    }
    
    @Test("G5 and G6 use AES authentication")
    func g5g6AESAuth() {
        #expect(TransmitterType.g5.usesAESAuthentication == true)
        #expect(TransmitterType.g6.usesAESAuthentication == true)
    }
    
    @Test("G7 does not use AES authentication")
    func g7NoAESAuth() {
        #expect(TransmitterType.g7.usesAESAuthentication == false)
    }
    
    @Test("Default firmware versions")
    func defaultFirmware() {
        #expect(TransmitterType.g5.defaultFirmwareVersion == "1.0.4.10")
        #expect(TransmitterType.g6.defaultFirmwareVersion == "1.6.5.25")
        #expect(TransmitterType.g7.defaultFirmwareVersion == "2.18.2.67")
    }
    
    @Test("TransmitterType is codable")
    func codable() throws {
        let type = TransmitterType.g6
        let encoded = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(TransmitterType.self, from: encoded)
        #expect(decoded == type)
    }
    
    @Test("All cases iterable")
    func allCases() {
        #expect(TransmitterType.allCases.count == 3)
    }
}

// MARK: - SimulatorTransmitterID Tests

@Suite("SimulatorTransmitterID Tests")
struct SimulatorTransmitterIDTests {
    
    @Test("Valid 6-character ID")
    func validID() {
        let id = SimulatorTransmitterID("8G1234")
        #expect(id != nil)
        #expect(id?.rawValue == "8G1234")
    }
    
    @Test("ID is uppercased")
    func uppercased() {
        let id = SimulatorTransmitterID("8g1234")
        #expect(id?.rawValue == "8G1234")
    }
    
    @Test("Whitespace is trimmed")
    func trimmed() {
        let id = SimulatorTransmitterID(" 8G1234 ")
        #expect(id?.rawValue == "8G1234")
    }
    
    @Test("Too short ID is rejected")
    func tooShort() {
        let id = SimulatorTransmitterID("8G123")
        #expect(id == nil)
    }
    
    @Test("Too long ID is rejected")
    func tooLong() {
        let id = SimulatorTransmitterID("8G12345")
        #expect(id == nil)
    }
    
    @Test("Non-alphanumeric characters rejected")
    func invalidChars() {
        #expect(SimulatorTransmitterID("8G-234") == nil)
        #expect(SimulatorTransmitterID("8G 234") == nil)
        #expect(SimulatorTransmitterID("8G.234") == nil)
    }
    
    @Test("8 prefix detects G6")
    func detectG6() {
        let id = SimulatorTransmitterID("8HABCD")
        #expect(id?.detectedType == .g6)
    }
    
    @Test("4 prefix detects G7")
    func detectG7With4() {
        let id = SimulatorTransmitterID("4P1234")
        #expect(id?.detectedType == .g7)
    }
    
    @Test("9 prefix detects G7 ONE")
    func detectG7With9() {
        let id = SimulatorTransmitterID("9N1234")
        #expect(id?.detectedType == .g7)
    }
    
    @Test("Other prefixes detect G5")
    func detectG5() {
        #expect(SimulatorTransmitterID("0A1234")?.detectedType == .g5)
        #expect(SimulatorTransmitterID("1B1234")?.detectedType == .g5)
        #expect(SimulatorTransmitterID("5C1234")?.detectedType == .g5)
    }
    
    @Test("Advertisement name uses last 2 chars")
    func advertisementName() {
        #expect(SimulatorTransmitterID("8G1234")?.advertisementName == "Dexcom34")
        #expect(SimulatorTransmitterID("4PABCD")?.advertisementName == "DexcomCD")
    }
    
    @Test("Suffix returns last 2 chars")
    func suffix() {
        #expect(SimulatorTransmitterID("8GXYZ9")?.suffix == "Z9")
    }
    
    @Test("Prefix returns first char")
    func prefix() {
        #expect(SimulatorTransmitterID("8G1234")?.prefix == "8")
    }
    
    @Test("Random G6 has 8 prefix")
    func randomG6() {
        let id = SimulatorTransmitterID.random(type: .g6)
        #expect(id.prefix == "8")
        #expect(id.detectedType == .g6)
    }
    
    @Test("Random G7 has 4 or 9 prefix")
    func randomG7() {
        let id = SimulatorTransmitterID.random(type: .g7)
        #expect(id.prefix == "4" || id.prefix == "9")
        #expect(id.detectedType == .g7)
    }
    
    @Test("Random ID is always 6 chars")
    func randomLength() {
        for type in TransmitterType.allCases {
            let id = SimulatorTransmitterID.random(type: type)
            #expect(id.rawValue.count == 6)
        }
    }
    
    @Test("Explicit type override")
    func typeOverride() {
        // Create with G5 ID but force G6 type
        let id = SimulatorTransmitterID("0A1234", type: .g6)
        #expect(id?.detectedType == .g6)
    }
    
    @Test("SimulatorTransmitterID is codable")
    func codable() throws {
        let id = SimulatorTransmitterID("8G1234")!
        let encoded = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(SimulatorTransmitterID.self, from: encoded)
        #expect(decoded == id)
    }
    
    @Test("SimulatorTransmitterID is hashable")
    func hashable() {
        let id1 = SimulatorTransmitterID("8G1234")!
        let id2 = SimulatorTransmitterID("8G1234")!
        let id3 = SimulatorTransmitterID("8G5678")!
        
        #expect(id1 == id2)
        #expect(id1 != id3)
        
        var set: Set<SimulatorTransmitterID> = []
        set.insert(id1)
        set.insert(id2)
        #expect(set.count == 1)
    }
}

// MARK: - FirmwareVersion Tests

@Suite("FirmwareVersion Tests")
struct FirmwareVersionTests {
    
    @Test("Parse valid version string")
    func parseValid() {
        let version = FirmwareVersion("1.6.5.25")
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 6)
        #expect(version?.patch == 5)
        #expect(version?.build == 25)
    }
    
    @Test("Invalid version strings rejected")
    func parseInvalid() {
        #expect(FirmwareVersion("1.6.5") == nil)  // Too few parts
        #expect(FirmwareVersion("1.6.5.25.1") == nil)  // Too many parts
        #expect(FirmwareVersion("1.6.5.abc") == nil)  // Non-numeric
        #expect(FirmwareVersion("1.6") == nil)
    }
    
    @Test("Version description")
    func description() {
        let version = FirmwareVersion(major: 2, minor: 18, patch: 2, build: 67)
        #expect(version.description == "2.18.2.67")
    }
    
    @Test("Version bytes")
    func bytes() {
        let version = FirmwareVersion(major: 1, minor: 6, patch: 5, build: 25)
        #expect(version.bytes == Data([1, 6, 5, 25]))
    }
    
    @Test("Version comparison")
    func comparison() {
        let v1 = FirmwareVersion("1.5.0.0")!
        let v2 = FirmwareVersion("1.6.0.0")!
        let v3 = FirmwareVersion("1.6.5.25")!
        let v4 = FirmwareVersion("2.0.0.0")!
        
        #expect(v1 < v2)
        #expect(v2 < v3)
        #expect(v3 < v4)
        #expect(v4 > v1)
    }
    
    @Test("FirmwareVersion is codable")
    func codable() throws {
        let version = FirmwareVersion("1.6.5.25")!
        let encoded = try JSONEncoder().encode(version)
        let decoded = try JSONDecoder().decode(FirmwareVersion.self, from: encoded)
        #expect(decoded == version)
    }
}

// MARK: - SimulatorTransmitterConfig Tests

@Suite("SimulatorTransmitterConfig Tests")
struct SimulatorTransmitterConfigTests {
    
    @Test("Create with ID only")
    func createWithID() {
        let id = SimulatorTransmitterID("8G1234")!
        let config = SimulatorTransmitterConfig(id: id)
        
        #expect(config.id == id)
        #expect(config.type == .g6)
        #expect(config.serialNumber.count == 10)
        #expect(config.firmwareVersion == FirmwareVersion("1.6.5.25")!)
    }
    
    @Test("Create with all parameters")
    func createWithAll() {
        let id = SimulatorTransmitterID("4P5678")!
        let config = SimulatorTransmitterConfig(
            id: id,
            serialNumber: "1234567890",
            firmwareVersion: FirmwareVersion("2.18.2.67"),
            type: .g7,
            activationDate: Date(timeIntervalSince1970: 0)
        )
        
        #expect(config.serialNumber == "1234567890")
        #expect(config.firmwareVersion.description == "2.18.2.67")
        #expect(config.type == .g7)
    }
    
    @Test("G6 preset")
    func g6Preset() {
        let config = SimulatorTransmitterConfig.g6(id: "8HABCD")
        #expect(config != nil)
        #expect(config?.type == .g6)
        #expect(config?.id.rawValue == "8HABCD")
    }
    
    @Test("G7 preset")
    func g7Preset() {
        let config = SimulatorTransmitterConfig.g7(id: "4PWXYZ")
        #expect(config != nil)
        #expect(config?.type == .g7)
    }
    
    @Test("Random config")
    func randomConfig() {
        let config = SimulatorTransmitterConfig.random(type: .g6)
        #expect(config.type == .g6)
        #expect(config.id.rawValue.count == 6)
    }
    
    @Test("Advertisement data")
    func advertisementData() {
        let config = SimulatorTransmitterConfig.g6(id: "8G1234")!
        let ad = config.advertisementData
        
        #expect(ad.localName == "Dexcom34")
        #expect(ad.serviceUUIDs.contains(.dexcomAdvertisement))
    }
    
    @Test("Session age calculation")
    func sessionAge() {
        let pastDate = Date().addingTimeInterval(-3600)  // 1 hour ago
        let id = SimulatorTransmitterID("8G1234")!
        let config = SimulatorTransmitterConfig(id: id, activationDate: pastDate)
        
        #expect(config.sessionAge >= 3600)
        #expect(config.sessionAge < 3610)  // Allow small tolerance
    }
    
    @Test("Session days calculation")
    func sessionDays() {
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86400)
        let id = SimulatorTransmitterID("8G1234")!
        let config = SimulatorTransmitterConfig(id: id, activationDate: threeDaysAgo)
        
        #expect(config.sessionDays == 3)
    }
    
    @Test("SimulatorTransmitterConfig is codable")
    func codable() throws {
        let config = SimulatorTransmitterConfig.g6(id: "8G1234")!
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SimulatorTransmitterConfig.self, from: encoded)
        
        #expect(decoded.id == config.id)
        #expect(decoded.type == config.type)
        #expect(decoded.serialNumber == config.serialNumber)
    }
}

// MARK: - TransmitterState Tests

@Suite("TransmitterState Tests")
struct TransmitterStateTests {
    
    @Test("All states exist")
    func allStates() {
        let states: [TransmitterState] = [.inactive, .warmup, .active, .expired, .lowBattery, .error]
        #expect(states.count == 6)
    }
    
    @Test("State is codable")
    func codable() throws {
        let state = TransmitterState.active
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TransmitterState.self, from: encoded)
        #expect(decoded == state)
    }
}

// MARK: - SensorSession Tests

@Suite("SensorSession Tests")
struct SensorSessionTests {
    
    @Test("G6 warmup is 2 hours")
    func g6Warmup() {
        let session = SensorSession(transmitterType: .g6)
        #expect(session.warmupDuration == 2 * 60 * 60)
    }
    
    @Test("G7 warmup is 30 minutes")
    func g7Warmup() {
        let session = SensorSession(transmitterType: .g7)
        #expect(session.warmupDuration == 30 * 60)
    }
    
    @Test("G6 max session is 10 days")
    func g6MaxSession() {
        let session = SensorSession(transmitterType: .g6)
        #expect(session.maxSessionDuration == 10 * 24 * 60 * 60)
    }
    
    @Test("G7 max session is 10.5 days")
    func g7MaxSession() {
        let session = SensorSession(transmitterType: .g7)
        #expect(session.maxSessionDuration == 10.5 * 24 * 60 * 60)
    }
    
    @Test("New session starts in warmup")
    func startsInWarmup() {
        let session = SensorSession()
        #expect(session.state == .warmup)
    }
    
    @Test("Elapsed time calculation")
    func elapsedTime() {
        let pastStart = Date().addingTimeInterval(-600)  // 10 min ago
        let session = SensorSession(startTime: pastStart)
        
        #expect(session.elapsed >= 600)
        #expect(session.elapsed < 610)
    }
    
    @Test("Warmup complete detection")
    func warmupComplete() {
        // Session started 3 hours ago (past 2hr warmup)
        let pastStart = Date().addingTimeInterval(-3 * 60 * 60)
        let session = SensorSession(startTime: pastStart, transmitterType: .g6)
        
        #expect(session.isWarmupComplete == true)
    }
    
    @Test("Warmup not complete")
    func warmupNotComplete() {
        // Session started 1 hour ago (still in 2hr warmup)
        let pastStart = Date().addingTimeInterval(-1 * 60 * 60)
        let session = SensorSession(startTime: pastStart, transmitterType: .g6)
        
        #expect(session.isWarmupComplete == false)
    }
    
    @Test("Session expired detection")
    func expired() {
        // Session started 11 days ago (past 10 day max)
        let pastStart = Date().addingTimeInterval(-11 * 24 * 60 * 60)
        let session = SensorSession(startTime: pastStart, transmitterType: .g6)
        
        #expect(session.isExpired == true)
    }
    
    @Test("Remaining time calculation")
    func remainingTime() {
        // Session started 5 days ago
        let pastStart = Date().addingTimeInterval(-5 * 24 * 60 * 60)
        let session = SensorSession(startTime: pastStart, transmitterType: .g6)
        
        // Should have ~5 days remaining
        let fiveDays = 5.0 * 24 * 60 * 60
        #expect(session.remainingTime > fiveDays - 100)
        #expect(session.remainingTime < fiveDays + 100)
    }
    
    @Test("Update state transitions warmup to active")
    func updateStateWarmupToActive() {
        // Session started 3 hours ago
        let pastStart = Date().addingTimeInterval(-3 * 60 * 60)
        var session = SensorSession(startTime: pastStart, state: .warmup, transmitterType: .g6)
        
        session.updateState()
        
        #expect(session.state == .active)
    }
    
    @Test("Update state sets expired")
    func updateStateExpired() {
        // Session started 11 days ago
        let pastStart = Date().addingTimeInterval(-11 * 24 * 60 * 60)
        var session = SensorSession(startTime: pastStart, state: .active, transmitterType: .g6)
        
        session.updateState()
        
        #expect(session.state == .expired)
    }
    
    @Test("SensorSession is codable")
    func codable() throws {
        let session = SensorSession(transmitterType: .g7)
        let encoded = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(SensorSession.self, from: encoded)
        
        #expect(decoded.state == session.state)
        #expect(decoded.warmupDuration == session.warmupDuration)
    }
}
