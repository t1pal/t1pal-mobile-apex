// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Libre3CloudFallbackTests.swift
// CGMKit
//
// Tests for Libre 3 cloud fallback functionality
// Trace: LIBRE-IMPL-005

import Testing
@testable import CGMKit
import T1PalCore
import BLEKit

@Suite("Libre 3 Cloud Fallback")
struct Libre3CloudFallbackTests {
    
    // MARK: - Config Tests
    
    @Test("Config with cloud credentials sets enableCloudFallback")
    func configWithCredentials() {
        let credentials = LibreLinkUpCredentials(
            email: "test@example.com",
            password: "password123",
            region: .us
        )
        
        let config = Libre3ManagerConfig(
            cloudCredentials: credentials,
            enableCloudFallback: true
        )
        
        #expect(config.cloudCredentials != nil)
        #expect(config.enableCloudFallback == true)
    }
    
    @Test("Config without credentials has no cloud fallback")
    func configWithoutCredentials() {
        let config = Libre3ManagerConfig()
        
        #expect(config.cloudCredentials == nil)
        #expect(config.enableCloudFallback == false)
    }
    
    // MARK: - Connection State Tests
    
    @Test("Connection state includes cloudFallback")
    func connectionStateHasCloudFallback() {
        let state = Libre3ConnectionState.cloudFallback
        #expect(state.isConnected == true)
    }
    
    @Test("CloudFallback state equals itself")
    func cloudFallbackEquality() {
        let state1 = Libre3ConnectionState.cloudFallback
        let state2 = Libre3ConnectionState.cloudFallback
        #expect(state1 == state2)
    }
    
    // MARK: - Manager Tests
    
    @Test("Manager reports cloud fallback availability")
    func managerCloudFallbackAvailability() async {
        let credentials = LibreLinkUpCredentials(
            email: "test@example.com",
            password: "password123",
            region: .us
        )
        
        let configWithFallback = Libre3ManagerConfig(
            cloudCredentials: credentials,
            enableCloudFallback: true
        )
        
        let configWithoutFallback = Libre3ManagerConfig()
        
        let managerWith = Libre3Manager(
            config: configWithFallback,
            central: MockBLECentral()
        )
        
        let managerWithout = Libre3Manager(
            config: configWithoutFallback,
            central: MockBLECentral()
        )
        
        let available = await managerWith.isCloudFallbackAvailable
        let notAvailable = await managerWithout.isCloudFallbackAvailable
        
        #expect(available == true)
        #expect(notAvailable == false)
    }
    
    @Test("Manager throws when fetchFromCloud called without credentials")
    func fetchFromCloudThrowsWithoutCredentials() async throws {
        let config = Libre3ManagerConfig()
        let manager = Libre3Manager(config: config, central: MockBLECentral())
        
        await #expect(throws: CGMError.self) {
            _ = try await manager.fetchFromCloud()
        }
    }
}
