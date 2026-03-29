// SPDX-License-Identifier: MIT
// LibreNFCReaderTests.swift
// CGMKit Tests
//
// Tests for Libre NFC parsing logic.
// Trace: CGM-022, REQ-CGM-002

import Testing
import Foundation
@testable import CGMKit

@Suite("Libre NFC Reader")
struct LibreNFCReaderTests {
    
    // MARK: - Sensor Family Detection
    
    @Test("Libre 1 detected from patchInfo 0xDF")
    func libre1DetectedFromPatchInfo() {
        let patchInfo = Data([0xDF, 0x00, 0x00, 0x00, 0x00, 0x00])
        let family = LibreSensorFamily(patchInfo: patchInfo)
        #expect(family == .libre1)
    }
    
    @Test("Libre 1 US detected from patchInfo 0xA2")
    func libre1USDetectedFromPatchInfo() {
        let patchInfo = Data([0xA2, 0x00, 0x00, 0x00, 0x00, 0x00])
        let family = LibreSensorFamily(patchInfo: patchInfo)
        #expect(family == .libre1US)
    }
    
    @Test("Libre 2 detected from patchInfo 0x9D with byte3=0")
    func libre2DetectedFromPatchInfo() {
        let patchInfo = Data([0x9D, 0x00, 0x00, 0x00, 0x00, 0x00])
        let family = LibreSensorFamily(patchInfo: patchInfo)
        #expect(family == .libre2)
    }
    
    @Test("Libre 2 US detected from patchInfo 0x9D with byte3=1")
    func libre2USDetectedFromPatchInfo() {
        let patchInfo = Data([0x9D, 0x00, 0x00, 0x01, 0x00, 0x00])
        let family = LibreSensorFamily(patchInfo: patchInfo)
        #expect(family == .libre2US)
    }
    
    @Test("Libre Pro detected from patchInfo 0x70")
    func libreProDetectedFromPatchInfo() {
        let patchInfo = Data([0x70, 0x00, 0x00, 0x00, 0x00, 0x00])
        let family = LibreSensorFamily(patchInfo: patchInfo)
        #expect(family == .librePro)
    }
    
    @Test("Unknown sensor from invalid patchInfo")
    func unknownSensorFromInvalidPatchInfo() {
        let patchInfo = Data([0xFF, 0x00, 0x00, 0x00, 0x00, 0x00])
        let family = LibreSensorFamily(patchInfo: patchInfo)
        #expect(family == .unknown)
    }
    
    @Test("Unknown sensor from short patchInfo")
    func unknownSensorFromShortPatchInfo() {
        let patchInfo = Data([0x9D, 0x00])  // Too short
        let family = LibreSensorFamily(patchInfo: patchInfo)
        #expect(family == .unknown)
    }
    
    // MARK: - Sensor State
    
    @Test("Sensor state not activated")
    func sensorStateNotActivated() {
        let state = LibreNFCSensorState(rawValue: 0x01)
        #expect(state == .notActivated)
        #expect(state?.isUsable == false)
    }
    
    @Test("Sensor state warming up")
    func sensorStateWarmingUp() {
        let state = LibreNFCSensorState(rawValue: 0x02)
        #expect(state == .warmingUp)
        #expect(state?.isUsable == true)
    }
    
    @Test("Sensor state active")
    func sensorStateActive() {
        let state = LibreNFCSensorState(rawValue: 0x03)
        #expect(state == .active)
        #expect(state?.isUsable == true)
    }
    
    @Test("Sensor state expired")
    func sensorStateExpired() {
        let state = LibreNFCSensorState(rawValue: 0x04)
        #expect(state == .expired)
        #expect(state?.isUsable == false)
    }
    
    @Test("Sensor state unknown for invalid value")
    func sensorStateUnknownForInvalidValue() {
        let state = LibreNFCSensorState(rawValue: 0x99)
        #expect(state == nil)
    }
    
    // MARK: - NFC Result Conversion
    
    @Test("NFC result converts to Libre2SensorInfo")
    func nfcResultConvertsToLibre2SensorInfo() {
        // Create mock FRAM with enableTime at bytes 317-320
        var fram = Data(repeating: 0x00, count: 344)
        // Set enableTime to 0x12345678 (little endian)
        fram[317] = 0x78
        fram[318] = 0x56
        fram[319] = 0x34
        fram[320] = 0x12
        // Set sensor state at byte 4
        fram[4] = 0x03  // Active
        
        let result = LibreNFCReadResult(
            sensorUID: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            patchInfo: Data([0x9D, 0x00, 0x00, 0x00, 0x00, 0x00]),
            fram: fram,
            sensorType: .libre2,
            serialNumber: "ABC12",
            sensorState: .active
        )
        
        let sensorInfo = result.toLibre2SensorInfo()
        
        #expect(sensorInfo.sensorUID.count == 8)
        #expect(sensorInfo.patchInfo.count == 6)
        #expect(sensorInfo.enableTime == 0x12345678)
        #expect(sensorInfo.serialNumber == "ABC12")
        #expect(sensorInfo.sensorType == .libre2)
    }
    
    @Test("Libre 2 US converts to libreUS14day type")
    func libre2USConvertsToLibreUS14day() {
        let result = LibreNFCReadResult(
            sensorUID: Data(repeating: 0x00, count: 8),
            patchInfo: Data([0x9D, 0x00, 0x00, 0x01, 0x00, 0x00]),
            fram: Data(repeating: 0x00, count: 344),
            sensorType: .libre2US,
            serialNumber: "TEST",
            sensorState: .active
        )
        
        let sensorInfo = result.toLibre2SensorInfo()
        #expect(sensorInfo.sensorType == .libreUS14day)
    }
    
    // MARK: - Error Descriptions
    
    @Test("NFC errors have descriptions")
    func nfcErrorsHaveDescriptions() {
        let errors: [LibreNFCError] = [
            .nfcNotSupported,
            .nfcNotAvailable,
            .sessionTimeout,
            .tagConnectionFailed,
            .commandFailed("test"),
            .invalidResponse,
            .sensorNotFound,
            .unsupportedSensorType,
            .userCancelled
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    // MARK: - NFC Availability
    
    @Test("NFC reader reports availability")
    func nfcReaderReportsAvailability() {
        let reader = LibreNFCReader()
        // On Linux, NFC is not available
        #if os(iOS)
        // May be true or false depending on device
        _ = reader.isNFCAvailable()
        #else
        #expect(reader.isNFCAvailable() == false)
        #endif
    }
}
