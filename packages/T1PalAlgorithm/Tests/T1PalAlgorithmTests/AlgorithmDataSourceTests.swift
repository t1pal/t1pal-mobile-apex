// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmDataSourceTests.swift
// T1Pal Mobile
//
// Tests for AlgorithmDataSource protocol and related types
// Requirements: ALG-INPUT-007, ALG-INPUT-010g/h

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("AlgorithmDataSourceTests")
struct AlgorithmDataSourceTests {
    
    // MARK: - Protocol Conformance Test
    
    func testMockDataSourceConformsToProtocol() async throws {
        let source = MockDataSource()
        
        // Verify all protocol methods are callable
        let glucose = try await source.glucoseHistory(count: 10)
        #expect(!(glucose.isEmpty))
        
        let doses = try await source.doseHistory(hours: 6)
        #expect(doses != nil)
        
        let carbs = try await source.carbHistory(hours: 6)
        #expect(carbs != nil)
        
        let profile = try await source.currentProfile()
        #expect(!(profile.sensitivityFactors.isEmpty))
        
        let loopSettings = try await source.loopSettings()
        // Loop settings may be nil for non-Loop users
        _ = loopSettings
    }
    
    // MARK: - LoopSettings Tests
    
    @Test func loopsettingsinit() {
        let settings = LoopSettings(
            maximumBasalRatePerHour: 4.0,
            maximumBolus: 10.0,
            minimumBGGuard: 70,
            dosingStrategy: "automaticBolus",
            dosingEnabled: true,
            preMealTargetRange: [80, 100]
        )
        
        #expect(settings.maximumBasalRatePerHour == 4.0)
        #expect(settings.maximumBolus == 10.0)
        #expect(settings.minimumBGGuard == 70)
        #expect(settings.dosingStrategy == "automaticBolus")
        #expect(settings.dosingEnabled == true)
        #expect(settings.preMealTargetRange == [80, 100])
    }
    
    @Test func loopsettingsdefaults() {
        let settings = LoopSettings()
        
        #expect(settings.maximumBasalRatePerHour == nil)
        #expect(settings.maximumBolus == nil)
        #expect(settings.minimumBGGuard == nil)
        #expect(settings.dosingStrategy == nil)
        #expect(settings.dosingEnabled == nil)
        #expect(settings.preMealTargetRange == nil)
    }
    
    // MARK: - AlgorithmDataSourceError Tests
    
    @Test func errordescriptions() {
        #expect(AlgorithmDataSourceError.noGlucoseData.errorDescription != nil)
        #expect(AlgorithmDataSourceError.insufficientGlucoseData(required: 10, available: 3)
            .errorDescription?.contains("10") ?? false)
        #expect(AlgorithmDataSourceError.profileNotAvailable.errorDescription != nil)
        #expect(AlgorithmDataSourceError.timeout.errorDescription != nil)
        #expect(AlgorithmDataSourceError.invalidResponse.errorDescription != nil)
    }
    
    // MARK: - AlgorithmDataDefaults Tests
    
    @Test func defaults() {
        #expect(AlgorithmDataDefaults.glucoseCount == 36)
        #expect(AlgorithmDataDefaults.doseHistoryHours == 6)
        #expect(AlgorithmDataDefaults.carbHistoryHours == 6)
        #expect(AlgorithmDataDefaults.minimumGlucoseCount == 3)
    }
}

// MARK: - DirectDataSource Tests (ALG-INPUT-010h)

@Suite("DirectDataSourceTests")
struct DirectDataSourceTests {
    
    // MARK: - DirectDataSource with Mock Providers
    
    func testDirectDataSourceConformsToProtocol() async throws {
        // Create mock providers
        let cgm = MockCGMDataProvider.stable(glucose: 120)
        let pump = MockPumpDataProvider.empty()
        let settings = MockSettingsProvider()
        
        // Create DirectDataSource
        let source = DirectDataSource(cgm: cgm, pump: pump, settings: settings)
        
        // Verify all protocol methods work
        let glucose = try await source.glucoseHistory(count: 10)
        #expect(glucose.count == 10)
        #expect(glucose.first?.glucose == 120)
        
        let doses = try await source.doseHistory(hours: 6)
        #expect(doses.isEmpty)  // Empty pump provider
        
        let carbs = try await source.carbHistory(hours: 6)
        #expect(carbs.isEmpty)
        
        let profile = try await source.currentProfile()
        #expect(!(profile.sensitivityFactors.isEmpty))
        
        let loopSettings = try await source.loopSettings()
        #expect(loopSettings == nil)  // Default MockSettingsProvider has nil settings
    }
    
    func testDirectDataSourceWithBolus() async throws {
        let cgm = MockCGMDataProvider.stable(glucose: 150)
        let pump = MockPumpDataProvider.withBolus(units: 2.5, minutesAgo: 30)
        let settings = MockSettingsProvider()
        
        let source = DirectDataSource(cgm: cgm, pump: pump, settings: settings)
        
        let doses = try await source.doseHistory(hours: 6)
        #expect(doses.count == 1)
        #expect(doses.first?.units == 2.5)
    }
    
    func testDirectDataSourceWithCustomProfile() async throws {
        let cgm = MockCGMDataProvider.stable(glucose: 100)
        let pump = MockPumpDataProvider.empty()
        
        // Custom profile with specific ISF
        var customProfile = TherapyProfile.default
        customProfile.sensitivityFactors = [
            SensitivityFactor(startTime: 0, factor: 50.0)
        ]
        let settings = MockSettingsProvider(profile: customProfile)
        
        let source = DirectDataSource(cgm: cgm, pump: pump, settings: settings)
        
        let profile = try await source.currentProfile()
        #expect(profile.sensitivityFactors.first?.factor == 50.0)
    }
    
    func testDirectDataSourceWithLoopSettings() async throws {
        let cgm = MockCGMDataProvider.stable(glucose: 110)
        let pump = MockPumpDataProvider.empty()
        let loopSettings = LoopSettings(
            maximumBasalRatePerHour: 5.0,
            maximumBolus: 12.0,
            dosingEnabled: true
        )
        let settings = MockSettingsProvider(settings: loopSettings)
        
        let source = DirectDataSource(cgm: cgm, pump: pump, settings: settings)
        
        let fetchedSettings = try await source.loopSettings()
        #expect(fetchedSettings != nil)
        #expect(fetchedSettings?.maximumBasalRatePerHour == 5.0)
        #expect(fetchedSettings?.maximumBolus == 12.0)
        #expect(fetchedSettings?.dosingEnabled == true)
    }
}

// MARK: - MockCGMDataProvider Tests (ALG-INPUT-010e)

@Suite("MockCGMDataProviderTests")
struct MockCGMDataProviderTests {
    
    func testStableGlucose() async throws {
        let provider = MockCGMDataProvider.stable(glucose: 120, count: 12)
        
        let history = try await provider.glucoseHistory(count: 12)
        #expect(history.count == 12)
        #expect(history.allSatisfy { $0.glucose == 120 })
        
        let latest = await provider.latestGlucose
        #expect(latest?.glucose == 120)
    }
    
    func testEmptyProvider() async throws {
        let provider = MockCGMDataProvider()
        
        let history = try await provider.glucoseHistory(count: 10)
        #expect(history.isEmpty)
        
        let latest = await provider.latestGlucose
        #expect(latest == nil)
    }
    
    func testCustomGlucoseValues() async throws {
        let readings = [
            GlucoseReading(glucose: 150, timestamp: Date(), trend: .singleUp),
            GlucoseReading(glucose: 140, timestamp: Date().addingTimeInterval(-300), trend: .flat),
            GlucoseReading(glucose: 130, timestamp: Date().addingTimeInterval(-600), trend: .singleDown)
        ]
        let provider = MockCGMDataProvider(glucoseValues: readings)
        
        let history = try await provider.glucoseHistory(count: 5)
        #expect(history.count == 3)  // Only 3 available
        #expect(history[0].glucose == 150)
        #expect(history[1].glucose == 140)
        #expect(history[2].glucose == 130)
    }
}

// MARK: - MockPumpDataProvider Tests (ALG-INPUT-010f)

@Suite("MockPumpDataProviderTests")
struct MockPumpDataProviderTests {
    
    func testEmptyProvider() async throws {
        let provider = MockPumpDataProvider.empty()
        
        let doses = try await provider.doseHistory(hours: 6)
        #expect(doses.isEmpty)
        
        let carbs = try await provider.carbHistory(hours: 6)
        #expect(carbs.isEmpty)
    }
    
    func testWithBolus() async throws {
        let provider = MockPumpDataProvider.withBolus(units: 3.0, minutesAgo: 60)
        
        let doses = try await provider.doseHistory(hours: 6)
        #expect(doses.count == 1)
        #expect(doses.first?.units == 3.0)
    }
    
