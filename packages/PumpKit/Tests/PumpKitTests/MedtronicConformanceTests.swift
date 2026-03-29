// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MedtronicConformanceTests.swift
// PumpKitTests
//
// Conformance tests validating PumpKit message implementations against
// real Medtronic protocol captures from tools/medtronic-rf/fixtures/
//
// Trace: SWIFT-RL-004, RL-PROTO-003
//
// These tests ensure our Swift implementation matches the exact byte
// patterns verified to work with real Medtronic hardware.

import Testing
import Foundation
@testable import PumpKit

@Suite("MedtronicConformanceTests")
struct MedtronicConformanceTests {
    
    // MARK: - CarelinkShortMessageBody Tests (SWIFT-RL-002)
    
    @Test("Carelink short message body produces 0x00")
    func carelinkShortMessageBodyProduces0x00() throws {
        let body = CarelinkShortMessageBody()
        
        #expect(CarelinkShortMessageBody.length == 1)
        #expect(body.txData == Data([0x00]))
    }
    
    @Test("Read command uses carelink short message body")
    func readCommandUsesCarelinkShortMessageBody() throws {
        // From fixture_read_model.json: getPumpModel body is [0x00]
        let msg = PumpMessage.readCommand(address: "208850", messageType: .getPumpModel)
        
        #expect(msg.messageType == .getPumpModel)
        #expect(msg.body == Data([0x00]))
    }
    
    // MARK: - PowerOnCarelinkMessageBody Tests (SWIFT-RL-005)
    
    @Test("Power on message body format")
    func powerOnMessageBodyFormat() throws {
        // From fixture_wakeup.json: PowerOn body is [02 01 01] + 62 zeros
        let body = PowerOnCarelinkMessageBody(durationMinutes: 1)
        
        #expect(PowerOnCarelinkMessageBody.length == 65)
        #expect(body.durationMinutes == 1)
        
        let txData = body.txData
        #expect(txData.count == 65)
        
        // First 3 bytes: [numArgs=02][on=01][duration=01]
        #expect(txData[0] == 0x02)
        #expect(txData[1] == 0x01)
        #expect(txData[2] == 0x01)
        
        // Remaining 62 bytes should be zeros
        for i in 3..<65 {
            #expect(txData[i] == 0x00)
        }
    }
    
    @Test("Power on message body with different durations")
    func powerOnMessageBodyWithDifferentDurations() throws {
        let body5min = PowerOnCarelinkMessageBody(durationMinutes: 5)
        #expect(body5min.txData[2] == 0x05)
        
        let body10min = PowerOnCarelinkMessageBody(durationMinutes: 10)
        #expect(body10min.txData[2] == 0x0A)
    }
    
    @Test("Power on from time interval")
    func powerOnFromTimeInterval() throws {
        // 90 seconds should round up to 2 minutes
        let body = PowerOnCarelinkMessageBody(duration: 90)
        #expect(body.durationMinutes == 2)
        #expect(body.txData[2] == 0x02)
    }
    
    @Test("Power on factory method")
    func powerOnFactoryMethod() throws {
        let msg = PumpMessage.powerOn(address: "208850", durationMinutes: 1)
        
        #expect(msg.messageType == .powerOn)
        #expect(msg.body.count == 65)
        #expect(msg.body[0] == 0x02)
        #expect(msg.body[1] == 0x01)
        #expect(msg.body[2] == 0x01)
    }
    
    // MARK: - Address Encoding Tests (SWIFT-RL-003)
    
    @Test("Serial encoded as hex pairs")
    func serialEncodedAsHexPairs() throws {
        // From fixtures: serial "208850" encodes to bytes [0x20, 0x88, 0x50]
        let msg = PumpMessage.readCommand(address: "208850", messageType: .getPumpModel)
        
        // The address property contains the 3 parsed bytes
        #expect(msg.address.count == 3)
        #expect(msg.address[0] == 0x20)
        #expect(msg.address[1] == 0x88)
        #expect(msg.address[2] == 0x50)
    }
    
    // MARK: - Full Message Assembly Tests
    
    @Test("Get pump model message matches fixture")
    func getPumpModelMessageMatchesFixture() throws {
        // From fixture_read_model.json:
        // raw_packet: "a7 20 88 50 8d 00 2b"
        // - A7 = Carelink packet type
        // - 20 88 50 = serial 208850
        // - 8D = getPumpModel
        // - 00 = body (CarelinkShortMessageBody)
        // - 2B = CRC
        
        let msg = PumpMessage.readCommand(address: "208850", messageType: .getPumpModel)
        let txData = msg.txData
        
        // Check structure (without CRC - that's added by MinimedPacket)
        #expect(txData[0] == 0xA7)
        #expect(txData[1] == 0x20)
        #expect(txData[2] == 0x88)
        #expect(txData[3] == 0x50)
        #expect(txData[4] == 0x8D)
        #expect(txData[5] == 0x00)
    }
    
    @Test("Power on message matches fixture")
    func powerOnMessageMatchesFixture() throws {
        // From fixture_wakeup.json:
        // raw_packet for powerOn with duration:
        // "a7 20 88 50 5d 02 01 01 00...00 c5"
        // - A7 = Carelink
        // - 20 88 50 = serial 208850
        // - 5D = powerOn
        // - 02 01 01 + 62 zeros = body
        // - C5 = CRC
        
        let msg = PumpMessage.powerOn(address: "208850", durationMinutes: 1)
        let txData = msg.txData
        
        #expect(txData[0] == 0xA7)
        #expect(txData[1] == 0x20)
        #expect(txData[2] == 0x88)
        #expect(txData[3] == 0x50)
        #expect(txData[4] == 0x5D)
        #expect(txData[5] == 0x02)
        #expect(txData[6] == 0x01)
        #expect(txData[7] == 0x01)
        
        // Total length: 1 (packet type) + 3 (address) + 1 (msg type) + 65 (body) = 70
        #expect(txData.count == 70)
    }
    
    // MARK: - Response Parsing Tests
    
    @Test("Parse get pump model response")
    func parseGetPumpModelResponse() throws {
        // From fixture_read_model.json response:
        // decoded_hex: "a7 20 88 50 8d 09 03 35 31 35 00..."
        // body_preview: "09 03 35 31 35" = length(9), string length(3), "515"
        
        let responseData = Data([
            0xA7,  // packet type
            0x20, 0x88, 0x50,  // serial
            0x8D,  // message type (getPumpModel)
            0x09,  // body: total length
            0x03,  // body: string length
            0x35, 0x31, 0x35,  // body: "515" in ASCII
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00  // padding
        ])
        
        let msg = PumpMessage(rxData: responseData)
        #expect(msg != nil)
        #expect(msg?.messageType == .getPumpModel)
        #expect(msg?.address[0] == 0x20)
        #expect(msg?.address[1] == 0x88)
        #expect(msg?.address[2] == 0x50)
        
        // Body should contain model info
        #expect(msg?.body[0] == 0x09)  // length
        #expect(msg?.body[1] == 0x03)  // string length
        
        // Extract model string
        if let body = msg?.body, body.count >= 5 {
            let modelBytes = body[2..<5]
            let model = String(bytes: modelBytes, encoding: .ascii)
            #expect(model == "515")
        }
    }
    
    @Test("Parse pump ack response")
    func parsePumpAckResponse() throws {
        // From fixture_wakeup.json: ACK response
        // decoded_hex: "a7 20 88 50 06 00 8e"
        // - 06 = pumpAck
        // - 00 = body
        // - 8E = CRC
        
        let ackData = Data([
            0xA7, 0x20, 0x88, 0x50,  // header
            0x06,  // pumpAck
            0x00   // body
        ])
        
        let msg = PumpMessage(rxData: ackData)
        #expect(msg != nil)
        #expect(msg?.messageType == .pumpAck)
    }
}

