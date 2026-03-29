// T1PalCoreTests.swift
// Tests for T1PalCore types

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Core Type Tests

@Suite("Core Types")
struct CoreTypeTests {
    
    @Test("Glucose reading conversion")
    func glucoseReadingConversion() {
        let reading = GlucoseReading(glucose: 180, timestamp: Date())
        #expect(abs(reading.glucoseMmol - (180 / 18.0182)) < 0.01)
    }
    
    @Test("Glucose trend arrow")
    func glucoseTrendArrow() {
        #expect(GlucoseTrend.flat.arrow == "→")
        #expect(GlucoseTrend.singleUp.arrow == "↑")
        #expect(GlucoseTrend.doubleDown.arrow == "↓↓")
    }
    
    @Test("Glucose trend is displayable")
    func glucoseTrendIsDisplayable() {
        #expect(GlucoseTrend.flat.isDisplayable)
        #expect(GlucoseTrend.singleUp.isDisplayable)
        #expect(GlucoseTrend.doubleDown.isDisplayable)
        #expect(!GlucoseTrend.notComputable.isDisplayable)
        #expect(!GlucoseTrend.rateOutOfRange.isDisplayable)
    }
    
    @Test("Glucose trend from rate")
    func glucoseTrendFromRate() {
        #expect(GlucoseTrend.fromRate(4.0) == .doubleUp)
        #expect(GlucoseTrend.fromRate(3.5) == .doubleUp)
        #expect(GlucoseTrend.fromRate(2.5) == .singleUp)
        #expect(GlucoseTrend.fromRate(2.0) == .singleUp)
        #expect(GlucoseTrend.fromRate(1.5) == .fortyFiveUp)
        #expect(GlucoseTrend.fromRate(1.0) == .fortyFiveUp)
        #expect(GlucoseTrend.fromRate(0.0) == .flat)
        #expect(GlucoseTrend.fromRate(0.5) == .flat)
        #expect(GlucoseTrend.fromRate(-0.5) == .flat)
        #expect(GlucoseTrend.fromRate(-1.5) == .fortyFiveDown)
        #expect(GlucoseTrend.fromRate(-2.5) == .singleDown)
        #expect(GlucoseTrend.fromRate(-4.0) == .doubleDown)
    }
    
    @Test("Glucose trend arrow with fallback")
    func glucoseTrendArrowWithFallback() {
        #expect(GlucoseTrend.flat.arrowWithFallback(rate: 2.0) == "→")
        #expect(GlucoseTrend.singleUp.arrowWithFallback(rate: nil) == "↑")
        #expect(GlucoseTrend.notComputable.arrowWithFallback(rate: 2.5) == "↑")
        #expect(GlucoseTrend.notComputable.arrowWithFallback(rate: -2.5) == "↓")
        #expect(GlucoseTrend.notComputable.arrowWithFallback(rate: 0.0) == "→")
        #expect(GlucoseTrend.notComputable.arrowWithFallback(rate: nil) == "")
        #expect(GlucoseTrend.rateOutOfRange.arrowWithFallback(rate: nil) == "")
    }
    
    @Test("Therapy profile defaults")
    func therapyProfileDefaults() {
        let profile = TherapyProfile()
        #expect(profile.basalRates.isEmpty)
        #expect(profile.targetGlucose.midpoint == 105)
    }
    
    @Test("Therapy profile current carb ratio")
    func currentCarbRatio() {
        // Profile with multiple carb ratio periods
        let profile = TherapyProfile(
            carbRatios: [
                CarbRatio(startTime: 0, ratio: 12),         // Midnight: 1:12
                CarbRatio(startTime: 21600, ratio: 10),     // 6am: 1:10 (breakfast)
                CarbRatio(startTime: 43200, ratio: 15),     // Noon: 1:15 (lunch)
                CarbRatio(startTime: 64800, ratio: 12)      // 6pm: 1:12 (dinner)
            ]
        )
        
        // Test at specific times
        let midnight = Calendar.current.startOfDay(for: Date())
        let _3am = midnight.addingTimeInterval(10800)    // 3:00 AM
        let _8am = midnight.addingTimeInterval(28800)    // 8:00 AM
        let _2pm = midnight.addingTimeInterval(50400)    // 2:00 PM
        let _9pm = midnight.addingTimeInterval(75600)    // 9:00 PM
        
        #expect(profile.carbRatioAt(_3am) == 12)   // Still in midnight period
        #expect(profile.carbRatioAt(_8am) == 10)   // Breakfast period
        #expect(profile.carbRatioAt(_2pm) == 15)   // Lunch period
        #expect(profile.carbRatioAt(_9pm) == 12)   // Dinner period
    }
    
    @Test("Therapy profile current ISF")
    func currentISF() {
        // Profile with multiple ISF periods
        let profile = TherapyProfile(
            sensitivityFactors: [
                SensitivityFactor(startTime: 0, factor: 50),      // Midnight
                SensitivityFactor(startTime: 21600, factor: 40),  // 6am (dawn phenomenon)
                SensitivityFactor(startTime: 43200, factor: 55)   // Noon
            ]
        )
        
        let midnight = Calendar.current.startOfDay(for: Date())
        let _3am = midnight.addingTimeInterval(10800)
        let _10am = midnight.addingTimeInterval(36000)
        let _4pm = midnight.addingTimeInterval(57600)
        
        #expect(profile.isfAt(_3am) == 50)
        #expect(profile.isfAt(_10am) == 40)
        #expect(profile.isfAt(_4pm) == 55)
    }
}

// MARK: - Identity Provider Tests (ID-001)

@Suite("Identity Provider")
struct IdentityProviderTests {
    
    @Test("Identity provider type all cases")
    func identityProviderTypeAllCases() {
        #expect(IdentityProviderType.allCases.count == 4)
        #expect(IdentityProviderType.allCases.contains(.nightscout))
        #expect(IdentityProviderType.allCases.contains(.tidepool))
        #expect(IdentityProviderType.allCases.contains(.t1pal))
        #expect(IdentityProviderType.allCases.contains(.custom))
    }
    
