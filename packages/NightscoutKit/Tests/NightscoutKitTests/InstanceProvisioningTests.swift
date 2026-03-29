// SPDX-License-Identifier: MIT
//
// InstanceProvisioningTests.swift
// NightscoutKit Tests
//
// Tests for managed Nightscout instance provisioning
// Trace: BIZ-004, PRD-015

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import NightscoutKit

@Suite("Instance Provisioning")
struct InstanceProvisioningTests {
    
    @Test("Create instance with valid config")
    func testCreateInstance() async throws {
        let client = MockProvisioningClient()
        
        let config = NightscoutInstanceConfig(
            subdomain: "testuser",
            region: .usEast,
            displayUnits: "mg/dL"
        )
        
        let instance = try await client.createInstance(config: config)
        
        #expect(instance.config.subdomain == "testuser")
        #expect(instance.status == .running)
        #expect(instance.url.absoluteString == "https://testuser.t1pal.org")
        #expect(!instance.apiSecret.isEmpty)
    }
    
    @Test("List instances returns created instances")
    func testListInstances() async throws {
        let client = MockProvisioningClient()
        
        // Create two instances
        let config1 = NightscoutInstanceConfig(subdomain: "user1")
        let config2 = NightscoutInstanceConfig(subdomain: "user2")
        
        _ = try await client.createInstance(config: config1)
        _ = try await client.createInstance(config: config2)
        
        let instances = try await client.listInstances()
        #expect(instances.count == 2)
    }
    
    @Test("Duplicate subdomain throws error")
    func testDuplicateSubdomain() async throws {
        let client = MockProvisioningClient()
        
        let config = NightscoutInstanceConfig(subdomain: "taken")
        _ = try await client.createInstance(config: config)
        
        await #expect(throws: ProvisioningError.self) {
            try await client.createInstance(config: config)
        }
    }
    
    @Test("Check subdomain availability")
    func testSubdomainAvailability() async throws {
        let client = MockProvisioningClient()
        
        // Initially available
        let available1 = try await client.checkSubdomainAvailable(subdomain: "newsite")
        #expect(available1 == true)
        
        // Create instance
        let config = NightscoutInstanceConfig(subdomain: "newsite")
        _ = try await client.createInstance(config: config)
        
        // Now taken
        let available2 = try await client.checkSubdomainAvailable(subdomain: "newsite")
        #expect(available2 == false)
    }
    
    @Test("Delete instance removes it")
    func testDeleteInstance() async throws {
        let client = MockProvisioningClient()
        
        let config = NightscoutInstanceConfig(subdomain: "todelete")
        let instance = try await client.createInstance(config: config)
        
        try await client.deleteInstance(id: instance.id)
        
        await #expect(throws: ProvisioningError.self) {
            try await client.getInstance(id: instance.id)
        }
        
        // Subdomain should be available again
        let available = try await client.checkSubdomainAvailable(subdomain: "todelete")
        #expect(available == true)
    }
    
    @Test("Hosting regions are available")
    func testHostingRegions() {
        let regions = HostingRegion.allCases
        #expect(regions.count == 4)
        #expect(regions.contains(.usEast))
        #expect(regions.contains(.euWest))
    }
    
    @Test("Update instance config")
    func testUpdateInstance() async throws {
        let client = MockProvisioningClient()
        
        let config = NightscoutInstanceConfig(
            subdomain: "original",
            displayUnits: "mg/dL"
        )
        let instance = try await client.createInstance(config: config)
        
        let updatedConfig = NightscoutInstanceConfig(
            subdomain: "original",
            displayUnits: "mmol/L",
            targetLow: 80,
            targetHigh: 160
        )
        
        let updated = try await client.updateInstance(id: instance.id, config: updatedConfig)
        #expect(updated.config.displayUnits == "mmol/L")
        #expect(updated.config.targetLow == 80)
    }
    
    @Test("Instance status values")
    func testInstanceStatus() {
        let statuses: [InstanceStatus] = [.provisioning, .running, .suspended, .maintenance, .error]
        #expect(statuses.count == 5)
    }
    
    @Test("Config with all plugins")
    func testConfigPlugins() {
        let config = NightscoutInstanceConfig(
            subdomain: "fullsite",
            enabledPlugins: ["careportal", "iob", "cob", "pump", "loop", "basal"]
        )
        #expect(config.enabledPlugins.count == 6)
        #expect(config.enabledPlugins.contains("loop"))
    }
}

// MARK: - Live Client Tests

@Suite("Live Provisioning Client")
struct LiveProvisioningClientTests {
    
    @Test("Client requires auth token")
    func testRequiresAuth() async throws {
        let client = LiveProvisioningClient(
            baseURL: URL(string: "https://api.t1pal.com")!
        )
        
        // Without setting auth token, should throw
        await #expect(throws: ProvisioningError.self) {
            try await client.listInstances()
        }
    }
    
    @Test("Subdomain validation rejects invalid")
    func testSubdomainValidation() async throws {
        let client = LiveProvisioningClient()
        await client.setAuthToken("test-token")
        
        // Too short - should return false without making API call
        let tooShort = try await client.checkSubdomainAvailable(subdomain: "ab")
        #expect(tooShort == false)
        
        // Invalid characters
        let invalid = try await client.checkSubdomainAvailable(subdomain: "my-site")
        #expect(invalid == false)
        
        // Uppercase
        let uppercase = try await client.checkSubdomainAvailable(subdomain: "MyName")
        #expect(uppercase == false)
    }
}

