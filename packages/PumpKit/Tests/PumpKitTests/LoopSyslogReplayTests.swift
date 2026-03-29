// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopSyslogReplayTests.swift
// PumpKitTests
//
// Integration tests using real Loop BLE captures from iOS syslog.
// These fixtures provide ground truth for RileyLink command/response patterns.
//
// Trace: TEST-FIXTURE-001, MDT-VERIFY-001

import Testing
import Foundation
@testable import PumpKit

/// Tests that replay Loop syslog captures to verify our implementation matches
@Suite("LoopSyslogReplayTests")
struct LoopSyslogReplayTests {
    
    // MARK: - Fixture Loading
    
    struct SyslogFixture: Codable {
        let metadata: Metadata
        let characteristics: Characteristics
        let session: [SessionEvent]
        let analysis: Analysis
        
        struct Metadata: Codable {
            let captureDate: String
            let source: String
            let app: String
            let operations: [String]
        }
        
        struct Characteristics: Codable {
            let data: CharacteristicInfo
            let responseCount: CharacteristicInfo
            let firmwareVersion: CharacteristicInfo
            
            struct CharacteristicInfo: Codable {
                let uuid: String
                let handle: String
                let value: String?
                let decoded: String?
            }
        }
        
        struct SessionEvent: Codable {
            let timestamp: String
            let operation: String
            let command: CommandData?
            let response: ResponseData?
            let responseCount: String
            
            struct CommandData: Codable {
                let hex: String
                let notes: String?
            }
            
            struct ResponseData: Codable {
                let hex: String
                let notes: String?
            }
        }
        
        struct Analysis: Codable {
            let pattern: String
            let responseCountSequence: [String]
            let observations: [String]
        }
    }
    
    func loadFixture(_ name: String) throws -> SyslogFixture {
        // Use absolute path for now - SPM test resources require Package.swift changes
        // TODO: CONFORM-001 - Add proper SPM resource handling
        let fixtureURL = URL(fileURLWithPath: "/home/bewest/src/t1pal-mobile-workspace/packages/PumpKit/Tests/PumpKitTests/Fixtures/loop-syslog-captures/\(name).json")
        
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw FixtureError.notFound(name)
        }
        
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(SyslogFixture.self, from: data)
    }
    
    enum FixtureError: Error {
        case notFound(String)
    }
    
    // MARK: - Tests
    
    /// TEST-FIXTURE-001: Verify fixture loads correctly
    @Test("Load pump suspend/resume fixture")
    func loadPumpSuspendResumeFixture() throws {
        let fixture = try loadFixture("2026-02-10-pump-suspend-resume")
        
        #expect(fixture.metadata.app == "Loop (com.medicaldatanetworks.loop-denim.Loop)")
        #expect(fixture.metadata.operations == ["suspend", "resume"])
        #expect(fixture.characteristics.data.handle == "0x0011")
        #expect(fixture.characteristics.responseCount.handle == "0x0014")
        #expect(fixture.session.count == 5)
    }
    
    /// TEST-FIXTURE-002: Verify responseCount increments correctly
    @Test("Response count sequence")
    func responseCountSequence() throws {
        let fixture = try loadFixture("2026-02-10-pump-suspend-resume")
        
        let expectedSequence = ["06", "07", "08", "09", "0A"]
        #expect(fixture.analysis.responseCountSequence == expectedSequence)
        
        // Verify each event has incrementing responseCount
        for (index, event) in fixture.session.enumerated() {
            #expect(event.responseCount == expectedSequence[index])
        }
    }
    
    /// TEST-FIXTURE-003: Verify command bytes are valid 4b6b
    @Test("Command bytes 4b6b valid")
    func commandBytes4b6bValid() throws {
        let fixture = try loadFixture("2026-02-10-pump-suspend-resume")
        
        // First event should have a command
        guard let command = fixture.session.first?.command else {
            Issue.record("First event should have command data")
            return
        }
        
        let commandData = Data(hexString: command.hex)
        #expect(commandData != nil)
        #expect((commandData?.count ?? 0) > 10)
        
        // First byte DD indicates 4b6b encoded data starting with valid nibble
        #expect(commandData?.first == 0xDD)
    }
    
    /// TEST-FIXTURE-004: Verify response bytes can be 4b6b decoded
    @Test("Response bytes 4b6b decode")
    func responseBytes4b6bDecode() throws {
        let fixture = try loadFixture("2026-02-10-pump-suspend-resume")
        
        // Get a response event
        guard let response = fixture.session[1].response else {
            Issue.record("Second event should have response data")
            return
        }
        
        guard let responseData = Data(hexString: response.hex) else {
            Issue.record("Response hex should be valid")
            return
        }
        
        // RFPacket format: [RSSI][packetCounter][4b6b data...]
        // Skip the 2-byte header like RFPacket does
        guard responseData.count > 2 else {
            Issue.record("Response too short for RFPacket header")
            return
        }
        let encodedData = responseData.dropFirst(2)
        
        // Try to decode with MinimedPacket
        let packet = MinimedPacket(encodedData: Data(encodedData))
        #expect(packet != nil)
        
        if let packet = packet {
            #expect(packet.data.count > 0)
        }
    }
    
    /// TEST-FIXTURE-005: Verify firmware version parsing
    @Test("Firmware version parsing")
    func firmwareVersionParsing() throws {
        let fixture = try loadFixture("2026-02-10-pump-suspend-resume")
        
        #expect(fixture.characteristics.firmwareVersion.decoded == "ble_rfspy 2.0")
        
        // Verify hex decodes to the string
        if let hexValue = fixture.characteristics.firmwareVersion.value,
           let data = Data(hexString: hexValue),
           let decoded = String(data: data, encoding: .utf8) {
            #expect(decoded == "ble_rfspy 2.0")
        }
    }
}

// Data hex extension now in TestHelpers.swift
