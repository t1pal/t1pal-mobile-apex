// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NightscoutVersionDetector.swift - Nightscout server version detection
// Part of NightscoutKit
// Trace: NS-COMPAT-008

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Version Info

/// Parsed Nightscout version information
public struct NightscoutVersionInfo: Sendable, Codable {
    public let rawVersion: String
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let serverName: String?
    
    public init(
        rawVersion: String,
        major: Int = 0,
        minor: Int = 0,
        patch: Int = 0,
        prerelease: String? = nil,
        serverName: String? = nil
    ) {
        self.rawVersion = rawVersion
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.serverName = serverName
    }
    
    /// Parse version string (e.g., "15.0.2", "14.2.3-dev")
    public static func parse(_ versionString: String, serverName: String? = nil) -> NightscoutVersionInfo {
        var version = versionString
        var prerelease: String? = nil
        
        // Handle prerelease suffix
        if let dashIndex = version.firstIndex(of: "-") {
            prerelease = String(version[version.index(after: dashIndex)...])
            version = String(version[..<dashIndex])
        }
        
        // Parse semver components
        let components = version.split(separator: ".").compactMap { Int($0) }
        
        return NightscoutVersionInfo(
            rawVersion: versionString,
            major: !components.isEmpty ? components[0] : 0,
            minor: components.count > 1 ? components[1] : 0,
            patch: components.count > 2 ? components[2] : 0,
            prerelease: prerelease,
            serverName: serverName
        )
    }
    
    /// Semantic version string
    public var semver: String {
        if let pre = prerelease {
            return "\(major).\(minor).\(patch)-\(pre)"
        }
        return "\(major).\(minor).\(patch)"
    }
    
    /// Check if version is at least the specified version
    public func isAtLeast(major: Int, minor: Int = 0, patch: Int = 0) -> Bool {
        if self.major > major { return true }
        if self.major < major { return false }
        if self.minor > minor { return true }
        if self.minor < minor { return false }
        return self.patch >= patch
    }
    
    /// Check if version is development/prerelease
    public var isPrerelease: Bool {
        prerelease != nil
    }
}

// MARK: - Feature Compatibility

/// Features available based on Nightscout version
public struct NightscoutFeatureSet: Sendable {
    public let supportsLoopPlugin: Bool
    public let supportsOpenAPS: Bool
    public let supportsBoluscalc: Bool
    public let supportsDeviceStatus: Bool
    public let supportsProfile: Bool
    public let supportsTreatments: Bool
    public let supportsV3API: Bool
    public let supportsWebSocket: Bool
    
    public init(
        supportsLoopPlugin: Bool = false,
        supportsOpenAPS: Bool = false,
        supportsBoluscalc: Bool = false,
        supportsDeviceStatus: Bool = false,
        supportsProfile: Bool = false,
        supportsTreatments: Bool = false,
        supportsV3API: Bool = false,
        supportsWebSocket: Bool = false
    ) {
        self.supportsLoopPlugin = supportsLoopPlugin
        self.supportsOpenAPS = supportsOpenAPS
        self.supportsBoluscalc = supportsBoluscalc
        self.supportsDeviceStatus = supportsDeviceStatus
        self.supportsProfile = supportsProfile
        self.supportsTreatments = supportsTreatments
        self.supportsV3API = supportsV3API
        self.supportsWebSocket = supportsWebSocket
    }
    
    /// Determine features from version
    public static func fromVersion(_ version: NightscoutVersionInfo) -> NightscoutFeatureSet {
        // Base features available in all modern versions
        let isModern = version.isAtLeast(major: 13)
        
        return NightscoutFeatureSet(
            supportsLoopPlugin: isModern,
            supportsOpenAPS: version.isAtLeast(major: 13, minor: 0),
            supportsBoluscalc: version.isAtLeast(major: 13, minor: 0),
            supportsDeviceStatus: true, // Available in all versions
            supportsProfile: true,      // Available in all versions
            supportsTreatments: true,   // Available in all versions
            supportsV3API: version.isAtLeast(major: 15, minor: 0),
            supportsWebSocket: version.isAtLeast(major: 14, minor: 0)
        )
    }
    
    /// All features (for testing)
    public static let all = NightscoutFeatureSet(
        supportsLoopPlugin: true,
        supportsOpenAPS: true,
        supportsBoluscalc: true,
        supportsDeviceStatus: true,
        supportsProfile: true,
        supportsTreatments: true,
        supportsV3API: true,
        supportsWebSocket: true
    )
    
    /// Minimal features (legacy server)
    public static let minimal = NightscoutFeatureSet(
        supportsLoopPlugin: false,
        supportsOpenAPS: false,
        supportsBoluscalc: false,
        supportsDeviceStatus: true,
        supportsProfile: true,
        supportsTreatments: true,
        supportsV3API: false,
        supportsWebSocket: false
    )
}

// MARK: - Version Detector

/// Detects Nightscout server version and capabilities
public final class NightscoutVersionDetector: @unchecked Sendable {
    
    private let lock = NSLock()
    private var cachedVersions: [URL: NightscoutVersionInfo] = [:]
    
    // MARK: - Singleton
    
    public static let shared = NightscoutVersionDetector()
    
    private init() {}
    
    // MARK: - Detection
    
    /// Detect version from Nightscout server
    public func detectVersion(url: URL, apiSecret: String? = nil) async throws -> NightscoutVersionInfo {
        // Check cache
        let cached = lock.withLock { cachedVersions[url] }
        if let cached = cached {
            return cached
        }
        
        // Fetch status
        let statusURL = url.appendingPathComponent("api/v1/status.json")
        var request = URLRequest(url: statusURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        if let secret = apiSecret {
            request.setValue("api-secret \(secret.sha1())", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VersionDetectionError.serverError
        }
        
        // Parse status
        let status = try JSONDecoder().decode(StatusResponse.self, from: data)
        
        guard let versionString = status.version else {
            throw VersionDetectionError.noVersion
        }
        
        let version = NightscoutVersionInfo.parse(versionString, serverName: status.name)
        
        // Cache result
        lock.withLock {
            cachedVersions[url] = version
        }
        
        return version
    }
    
    /// Get features for a server
    public func detectFeatures(url: URL, apiSecret: String? = nil) async throws -> NightscoutFeatureSet {
        let version = try await detectVersion(url: url, apiSecret: apiSecret)
        return NightscoutFeatureSet.fromVersion(version)
    }
    
    /// Clear cached version info
    public func clearCache() {
        lock.withLock {
            cachedVersions.removeAll()
        }
    }
    
    /// Clear cached version for specific URL
    public func clearCache(for url: URL) {
        lock.withLock {
            _ = cachedVersions.removeValue(forKey: url)
        }
    }
}

// MARK: - Error Types

public enum VersionDetectionError: Error, LocalizedError, Sendable {
    case serverError
    case noVersion
    case invalidResponse
    
    public var errorDescription: String? {
        switch self {
        case .serverError:
            return "Failed to contact Nightscout server"
        case .noVersion:
            return "Server did not return version information"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Internal Types

private struct StatusResponse: Codable {
    let status: String?
    let name: String?
    let version: String?
    let serverTime: String?
    let apiEnabled: Bool?
    let careportalEnabled: Bool?
}
