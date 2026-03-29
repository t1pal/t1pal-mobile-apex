// SPDX-License-Identifier: MIT
//
// DeviceInfoServiceTests.swift
// BLEKit
//
// Tests for Device Information Service reader
// Trace: BLE-DIAG-001

import Foundation
import Testing
@testable import BLEKit

// MARK: - UUID Tests

@Suite("DeviceInfoServiceUUIDs")
struct DeviceInfoServiceUUIDTests {
    @Test("Service UUID")
    func deviceInfoServiceUUID() {
        let uuid = DeviceInfoServiceUUIDs.service
        #expect(uuid.shortUUID == 0x180A)
    }
    
    @Test("Characteristic UUIDs")
    func characteristicUUIDs() {
        #expect(DeviceInfoServiceUUIDs.manufacturerName.shortUUID == 0x2A29)
        #expect(DeviceInfoServiceUUIDs.modelNumber.shortUUID == 0x2A24)
        #expect(DeviceInfoServiceUUIDs.serialNumber.shortUUID == 0x2A25)
        #expect(DeviceInfoServiceUUIDs.hardwareRevision.shortUUID == 0x2A27)
        #expect(DeviceInfoServiceUUIDs.firmwareRevision.shortUUID == 0x2A26)
        #expect(DeviceInfoServiceUUIDs.softwareRevision.shortUUID == 0x2A28)
        #expect(DeviceInfoServiceUUIDs.systemID.shortUUID == 0x2A23)
    }
    
    @Test("All characteristics count")
    func allCharacteristicsCount() {
        #expect(DeviceInfoServiceUUIDs.allCharacteristics.count == 7)
    }
}

// MARK: - Parser Tests

@Suite("DeviceInfoParser")
struct DeviceInfoParserTests {
    @Test("Parse string")
    func parseString() {
        let data = Data("Dexcom".utf8)
        let result = DeviceInfoParser.parseString(data)
        #expect(result == "Dexcom")
    }
    
    @Test("Parse string with null terminator")
    func parseStringWithNullTerminator() {
        var data = Data("G6".utf8)
        data.append(0x00)
        let result = DeviceInfoParser.parseString(data)
        #expect(result == "G6")
    }
    
    @Test("Parse empty string")
    func parseStringEmpty() {
        let data = Data()
        let result = DeviceInfoParser.parseString(data)
        #expect(result == "")
    }
    
    @Test("Parse system ID")
    func parseSystemID() {
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let result = DeviceInfoParser.parseSystemID(data)
        #expect(result == "01:02:03:04:05:06:07:08")
    }
    
    @Test("Parse system ID too short")
    func parseSystemIDTooShort() {
        let data = Data([0x01, 0x02, 0x03])
        let result = DeviceInfoParser.parseSystemID(data)
        #expect(result == nil)
    }
}

// MARK: - DeviceInfo Tests

@Suite("DeviceInfo")
struct DeviceInfoTests {
    @Test("Init empty")
    func deviceInfoInitEmpty() {
        let info = DeviceInfo()
        #expect(!info.hasInfo)
        #expect(info.summary == "Unknown Device")
    }
    
    @Test("With manufacturer")
    func deviceInfoWithManufacturer() {
        let info = DeviceInfo(manufacturerName: "Dexcom")
        #expect(info.hasInfo)
        #expect(info.summary == "Dexcom")
    }
    
    @Test("Full summary")
    func deviceInfoFullSummary() {
        let info = DeviceInfo(
            manufacturerName: "Dexcom",
            modelNumber: "G6",
            firmwareRevision: "1.2.3"
        )
        #expect(info.summary == "Dexcom G6 FW: 1.2.3")
    }
    
