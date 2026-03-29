// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MedtronicIntegrationTests.swift
// PumpKitTests
//
// APP-INT-005/006/007: Medtronic pump integration tests
// Tests model detection, status parsing, and temp basal command round-trip
// using fixtures and simulation mode (no hardware required).
//
// Trace: APP-INT-005, APP-INT-006, APP-INT-007, PUMP-MDT-006

import Testing
import Foundation
@testable import PumpKit

// MARK: - APP-INT-005: Pump Model Detection Tests

@Suite("APP-INT-005: Medtronic Model Detection")
struct MedtronicModelDetectionTests {
    
    // MARK: - Model String Parsing from Response Bytes
    
    @Test("Parse model 515 from fixture response")
    func parseModel515FromFixture() throws {
        // From fixture_read_model.json: body_preview = "09 03 35 31 35 00..."
        // Model string "515" is ASCII bytes at positions 2-4: 0x35='5', 0x31='1', 0x35='5'
        let responseBody = Data([0x09, 0x03, 0x35, 0x31, 0x35, 0x00, 0x00, 0x00])
        
        // Extract model string (bytes 2-4, ASCII)
        let modelBytes = responseBody.subdata(in: 2..<5)
        let modelString = String(data: modelBytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
        
        #expect(modelString == "515")
        
        // Verify model enum can be created
        let model = MinimedPumpModel(rawValue: modelString!)
        #expect(model == .model515)
        #expect(model?.isPre523 == true)
        #expect(model?.insulinBitPackingScale == 10)
    }
    
    @Test("Parse model 554 from synthesized response")
    func parseModel554FromResponse() throws {
        // Synthesized: Model 554 response body
        let responseBody = Data([0x09, 0x03, 0x35, 0x35, 0x34, 0x00, 0x00, 0x00])
        
        let modelBytes = responseBody.subdata(in: 2..<5)
        let modelString = String(data: modelBytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
        
        #expect(modelString == "554")
        
        let model = MinimedPumpModel(rawValue: modelString!)
        #expect(model == .model554)
        #expect(model?.isPre523 == false)
        #expect(model?.insulinBitPackingScale == 40)
    }
    
    @Test("Parse model 723 from synthesized response")
    func parseModel723FromResponse() throws {
        // Synthesized: Model 723 response body
        let responseBody = Data([0x09, 0x03, 0x37, 0x32, 0x33, 0x00, 0x00, 0x00])
        
        let modelBytes = responseBody.subdata(in: 2..<5)
        let modelString = String(data: modelBytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
        
        #expect(modelString == "723")
        
        let model = MinimedPumpModel(rawValue: modelString!)
        #expect(model == .model723)
        #expect(model?.reservoirCapacity == 300) // Large reservoir
    }
    
    @Test("Parse model 522 from synthesized response")
    func parseModel522FromResponse() throws {
        // Synthesized: Model 522 response (pre-523, scale=10)
        let responseBody = Data([0x09, 0x03, 0x35, 0x32, 0x32, 0x00, 0x00, 0x00])
        
        let modelBytes = responseBody.subdata(in: 2..<5)
        let modelString = String(data: modelBytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters)
        
        #expect(modelString == "522")
        
        let model = MinimedPumpModel(rawValue: modelString!)
        #expect(model == .model522)
        #expect(model?.isPre523 == true) // Important: 522 is pre-523!
        #expect(model?.insulinBitPackingScale == 10)
    }
    
    // MARK: - Model-to-Variant Mapping
    
    @Test("All model strings map to valid enum cases")
    func allModelStringsMapToEnums() {
        // MDT-BUG-002: Test all 20 pump models (including 711/712/715/540/740/551/751)
        let testCases: [(String, MinimedPumpModel)] = [
            // Pre-523 models (scale=10)
            ("508", .model508),
            ("511", .model511),
            ("711", .model711),  // MDT-BUG-002: Added 7xx variant
            ("512", .model512),
            ("712", .model712),  // MDT-BUG-002: Added 7xx variant
            ("515", .model515),
            ("715", .model715),  // MDT-BUG-002: Added 7xx variant
            ("522", .model522),
            ("722", .model722),
            // 523+ models (scale=40)
            ("523", .model523),
            ("723", .model723),
            ("530", .model530),
            ("730", .model730),
            ("540", .model540),  // MDT-BUG-002: Added
            ("740", .model740),  // MDT-BUG-002: Added
            ("551", .model551),  // MDT-BUG-002: Added (has low suspend)
            ("751", .model751),  // MDT-BUG-002: Added (has low suspend)
            ("554", .model554),
            ("754", .model754),
        ]
        
        for (modelString, expectedModel) in testCases {
            let model = MinimedPumpModel(rawValue: modelString)
            #expect(model == expectedModel, "Model '\(modelString)' should map to \(expectedModel)")
        }
    }
    
    // MDT-TEST-001: Test insulinBitPackingScale for all pump models
    @Test("InsulonBitPackingScale correct for all models")
    func insulinBitPackingScaleForAllModels() {
        // Pre-523 models should have scale=10
        let pre523Models: [MinimedPumpModel] = [
            .model508, .model511, .model711,
            .model512, .model712,
            .model515, .model715,
            .model522, .model722
        ]
        for model in pre523Models {
            #expect(model.insulinBitPackingScale == 10, "\(model.rawValue) should have scale 10")
            #expect(model.isPre523 == true, "\(model.rawValue) should be pre-523")
        }
        
        // 523+ models should have scale=40
        let post523Models: [MinimedPumpModel] = [
            .model523, .model723,
            .model530, .model730,
            .model540, .model740,
            .model551, .model751,
            .model554, .model754
        ]
        for model in post523Models {
            #expect(model.insulinBitPackingScale == 40, "\(model.rawValue) should have scale 40")
            #expect(model.isPre523 == false, "\(model.rawValue) should NOT be pre-523")
        }
    }
    
    // MDT-TEST-001: Test reservoir capacity by size
    @Test("Reservoir capacity correct for all models")
    func reservoirCapacityForAllModels() {
        // 5xx models = 176U (small)
        let smallModels: [MinimedPumpModel] = [
            .model508, .model511, .model512, .model515, .model522,
            .model523, .model530, .model540, .model551, .model554
        ]
        for model in smallModels {
            #expect(model.reservoirCapacity == 176, "\(model.rawValue) should have 176U capacity")
        }
        
        // 7xx models = 300U (large)
        let largeModels: [MinimedPumpModel] = [
            .model711, .model712, .model715, .model722,
            .model723, .model730, .model740, .model751, .model754
        ]
        for model in largeModels {
            #expect(model.reservoirCapacity == 300, "\(model.rawValue) should have 300U capacity")
        }
    }
    
    // MDT-TEST-001: Test low suspend feature detection
    @Test("Low suspend feature correct for 551+ models")
    func lowSuspendFeatureDetection() {
        // Models with low suspend (generation >= 51)
        let lowSuspendModels: [MinimedPumpModel] = [.model551, .model751, .model554, .model754]
        for model in lowSuspendModels {
            #expect(model.hasLowSuspend == true, "\(model.rawValue) should have low suspend")
        }
        
        // Models without low suspend
        let noLowSuspendModels: [MinimedPumpModel] = [
            .model508, .model511, .model711, .model512, .model712,
            .model515, .model715, .model522, .model722,
            .model523, .model723, .model530, .model730, .model540, .model740
        ]
        for model in noLowSuspendModels {
            #expect(model.hasLowSuspend == false, "\(model.rawValue) should NOT have low suspend")
        }
    }
    
    @Test("Unknown model string returns nil")
    func unknownModelReturnsNil() {
        let unknownModel = MinimedPumpModel(rawValue: "999")
        #expect(unknownModel == nil)
        
        let invalidModel = MinimedPumpModel(rawValue: "ABC")
        #expect(invalidModel == nil)
    }
}

// MARK: - APP-INT-006: Pump Status Reading Tests

@Suite("APP-INT-006: Medtronic Status Reading")
struct MedtronicStatusReadingTests {
    
    // MARK: - Reservoir Level Parsing
    
    @Test("Parse reservoir 120U for model 515 (pre-523)")
    func parseReservoir515_120U() throws {
        // From fixture_reservoir.json: Model 515 - 120.0U
        // Body bytes[1:3] = 0x04B0 = 1200 strokes -> 1200/10 = 120.0U
        let body = Data([0x00, 0x04, 0xB0])
        let scale = MinimedPumpModel.model515.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 120.0)
    }
    
    @Test("Parse reservoir 135U for model 522 (pre-523)")
    func parseReservoir522_135U() throws {
        // From fixture_reservoir.json: Loop Test Vector - Model 522 135.0U
        let body = Data([0x02, 0x05, 0x46])
        let scale = MinimedPumpModel.model522.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 135.0)
    }
    
    @Test("Parse reservoir 80.875U for model 723 (523+)")
    func parseReservoir723_80_875U() throws {
        // From fixture_reservoir.json: Loop Test Vector - Model 723 80.875U
        // Body bytes[3:5] = 0x0CA3 = 3235 strokes -> 3235/40 = 80.875U
        let body = Data([0x04, 0x00, 0x00, 0x0C, 0xA3])
        let scale = MinimedPumpModel.model723.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(abs(result.unitsRemaining - 80.875) < 0.001)
    }
    
    @Test("Parse reservoir 200U for model 554 (523+)")
    func parseReservoir554_200U() throws {
        // From fixture_reservoir.json: Model 554 - 200.0U full
        let body = Data([0x00, 0x00, 0x00, 0x1F, 0x40])
        let scale = MinimedPumpModel.model554.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 200.0)
    }
    
