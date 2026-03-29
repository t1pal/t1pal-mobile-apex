// SPDX-License-Identifier: AGPL-3.0-or-later
// KeychainHelper.swift
// T1PalCore
//
// Secure credential storage using Keychain (Darwin) with UserDefaults fallback (Linux)
// Trace: NS-SEC-001, PRD-014, BLE-CTX-033

import Foundation

#if canImport(Security)
import Security
#endif

// MARK: - Keychain Helper

/// Secure credential storage helper
/// Uses Keychain on Darwin platforms, UserDefaults fallback on Linux
///
/// Thread-safety: `@unchecked Sendable` is used because:
/// - Keychain APIs (SecItemAdd, etc.) are thread-safe (Apple docs)
/// - No mutable instance state
/// Trace: TECH-001, PROD-READY-012
public final class KeychainHelper: @unchecked Sendable {
    
    /// Shared instance
    public static let shared = KeychainHelper()
    
    /// Service identifier for Keychain items
    private let service = "com.t1pal.credentials"
    
    private init() {}
    
    // MARK: - Public API
    
    /// Save a credential securely
    /// - Parameters:
    ///   - value: The credential value to store
    ///   - account: The account identifier (e.g., Nightscout URL)
    /// - Returns: True if saved successfully
    @discardableResult
    public func save(_ value: String, forAccount account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        return saveToKeychain(data: data, account: account)
        #else
        // Linux fallback - use UserDefaults (not ideal but functional)
        UserDefaults.standard.set(value, forKey: keychainFallbackKey(account))
        return true
        #endif
    }
    
    /// Load a credential
    /// - Parameter account: The account identifier
    /// - Returns: The stored credential, or nil if not found
    public func load(forAccount account: String) -> String? {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        return loadFromKeychain(account: account)
        #else
        // Linux fallback
        return UserDefaults.standard.string(forKey: keychainFallbackKey(account))
        #endif
    }
    
    /// Delete a credential
    /// - Parameter account: The account identifier
    /// - Returns: True if deleted successfully
    @discardableResult
    public func delete(forAccount account: String) -> Bool {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        return deleteFromKeychain(account: account)
        #else
        // Linux fallback
        UserDefaults.standard.removeObject(forKey: keychainFallbackKey(account))
        return true
        #endif
    }
    
    /// Check if a credential exists
    /// - Parameter account: The account identifier
    /// - Returns: True if credential exists
    public func exists(forAccount account: String) -> Bool {
        return load(forAccount: account) != nil
    }
    
    // MARK: - Convenience Methods
    
    /// Save Nightscout API secret
    public func saveNightscoutSecret(_ secret: String, forURL url: String) -> Bool {
        save(secret, forAccount: nightscoutAccount(for: url))
    }
    
    /// Load Nightscout API secret
    public func loadNightscoutSecret(forURL url: String) -> String? {
        load(forAccount: nightscoutAccount(for: url))
    }
    
    /// Delete Nightscout API secret
    public func deleteNightscoutSecret(forURL url: String) -> Bool {
        delete(forAccount: nightscoutAccount(for: url))
    }
    
    /// Save Nightscout JWT token
    public func saveNightscoutToken(_ token: String, forURL url: String) -> Bool {
        save(token, forAccount: nightscoutTokenAccount(for: url))
    }
    
    /// Load Nightscout JWT token
    public func loadNightscoutToken(forURL url: String) -> String? {
        load(forAccount: nightscoutTokenAccount(for: url))
    }
    
    /// Delete Nightscout JWT token
    public func deleteNightscoutToken(forURL url: String) -> Bool {
        delete(forAccount: nightscoutTokenAccount(for: url))
    }
    
    // MARK: - BLE Device Config (BLE-CTX-033)
    
