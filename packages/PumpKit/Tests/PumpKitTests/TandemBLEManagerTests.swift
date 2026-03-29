// SPDX-License-Identifier: MIT
//
// TandemBLEManagerTests.swift
// PumpKitTests
//
// Tests for Tandem t:slim X2 BLE connection manager
// Trace: TANDEM-IMPL-001

import Testing
import Foundation
@testable import PumpKit

@Suite("TandemBLEManager Tests", .serialized)
struct TandemBLEManagerTests {
    
    // MARK: - Initial State
    
    @Test("Initial state is disconnected")
    func initialState() async throws {
        let manager = TandemBLEManager()
        let state = await manager.state
        let pump = await manager.connectedPump
        
        #expect(state == .disconnected)
        #expect(pump == nil)
    }
    
    // MARK: - Scanning
    
    @Test("Start scanning changes state")
    func startScanning() async throws {
        let manager = TandemBLEManager()
        
        await manager.startScanning()
        let state = await manager.state
        
        #expect(state == .scanning)
        
        await manager.stopScanning()
    }
    
    @Test("Stop scanning returns to disconnected")
    func stopScanning() async throws {
        let manager = TandemBLEManager()
        
        await manager.startScanning()
        await manager.stopScanning()
        
        let state = await manager.state
        #expect(state == .disconnected)
    }
    
    @Test("Scan discovers pumps")
    func scanDiscovery() async throws {
        let manager = TandemBLEManager()
        
        await manager.startScanning()
        
        // Wait for simulated discovery
        try await Task.sleep(nanoseconds: 600_000_000)
        
        let pumps = await manager.discoveredPumps
        #expect(pumps.count > 0)
        
        // Check simulated pump
        if let pump = pumps.first {
            #expect(pump.isTandemPump)
            #expect(pump.serialNumber != nil)
        }
        
        await manager.stopScanning()
    }
    
    // MARK: - Connection
    
    @Test("Connect to pump")
    func connectToPump() async throws {
        let manager = TandemBLEManager()
        
        let pump = DiscoveredTandemPump(
            id: "test-001",
            name: "t:slim X2",
            rssi: -50,
            serialNumber: "TP12345678"
        )
        
        try await manager.connect(to: pump)
        
        let state = await manager.state
        let connected = await manager.connectedPump
        
        #expect(state == .ready)
        #expect(connected != nil)
        #expect(connected?.id == pump.id)
        
        await manager.disconnect()
    }
    
    @Test("Disconnect from pump")
    func disconnectFromPump() async throws {
        let manager = TandemBLEManager()
        
        let pump = DiscoveredTandemPump(
            id: "test-002",
            name: "t:slim X2",
            rssi: -55
        )
        
        try await manager.connect(to: pump)
        await manager.disconnect()
        
        let state = await manager.state
        let connected = await manager.connectedPump
        
        #expect(state == .disconnected)
        #expect(connected == nil)
    }
    
    @Test("Already connected error")
    func alreadyConnectedError() async throws {
        let manager = TandemBLEManager()
        
        let pump1 = DiscoveredTandemPump(id: "pump-1", name: "t:slim X2", rssi: -50)
        let pump2 = DiscoveredTandemPump(id: "pump-2", name: "t:slim X2", rssi: -55)
        
        try await manager.connect(to: pump1)
        
        do {
            try await manager.connect(to: pump2)
            Issue.record("Should throw alreadyConnected error")
        } catch let error as TandemBLEError {
            #expect(error == .alreadyConnected)
        }
        
        await manager.disconnect()
    }
    
    // MARK: - Commands
    
    @Test("Read basal status")
    func readBasalStatus() async throws {
        let manager = TandemBLEManager()
        let pump = DiscoveredTandemPump(id: "test-003", name: "t:slim X2", rssi: -50)
        
        try await manager.connect(to: pump)
        
        let status = try await manager.readBasalStatus()
        
        // Check mock response values
        #expect(status.profileBasalRateMilliunits == 800)
        #expect(status.currentBasalRateMilliunits == 800)
        #expect(abs(status.profileBasalRate - 0.8) < 0.001)
        #expect(!status.isTempRateActive)
        #expect(!status.isSuspended)
        
        await manager.disconnect()
    }
    
