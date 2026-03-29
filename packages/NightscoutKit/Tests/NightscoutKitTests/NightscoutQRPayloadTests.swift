// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutQRPayloadTests.swift
// T1Pal Mobile
//
// Tests for QR code payload parsing
// Requirements: NS-QR-001, NS-QR-002

import Foundation
import Testing
@testable import NightscoutKit

// MARK: - NS-QR-001: Payload Parsing

@Suite("NightscoutQRPayload Parsing")
struct NightscoutQRPayloadParsingTests {
    @Test("Parse valid QR payload")
    func parseValidQRPayload() throws {
        let json = """
        {"rest": {"endpoint": ["https://myapisecret123@mysite.herokuapp.com/"]}}
        """
        
        let payload = try NightscoutQRPayload.parse(from: json)
        
        #expect(payload.rest.endpoint.count == 1)
        #expect(payload.rest.endpoint.first == "https://myapisecret123@mysite.herokuapp.com/")
    }
    
    @Test("Parse multiple endpoints")
    func parseMultipleEndpoints() throws {
        let json = """
        {"rest": {"endpoint": ["https://secret1@site1.com/", "https://secret2@site2.com/"]}}
        """
        
        let payload = try NightscoutQRPayload.parse(from: json)
        
        #expect(payload.rest.endpoint.count == 2)
    }
    
    @Test("Parse from Data")
    func parseFromData() throws {
        let json = """
        {"rest": {"endpoint": ["https://abc123@ns.example.com/"]}}
        """
        let data = json.data(using: .utf8)!
        
        let payload = try NightscoutQRPayload.parse(from: data)
        
        #expect(payload.rest.endpoint.first == "https://abc123@ns.example.com/")
    }
    
    @Test("Parse missing rest key throws")
    func parseMissingRestKey() {
        let json = """
        {"other": {"endpoint": ["https://secret@site.com/"]}}
        """
        
        #expect(throws: (any Error).self) {
            try NightscoutQRPayload.parse(from: json)
        }
    }
    
    @Test("Parse missing endpoint key throws")
    func parseMissingEndpointKey() {
        let json = """
        {"rest": {"urls": ["https://secret@site.com/"]}}
        """
        
        #expect(throws: (any Error).self) {
            try NightscoutQRPayload.parse(from: json)
        }
    }
    
    @Test("Parse invalid JSON throws")
    func parseInvalidJSON() {
        let json = "not valid json"
        
        #expect(throws: (any Error).self) {
            try NightscoutQRPayload.parse(from: json)
        }
    }
}

// MARK: - NS-QR-002: Credential Extraction

@Suite("NightscoutQRPayload Credential Extraction")
struct NightscoutQRPayloadCredentialTests {
    @Test("Extract credentials success")
    func extractCredentialsSuccess() throws {
        let json = """
        {"rest": {"endpoint": ["https://myapisecret123@mysite.herokuapp.com/"]}}
        """
        let payload = try NightscoutQRPayload.parse(from: json)
        
        let credentials = try payload.extractCredentials()
        
        #expect(credentials.url.absoluteString == "https://mysite.herokuapp.com/")
        #expect(credentials.apiSecret == "myapisecret123")
    }
    
    @Test("Extract credentials with port")
    func extractCredentialsWithPort() throws {
        let json = """
        {"rest": {"endpoint": ["https://secretABC@localhost:1337/"]}}
        """
        let payload = try NightscoutQRPayload.parse(from: json)
        
        let credentials = try payload.extractCredentials()
        
        #expect(credentials.url.absoluteString == "https://localhost:1337/")
        #expect(credentials.apiSecret == "secretABC")
    }
    
    @Test("Extract credentials with path")
    func extractCredentialsWithPath() throws {
        let json = """
        {"rest": {"endpoint": ["https://secret@site.com/api/v1/"]}}
        """
        let payload = try NightscoutQRPayload.parse(from: json)
        
        let credentials = try payload.extractCredentials()
        
        #expect(credentials.url.absoluteString == "https://site.com/api/v1/")
        #expect(credentials.apiSecret == "secret")
    }
    
