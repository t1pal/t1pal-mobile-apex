// SPDX-License-Identifier: MIT
//
// SessionManagerTests.swift
// T1PalCore Tests
//
// Tests for multi-device session management
// Backlog: ID-SESS-001

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import T1PalCore

// MARK: - Device Session Tests

@Suite("Device Session")
struct DeviceSessionTests {
    
    @Test("Create session with defaults")
    func testCreateWithDefaults() {
        let session = DeviceSession(
            deviceId: "device-123",
            deviceName: "My iPhone"
        )
        
        #expect(!session.id.isEmpty)
        #expect(session.deviceId == "device-123")
        #expect(session.deviceName == "My iPhone")
        #expect(session.deviceType == .unknown)
        #expect(session.isCurrent == false)
    }
    
    @Test("Session is expired")
    func testIsExpired() {
        let expiredSession = DeviceSession(
            deviceId: "device-123",
            deviceName: "Expired",
            expiresAt: Date().addingTimeInterval(-3600) // 1 hour ago
        )
        
        let validSession = DeviceSession(
            deviceId: "device-456",
            deviceName: "Valid",
            expiresAt: Date().addingTimeInterval(3600) // 1 hour from now
        )
        
        let noExpirySession = DeviceSession(
            deviceId: "device-789",
            deviceName: "No Expiry"
        )
        
        #expect(expiredSession.isExpired == true)
        #expect(validSession.isExpired == false)
        #expect(noExpirySession.isExpired == false)
    }
    
    @Test("Time remaining calculation")
    func testTimeRemaining() {
        let futureExpiry = Date().addingTimeInterval(3600)
        let session = DeviceSession(
            deviceId: "device-123",
            deviceName: "Test",
            expiresAt: futureExpiry
        )
        
        let remaining = session.timeRemaining
        #expect(remaining != nil)
        #expect(remaining! > 3500) // Should be close to 3600
        #expect(remaining! <= 3600)
    }
    
    @Test("Session equality")
    func testEquality() {
        let now = Date()
        let session1 = DeviceSession(
            id: "session-1",
            deviceId: "device-123",
            deviceName: "My iPhone",
            createdAt: now,
            lastActiveAt: now
        )
        
        let session2 = DeviceSession(
            id: "session-1",
            deviceId: "device-123",
            deviceName: "My iPhone",
            createdAt: now,
            lastActiveAt: now
        )
        
        #expect(session1 == session2)
    }
    
    @Test("Session is Codable")
    func testCodable() throws {
        let original = DeviceSession(
            id: "session-123",
            deviceId: "device-456",
            deviceName: "Test Device",
            deviceType: .iPhone,
            isCurrent: true,
            token: "token-abc"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DeviceSession.self, from: data)
        
        #expect(decoded.id == original.id)
        #expect(decoded.deviceId == original.deviceId)
        #expect(decoded.deviceType == original.deviceType)
        #expect(decoded.token == original.token)
    }
}

// MARK: - Device Type Tests

@Suite("Device Type")
struct DeviceTypeTests {
    
    @Test("All device types exist")
    func testAllCases() {
        let types = DeviceType.allCases
        #expect(types.count == 6)
        #expect(types.contains(.iPhone))
        #expect(types.contains(.iPad))
        #expect(types.contains(.watch))
        #expect(types.contains(.mac))
        #expect(types.contains(.web))
        #expect(types.contains(.unknown))
    }
    
    @Test("Display names")
    func testDisplayNames() {
        #expect(DeviceType.iPhone.displayName == "iPhone")
        #expect(DeviceType.iPad.displayName == "iPad")
        #expect(DeviceType.watch.displayName == "Apple Watch")
        #expect(DeviceType.mac.displayName == "Mac")
        #expect(DeviceType.web.displayName == "Web Browser")
    }
    
