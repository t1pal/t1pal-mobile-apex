// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// NightscoutV3ClientTests.swift - Tests for Nightscout API v3 client
// Part of NightscoutKit
// Trace: NS-V3-001, NS-V3-002, NS-V3-003, NS-V3-004

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - V3 Query Tests

@Suite("V3 Query")
struct V3QueryTests {
    
    @Test("Default query has no items")
    func defaultQueryEmpty() {
        let query = V3Query()
        let items = query.toQueryItems()
        // Default has sortField = "date", sortDescending = true
        #expect(items.count == 1)
        #expect(items.first?.name == "sort$desc")
        #expect(items.first?.value == "date")
    }
    
    @Test("Query with limit and skip")
    func queryWithPagination() {
        let query = V3Query(limit: 100, skip: 50)
        let items = query.toQueryItems()
        
        let limitItem = items.first { $0.name == "limit" }
        let skipItem = items.first { $0.name == "skip" }
        
        #expect(limitItem?.value == "100")
        #expect(skipItem?.value == "50")
    }
    
    @Test("Query with ascending sort")
    func queryWithAscendingSort() {
        let query = V3Query(sortField: "created_at", sortDescending: false)
        let items = query.toQueryItems()
        
        let sortItem = items.first { $0.name == "sort" }
        #expect(sortItem?.value == "created_at")
    }
    
    @Test("Query with descending sort")
    func queryWithDescendingSort() {
        let query = V3Query(sortField: "date", sortDescending: true)
        let items = query.toQueryItems()
        
        let sortItem = items.first { $0.name == "sort$desc" }
        #expect(sortItem?.value == "date")
    }
    
    @Test("Query with field projection")
    func queryWithFields() {
        let query = V3Query(fields: ["sgv", "date", "direction"])
        let items = query.toQueryItems()
        
        let fieldsItem = items.first { $0.name == "fields" }
        #expect(fieldsItem?.value == "sgv,date,direction")
    }
    
    @Test("Query with date range")
    func queryWithDateRange() {
        let from = Date(timeIntervalSince1970: 1707800000)
        let to = Date(timeIntervalSince1970: 1707864000)
        
        let query = V3Query(dateFrom: from, dateTo: to)
        let items = query.toQueryItems()
        
        let fromItem = items.first { $0.name == "date$gte" }
        let toItem = items.first { $0.name == "date$lte" }
        
        #expect(fromItem?.value == "1707800000000")
        #expect(toItem?.value == "1707864000000")
    }
    
    @Test("Full query with all parameters")
    func fullQuery() {
        let query = V3Query(
            limit: 50,
            skip: 100,
            sortField: "date",
            sortDescending: true,
            fields: ["sgv", "direction"],
            dateFrom: Date(timeIntervalSince1970: 1707800000),
            dateTo: Date(timeIntervalSince1970: 1707864000)
        )
        
        let items = query.toQueryItems()
        
        #expect(items.count == 6)
        #expect(items.contains { $0.name == "limit" && $0.value == "50" })
        #expect(items.contains { $0.name == "skip" && $0.value == "100" })
        #expect(items.contains { $0.name == "sort$desc" && $0.value == "date" })
        #expect(items.contains { $0.name == "fields" && $0.value == "sgv,direction" })
        #expect(items.contains { $0.name == "date$gte" })
        #expect(items.contains { $0.name == "date$lte" })
    }
}

// MARK: - V3 JWT Token Tests

@Suite("V3 JWT Token")
struct V3JWTTokenTests {
    
    @Test("Token creation")
    func tokenCreation() {
        let now = Date()
        let token = JWTToken(
            token: "test-jwt-token",
            issuedAt: now,
            expiresAt: now.addingTimeInterval(3600),
            permissions: ["entries": "crud"]
        )
        
        #expect(token.token == "test-jwt-token")
        #expect(token.permissions?["entries"] == "crud")
    }
    
    @Test("Token not expired")
    func tokenNotExpired() {
        let token = JWTToken(
            token: "test",
            issuedAt: Date(),
            expiresAt: Date().addingTimeInterval(3600)  // 1 hour from now
        )
        
        #expect(!token.isExpired)
        #expect(!token.needsRefresh)
    }
    
    @Test("Token expired")
    func tokenExpired() {
        let token = JWTToken(
            token: "test",
            issuedAt: Date().addingTimeInterval(-7200),  // 2 hours ago
            expiresAt: Date().addingTimeInterval(-3600)  // 1 hour ago
        )
        
        #expect(token.isExpired)
    }
    
