// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ManagedSettingsTests.swift
// T1PalCoreTests
//
// Tests for provider-managed settings functionality.
// Trace: ID-ENT-003

import Testing
import Foundation
@testable import T1PalCore

@Suite("Managed Settings Tests")
struct ManagedSettingsTests {
    
    // MARK: - Settings Policy Tests
    
    @Suite("Settings Policy")
    struct SettingsPolicyTests {
        @Test("Settings policy allows override")
        func settingsPolicyAllowsOverride() {
            #expect(!SettingsPolicy.locked.allowsOverride)
            #expect(SettingsPolicy.suggested.allowsOverride)
            #expect(SettingsPolicy.default.allowsOverride)
        }
        
        @Test("Settings policy description")
        func settingsPolicyDescription() {
            #expect(SettingsPolicy.locked.description == "Set by your care team")
            #expect(SettingsPolicy.suggested.description == "Recommended by your care team")
            #expect(SettingsPolicy.default.description == "Your preference")
        }
        
        @Test("Settings policy icon name")
        func settingsPolicyIconName() {
            #expect(SettingsPolicy.locked.iconName == "lock.fill")
            #expect(SettingsPolicy.suggested.iconName == "sparkles")
            #expect(SettingsPolicy.default.iconName == "person.fill")
        }
    }
    
    // MARK: - Managed Setting Value Tests
    
    @Suite("Managed Setting Value")
    struct ManagedSettingValueTests {
        @Test("Managed setting value creation")
        func managedSettingValueCreation() {
            let setting = ManagedSettingValue(value: 180.0, policy: .locked, reason: "Safety limit")
            
            #expect(setting.value == 180.0)
            #expect(setting.policy == .locked)
            #expect(setting.reason == "Safety limit")
        }
        
        @Test("Managed setting value default policy")
        func managedSettingValueDefaultPolicy() {
            let setting = ManagedSettingValue(value: 70.0)
            
            #expect(setting.policy == .suggested)
            #expect(setting.reason == nil)
        }
    }
    
    // MARK: - Managed Settings Payload Tests
    
    @Suite("Managed Settings Payload")
    struct ManagedSettingsPayloadTests {
        @Test("Managed settings payload creation")
        func managedSettingsPayloadCreation() {
            let payload = ManagedSettingsPayload(
                providerId: "clinic.123",
                providerName: "Acme Clinic",
                version: 1,
                highGlucoseThreshold: ManagedSettingValue(value: 180.0, policy: .locked),
                lowGlucoseThreshold: ManagedSettingValue(value: 70.0, policy: .suggested)
            )
            
            #expect(payload.providerId == "clinic.123")
            #expect(payload.providerName == "Acme Clinic")
            #expect(payload.version == 1)
            #expect(payload.highGlucoseThreshold?.value == 180.0)
            #expect(payload.highGlucoseThreshold?.policy == .locked)
            #expect(payload.lowGlucoseThreshold?.value == 70.0)
            #expect(payload.lowGlucoseThreshold?.policy == .suggested)
        }
        
        @Test("Managed settings payload expiration")
        func managedSettingsPayloadExpiration() {
            let notExpired = ManagedSettingsPayload(
                providerId: "clinic.123",
                providerName: "Test",
                expiresAt: Date().addingTimeInterval(3600)
            )
            #expect(!notExpired.isExpired)
            
            let expired = ManagedSettingsPayload(
                providerId: "clinic.123",
                providerName: "Test",
                expiresAt: Date().addingTimeInterval(-3600)
            )
            #expect(expired.isExpired)
            
            let noExpiry = ManagedSettingsPayload(
                providerId: "clinic.123",
                providerName: "Test",
                expiresAt: nil
            )
            #expect(!noExpiry.isExpired)
        }
        
        @Test("Managed settings payload JSON parsing")
        func managedSettingsPayloadJSONParsing() throws {
            let json = """
            {
                "providerId": "clinic.456",
                "providerName": "Test Clinic",
                "issuedAt": "2026-02-22T10:00:00Z",
                "version": 2,
                "highGlucoseThreshold": {
                    "value": 180.0,
                    "policy": "locked",
                    "reason": "Safety requirement"
                },
                "lowGlucoseThreshold": {
                    "value": 70.0,
                    "policy": "suggested"
                }
            }
            """.data(using: .utf8)!
            
            let payload = try ManagedSettingsPayload.parse(from: json)
            
            #expect(payload.providerId == "clinic.456")
            #expect(payload.providerName == "Test Clinic")
            #expect(payload.version == 2)
            #expect(payload.highGlucoseThreshold?.value == 180.0)
            #expect(payload.highGlucoseThreshold?.policy == .locked)
            #expect(payload.highGlucoseThreshold?.reason == "Safety requirement")
            #expect(payload.lowGlucoseThreshold?.value == 70.0)
            #expect(payload.lowGlucoseThreshold?.policy == .suggested)
        }
        
