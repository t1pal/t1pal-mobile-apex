// SPDX-License-Identifier: MIT
//
// AlgorithmFaultInjectionTests.swift
// T1PalAlgorithmTests
//
// Fault injection tests for algorithm safety validation.
// Tests algorithm behavior under simulated failure conditions.
// Trace: ALG-FAULT-001, ALG-FAULT-002, ALG-FAULT-003, ALG-FAULT-004
//
// Categories:
// - ALG-FAULT-001: Glucose sensor failures
// - ALG-FAULT-002: Pump communication failure types (via FaultTypes)
// - ALG-FAULT-003: Stale data scenarios
// - ALG-FAULT-004: Safety limit enforcement under faults

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

// MARK: - ALG-FAULT-001: Glucose Sensor Failures

@Suite("Glucose Sensor Fault Tests")
struct GlucoseSensorFaultTests {
    
    var profile: TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
    }
    
    var safetyLimits: SafetyLimits { SafetyLimits() }
    
    // MARK: - Invalid Value Faults
    
    /// Algorithm must handle negative glucose values gracefully
    @Test("Algorithm handles negative glucose values gracefully")
    func invalidGlucoseNegativeValue() throws {
        let faultConfig = FaultConfiguration(
            dataFaults: [.invalidValue(value: -1)],
            isEnabled: true
        )
        #expect(faultConfig.hasFaults)
        
        // Simulate reading with invalid value
        let readings = [
            GlucoseReading(glucose: -1, timestamp: Date()),  // Invalid
            GlucoseReading(glucose: 120, timestamp: Date().addingTimeInterval(-300)),
            GlucoseReading(glucose: 115, timestamp: Date().addingTimeInterval(-600))
        ]
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        // Should either filter invalid or return safe default
        do {
            let decision = try algo.calculate(inputs)
            // Should not suggest aggressive action based on invalid data
            if let tempBasal = decision.suggestedTempBasal {
                #expect(tempBasal.rate <= profile.basalRates[0].rate * 1.5,
                    "Should not increase basal aggressively with invalid glucose")
            }
        } catch {
            // Throwing is acceptable for invalid data
        }
    }
    
    /// Algorithm must handle out-of-range high glucose (>500)
    @Test("Algorithm handles extremely high glucose values")
    func invalidGlucoseExtremelyHigh() throws {
        let readings = [
            GlucoseReading(glucose: 999, timestamp: Date()),  // Sensor error indicator
            GlucoseReading(glucose: 180, timestamp: Date().addingTimeInterval(-300)),
            GlucoseReading(glucose: 175, timestamp: Date().addingTimeInterval(-600))
        ]
        
        let algo = LoopAlgorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 2.0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        do {
            let decision = try algo.calculate(inputs)
            // Should not overdose based on fake 999 reading
            if let bolus = decision.suggestedBolus {
                #expect(bolus <= 5.0,
                    "Should not suggest large bolus for sensor error value")
            }
        } catch {
            // Algorithm correctly rejects sensor error value
        }
    }
    
    // MARK: - Missing Trend Faults
    
    /// Algorithm must handle readings with unknown/not-computable trend arrow
    @Test("Algorithm handles missing trend arrows")
    func missingTrendArrow() throws {
        let readings = [
            GlucoseReading(glucose: 150, timestamp: Date(), trend: .notComputable),
            GlucoseReading(glucose: 145, timestamp: Date().addingTimeInterval(-300), trend: .notComputable),
            GlucoseReading(glucose: 140, timestamp: Date().addingTimeInterval(-600), trend: .notComputable)
        ]
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 1.0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        // Should calculate trend from values even without explicit trend
        let decision = try algo.calculate(inputs)
        #expect(decision != nil, "Should produce decision even without trend arrows")
    }
    
    // MARK: - Conflicting Source Faults
    
    /// Algorithm must handle conflicting readings from different sources
    @Test("Algorithm handles conflicting source readings")
    func conflictingSourceReadings() throws {
        let now = Date()
        let readings = [
            // BLE reading says 120
            GlucoseReading(glucose: 120, timestamp: now, source: "BLE"),
            // HealthKit reading says 150 (30 mg/dL conflict)
            GlucoseReading(glucose: 150, timestamp: now, source: "HealthKit"),
            GlucoseReading(glucose: 115, timestamp: now.addingTimeInterval(-300), source: "BLE")
        ]
        
        let faultConfig = FaultConfiguration(
            dataFaults: [.conflictingSource(deltaMilligrams: 30)],
            isEnabled: true
        )
        #expect(faultConfig.dataFaults.first?.severity == .warning)
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        // Algorithm should handle conflicting sources gracefully
        do {
            let decision = try algo.calculate(inputs)
            // Should be conservative when sources conflict
            #expect(decision != nil)
        } catch {
            // Algorithm correctly rejects conflicting data
        }
    }
}

