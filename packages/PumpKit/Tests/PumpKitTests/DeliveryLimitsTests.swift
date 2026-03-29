// SPDX-License-Identifier: MIT
//
// DeliveryLimitsTests.swift
// T1Pal Mobile
//
// Unit tests for DeliveryLimits
// Requirements: REQ-AID-006

import Testing
import Foundation
@testable import PumpKit

// MARK: - DeliveryLimits Configuration Tests

@Suite("Delivery Limits Configuration")
struct DeliveryLimitsConfigTests {
    
    @Test("Default limits are reasonable")
    func defaultLimits() {
        let limits = DeliveryLimits.default
        
        #expect(limits.maxBolus == 10.0)
        #expect(limits.maxHourlyDelivery == 15.0)
        #expect(limits.maxDailyDelivery == 100.0)
        #expect(limits.maxTempBasalRate == 10.0)
        #expect(limits.maxTempBasalDuration == 7200)
    }
    
    @Test("Conservative limits are stricter")
    func conservativeLimits() {
        let limits = DeliveryLimits.conservative
        
        #expect(limits.maxBolus < DeliveryLimits.default.maxBolus)
        #expect(limits.maxHourlyDelivery < DeliveryLimits.default.maxHourlyDelivery)
        #expect(limits.maxDailyDelivery < DeliveryLimits.default.maxDailyDelivery)
    }
    
    @Test("Relaxed limits are more permissive")
    func relaxedLimits() {
        let limits = DeliveryLimits.relaxed
        
        #expect(limits.maxBolus > DeliveryLimits.default.maxBolus)
        #expect(limits.maxHourlyDelivery > DeliveryLimits.default.maxHourlyDelivery)
        #expect(limits.maxDailyDelivery > DeliveryLimits.default.maxDailyDelivery)
    }
    
    @Test("Custom limits initialization")
    func customLimits() {
        let limits = DeliveryLimits(
            maxBolus: 8.0,
            maxHourlyDelivery: 12.0,
            maxDailyDelivery: 80.0,
            maxTempBasalRate: 8.0,
            maxTempBasalDuration: 5400
        )
        
        #expect(limits.maxBolus == 8.0)
        #expect(limits.maxHourlyDelivery == 12.0)
        #expect(limits.maxDailyDelivery == 80.0)
        #expect(limits.maxTempBasalRate == 8.0)
        #expect(limits.maxTempBasalDuration == 5400)
    }
    
    @Test("Limits are codable")
    func limitsCodable() throws {
        let limits = DeliveryLimits.default
        let encoded = try JSONEncoder().encode(limits)
        let decoded = try JSONDecoder().decode(DeliveryLimits.self, from: encoded)
        
        #expect(decoded == limits)
    }
}

// MARK: - DeliveryRecord Tests

@Suite("Delivery Record")
struct DeliveryRecordTests {
    
    @Test("Record creation")
    func recordCreation() {
        let record = DeliveryRecord(units: 2.5, type: .bolus)
        
        #expect(record.units == 2.5)
        #expect(record.type == .bolus)
        #expect(record.timestamp <= Date())
    }
    
    @Test("All delivery types")
    func allDeliveryTypes() {
        let types: [DeliveryType] = [.bolus, .basal, .tempBasal, .correction]
        #expect(types.count == 4)
    }
    
    @Test("Record is codable")
    func recordCodable() throws {
        let record = DeliveryRecord(units: 3.0, type: .correction)
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(DeliveryRecord.self, from: encoded)
        
        #expect(decoded.units == record.units)
        #expect(decoded.type == record.type)
    }
}

// MARK: - DeliveryTracker Tests

@Suite("Delivery Tracker")
struct DeliveryTrackerTests {
    
    @Test("Initial state is empty")
    func initialState() async {
        let tracker = DeliveryTracker()
        
        let hourly = await tracker.hourlyDelivery()
        let daily = await tracker.dailyDelivery()
        let count = await tracker.recordCount()
        
        #expect(hourly == 0)
        #expect(daily == 0)
        #expect(count == 0)
    }
    