    @Test("Parse reservoir 300U for model 754 (large reservoir)")
    func parseReservoir754_300U() throws {
        // 12000 strokes / 40 = 300.0U
        let body = Data([0x00, 0x00, 0x00, 0x2E, 0xE0])
        let scale = MinimedPumpModel.model754.insulinBitPackingScale
        
        let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: scale))
        #expect(result.unitsRemaining == 300.0)
    }
    
    @Test("Parse empty reservoir (0U)")
    func parseReservoirEmpty() throws {
        // Pre-523: 0 strokes
        let bodyPre523 = Data([0x00, 0x00, 0x00])
        let resultPre523 = try #require(MedtronicReservoirResponse.parse(from: bodyPre523, scale: 10))
        #expect(resultPre523.unitsRemaining == 0.0)
        
        // 523+: 0 strokes
        let body523 = Data([0x00, 0x00, 0x00, 0x00, 0x00])
        let result523 = try #require(MedtronicReservoirResponse.parse(from: body523, scale: 40))
        #expect(result523.unitsRemaining == 0.0)
    }
    
    // MARK: - Battery Status Parsing
    
    @Test("Parse battery normal status")
    func parseBatteryNormal() throws {
        // status=0 (normal), voltage=1.52V (0x0098 / 100)
        let body = Data([0x00, 0x00, 0x98])
        
        let result = try #require(MedtronicBatteryResponse.parse(from: body))
        #expect(result.status == .normal)
        #expect(abs(result.volts - 1.52) < 0.01)
        #expect(result.estimatedPercent > 80) // ~93%
    }
    
    @Test("Parse battery low status")
    func parseBatteryLow() throws {
        // status=1 (low), voltage=1.15V (0x0073 / 100)
        let body = Data([0x01, 0x00, 0x73])
        
        let result = try #require(MedtronicBatteryResponse.parse(from: body))
        #expect(result.status == .low)
        #expect(abs(result.volts - 1.15) < 0.01)
        #expect(result.estimatedPercent < 20) // ~11%
    }
    
    @Test("Parse battery with typical voltages")
    func parseBatteryTypicalVoltages() throws {
        let testCases: [(Data, Double, Int)] = [
            // (body, expectedVolts, minExpectedPercent)
            (Data([0x00, 0x00, 0x9B]), 1.55, 90),  // Full
            (Data([0x00, 0x00, 0x8C]), 1.40, 60),  // Good
            (Data([0x00, 0x00, 0x7D]), 1.25, 30),  // Medium
            (Data([0x01, 0x00, 0x6E]), 1.10, 0),   // Empty
        ]
        
        for (body, expectedVolts, minPercent) in testCases {
            let result = try #require(MedtronicBatteryResponse.parse(from: body))
            #expect(abs(result.volts - expectedVolts) < 0.01, "Expected \(expectedVolts)V")
            #expect(result.estimatedPercent >= minPercent, "Expected >= \(minPercent)%")
        }
    }
    
    // MARK: - Status Response Parsing
    
    @Test("Parse normal status (not bolusing, not suspended)")
    func parseStatusNormal() throws {
        // [status=03][bolusing=0][suspended=0]
        let body = Data([0x03, 0x00, 0x00])
        
        let result = try #require(MedtronicStatusResponse.parse(from: body))
        #expect(result.bolusing == false)
        #expect(result.suspended == false)
        #expect(result.canDeliver == true)
    }
    
    @Test("Parse suspended status")
    func parseStatusSuspended() throws {
        // [status=03][bolusing=0][suspended=1]
        let body = Data([0x03, 0x00, 0x01])
        
        let result = try #require(MedtronicStatusResponse.parse(from: body))
        #expect(result.bolusing == false)
        #expect(result.suspended == true)
        #expect(result.canDeliver == false)
    }
    
    @Test("Parse bolusing status")
    func parseStatusBolusing() throws {
        // [status=03][bolusing=1][suspended=0]
        let body = Data([0x03, 0x01, 0x00])
        
        let result = try #require(MedtronicStatusResponse.parse(from: body))
        #expect(result.bolusing == true)
        #expect(result.suspended == false)
        #expect(result.canDeliver == false) // Can't deliver while bolusing
    }
    
    // MARK: - IOB/Active Insulin
    
    @Test("Status response IOB field")
    func statusResponseIOB() {
        let status = MedtronicStatusResponse(
            bolusing: false,
            suspended: false,
            normalBasalRunning: true,
            tempBasalRunning: false,
            reservoirLevel: 150.0,
            batteryPercent: 80,
            activeInsulin: 2.5
        )
        
        #expect(status.activeInsulin == 2.5)
        #expect(status.canDeliver == true)
        #expect(status.isLowReservoir == false)
        #expect(status.isLowBattery == false)
    }
    
    @Test("Status low reservoir detection")
    func statusLowReservoirDetection() {
        let lowReservoir = MedtronicStatusResponse(
            reservoirLevel: 15.0,
            batteryPercent: 80
        )
        #expect(lowReservoir.isLowReservoir == true)
        
        let normalReservoir = MedtronicStatusResponse(
            reservoirLevel: 25.0,
            batteryPercent: 80
        )
        #expect(normalReservoir.isLowReservoir == false)
    }
    
    @Test("Status low battery detection")
    func statusLowBatteryDetection() {
        let lowBattery = MedtronicStatusResponse(
            reservoirLevel: 100.0,
            batteryPercent: 15
        )
        #expect(lowBattery.isLowBattery == true)
        
        let normalBattery = MedtronicStatusResponse(
            reservoirLevel: 100.0,
            batteryPercent: 25
        )
        #expect(normalBattery.isLowBattery == false)
    }
}

