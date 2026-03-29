// SPDX-License-Identifier: AGPL-3.0-or-later
// NightscoutIdentityTests.swift - Identity and multi-looper tests
// Extracted from NightscoutKitTests.swift (CODE-028)
// Trace: ID-003, ID-005, ID-007, ID-008, NS-COMPAT-005

import Foundation
import Testing
@testable import NightscoutKit
import T1PalCore

// MARK: - Nightscout Discovery Tests (ID-003)

@Suite("NightscoutDiscoveryResult")
struct NightscoutDiscoveryResultTests {
    @Test("discovery result initialization")
    func discoveryResultInit() {
        let result = NightscoutDiscoveryResult(
            url: URL(string: "https://my.nightscout.io")!,
            serverName: "My Nightscout",
            version: "14.2.6",
            apiEnabled: true,
            careportalEnabled: true,
            authRequired: true,
            authValid: true,
            permissions: Set(["readable", "api:*:create"])
        )
        
        #expect(result.serverName == "My Nightscout")
        #expect(result.version == "14.2.6")
        #expect(result.apiEnabled)
        #expect(result.careportalEnabled)
    }
    
    @Test("can read with valid auth")
    func canReadWithValidAuth() {
        let result = NightscoutDiscoveryResult(
            url: URL(string: "https://test.nightscout.io")!,
            authRequired: true,
            authValid: true,
            permissions: Set(["readable"])
        )
        
        #expect(result.canRead)
    }
    
    @Test("can read with no auth")
    func canReadWithNoAuth() {
        let result = NightscoutDiscoveryResult(
            url: URL(string: "https://test.nightscout.io")!,
            authRequired: false,
            authValid: false,
            permissions: []
        )
        
        #expect(result.canRead)
    }
    
    @Test("cannot read with invalid auth")
    func cannotReadWithInvalidAuth() {
        let result = NightscoutDiscoveryResult(
            url: URL(string: "https://test.nightscout.io")!,
            authRequired: true,
            authValid: false,
            permissions: []
        )
        
        #expect(!result.canRead)
    }
    
    @Test("can write with permissions")
    func canWriteWithPermissions() {
        let result = NightscoutDiscoveryResult(
            url: URL(string: "https://test.nightscout.io")!,
            authValid: true,
            permissions: Set(["api:*:create", "readable"])
        )
        
        #expect(result.canWrite)
    }
    
    @Test("cannot write without permission")
    func cannotWriteWithoutPermission() {
        let result = NightscoutDiscoveryResult(
            url: URL(string: "https://test.nightscout.io")!,
            authValid: true,
            permissions: Set(["readable"])
        )
        
        #expect(!result.canWrite)
    }
}