    @Test("Auth method raw values")
    func authMethodRawValues() {
        #expect(AuthMethod.apiSecret.rawValue == "api_secret")
        #expect(AuthMethod.bearerToken.rawValue == "bearer_token")
        #expect(AuthMethod.oauth2.rawValue == "oauth2")
        #expect(AuthMethod.oidc.rawValue == "oidc")
        #expect(AuthMethod.none.rawValue == "none")
    }
    
    @Test("Token type raw values")
    func tokenTypeRawValues() {
        #expect(TokenType.access.rawValue == "access")
        #expect(TokenType.refresh.rawValue == "refresh")
        #expect(TokenType.apiSecret.rawValue == "api_secret")
        #expect(TokenType.idToken.rawValue == "id_token")
    }
    
    @Test("Auth credential init")
    func authCredentialInit() {
        let credential = AuthCredential(
            tokenType: .access,
            value: "test_token",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "openid profile"
        )
        
        #expect(credential.tokenType == .access)
        #expect(credential.value == "test_token")
        #expect(credential.scope == "openid profile")
        #expect(!credential.isExpired)
    }
    
    @Test("Auth credential expired")
    func authCredentialExpired() {
        let expiredCredential = AuthCredential(
            tokenType: .access,
            value: "expired_token",
            expiresAt: Date().addingTimeInterval(-60)
        )
        #expect(expiredCredential.isExpired)
    }
    
    @Test("Auth credential will expire")
    func authCredentialWillExpire() {
        let credential = AuthCredential(
            tokenType: .access,
            value: "expiring_token",
            expiresAt: Date().addingTimeInterval(300)
        )
        #expect(credential.willExpire(within: 600))
        #expect(!credential.willExpire(within: 60))
    }
    
    @Test("Auth credential no expiry")
    func authCredentialNoExpiry() {
        let credential = AuthCredential(
            tokenType: .apiSecret,
            value: "permanent_secret"
        )
        #expect(credential.expiresAt == nil)
        #expect(!credential.isExpired)
        #expect(!credential.willExpire(within: 86400))
    }
    
    @Test("Auth credential encoding")
    func authCredentialEncoding() throws {
        let credential = AuthCredential(
            tokenType: .access,
            value: "test_token",
            expiresAt: Date(timeIntervalSince1970: 1700000000),
            scope: "read write"
        )
        
        let encoded = try JSONEncoder().encode(credential)
        let decoded = try JSONDecoder().decode(AuthCredential.self, from: encoded)
        
        #expect(decoded.tokenType == .access)
        #expect(decoded.value == "test_token")
        #expect(decoded.scope == "read write")
    }
    
    @Test("OAuth2 config init")
    func oauth2ConfigInit() {
        let config = OAuth2Config(
            authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
            tokenEndpoint: URL(string: "https://auth.example.com/token")!,
            clientId: "test_client",
            redirectUri: URL(string: "t1pal://callback")!,
            scope: "openid profile email"
        )
        
        #expect(config.clientId == "test_client")
        #expect(config.scope == "openid profile email")
        #expect(config.responseType == "code")
    }
    
