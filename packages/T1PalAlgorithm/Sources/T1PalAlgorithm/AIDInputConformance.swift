// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AIDInputConformance.swift
// T1Pal Mobile
//
// Conformance test infrastructure for AID app vs CLI input assembly
// Requirements: ALG-INPUT-019a
//
// Validates that DirectDataSource (AID app path) produces the same
// AlgorithmInputs as NightscoutDataSource (CLI path) for identical
// device states.

import Foundation
import T1PalCore

// MARK: - Recorded Device State (ALG-INPUT-019b)

/// Snapshot of device state for conformance testing.
///
/// Captures all data needed to reproduce algorithm inputs via both
/// CLI (Nightscout) and AID (Direct) paths.
///
/// Usage:
/// ```swift
/// let recorder = DeviceStateRecorder(cgm: cgmManager, pump: pumpManager)
/// let state = try await recorder.captureCurrentState()
/// // Later: replay through both paths and compare
/// ```
public struct RecordedDeviceState: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let scenario: String
    
    // CGM data
    public let glucoseReadings: [GlucoseReading]
    
    // Pump data
    public let insulinDoses: [InsulinDose]
    public let carbEntries: [CarbEntry]
    
    // Settings
    public let profile: TherapyProfile
    public let loopSettings: LoopSettings?
    public let basalSchedule: [ScheduledBasalRate]?
    
    // Pre-calculated values (for validation)
    public let expectedIOB: Double?
    public let expectedCOB: Double?
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        scenario: String = "unknown",
        glucoseReadings: [GlucoseReading],
        insulinDoses: [InsulinDose] = [],
        carbEntries: [CarbEntry] = [],
        profile: TherapyProfile,
        loopSettings: LoopSettings? = nil,
        basalSchedule: [ScheduledBasalRate]? = nil,
        expectedIOB: Double? = nil,
        expectedCOB: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.scenario = scenario
        self.glucoseReadings = glucoseReadings
        self.insulinDoses = insulinDoses
        self.carbEntries = carbEntries
        self.profile = profile
        self.loopSettings = loopSettings
        self.basalSchedule = basalSchedule
        self.expectedIOB = expectedIOB
        self.expectedCOB = expectedCOB
    }
}

/// Scheduled basal rate entry for recording
public struct ScheduledBasalRate: Codable, Sendable {
    public let startTime: TimeInterval  // Seconds from midnight
    public let rate: Double             // U/hr
    
    public init(startTime: TimeInterval, rate: Double) {
        self.startTime = startTime
        self.rate = rate
    }
}

// MARK: - Conformance Test Protocol (ALG-INPUT-019a)

/// Protocol for AID input conformance testing.
///
/// Implementations run the same device state through both CLI and AID
/// paths, then compare the resulting AlgorithmInputs.
public protocol AIDInputConformanceTest: Sendable {
    /// Run state through CLI path (via NightscoutDataSource adapter)
    func runCLIPath(_ state: RecordedDeviceState) async throws -> AlgorithmInputs
    
    /// Run state through AID path (via DirectDataSource adapter)
    func runAIDPath(_ state: RecordedDeviceState) async throws -> AlgorithmInputs
    
    /// Compare inputs with tolerances and return result
    func compareInputs(_ cli: AlgorithmInputs, _ aid: AlgorithmInputs) -> AIDInputConformanceResult
}

// MARK: - Conformance Result

/// Result of comparing CLI and AID path inputs
public struct AIDInputConformanceResult: Sendable {
    public let passed: Bool
    public let glucoseMatch: FieldComparisonResult
    public let iobMatch: FieldComparisonResult
    public let cobMatch: FieldComparisonResult
    public let doseHistoryMatch: FieldComparisonResult
    public let carbHistoryMatch: FieldComparisonResult
    public let profileMatch: FieldComparisonResult
    
    public var summary: String {
        let fields = [
            ("Glucose", glucoseMatch),
            ("IOB", iobMatch),
            ("COB", cobMatch),
            ("DoseHistory", doseHistoryMatch),
            ("CarbHistory", carbHistoryMatch),
            ("Profile", profileMatch)
        ]
        let failures = fields.filter { !$0.1.matches }
        if failures.isEmpty {
            return "✅ All fields match"
        } else {
            return "❌ Mismatches: " + failures.map { "\($0.0): \($0.1.reason)" }.joined(separator: "; ")
        }
    }
    