    /// Save BLE CGM device configuration securely
    /// - Parameters:
    ///   - config: The BLE device configuration to store
    ///   - deviceId: Unique identifier (e.g., transmitter ID or UUID)
    /// - Returns: True if saved successfully
    @discardableResult
    public func saveBLEDeviceConfig(_ config: BLEDeviceConfig, for deviceId: String) -> Bool {
        guard let data = try? JSONEncoder().encode(config),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }
        return save(jsonString, forAccount: bleDeviceAccount(for: config.cgmType, deviceId: deviceId))
    }
    
    /// Load BLE CGM device configuration
    /// - Parameters:
    ///   - cgmType: The CGM type
    ///   - deviceId: Unique identifier
    /// - Returns: The stored configuration, or nil if not found
    public func loadBLEDeviceConfig(for cgmType: BLECGMType, deviceId: String) -> BLEDeviceConfig? {
        guard let jsonString = load(forAccount: bleDeviceAccount(for: cgmType, deviceId: deviceId)),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(BLEDeviceConfig.self, from: data)
    }
    
    /// Delete BLE CGM device configuration
    /// - Parameters:
    ///   - cgmType: The CGM type
    ///   - deviceId: Unique identifier
    /// - Returns: True if deleted successfully
    @discardableResult
    public func deleteBLEDeviceConfig(for cgmType: BLECGMType, deviceId: String) -> Bool {
        delete(forAccount: bleDeviceAccount(for: cgmType, deviceId: deviceId))
    }
    
    /// Check if BLE device config exists
    public func bleDeviceConfigExists(for cgmType: BLECGMType, deviceId: String) -> Bool {
        exists(forAccount: bleDeviceAccount(for: cgmType, deviceId: deviceId))
    }
    
    // MARK: - Pump Device Config (BLE-CTX-033)
    
    /// Save pump device configuration securely
    /// - Parameters:
    ///   - config: The pump device configuration to store
    ///   - pumpId: Unique identifier (e.g., serial number or UUID)
    /// - Returns: True if saved successfully
    @discardableResult
    public func savePumpDeviceConfig(_ config: PumpDeviceConfig, for pumpId: String) -> Bool {
        guard let data = try? JSONEncoder().encode(config),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }
        return save(jsonString, forAccount: pumpDeviceAccount(for: config.pumpType, pumpId: pumpId))
    }
    
    /// Load pump device configuration
    /// - Parameters:
    ///   - pumpType: The pump type
    ///   - pumpId: Unique identifier
    /// - Returns: The stored configuration, or nil if not found
    public func loadPumpDeviceConfig(for pumpType: PumpDeviceType, pumpId: String) -> PumpDeviceConfig? {
        guard let jsonString = load(forAccount: pumpDeviceAccount(for: pumpType, pumpId: pumpId)),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(PumpDeviceConfig.self, from: data)
    }
    
    /// Delete pump device configuration
    /// - Parameters:
    ///   - pumpType: The pump type
    ///   - pumpId: Unique identifier
    /// - Returns: True if deleted successfully
    @discardableResult
    public func deletePumpDeviceConfig(for pumpType: PumpDeviceType, pumpId: String) -> Bool {
        delete(forAccount: pumpDeviceAccount(for: pumpType, pumpId: pumpId))
    }
    
    /// Check if pump device config exists
    public func pumpDeviceConfigExists(for pumpType: PumpDeviceType, pumpId: String) -> Bool {
        exists(forAccount: pumpDeviceAccount(for: pumpType, pumpId: pumpId))
    }
    
    // MARK: - Private Helpers
    
    private func nightscoutAccount(for url: String) -> String {
        "nightscout.secret.\(url.lowercased())"
    }
    
    private func nightscoutTokenAccount(for url: String) -> String {
        "nightscout.token.\(url.lowercased())"
    }
    
    private func bleDeviceAccount(for cgmType: BLECGMType, deviceId: String) -> String {
        "ble.device.\(cgmType.rawValue).\(deviceId.lowercased())"
    }
    
    private func pumpDeviceAccount(for pumpType: PumpDeviceType, pumpId: String) -> String {
        "pump.device.\(pumpType.rawValue).\(pumpId.lowercased())"
    }
    
    private func keychainFallbackKey(_ account: String) -> String {
        "keychain.fallback.\(account)"
    }
    
    // MARK: - Darwin Keychain Implementation
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    
    private func saveToKeychain(data: Data, account: String) -> Bool {
        // Delete existing item first
        deleteFromKeychain(account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func loadFromKeychain(account: String) -> String? {
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
    
    @discardableResult
    private func deleteFromKeychain(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    #endif
}

// MARK: - Keychain Error

/// Errors that can occur during Keychain operations
public enum KeychainError: Error, LocalizedError, Sendable {
    case saveFailed
    case loadFailed
    case deleteFailed
    case dataConversionFailed
    
    public var errorDescription: String? {
        switch self {
        case .saveFailed: return "Failed to save credential to Keychain"
        case .loadFailed: return "Failed to load credential from Keychain"
        case .deleteFailed: return "Failed to delete credential from Keychain"
        case .dataConversionFailed: return "Failed to convert credential data"
        }
    }
}
