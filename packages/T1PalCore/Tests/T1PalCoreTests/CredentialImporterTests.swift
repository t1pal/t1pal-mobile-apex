// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// CredentialImporterTests.swift
// T1PalCoreTests
//
// Tests for credential import from Loop, Trio, xDrip4iOS, AAPS
// Trace: ID-MIGRATE-001, ID-MIGRATE-002, ID-MIGRATE-003

import Testing
import Foundation
@testable import T1PalCore

@Suite("Credential Importer Tests")
struct CredentialImporterTests {
    
    // MARK: - Source Configuration Tests
    
    @Suite("Source Configuration")
    struct SourceConfigurationTests {
        @Test("Loop source has correct bundle identifiers")
        func loopSourceHasCorrectBundleIdentifiers() {
            let source = CredentialImportSource.loop
            #expect(source.knownBundleIdentifiers.contains("com.loopkit.Loop"))
            #expect(source.knownBundleIdentifiers.contains("com.loudnate.Loop"))
        }
        
        @Test("Trio source has correct bundle identifiers")
        func trioSourceHasCorrectBundleIdentifiers() {
            let source = CredentialImportSource.trio
            #expect(source.knownBundleIdentifiers.contains("org.nightscout.Trio"))
        }
        
        @Test("xDrip source has correct bundle identifiers")
        func xDripSourceHasCorrectBundleIdentifiers() {
            let source = CredentialImportSource.xdrip
            #expect(source.knownBundleIdentifiers.contains("com.JohanDegraeve.xdripswift"))
        }
        
        @Test("AAPS source has no bundle identifiers (Android-only)")
        func aapsSourceHasNoBundleIdentifiers() {
            let source = CredentialImportSource.aaps
            #expect(source.knownBundleIdentifiers.isEmpty)
        }
        
        @Test("Keychain account keys are correct")
        func keychainAccountKeys() {
            let loop = CredentialImportSource.loop
            #expect(loop.keychainAccountKeys.url == "NightscoutConfig.url")
            #expect(loop.keychainAccountKeys.secret == "NightscoutConfig.secret")
            
            let xdrip = CredentialImportSource.xdrip
            #expect(xdrip.keychainAccountKeys.url == "nightscoutUrl")
            #expect(xdrip.keychainAccountKeys.secret == "nightscoutAPIKey")
        }
        
        @Test("User defaults keys are correct")
        func userDefaultsKeys() {
            let loop = CredentialImportSource.loop
            #expect(loop.userDefaultsKeys.url == "nightscoutURL")
            #expect(loop.userDefaultsKeys.secret == "nightscoutAPISecret")
        }
    }
    
    // MARK: - Import Result Tests
    
    @Suite("Import Results")
    struct ImportResultTests {
        @Test("Successful import result")
        func successfulImportResult() {
            let result = CredentialImportResult(
                source: .loop,
                nightscoutURL: URL(string: "https://myns.herokuapp.com")!,
                hasAPISecret: true
            )
            
            #expect(result.isSuccessful)
            #expect(!result.isPartial)
            #expect(result.source == .loop)
        }
        
        @Test("Partial import result")
        func partialImportResult() {
            let result = CredentialImportResult(
                source: .trio,
                nightscoutURL: URL(string: "https://myns.herokuapp.com")!,
                hasAPISecret: false
            )
            
            #expect(!result.isSuccessful)
            #expect(result.isPartial)
        }
        
        @Test("Failed import result")
        func failedImportResult() {
            let result = CredentialImportResult(
                source: .xdrip,
                nightscoutURL: nil,
                hasAPISecret: false
            )
            
            #expect(!result.isSuccessful)
            #expect(!result.isPartial)
        }
    }
    
    // MARK: - Error Tests
    
    @Suite("Errors")
    struct ErrorTests {
        @Test("Source not found error contains source name")
        func sourceNotFoundError() {
            let error = CredentialImportError.sourceNotFound(.loop)
            #expect(error.errorDescription?.contains("Loop") ?? false)
        }
        
        @Test("Invalid URL error contains 'Invalid'")
        func invalidURLError() {
            let error = CredentialImportError.invalidURL("not-a-url")
            #expect(error.errorDescription?.contains("Invalid") ?? false)
        }
        
        @Test("Partial import error contains 'secret'")
        func partialImportError() {
            let error = CredentialImportError.partialImport(
                url: URL(string: "https://myns.herokuapp.com")!,
                missingSecret: true
            )
            #expect(error.errorDescription?.contains("secret") ?? false)
        }
    }
    
    // MARK: - AAPS Export Import Tests
    