    public init(
        glucoseMatch: FieldComparisonResult,
        iobMatch: FieldComparisonResult,
        cobMatch: FieldComparisonResult,
        doseHistoryMatch: FieldComparisonResult,
        carbHistoryMatch: FieldComparisonResult,
        profileMatch: FieldComparisonResult
    ) {
        self.glucoseMatch = glucoseMatch
        self.iobMatch = iobMatch
        self.cobMatch = cobMatch
        self.doseHistoryMatch = doseHistoryMatch
        self.carbHistoryMatch = carbHistoryMatch
        self.profileMatch = profileMatch
        self.passed = glucoseMatch.matches && iobMatch.matches && cobMatch.matches &&
                      doseHistoryMatch.matches && carbHistoryMatch.matches && profileMatch.matches
    }
}

/// Result of comparing a single field
public struct FieldComparisonResult: Sendable {
    public let matches: Bool
    public let reason: String
    public let cliValue: String
    public let aidValue: String
    
    public static func match() -> FieldComparisonResult {
        FieldComparisonResult(matches: true, reason: "Match", cliValue: "", aidValue: "")
    }
    
    public static func mismatch(reason: String, cli: String, aid: String) -> FieldComparisonResult {
        FieldComparisonResult(matches: false, reason: reason, cliValue: cli, aidValue: aid)
    }
    
    public init(matches: Bool, reason: String, cliValue: String, aidValue: String) {
        self.matches = matches
        self.reason = reason
        self.cliValue = cliValue
        self.aidValue = aidValue
    }
}

// MARK: - Tolerances

/// Tolerances for AID input conformance comparisons
public enum AIDInputConformanceTolerance {
    /// IOB tolerance in units
    public static let iob: Double = 0.01
    
    /// COB tolerance in grams
    public static let cob: Double = 1.0
    
    /// Glucose tolerance in mg/dL
    public static let glucose: Double = 0.5
    
    /// Timestamp tolerance in seconds
    public static let timestamp: TimeInterval = 1.0
    
    /// Temp basal rate tolerance in U/hr
    public static let basalRate: Double = 0.05
    
    /// ISF tolerance in mg/dL/U
    public static let isf: Double = 0.1
    
    /// CR tolerance in g/U
    public static let carbRatio: Double = 0.1
}

// MARK: - Comparison Helpers

public extension AIDInputConformanceResult {
    
    /// Compare two AlgorithmInputs with tolerances
    static func compare(_ cli: AlgorithmInputs, _ aid: AlgorithmInputs) -> AIDInputConformanceResult {
        AIDInputConformanceResult(
            glucoseMatch: compareGlucose(cli.glucose, aid.glucose),
            iobMatch: compareIOB(cli.insulinOnBoard, aid.insulinOnBoard),
            cobMatch: compareCOB(cli.carbsOnBoard, aid.carbsOnBoard),
            doseHistoryMatch: compareDoseHistory(cli.doseHistory, aid.doseHistory),
            carbHistoryMatch: compareCarbHistory(cli.carbHistory, aid.carbHistory),
            profileMatch: compareProfile(cli.profile, aid.profile)
        )
    }
    
    private static func compareGlucose(_ cli: [GlucoseReading], _ aid: [GlucoseReading]) -> FieldComparisonResult {
        guard cli.count == aid.count else {
            return .mismatch(reason: "count", cli: "\(cli.count)", aid: "\(aid.count)")
        }
        
        for (i, (c, a)) in zip(cli, aid).enumerated() {
            if abs(c.glucose - a.glucose) > AIDInputConformanceTolerance.glucose {
                return .mismatch(reason: "value[\(i)]", cli: "\(c.glucose)", aid: "\(a.glucose)")
            }
            if abs(c.timestamp.timeIntervalSince(a.timestamp)) > AIDInputConformanceTolerance.timestamp {
                return .mismatch(reason: "timestamp[\(i)]", cli: "\(c.timestamp)", aid: "\(a.timestamp)")
            }
        }
        return .match()
    }
    
    private static func compareIOB(_ cli: Double, _ aid: Double) -> FieldComparisonResult {
        if abs(cli - aid) <= AIDInputConformanceTolerance.iob {
            return .match()
        }
        return .mismatch(reason: "delta=\(String(format: "%.3f", abs(cli - aid)))U", 
                        cli: String(format: "%.3f", cli), 
                        aid: String(format: "%.3f", aid))
    }
    
