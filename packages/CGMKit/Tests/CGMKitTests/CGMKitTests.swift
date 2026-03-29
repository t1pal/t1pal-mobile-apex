// SPDX-License-Identifier: MIT
//
// CGMKitTests.swift
// T1Pal Mobile

import Testing
import Foundation
@testable import CGMKit
import T1PalCore

@Test func testSensorState() {
    #expect(SensorState.active.rawValue == "active")
    #expect(SensorState.warmingUp.rawValue == "warmingUp")
    #expect(SensorState.expired.rawValue == "expired")
}

@Test func testCGMType() {
    let g7: CGMKit.CGMType = .dexcomG7
    let sim: CGMKit.CGMType = .simulation
    let nsFollow: CGMKit.CGMType = .nightscoutFollower
    let share: CGMKit.CGMType = .dexcomShare
    #expect(g7.rawValue == "dexcomG7")
    #expect(sim.rawValue == "simulation")
    #expect(nsFollow.rawValue == "nightscoutFollower")
    #expect(share.rawValue == "dexcomShare")
}

@Test func testSensorInfo() {
    let info = SensorInfo(id: "test-123", name: "Test Sensor", type: .simulation)
    #expect(info.id == "test-123")
    #expect(info.name == "Test Sensor")
    #expect(info.type == .simulation)
}

@Test func testCGMError() {
    let error = CGMError.sensorExpired
    #expect(error == .sensorExpired)
}

// MARK: - Dexcom Share Tests

@Test func testDexcomShareServer() {
    #expect(DexcomShareServer.us.rawValue == "share2.dexcom.com")
    #expect(DexcomShareServer.ous.rawValue == "shareous1.dexcom.com")
}

@Test func testDexcomShareCredentials() {
    let creds = DexcomShareCredentials(
        username: "test@example.com",
        password: "secret",
        server: .us
    )
    #expect(creds.username == "test@example.com")
    #expect(creds.password == "secret")
    #expect(creds.server == .us)
}

@Test func testDexcomShareGlucoseParsing() {
    // Test parsing of Dexcom's weird timestamp format
    let glucose = DexcomShareGlucose(
        WT: "/Date(1706817600000)/",  // 2024-02-01 16:00:00 UTC
        ST: "/Date(1706817600000)/",
        DT: "/Date(1706817600000)/",
        Value: 120,
        Trend: 4  // Flat
    )
    
    let reading = glucose.toGlucoseReading()
    #expect(reading != nil)
    #expect(reading?.glucose == 120)
    #expect(reading?.trend == .flat)
    #expect(reading?.source == "DexcomShare")
}

@Test func testDexcomShareTrendMapping() {
    // Test all trend values
    let trends: [(Int, GlucoseTrend)] = [
        (1, .doubleUp),
        (2, .singleUp),
        (3, .fortyFiveUp),
        (4, .flat),
        (5, .fortyFiveDown),
        (6, .singleDown),
        (7, .doubleDown),
        (0, .notComputable),
        (99, .notComputable)
    ]
    
    for (dexcomTrend, expectedTrend) in trends {
        let glucose = DexcomShareGlucose(
            WT: "/Date(1706817600000)/",
            ST: "/Date(1706817600000)/",
            DT: "/Date(1706817600000)/",
            Value: 100,
            Trend: dexcomTrend
        )
        let reading = glucose.toGlucoseReading()
        #expect(reading?.trend == expectedTrend, "Trend \(dexcomTrend) should map to \(expectedTrend)")
    }
}

@Test func testDexcomShareError() {
    let error = DexcomShareError.invalidCredentials
    switch error {
    case .invalidCredentials:
        #expect(true)
    default:
        #expect(Bool(false), "Expected invalidCredentials")
    }
}

// MARK: - Nightscout Follower Tests

@Test func testNightscoutFollowerConfig() {
    let config = NightscoutFollowerConfig(
        url: URL(string: "https://example.fly.dev")!,
        apiSecret: "mysecret",
        token: nil,
        fetchIntervalSeconds: 120
    )
    #expect(config.url.absoluteString == "https://example.fly.dev")
    #expect(config.apiSecret == "mysecret")
    #expect(config.token == nil)
    #expect(config.fetchIntervalSeconds == 120)
}

@Test func testNightscoutFollowerConfigDefaults() {
    let config = NightscoutFollowerConfig(url: URL(string: "https://ns.example.com")!)
    #expect(config.apiSecret == nil)
    #expect(config.token == nil)
    #expect(config.fetchIntervalSeconds == 60)
}