    @Test("OAuth2 config encoding")
    func oauth2ConfigEncoding() throws {
        let config = OAuth2Config(
            authorizationEndpoint: URL(string: "https://auth.example.com/authorize")!,
            tokenEndpoint: URL(string: "https://auth.example.com/token")!,
            clientId: "test_client",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(OAuth2Config.self, from: encoded)
        
        #expect(decoded.clientId == "test_client")
    }
    
    @Test("Token response init")
    func tokenResponseInit() {
        let response = TokenResponse(
            accessToken: "access_123",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "refresh_456",
            scope: "openid",
            idToken: "id_789"
        )
        
        #expect(response.accessToken == "access_123")
        #expect(response.tokenType == "Bearer")
        #expect(response.expiresIn == 3600)
        #expect(response.refreshToken == "refresh_456")
    }
    
    @Test("Token response decoding")
    func tokenResponseDecoding() throws {
        let json = """
        {
            "access_token": "abc123",
            "token_type": "Bearer",
            "expires_in": 7200,
            "refresh_token": "xyz789",
            "scope": "openid profile"
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(TokenResponse.self, from: json)
        
        #expect(response.accessToken == "abc123")
        #expect(response.tokenType == "Bearer")
        #expect(response.expiresIn == 7200)
        #expect(response.refreshToken == "xyz789")
        #expect(response.scope == "openid profile")
    }
    
    @Test("Token response to credential")
    func tokenResponseToCredential() {
        let response = TokenResponse(
            accessToken: "access_token",
            expiresIn: 3600,
            scope: "openid"
        )
        
        let credential = response.toCredential()
        
        #expect(credential.tokenType == .access)
        #expect(credential.value == "access_token")
        #expect(credential.scope == "openid")
        #expect(credential.expiresAt != nil)
    }
    
    @Test("User identity init")
    func userIdentityInit() {
        let identity = UserIdentity(
            id: "user123",
            provider: .tidepool,
            displayName: "Test User",
            email: "test@example.com"
        )
        
        #expect(identity.id == "user123")
        #expect(identity.provider == .tidepool)
        #expect(identity.displayName == "Test User")
        #expect(identity.email == "test@example.com")
    }
    
    @Test("User identity encoding")
    func userIdentityEncoding() throws {
        let identity = UserIdentity(
            id: "user456",
            provider: .nightscout,
            displayName: "NS User"
        )
        
        let encoded = try JSONEncoder().encode(identity)
        let decoded = try JSONDecoder().decode(UserIdentity.self, from: encoded)
        
        #expect(decoded.id == "user456")
        #expect(decoded.provider == .nightscout)
    }
    
    @Test("Nightscout instance init")
    func nightscoutInstanceInit() {
        let instance = NightscoutInstance(
            url: URL(string: "https://my.nightscout.io")!,
            name: "My Nightscout",
            authMethod: .apiSecret,
            isDefault: true
        )
        
        #expect(instance.name == "My Nightscout")
        #expect(instance.authMethod == .apiSecret)
        #expect(instance.isDefault)
    }
    
    @Test("Nightscout instance hash equality")
    func nightscoutInstanceHashEquality() {
        let instance1 = NightscoutInstance(
            url: URL(string: "https://my.nightscout.io")!,
            name: "Instance 1"
        )
        
        let instance2 = NightscoutInstance(
            url: URL(string: "https://my.nightscout.io")!,
            name: "Instance 2"
        )
        
        let instance3 = NightscoutInstance(
            url: URL(string: "https://other.nightscout.io")!,
            name: "Instance 1"
        )
        
        #expect(instance1 == instance2)
        #expect(instance1 != instance3)
    }
    
    @Test("Nightscout instance encoding")
    func nightscoutInstanceEncoding() throws {
        let instance = NightscoutInstance(
            url: URL(string: "https://my.nightscout.io")!,
            name: "Test",
            authMethod: .bearerToken
        )
        
        let encoded = try JSONEncoder().encode(instance)
        let decoded = try JSONDecoder().decode(NightscoutInstance.self, from: encoded)
        
        #expect(decoded.name == "Test")
        #expect(decoded.authMethod == .bearerToken)
    }
}

// MARK: - Credential Storage Tests (ID-002)

@Suite("Credential Key")
struct CredentialKeyTests {
    
    @Test("Credential key creation")
    func credentialKeyCreation() {
        let key = CredentialKey(service: "com.test", account: "user@test.com")
        
        #expect(key.service == "com.test")
        #expect(key.account == "user@test.com")
        #expect(key.accessGroup == nil)
    }
    
    @Test("Credential key with access group")
    func credentialKeyWithAccessGroup() {
        let key = CredentialKey(service: "com.test", account: "user", accessGroup: "group.com.test")
        #expect(key.accessGroup == "group.com.test")
    }
    
    @Test("Nightscout key factory")
    func nightscoutKeyFactory() {
        let key = CredentialKey.nightscout(url: URL(string: "https://myns.herokuapp.com")!)
        #expect(key.service == "com.t1pal.nightscout")
        #expect(key.account == "myns.herokuapp.com")
    }
    
    @Test("OAuth2 key factory")
    func oauth2KeyFactory() {
        let key = CredentialKey.oauth2(provider: .tidepool, userId: "user123")
        #expect(key.service == "com.t1pal.tidepool")
        #expect(key.account == "user123")
    }
    
    @Test("Credential key hashable")
    func credentialKeyHashable() {
        let key1 = CredentialKey(service: "com.test", account: "user")
        let key2 = CredentialKey(service: "com.test", account: "user")
        
        #expect(key1 == key2)
        #expect(key1.hashValue == key2.hashValue)
    }
}

@Suite("Stored Credential")
struct StoredCredentialTests {
    
    @Test("Stored credential creation")
    func storedCredentialCreation() {
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: nil)
        let key = CredentialKey(service: "test", account: "user")
        let stored = StoredCredential(credential: credential, key: key)
        
        #expect(stored.credential.value == "token")
        #expect(stored.key.service == "test")
        #expect(stored.lastAccessedAt == nil)
    }
    
    @Test("Needs refresh with expired credential")
    func needsRefreshWithExpiredCredential() {
        let expired = Date().addingTimeInterval(-60)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: expired)
        let key = CredentialKey(service: "test", account: "user")
        let stored = StoredCredential(credential: credential, key: key)
        
        #expect(stored.needsRefresh())
    }
    
    @Test("Needs refresh with valid credential")
    func needsRefreshWithValidCredential() {
        let future = Date().addingTimeInterval(3600)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: future)
        let key = CredentialKey(service: "test", account: "user")
        let stored = StoredCredential(credential: credential, key: key)
        
        #expect(!stored.needsRefresh())
    }
    
    @Test("Needs refresh with custom margin")
    func needsRefreshWithCustomMargin() {
        let future = Date().addingTimeInterval(600)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: future)
        let key = CredentialKey(service: "test", account: "user")
        let stored = StoredCredential(credential: credential, key: key)
        
        #expect(!stored.needsRefresh(margin: 300))
        #expect(stored.needsRefresh(margin: 700))
    }
}

@Suite("Credential Key Data")
struct CredentialKeyDataTests {
    
    @Test("Credential key data round trip")
    func credentialKeyDataRoundTrip() {
        let key = CredentialKey(service: "com.test", account: "user", accessGroup: "group")
        let data = CredentialKeyData(from: key)
        let roundTripped = data.toKey()
        
        #expect(roundTripped.service == key.service)
        #expect(roundTripped.account == key.account)
        #expect(roundTripped.accessGroup == key.accessGroup)
    }
}

@Suite("Memory Credential Store")
struct MemoryCredentialStoreTests {
    
    @Test("Store and retrieve")
    func storeAndRetrieve() async throws {
        let store = MemoryCredentialStore()
        let credential = AuthCredential(tokenType: .apiSecret, value: "secret", expiresAt: nil)
        let key = CredentialKey(service: "test", account: "user")
        
        try await store.store(credential, for: key)
        let retrieved = try await store.retrieve(for: key)
        
        #expect(retrieved.value == "secret")
    }
    
    @Test("Retrieve not found")
    func retrieveNotFound() async {
        let store = MemoryCredentialStore()
        let key = CredentialKey(service: "test", account: "unknown")
        
        await #expect(throws: CredentialStoreError.self) {
            _ = try await store.retrieve(for: key)
        }
    }
    
    @Test("Delete")
    func delete() async throws {
        let store = MemoryCredentialStore()
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: nil)
        let key = CredentialKey(service: "test", account: "user")
        
        try await store.store(credential, for: key)
        let existsBefore = await store.exists(for: key)
        #expect(existsBefore)
        
        try await store.delete(for: key)
        let existsAfter = await store.exists(for: key)
        #expect(!existsAfter)
    }
    
    @Test("Delete not found")
    func deleteNotFound() async {
        let store = MemoryCredentialStore()
        let key = CredentialKey(service: "test", account: "unknown")
        
        await #expect(throws: CredentialStoreError.self) {
            try await store.delete(for: key)
        }
    }
    
    @Test("Exists")
    func exists() async throws {
        let store = MemoryCredentialStore()
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: nil)
        let key = CredentialKey(service: "test", account: "user")
        
        let existsBefore = await store.exists(for: key)
        #expect(!existsBefore)
        try await store.store(credential, for: key)
        let existsAfter = await store.exists(for: key)
        #expect(existsAfter)
    }
    
    @Test("All keys for service")
    func allKeysForService() async throws {
        let store = MemoryCredentialStore()
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: nil)
        
        try await store.store(credential, for: CredentialKey(service: "service1", account: "user1"))
        try await store.store(credential, for: CredentialKey(service: "service1", account: "user2"))
        try await store.store(credential, for: CredentialKey(service: "service2", account: "user3"))
        
        let keys = try await store.allKeys(for: "service1")
        #expect(keys.count == 2)
    }
    
    @Test("Clear")
    func clear() async throws {
        let store = MemoryCredentialStore()
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: nil)
        
        try await store.store(credential, for: CredentialKey(service: "test", account: "user1"))
        try await store.store(credential, for: CredentialKey(service: "test", account: "user2"))
        
        await store.clear()
        
        let keys = try await store.allKeys(for: "test")
        #expect(keys.isEmpty)
    }
}

@Suite("Credential Manager")
struct CredentialManagerTests {
    
    @Test("Get and store credential")
    func getAndStoreCredential() async throws {
        let store = MemoryCredentialStore()
        let manager = CredentialManager(store: store)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: nil)
        let key = CredentialKey(service: "test", account: "user")
        
        try await manager.storeCredential(credential, for: key)
        let retrieved = try await manager.getCredential(for: key)
        
        #expect(retrieved.value == "token")
    }
    
    @Test("Store with refresh token")
    func storeWithRefreshToken() async throws {
        let store = MemoryCredentialStore()
        let manager = CredentialManager(store: store)
        let credential = AuthCredential(tokenType: .access, value: "access", expiresAt: nil)
        let key = CredentialKey(service: "test", account: "user")
        
        try await manager.storeCredential(credential, for: key, refreshToken: "refresh123")
        let refreshToken = await manager.getRefreshToken(for: key)
        
        #expect(refreshToken == "refresh123")
    }
    
    @Test("Delete credential")
    func deleteCredential() async throws {
        let store = MemoryCredentialStore()
        let manager = CredentialManager(store: store)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: nil)
        let key = CredentialKey(service: "test", account: "user")
        
        try await manager.storeCredential(credential, for: key, refreshToken: "refresh")
        try await manager.deleteCredential(for: key)
        
        let hasValid = await manager.hasValidCredential(for: key)
        #expect(!hasValid)
        
        let refreshToken = await manager.getRefreshToken(for: key)
        #expect(refreshToken == nil)
    }
    
    @Test("Has valid credential with valid")
    func hasValidCredentialWithValid() async throws {
        let store = MemoryCredentialStore()
        let manager = CredentialManager(store: store)
        let future = Date().addingTimeInterval(3600)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: future)
        let key = CredentialKey(service: "test", account: "user")
        
        try await manager.storeCredential(credential, for: key)
        let hasValid = await manager.hasValidCredential(for: key)
        
        #expect(hasValid)
    }
    
    @Test("Has valid credential with expired")
    func hasValidCredentialWithExpired() async throws {
        let store = MemoryCredentialStore()
        let manager = CredentialManager(store: store)
        let past = Date().addingTimeInterval(-3600)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: past)
        let key = CredentialKey(service: "test", account: "user")
        
        try await manager.storeCredential(credential, for: key)
        let hasValid = await manager.hasValidCredential(for: key)
        
        #expect(!hasValid)
    }
    
    @Test("List credentials")
    func listCredentials() async throws {
        let store = MemoryCredentialStore()
        let manager = CredentialManager(store: store)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: nil)
        
        try await manager.storeCredential(credential, for: CredentialKey(service: "svc", account: "user1"))
        try await manager.storeCredential(credential, for: CredentialKey(service: "svc", account: "user2"))
        
        let keys = try await manager.listCredentials(for: "svc")
        #expect(keys.count == 2)
    }
}

@Suite("Credential Expiry Monitor")
struct CredentialExpiryMonitorTests {
    
    @Test("Check expiry valid")
    func checkExpiryValid() async throws {
        let store = MemoryCredentialStore()
        let monitor = CredentialExpiryMonitor(store: store)
        let future = Date().addingTimeInterval(3600)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: future)
        let key = CredentialKey(service: "test", account: "user")
        
        try await store.store(credential, for: key)
        let status = try await monitor.checkExpiry(for: key)
        
        if case .valid = status {
            // Expected
        } else {
            Issue.record("Expected valid status")
        }
    }
    
    @Test("Check expiry expired")
    func checkExpiryExpired() async throws {
        let store = MemoryCredentialStore()
        let monitor = CredentialExpiryMonitor(store: store)
        let past = Date().addingTimeInterval(-3600)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: past)
        let key = CredentialKey(service: "test", account: "user")
        
        try await store.store(credential, for: key)
        let status = try await monitor.checkExpiry(for: key)
        
        if case .expired = status {
            // Expected
        } else {
            Issue.record("Expected expired status")
        }
    }
    
    @Test("Check expiry expiring soon")
    func checkExpiryExpiringSoon() async throws {
        let store = MemoryCredentialStore()
        let monitor = CredentialExpiryMonitor(store: store, warningThreshold: 600)
        let future = Date().addingTimeInterval(300)
        let credential = AuthCredential(tokenType: .access, value: "token", expiresAt: future)
        let key = CredentialKey(service: "test", account: "user")
        
        try await store.store(credential, for: key)
        let status = try await monitor.checkExpiry(for: key)
        
        if case .expiringSoon(let remaining) = status {
            #expect(remaining < 600)
        } else {
            Issue.record("Expected expiringSoon status")
        }
    }
}

@Suite("Token Refresh Request")
struct TokenRefreshRequestTests {
    
    @Test("Token refresh request creation")
    func tokenRefreshRequestCreation() {
        let config = OAuth2Config(
            authorizationEndpoint: URL(string: "https://auth.test.com/authorize")!,
            tokenEndpoint: URL(string: "https://auth.test.com/token")!,
            clientId: "client123",
            redirectUri: URL(string: "t1pal://callback")!
        )
        let request = TokenRefreshRequest(refreshToken: "refresh_token", config: config)
        
        #expect(request.refreshToken == "refresh_token")
        #expect(request.config.clientId == "client123")
    }
}

// MARK: - Tidepool Identity Tests (ID-004)

@Suite("Tidepool Environment")
struct TidepoolEnvironmentTests {
    
    @Test("Production URLs")
    func productionUrls() {
        let env = TidepoolEnvironment.production
        #expect(env.apiUrl.absoluteString == "https://api.tidepool.org")
        #expect(env.uploadUrl.absoluteString == "https://uploads.tidepool.org")
    }
    
    @Test("QA1 URLs")
    func qa1Urls() {
        let env = TidepoolEnvironment.qa1
        #expect(env.apiUrl.absoluteString.contains("qa1"))
    }
    
    @Test("Local URLs")
    func localUrls() {
        let env = TidepoolEnvironment.local
        #expect(env.apiUrl.absoluteString.contains("localhost"))
    }
    
    @Test("Auth URL")
    func authUrl() {
        let env = TidepoolEnvironment.production
        #expect(env.authUrl.absoluteString == "https://api.tidepool.org/auth")
    }
    
    @Test("All cases")
    func allCases() {
        #expect(TidepoolEnvironment.allCases.count == 5)
    }
}

@Suite("Tidepool Config")
struct TidepoolConfigTests {
    
    @Test("Config creation")
    func configCreation() {
        let config = TidepoolConfig(
            environment: .production,
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://oauth")!
        )
        
        #expect(config.clientId == "test-client")
        #expect(config.environment == .production)
    }
    
    @Test("To OAuth2 config")
    func toOAuth2Config() {
        let config = TidepoolConfig(
            environment: .production,
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://oauth")!,
            scope: "openid profile"
        )
        
        let oauth = config.toOAuth2Config()
        
        #expect(oauth.clientId == "test-client")
        #expect(oauth.authorizationEndpoint.absoluteString.contains("oauth2/authorize"))
        #expect(oauth.tokenEndpoint.absoluteString.contains("oauth2/token"))
    }
}

@Suite("Tidepool Session")
struct TidepoolSessionTests {
    
    @Test("Session creation")
    func sessionCreation() {
        let session = TidepoolSession(userId: "user123", token: "token456")
        
        #expect(session.userId == "user123")
        #expect(session.token == "token456")
        #expect(session.expiresAt == nil)
    }
    
    @Test("Session with expiry")
    func sessionWithExpiry() {
        let session = TidepoolSession(
            userId: "user123",
            token: "token456",
            serverTime: Date(),
            expiresIn: 3600
        )
        
        #expect(session.expiresAt != nil)
        #expect(session.expiresAt! > Date())
    }
    
    @Test("Session to credential")
    func sessionToCredential() {
        let session = TidepoolSession(
            userId: "user123",
            token: "token456",
            expiresIn: 3600
        )
        
        let credential = session.toCredential()
        
        #expect(credential.value == "token456")
        #expect(credential.tokenType == .access)
    }
}

@Suite("Tidepool Profile")
struct TidepoolProfileTests {
    
    @Test("Profile creation")
    func profileCreation() {
        let profile = TidepoolProfile(
            userid: "user123",
            username: "test@example.com",
            emails: ["test@example.com"],
            emailVerified: true
        )
        
        #expect(profile.userid == "user123")
        #expect(profile.emails?.first == "test@example.com")
    }
    
    @Test("Profile to user identity")
    func profileToUserIdentity() {
        let profile = TidepoolProfile(
            userid: "user123",
            emails: ["test@example.com"],
            profile: TidepoolProfileData(fullName: "Test User")
        )
        
        let identity = profile.toUserIdentity()
        
        #expect(identity.id == "user123")
        #expect(identity.provider == .tidepool)
        #expect(identity.displayName == "Test User")
        #expect(identity.email == "test@example.com")
    }
    
    @Test("Profile decoding")
    func profileDecoding() throws {
        let json = """
        {
            "userid": "abc123",
            "username": "user@test.com",
            "emails": ["user@test.com"],
            "emailVerified": true,
            "profile": {
                "fullName": "John Doe",
                "patient": {
                    "birthday": "1990-01-15",
                    "diagnosisType": "type1"
                }
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let profile = try JSONDecoder().decode(TidepoolProfile.self, from: data)
        
        #expect(profile.userid == "abc123")
        #expect(profile.profile?.fullName == "John Doe")
        #expect(profile.profile?.patient?.diagnosisType == "type1")
    }
}

@Suite("Tidepool Patient Data")
struct TidepoolPatientDataTests {
    
    @Test("Patient data creation")
    func patientDataCreation() {
        let patient = TidepoolPatientData(
            birthday: "1990-01-15",
            diagnosisDate: "2000-06-01",
            diagnosisType: "type1",
            targetDevices: ["pump", "cgm"],
            targetTimezone: "America/New_York"
        )
        
        #expect(patient.diagnosisType == "type1")
        #expect(patient.targetDevices?.count == 2)
    }
}

@Suite("Tidepool Error")
struct TidepoolErrorTests {
    
    @Test("Error cases")
    func errorCases() {
        let errors: [TidepoolError] = [
            .invalidCredentials,
            .sessionExpired,
            .networkError("connection failed"),
            .rateLimited,
            .serverError(500),
            .userNotFound,
            .accessDenied,
            .invalidResponse
        ]
        
        #expect(errors.count == 8)
    }
}

@Suite("Tidepool Auth")
struct TidepoolAuthTests {
    
    @Test("Auth creation")
    func authCreation() async {
        let config = TidepoolConfig(
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://oauth")!
        )
        let auth = TidepoolAuth(config: config)
        
        let session = await auth.getCurrentSession()
        #expect(session == nil)
    }
    
    @Test("Set and get session")
    func setAndGetSession() async {
        let config = TidepoolConfig(
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://oauth")!
        )
        let auth = TidepoolAuth(config: config)
        
        let session = TidepoolSession(userId: "user1", token: "token1")
        await auth.setSession(session)
        
        let retrieved = await auth.getCurrentSession()
        #expect(retrieved?.userId == "user1")
    }
    
    @Test("Clear session")
    func clearSession() async {
        let config = TidepoolConfig(
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://oauth")!
        )
        let auth = TidepoolAuth(config: config)
        
        await auth.setSession(TidepoolSession(userId: "user1", token: "token1"))
        await auth.clearSession()
        
        let session = await auth.getCurrentSession()
        #expect(session == nil)
    }
    
    @Test("Credential key")
    func credentialKey() async {
        let config = TidepoolConfig(
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://oauth")!
        )
        let auth = TidepoolAuth(config: config)
        
        let key = await auth.credentialKey(userId: "user123")
        
        #expect(key.service == "com.t1pal.tidepool")
        #expect(key.account == "user123")
    }
    
    @Test("Build authorization URL")
    func buildAuthorizationUrl() async {
        let config = TidepoolConfig(
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://oauth")!,
            scope: "openid profile"
        )
        let auth = TidepoolAuth(config: config)
        
        let url = await auth.buildAuthorizationUrl(state: "random-state")
        
        #expect(url.absoluteString.contains("client_id=test-client"))
        #expect(url.absoluteString.contains("state=random-state"))
        #expect(url.absoluteString.contains("response_type=code"))
    }
    
    @Test("Expired session not returned")
    func expiredSessionNotReturned() async {
        let config = TidepoolConfig(
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://oauth")!
        )
        let auth = TidepoolAuth(config: config)
        
        let expiredSession = TidepoolSession(
            userId: "user1",
            token: "token1",
            serverTime: Date().addingTimeInterval(-3700),
            expiresIn: 3600
        )
        await auth.setSession(expiredSession)
        
        let session = await auth.getCurrentSession()
        #expect(session == nil)
    }
}

@Suite("Tidepool DataSet")
struct TidepoolDataSetTests {
    
    @Test("DataSet creation")
    func dataSetCreation() {
        let dataSet = TidepoolDataSet(
            id: "ds123",
            userId: "user456",
            deviceId: "pump001",
            deviceManufacturers: ["Medtronic"],
            deviceModel: "670G"
        )
        
        #expect(dataSet.id == "ds123")
        #expect(dataSet.deviceModel == "670G")
    }
}

@Suite("Tidepool Client Info")
struct TidepoolClientInfoTests {
    
    @Test("Client info creation")
    func clientInfoCreation() {
        let client = TidepoolClientInfo(
            name: "Test App",
            version: "1.0.0",
            platform: "iOS"
        )
        
        #expect(client.name == "Test App")
    }
    
    @Test("T1Pal client info")
    func t1PalClientInfo() {
        let client = TidepoolClientInfo.t1pal
        
        #expect(client.name == "T1Pal Mobile")
        #expect(client.platform == "iOS")
    }
}

// MARK: - T1Pal Identity Tests (ID-006)

@Suite("T1Pal Environment")
struct T1PalEnvironmentTests {
    
    @Test("Production URLs")
    func productionUrls() {
        let env = T1PalEnvironment.production
        
        #expect(env.apiUrl.absoluteString == "https://api.t1pal.com")
        #expect(env.authUrl.absoluteString == "https://api.t1pal.com/auth")
        #expect(env.nightscoutUrl.absoluteString == "https://ns.t1pal.com")
    }
    
    @Test("Staging URLs")
    func stagingUrls() {
        let env = T1PalEnvironment.staging
        
        #expect(env.apiUrl.absoluteString == "https://staging-api.t1pal.com")
        #expect(env.nightscoutUrl.absoluteString == "https://staging-ns.t1pal.com")
    }
    
    @Test("All cases")
    func allCases() {
        #expect(T1PalEnvironment.allCases.count == 4)
    }
}

@Suite("T1Pal Config")
struct T1PalConfigTests {
    
    @Test("Config creation")
    func configCreation() {
        let config = T1PalConfig(
            environment: .production,
            clientId: "t1pal-mobile",
            redirectUri: URL(string: "t1pal://callback")!
        )
        
        #expect(config.environment == .production)
        #expect(config.clientId == "t1pal-mobile")
        #expect(config.scope.contains("nightscout"))
    }
    
    @Test("OAuth2 config conversion")
    func oauth2ConfigConversion() {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test-client",
            redirectUri: URL(string: "t1pal://auth")!,
            scope: "openid profile"
        )
        
        let oauth = config.toOAuth2Config()
        
        #expect(oauth.clientId == "test-client")
        #expect(oauth.authorizationEndpoint.absoluteString.contains("oauth2/authorize"))
        #expect(oauth.tokenEndpoint.absoluteString.contains("oauth2/token"))
    }
}

@Suite("T1Pal Session")
struct T1PalSessionTests {
    
    @Test("Session creation")
    func sessionCreation() {
        let session = T1PalSession(
            userId: "user123",
            accessToken: "access_token_here",
            refreshToken: "refresh_token_here",
            expiresIn: 3600
        )
        
        #expect(session.userId == "user123")
        #expect(session.accessToken == "access_token_here")
        #expect(session.canRefresh)
    }
    
    @Test("Session not expired")
    func sessionNotExpired() {
        let session = T1PalSession(
            userId: "user1",
            accessToken: "token",
            expiresIn: 3600,
            issuedAt: Date()
        )
        
        #expect(!session.isExpired)
        #expect(session.expiresAt != nil)
    }
    
    @Test("Session expired")
    func sessionExpired() {
        let session = T1PalSession(
            userId: "user1",
            accessToken: "token",
            expiresIn: 3600,
            issuedAt: Date().addingTimeInterval(-7200)
        )
        
        #expect(session.isExpired)
    }
    
    @Test("Session without refresh token")
    func sessionWithoutRefreshToken() {
        let session = T1PalSession(userId: "user1", accessToken: "token")
        #expect(!session.canRefresh)
    }
    
    @Test("To credential")
    func toCredential() {
        let session = T1PalSession(
            userId: "user1",
            accessToken: "my_token",
            expiresIn: 3600
        )
        
        let credential = session.toCredential()
        
        #expect(credential.tokenType == .access)
        #expect(credential.value == "my_token")
        #expect(credential.expiresAt != nil)
    }
}

@Suite("T1Pal Profile")
struct T1PalProfileTests {
    
    @Test("Profile creation")
    func profileCreation() {
        let profile = T1PalProfile(
            userId: "user123",
            email: "test@example.com",
            displayName: "Test User",
            verified: true
        )
        
        #expect(profile.userId == "user123")
        #expect(profile.email == "test@example.com")
        #expect(profile.verified)
    }
    
    @Test("To user identity")
    func toUserIdentity() {
        let profile = T1PalProfile(
            userId: "user123",
            email: "test@example.com",
            displayName: "Test User",
            verified: true
        )
        
        let identity = profile.toUserIdentity()
        
        #expect(identity.id == "user123")
        #expect(identity.provider == .t1pal)
        #expect(identity.email == "test@example.com")
        #expect(identity.displayName == "Test User")
    }
}

@Suite("T1Pal Subscription")
struct T1PalSubscriptionTests {
    
    @Test("Active subscription")
    func activeSubscription() {
        let subscription = T1PalSubscription(
            plan: .basic,
            status: .active,
            nightscoutLimit: 1
        )
        
        #expect(subscription.isActive)
        #expect(subscription.nightscoutLimit == 1)
    }
    
    @Test("Trialing subscription")
    func trialingSubscription() {
        let subscription = T1PalSubscription(plan: .family, status: .trialing)
        #expect(subscription.isActive)
    }
    
    @Test("Canceled subscription")
    func canceledSubscription() {
        let subscription = T1PalSubscription(plan: .basic, status: .canceled)
        #expect(!subscription.isActive)
    }
    
    @Test("Expired subscription")
    func expiredSubscription() {
        let subscription = T1PalSubscription(plan: .family, status: .expired)
        #expect(!subscription.isActive)
    }
}

@Suite("T1Pal Plan")
struct T1PalPlanTests {
    
    @Test("Free plan")
    func freePlan() {
        let plan = T1PalPlan.free
        #expect(plan.displayName == "Free")
        #expect(plan.nightscoutLimit == 1)
    }
    
    @Test("Family plan")
    func familyPlan() {
        let plan = T1PalPlan.family
        #expect(plan.displayName == "Family")
        #expect(plan.nightscoutLimit == 5)
    }
    
    @Test("Clinic plan")
    func clinicPlan() {
        let plan = T1PalPlan.clinic
        #expect(plan.displayName == "Clinic")
        #expect(plan.nightscoutLimit == 50)
    }
    
    @Test("All plans")
    func allPlans() {
        #expect(T1PalPlan.allCases.count == 4)
    }
}

@Suite("T1Pal Instance")
struct T1PalInstanceTests {
    
    @Test("Instance creation")
    func instanceCreation() {
        let instance = T1PalInstance(
            id: "inst123",
            userId: "user456",
            subdomain: "mysite",
            displayName: "My Nightscout",
            status: .active
        )
        
        #expect(instance.id == "inst123")
        #expect(instance.subdomain == "mysite")
        #expect(instance.status.isUsable)
    }
    
    @Test("Nightscout URL")
    func nightscoutUrl() {
        let instance = T1PalInstance(
            id: "inst1",
            userId: "user1",
            subdomain: "kiddo"
        )
        
        let url = instance.nightscoutUrl(environment: .production)
        #expect(url.absoluteString == "https://kiddo.ns.t1pal.com")
        
        let stagingUrl = instance.nightscoutUrl(environment: .staging)
        #expect(stagingUrl.absoluteString == "https://kiddo.staging-ns.t1pal.com")
    }
    
    @Test("To Nightscout instance")
    func toNightscoutInstance() {
        let instance = T1PalInstance(
            id: "inst1",
            userId: "user1",
            subdomain: "myloop",
            displayName: "My Loop",
            status: .active,
            apiSecret: "secret123"
        )
        
        let nsInstance = instance.toNightscoutInstance()
        
        #expect(nsInstance.name == "My Loop")
        #expect(nsInstance.url.absoluteString.contains("myloop"))
        #expect(nsInstance.authMethod == .apiSecret)
    }
    
    @Test("Provisioning status")
    func provisioningStatus() {
        let instance = T1PalInstance(
            id: "inst1",
            userId: "user1",
            subdomain: "pending",
            status: .provisioning
        )
        
        #expect(!instance.status.isUsable)
    }
}

@Suite("T1Pal Instance Status")
struct T1PalInstanceStatusTests {
    
    @Test("Active is usable")
    func activeIsUsable() {
        #expect(T1PalInstanceStatus.active.isUsable)
    }
    
    @Test("Provisioning not usable")
    func provisioningNotUsable() {
        #expect(!T1PalInstanceStatus.provisioning.isUsable)
    }
    
    @Test("Suspended not usable")
    func suspendedNotUsable() {
        #expect(!T1PalInstanceStatus.suspended.isUsable)
    }
    
    @Test("Deleted not usable")
    func deletedNotUsable() {
        #expect(!T1PalInstanceStatus.deleted.isUsable)
    }
}

@Suite("T1Pal Provision Request")
struct T1PalProvisionRequestTests {
    
    @Test("Valid subdomain")
    func validSubdomain() {
        let request = T1PalProvisionRequest(subdomain: "mysite123")
        #expect(request.isValidSubdomain)
    }
    
    @Test("Subdomain too short")
    func subdomainTooShort() {
        let request = T1PalProvisionRequest(subdomain: "ab")
        #expect(!request.isValidSubdomain)
    }
    
    @Test("Subdomain starts with number")
    func subdomainStartsWithNumber() {
        let request = T1PalProvisionRequest(subdomain: "123site")
        #expect(!request.isValidSubdomain)
    }
    
    @Test("Subdomain with dash")
    func subdomainWithDash() {
        let request = T1PalProvisionRequest(subdomain: "my-site")
        #expect(request.isValidSubdomain)
    }
    
    @Test("Subdomain too long")
    func subdomainTooLong() {
        let longName = String(repeating: "a", count: 35)
        let request = T1PalProvisionRequest(subdomain: longName)
        #expect(!request.isValidSubdomain)
    }
    
    @Test("Default units")
    func defaultUnits() {
        let request = T1PalProvisionRequest(subdomain: "mysite")
        #expect(request.units == "mg/dl")
    }
}

@Suite("T1Pal Auth")
struct T1PalAuthTests {
    
    @Test("Auth initialization")
    func authInitialization() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let isAuth = await auth.isAuthenticated
        #expect(!isAuth)
    }
    
    @Test("Set and get session")
    func setAndGetSession() async {
        let config = T1PalConfig(
            environment: .staging,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let session = T1PalSession(
            userId: "user1",
            accessToken: "token123",
            expiresIn: 3600
        )
        await auth.setSession(session)
        
        let retrieved = await auth.getCurrentSession()
        #expect(retrieved != nil)
        #expect(retrieved?.userId == "user1")
    }
    
    @Test("Clear session")
    func clearSession() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        await auth.setSession(T1PalSession(userId: "u1", accessToken: "t1"))
        await auth.clearSession()
        
        let session = await auth.getCurrentSession()
        #expect(session == nil)
    }
    
    @Test("Expired session returns nil")
    func expiredSessionReturnsNil() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let expired = T1PalSession(
            userId: "user1",
            accessToken: "token",
            expiresIn: 3600,
            issuedAt: Date().addingTimeInterval(-7200)
        )
        await auth.setSession(expired)
        
        let session = await auth.getCurrentSession()
        #expect(session == nil)
    }
    