    @Test("Codable encoding/decoding")
    func deviceInfoCodable() throws {
        let original = DeviceInfo(
            manufacturerName: "Abbott",
            modelNumber: "Libre 2",
            serialNumber: "ABC123",
            hardwareRevision: "1.0",
            firmwareRevision: "2.1.0",
            softwareRevision: "3.0",
            systemID: "01:02:03:04:05:06:07:08",
            deviceIdentifier: "test-device-uuid"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DeviceInfo.self, from: data)
        
        #expect(decoded.manufacturerName == original.manufacturerName)
        #expect(decoded.modelNumber == original.modelNumber)
        #expect(decoded.serialNumber == original.serialNumber)
        #expect(decoded.hardwareRevision == original.hardwareRevision)
        #expect(decoded.firmwareRevision == original.firmwareRevision)
        #expect(decoded.softwareRevision == original.softwareRevision)
        #expect(decoded.systemID == original.systemID)
        #expect(decoded.deviceIdentifier == original.deviceIdentifier)
    }
}

// MARK: - Parser Update Tests

@Suite("DeviceInfoParser Update")
struct DeviceInfoParserUpdateTests {
    @Test("Update manufacturer name")
    func updateManufacturerName() {
        var info = DeviceInfo()
        let data = Data("Dexcom".utf8)
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: DeviceInfoServiceUUIDs.manufacturerName,
            data: data
        )
        
        #expect(info.manufacturerName == "Dexcom")
    }
    
    @Test("Update model number")
    func updateModelNumber() {
        var info = DeviceInfo()
        let data = Data("G7".utf8)
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: DeviceInfoServiceUUIDs.modelNumber,
            data: data
        )
        
        #expect(info.modelNumber == "G7")
    }
    
    @Test("Update firmware revision")
    func updateFirmwareRevision() {
        var info = DeviceInfo()
        let data = Data("1.4.2.10".utf8)
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: DeviceInfoServiceUUIDs.firmwareRevision,
            data: data
        )
        
        #expect(info.firmwareRevision == "1.4.2.10")
    }
    
    @Test("Update hardware revision")
    func updateHardwareRevision() {
        var info = DeviceInfo()
        let data = Data("Rev B".utf8)
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: DeviceInfoServiceUUIDs.hardwareRevision,
            data: data
        )
        
        #expect(info.hardwareRevision == "Rev B")
    }
    
    @Test("Update system ID")
    func updateSystemID() {
        var info = DeviceInfo()
        let data = Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89])
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: DeviceInfoServiceUUIDs.systemID,
            data: data
        )
        
        #expect(info.systemID == "AB:CD:EF:01:23:45:67:89")
    }
    
    @Test("Update unknown characteristic")
    func updateUnknownCharacteristic() {
        var info = DeviceInfo()
        let unknownUUID = BLEUUID(short: 0x1234)
        let data = Data("test".utf8)
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: unknownUUID,
            data: data
        )
        
        // Should not crash, info should remain empty
        #expect(!info.hasInfo)
    }
    
    @Test("Update multiple characteristics")
    func updateMultipleCharacteristics() {
        var info = DeviceInfo()
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: DeviceInfoServiceUUIDs.manufacturerName,
            data: Data("Medtronic".utf8)
        )
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: DeviceInfoServiceUUIDs.modelNumber,
            data: Data("670G".utf8)
        )
        
        DeviceInfoParser.update(
            deviceInfo: &info,
            characteristic: DeviceInfoServiceUUIDs.firmwareRevision,
            data: Data("4.0".utf8)
        )
        
        #expect(info.manufacturerName == "Medtronic")
        #expect(info.modelNumber == "670G")
        #expect(info.firmwareRevision == "4.0")
        #expect(info.summary == "Medtronic 670G FW: 4.0")
    }
}

// MARK: - Error Tests

@Suite("DeviceInfoError")
struct DeviceInfoErrorTests {
    @Test("Error descriptions")
    func deviceInfoErrorDescriptions() {
        #expect(DeviceInfoError.notConnected.errorDescription != nil)
        #expect(DeviceInfoError.serviceNotFound.errorDescription != nil)
        #expect(DeviceInfoError.characteristicNotFound(DeviceInfoServiceUUIDs.firmwareRevision).errorDescription != nil)
        #expect(DeviceInfoError.readFailed("test").errorDescription != nil)
        #expect(DeviceInfoError.timeout.errorDescription != nil)
    }
}