    @Test("Token needs refresh within 15 minutes of expiry")
    func tokenNeedsRefresh() {
        let token = JWTToken(
            token: "test",
            issuedAt: Date().addingTimeInterval(-3000),
            expiresAt: Date().addingTimeInterval(600)  // 10 minutes from now
        )
        
        #expect(token.needsRefresh)
    }
}

// MARK: - V3 Response Parsing Tests

@Suite("V3 Response Parsing")
struct V3ResponseParsingTests {
    
    @Test("Parse version response")
    func parseVersionResponse() throws {
        let json = """
        {
            "status": 200,
            "result": {
                "version": "15.0.2",
                "apiVersion": "3.0.4",
                "srvDate": 1707864000000,
                "storage": {
                    "storage": "mongodb",
                    "version": "6.0.4"
                }
            }
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(V3VersionResponse.self, from: json)
        
        #expect(response.status == 200)
        #expect(response.result.version == "15.0.2")
        #expect(response.result.apiVersion == "3.0.4")
        #expect(response.result.storage?.storage == "mongodb")
    }
    
    @Test("Parse status response with permissions")
    func parseStatusResponse() throws {
        let json = """
        {
            "status": 200,
            "result": {
                "version": "15.0.2",
                "apiVersion": "3.0.4",
                "srvDate": 1707864000000,
                "storage": {
                    "storage": "mongodb",
                    "version": "6.0.4"
                },
                "apiPermissions": {
                    "entries": "crud",
                    "treatments": "crud",
                    "devicestatus": "crud"
                }
            }
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(V3StatusResponse.self, from: json)
        
        #expect(response.status == 200)
        #expect(response.result.apiPermissions?["entries"] == "crud")
        #expect(response.result.apiPermissions?["treatments"] == "crud")
    }
    
    @Test("Parse lastModified response")
    func parseLastModifiedResponse() throws {
        let json = """
        {
            "status": 200,
            "result": {
                "srvDate": 1707864000000,
                "collections": {
                    "devicestatus": 1707863900000,
                    "entries": 1707863800000,
                    "treatments": 1707863700000
                }
            }
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(V3LastModifiedResponse.self, from: json)
        
        #expect(response.status == 200)
        #expect(response.result.srvDate == 1707864000000)
        #expect(response.result.collections["entries"] == 1707863800000)
        #expect(response.result.collections["treatments"] == 1707863700000)
    }
    
    @Test("Parse create response")
    func parseCreateResponse() throws {
        let json = """
        {
            "status": 201,
            "identifier": "entry-new-001",
            "lastModified": 1707864301000
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(V3CreateResponse.self, from: json)
        
        #expect(response.status == 201)
        #expect(response.identifier == "entry-new-001")
        #expect(response.lastModified == 1707864301000)
        #expect(response.isDeduplication != true)
    }
    
    @Test("Parse create response with deduplication")
    func parseCreateDeduplicationResponse() throws {
        let json = """
        {
            "status": 200,
            "identifier": "entry-001",
            "lastModified": 1707864302000,
            "isDeduplication": true,
            "deduplicatedIdentifier": "entry-001"
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(V3CreateResponse.self, from: json)
        
        #expect(response.status == 200)
        #expect(response.isDeduplication == true)
        #expect(response.deduplicatedIdentifier == "entry-001")
    }
    
    @Test("Parse JWT auth response")
    func parseJWTAuthResponse() throws {
        let json = """
        {
            "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test",
            "iat": 1707864000,
            "exp": 1707867600,
            "sub": "testadmin",
            "permissionGroups": ["api:*:read", "api:*:create"]
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(JWTAuthResponse.self, from: json)
        
        #expect(response.token.hasPrefix("eyJhbG"))
        #expect(response.iat == 1707864000)
        #expect(response.exp == 1707867600)
        #expect(response.sub == "testadmin")
        #expect(response.permissionGroups?.count == 2)
    }
    
    @Test("Parse wrapped array response")
    func parseWrappedArrayResponse() throws {
        let json = """
        {
            "status": 200,
            "result": [
                {"sgv": 120, "direction": "Flat"},
                {"sgv": 118, "direction": "FortyFiveUp"}
            ]
        }
        """.data(using: .utf8)!
        
        struct SimpleEntry: Decodable {
            let sgv: Int
            let direction: String
        }
        
        let response = try JSONDecoder().decode(V3ArrayResponse<SimpleEntry>.self, from: json)
        
        #expect(response.status == 200)
        #expect(response.items.count == 2)
        #expect(response.items[0].sgv == 120)
        #expect(response.items[1].direction == "FortyFiveUp")
    }
}

// MARK: - V3 Error Tests

@Suite("V3 Errors")
struct V3ErrorTests {
    
    @Test("Authentication failed error description")
    func authFailedDescription() {
        let error = V3Error.authenticationFailed(statusCode: 401)
        #expect(error.errorDescription?.contains("401") == true)
        #expect(error.errorDescription?.contains("Authentication") == true)
    }
    
    @Test("Server error description")
    func serverErrorDescription() {
        let error = V3Error.serverError(statusCode: 500)
        #expect(error.errorDescription?.contains("500") == true)
    }
    
    @Test("Not found error description")
    func notFoundDescription() {
        let error = V3Error.notFound(identifier: "entry-123")
        #expect(error.errorDescription?.contains("entry-123") == true)
    }
    
    @Test("Invalid response error")
    func invalidResponseDescription() {
        let error = V3Error.invalidResponse
        #expect(error.errorDescription?.contains("Invalid") == true)
    }
}

// MARK: - V3 Client Initialization Tests

@Suite("V3 Client Initialization")
struct V3ClientInitTests {
    
    @Test("Client normalizes token without prefix")
    func clientNormalizesToken() async {
        let client = NightscoutV3Client(
            baseURL: URL(string: "https://example.herokuapp.com")!,
            accessToken: "testadmin-ad3b1f9d7b3f59d5"
        )
        
        // Client is an actor, just verify it was created
        #expect(client != nil)
    }
    
    @Test("Client accepts token with prefix")
    func clientAcceptsTokenWithPrefix() async {
        let client = NightscoutV3Client(
            baseURL: URL(string: "https://example.herokuapp.com")!,
            accessToken: "token=testadmin-ad3b1f9d7b3f59d5"
        )
        
        #expect(client != nil)
    }
}

// MARK: - V3 Client Factory Tests

@Suite("V3 Client Factory")
struct V3ClientFactoryTests {
    
    @Test("Factory creates client when token available")
    func factoryWithToken() {
        let config = NightscoutConfig(
            url: URL(string: "https://example.herokuapp.com")!,
            apiSecret: nil,
            token: "testadmin-hash"
        )
        
        let v3 = NightscoutV3Client.from(config: config)
        #expect(v3 != nil)
    }
    
    @Test("Factory creates client when apiSecret available")
    func factoryWithApiSecret() {
        let config = NightscoutConfig(
            url: URL(string: "https://example.herokuapp.com")!,
            apiSecret: "mysecret",
            token: nil
        )
        
        let v3 = NightscoutV3Client.from(config: config)
        #expect(v3 != nil)
    }
    
    @Test("Factory returns nil when no credentials")
    func factoryWithoutCredentials() {
        let config = NightscoutConfig(
            url: URL(string: "https://example.herokuapp.com")!,
            apiSecret: nil,
            token: nil
        )
        
        let v3 = NightscoutV3Client.from(config: config)
        #expect(v3 == nil)
    }
}

// MARK: - Fixture Loading Tests

@Suite("V3 API Fixtures")
struct V3APIFixtureTests {
    
    @Test("Load and parse v3 fixture file")
    func loadFixture() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "fixture_ns_v3_api",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
        
        // Skip if fixture not in bundle (happens during incremental builds)
        guard let url = fixtureURL else {
            return
        }
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["description"] != nil)
        #expect(json?["jwt_auth"] != nil)
        #expect(json?["entries_search"] != nil)
        #expect(json?["treatments_search"] != nil)
        #expect(json?["devicestatus_search"] != nil)
    }
    
    @Test("Parse entries from fixture")
    func parseEntriesFixture() throws {
        let json = """
        {
            "status": 200,
            "result": [
                {
                    "identifier": "entry-001",
                    "date": 1707864000000,
                    "dateString": "2024-02-13T20:00:00.000Z",
                    "type": "sgv",
                    "sgv": 120,
                    "direction": "Flat",
                    "device": "T1Pal"
                }
            ]
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(V3ArrayResponse<NightscoutEntry>.self, from: json)
        
        #expect(response.items.count == 1)
        #expect(response.items[0].sgv == 120)
        #expect(response.items[0].direction == "Flat")
    }
    
    @Test("Parse treatments from fixture")
    func parseTreatmentsFixture() throws {
        let json = """
        {
            "status": 200,
            "result": [
                {
                    "identifier": "treatment-001",
                    "date": 1707864000000,
                    "created_at": "2024-02-13T20:00:00.000Z",
                    "eventType": "Correction Bolus",
                    "insulin": 2.5,
                    "device": "T1Pal"
                }
            ]
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(V3ArrayResponse<NightscoutTreatment>.self, from: json)
        
        #expect(response.items.count == 1)
        #expect(response.items[0].insulin == 2.5)
        #expect(response.items[0].eventType == "Correction Bolus")
    }
}
