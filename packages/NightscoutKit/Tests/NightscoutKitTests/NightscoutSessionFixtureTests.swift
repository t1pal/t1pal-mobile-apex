// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutSessionFixtureTests.swift
// NightscoutKit
//
// Conformance tests for NS-SESSION protocol sequence fixtures
// Task: BATCH-NS-SESSION (NS-SESSION-001..005)

import Foundation
import Testing
@testable import NightscoutKit

private func loadFixture(_ name: String) throws -> [String: Any] {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw FixtureError.notFound(name)
    }
    let data = try Data(contentsOf: url)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    return json
}

private enum FixtureError: Error {
    case notFound(String)
}

@Suite("NS-SESSION-001: Entries Sync")
struct EntriesSyncFixtureTests {
    
    @Test("fixture structure is valid")
    func fixtureStructure() throws {
        let fixture = try loadFixture("fixture_ns_entries_sync")
        
        #expect(fixture["_task"] as? String == "NS-SESSION-001")
        #expect(fixture["_source"] != nil)
        #expect(fixture["_description"] != nil)
        #expect(fixture["_format"] != nil)
        
        let vectors = fixture["test_vectors"] as? [[String: Any]]
        #expect(vectors != nil)
        #expect((vectors?.count ?? 0) >= 3)
        
        let schema = fixture["entry_schema"] as? [String: Any]
        #expect(schema != nil)
        let required = schema?["required"] as? [String]
        #expect(required?.contains("type") ?? false)
        #expect(required?.contains("sgv") ?? false)
        #expect(required?.contains("dateString") ?? false)
    }
    
    @Test("full sequence validates")
    func fullSequence() throws {
        let fixture = try loadFixture("fixture_ns_entries_sync")
        let vectors = fixture["test_vectors"] as! [[String: Any]]
        
        let fullSequence = vectors.first { ($0["id"] as? String) == "entries_sync_full_sequence" }
        #expect(fullSequence != nil)
        
        let steps = fullSequence!["steps"] as! [[String: Any]]
        #expect(steps.count == 5)
        
        // Step 1: GET request
        #expect(steps[0]["direction"] as? String == "tx")
        #expect(steps[0]["method"] as? String == "GET")
        #expect(steps[0]["path"] as? String == "/api/v1/entries")
        
        // Step 2: 200 response
        #expect(steps[1]["direction"] as? String == "rx")
        #expect(steps[1]["status"] as? Int == 200)
        
        // Step 3: Client-side deduplication
        #expect(steps[2]["action"] as? String == "dedupe")
        #expect(steps[2]["new_count"] as? Int == 5)
        
        // Step 4: POST new entries
        #expect(steps[3]["direction"] as? String == "tx")
        #expect(steps[3]["method"] as? String == "POST")
        
        // Step 5: Upload confirmation
        #expect(steps[4]["direction"] as? String == "rx")
        #expect(steps[4]["status"] as? Int == 200)
    }
}

@Suite("NS-SESSION-002: Treatments Sync")
struct TreatmentsSyncFixtureTests {
    
    @Test("fixture structure is valid")
    func fixtureStructure() throws {
        let fixture = try loadFixture("fixture_ns_treatments_sync")
        
        #expect(fixture["_task"] as? String == "NS-SESSION-002")
        
        let eventTypes = fixture["treatment_event_types"] as? [String]
        #expect(eventTypes != nil)
        #expect((eventTypes?.count ?? 0) >= 20)
        #expect(eventTypes?.contains("Temp Basal") ?? false)
        #expect(eventTypes?.contains("Meal Bolus") ?? false)
        #expect(eventTypes?.contains("Correction Bolus") ?? false)
        
        let vectors = fixture["test_vectors"] as? [[String: Any]]
        #expect((vectors?.count ?? 0) >= 4)
    }
    
