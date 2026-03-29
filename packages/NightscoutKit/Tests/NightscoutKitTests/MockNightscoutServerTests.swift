// SPDX-License-Identifier: MIT
// NightscoutKit - MockNightscoutServerTests
// Tests for INT-001: Mock Nightscout server for offline testing

import Testing
import Foundation
@testable import NightscoutKit

@Suite("MockNightscoutServer")
struct MockNightscoutServerTests {
    
    // MARK: - Basic Response Tests
    
    @Test("Create JSON response")
    func createJSONResponse() {
        let response = MockNightscoutResponse.json(#"{"test": true}"#)
        
        #expect(response.statusCode == 200)
        #expect(response.headers["Content-Type"] == "application/json")
        #expect(response.data.count > 0)
    }
    
    @Test("Create error response")
    func createErrorResponse() {
        let response = MockNightscoutResponse.error(statusCode: 400, message: "Bad Request")
        
        #expect(response.statusCode == 400)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("400"))
        #expect(body.contains("Bad Request"))
    }
    
    @Test("Unauthorized response")
    func unauthorizedResponse() {
        let response = MockNightscoutResponse.unauthorized
        #expect(response.statusCode == 401)
    }
    
    @Test("Server error response")
    func serverErrorResponse() {
        let response = MockNightscoutResponse.serverError
        #expect(response.statusCode == 500)
    }
    
    @Test("Empty success response")
    func emptySuccessResponse() {
        let response = MockNightscoutResponse.emptySuccess
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body == "[]")
    }
    
    // MARK: - Endpoint Matcher Tests
    
    @Test("Exact matcher")
    func exactMatcher() {
        let matcher = MockEndpointMatcher.exact("/api/v1/entries")
        
        #expect(matcher.matches("/api/v1/entries") == true)
        #expect(matcher.matches("/api/v1/entries/sgv") == false)
        #expect(matcher.matches("/api/v1") == false)
    }
    
    @Test("Prefix matcher")
    func prefixMatcher() {
        let matcher = MockEndpointMatcher.prefix("/api/v1/entries")
        
        #expect(matcher.matches("/api/v1/entries") == true)
        #expect(matcher.matches("/api/v1/entries/sgv") == true)
        #expect(matcher.matches("/api/v1/treatments") == false)
    }
    
    @Test("Regex matcher")
    func regexMatcher() {
        let matcher = MockEndpointMatcher.regex("/api/v1/entries.*count=\\d+")
        
        #expect(matcher.matches("/api/v1/entries?count=10") == true)
        #expect(matcher.matches("/api/v1/entries?count=100") == true)
        #expect(matcher.matches("/api/v1/entries") == false)
    }
    
    @Test("Any matcher")
    func anyMatcher() {
        let matcher = MockEndpointMatcher.any
        
        #expect(matcher.matches("/anything") == true)
        #expect(matcher.matches("/api/v1/entries") == true)
        #expect(matcher.matches("") == true)
    }
    
    // MARK: - Server Request Handling Tests
    
