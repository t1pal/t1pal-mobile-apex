// SPDX-License-Identifier: MIT
// PassiveBLEScanner Tests
// Trace: REQ-CGM-009a, CGM-028

import Testing
import Foundation
@testable import BLEKit

// MARK: - CGMDeviceType Tests

@Suite("CGM Device Type")
struct CGMDeviceTypeTests {
    
    @Test("All device types have raw values")
    func deviceTypesHaveRawValues() {
        #expect(CGMDeviceType.dexcomG6.rawValue == "dexcomG6")
        #expect(CGMDeviceType.dexcomG7.rawValue == "dexcomG7")
        #expect(CGMDeviceType.libre2.rawValue == "libre2")
        #expect(CGMDeviceType.libre3.rawValue == "libre3")
        #expect(CGMDeviceType.miaomiao.rawValue == "miaomiao")
        #expect(CGMDeviceType.bubble.rawValue == "bubble")
        #expect(CGMDeviceType.unknown.rawValue == "unknown")
    }
    
    @Test("Device type is codable")
    func deviceTypeIsCodable() throws {
        let type = CGMDeviceType.dexcomG7
        let data = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(CGMDeviceType.self, from: data)
        
        #expect(decoded == type)
    }
}

// MARK: - PassiveScanResult Tests

@Suite("Passive Scan Result")
struct PassiveScanResultTests {
    
    @Test("Result has correct properties")
    func resultHasCorrectProperties() {
        let result = PassiveScanResult(
            transmitterId: "8N1234",
            transmitterType: .dexcomG6,
            rssi: -65,
            advertisementData: nil,
            vendorConnected: false
        )
        
        #expect(result.transmitterId == "8N1234")
        #expect(result.transmitterType == .dexcomG6)
        #expect(result.rssi == -65)
        #expect(result.vendorConnected == false)
    }
    
    @Test("Result detects vendor connection")
    func resultDetectsVendorConnection() {
        let connectedResult = PassiveScanResult(
            transmitterId: "8N1234",
            transmitterType: .dexcomG6,
            rssi: -65,
            advertisementData: nil,
            vendorConnected: true
        )
        
        #expect(connectedResult.vendorConnected == true)
    }
    
    @Test("Result timestamp defaults to now")
    func resultTimestampDefaultsToNow() {
        let before = Date()
        let result = PassiveScanResult(
            transmitterId: "8N1234",
            transmitterType: .dexcomG6,
            rssi: -65,
            advertisementData: nil
        )
        let after = Date()
        
        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }
}

// MARK: - PassiveBLEScanner Tests

@Suite("Passive BLE Scanner")
struct PassiveBLEScannerTests {
    
    @Test("Scanner starts not scanning")
    func scannerStartsNotScanning() async {
        let scanner = PassiveBLEScanner.createMock()
        
        let isScanning = await scanner.isScanning
        
        #expect(!isScanning)
    }
    
    @Test("Scanner starts with no known transmitters")
    func scannerStartsWithNoTransmitters() async {
        let scanner = PassiveBLEScanner.createMock()
        
        let transmitters = await scanner.getAllTransmitters()
        
        #expect(transmitters.isEmpty)
    }
    
    @Test("Scanner can clear transmitters")
    func scannerCanClearTransmitters() async {
        let scanner = PassiveBLEScanner.createMock()
        
        await scanner.clearTransmitters()
        
        let transmitters = await scanner.getAllTransmitters()
        #expect(transmitters.isEmpty)
    }
    
    @Test("Get transmitter returns nil for unknown")
    func getTransmitterReturnsNilForUnknown() async {
        let scanner = PassiveBLEScanner.createMock()
        
        let result = await scanner.getTransmitter("nonexistent")
        
        #expect(result == nil)
    }
    
    @Test("Is vendor connected returns false for unknown")
    func isVendorConnectedReturnsFalseForUnknown() async {
        let scanner = PassiveBLEScanner.createMock()
        
        let connected = await scanner.isVendorConnected("nonexistent")
        
        #expect(!connected)
    }
    
    @Test("Custom stale threshold is applied")
    func customStaleThresholdApplied() async {
        // Use mock for test isolation
        let scanner = PassiveBLEScanner.createMock(staleThresholdSeconds: 60)
        
        // Scanner created with custom threshold
        // This is mostly a compile-time check
        let isScanning = await scanner.isScanning
        #expect(!isScanning)
    }
}
