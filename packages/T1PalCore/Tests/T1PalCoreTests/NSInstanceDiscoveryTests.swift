// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NSInstanceDiscoveryTests.swift
// T1PalCoreTests
//
// Tests for Nightscout instance discovery protocol and types.
// Trace: PRD-003, REQ-ID-004

import Foundation
import Testing
@testable import T1PalCore

@Suite("NS Instance Discovery Tests")
struct NSInstanceDiscoveryTests {
    
    // MARK: - Instance Binding Tests
    
    @Test("NSInstanceBinding initializes with all properties")
    func testInstanceBindingInit() {
        let binding = NSInstanceBinding(
            id: "test-instance-1",
            url: URL(string: "https://my.nightscout.com")!,
            displayName: "My Nightscout",
            role: .owner,
            isPrimary: true,
            hostingType: .selfHosted,
            createdAt: Date()
        )
        
        #expect(binding.id == "test-instance-1")
        #expect(binding.url.absoluteString == "https://my.nightscout.com")
        #expect(binding.displayName == "My Nightscout")
        #expect(binding.role == .owner)
        #expect(binding.isPrimary == true)
        #expect(binding.hostingType == .selfHosted)
    }
    
    @Test("NSInstanceBinding defaults are sensible")
    func testInstanceBindingDefaults() {
        let binding = NSInstanceBinding(
            id: "minimal",
            url: URL(string: "https://ns.example.com")!,
            displayName: "Minimal"
        )
        
        #expect(binding.role == .owner)
        #expect(binding.isPrimary == false)
        #expect(binding.hostingType == .selfHosted)
    }
    
    // MARK: - Role Tests
    
    @Test("NSInstanceRole has correct display names")
    func testRoleDisplayNames() {
        #expect(NSInstanceRole.owner.displayName == "Owner")
        #expect(NSInstanceRole.caregiver.displayName == "Caregiver")
        #expect(NSInstanceRole.follower.displayName == "Follower")
        #expect(NSInstanceRole.provider.displayName == "Healthcare Provider")
    }
    
    @Test("NSInstanceRole write permissions are correct")
    func testRoleWritePermissions() {
        #expect(NSInstanceRole.owner.canWriteTreatments == true)
        #expect(NSInstanceRole.caregiver.canWriteTreatments == true)
        #expect(NSInstanceRole.provider.canWriteTreatments == true)
        #expect(NSInstanceRole.follower.canWriteTreatments == false)
    }
    
    // MARK: - Hosting Type Tests
    
    @Test("NSHostingType has correct display names")
    func testHostingTypeDisplayNames() {
        #expect(NSHostingType.t1palHosted.displayName == "T1Pal Hosted")
        #expect(NSHostingType.selfHosted.displayName == "Self-Hosted")
        #expect(NSHostingType.heroku.displayName == "Heroku")
        #expect(NSHostingType.other.displayName == "Other")
    }
    
    // MARK: - Discovery Response Tests
    
    @Test("NSDiscoveryResponse initializes correctly")
    func testDiscoveryResponse() {
        let instances = [
            NSInstanceBinding(id: "1", url: URL(string: "https://ns1.com")!, displayName: "NS1"),
            NSInstanceBinding(id: "2", url: URL(string: "https://ns2.com")!, displayName: "NS2")
        ]
        
        let response = NSDiscoveryResponse(instances: instances, hasMore: false)
        
        #expect(response.instances.count == 2)
        #expect(response.totalCount == 2)
        #expect(response.hasMore == false)
    }
    
    @Test("NSDiscoveryResponse totalCount can differ from instances count")
    func testDiscoveryResponsePagination() {
        let instances = [
            NSInstanceBinding(id: "1", url: URL(string: "https://ns1.com")!, displayName: "NS1")
        ]
        
        let response = NSDiscoveryResponse(instances: instances, totalCount: 5, hasMore: true)
        
        #expect(response.instances.count == 1)
        #expect(response.totalCount == 5)
        #expect(response.hasMore == true)
    }
    
    // MARK: - Validation Response Tests
    
    @Test("NSValidationResponse initializes correctly")
    func testValidationResponse() {
        let response = NSValidationResponse(
            isValid: true,
            version: "15.0.2",
            capabilities: ["careportal", "iob", "cob"]
        )
        
        #expect(response.isValid == true)
        #expect(response.version == "15.0.2")
        #expect(response.capabilities.count == 3)
        #expect(response.error == nil)
    }
    