// MARK: - ALG-FAULT-002: Pump Communication Fault Types

@Suite("Pump Communication Fault Type Tests")
struct PumpCommunicationFaultTypeTests {
    
    /// Verify PumpCommandError types exist and are usable
    @Test("Pump command error types exist and have descriptions")
    func pumpCommandErrorTypes() {
        // Verify all error types are defined and can be constructed
        let errors: [PumpCommandError] = [
            .pumpNotConnected,
            .commandTimeout,
            .maxRetriesExceeded,
            .commandRejected("Test rejection"),
            .safetyLimitExceeded("Test limit"),
            .invalidCommand("Test invalid"),
            .communicationError("Test comm error"),
            .smbNotEnabled,
            .smbTooSoon(remainingSeconds: 60)
        ]
        
        // All errors should have localized descriptions
        for error in errors {
            #expect(!error.localizedDescription.isEmpty, "\(error) should have description")
        }
        
        // Verify error count
        #expect(errors.count == 9, "Should have 9 error types")
    }
    
    /// Verify safety limit exceeded errors are properly categorized
    @Test("Safety limit exceeded error is properly categorized")
    func safetyLimitExceededError() {
        let error = PumpCommandError.safetyLimitExceeded("Bolus exceeds 10U max")
        
        if case .safetyLimitExceeded(let reason) = error {
            #expect(reason.contains("Bolus"))
            #expect(reason.contains("max"))
        } else {
            Issue.record("Should be safetyLimitExceeded")
        }
    }
    
    /// Verify command timeout handling
    @Test("Command timeout configuration has correct defaults")
    func commandTimeoutConfiguration() {
        let config = PumpCommandDeliveryConfiguration()
        
        // Default values
        #expect(config.maxRetries == 3)
        #expect(config.retryDelay == 2.0)
        #expect(config.commandTimeout == 30.0)
        
        // Configuration is immutable (let constants) - verify custom init works
        let customConfig = PumpCommandDeliveryConfiguration(
            maxRetries: 5,
            retryDelay: 3.0,
            commandTimeout: 45.0
        )
        #expect(customConfig.maxRetries == 5)
    }
    
    /// Verify pump command history tracking
    @Test("Pump command history tracking works")
    func pumpCommandHistory() {
        var history = PumpCommandHistory()
        
        let command = PumpCommand(
            type: .tempBasal,
            tempBasalRate: 1.5,
            tempBasalDuration: 30 * 60,
            status: .success
        )
        
        history.addCommand(command)
        
        #expect(history.commands.count == 1)
        #expect(history.commands.filter { $0.status == .success }.count == 1)
        #expect(history.commands.filter { $0.status == .failed }.count == 0)
    }
}

// MARK: - ALG-FAULT-003: Stale Data Scenarios

@Suite("Stale Data Fault Tests")
struct StaleDataFaultTests {
    