// MARK: - APP-INT-007: Temp Basal Command Round-Trip Tests

@Suite("APP-INT-007: Temp Basal Round-Trip")
struct MedtronicTempBasalRoundTripTests {
    
    /// Helper to create command with minutes instead of seconds
    private func makeCommand(rate: Double, durationMinutes: Int) -> MedtronicTempBasalCommand {
        MedtronicTempBasalCommand(unitsPerHour: rate, duration: TimeInterval(durationMinutes * 60))
    }
    
    // MARK: - Command Encoding (Rate → Strokes)
    
    @Test("Encode 1.1 U/hr @ 30min (Loop test vector)")
    func encodeTempBasal_1_1_30() throws {
        // From fixture_tempbasal_tx.json: 1.1 U/hr * 40 = 44 strokes, 30min/30 = 1 segment
        // Expected body: [03 00 2C 01]
        let command = makeCommand(rate: 1.1, durationMinutes: 30)
        
        let body = command.txData
        #expect(body.count == 4)
        #expect(body[0] == 0x03) // Length byte
        #expect(body[1] == 0x00) // Strokes high byte
        #expect(body[2] == 0x2C) // Strokes low byte (44)
        #expect(body[3] == 0x01) // Time segments (1)
        
        // Verify encoding math
        #expect(command.strokes == 44)
        #expect(command.timeSegments == 1)
    }
    