    @Test("Extract credentials uses first endpoint")
    func extractCredentialsUsesFirstEndpoint() throws {
        let json = """
        {"rest": {"endpoint": ["https://first@site1.com/", "https://second@site2.com/"]}}
        """
        let payload = try NightscoutQRPayload.parse(from: json)
        
        let credentials = try payload.extractCredentials()
        
        #expect(credentials.apiSecret == "first")
        #expect(credentials.url.host == "site1.com")
    }
    
    @Test("Extract credentials no endpoints throws")
    func extractCredentialsNoEndpoints() throws {
        let payload = NightscoutQRPayload(
            rest: NightscoutQRPayload.RestConfig(endpoint: [])
        )
        
        #expect(throws: NightscoutQRPayload.ParseError.noEndpoints) {
            try payload.extractCredentials()
        }
    }
    
    @Test("Extract credentials empty endpoint throws")
    func extractCredentialsEmptyEndpoint() throws {
        let payload = NightscoutQRPayload(
            rest: NightscoutQRPayload.RestConfig(endpoint: [""])
        )
        
        #expect(throws: NightscoutQRPayload.ParseError.noEndpoints) {
            try payload.extractCredentials()
        }
    }
    
    @Test("Extract credentials missing secret throws")
    func extractCredentialsMissingSecret() throws {
        let json = """
        {"rest": {"endpoint": ["https://site.com/"]}}
        """
        let payload = try NightscoutQRPayload.parse(from: json)
        
        #expect(throws: NightscoutQRPayload.ParseError.missingCredentials) {
            try payload.extractCredentials()
        }
    }
    
    @Test("Extract credentials invalid URL throws")
    func extractCredentialsInvalidURL() throws {
        // Use characters that URL() definitively rejects
        let payload = NightscoutQRPayload(
            rest: NightscoutQRPayload.RestConfig(endpoint: ["://invalid\u{0000}url"])
        )
        
        #expect(throws: NightscoutQRPayload.ParseError.invalidURL) {
            try payload.extractCredentials()
        }
    }
    
    @Test("Extract credentials URL without credentials throws")
    func extractCredentialsURLWithoutCredentials() throws {
        // A path-like string parses as URL but has no user component
        let payload = NightscoutQRPayload(
            rest: NightscoutQRPayload.RestConfig(endpoint: ["not a valid url"])
        )
        
        #expect(throws: NightscoutQRPayload.ParseError.missingCredentials) {
            try payload.extractCredentials()
        }
    }
    
    @Test("Extract credentials special characters in secret")
    func extractCredentialsSpecialCharactersInSecret() throws {
        // URL-encoded special characters in secret
        let json = """
        {"rest": {"endpoint": ["https://my%40secret%21@site.com/"]}}
        """
        let payload = try NightscoutQRPayload.parse(from: json)
        
        let credentials = try payload.extractCredentials()
        
        // URL.user returns decoded value
        #expect(credentials.apiSecret == "my@secret!")
        #expect(credentials.url.absoluteString == "https://site.com/")
    }
}

// MARK: - Credentials Conversion

@Suite("NightscoutQRPayload Conversion")
struct NightscoutQRPayloadConversionTests {
    @Test("Credentials to config")
    func credentialsToConfig() throws {
        let json = """
        {"rest": {"endpoint": ["https://myapisecret@mysite.com/"]}}
        """
        let payload = try NightscoutQRPayload.parse(from: json)
        let credentials = try payload.extractCredentials()
        
        let config = credentials.toConfig()
        
        #expect(config.url.absoluteString == "https://mysite.com/")
        #expect(config.apiSecret == "myapisecret")
        #expect(config.token == nil)
    }
    
    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let original = NightscoutQRPayload(
            rest: NightscoutQRPayload.RestConfig(endpoint: ["https://secret@site.com/"])
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NightscoutQRPayload.self, from: data)
        
        #expect(decoded.rest.endpoint == original.rest.endpoint)
    }
}
