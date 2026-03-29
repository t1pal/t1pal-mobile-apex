// SPDX-License-Identifier: MIT
// HealthKitCGMManager Tests
// Trace: REQ-CGM-010, CGM-024, CGM-032, CGM-033
// Test Coverage: TEST-CGM-006 (Observer Mode), TEST-CGM-007 (Gap Detection),
//                TEST-CGM-008 (Background Delivery), TEST-CGM-009 (Connection Mode)
// Note: E2E integration tests require iOS device with HealthKit access

import Testing
import Foundation
@testable import CGMKit
@testable import T1PalCore

@Suite("HealthKit CGM Config")
struct HealthKitCGMConfigTests {
    
    @Test("Default config has correct values")
    func defaultConfigValues() {
        let config = HealthKitCGMConfig.default
        
        #expect(config.maxReadingAgeSeconds == 900)
        #expect(config.trendWindowMinutes == 15)
        #expect(config.minSamplesForTrend == 3)
        #expect(config.gapThresholdSeconds == 900)
        #expect(config.expectedIntervalSeconds == 300)
        #expect(config.enableBackgroundDelivery == true)
        #expect(config.backgroundDeliveryFrequency == .immediate)
        #expect(config.enableGapFilling == false)
        #expect(config.gapFillThresholdSeconds == 900)
        #expect(config.duplicateWindowSeconds == 120)
    }
    
    @Test("Custom config values")
    func customConfigValues() {
        let config = HealthKitCGMConfig(
            maxReadingAgeSeconds: 600,
            trendWindowMinutes: 20,
            minSamplesForTrend: 5,
            gapThresholdSeconds: 1200,
            expectedIntervalSeconds: 600,
            enableBackgroundDelivery: false,
            backgroundDeliveryFrequency: .hourly,
            enableGapFilling: true,
            gapFillThresholdSeconds: 600,
            duplicateWindowSeconds: 60
        )
        
        #expect(config.maxReadingAgeSeconds == 600)
        #expect(config.trendWindowMinutes == 20)
        #expect(config.minSamplesForTrend == 5)
        #expect(config.gapThresholdSeconds == 1200)
        #expect(config.expectedIntervalSeconds == 600)
        #expect(config.enableBackgroundDelivery == false)
        #expect(config.backgroundDeliveryFrequency == .hourly)
        #expect(config.enableGapFilling == true)
        #expect(config.gapFillThresholdSeconds == 600)
        #expect(config.duplicateWindowSeconds == 60)
    }
    
    @Test("Config is encodable to JSON")
    func configEncodesToJSON() throws {
        let config = HealthKitCGMConfig.default
        let data = try JSONEncoder().encode(config)
        
        #expect(data.count > 0)
        
        let decoded = try JSONDecoder().decode(HealthKitCGMConfig.self, from: data)
        #expect(decoded.maxReadingAgeSeconds == config.maxReadingAgeSeconds)
        #expect(decoded.gapThresholdSeconds == config.gapThresholdSeconds)
        #expect(decoded.enableBackgroundDelivery == config.enableBackgroundDelivery)
        #expect(decoded.backgroundDeliveryFrequency == config.backgroundDeliveryFrequency)
        #expect(decoded.enableGapFilling == config.enableGapFilling)
        #expect(decoded.gapFillThresholdSeconds == config.gapFillThresholdSeconds)
    }
}

@Suite("Glucose Trend Calculator")
struct GlucoseTrendCalculatorTests {
    
    func makeReadings(values: [(minutesAgo: Double, glucose: Double)]) -> [GlucoseReading] {
        let now = Date()
        return values.map { pair in
            GlucoseReading(
                glucose: pair.glucose,
                timestamp: now.addingTimeInterval(-pair.minutesAgo * 60),
                trend: .notComputable,
                source: "Test"
            )
        }
    }
    
    @Test("Flat glucose returns flat trend")
    func flatGlucoseReturnsFlatTrend() {
        let readings = makeReadings(values: [
            (0, 100), (5, 100), (10, 100), (15, 100)
        ])
        
        let trend = GlucoseTrendCalculator.calculateTrend(from: readings, windowMinutes: 20)
        
        #expect(trend == .flat)
    }
    
    @Test("Rising glucose returns up trend")
    func risingGlucoseReturnsUpTrend() {
        // Rising at 2 mg/dL per minute
        let readings = makeReadings(values: [
            (0, 130), (5, 120), (10, 110), (15, 100)
        ])
        
        let trend = GlucoseTrendCalculator.calculateTrend(from: readings, windowMinutes: 20)
        
        #expect(trend == .singleUp || trend == .fortyFiveUp)
    }
    
