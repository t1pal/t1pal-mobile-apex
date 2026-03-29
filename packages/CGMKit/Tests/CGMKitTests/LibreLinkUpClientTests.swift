// SPDX-License-Identifier: MIT
//
// LibreLinkUpClientTests.swift
// CGMKit
//
// Tests for LibreLink Up client.
// Trace: PRD-004 REQ-CGM-002 CGM-006

import Testing
import Foundation
@testable import CGMKit

@Suite("LibreLinkUp Client Tests")
struct LibreLinkUpClientTests {
    
    // MARK: - Region Tests
    
    @Test("All regions have valid base URLs")
    func regionsHaveValidURLs() {
        let regions: [LibreLinkUpRegion] = [.us, .eu, .de, .fr, .jp, .ap, .au]
        
        for region in regions {
            #expect(region.baseURL.absoluteString.contains("libreview.io"))
            #expect(region.baseURL.absoluteString.hasPrefix("https://"))
        }
    }
    
    @Test("US region has correct URL")
    func usRegionURL() {
        #expect(LibreLinkUpRegion.us.baseURL.absoluteString == "https://api-us.libreview.io/llu")
    }
    
    @Test("EU region has correct URL")
    func euRegionURL() {
        #expect(LibreLinkUpRegion.eu.baseURL.absoluteString == "https://api-eu.libreview.io/llu")
    }
    
    // MARK: - Credentials Tests
    
    @Test("Credentials store values correctly")
    func credentialsStoreValues() {
        let creds = LibreLinkUpCredentials(
            email: "test@example.com",
            password: "secret123",
            region: .eu
        )
        
        #expect(creds.email == "test@example.com")
        #expect(creds.password == "secret123")
        #expect(creds.region == .eu)
    }
    
    @Test("Credentials default to US region")
    func credentialsDefaultRegion() {
        let creds = LibreLinkUpCredentials(
            email: "test@example.com",
            password: "secret"
        )
        
        #expect(creds.region == .us)
    }
    
    // MARK: - LibreLinkUpGlucose Tests
    
    @Test("LibreLinkUpGlucose converts to GlucoseReading")
    func glucoseConvertsToReading() {
        let glucose = LibreLinkUpGlucose(
            value: 120.0,
            timestamp: Date(),
            trend: .flat
        )
        
        let reading = glucose.toGlucoseReading()
        
        #expect(reading.glucose == 120.0)
        #expect(reading.trend == .flat)
        #expect(reading.source == "LibreLinkUp")
    }
    
    // MARK: - LibreLinkUpConnection Tests
    
    @Test("Connection display name combines first and last")
    func connectionDisplayName() {
        let conn = LibreLinkUpConnection(
            patientId: "123",
            firstName: "John",
            lastName: "Doe",
            latestGlucose: nil
        )
        
        #expect(conn.displayName == "John Doe")
    }
    
    @Test("Connection display name handles nil values")
    func connectionDisplayNameNil() {
        let conn1 = LibreLinkUpConnection(
            patientId: "123",
            firstName: "John",
            lastName: nil,
            latestGlucose: nil
        )
        #expect(conn1.displayName == "John")
        
        let conn2 = LibreLinkUpConnection(
            patientId: "123",
            firstName: nil,
            lastName: nil,
            latestGlucose: nil
        )
        #expect(conn2.displayName == "")
    }
    
    // MARK: - Error Tests
    
    @Test("LibreLinkUpError is Error type")
    func errorsAreErrorType() {
        let errors: [LibreLinkUpError] = [
            .authenticationFailed,
            .invalidCredentials,
            .accountLocked,
            .termsNotAccepted,
            .regionRedirect("eu"),
            .sessionExpired,
            .noConnections,
            .networkError("test"),
            .parseError,
            .notImplemented
        ]
        
        for error in errors {
            #expect(error is Error)
        }
    }
    
    // MARK: - Client Initialization Tests
    
    @Test("Client initializes with credentials")
    func clientInitializes() async {
        let creds = LibreLinkUpCredentials(
            email: "test@example.com",
            password: "secret"
        )
        
        let client = LibreLinkUpClient(credentials: creds)
        // Just verify it initializes without error
        #expect(client != nil)
    }
    
    // MARK: - CGM Manager Tests
    
    @Test("LibreLinkUpCGM has correct display name")
    func cgmDisplayName() async {
        let creds = LibreLinkUpCredentials(email: "test@test.com", password: "test")
        let cgm = LibreLinkUpCGM(credentials: creds)
        
        let name = await cgm.displayName
        #expect(name == "LibreLink Up")
    }
    
    @Test("LibreLinkUpCGM has correct CGM type")
    func cgmType() async {
        let creds = LibreLinkUpCredentials(email: "test@test.com", password: "test")
        let cgm = LibreLinkUpCGM(credentials: creds)
        
        let type = await cgm.cgmType
        #expect(type == .libre2)
    }
    
    @Test("LibreLinkUpCGM sensor state is notStarted initially")
    func cgmSensorStateInitial() async {
        let creds = LibreLinkUpCredentials(email: "test@test.com", password: "test")
        let cgm = LibreLinkUpCGM(credentials: creds)
        
        let state = await cgm.sensorState
        #expect(state == .notStarted)
    }
    
    @Test("LibreLinkUpCGM latest reading is nil initially")
    func cgmLatestReadingNil() async {
        let creds = LibreLinkUpCredentials(email: "test@test.com", password: "test")
        let cgm = LibreLinkUpCGM(credentials: creds)
        
        let reading = await cgm.latestReading
        #expect(reading == nil)
    }
    
    @Test("LibreLinkUpCGM disconnect sets state to stopped")
    func cgmDisconnectSetsState() async {
        let creds = LibreLinkUpCredentials(email: "test@test.com", password: "test")
        let cgm = LibreLinkUpCGM(credentials: creds)
        
        await cgm.disconnect()
        
        let state = await cgm.sensorState
        #expect(state == .stopped)
    }
    
    // MARK: - Credentials Codable Tests
    
    @Test("Credentials can be encoded and decoded")
    func credentialsCodable() throws {
        let creds = LibreLinkUpCredentials(
            email: "test@example.com",
            password: "secret123",
            region: .de
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(creds)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LibreLinkUpCredentials.self, from: data)
        
        #expect(decoded.email == creds.email)
        #expect(decoded.password == creds.password)
        #expect(decoded.region == creds.region)
    }
}