    func testDoseHistoryFiltering() async throws {
        // Create doses at different times
        let recentDose = InsulinDose(
            units: 2.0,
            timestamp: Date().addingTimeInterval(-1800),  // 30 min ago
            type: .novolog,
            source: "test"
        )
        let oldDose = InsulinDose(
            units: 1.0,
            timestamp: Date().addingTimeInterval(-25200),  // 7 hours ago
            type: .novolog,
            source: "test"
        )
        let provider = MockPumpDataProvider(doses: [recentDose, oldDose])
        
        // Request 6 hours - should only get recent dose
        let doses = try await provider.doseHistory(hours: 6)
        #expect(doses.count == 1)
        #expect(doses.first?.units == 2.0)
    }
    
    func testReservoirLevel() async throws {
        let provider = MockPumpDataProvider(reservoirLevel: 75.5)
        
        let level = await provider.reservoirLevel
        #expect(level == 75.5)
    }
    
    func testCarbHistory() async throws {
        let carbs = [
            CarbEntry(grams: 45, timestamp: Date().addingTimeInterval(-1800), absorptionType: .medium, source: "test"),
            CarbEntry(grams: 15, timestamp: Date().addingTimeInterval(-3600), absorptionType: .fast, source: "test")
        ]
        let provider = MockPumpDataProvider(carbs: carbs)
        
        let history = try await provider.carbHistory(hours: 6)
        #expect(history.count == 2)
        #expect(history.first?.grams == 45)
    }
}

// MARK: - MockSettingsProvider Tests

@Suite("MockSettingsProviderTests")
struct MockSettingsProviderTests {
    
    func testDefaultProfile() async throws {
        let provider = MockSettingsProvider()
        
        let profile = try await provider.currentProfile()
        #expect(!(profile.sensitivityFactors.isEmpty))
        
        let settings = try await provider.loopSettings()
        #expect(settings == nil)
    }
    
    func testCustomProfile() async throws {
        var customProfile = TherapyProfile.default
        customProfile.carbRatios = [
            CarbRatio(startTime: 0, ratio: 8.0)
        ]
        let provider = MockSettingsProvider(profile: customProfile)
        
        let profile = try await provider.currentProfile()
        #expect(profile.carbRatios.first?.ratio == 8.0)
    }
    
    func testWithLoopSettings() async throws {
        let loopSettings = LoopSettings(
            maximumBasalRatePerHour: 6.0,
            dosingStrategy: "tempBasalOnly"
        )
        let provider = MockSettingsProvider(settings: loopSettings)
        
        let settings = try await provider.loopSettings()
        #expect(settings?.maximumBasalRatePerHour == 6.0)
        #expect(settings?.dosingStrategy == "tempBasalOnly")
    }
}

// MARK: - AIDInputConformance Tests (ALG-INPUT-019a)

@Suite("AIDInputConformanceTests")
struct AIDInputConformanceTests {
    
    @Test func recordeddevicestateinit() {
        let readings = [GlucoseReading(glucose: 120, timestamp: Date(), trend: .flat)]
        let profile = TherapyProfile.default
        
        let state = RecordedDeviceState(
            scenario: "test",
            glucoseReadings: readings,
            profile: profile
        )
        
        #expect(state.scenario == "test")
        #expect(state.glucoseReadings.count == 1)
        #expect(!(state.profile.sensitivityFactors.isEmpty))
    }
    
    func testConformanceResultAllMatch() async throws {
        let runner = MockAIDInputConformanceRunner()
        let readings = [GlucoseReading(glucose: 120, timestamp: Date(), trend: .flat)]
        let state = RecordedDeviceState(
            scenario: "stable",
            glucoseReadings: readings,
            profile: .default,
            expectedIOB: 1.5,
            expectedCOB: 30
        )
        
        let cliInputs = try await runner.runCLIPath(state)
        let aidInputs = try await runner.runAIDPath(state)
        let result = runner.compareInputs(cliInputs, aidInputs)
        
        #expect(result.passed)
        #expect(result.glucoseMatch.matches)
        #expect(result.iobMatch.matches)
        #expect(result.cobMatch.matches)
    }
    
    @Test func iobmismatchdetected() {
        let glucose = [GlucoseReading(glucose: 100, timestamp: Date(), trend: .flat)]
        let profile = TherapyProfile.default
        
        let cliInputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 1.5,
            carbsOnBoard: 0,
            profile: profile
        )
        let aidInputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 1.55,  // 0.05 delta > 0.01 tolerance
            carbsOnBoard: 0,
            profile: profile
        )
        
        let result = AIDInputConformanceResult.compare(cliInputs, aidInputs)
        #expect(!(result.passed))
        #expect(!(result.iobMatch.matches))
        #expect(result.iobMatch.reason.contains("delta"))
    }
    
    @Test func toleranceconstants() {
        #expect(AIDInputConformanceTolerance.iob == 0.01)
        #expect(AIDInputConformanceTolerance.cob == 1.0)
        #expect(AIDInputConformanceTolerance.glucose == 0.5)
    }
}

// MARK: - ALG-INPUT-019e: Glucose Array Conformance Tests

@Suite("GlucoseArrayConformanceTests")
struct GlucoseArrayConformanceTests {
    
    let baseTime = Date()
    let profile = TherapyProfile(
        basalRates: [BasalRate(startTime: 0, rate: 1.0)],
        carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
        sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
        targetGlucose: TargetRange(low: 100, high: 120)
    )
    
    @Test func glucosecountmismatch() {
        let cli = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 100, timestamp: baseTime, trend: .flat)],
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        let aid = AlgorithmInputs(
            glucose: [
                GlucoseReading(glucose: 100, timestamp: baseTime, trend: .flat),
                GlucoseReading(glucose: 105, timestamp: baseTime.addingTimeInterval(-300), trend: .flat)
            ],
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.glucoseMatch.matches))
        #expect(result.glucoseMatch.reason.contains("count"))
    }
    
    @Test func glucosevaluewithintolerance() {
        let cli = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 100.0, timestamp: baseTime, trend: .flat)],
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        let aid = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 100.4, timestamp: baseTime, trend: .flat)], // Within 0.5 tolerance
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.glucoseMatch.matches)
    }
    
    @Test func glucosevalueoutsidetolerance() {
        let cli = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 100.0, timestamp: baseTime, trend: .flat)],
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        let aid = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 101.0, timestamp: baseTime, trend: .flat)], // 1.0 > 0.5 tolerance
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.glucoseMatch.matches))
        #expect(result.glucoseMatch.reason.contains("value"))
    }
    
    @Test func glucosetimestampwithintolerance() {
        let cli = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 100, timestamp: baseTime, trend: .flat)],
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        let aid = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 100, timestamp: baseTime.addingTimeInterval(0.9), trend: .flat)], // 0.9s < 1.0s tolerance
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.glucoseMatch.matches)
    }
    
    @Test func glucosetimestampoutsidetolerance() {
        let cli = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 100, timestamp: baseTime, trend: .flat)],
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        let aid = AlgorithmInputs(
            glucose: [GlucoseReading(glucose: 100, timestamp: baseTime.addingTimeInterval(2.0), trend: .flat)], // 2.0s > 1.0s tolerance
            insulinOnBoard: 0, carbsOnBoard: 0, profile: profile
        )
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.glucoseMatch.matches))
        #expect(result.glucoseMatch.reason.contains("timestamp"))
    }
    
    @Test func multipleglucosereadingsmatch() {
        let readings = (0..<6).map { i in
            GlucoseReading(glucose: 100 + Double(i * 5), timestamp: baseTime.addingTimeInterval(Double(-i * 300)), trend: .singleUp)
        }
        let cli = AlgorithmInputs(glucose: readings, insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: readings, insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.glucoseMatch.matches)
        #expect(result.passed)
    }
    
    @Test func emptyglucosearraysmatch() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.glucoseMatch.matches)
    }
}

// MARK: - ALG-INPUT-019f: IOB Conformance Tests

@Suite("IOBConformanceTests")
struct IOBConformanceTests {
    
    let profile = TherapyProfile(
        basalRates: [BasalRate(startTime: 0, rate: 1.0)],
        carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
        sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
        targetGlucose: TargetRange(low: 100, high: 120)
    )
    
    @Test func iobexactmatch() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.50, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.50, carbsOnBoard: 0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.iobMatch.matches)
    }
    
    @Test func iobwithintolerance() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.50, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.509, carbsOnBoard: 0, profile: profile) // 0.009 < 0.01 tolerance
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.iobMatch.matches)
    }
    
    @Test func iobattoleranceboundary() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.50, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.51, carbsOnBoard: 0, profile: profile) // 0.01 = exactly at tolerance
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.iobMatch.matches) // <= tolerance passes
    }
    
    @Test func ioboutsidetolerance() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.50, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.52, carbsOnBoard: 0, profile: profile) // 0.02 > 0.01 tolerance
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.iobMatch.matches))
        #expect(result.iobMatch.reason.contains("delta"))
    }
    
    @Test func iobzerovalues() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.iobMatch.matches)
    }
    
    @Test func ioblargevalueswithintolerance() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 15.235, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 15.240, carbsOnBoard: 0, profile: profile) // 0.005 < 0.01
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.iobMatch.matches)
    }
}

