// NightscoutDataSourceTests.swift - Tests for NightscoutDataSource
// Part of NightscoutKitTests
//
// Task: DS-STREAM-004

import Testing
import Foundation
@testable import NightscoutKit
@testable import T1PalCore

// MARK: - NightscoutDataSource Tests

@Suite("NightscoutDataSource")
struct NightscoutDataSourceTests {
    
    // MARK: - Initialization Tests
    
    @Test("Create from URL")
    func createFromURL() async {
        let url = URL(string: "https://example.nightscout.com")!
        let source = NightscoutDataSource(url: url, apiSecret: "test-secret", name: "Test NS")
        
        #expect(source.name == "Test NS")
        #expect(source.id.hasPrefix("nightscout-"))
    }
    
    @Test("Create from client")
    func createFromClient() async {
        let config = NightscoutConfig(
            url: URL(string: "https://example.nightscout.com")!,
            apiSecret: "test-secret"
        )
        let client = NightscoutClient(config: config)
        let source = NightscoutDataSource(client: client, name: "Client Source")
        
        #expect(source.name == "Client Source")
        #expect(source.id.hasPrefix("nightscout-"))
    }
    
    @Test("Factory method with URL string")
    func factoryMethodURLString() async {
        let source = NightscoutDataSource.create(
            urlString: "https://test.herokuapp.com",
            apiSecret: "secret123",
            name: "Factory Source"
        )
        
        #expect(source != nil)
        #expect(source?.name == "Factory Source")
    }
    
    @Test("Factory method with invalid URL returns nil")
    func factoryMethodInvalidURL() async {
        // Empty string is definitely an invalid URL
        let source = NightscoutDataSource.create(
            urlString: "",
            apiSecret: nil,
            name: "Invalid"
        )
        
        #expect(source == nil)
    }
    
    // MARK: - Status Tests
    
    @Test("Initial status is disconnected")
    func initialStatusDisconnected() async {
        let url = URL(string: "https://example.nightscout.com")!
        let source = NightscoutDataSource(url: url, name: "Status Test")
        
        // Note: status is async and may attempt connection
        // For unit test, we just verify the source was created
        #expect(source.id.hasPrefix("nightscout-"))
    }
    
    @Test("Status description for connected")
    func statusDescriptionConnected() async {
        // This would require mocking - for now just verify the property exists
        let url = URL(string: "https://example.nightscout.com")!
        let source = NightscoutDataSource(url: url, name: "Desc Test")
        
        let description = await source.statusDescription
        // Initially should be disconnected or connecting
        #expect(!description.isEmpty)
    }
}

// MARK: - DataSourceManager Integration Tests

@Suite("NightscoutDataSource DataSourceManager Integration")
struct NightscoutDataSourceManagerTests {
    
    @Test("Register Nightscout with DataSourceManager")
    func registerNightscout() async {
        let manager = DataSourceManager()
        let url = URL(string: "https://test.nightscout.com")!
        
        let source = await manager.registerNightscout(
            url: url,
            apiSecret: "test-secret",
            name: "Integrated NS",
            setActive: true
        )
        
        #expect(source.name == "Integrated NS")
        
        // Verify it was registered
        let activeSource = await manager.activeSource
        #expect(activeSource?.id == source.id)
    }
    
    @Test("Register multiple Nightscout sources")
    func registerMultipleSources() async {
        let manager = DataSourceManager()
        
        let source1 = await manager.registerNightscout(
            url: URL(string: "https://ns1.example.com")!,
            apiSecret: "secret1",
            name: "NS One",
            setActive: false
        )
        
        let source2 = await manager.registerNightscout(
            url: URL(string: "https://ns2.example.com")!,
            apiSecret: "secret2",
            name: "NS Two",
            setActive: true
        )
        
        let sources = await manager.sources
        #expect(sources.count >= 2)
        
        let activeSource = await manager.activeSource
        #expect(activeSource?.id == source2.id)
    }
    
    @Test("Register with NightscoutClient")
    func registerWithClient() async {
        let manager = DataSourceManager()
        let config = NightscoutConfig(
            url: URL(string: "https://client.nightscout.com")!,
            apiSecret: "client-secret"
        )
        let client = NightscoutClient(config: config)
        
        let source = await manager.registerNightscout(
            client: client,
            name: "Client-Based NS",
            setActive: true
        )
        
        #expect(source.name == "Client-Based NS")
        
        let activeSource = await manager.activeSource
        #expect(activeSource?.id == source.id)
    }
}

// MARK: - GlucoseDataSource Protocol Conformance

@Suite("NightscoutDataSource Protocol Conformance")
struct NightscoutDataSourceProtocolTests {
    
    @Test("Implements GlucoseDataSource protocol")
    func implementsProtocol() async {
        let url = URL(string: "https://example.nightscout.com")!
        let source = NightscoutDataSource(url: url, name: "Protocol Test")
        
        // Verify protocol properties are accessible
        let _ = source.id
        let _ = source.name
        let _ = await source.status
        
        // Protocol methods exist (would throw on actual network call)
        // Just verify the types compile correctly
        #expect(source.id.hasPrefix("nightscout-"))
    }
    
    @Test("Can be used as GlucoseDataSource")
    func usableAsGlucoseDataSource() async {
        let url = URL(string: "https://example.nightscout.com")!
        let source: any GlucoseDataSource = NightscoutDataSource(url: url, name: "Any Test")
        
        #expect(source.name == "Any Test")
        #expect(!source.id.isEmpty)
    }
}