    private static func compareCOB(_ cli: Double, _ aid: Double) -> FieldComparisonResult {
        if abs(cli - aid) <= AIDInputConformanceTolerance.cob {
            return .match()
        }
        return .mismatch(reason: "delta=\(String(format: "%.1f", abs(cli - aid)))g",
                        cli: String(format: "%.1f", cli),
                        aid: String(format: "%.1f", aid))
    }
    
    private static func compareDoseHistory(_ cli: [InsulinDose]?, _ aid: [InsulinDose]?) -> FieldComparisonResult {
        switch (cli, aid) {
        case (nil, nil):
            return .match()
        case (let c?, nil):
            return .mismatch(reason: "AID missing history", cli: "\(c.count) doses", aid: "nil")
        case (nil, let a?):
            return .mismatch(reason: "CLI missing history", cli: "nil", aid: "\(a.count) doses")
        case (let c?, let a?):
            if c.count != a.count {
                return .mismatch(reason: "count", cli: "\(c.count)", aid: "\(a.count)")
            }
            // Check total units match (detailed comparison can be expanded)
            let cliTotal = c.reduce(0) { $0 + $1.units }
            let aidTotal = a.reduce(0) { $0 + $1.units }
            if abs(cliTotal - aidTotal) > 0.01 {
                return .mismatch(reason: "total units", 
                                cli: String(format: "%.2f", cliTotal),
                                aid: String(format: "%.2f", aidTotal))
            }
            return .match()
        }
    }
    
    private static func compareCarbHistory(_ cli: [CarbEntry]?, _ aid: [CarbEntry]?) -> FieldComparisonResult {
        switch (cli, aid) {
        case (nil, nil):
            return .match()
        case (let c?, nil):
            return .mismatch(reason: "AID missing history", cli: "\(c.count) entries", aid: "nil")
        case (nil, let a?):
            return .mismatch(reason: "CLI missing history", cli: "nil", aid: "\(a.count) entries")
        case (let c?, let a?):
            if c.count != a.count {
                return .mismatch(reason: "count", cli: "\(c.count)", aid: "\(a.count)")
            }
            let cliTotal = c.reduce(0) { $0 + $1.grams }
            let aidTotal = a.reduce(0) { $0 + $1.grams }
            if abs(cliTotal - aidTotal) > 1.0 {
                return .mismatch(reason: "total grams",
                                cli: String(format: "%.0f", cliTotal),
                                aid: String(format: "%.0f", aidTotal))
            }
            return .match()
        }
    }
    
    private static func compareProfile(_ cli: TherapyProfile, _ aid: TherapyProfile) -> FieldComparisonResult {
        // Compare key profile fields
        if cli.sensitivityFactors.count != aid.sensitivityFactors.count {
            return .mismatch(reason: "ISF schedule count",
                            cli: "\(cli.sensitivityFactors.count)",
                            aid: "\(aid.sensitivityFactors.count)")
        }
        if cli.carbRatios.count != aid.carbRatios.count {
            return .mismatch(reason: "CR schedule count",
                            cli: "\(cli.carbRatios.count)",
                            aid: "\(aid.carbRatios.count)")
        }
        // More detailed comparison can be added
        return .match()
    }
}

// MARK: - Mock Conformance Runner

/// Simple conformance runner using mock adapters for testing
public struct MockAIDInputConformanceRunner: AIDInputConformanceTest {
    
    public init() {}
    
    public func runCLIPath(_ state: RecordedDeviceState) async throws -> AlgorithmInputs {
        // Simulates CLI path by building inputs from recorded state
        AlgorithmInputs(
            glucose: state.glucoseReadings,
            insulinOnBoard: state.expectedIOB ?? 0,
            carbsOnBoard: state.expectedCOB ?? 0,
            profile: state.profile,
            doseHistory: state.insulinDoses.isEmpty ? nil : state.insulinDoses,
            carbHistory: state.carbEntries.isEmpty ? nil : state.carbEntries
        )
    }
    