// MARK: - ALG-INPUT-019g: COB Conformance Tests

@Suite("COBConformanceTests")
struct COBConformanceTests {
    
    let profile = TherapyProfile(
        basalRates: [BasalRate(startTime: 0, rate: 1.0)],
        carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
        sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
        targetGlucose: TargetRange(low: 100, high: 120)
    )
    
    @Test func cobexactmatch() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 45.0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 45.0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.cobMatch.matches)
    }
    
    @Test func cobwithintolerance() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 45.0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 45.8, profile: profile) // 0.8 < 1.0 tolerance
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.cobMatch.matches)
    }
    
    @Test func cobattoleranceboundary() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 45.0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 46.0, profile: profile) // 1.0 = exactly at tolerance
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.cobMatch.matches) // <= tolerance passes
    }
    
    @Test func coboutsidetolerance() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 45.0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 46.5, profile: profile) // 1.5 > 1.0 tolerance
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.cobMatch.matches))
        #expect(result.cobMatch.reason.contains("delta"))
    }
    
    @Test func cobzerovalues() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.cobMatch.matches)
    }
    
    @Test func coblargevalueswithintolerance() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 150.0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 150.9, profile: profile) // 0.9 < 1.0
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.cobMatch.matches)
    }
}

// MARK: - Combined Conformance Tests

@Suite("CombinedConformanceTests")
struct CombinedConformanceTests {
    
    let baseTime = Date()
    let profile = TherapyProfile(
        basalRates: [BasalRate(startTime: 0, rate: 1.0)],
        carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
        sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
        targetGlucose: TargetRange(low: 100, high: 120)
    )
    
    @Test func allfieldsmatchingpass() {
        let glucose = [GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat)]
        let cli = AlgorithmInputs(glucose: glucose, insulinOnBoard: 1.5, carbsOnBoard: 30, profile: profile)
        let aid = AlgorithmInputs(glucose: glucose, insulinOnBoard: 1.5, carbsOnBoard: 30, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.passed)
        #expect(result.glucoseMatch.matches)
        #expect(result.iobMatch.matches)
        #expect(result.cobMatch.matches)
    }
    
    @Test func singlefieldmismatchfails() {
        let glucose = [GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat)]
        let cli = AlgorithmInputs(glucose: glucose, insulinOnBoard: 1.5, carbsOnBoard: 30, profile: profile)
        let aid = AlgorithmInputs(glucose: glucose, insulinOnBoard: 1.55, carbsOnBoard: 30, profile: profile) // IOB mismatch
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.passed))
        #expect(result.glucoseMatch.matches)
        #expect(!(result.iobMatch.matches)) // This one fails
        #expect(result.cobMatch.matches)
    }
    
    @Test func allfieldswithintolerancepass() {
        let cliGlucose = [GlucoseReading(glucose: 120.0, timestamp: baseTime, trend: .flat)]
        let aidGlucose = [GlucoseReading(glucose: 120.4, timestamp: baseTime.addingTimeInterval(0.5), trend: .flat)]
        
        let cli = AlgorithmInputs(glucose: cliGlucose, insulinOnBoard: 1.500, carbsOnBoard: 30.0, profile: profile)
        let aid = AlgorithmInputs(glucose: aidGlucose, insulinOnBoard: 1.505, carbsOnBoard: 30.8, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.passed)
    }
}

// MARK: - ALG-INPUT-019i: Carb History Conformance Tests

@Suite("CarbHistoryConformanceTests")
struct CarbHistoryConformanceTests {
    
    let baseTime = Date()
    let profile = TherapyProfile(
        basalRates: [BasalRate(startTime: 0, rate: 1.0)],
        carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
        sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
        targetGlucose: TargetRange(low: 100, high: 120)
    )
    
    @Test func carbhistorybothnilmatch() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile, carbHistory: nil)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile, carbHistory: nil)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.carbHistoryMatch.matches)
    }
    
    @Test func carbhistoryclihasaidmissing() {
        let carbs = [CarbEntry(grams: 30, timestamp: baseTime)]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: carbs)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: nil)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.carbHistoryMatch.matches))
        #expect(result.carbHistoryMatch.reason.contains("AID missing"))
    }
    
    @Test func carbhistoryaidhasclimissing() {
        let carbs = [CarbEntry(grams: 30, timestamp: baseTime)]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: nil)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: carbs)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.carbHistoryMatch.matches))
        #expect(result.carbHistoryMatch.reason.contains("CLI missing"))
    }
    
    @Test func carbhistorycountmismatch() {
        let cliCarbs = [CarbEntry(grams: 30, timestamp: baseTime)]
        let aidCarbs = [
            CarbEntry(grams: 20, timestamp: baseTime),
            CarbEntry(grams: 10, timestamp: baseTime.addingTimeInterval(-3600))
        ]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: cliCarbs)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: aidCarbs)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.carbHistoryMatch.matches))
        #expect(result.carbHistoryMatch.reason.contains("count"))
    }
    
    @Test func carbhistorytotalgramswithintolerance() {
        let cliCarbs = [CarbEntry(grams: 30.0, timestamp: baseTime)]
        let aidCarbs = [CarbEntry(grams: 30.8, timestamp: baseTime)] // 0.8 < 1.0 tolerance
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: cliCarbs)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: aidCarbs)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.carbHistoryMatch.matches)
    }
    
    @Test func carbhistorytotalgramsoutsidetolerance() {
        let cliCarbs = [CarbEntry(grams: 30.0, timestamp: baseTime)]
        let aidCarbs = [CarbEntry(grams: 32.0, timestamp: baseTime)] // 2.0 > 1.0 tolerance
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 30, profile: profile, carbHistory: cliCarbs)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 32, profile: profile, carbHistory: aidCarbs)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.carbHistoryMatch.matches))
        #expect(result.carbHistoryMatch.reason.contains("total grams"))
    }
    
    @Test func carbhistorymultipleentriesmatch() {
        let carbs = [
            CarbEntry(grams: 30, timestamp: baseTime),
            CarbEntry(grams: 15, timestamp: baseTime.addingTimeInterval(-3600)),
            CarbEntry(grams: 20, timestamp: baseTime.addingTimeInterval(-7200))
        ]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 65, profile: profile, carbHistory: carbs)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 65, profile: profile, carbHistory: carbs)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.carbHistoryMatch.matches)
    }
    
    @Test func carbhistoryemptyarraysmatch() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile, carbHistory: [])
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile, carbHistory: [])
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.carbHistoryMatch.matches)
    }
}

// MARK: - ALG-INPUT-019j: Profile Conformance Tests

@Suite("ProfileConformanceTests")
struct ProfileConformanceTests {
    
    @Test func profileexactmatch() {
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.profileMatch.matches)
    }
    
    @Test func profileisfcountmismatch() {
        let cliProfile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let aidProfile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [
                SensitivityFactor(startTime: 0, factor: 50),
                SensitivityFactor(startTime: 43200, factor: 45) // 12:00
            ],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: cliProfile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: aidProfile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.profileMatch.matches))
        #expect(result.profileMatch.reason.contains("ISF"))
    }
    
    @Test func profilecrcountmismatch() {
        let cliProfile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let aidProfile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [
                CarbRatio(startTime: 0, ratio: 10),
                CarbRatio(startTime: 43200, ratio: 12) // 12:00
            ],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: cliProfile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: aidProfile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.profileMatch.matches))
        #expect(result.profileMatch.reason.contains("CR"))
    }
    
    @Test func profilemultipleschedulesmatch() {
        let profile = TherapyProfile(
            basalRates: [
                BasalRate(startTime: 0, rate: 0.8),
                BasalRate(startTime: 21600, rate: 1.0),  // 06:00
                BasalRate(startTime: 43200, rate: 0.9)   // 12:00
            ],
            carbRatios: [
                CarbRatio(startTime: 0, ratio: 12),
                CarbRatio(startTime: 43200, ratio: 10)   // 12:00
            ],
            sensitivityFactors: [
                SensitivityFactor(startTime: 0, factor: 55),
                SensitivityFactor(startTime: 43200, factor: 45) // 12:00
            ],
            targetGlucose: TargetRange(low: 100, high: 110)
        )
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.profileMatch.matches)
    }
    
    @Test func profileemptyschedulesmatch() {
        let profile = TherapyProfile(
            basalRates: [],
            carbRatios: [],
            sensitivityFactors: [],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.profileMatch.matches)
    }
}

// MARK: - ALG-INPUT-019h: Dose History Conformance Tests