// MARK: - Fixture Loading Tests

@Suite("MedtronicFixtureTests")
struct MedtronicFixtureTests {
    
    @Test("Fixture read model exists")
    func fixtureReadModelExists() throws {
        // Verify fixture is accessible as test resource
        let bundle = Bundle.module
        let url = bundle.url(forResource: "fixture_read_model", withExtension: "json", subdirectory: "Fixtures")
        #expect(url != nil)
    }
    
    @Test("Fixture wakeup exists")
    func fixtureWakeupExists() throws {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "fixture_wakeup", withExtension: "json", subdirectory: "Fixtures")
        #expect(url != nil)
    }
    
    @Test("Load and parse read model fixture")
    func loadAndParseReadModelFixture() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_read_model", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("Could not find fixture_read_model.json")
            return
        }
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["test_name"] as? String == "read_model")
        #expect(json?["pump_serial"] as? String == "208850")
        #expect(json?["success"] as? Bool == true)
        
        // Verify result contains model
        if let result = json?["result"] as? [String: Any] {
            #expect(result["model"] as? String == "515")
        }
    }
    
    @Test("Load and parse wakeup fixture")
    func loadAndParseWakeupFixture() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_wakeup", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("Could not find fixture_wakeup.json")
            return
        }
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["test_name"] as? String == "wakeup_sequence")
        #expect(json?["pump_serial"] as? String == "208850")
        #expect(json?["success"] as? Bool == true)
    }
    
    @Test("Fixture read temp basal exists")
    func fixtureReadTempBasalExists() throws {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "fixture_read_tempbasal", withExtension: "json", subdirectory: "Fixtures")
        #expect(url != nil)
    }
    
    @Test("Load and parse temp basal fixture")
    func loadAndParseTempBasalFixture() throws {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "fixture_read_tempbasal", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("Could not find fixture_read_tempbasal.json")
            return
        }
        
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json != nil)
        #expect(json?["test_name"] as? String == "temp_basal_reading_parsing")
        
        // Verify vectors array exists
        if let vectors = json?["vectors"] as? [[String: Any]] {
            #expect(vectors.count > 0)
            
            // Verify first vector has expected fields
            if let firstVector = vectors.first {
                #expect(firstVector["name"] != nil)
                #expect(firstVector["rate_type"] != nil)
                #expect(firstVector["expected_rate"] != nil)
            }
        }
    }
}

// MARK: - MDT-SYNTH-002: Reservoir Parsing Conformance Tests

@Suite("MedtronicReservoirConformanceTests")
struct MedtronicReservoirConformanceTests {
    
    /// MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
    /// Production code (MedtronicCommands.swift:602) strips 5-byte header before calling parse()
    /// Tests must pass body-only to match production behavior
    
    // MARK: - Loop Test Vectors (from MinimedKitTests)
    
    /// Loop Test Vector: Model 723 at 80.875U
    /// Source: MinimedKitTests/ReadRemainingInsulinMessageBodyTests.swift
    @Test("Loop vector model 723 80.875U")
    func loopVector_Model723_80_875U() throws {
        // body[3:5] = 0x0CA3 = 3235 strokes; units = 3235 / 40 = 80.875
        // Body only - no header
        let body = Data([0x04, 0x00, 0x00, 0x0C, 0xA3])  // body[3:5] = 0x0CA3
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 40))
        #expect(abs(result.unitsRemaining - 80.875) < 0.001)
    }
    
    /// Loop Test Vector: Model 522 at 135.0U
    /// Source: MinimedKitTests/ReadRemainingInsulinMessageBodyTests.swift
    @Test("Loop vector model 522 135U")
    func loopVector_Model522_135U() throws {
        // body[1:3] = 0x0546 = 1350 strokes; units = 1350 / 10 = 135.0
        // Body only - no header
        let body = Data([0x02, 0x05, 0x46])  // body[1:3] = 0x0546
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 10))
        #expect(abs(result.unitsRemaining - 135.0) < 0.001)
    }
    
    // MARK: - Pre-523 Model Tests (scale=10, body[1:3])
    
    /// Test pre-523 pump (scale=10, body[1:3])
    @Test("Model 515 reservoir parsing 120U")
    func model515ReservoirParsing120U() throws {
        // body[1:3] = 0x04B0 = 1200 strokes; units = 1200 / 10 = 120.0
        // Body only - no header
        let body = Data([0x00, 0x04, 0xB0])  // body[1:3] = 0x04B0
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 10))
        #expect(abs(result.unitsRemaining - 120.0) < 0.01)
    }
    
    @Test("Model 515 reservoir parsing 50.5U")
    func model515ReservoirParsing50_5U() throws {
        // body[1:3] = 0x01F9 = 505 strokes; units = 505 / 10 = 50.5
        // Body only - no header
        let body = Data([0x00, 0x01, 0xF9])  // body[1:3] = 0x01F9
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 10))
        #expect(abs(result.unitsRemaining - 50.5) < 0.01)
    }
    
    @Test("Model 515 reservoir empty")
    func model515ReservoirEmpty() throws {
        // body[1:3] = 0x0000 = 0 strokes; units = 0 / 10 = 0.0
        // Body only - no header
        let body = Data([0x00, 0x00, 0x00])  // body[1:3] = 0x0000
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 10))
        #expect(abs(result.unitsRemaining - 0.0) < 0.01)
    }
    
    // MARK: - 523+ Model Tests (scale=40, body[3:5])
    
    /// Test 523+ pump (scale=40, body[3:5])
    @Test("Model 523 reservoir parsing 180U")
    func model523ReservoirParsing180U() throws {
        // body[3:5] = 0x1C20 = 7200 strokes; units = 7200 / 40 = 180.0
        // Body only - no header
        let body = Data([0x00, 0x00, 0x00, 0x1C, 0x20])  // body[3:5] = 0x1C20
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 40))
        #expect(abs(result.unitsRemaining - 180.0) < 0.01)
    }
    
    @Test("Model 523 reservoir parsing 75.15U")
    func model523ReservoirParsing75_15U() throws {
        // body[3:5] = 0x0BBE = 3006 strokes; units = 3006 / 40 = 75.15
        // Body only - no header
        let body = Data([0x00, 0x00, 0x00, 0x0B, 0xBE])  // body[3:5] = 0x0BBE
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 40))
        #expect(abs(result.unitsRemaining - 75.15) < 0.01)
    }
    
    @Test("Model 554 full reservoir 200U")
    func model554FullReservoir200U() throws {
        // body[3:5] = 0x1F40 = 8000 strokes; units = 8000 / 40 = 200.0
        // Body only - no header
        let body = Data([0x00, 0x00, 0x00, 0x1F, 0x40])  // body[3:5] = 0x1F40
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 40))
        #expect(abs(result.unitsRemaining - 200.0) < 0.01)
    }
    
    @Test("Model 723 large reservoir 300U")
    func model723LargeReservoir300U() throws {
        // body[3:5] = 0x2EE0 = 12000 strokes; units = 12000 / 40 = 300.0
        // Body only - no header
        let body = Data([0x00, 0x00, 0x00, 0x2E, 0xE0])  // body[3:5] = 0x2EE0
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 40))
        #expect(abs(result.unitsRemaining - 300.0) < 0.01)
    }
    
    /// Test edge cases - body length validation
    @Test("Reservoir parsing requires minimum bytes")
    func reservoirParsingRequiresMinimumBytes() {
        // Pre-523 needs at least 3 bytes body for indices [1:3]
        let tooShort = Data([0x00, 0x04])  // only 2 bytes body
        #expect(MedtronicReservoirResponse.parse(from: tooShort, scale: 10) == nil)
        
        // 523+ needs at least 5 bytes body for indices [3:5]
        let tooShort523 = Data([0x00, 0x00, 0x00, 0x1C])  // only 4 bytes body
        #expect(MedtronicReservoirResponse.parse(from: tooShort523, scale: 40) == nil)
    }
    
    /// Test MedtronicVariant scale mapping
    @Test("Variant insulin bit packing scale")
    func variantInsulinBitPackingScale() {
        // Pre-523 models should use scale 10
        let variant522 = MedtronicVariant(model: .model522, region: .northAmerica)
        #expect(variant522.insulinBitPackingScale == 10)
        
        let variant722 = MedtronicVariant(model: .model722, region: .northAmerica)
        #expect(variant722.insulinBitPackingScale == 10)
        
        // 523+ models should use scale 40
        let variant523 = MedtronicVariant(model: .model523, region: .northAmerica)
        #expect(variant523.insulinBitPackingScale == 40)
        
        let variant723 = MedtronicVariant(model: .model723, region: .northAmerica)
        #expect(variant723.insulinBitPackingScale == 40)
        
        let variant754 = MedtronicVariant(model: .model754, region: .northAmerica)
        #expect(variant754.insulinBitPackingScale == 40)
    }
    
    /// PYTHON-COMPAT: Verify Swift parsing matches decocare ReadRemainingInsulin
    /// Reference: decocare/commands.py line 727-738
    @Test("Python compat reservoir parsing")
    func pythonCompat_ReservoirParsing() throws {
        // Pre-523 model test cases (scale=10, body[1:3])
        // Body only - no header
        let pre523Cases: [(body: [UInt8], expectedUnits: Double)] = [
            ([0x02, 0x05, 0x46], 135.0),   // body[1:3] = 0x0546
            ([0x00, 0x04, 0xB0], 120.0),   // 1200 strokes
            ([0x00, 0x01, 0xF9], 50.5),    // 505 strokes
        ]
        
        for testCase in pre523Cases {
            let body = Data(testCase.body)
            let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 10))
            
            // Python: strokes = lib.BangInt(data[0:2]); units = strokes / 10.0
            // Maps to MinimedKit body[1:3]
            let pythonStrokes = Int(testCase.body[1]) << 8 + Int(testCase.body[2])
            let pythonUnits = Double(pythonStrokes) / 10.0
            #expect(abs(result.unitsRemaining - pythonUnits) < 0.001)
        }
        
        // 523+ model test cases (scale=40, body[3:5])
        // Body only - no header
        let post523Cases: [(body: [UInt8], expectedUnits: Double)] = [
            ([0x04, 0x00, 0x00, 0x0C, 0xA3], 80.875),   // body[3:5] = 0x0CA3
            ([0x00, 0x00, 0x00, 0x1C, 0x20], 180.0),    // 7200 strokes
            ([0x00, 0x00, 0x00, 0x2E, 0xE0], 300.0),    // 12000 strokes
        ]
        
        for testCase in post523Cases {
            let body = Data(testCase.body)
            let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: 40))
            
            // Python: strokes = lib.BangInt(data[2:4]); units = strokes / 40.0
            // Maps to MinimedKit body[3:5]
            let pythonStrokes = Int(testCase.body[3]) << 8 + Int(testCase.body[4])
            let pythonUnits = Double(pythonStrokes) / 40.0
            #expect(abs(result.unitsRemaining - pythonUnits) < 0.001)
        }
    }
}

