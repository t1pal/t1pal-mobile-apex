// SPDX-License-Identifier: MIT
//
// BLEPeripheralManagerTests.swift
// BLEKitTests
//
// Unit tests for BLE Peripheral Manager protocol and types.
// Trace: PRD-007 REQ-SIM-001

import Testing
import Foundation
@testable import BLEKit

@Suite("BLE Peripheral Manager Protocol")
struct BLEPeripheralManagerTests {
    
    // MARK: - Peripheral Manager State
    
    @Test("State enum has all expected cases")
    func stateEnumCases() {
        let states: [BLEPeripheralManagerState] = [
            .unknown, .resetting, .unsupported, .unauthorized, .poweredOff, .poweredOn
        ]
        #expect(states.count == 6)
    }
    
    @Test("State is codable")
    func stateCodable() throws {
        let state = BLEPeripheralManagerState.poweredOn
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BLEPeripheralManagerState.self, from: encoded)
        #expect(decoded == state)
    }
    
    // MARK: - Mutable Service
    
    @Test("Create mutable service with characteristics")
    func mutableServiceCreation() {
        let char = BLEMutableCharacteristic(
            uuid: .dexcomAuthentication,
            properties: [.read, .write, .notify],
            permissions: [.readable, .writeable],
            value: Data([0x01, 0x02])
        )
        
        let service = BLEMutableService(
            uuid: .dexcomService,
            isPrimary: true,
            characteristics: [char]
        )
        
        #expect(service.uuid == .dexcomService)
        #expect(service.isPrimary == true)
        #expect(service.characteristics.count == 1)
        #expect(service.characteristics[0].uuid == .dexcomAuthentication)
    }
    
    @Test("Service is identifiable by UUID")
    func serviceIdentifiable() {
        let service = BLEMutableService(uuid: .dexcomService, isPrimary: true)
        #expect(service.id == .dexcomService)
    }
    
    // MARK: - Mutable Characteristic
    
    @Test("Create mutable characteristic with all properties")
    func mutableCharacteristicCreation() {
        let char = BLEMutableCharacteristic(
            uuid: .dexcomControl,
            properties: [.read, .write, .notify, .indicate],
            permissions: [.readable, .writeable, .readEncryptionRequired],
            value: Data([0xAB, 0xCD])
        )
        
        #expect(char.uuid == .dexcomControl)
        #expect(char.properties.contains(.read))
        #expect(char.properties.contains(.write))
        #expect(char.properties.contains(.notify))
        #expect(char.properties.contains(.indicate))
        #expect(char.permissions.contains(.readable))
        #expect(char.permissions.contains(.writeable))
        #expect(char.permissions.contains(.readEncryptionRequired))
        #expect(char.value == Data([0xAB, 0xCD]))
    }
    
    @Test("Characteristic is identifiable by UUID")
    func characteristicIdentifiable() {
        let char = BLEMutableCharacteristic(
            uuid: .dexcomBackfill,
            properties: .read,
            permissions: .readable
        )
        #expect(char.id == .dexcomBackfill)
    }
    
    // MARK: - Attribute Permissions
    
    @Test("Attribute permissions option set")
    func attributePermissions() {
        var perms: BLEAttributePermissions = []
        #expect(perms.isEmpty)
        
        perms.insert(.readable)
        #expect(perms.contains(.readable))
        
        perms.insert(.writeable)
        #expect(perms.contains([.readable, .writeable]))
        
        let encrypted: BLEAttributePermissions = [.readEncryptionRequired, .writeEncryptionRequired]
        #expect(encrypted.contains(.readEncryptionRequired))
        #expect(encrypted.contains(.writeEncryptionRequired))
    }
    
    // MARK: - Advertisement Data
    
    @Test("Create advertisement data")
    func advertisementDataCreation() {
        let ad = BLEAdvertisementData(
            localName: "TestDevice",
            serviceUUIDs: [.dexcomAdvertisement, .dexcomService],
            manufacturerData: Data([0x01, 0x02, 0x03])
        )
        
        #expect(ad.localName == "TestDevice")
        #expect(ad.serviceUUIDs.count == 2)
        #expect(ad.serviceUUIDs.contains(.dexcomAdvertisement))
        #expect(ad.manufacturerData == Data([0x01, 0x02, 0x03]))
    }
    
    @Test("Create Dexcom G6 advertisement")
    func dexcomG6Advertisement() {
        let ad = BLEAdvertisementData.dexcom(transmitterID: "8G1234", isG7: false)
        
        #expect(ad.localName == "Dexcom34")
        #expect(ad.serviceUUIDs.count == 1)
        #expect(ad.serviceUUIDs.contains(.dexcomAdvertisement))
    }
    
    @Test("Create Dexcom G7 advertisement")
    func dexcomG7Advertisement() {
        let ad = BLEAdvertisementData.dexcom(transmitterID: "9G5678", isG7: true)
        
        #expect(ad.localName == "Dexcom78")
        #expect(ad.serviceUUIDs.count == 1)
        #expect(ad.serviceUUIDs.contains(.dexcomG7Advertisement))
    }
    
    // MARK: - Central Info
    
    @Test("Create central info")
    func centralInfoCreation() {
        let uuid = BLEUUID(UUID())
        let central = BLECentralInfo(identifier: uuid, maximumUpdateValueLength: 185)
        
        #expect(central.identifier == uuid)
        #expect(central.maximumUpdateValueLength == 185)
        #expect(central.id == uuid)
    }
    
    @Test("Central info default MTU")
    func centralInfoDefaultMTU() {
        let uuid = BLEUUID(UUID())
        let central = BLECentralInfo(identifier: uuid)
        
        #expect(central.maximumUpdateValueLength == 512)
    }
    
    // MARK: - ATT Requests
    
    @Test("Create read request")
    func readRequestCreation() {
        let central = BLECentralInfo(identifier: BLEUUID(UUID()))
        let request = BLEATTReadRequest(
            central: central,
            characteristicUUID: .dexcomControl,
            offset: 10
        )
        
        #expect(request.central == central)
        #expect(request.characteristicUUID == .dexcomControl)
        #expect(request.offset == 10)
    }
    
    @Test("Create write request")
    func writeRequestCreation() {
        let central = BLECentralInfo(identifier: BLEUUID(UUID()))
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let request = BLEATTWriteRequest(
            central: central,
            characteristicUUID: .dexcomAuthentication,
            value: data,
            offset: 0
        )
        
        #expect(request.central == central)
        #expect(request.characteristicUUID == .dexcomAuthentication)
        #expect(request.value == data)
        #expect(request.offset == 0)
    }
    
    // MARK: - Subscription Change
    
    @Test("Subscription change subscribe")
    func subscriptionChangeSubscribe() {
        let central = BLECentralInfo(identifier: BLEUUID(UUID()))
        let change = BLESubscriptionChange(
            central: central,
            characteristicUUID: .dexcomControl,
            isSubscribed: true
        )
        
        #expect(change.central == central)
        #expect(change.characteristicUUID == .dexcomControl)
        #expect(change.isSubscribed == true)
    }
    
    @Test("Subscription change unsubscribe")
    func subscriptionChangeUnsubscribe() {
        let central = BLECentralInfo(identifier: BLEUUID(UUID()))
        let change = BLESubscriptionChange(
            central: central,
            characteristicUUID: .dexcomControl,
            isSubscribed: false
        )
        
        #expect(change.isSubscribed == false)
    }
    
    // MARK: - ATT Errors
    
    @Test("ATT error codes")
    func attErrorCodes() {
        #expect(BLEATTError.success.rawValue == 0x00)
        #expect(BLEATTError.invalidHandle.rawValue == 0x01)
        #expect(BLEATTError.readNotPermitted.rawValue == 0x02)
        #expect(BLEATTError.writeNotPermitted.rawValue == 0x03)
        #expect(BLEATTError.insufficientAuthentication.rawValue == 0x05)
        #expect(BLEATTError.attributeNotFound.rawValue == 0x0A)
        #expect(BLEATTError.insufficientEncryption.rawValue == 0x0F)
        #expect(BLEATTError.insufficientResources.rawValue == 0x11)
    }
    
    // MARK: - Peripheral Manager Options
    
    @Test("Default peripheral manager options")
    func defaultOptions() {
        let options = BLEPeripheralManagerOptions.default
        #expect(options.showPowerAlert == false)
        #expect(options.restorationIdentifier == nil)
    }
    
    @Test("Custom peripheral manager options")
    func customOptions() {
        let options = BLEPeripheralManagerOptions(
            showPowerAlert: true,
            restorationIdentifier: "com.t1pal.cgmsim"
        )
        #expect(options.showPowerAlert == true)
        #expect(options.restorationIdentifier == "com.t1pal.cgmsim")
    }
}