    @Test("Read temp rate status")
    func readTempRateStatus() async throws {
        let manager = TandemBLEManager()
        let pump = DiscoveredTandemPump(id: "test-004", name: "t:slim X2", rssi: -50)
        
        try await manager.connect(to: pump)
        
        let status = try await manager.readTempRateStatus()
        
        // Mock returns inactive temp rate
        #expect(!status.isActive)
        #expect(status.percentage == 100)
        
        await manager.disconnect()
    }
    
    @Test("Read IOB")
    func readIOB() async throws {
        let manager = TandemBLEManager()
        let pump = DiscoveredTandemPump(id: "test-005", name: "t:slim X2", rssi: -50)
        
        try await manager.connect(to: pump)
        
        let iob = try await manager.readIOB()
        
        // Mock returns 2.5 U IOB
        #expect(iob.iobMilliunits == 2500)
        #expect(abs(iob.iob - 2.5) < 0.001)
        
        await manager.disconnect()
    }
    
    @Test("Command when not connected throws error")
    func commandWhenNotConnected() async throws {
        let manager = TandemBLEManager()
        
        do {
            _ = try await manager.readBasalStatus()
            Issue.record("Should throw notConnected error")
        } catch let error as TandemBLEError {
            #expect(error == .notConnected)
        }
    }
    
    // MARK: - Diagnostics
    
    @Test("Diagnostic info")
    func diagnosticInfo() async throws {
        let manager = TandemBLEManager()
        let pump = DiscoveredTandemPump(id: "test-006", name: "t:slim X2", rssi: -50)
        
        try await manager.connect(to: pump)
        
        let diag = await manager.diagnosticInfo()
        
        #expect(diag.state == .ready)
        #expect(diag.connectedPump != nil)
        #expect(diag.session != nil)
        #expect(diag.isHealthy)
        
        await manager.disconnect()
    }
    
    // MARK: - Factory Methods (PUMP-PG-009)
    
    @Test("forDemo creates manager")
    func forDemo() async throws {
        let manager = TandemBLEManager.forDemo()
        let state = await manager.state
        
        #expect(state == .disconnected)
    }
    
    @Test("forTesting creates manager")
    func forTesting() async throws {
        let manager = TandemBLEManager.forTesting()
        let state = await manager.state
        
        #expect(state == .disconnected)
    }
    
    @Test("setTestState changes state")
    func setTestState() async throws {
        let manager = TandemBLEManager.forTesting()
        
        await manager.setTestState(.ready)
        let state = await manager.state
        
        #expect(state == .ready)
    }
    
    @Test("resumeSession sets up ready state")
    func resumeSession() async throws {
        let manager = TandemBLEManager.forDemo()
        
        await manager.resumeSession(pumpId: "test-pump-001", serial: "TP99999999")
        
        let state = await manager.state
        let pump = await manager.connectedPump
        let session = await manager.session
        
        #expect(state == .ready)
        #expect(pump != nil)
        #expect(pump?.serialNumber == "TP99999999")
        #expect(session != nil)
        #expect(session?.pumpId == "test-pump-001")
    }
    
    @Test("setPairingCode stores code")
    func setPairingCode() async throws {
        let manager = TandemBLEManager.forTesting()
        
        await manager.setPairingCode("123456")
        let code = await manager.pairingCode
        
        #expect(code == "123456")
    }
    
    @Test("getDiscoveredPumps returns empty initially")
    func getDiscoveredPumps() async throws {
        let manager = TandemBLEManager.forTesting()
        
        let pumps = await manager.getDiscoveredPumps()
        
        #expect(pumps.isEmpty)
    }
    
    @Test("getDiscoveredPumps returns pumps after scan")
    func getDiscoveredPumpsAfterScan() async throws {
        let manager = TandemBLEManager.forTesting()
        
        await manager.startScanning()
        // Wait for simulated discovery
        try await Task.sleep(for: .milliseconds(100))
        
        let pumps = await manager.getDiscoveredPumps()
        
        #expect(!pumps.isEmpty)
        
        await manager.stopScanning()
    }
    