    @Test("bolus wizard treatment validates")
    func bolusWizard() throws {
        let fixture = try loadFixture("fixture_ns_treatments_sync")
        let vectors = fixture["test_vectors"] as! [[String: Any]]
        
        let bolusWizard = vectors.first { ($0["id"] as? String) == "treatments_bolus_wizard" }
        #expect(bolusWizard != nil)
        
        let steps = bolusWizard!["steps"] as! [[String: Any]]
        let postStep = steps[0]
        let body = postStep["body"] as! [[String: Any]]
        let treatment = body[0]
        
        let calc = treatment["bolusCalculation"] as! [String: Any]
        #expect(calc["carbs"] != nil)
        #expect(calc["ic"] != nil)
        #expect(calc["bg"] != nil)
        #expect(calc["isf"] != nil)
        #expect(calc["totalBolus"] != nil)
        #expect(calc["iob"] != nil)
        #expect(calc["finalBolus"] != nil)
    }
}

@Suite("NS-SESSION-003: Profile Round-Trip")
struct ProfileRoundTripFixtureTests {
    
    @Test("fixture structure is valid")
    func fixtureStructure() throws {
        let fixture = try loadFixture("fixture_ns_profile_round_trip")
        
        #expect(fixture["_task"] as? String == "NS-SESSION-003")
        
        let schema = fixture["profile_schema"] as? [String: Any]
        #expect(schema != nil)
        
        let storeFields = schema?["store_fields"] as? [String]
        #expect(storeFields?.contains("dia") ?? false)
        #expect(storeFields?.contains("carbratio") ?? false)
        #expect(storeFields?.contains("sens") ?? false)
        #expect(storeFields?.contains("basal") ?? false)
    }
    
    @Test("mmol conversion is accurate")
    func mmolConversion() throws {
        let fixture = try loadFixture("fixture_ns_profile_round_trip")
        let vectors = fixture["test_vectors"] as! [[String: Any]]
        
        let mmolVector = vectors.first { ($0["id"] as? String) == "profile_mmol_conversion" }
        #expect(mmolVector != nil)
        
        let steps = mmolVector!["steps"] as! [[String: Any]]
        let convertStep = steps.first { ($0["action"] as? String) == "convert" }
        #expect(convertStep != nil)
        
        let conversions = convertStep!["conversions"] as! [String: [String: Double]]
        
        let sens = conversions["sens"]!
        #expect(sens["mmol"] == 2.8)
        let expectedMgdl = 2.8 * 18.0182
        let diff = abs(sens["mgdl"]! - expectedMgdl)
        #expect(diff < 0.1)
    }
}

@Suite("NS-SESSION-004: WebSocket Session")
struct WebSocketSessionFixtureTests {
    
    @Test("fixture structure is valid")
    func fixtureStructure() throws {
        let fixture = try loadFixture("fixture_ns_websocket_session")
        
        #expect(fixture["_task"] as? String == "NS-SESSION-004")
        
        let enginePackets = fixture["engine_io_packets"] as? [String: String]
        #expect(enginePackets?["0"] == "OPEN")
        #expect(enginePackets?["2"] == "PING")
        #expect(enginePackets?["3"] == "PONG")
        
        let socketPackets = fixture["socket_io_packets"] as? [String: String]
        #expect(socketPackets?["0"] == "CONNECT")
        #expect(socketPackets?["2"] == "EVENT")
    }
    
    @Test("connect sequence validates")
    func connectSequence() throws {
        let fixture = try loadFixture("fixture_ns_websocket_session")
        let vectors = fixture["test_vectors"] as! [[String: Any]]
        
        let connectSequence = vectors.first { ($0["id"] as? String) == "websocket_connect_sequence" }
        #expect(connectSequence != nil)
        
        let steps = connectSequence!["steps"] as! [[String: Any]]
        #expect(steps.count >= 8)
        
        let pollingSteps = steps.filter { ($0["transport"] as? String) == "polling" }
        let wsSteps = steps.filter { ($0["transport"] as? String) == "websocket" }
        #expect(pollingSteps.count >= 1)
        #expect(wsSteps.count >= 5)
    }
    