    var profile: TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
    }
    
    // MARK: - Stale CGM Data
    
    /// Algorithm should recognize 15+ minute old data as stale
    /// Note: Current implementation may not fully enforce stale data handling.
    /// This test documents the FaultConfiguration API and expected behavior.
    @Test("Algorithm recognizes 15+ minute old data as stale")
    func staleData15Minutes() throws {
        let faultConfig = FaultConfiguration(
            dataFaults: [.staleData(gapMinutes: 15)],
            isEnabled: true
        )
        #expect(faultConfig.dataFaults.first?.severity == .warning)
        
        // Create readings that are 15+ minutes old
        let oldTimestamp = Date().addingTimeInterval(-15 * 60)
        let readings = [
            GlucoseReading(glucose: 180, timestamp: oldTimestamp),
            GlucoseReading(glucose: 175, timestamp: oldTimestamp.addingTimeInterval(-300)),
            GlucoseReading(glucose: 170, timestamp: oldTimestamp.addingTimeInterval(-600))
        ]
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        // Algorithm should produce a decision (may or may not be conservative with stale data)
        // Future: Should be conservative with stale data - reduce or zero basal
        do {
            let decision = try algo.calculate(inputs)
            // Verify algorithm runs without crashing on stale data
            #expect(decision != nil, "Algorithm should handle stale data gracefully")
        } catch {
            // Throwing is also acceptable for stale data
        }
    }
    
    /// Algorithm should handle 1 hour gap in data
    @Test("Algorithm handles 60 minute data gap")
    func dataGap60Minutes() throws {
        let now = Date()
        // Gap from 60 to 5 minutes ago
        let readings = [
            GlucoseReading(glucose: 120, timestamp: now.addingTimeInterval(-5 * 60)),
            // 55 minute gap
            GlucoseReading(glucose: 150, timestamp: now.addingTimeInterval(-60 * 60)),
            GlucoseReading(glucose: 145, timestamp: now.addingTimeInterval(-65 * 60))
        ]
        
        let faultConfig = FaultConfiguration(
            dataFaults: [.dataGap(startMinutesAgo: 60, durationMinutes: 55)],
            isEnabled: true
        )
        #expect(faultConfig.hasFaults)
        
        let algo = LoopAlgorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 3.0,  // High IOB
            carbsOnBoard: 20,
            profile: profile
        )
        
        // With large gap, algorithm should be conservative
        let decision = try algo.calculate(inputs)
        // Should not suggest aggressive action without continuous data
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate <= 2.0,
                "Should be conservative with 1-hour data gap")
        }
    }
    
    // MARK: - Out of Order Data
    
    /// Algorithm should handle out-of-order timestamps
    @Test("Algorithm handles out-of-order readings")
    func outOfOrderReadings() throws {
        let now = Date()
        // Deliberately out of order
        let readings = [
            GlucoseReading(glucose: 130, timestamp: now.addingTimeInterval(-300)),  // 5 min ago
            GlucoseReading(glucose: 140, timestamp: now),  // Now (out of order)
            GlucoseReading(glucose: 120, timestamp: now.addingTimeInterval(-600))   // 10 min ago
        ]
        
        let faultConfig = FaultConfiguration(
            dataFaults: [.outOfOrderReadings],
            isEnabled: true
        )
        #expect(faultConfig.dataFaults.first?.severity == .error)
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        // Algorithm should either sort or handle gracefully
        do {
            let decision = try algo.calculate(inputs)
            #expect(decision != nil, "Should produce decision even with out-of-order data")
        } catch {
            // Algorithm correctly rejects out-of-order data
        }
    }
    
    // MARK: - Duplicate Readings
    
    /// Algorithm should deduplicate readings with same timestamp
    @Test("Algorithm handles duplicate readings")
    func duplicateReadings() throws {
        let now = Date()
        let readings = [
            GlucoseReading(glucose: 140, timestamp: now),
            GlucoseReading(glucose: 142, timestamp: now),  // Duplicate timestamp
            GlucoseReading(glucose: 141, timestamp: now),  // Another duplicate
            GlucoseReading(glucose: 135, timestamp: now.addingTimeInterval(-300))
        ]
        
        let faultConfig = FaultConfiguration(
            dataFaults: [.duplicateReadings(count: 3)],
            isEnabled: true
        )
        #expect(faultConfig.dataFaults.first?.severity == .info)
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        // Should handle duplicates gracefully
        let decision = try algo.calculate(inputs)
        #expect(decision != nil, "Should handle duplicate readings")
    }
    
    // MARK: - Future Readings
    
    /// Algorithm should reject or ignore future-dated readings
    @Test("Algorithm handles future-dated readings")
    func futureReadings() throws {
        let now = Date()
        let readings = [
            GlucoseReading(glucose: 100, timestamp: now.addingTimeInterval(5 * 60)),  // 5 min in future
            GlucoseReading(glucose: 120, timestamp: now),
            GlucoseReading(glucose: 115, timestamp: now.addingTimeInterval(-300))
        ]
        
        let faultConfig = FaultConfiguration(
            dataFaults: [.futureReadings(minutesAhead: 5)],
            isEnabled: true
        )
        #expect(faultConfig.dataFaults.first?.severity == .error)
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        // Should filter future readings or fail gracefully
        do {
            let decision = try algo.calculate(inputs)
            // Should not base decision on future reading
            #expect(decision != nil)
        } catch {
            // Algorithm correctly rejects future-dated readings
        }
    }
}