    @Test("Symbol names")
    func testSymbolNames() {
        #expect(DeviceType.iPhone.symbolName == "iphone")
        #expect(DeviceType.iPad.symbolName == "ipad")
        #expect(DeviceType.watch.symbolName == "applewatch")
    }
    
    @Test("Raw values for API")
    func testRawValues() {
        #expect(DeviceType.iPhone.rawValue == "iphone")
        #expect(DeviceType.iPad.rawValue == "ipad")
        #expect(DeviceType.watch.rawValue == "watch")
    }
}

// MARK: - Mock Session Manager Tests

@Suite("Mock Session Manager")
struct MockSessionManagerTests {
    
    @Test("Register device creates session")
    func testRegisterDevice() async throws {
        let manager = MockSessionManager()
        
        let session = try await manager.registerDevice(
            name: "Test iPhone",
            type: .iPhone
        )
        
        #expect(session.deviceName == "Test iPhone")
        #expect(session.deviceType == .iPhone)
        #expect(session.isCurrent == true)
        #expect(session.token != nil)
        #expect(session.refreshToken != nil)
    }
    
    @Test("List sessions returns all sessions")
    func testListSessions() async throws {
        let manager = MockSessionManager()
        
        // Register current device
        let current = try await manager.registerDevice(name: "Current", type: .iPhone)
        
        // Add other sessions
        let other1 = DeviceSession(
            deviceId: "other-1",
            deviceName: "iPad",
            deviceType: .iPad
        )
        let other2 = DeviceSession(
            deviceId: "other-2",
            deviceName: "Mac",
            deviceType: .mac
        )
        
        await manager.addSession(other1)
        await manager.addSession(other2)
        
        let sessions = try await manager.listSessions()
        #expect(sessions.count == 3)
        
        let callCount = await manager.listSessionsCallCount
        #expect(callCount == 1)
    }
    
    @Test("Get current session")
    func testGetCurrentSession() async throws {
        let manager = MockSessionManager()
        
        // Initially no session
        let initial = await manager.getCurrentSession()
        #expect(initial == nil)
        
        // Register creates current session
        _ = try await manager.registerDevice(name: "Test", type: .iPhone)
        
        let current = await manager.getCurrentSession()
        #expect(current != nil)
        #expect(current?.isCurrent == true)
    }
    
    @Test("Revoke session removes it")
    func testRevokeSession() async throws {
        let manager = MockSessionManager()
        
        // Set up current session
        _ = try await manager.registerDevice(name: "Current", type: .iPhone)
        
        // Add another session
        let other = DeviceSession(
            id: "other-session",
            deviceId: "other-device",
            deviceName: "Other iPad",
            deviceType: .iPad
        )
        await manager.addSession(other)
        
        // Verify we have 2 sessions
        var sessions = try await manager.listSessions()
        #expect(sessions.count == 2)
        
        // Revoke the other session
        try await manager.revokeSession(id: "other-session")
        
        // Now only 1 session
        sessions = try await manager.listSessions()
        #expect(sessions.count == 1)
        
        let revokeCount = await manager.revokeCallCount
        #expect(revokeCount == 1)
    }
    