    @Suite("AAPS Export Import")
    struct AAPSExportImportTests {
        @Test("Import from AAPS export JSON")
        func importFromAAPSExportJSON() async throws {
            let memoryStore = MemoryCredentialStore()
            let importer = CredentialImporter.withMemoryStore(memoryStore)
            
            let exportJSON: [String: Any] = [
                "nsclient_url": "https://aaps-ns.herokuapp.com",
                "nsclient_api_secret": "test-secret-123"
            ]
            
            let tempDir = FileManager.default.temporaryDirectory
            let exportFile = tempDir.appendingPathComponent("aaps-export-\(UUID()).json")
            
            let data = try JSONSerialization.data(withJSONObject: exportJSON)
            try data.write(to: exportFile)
            
            defer {
                try? FileManager.default.removeItem(at: exportFile)
            }
            
            let result = try await importer.importFromAAPSExport(fileURL: exportFile)
            
            #expect(result.source == .aaps)
            #expect(result.nightscoutURL?.absoluteString == "https://aaps-ns.herokuapp.com")
            #expect(result.hasAPISecret)
            #expect(result.isSuccessful)
            
            // Verify credential was stored
            let key = CredentialKey.nightscout(url: result.nightscoutURL!)
            let stored = try await memoryStore.retrieve(for: key)
            #expect(stored.tokenType == .apiSecret)
            #expect(stored.value == "test-secret-123")
            
            await memoryStore.clear()
        }
        
        @Test("Import from AAPS export with alternative keys")
        func importFromAAPSExportAlternativeKeys() async throws {
            let memoryStore = MemoryCredentialStore()
            let importer = CredentialImporter.withMemoryStore(memoryStore)
            
            let exportJSON: [String: Any] = [
                "nsClientURL": "https://alt-ns.herokuapp.com",
                "nsClientAPISecret": "alt-secret"
            ]
            
            let tempDir = FileManager.default.temporaryDirectory
            let exportFile = tempDir.appendingPathComponent("aaps-export-alt-\(UUID()).json")
            
            let data = try JSONSerialization.data(withJSONObject: exportJSON)
            try data.write(to: exportFile)
            
            defer {
                try? FileManager.default.removeItem(at: exportFile)
            }
            
            let result = try await importer.importFromAAPSExport(fileURL: exportFile)
            
            #expect(result.nightscoutURL?.absoluteString == "https://alt-ns.herokuapp.com")
            #expect(result.hasAPISecret)
            
            await memoryStore.clear()
        }
        
        @Test("Import from AAPS export partial (URL only)")
        func importFromAAPSExportPartial() async throws {
            let memoryStore = MemoryCredentialStore()
            let importer = CredentialImporter.withMemoryStore(memoryStore)
            
            let exportJSON: [String: Any] = [
                "nsclient_url": "https://partial-ns.herokuapp.com"
            ]
            
            let tempDir = FileManager.default.temporaryDirectory
            let exportFile = tempDir.appendingPathComponent("aaps-export-partial-\(UUID()).json")
            
            let data = try JSONSerialization.data(withJSONObject: exportJSON)
            try data.write(to: exportFile)
            
            defer {
                try? FileManager.default.removeItem(at: exportFile)
            }
            
            let result = try await importer.importFromAAPSExport(fileURL: exportFile)
            
            #expect(result.nightscoutURL?.absoluteString == "https://partial-ns.herokuapp.com")
            #expect(!result.hasAPISecret)
            #expect(result.isPartial)
            
            await memoryStore.clear()
        }
        
        @Test("Import from AAPS export with no credentials throws error")
        func importFromAAPSExportNoCredentials() async throws {
            let memoryStore = MemoryCredentialStore()
            let importer = CredentialImporter.withMemoryStore(memoryStore)
            
            let exportJSON: [String: Any] = [
                "some_other_setting": "value"
            ]
            
            let tempDir = FileManager.default.temporaryDirectory
            let exportFile = tempDir.appendingPathComponent("aaps-export-empty-\(UUID()).json")
            
            let data = try JSONSerialization.data(withJSONObject: exportJSON)
            try data.write(to: exportFile)
            
            defer {
                try? FileManager.default.removeItem(at: exportFile)
            }
            
            await #expect(throws: CredentialImportError.self) {
                _ = try await importer.importFromAAPSExport(fileURL: exportFile)
            }
            
            await memoryStore.clear()
        }
    }
    
    // MARK: - Scan Tests
    
    @Suite("Credential Scan")
    struct ScanTests {
        @Test("Scan for credentials returns array")
        func scanForCredentialsReturnsArray() async {
            let memoryStore = MemoryCredentialStore()
            let importer = CredentialImporter.withMemoryStore(memoryStore)
            
            let results = await importer.scanForCredentials()
            #expect(results != nil)
            
            await memoryStore.clear()
        }
    }
    
    // MARK: - Factory Tests
    
    @Suite("Factory Methods")
    struct FactoryTests {
        @Test("Factory with keychain store")
        func factoryWithKeychainStore() {
            let importer = CredentialImporter.withKeychainStore()
            #expect(importer != nil)
        }
        
        @Test("Factory with memory store")
        func factoryWithMemoryStore() {
            let store = MemoryCredentialStore()
            let importer = CredentialImporter.withMemoryStore(store)
            #expect(importer != nil)
        }
    }
}