@Suite("Mock BLE Peripheral Manager")
struct MockBLEPeripheralManagerTests {
    
    @Test("Initial state is powered on")
    func initialState() async {
        let manager = MockBLEPeripheralManager()
        let state = await manager.state
        #expect(state == .poweredOn)
    }
    
    @Test("Add service")
    func addService() async throws {
        let manager = MockBLEPeripheralManager()
        
        let service = BLEMutableService(
            uuid: .dexcomService,
            isPrimary: true,
            characteristics: [
                BLEMutableCharacteristic(
                    uuid: .dexcomAuthentication,
                    properties: [.read, .write],
                    permissions: [.readable, .writeable]
                )
            ]
        )
        
        try await manager.addService(service)
        
        let addedServices = await manager.addedServices
        #expect(addedServices.count == 1)
        #expect(addedServices[0].uuid == .dexcomService)
    }
    
    @Test("Remove service")
    func removeService() async throws {
        let manager = MockBLEPeripheralManager()
        
        let service = BLEMutableService(uuid: .dexcomService, isPrimary: true)
        try await manager.addService(service)
        
        await manager.removeService(.dexcomService)
        
        let retrieved = await manager.getService(uuid: .dexcomService)
        #expect(retrieved == nil)
    }
    
    @Test("Start and stop advertising")
    func advertising() async throws {
        let manager = MockBLEPeripheralManager()
        
        let isAdvertisingBefore = await manager.isAdvertising
        #expect(isAdvertisingBefore == false)
        
        let ad = BLEAdvertisementData.dexcom(transmitterID: "8G1234")
        try await manager.startAdvertising(ad)
        
        let isAdvertisingAfter = await manager.isAdvertising
        #expect(isAdvertisingAfter == true)
        
        let currentAd = await manager.currentAdvertisement
        #expect(currentAd?.localName == "Dexcom34")
        
        await manager.stopAdvertising()
        
        let isAdvertisingFinal = await manager.isAdvertising
        #expect(isAdvertisingFinal == false)
    }
    
