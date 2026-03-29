// SPDX-License-Identifier: MIT
//
// CGMCapabilityGateTests.swift
// T1PalCore Tests
//
// Tests for CGM tier detection and permission gates
// Backlog: ENHANCE-TIER2-001

import Foundation
import Testing
@testable import T1PalCore

// MARK: - Bluetooth Permission Status Tests

@Suite("Bluetooth Permission Status")
struct BluetoothPermissionStatusTests {
    
    @Test("Authorized is usable")
    func testAuthorizedIsUsable() {
        #expect(BluetoothPermissionStatus.authorized.isUsable == true)
    }
    
    @Test("Not determined can request")
    func testNotDeterminedCanRequest() {
        #expect(BluetoothPermissionStatus.notDetermined.canRequest == true)
    }
    
    @Test("Denied cannot request")
    func testDeniedCannotRequest() {
        #expect(BluetoothPermissionStatus.denied.canRequest == false)
    }
    
    @Test("All statuses have descriptions")
    func testDescriptions() {
        for status in [BluetoothPermissionStatus.notDetermined, .authorized, .denied, .restricted, .unsupported] {
            #expect(!status.displayDescription.isEmpty)
        }
    }
}

// MARK: - CGM Connection Status Tests

@Suite("CGM Connection Status")
struct CGMConnectionStatusTests {
    
    @Test("Connected is receiving data")
    func testConnectedIsReceivingData() {
        #expect(CGMConnectionStatus.connected.isReceivingData == true)
    }
    
    @Test("Streaming is receiving data")
    func testStreamingIsReceivingData() {
        #expect(CGMConnectionStatus.streaming.isReceivingData == true)
    }
    
    @Test("Disconnected is not receiving data")
    func testDisconnectedNotReceiving() {
        #expect(CGMConnectionStatus.disconnected.isReceivingData == false)
    }
    
    @Test("Scanning is not receiving data")
    func testScanningNotReceiving() {
        #expect(CGMConnectionStatus.scanning.isReceivingData == false)
    }
    
    @Test("All statuses have descriptions")
    func testDescriptions() {
        for status in [CGMConnectionStatus.disconnected, .scanning, .connecting, .connected, .streaming] {
            #expect(!status.displayDescription.isEmpty)
        }
    }
}

// MARK: - CGM Data Freshness Tests

@Suite("CGM Data Freshness")
struct CGMDataFreshnessTests {
    
    @Test("Fresh data within threshold")
    func testFreshData() {
        let freshness = CGMDataFreshness(
            lastReadingDate: Date().addingTimeInterval(-60), // 1 minute ago
            checkDate: Date()
        )
        
        #expect(freshness.isFresh == true)
        #expect(freshness.isStale == false)
        #expect(freshness.isExpired == false)
        #expect(freshness.freshnessLevel == .fresh)
    }
    
    @Test("Stale data beyond fresh threshold")
    func testStaleData() {
        let freshness = CGMDataFreshness(
            lastReadingDate: Date().addingTimeInterval(-600), // 10 minutes ago
            checkDate: Date()
        )
        
        #expect(freshness.isFresh == false)
        #expect(freshness.isStale == true)
        #expect(freshness.isExpired == false)
        #expect(freshness.freshnessLevel == .stale)
    }
    
    @Test("Expired data beyond stale threshold")
    func testExpiredData() {
        let freshness = CGMDataFreshness(
            lastReadingDate: Date().addingTimeInterval(-1200), // 20 minutes ago
            checkDate: Date()
        )
        
        #expect(freshness.isFresh == false)
        #expect(freshness.isStale == false)
        #expect(freshness.isExpired == true)
        #expect(freshness.freshnessLevel == .expired)
    }
    
    @Test("No data is expired")
    func testNoData() {
        let freshness = CGMDataFreshness(lastReadingDate: nil)
        
        #expect(freshness.isFresh == false)
        #expect(freshness.isExpired == true)
        #expect(freshness.ageSeconds == nil)
    }
    
    @Test("Age calculation")
    func testAgeCalculation() {
        let now = Date()
        let freshness = CGMDataFreshness(
            lastReadingDate: now.addingTimeInterval(-120),
            checkDate: now
        )
        
        #expect(freshness.ageSeconds == 120)
    }
    
    @Test("Freshness levels have symbols")
    func testFreshnessSymbols() {
        #expect(!CGMDataFreshness.FreshnessLevel.fresh.symbolName.isEmpty)
        #expect(!CGMDataFreshness.FreshnessLevel.stale.symbolName.isEmpty)
        #expect(!CGMDataFreshness.FreshnessLevel.expired.symbolName.isEmpty)
    }
}

// MARK: - CGM Tier Status Tests

@Suite("CGM Tier Status")
struct CGMTierStatusTests {
    
