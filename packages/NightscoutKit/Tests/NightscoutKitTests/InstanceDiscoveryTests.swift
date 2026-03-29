// SPDX-License-Identifier: MIT
//
// InstanceDiscoveryTests.swift
// NightscoutKitTests
//
// Tests for Nightscout instance discovery
// Backlog: ID-NS-001

import Foundation
import Testing
@testable import NightscoutKit

@Suite("InstanceBinding")
struct InstanceBindingTests {
    
    @Test("binding creation with defaults")
    func bindingCreation() {
        let binding = InstanceBinding(
            id: "ns-123",
            url: URL(string: "https://my.nightscout.com")!,
            displayName: "My Nightscout"
        )
        
        #expect(binding.id == "ns-123")
        #expect(binding.displayName == "My Nightscout")
        #expect(binding.role == .owner)
        #expect(binding.permissionLevel == .full)
        #expect(!binding.isPrimary)
        #expect(binding.hostingType == .selfHosted)
    }
    
    @Test("binding equality")
    func bindingEquality() {
        let now = Date()
        let binding1 = InstanceBinding(
            id: "ns-123",
            url: URL(string: "https://my.nightscout.com")!,
            displayName: "My NS",
            createdAt: now
        )
        
        let binding2 = InstanceBinding(
            id: "ns-123",
            url: URL(string: "https://my.nightscout.com")!,
            displayName: "My NS",
            createdAt: now
        )
        
        #expect(binding1 == binding2)
    }
    
    @Test("binding codable round-trip")
    func bindingCodable() throws {
        let binding = InstanceBinding(
            id: "ns-456",
            url: URL(string: "https://test.ns.com")!,
            displayName: "Test NS",
            role: .caregiver,
            permissionLevel: .readOnly,
            isPrimary: true,
            hostingType: .t1palHosted
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(binding)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(InstanceBinding.self, from: data)
        
        #expect(decoded.id == binding.id)
        #expect(decoded.role == .caregiver)
        #expect(decoded.permissionLevel == .readOnly)
        #expect(decoded.isPrimary)
        #expect(decoded.hostingType == .t1palHosted)
    }
}

@Suite("InstanceRole")
struct InstanceRoleTests {
    
    @Test("owner permissions")
    func ownerPermissions() {
        let role = InstanceRole.owner
        #expect(role.canInvite)
        #expect(role.canModifySettings)
        #expect(role.displayName == "Owner")
    }
    
    @Test("admin permissions")
    func adminPermissions() {
        let role = InstanceRole.admin
        #expect(role.canInvite)
        #expect(role.canModifySettings)
    }
    
    @Test("caregiver permissions")
    func caregiverPermissions() {
        let role = InstanceRole.caregiver
        #expect(!role.canInvite)
        #expect(!role.canModifySettings)
    }
    
    @Test("readonly permissions")
    func readonlyPermissions() {
        let role = InstanceRole.readonly
        #expect(!role.canInvite)
        #expect(!role.canModifySettings)
    }
    
    @Test("all cases count")
    func allCases() {
        #expect(InstanceRole.allCases.count == 4)
    }
}

@Suite("PermissionLevel")
struct PermissionLevelTests {
    
    @Test("full permissions")
    func fullPermissions() {
        let level = PermissionLevel.full
        #expect(level.canWriteEntries)
        #expect(level.canWriteTreatments)
        #expect(level.canReadProfile)
    }
    
    @Test("readWrite permissions")
    func readWritePermissions() {
        let level = PermissionLevel.readWrite
        #expect(level.canWriteEntries)
        #expect(level.canWriteTreatments)
        #expect(level.canReadProfile)
    }
    
    @Test("readOnly permissions")
    func readOnlyPermissions() {
        let level = PermissionLevel.readOnly
        #expect(!level.canWriteEntries)
        #expect(!level.canWriteTreatments)
        #expect(level.canReadProfile)
    }
    