    @Test("Recording bolus updates totals")
    func recordBolus() async {
        let tracker = DeliveryTracker()
        
        await tracker.recordBolus(units: 2.5)
        
        let hourly = await tracker.hourlyDelivery()
        let daily = await tracker.dailyDelivery()
        
        #expect(hourly == 2.5)
        #expect(daily == 2.5)
    }
    
    @Test("Multiple records accumulate")
    func multipleRecords() async {
        let tracker = DeliveryTracker()
        
        await tracker.recordBolus(units: 2.0)
        await tracker.recordBasal(units: 1.0)
        await tracker.recordTempBasal(units: 0.5)
        
        let hourly = await tracker.hourlyDelivery()
        #expect(hourly == 3.5)
    }
    
    @Test("Remaining allowance calculation")
    func remainingAllowance() async {
        let limits = DeliveryLimits(maxHourlyDelivery: 10.0, maxDailyDelivery: 50.0)
        let tracker = DeliveryTracker(limits: limits)
        
        await tracker.recordBolus(units: 3.0)
        
        let remainingHourly = await tracker.remainingHourlyAllowance()
        let remainingDaily = await tracker.remainingDailyAllowance()
        
        #expect(remainingHourly == 7.0)
        #expect(remainingDaily == 47.0)
    }
    
    @Test("Clear records works")
    func clearRecords() async {
        let tracker = DeliveryTracker()
        
        await tracker.recordBolus(units: 5.0)
        await tracker.clearRecords()
        
        let count = await tracker.recordCount()
        #expect(count == 0)
    }
}

// MARK: - Bolus Limit Validation Tests

@Suite("Bolus Limit Validation")
struct BolusLimitValidationTests {
    
    @Test("Bolus within limit passes")
    func bolusWithinLimit() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(maxBolus: 10.0))
        
        let result = await tracker.canDeliverBolus(units: 5.0)
        
        switch result {
        case .success:
            break // Expected
        case .failure(let error):
            Issue.record("Expected success, got \(error)")
        }
    }
    
    @Test("Bolus exceeding max fails")
    func bolusExceedsMax() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(maxBolus: 10.0))
        
        let result = await tracker.canDeliverBolus(units: 12.0)
        
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            if case .bolusExceedsMax(let requested, let limit) = error {
                #expect(requested == 12.0)
                #expect(limit == 10.0)
            } else {
                Issue.record("Expected bolusExceedsMax error")
            }
        }
    }
    
    @Test("Bolus exceeding hourly limit fails")
    func bolusExceedsHourly() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(
            maxBolus: 20.0,
            maxHourlyDelivery: 10.0
        ))
        
        // Record 8 units already delivered
        await tracker.recordBolus(units: 8.0)
        
        // Try to deliver 5 more (would be 13, over 10 limit)
        let result = await tracker.canDeliverBolus(units: 5.0)
        
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            if case .hourlyLimitExceeded(let projected, let limit, _) = error {
                #expect(projected == 13.0)
                #expect(limit == 10.0)
            } else {
                Issue.record("Expected hourlyLimitExceeded error, got \(error)")
            }
        }
    }
    
    @Test("Bolus exceeding daily limit fails")
    func bolusExceedsDaily() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(
            maxBolus: 100.0,
            maxHourlyDelivery: 100.0,
            maxDailyDelivery: 50.0
        ))
        
        // Record 48 units already delivered
        await tracker.recordBolus(units: 48.0)
        
        // Try to deliver 5 more (would be 53, over 50 limit)
        let result = await tracker.canDeliverBolus(units: 5.0)
        
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            if case .dailyLimitExceeded(let projected, let limit, _) = error {
                #expect(projected == 53.0)
                #expect(limit == 50.0)
            } else {
                Issue.record("Expected dailyLimitExceeded error, got \(error)")
            }
        }
    }
}