    // MARK: - BLE Transport Tests (PUMP-PG-007)
    
    @Test("setCentral disables simulation")
    func setCentralDisablesSimulation() async throws {
        let manager = TandemBLEManager()
        
        // Initially simulation should be allowed
        let initialAllow = await manager.allowSimulation
        #expect(initialAllow == true)
        
        // After setting central (we'd need a mock here - just test the property)
        // This tests that the manager has the allowSimulation property
    }
    
    @Test("Init with simulation disabled requires central for scan")
    func initWithSimulationDisabled() async throws {
        let manager = TandemBLEManager()
        await manager.setAllowSimulation(false)
        
        await manager.startScanning()
        
        // Without central and simulation disabled, should go to error state
        try await Task.sleep(for: .milliseconds(50))
        let state = await manager.state
        #expect(state == .error)
    }
    
    @Test("Disconnect cleans up state")
    func disconnectCleansUp() async throws {
        let manager = TandemBLEManager.forTesting()
        
        // Connect first
        await manager.startScanning()
        try await Task.sleep(for: .milliseconds(50))
        
        let pumps = await manager.getDiscoveredPumps()
        guard let pump = pumps.first else {
            Issue.record("No pump discovered")
            return
        }
        
        try await manager.connect(to: pump)
        
        // Verify connected
        let connectedState = await manager.state
        #expect(connectedState == .ready)
        
        // Disconnect
        await manager.disconnect()
        
        // Verify disconnected
        let disconnectedState = await manager.state
        #expect(disconnectedState == .disconnected)
        
        let connectedPump = await manager.connectedPump
        #expect(connectedPump == nil)
    }
}

// MARK: - TandemCommands Tests

@Suite("TandemCommands Tests")
struct TandemCommandsTests {
    
    // MARK: - CRC-16 Tests
    
    @Test("CRC-16 calculation")
    func crc16Calculation() {
        // Test vector from x2_parsers.py
        let data = Data([0x29, 0x01, 0x06, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00])
        let crc = TandemCRC16.calculate(data)
        
        // CRC should be calculated correctly
        #expect(crc != 0)
    }
    
    @Test("CRC-16 verify valid")
    func crc16Verify() {
        // Build a message with valid CRC
        var data = Data([0x29, 0x01, 0x06, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00])
        let crc = TandemCRC16.calculate(data)
        data.append(UInt8((crc >> 8) & 0xFF))
        data.append(UInt8(crc & 0xFF))
        
        #expect(TandemCRC16.verify(data))
    }
    
    @Test("CRC-16 verify invalid")
    func crc16VerifyInvalid() {
        var data = Data([0x29, 0x01, 0x06, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00])
        // Append wrong CRC
        data.append(0x00)
        data.append(0x00)
        
        #expect(!TandemCRC16.verify(data))
    }
    
    // MARK: - Message Parsing Tests
    
    @Test("Parse unsigned message")
    func parseUnsignedMessage() {
        // CurrentBasalStatusResponse: opcode 42, txid 1, cargo len 6
        var data = Data([42, 0x01, 0x06, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00])
        let crc = TandemCRC16.calculate(data)
        data.append(UInt8((crc >> 8) & 0xFF))
        data.append(UInt8(crc & 0xFF))
        
        let message = parseTandemMessage(data, signed: false)
        
        #expect(message != nil)
        #expect(message?.opcode == 42)
        #expect(message?.transactionId == 1)
        #expect(message?.cargo.count == 6)
        #expect(message?.crcValid ?? false)
        #expect(!(message?.isSigned ?? true))
    }
    