// MARK: - Libre 3 Tests

@Test func testLibre3UUIDs() {
    // Note: Legacy aliases point to new canonical names from LIBRE3-009
    // service → dataService, control → patchControl, auth → commandResponse
    #expect(Libre3UUID.service == "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4")
    #expect(Libre3UUID.glucoseData == "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4")
    #expect(Libre3UUID.control == "08981338-EF89-11E9-81B4-2A2AE2DBCCE4")
    #expect(Libre3UUID.auth == "08982198-EF89-11E9-81B4-2A2AE2DBCCE4")
}

@Test func testLibre3SensorStateMapping() {
    #expect(Libre3SensorState.notActivated.sensorState == .notStarted)
    #expect(Libre3SensorState.warmingUp.sensorState == .warmingUp)
    #expect(Libre3SensorState.ready.sensorState == .active)
    #expect(Libre3SensorState.expired.sensorState == .expired)
    #expect(Libre3SensorState.shutdown.sensorState == .stopped)
    #expect(Libre3SensorState.failure.sensorState == .failed)
}

@Test func testLibre3ReadingCreation() {
    let reading = Libre3Reading(
        rawValue: 120,
        timestamp: Date(),
        quality: 0,
        trendArrow: 3,
        sensorAge: 1440
    )
    
    #expect(reading.glucoseMgdL == 120.0)
    #expect(reading.isValid)
    #expect(reading.trend == .flat)
}

@Test func testLibre3ReadingValidity() {
    // Invalid - quality not 0
    let badQuality = Libre3Reading(rawValue: 120, timestamp: Date(), quality: 1, trendArrow: 3, sensorAge: 100)
    #expect(!badQuality.isValid)
    
    // Invalid - too low
    let tooLow = Libre3Reading(rawValue: 39, timestamp: Date(), quality: 0, trendArrow: 3, sensorAge: 100)
    #expect(!tooLow.isValid)
    
    // Invalid - too high
    let tooHigh = Libre3Reading(rawValue: 501, timestamp: Date(), quality: 0, trendArrow: 3, sensorAge: 100)
    #expect(!tooHigh.isValid)
    
    // Valid
    let valid = Libre3Reading(rawValue: 120, timestamp: Date(), quality: 0, trendArrow: 3, sensorAge: 100)
    #expect(valid.isValid)
}

@Test func testLibre3ReadingTrends() {
    // Trend mapping from Juggluco trend2rate(): (trend - 3) * 1.3 mg/dL/min
    // 1 = -2.6 (doubleDown), 2 = -1.3 (singleDown), 3 = 0 (flat)
    // 4 = +1.3 (singleUp), 5 = +2.6 (doubleUp)
    let trends: [(UInt8, GlucoseTrend)] = [
        (1, .doubleDown),
        (2, .singleDown),
        (3, .flat),
        (4, .singleUp),
        (5, .doubleUp),
        (0, .notComputable),
        (99, .notComputable)
    ]
    
    for (arrow, expected) in trends {
        let reading = Libre3Reading(rawValue: 100, timestamp: Date(), quality: 0, trendArrow: arrow, sensorAge: 100)
        #expect(reading.trend == expected, "Arrow \(arrow) should map to \(expected)")
    }
}

@Test func testLibre3ReadingToGlucoseReading() {
    let libre3Reading = Libre3Reading(
        rawValue: 145,
        timestamp: Date(),
        quality: 0,
        trendArrow: 4,  // singleUp per Juggluco mapping
        sensorAge: 2880
    )
    
    let glucoseReading = libre3Reading.toGlucoseReading()
    #expect(glucoseReading != nil)
    #expect(glucoseReading?.glucose == 145.0)
    #expect(glucoseReading?.trend == .singleUp)
    #expect(glucoseReading?.source == "Libre3")
}

@Test func testLibre3ReadingToGlucoseReadingInvalid() {
    let invalid = Libre3Reading(rawValue: 30, timestamp: Date(), quality: 0, trendArrow: 3, sensorAge: 100)
    #expect(invalid.toGlucoseReading() == nil)
}

@Test func testLibre3SensorInfo() {
    let start = Date()
    let expiration = start.addingTimeInterval(14 * 24 * 3600)
    
    let info = Libre3SensorInfo(
        serialNumber: "ABC123DEF",
        sensorState: .ready,
        startDate: start,
        expirationDate: expiration,
        firmwareVersion: "1.2"
    )
    
    #expect(info.serialNumber == "ABC123DEF")
    #expect(info.sensorState == .ready)
    #expect(info.firmwareVersion == "1.2")
    #expect(info.daysRemaining >= 13) // Allow for timing variance
    #expect(info.daysRemaining <= 14)
    #expect(!info.isExpired)
}