// MARK: - TempBasal Limit Validation Tests

@Suite("TempBasal Limit Validation")
struct TempBasalLimitValidationTests {
    
    @Test("TempBasal within limits passes")
    func tempBasalWithinLimits() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(
            maxTempBasalRate: 10.0,
            maxTempBasalDuration: 7200
        ))
        
        let result = await tracker.canSetTempBasal(rate: 5.0, duration: 3600)
        
        switch result {
        case .success:
            break // Expected
        case .failure(let error):
            Issue.record("Expected success, got \(error)")
        }
    }
    
    @Test("TempBasal rate exceeding max fails")
    func tempBasalRateExceedsMax() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(maxTempBasalRate: 8.0))
        
        let result = await tracker.canSetTempBasal(rate: 10.0, duration: 1800)
        
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            if case .tempBasalRateExceedsMax(let requested, let limit) = error {
                #expect(requested == 10.0)
                #expect(limit == 8.0)
            } else {
                Issue.record("Expected tempBasalRateExceedsMax error")
            }
        }
    }
    
    @Test("TempBasal duration exceeding max fails")
    func tempBasalDurationExceedsMax() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(maxTempBasalDuration: 3600))
        
        let result = await tracker.canSetTempBasal(rate: 2.0, duration: 7200)
        
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            if case .tempBasalDurationExceedsMax(let requested, let limit) = error {
                #expect(requested == 7200)
                #expect(limit == 3600)
            } else {
                Issue.record("Expected tempBasalDurationExceedsMax error")
            }
        }
    }
}

// MARK: - LimitValidator Tests

@Suite("Limit Validator")
struct LimitValidatorTests {
    
    @Test("Validate bolus within limit")
    func validateBolusWithinLimit() {
        let validator = LimitValidator(limits: DeliveryLimits(maxBolus: 10.0))
        let command = BolusCommand.normal(5.0)
        
        let result = validator.validateBolus(command)
        
        switch result {
        case .success:
            break // Expected
        case .failure:
            Issue.record("Expected success")
        }
    }
    
    @Test("Validate bolus exceeding limit")
    func validateBolusExceedsLimit() {
        let validator = LimitValidator(limits: DeliveryLimits(maxBolus: 10.0))
        let command = BolusCommand.normal(15.0)
        
        let result = validator.validateBolus(command)
        
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            #expect(error == .bolusExceedsMax(requested: 15.0, limit: 10.0))
        }
    }
    
    @Test("Validate temp basal within limits")
    func validateTempBasalWithinLimits() {
        let validator = LimitValidator(limits: DeliveryLimits(
            maxTempBasalRate: 10.0,
            maxTempBasalDuration: 7200
        ))
        let command = TempBasalCommand(rate: 5.0, duration: 3600)
        
        let result = validator.validateTempBasal(command)
        
        switch result {
        case .success:
            break // Expected
        case .failure:
            Issue.record("Expected success")
        }
    }
    
    @Test("Validate temp basal rate too high")
    func validateTempBasalRateTooHigh() {
        let validator = LimitValidator(limits: DeliveryLimits(maxTempBasalRate: 5.0))
        let command = TempBasalCommand(rate: 8.0, duration: 1800)
        
        let result = validator.validateTempBasal(command)
        
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            #expect(error == .tempBasalRateExceedsMax(requested: 8.0, limit: 5.0))
        }
    }
    
    @Test("Validate temp basal duration too long")
    func validateTempBasalDurationTooLong() {
        let validator = LimitValidator(limits: DeliveryLimits(maxTempBasalDuration: 3600))
        let command = TempBasalCommand(rate: 2.0, duration: 7200)
        
        let result = validator.validateTempBasal(command)
        
        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            #expect(error == .tempBasalDurationExceedsMax(requested: 7200, limit: 3600))
        }
    }
}

// MARK: - DeliverySummary Tests