    public func runAIDPath(_ state: RecordedDeviceState) async throws -> AlgorithmInputs {
        // Simulates AID path - should produce identical results
        AlgorithmInputs(
            glucose: state.glucoseReadings,
            insulinOnBoard: state.expectedIOB ?? 0,
            carbsOnBoard: state.expectedCOB ?? 0,
            profile: state.profile,
            doseHistory: state.insulinDoses.isEmpty ? nil : state.insulinDoses,
            carbHistory: state.carbEntries.isEmpty ? nil : state.carbEntries
        )
    }
    
    public func compareInputs(_ cli: AlgorithmInputs, _ aid: AlgorithmInputs) -> AIDInputConformanceResult {
        AIDInputConformanceResult.compare(cli, aid)
    }
}

// MARK: - DeviceStateRecorder (ALG-INPUT-019b)

/// Captures current device state from CGM and pump providers.
/// 
/// Use this to record real device state for conformance testing
/// or to save scenarios for replay testing.
///
/// Example:
/// ```swift
/// let recorder = DeviceStateRecorder(
///     cgm: myCGMManager,
///     pump: myPumpManager,
///     settings: mySettingsStore
/// )
/// let state = try await recorder.captureState(scenario: "normal_day")
/// ```
public struct DeviceStateRecorder: Sendable {
    
    private let cgmProvider: any CGMDataProvider
    private let pumpProvider: any PumpDataProvider
    private let settingsProvider: any SettingsProvider
    
    /// Configuration for state capture
    public struct CaptureConfig: Sendable {
        /// Number of glucose readings to capture
        public let glucoseCount: Int
        
        /// Hours of dose history to capture
        public let doseHistoryHours: Int
        
        /// Hours of carb history to capture
        public let carbHistoryHours: Int
        
        public init(
            glucoseCount: Int = 24,     // ~2 hours at 5-min intervals
            doseHistoryHours: Int = 6,  // 6 hours of doses
            carbHistoryHours: Int = 6   // 6 hours of carbs
        ) {
            self.glucoseCount = glucoseCount
            self.doseHistoryHours = doseHistoryHours
            self.carbHistoryHours = carbHistoryHours
        }
        
        /// Default capture configuration
        public static let `default` = CaptureConfig()
        
        /// Extended capture for analysis (more data)
        public static let extended = CaptureConfig(
            glucoseCount: 288,       // 24 hours
            doseHistoryHours: 24,
            carbHistoryHours: 24
        )
        
        /// Minimal capture for quick tests
        public static let minimal = CaptureConfig(
            glucoseCount: 6,         // 30 minutes
            doseHistoryHours: 1,
            carbHistoryHours: 1
        )
    }
    
    /// Initialize with data providers
    /// - Parameters:
    ///   - cgm: Provider for CGM glucose data
    ///   - pump: Provider for insulin and carb history
    ///   - settings: Provider for therapy settings
    public init(
        cgm: any CGMDataProvider,
        pump: any PumpDataProvider,
        settings: any SettingsProvider
    ) {
        self.cgmProvider = cgm
        self.pumpProvider = pump
        self.settingsProvider = settings
    }
    
    /// Capture current device state into a RecordedDeviceState
    /// - Parameters:
    ///   - scenario: Description of the scenario (e.g., "post_meal_rise")
    ///   - config: Capture configuration (default: .default)
    /// - Returns: Recorded device state snapshot
    public func captureState(
        scenario: String = "captured",
        config: CaptureConfig = .default
    ) async throws -> RecordedDeviceState {
        // Capture all data concurrently
        async let glucoseTask = cgmProvider.glucoseHistory(count: config.glucoseCount)
        async let dosesTask = pumpProvider.doseHistory(hours: config.doseHistoryHours)
        async let carbsTask = pumpProvider.carbHistory(hours: config.carbHistoryHours)
        async let profileTask = settingsProvider.currentProfile()
        async let loopSettingsTask = settingsProvider.loopSettings()
        
        let (glucose, doses, carbs, profile, loopSettings) = try await (
            glucoseTask, dosesTask, carbsTask, profileTask, loopSettingsTask
        )
        
        return RecordedDeviceState(
            timestamp: Date(),
            scenario: scenario,
            glucoseReadings: glucose,
            insulinDoses: doses,
            carbEntries: carbs,
            profile: profile,
            loopSettings: loopSettings
        )
    }
    
