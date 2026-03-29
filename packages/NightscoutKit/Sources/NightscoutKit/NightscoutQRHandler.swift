// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutQRHandler.swift
// T1Pal Mobile
//
// Handler for processing Nightscout QR code scan results
// Requirements: NS-QR-003, NS-QR-004

import Foundation

#if canImport(Combine)
import Combine

/// Handler for Nightscout QR code scanning workflow
///
/// Usage:
/// ```swift
/// let handler = NightscoutQRHandler { config in
///     // Configure your NightscoutClient with config
///     nightscoutClient.configure(config)
/// }
/// 
/// // When QR code is scanned:
/// handler.handleScan(result: scannedString)
/// ```
@MainActor
public final class NightscoutQRHandler: ObservableObject {
    
    /// Current scanning state
    @Published public private(set) var state: ScanState = .idle
    
    /// Callback when credentials are successfully extracted
    public var onCredentialsExtracted: ((NightscoutConfig) -> Void)?
    
    /// Callback for errors
    public var onError: ((ScanError) -> Void)?
    
    /// Scanning state
    public enum ScanState: Equatable {
        case idle
        case processing
        case validating
        case success(url: URL, hasSecret: Bool, validated: Bool)
        case error(ScanError)
    }
    
    /// Scan error types
    public enum ScanError: Error, Equatable {
        case notNightscoutQR
        case invalidJSON
        case invalidPayload(String)
        case extractionFailed(String)
        case connectionFailed(String)
        
        public var localizedDescription: String {
            switch self {
            case .notNightscoutQR:
                return "This QR code doesn't appear to be a Nightscout configuration"
            case .invalidJSON:
                return "Invalid QR code format"
            case .invalidPayload(let detail):
                return "Invalid Nightscout payload: \(detail)"
            case .extractionFailed(let detail):
                return "Could not extract credentials: \(detail)"
            case .connectionFailed(let detail):
                return "Connection failed: \(detail)"
            }
        }
    }
    
    public init(
        onCredentialsExtracted: ((NightscoutConfig) -> Void)? = nil,
        onError: ((ScanError) -> Void)? = nil
    ) {
        self.onCredentialsExtracted = onCredentialsExtracted
        self.onError = onError
    }
    
    /// Handle a scanned QR code string
    ///
    /// - Parameters:
    ///   - result: Raw string from QR code scan
    ///   - validate: If true, validates connection before completing (default: false)
    public func handleScan(result: String, validate: Bool = false) {
        state = .processing
        
        // Quick check: does it look like Nightscout JSON?
        guard result.contains("rest") && result.contains("endpoint") else {
            let error = ScanError.notNightscoutQR
            state = .error(error)
            onError?(error)
            return
        }
        
        do {
            let payload = try NightscoutQRPayload.parse(from: result)
            let credentials = try payload.extractCredentials()
            let config = credentials.toConfig()
            
            if validate {
                state = .validating
                Task {
                    await validateAndComplete(config: config, credentials: credentials)
                }
            } else {
                state = .success(url: credentials.url, hasSecret: !credentials.apiSecret.isEmpty, validated: false)
                onCredentialsExtracted?(config)
            }
            
        } catch let error as NightscoutQRPayload.ParseError {
            let scanError: ScanError
            switch error {
            case .noEndpoints:
                scanError = .invalidPayload("No endpoint URL found")
            case .invalidURL:
                scanError = .extractionFailed("Invalid URL format")
            case .missingCredentials:
                scanError = .extractionFailed("No API secret in URL")
            case .malformedBasicAuth:
                scanError = .extractionFailed("Malformed authentication")
            }
            state = .error(scanError)
            onError?(scanError)
            
        } catch is DecodingError {
            let error = ScanError.invalidJSON
            state = .error(error)
            onError?(error)
            
        } catch {
            let scanError = ScanError.extractionFailed(error.localizedDescription)
            state = .error(scanError)
            onError?(scanError)
        }
    }
    
    /// Reset to idle state
    public func reset() {
        state = .idle
    }
    
    /// Validate connection and complete the scan flow
    private func validateAndComplete(config: NightscoutConfig, credentials: NightscoutQRPayload.Credentials) async {
        do {
            try await validateConnection(config: config)
            state = .success(url: credentials.url, hasSecret: !credentials.apiSecret.isEmpty, validated: true)
            onCredentialsExtracted?(config)
        } catch {
            let scanError = ScanError.connectionFailed(error.localizedDescription)
            state = .error(scanError)
            onError?(scanError)
        }
    }
    
    /// Validate connection to Nightscout server
    ///
    /// Makes a test request to status.json to verify the URL and credentials work.
    /// - Parameter config: NightscoutConfig to validate
    /// - Throws: ConnectionError if validation fails
    public func validateConnection(config: NightscoutConfig) async throws {
        let statusUrl = config.url.appendingPathComponent("api/v1/status.json")
        
        var request = URLRequest(url: statusUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        // Add auth header if available
        if let token = config.token {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        } else if let hash = config.apiSecretHash {
            request.setValue("api-secret " + hash, forHTTPHeaderField: "api-secret")
        }
        
        #if canImport(FoundationNetworking)
        // Linux: throw error indicating validation requires iOS
        throw ConnectionError.platformUnsupported
        #else
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ConnectionError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 401, 403:
            throw ConnectionError.authenticationFailed
        case 404:
            throw ConnectionError.serverNotFound
        default:
            throw ConnectionError.serverError(httpResponse.statusCode)
        }
        #endif
    }
    
    /// Connection validation errors
    public enum ConnectionError: Error, LocalizedError {
        case platformUnsupported
        case invalidResponse
        case authenticationFailed
        case serverNotFound
        case serverError(Int)
        
        public var errorDescription: String? {
            switch self {
            case .platformUnsupported:
                return "Connection validation not supported on this platform"
            case .invalidResponse:
                return "Invalid response from server"
            case .authenticationFailed:
                return "Authentication failed - check API secret"
            case .serverNotFound:
                return "Nightscout server not found"
            case .serverError(let code):
                return "Server error (HTTP \(code))"
            }
        }
    }
    
    /// Check if a string might be a Nightscout QR code
    ///
    /// - Parameter string: String to check
    /// - Returns: true if the string looks like Nightscout JSON
    public static func looksLikeNightscoutQR(_ string: String) -> Bool {
        string.contains("rest") && string.contains("endpoint")
    }
}

#endif // canImport(Combine)
