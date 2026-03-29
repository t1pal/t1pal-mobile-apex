// SettingsBindingTests.swift - Tests for SettingsBinding
// Part of T1PalCoreTests
// Trace: PROD-PERSIST-002

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Settings Key Tests

@Suite("Settings Keys")
struct SettingsKeyTests {
    
    @Test("All keys have unique raw values")
    func allKeysUnique() {
        let allKeys = SettingsKey.allCases
        let rawValues = Set(allKeys.map { $0.rawValue })
        #expect(allKeys.count == rawValues.count, "Some keys have duplicate raw values")
    }
    
    @Test("Keys have proper prefixes")
    func keyPrefixes() {
        for key in SettingsKey.allCases {
            #expect(key.rawValue.hasPrefix("settings."), "Key \(key) should have 'settings.' prefix")
        }
    }
    
    @Test("Data source keys exist")
    func dataSourceKeys() {
        #expect(SettingsKey.activeDataSourceID.rawValue == "settings.dataSource.activeID")
        #expect(SettingsKey.nightscoutURL.rawValue == "settings.dataSource.nightscoutURL")
    }
    
    @Test("Algorithm keys exist")
    func algorithmKeys() {
        #expect(SettingsKey.algorithmName.rawValue == "settings.algorithm.name")
        #expect(SettingsKey.algorithmDIA.rawValue == "settings.algorithm.dia")
        #expect(SettingsKey.algorithmISF.rawValue == "settings.algorithm.isf")
        #expect(SettingsKey.algorithmICR.rawValue == "settings.algorithm.icr")
        #expect(SettingsKey.algorithmSMBEnabled.rawValue == "settings.algorithm.smbEnabled")
    }
    
    @Test("CGM keys exist")
    func cgmKeys() {
        #expect(SettingsKey.cgmType.rawValue == "settings.cgm.type")
        #expect(SettingsKey.cgmTransmitterId.rawValue == "settings.cgm.transmitterId")
        #expect(SettingsKey.cgmConnectionMode.rawValue == "settings.cgm.connectionMode")
    }
    
    @Test("Pump keys exist")
    func pumpKeys() {
        #expect(SettingsKey.pumpEnabled.rawValue == "settings.pump.enabled")
        #expect(SettingsKey.pumpType.rawValue == "settings.pump.type")
        #expect(SettingsKey.pumpSerial.rawValue == "settings.pump.serial")
    }
    
    @Test("AID keys exist")
    func aidKeys() {
        #expect(SettingsKey.aidEnabled.rawValue == "settings.aid.enabled")
        #expect(SettingsKey.aidClosedLoopAllowed.rawValue == "settings.aid.closedLoopAllowed")
        #expect(SettingsKey.aidLoopInterval.rawValue == "settings.aid.loopInterval")
    }
    
    @Test("Onboarding keys exist")
    func onboardingKeys() {
        #expect(SettingsKey.onboardingComplete.rawValue == "settings.onboarding.complete")
        #expect(SettingsKey.termsAccepted.rawValue == "settings.onboarding.termsAccepted")
    }
}

// MARK: - Settings Defaults Tests

@Suite("Settings Defaults")
struct SettingsDefaultsTests {
    
    @Test("Glucose thresholds have sensible defaults")
    func glucoseDefaults() {
        #expect(SettingsDefaults.lowGlucoseThreshold == 70.0)
        #expect(SettingsDefaults.highGlucoseThreshold == 180.0)
        #expect(SettingsDefaults.urgentLowThreshold == 55.0)
        #expect(SettingsDefaults.urgentHighThreshold == 250.0)
        
        // Verify ordering
        #expect(SettingsDefaults.urgentLowThreshold < SettingsDefaults.lowGlucoseThreshold)
        #expect(SettingsDefaults.lowGlucoseThreshold < SettingsDefaults.highGlucoseThreshold)
        #expect(SettingsDefaults.highGlucoseThreshold < SettingsDefaults.urgentHighThreshold)
    }
    
    @Test("Algorithm defaults are safe")
    func algorithmDefaults() {
        #expect(SettingsDefaults.algorithmDIA >= 3.0, "DIA should be at least 3 hours")
        #expect(SettingsDefaults.algorithmISF >= 10.0, "ISF should be at least 10")
        #expect(SettingsDefaults.algorithmICR >= 2.0, "ICR should be at least 2")
        #expect(SettingsDefaults.algorithmSuspendThreshold >= 50.0, "Suspend should be at least 50")
    }
    