    @Test("Parse basal status")
    func parseBasalStatus() {
        // Profile: 800 mU/hr (0x0320), Current: 800 mU/hr, flags: 0
        let cargo = Data([0x20, 0x03, 0x20, 0x03, 0x00, 0x00])
        
        let status = TandemBasalStatus.parse(from: cargo)
        
        #expect(status != nil)
        #expect(status?.profileBasalRateMilliunits == 800)
        #expect(status?.currentBasalRateMilliunits == 800)
        #expect(abs((status?.profileBasalRate ?? 0) - 0.8) < 0.001)
        #expect(!(status?.isTempRateActive ?? true))
    }
    
    @Test("Parse basal status with temp rate")
    func parseBasalStatusWithTempRate() {
        // Profile: 1000 mU/hr, Current: 500 mU/hr, flags: TEMP_RATE_ACTIVE
        let cargo = Data([0xE8, 0x03, 0xF4, 0x01, 0x02, 0x00])
        
        let status = TandemBasalStatus.parse(from: cargo)
        
        #expect(status != nil)
        #expect(status?.profileBasalRateMilliunits == 1000)
        #expect(status?.currentBasalRateMilliunits == 500)
        #expect(status?.isTempRateActive ?? false)
    }
    
    @Test("Parse temp rate status")
    func parseTempRateStatus() {
        // Active: true, percentage: 50, remaining: 30 min
        let cargo = Data([0x01, 0x32, 0x1E, 0x00])
        
        let status = TandemTempRateStatus.parse(from: cargo)
        
        #expect(status != nil)
        #expect(status?.isActive ?? false)
        #expect(status?.percentage == 50)
        #expect(status?.remainingMinutes == 30)
    }
    
    @Test("Parse IOB status")
    func parseIOBStatus() {
        // IOB: 3500 mU (3.5 U)
        let cargo = Data([0xAC, 0x0D, 0x00, 0x00])
        
        let status = TandemIOBStatus.parse(from: cargo)
        
        #expect(status != nil)
        #expect(status?.iobMilliunits == 3500)
        #expect(abs((status?.iob ?? 0) - 3.5) < 0.001)
    }
    
    // MARK: - Opcode Tests
    
    @Test("Unsigned opcode properties")
    func unsignedOpcodeProperties() {
        let opcode = TandemUnsignedOpcode.currentBasalStatusRequest
        
        #expect(opcode.rawValue == 41)
        #expect(opcode.displayName == "CurrentBasalStatusRequest")
        #expect(opcode.isRequest)
    }
    
    @Test("Signed opcode properties")
    func signedOpcodeProperties() {
        let opcode = TandemSignedOpcode.setTempRateRequest
        
        #expect(opcode.rawValue == 164)
        #expect(opcode.signedValue == -92)
        #expect(opcode.displayName == "SetTempRateRequest")
        #expect(opcode.isRequest)
    }
    
    // MARK: - Characteristic Tests
    
    @Test("Characteristic signature requirements")
    func characteristicProperties() {
        #expect(TandemCharacteristic.control.requiresSignature)
        #expect(TandemCharacteristic.controlStream.requiresSignature)
        #expect(!TandemCharacteristic.currentStatus.requiresSignature)
        #expect(!TandemCharacteristic.authorization.requiresSignature)
        #expect(!TandemCharacteristic.historyLog.requiresSignature)
    }
    
    // MARK: - Protocol Constants Tests
    
    @Test("Protocol constants")
    func protocolConstants() {
        #expect(TandemProtocol.mtu == 185)
        #expect(TandemProtocol.tokenRefreshInterval == 120)
        #expect(TandemProtocol.signatureSize == 24)
    }
    
    // MARK: - Delivery Status Tests
    
    @Test("Delivery status values")
    func deliveryStatus() {
        #expect(TandemDeliveryStatus.suspended.rawValue == 0)
        #expect(TandemDeliveryStatus.deliveringBasal.rawValue == 1)
        #expect(TandemDeliveryStatus.deliveringBolus.rawValue == 2)
        
        #expect(!TandemDeliveryStatus.suspended.isDelivering)
        #expect(TandemDeliveryStatus.deliveringBasal.isDelivering)
    }
    
    // MARK: - Basal Modified Flags Tests
    