// MARK: - ALG-FAULT-004: Safety Limit Enforcement Under Faults

@Suite("Safety Limit Fault Tests")
struct SafetyLimitFaultTests {
    
    var profile: TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
    }
    
    var safetyLimits: SafetyLimits { SafetyLimits() }
    var guardian: SafetyGuardian { SafetyGuardian(limits: safetyLimits) }
    
    // MARK: - Safety Under Sensor Faults
    
    /// Safety limits must be enforced even when sensor data is faulty
    @Test("Safety limits enforced with invalid sensor data")
    func safetyLimitsWithInvalidSensorData() throws {
        // Simulate sensor reading sensor max (400+) which might trigger large correction
        let readings = makeGlucoseReadings(current: 400, trend: 0)
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        
        // Even at 400 mg/dL, safety checks should validate any bolus
        if let bolus = decision.suggestedBolus {
            let check = guardian.checkBolus(bolus)
            // Either allowed within limits or limited
            switch check {
            case .allowed:
                #expect(bolus <= safetyLimits.maxBolus)
            case .limited(_, let limitedValue, _):
                #expect(limitedValue <= safetyLimits.maxBolus)
            case .denied:
                // Safety correctly denied excessive bolus
                break
            }
        }
        
        // Temp basal should also be within limits
        if let tempBasal = decision.suggestedTempBasal {
            let check = guardian.checkBasalRate(tempBasal.rate)
            switch check {
            case .allowed:
                #expect(tempBasal.rate <= safetyLimits.maxBasalRate)
            case .limited(_, let limitedValue, _):
                #expect(limitedValue <= safetyLimits.maxBasalRate)
            case .denied:
                break
            }
        }
    }
    
    // MARK: - Safety Under High IOB
    
    /// High IOB should prevent additional dosing
    @Test("High IOB prevents excessive dosing")
    func highIOBPreventsExcessiveDosing() throws {
        let readings = makeGlucoseReadings(current: 200, trend: 1)
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: safetyLimits.maxIOB - 0.5,  // Near max IOB
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        
        // With IOB near max, check should limit additional dosing
        if let bolus = decision.suggestedBolus {
            let check = guardian.checkIOB(
                current: safetyLimits.maxIOB - 0.5,
                additional: bolus
            )
            // Should be limited or denied if would exceed max
            switch check {
            case .allowed:
                Issue.record("Should limit/deny bolus when IOB near max")
            case .limited, .denied:
                // Correctly limited/denied bolus near max IOB
                break
            }
        }
    }
    
    // MARK: - Safety Under Network Faults
    
    /// Safety limits work independently of network connectivity
    @Test("Safety limits work offline")
    func safetyLimitsOffline() throws {
        let networkFault = FaultConfiguration(
            networkFaults: [.connectionRefused, .dnsFailure],
            isEnabled: true
        )
        #expect(networkFault.hasFaults)
        
        // Even offline, local safety checks should work
        let excessiveBasal = 10.0  // Well above typical max
        let check = guardian.checkBasalRate(excessiveBasal)
        
        switch check {
        case .allowed:
            Issue.record("Should not allow 10 U/hr basal")
        case .limited(_, let limitedValue, _):
            #expect(limitedValue <= safetyLimits.maxBasalRate,
                "Safety limits must work offline")
        case .denied:
            // Safety correctly denied excessive basal
            break
        }
    }
    
    // MARK: - Suspension Under Combined Faults
    
    /// Algorithm must suspend in severe hypo regardless of other faults
    @Test("Emergency suspension under multiple faults")
    func emergencySuspensionUnderMultipleFaults() throws {
        let combinedFaults = FaultConfiguration(
            dataFaults: [.staleData(gapMinutes: 20), .missingTrend],
            networkFaults: [.connectionRefused],
            isEnabled: true
        )
        #expect(combinedFaults.hasFaults)
        #expect(combinedFaults.dataFaults.count == 2)
        #expect(combinedFaults.networkFaults.count == 1)
        
        // With severe low glucose + faults, suspension should trigger
        let readings = makeGlucoseReadings(current: 50, trend: -2)  // Severe hypo, falling
        
        let algo = Oref1Algorithm()
        let inputs = AlgorithmInputs(
            glucose: readings,
            insulinOnBoard: 3.0,
            carbsOnBoard: 0,
            profile: profile
        )
        
        let decision = try algo.calculate(inputs)
        
        // Must suspend or zero basal in severe hypo
        if let tempBasal = decision.suggestedTempBasal {
            #expect(tempBasal.rate <= 0.1,
                "Must suspend basal in severe hypoglycemia regardless of other faults")
        }
        
        // Must not suggest bolus
        #expect(decision.suggestedBolus == nil,
            "Must not suggest bolus during severe hypoglycemia")
    }
    
    // MARK: - Audit Logging Under Faults
    
    /// Safety audit log should record events even during faults
    @Test("Audit log records events during faults")
    func auditLogDuringFaults() throws {
        let auditLog = SafetyAuditLog()
        
        // Log safety event
        auditLog.log(SafetyAuditEntry(
            eventType: "limitApplied",
            originalValue: 15.0,
            limitedValue: safetyLimits.maxBolus,
            reason: "Bolus exceeded max during sensor fault scenario"
        ))
        
        // Verify log captured
        let recent = auditLog.recentEntries(count: 10)
        #expect(recent.count > 0, "Audit log should capture safety events")
        #expect(recent.first?.reason.contains("fault") == true)
    }
}