    @Test("Encode 6.5 U/hr @ 150min (Loop test vector)")
    func encodeTempBasal_6_5_150() throws {
        // From fixture_tempbasal_tx.json: 6.5 U/hr * 40 = 260 strokes, 150min/30 = 5 segments
        // Expected body: [03 01 04 05]
        let command = makeCommand(rate: 6.5, durationMinutes: 150)
        
        let body = command.txData
        #expect(body[0] == 0x03)
        #expect(body[1] == 0x01) // Strokes high byte (260 >> 8 = 1)
        #expect(body[2] == 0x04) // Strokes low byte (260 & 0xFF = 4)
        #expect(body[3] == 0x05) // Time segments (5)
        
        #expect(command.strokes == 260)
        #expect(command.timeSegments == 5)
    }
    
    @Test("Encode 0 U/hr @ 30min (suspend)")
    func encodeTempBasal_0_30() throws {
        // 0 U/hr = suspend (common for AID)
        // Expected body: [03 00 00 01]
        let command = makeCommand(rate: 0.0, durationMinutes: 30)
        
        let body = command.txData
        #expect(body[0] == 0x03)
        #expect(body[1] == 0x00)
        #expect(body[2] == 0x00)
        #expect(body[3] == 0x01)
        
        #expect(command.strokes == 0)
    }
    