    @Test("NSValidationResponse can represent failure")
    func testValidationResponseFailure() {
        let response = NSValidationResponse(
            isValid: false,
            error: "Connection timeout"
        )
        
        #expect(response.isValid == false)
        #expect(response.error == "Connection timeout")
    }
    
    // MARK: - Error Tests
    
    @Test("NSDiscoveryError has correct descriptions")
    func testErrorDescriptions() {
        let errors: [NSDiscoveryError] = [
            .notAuthenticated,
            .networkError("timeout"),
            .serverError(500, "Internal Server Error"),
            .invalidResponse,
            .instanceNotFound,
            .validationFailed("bad URL")
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(error.errorDescription!.isEmpty == false)
        }
    }
    
    // MARK: - Mock Client Tests
    
    @Test("MockNSDiscoveryClient requires access token")
    func testMockClientRequiresAuth() async throws {
        let client = MockNSDiscoveryClient()
        // No token set
        
        do {
            _ = try await client.discoverInstances()
            #expect(Bool(false), "Should have thrown notAuthenticated")
        } catch let error as NSDiscoveryError {
            if case .notAuthenticated = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected notAuthenticated error")
            }
        }
    }
    
    @Test("MockNSDiscoveryClient returns configured instances")
    func testMockClientReturnsInstances() async throws {
        let client = MockNSDiscoveryClient()
        await client.setAccessToken("test-token")
        
        let instances = [
            NSInstanceBinding(id: "mock-1", url: URL(string: "https://mock.ns.com")!, displayName: "Mock NS")
        ]
        await client.setMockInstances(instances)
        
        let response = try await client.discoverInstances()
        
        #expect(response.instances.count == 1)
        #expect(response.instances[0].id == "mock-1")
    }
    
    @Test("MockNSDiscoveryClient can simulate failures")
    func testMockClientSimulatesFailure() async throws {
        let client = MockNSDiscoveryClient()
        await client.setAccessToken("test-token")
        await client.setFailure(.serverError(503, "Service Unavailable"))
        
        do {
            _ = try await client.discoverInstances()
            #expect(Bool(false), "Should have thrown")
        } catch let error as NSDiscoveryError {
            if case .serverError(let code, _) = error {
                #expect(code == 503)
            } else {
                #expect(Bool(false), "Expected serverError")
            }
        }
    }
    
    @Test("MockNSDiscoveryClient validates instances")
    func testMockClientValidation() async throws {
        let client = MockNSDiscoveryClient()
        
        let response = try await client.validateInstance(
            url: URL(string: "https://test.ns.com")!,
            apiSecret: nil
        )
        
        #expect(response.isValid == true)
        #expect(response.version == "15.0.2")
        #expect(response.capabilities.contains("iob"))
    }
}

// MARK: - Codable Tests

@Suite("NS Instance Codable Tests")
struct NSInstanceCodableTests {
    
    @Test("NSInstanceBinding encodes and decodes correctly")
    func testBindingCodable() throws {
        let binding = NSInstanceBinding(
            id: "codable-test",
            url: URL(string: "https://ns.example.com")!,
            displayName: "Codable Test",
            role: .caregiver,
            isPrimary: true,
            hostingType: .heroku
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(binding)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NSInstanceBinding.self, from: data)
        
        #expect(decoded.id == binding.id)
        #expect(decoded.url == binding.url)
        #expect(decoded.displayName == binding.displayName)
        #expect(decoded.role == binding.role)
        #expect(decoded.isPrimary == binding.isPrimary)
        #expect(decoded.hostingType == binding.hostingType)
    }
    
    @Test("NSDiscoveryResponse encodes and decodes correctly")
    func testResponseCodable() throws {
        let instances = [
            NSInstanceBinding(id: "1", url: URL(string: "https://ns1.com")!, displayName: "NS1")
        ]
        let response = NSDiscoveryResponse(instances: instances, totalCount: 10, hasMore: true)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(response)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NSDiscoveryResponse.self, from: data)
        
        #expect(decoded.instances.count == 1)
        #expect(decoded.totalCount == 10)
        #expect(decoded.hasMore == true)
    }
}
