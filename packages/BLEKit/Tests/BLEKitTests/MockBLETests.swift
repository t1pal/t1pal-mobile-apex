// SPDX-License-Identifier: MIT
//
// MockBLETests.swift
// BLEKitTests
//
// Unit tests for mock BLE implementations.

import Testing
import Foundation
@testable import BLEKit

@Suite("MockBLECentral Tests", .serialized)
struct MockBLECentralTests {
    
    @Test("Central starts in powered on state")
    func initialState() async {
        let central = MockBLECentral()
        
        let state = await central.state
        #expect(state == .poweredOn)
    }
    
    @Test("Central state can be changed")
    func stateChange() async {
        let central = MockBLECentral()
        
        await central.setState(.poweredOff)
        let state = await central.state
        
        #expect(state == .poweredOff)
    }
    
    @Test("Scan fails when not powered on")
    func scanFailsWhenOff() async {
        let central = MockBLECentral()
        await central.setState(.poweredOff)
        
        var gotError = false
        let stream = central.scan(for: nil)
        
        do {
            for try await _ in stream {
                break
            }
        } catch {
            gotError = true
            #expect(error is BLEError)
        }
        
        #expect(gotError)
    }
    
    @Test("Scan returns mock results")
    func scanReturnsMockResults() async throws {
        let central = MockBLECentral()
        
        let mockResult = BLEScanResult(
            peripheral: BLEPeripheralInfo(identifier: BLEUUID(short: 0x1234), name: "Test Device"),
            rssi: -50,
            advertisement: BLEAdvertisement(serviceUUIDs: [.dexcomAdvertisement])
        )
        await central.addScanResult(mockResult)
        
        var results: [BLEScanResult] = []
        let stream = central.scan(for: nil)
        
        // Collect one result then stop
        for try await result in stream {
            results.append(result)
            await central.stopScan()
            break
        }
        
        #expect(results.count >= 1)
        #expect(results.first?.peripheral.name == "Test Device")
    }
    
    @Test("Connect returns mock peripheral")
    func connectReturnsPeripheral() async throws {
        let central = MockBLECentral()
        
        let peripheralInfo = BLEPeripheralInfo(identifier: BLEUUID(short: 0x1234), name: "Test")
        let peripheral = try await central.connect(to: peripheralInfo)
        
        let state = await peripheral.state
        #expect(state == .connected)
    }
    
    @Test("Connect fails when not powered on")
    func connectFailsWhenOff() async {
        let central = MockBLECentral()
        await central.setState(.poweredOff)
        
        let peripheralInfo = BLEPeripheralInfo(identifier: BLEUUID(short: 0x1234), name: "Test")
        
        do {
            _ = try await central.connect(to: peripheralInfo)
            Issue.record("Expected error")
        } catch {
            #expect(error is BLEError)
        }
    }
    
    @Test("Connect throws configured error")
    func connectWithConfiguredError() async {
        let central = MockBLECentral()
        await central.setConnectError(.connectionTimeout)
        
        let peripheralInfo = BLEPeripheralInfo(identifier: BLEUUID(short: 0x1234), name: "Test")
        
        do {
            _ = try await central.connect(to: peripheralInfo)
            Issue.record("Expected error")
        } catch let error as BLEError {
            if case .connectionTimeout = error {
                // Expected
            } else {
                Issue.record("Wrong error type")
            }
        } catch {
            Issue.record("Wrong error type")
        }
    }
    
    @Test("Disconnect changes peripheral state")
    func disconnect() async throws {
        let central = MockBLECentral()
        
        let peripheralInfo = BLEPeripheralInfo(identifier: BLEUUID(short: 0x1234), name: "Test")
        let peripheral = try await central.connect(to: peripheralInfo)
        
        await central.disconnect(peripheral)
        
        let state = await peripheral.state
        #expect(state == .disconnected)
    }
    