// MARK: - MDT-SYNTH-001: Battery Parsing Conformance Tests

@Suite("MedtronicBatteryConformanceTests")
struct MedtronicBatteryConformanceTests {
    
    /// Test Loop fixture vector: 1.4V Normal
    /// Source: MinimedKitTests/GetBatteryCarelinkMessageBodyTests.swift
    @Test("Loop vector 1.4V normal")
    func loopVector_1_4V_Normal() throws {
        // From fixture_battery.json: Loop Test Vector - 1.4V Normal
        // response_bytes: [0, 0, 140] = indicator=0, voltage=140/100=1.4V
        let data = Data([0x00, 0x00, 0x8C])
        
        let result = try #require(MedtronicBatteryResponse.parse(from: data))
        #expect(result.status == .normal)
        #expect(abs(result.volts - 1.4) < 0.01)
    }
    
    /// Test 1.45V Normal battery
    @Test("Normal battery 1.45V")
    func normalBattery_1_45V() throws {
        // From fixture_battery.json: Normal Battery - 1.45V
        // response_bytes: [0, 0, 145] = indicator=0, voltage=145/100=1.45V
        let data = Data([0x00, 0x00, 0x91])
        
        let result = try #require(MedtronicBatteryResponse.parse(from: data))
        #expect(result.status == .normal)
        #expect(abs(result.volts - 1.45) < 0.01)
    }
    
    /// Test Low battery at 1.15V
    @Test("Low battery 1.15V")
    func lowBattery_1_15V() throws {
        // From fixture_battery.json: Low Battery - 1.15V
        // response_bytes: [1, 0, 115] = indicator=1 (low), voltage=115/100=1.15V
        let data = Data([0x01, 0x00, 0x73])
        
        let result = try #require(MedtronicBatteryResponse.parse(from: data))
        #expect(result.status == .low)
        #expect(abs(result.volts - 1.15) < 0.01)
    }
    
    /// Test Full battery at 1.55V
    @Test("Full battery 1.55V")
    func fullBattery_1_55V() throws {
        // From fixture_battery.json: Full Battery - 1.55V
        // response_bytes: [0, 0, 155] = indicator=0, voltage=155/100=1.55V
        let data = Data([0x00, 0x00, 0x9B])
        
        let result = try #require(MedtronicBatteryResponse.parse(from: data))
        #expect(result.status == .normal)
        #expect(abs(result.volts - 1.55) < 0.01)
        #expect(result.estimatedPercent == 100)
    }
    
    /// Test Very Low battery at 1.1V
    @Test("Very low battery 1.1V")
    func veryLowBattery_1_1V() throws {
        // From fixture_battery.json: Very Low Battery - 1.1V
        // response_bytes: [1, 0, 110] = indicator=1 (low), voltage=110/100=1.1V
        let data = Data([0x01, 0x00, 0x6E])
        
        let result = try #require(MedtronicBatteryResponse.parse(from: data))
        #expect(result.status == .low)
        #expect(abs(result.volts - 1.1) < 0.01)
        #expect(result.estimatedPercent == 0)
    }
    
    /// Test Unknown status indicator (edge case)
    @Test("Unknown status 1.3V")
    func unknownStatus_1_3V() throws {
        // From fixture_battery.json: Unknown Status - 1.3V
        // response_bytes: [2, 0, 130] = indicator=2 (unknown), voltage=130/100=1.3V
        let data = Data([0x02, 0x00, 0x82])
        
        let result = try #require(MedtronicBatteryResponse.parse(from: data))
        #expect(result.status == .unknown(rawValue: 2))
        #expect(abs(result.volts - 1.3) < 0.01)
    }
    
    /// Test insufficient data returns nil
    @Test("Battery parsing requires minimum bytes")
    func batteryParsingRequiresMinimumBytes() {
        let tooShort = Data([0x00, 0x00])
        #expect(MedtronicBatteryResponse.parse(from: tooShort) == nil)
    }
    
