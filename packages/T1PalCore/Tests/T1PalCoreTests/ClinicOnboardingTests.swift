// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ClinicOnboardingTests.swift
// T1PalCoreTests
//
// Tests for clinic/enterprise onboarding flow.
// Trace: ID-ENT-002

import Testing
@testable import T1PalCore
import Foundation

// MARK: - Clinic QR Payload Tests

@Suite("ClinicQRPayload Tests")
struct ClinicQRPayloadTests {
    
    @Test("Parse valid QR payload")
    func testParseValid() throws {
        let json = """
        {
            "clinicId": "clinic-123",
            "clinicName": "Test Clinic",
            "issuerURL": "https://auth.testclinic.com"
        }
        """
        
        let payload = try ClinicQRPayload.parse(from: json)
        
        #expect(payload.clinicId == "clinic-123")
        #expect(payload.clinicName == "Test Clinic")
        #expect(payload.issuerURL == URL(string: "https://auth.testclinic.com")!)
        #expect(payload.clientId == nil)
        #expect(payload.additionalScopes == nil)
    }
    
    @Test("Parse full QR payload")
    func testParseFullPayload() throws {
        let json = """
        {
            "clinicId": "clinic-456",
            "clinicName": "Full Test Clinic",
            "issuerURL": "https://auth.fullclinic.com",
            "clientId": "t1pal-client",
            "redirectUri": "t1pal://callback",
            "additionalScopes": ["patient.read", "fhirUser"],
            "profileSyncURL": "https://api.fullclinic.com/profile",
            "settingsSyncURL": "https://api.fullclinic.com/settings"
        }
        """
        
        let payload = try ClinicQRPayload.parse(from: json)
        
        #expect(payload.clinicId == "clinic-456")
        #expect(payload.clientId == "t1pal-client")
        #expect(payload.additionalScopes?.count == 2)
        #expect(payload.profileSyncURL != nil)
        #expect(payload.settingsSyncURL != nil)
    }
    
    @Test("Parse payload with expiration")
    func testParseWithExpiration() throws {
        let futureDate = Date().addingTimeInterval(3600) // 1 hour from now
        let isoFormatter = ISO8601DateFormatter()
        let dateString = isoFormatter.string(from: futureDate)
        
        let json = """
        {
            "clinicId": "clinic-exp",
            "clinicName": "Expiring Clinic",
            "issuerURL": "https://auth.expclinic.com",
            "expiresAt": "\(dateString)"
        }
        """
        
        let payload = try ClinicQRPayload.parse(from: json)
        
        #expect(payload.expiresAt != nil)
        #expect(payload.isExpired == false)
    }
    
    @Test("Detect expired payload")
    func testExpiredPayload() throws {
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let isoFormatter = ISO8601DateFormatter()
        let dateString = isoFormatter.string(from: pastDate)
        
        let json = """
        {
            "clinicId": "clinic-old",
            "clinicName": "Old Clinic",
            "issuerURL": "https://auth.oldclinic.com",
            "expiresAt": "\(dateString)"
        }
        """
        
        let payload = try ClinicQRPayload.parse(from: json)
        
        #expect(payload.isExpired == true)
    }
    
    @Test("Parse fails for invalid JSON")
    func testInvalidJSON() {
        let json = "not valid json"
        
        #expect(throws: ClinicOnboardingError.self) {
            try ClinicQRPayload.parse(from: json)
        }
    }
    
    @Test("Parse fails for missing required fields")
    func testMissingFields() {
        let json = """
        {
            "clinicId": "clinic-123"
        }
        """
        
        #expect(throws: ClinicOnboardingError.self) {
            try ClinicQRPayload.parse(from: json)
        }
    }
}

// MARK: - Clinic User Profile Tests

@Suite("ClinicUserProfile Tests")
struct ClinicUserProfileTests {
    
    @Test("Profile initializes correctly")
    func testInitialization() {
        let profile = ClinicUserProfile(
            subject: "user_123",
            name: "John Doe",
            email: "john@example.com",
            emailVerified: true,
            organizationName: "Test Clinic",
            role: "patient"
        )
        
        #expect(profile.subject == "user_123")
        #expect(profile.name == "John Doe")
        #expect(profile.email == "john@example.com")
        #expect(profile.emailVerified == true)
        #expect(profile.organizationName == "Test Clinic")
        #expect(profile.role == "patient")
    }
    
