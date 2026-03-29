// KeychainHelperTests.swift
// Tests for KeychainHelper BLE/Pump config methods
// Trace: BLE-CTX-033, PRD-004 REQ-CGM-PERSIST

import Testing
@testable import T1PalCore

@Suite("Keychain Helper Tests")
struct KeychainHelperTests {
    
    let keychain = KeychainHelper.shared
    
    // MARK: - BLE Device Config Tests
    
    @Suite("BLE Device Config")
    struct BLEDeviceConfigTests {
        let keychain = KeychainHelper.shared
        
        @Test("Save BLE device config")
        func saveBLEDeviceConfig() {
            let config = BLEDeviceConfig.dexcomG6(transmitterId: "8G1234", sensorCode: "1234")
            
            let saved = keychain.saveBLEDeviceConfig(config, for: "TEST123-SAVE")
            #expect(saved)
            
            #expect(keychain.bleDeviceConfigExists(for: .dexcomG6, deviceId: "TEST123-SAVE"))
            
            // Clean up
            keychain.deleteBLEDeviceConfig(for: .dexcomG6, deviceId: "TEST123-SAVE")
        }
        
        @Test("Load BLE device config")
        func loadBLEDeviceConfig() {
            let config = BLEDeviceConfig.dexcomG6(transmitterId: "8G1234", sensorCode: "1234")
            keychain.saveBLEDeviceConfig(config, for: "TEST123-LOAD")
            
            let loaded = keychain.loadBLEDeviceConfig(for: .dexcomG6, deviceId: "TEST123-LOAD")
            
            #expect(loaded != nil)
            #expect(loaded?.cgmType == .dexcomG6)
            #expect(loaded?.transmitterId == "8G1234")
            #expect(loaded?.sensorCode == "1234")
            
            // Clean up
            keychain.deleteBLEDeviceConfig(for: .dexcomG6, deviceId: "TEST123-LOAD")
        }
        
        @Test("Delete BLE device config")
        func deleteBLEDeviceConfig() {
            let config = BLEDeviceConfig.dexcomG6(transmitterId: "8G1234")
            keychain.saveBLEDeviceConfig(config, for: "TEST123-DEL")
            
            #expect(keychain.bleDeviceConfigExists(for: .dexcomG6, deviceId: "TEST123-DEL"))
            
            let deleted = keychain.deleteBLEDeviceConfig(for: .dexcomG6, deviceId: "TEST123-DEL")
            #expect(deleted)
            
            #expect(!keychain.bleDeviceConfigExists(for: .dexcomG6, deviceId: "TEST123-DEL"))
        }
        
        @Test("Load nonexistent BLE config returns nil")
        func loadNonexistentBLEConfig() {
            let loaded = keychain.loadBLEDeviceConfig(for: .dexcomG6, deviceId: "NONEXISTENT")
            #expect(loaded == nil)
        }
        
        @Test("Multiple BLE configs")
        func multipleBLEConfigs() {
            let g6Config = BLEDeviceConfig.dexcomG6(transmitterId: "8G1234")
            let g7Config = BLEDeviceConfig.dexcomG7(transmitterId: "9H5678")
            
            keychain.saveBLEDeviceConfig(g6Config, for: "TEST123-MULTI")
            keychain.saveBLEDeviceConfig(g7Config, for: "TEST456-MULTI")
            
            let loadedG6 = keychain.loadBLEDeviceConfig(for: .dexcomG6, deviceId: "TEST123-MULTI")
            let loadedG7 = keychain.loadBLEDeviceConfig(for: .dexcomG7, deviceId: "TEST456-MULTI")
            
            #expect(loadedG6?.cgmType == .dexcomG6)
            #expect(loadedG7?.cgmType == .dexcomG7)
            
            // Clean up
            keychain.deleteBLEDeviceConfig(for: .dexcomG6, deviceId: "TEST123-MULTI")
            keychain.deleteBLEDeviceConfig(for: .dexcomG7, deviceId: "TEST456-MULTI")
        }
        
        @Test("Overwrite BLE config")
        func overwriteBLEConfig() {
            let config1 = BLEDeviceConfig.dexcomG6(transmitterId: "8G1234", sensorCode: "1111")
            let config2 = BLEDeviceConfig.dexcomG6(transmitterId: "8G1234", sensorCode: "2222")
            
            keychain.saveBLEDeviceConfig(config1, for: "TEST123-OVR")
            keychain.saveBLEDeviceConfig(config2, for: "TEST123-OVR")
            
            let loaded = keychain.loadBLEDeviceConfig(for: .dexcomG6, deviceId: "TEST123-OVR")
            #expect(loaded?.sensorCode == "2222")
            
            // Clean up
            keychain.deleteBLEDeviceConfig(for: .dexcomG6, deviceId: "TEST123-OVR")
        }
    }
    
    // MARK: - Pump Device Config Tests
    
    @Suite("Pump Device Config")
    struct PumpDeviceConfigTests {
        let keychain = KeychainHelper.shared
        