    @Test("Falling glucose returns down trend")
    func fallingGlucoseReturnsDownTrend() {
        // Falling at 2 mg/dL per minute
        let readings = makeReadings(values: [
            (0, 100), (5, 110), (10, 120), (15, 130)
        ])
        
        let trend = GlucoseTrendCalculator.calculateTrend(from: readings, windowMinutes: 20)
        
        #expect(trend == .singleDown || trend == .fortyFiveDown)
    }
    
    @Test("Insufficient samples returns notComputable")
    func insufficientSamplesReturnsNotComputable() {
        let readings = makeReadings(values: [
            (0, 100), (5, 110)
        ])
        
        let trend = GlucoseTrendCalculator.calculateTrend(from: readings, windowMinutes: 20)
        
        #expect(trend == .notComputable)
    }
    
    @Test("Samples outside window excluded")
    func samplesOutsideWindowExcluded() {
        let readings = makeReadings(values: [
            (0, 100), (5, 105), (10, 110),  // In 15-min window
            (20, 200), (25, 250)              // Outside window
        ])
        
        // Should only use first 3 samples, which show slight rise
        let trend = GlucoseTrendCalculator.calculateTrend(from: readings, windowMinutes: 15)
        
        #expect(trend != .notComputable)
    }
    
    @Test("Trend arrow thresholds are correct")
    func trendArrowThresholdsCorrect() {
        // DoubleUp > 3
        #expect(GlucoseTrendCalculator.trendFromSlope(4.0) == .doubleUp)
        // SingleUp 2-3
        #expect(GlucoseTrendCalculator.trendFromSlope(2.5) == .singleUp)
        // FortyFiveUp 1-2
        #expect(GlucoseTrendCalculator.trendFromSlope(1.5) == .fortyFiveUp)
        // Flat -1 to 1
        #expect(GlucoseTrendCalculator.trendFromSlope(0.0) == .flat)
        // FortyFiveDown -2 to -1
        #expect(GlucoseTrendCalculator.trendFromSlope(-1.5) == .fortyFiveDown)
        // SingleDown -3 to -2
        #expect(GlucoseTrendCalculator.trendFromSlope(-2.5) == .singleDown)
        // DoubleDown < -3
        #expect(GlucoseTrendCalculator.trendFromSlope(-4.0) == .doubleDown)
    }
}

// MARK: - HealthKit CGM Manager Tests (TEST-CGM-006)

@Suite("HealthKit CGM Manager")
struct HealthKitCGMManagerTests {
    
    @Test("Manager has correct display name and type")
    func managerHasCorrectDisplayNameAndType() async {
        let manager = HealthKitCGMManager()
        
        let name = await manager.displayName
        let type = await manager.cgmType
        
        #expect(name == "HealthKit Observer")
        #expect(type == .healthKitObserver)
    }
    
    @Test("Manager starts in notStarted state")
    func managerStartsInNotStartedState() async {
        let manager = HealthKitCGMManager()
        
        let state = await manager.sensorState
        
        #expect(state == .notStarted)
    }
    
    @Test("Manager has no initial reading")
    func managerHasNoInitialReading() async {
        let manager = HealthKitCGMManager()
        
        let reading = await manager.latestReading
        
        #expect(reading == nil)
    }
    
    @Test("Custom config is applied")
    func customConfigIsApplied() async {
        let config = HealthKitCGMConfig(
            maxReadingAgeSeconds: 600,
            trendWindowMinutes: 20,
            minSamplesForTrend: 5
        )
        let manager = HealthKitCGMManager(config: config)
        
        // Manager should accept custom config without error
        let type = await manager.cgmType
        #expect(type == .healthKitObserver)
    }
    
    @Test("Disconnect changes state to stopped")
    func disconnectChangesStateToStopped() async {
        let manager = HealthKitCGMManager()
        
        await manager.disconnect()
        
        let state = await manager.sensorState
        #expect(state == .stopped)
    }
    
    @Test("Get recent readings returns empty initially")
    func getRecentReadingsReturnsEmptyInitially() async {
        let manager = HealthKitCGMManager()
        
        let readings = await manager.getRecentReadings()
        
        #expect(readings.isEmpty)
    }
    
    @Test("Gap status starts as noDataYet")
    func gapStatusStartsAsNoDataYet() async {
        let manager = HealthKitCGMManager()
        
        let status = await manager.gapStatus
        
        #expect(status == .noDataYet)
    }
    