    @Test("Server handles registered endpoint")
    func serverHandlesRegisteredEndpoint() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/status")
        
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("Mock Nightscout"))
    }
    
    @Test("Server returns 404 for unregistered endpoint")
    func serverReturns404ForUnregistered() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(method: "GET", path: "/unknown/endpoint")
        
        #expect(response.statusCode == 404)
    }
    
    @Test("Server records requests")
    func serverRecordsRequests() async {
        let server = MockNightscoutServer()
        
        _ = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        _ = await server.handleRequest(method: "POST", path: "/api/v1/entries", body: "{}".data(using: .utf8))
        
        let history = await server.getRequestHistory()
        #expect(history.count == 2)
        #expect(history[0].method == "GET")
        #expect(history[1].method == "POST")
    }
    
    @Test("Server tracks call count")
    func serverTracksCallCount() async {
        let server = MockNightscoutServer()
        
        _ = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        _ = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        _ = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        
        let count = await server.callCount(method: "GET", path: "entries")
        #expect(count == 3)
    }
    
    @Test("Server wasCalled check")
    func serverWasCalledCheck() async {
        let server = MockNightscoutServer()
        
        let beforeCall = await server.wasCalled(method: "GET", path: "entries")
        #expect(beforeCall == false)
        
        _ = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        
        let afterCall = await server.wasCalled(method: "GET", path: "entries")
        #expect(afterCall == true)
    }
    
    // MARK: - Custom Endpoint Registration Tests
    
    @Test("Register custom GET endpoint")
    func registerCustomGETEndpoint() async {
        let server = MockNightscoutServer()
        
        await server.registerGET("/custom/endpoint", response: .json(#"{"custom": true}"#))
        
        let response = await server.handleRequest(method: "GET", path: "/custom/endpoint")
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("custom"))
    }
    
    @Test("Register custom POST endpoint")
    func registerCustomPOSTEndpoint() async {
        let server = MockNightscoutServer()
        
        await server.registerPOST("/custom/post", response: .json(#"{"posted": true}"#))
        
        let response = await server.handleRequest(method: "POST", path: "/custom/post")
        #expect(response.statusCode == 200)
    }
    
    @Test("Later registration overrides earlier")
    func laterRegistrationOverrides() async {
        let server = MockNightscoutServer()
        
        await server.registerGET("/override", response: .json(#"{"version": 1}"#))
        await server.registerGET("/override", response: .json(#"{"version": 2}"#))
        
        let response = await server.handleRequest(method: "GET", path: "/override")
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("version\": 2") || body.contains("version\":2"))
    }
    
    @Test("Reset clears custom endpoints")
    func resetClearsCustomEndpoints() async {
        let server = MockNightscoutServer()
        
        await server.registerGET("/custom", response: .json("{}"))
        
        // Should work before reset
        var response = await server.handleRequest(method: "GET", path: "/custom")
        #expect(response.statusCode == 200)
        
        await server.reset()
        
        // Should 404 after reset
        response = await server.handleRequest(method: "GET", path: "/custom")
        #expect(response.statusCode == 404)
    }
    
    // MARK: - Default Endpoints Tests
    
    @Test("Default status endpoint")
    func defaultStatusEndpoint() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/status")
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("Mock Nightscout"))
        #expect(body.contains("14.2.6"))
    }
    
    @Test("Default entries endpoint")
    func defaultEntriesEndpoint() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("sgv"))
    }
    
    @Test("Default treatments endpoint")
    func defaultTreatmentsEndpoint() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/treatments")
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("Temp Basal") || body.contains("eventType"))
    }
    
    @Test("Default devicestatus endpoint")
    func defaultDeviceStatusEndpoint() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/devicestatus")
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("loop"))
    }
    
    @Test("Default profile endpoint")
    func defaultProfileEndpoint() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/profile")
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body.contains("defaultProfile"))
    }
    
    // MARK: - POST Endpoints Tests
    
    @Test("POST entries returns success")
    func postEntriesSuccess() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(
            method: "POST",
            path: "/api/v1/entries",
            body: #"[{"sgv": 120}]"#.data(using: .utf8)
        )
        
        #expect(response.statusCode == 200)
    }
    
    @Test("POST treatments returns success")
    func postTreatmentsSuccess() async {
        let server = MockNightscoutServer()
        
        let response = await server.handleRequest(
            method: "POST",
            path: "/api/v1/treatments",
            body: #"[{"eventType": "Bolus"}]"#.data(using: .utf8)
        )
        
        #expect(response.statusCode == 200)
    }
}

@Suite("MockNightscoutData")
struct MockNightscoutDataTests {
    
    @Test("Status JSON is valid")
    func statusJSONIsValid() throws {
        let data = MockNightscoutData.statusJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        #expect(json["status"] as? String == "ok")
        #expect(json["name"] as? String == "Mock Nightscout")
    }
    
    @Test("Entries JSON generates valid array")
    func entriesJSONGeneratesValidArray() throws {
        let data = MockNightscoutData.entriesJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        #expect(json.count == 12)
        #expect(json[0]["sgv"] != nil)
        #expect(json[0]["date"] != nil)
    }
    
    @Test("Low glucose entries scenario")
    func lowGlucoseEntriesScenario() throws {
        let data = MockNightscoutData.lowGlucoseEntries().data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        #expect(json.count == 12)
        
        // Should have low values
        let sgvs = json.compactMap { $0["sgv"] as? Int }
        let minSGV = sgvs.min()!
        #expect(minSGV <= 70)
    }
    
    @Test("High glucose entries scenario")
    func highGlucoseEntriesScenario() throws {
        let data = MockNightscoutData.highGlucoseEntries().data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        #expect(json.count == 12)
        
        // Should have high values
        let sgvs = json.compactMap { $0["sgv"] as? Int }
        let maxSGV = sgvs.max()!
        #expect(maxSGV >= 200)
    }
    