        @Test("Managed settings payload full JSON parsing")
        func managedSettingsPayloadFullJSONParsing() throws {
            let json = """
            {
                "providerId": "clinic.789",
                "providerName": "Full Test Clinic",
                "issuedAt": "2026-02-22T10:00:00Z",
                "expiresAt": "2027-02-22T10:00:00Z",
                "version": 3,
                "glucoseUnit": {"value": "mg/dL", "policy": "suggested"},
                "highGlucoseThreshold": {"value": 180.0, "policy": "locked"},
                "lowGlucoseThreshold": {"value": 70.0, "policy": "locked"},
                "urgentHighThreshold": {"value": 250.0, "policy": "suggested"},
                "urgentLowThreshold": {"value": 55.0, "policy": "locked", "reason": "Critical safety"},
                "highAlertEnabled": {"value": true, "policy": "locked"},
                "lowAlertEnabled": {"value": true, "policy": "locked"},
                "urgentAlertEnabled": {"value": true, "policy": "locked"},
                "staleDataAlertEnabled": {"value": true, "policy": "suggested"},
                "staleDataMinutes": {"value": 15, "policy": "suggested"},
                "targetGlucose": {"value": 110.0, "policy": "suggested"},
                "correctionRangeLow": {"value": 100.0, "policy": "suggested"},
                "correctionRangeHigh": {"value": 120.0, "policy": "suggested"},
                "maxBasalRate": {"value": 2.5, "policy": "locked"},
                "maxBolus": {"value": 10.0, "policy": "locked"},
                "suspendThreshold": {"value": 70.0, "policy": "locked"}
            }
            """.data(using: .utf8)!
            
            let payload = try ManagedSettingsPayload.parse(from: json)
            
            #expect(payload.providerId == "clinic.789")
            #expect(payload.version == 3)
            #expect(payload.expiresAt != nil)
            #expect(payload.glucoseUnit?.value == "mg/dL")
            #expect(payload.maxBasalRate?.value == 2.5)
            #expect(payload.maxBasalRate?.policy == .locked)
            #expect(payload.maxBolus?.value == 10.0)
            #expect(payload.suspendThreshold?.value == 70.0)
            #expect(payload.urgentLowThreshold?.reason == "Critical safety")
        }
    }
    
    // MARK: - Managed Setting Field Tests
    
    @Suite("Managed Setting Field")
    struct ManagedSettingFieldTests {
        @Test("Managed setting field display names")
        func managedSettingFieldDisplayNames() {
            #expect(ManagedSettingField.glucoseUnit.displayName == "Glucose Unit")
            #expect(ManagedSettingField.highGlucoseThreshold.displayName == "High Threshold")
            #expect(ManagedSettingField.maxBasalRate.displayName == "Max Basal")
            #expect(ManagedSettingField.suspendThreshold.displayName == "Suspend Threshold")
        }
        
        @Test("All managed setting fields have display names")
        func allManagedSettingFieldsHaveDisplayNames() {
            for field in ManagedSettingField.allCases {
                #expect(!field.displayName.isEmpty, "\(field) should have display name")
            }
        }
    }
    
    // MARK: - AnyCodable Tests
    
    @Suite("AnyCodable")
    struct AnyCodableTests {
        @Test("AnyCodable bool encoding")
        func anyCodableBoolEncoding() throws {
            let value = AnyCodable(true)
            let encoded = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
            #expect(decoded.value as? Bool == true)
        }
        
        @Test("AnyCodable int encoding")
        func anyCodableIntEncoding() throws {
            let value = AnyCodable(42)
            let encoded = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
            #expect(decoded.value as? Int == 42)
        }
        
        @Test("AnyCodable double encoding")
        func anyCodableDoubleEncoding() throws {
            let value = AnyCodable(3.14)
            let encoded = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
            #expect(decoded.value as? Double == 3.14)
        }
        
        @Test("AnyCodable string encoding")
        func anyCodableStringEncoding() throws {
            let value = AnyCodable("hello")
            let encoded = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
            #expect(decoded.value as? String == "hello")
        }
        
        @Test("AnyCodable equality")
        func anyCodableEquality() {
            #expect(AnyCodable(true) == AnyCodable(true))
            #expect(AnyCodable(42) == AnyCodable(42))
            #expect(AnyCodable(3.14) == AnyCodable(3.14))
            #expect(AnyCodable("test") == AnyCodable("test"))
            #expect(AnyCodable(true) != AnyCodable(false))
            #expect(AnyCodable(1) != AnyCodable(2))
        }
    }
    
    // MARK: - Managed Settings Manager Tests
    
    @Suite("Managed Settings Manager", .serialized)
    struct ManagedSettingsManagerTests {
        
        /// Clear any persisted settings before each test to ensure isolation
        private func clearPersistedSettings() {
            UserDefaults.standard.removeObject(forKey: "com.t1pal.managedSettings")
        }
        