        @Test("Save pump device config")
        func savePumpDeviceConfig() {
            let config = PumpDeviceConfig.medtronic(serial: "ABC123-SAVE", bridge: .rileyLink)
            
            let saved = keychain.savePumpDeviceConfig(config, for: "ABC123-SAVE")
            #expect(saved)
            
            #expect(keychain.pumpDeviceConfigExists(for: .medtronic, pumpId: "ABC123-SAVE"))
            
            // Clean up
            keychain.deletePumpDeviceConfig(for: .medtronic, pumpId: "ABC123-SAVE")
        }
        
        @Test("Load pump device config")
        func loadPumpDeviceConfig() {
            let config = PumpDeviceConfig.medtronic(serial: "ABC123-LOAD", bridge: .rileyLink, bridgeId: "RL1234")
            keychain.savePumpDeviceConfig(config, for: "ABC123-LOAD")
            
            let loaded = keychain.loadPumpDeviceConfig(for: .medtronic, pumpId: "ABC123-LOAD")
            
            #expect(loaded != nil)
            #expect(loaded?.pumpType == .medtronic)
            #expect(loaded?.pumpSerial == "ABC123-LOAD")
            #expect(loaded?.bridgeType == .rileyLink)
            #expect(loaded?.bridgeId == "RL1234")
            
            // Clean up
            keychain.deletePumpDeviceConfig(for: .medtronic, pumpId: "ABC123-LOAD")
        }
        
        @Test("Delete pump device config")
        func deletePumpDeviceConfig() {
            let config = PumpDeviceConfig.dana()
            keychain.savePumpDeviceConfig(config, for: "DANA01-DEL")
            
            #expect(keychain.pumpDeviceConfigExists(for: .dana, pumpId: "DANA01-DEL"))
            
            let deleted = keychain.deletePumpDeviceConfig(for: .dana, pumpId: "DANA01-DEL")
            #expect(deleted)
            
            #expect(!keychain.pumpDeviceConfigExists(for: .dana, pumpId: "DANA01-DEL"))
        }
        
        @Test("Load nonexistent pump config returns nil")
        func loadNonexistentPumpConfig() {
            let loaded = keychain.loadPumpDeviceConfig(for: .medtronic, pumpId: "NONEXISTENT")
            #expect(loaded == nil)
        }
    }
    
    // MARK: - Account Key Format Tests
    
    @Suite("Account Key Format")
    struct AccountKeyFormatTests {
        let keychain = KeychainHelper.shared
        
        @Test("Account key is case insensitive")
        func accountKeyIsCaseInsensitive() {
            let config = BLEDeviceConfig.dexcomG6(transmitterId: "8G1234")
            
            keychain.saveBLEDeviceConfig(config, for: "TestDevice-CASE")
            
            // Should find with lowercase
            #expect(keychain.bleDeviceConfigExists(for: .dexcomG6, deviceId: "testdevice-case"))
            
            // Clean up
            keychain.deleteBLEDeviceConfig(for: .dexcomG6, deviceId: "testdevice-case")
        }
    }
    
    // MARK: - Libre Device Tests
    
    @Suite("Libre Devices")
    struct LibreDeviceTests {
        let keychain = KeychainHelper.shared
        
        @Test("Save Libre2 config")
        func saveLibre2Config() {
            let config = BLEDeviceConfig.libre2()
            
            let saved = keychain.saveBLEDeviceConfig(config, for: "libre-sensor-1")
            #expect(saved)
            
            let loaded = keychain.loadBLEDeviceConfig(for: .libre2, deviceId: "libre-sensor-1")
            #expect(loaded?.cgmType == .libre2)
            
            // Clean up
            keychain.deleteBLEDeviceConfig(for: .libre2, deviceId: "libre-sensor-1")
        }
    }
    
    // MARK: - Omnipod Config Tests
    
    @Suite("Omnipod Configs")
    struct OmnipodConfigTests {
        let keychain = KeychainHelper.shared
        
        @Test("Save Omnipod Eros config")
        func saveOmnipodErosConfig() {
            let config = PumpDeviceConfig.omnipodEros(bridge: .orangeLink, bridgeId: "OL5678")
            
            let saved = keychain.savePumpDeviceConfig(config, for: "pod-lot-123")
            #expect(saved)
            
            let loaded = keychain.loadPumpDeviceConfig(for: .omnipodEros, pumpId: "pod-lot-123")
            #expect(loaded?.pumpType == .omnipodEros)
            #expect(loaded?.bridgeType == .orangeLink)
            
            // Clean up
            keychain.deletePumpDeviceConfig(for: .omnipodEros, pumpId: "pod-lot-123")
        }
        
        @Test("Save Omnipod DASH config")
        func saveOmnipodDashConfig() {
            let config = PumpDeviceConfig.omnipodDash()
            
            let saved = keychain.savePumpDeviceConfig(config, for: "dash-pod-1")
            #expect(saved)
            
            let loaded = keychain.loadPumpDeviceConfig(for: .omnipodDash, pumpId: "dash-pod-1")
            #expect(loaded?.pumpType == .omnipodDash)
            #expect(loaded?.bridgeType == nil) // Dash uses Bluetooth directly
            
            // Clean up
            keychain.deletePumpDeviceConfig(for: .omnipodDash, pumpId: "dash-pod-1")
        }
    }
}