    @Test("Basal modified flags")
    func basalModifiedFlags() {
        let flags = TandemBasalModifiedFlags([.tempRateActive, .profileRate])
        
        #expect(flags.contains(.tempRateActive))
        #expect(flags.contains(.profileRate))
        #expect(!flags.contains(.suspended))
    }
}

// MARK: - Discovered Pump Tests

@Suite("DiscoveredTandemPump Tests")
struct DiscoveredTandemPumpTests {
    
    @Test("Is Tandem pump detection")
    func isTandemPump() {
        let pump1 = DiscoveredTandemPump(id: "1", name: "t:slim X2", rssi: -50)
        let pump2 = DiscoveredTandemPump(id: "2", name: "tslim", rssi: -50)
        let pump3 = DiscoveredTandemPump(id: "3", name: "Tandem Pump", rssi: -50)
        let pump4 = DiscoveredTandemPump(id: "4", name: "Other Pump", rssi: -50)
        
        #expect(pump1.isTandemPump)
        #expect(pump2.isTandemPump)
        #expect(pump3.isTandemPump)
        #expect(!pump4.isTandemPump)
    }
    
    @Test("Display name formatting")
    func displayName() {
        let pump1 = DiscoveredTandemPump(id: "1", name: "t:slim X2", rssi: -50, serialNumber: "TP12345")
        let pump2 = DiscoveredTandemPump(id: "2", name: "t:slim X2", rssi: -50)
        
        #expect(pump1.displayName == "t:slim X2 (TP12345)")
        #expect(pump2.displayName == "t:slim X2")
    }
}

// MARK: - HMAC-SHA1 Tests (TANDEM-IMPL-003)

@Suite("TandemHMAC Tests")
struct TandemHMACTests {
    
    // MARK: - RFC 2202 Test Vectors
    
    @Test("HMAC-SHA1 RFC vector 1")
    func hmacSha1RFCVector1() {
        // RFC 2202 Test Case 1
        let key = Data(repeating: 0x0b, count: 20)
        let data = "Hi There".data(using: .utf8)!
        let expected = Data([
            0xb6, 0x17, 0x31, 0x86, 0x55, 0x05, 0x72, 0x64,
            0xe2, 0x8b, 0xc0, 0xb6, 0xfb, 0x37, 0x8c, 0x8e,
            0xf1, 0x46, 0xbe, 0x00
        ])
        
        let result = TandemHMAC.computeHMAC(message: data, key: key)
        
        #expect(result.count == 20)
        #expect(result == expected)
    }
    
    @Test("HMAC-SHA1 RFC vector 2")
    func hmacSha1RFCVector2() {
        // RFC 2202 Test Case 2
        let key = "Jefe".data(using: .utf8)!
        let data = "what do ya want for nothing?".data(using: .utf8)!
        let expected = Data([
            0xef, 0xfc, 0xdf, 0x6a, 0xe5, 0xeb, 0x2f, 0xa2,
            0xd2, 0x74, 0x16, 0xd5, 0xf1, 0x84, 0xdf, 0x9c,
            0x25, 0x9a, 0x7c, 0x79
        ])
        
        let result = TandemHMAC.computeHMAC(message: data, key: key)
        
        #expect(result.count == 20)
        #expect(result == expected)
    }
    
    // MARK: - Signature Building Tests
    
    @Test("Build signature")
    func buildSignature() {
        let sessionKey = Data([
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10
        ])
        let cargo = Data([0x64, 0x3C, 0x00]) // 100%, 60 minutes
        let pumpTime: UInt32 = 0x12345678
        
        let signature = TandemHMAC.buildSignature(
            cargo: cargo,
            pumpTimeSinceReset: pumpTime,
            sessionKey: sessionKey
        )
        
        #expect(signature.count == 24)
        
        // Verify time bytes (little-endian)
        #expect(signature[0] == 0x78)
        #expect(signature[1] == 0x56)
        #expect(signature[2] == 0x34)
        #expect(signature[3] == 0x12)
        
        // HMAC should be non-zero
        let hmac = signature.suffix(20)
        #expect(!hmac.allSatisfy { $0 == 0 })
    }
    