@Suite("DoseHistoryConformanceTests")
struct DoseHistoryConformanceTests {
    
    let baseTime = Date()
    let profile = TherapyProfile(
        basalRates: [BasalRate(startTime: 0, rate: 1.0)],
        carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
        sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
        targetGlucose: TargetRange(low: 100, high: 120)
    )
    
    @Test func dosehistorybothnilmatch() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile, doseHistory: nil)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile, doseHistory: nil)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.doseHistoryMatch.matches)
    }
    
    @Test func dosehistoryclihasaidmissing() {
        let doses = [InsulinDose(units: 2.5, timestamp: baseTime)]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: doses)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: nil)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.doseHistoryMatch.matches))
        #expect(result.doseHistoryMatch.reason.contains("AID missing"))
    }
    
    @Test func dosehistoryaidhasclimissing() {
        let doses = [InsulinDose(units: 2.5, timestamp: baseTime)]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: nil)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: doses)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.doseHistoryMatch.matches))
        #expect(result.doseHistoryMatch.reason.contains("CLI missing"))
    }
    
    @Test func dosehistorycountmismatch() {
        let cliDoses = [InsulinDose(units: 2.5, timestamp: baseTime)]
        let aidDoses = [
            InsulinDose(units: 1.5, timestamp: baseTime),
            InsulinDose(units: 1.0, timestamp: baseTime.addingTimeInterval(-3600))
        ]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: cliDoses)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: aidDoses)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.doseHistoryMatch.matches))
        #expect(result.doseHistoryMatch.reason.contains("count"))
    }
    
    @Test func dosehistorytotalunitswithintolerance() {
        let cliDoses = [InsulinDose(units: 2.500, timestamp: baseTime)]
        let aidDoses = [InsulinDose(units: 2.508, timestamp: baseTime)] // 0.008 < 0.01 tolerance
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: cliDoses)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: aidDoses)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.doseHistoryMatch.matches)
    }
    
    @Test func dosehistorytotalunitsoutsidetolerance() {
        let cliDoses = [InsulinDose(units: 2.50, timestamp: baseTime)]
        let aidDoses = [InsulinDose(units: 2.52, timestamp: baseTime)] // 0.02 > 0.01 tolerance
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 2.5, carbsOnBoard: 0, profile: profile, doseHistory: cliDoses)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 2.52, carbsOnBoard: 0, profile: profile, doseHistory: aidDoses)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(!(result.doseHistoryMatch.matches))
        #expect(result.doseHistoryMatch.reason.contains("total units"))
    }
    
    @Test func dosehistorymultipledosesmatch() {
        let doses = [
            InsulinDose(units: 3.0, timestamp: baseTime),                           // Bolus
            InsulinDose(units: 0.5, timestamp: baseTime.addingTimeInterval(-1800)), // Temp basal segment
            InsulinDose(units: 0.5, timestamp: baseTime.addingTimeInterval(-3600)), // Temp basal segment
            InsulinDose(units: 2.0, timestamp: baseTime.addingTimeInterval(-7200))  // Earlier bolus
        ]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 6.0, carbsOnBoard: 0, profile: profile, doseHistory: doses)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 6.0, carbsOnBoard: 0, profile: profile, doseHistory: doses)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.doseHistoryMatch.matches)
    }
    
    @Test func dosehistoryemptyarraysmatch() {
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile, doseHistory: [])
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 0, carbsOnBoard: 0, profile: profile, doseHistory: [])
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.doseHistoryMatch.matches)
    }
    
    @Test func dosehistorybolusandtempbasalmixed() {
        // Simulates real-world scenario with boluses and temp basal segments
        let cliDoses = [
            InsulinDose(units: 4.5, timestamp: baseTime),                            // Correction bolus
            InsulinDose(units: 0.8, timestamp: baseTime.addingTimeInterval(-1800)),  // 30min temp basal
            InsulinDose(units: 0.6, timestamp: baseTime.addingTimeInterval(-3600))   // Previous temp
        ]
        let aidDoses = [
            InsulinDose(units: 4.5, timestamp: baseTime),
            InsulinDose(units: 0.8, timestamp: baseTime.addingTimeInterval(-1800)),
            InsulinDose(units: 0.6, timestamp: baseTime.addingTimeInterval(-3600))
        ]
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 5.9, carbsOnBoard: 0, profile: profile, doseHistory: cliDoses)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 5.9, carbsOnBoard: 0, profile: profile, doseHistory: aidDoses)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.doseHistoryMatch.matches)
        #expect(result.passed)
    }
    
    @Test func dosehistorylargetotalwithintolerance() {
        // Many small temp basal segments summing to large total
        let doses = (0..<24).map { i in
            InsulinDose(units: 0.5, timestamp: baseTime.addingTimeInterval(Double(-i * 1800)))
        }
        let cli = AlgorithmInputs(glucose: [], insulinOnBoard: 12.0, carbsOnBoard: 0, profile: profile, doseHistory: doses)
        let aid = AlgorithmInputs(glucose: [], insulinOnBoard: 12.0, carbsOnBoard: 0, profile: profile, doseHistory: doses)
        
        let result = AIDInputConformanceResult.compare(cli, aid)
        #expect(result.doseHistoryMatch.matches)
    }
}

// MARK: - ALG-INPUT-019k: Algorithm Output Conformance Tests

@Suite("AlgorithmOutputConformanceTests")
struct AlgorithmOutputConformanceTests {
    
    // MARK: - Temp Basal Rate Tests
    