    @Test("Reset clears mock data")
    func reset() async {
        let central = MockBLECentral()
        
        await central.addScanResult(BLEScanResult(
            peripheral: BLEPeripheralInfo(identifier: BLEUUID(short: 0x1234), name: nil),
            rssi: -50,
            advertisement: BLEAdvertisement()
        ))
        await central.setConnectError(.connectionTimeout)
        
        await central.reset()
        
        // Connect should work after reset
        let peripheralInfo = BLEPeripheralInfo(identifier: BLEUUID(short: 0x1234), name: "Test")
        let peripheral = try? await central.connect(to: peripheralInfo)
        
        #expect(peripheral != nil)
    }
}

@Suite("MockBLEPeripheral Tests", .serialized)
struct MockBLEPeripheralTests {
    
    @Test("Peripheral has identifier and name")
    func identifierAndName() async {
        let id = BLEUUID(short: 0x1234)
        let peripheral = MockBLEPeripheral(identifier: id, name: "Test Device")
        
        #expect(peripheral.identifier == id)
        #expect(peripheral.name == "Test Device")
    }
    
    @Test("Discover services when connected")
    func discoverServices() async throws {
        let peripheral = MockBLEPeripheral(identifier: BLEUUID(short: 0x1234), name: nil)
        await peripheral.setState(.connected)
        
        let service = BLEService(uuid: .dexcomService, isPrimary: true)
        await peripheral.addService(service)
        
        let services = try await peripheral.discoverServices(nil)
        
        #expect(services.count == 1)
        #expect(services.first?.uuid == .dexcomService)
    }
    
    @Test("Discover services fails when disconnected")
    func discoverServicesFailsWhenDisconnected() async {
        let peripheral = MockBLEPeripheral(identifier: BLEUUID(short: 0x1234), name: nil)
        
        do {
            _ = try await peripheral.discoverServices(nil)
            Issue.record("Expected error")
        } catch {
            #expect(error is BLEError)
        }
    }
    
    @Test("Discover characteristics for service")
    func discoverCharacteristics() async throws {
        let peripheral = MockBLEPeripheral(identifier: BLEUUID(short: 0x1234), name: nil)
        await peripheral.setState(.connected)
        
        let service = BLEService(uuid: .dexcomService, isPrimary: true)
        let char = BLECharacteristic(
            uuid: .dexcomControl,
            properties: [.write, .notify],
            serviceUUID: .dexcomService
        )
        await peripheral.addService(service)
        await peripheral.addCharacteristics([char], for: .dexcomService)
        
        let chars = try await peripheral.discoverCharacteristics(nil, for: service)
        
        #expect(chars.count == 1)
        #expect(chars.first?.uuid == .dexcomControl)
    }
    
    @Test("Read value from characteristic")
    func readValue() async throws {
        let peripheral = MockBLEPeripheral(identifier: BLEUUID(short: 0x1234), name: nil)
        await peripheral.setState(.connected)
        
        let char = BLECharacteristic(
            uuid: .dexcomControl,
            properties: [.read],
            serviceUUID: .dexcomService
        )
        await peripheral.setValue(Data([0x01, 0x02, 0x03]), for: .dexcomControl)
        
        let value = try await peripheral.readValue(for: char)
        
        #expect(value == Data([0x01, 0x02, 0x03]))
    }
    
    @Test("Write value to characteristic")
    func writeValue() async throws {
        let peripheral = MockBLEPeripheral(identifier: BLEUUID(short: 0x1234), name: nil)
        await peripheral.setState(.connected)
        
        let char = BLECharacteristic(
            uuid: .dexcomControl,
            properties: [.write],
            serviceUUID: .dexcomService
        )
        
        try await peripheral.writeValue(Data([0xAB, 0xCD]), for: char, type: .withResponse)
        
        // Read back to verify
        let value = try await peripheral.readValue(for: char)
        #expect(value == Data([0xAB, 0xCD]))
    }
    
    @Test("Disconnect changes peripheral state to disconnected")
    func disconnectState() async throws {
        let peripheral = MockBLEPeripheral(identifier: BLEUUID(short: 0x1234), name: nil)
        await peripheral.setState(.connected)
        
        await peripheral.disconnect()
        
        let state = await peripheral.state
        #expect(state == .disconnected)
    }
}