@Suite("Delivery Summary")
struct DeliverySummaryTests {
    
    @Test("Summary with no delivery")
    func summaryNoDelivery() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(
            maxHourlyDelivery: 10.0,
            maxDailyDelivery: 50.0
        ))
        
        let summary = await tracker.summary()
        
        #expect(summary.hourlyDelivery == 0)
        #expect(summary.dailyDelivery == 0)
        #expect(summary.remainingHourly == 10.0)
        #expect(summary.remainingDaily == 50.0)
        #expect(summary.hourlyPercentUsed == 0)
        #expect(summary.dailyPercentUsed == 0)
    }
    
    @Test("Summary with partial delivery")
    func summaryPartialDelivery() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(
            maxHourlyDelivery: 10.0,
            maxDailyDelivery: 100.0
        ))
        
        await tracker.recordBolus(units: 5.0)
        
        let summary = await tracker.summary()
        
        #expect(summary.hourlyDelivery == 5.0)
        #expect(summary.dailyDelivery == 5.0)
        #expect(summary.remainingHourly == 5.0)
        #expect(summary.remainingDaily == 95.0)
        #expect(summary.hourlyPercentUsed == 0.5)
        #expect(summary.dailyPercentUsed == 0.05)
    }
}

// MARK: - DeliveryLimitError Tests

@Suite("Delivery Limit Errors")
struct DeliveryLimitErrorTests {
    
    @Test("All error cases exist")
    func allErrorCases() {
        let errors: [DeliveryLimitError] = [
            .bolusExceedsMax(requested: 15, limit: 10),
            .hourlyLimitExceeded(projected: 12, limit: 10, remaining: 2),
            .dailyLimitExceeded(projected: 110, limit: 100, remaining: 5),
            .tempBasalRateExceedsMax(requested: 12, limit: 10),
            .tempBasalDurationExceedsMax(requested: 14400, limit: 7200)
        ]
        
        #expect(errors.count == 5)
    }
    
    @Test("Errors are equatable")
    func errorsEquatable() {
        #expect(DeliveryLimitError.bolusExceedsMax(requested: 15, limit: 10) ==
                .bolusExceedsMax(requested: 15, limit: 10))
        #expect(DeliveryLimitError.bolusExceedsMax(requested: 15, limit: 10) !=
                .bolusExceedsMax(requested: 20, limit: 10))
    }
}

// MARK: - Edge Cases

@Suite("Delivery Limits Edge Cases")
struct DeliveryLimitsEdgeCaseTests {
    
    @Test("Zero bolus is allowed")
    func zeroBolus() async {
        let tracker = DeliveryTracker()
        
        let result = await tracker.canDeliverBolus(units: 0)
        
        switch result {
        case .success:
            break // Expected
        case .failure:
            Issue.record("Zero bolus should be allowed")
        }
    }
    
    @Test("Exact limit is allowed")
    func exactLimit() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(maxBolus: 10.0))
        
        let result = await tracker.canDeliverBolus(units: 10.0)
        
        switch result {
        case .success:
            break // Expected
        case .failure:
            Issue.record("Exact limit should be allowed")
        }
    }
    
    @Test("Just over limit is rejected")
    func justOverLimit() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(maxBolus: 10.0))
        
        let result = await tracker.canDeliverBolus(units: 10.01)
        
        switch result {
        case .success:
            Issue.record("Just over limit should be rejected")
        case .failure:
            break // Expected
        }
    }
    
    @Test("Negative remaining returns zero")
    func negativeRemainingReturnsZero() async {
        let tracker = DeliveryTracker(limits: DeliveryLimits(
            maxBolus: 100,
            maxHourlyDelivery: 10.0
        ))
        
        // Record more than limit (simulating bypass or error)
        await tracker.recordBolus(units: 15.0)
        
        let remaining = await tracker.remainingHourlyAllowance()
        #expect(remaining == 0)
    }
}