    @Test func tempbasalrateexactmatch() {
        let cli = AlgorithmOutput(tempBasalRate: 1.5, tempBasalDuration: 1800, success: true)
        let aid = AlgorithmOutput(tempBasalRate: 1.5, tempBasalDuration: 1800, success: true)
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.tempBasalRateMatch.matches)
        #expect(result.passed)
    }
    
    @Test func tempbasalratewithintolerance() {
        let cli = AlgorithmOutput(tempBasalRate: 1.50, tempBasalDuration: 1800, success: true)
        let aid = AlgorithmOutput(tempBasalRate: 1.54, tempBasalDuration: 1800, success: true) // 0.04 < 0.05 tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.tempBasalRateMatch.matches)
    }
    
    @Test func tempbasalrateattoleranceboundary() {
        let cli = AlgorithmOutput(tempBasalRate: 1.50, tempBasalDuration: 1800, success: true)
        let aid = AlgorithmOutput(tempBasalRate: 1.549, tempBasalDuration: 1800, success: true) // 0.049 < 0.05 tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.tempBasalRateMatch.matches)
    }
    
    @Test func tempbasalrateoutsidetolerance() {
        let cli = AlgorithmOutput(tempBasalRate: 1.50, tempBasalDuration: 1800, success: true)
        let aid = AlgorithmOutput(tempBasalRate: 1.60, tempBasalDuration: 1800, success: true) // 0.10 > 0.05 tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(!(result.tempBasalRateMatch.matches))
        #expect(result.tempBasalRateMatch.reason.contains("delta"))
    }
    
    @Test func tempbasalratebothnil() {
        let cli = AlgorithmOutput(tempBasalRate: nil, success: true)
        let aid = AlgorithmOutput(tempBasalRate: nil, success: true)
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.tempBasalRateMatch.matches)
    }
    
    @Test func tempbasalrateclihasaidmissing() {
        let cli = AlgorithmOutput(tempBasalRate: 1.5, success: true)
        let aid = AlgorithmOutput(tempBasalRate: nil, success: true)
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(!(result.tempBasalRateMatch.matches))
        #expect(result.tempBasalRateMatch.reason.contains("AID missing"))
    }
    
    // MARK: - Temp Basal Duration Tests
    
    @Test func tempbasaldurationwithintolerance() {
        let cli = AlgorithmOutput(tempBasalRate: 1.5, tempBasalDuration: 1800, success: true)
        let aid = AlgorithmOutput(tempBasalRate: 1.5, tempBasalDuration: 1850, success: true) // 50s < 60s tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.tempBasalDurationMatch.matches)
    }
    
    @Test func tempbasaldurationoutsidetolerance() {
        let cli = AlgorithmOutput(tempBasalRate: 1.5, tempBasalDuration: 1800, success: true)
        let aid = AlgorithmOutput(tempBasalRate: 1.5, tempBasalDuration: 1900, success: true) // 100s > 60s tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(!(result.tempBasalDurationMatch.matches))
    }
    
    // MARK: - Suggested Bolus Tests
    
    @Test func suggestedboluswithintolerance() {
        let cli = AlgorithmOutput(suggestedBolus: 2.50, success: true)
        let aid = AlgorithmOutput(suggestedBolus: 2.508, success: true) // 0.008 < 0.01 tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.suggestedBolusMatch.matches)
    }
    
    @Test func suggestedbolusoutsidetolerance() {
        let cli = AlgorithmOutput(suggestedBolus: 2.50, success: true)
        let aid = AlgorithmOutput(suggestedBolus: 2.52, success: true) // 0.02 > 0.01 tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(!(result.suggestedBolusMatch.matches))
    }
    
    // MARK: - Eventual BG Tests
    
    @Test func eventualbgwithintolerance() {
        let cli = AlgorithmOutput(eventualBG: 120.0, success: true)
        let aid = AlgorithmOutput(eventualBG: 120.8, success: true) // 0.8 < 1.0 tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.eventualBGMatch.matches)
    }
    
    @Test func eventualbgoutsidetolerance() {
        let cli = AlgorithmOutput(eventualBG: 120.0, success: true)
        let aid = AlgorithmOutput(eventualBG: 122.0, success: true) // 2.0 > 1.0 tolerance
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(!(result.eventualBGMatch.matches))
    }
    
    // MARK: - Success Flag Tests
    
    @Test func successflagmatch() {
        let cli = AlgorithmOutput(success: true)
        let aid = AlgorithmOutput(success: true)
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.successMatch.matches)
    }
    
    @Test func successflagmismatch() {
        let cli = AlgorithmOutput(success: true)
        let aid = AlgorithmOutput(success: false)
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(!(result.successMatch.matches))
        #expect(result.successMatch.reason.contains("mismatch"))
    }
    
    // MARK: - Combined Tests
    
    @Test func allfieldsmatchingpass() {
        let cli = AlgorithmOutput(
            tempBasalRate: 1.2,
            tempBasalDuration: 1800,
            suggestedBolus: nil,
            eventualBG: 115.0,
            success: true
        )
        let aid = AlgorithmOutput(
            tempBasalRate: 1.2,
            tempBasalDuration: 1800,
            suggestedBolus: nil,
            eventualBG: 115.0,
            success: true
        )
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.passed)
    }
    
    @Test func singlefieldmismatchfails() {
        let cli = AlgorithmOutput(
            tempBasalRate: 1.2,
            tempBasalDuration: 1800,
            eventualBG: 115.0,
            success: true
        )
        let aid = AlgorithmOutput(
            tempBasalRate: 1.5, // 0.3 > 0.05 tolerance - fails
            tempBasalDuration: 1800,
            eventualBG: 115.0,
            success: true
        )
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(!(result.passed))
        #expect(!(result.tempBasalRateMatch.matches))
        #expect(result.tempBasalDurationMatch.matches)
        #expect(result.eventualBGMatch.matches)
    }
    
    @Test func allfieldswithintolerancepass() {
        let cli = AlgorithmOutput(
            tempBasalRate: 1.20,
            tempBasalDuration: 1800,
            suggestedBolus: 3.00,
            eventualBG: 110.0,
            success: true
        )
        let aid = AlgorithmOutput(
            tempBasalRate: 1.24,    // 0.04 < 0.05
            tempBasalDuration: 1830, // 30s < 60s
            suggestedBolus: 3.005,   // 0.005 < 0.01
            eventualBG: 110.5,       // 0.5 < 1.0
            success: true
        )
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.passed)
    }
    
    @Test func realistictempbasalrecommendation() {
        // Simulates Loop-style temp basal recommendation
        let cli = AlgorithmOutput(
            tempBasalRate: 0.0,       // Suspend delivery
            tempBasalDuration: 1800,  // 30 minutes
            suggestedBolus: nil,
            eventualBG: 85.0,         // Below target
            success: true
        )
        let aid = AlgorithmOutput(
            tempBasalRate: 0.0,
            tempBasalDuration: 1800,
            suggestedBolus: nil,
            eventualBG: 85.0,
            success: true
        )
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.passed)
    }
    
    @Test func realistichightemprecommendation() {
        // High temp for rising BG
        let cli = AlgorithmOutput(
            tempBasalRate: 2.5,       // High temp
            tempBasalDuration: 1800,
            suggestedBolus: nil,
            eventualBG: 180.0,        // Predicted high
            success: true
        )
        let aid = AlgorithmOutput(
            tempBasalRate: 2.48,      // Within tolerance
            tempBasalDuration: 1810,  // Within tolerance
            suggestedBolus: nil,
            eventualBG: 180.5,        // Within tolerance
            success: true
        )
        
        let result = AlgorithmOutputConformanceResult.compare(cli, aid)
        #expect(result.passed)
    }
}

// MARK: - ALG-INPUT-019b: DeviceStateRecorder Tests

@Suite("DeviceStateRecorderTests")
struct DeviceStateRecorderTests {
    
    let baseTime = Date()
    
    // MARK: - CaptureConfig Tests
    
    @Test func defaultcaptureconfig() {
        let config = DeviceStateRecorder.CaptureConfig.default
        
        #expect(config.glucoseCount == 24)
        #expect(config.doseHistoryHours == 6)
        #expect(config.carbHistoryHours == 6)
    }
    
    @Test func extendedcaptureconfig() {
        let config = DeviceStateRecorder.CaptureConfig.extended
        
        #expect(config.glucoseCount == 288)
        #expect(config.doseHistoryHours == 24)
        #expect(config.carbHistoryHours == 24)
    }
    
    @Test func minimalcaptureconfig() {
        let config = DeviceStateRecorder.CaptureConfig.minimal
        
        #expect(config.glucoseCount == 6)
        #expect(config.doseHistoryHours == 1)
        #expect(config.carbHistoryHours == 1)
    }
    
    @Test func customcaptureconfig() {
        let config = DeviceStateRecorder.CaptureConfig(
            glucoseCount: 12,
            doseHistoryHours: 4,
            carbHistoryHours: 8
        )
        
        #expect(config.glucoseCount == 12)
        #expect(config.doseHistoryHours == 4)
        #expect(config.carbHistoryHours == 8)
    }
    
    // MARK: - Recorder Initialization Tests
    
    @Test func recorderinitialization() {
        let cgm = MockCGMDataProvider()
        let pump = MockPumpDataProvider()
        let settings = MockSettingsProvider()
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        
        // Just verify it compiles and initializes
        #expect(recorder != nil)
    }
    
    // MARK: - Capture State Tests
    
    func testCaptureStateBasic() async throws {
        let glucose = [GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat)]
        let doses = [InsulinDose(units: 2.0, timestamp: baseTime)]
        let carbs = [CarbEntry(grams: 30, timestamp: baseTime)]
        let profile = TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
        
        let cgm = MockCGMDataProvider(glucoseValues: glucose)
        let pump = MockPumpDataProvider(doses: doses, carbs: carbs)
        let settings = MockSettingsProvider(profile: profile)
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        let state = try await recorder.captureState(scenario: "test_basic")
        
        #expect(state.scenario == "test_basic")
        #expect(state.glucoseReadings.count == 1)
        #expect(state.insulinDoses.count == 1)
        #expect(state.carbEntries.count == 1)
        #expect(state.profile.carbRatios.first?.ratio == 10)
    }
    
    func testCaptureStateWithMinimalConfig() async throws {
        let glucose = (0..<10).map { i in
            GlucoseReading(glucose: 100 + Double(i), timestamp: baseTime.addingTimeInterval(Double(-i * 300)), trend: .flat)
        }
        let cgm = MockCGMDataProvider(glucoseValues: glucose)
        let pump = MockPumpDataProvider()
        let settings = MockSettingsProvider()
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        let state = try await recorder.captureState(config: .minimal)
        
        // Should only get 6 readings even though 10 are available
        #expect(state.glucoseReadings.count == 6)
    }
    
    func testCaptureStateWithExpectedValues() async throws {
        let cgm = MockCGMDataProvider()
        let pump = MockPumpDataProvider()
        let settings = MockSettingsProvider()
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        let state = try await recorder.captureStateWithExpected(
            scenario: "post_meal",
            iob: 3.5,
            cob: 45.0
        )
        
        #expect(state.scenario == "post_meal")
        #expect(state.expectedIOB == 3.5)
        #expect(state.expectedCOB == 45.0)
    }
    
    func testCaptureStatePreservesTimestamp() async throws {
        let cgm = MockCGMDataProvider()
        let pump = MockPumpDataProvider()
        let settings = MockSettingsProvider()
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        let beforeCapture = Date()
        let state = try await recorder.captureState()
        let afterCapture = Date()
        
        #expect(state.timestamp >= beforeCapture)
        #expect(state.timestamp <= afterCapture)
    }
    
    func testCaptureStateGeneratesUniqueId() async throws {
        let cgm = MockCGMDataProvider()
        let pump = MockPumpDataProvider()
        let settings = MockSettingsProvider()
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        let state1 = try await recorder.captureState()
        let state2 = try await recorder.captureState()
        
        #expect(state1.id != state2.id)
    }
    
    func testCaptureStateIncludesLoopSettings() async throws {
        let loopSettings = LoopSettings(
            maximumBolus: 10.0,
            minimumBGGuard: 70.0
        )
        let cgm = MockCGMDataProvider()
        let pump = MockPumpDataProvider()
        let settings = MockSettingsProvider(settings: loopSettings)
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        let state = try await recorder.captureState()
        
        #expect(state.loopSettings != nil)
        #expect(state.loopSettings?.maximumBolus == 10.0)
        #expect(state.loopSettings?.minimumBGGuard == 70.0)
    }
    
    // MARK: - Edge Cases
    
    func testCaptureStateWithEmptyData() async throws {
        let cgm = MockCGMDataProvider(glucoseValues: [])
        let pump = MockPumpDataProvider(doses: [], carbs: [])
        let settings = MockSettingsProvider()
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        let state = try await recorder.captureState()
        
        #expect(state.glucoseReadings.isEmpty)
        #expect(state.insulinDoses.isEmpty)
        #expect(state.carbEntries.isEmpty)
    }
    
    func testCaptureStateWithLargeDataset() async throws {
        // 288 readings (24 hours at 5-min intervals)
        let glucose = (0..<288).map { i in
            GlucoseReading(glucose: 100 + Double(i % 50), timestamp: baseTime.addingTimeInterval(Double(-i * 300)), trend: .flat)
        }
        // 48 doses (one every 30 min)
        let doses = (0..<48).map { i in
            InsulinDose(units: 0.5, timestamp: baseTime.addingTimeInterval(Double(-i * 1800)))
        }
        
        let cgm = MockCGMDataProvider(glucoseValues: glucose)
        let pump = MockPumpDataProvider(doses: doses)
        let settings = MockSettingsProvider()
        
        let recorder = DeviceStateRecorder(cgm: cgm, pump: pump, settings: settings)
        let state = try await recorder.captureState(config: DeviceStateRecorder.CaptureConfig.extended)
        
        #expect(state.glucoseReadings.count == 288)
        #expect(state.insulinDoses.count > 0)
    }
}

