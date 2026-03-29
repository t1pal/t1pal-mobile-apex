// SPDX-License-Identifier: MIT
//
// JWTTokenTests.swift
// T1Pal Mobile
//
// Tests for JWT token decoding and management
// Requirements: REQ-AUTH-002

import Foundation
import Testing
@testable import NightscoutKit

/// Thread-safe counter for async tests
private actor RefreshCounter {
    var count = 0
    func increment() { count += 1 }
}

/// Create a test JWT token with given claims
private func makeTestToken(
    iat: Int = Int(Date().timeIntervalSince1970),
    exp: Int = Int(Date().timeIntervalSince1970) + 3600,
    sub: String = "api:read"
) -> String {
    let header = base64URLEncode(#"{"alg":"HS256","typ":"JWT"}"#)
    let payload = base64URLEncode(#"{"iat":\#(iat),"exp":\#(exp),"sub":"\#(sub)"}"#)
    let signature = "test_signature_abc123"
    return "\(header).\(payload).\(signature)"
}

/// Create an expired test token
private func makeExpiredToken() -> String {
    let past = Int(Date().timeIntervalSince1970) - 3600
    return makeTestToken(iat: past - 3600, exp: past)
}

/// Create a token expiring soon (within refresh margin)
private func makeExpiringToken(secondsUntilExpiry: Int = 60) -> String {
    let now = Int(Date().timeIntervalSince1970)
    return makeTestToken(iat: now - 3600, exp: now + secondsUntilExpiry)
}

private func base64URLEncode(_ string: String) -> String {
    let data = Data(string.utf8)
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
    
@Suite("JWTDecoder")
struct JWTDecoderTests {
    
    @Test("decodes valid token")
    func decodeValidToken() throws {
        let token = makeTestToken(sub: "api:read,api:write")
        
        let claims = try JWTDecoder.decode(token)
        
        #expect(claims.iat != nil)
        #expect(claims.exp != nil)
        #expect(claims.sub == "api:read,api:write")
        #expect(!claims.isExpired)
    }
    
    @Test("decodes expired token")
    func decodeExpiredToken() throws {
        let token = makeExpiredToken()
        
        let claims = try JWTDecoder.decode(token)
        
        #expect(claims.isExpired)
    }
    
    @Test("rejects invalid format")
    func decodeInvalidFormat() {
        #expect(throws: JWTDecoder.JWTError.self) {
            try JWTDecoder.decode("single_part")
        }
        
        #expect(throws: JWTDecoder.JWTError.self) {
            try JWTDecoder.decode("")
        }
    }
    
    @Test("rejects invalid base64")
    func decodeInvalidBase64() {
        let token = "header.!!!invalid!!!.signature"
        
        #expect(throws: JWTDecoder.JWTError.self) {
            try JWTDecoder.decode(token)
        }
    }
    
    @Test("claims expiresAt property")
    func claimsExpiresAt() throws {
        let futureTime = Int(Date().timeIntervalSince1970) + 7200
        let token = makeTestToken(exp: futureTime)
        
        let claims = try JWTDecoder.decode(token)
        
        #expect(claims.expiresAt != nil)
        let expectedDate = Date(timeIntervalSince1970: Double(futureTime))
        let diff = abs((claims.expiresAt?.timeIntervalSince1970 ?? 0) - expectedDate.timeIntervalSince1970)
        #expect(diff < 1.0)
    }
}
    
@Suite("JWTTokenManager")
struct JWTTokenManagerTests {
    
    @Test("set and get token")
    func setAndGetToken() async throws {
        let manager = JWTTokenManager()
        let token = makeTestToken()
        
        try await manager.setToken(token)
        
        let validToken = await manager.getValidToken()
        #expect(validToken == token)
    }
    