    @Test("Encode 0.5 U/hr @ 60min")
    func encodeTempBasal_0_5_60() throws {
        // 0.5 U/hr * 40 = 20 strokes, 60min/30 = 2 segments
        // Expected body: [03 00 14 02]
        let command = makeCommand(rate: 0.5, durationMinutes: 60)
        
        let body = command.txData
        #expect(body[1] == 0x00)
        #expect(body[2] == 0x14) // 20
        #expect(body[3] == 0x02)
        
        #expect(command.strokes == 20)
        #expect(command.timeSegments == 2)
    }
    
    @Test("Encode 35 U/hr @ 30min (max rate)")
    func encodeTempBasal_35_30() throws {
        // 35 U/hr * 40 = 1400 strokes
        // Expected body: [03 05 78 01]
        let command = makeCommand(rate: 35.0, durationMinutes: 30)
        
        let body = command.txData
        #expect(body[1] == 0x05)
        #expect(body[2] == 0x78)
        
        #expect(command.strokes == 1400)
    }
    
    @Test("Encode 2.0 U/hr @ 1440min (max duration)")
    func encodeTempBasal_2_1440() throws {
        // 2.0 U/hr * 40 = 80 strokes, 1440min/30 = 48 segments
        // Expected body: [03 00 50 30]
        let command = makeCommand(rate: 2.0, durationMinutes: 1440)
        
        let body = command.txData
        #expect(body[2] == 0x50) // 80
        #expect(body[3] == 0x30) // 48
        
        #expect(command.timeSegments == 48)
    }
    
    @Test("Encode 0.025 U/hr @ 30min (minimum rate)")
    func encodeTempBasal_0_025_30() throws {
        // 0.025 U/hr * 40 = 1 stroke (minimum non-zero)
        // Expected body: [03 00 01 01]
        let command = makeCommand(rate: 0.025, durationMinutes: 30)
        
        let body = command.txData
        #expect(body[2] == 0x01)
        
        #expect(command.strokes == 1)
    }
    