@Test func testLibre3SensorInfoExpired() {
    let start = Date().addingTimeInterval(-15 * 24 * 3600)
    let expiration = start.addingTimeInterval(14 * 24 * 3600)
    
    let info = Libre3SensorInfo(
        serialNumber: "EXPIRED01",
        sensorState: .expired,
        startDate: start,
        expirationDate: expiration
    )
    
    #expect(info.isExpired)
    #expect(info.daysRemaining == 0)
    #expect(info.timeRemaining == 0)
}

@Test func testLibre3PacketParserGlucose() {
    let parser = Libre3PacketParser()
    
    // Build test packet: rawValue(2) + timestamp(4) + quality(1) + trend(1) + sensorAge(2)
    var data = Data()
    
    // rawValue = 125 (little endian)
    data.append(125)  // low byte
    data.append(0)    // high byte
    
    // timestamp (4 bytes, little endian) - use a known value
    let ts: UInt32 = 1706817600  // 2024-02-01
    data.append(UInt8(ts & 0xFF))
    data.append(UInt8((ts >> 8) & 0xFF))
    data.append(UInt8((ts >> 16) & 0xFF))
    data.append(UInt8((ts >> 24) & 0xFF))
    
    data.append(0)  // quality
    data.append(3)  // trend (flat)
    
    // sensorAge = 1440 (little endian)
    data.append(UInt8(1440 & 0xFF))
    data.append(UInt8((1440 >> 8) & 0xFF))
    
    let reading = parser.parseGlucosePacket(data)
    #expect(reading != nil)
    #expect(reading?.rawValue == 125)
    #expect(reading?.quality == 0)
    #expect(reading?.trendArrow == 3)
    #expect(reading?.sensorAge == 1440)
}

@Test func testLibre3PacketParserGlucoseTooShort() {
    let parser = Libre3PacketParser()
    let data = Data([0x01, 0x02, 0x03]) // Too short
    
    let reading = parser.parseGlucosePacket(data)
    #expect(reading == nil)
}

@Test func testLibre3ConnectionState() {
    #expect(!Libre3ConnectionState.disconnected.isConnected)
    #expect(!Libre3ConnectionState.scanning.isConnected)
    #expect(!Libre3ConnectionState.connecting.isConnected)
    #expect(!Libre3ConnectionState.authenticating.isConnected)
    #expect(Libre3ConnectionState.connected.isConnected)
    #expect(!Libre3ConnectionState.error("test").isConnected)
}

@Test func testLibre3ManagerProperties() async {
    let manager = Libre3Manager()
    
    let displayName = await manager.displayName
    let cgmType = await manager.cgmType
    let state = await manager.sensorState
    
    #expect(displayName == "Libre 3")
    #expect(cgmType == .libre3)
    #expect(state == .notStarted)
}

@Test func testLibre3SimulatorProperties() async {
    let simulator = Libre3Simulator()
    
    let displayName = await simulator.displayName
    let cgmType = await simulator.cgmType
    
    #expect(displayName == "Libre 3 (Simulated)")
    #expect(cgmType == .libre3)
}

// MARK: - Unified Callback Naming Tests (ARCH-001)

@Test func testCGMManagerUnifiedCallbackAliases() async {
    // Test that unified aliases work for CGM managers
    let simulator = Libre3Simulator()
    
    // Verify aliases are available (compile-time check)
    // Set via unified aliases
    let onData: (@Sendable (GlucoseReading) -> Void)? = { _ in }
    let onState: (@Sendable (SensorState) -> Void)? = { _ in }
    
    await MainActor.run {
        // These should compile - proving the aliases exist
        _ = onData
        _ = onState
    }
    
    // Verify aliases are correctly mapped to underlying properties
    await simulator.setCallbacksViaAlias(
        onData: { _ in },
        onState: { _ in }
    )
    
    #expect(await simulator.onDataReceived != nil)
    #expect(await simulator.onStateChanged != nil)
    #expect(await simulator.onReadingReceived != nil)  // Original still works
    #expect(await simulator.onSensorStateChanged != nil)  // Original still works
}

// Helper extension for testing
extension Libre3Simulator {
    func setCallbacksViaAlias(
        onData: (@Sendable (GlucoseReading) -> Void)?,
        onState: (@Sendable (SensorState) -> Void)?
    ) {
        self.onDataReceived = onData
        self.onStateChanged = onState
    }
}