    @Test("AID loop interval is 5 minutes")
    func aidLoopInterval() {
        #expect(SettingsDefaults.aidLoopInterval == 300)
    }
}

// MARK: - Persisted Algorithm Settings Tests

@Suite("Persisted Algorithm Settings")
struct PersistedAlgorithmSettingsTests {
    
    @Test("Default initialization")
    func defaultInit() {
        let settings = PersistedAlgorithmSettings()
        
        #expect(settings.algorithmName == "oref0")
        #expect(settings.dia == 5.0)
        #expect(settings.isf == 50.0)
        #expect(settings.icr == 10.0)
        #expect(settings.basalRate == 1.0)
        #expect(settings.targetLow == 100.0)
        #expect(settings.targetHigh == 120.0)
        #expect(settings.smbEnabled == false)
        #expect(settings.uamEnabled == false)
    }
    
    @Test("Custom initialization")
    func customInit() {
        let settings = PersistedAlgorithmSettings(
            algorithmName: "oref1",
            dia: 4.0,
            isf: 40.0,
            icr: 8.0,
            basalRate: 1.5,
            targetLow: 90.0,
            targetHigh: 100.0,
            smbEnabled: true,
            maxSMB: 2.0,
            uamEnabled: true,
            maxBasalRate: 8.0,
            maxBolus: 15.0,
            maxIOB: 15.0,
            suspendThreshold: 65.0
        )
        
        #expect(settings.algorithmName == "oref1")
        #expect(settings.smbEnabled == true)
        #expect(settings.uamEnabled == true)
        #expect(settings.maxSMB == 2.0)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PersistedAlgorithmSettings(
            algorithmName: "oref1",
            dia: 4.5,
            smbEnabled: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PersistedAlgorithmSettings.self, from: data)
        
        #expect(decoded == original)
    }
    
    @Test("Equatable comparison")
    func equatable() {
        let a = PersistedAlgorithmSettings()
        let b = PersistedAlgorithmSettings()
        let c = PersistedAlgorithmSettings(algorithmName: "oref1")
        
        #expect(a == b)
        #expect(a != c)
    }
    
    @Test("Static default preset")
    func staticDefault() {
        let settings = PersistedAlgorithmSettings.default
        #expect(settings.algorithmName == "oref0")
        #expect(settings.dia == 5.0)
    }
}

// MARK: - CGM Connection Mode Tests

@Suite("CGM Connection Mode")
struct CGMConnectionModeTests {
    
    @Test("All cases have raw values")
    func rawValues() {
        #expect(CGMConnectionMode.ble.rawValue == "ble")
        #expect(CGMConnectionMode.cloud.rawValue == "cloud")
        #expect(CGMConnectionMode.demo.rawValue == "demo")
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for mode in CGMConnectionMode.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(mode)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(CGMConnectionMode.self, from: data)
            
            #expect(decoded == mode)
        }
    }
}

// MARK: - Persisted CGM Settings Tests

@Suite("Persisted CGM Settings")
struct PersistedCGMSettingsTests {
    
    @Test("Default initialization")
    func defaultInit() {
        let settings = PersistedCGMSettings()
        
        #expect(settings.cgmType == "dexcomG6")
        #expect(settings.transmitterId == nil)
        #expect(settings.sensorCode == nil)
        #expect(settings.connectionMode == .ble)
    }
    
    @Test("Custom initialization")
    func customInit() {
        let settings = PersistedCGMSettings(
            cgmType: "dexcomG7",
            transmitterId: "ABC123",
            sensorCode: "1234",
            connectionMode: .ble
        )
        
        #expect(settings.cgmType == "dexcomG7")
        #expect(settings.transmitterId == "ABC123")
        #expect(settings.sensorCode == "1234")
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PersistedCGMSettings(
            cgmType: "libre2",
            transmitterId: "XYZ789",
            connectionMode: .cloud
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PersistedCGMSettings.self, from: data)
        
        #expect(decoded == original)
    }
}

// MARK: - Persisted Pump Settings Tests

@Suite("Persisted Pump Settings")
struct PersistedPumpSettingsTests {
    