    /// PYTHON-COMPAT: Verify Swift parsing matches decocare ReadBatteryStatus
    /// Reference: decocare/commands.py line 698-704
    /// Python: volt = lib.BangInt((bd[1], bd[2])); battery = {'voltage': volt/100.0}
    @Test("Python compat battery parsing")
    func pythonCompat_BatteryParsing() throws {
        // Using the same byte sequences that decocare would process
        let testCases: [(bytes: [UInt8], expectedVolts: Double, expectedStatus: String)] = [
            ([0x00, 0x00, 0x8C], 1.4, "normal"),   // Loop test vector
            ([0x00, 0x00, 0x91], 1.45, "normal"),  // Mid-range
            ([0x01, 0x00, 0x73], 1.15, "low"),     // Low battery
        ]
        
        for testCase in testCases {
            let data = Data(testCase.bytes)
            let result = try #require(MedtronicBatteryResponse.parse(from: data))
            
            // Python: volt = lib.BangInt((bd[1], bd[2])) / 100.0
            let pythonVolts = Double(Int(testCase.bytes[1]) << 8 + Int(testCase.bytes[2])) / 100.0
            #expect(abs(result.volts - pythonVolts) < 0.001)
            #expect(abs(result.volts - testCase.expectedVolts) < 0.01)
        }
    }
}

// MARK: - MDT-IMPL-003: Firmware Version Parsing Tests

@Suite("MedtronicFirmwareConformanceTests")
struct MedtronicFirmwareConformanceTests {
    
    /// Test firmware version parsing with typical version string
    @Test("Firmware version parsing")
    func firmwareVersionParsing() throws {
        // Typical firmware: "2.4A" with null terminator
        // Format: [unused][version string][null]
        let data = Data([0x00, 0x32, 0x2E, 0x34, 0x41, 0x00])  // [unused]["2.4A"][null]
        
        let result = try #require(MedtronicFirmwareResponse.parse(from: data))
        #expect(result.version == "2.4A")
    }
    
    /// Test firmware with longer version string
    @Test("Firmware version longer")
    func firmwareVersionLonger() throws {
        // "2.6.12" format
        let data = Data([0x00] + Array("2.6.12".utf8) + [0x00])
        
        let result = try #require(MedtronicFirmwareResponse.parse(from: data))
        #expect(result.version == "2.6.12")
    }
    
    /// Test firmware parsing without null terminator (uses full data)
    @Test("Firmware version no null")
    func firmwareVersionNoNull() throws {
        // No null terminator - uses remaining data
        let data = Data([0x00] + Array("2.4A".utf8))
        
        let result = try #require(MedtronicFirmwareResponse.parse(from: data))
        #expect(result.version == "2.4A")
    }
    
    /// Test too short data returns nil
    @Test("Firmware version too short")
    func firmwareVersionTooShort() throws {
        let tooShort = Data([0x00])  // Only padding byte
        #expect(MedtronicFirmwareResponse.parse(from: tooShort) == nil)
    }
}

// MARK: - MDT-IMPL-001: Time Parsing Tests

@Suite("MedtronicTimeConformanceTests")
struct MedtronicTimeConformanceTests {
    
    /// Test time parsing with typical pump time
    @Test("Time parsing")
    func timeParsing() throws {
        // 2024-03-15 14:30:45
        // Format: [unused][hour][minute][second][year_hi][year_lo][month][day]
        let data = Data([0x00, 14, 30, 45, 0x07, 0xE8, 3, 15])  // 0x07E8 = 2024
        
        let result = try #require(MedtronicTimeResponse.parse(from: data))
        #expect(result.dateComponents.hour == 14)
        #expect(result.dateComponents.minute == 30)
        #expect(result.dateComponents.second == 45)
        #expect(result.dateComponents.year == 2024)
        #expect(result.dateComponents.month == 3)
        #expect(result.dateComponents.day == 15)
    }
    
    /// Test midnight time
    @Test("Midnight time")
    func midnightTime() throws {
        // 2025-01-01 00:00:00
        let data = Data([0x00, 0, 0, 0, 0x07, 0xE9, 1, 1])  // 0x07E9 = 2025
        
        let result = try #require(MedtronicTimeResponse.parse(from: data))
        #expect(result.dateComponents.hour == 0)
        #expect(result.dateComponents.minute == 0)
        #expect(result.dateComponents.second == 0)
        #expect(result.dateComponents.year == 2025)
    }
    
    /// Test end of day time
    @Test("End of day time")
    func endOfDayTime() throws {
        // 2023-12-31 23:59:59
        let data = Data([0x00, 23, 59, 59, 0x07, 0xE7, 12, 31])  // 0x07E7 = 2023
        
        let result = try #require(MedtronicTimeResponse.parse(from: data))
        #expect(result.dateComponents.hour == 23)
        #expect(result.dateComponents.minute == 59)
        #expect(result.dateComponents.second == 59)
        #expect(result.dateComponents.year == 2023)
        #expect(result.dateComponents.month == 12)
        #expect(result.dateComponents.day == 31)
    }
    
    /// Test date conversion
    @Test("Date conversion")
    func dateConversion() throws {
        // 2024-06-15 12:00:00
        let data = Data([0x00, 12, 0, 0, 0x07, 0xE8, 6, 15])
        
        let result = try #require(MedtronicTimeResponse.parse(from: data))
        let date = try #require(result.date)
        
        let calendar = Calendar.current
        #expect(calendar.component(.hour, from: date) == 12)
        #expect(calendar.component(.month, from: date) == 6)
        #expect(calendar.component(.day, from: date) == 15)
    }
    
    /// Test too short data returns nil
    @Test("Time too short")
    func timeTooShort() throws {
        let tooShort = Data([0x00, 12, 30, 45, 0x07, 0xE8, 3])  // Only 7 bytes
        #expect(MedtronicTimeResponse.parse(from: tooShort) == nil)
    }
}

// MARK: - MDT-IMPL-002: Settings Parsing Tests

@Suite("MedtronicSettingsConformanceTests")
struct MedtronicSettingsConformanceTests {
    
    /// Test settings parsing for x23+ pump (newer format)
    @Test("Settings parsing newer")
    func settingsParsingNewer() throws {
        // Simulate x23+ pump response (byte[0] = 25 indicates newer)
        // maxBolus at [7], maxBasal at [8:9], profile at [12], IAC at [18]
        var data = Data(repeating: 0, count: 65)
        data[0] = 25  // x23 indicator
        data[7] = 100  // maxBolus = 100/10 = 10.0 U
        data[8] = 0x01  // maxBasal high byte
        data[9] = 0x40  // maxBasal low byte = 320/40 = 8.0 U/hr
        data[12] = 1  // Profile A
        data[18] = 4  // 4 hour insulin action curve
        
        let result = try #require(MedtronicSettingsResponse.parse(from: data))
        #expect(abs(result.maxBolus - 10.0) < 0.01)
        #expect(abs(result.maxBasal - 8.0) < 0.01)
        #expect(result.selectedBasalProfile == .profileA)
        #expect(result.insulinActionCurveHours == 4)
    }
    
    /// Test settings parsing for x22 and earlier (older format)
    @Test("Settings parsing older")
    func settingsParsingOlder() throws {
        // Simulate x22 pump response (byte[0] != 25)
        // maxBolus at [6], maxBasal at [7:8]
        var data = Data(repeating: 0, count: 65)
        data[0] = 19  // x22 indicator
        data[6] = 150  // maxBolus = 150/10 = 15.0 U
        data[7] = 0x00  // maxBasal high byte
        data[8] = 0x50  // maxBasal low byte = 80/40 = 2.0 U/hr
        data[12] = 0  // Standard profile
        data[18] = 5  // 5 hour insulin action curve
        
        let result = try #require(MedtronicSettingsResponse.parse(from: data, isNewer: false))
        #expect(abs(result.maxBolus - 15.0) < 0.01)
        #expect(abs(result.maxBasal - 2.0) < 0.01)
        #expect(result.selectedBasalProfile == .standard)
        #expect(result.insulinActionCurveHours == 5)
    }
    
    /// Test basal profile B
    @Test("Basal profile B")
    func basalProfileB() throws {
        var data = Data(repeating: 0, count: 65)
        data[0] = 25
        data[7] = 50
        data[8] = 0x00
        data[9] = 0x28  // 40/40 = 1.0 U/hr
        data[12] = 2  // Profile B
        data[18] = 3
        
        let result = try #require(MedtronicSettingsResponse.parse(from: data))
        #expect(result.selectedBasalProfile == .profileB)
    }
    