    // MARK: - Rounding Behavior
    
    @Test("Rate rounds down to nearest stroke (1.442 U/hr → 1.425)")
    func rateRoundsDown() throws {
        // 1.442 U/hr * 40 = 57.68 → 57 strokes = 1.425 U/hr
        let command = makeCommand(rate: 1.442, durationMinutes: 30)
        
        #expect(command.strokes == 57)
        #expect(command.deliveredRate == 1.425)
    }
    
    @Test("Duration rounds down to nearest segment (65min → 60min)")
    func durationRoundsDown() throws {
        // 65 min / 30 = 2.16 → 2 segments = 60 min
        let command = makeCommand(rate: 1.0, durationMinutes: 65)
        
        #expect(command.timeSegments == 2)
        #expect(command.deliveredDurationMinutes == 60)
    }
    
    // MARK: - Decode from Bytes (Round-Trip)
    
    @Test("Decode 1.1 U/hr @ 30min from bytes")
    func decodeTempBasal_1_1_30() throws {
        let body = Data([0x03, 0x00, 0x2C, 0x01])
        
        let decoded = try #require(MedtronicTempBasalCommand.parse(from: body))
        #expect(decoded.deliveredRate == 1.1)
        #expect(decoded.deliveredDurationMinutes == 30)
    }
    
    @Test("Decode 6.5 U/hr @ 150min from bytes")
    func decodeTempBasal_6_5_150() throws {
        let body = Data([0x03, 0x01, 0x04, 0x05])
        
        let decoded = try #require(MedtronicTempBasalCommand.parse(from: body))
        #expect(decoded.deliveredRate == 6.5)
        #expect(decoded.deliveredDurationMinutes == 150)
    }
    
    @Test("Round-trip encoding preserves values")
    func roundTripEncoding() throws {
        let testCases: [(Double, Int)] = [
            (0.0, 30),
            (0.5, 60),
            (1.0, 30),
            (1.5, 90),
            (2.0, 120),
            (5.0, 180),
            (10.0, 240),
            (25.0, 30),
        ]
        
        for (rate, durationMinutes) in testCases {
            let original = makeCommand(rate: rate, durationMinutes: durationMinutes)
            let encoded = original.txData
            let decoded = try #require(MedtronicTempBasalCommand.parse(from: encoded))
            
            #expect(decoded.deliveredRate == original.deliveredRate,
                   "Rate mismatch for \(rate) U/hr")
            #expect(decoded.deliveredDurationMinutes == original.deliveredDurationMinutes,
                   "Duration mismatch for \(durationMinutes) min")
        }
    }
    
    // MARK: - Validation
    
    @Test("Reject too-short body")
    func rejectTooShortBody() {
        let shortBody = Data([0x03, 0x00])
        let result = MedtronicTempBasalCommand.parse(from: shortBody)
        #expect(result == nil)
    }
    
    @Test("Reject invalid length byte")
    func rejectInvalidLengthByte() {
        // Length byte should be 0x03
        let badLength = Data([0x05, 0x00, 0x14, 0x02])
        let result = MedtronicTempBasalCommand.parse(from: badLength)
        #expect(result == nil)
    }
}

// MARK: - MDT-TEST-002: Reservoir Parsing Tests with Scale 10 vs 40

@Suite("MDT-TEST-002: Reservoir Scale Parsing")
struct MedtronicReservoirScaleTests {
    