    @Test("Default initialization")
    func defaultInit() {
        let settings = PersistedPumpSettings()
        
        #expect(settings.enabled == false)
        #expect(settings.pumpType == "medtronic")
        #expect(settings.serial == nil)
        #expect(settings.bridgeType == nil)
    }
    
    @Test("Custom initialization")
    func customInit() {
        let settings = PersistedPumpSettings(
            enabled: true,
            pumpType: "dana-i",
            serial: "123456",
            bridgeType: "integrated",
            bridgeId: nil
        )
        
        #expect(settings.enabled == true)
        #expect(settings.pumpType == "dana-i")
        #expect(settings.serial == "123456")
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PersistedPumpSettings(
            enabled: true,
            pumpType: "medtronic",
            serial: "555555",
            bridgeType: "rileyLink",
            bridgeId: "RL-001"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PersistedPumpSettings.self, from: data)
        
        #expect(decoded == original)
    }
}

// MARK: - Persisted AID Settings Tests

@Suite("Persisted AID Settings")
struct PersistedAIDSettingsTests {
    
    @Test("Default initialization")
    func defaultInit() {
        let settings = PersistedAIDSettings()
        
        #expect(settings.enabled == false)
        #expect(settings.closedLoopAllowed == false)
        #expect(settings.lastLoopTime == nil)
        #expect(settings.loopInterval == 300)
    }
    
    @Test("Custom initialization")
    func customInit() {
        let now = Date()
        let settings = PersistedAIDSettings(
            enabled: true,
            closedLoopAllowed: true,
            lastLoopTime: now,
            loopInterval: 180
        )
        
        #expect(settings.enabled == true)
        #expect(settings.closedLoopAllowed == true)
        #expect(settings.lastLoopTime == now)
        #expect(settings.loopInterval == 180)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PersistedAIDSettings(
            enabled: true,
            closedLoopAllowed: true,
            loopInterval: 300
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PersistedAIDSettings.self, from: data)
        
        #expect(decoded.enabled == original.enabled)
        #expect(decoded.closedLoopAllowed == original.closedLoopAllowed)
        #expect(decoded.loopInterval == original.loopInterval)
    }
}

// MARK: - Persisted Onboarding Settings Tests

@Suite("Persisted Onboarding Settings")
struct PersistedOnboardingSettingsTests {
    
    @Test("Default initialization")
    func defaultInit() {
        let settings = PersistedOnboardingSettings()
        
        #expect(settings.complete == false)
        #expect(settings.currentStep == 0)
        #expect(settings.termsAccepted == false)
        #expect(settings.trainingComplete == false)
    }
    
    @Test("Completed state")
    func completedState() {
        let settings = PersistedOnboardingSettings(
            complete: true,
            currentStep: 5,
            termsAccepted: true,
            trainingComplete: true
        )
        
        #expect(settings.complete == true)
        #expect(settings.currentStep == 5)
        #expect(settings.termsAccepted == true)
        #expect(settings.trainingComplete == true)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = PersistedOnboardingSettings(
            complete: true,
            currentStep: 3,
            termsAccepted: true,
            trainingComplete: false
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PersistedOnboardingSettings.self, from: data)
        
        #expect(decoded == original)
    }
}

// MARK: - Settings Store Extension Tests

@Suite("Settings Store Algorithm Settings")
struct SettingsStoreAlgorithmTests {
    
    @Test("Algorithm name persistence")
    func algorithmName() {
        let defaults = UserDefaults(suiteName: "test.algorithm.name")!
        defer { defaults.removePersistentDomain(forName: "test.algorithm.name") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.algorithmName == "oref0")
        
        // Set and get
        store.algorithmName = "oref1"
        #expect(store.algorithmName == "oref1")
    }
    
    @Test("Algorithm DIA persistence")
    func algorithmDIA() {
        let defaults = UserDefaults(suiteName: "test.algorithm.dia")!
        defer { defaults.removePersistentDomain(forName: "test.algorithm.dia") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.algorithmDIA == 5.0)
        
        // Set and get
        store.algorithmDIA = 4.5
        #expect(store.algorithmDIA == 4.5)
    }
    
    @Test("Algorithm ISF persistence")
    func algorithmISF() {
        let defaults = UserDefaults(suiteName: "test.algorithm.isf")!
        defer { defaults.removePersistentDomain(forName: "test.algorithm.isf") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.algorithmISF == 50.0)
        
        // Set and get
        store.algorithmISF = 40.0
        #expect(store.algorithmISF == 40.0)
    }
    