    @Test("Profile is codable")
    func testCodable() throws {
        let profile = ClinicUserProfile(
            subject: "user_456",
            name: "Jane Doe",
            email: "jane@example.com",
            emailVerified: true,
            organizationName: "Another Clinic",
            role: "caregiver"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(profile)
        let decoded = try decoder.decode(ClinicUserProfile.self, from: data)
        
        #expect(decoded == profile)
    }
    
    @Test("Profile with additional claims")
    func testAdditionalClaims() {
        let profile = ClinicUserProfile(
            subject: "user_789",
            additionalClaims: [
                "department": "Endocrinology",
                "mrn": "12345678"
            ]
        )
        
        #expect(profile.additionalClaims?["department"] == "Endocrinology")
        #expect(profile.additionalClaims?["mrn"] == "12345678")
    }
}

// MARK: - Clinic Onboarding State Tests

@Suite("ClinicOnboardingState Tests")
struct ClinicOnboardingStateTests {
    
    @Test("State initializes empty")
    func testInitialization() {
        let state = ClinicOnboardingState()
        
        #expect(state.providerConfig == nil)
        #expect(state.qrPayload == nil)
        #expect(state.userProfile == nil)
        #expect(state.hasAccessToken == false)
        #expect(state.hasRefreshToken == false)
        #expect(state.settingsSynced == false)
        #expect(state.error == nil)
    }
    
    @Test("State resets correctly")
    func testReset() {
        var state = ClinicOnboardingState()
        
        // Set some values
        state.hasAccessToken = true
        state.hasRefreshToken = true
        state.settingsSynced = true
        state.error = .authenticationCancelled
        
        // Reset
        state.reset()
        
        #expect(state.hasAccessToken == false)
        #expect(state.hasRefreshToken == false)
        #expect(state.settingsSynced == false)
        #expect(state.error == nil)
    }
}

// MARK: - Clinic Onboarding Error Tests

@Suite("ClinicOnboardingError Tests")
struct ClinicOnboardingErrorTests {
    
    @Test("Error descriptions are meaningful")
    func testErrorDescriptions() {
        let errors: [ClinicOnboardingError] = [
            .invalidQRCode("bad format"),
            .qrCodeExpired,
            .providerNotFound,
            .discoveryFailed("timeout"),
            .authenticationFailed("invalid token"),
            .authenticationCancelled,
            .profileFetchFailed("network error"),
            .settingsSyncFailed("server error"),
            .networkError("no connection")
        ]
        
        for error in errors {
            #expect(error.localizedDescription.count > 10)
            #expect(!error.localizedDescription.isEmpty)
        }
    }
    
    @Test("Expired QR code error message")
    func testExpiredMessage() {
        let error = ClinicOnboardingError.qrCodeExpired
        #expect(error.localizedDescription.contains("expired"))
    }
    
    @Test("Authentication cancelled error message")
    func testCancelledMessage() {
        let error = ClinicOnboardingError.authenticationCancelled
        #expect(error.localizedDescription.contains("cancelled"))
    }
}

// MARK: - Default Steps Tests

@Suite("ClinicOnboardingStep Tests")
struct ClinicOnboardingStepTests {
    
    @Test("Default steps are complete")
    func testDefaultSteps() {
        let steps = ClinicOnboardingStep.defaultSteps
        
        // 9 steps: welcome, scanQRCode, selectProvider, authenticate, reviewProfile,
        // discoverInstances, selectInstance, syncSettings, complete
        #expect(steps.count == 9)
        #expect(steps.first?.type == .welcome)
        #expect(steps.last?.type == .complete)
    }
    
    @Test("Steps have required properties")
    func testStepProperties() {
        for step in ClinicOnboardingStep.defaultSteps {
            #expect(!step.id.isEmpty)
            #expect(!step.title.isEmpty)
            #expect(!step.iconName.isEmpty)
        }
    }
    
    @Test("Skippable steps are marked")
    func testSkippableSteps() {
        let steps = ClinicOnboardingStep.defaultSteps
        
        let scanStep = steps.first { $0.type == .scanQRCode }
        let selectStep = steps.first { $0.type == .selectProvider }
        let syncStep = steps.first { $0.type == .syncSettings }
        let authStep = steps.first { $0.type == .authenticate }
        
        #expect(scanStep?.isSkippable == true)
        #expect(selectStep?.isSkippable == true)
        #expect(syncStep?.isSkippable == true)
        #expect(authStep?.isSkippable == false)
    }
}

// MARK: - Clinic Onboarding Manager Tests

// Note: ClinicOnboardingManager tests require iOS 17+ / macOS 14+ with Observation framework.
// These tests are skipped on Linux. Run on macOS or iOS for full coverage.

#if os(macOS) || os(iOS)
// Manager tests would go here but require @Observable which isn't available on Linux
#endif