    /// Test too short data returns nil
    @Test("Settings too short")
    func settingsTooShort() throws {
        let tooShort = Data(repeating: 0, count: 18)  // Need at least 19 bytes
        #expect(MedtronicSettingsResponse.parse(from: tooShort) == nil)
    }
    
    /// Test opcode value
    @Test("Settings opcode")
    func settingsOpcode() throws {
        #expect(MedtronicOpcode.getSettings.rawValue == 0xC0)
    }
}

// MARK: - FIX-MDT-002: History Parsing Conformance Tests

@Suite("MedtronicHistoryConformanceTests")
struct MedtronicHistoryConformanceTests {
    
    /// Test opcode identification
    @Test("Opcode values")
    func opcodeValues() {
        // Verify opcodes match decocare/records/bolus.py
        #expect(MinimedHistoryOpcode.bolusNormal.rawValue == 0x01)
        #expect(MinimedHistoryOpcode.prime.rawValue == 0x03)
        #expect(MinimedHistoryOpcode.alarmPump.rawValue == 0x06)
        #expect(MinimedHistoryOpcode.resultDailyTotal.rawValue == 0x07)
        #expect(MinimedHistoryOpcode.suspend.rawValue == 0x1E)
        #expect(MinimedHistoryOpcode.resume.rawValue == 0x1F)
        #expect(MinimedHistoryOpcode.rewind.rawValue == 0x21)
        #expect(MinimedHistoryOpcode.tempBasal.rawValue == 0x33)
        #expect(MinimedHistoryOpcode.bolusWizardBolusEstimate.rawValue == 0x5B)
        #expect(MinimedHistoryOpcode.basalProfileStart.rawValue == 0x7B)
    }
    
    /// Test record length for 522 (smaller pump)
    @Test("Record length 522")
    func recordLength522() {
        // From fixture_history.json: record_lengths
        #expect(MinimedHistoryOpcode.bolusNormal.length(isLargerPump: false) == 9)
        #expect(MinimedHistoryOpcode.prime.length(isLargerPump: false) == 10)
        #expect(MinimedHistoryOpcode.alarmPump.length(isLargerPump: false) == 9)
        #expect(MinimedHistoryOpcode.resultDailyTotal.length(isLargerPump: false) == 10)
        #expect(MinimedHistoryOpcode.suspend.length(isLargerPump: false) == 7)
        #expect(MinimedHistoryOpcode.resume.length(isLargerPump: false) == 7)
        #expect(MinimedHistoryOpcode.rewind.length(isLargerPump: false) == 7)
        #expect(MinimedHistoryOpcode.tempBasal.length(isLargerPump: false) == 8)
    }
    
    /// Test record length for 523+ (larger pump)
    @Test("Record length 523")
    func recordLength523() {
        // From fixture_history.json: 523+ uses larger bolus records
        #expect(MinimedHistoryOpcode.bolusNormal.length(isLargerPump: true) == 13)
        #expect(MinimedHistoryOpcode.prime.length(isLargerPump: true) == 10)  // Same
        #expect(MinimedHistoryOpcode.suspend.length(isLargerPump: true) == 7)  // Same
    }
    
    /// Test parser initialization
    @Test("Parser initialization")
    func parserInitialization() {
        let parser522 = MinimedHistoryParser(isLargerPump: false)
        let parser523 = MinimedHistoryParser(isLargerPump: true)
        
        // Just verify they can be created
        #expect(parser522 != nil)
        #expect(parser523 != nil)
    }
    
    /// Test parsing a simple suspend record
    @Test("Parse suspend record")
    func parseSuspendRecord() {
        // From fixture_history.json: suspend_record
        // [30, 0, 45, 71, 13, 20, 13] = suspend opcode + date
        let data = Data([0x1E, 0x00, 0x2D, 0x47, 0x0D, 0x14, 0x0D])
        
        let parser = MinimedHistoryParser(isLargerPump: false)
        let events = parser.parse(data)
        
        #expect(events.count == 1)
        #expect(events.first?.type == .suspend)
    }
    
    /// Test parsing a simple resume record
    @Test("Parse resume record")
    func parseResumeRecord() {
        // From fixture_history.json: resume_record
        let data = Data([0x1F, 0x00, 0x2E, 0x47, 0x0D, 0x14, 0x0D])
        
        let parser = MinimedHistoryParser(isLargerPump: false)
        let events = parser.parse(data)
        
        #expect(events.count == 1)
        #expect(events.first?.type == .resume)
    }
    
    /// Test parsing a rewind record
    @Test("Parse rewind record")
    func parseRewindRecord() {
        // From fixture_history.json: rewind_record
        let data = Data([0x21, 0x00, 0x2F, 0x47, 0x0D, 0x14, 0x0D])
        
        let parser = MinimedHistoryParser(isLargerPump: false)
        let events = parser.parse(data)
        
        #expect(events.count == 1)
        #expect(events.first?.type == .rewind)
    }
    
    /// Test parsing bolus record from 522 pump
    @Test("Parse bolus normal 522")
    func parseBolusNormal522() {
        // From fixture_history.json: bolus_normal_522
        // [1, 56, 56, 0, 220, 5, 79, 18, 12] = 5.6U normal bolus
        let data = Data([0x01, 0x38, 0x38, 0x00, 0xDC, 0x05, 0x4F, 0x12, 0x0C])
        
        let parser = MinimedHistoryParser(isLargerPump: false)
        let events = parser.parse(data)
        
        #expect(events.count == 1)
        #expect(events.first?.type == .bolus)
        
        // Verify bolus amount is parsed correctly
        // head[2] / 10.0 = 56 / 10 = 5.6U
        if let amountStr = events.first?.data?["amount"],
           let amount = Double(amountStr) {
            #expect(abs(amount - 5.6) < 0.01)
        }
    }
    
    /// Test empty data returns no events
    @Test("Parse empty data")
    func parseEmptyData() {
        let parser = MinimedHistoryParser(isLargerPump: false)
        let events = parser.parse(Data())
        
        #expect(events.count == 0)
    }
    
    /// Test null bytes at end (page terminator)
    @Test("Parse null terminator")
    func parseNullTerminator() {
        // A page ending with 0x00 0x00 should stop parsing
        let data = Data([0x00, 0x00])
        
        let parser = MinimedHistoryParser(isLargerPump: false)
        let events = parser.parse(data)
        
        #expect(events.count == 0)
    }
}

// MARK: - MDT-IMPL-005: Glucose Page Conformance Tests

@Suite("MedtronicGlucosePageConformanceTests")
struct MedtronicGlucosePageConformanceTests {
    
    /// Test opcode value matches Loop
    @Test("Opcode value")
    func opcodeValue() {
        #expect(MedtronicOpcode.getGlucosePage.rawValue == 0x9A)
        #expect(MedtronicOpcode.getGlucosePage.displayName == "Get Glucose Page")
    }
    
    /// Test request TX data format matches Loop GetGlucosePageMessageBody
    /// Loop format: [numArgs=4][pageNum 4 bytes big-endian]
    @Test("Request TX data format")
    func requestTxDataFormat() {
        let cmd = MedtronicGlucosePageCommand(pageNum: 13)
        
        // From GetGlucosePageMessageBodyTests: pageNum 13 -> "040000000d"
        #expect(cmd.txData == Data([0x04, 0x00, 0x00, 0x00, 0x0D]))
    }
    
    /// Test request with larger page number
    @Test("Request large page number")
    func requestLargePageNumber() {
        let cmd = MedtronicGlucosePageCommand(pageNum: 256)
        
        // pageNum 256 = 0x00000100
        #expect(cmd.txData == Data([0x04, 0x00, 0x00, 0x01, 0x00]))
    }
    