    // MDT-TEST-002: Verify same byte pattern parses differently with scale 10 vs 40
    @Test("Same stroke count parses to different units with scale 10 vs 40")
    func scaleAffectsUnits() throws {
        // 1000 strokes encoded in pre-523 format (3 bytes)
        // bytes[1:3] = 0x03E8 = 1000
        let pre523Body = Data([0x00, 0x03, 0xE8])
        
        let resultScale10 = try #require(MedtronicReservoirResponse.parse(from: pre523Body, scale: 10))
        #expect(resultScale10.unitsRemaining == 100.0, "1000 strokes / 10 = 100U")
        
        // Same stroke count in 523+ format (5 bytes)
        // bytes[3:5] = 0x03E8 = 1000
        let post523Body = Data([0x00, 0x00, 0x00, 0x03, 0xE8])
        
        let resultScale40 = try #require(MedtronicReservoirResponse.parse(from: post523Body, scale: 40))
        #expect(resultScale40.unitsRemaining == 25.0, "1000 strokes / 40 = 25U")
    }
    
    // MDT-TEST-002: Test all pre-523 models parse with scale 10
    @Test("All pre-523 models use scale 10 for reservoir parsing")
    func pre523ModelsUseScale10() throws {
        let pre523Models: [MinimedPumpModel] = [
            .model508, .model511, .model711,
            .model512, .model712,
            .model515, .model715,
            .model522, .model722
        ]
        
        // 800 strokes -> 80U at scale 10
        let body = Data([0x00, 0x03, 0x20])  // 0x0320 = 800
        
        for model in pre523Models {
            let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: model.insulinBitPackingScale))
            #expect(result.unitsRemaining == 80.0, "\(model.rawValue) should parse 800 strokes as 80U")
        }
    }
    
    // MDT-TEST-002: Test all 523+ models parse with scale 40
    @Test("All 523+ models use scale 40 for reservoir parsing")
    func post523ModelsUseScale40() throws {
        let post523Models: [MinimedPumpModel] = [
            .model523, .model723,
            .model530, .model730,
            .model540, .model740,
            .model551, .model751,
            .model554, .model754
        ]
        
        // 4000 strokes -> 100U at scale 40
        let body = Data([0x00, 0x00, 0x00, 0x0F, 0xA0])  // 0x0FA0 = 4000
        
        for model in post523Models {
            let result = try #require(MedtronicReservoirResponse.parse(from: body, scale: model.insulinBitPackingScale))
            #expect(result.unitsRemaining == 100.0, "\(model.rawValue) should parse 4000 strokes as 100U")
        }
    }
    
    // MDT-TEST-002: Verify precision at scale boundaries
    @Test("Scale 40 enables 0.025U precision")
    func scale40EnablesHighPrecision() throws {
        // 1 stroke at scale 40 = 0.025U
        let body1Stroke = Data([0x00, 0x00, 0x00, 0x00, 0x01])
        let result1 = try #require(MedtronicReservoirResponse.parse(from: body1Stroke, scale: 40))
        #expect(abs(result1.unitsRemaining - 0.025) < 0.001, "1 stroke / 40 = 0.025U")
        
        // 3 strokes at scale 40 = 0.075U
        let body3Strokes = Data([0x00, 0x00, 0x00, 0x00, 0x03])
        let result3 = try #require(MedtronicReservoirResponse.parse(from: body3Strokes, scale: 40))
        #expect(abs(result3.unitsRemaining - 0.075) < 0.001, "3 strokes / 40 = 0.075U")
    }
    
    // MDT-TEST-002: Verify precision at scale 10
    @Test("Scale 10 has 0.1U precision")
    func scale10Has01UPrecision() throws {
        // 1 stroke at scale 10 = 0.1U
        let body1Stroke = Data([0x00, 0x00, 0x01])
        let result1 = try #require(MedtronicReservoirResponse.parse(from: body1Stroke, scale: 10))
        #expect(abs(result1.unitsRemaining - 0.1) < 0.001, "1 stroke / 10 = 0.1U")
        
        // 15 strokes at scale 10 = 1.5U
        let body15Strokes = Data([0x00, 0x00, 0x0F])
        let result15 = try #require(MedtronicReservoirResponse.parse(from: body15Strokes, scale: 10))
        #expect(abs(result15.unitsRemaining - 1.5) < 0.001, "15 strokes / 10 = 1.5U")
    }
}