// MARK: - RecordedStateDataSource Tests (ALG-INPUT-019c)

@Suite("RecordedStateDataSourceTests")
struct RecordedStateDataSourceTests {
    
    // Use instance property to avoid Date() drift (ALG-TEST-FIX-002)
    let baseTime: Date
    
    init() {
        baseTime = Date()
    }
    
    var sampleProfile: TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
    }
    
    // MARK: - Initialization
    
    @Test func datasourceinitialization() {
        let state = RecordedDeviceState(
            glucoseReadings: [],
            profile: sampleProfile
        )
        let dataSource = RecordedStateDataSource(state: state)
        
        #expect(dataSource.state.id == state.id)
    }
    
    // MARK: - Glucose History
    
    func testGlucoseHistoryReturnsReadings() async throws {
        let readings = [
            GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat),
            GlucoseReading(glucose: 115, timestamp: baseTime.addingTimeInterval(-300), trend: .flat),
            GlucoseReading(glucose: 110, timestamp: baseTime.addingTimeInterval(-600), trend: .flat)
        ]
        let state = RecordedDeviceState(glucoseReadings: readings, profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.glucoseHistory(count: 10)
        
        #expect(result.count == 3)
    }
    
    func testGlucoseHistoryRespectsCount() async throws {
        let readings = (0..<20).map { i in
            GlucoseReading(glucose: 100 + Double(i), timestamp: baseTime.addingTimeInterval(Double(-i * 300)), trend: .flat)
        }
        let state = RecordedDeviceState(glucoseReadings: readings, profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.glucoseHistory(count: 5)
        
        #expect(result.count == 5)
    }
    
    func testGlucoseHistorySortedNewestFirst() async throws {
        let readings = [
            GlucoseReading(glucose: 110, timestamp: baseTime.addingTimeInterval(-600), trend: .flat),
            GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat),
            GlucoseReading(glucose: 115, timestamp: baseTime.addingTimeInterval(-300), trend: .flat)
        ]
        let state = RecordedDeviceState(glucoseReadings: readings, profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.glucoseHistory(count: 10)
        
        #expect(result.first?.glucose == 120) // Newest
        #expect(result.last?.glucose == 110)  // Oldest
    }
    
    // MARK: - Dose History
    
    func testDoseHistoryFiltersByTimeWindow() async throws {
        let doses = [
            InsulinDose(units: 1.0, timestamp: baseTime),                            // Now
            InsulinDose(units: 2.0, timestamp: baseTime.addingTimeInterval(-3600)),  // 1 hour ago
            InsulinDose(units: 3.0, timestamp: baseTime.addingTimeInterval(-10800)), // 3 hours ago
            InsulinDose(units: 4.0, timestamp: baseTime.addingTimeInterval(-25200))  // 7 hours ago
        ]
        let state = RecordedDeviceState(glucoseReadings: [], insulinDoses: doses, profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.doseHistory(hours: 6)
        
        #expect(result.count == 3) // Only doses within 6 hours
    }
    
    func testDoseHistorySortedNewestFirst() async throws {
        let doses = [
            InsulinDose(units: 3.0, timestamp: baseTime.addingTimeInterval(-600)),
            InsulinDose(units: 1.0, timestamp: baseTime),
            InsulinDose(units: 2.0, timestamp: baseTime.addingTimeInterval(-300))
        ]
        let state = RecordedDeviceState(glucoseReadings: [], insulinDoses: doses, profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.doseHistory(hours: 1)
        
        #expect(result.first?.units == 1.0) // Newest
        #expect(result.last?.units == 3.0)  // Oldest
    }
    
    // MARK: - Carb History
    
    func testCarbHistoryFiltersByTimeWindow() async throws {
        let carbs = [
            CarbEntry(grams: 30, timestamp: baseTime),                            // Now
            CarbEntry(grams: 20, timestamp: baseTime.addingTimeInterval(-7200)),  // 2 hours ago
            CarbEntry(grams: 10, timestamp: baseTime.addingTimeInterval(-14400))  // 4 hours ago
        ]
        let state = RecordedDeviceState(glucoseReadings: [], carbEntries: carbs, profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.carbHistory(hours: 3)
        
        #expect(result.count == 2) // Only carbs within 3 hours
    }
    
    func testCarbHistorySortedNewestFirst() async throws {
        let carbs = [
            CarbEntry(grams: 10, timestamp: baseTime.addingTimeInterval(-600)),
            CarbEntry(grams: 30, timestamp: baseTime),
            CarbEntry(grams: 20, timestamp: baseTime.addingTimeInterval(-300))
        ]
        let state = RecordedDeviceState(glucoseReadings: [], carbEntries: carbs, profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.carbHistory(hours: 1)
        
        #expect(result.first?.grams == 30) // Newest
        #expect(result.last?.grams == 10)  // Oldest
    }
    
    // MARK: - Profile and Settings
    
    func testCurrentProfileReturnsRecordedProfile() async throws {
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let profile = try await dataSource.currentProfile()
        
        #expect(profile.carbRatios.first?.ratio == 10)
        #expect(profile.sensitivityFactors.first?.factor == 50)
    }
    
    func testLoopSettingsReturnsRecordedSettings() async throws {
        let settings = LoopSettings(maximumBolus: 10.0, minimumBGGuard: 70.0)
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile, loopSettings: settings)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.loopSettings()
        
        #expect(result != nil)
        #expect(result?.maximumBolus == 10.0)
        #expect(result?.minimumBGGuard == 70.0)
    }
    
    func testLoopSettingsReturnsNilWhenNotRecorded() async throws {
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        let result = try await dataSource.loopSettings()
        
        #expect(result == nil)
    }
    
    // MARK: - Extension Properties
    
    @Test func allglucosereadingsproperty() {
        let readings = (0..<10).map { i in
            GlucoseReading(glucose: 100 + Double(i), timestamp: baseTime.addingTimeInterval(Double(-i * 300)), trend: .flat)
        }
        let state = RecordedDeviceState(glucoseReadings: readings, profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        #expect(dataSource.allGlucoseReadings.count == 10)
    }
    
    @Test func expectediobproperty() {
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile, expectedIOB: 2.5)
        let dataSource = RecordedStateDataSource(state: state)
        
        #expect(dataSource.expectedIOB == 2.5)
    }
    
    @Test func expectedcobproperty() {
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile, expectedCOB: 30.0)
        let dataSource = RecordedStateDataSource(state: state)
        
        #expect(dataSource.expectedCOB == 30.0)
    }
    
    @Test func referencetimeproperty() {
        let specificTime = Date(timeIntervalSince1970: 1000000)
        let state = RecordedDeviceState(timestamp: specificTime, glucoseReadings: [], profile: sampleProfile)
        let dataSource = RecordedStateDataSource(state: state)
        
        #expect(dataSource.referenceTime == specificTime)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyStateReturnsEmptyResults() async throws {
        let state = RecordedDeviceState(
            glucoseReadings: [],
            insulinDoses: [],
            carbEntries: [],
            profile: sampleProfile
        )
        let dataSource = RecordedStateDataSource(state: state)
        
        let glucose = try await dataSource.glucoseHistory(count: 10)
        let doses = try await dataSource.doseHistory(hours: 6)
        let carbs = try await dataSource.carbHistory(hours: 6)
        
        #expect(glucose.isEmpty)
        #expect(doses.isEmpty)
        #expect(carbs.isEmpty)
    }
    
    func testLargeDatasetHandling() async throws {
        // 288 glucose readings (24 hours at 5-min intervals)
        let readings = (0..<288).map { i in
            GlucoseReading(glucose: 100 + Double(i % 50), timestamp: baseTime.addingTimeInterval(Double(-i * 300)), trend: .flat)
        }
        // 48 doses
        let doses = (0..<48).map { i in
            InsulinDose(units: 0.5, timestamp: baseTime.addingTimeInterval(Double(-i * 1800)))
        }
        
        let state = RecordedDeviceState(
            glucoseReadings: readings,
            insulinDoses: doses,
            profile: sampleProfile
        )
        let dataSource = RecordedStateDataSource(state: state)
        
        let glucoseResult = try await dataSource.glucoseHistory(count: 100)
        let doseResult = try await dataSource.doseHistory(hours: 24)
        
        #expect(glucoseResult.count == 100)
        #expect(doseResult.count == 48)
    }
}

// MARK: - RecordedStateDirectDataSource Tests (ALG-INPUT-019d)

@Suite("RecordedStateDirectDataSourceTests")
struct RecordedStateDirectDataSourceTests {
    
    // Use instance property to avoid Date() drift (ALG-TEST-FIX-002)
    let baseTime: Date
    
    init() {
        baseTime = Date()
    }
    
    var sampleProfile: TherapyProfile {
        TherapyProfile(
            basalRates: [BasalRate(startTime: 0, rate: 1.0)],
            carbRatios: [CarbRatio(startTime: 0, ratio: 10)],
            sensitivityFactors: [SensitivityFactor(startTime: 0, factor: 50)],
            targetGlucose: TargetRange(low: 100, high: 120)
        )
    }
    
    // MARK: - RecordedStateCGMProvider Tests
    
    @Test func testCGMProviderReturnsGlucoseHistory() async throws {
        let readings = [
            GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat),
            GlucoseReading(glucose: 115, timestamp: baseTime.addingTimeInterval(-300), trend: .flat),
            GlucoseReading(glucose: 110, timestamp: baseTime.addingTimeInterval(-600), trend: .flat)
        ]
        let state = RecordedDeviceState(glucoseReadings: readings, profile: sampleProfile)
        let provider = RecordedStateCGMProvider(state: state)
        
        let result = try await provider.glucoseHistory(count: 10)
        
        #expect(result.count == 3)
    }
    
    func testCGMProviderLatestGlucose() async throws {
        let readings = [
            GlucoseReading(glucose: 110, timestamp: baseTime.addingTimeInterval(-600), trend: .flat),
            GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat),
            GlucoseReading(glucose: 115, timestamp: baseTime.addingTimeInterval(-300), trend: .flat)
        ]
        let state = RecordedDeviceState(glucoseReadings: readings, profile: sampleProfile)
        let provider = RecordedStateCGMProvider(state: state)
        
        let latest = await provider.latestGlucose
        
        #expect(latest?.glucose == 120) // Newest reading
    }
    
    func testCGMProviderRespectsCount() async throws {
        let readings = (0..<20).map { i in
            GlucoseReading(glucose: 100 + Double(i), timestamp: baseTime.addingTimeInterval(Double(-i * 300)), trend: .flat)
        }
        let state = RecordedDeviceState(glucoseReadings: readings, profile: sampleProfile)
        let provider = RecordedStateCGMProvider(state: state)
        
        let result = try await provider.glucoseHistory(count: 5)
        
        #expect(result.count == 5)
    }
    
    // MARK: - RecordedStatePumpProvider Tests
    
    func testPumpProviderDoseHistory() async throws {
        let doses = [
            InsulinDose(units: 1.0, timestamp: baseTime),
            InsulinDose(units: 2.0, timestamp: baseTime.addingTimeInterval(-3600)),
            InsulinDose(units: 3.0, timestamp: baseTime.addingTimeInterval(-7200))
        ]
        let state = RecordedDeviceState(glucoseReadings: [], insulinDoses: doses, profile: sampleProfile)
        let provider = RecordedStatePumpProvider(state: state)
        
        let result = try await provider.doseHistory(hours: 6)
        
        #expect(result.count == 3)
    }
    
    func testPumpProviderDoseHistoryFiltersByTime() async throws {
        let doses = [
            InsulinDose(units: 1.0, timestamp: baseTime),
            InsulinDose(units: 2.0, timestamp: baseTime.addingTimeInterval(-7200)),  // 2 hours ago
            InsulinDose(units: 3.0, timestamp: baseTime.addingTimeInterval(-14400))  // 4 hours ago
        ]
        let state = RecordedDeviceState(glucoseReadings: [], insulinDoses: doses, profile: sampleProfile)
        let provider = RecordedStatePumpProvider(state: state)
        
        let result = try await provider.doseHistory(hours: 3)
        
        #expect(result.count == 2) // Only doses within 3 hours
    }
    
    func testPumpProviderCarbHistory() async throws {
        let carbs = [
            CarbEntry(grams: 30, timestamp: baseTime),
            CarbEntry(grams: 20, timestamp: baseTime.addingTimeInterval(-1800))
        ]
        let state = RecordedDeviceState(glucoseReadings: [], carbEntries: carbs, profile: sampleProfile)
        let provider = RecordedStatePumpProvider(state: state)
        
        let result = try await provider.carbHistory(hours: 1)
        
        #expect(result.count == 2)
    }
    
    func testPumpProviderCarbHistoryFiltersByTime() async throws {
        let carbs = [
            CarbEntry(grams: 30, timestamp: baseTime),
            CarbEntry(grams: 20, timestamp: baseTime.addingTimeInterval(-7200)),   // 2 hours ago
            CarbEntry(grams: 10, timestamp: baseTime.addingTimeInterval(-14400))   // 4 hours ago
        ]
        let state = RecordedDeviceState(glucoseReadings: [], carbEntries: carbs, profile: sampleProfile)
        let provider = RecordedStatePumpProvider(state: state)
        
        let result = try await provider.carbHistory(hours: 3)
        
        #expect(result.count == 2) // Only carbs within 3 hours
    }
    
    func testPumpProviderReservoirLevelNil() async throws {
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile)
        let provider = RecordedStatePumpProvider(state: state)
        
        let level = await provider.reservoirLevel
        
        #expect(level == nil) // Not recorded
    }
    
    // MARK: - RecordedStateSettingsProvider Tests
    
    func testSettingsProviderReturnsProfile() async throws {
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile)
        let provider = RecordedStateSettingsProvider(state: state)
        
        let profile = try await provider.currentProfile()
        
        #expect(profile.carbRatios.first?.ratio == 10)
        #expect(profile.sensitivityFactors.first?.factor == 50)
    }
    
    func testSettingsProviderReturnsLoopSettings() async throws {
        let settings = LoopSettings(maximumBolus: 10.0, minimumBGGuard: 70.0)
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile, loopSettings: settings)
        let provider = RecordedStateSettingsProvider(state: state)
        
        let result = try await provider.loopSettings()
        
        #expect(result != nil)
        #expect(result?.maximumBolus == 10.0)
    }
    
    func testSettingsProviderReturnsNilLoopSettings() async throws {
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile)
        let provider = RecordedStateSettingsProvider(state: state)
        
        let result = try await provider.loopSettings()
        
        #expect(result == nil)
    }
    
    // MARK: - RecordedStateDirectDataSource Integration Tests
    
    @Test func directdatasourcecreation() {
        let state = RecordedDeviceState(glucoseReadings: [], profile: sampleProfile)
        let wrapper = RecordedStateDirectDataSource(state: state)
        
        #expect(wrapper.dataSource != nil)
        #expect(wrapper.cgmProvider != nil)
        #expect(wrapper.pumpProvider != nil)
        #expect(wrapper.settingsProvider != nil)
    }
    
    func testDirectDataSourceIntegration() async throws {
        let readings = [
            GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat),
            GlucoseReading(glucose: 115, timestamp: baseTime.addingTimeInterval(-300), trend: .flat)
        ]
        let doses = [
            InsulinDose(units: 2.0, timestamp: baseTime)
        ]
        let carbs = [
            CarbEntry(grams: 30, timestamp: baseTime)
        ]
        let state = RecordedDeviceState(
            glucoseReadings: readings,
            insulinDoses: doses,
            carbEntries: carbs,
            profile: sampleProfile
        )
        let wrapper = RecordedStateDirectDataSource(state: state)
        
        // Test through DirectDataSource interface
        let glucose = try await wrapper.dataSource.glucoseHistory(count: 10)
        let doseHistory = try await wrapper.dataSource.doseHistory(hours: 6)
        let carbHistory = try await wrapper.dataSource.carbHistory(hours: 6)
        let profile = try await wrapper.dataSource.currentProfile()
        
        #expect(glucose.count == 2)
        #expect(doseHistory.count == 1)
        #expect(carbHistory.count == 1)
        #expect(profile.carbRatios.first?.ratio == 10)
    }
    
    @Test func directdatasourceextensionproperties() {
        let state = RecordedDeviceState(
            timestamp: baseTime,
            scenario: "test_scenario",
            glucoseReadings: [],
            profile: sampleProfile,
            expectedIOB: 2.5,
            expectedCOB: 30.0
        )
        let wrapper = RecordedStateDirectDataSource(state: state)
        
        #expect(wrapper.expectedIOB == 2.5)
        #expect(wrapper.expectedCOB == 30.0)
        #expect(wrapper.referenceTime == baseTime)
        #expect(wrapper.scenario == "test_scenario")
    }
    
    // MARK: - Conformance Path Comparison
    
    func testBothAdaptersProduceSameResults() async throws {
        let readings = [
            GlucoseReading(glucose: 120, timestamp: baseTime, trend: .flat),
            GlucoseReading(glucose: 115, timestamp: baseTime.addingTimeInterval(-300), trend: .flat)
        ]
        let doses = [
            InsulinDose(units: 2.0, timestamp: baseTime)
        ]
        let state = RecordedDeviceState(
            glucoseReadings: readings,
            insulinDoses: doses,
            profile: sampleProfile
        )
        
        // CLI path adapter
        let cliAdapter = RecordedStateDataSource(state: state)
        
        // AID path adapter
        let aidAdapter = RecordedStateDirectDataSource(state: state)
        
        // Both should return the same glucose data
        let cliGlucose = try await cliAdapter.glucoseHistory(count: 10)
        let aidGlucose = try await aidAdapter.dataSource.glucoseHistory(count: 10)
        
        #expect(cliGlucose.count == aidGlucose.count)
        #expect(cliGlucose.first?.glucose == aidGlucose.first?.glucose)
        
        // Both should return the same dose data
        let cliDoses = try await cliAdapter.doseHistory(hours: 6)
        let aidDoses = try await aidAdapter.dataSource.doseHistory(hours: 6)
        
        #expect(cliDoses.count == aidDoses.count)
        
        // Both should return the same profile
        let cliProfile = try await cliAdapter.currentProfile()
        let aidProfile = try await aidAdapter.dataSource.currentProfile()
        
        #expect(cliProfile.carbRatios.first?.ratio == aidProfile.carbRatios.first?.ratio)
    }
}

