// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutQRPayload.swift
// T1Pal Mobile
//
// QR code payload parsing for Nightscout configuration
// Requirements: NS-QR-001, NS-QR-002

import Foundation

/// Standard Nightscout QR code payload format
///
/// QR codes use the format:
/// ```json
/// {"rest": {"endpoint": ["https://<api_secret>@<domain>/"]}}
/// ```
///
/// Example:
/// ```json
/// {"rest": {"endpoint": ["https://myapisecret123@mysite.herokuapp.com/"]}}
/// ```
public struct NightscoutQRPayload: Codable, Sendable {
    public let rest: RestConfig
    
    public struct RestConfig: Codable, Sendable {
        public let endpoint: [String]
        
        public init(endpoint: [String]) {
            self.endpoint = endpoint
        }
    }
    
    public init(rest: RestConfig) {
        self.rest = rest
    }
    
    /// Decoded credentials from the QR payload
    public struct Credentials: Sendable, Equatable {
        public let url: URL
        public let apiSecret: String
        
        public init(url: URL, apiSecret: String) {
            self.url = url
            self.apiSecret = apiSecret
        }
        
        /// Convert to NightscoutConfig
        public func toConfig() -> NightscoutConfig {
            NightscoutConfig(url: url, apiSecret: apiSecret)
        }
    }
    
    /// Parse error types
    public enum ParseError: Error, Equatable {
        case noEndpoints
        case invalidURL
        case missingCredentials
        case malformedBasicAuth
    }
    
    /// Extract URL and API secret from the first endpoint
    ///
    /// Parses the basic auth format: `https://<secret>@<domain>/`
    ///
    /// - Returns: Credentials with clean URL and extracted secret
    /// - Throws: ParseError if the endpoint cannot be parsed
    public func extractCredentials() throws -> Credentials {
        guard let endpointString = rest.endpoint.first, !endpointString.isEmpty else {
            throw ParseError.noEndpoints
        }
        
        guard let url = URL(string: endpointString) else {
            throw ParseError.invalidURL
        }
        
        // Extract the user component (API secret)
        guard let secret = url.user, !secret.isEmpty else {
            throw ParseError.missingCredentials
        }
        
        // Remove user (secret) from URL to get clean base URL
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ParseError.malformedBasicAuth
        }
        
        components.user = nil
        components.password = nil
        
        guard let cleanURL = components.url else {
            throw ParseError.malformedBasicAuth
        }
        
        return Credentials(url: cleanURL, apiSecret: secret)
    }
    
    /// Parse QR code JSON data into a payload
    ///
    /// - Parameter data: JSON data from QR code scan
    /// - Returns: Parsed NightscoutQRPayload
    /// - Throws: DecodingError if JSON is invalid
    public static func parse(from data: Data) throws -> NightscoutQRPayload {
        let decoder = JSONDecoder()
        return try decoder.decode(NightscoutQRPayload.self, from: data)
    }
    
    /// Parse QR code JSON string into a payload
    ///
    /// - Parameter jsonString: JSON string from QR code scan
    /// - Returns: Parsed NightscoutQRPayload
    /// - Throws: DecodingError if JSON is invalid
    public static func parse(from jsonString: String) throws -> NightscoutQRPayload {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Could not convert string to UTF-8 data"
                )
            )
        }
        return try parse(from: data)
    }
}