    @Test("Ready when all checks pass")
    func testReadyState() {
        let status = CGMTierStatus(
            bluetoothStatus: .authorized,
            connectionStatus: .streaming,
            dataFreshness: CGMDataFreshness(lastReadingDate: Date())
        )
        
        #expect(status.isReady == true)
        #expect(status.blockers.isEmpty)
        #expect(status.primaryBlocker == nil)
    }
    
    @Test("Not ready when Bluetooth denied")
    func testBluetoothBlocked() {
        let status = CGMTierStatus(
            bluetoothStatus: .denied,
            connectionStatus: .streaming,
            dataFreshness: CGMDataFreshness(lastReadingDate: Date())
        )
        
        #expect(status.isReady == false)
        #expect(status.blockers.count == 1)
        #expect(status.primaryBlocker == .bluetoothPermission(.denied))
    }
    
    @Test("Not ready when disconnected")
    func testConnectionBlocked() {
        let status = CGMTierStatus(
            bluetoothStatus: .authorized,
            connectionStatus: .disconnected,
            dataFreshness: CGMDataFreshness(lastReadingDate: Date())
        )
        
        #expect(status.isReady == false)
        #expect(status.blockers.contains(.cgmConnection(.disconnected)))
    }
    
    @Test("Not ready when data expired")
    func testDataExpiredBlocked() {
        let status = CGMTierStatus(
            bluetoothStatus: .authorized,
            connectionStatus: .streaming,
            dataFreshness: CGMDataFreshness(lastReadingDate: Date().addingTimeInterval(-1200))
        )
        
        #expect(status.isReady == false)
        #expect(status.blockers.contains(.dataFreshness(.expired)))
    }
    
    @Test("Multiple blockers")
    func testMultipleBlockers() {
        let status = CGMTierStatus(
            bluetoothStatus: .denied,
            connectionStatus: .disconnected,
            dataFreshness: CGMDataFreshness(lastReadingDate: nil)
        )
        
        #expect(status.blockers.count == 3)
        #expect(status.isReady == false)
    }
    
    @Test("Status message when ready")
    func testStatusMessageReady() {
        let status = CGMTierStatus(
            bluetoothStatus: .authorized,
            connectionStatus: .streaming,
            dataFreshness: CGMDataFreshness(lastReadingDate: Date())
        )
        
        #expect(status.statusMessage == "CGM tier active")
    }
    
    @Test("Status message when blocked")
    func testStatusMessageBlocked() {
        let status = CGMTierStatus(
            bluetoothStatus: .denied,
            connectionStatus: .disconnected,
            dataFreshness: CGMDataFreshness(lastReadingDate: nil)
        )
        
        #expect(status.statusMessage.contains("denied"))
    }
}

// MARK: - CGM Blocker Tests

@Suite("CGM Blocker")
struct CGMBlockerTests {
    
    @Test("Bluetooth blocker messages")
    func testBluetoothBlockerMessages() {
        let blocker = CGMBlocker.bluetoothPermission(.denied)
        
        #expect(!blocker.userMessage.isEmpty)
        #expect(!blocker.actionPrompt.isEmpty)
        #expect(blocker.isResolvable == true)
    }
    
    @Test("Connection blocker messages")
    func testConnectionBlockerMessages() {
        let blocker = CGMBlocker.cgmConnection(.disconnected)
        
        #expect(!blocker.userMessage.isEmpty)
        #expect(!blocker.actionPrompt.isEmpty)
        #expect(blocker.isResolvable == true)
    }
    
    @Test("Freshness blocker messages")
    func testFreshnessBlockerMessages() {
        let blocker = CGMBlocker.dataFreshness(.expired)
        
        #expect(!blocker.userMessage.isEmpty)
        #expect(!blocker.actionPrompt.isEmpty)
        #expect(blocker.isResolvable == true)
    }
    
    @Test("Bluetooth not determined action prompt")
    func testBluetoothNotDeterminedPrompt() {
        let blocker = CGMBlocker.bluetoothPermission(.notDetermined)
        
        #expect(blocker.actionPrompt.contains("Enable"))
    }
    
    @Test("Bluetooth unsupported not resolvable")
    func testBluetoothUnsupportedNotResolvable() {
        let blocker = CGMBlocker.bluetoothPermission(.unsupported)
        
        #expect(blocker.isResolvable == false)
    }
}

// MARK: - Mock CGM Capability Gate Tests

@Suite("Mock CGM Capability Gate")
struct MockCGMCapabilityGateTests {
    
    @Test("Default state is not tier 2 ready")
    func testDefaultStateNotReady() async {
        let gate = MockCGMCapabilityGate()
        
        let isReady = await gate.isTier2Ready()
        #expect(isReady == false)
    }
    