@Suite("NightscoutServerStatus")
struct NightscoutServerStatusTests {
    @Test("server status decoding")
    func serverStatusDecoding() throws {
        let json = """
        {
            "status": "ok",
            "name": "Test Nightscout",
            "version": "14.2.5",
            "apiEnabled": true,
            "careportalEnabled": false,
            "settings": {
                "units": "mg/dl",
                "timeFormat": 12
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let status = try JSONDecoder().decode(NightscoutServerStatus.self, from: data)
        
        #expect(status.status == "ok")
        #expect(status.name == "Test Nightscout")
        #expect(status.version == "14.2.5")
        #expect(status.apiEnabled == true)
        #expect(status.careportalEnabled == false)
        #expect(status.settings?.units == "mg/dl")
    }
    
    @Test("server status initialization")
    func serverStatusInit() {
        let status = NightscoutServerStatus(
            status: "ok",
            name: "My Server",
            version: "15.0.0"
        )
        
        #expect(status.name == "My Server")
        #expect(status.settings == nil)
    }
}

@Suite("NightscoutSettings")
struct NightscoutSettingsTests {
    @Test("settings decoding")
    func settingsDecoding() throws {
        let json = """
        {
            "units": "mmol",
            "timeFormat": 24,
            "theme": "colors",
            "language": "en"
        }
        """
        
        let data = json.data(using: .utf8)!
        let settings = try JSONDecoder().decode(NightscoutSettings.self, from: data)
        
        #expect(settings.units == "mmol")
        #expect(settings.timeFormat == 24)
        #expect(settings.theme == "colors")
        #expect(settings.language == "en")
    }
}

@Suite("NightscoutAuthResult")
struct NightscoutAuthResultTests {
    @Test("auth result decoding")
    func authResultDecoding() throws {
        let json = """
        {
            "rolefound": "admin",
            "message": "Authorized",
            "isAdmin": true,
            "isReadable": true,
            "permissions": ["*", "api:*:create", "api:*:read"]
        }
        """
        
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(NightscoutAuthResult.self, from: data)
        
        #expect(result.rolefound == "admin")
        #expect(result.isAdmin == true)
        #expect(result.permissions?.count == 3)
    }
}

@Suite("NightscoutDiscovery")
struct NightscoutDiscoveryTests {
    @Test("normalize url with scheme")
    func normalizeUrlWithScheme() async throws {
        let discovery = NightscoutDiscovery()
        
        let url = try await discovery.normalizeUrl("https://my.nightscout.io")
        #expect(url.absoluteString == "https://my.nightscout.io")
    }
    
    @Test("normalize url without scheme")
    func normalizeUrlWithoutScheme() async throws {
        let discovery = NightscoutDiscovery()
        
        let url = try await discovery.normalizeUrl("my.nightscout.io")
        #expect(url.absoluteString == "https://my.nightscout.io")
    }
    
    @Test("normalize url removes trailing slash")
    func normalizeUrlRemovesTrailingSlash() async throws {
        let discovery = NightscoutDiscovery()
        
        let url = try await discovery.normalizeUrl("https://my.nightscout.io/")
        #expect(url.absoluteString == "https://my.nightscout.io")
    }
    
    @Test("normalize url with http")
    func normalizeUrlWithHttp() async throws {
        let discovery = NightscoutDiscovery()
        
        let url = try await discovery.normalizeUrl("http://localhost:1337")
        #expect(url.absoluteString == "http://localhost:1337")
    }
    
    @Test("normalize url trims whitespace")
    func normalizeUrlTrimsWhitespace() async throws {
        let discovery = NightscoutDiscovery()
        
        let url = try await discovery.normalizeUrl("  https://my.nightscout.io  ")
        #expect(url.absoluteString == "https://my.nightscout.io")
    }
    
    @Test("normalize invalid url throws")
    func normalizeInvalidUrlThrows() async {
        let discovery = NightscoutDiscovery()
        
        await #expect(throws: NightscoutDiscoveryError.self) {
            try await discovery.normalizeUrl("")
        }
    }
}

@Suite("NightscoutUrlParser")
struct NightscoutUrlParserTests {
    @Test("suggest url from name")
    func suggestUrlFromName() {
        let suggestions = NightscoutUrlParser.suggestUrl(from: "mysite")
        
        #expect(suggestions.contains("https://mysite.fly.dev"))
        #expect(suggestions.contains("https://mysite.herokuapp.com"))
        #expect(suggestions.contains("https://mysite.azurewebsites.net"))
        #expect(suggestions.contains("https://mysite.railway.app"))
        #expect(suggestions.contains("https://mysite.render.com"))
    }
    
    @Test("suggest url from full domain")
    func suggestUrlFromFullDomain() {
        let suggestions = NightscoutUrlParser.suggestUrl(from: "mysite.example.com")
        
        #expect(suggestions.isEmpty)
    }
}

@Suite("NightscoutDiscoveryError")
struct NightscoutDiscoveryErrorTests {
    @Test("error cases")
    func errorCases() {
        let errors: [NightscoutDiscoveryError] = [
            .invalidUrl("test"),
            .networkError("connection failed"),
            .serverNotFound,
            .notNightscoutServer,
            .authenticationFailed,
            .insufficientPermissions(Set(["read"])),
            .timeout,
            .unsupportedVersion("1.0")
        ]
        
        #expect(errors.count == 8)
    }
}

// MARK: - Nightscout Direct Auth Tests (ID-005)

@Suite("NightscoutAuthMode")
struct NightscoutAuthModeTests {
    @Test("auth mode values")
    func authModeValues() {
        #expect(NightscoutAuthMode.apiSecret.rawValue == "api_secret")
        #expect(NightscoutAuthMode.jwtToken.rawValue == "jwt")
        #expect(NightscoutAuthMode.none.rawValue == "none")
    }
}

@Suite("NightscoutJWTClaims")
struct NightscoutJWTClaimsTests {
    @Test("claims creation")
    func claimsCreation() {
        let claims = NightscoutJWTClaims(
            accessToken: "token123",
            iat: 1704067200,
            exp: 1704153600,
            sub: "readable"
        )
        
        #expect(claims.accessToken == "token123")
        #expect(claims.sub == "readable")
    }
    
    @Test("is expired")
    func isExpired() {
        let pastExp = Int(Date().timeIntervalSince1970) - 3600  // 1 hour ago
        let claims = NightscoutJWTClaims(exp: pastExp)
        
        #expect(claims.isExpired)
    }
    
    @Test("not expired")
    func notExpired() {
        let futureExp = Int(Date().timeIntervalSince1970) + 3600  // 1 hour from now
        let claims = NightscoutJWTClaims(exp: futureExp)
        
        #expect(!claims.isExpired)
    }
    
    @Test("expires at")
    func expiresAt() {
        let exp = Int(Date().timeIntervalSince1970) + 3600
        let claims = NightscoutJWTClaims(exp: exp)
        
        #expect(claims.expiresAt != nil)
    }
    
    @Test("no expiration")
    func noExpiration() {
        let claims = NightscoutJWTClaims()
        
        #expect(!claims.isExpired)
        #expect(claims.expiresAt == nil)
    }
}

@Suite("NightscoutPermissions")
struct NightscoutPermissionsTests {
    @Test("basic permissions")
    func basicPermissions() {
        let perms: NightscoutPermissions = [.readable, .apiRead]
        
        #expect(perms.contains(.readable))
        #expect(perms.contains(.apiRead))
        #expect(!perms.contains(.apiCreate))
    }
    
    @Test("read only preset")
    func readOnlyPreset() {
        let perms = NightscoutPermissions.readOnly
        
        #expect(perms.contains(.readable))
        #expect(perms.contains(.apiRead))
        #expect(!perms.contains(.apiCreate))
    }
    
    @Test("read write preset")
    func readWritePreset() {
        let perms = NightscoutPermissions.readWrite
        
        #expect(perms.contains(.apiRead))
        #expect(perms.contains(.apiCreate))
        #expect(perms.contains(.apiUpdate))
        #expect(!perms.contains(.admin))
    }
    
    @Test("from strings admin")
    func fromStringsAdmin() {
        let perms = NightscoutPermissions.from(strings: ["*"])
        
        #expect(perms.contains(.admin))
        #expect(perms.contains(.apiRead))
        #expect(perms.contains(.apiCreate))
    }
    
    @Test("from strings readable")
    func fromStringsReadable() {
        let perms = NightscoutPermissions.from(strings: ["readable"])
        
        #expect(perms.contains(.readable))
        #expect(!perms.contains(.apiRead))
    }
    
    @Test("from strings api create")
    func fromStringsApiCreate() {
        let perms = NightscoutPermissions.from(strings: ["api:*:read", "api:*:create"])
        
        #expect(perms.contains(.apiRead))
        #expect(perms.contains(.apiCreate))
        #expect(!perms.contains(.admin))
    }
    
    @Test("from strings careportal")
    func fromStringsCareportal() {
        let perms = NightscoutPermissions.from(strings: ["careportal"])
        
        #expect(perms.contains(.careportal))
    }
}

@Suite("NightscoutAuthState")
struct NightscoutAuthStateTests {
    @Test("auth state creation")
    func authStateCreation() {
        let state = NightscoutAuthState(
            url: URL(string: "https://my.nightscout.io")!,
            mode: .apiSecret,
            isAuthenticated: true,
            permissions: [.readable, .apiRead, .apiCreate],
            serverName: "My NS"
        )
        
        #expect(state.serverName == "My NS")
        #expect(state.mode == .apiSecret)
        #expect(state.isAuthenticated)
    }
    
    @Test("is valid")
    func isValid() {
        let state = NightscoutAuthState(
            url: URL(string: "https://test.io")!,
            mode: .apiSecret,
            isAuthenticated: true,
            permissions: [.apiRead]
        )
        
        #expect(state.isValid)
    }
    
    @Test("is valid expired")
    func isValidExpired() {
        let state = NightscoutAuthState(
            url: URL(string: "https://test.io")!,
            mode: .jwtToken,
            isAuthenticated: true,
            permissions: [.apiRead],
            expiresAt: Date().addingTimeInterval(-3600)
        )
        
        #expect(!state.isValid)
    }
    
    @Test("can read")
    func canRead() {
        let state = NightscoutAuthState(
            url: URL(string: "https://test.io")!,
            mode: .apiSecret,
            isAuthenticated: true,
            permissions: [.apiRead]
        )
        
        #expect(state.canRead)
    }
    
    @Test("can write")
    func canWrite() {
        let state = NightscoutAuthState(
            url: URL(string: "https://test.io")!,
            mode: .apiSecret,
            isAuthenticated: true,
            permissions: [.apiRead, .apiCreate]
        )
        
        #expect(state.canWrite)
    }
    
    @Test("cannot write read only")
    func cannotWriteReadOnly() {
        let state = NightscoutAuthState(
            url: URL(string: "https://test.io")!,
            mode: .apiSecret,
            isAuthenticated: true,
            permissions: [.apiRead]
        )
        
        #expect(!state.canWrite)
    }
    
    @Test("not authenticated cannot read")
    func notAuthenticatedCannotRead() {
        let state = NightscoutAuthState(
            url: URL(string: "https://test.io")!,
            mode: .none,
            isAuthenticated: false,
            permissions: [.apiRead]
        )
        
        #expect(!state.canRead)
    }
}

@Suite("NightscoutAuth")
struct NightscoutAuthTests {
    @Test("auth creation")
    func authCreation() async {
        let auth = NightscoutAuth()
        
        let state = await auth.getAuthState(for: URL(string: "https://test.io")!)
        #expect(state == nil)
    }
    
    @Test("is authenticated false")
    func isAuthenticatedFalse() async {
        let auth = NightscoutAuth()
        
        let isAuth = await auth.isAuthenticated(for: URL(string: "https://test.io")!)
        #expect(!isAuth)
    }
    
    @Test("get authenticated urls empty")
    func getAuthenticatedUrlsEmpty() async {
        let auth = NightscoutAuth()
        
        let urls = await auth.getAuthenticatedUrls()
        #expect(urls.isEmpty)
    }
}

// MARK: - Multi-Looper Tests (ID-007)

@Suite("LooperProfile")
struct LooperProfileTests {
    @Test("profile creation")
    func profileCreation() {
        let profile = LooperProfile(
            name: "Child 1",
            nightscoutUrl: URL(string: "https://child1.nightscout.io")!,
            color: "#FF5733",
            emoji: "👶"
        )
        
        #expect(profile.name == "Child 1")
        #expect(profile.color == "#FF5733")
        #expect(profile.emoji == "👶")
        #expect(!profile.isActive)
    }
    
    @Test("with access time")
    func withAccessTime() {
        let profile = LooperProfile(
            name: "Test",
            nightscoutUrl: URL(string: "https://test.io")!
        )
        
        let updated = profile.withAccessTime()
        
        #expect(updated.lastAccessedAt != nil)
        #expect(updated.id == profile.id)
    }
    
    @Test("with active status")
    func withActiveStatus() {
        let profile = LooperProfile(
            name: "Test",
            nightscoutUrl: URL(string: "https://test.io")!,
            isActive: false
        )
        
        let activated = profile.withActiveStatus(true)
        
        #expect(activated.isActive)
        #expect(activated.id == profile.id)
    }
    
    @Test("profile hashable")
    func profileHashable() {
        let profile1 = LooperProfile(
            id: UUID(),
            name: "Test1",
            nightscoutUrl: URL(string: "https://test1.io")!
        )
        let profile2 = LooperProfile(
            id: profile1.id,
            name: "Test2",
            nightscoutUrl: URL(string: "https://test2.io")!
        )
        
        // Same ID = equal
        #expect(profile1 == profile2)
    }
    
    @Test("profile codable")
    func profileCodable() throws {
        let profile = LooperProfile(
            name: "Test",
            nightscoutUrl: URL(string: "https://test.io")!,
            color: "#00FF00"
        )
        
        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(LooperProfile.self, from: encoded)
        
        #expect(decoded.name == "Test")
        #expect(decoded.color == "#00FF00")
    }
}

@Suite("InstanceRegistryEvent")
struct InstanceRegistryEventTests {
    @Test("event cases")
    func eventCases() {
        let profile = LooperProfile(
            name: "Test",
            nightscoutUrl: URL(string: "https://test.io")!
        )
        
        let events: [InstanceRegistryEvent] = [
            .added(profile),
            .removed(profile.id),
            .updated(profile),
            .activeChanged(profile),
            .activeChanged(nil)
        ]
        
        #expect(events.count == 5)
    }
}

@Suite("InstanceRegistry")
struct InstanceRegistryTests {
    @Test("registry creation")
    func registryCreation() async {
        let registry = InstanceRegistry()
        
        let profiles = await registry.getAllProfiles()
        #expect(profiles.isEmpty)
    }
    
    @Test("add profile")
    func addProfile() async {
        let registry = InstanceRegistry()
        let profile = LooperProfile(
            name: "Child",
            nightscoutUrl: URL(string: "https://child.ns.io")!
        )
        
        await registry.addProfile(profile)
        
        let count = await registry.getProfileCount()
        #expect(count == 1)
    }
    
    @Test("first profile becomes active")
    func firstProfileBecomesActive() async {
        let registry = InstanceRegistry()
        let profile = LooperProfile(
            name: "First",
            nightscoutUrl: URL(string: "https://first.io")!
        )
        
        await registry.addProfile(profile)
        
        let active = await registry.getActiveProfile()
        #expect(active != nil)
        #expect(active?.id == profile.id)
    }
    
    @Test("get profile by id")
    func getProfileById() async {
        let registry = InstanceRegistry()
        let profile = LooperProfile(
            name: "Test",
            nightscoutUrl: URL(string: "https://test.io")!
        )
        
        await registry.addProfile(profile)
        
        let retrieved = await registry.getProfile(profile.id)
        #expect(retrieved != nil)
        #expect(retrieved?.name == "Test")
    }
    
    @Test("get profile by url")
    func getProfileByUrl() async {
        let registry = InstanceRegistry()
        let url = URL(string: "https://unique.ns.io")!
        let profile = LooperProfile(name: "Unique", nightscoutUrl: url)
        
        await registry.addProfile(profile)
        
        let found = await registry.getProfile(for: url)
        #expect(found != nil)
    }
    
    @Test("remove profile")
    func removeProfile() async throws {
        let registry = InstanceRegistry()
        let profile = LooperProfile(
            name: "ToRemove",
            nightscoutUrl: URL(string: "https://remove.io")!
        )
        
        await registry.addProfile(profile)
        try await registry.removeProfile(profile.id)
        
        let count = await registry.getProfileCount()
        #expect(count == 0)
    }
    
    @Test("remove non existent")
    func removeNonExistent() async {
        let registry = InstanceRegistry()
        
        do {
            try await registry.removeProfile(UUID())
            Issue.record("Should throw")
        } catch let error as InstanceRegistryError {
            if case .profileNotFound = error {
                // Expected
            } else {
                Issue.record("Wrong error")
            }
        } catch {
            Issue.record("Unexpected error")
        }
    }
    
    @Test("set active profile")
    func setActiveProfile() async throws {
        let registry = InstanceRegistry()
        
        let profile1 = LooperProfile(name: "P1", nightscoutUrl: URL(string: "https://p1.io")!)
        let profile2 = LooperProfile(name: "P2", nightscoutUrl: URL(string: "https://p2.io")!)
        
        await registry.addProfile(profile1)
        await registry.addProfile(profile2)
        
        try await registry.setActiveProfile(profile2.id)
        
        let active = await registry.getActiveProfile()
        #expect(active?.id == profile2.id)
    }
    
    @Test("export import profiles")
    func exportImportProfiles() async {
        let registry1 = InstanceRegistry()
        let profile = LooperProfile(name: "Export", nightscoutUrl: URL(string: "https://export.io")!)
        
        await registry1.addProfile(profile)
        let exported = await registry1.exportProfiles()
        
        let registry2 = InstanceRegistry()
        await registry2.importProfiles(exported)
        
        let count = await registry2.getProfileCount()
        #expect(count == 1)
    }
    
    @Test("clear")
    func clear() async {
        let registry = InstanceRegistry()
        
        await registry.addProfile(LooperProfile(name: "P1", nightscoutUrl: URL(string: "https://p1.io")!))
        await registry.addProfile(LooperProfile(name: "P2", nightscoutUrl: URL(string: "https://p2.io")!))
        
        await registry.clear()
        
        let isEmpty = await registry.isEmpty
        #expect(isEmpty)
    }
}

@Suite("InstanceRegistryError")
struct InstanceRegistryErrorTests {
    @Test("error cases")
    func errorCases() {
        let errors: [InstanceRegistryError] = [
            .profileNotFound,
            .noActiveProfile,
            .duplicateUrl,
            .authenticationRequired,
            .credentialNotFound
        ]
        
        #expect(errors.count == 5)
    }
}

@Suite("InstanceSwitcher")
struct InstanceSwitcherTests {
    @Test("switcher creation")
    func switcherCreation() async {
        let registry = InstanceRegistry()
        let switcher = InstanceSwitcher(registry: registry)
        
        let recent = await switcher.getRecentProfiles()
        #expect(recent.isEmpty)
    }
    
    @Test("switch to updates recent")
    func switchToUpdatesRecent() async throws {
        let registry = InstanceRegistry()
        let switcher = InstanceSwitcher(registry: registry)
        
        let profile = LooperProfile(name: "Test", nightscoutUrl: URL(string: "https://test.io")!)
        await registry.addProfile(profile)
        
        try await switcher.switchTo(profile.id)
        
        let recent = await switcher.getRecentProfiles()
        #expect(recent.count == 1)
        #expect(recent.first?.id == profile.id)
    }
}

@Suite("LooperQuickStatus")
struct LooperQuickStatusTests {
    @Test("quick status creation")
    func quickStatusCreation() {
        let profile = LooperProfile(name: "Test", nightscoutUrl: URL(string: "https://test.io")!)
        let status = LooperQuickStatus(
            profile: profile,
            latestGlucose: 120,
            glucoseDate: Date(),
            direction: "Flat",
            isReachable: true
        )
        
        #expect(status.latestGlucose == 120)
        #expect(status.isReachable)
    }
    
    @Test("data age")
    func dataAge() {
        let profile = LooperProfile(name: "Test", nightscoutUrl: URL(string: "https://test.io")!)
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        let status = LooperQuickStatus(
            profile: profile,
            glucoseDate: fiveMinutesAgo,
            isReachable: true
        )
        
        #expect(status.dataAge != nil)
        #expect(status.dataAge! > 290)
    }
    
    @Test("is stale")
    func isStale() {
        let profile = LooperProfile(name: "Test", nightscoutUrl: URL(string: "https://test.io")!)
        
        // Recent data - not stale
        let recent = LooperQuickStatus(
            profile: profile,
            glucoseDate: Date().addingTimeInterval(-60),
            isReachable: true
        )
        #expect(!recent.isStale)
        
        // Old data - stale
        let old = LooperQuickStatus(
            profile: profile,
            glucoseDate: Date().addingTimeInterval(-900),
            isReachable: true
        )
        #expect(old.isStale)
    }
    
    @Test("no data is stale")
    func noDataIsStale() {
        let profile = LooperProfile(name: "Test", nightscoutUrl: URL(string: "https://test.io")!)
        let status = LooperQuickStatus(profile: profile, isReachable: false)
        
        #expect(status.isStale)
    }
}

// MARK: - Caregiver Invitation Tests (ID-008)

@Suite("CaregiverPermission")
struct CaregiverPermissionTests {
    @Test("permission levels")
    func permissionLevels() {
        #expect(CaregiverPermission.readOnly.canRead)
        #expect(!CaregiverPermission.readOnly.canWrite)
        #expect(!CaregiverPermission.readOnly.canModifySettings)
        #expect(!CaregiverPermission.readOnly.canInvite)
    }
    
    @Test("read write permission")
    func readWritePermission() {
        let perm = CaregiverPermission.readWrite
        
        #expect(perm.canRead)
        #expect(perm.canWrite)
        #expect(!perm.canModifySettings)
    }
    
    @Test("full access permission")
    func fullAccessPermission() {
        let perm = CaregiverPermission.fullAccess
        
        #expect(perm.canWrite)
        #expect(perm.canModifySettings)
        #expect(!perm.canInvite)
    }
    
    @Test("admin permission")
    func adminPermission() {
        let perm = CaregiverPermission.admin
        
        #expect(perm.canWrite)
        #expect(perm.canModifySettings)
        #expect(perm.canInvite)
    }
    
    @Test("display name")
    func displayName() {
        #expect(CaregiverPermission.readOnly.displayName == "View Only")
        #expect(CaregiverPermission.admin.displayName == "Administrator")
    }
    
    @Test("all cases")
    func allCases() {
        #expect(CaregiverPermission.allCases.count == 4)
    }
}

@Suite("InviteStatus")
struct InviteStatusTests {
    @Test("status values")
    func statusValues() {
        #expect(InviteStatus.pending.rawValue == "pending")
        #expect(InviteStatus.accepted.rawValue == "accepted")
        #expect(InviteStatus.expired.rawValue == "expired")
        #expect(InviteStatus.revoked.rawValue == "revoked")
    }
}

@Suite("CaregiverInvite")
struct CaregiverInviteTests {
    @Test("invite creation")
    func inviteCreation() {
        let invite = CaregiverInvite(
            code: "ABC123",
            profileId: UUID(),
            permission: .readOnly,
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        #expect(invite.code == "ABC123")
        #expect(invite.permission == .readOnly)
        #expect(invite.status == .pending)
        #expect(invite.maxUses == 1)
    }
    
    @Test("is valid")
    func isValid() {
        let invite = CaregiverInvite(
            code: "VALID",
            profileId: UUID(),
            permission: .readWrite,
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        #expect(invite.isValid)
        #expect(!invite.isExpired)
    }
    
    @Test("is expired")
    func isExpired() {
        let invite = CaregiverInvite(
            code: "EXPIRED",
            profileId: UUID(),
            permission: .readOnly,
            expiresAt: Date().addingTimeInterval(-3600)
        )
        
        #expect(invite.isExpired)
        #expect(!invite.isValid)
    }
    
    @Test("time remaining")
    func timeRemaining() {
        let invite = CaregiverInvite(
            code: "TEST",
            profileId: UUID(),
            permission: .readOnly,
            expiresAt: Date().addingTimeInterval(1800)
        )
        
        #expect(invite.timeRemaining > 1700)
        #expect(invite.timeRemaining < 1900)
    }
    
    @Test("shareable link")
    func shareableLink() {
        let invite = CaregiverInvite(
            code: "SHARE123",
            profileId: UUID(),
            permission: .readOnly,
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        let link = invite.shareableLink()
        
        #expect(link.absoluteString.contains("code=SHARE123"))
        #expect(link.absoluteString.contains("invite"))
    }
    
    @Test("with use")
    func withUse() {
        let invite = CaregiverInvite(
            code: "USE",
            profileId: UUID(),
            permission: .readOnly,
            expiresAt: Date().addingTimeInterval(3600),
            maxUses: 2
        )
        
        let used = invite.withUse()
        
        #expect(used.useCount == 1)
        #expect(used.status == .pending)
        
        let usedAgain = used.withUse()
        #expect(usedAgain.useCount == 2)
        #expect(usedAgain.status == .accepted)
    }
    
    @Test("revoked")
    func revoked() {
        let invite = CaregiverInvite(
            code: "REVOKE",
            profileId: UUID(),
            permission: .readOnly,
            expiresAt: Date().addingTimeInterval(3600)
        )
        
        let revoked = invite.revoked()
        
        #expect(revoked.status == .revoked)
        #expect(!revoked.isValid)
    }
    
    @Test("codable")
    func codable() throws {
        let invite = CaregiverInvite(
            code: "ENCODE",
            profileId: UUID(),
            permission: .fullAccess,
            expiresAt: Date().addingTimeInterval(3600),
            note: "Test note"
        )
        
        let encoded = try JSONEncoder().encode(invite)
        let decoded = try JSONDecoder().decode(CaregiverInvite.self, from: encoded)
        
        #expect(decoded.code == "ENCODE")
        #expect(decoded.permission == .fullAccess)
        #expect(decoded.note == "Test note")
    }
}

@Suite("CaregiverRelationship")
struct CaregiverRelationshipTests {
    @Test("relationship creation")
    func relationshipCreation() {
        let relationship = CaregiverRelationship(
            caregiverId: "caregiver123",
            caregiverName: "Mom",
            profileId: UUID(),
            permission: .readWrite,
            inviteId: UUID()
        )
        
        #expect(relationship.caregiverId == "caregiver123")
        #expect(relationship.caregiverName == "Mom")
    }
    
    @Test("relationship codable")
    func relationshipCodable() throws {
        let relationship = CaregiverRelationship(
            caregiverId: "user1",
            profileId: UUID(),
            permission: .admin,
            inviteId: UUID()
        )
        
        let encoded = try JSONEncoder().encode(relationship)
        let decoded = try JSONDecoder().decode(CaregiverRelationship.self, from: encoded)
        
        #expect(decoded.caregiverId == "user1")
        #expect(decoded.permission == .admin)
    }
}

@Suite("InviteCodeGenerator")
struct InviteCodeGeneratorTests {
    @Test("generate code")
    func generateCode() {
        let code = InviteCodeGenerator.generateCode()
        
        #expect(code.count == 8)
        #expect(code.allSatisfy { $0.isLetter || $0.isNumber })
    }
    
    @Test("generate code custom length")
    func generateCodeCustomLength() {
        let code = InviteCodeGenerator.generateCode(length: 12)
        
        #expect(code.count == 12)
    }
    
    @Test("generate pin")
    func generatePin() {
        let pin = InviteCodeGenerator.generatePin()
        
        #expect(pin.count == 6)
        #expect(pin.allSatisfy { $0.isNumber })
    }
    
    @Test("generate memorable")
    func generateMemorable() {
        let code = InviteCodeGenerator.generateMemorable()
        
        #expect(code.contains("-"))
        let parts = code.split(separator: "-")
        #expect(parts.count == 3)
    }
    
    @Test("codes are unique")
    func codesAreUnique() {
        let codes = (0..<100).map { _ in InviteCodeGenerator.generateCode() }
        let unique = Set(codes)
        
        // Should be highly likely all unique
        #expect(unique.count == 100)
    }
}

@Suite("InviteManager")
struct InviteManagerTests {
    @Test("create invite")
    func createInvite() async {
        let manager = InviteManager()
        let profileId = UUID()
        
        let invite = await manager.createInvite(
            for: profileId,
            permission: .readOnly
        )
        
        #expect(invite.profileId == profileId)
        #expect(invite.permission == .readOnly)
        #expect(invite.isValid)
    }
    
    @Test("get invite by code")
    func getInviteByCode() async {
        let manager = InviteManager()
        let created = await manager.createInvite(
            for: UUID(),
            permission: .readWrite
        )
        
        let found = await manager.getInvite(byCode: created.code)
        
        #expect(found != nil)
        #expect(found?.id == created.id)
    }
    
    @Test("get invite by code case insensitive")
    func getInviteByCodeCaseInsensitive() async {
        let manager = InviteManager()
        let created = await manager.createInvite(
            for: UUID(),
            permission: .readOnly
        )
        
        let found = await manager.getInvite(byCode: created.code.lowercased())
        
        #expect(found != nil)
    }
    
    @Test("accept invite")
    func acceptInvite() async throws {
        let manager = InviteManager()
        let profileId = UUID()
        let invite = await manager.createInvite(
            for: profileId,
            permission: .fullAccess
        )
        
        let relationship = try await manager.acceptInvite(
            code: invite.code,
            caregiverId: "caregiver1",
            caregiverName: "Dad"
        )
        
        #expect(relationship.caregiverId == "caregiver1")
        #expect(relationship.permission == .fullAccess)
        #expect(relationship.profileId == profileId)
    }
    
    @Test("accept invite not found")
    func acceptInviteNotFound() async {
        let manager = InviteManager()
        
        do {
            _ = try await manager.acceptInvite(code: "INVALID", caregiverId: "user")
            Issue.record("Should throw")
        } catch let error as InviteError {
            #expect(error == .notFound)
        } catch {
            Issue.record("Wrong error")
        }
    }
    
    @Test("revoke invite")
    func revokeInvite() async throws {
        let manager = InviteManager()
        let invite = await manager.createInvite(
            for: UUID(),
            permission: .readOnly
        )
        
        try await manager.revokeInvite(invite.id)
        
        let found = await manager.getInvite(byId: invite.id)
        #expect(found?.status == .revoked)
        #expect(!(found?.isValid ?? true))
    }
    
    @Test("get invites for profile")
    func getInvitesForProfile() async {
        let manager = InviteManager()
        let profileId = UUID()
        
        _ = await manager.createInvite(for: profileId, permission: .readOnly)
        _ = await manager.createInvite(for: profileId, permission: .readWrite)
        _ = await manager.createInvite(for: UUID(), permission: .admin)
        
        let invites = await manager.getInvites(for: profileId)
        
        #expect(invites.count == 2)
    }
    
    @Test("get active invites")
    func getActiveInvites() async {
        let manager = InviteManager()
        
        _ = await manager.createInvite(for: UUID(), permission: .readOnly)
        _ = await manager.createInvite(for: UUID(), permission: .readWrite)
        
        let active = await manager.getActiveInvites()
        
        #expect(active.count == 2)
    }
    
    @Test("get relationships for profile")
    func getRelationshipsForProfile() async throws {
        let manager = InviteManager()
        let profileId = UUID()
        
        let invite = await manager.createInvite(for: profileId, permission: .readOnly)
        _ = try await manager.acceptInvite(code: invite.code, caregiverId: "user1")
        
        let relationships = await manager.getRelationships(for: profileId)
        
        #expect(relationships.count == 1)
    }
    
    @Test("remove relationship")
    func removeRelationship() async throws {
        let manager = InviteManager()
        let invite = await manager.createInvite(for: UUID(), permission: .readOnly)
        let relationship = try await manager.acceptInvite(code: invite.code, caregiverId: "user1")
        
        try await manager.removeRelationship(relationship.id)
        
        let count = await manager.relationshipCount
        #expect(count == 0)
    }
    
    @Test("export import")
    func exportImport() async {
        let manager1 = InviteManager()
        _ = await manager1.createInvite(for: UUID(), permission: .readOnly)
        _ = await manager1.createInvite(for: UUID(), permission: .admin)
        
        let exported = await manager1.exportInvites()
        
        let manager2 = InviteManager()
        await manager2.importInvites(exported)
        
        let count = await manager2.inviteCount
        #expect(count == 2)
    }
}

@Suite("InviteError")
struct InviteErrorTests {
    @Test("error equality")
    func errorEquality() {
        #expect(InviteError.notFound == InviteError.notFound)
        #expect(InviteError.expired != InviteError.invalid)
    }
    
    @Test("all error cases")
    func allErrorCases() {
        let errors: [InviteError] = [
            .notFound,
            .expired,
            .invalid,
            .maxUsesReached,
            .alreadyAccepted,
            .relationshipNotFound,
            .permissionDenied
        ]
        
        #expect(errors.count == 7)
    }
}

@Suite("CaregiverAccessChecker")
struct CaregiverAccessCheckerTests {
    @Test("can access")
    func canAccess() {
        let profileId = UUID()
        let relationships = [
            CaregiverRelationship(
                caregiverId: "user1",
                profileId: profileId,
                permission: .readOnly,
                inviteId: UUID()
            )
        ]
        
        let checker = CaregiverAccessChecker(relationships: relationships)
        
        #expect(checker.canAccess(caregiverId: "user1", profileId: profileId))
        #expect(!checker.canAccess(caregiverId: "user2", profileId: profileId))
    }
    
    @Test("get permission")
    func getPermission() {
        let profileId = UUID()
        let relationships = [
            CaregiverRelationship(
                caregiverId: "user1",
                profileId: profileId,
                permission: .fullAccess,
                inviteId: UUID()
            )
        ]
        
        let checker = CaregiverAccessChecker(relationships: relationships)
        
        let perm = checker.getPermission(caregiverId: "user1", profileId: profileId)
        #expect(perm == .fullAccess)
    }
    
    @Test("can write")
    func canWrite() {
        let profileId = UUID()
        let relationships = [
            CaregiverRelationship(
                caregiverId: "reader",
                profileId: profileId,
                permission: .readOnly,
                inviteId: UUID()
            ),
            CaregiverRelationship(
                caregiverId: "writer",
                profileId: profileId,
                permission: .readWrite,
                inviteId: UUID()
            )
        ]
        
        let checker = CaregiverAccessChecker(relationships: relationships)
        
        #expect(!checker.canWrite(caregiverId: "reader", profileId: profileId))
        #expect(checker.canWrite(caregiverId: "writer", profileId: profileId))
    }
    
    @Test("can invite")
    func canInvite() {
        let profileId = UUID()
        let relationships = [
            CaregiverRelationship(
                caregiverId: "admin",
                profileId: profileId,
                permission: .admin,
                inviteId: UUID()
            ),
            CaregiverRelationship(
                caregiverId: "full",
                profileId: profileId,
                permission: .fullAccess,
                inviteId: UUID()
            )
        ]
        
        let checker = CaregiverAccessChecker(relationships: relationships)
        
        #expect(checker.canInvite(caregiverId: "admin", profileId: profileId))
        #expect(!checker.canInvite(caregiverId: "full", profileId: profileId))
    }
}

// MARK: - Sync Identifier Tests (NS-COMPAT-005)

@Suite("SyncIdentifier")
struct SyncIdentifierTests {
    
    // MARK: - Entry Sync Identifier
    
    @Test("entry sync identifier generation")
    func entrySyncIdentifierGeneration() {
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: "dexcom"
        )
        
        #expect(entry.syncIdentifier == "dexcom:sgv:1769860800000")
    }
    
    @Test("entry sync identifier without device")
    func entrySyncIdentifierWithoutDevice() {
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: nil
        )
        
        #expect(entry.syncIdentifier == "T1Pal:sgv:1769860800000")
    }
    
    @Test("entry sync identifier from explicit")
    func entrySyncIdentifierFromExplicit() {
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: "dexcom",
            identifier: "my-custom-id"
        )
        
        #expect(entry.syncIdentifier == "my-custom-id")
    }
    
    @Test("entry equality")
    func entryEquality() {
        let entry1 = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: "dexcom"
        )
        
        let entry2 = NightscoutEntry(
            type: "sgv",
            sgv: 125,  // Different value but same identifier
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: "dexcom"
        )
        
        // Same syncIdentifier means equal (for dedup purposes)
        #expect(entry1 == entry2)
    }
    
    @Test("entry inequality")
    func entryInequality() {
        let entry1 = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: "dexcom"
        )
        
        let entry2 = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            dateString: "2026-02-01T12:05:00Z",
            date: 1769861100000,  // Different timestamp
            device: "dexcom"
        )
        
        #expect(entry1 != entry2)
    }
    
    // MARK: - Treatment Sync Identifier
    
    @Test("treatment sync identifier generation")
    func treatmentSyncIdentifierGeneration() {
        let treatment = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5,
            enteredBy: "Loop"
        )
        
        #expect(treatment.syncIdentifier == "Loop:Bolus:2026-02-01T12:00:00Z")
    }
    
    @Test("treatment sync identifier without enteredBy")
    func treatmentSyncIdentifierWithoutEnteredBy() {
        let treatment = NightscoutTreatment(
            eventType: "Carb Correction",
            created_at: "2026-02-01T12:00:00Z",
            carbs: 30,
            enteredBy: nil
        )
        
        #expect(treatment.syncIdentifier == "T1Pal:Carb Correction:2026-02-01T12:00:00Z")
    }
    
    @Test("treatment sync identifier from explicit")
    func treatmentSyncIdentifierFromExplicit() {
        let treatment = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5,
            enteredBy: "Loop",
            identifier: "my-treatment-id"
        )
        
        #expect(treatment.syncIdentifier == "my-treatment-id")
    }
    
    @Test("treatment equality")
    func treatmentEquality() {
        let treatment1 = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5,
            enteredBy: "Loop"
        )
        
        let treatment2 = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 3.0,  // Different insulin but same identifier
            enteredBy: "Loop"
        )
        
        #expect(treatment1 == treatment2)
    }
    
    @Test("treatment inequality")
    func treatmentInequality() {
        let treatment1 = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5,
            enteredBy: "Loop"
        )
        
        let treatment2 = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-01T12:05:00Z",  // Different timestamp
            insulin: 2.5,
            enteredBy: "Loop"
        )
        
        #expect(treatment1 != treatment2)
    }
    
    // MARK: - Deduplication with Set
    
    @Test("entry deduplication with set")
    func entryDeduplicationWithSet() {
        let entry1 = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: "dexcom"
        )
        
        let entry2 = NightscoutEntry(
            type: "sgv",
            sgv: 121,  // Different value, same device/time
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: "dexcom"
        )
        
        let entry3 = NightscoutEntry(
            type: "sgv",
            sgv: 130,
            dateString: "2026-02-01T12:05:00Z",
            date: 1769861100000,  // Different timestamp
            device: "dexcom"
        )
        
        var entrySet: Set<NightscoutEntry> = []
        entrySet.insert(entry1)
        entrySet.insert(entry2)  // Should be deduplicated
        entrySet.insert(entry3)
        
        #expect(entrySet.count == 2)  // Only 2 unique entries
    }
    
    @Test("treatment deduplication with set")
    func treatmentDeduplicationWithSet() {
        let treatment1 = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5,
            enteredBy: "Loop"
        )
        
        let treatment2 = NightscoutTreatment(
            eventType: "Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.6,  // Different insulin, same source/time
            enteredBy: "Loop"
        )
        
        let treatment3 = NightscoutTreatment(
            eventType: "Carb Correction",
            created_at: "2026-02-01T12:00:00Z",
            carbs: 30,
            enteredBy: "Loop"
        )
        
        var treatmentSet: Set<NightscoutTreatment> = []
        treatmentSet.insert(treatment1)
        treatmentSet.insert(treatment2)  // Should be deduplicated
        treatmentSet.insert(treatment3)  // Different event type, should be kept
        
        #expect(treatmentSet.count == 2)  // Only 2 unique treatments
    }
    
    // MARK: - SyncIdentifierGenerator
    
    @Test("sync identifier generator for entry")
    func syncIdentifierGeneratorForEntry() {
        let id = SyncIdentifierGenerator.forEntry(date: 1769860800000, type: "sgv", device: "dexcom")
        #expect(id == "dexcom:sgv:1769860800000")
    }
    
    @Test("sync identifier generator for treatment")
    func syncIdentifierGeneratorForTreatment() {
        let id = SyncIdentifierGenerator.forTreatment(createdAt: "2026-02-01T12:00:00Z", eventType: "Bolus", enteredBy: "T1Pal")
        #expect(id == "T1Pal:Bolus:2026-02-01T12:00:00Z")
    }
    
    @Test("sync identifier generator for device status")
    func syncIdentifierGeneratorForDeviceStatus() {
        let id = SyncIdentifierGenerator.forDeviceStatus(device: "T1PalDemo", createdAt: "2026-02-01T12:00:00Z")
        #expect(id == "T1PalDemo:devicestatus:2026-02-01T12:00:00Z")
    }
    
    @Test("sync identifier generator unique")
    func syncIdentifierGeneratorUnique() {
        let id1 = SyncIdentifierGenerator.unique(prefix: "test")
        let id2 = SyncIdentifierGenerator.unique(prefix: "test")
        
        #expect(id1.hasPrefix("test:"))
        #expect(id2.hasPrefix("test:"))
        #expect(id1 != id2)  // UUIDs should be different
    }
}