    @Test("Algorithm SMB enabled persistence")
    func algorithmSMBEnabled() {
        let defaults = UserDefaults(suiteName: "test.algorithm.smb")!
        defer { defaults.removePersistentDomain(forName: "test.algorithm.smb") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.algorithmSMBEnabled == false)
        
        // Set and get
        store.algorithmSMBEnabled = true
        #expect(store.algorithmSMBEnabled == true)
    }
    
    @Test("Get algorithm settings as struct")
    func getAlgorithmSettings() {
        let defaults = UserDefaults(suiteName: "test.algorithm.struct")!
        defer { defaults.removePersistentDomain(forName: "test.algorithm.struct") }
        
        let store = SettingsStore(userDefaults: defaults)
        store.algorithmName = "oref1"
        store.algorithmDIA = 4.5
        store.algorithmSMBEnabled = true
        
        let settings = store.getAlgorithmSettings()
        
        #expect(settings.algorithmName == "oref1")
        #expect(settings.dia == 4.5)
        #expect(settings.smbEnabled == true)
    }
    
    @Test("Save algorithm settings from struct")
    func saveAlgorithmSettings() {
        let defaults = UserDefaults(suiteName: "test.algorithm.save")!
        defer { defaults.removePersistentDomain(forName: "test.algorithm.save") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        let settings = PersistedAlgorithmSettings(
            algorithmName: "oref1",
            dia: 4.0,
            isf: 45.0,
            smbEnabled: true,
            uamEnabled: true
        )
        
        store.saveAlgorithmSettings(settings)
        
        #expect(store.algorithmName == "oref1")
        #expect(store.algorithmDIA == 4.0)
        #expect(store.algorithmISF == 45.0)
        #expect(store.algorithmSMBEnabled == true)
        #expect(store.algorithmUAMEnabled == true)
    }
}

// MARK: - Settings Store CGM Tests

@Suite("Settings Store CGM Settings")
struct SettingsStoreCGMTests {
    
    @Test("CGM type persistence")
    func cgmType() {
        let defaults = UserDefaults(suiteName: "test.cgm.type")!
        defer { defaults.removePersistentDomain(forName: "test.cgm.type") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.cgmType == "dexcomG6")
        
        // Set and get
        store.cgmType = "libre2"
        #expect(store.cgmType == "libre2")
    }
    
    @Test("CGM transmitter ID persistence")
    func cgmTransmitterId() {
        let defaults = UserDefaults(suiteName: "test.cgm.transmitter")!
        defer { defaults.removePersistentDomain(forName: "test.cgm.transmitter") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.cgmTransmitterId == nil)
        
        // Set and get
        store.cgmTransmitterId = "ABC123"
        #expect(store.cgmTransmitterId == "ABC123")
    }
    
    @Test("CGM connection mode persistence")
    func cgmConnectionMode() {
        let defaults = UserDefaults(suiteName: "test.cgm.mode")!
        defer { defaults.removePersistentDomain(forName: "test.cgm.mode") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.cgmConnectionMode == .ble)
        
        // Set and get
        store.cgmConnectionMode = .cloud
        #expect(store.cgmConnectionMode == .cloud)
    }
    
    @Test("Get CGM settings as struct")
    func getCGMSettings() {
        let defaults = UserDefaults(suiteName: "test.cgm.struct")!
        defer { defaults.removePersistentDomain(forName: "test.cgm.struct") }
        
        let store = SettingsStore(userDefaults: defaults)
        store.cgmType = "dexcomG7"
        store.cgmTransmitterId = "XYZ789"
        store.cgmConnectionMode = .ble
        
        let settings = store.getCGMSettings()
        
        #expect(settings.cgmType == "dexcomG7")
        #expect(settings.transmitterId == "XYZ789")
        #expect(settings.connectionMode == .ble)
    }
    
    @Test("Save CGM settings from struct")
    func saveCGMSettings() {
        let defaults = UserDefaults(suiteName: "test.cgm.save")!
        defer { defaults.removePersistentDomain(forName: "test.cgm.save") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        let settings = PersistedCGMSettings(
            cgmType: "libre3",
            transmitterId: "L3-001",
            sensorCode: "9999",
            connectionMode: .ble
        )
        
        store.saveCGMSettings(settings)
        
        #expect(store.cgmType == "libre3")
        #expect(store.cgmTransmitterId == "L3-001")
        #expect(store.cgmSensorCode == "9999")
        #expect(store.cgmConnectionMode == .ble)
    }
}

// MARK: - Settings Store Pump Tests

@Suite("Settings Store Pump Settings")
struct SettingsStorePumpTests {
    
