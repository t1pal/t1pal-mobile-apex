// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// CredentialImporter.swift
// T1PalCore
//
// Import credentials from other AID apps (Loop, Trio, AAPS, xDrip4iOS).
// Reduces migration friction by preserving existing Nightscout configuration.
// Trace: ID-MIGRATE-001, ID-MIGRATE-002, ID-MIGRATE-003, PRD-003

import Foundation

#if canImport(Security)
import Security
#endif

// MARK: - Import Source

/// Source app for credential import
public enum CredentialImportSource: String, CaseIterable, Sendable {
    case loop = "Loop"
    case trio = "Trio"
    case xdrip = "xDrip4iOS"
    case aaps = "AAPS"
    
    /// Known bundle identifiers for this source
    public var knownBundleIdentifiers: [String] {
        switch self {
        case .loop:
            return [
                "com.loopkit.Loop",
                "com.loopkit.Loop.dev",
                "com.loudnate.Loop"
            ]
        case .trio:
            return [
                "org.nightscout.Trio",
                "com.diyloop.Trio"
            ]
        case .xdrip:
            return [
                "com.JohanDegraeve.xdripswift",
                "com.JohanDegraeve.xDrip4iOS"
            ]
        case .aaps:
            // AAPS is Android-only; import via exported config file
            return []
        }
    }
    
    /// Keychain account keys used by this source
    public var keychainAccountKeys: (url: String, secret: String) {
        switch self {
        case .loop, .trio:
            // Trio uses these keys with bundle identifier as service
            return ("NightscoutConfig.url", "NightscoutConfig.secret")
        case .xdrip:
            return ("nightscoutUrl", "nightscoutAPIKey")
        case .aaps:
            return ("", "") // N/A - file-based import
        }
    }
    
    /// UserDefaults keys used by this source (legacy storage)
    public var userDefaultsKeys: (url: String, secret: String) {
        switch self {
        case .loop:
            return ("nightscoutURL", "nightscoutAPISecret")
        case .trio:
            return ("NightscoutConfig.url", "NightscoutConfig.secret")
        case .xdrip:
            return ("nightscoutUrl", "nightscoutAPIKey")
        case .aaps:
            return ("", "") // N/A
        }
    }
    
    /// Display name for UI
    public var displayName: String {
        rawValue
    }
}

// MARK: - Import Result

/// Result of credential import attempt
public struct CredentialImportResult: Sendable {
    public let source: CredentialImportSource
    public let nightscoutURL: URL?
    public let hasAPISecret: Bool
    public let importedAt: Date
    public let sourceInfo: String?
    
    public var isSuccessful: Bool {
        nightscoutURL != nil && hasAPISecret
    }
    
    public var isPartial: Bool {
        nightscoutURL != nil && !hasAPISecret
    }
    
    public init(
        source: CredentialImportSource,
        nightscoutURL: URL?,
        hasAPISecret: Bool,
        importedAt: Date = Date(),
        sourceInfo: String? = nil
    ) {
        self.source = source
        self.nightscoutURL = nightscoutURL
        self.hasAPISecret = hasAPISecret
        self.importedAt = importedAt
        self.sourceInfo = sourceInfo
    }
}

// MARK: - Import Error

/// Errors during credential import
public enum CredentialImportError: Error, LocalizedError, Sendable {
    case sourceNotFound(CredentialImportSource)
    case keychainAccessDenied
    case noCredentialsFound
    case invalidURL(String)
    case partialImport(url: URL, missingSecret: Bool)
    case unsupportedPlatform
    
    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let source):
            return "\(source.displayName) app credentials not found on this device."
        case .keychainAccessDenied:
            return "Unable to access Keychain. Check app permissions."
        case .noCredentialsFound:
            return "No Nightscout credentials found in the source app."
        case .invalidURL(let urlString):
            return "Invalid Nightscout URL: \(urlString)"
        case .partialImport(let url, let missingSecret):
            if missingSecret {
                return "Found URL (\(url.host ?? "unknown")) but API secret not accessible."
            }
            return "Partial import from \(url.host ?? "unknown")."
        case .unsupportedPlatform:
            return "Credential import is only supported on iOS."
        }
    }
}