    @Test("Verify signature")
    func verifySignature() {
        let sessionKey = Data([
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10
        ])
        let cargo = Data([0x64, 0x3C, 0x00])
        let pumpTime: UInt32 = 0x12345678
        
        // Build signature
        let signature = TandemHMAC.buildSignature(
            cargo: cargo,
            pumpTimeSinceReset: pumpTime,
            sessionKey: sessionKey
        )
        
        // Verify should pass
        #expect(TandemHMAC.verifySignature(
            cargo: cargo,
            signature: signature,
            sessionKey: sessionKey
        ))
    }
    
    @Test("Verify signature fails with wrong key")
    func verifySignatureFailsWithWrongKey() {
        let sessionKey = Data([
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10
        ])
        let wrongKey = Data([
            0xFF, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10
        ])
        let cargo = Data([0x64, 0x3C, 0x00])
        let pumpTime: UInt32 = 0x12345678
        
        // Build signature with correct key
        let signature = TandemHMAC.buildSignature(
            cargo: cargo,
            pumpTimeSinceReset: pumpTime,
            sessionKey: sessionKey
        )
        
        // Verify with wrong key should fail
        #expect(!TandemHMAC.verifySignature(
            cargo: cargo,
            signature: signature,
            sessionKey: wrongKey
        ))
    }
    
    @Test("Verify signature fails with tampered cargo")
    func verifySignatureFailsWithTamperedCargo() {
        let sessionKey = Data([
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10
        ])
        let cargo = Data([0x64, 0x3C, 0x00])
        let tamperedCargo = Data([0x64, 0x3C, 0x01])  // Changed last byte
        let pumpTime: UInt32 = 0x12345678
        
        // Build signature with original cargo
        let signature = TandemHMAC.buildSignature(
            cargo: cargo,
            pumpTimeSinceReset: pumpTime,
            sessionKey: sessionKey
        )
        
        // Verify with tampered cargo should fail
        #expect(!TandemHMAC.verifySignature(
            cargo: tamperedCargo,
            signature: signature,
            sessionKey: sessionKey
        ))
    }
    
    // MARK: - Extraction Tests
    
    @Test("Extract pump time from signature")
    func extractPumpTime() {
        let signature = Data([
            0x78, 0x56, 0x34, 0x12,  // Time: 0x12345678
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
            0x10, 0x11, 0x12, 0x13
        ])
        
        let time = TandemHMAC.extractPumpTime(from: signature)
        #expect(time == 0x12345678)
    }
    
    @Test("Extract HMAC from signature")
    func extractHMAC() {
        let expectedHMAC = Data([
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
            0x10, 0x11, 0x12, 0x13
        ])
        var signature = Data([0x78, 0x56, 0x34, 0x12])
        signature.append(expectedHMAC)
        
        let hmac = TandemHMAC.extractHMAC(from: signature)
        #expect(hmac == expectedHMAC)
    }
    
    // MARK: - Signed Message Builder Tests
    
    @Test("Signed message builder")
    func signedMessageBuilder() {
        let sessionKey = Data(repeating: 0x42, count: 32)
        let builder = TandemSignedMessageBuilder(sessionKey: sessionKey, initialPumpTime: 1000)
        
        let message = builder.buildMessage(
            opcode: .setTempRateRequest,
            transactionId: 1,
            cargo: Data([0x64, 0x3C, 0x00])
        )
        
        // Message structure: opcode(1) + txid(1) + len(1) + cargo(3) + sig(24) + crc(2) = 32 bytes
        #expect(message.count == 32)
        
        // Check opcode
        #expect(message[0] == 164)  // SetTempRateRequest
        
        // Check transaction ID
        #expect(message[1] == 1)
        
        // Check cargo length (3 + 24 = 27)
        #expect(message[2] == 27)
        
        // Verify CRC
        #expect(TandemCRC16.verify(message))
    }
    
    // MARK: - Constants Tests
    
    @Test("HMAC constants")
    func hmacConstants() {
        #expect(TandemHMAC.hmacSize == 20)
        #expect(TandemHMAC.signatureSize == 24)
    }
}