    @Test("Build authorization URL")
    func buildAuthorizationUrl() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "my-client",
            redirectUri: URL(string: "t1pal://callback")!,
            scope: "openid profile"
        )
        let auth = T1PalAuth(config: config)
        
        let url = await auth.buildAuthorizationUrl(state: "test-state")
        
        #expect(url.absoluteString.contains("oauth2/authorize"))
        #expect(url.absoluteString.contains("client_id=my-client"))
        #expect(url.absoluteString.contains("state=test-state"))
    }
    
    @Test("Credential key")
    func credentialKey() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let key = await auth.credentialKey(userId: "user123")
        
        #expect(key.service == "com.t1pal.t1pal")
        #expect(key.account == "user123")
    }
    
    @Test("Environment")
    func environment() async {
        let config = T1PalConfig(
            environment: .staging,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let env = await auth.environment
        #expect(env == .staging)
    }
    
    @Test("Instance management")
    func instanceManagement() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let instance = T1PalInstance(
            id: "inst1",
            userId: "user1",
            subdomain: "test",
            status: .active
        )
        await auth.addInstance(instance)
        
        var instances = await auth.getInstances()
        #expect(instances.count == 1)
        
        await auth.removeInstance(id: "inst1")
        instances = await auth.getInstances()
        #expect(instances.count == 0)
    }
    
    @Test("Can provision instance no profile")
    func canProvisionInstanceNoProfile() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let canProvision = await auth.canProvisionInstance()
        #expect(!canProvision)
    }
    
    @Test("Can provision instance with active subscription")
    func canProvisionInstanceWithActiveSubscription() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let profile = T1PalProfile(
            userId: "user1",
            email: "test@example.com",
            subscription: T1PalSubscription(
                plan: .family,
                status: .active,
                nightscoutLimit: 5
            )
        )
        await auth.setProfile(profile)
        
        let canProvision = await auth.canProvisionInstance()
        #expect(canProvision)
    }
    
    @Test("Cannot provision at limit")
    func cannotProvisionAtLimit() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        let profile = T1PalProfile(
            userId: "user1",
            email: "test@example.com",
            subscription: T1PalSubscription(
                plan: .basic,
                status: .active,
                nightscoutLimit: 1
            )
        )
        await auth.setProfile(profile)
        await auth.addInstance(T1PalInstance(
            id: "i1",
            userId: "user1",
            subdomain: "site1",
            status: .active
        ))
        
        let canProvision = await auth.canProvisionInstance()
        #expect(!canProvision)
    }
    
    @Test("Get active instances")
    func getActiveInstances() async {
        let config = T1PalConfig(
            environment: .production,
            clientId: "test",
            redirectUri: URL(string: "t1pal://auth")!
        )
        let auth = T1PalAuth(config: config)
        
        await auth.setInstances([
            T1PalInstance(id: "i1", userId: "u1", subdomain: "active1", status: .active),
            T1PalInstance(id: "i2", userId: "u1", subdomain: "prov", status: .provisioning),
            T1PalInstance(id: "i3", userId: "u1", subdomain: "active2", status: .active)
        ])
        
        let active = await auth.getActiveInstances()
        #expect(active.count == 2)
    }
}