    @Test("Pump enabled persistence")
    func pumpEnabled() {
        let defaults = UserDefaults(suiteName: "test.pump.enabled")!
        defer { defaults.removePersistentDomain(forName: "test.pump.enabled") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.pumpEnabled == false)
        
        // Set and get
        store.pumpEnabled = true
        #expect(store.pumpEnabled == true)
    }
    
    @Test("Pump type persistence")
    func pumpType() {
        let defaults = UserDefaults(suiteName: "test.pump.type")!
        defer { defaults.removePersistentDomain(forName: "test.pump.type") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.pumpType == "medtronic")
        
        // Set and get
        store.pumpType = "dana-i"
        #expect(store.pumpType == "dana-i")
    }
    
    @Test("Pump serial persistence")
    func pumpSerial() {
        let defaults = UserDefaults(suiteName: "test.pump.serial")!
        defer { defaults.removePersistentDomain(forName: "test.pump.serial") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.pumpSerial == nil)
        
        // Set and get
        store.pumpSerial = "123456"
        #expect(store.pumpSerial == "123456")
    }
    
    @Test("Get pump settings as struct")
    func getPumpSettings() {
        let defaults = UserDefaults(suiteName: "test.pump.struct")!
        defer { defaults.removePersistentDomain(forName: "test.pump.struct") }
        
        let store = SettingsStore(userDefaults: defaults)
        store.pumpEnabled = true
        store.pumpType = "omnipod"
        store.pumpSerial = "OP-001"
        
        let settings = store.getPumpSettings()
        
        #expect(settings.enabled == true)
        #expect(settings.pumpType == "omnipod")
        #expect(settings.serial == "OP-001")
    }
    
    @Test("Save pump settings from struct")
    func savePumpSettings() {
        let defaults = UserDefaults(suiteName: "test.pump.save")!
        defer { defaults.removePersistentDomain(forName: "test.pump.save") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        let settings = PersistedPumpSettings(
            enabled: true,
            pumpType: "medtronic",
            serial: "555555",
            bridgeType: "rileyLink",
            bridgeId: "RL-001"
        )
        
        store.savePumpSettings(settings)
        
        #expect(store.pumpEnabled == true)
        #expect(store.pumpType == "medtronic")
        #expect(store.pumpSerial == "555555")
        #expect(store.pumpBridgeType == "rileyLink")
        #expect(store.pumpBridgeId == "RL-001")
    }
}

// MARK: - Settings Store AID Tests

@Suite("Settings Store AID Settings")
struct SettingsStoreAIDTests {
    
    @Test("AID enabled persistence")
    func aidEnabled() {
        let defaults = UserDefaults(suiteName: "test.aid.enabled")!
        defer { defaults.removePersistentDomain(forName: "test.aid.enabled") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.aidEnabled == false)
        
        // Set and get
        store.aidEnabled = true
        #expect(store.aidEnabled == true)
    }
    
    @Test("AID closed loop allowed persistence")
    func aidClosedLoopAllowed() {
        let defaults = UserDefaults(suiteName: "test.aid.closedloop")!
        defer { defaults.removePersistentDomain(forName: "test.aid.closedloop") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.aidClosedLoopAllowed == false)
        
        // Set and get
        store.aidClosedLoopAllowed = true
        #expect(store.aidClosedLoopAllowed == true)
    }
    
    @Test("AID last loop time persistence")
    func aidLastLoopTime() {
        let defaults = UserDefaults(suiteName: "test.aid.lastloop")!
        defer { defaults.removePersistentDomain(forName: "test.aid.lastloop") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.aidLastLoopTime == nil)
        
        // Set and get
        let now = Date()
        store.aidLastLoopTime = now
        #expect(store.aidLastLoopTime != nil)
    }
    
    @Test("AID loop interval persistence")
    func aidLoopInterval() {
        let defaults = UserDefaults(suiteName: "test.aid.interval")!
        defer { defaults.removePersistentDomain(forName: "test.aid.interval") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.aidLoopInterval == 300)
        
        // Set and get
        store.aidLoopInterval = 180
        #expect(store.aidLoopInterval == 180)
    }
    