    /// Capture state with pre-calculated IOB/COB values
    /// - Parameters:
    ///   - scenario: Description of the scenario
    ///   - iob: Pre-calculated insulin on board
    ///   - cob: Pre-calculated carbs on board
    ///   - config: Capture configuration
    /// - Returns: Recorded device state with expected values
    public func captureStateWithExpected(
        scenario: String = "captured",
        iob: Double,
        cob: Double,
        config: CaptureConfig = .default
    ) async throws -> RecordedDeviceState {
        let baseState = try await captureState(scenario: scenario, config: config)
        
        return RecordedDeviceState(
            id: baseState.id,
            timestamp: baseState.timestamp,
            scenario: baseState.scenario,
            glucoseReadings: baseState.glucoseReadings,
            insulinDoses: baseState.insulinDoses,
            carbEntries: baseState.carbEntries,
            profile: baseState.profile,
            loopSettings: baseState.loopSettings,
            basalSchedule: baseState.basalSchedule,
            expectedIOB: iob,
            expectedCOB: cob
        )
    }
}

/// Errors that can occur during state recording
public enum DeviceStateRecorderError: Error, Sendable {
    case cgmUnavailable(String)
    case pumpUnavailable(String)
    case settingsUnavailable(String)
    case noGlucoseData
}

// MARK: - Algorithm Output Conformance (ALG-INPUT-019k)

/// Represents algorithm recommendation output for conformance testing
public struct AlgorithmOutput: Sendable, Codable, Equatable {
    /// Suggested temp basal rate (U/hr), nil if no change
    public let tempBasalRate: Double?
    
    /// Suggested temp basal duration (seconds)
    public let tempBasalDuration: TimeInterval?
    
    /// Suggested bolus (U), nil if none
    public let suggestedBolus: Double?
    
    /// Predicted eventual BG (mg/dL)
    public let eventualBG: Double?
    
    /// Whether calculation succeeded
    public let success: Bool
    
    public init(
        tempBasalRate: Double? = nil,
        tempBasalDuration: TimeInterval? = nil,
        suggestedBolus: Double? = nil,
        eventualBG: Double? = nil,
        success: Bool = true
    ) {
        self.tempBasalRate = tempBasalRate
        self.tempBasalDuration = tempBasalDuration
        self.suggestedBolus = suggestedBolus
        self.eventualBG = eventualBG
        self.success = success
    }
}

/// Result of comparing algorithm outputs
public struct AlgorithmOutputConformanceResult: Sendable {
    public let tempBasalRateMatch: FieldComparisonResult
    public let tempBasalDurationMatch: FieldComparisonResult
    public let suggestedBolusMatch: FieldComparisonResult
    public let eventualBGMatch: FieldComparisonResult
    public let successMatch: FieldComparisonResult
    
    public var passed: Bool {
        tempBasalRateMatch.matches &&
        tempBasalDurationMatch.matches &&
        suggestedBolusMatch.matches &&
        eventualBGMatch.matches &&
        successMatch.matches
    }
    
    public init(
        tempBasalRateMatch: FieldComparisonResult,
        tempBasalDurationMatch: FieldComparisonResult,
        suggestedBolusMatch: FieldComparisonResult,
        eventualBGMatch: FieldComparisonResult,
        successMatch: FieldComparisonResult
    ) {
        self.tempBasalRateMatch = tempBasalRateMatch
        self.tempBasalDurationMatch = tempBasalDurationMatch
        self.suggestedBolusMatch = suggestedBolusMatch
        self.eventualBGMatch = eventualBGMatch
        self.successMatch = successMatch
    }
}

// MARK: - Output Comparison Helpers

public extension AlgorithmOutputConformanceResult {
    
    /// Compare two AlgorithmOutputs with tolerances
    static func compare(_ cli: AlgorithmOutput, _ aid: AlgorithmOutput) -> AlgorithmOutputConformanceResult {
        AlgorithmOutputConformanceResult(
            tempBasalRateMatch: compareOptionalDouble(cli.tempBasalRate, aid.tempBasalRate, 
                                                       tolerance: AIDInputConformanceTolerance.basalRate,
                                                       name: "tempBasalRate"),
            tempBasalDurationMatch: compareOptionalDouble(cli.tempBasalDuration, aid.tempBasalDuration,
                                                           tolerance: 60.0, // 60 second tolerance
                                                           name: "tempBasalDuration"),
            suggestedBolusMatch: compareOptionalDouble(cli.suggestedBolus, aid.suggestedBolus,
                                                        tolerance: AIDInputConformanceTolerance.iob,
                                                        name: "suggestedBolus"),
            eventualBGMatch: compareOptionalDouble(cli.eventualBG, aid.eventualBG,
                                                    tolerance: 1.0, // 1 mg/dL tolerance for predictions
                                                    name: "eventualBG"),
            successMatch: compareBool(cli.success, aid.success, name: "success")
        )
    }
    