    /// Test response parsing - first frame
    @Test("Response parse first frame")
    func responseParseFirstFrame() {
        // Frame 0, not last (0x00)
        var data = Data([0x00])
        data.append(contentsOf: [UInt8](repeating: 0xAB, count: 64))
        
        let response = MedtronicGlucosePageResponse(data: data)
        #expect(response != nil)
        #expect(response!.frameNumber == 0)
        #expect(!response!.lastFrame)
        #expect(response!.frameData.count == 64)
        #expect(response!.frameData[0] == 0xAB)
    }
    
    /// Test response parsing - last frame
    @Test("Response parse last frame")
    func responseParseLastFrame() {
        // Frame 3, last (0x83 = 0x80 | 0x03)
        var data = Data([0x83])
        data.append(contentsOf: [UInt8](repeating: 0xCD, count: 64))
        
        let response = MedtronicGlucosePageResponse(data: data)
        #expect(response != nil)
        #expect(response!.frameNumber == 3)
        #expect(response!.lastFrame)
        #expect(response!.frameData.count == 64)
    }
    
    /// Test response parsing with minimal data
    @Test("Response parse minimal")
    func responseParseMinimal() {
        let data = Data([0x80])  // Last frame, frame 0, no data
        
        let response = MedtronicGlucosePageResponse(data: data)
        #expect(response != nil)
        #expect(response!.frameNumber == 0)
        #expect(response!.lastFrame)
        #expect(response!.frameData.count == 0)
    }
}

// MARK: - MDT-SYNTH-003: Temp Basal Reading Conformance Tests

@Suite("MedtronicTempBasalConformanceTests")
struct MedtronicTempBasalConformanceTests {
    
    // MARK: - Loop Test Vectors (from MinimedKitTests)
    
    /// Loop Test Vector: 1.375U @ 23min
    /// Source: MinimedKitTests/ReadTempBasalCarelinkMessageBodyTests.swift
    @Test("Loop vector 1.375U at 23min")
    func loopVector_1_375U_at_23min() throws {
        // From fixture_read_tempbasal.json: Loop Test Vector - 1.375U @ 23min
        // body_hex: "06 00 00 00 37 00 17"
        // rateType=0 (absolute), strokes=0x0037=55, rate=55/40=1.375, minutes=0x0017=23
        let data = Data([0x06, 0x00, 0x00, 0x00, 0x37, 0x00, 0x17])
        
        let result = try #require(MedtronicTempBasalResponse.parse(from: data))
        #expect(abs(result.rate - 1.375) < 0.001)
        #expect(result.rateType == .absolute)
        #expect(result.timeRemaining == TimeInterval(23 * 60))
        #expect(result.minutesRemaining == 23)
        #expect(result.isActive)
    }
    
    /// Loop Test Vector: 0U @ 29min (Zero Rate / Suspend)
    /// Source: MinimedKitTests/ReadTempBasalCarelinkMessageBodyTests.swift
    @Test("Loop vector 0U at 29min")
    func loopVector_0U_at_29min() throws {
        // From fixture_read_tempbasal.json: Loop Test Vector - 0U @ 29min (Zero Rate)
        // body_hex: "06 00 00 00 00 00 1D"
        // rateType=0, strokes=0, rate=0U/hr, minutes=0x001D=29
        let data = Data([0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1D])
        
        let result = try #require(MedtronicTempBasalResponse.parse(from: data))
        #expect(abs(result.rate - 0.0) < 0.001)
        #expect(result.rateType == .absolute)
        #expect(result.timeRemaining == TimeInterval(29 * 60))
    }
    
    /// Loop Test Vector: 34U @ 30min (High Rate)
    /// Source: MinimedKitTests/ReadTempBasalCarelinkMessageBodyTests.swift
    @Test("Loop vector 34U at 30min")
    func loopVector_34U_at_30min() throws {
        // From fixture_read_tempbasal.json: Loop Test Vector - 34U @ 30min (High Rate)
        // body_hex: "06 00 00 05 50 00 1E"
        // rateType=0, strokes=0x0550=1360, rate=1360/40=34U/hr, minutes=0x001E=30
        let data = Data([0x06, 0x00, 0x00, 0x05, 0x50, 0x00, 0x1E])
        
        let result = try #require(MedtronicTempBasalResponse.parse(from: data))
        #expect(abs(result.rate - 34.0) < 0.001)
        #expect(result.rateType == .absolute)
        #expect(result.timeRemaining == TimeInterval(30 * 60))
    }
    
    // MARK: - Percent Rate Tests
    
    /// Percent Rate: 50% @ 60min
    @Test("Percent rate 50 at 60min")
    func percentRate_50_at_60min() throws {
        // From fixture_read_tempbasal.json: Percent Rate - 50% @ 60min
        // body_hex: "06 01 32 00 00 00 3C"
        // rateType=1 (percent), percentValue=0x32=50, minutes=0x003C=60
        let data = Data([0x06, 0x01, 0x32, 0x00, 0x00, 0x00, 0x3C])
        
        let result = try #require(MedtronicTempBasalResponse.parse(from: data))
        #expect(abs(result.rate - 50.0) < 0.001)
        #expect(result.rateType == .percent)
        #expect(result.timeRemaining == TimeInterval(60 * 60))
    }
    
    /// Percent Rate: 0% @ 45min (Suspend via percent)
    @Test("Percent rate 0 at 45min")
    func percentRate_0_at_45min() throws {
        // From fixture_read_tempbasal.json: Percent Rate - 0% @ 45min (Suspend)
        // body_hex: "06 01 00 00 00 00 2D"
        let data = Data([0x06, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2D])
        
        let result = try #require(MedtronicTempBasalResponse.parse(from: data))
        #expect(abs(result.rate - 0.0) < 0.001)
        #expect(result.rateType == .percent)
        #expect(result.timeRemaining == TimeInterval(45 * 60))
    }
    
    /// Percent Rate: 200% @ 120min (Max)
    @Test("Percent rate 200 at 120min")
    func percentRate_200_at_120min() throws {
        // From fixture_read_tempbasal.json: Percent Rate - 200% @ 120min (Max)
        // body_hex: "06 01 C8 00 00 00 78"
        let data = Data([0x06, 0x01, 0xC8, 0x00, 0x00, 0x00, 0x78])
        
        let result = try #require(MedtronicTempBasalResponse.parse(from: data))
        #expect(abs(result.rate - 200.0) < 0.001)
        #expect(result.rateType == .percent)
        #expect(result.timeRemaining == TimeInterval(120 * 60))
    }
    
    // MARK: - Edge Cases
    
    /// Absolute Rate: 0.5U @ 15min
    @Test("Absolute rate 0.5U at 15min")
    func absoluteRate_0_5U_at_15min() throws {
        // From fixture_read_tempbasal.json: Absolute Rate - 0.5U @ 15min
        // body_hex: "06 00 00 00 14 00 0F"
        // strokes=0x0014=20, rate=20/40=0.5U/hr
        let data = Data([0x06, 0x00, 0x00, 0x00, 0x14, 0x00, 0x0F])
        
        let result = try #require(MedtronicTempBasalResponse.parse(from: data))
        #expect(abs(result.rate - 0.5) < 0.001)
        #expect(result.rateType == .absolute)
        #expect(result.minutesRemaining == 15)
    }
    