// MARK: - Credential Importer

/// Imports Nightscout credentials from other AID apps
///
/// Supports importing from:
/// - Loop (iOS) - Keychain + UserDefaults
/// - Trio (iOS) - Keychain + UserDefaults
/// - xDrip4iOS (iOS) - UserDefaults
/// - AAPS (Android) - via exported JSON config file
///
/// Trace: ID-MIGRATE-001, ID-MIGRATE-002, ID-MIGRATE-003
public actor CredentialImporter {
    
    /// Target credential store for imported credentials
    private let targetStore: any CredentialStoring
    
    /// Detected credentials cache
    private var detectedCredentials: [CredentialImportSource: CredentialImportResult] = [:]
    
    public init(targetStore: any CredentialStoring) {
        self.targetStore = targetStore
    }
    
    // MARK: - Detection
    
    /// Scan for available credentials from all supported sources
    public func scanForCredentials() async -> [CredentialImportResult] {
        var results: [CredentialImportResult] = []
        
        for source in CredentialImportSource.allCases {
            if let result = await detectCredentials(from: source) {
                results.append(result)
                detectedCredentials[source] = result
            }
        }
        
        return results
    }
    
    /// Detect credentials from a specific source
    public func detectCredentials(from source: CredentialImportSource) async -> CredentialImportResult? {
        #if os(iOS) || os(macOS)
        // Try Keychain first (more secure storage)
        if let result = await detectFromKeychain(source: source) {
            return result
        }
        
        // Fall back to UserDefaults (legacy storage)
        if let result = await detectFromUserDefaults(source: source) {
            return result
        }
        #endif
        
        return nil
    }
    
    // MARK: - Import
    
    /// Import credentials from a detected source into T1Pal's credential store
    public func importCredentials(
        from source: CredentialImportSource,
        apiSecret: String? = nil
    ) async throws -> CredentialImportResult {
        // Check cache first, then detect
        var detected = detectedCredentials[source]
        if detected == nil {
            detected = await detectCredentials(from: source)
        }
        
        guard let detected = detected else {
            throw CredentialImportError.sourceNotFound(source)
        }
        
        guard let url = detected.nightscoutURL else {
            throw CredentialImportError.noCredentialsFound
        }
        
        // Get API secret from detection or parameter
        let secret: String
        if let providedSecret = apiSecret {
            secret = providedSecret
        } else if detected.hasAPISecret {
            // Re-read the secret for actual import
            guard let loadedSecret = await loadSecretValue(from: source, for: url) else {
                throw CredentialImportError.partialImport(url: url, missingSecret: true)
            }
            secret = loadedSecret
        } else {
            throw CredentialImportError.partialImport(url: url, missingSecret: true)
        }
        
        // Store in T1Pal's credential store
        let credential = AuthCredential(
            tokenType: .apiSecret,
            value: secret,
            expiresAt: nil,
            scope: "nightscout"
        )
        
        let key = CredentialKey.nightscout(url: url)
        try await targetStore.store(credential, for: key)
        
        return CredentialImportResult(
            source: source,
            nightscoutURL: url,
            hasAPISecret: true,
            sourceInfo: "Imported from \(source.displayName)"
        )
    }
    
    /// Import from AAPS exported preferences JSON
    public func importFromAAPSExport(fileURL: URL) async throws -> CredentialImportResult {
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // AAPS stores NS config in preferences
        guard let nsUrl = json?["nsclient_url"] as? String ?? json?["nsClientURL"] as? String,
              let url = URL(string: nsUrl) else {
            throw CredentialImportError.noCredentialsFound
        }
        
        let apiSecret = json?["nsclient_api_secret"] as? String ?? json?["nsClientAPISecret"] as? String
        
        if let secret = apiSecret, !secret.isEmpty {
            let credential = AuthCredential(
                tokenType: .apiSecret,
                value: secret,
                expiresAt: nil,
                scope: "nightscout"
            )
            let key = CredentialKey.nightscout(url: url)
            try await targetStore.store(credential, for: key)
        }
        
        return CredentialImportResult(
            source: .aaps,
            nightscoutURL: url,
            hasAPISecret: apiSecret != nil && !apiSecret!.isEmpty,
            sourceInfo: "Imported from AAPS export file"
        )
    }
    
    // MARK: - Private Helpers
    
    #if os(iOS) || os(macOS)
    
    private func detectFromKeychain(source: CredentialImportSource) async -> CredentialImportResult? {
        let keys = source.keychainAccountKeys
        guard !keys.url.isEmpty else { return nil }
        
        // Try each known bundle identifier as service name
        for bundleId in source.knownBundleIdentifiers {
            if let urlString = loadFromKeychain(service: bundleId, account: keys.url),
               let url = URL(string: urlString) {
                let hasSecret = loadFromKeychain(service: bundleId, account: keys.secret) != nil
                
                return CredentialImportResult(
                    source: source,
                    nightscoutURL: url,
                    hasAPISecret: hasSecret,
                    sourceInfo: "Found in Keychain (\(bundleId))"
                )
            }
        }
        
        return nil
    }
    
    private func detectFromUserDefaults(source: CredentialImportSource) async -> CredentialImportResult? {
        let keys = source.userDefaultsKeys
        guard !keys.url.isEmpty else { return nil }
        
        // Try app group containers for each known bundle ID
        for bundleId in source.knownBundleIdentifiers {
            let appGroupId = "group.\(bundleId)"
            
            if let defaults = UserDefaults(suiteName: appGroupId),
               let urlString = defaults.string(forKey: keys.url),
               let url = URL(string: urlString) {
                let hasSecret = defaults.string(forKey: keys.secret) != nil
                
                return CredentialImportResult(
                    source: source,
                    nightscoutURL: url,
                    hasAPISecret: hasSecret,
                    sourceInfo: "Found in UserDefaults (\(appGroupId))"
                )
            }
        }
        
        // Try standard UserDefaults (same app family)
        let defaults = UserDefaults.standard
        if let urlString = defaults.string(forKey: keys.url),
           let url = URL(string: urlString) {
            let hasSecret = defaults.string(forKey: keys.secret) != nil
            
            return CredentialImportResult(
                source: source,
                nightscoutURL: url,
                hasAPISecret: hasSecret,
                sourceInfo: "Found in standard UserDefaults"
            )
        }
        
        return nil
    }
    
    private func loadSecret(from source: CredentialImportSource, for url: URL) async -> String? {
        let keys = source.keychainAccountKeys
        
        // Try Keychain first
        for bundleId in source.knownBundleIdentifiers {
            if let secret = loadFromKeychain(service: bundleId, account: keys.secret) {
                return secret
            }
        }
        
        // Try UserDefaults
        let udKeys = source.userDefaultsKeys
        for bundleId in source.knownBundleIdentifiers {
            let appGroupId = "group.\(bundleId)"
            if let defaults = UserDefaults(suiteName: appGroupId),
               let secret = defaults.string(forKey: udKeys.secret) {
                return secret
            }
        }
        
        // Try standard defaults
        if let secret = UserDefaults.standard.string(forKey: udKeys.secret) {
            return secret
        }
        
        return nil
    }
    
    private func loadFromKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    #endif
    
    // MARK: - Cross-Platform Secret Loading
    
    /// Load secret value - dispatches to platform-specific implementation
    private func loadSecretValue(from source: CredentialImportSource, for url: URL) async -> String? {
        #if os(iOS) || os(macOS)
        return await loadSecret(from: source, for: url)
        #else
        // On Linux, credential import from other apps is not supported
        // (AAPS file import still works)
        return nil
        #endif
    }
}

// MARK: - Factory

extension CredentialImporter {
    
    /// Create importer with Keychain-backed target store
    public static func withKeychainStore() -> CredentialImporter {
        CredentialImporter(targetStore: KeychainCredentialStore.nightscout)
    }
    
    /// Create importer with memory store (for testing)
    public static func withMemoryStore(_ store: MemoryCredentialStore) -> CredentialImporter {
        CredentialImporter(targetStore: store)
    }
}
