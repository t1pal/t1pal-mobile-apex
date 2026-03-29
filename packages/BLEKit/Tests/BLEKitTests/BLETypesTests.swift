// SPDX-License-Identifier: MIT
//
// BLETypesTests.swift
// BLEKitTests
//
// Unit tests for BLE types.

import Testing
import Foundation
@testable import BLEKit

@Suite("BLEUUID Tests")
struct BLEUUIDTests {
    
    @Test("Create BLEUUID from 16-bit short UUID")
    func shortUUID() {
        let uuid = BLEUUID(short: 0x180D) // Heart Rate Service
        
        #expect(uuid.shortUUID == 0x180D)
        #expect(uuid.description == "180D")
    }
    
    @Test("Create BLEUUID from UUID string")
    func uuidString() {
        let uuid = BLEUUID(string: "F8083532-849E-531C-C594-30F1F86A4EA5")
        
        #expect(uuid != nil)
        #expect(uuid?.description == "F8083532-849E-531C-C594-30F1F86A4EA5")
    }
    
    @Test("BLEUUID string parsing handles lowercase")
    func lowercaseString() {
        let uuid = BLEUUID(string: "f8083532-849e-531c-c594-30f1f86a4ea5")
        
        #expect(uuid != nil)
    }
    
    @Test("BLEUUID string parsing handles no dashes")
    func noDashes() {
        let uuid = BLEUUID(string: "F8083532849E531CC59430F1F86A4EA5")
        
        #expect(uuid != nil)
    }
    
    @Test("BLEUUID invalid string returns nil")
    func invalidString() {
        let uuid = BLEUUID(string: "invalid")
        
        #expect(uuid == nil)
    }
    
    @Test("Dexcom UUIDs are defined correctly")
    func dexcomUUIDs() {
        #expect(BLEUUID.dexcomAdvertisement.shortUUID == 0xFEBC)
        #expect(BLEUUID.dexcomService.description == "F8083532-849E-531C-C594-30F1F86A4EA5")
        #expect(BLEUUID.dexcomCommunication.description == "F8083533-849E-531C-C594-30F1F86A4EA5")
        #expect(BLEUUID.dexcomControl.description == "F8083534-849E-531C-C594-30F1F86A4EA5")
        #expect(BLEUUID.dexcomAuthentication.description == "F8083535-849E-531C-C594-30F1F86A4EA5")
        #expect(BLEUUID.dexcomBackfill.description == "F8083536-849E-531C-C594-30F1F86A4EA5")
    }
    
    /// Validate Libre 2 BLE UUIDs against LibreTransmitter/Bluetooth/Transmitter/Libre2DirectTransmitter.swift:37-40
    @Test("Libre 2 UUIDs match LibreTransmitter")
    func libre2UUIDs() {
        // Source: externals/LibreTransmitter/Bluetooth/Transmitter/Libre2DirectTransmitter.swift
        // Lines 37-40:
        //   static var writeCharacteristic: UUIDContainer? = "F001"
        //   static var notifyCharacteristic: UUIDContainer? = "F002"
        //   static var serviceUUID: [UUIDContainer] = ["FDE3"]
        #expect(BLEUUID.libre2Service.shortUUID == 0xFDE3, "Service UUID must be FDE3 (Libre2DirectTransmitter.swift:40)")
        #expect(BLEUUID.libre2WriteCharacteristic.shortUUID == 0xF001, "Write characteristic must be F001 (Libre2DirectTransmitter.swift:37)")
        #expect(BLEUUID.libre2NotifyCharacteristic.shortUUID == 0xF002, "Notify characteristic must be F002 (Libre2DirectTransmitter.swift:38)")
    }
    
    @Test("BLEUUID hashable")
    func hashable() {
        let uuid1 = BLEUUID(short: 0x180D)
        let uuid2 = BLEUUID(short: 0x180D)
        let uuid3 = BLEUUID(short: 0x180F)
        
        #expect(uuid1 == uuid2)
        #expect(uuid1 != uuid3)
        
        var set: Set<BLEUUID> = []
        set.insert(uuid1)
        set.insert(uuid2)
        
        #expect(set.count == 1)
    }
    
    @Test("BLEUUID from Foundation UUID")
    func foundationUUID() {
        let foundation = UUID()
        let ble = BLEUUID(foundation)
        
        #expect(ble.data.count == 16)
    }
}

@Suite("BLE States Tests")
struct BLEStatesTests {
    
    @Test("BLECentralState values")
    func centralStates() {
        let states: [BLECentralState] = [
            .unknown, .resetting, .unsupported,
            .unauthorized, .poweredOff, .poweredOn
        ]
        
        #expect(states.count == 6)
    }
    
    @Test("BLEPeripheralState values")
    func peripheralStates() {
        let states: [BLEPeripheralState] = [
            .disconnected, .connecting, .connected, .disconnecting
        ]
        
        #expect(states.count == 4)
    }
}

@Suite("BLE Advertisement Tests")
struct BLEAdvertisementTests {
    
    @Test("Create advertisement with defaults")
    func defaultAdvertisement() {
        let ad = BLEAdvertisement()
        
        #expect(ad.localName == nil)
        #expect(ad.serviceUUIDs.isEmpty)
        #expect(ad.manufacturerData == nil)
        #expect(ad.isConnectable == true)
    }
    
    @Test("Create advertisement with values")
    func fullAdvertisement() {
        let ad = BLEAdvertisement(
            localName: "Dexcom G7",
            serviceUUIDs: [.dexcomAdvertisement],
            manufacturerData: Data([0x01, 0x02]),
            isConnectable: true
        )
        
        #expect(ad.localName == "Dexcom G7")
        #expect(ad.serviceUUIDs.count == 1)
        #expect(ad.manufacturerData?.count == 2)
    }
}

@Suite("BLE Characteristic Properties Tests")
struct BLECharacteristicPropertiesTests {
    
    @Test("Characteristic properties flags")
    func propertyFlags() {
        let props: BLECharacteristicProperties = [.read, .notify]
        
        #expect(props.contains(.read))
        #expect(props.contains(.notify))
        #expect(!props.contains(.write))
        #expect(!props.contains(.indicate))
    }
}

@Suite("BLE Error Tests")
struct BLEErrorTests {
    
    @Test("BLE errors are Error type")
    func errorsConformToError() {
        let errors: [BLEError] = [
            .notPoweredOn,
            .unauthorized,
            .unsupported,
            .scanFailed("test"),
            .connectionFailed("test"),
            .connectionTimeout,
            .disconnected,
            .serviceNotFound(BLEUUID(short: 0x180D)),
            .characteristicNotFound(BLEUUID(short: 0x2A37)),
            .readFailed("test"),
            .writeFailed("test"),
            .notificationFailed("test"),
            .invalidState("test")
        ]
        
        #expect(errors.count == 13)
    }
}