    @Test("get valid token when expired returns nil")
    func getValidTokenWhenExpired() async throws {
        let manager = JWTTokenManager()
        let expiredToken = makeExpiredToken()
        
        try await manager.setToken(expiredToken)
        
        let validToken = await manager.getValidToken()
        #expect(validToken == nil)
    }
    
    @Test("isExpired returns correct state")
    func isExpired() async throws {
        let manager = JWTTokenManager()
        
        // No token
        let noTokenExpired = await manager.isExpired()
        #expect(noTokenExpired)
        
        // Valid token
        try await manager.setToken(makeTestToken())
        let validNotExpired = await manager.isExpired()
        #expect(!validNotExpired)
        
        // Expired token
        try await manager.setToken(makeExpiredToken())
        let expiredIsExpired = await manager.isExpired()
        #expect(expiredIsExpired)
    }
    
    @Test("needsRefresh detects expiring tokens")
    func needsRefresh() async throws {
        // Manager with 5 minute refresh margin
        let manager = JWTTokenManager(refreshMargin: 300)
        
        // Token expiring in 1 hour - no refresh needed
        try await manager.setToken(makeTestToken(exp: Int(Date().timeIntervalSince1970) + 3600))
        let needsRefresh1 = await manager.needsRefresh()
        #expect(!needsRefresh1)
        
        // Token expiring in 2 minutes - needs refresh
        try await manager.setToken(makeExpiringToken(secondsUntilExpiry: 120))
        let needsRefresh2 = await manager.needsRefresh()
        #expect(needsRefresh2)
    }
    
    @Test("auto refresh on getValidToken")
    func autoRefreshOnGetValidToken() async throws {
        let refreshCounter = RefreshCounter()
        let newToken = makeTestToken(exp: Int(Date().timeIntervalSince1970) + 7200)
        
        let manager = JWTTokenManager(
            token: makeExpiringToken(secondsUntilExpiry: 60),
            refreshMargin: 300
        ) {
            await refreshCounter.increment()
            return newToken
        }
        
        // Should trigger refresh since token expires in 60s (within 300s margin)
        let validToken = await manager.getValidToken()
        
        let count = await refreshCounter.count
        #expect(count == 1)
        #expect(validToken == newToken)
    }
    
    @Test("refresh backoff on failure")
    func refreshBackoff() async throws {
        let refreshCounter = RefreshCounter()
        
        let manager = JWTTokenManager(
            token: makeExpiringToken(secondsUntilExpiry: 60),
            refreshMargin: 300
        ) {
            await refreshCounter.increment()
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }
        
        // First call triggers refresh (fails)
        _ = await manager.getValidToken()
        var count = await refreshCounter.count
        #expect(count == 1)
        
        // Second call within 30s backoff should not refresh again
        _ = await manager.getValidToken()
        count = await refreshCounter.count
        #expect(count == 1)
    }
    
    @Test("clear removes token and claims")
    func clear() async throws {
        let manager = JWTTokenManager()
        try await manager.setToken(makeTestToken())
        
        await manager.clear()
        
        let token = await manager.getValidToken()
        let claims = await manager.getClaims()
        
        #expect(token == nil)
        #expect(claims == nil)
    }
    
    @Test("getClaims returns decoded claims")
    func getClaims() async throws {
        let manager = JWTTokenManager()
        let token = makeTestToken(sub: "admin")
        
        try await manager.setToken(token)
        let claims = await manager.getClaims()
        
        #expect(claims != nil)
        #expect(claims?.sub == "admin")
    }
    
    @Test("expiresAt returns expiration date")
    func expiresAt() async throws {
        let manager = JWTTokenManager()
        let futureExp = Int(Date().timeIntervalSince1970) + 7200
        let token = makeTestToken(exp: futureExp)
        
        try await manager.setToken(token)
        let expiresAt = await manager.expiresAt()
        
        #expect(expiresAt != nil)
        let diff = abs((expiresAt?.timeIntervalSince1970 ?? 0) - Double(futureExp))
        #expect(diff < 1.0)
    }
}