    @Test("entriesOnly permissions")
    func entriesOnlyPermissions() {
        let level = PermissionLevel.entriesOnly
        #expect(!level.canWriteEntries)
        #expect(!level.canWriteTreatments)
        #expect(!level.canReadProfile)
    }
    
    @Test("all cases count")
    func allCases() {
        #expect(PermissionLevel.allCases.count == 4)
    }
}

@Suite("ValidationResponse")
struct ValidationResponseTests {
    
    @Test("valid response")
    func validResponse() {
        let response = ValidationResponse(
            isValid: true,
            version: "15.0.2",
            serverName: "My NS",
            apiVersion: "v3",
            enabledPlugins: ["careportal", "iob"]
        )
        
        #expect(response.isValid)
        #expect(response.version == "15.0.2")
        #expect(response.apiVersion == "v3")
        #expect(response.enabledPlugins?.count == 2)
        #expect(response.error == nil)
    }
    
    @Test("invalid response")
    func invalidResponse() {
        let response = ValidationResponse(
            isValid: false,
            error: "Not a Nightscout server"
        )
        
        #expect(!response.isValid)
        #expect(response.error != nil)
    }
    
    @Test("codable from JSON")
    func codable() throws {
        let json = """
        {
            "isValid": true,
            "version": "14.2.6",
            "serverName": "Test",
            "apiVersion": "v1"
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ValidationResponse.self, from: data)
        
        #expect(response.isValid)
        #expect(response.version == "14.2.6")
    }
}

@Suite("DiscoveryResponse")
struct DiscoveryResponseTests {
    
    @Test("empty response")
    func emptyResponse() {
        let response = DiscoveryResponse(instances: [])
        
        #expect(response.instances.isEmpty)
        #expect(response.totalCount == 0)
        #expect(!response.hasMore)
    }
    
    @Test("response with instances")
    func responseWithInstances() {
        let binding = InstanceBinding(
            id: "ns-1",
            url: URL(string: "https://test.com")!,
            displayName: "Test"
        )
        
        let response = DiscoveryResponse(
            instances: [binding],
            totalCount: 10,
            hasMore: true
        )
        
        #expect(response.instances.count == 1)
        #expect(response.totalCount == 10)
        #expect(response.hasMore)
    }
}

@Suite("DiscoveryError")
struct DiscoveryErrorTests {
    
    @Test("error descriptions")
    func errorDescriptions() {
        #expect(DiscoveryError.notAuthenticated.errorDescription != nil)
        #expect(DiscoveryError.instanceNotFound.errorDescription != nil)
        #expect(DiscoveryError.alreadyBound.errorDescription != nil)
        #expect(DiscoveryError.networkError("timeout").errorDescription != nil)
        #expect(DiscoveryError.serverError(500, "Internal error").errorDescription != nil)
        #expect(DiscoveryError.validationFailed("Invalid URL").errorDescription != nil)
    }
}

@Suite("MockDiscoveryClient")
struct MockDiscoveryClientTests {
    
    @Test("discover empty instances")
    func discoverEmptyInstances() async throws {
        let client = MockDiscoveryClient()
        let response = try await client.discoverInstances()
        
        #expect(response.instances.isEmpty)
    }
    
    @Test("bind instance")
    func bindInstance() async throws {
        let client = MockDiscoveryClient()
        let binding = try await client.bindInstance(
            url: URL(string: "https://my.ns.com")!,
            apiSecret: "test-secret",
            displayName: "My Nightscout"
        )
        
        #expect(binding.displayName == "My Nightscout")
        #expect(binding.role == .owner)
        #expect(binding.isPrimary)
    }
    
    @Test("bind duplicate throws")
    func bindDuplicateThrows() async throws {
        let client = MockDiscoveryClient()
        let url = URL(string: "https://duplicate.ns.com")!
        
        _ = try await client.bindInstance(
            url: url,
            apiSecret: "secret",
            displayName: "First"
        )
        
        await #expect(throws: DiscoveryError.self) {
            try await client.bindInstance(
                url: url,
                apiSecret: "secret",
                displayName: "Second"
            )
        }
    }
    
    @Test("discover after bind")
    func discoverAfterBind() async throws {
        let client = MockDiscoveryClient()
        
        _ = try await client.bindInstance(
            url: URL(string: "https://test1.ns.com")!,
            apiSecret: "secret1",
            displayName: "Test 1"
        )
        
        _ = try await client.bindInstance(
            url: URL(string: "https://test2.ns.com")!,
            apiSecret: "secret2",
            displayName: "Test 2"
        )
        
        let response = try await client.discoverInstances()
        
        #expect(response.instances.count == 2)
    }
    
    @Test("unbind instance")
    func unbindInstance() async throws {
        let client = MockDiscoveryClient()
        let binding = try await client.bindInstance(
            url: URL(string: "https://unbind.ns.com")!,
            apiSecret: "secret",
            displayName: "To Unbind"
        )
        
        try await client.unbindInstance(id: binding.id)
        
        let response = try await client.discoverInstances()
        #expect(response.instances.isEmpty)
    }
    
    @Test("unbind nonexistent throws")
    func unbindNonexistentThrows() async throws {
        let client = MockDiscoveryClient()
        
        await #expect(throws: DiscoveryError.self) {
            try await client.unbindInstance(id: "nonexistent")
        }
    }
    
    @Test("get primary instance")
    func getPrimaryInstance() async throws {
        let client = MockDiscoveryClient()
        
        _ = try await client.bindInstance(
            url: URL(string: "https://primary.ns.com")!,
            apiSecret: "secret",
            displayName: "Primary"
        )
        
        let primary = try await client.getPrimaryInstance()
        
        #expect(primary != nil)
        #expect(primary!.isPrimary)
    }
    
    @Test("set primary instance")
    func setPrimaryInstance() async throws {
        let client = MockDiscoveryClient()
        
        let first = try await client.bindInstance(
            url: URL(string: "https://first.ns.com")!,
            apiSecret: "secret1",
            displayName: "First"
        )
        
        let second = try await client.bindInstance(
            url: URL(string: "https://second.ns.com")!,
            apiSecret: "secret2",
            displayName: "Second"
        )
        
        var primary = try await client.getPrimaryInstance()
        #expect(primary?.id == first.id)
        
        try await client.setPrimaryInstance(id: second.id)
        
        primary = try await client.getPrimaryInstance()
        #expect(primary?.id == second.id)
    }
    
    @Test("validate instance")
    func validateInstance() async throws {
        let client = MockDiscoveryClient()
        
        let response = try await client.validateInstance(
            url: URL(string: "https://valid.ns.com")!,
            apiSecret: "secret"
        )
        
        #expect(response.isValid)
        #expect(response.version != nil)
        #expect(response.apiVersion == "v3")
    }
    
    @Test("validate instance HTTP")
    func validateInstanceHTTP() async throws {
        let client = MockDiscoveryClient()
        
        let response = try await client.validateInstance(
            url: URL(string: "http://insecure.ns.com")!,
            apiSecret: nil
        )
        
        #expect(response.isValid || response.error != nil)
    }
    
    @Test("add pre-configured binding")
    func addPreConfiguredBinding() async throws {
        let client = MockDiscoveryClient()
        let binding = InstanceBinding(
            id: "preconfigured",
            url: URL(string: "https://pre.ns.com")!,
            displayName: "Pre-configured"
        )
        
        await client.addBinding(binding)
        
        let response = try await client.discoverInstances()
        #expect(response.instances.count == 1)
        #expect(response.instances.first?.id == "preconfigured")
    }
}

@Suite("HostingType")
struct HostingTypeTests {
    
    @Test("display names")
    func displayNames() {
        #expect(HostingType.selfHosted.displayName == "Self-Hosted")
        #expect(HostingType.t1palHosted.displayName == "T1Pal Hosted")
    }
    
    @Test("all cases count")
    func allCases() {
        #expect(HostingType.allCases.count == 2)
    }
}