    @Test("Check gap status returns noDataYet when no readings")
    func checkGapStatusReturnsNoDataYetWhenNoReadings() async {
        let manager = HealthKitCGMManager()
        
        let status = await manager.checkGapStatus()
        
        #expect(status == .noDataYet)
    }
}

// MARK: - Gap Status Tests (CGM-032, TEST-CGM-007)

@Suite("Gap Status")
struct GapStatusTests {
    
    @Test("GapStatus noGap is not a gap")
    func noGapIsNotGap() {
        let status = GapStatus.noGap
        
        #expect(!status.isGap)
        #expect(status.description == "Data flowing normally")
    }
    
    @Test("GapStatus gapDetected is a gap")
    func gapDetectedIsGap() {
        let date = Date()
        let status = GapStatus.gapDetected(since: date, duration: 900)
        
        #expect(status.isGap)
        #expect(status.description == "No data for 15 minutes")
    }
    
    @Test("GapStatus noDataYet is not a gap")
    func noDataYetIsNotGap() {
        let status = GapStatus.noDataYet
        
        #expect(!status.isGap)
        #expect(status.description == "Waiting for first reading")
    }
    
    @Test("GapStatus equatable works correctly")
    func gapStatusEquatable() {
        #expect(GapStatus.noGap == GapStatus.noGap)
        #expect(GapStatus.noDataYet == GapStatus.noDataYet)
        #expect(GapStatus.noGap != GapStatus.noDataYet)
    }
    
    @Test("Gap duration formatted as minutes")
    func gapDurationFormattedAsMinutes() {
        // 30 minutes
        let status30 = GapStatus.gapDetected(since: Date(), duration: 1800)
        #expect(status30.description == "No data for 30 minutes")
        
        // 1 hour
        let status60 = GapStatus.gapDetected(since: Date(), duration: 3600)
        #expect(status60.description == "No data for 60 minutes")
    }
    
    @Test("Gap with different durations are not equal")
    func gapWithDifferentDurationsNotEqual() {
        let date = Date()
        let gap1 = GapStatus.gapDetected(since: date, duration: 900)
        let gap2 = GapStatus.gapDetected(since: date, duration: 1800)
        
        #expect(gap1 != gap2)
    }
}

// MARK: - Background Delivery Tests (CGM-033)

@Suite("Background Delivery Frequency")
struct BackgroundDeliveryFrequencyTests {
    
    @Test("Frequency raw values match HKUpdateFrequency")
    func frequencyRawValuesMatchHK() {
        // HKUpdateFrequency: immediate = 1, hourly = 2, daily = 3, weekly = 4
        #expect(BackgroundDeliveryFrequency.immediate.rawValue == 1)
        #expect(BackgroundDeliveryFrequency.hourly.rawValue == 2)
        #expect(BackgroundDeliveryFrequency.daily.rawValue == 3)
        #expect(BackgroundDeliveryFrequency.weekly.rawValue == 4)
    }
    
    @Test("Frequency is encodable to JSON")
    func frequencyEncodesToJSON() throws {
        let frequency = BackgroundDeliveryFrequency.immediate
        let data = try JSONEncoder().encode(frequency)
        
        #expect(data.count > 0)
        
        let decoded = try JSONDecoder().decode(BackgroundDeliveryFrequency.self, from: data)
        #expect(decoded == .immediate)
    }
    
    @Test("All frequencies decode correctly")
    func allFrequenciesDecodeCorrectly() throws {
        let frequencies: [BackgroundDeliveryFrequency] = [.immediate, .hourly, .daily, .weekly]
        
        for freq in frequencies {
            let data = try JSONEncoder().encode(freq)
            let decoded = try JSONDecoder().decode(BackgroundDeliveryFrequency.self, from: data)
            #expect(decoded == freq)
        }
    }
}

// MARK: - Background Delivery Tests (CGM-033, TEST-CGM-008)

@Suite("Background Delivery Manager")
struct BackgroundDeliveryManagerTests {
    
    @Test("Manager starts with background delivery disabled")
    func managerStartsWithBackgroundDeliveryDisabled() async {
        let manager = HealthKitCGMManager()
        
        let enabled = await manager.isBackgroundDeliveryEnabled
        
        #expect(!enabled)
    }
    
    @Test("Config with background delivery disabled")
    func configWithBackgroundDeliveryDisabled() async {
        let config = HealthKitCGMConfig(enableBackgroundDelivery: false)
        let manager = HealthKitCGMManager(config: config)
        
        let enabled = await manager.isBackgroundDeliveryEnabled
        
        #expect(!enabled)
    }
    
    @Test("Default config enables background delivery")
    func defaultConfigEnablesBackgroundDelivery() {
        let config = HealthKitCGMConfig.default
        
        #expect(config.enableBackgroundDelivery == true)
    }
    