    @Test("Cannot revoke current session")
    func testCannotRevokeCurrent() async throws {
        let manager = MockSessionManager()
        
        let current = try await manager.registerDevice(name: "Current", type: .iPhone)
        
        await #expect(throws: SessionError.self) {
            try await manager.revokeSession(id: current.id)
        }
    }
    
    @Test("Revoke session not found throws")
    func testRevokeNotFound() async throws {
        let manager = MockSessionManager()
        
        await #expect(throws: SessionError.self) {
            try await manager.revokeSession(id: "nonexistent")
        }
    }
    
    @Test("Revoke all other sessions")
    func testRevokeAllOther() async throws {
        let manager = MockSessionManager()
        
        // Register current
        _ = try await manager.registerDevice(name: "Current", type: .iPhone)
        
        // Add others
        for i in 1...3 {
            let session = DeviceSession(
                id: "other-\(i)",
                deviceId: "device-\(i)",
                deviceName: "Device \(i)",
                deviceType: .iPad
            )
            await manager.addSession(session)
        }
        
        // Verify 4 sessions
        var sessions = try await manager.listSessions()
        #expect(sessions.count == 4)
        
        // Revoke all others
        let revoked = try await manager.revokeAllOtherSessions()
        #expect(revoked == 3)
        
        // Only current remains
        sessions = try await manager.listSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.isCurrent == true)
    }
    
    @Test("Touch session updates timestamp")
    func testTouchSession() async throws {
        let manager = MockSessionManager()
        
        let original = try await manager.registerDevice(name: "Test", type: .iPhone)
        let originalTime = original.lastActiveAt
        
        // Wait a tiny bit
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        
        // Touch the session
        try await manager.touchSession()
        
        let updated = await manager.getCurrentSession()
        #expect(updated != nil)
        #expect(updated!.lastActiveAt > originalTime)
    }
    
    @Test("Touch requires authentication")
    func testTouchRequiresAuth() async throws {
        let manager = MockSessionManager()
        
        // No session registered
        await #expect(throws: SessionError.self) {
            try await manager.touchSession()
        }
    }
    
    @Test("Rename device updates name")
    func testRenameDevice() async throws {
        let manager = MockSessionManager()
        
        let original = try await manager.registerDevice(name: "Original Name", type: .iPhone)
        
        let renamed = try await manager.renameDevice(
            sessionId: original.id,
            newName: "New Name"
        )
        
        #expect(renamed.deviceName == "New Name")
        #expect(renamed.id == original.id)
        
        // Current session is also updated
        let current = await manager.getCurrentSession()
        #expect(current?.deviceName == "New Name")
    }
    
    @Test("Rename nonexistent session throws")
    func testRenameNotFound() async throws {
        let manager = MockSessionManager()
        
        await #expect(throws: SessionError.self) {
            try await manager.renameDevice(sessionId: "nonexistent", newName: "New")
        }
    }
}

// MARK: - Session Error Tests

@Suite("Session Errors")
struct SessionErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let errors: [SessionError] = [
            .notAuthenticated,
            .sessionExpired,
            .sessionNotFound,
            .deviceNotRegistered,
            .serverError(500),
            .invalidResponse,
            .revokeNotAllowed("test")
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    @Test("Network error wraps underlying")
    func testNetworkError() {
        let underlying = URLError(.notConnectedToInternet)
        let error = SessionError.networkError(underlying)
        #expect(error.errorDescription?.contains("Network") == true)
    }
}

// MARK: - Device Identifier Tests

@Suite("Device Identifier")
struct DeviceIdentifierTests {
    
    @Test("Get device ID returns non-empty string")
    func testGetDeviceId() {
        let deviceId = DeviceIdentifier.getDeviceId()
        #expect(!deviceId.isEmpty)
    }
    
    @Test("Get device name returns non-empty string")
    func testGetDeviceName() {
        let name = DeviceIdentifier.getDeviceName()
        #expect(!name.isEmpty)
    }
    
    @Test("Get device type returns valid type")
    func testGetDeviceType() {
        let type = DeviceIdentifier.getDeviceType()
        #expect(DeviceType.allCases.contains(type))
    }
}

// MARK: - Live Session Manager Tests

@Suite("Live Session Manager")
struct LiveSessionManagerTests {
    
    @Test("Manager requires configuration")
    func testRequiresConfiguration() async throws {
        let manager = LiveSessionManager()
        
        // Without configuration, should throw not authenticated
        await #expect(throws: SessionError.self) {
            try await manager.listSessions()
        }
    }
    
    @Test("Get current session before auth returns nil")
    func testGetCurrentBeforeAuth() async {
        let manager = LiveSessionManager()
        
        let session = await manager.getCurrentSession()
        #expect(session == nil)
    }
}
