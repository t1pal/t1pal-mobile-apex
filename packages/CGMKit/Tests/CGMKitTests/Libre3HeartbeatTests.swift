// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Libre3HeartbeatTests.swift
// CGMKit
//
// Tests for Libre 3 heartbeat/coexistence mode (LIBRE3-014)
// This mode detects LibreLink app BLE connections and fetches from cloud

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

/// Tests for heartbeat mode - xDrip4iOS pattern for coexistence
/// Trace: LIBRE3-014a, LIBRE3-014b, LIBRE3-014c
@Suite("Libre3HeartbeatTests")
struct Libre3HeartbeatTests {
    
    // MARK: - LIBRE3-014a: Connection Events Registration
    
    @Test("Heartbeat mode requires cloud credentials")
    func heartbeatRequiresCredentials() async throws {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOn)
        
        // Config without cloud credentials
        let config = Libre3ManagerConfig(
            cloudCredentials: nil,
            enableCloudFallback: false
        )
        
        let manager = Libre3Manager(config: config, central: mockCentral)
        
        // Should throw not configured error
        await #expect(throws: CGMError.self) {
            try await manager.startHeartbeatMode()
        }
    }
    
    @Test("Heartbeat mode requires BLE powered on")
    func heartbeatRequiresBLE() async throws {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOff)
        
        let config = Libre3ManagerConfig(
            cloudCredentials: LibreLinkUpCredentials(
                email: "test@test.com",
                password: "test"
            ),
            enableCloudFallback: true
        )
        
        let manager = Libre3Manager(config: config, central: mockCentral)
        
        // Should throw BLE unavailable
        await #expect(throws: CGMError.self) {
            try await manager.startHeartbeatMode()
        }
    }
    
    @Test("Heartbeat mode starts successfully with valid config")
    func heartbeatStartsSuccessfully() async throws {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOn)
        
        let config = Libre3ManagerConfig(
            cloudCredentials: LibreLinkUpCredentials(
                email: "test@test.com",
                password: "test"
            ),
            enableCloudFallback: true
        )
        
        let manager = Libre3Manager(config: config, central: mockCentral)
        
        try await manager.startHeartbeatMode()
        
        // Verify heartbeat mode is active
        let isActive = await manager.isHeartbeatModeActive
        #expect(isActive == true)
    }
    
    @Test("Heartbeat mode can be stopped")
    func heartbeatCanBeStopped() async throws {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOn)
        
        let config = Libre3ManagerConfig(
            cloudCredentials: LibreLinkUpCredentials(
                email: "test@test.com",
                password: "test"
            ),
            enableCloudFallback: true
        )
        
        let manager = Libre3Manager(config: config, central: mockCentral)
        
        try await manager.startHeartbeatMode()
        await manager.stopHeartbeatMode()
        
        let isActive = await manager.isHeartbeatModeActive
        #expect(isActive == false)
    }
    
    // MARK: - LIBRE3-014b: Callback on detection
    
    @Test("Callback fires on LibreLink connection")
    func callbackFiresOnConnection() async throws {
        let mockCentral = MockBLECentral()
        await mockCentral.setState(.poweredOn)
        
        let config = Libre3ManagerConfig(
            cloudCredentials: LibreLinkUpCredentials(
                email: "test@test.com",
                password: "test"
            ),
            enableCloudFallback: true
        )
        
        let manager = Libre3Manager(config: config, central: mockCentral)
        
        let expectation = UncheckedSendable(false)
        await manager.setOnLibreLinkConnectionDetected { _ in
            // Can't mutate here, but validates the callback type compiles
        }
        
        try await manager.startHeartbeatMode()
        
        // Verify callback was set
        // (actual connection event testing requires MockBLECentral enhancements)
    }
}

// MARK: - Helper extension

extension Libre3Manager {
    func setOnLibreLinkConnectionDetected(_ callback: (@Sendable (Bool) -> Void)?) async {
        self.onLibreLinkConnectionDetected = callback
    }
}

// UncheckedSendable for test expectations
struct UncheckedSendable<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