    @Test("socket events are documented")
    func socketEvents() throws {
        let fixture = try loadFixture("fixture_ns_websocket_session")
        
        let events = fixture["socket_events"] as! [String: [String]]
        
        let clientEvents = events["client_to_server"]!
        #expect(clientEvents.contains("authorize"))
        #expect(clientEvents.contains("subscribe"))
        
        let serverEvents = events["server_to_client"]!
        #expect(serverEvents.contains("dataUpdate"))
        #expect(serverEvents.contains("alarm"))
        #expect(serverEvents.contains("announcement"))
    }
}

@Suite("NS-SESSION-005: Remote Command")
struct RemoteCommandFixtureTests {
    
    @Test("fixture structure is valid")
    func fixtureStructure() throws {
        let fixture = try loadFixture("fixture_ns_remote_command")
        
        #expect(fixture["_task"] as? String == "NS-SESSION-005")
        
        let otpConfig = fixture["otp_config"] as? [String: Any]
        #expect(otpConfig?["algorithm"] as? String == "SHA1")
        #expect(otpConfig?["digits"] as? Int == 6)
        #expect(otpConfig?["period"] as? Int == 30)
        
        let commandTypes = fixture["remote_command_types"] as! [String: [String]]
        let otpRequired = commandTypes["otp_required"]!
        let noOtp = commandTypes["no_otp_required"]!
        
        #expect(otpRequired.contains("Remote Bolus"))
        #expect(otpRequired.contains("Suspend Pump"))
        #expect(noOtp.contains("Remote Carbs"))
        #expect(noOtp.contains("Note"))
    }
    
    @Test("remote bolus with OTP validates")
    func remoteBolusWithOTP() throws {
        let fixture = try loadFixture("fixture_ns_remote_command")
        let vectors = fixture["test_vectors"] as! [[String: Any]]
        
        let bolusVector = vectors.first { ($0["id"] as? String) == "remote_bolus_command" }
        #expect(bolusVector != nil)
        
        let steps = bolusVector!["steps"] as! [[String: Any]]
        
        // Step 1: OTP generation
        let otpStep = steps[0]
        #expect(otpStep["action"] as? String == "generate_otp")
        #expect(otpStep["secret"] != nil)
        #expect(otpStep["digits"] as? Int == 6)
        
        // Step 2: POST with OTP
        let postStep = steps[1]
        let body = postStep["body"] as! [[String: Any]]
        #expect(body[0]["otp"] != nil)
        #expect(body[0]["isRemote"] as? Bool == true)
        
        // Poll for acknowledgment
        let pollStep = steps.first { ($0["action"] as? String) == "poll_ack" }
        #expect(pollStep != nil)
    }
    
    @Test("invalid OTP is rejected")
    func commandRejectedInvalidOTP() throws {
        let fixture = try loadFixture("fixture_ns_remote_command")
        let vectors = fixture["test_vectors"] as! [[String: Any]]
        
        let rejectedVector = vectors.first { ($0["id"] as? String) == "remote_command_rejected_invalid_otp" }
        #expect(rejectedVector != nil)
        
        let steps = rejectedVector!["steps"] as! [[String: Any]]
        let response = steps[1]
        
        #expect(response["status"] as? Int == 401)
        let body = response["body"] as! [String: Any]
        #expect(body["message"] as? String == "Invalid OTP")
    }
    
    @Test("command status values are complete")
    func commandStatusValues() throws {
        let fixture = try loadFixture("fixture_ns_remote_command")
        
        let statusValues = fixture["command_status_values"] as! [String]
        #expect(statusValues.contains("pending"))
        #expect(statusValues.contains("acknowledged"))
        #expect(statusValues.contains("delivered"))
        #expect(statusValues.contains("failed"))
        #expect(statusValues.contains("expired"))
    }
}