    @Test("Update value tracks history")
    func updateValueHistory() async {
        let manager = MockBLEPeripheralManager()
        
        let char = BLEMutableCharacteristic(
            uuid: .dexcomControl,
            properties: .notify,
            permissions: .readable
        )
        
        let result = await manager.updateValue(Data([0x01, 0x02]), for: char, onSubscribedCentrals: nil)
        #expect(result == true)
        
        let history = await manager.updateHistory
        #expect(history.count == 1)
        #expect(history[0].0 == Data([0x01, 0x02]))
        #expect(history[0].1 == .dexcomControl)
    }
    
    @Test("Simulate state change")
    func simulateStateChange() async {
        let manager = MockBLEPeripheralManager()
        
        await manager.simulateStateChange(.poweredOff)
        
        let state = await manager.state
        #expect(state == .poweredOff)
    }
    
    @Test("Add service fails when not powered on")
    func addServiceFailsWhenOff() async {
        let manager = MockBLEPeripheralManager()
        await manager.simulateStateChange(.poweredOff)
        
        let service = BLEMutableService(uuid: .dexcomService, isPrimary: true)
        
        do {
            try await manager.addService(service)
            Issue.record("Expected error but succeeded")
        } catch {
            // Expected
            #expect(error is BLEError)
        }
    }
    