    @Test("Enable tier 2 makes ready")
    func testEnableTier2() async {
        let gate = MockCGMCapabilityGate()
        
        await gate.enableTier2()
        
        let isReady = await gate.isTier2Ready()
        #expect(isReady == true)
    }
    
    @Test("Configure specific state")
    func testConfigureState() async {
        let gate = MockCGMCapabilityGate()
        
        await gate.configure(
            bluetooth: .authorized,
            connection: .connected,
            lastReading: Date()
        )
        
        let status = await gate.getTier2Status()
        #expect(status.bluetoothStatus == .authorized)
        #expect(status.connectionStatus == .connected)
        #expect(status.isReady == true)
    }
    
    @Test("Check Bluetooth permission")
    func testCheckBluetooth() async {
        let gate = MockCGMCapabilityGate()
        await gate.configure(bluetooth: .denied, connection: .disconnected, lastReading: nil)
        
        let status = await gate.checkBluetoothPermission()
        #expect(status == .denied)
    }
    
    @Test("Check CGM connection")
    func testCheckConnection() async {
        let gate = MockCGMCapabilityGate()
        await gate.configure(bluetooth: .authorized, connection: .scanning, lastReading: nil)
        
        let status = await gate.checkCGMConnection()
        #expect(status == .scanning)
    }
    
    @Test("Check data freshness")
    func testCheckFreshness() async {
        let gate = MockCGMCapabilityGate()
        let readingDate = Date().addingTimeInterval(-60)
        await gate.configure(bluetooth: .authorized, connection: .streaming, lastReading: readingDate)
        
        let freshness = await gate.checkDataFreshness()
        #expect(freshness.isFresh == true)
    }
    
    @Test("Check count is tracked")
    func testCheckCount() async {
        let gate = MockCGMCapabilityGate()
        
        _ = await gate.checkBluetoothPermission()
        _ = await gate.checkCGMConnection()
        _ = await gate.checkDataFreshness()
        
        let count = await gate.checkCount
        #expect(count == 3)
    }
    
    @Test("Get tier 2 status includes all fields")
    func testGetTier2StatusFields() async {
        let gate = MockCGMCapabilityGate()
        await gate.enableTier2()
        
        let status = await gate.getTier2Status()
        
        #expect(status.bluetoothStatus == .authorized)
        #expect(status.connectionStatus == .streaming)
        #expect(status.dataFreshness.isFresh == true)
        #expect(status.blockers.isEmpty)
    }
}

// MARK: - Live CGM Capability Gate Tests

@Suite("Live CGM Capability Gate")
struct LiveCGMCapabilityGateTests {
    
    @Test("Creates with default providers")
    func testCreatesWithDefaults() async {
        let gate = LiveCGMCapabilityGate()
        
        // Should not crash - uses default providers
        let status = await gate.getTier2Status()
        #expect(status.bluetoothStatus != nil)
    }
    
    @Test("Is tier 2 ready with all blockers")
    func testIsTier2ReadyWithBlockers() async {
        let gate = LiveCGMCapabilityGate()
        
        // With default/empty state, should not be ready
        let isReady = await gate.isTier2Ready()
        #expect(isReady == false)
    }
}

// MARK: - CGM Tier Status Capability Extension Tests

@Suite("CGM Tier Status Capability Extension")
struct CGMTierStatusCapabilityExtensionTests {
    
    @Test("Converts to capability statuses")
    func testConvertsToCapabilityStatuses() {
        let status = CGMTierStatus(
            bluetoothStatus: .authorized,
            connectionStatus: .streaming,
            dataFreshness: CGMDataFreshness(lastReadingDate: Date())
        )
        
        let capabilityStatuses = status.capabilityStatuses
        
        #expect(capabilityStatuses.count == 2)
        
        let btStatus = capabilityStatuses.first { $0.capability == .bluetoothAccess }
        #expect(btStatus?.isAvailable == true)
        
        let cgmStatus = capabilityStatuses.first { $0.capability == .cgmDevice }
        #expect(cgmStatus?.isAvailable == true)
    }
    
    @Test("Converts unavailable statuses")
    func testConvertsUnavailableStatuses() {
        let status = CGMTierStatus(
            bluetoothStatus: .denied,
            connectionStatus: .disconnected,
            dataFreshness: CGMDataFreshness(lastReadingDate: nil)
        )
        
        let capabilityStatuses = status.capabilityStatuses
        
        let btStatus = capabilityStatuses.first { $0.capability == .bluetoothAccess }
        #expect(btStatus?.isAvailable == false)
        #expect(btStatus?.canRequest == false)
        
        let cgmStatus = capabilityStatuses.first { $0.capability == .cgmDevice }
        #expect(cgmStatus?.isAvailable == false)
        #expect(cgmStatus?.canRequest == true)
    }
}
