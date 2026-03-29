// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutQRHandlerTests.swift
// T1Pal Mobile
//
// Tests for QR code handler including validation
// Requirements: NS-QR-003, NS-QR-010

import Foundation
import Testing
@testable import NightscoutKit

#if canImport(Combine)
import Combine

// MARK: - State Tests

@Suite("NightscoutQRHandler State")
@MainActor
struct NightscoutQRHandlerStateTests {
    @Test("Initial state is idle")
    func initialState() {
        let handler = NightscoutQRHandler()
        #expect(handler.state == .idle)
    }
    
    @Test("Reset state")
    func resetState() {
        let handler = NightscoutQRHandler()
        handler.handleScan(result: "invalid")
        #expect(handler.state != .idle)
        
        handler.reset()
        #expect(handler.state == .idle)
    }
}

// MARK: - Scan Without Validation

@Suite("NightscoutQRHandler Scan")
@MainActor
struct NightscoutQRHandlerScanTests {
    @Test("Handle scan valid QR")
    func handleScanValidQR() {
        let handler = NightscoutQRHandler()
        let json = """
        {"rest": {"endpoint": ["https://myapisecret123@mysite.herokuapp.com/"]}}
        """
        
        handler.handleScan(result: json)
        
        if case .success(let url, let hasSecret, let validated) = handler.state {
            #expect(url.host == "mysite.herokuapp.com")
            #expect(hasSecret)
            #expect(!validated) // Not validated by default
        } else {
            Issue.record("Expected success state, got \(handler.state)")
        }
    }
    
    @Test("Handle scan not Nightscout QR")
    func handleScanNotNightscoutQR() {
        let handler = NightscoutQRHandler()
        
        handler.handleScan(result: "just some random text")
        
        if case .error(let error) = handler.state {
            #expect(error == .notNightscoutQR)
        } else {
            Issue.record("Expected error state")
        }
    }
    
    @Test("Handle scan invalid JSON")
    func handleScanInvalidJSON() {
        let handler = NightscoutQRHandler()
        // Contains rest and endpoint keywords but invalid JSON
        let invalid = """
        {rest: endpoint ["broken"}
        """
        
        handler.handleScan(result: invalid)
        
        if case .error(let error) = handler.state {
            #expect(error == .invalidJSON)
        } else {
            Issue.record("Expected error state")
        }
    }
    
    @Test("Handle scan missing credentials")
    func handleScanMissingCredentials() {
        let handler = NightscoutQRHandler()
        // Valid JSON but URL has no credentials
        let json = """
        {"rest": {"endpoint": ["https://mysite.com/"]}}
        """
        
        handler.handleScan(result: json)
        
        if case .error(let error) = handler.state {
            #expect(error == .extractionFailed("No API secret in URL"))
        } else {
            Issue.record("Expected error state, got \(handler.state)")
        }
    }
}

// MARK: - Callbacks

@Suite("NightscoutQRHandler Callbacks")
@MainActor
struct NightscoutQRHandlerCallbackTests {
    @Test("On credentials extracted callback")
    func onCredentialsExtractedCallback() {
        var extractedConfig: NightscoutConfig?
        let handler = NightscoutQRHandler(
            onCredentialsExtracted: { config in
                extractedConfig = config
            }
        )
        
        let json = """
        {"rest": {"endpoint": ["https://secret123@site.com/"]}}
        """
        
        handler.handleScan(result: json)
        
        #expect(extractedConfig != nil)
        #expect(extractedConfig?.url.host == "site.com")
        #expect(extractedConfig?.apiSecret == "secret123")
    }
    
    @Test("On error callback")
    func onErrorCallback() {
        var receivedError: NightscoutQRHandler.ScanError?
        let handler = NightscoutQRHandler(
            onError: { error in
                receivedError = error
            }
        )
        
        handler.handleScan(result: "not nightscout")
        
        #expect(receivedError != nil)
        #expect(receivedError == .notNightscoutQR)
    }
}

// MARK: - Static Helpers

@Suite("NightscoutQRHandler Helpers")
struct NightscoutQRHandlerHelperTests {
    @Test("Looks like Nightscout QR")
    func looksLikeNightscoutQR() {
        #expect(NightscoutQRHandler.looksLikeNightscoutQR(
            #"{"rest": {"endpoint": ["https://s@site.com/"]}}"#
        ))
        #expect(!NightscoutQRHandler.looksLikeNightscoutQR("random text"))
        #expect(!NightscoutQRHandler.looksLikeNightscoutQR("rest without endpoint"))
        #expect(!NightscoutQRHandler.looksLikeNightscoutQR("endpoint without rest"))
    }
}

// MARK: - Connection Error Tests

@Suite("NightscoutQRHandler Connection Errors")
struct NightscoutQRHandlerConnectionErrorTests {
    @Test("Connection error descriptions")
    func connectionErrorDescriptions() {
        #expect(NightscoutQRHandler.ConnectionError.platformUnsupported.errorDescription != nil)
        #expect(NightscoutQRHandler.ConnectionError.invalidResponse.errorDescription != nil)
        #expect(NightscoutQRHandler.ConnectionError.authenticationFailed.errorDescription != nil)
        #expect(NightscoutQRHandler.ConnectionError.serverNotFound.errorDescription != nil)
        #expect(NightscoutQRHandler.ConnectionError.serverError(500).errorDescription != nil)
        
        #expect(NightscoutQRHandler.ConnectionError.serverError(503).errorDescription!.contains("503"))
    }
}

// MARK: - ScanError Tests

@Suite("NightscoutQRHandler Scan Errors")
struct NightscoutQRHandlerScanErrorTests {
    @Test("Scan error descriptions")
    func scanErrorDescriptions() {
        #expect(NightscoutQRHandler.ScanError.notNightscoutQR.localizedDescription.contains("QR"))
        #expect(NightscoutQRHandler.ScanError.invalidJSON.localizedDescription.contains("Invalid"))
        #expect(NightscoutQRHandler.ScanError.connectionFailed("timeout").localizedDescription.contains("timeout"))
    }
}

// MARK: - Validation Parameter

@Suite("NightscoutQRHandler Validation")
@MainActor
struct NightscoutQRHandlerValidationTests {
    @Test("Handle scan with validate false")
    func handleScanWithValidateFalse() {
        let handler = NightscoutQRHandler()
        let json = """
        {"rest": {"endpoint": ["https://secret@site.com/"]}}
        """
        
        handler.handleScan(result: json, validate: false)
        
        // Should complete synchronously without validation
        if case .success(_, _, let validated) = handler.state {
            #expect(!validated)
        } else {
            Issue.record("Expected success state")
        }
    }
}

#endif // canImport(Combine)
