// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutConfigurationValidatorTests.swift
// T1Pal Mobile
//
// Tests for Nightscout URL and credential validation
// Requirements: APP-STATES-009

import XCTest
@testable import NightscoutKit

final class NightscoutConfigurationValidatorTests: XCTestCase {
    
    var validator: NightscoutConfigurationValidator!
    
    override func setUp() {
        super.setUp()
        validator = NightscoutConfigurationValidator()
    }
    
    // MARK: - URL Validation Tests
    
    func testValidHTTPSURL() {
        let result = validator.validateURL("https://my-nightscout.herokuapp.com")
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
    }
    
    func testValidHTTPSURLWithTrailingSlash() {
        let result = validator.validateURL("https://my-nightscout.herokuapp.com/")
        XCTAssertTrue(result.isValid)
    }
    
    func testValidHTTPSURLWithPort() {
        let result = validator.validateURL("https://nightscout.example.com:1337")
        XCTAssertTrue(result.isValid)
    }
    
    func testEmptyURLFails() {
        let result = validator.validateURL("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .urlEmpty)
    }
    
    func testNilURLFails() {
        let result = validator.validateURL(nil)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .urlEmpty)
    }
    
    func testWhitespaceOnlyURLFails() {
        let result = validator.validateURL("   ")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .urlEmpty)
    }
    
    func testURLWithoutScheme() {
        let result = validator.validateURL("my-nightscout.herokuapp.com")
        XCTAssertFalse(result.isValid)
        // Should fail with invalid format (no scheme)
        XCTAssertTrue(result.errors.contains(where: {
            if case .urlInvalidFormat = $0 { return true }
            return false
        }))
    }
    
    func testURLWithIncorrectAPIPath() {
        let result = validator.validateURL("https://my-nightscout.herokuapp.com/api/v1")
        // Should warn about path but still technically valid URL
        XCTAssertTrue(result.errors.contains(where: {
            if case .urlContainsPath = $0 { return true }
            return false
        }))
    }
    
    func testURLWithEntriesPath() {
        let result = validator.validateURL("https://my-nightscout.herokuapp.com/entries")
        XCTAssertTrue(result.errors.contains(where: {
            if case .urlContainsPath("/entries") = $0 { return true }
            return false
        }))
    }
    
    func testURLWithWhitespace() {
        let result = validator.validateURL("  https://my-nightscout.herokuapp.com  ")
        XCTAssertTrue(result.isValid)
    }
    
    #if !DEBUG
    func testHTTPURLFailsInRelease() {
        let result = validator.validateURL("http://my-nightscout.herokuapp.com")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .urlNotHTTPS)
    }
    #endif
    
    // MARK: - API Secret Validation Tests
    
    func testValidAPISecret() {
        let result = validator.validateAPISecretFormat("my-super-secret-password")
        XCTAssertTrue(result.isValid)
    }
    
    func testValidSHA1HashedSecret() {
        // SHA1 hash is 40 characters
        let result = validator.validateAPISecretFormat("a94a8fe5ccb19ba61c4c0873d391e987982fbbd3")
        XCTAssertTrue(result.isValid)
    }
    
    func testEmptyAPISecretFails() {
        let result = validator.validateAPISecretFormat("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .apiSecretEmpty)
    }
    
    func testNilAPISecretFails() {
        let result = validator.validateAPISecretFormat(nil)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .apiSecretEmpty)
    }
    
    func testShortAPISecretFails() {
        let result = validator.validateAPISecretFormat("short")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .apiSecretInvalidFormat)
    }
    
    func testAPISecretWith12CharactersPass() {
        let result = validator.validateAPISecretFormat("twelve-chars")
        XCTAssertTrue(result.isValid)
    }
    
    // MARK: - Combined Validation Tests
    
    func testValidURLAndSecretAsync() async {
        let result = await validator.validate(
            urlString: "https://my-nightscout.herokuapp.com",
            apiSecret: "my-super-secret",
            checkServer: false
        )
        XCTAssertTrue(result.isValid)
    }
    
    func testInvalidURLStopsEarly() async {
        let result = await validator.validate(
            urlString: "",
            apiSecret: "my-super-secret",
            checkServer: false
        )
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .urlEmpty)
    }
    
    func testInvalidSecretFormat() async {
        let result = await validator.validate(
            urlString: "https://my-nightscout.herokuapp.com",
            apiSecret: "short",
            checkServer: false
        )
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.first, .apiSecretInvalidFormat)
    }
    
    // MARK: - Version Check Tests
    
    func testCurrentVersionSupported() {
        XCTAssertTrue(validator.isVersionSupported("15.0.0"))
    }
    
    func testMinimumVersionSupported() {
        XCTAssertTrue(validator.isVersionSupported("14.0.0"))
    }
    
    func testOldVersionNotSupported() {
        XCTAssertFalse(validator.isVersionSupported("13.0.0"))
    }
    
    func testVersionWithDevSuffix() {
        XCTAssertTrue(validator.isVersionSupported("15.0.0-dev"))
    }
    
    func testVersionWithBuildNumber() {
        XCTAssertTrue(validator.isVersionSupported("14.2.6-2023.01.15"))
    }
    
    func testPartialVersionComparison() {
        XCTAssertTrue(validator.isVersionSupported("14.1"))
        XCTAssertTrue(validator.isVersionSupported("14"))
        XCTAssertFalse(validator.isVersionSupported("13.9.9"))
    }
    
    // MARK: - Validation Result Tests
    
    func testSuccessResultHasServerInfo() {
        let serverInfo = NightscoutValidationResult.ServerInfo(
            version: "15.0.0",
            serverName: "My NS",
            apiVersion: "v3",
            enabledPlugins: ["careportal", "pump"]
        )
        let result = NightscoutValidationResult.success(serverInfo: serverInfo)
        
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.serverInfo?.version, "15.0.0")
        XCTAssertEqual(result.serverInfo?.enabledPlugins.count, 2)
    }
    
    func testFailureResultHasErrors() {
        let result = NightscoutValidationResult.failure([.urlEmpty, .apiSecretEmpty])
        
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertNil(result.serverInfo)
    }
    
    // MARK: - Error Descriptions
    
    func testErrorDescriptions() {
        let errors: [NightscoutValidationError] = [
            .urlEmpty,
            .urlInvalidFormat("test"),
            .urlNotHTTPS,
            .urlContainsPath("/api"),
            .apiSecretEmpty,
            .apiSecretInvalidFormat,
            .serverUnreachable("timeout"),
            .serverInvalidResponse,
            .authenticationFailed,
            .notNightscoutServer,
            .serverVersionTooOld("13.0")
        ]
        
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "Error \(error) should have description")
        }
    }
}