    @Test("Hourly frequency config is applied")
    func hourlyFrequencyConfigApplied() {
        let config = HealthKitCGMConfig(backgroundDeliveryFrequency: .hourly)
        
        #expect(config.backgroundDeliveryFrequency == .hourly)
    }
}

// MARK: - Gap Fill Tests (CGM-029)

@Suite("Gap Fill Result")
struct GapFillResultTests {
    
    @Test("Written result wasWritten is true")
    func writtenResultWasWrittenTrue() {
        let result = GapFillResult.written(timestamp: Date(), glucose: 120.0)
        
        #expect(result.wasWritten)
    }
    
    @Test("Skipped results wasWritten is false")
    func skippedResultsWasWrittenFalse() {
        #expect(!GapFillResult.skippedDisabled.wasWritten)
        #expect(!GapFillResult.skippedNoGap.wasWritten)
        #expect(!GapFillResult.skippedDuplicate(existingTimestamp: Date()).wasWritten)
    }
    
    @Test("Failed results wasWritten is false")
    func failedResultsWasWrittenFalse() {
        #expect(!GapFillResult.failedUnauthorized.wasWritten)
        #expect(!GapFillResult.failedError("test").wasWritten)
    }
    
    @Test("Written result description includes glucose")
    func writtenDescriptionIncludesGlucose() {
        let result = GapFillResult.written(timestamp: Date(), glucose: 145.0)
        
        #expect(result.description.contains("145"))
    }
    
    @Test("Skipped disabled description is correct")
    func skippedDisabledDescription() {
        let result = GapFillResult.skippedDisabled
        
        #expect(result.description == "Skipped - gap filling disabled")
    }
    
    @Test("Skipped no gap description is correct")
    func skippedNoGapDescription() {
        let result = GapFillResult.skippedNoGap
        
        #expect(result.description == "Skipped - no gap detected")
    }
    
    @Test("Failed unauthorized description is correct")
    func failedUnauthorizedDescription() {
        let result = GapFillResult.failedUnauthorized
        
        #expect(result.description == "Failed - not authorized to write")
    }
    
    @Test("GapFillResult equatable works")
    func gapFillResultEquatable() {
        #expect(GapFillResult.skippedDisabled == GapFillResult.skippedDisabled)
        #expect(GapFillResult.skippedNoGap == GapFillResult.skippedNoGap)
        #expect(GapFillResult.skippedDisabled != GapFillResult.skippedNoGap)
    }
}

@Suite("Gap Fill Manager")
struct GapFillManagerTests {
    
    @Test("Manager starts without gap-fill authorization")
    func managerStartsWithoutGapFillAuth() async {
        let manager = HealthKitCGMManager()
        
        let hasAuth = await manager.hasGapFillWriteAuthorization
        
        #expect(!hasAuth)
    }
    
    @Test("Manager starts with no last gap-fill result")
    func managerStartsWithNoLastResult() async {
        let manager = HealthKitCGMManager()
        
        let lastResult = await manager.lastGapFillResult
        
        #expect(lastResult == nil)
    }
    
    @Test("Gap fill returns skippedDisabled when disabled")
    func gapFillReturnsSkippedWhenDisabled() async {
        let config = HealthKitCGMConfig(enableGapFilling: false)
        let manager = HealthKitCGMManager(config: config)
        
        let reading = GlucoseReading(glucose: 120, timestamp: Date(), trend: .flat, source: "Test")
        let result = await manager.gapFillIfNeeded(reading: reading, lastVendorTimestamp: nil)
        
        #expect(result == .skippedDisabled)
    }
    
    @Test("Gap fill returns skippedNoGap when vendor is recent")
    func gapFillReturnsSkippedNoGapWhenRecent() async {
        let config = HealthKitCGMConfig(
            enableGapFilling: true,
            gapFillThresholdSeconds: 900
        )
        let manager = HealthKitCGMManager(config: config)
        
        let reading = GlucoseReading(glucose: 120, timestamp: Date(), trend: .flat, source: "Test")
        // Vendor data is only 5 minutes old - no gap
        let recentVendor = Date().addingTimeInterval(-300)
        let result = await manager.gapFillIfNeeded(reading: reading, lastVendorTimestamp: recentVendor)
        
        #expect(result == .skippedNoGap)
    }
    
    @Test("Gap fill config with gap filling enabled")
    func configWithGapFillingEnabled() {
        let config = HealthKitCGMConfig(enableGapFilling: true)
        
        #expect(config.enableGapFilling == true)
    }
}