    @Test("Stable glucose entries scenario")
    func stableGlucoseEntriesScenario() throws {
        let data = MockNightscoutData.stableGlucoseEntries(around: 110).data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        #expect(json.count == 12)
        
        // Should have stable values around 110
        let sgvs = json.compactMap { $0["sgv"] as? Int }
        let average = Double(sgvs.reduce(0, +)) / Double(sgvs.count)
        #expect(average >= 105 && average <= 115)
    }
    
    @Test("Treatments JSON has multiple types")
    func treatmentsJSONHasMultipleTypes() throws {
        let data = MockNightscoutData.treatmentsJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        #expect(json.count >= 3)
        
        let eventTypes = json.compactMap { $0["eventType"] as? String }
        #expect(eventTypes.contains("Temp Basal"))
        #expect(eventTypes.contains("Meal Bolus"))
    }
    
    @Test("Device status JSON has loop data")
    func deviceStatusJSONHasLoopData() throws {
        let data = MockNightscoutData.deviceStatusJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        #expect(json.count >= 1)
        #expect(json[0]["loop"] != nil)
        #expect(json[0]["pump"] != nil)
    }
    
    @Test("Profile JSON has required fields")
    func profileJSONHasRequiredFields() throws {
        let data = MockNightscoutData.profileJSON.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        
        #expect(json.count >= 1)
        #expect(json[0]["defaultProfile"] != nil)
        #expect(json[0]["store"] != nil)
    }
}

@Suite("MockNightscoutScenario")
struct MockNightscoutScenarioTests {
    
    @Test("Normal scenario uses default data")
    func normalScenarioUsesDefaultData() async {
        let server = MockNightscoutServer()
        await MockNightscoutScenario.normal.configure(server)
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        #expect(response.statusCode == 200)
    }
    
    @Test("Low glucose scenario returns low values")
    func lowGlucoseScenarioReturnsLowValues() async throws {
        let server = MockNightscoutServer()
        await MockNightscoutScenario.lowGlucose.configure(server)
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        #expect(response.statusCode == 200)
        
        let json = try JSONSerialization.jsonObject(with: response.data) as! [[String: Any]]
        let sgvs = json.compactMap { $0["sgv"] as? Int }
        let minSGV = sgvs.min()!
        #expect(minSGV <= 70)
    }
    
    @Test("Unauthorized scenario returns 401")
    func unauthorizedScenarioReturns401() async {
        let server = MockNightscoutServer()
        await MockNightscoutScenario.unauthorized.configure(server)
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        #expect(response.statusCode == 401)
    }
    
    @Test("Server error scenario returns 500")
    func serverErrorScenarioReturns500() async {
        let server = MockNightscoutServer()
        await MockNightscoutScenario.serverError.configure(server)
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        #expect(response.statusCode == 500)
    }
    
    @Test("No data scenario returns empty array")
    func noDataScenarioReturnsEmptyArray() async {
        let server = MockNightscoutServer()
        await MockNightscoutScenario.noData.configure(server)
        
        let response = await server.handleRequest(method: "GET", path: "/api/v1/entries")
        #expect(response.statusCode == 200)
        let body = String(data: response.data, encoding: .utf8)!
        #expect(body == "[]")
    }
}

@Suite("RecordedRequest")
struct RecordedRequestTests {
    
    @Test("Recorded request stores method and path")
    func recordedRequestStoresMethodAndPath() {
        let request = RecordedRequest(
            method: "POST",
            path: "/api/v1/entries",
            body: nil,
            headers: [:],
            timestamp: Date()
        )
        
        #expect(request.method == "POST")
        #expect(request.path == "/api/v1/entries")
    }
    
    @Test("Recorded request body as string")
    func recordedRequestBodyAsString() {
        let request = RecordedRequest(
            method: "POST",
            path: "/test",
            body: "Hello, World!".data(using: .utf8),
            headers: [:],
            timestamp: Date()
        )
        
        #expect(request.bodyString == "Hello, World!")
    }
    
    @Test("Recorded request body as JSON")
    func recordedRequestBodyAsJSON() {
        struct TestBody: Codable {
            let name: String
            let value: Int
        }
        
        let json = #"{"name": "test", "value": 42}"#
        let request = RecordedRequest(
            method: "POST",
            path: "/test",
            body: json.data(using: .utf8),
            headers: [:],
            timestamp: Date()
        )
        
        let decoded = request.bodyJSON(as: TestBody.self)
        #expect(decoded?.name == "test")
        #expect(decoded?.value == 42)
    }
}