    private static func compareOptionalDouble(_ cli: Double?, _ aid: Double?, tolerance: Double, name: String) -> FieldComparisonResult {
        switch (cli, aid) {
        case (nil, nil):
            return .match()
        case (let c?, nil):
            return .mismatch(reason: "\(name): AID missing", cli: String(format: "%.3f", c), aid: "nil")
        case (nil, let a?):
            return .mismatch(reason: "\(name): CLI missing", cli: "nil", aid: String(format: "%.3f", a))
        case (let c?, let a?):
            if abs(c - a) <= tolerance {
                return .match()
            }
            return .mismatch(reason: "\(name): delta=\(String(format: "%.3f", abs(c - a)))",
                            cli: String(format: "%.3f", c),
                            aid: String(format: "%.3f", a))
        }
    }
    
    private static func compareBool(_ cli: Bool, _ aid: Bool, name: String) -> FieldComparisonResult {
        if cli == aid {
            return .match()
        }
        return .mismatch(reason: "\(name) mismatch", cli: "\(cli)", aid: "\(aid)")
    }
}

// MARK: - RecordedStateDataSource (ALG-INPUT-019c)

/// AlgorithmDataSource adapter that replays data from a RecordedDeviceState.
///
/// This enables conformance testing by allowing recorded state to be passed
/// through the same paths as live data sources (CLI/Nightscout or AID/Direct).
///
/// Usage:
/// ```swift
/// let recordedState = // ... loaded from fixture
/// let dataSource = RecordedStateDataSource(state: recordedState)
/// let assembler = AlgorithmInputAssembler(dataSource: dataSource)
/// let inputs = try await assembler.assembleInputs(at: recordedState.timestamp)
/// ```
public struct RecordedStateDataSource: AlgorithmDataSource, Sendable {
    
    /// The recorded state to replay
    public let state: RecordedDeviceState
    
    /// Create a data source from a recorded state
    /// - Parameter state: The recorded device state to replay
    public init(state: RecordedDeviceState) {
        self.state = state
    }
    
    // MARK: - AlgorithmDataSource Protocol
    
    public func glucoseHistory(count: Int) async throws -> [GlucoseReading] {
        // Return up to `count` readings, sorted newest first
        let sorted = state.glucoseReadings.sorted { $0.timestamp > $1.timestamp }
        return Array(sorted.prefix(count))
    }
    