// MARK: - ConformanceFixtures Tests (ALG-INPUT-019l)

@Suite("ConformanceFixturesTests")
struct ConformanceFixturesTests {
    
    // MARK: - Fixture Availability
    
    @Test func allfixturesexist() {
        let all = ConformanceFixtures.all
        #expect(all.count == 6)
    }
    
    @Test func fixturescenarionames() {
        let expectedScenarios = [
            "stable_overnight",
            "post_meal_rise",
            "exercise_low",
            "missed_bolus",
            "stacking_boluses",
            "dawn_phenomenon"
        ]
        
        for scenario in expectedScenarios {
            let fixture = ConformanceFixtures.fixture(named: scenario)
            #expect(fixture != nil, "Missing fixture: \(scenario)")
        }
    }
    
    // MARK: - Fixture Validation
    
    @Test func allfixturespassvalidation() {
        let results = ConformanceFixtures.validateAll()
        
        for (scenario, issues) in results {
            #expect(issues.isEmpty, "Fixture \(scenario) has issues: \(issues)")
        }
    }
    
    @Test func stableovernightfixture() {
        let fixture = ConformanceFixtures.stableOvernight
        
        #expect(fixture.scenario == "stable_overnight")
        #expect(fixture.glucoseReadings.count == 36)
        #expect(!(fixture.insulinDoses.isEmpty))
        #expect(fixture.carbEntries.isEmpty)
        #expect(fixture.expectedIOB != nil)
        #expect(fixture.expectedCOB == 0.0)
    }
    