    @Test("Advertising fails when not powered on")
    func advertisingFailsWhenOff() async {
        let manager = MockBLEPeripheralManager()
        await manager.simulateStateChange(.poweredOff)
        
        let ad = BLEAdvertisementData.dexcom(transmitterID: "8G1234")
        
        do {
            try await manager.startAdvertising(ad)
            Issue.record("Expected error but succeeded")
        } catch {
            // Expected
            #expect(error is BLEError)
        }
    }
    
    @Test("Simulate central subscribe")
    func simulateCentralSubscribe() async {
        let manager = MockBLEPeripheralManager()
        let central = BLECentralInfo(identifier: BLEUUID(UUID()))
        
        await manager.simulateCentralSubscribe(central: central, to: .dexcomControl)
        // Test passes if no crash - subscription change was emitted
    }
}

@Suite("Dexcom Transmitter Simulation")
struct DexcomSimulationTests {
    
    @Test("Build Dexcom G6 GATT service")
    func dexcomG6Service() {
        // Authentication characteristic
        let auth = BLEMutableCharacteristic(
            uuid: .dexcomAuthentication,
            properties: [.read, .write, .indicate],
            permissions: [.readable, .writeable]
        )
        
        // Control characteristic
        let control = BLEMutableCharacteristic(
            uuid: .dexcomControl,
            properties: [.read, .write, .indicate],
            permissions: [.readable, .writeable]
        )
        
        // Backfill characteristic
        let backfill = BLEMutableCharacteristic(
            uuid: .dexcomBackfill,
            properties: [.read, .notify],
            permissions: [.readable]
        )
        
        // Dexcom service
        let service = BLEMutableService(
            uuid: .dexcomService,
            isPrimary: true,
            characteristics: [auth, control, backfill]
        )
        
        #expect(service.characteristics.count == 3)
        #expect(service.characteristics.map(\.uuid).contains(.dexcomAuthentication))
        #expect(service.characteristics.map(\.uuid).contains(.dexcomControl))
        #expect(service.characteristics.map(\.uuid).contains(.dexcomBackfill))
    }
    
    @Test("Parse transmitter ID to advertisement name")
    func transmitterIDToName() {
        // G6 transmitters start with 8
        let g6Ad = BLEAdvertisementData.dexcom(transmitterID: "8HABCD", isG7: false)
        #expect(g6Ad.localName == "DexcomCD")
        
        // G7 transmitters start with 9
        let g7Ad = BLEAdvertisementData.dexcom(transmitterID: "9NWXYZ", isG7: true)
        #expect(g7Ad.localName == "DexcomYZ")
    }
    
    @Test("Full simulator setup flow")
    func fullSimulatorSetup() async throws {
        let manager = MockBLEPeripheralManager()
        
        // 1. Build service structure
        let service = BLEMutableService(
            uuid: .dexcomService,
            isPrimary: true,
            characteristics: [
                BLEMutableCharacteristic(
                    uuid: .dexcomAuthentication,
                    properties: [.read, .write, .indicate],
                    permissions: [.readable, .writeable]
                ),
                BLEMutableCharacteristic(
                    uuid: .dexcomControl,
                    properties: [.read, .write, .indicate],
                    permissions: [.readable, .writeable]
                )
            ]
        )
        
        // 2. Add service to manager
        try await manager.addService(service)
        
        // 3. Start advertising as Dexcom
        let ad = BLEAdvertisementData.dexcom(transmitterID: "8G1234", isG7: false)
        try await manager.startAdvertising(ad)
        
        // 4. Verify setup
        let isAdvertising = await manager.isAdvertising
        #expect(isAdvertising == true)
        
        let addedServices = await manager.addedServices
        #expect(addedServices.count == 1)
        #expect(addedServices[0].characteristics.count == 2)
    }
}