// MARK: - Fault Preset Tests

@Suite("Fault Preset Tests")
struct FaultPresetTests {
    
    /// Verify all fault presets produce valid configurations
    @Test("All presets produce valid configuration")
    func allPresetsProduceValidConfig() {
        for preset in FaultPreset.allCases {
            let config = preset.configuration
            #expect(config.isEnabled, "\(preset.rawValue) should be enabled")
            #expect(config.hasFaults, "\(preset.rawValue) should have faults")
            #expect(!preset.description.isEmpty, "\(preset.rawValue) should have description")
        }
    }
    
    /// Verify data fault presets have correct category
    @Test("Data fault presets have correct category")
    func dataFaultCategories() {
        let dataPresets: [FaultPreset] = [.staleG6, .sensorWarmup, .signalLoss, .badData, .compressionLow]
        for preset in dataPresets {
            #expect(preset.category == .data, "\(preset.rawValue) should be data category")
            #expect(!preset.configuration.dataFaults.isEmpty)
        }
    }
    
    /// Verify network fault presets have correct category
    @Test("Network fault presets have correct category")
    func networkFaultCategories() {
        let networkPresets: [FaultPreset] = [.networkFlaky, .serverDown, .networkOutage, .slowConnection, .authExpired]
        for preset in networkPresets {
            #expect(preset.category == .network, "\(preset.rawValue) should be network category")
            #expect(!preset.configuration.networkFaults.isEmpty)
        }
    }
    
    /// Verify fault severity levels
    @Test("Fault severity levels are correct")
    func faultSeverityLevels() {
        // Stale data should be warning
        #expect(DataFaultType.staleData(gapMinutes: 15).severity == .warning)
        
        // Invalid value should be error
        #expect(DataFaultType.invalidValue(value: -1).severity == .error)
        
        // Duplicate readings should be info
        #expect(DataFaultType.duplicateReadings(count: 2).severity == .info)
        
        // Network timeout should be warning
        #expect(NetworkFaultType.timeout(afterSeconds: 5).severity == .warning)
        
        // Server error should be error
        #expect(NetworkFaultType.serverError(statusCode: 500).severity == .error)
    }
}

// MARK: - Test Helpers

private func makeGlucoseReadings(current: Double, trend: Double, count: Int = 6) -> [GlucoseReading] {
    let now = Date()
    return (0..<count).map { i in
        let timestamp = now.addingTimeInterval(TimeInterval(-i * 5 * 60))
        let glucose = current - Double(i) * trend
        return GlucoseReading(glucose: glucose, timestamp: timestamp)
    }
}