    @Test func postmealrisefixture() {
        let fixture = ConformanceFixtures.postMealRise
        
        #expect(fixture.scenario == "post_meal_rise")
        #expect(!(fixture.glucoseReadings.isEmpty))
        #expect(!(fixture.insulinDoses.isEmpty))
        #expect(fixture.carbEntries.count == 1)
        #expect(fixture.carbEntries.first?.grams == 45)
        #expect(fixture.expectedIOB ?? 0 > 2.0)
        #expect(fixture.expectedCOB ?? 0 > 10.0)
    }
    
    @Test func exerciselowfixture() {
        let fixture = ConformanceFixtures.exerciseLow
        
        #expect(fixture.scenario == "exercise_low")
        #expect(!(fixture.glucoseReadings.isEmpty))
        #expect(fixture.carbEntries.isEmpty)
        // Low IOB expected during exercise
        #expect(fixture.expectedIOB ?? 10 < 0.5)
    }
    
    @Test func missedbolusfixture() {
        let fixture = ConformanceFixtures.missedBolus
        
        #expect(fixture.scenario == "missed_bolus")
        #expect(!(fixture.carbEntries.isEmpty))
        // High COB from unbolused meal
        #expect(fixture.expectedCOB ?? 0 > 30.0)
        // Low IOB (no bolus given)
        #expect(fixture.expectedIOB ?? 10 < 1.5)
    }
    
    @Test func stackingbolusesfixture() {
        let fixture = ConformanceFixtures.stackingBoluses
        
        #expect(fixture.scenario == "stacking_boluses")
        // High IOB from stacked corrections
        #expect(fixture.expectedIOB ?? 0 > 4.0)
        // Multiple bolus doses
        let bolusDoses = fixture.insulinDoses.filter { $0.source == "bolus" }
        #expect(bolusDoses.count >= 2)
    }
    
    @Test func dawnphenomenonfixture() {
        let fixture = ConformanceFixtures.dawnPhenomenon
        
        #expect(fixture.scenario == "dawn_phenomenon")
        #expect(fixture.carbEntries.isEmpty)
        #expect(fixture.expectedCOB == 0.0)
        // Has temp basals
        let tempBasals = fixture.insulinDoses.filter { $0.source == "tempBasal" }
        #expect(tempBasals.count > 0)
    }
    
    // MARK: - Profile Consistency
    
    @Test func allfixtureshavestandardprofile() {
        for fixture in ConformanceFixtures.all {
            #expect(!fixture.profile.basalRates.isEmpty, "\(fixture.scenario) missing basal rates")
            #expect(!fixture.profile.carbRatios.isEmpty, "\(fixture.scenario) missing carb ratios")
            #expect(!fixture.profile.sensitivityFactors.isEmpty, "\(fixture.scenario) missing ISF")
        }
    }
    
    @Test func allfixtureshaveloopsettings() {
        for fixture in ConformanceFixtures.all {
            #expect(fixture.loopSettings != nil, "\(fixture.scenario) missing Loop settings")
        }
    }
    
    // MARK: - Adapter Integration
    
    func testFixturesWorkWithCLIAdapter() async throws {
        for fixture in ConformanceFixtures.all {
            let adapter = RecordedStateDataSource(state: fixture)
            let glucose = try await adapter.glucoseHistory(count: 10)
            #expect(!glucose.isEmpty, "\(fixture.scenario) returned no glucose via CLI adapter")
        }
    }
    
    func testFixturesWorkWithAIDAdapter() async throws {
        for fixture in ConformanceFixtures.all {
            let adapter = RecordedStateDirectDataSource(state: fixture)
            let glucose = try await adapter.dataSource.glucoseHistory(count: 10)
            #expect(!glucose.isEmpty, "\(fixture.scenario) returned no glucose via AID adapter")
        }
    }
    
    func testBothAdaptersMatchForAllFixtures() async throws {
        for fixture in ConformanceFixtures.all {
            let cli = RecordedStateDataSource(state: fixture)
            let aid = RecordedStateDirectDataSource(state: fixture)
            
            let cliGlucose = try await cli.glucoseHistory(count: 20)
            let aidGlucose = try await aid.dataSource.glucoseHistory(count: 20)
            
            #expect(
                cliGlucose.count == aidGlucose.count,
                "\(fixture.scenario): glucose count mismatch"
            )
            
            let cliProfile = try await cli.currentProfile()
            let aidProfile = try await aid.dataSource.currentProfile()
            
            #expect(
                cliProfile.carbRatios.first?.ratio == aidProfile.carbRatios.first?.ratio,
                "\(fixture.scenario): profile mismatch"
            )
        }
    }
}