// MARK: - Instance Creation Flow Tests

@Suite("Instance Creation Flow")
struct InstanceCreationFlowTests {
    
    @Test("Create and bind flow")
    func testCreateAndBind() async throws {
        let provisioningClient = MockProvisioningClient()
        let discoveryClient = MockDiscoveryClient()
        
        let flow = InstanceCreationFlow(
            provisioningClient: provisioningClient,
            discoveryClient: discoveryClient
        )
        
        let config = NightscoutInstanceConfig(subdomain: "newsite")
        let binding = try await flow.createAndBind(config: config)
        
        #expect(binding.displayName == "newsite")
        #expect(binding.role == .owner)
        // Note: MockDiscoveryClient uses selfHosted by default
        #expect(binding.hostingType == .selfHosted)
        #expect(binding.url.absoluteString == "https://newsite.t1pal.org")
    }
    
    @Test("Check availability - available")
    func testCheckAvailabilityAvailable() async throws {
        let provisioningClient = MockProvisioningClient()
        let discoveryClient = MockDiscoveryClient()
        
        let flow = InstanceCreationFlow(
            provisioningClient: provisioningClient,
            discoveryClient: discoveryClient
        )
        
        let result = try await flow.checkAvailability(subdomain: "newsite")
        
        if case .available = result {
            // Expected
        } else {
            Issue.record("Expected available, got \(result)")
        }
    }
    
    @Test("Check availability - taken with alternatives")
    func testCheckAvailabilityTaken() async throws {
        let provisioningClient = MockProvisioningClient()
        let discoveryClient = MockDiscoveryClient()
        
        // Take the subdomain first
        let config = NightscoutInstanceConfig(subdomain: "takensite")
        _ = try await provisioningClient.createInstance(config: config)
        
        let flow = InstanceCreationFlow(
            provisioningClient: provisioningClient,
            discoveryClient: discoveryClient
        )
        
        let result = try await flow.checkAvailability(subdomain: "takensite")
        
        if case .taken(let alternatives) = result {
            #expect(!alternatives.isEmpty)
            #expect(alternatives.contains("takensite1"))
            #expect(alternatives.contains("takensitens"))
        } else {
            Issue.record("Expected taken, got \(result)")
        }
    }
}

// MARK: - Provisioning Status Poller Tests

@Suite("Provisioning Status Poller")
struct ProvisioningStatusPollerTests {
    
    @Test("Wait for running returns immediately when already running")
    func testAlreadyRunning() async throws {
        let client = MockProvisioningClient()
        let config = NightscoutInstanceConfig(subdomain: "readysite")
        let instance = try await client.createInstance(config: config)
        
        // MockProvisioningClient returns .running immediately
        let poller = ProvisioningStatusPoller(
            client: client,
            pollInterval: 0.1,
            maxAttempts: 3
        )
        
        let result = try await poller.waitForRunning(instanceId: instance.id)
        #expect(result.status == .running)
    }
    
    @Test("Wait for instance not found throws")
    func testInstanceNotFound() async throws {
        let client = MockProvisioningClient()
        let poller = ProvisioningStatusPoller(client: client)
        
        await #expect(throws: ProvisioningError.self) {
            try await poller.waitForRunning(instanceId: UUID())
        }
    }
}

// MARK: - Subdomain Availability Tests

@Suite("Subdomain Availability")
struct SubdomainAvailabilityTests {
    
    @Test("Available case")
    func testAvailableCase() {
        let availability = SubdomainAvailability.available
        if case .available = availability {
            // Expected
        } else {
            Issue.record("Expected available")
        }
    }
    
    @Test("Taken with alternatives")
    func testTakenCase() {
        let availability = SubdomainAvailability.taken(suggestedAlternatives: ["site1", "site2"])
        if case .taken(let alts) = availability {
            #expect(alts.count == 2)
        } else {
            Issue.record("Expected taken")
        }
    }
    
    @Test("Invalid with reason")
    func testInvalidCase() {
        let availability = SubdomainAvailability.invalid(reason: "Contains invalid characters")
        if case .invalid(let reason) = availability {
            #expect(reason.contains("invalid"))
        } else {
            Issue.record("Expected invalid")
        }
    }
}

// MARK: - Provisioning Error Tests

@Suite("Provisioning Errors")
struct ProvisioningErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let errors: [ProvisioningError] = [
            .notAuthenticated,
            .insufficientTier,
            .subdomainTaken,
            .invalidConfiguration("test"),
            .provisioningFailed("test"),
            .instanceNotFound
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    @Test("Network error wraps underlying error")
    func testNetworkError() {
        let underlying = URLError(.notConnectedToInternet)
        let error = ProvisioningError.networkError(underlying)
        #expect(error.errorDescription?.contains("Network") == true)
    }
}