        @Test("Managed settings manager initial state")
        func managedSettingsManagerInitialState() async {
            clearPersistedSettings()
            let manager = ManagedSettingsManager()
            
            let hasSettings = await manager.hasManagedSettings()
            let providerName = await manager.providerName()
            
            if !hasSettings {
                #expect(providerName == nil)
            }
        }
        
        @Test("Managed settings manager policy lookup")
        func managedSettingsManagerPolicyLookup() async {
            clearPersistedSettings()
            let manager = ManagedSettingsManager()
            
            let policy = await manager.policy(for: .glucoseUnit)
            #expect(policy == .default)
            
            let canModify = await manager.canModify(field: .glucoseUnit)
            #expect(canModify)
        }
        
        @Test("Managed settings manager apply payload")
        func managedSettingsManagerApplyPayload() async throws {
            clearPersistedSettings()
            let manager = ManagedSettingsManager()
            
            let payload = ManagedSettingsPayload(
                providerId: "test.clinic",
                providerName: "Test Clinic",
                version: 1,
                highGlucoseThreshold: ManagedSettingValue(value: 180.0, policy: .locked),
                lowGlucoseThreshold: ManagedSettingValue(value: 70.0, policy: .suggested)
            )
            
            try await manager.apply(payload)
            
            let hasSettings = await manager.hasManagedSettings()
            #expect(hasSettings)
            
            let providerName = await manager.providerName()
            #expect(providerName == "Test Clinic")
            
            let highPolicy = await manager.policy(for: .highGlucoseThreshold)
            #expect(highPolicy == .locked)
            
            let canModifyHigh = await manager.canModify(field: .highGlucoseThreshold)
            #expect(!canModifyHigh)
            
            let lowPolicy = await manager.policy(for: .lowGlucoseThreshold)
            #expect(lowPolicy == .suggested)
            
            let canModifyLow = await manager.canModify(field: .lowGlucoseThreshold)
            #expect(canModifyLow)
            
            // Cleanup
            await manager.clearManagedSettings()
        }
        
        @Test("Managed settings manager rejects expired payload")
        func managedSettingsManagerRejectsExpiredPayload() async {
            clearPersistedSettings()
            let manager = ManagedSettingsManager()
            
            let expiredPayload = ManagedSettingsPayload(
                providerId: "test.clinic",
                providerName: "Test Clinic",
                expiresAt: Date().addingTimeInterval(-3600),
                version: 1
            )
            
            await #expect(throws: ManagedSettingsError.self) {
                try await manager.apply(expiredPayload)
            }
        }
        
        @Test("Managed settings manager version conflict")
        func managedSettingsManagerVersionConflict() async throws {
            clearPersistedSettings()
            let manager = ManagedSettingsManager()
            
            // Apply version 5
            let v5Payload = ManagedSettingsPayload(
                providerId: "test.clinic",
                providerName: "Test Clinic",
                version: 5
            )
            try await manager.apply(v5Payload)
            
            // Try to apply version 3 (older)
            let v3Payload = ManagedSettingsPayload(
                providerId: "test.clinic",
                providerName: "Test Clinic",
                version: 3
            )
            
            do {
                try await manager.apply(v3Payload)
                Issue.record("Should have thrown versionConflict error")
            } catch let error as ManagedSettingsError {
                if case .versionConflict(let current, let incoming) = error {
                    #expect(current == 5)
                    #expect(incoming == 3)
                } else {
                    Issue.record("Wrong error type: \(error)")
                }
            }
            
            // Cleanup
            await manager.clearManagedSettings()
        }
        
        @Test("Managed settings manager clear settings")
        func managedSettingsManagerClearSettings() async throws {
            clearPersistedSettings()
            let manager = ManagedSettingsManager()
            
            let payload = ManagedSettingsPayload(
                providerId: "test.clinic",
                providerName: "Test Clinic",
                version: 1
            )
            try await manager.apply(payload)
            
            var hasSettings = await manager.hasManagedSettings()
            #expect(hasSettings)
            
            await manager.clearManagedSettings()
            
            hasSettings = await manager.hasManagedSettings()
            #expect(!hasSettings)
            
            let providerName = await manager.providerName()
            #expect(providerName == nil)
        }
    }
    
    // MARK: - Error Tests
    
    @Suite("Errors")
    struct ErrorTests {
        @Test("Managed settings error descriptions")
        func managedSettingsErrorDescriptions() {
            let networkError = ManagedSettingsError.networkError("Connection failed")
            #expect(networkError.localizedDescription.contains("Network error"))
            
            let fetchError = ManagedSettingsError.fetchFailed("HTTP 500")
            #expect(fetchError.localizedDescription.contains("Could not fetch"))
            
            let parseError = ManagedSettingsError.parseFailed("Invalid JSON")
            #expect(parseError.localizedDescription.contains("Invalid settings format"))
            
            let expiredError = ManagedSettingsError.settingsExpired
            #expect(expiredError.localizedDescription.contains("expired"))
            
            let versionError = ManagedSettingsError.versionConflict(current: 5, incoming: 3)
            #expect(versionError.localizedDescription.contains("conflict"))
        }
    }
}