    public func doseHistory(hours: Int) async throws -> [InsulinDose] {
        // Filter to doses within the requested time window
        let cutoff = state.timestamp.addingTimeInterval(-Double(hours) * 3600)
        return state.insulinDoses.filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func carbHistory(hours: Int) async throws -> [CarbEntry] {
        // Filter to carbs within the requested time window
        let cutoff = state.timestamp.addingTimeInterval(-Double(hours) * 3600)
        return state.carbEntries.filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func currentProfile() async throws -> TherapyProfile {
        return state.profile
    }
    
    public func loopSettings() async throws -> LoopSettings? {
        return state.loopSettings
    }
}

// MARK: - RecordedStateDataSource Extensions

public extension RecordedStateDataSource {
    
    /// Get all glucose readings without count limit
    var allGlucoseReadings: [GlucoseReading] {
        state.glucoseReadings.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Get all dose history without time limit
    var allDoses: [InsulinDose] {
        state.insulinDoses.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Get all carb entries without time limit
    var allCarbs: [CarbEntry] {
        state.carbEntries.sorted { $0.timestamp > $1.timestamp }
    }
    
    /// The reference timestamp for this recorded state
    var referenceTime: Date {
        state.timestamp
    }
    
    /// Expected IOB value from recording (if available)
    var expectedIOB: Double? {
        state.expectedIOB
    }
    
    /// Expected COB value from recording (if available)
    var expectedCOB: Double? {
        state.expectedCOB
    }
    
    /// Get basal schedule if recorded
    var basalSchedule: [ScheduledBasalRate]? {
        state.basalSchedule
    }
}

// MARK: - RecordedState Providers (ALG-INPUT-019d)

/// CGM data provider that replays data from a RecordedDeviceState.
///
/// Implements CGMDataProvider for use with DirectDataSource.
public final class RecordedStateCGMProvider: CGMDataProvider, @unchecked Sendable {
    
    private let state: RecordedDeviceState
    private let sortedReadings: [GlucoseReading]
    
    /// Create a provider from a recorded state
    public init(state: RecordedDeviceState) {
        self.state = state
        self.sortedReadings = state.glucoseReadings.sorted { $0.timestamp > $1.timestamp }
    }
    
    public var latestGlucose: GlucoseReading? {
        get async { sortedReadings.first }
    }
    
    public func glucoseHistory(count: Int) async throws -> [GlucoseReading] {
        Array(sortedReadings.prefix(count))
    }
}

/// Pump data provider that replays data from a RecordedDeviceState.
///
/// Implements PumpDataProvider for use with DirectDataSource.
public final class RecordedStatePumpProvider: PumpDataProvider, @unchecked Sendable {
    
    private let state: RecordedDeviceState
    
    /// Create a provider from a recorded state
    public init(state: RecordedDeviceState) {
        self.state = state
    }
    
    public var reservoirLevel: Double? {
        get async { nil } // Not recorded in state
    }
    
    public func doseHistory(hours: Int) async throws -> [InsulinDose] {
        let cutoff = state.timestamp.addingTimeInterval(-Double(hours) * 3600)
        return state.insulinDoses
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    public func carbHistory(hours: Int) async throws -> [CarbEntry] {
        let cutoff = state.timestamp.addingTimeInterval(-Double(hours) * 3600)
        return state.carbEntries
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }
}

/// Settings provider that replays data from a RecordedDeviceState.
///
/// Implements SettingsProvider for use with DirectDataSource.
public final class RecordedStateSettingsProvider: SettingsProvider, @unchecked Sendable {
    
    private let state: RecordedDeviceState
    
    /// Create a provider from a recorded state
    public init(state: RecordedDeviceState) {
        self.state = state
    }
    
    public func currentProfile() async throws -> TherapyProfile {
        state.profile
    }
    
    public func loopSettings() async throws -> LoopSettings? {
        state.loopSettings
    }
}

// MARK: - RecordedStateDirectDataSource

/// Convenience wrapper that creates a DirectDataSource from RecordedDeviceState.
///
/// This provides the AID path equivalent of RecordedStateDataSource (CLI path).
/// Both adapters allow the same recorded state to be processed through different
/// paths for conformance testing.
///
/// Usage:
/// ```swift
/// let state = // ... recorded or loaded state
/// let directSource = RecordedStateDirectDataSource(state: state)
/// let inputs = try await assembler.assembleInputs(using: directSource.dataSource)
/// ```
public struct RecordedStateDirectDataSource: Sendable {
    
    /// The underlying DirectDataSource
    public let dataSource: DirectDataSource
    
    /// The original recorded state
    public let state: RecordedDeviceState
    
    /// The CGM provider wrapping the recorded state
    public let cgmProvider: RecordedStateCGMProvider
    
    /// The pump provider wrapping the recorded state
    public let pumpProvider: RecordedStatePumpProvider
    
    /// The settings provider wrapping the recorded state
    public let settingsProvider: RecordedStateSettingsProvider
    
    /// Create a DirectDataSource from a recorded state
    public init(state: RecordedDeviceState) {
        self.state = state
        self.cgmProvider = RecordedStateCGMProvider(state: state)
        self.pumpProvider = RecordedStatePumpProvider(state: state)
        self.settingsProvider = RecordedStateSettingsProvider(state: state)
        self.dataSource = DirectDataSource(
            cgm: cgmProvider,
            pump: pumpProvider,
            settings: settingsProvider
        )
    }
}

// MARK: - RecordedStateDirectDataSource Extensions

public extension RecordedStateDirectDataSource {
    
    /// Expected IOB from the recorded state (if available)
    var expectedIOB: Double? {
        state.expectedIOB
    }
    
    /// Expected COB from the recorded state (if available)
    var expectedCOB: Double? {
        state.expectedCOB
    }
    
    /// Reference timestamp from the recorded state
    var referenceTime: Date {
        state.timestamp
    }
    
    /// Scenario name from the recorded state
    var scenario: String {
        state.scenario
    }
}