    /// No Temp Basal Active: 0U @ 0min
    @Test("No temp basal active")
    func noTempBasalActive() throws {
        // From fixture_read_tempbasal.json: No Temp Basal Active
        // body_hex: "06 00 00 00 00 00 00"
        let data = Data([0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        
        let result = try #require(MedtronicTempBasalResponse.parse(from: data))
        #expect(abs(result.rate - 0.0) < 0.001)
        #expect(result.timeRemaining == 0)
        #expect(!result.isActive)
    }
    
    /// Test insufficient data returns nil
    @Test("Temp basal parsing requires minimum bytes")
    func tempBasalParsingRequiresMinimumBytes() {
        let tooShort = Data([0x06, 0x00, 0x00, 0x00, 0x37, 0x00])  // Only 6 bytes
        #expect(MedtronicTempBasalResponse.parse(from: tooShort) == nil)
    }
    
    /// Test invalid rate type returns nil
    @Test("Invalid rate type returns nil")
    func invalidRateTypeReturnsNil() {
        // rateType=2 is invalid (only 0 and 1 are valid)
        let invalidData = Data([0x06, 0x02, 0x00, 0x00, 0x37, 0x00, 0x17])
        #expect(MedtronicTempBasalResponse.parse(from: invalidData) == nil)
    }
    
    // MARK: - PYTHON-COMPAT Tests
    
    /// PYTHON-COMPAT: Verify Swift parsing matches MinimedKit ReadTempBasalCarelinkMessageBody
    /// Reference: MinimedKit/Messages/ReadTempBasalCarelinkMessageBody.swift
    /// Python equivalent: strokes = int.from_bytes(data[3:5], 'big'); rate = strokes / 40.0
    @Test("Python compat temp basal parsing")
    func pythonCompat_TempBasalParsing() throws {
        // Absolute rate test cases
        let absoluteCases: [(bytes: [UInt8], expectedRate: Double, expectedMinutes: Int)] = [
            ([0x06, 0x00, 0x00, 0x00, 0x37, 0x00, 0x17], 1.375, 23),   // Loop test vector
            ([0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1D], 0.0, 29),     // Zero rate
            ([0x06, 0x00, 0x00, 0x05, 0x50, 0x00, 0x1E], 34.0, 30),    // High rate
        ]
        
        for testCase in absoluteCases {
            let data = Data(testCase.bytes)
            let result = try #require(MedtronicTempBasalResponse.parse(from: data))
            
            // Python: strokes = int.from_bytes(data[3:5], 'big'); rate = strokes / 40.0
            let pythonStrokes = Int(testCase.bytes[3]) << 8 + Int(testCase.bytes[4])
            let pythonRate = Double(pythonStrokes) / 40.0
            #expect(abs(result.rate - pythonRate) < 0.001)
            
            // Python: minutes = int.from_bytes(data[5:7], 'big')
            let pythonMinutes = Int(testCase.bytes[5]) << 8 + Int(testCase.bytes[6])
            #expect(result.minutesRemaining == pythonMinutes)
        }
        
        // Percent rate test cases
        let percentCases: [(bytes: [UInt8], expectedPercent: Double)] = [
            ([0x06, 0x01, 0x32, 0x00, 0x00, 0x00, 0x3C], 50.0),   // 50%
            ([0x06, 0x01, 0xC8, 0x00, 0x00, 0x00, 0x78], 200.0),  // 200%
        ]
        
        for testCase in percentCases {
            let data = Data(testCase.bytes)
            let result = try #require(MedtronicTempBasalResponse.parse(from: data))
            
            // Python: percent = data[2]
            let pythonPercent = Double(testCase.bytes[2])
            #expect(abs(result.rate - pythonPercent) < 0.001)
            #expect(result.rateType == .percent)
        }
    }
}

// MARK: - SESSION-MDT-002: Status Session Conformance Tests

/// Tests validating the complete status query session
/// Trace: SESSION-MDT-002
@Suite("MedtronicStatusSessionTests")
struct MedtronicStatusSessionTests {
    
    /// Test that fixture file exists and is valid JSON
    @Test("Status session fixture exists")
    func statusSessionFixtureExists() throws {
        let fixturePath = "conformance/protocol/medtronic/fixture_mdt_status_session.json"
        let url = URL(fileURLWithPath: fixturePath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        
        // Also try relative to package root
        let altUrl = URL(fileURLWithPath: "../../../\(fixturePath)", relativeTo: URL(fileURLWithPath: #file))
        
        let fileURL = FileManager.default.fileExists(atPath: url.path) ? url : altUrl
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
    
    /// Test reservoir parsing against session fixture test vectors
    /// MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
    @Test("Status session reservoir vectors")
    func statusSessionReservoirVectors() throws {
        // Test vectors: body-only data for parse()
        // MDT-HIST-020: x23+ body[3:5], pre-523 body[1:3]
        let testVectors: [(model: String, scale: Int, body: [UInt8], expected: Double)] = [
            ("523", 40, [0x00, 0x00, 0x00, 0x1C, 0x20], 180.0),  // body[3:5] = 0x1C20 = 7200 strokes
            ("515", 10, [0x00, 0x04, 0xB0], 120.0),               // body[1:3] = 0x04B0 = 1200 strokes
        ]
        
        for vector in testVectors {
            let body = Data(vector.body)
            let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: vector.scale))
            #expect(abs(result.unitsRemaining - vector.expected) < 0.01)
        }
    }
    
    /// Test battery parsing against session fixture test vectors
    @Test("Status session battery vectors")
    func statusSessionBatteryVectors() throws {
        // Test vectors from fixture_mdt_status_session.json
        let testVectors: [(bytes: [UInt8], expectedVolts: Double, expectedStatus: MedtronicBatteryResponse.BatteryStatus)] = [
            ([0, 0, 145], 1.45, .normal),
            ([1, 0, 115], 1.15, .low),
        ]
        
        for vector in testVectors {
            let data = Data(vector.bytes)
            let result = try #require(MedtronicBatteryResponse.parse(from: data))
            #expect(abs(result.volts - vector.expectedVolts) < 0.01)
            #expect(result.status == vector.expectedStatus)
        }
    }
    
    /// Test status parsing against session fixture test vectors
    @Test("Status session status vectors")
    func statusSessionStatusVectors() throws {
        // Test vectors from fixture_mdt_status_session.json
        // Format: [status_code, bolusing, suspended]
        let testVectors: [(bytes: [UInt8], expectedBolusing: Bool, expectedSuspended: Bool)] = [
            ([3, 0, 0], false, false),  // Normal - idle
            ([3, 1, 0], true, false),   // Normal - bolusing
            ([3, 0, 1], false, true),   // Normal - suspended
        ]
        
        for vector in testVectors {
            let data = Data(vector.bytes)
            let result = try #require(MedtronicStatusResponse.parse(from: data))
            #expect(result.bolusing == vector.expectedBolusing)
            #expect(result.suspended == vector.expectedSuspended)
        }
    }
    
    /// Test complete session state machine transitions
    @Test("Status session state machine")
    func statusSessionStateMachine() throws {
        // Verify state sequence from fixture
        let expectedStates = ["awake", "querying_status", "reading_reservoir", "reading_battery", "complete"]
        
        // Simulate session state machine
        var currentState = "awake"
        let transitions: [(from: String, to: String, trigger: String)] = [
            ("awake", "querying_status", "send_status_query"),
            ("querying_status", "reading_reservoir", "status_received"),
            ("reading_reservoir", "reading_battery", "reservoir_received"),
            ("reading_battery", "complete", "battery_received"),
        ]
        
        var visitedStates = [currentState]
        for transition in transitions {
            #expect(currentState == transition.from)
            currentState = transition.to
            visitedStates.append(currentState)
        }
        
        #expect(visitedStates == expectedStates)
    }
    
    /// Test that session produces expected final result
    /// MDT-DIAG-FIX: parse() expects BODY ONLY (headers stripped by caller in production)
    @Test("Status session final result")
    func statusSessionFinalResult() throws {
        // Expected result from fixture_mdt_status_session.json
        let expectedResult = (
            success: true,
            bolusing: false,
            suspended: false,
            reservoirUnits: 180.0,
            batteryVolts: 1.45,
            batteryPercent: 77
        )
        
        // Simulate parsing each step's response - body-only data
        let statusData = Data([0x03, 0x00, 0x00])
        let reservoirBody = Data([0x00, 0x00, 0x00, 0x1C, 0x20])  // body[3:5] = 0x1C20
        let batteryData = Data([0x00, 0x00, 0x91])
        
        let status = try #require(MedtronicStatusResponse.parse(from: statusData))
        let reservoir = try #require(MedtronicReservoirResponse.parse(from: reservoirBody, scale: 40))
        let battery = try #require(MedtronicBatteryResponse.parse(from: batteryData))
        
        #expect(status.bolusing == expectedResult.bolusing)
        #expect(status.suspended == expectedResult.suspended)
        #expect(abs(reservoir.unitsRemaining - expectedResult.reservoirUnits) < 0.01)
        #expect(abs(battery.volts - expectedResult.batteryVolts) < 0.01)
        #expect(battery.estimatedPercent == expectedResult.batteryPercent)
    }
    
    // MARK: - Basal Schedule Command Tests (MDT-IMPL-006)
    
    /// Test setBasalProfile opcodes match Loop MessageType values
    @Test("Set basal profile opcodes")
    func setBasalProfileOpcodes() throws {
        // From externals/MinimedKit/MinimedKit/Messages/MessageType.swift
        #expect(MedtronicOpcode.setBasalProfileA.rawValue == 0x30)
        #expect(MedtronicOpcode.setBasalProfileB.rawValue == 0x31)
        #expect(MedtronicOpcode.setBasalProfileStandard.rawValue == 0x6F)
    }
    
    /// Test that opcodes are marked as write commands
    @Test("Set basal profile are write commands")
    func setBasalProfileAreWriteCommands() throws {
        #expect(MedtronicOpcode.setBasalProfileA.isWriteCommand)
        #expect(MedtronicOpcode.setBasalProfileB.isWriteCommand)
        #expect(MedtronicOpcode.setBasalProfileStandard.isWriteCommand)
    }
    
    /// Test basal schedule command opcode selection by profile
    @Test("Basal schedule command opcode selection")
    func basalScheduleCommandOpcodeSelection() throws {
        let standardCmd = MedtronicBasalScheduleCommand(entries: [], profile: .standard)
        #expect(standardCmd.opcode == .setBasalProfileStandard)
        
        let profileACmd = MedtronicBasalScheduleCommand(entries: [], profile: .profileA)
        #expect(profileACmd.opcode == .setBasalProfileA)
        
        let profileBCmd = MedtronicBasalScheduleCommand(entries: [], profile: .profileB)
        #expect(profileBCmd.opcode == .setBasalProfileB)
    }
    
    /// Test basal schedule entry raw value encoding
    /// Reference: MinimedKit BasalScheduleEntry.rawValue
    @Test("Basal schedule entry encoding")
    func basalScheduleEntryEncoding() throws {
        // Entry: 1.0 U/hr at midnight (slot 0)
        // rate * 40 = 40 = 0x0028 little-endian
        let entry1 = MedtronicBasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0)
        #expect(entry1.rawValue == Data([0x28, 0x00, 0x00]))
        
        // Entry: 2.0 U/hr at 4:00 AM (slot 8)
        // rate * 40 = 80 = 0x0050 little-endian
        let entry2 = MedtronicBasalScheduleEntry(index: 1, timeOffset: 4 * 3600, rate: 2.0)
        #expect(entry2.rawValue == Data([0x50, 0x00, 0x08]))
    }
    
    /// Test basal schedule raw value matches Loop test vector
    /// Reference: MinimedKit BasalScheduleTests.testTxData
    @Test("Basal schedule raw value matches Loop")
    func basalScheduleRawValueMatchesLoop() throws {
        // From BasalScheduleTests.swift:
        // entries: 1.0 U/hr at 0:00, 2.0 U/hr at 4:00
        // Expected: "280000500008000000..."
        let entries = [
            MedtronicBasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0),
            MedtronicBasalScheduleEntry(index: 1, timeOffset: 4 * 3600, rate: 2.0),
        ]
        let cmd = MedtronicBasalScheduleCommand(entries: entries, profile: .standard)
        
        let rawValue = cmd.rawValue
        #expect(rawValue.count == 192)
        
        // Check first 6 bytes (2 entries × 3 bytes each)
        #expect(rawValue[0] == 0x28)
        #expect(rawValue[1] == 0x00)
        #expect(rawValue[2] == 0x00)
        #expect(rawValue[3] == 0x50)
        #expect(rawValue[4] == 0x00)
        #expect(rawValue[5] == 0x08)
        
        // Rest should be zeros
        for i in 6..<192 {
            #expect(rawValue[i] == 0x00)
        }
    }
    
    /// Test frame splitting matches Loop DataFrameMessageBody pattern
    @Test("Basal schedule frame splitting")
    func basalScheduleFrameSplitting() throws {
        let entries = [
            MedtronicBasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0),
        ]
        let cmd = MedtronicBasalScheduleCommand(entries: entries, profile: .standard)
        
        let frames = cmd.frames
        #expect(frames.count == 3)
        
        // Each frame should be 65 bytes (CarelinkLongMessageBody.length)
        for (i, frame) in frames.enumerated() {
            #expect(frame.count == 65, "Frame \(i) should be 65 bytes")
        }
        
        // Frame 0: header=0x01 (frame 1, not last)
        #expect(frames[0][0] == 0x01)
        
        // Frame 1: header=0x02 (frame 2, not last)
        #expect(frames[1][0] == 0x02)
        
        // Frame 2: header=0x83 (frame 3, IS last - bit 7 set)
        #expect(frames[2][0] == 0x83)
    }
    
    /// Test frame content matches Loop test vectors
    /// Reference: MinimedKit BasalScheduleTests.testDataFrameParsing
    @Test("Basal schedule frame content matches Loop")
    func basalScheduleFrameContentMatchesLoop() throws {
        // Using Loop's test data for full validation
        let entries = [
            MedtronicBasalScheduleEntry(index: 0, timeOffset: 0, rate: 1.0),
            MedtronicBasalScheduleEntry(index: 1, timeOffset: 4 * 3600, rate: 2.0),
        ]
        let cmd = MedtronicBasalScheduleCommand(entries: entries, profile: .standard)
        
        let frames = cmd.frames
        
        // First frame should start with: 01 28 00 00 50 00 08 00...
        // (header=01, then first 64 bytes of content)
        #expect(frames[0][0] == 0x01)
        #expect(frames[0][1] == 0x28)
        #expect(frames[0][2] == 0x00)
        #expect(frames[0][3] == 0x00)
        #expect(frames[0][4] == 0x50)
        #expect(frames[0][5] == 0x00)
        #expect(frames[0][6] == 0x08)
    }
    
    /// Test empty schedule marker
    @Test("Empty basal schedule marker")
    func emptyBasalScheduleMarker() throws {
        let cmd = MedtronicBasalScheduleCommand(entries: [], profile: .standard)
        let rawValue = cmd.rawValue
        
        // Empty schedule should have 0x3F in byte 2
        #expect(rawValue[2] == 0x3F)
    }
    
    /// Test entry parsing round-trip
    @Test("Basal schedule entry round trip")
    func basalScheduleEntryRoundTrip() throws {
        let original = MedtronicBasalScheduleEntry(index: 5, timeOffset: 2.5 * 3600, rate: 0.85)
        let parsed = try #require(MedtronicBasalScheduleEntry(rawValue: original.rawValue))
        
        #expect(abs(parsed.rate - original.rate) < 0.025)
        #expect(parsed.timeOffset == original.timeOffset)
    }
}