    @Test("Get AID settings as struct")
    func getAIDSettings() {
        let defaults = UserDefaults(suiteName: "test.aid.struct")!
        defer { defaults.removePersistentDomain(forName: "test.aid.struct") }
        
        let store = SettingsStore(userDefaults: defaults)
        store.aidEnabled = true
        store.aidClosedLoopAllowed = true
        store.aidLoopInterval = 180
        
        let settings = store.getAIDSettings()
        
        #expect(settings.enabled == true)
        #expect(settings.closedLoopAllowed == true)
        #expect(settings.loopInterval == 180)
    }
    
    @Test("Save AID settings from struct")
    func saveAIDSettings() {
        let defaults = UserDefaults(suiteName: "test.aid.save")!
        defer { defaults.removePersistentDomain(forName: "test.aid.save") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        let now = Date()
        let settings = PersistedAIDSettings(
            enabled: true,
            closedLoopAllowed: true,
            lastLoopTime: now,
            loopInterval: 240
        )
        
        store.saveAIDSettings(settings)
        
        #expect(store.aidEnabled == true)
        #expect(store.aidClosedLoopAllowed == true)
        #expect(store.aidLastLoopTime != nil)
        #expect(store.aidLoopInterval == 240)
    }
}

// MARK: - Settings Store Onboarding Tests

@Suite("Settings Store Onboarding Settings")
struct SettingsStoreOnboardingTests {
    
    @Test("Onboarding complete persistence")
    func onboardingComplete() {
        let defaults = UserDefaults(suiteName: "test.onboarding.complete")!
        defer { defaults.removePersistentDomain(forName: "test.onboarding.complete") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.onboardingComplete == false)
        
        // Set and get
        store.onboardingComplete = true
        #expect(store.onboardingComplete == true)
    }
    
    @Test("Onboarding step persistence")
    func onboardingStep() {
        let defaults = UserDefaults(suiteName: "test.onboarding.step")!
        defer { defaults.removePersistentDomain(forName: "test.onboarding.step") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.onboardingStep == 0)
        
        // Set and get
        store.onboardingStep = 3
        #expect(store.onboardingStep == 3)
    }
    
    @Test("Terms accepted persistence")
    func termsAccepted() {
        let defaults = UserDefaults(suiteName: "test.onboarding.terms")!
        defer { defaults.removePersistentDomain(forName: "test.onboarding.terms") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.termsAccepted == false)
        
        // Set and get
        store.termsAccepted = true
        #expect(store.termsAccepted == true)
    }
    
    @Test("Training complete persistence")
    func trainingComplete() {
        let defaults = UserDefaults(suiteName: "test.onboarding.training")!
        defer { defaults.removePersistentDomain(forName: "test.onboarding.training") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        // Default
        #expect(store.trainingComplete == false)
        
        // Set and get
        store.trainingComplete = true
        #expect(store.trainingComplete == true)
    }
    
    @Test("Get onboarding settings as struct")
    func getOnboardingSettings() {
        let defaults = UserDefaults(suiteName: "test.onboarding.struct")!
        defer { defaults.removePersistentDomain(forName: "test.onboarding.struct") }
        
        let store = SettingsStore(userDefaults: defaults)
        store.onboardingComplete = true
        store.onboardingStep = 5
        store.termsAccepted = true
        store.trainingComplete = true
        
        let settings = store.getOnboardingSettings()
        
        #expect(settings.complete == true)
        #expect(settings.currentStep == 5)
        #expect(settings.termsAccepted == true)
        #expect(settings.trainingComplete == true)
    }
    
    @Test("Save onboarding settings from struct")
    func saveOnboardingSettings() {
        let defaults = UserDefaults(suiteName: "test.onboarding.save")!
        defer { defaults.removePersistentDomain(forName: "test.onboarding.save") }
        
        let store = SettingsStore(userDefaults: defaults)
        
        let settings = PersistedOnboardingSettings(
            complete: true,
            currentStep: 4,
            termsAccepted: true,
            trainingComplete: false
        )
        
        store.saveOnboardingSettings(settings)
        
        #expect(store.onboardingComplete == true)
        #expect(store.onboardingStep == 4)
        #expect(store.termsAccepted == true)
        #expect(store.trainingComplete == false)
    }
}
