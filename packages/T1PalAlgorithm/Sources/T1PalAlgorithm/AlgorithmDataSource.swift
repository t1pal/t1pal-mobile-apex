// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmDataSource.swift
// T1Pal Mobile
//
// Protocol for algorithm data sources (Nightscout, Mock, Direct CGM/Pump)
// Requirements: ALG-INPUT-007

import Foundation
import T1PalCore

// MARK: - AlgorithmDataSource Protocol

/// Protocol for providing algorithm input data from various sources.
///
/// Implementations:
/// - `NightscoutDataSource`: Fetches from Nightscout API
/// - `MockDataSource`: Returns test/demo data
/// - `DirectDataSource`: Reads from connected CGM/pump (AID app)
///
/// Usage:
/// ```swift
/// let assembler = AlgorithmInputAssembler(dataSource: nightscoutSource)
/// let inputs = try await assembler.assembleInputs(at: Date())
/// let result = algorithm.calculate(inputs)
/// ```
public protocol AlgorithmDataSource: Sendable {
    
    /// Fetch recent glucose readings.
    /// - Parameter count: Number of readings to fetch (most recent first)
    /// - Returns: Array of glucose readings, ordered newest to oldest
    func glucoseHistory(count: Int) async throws -> [GlucoseReading]
    
    /// Fetch dose history (boluses and temp basals).
    /// - Parameter hours: How far back to fetch
    /// - Returns: Array of insulin doses within the time window
    func doseHistory(hours: Int) async throws -> [InsulinDose]
    
    /// Fetch carb entry history.
    /// - Parameter hours: How far back to fetch
    /// - Returns: Array of carb entries within the time window
    func carbHistory(hours: Int) async throws -> [CarbEntry]
    
    /// Fetch the current therapy profile (ISF, CR, basal, targets).
    /// - Returns: The active therapy profile
    func currentProfile() async throws -> TherapyProfile
    
    /// Fetch Loop-specific settings (if available).
    /// - Returns: Loop settings or nil for non-Loop users
    func loopSettings() async throws -> LoopSettings?
}

// MARK: - LoopSettings

/// Loop-specific algorithm settings.
/// Mirrors NightscoutKit.LoopSettings for use without NS dependency.
public struct LoopSettings: Codable, Sendable {
    public let maximumBasalRatePerHour: Double?
    public let maximumBolus: Double?
    public let minimumBGGuard: Double?
    public let dosingStrategy: String?
    public let dosingEnabled: Bool?
    public let preMealTargetRange: [Double]?
    
    public init(
        maximumBasalRatePerHour: Double? = nil,
        maximumBolus: Double? = nil,
        minimumBGGuard: Double? = nil,
        dosingStrategy: String? = nil,
        dosingEnabled: Bool? = nil,
        preMealTargetRange: [Double]? = nil
    ) {
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
        self.minimumBGGuard = minimumBGGuard
        self.dosingStrategy = dosingStrategy
        self.dosingEnabled = dosingEnabled
        self.preMealTargetRange = preMealTargetRange
    }
}

// MARK: - Data Source Errors

/// Errors that can occur when fetching algorithm data.
public enum AlgorithmDataSourceError: Error, LocalizedError {
    case noGlucoseData
    case insufficientGlucoseData(required: Int, available: Int)
    case profileNotAvailable
    case connectionFailed(underlying: Error)
    case timeout
    case invalidResponse
    
    public var errorDescription: String? {
        switch self {
        case .noGlucoseData:
            return "No glucose data available"
        case .insufficientGlucoseData(let required, let available):
            return "Insufficient glucose data: need \(required), have \(available)"
        case .profileNotAvailable:
            return "Therapy profile not available"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .timeout:
            return "Data source request timed out"
        case .invalidResponse:
            return "Invalid response from data source"
        }
    }
}

// MARK: - Default Fetch Parameters

/// Standard parameters for algorithm data fetching.
public enum AlgorithmDataDefaults {
    /// Default glucose count for prediction (3 hours at 5-min intervals)
    public static let glucoseCount = 36
    
    /// Hours of dose history needed for accurate IOB
    public static let doseHistoryHours = 6
    
    /// Hours of carb history needed for accurate COB
    public static let carbHistoryHours = 6
    
    /// Minimum glucose readings required for algorithm
    public static let minimumGlucoseCount = 3
}

// MARK: - Provider Protocols (ALG-INPUT-010a/b/c)

/// Protocol for providing glucose data from a CGM manager.
/// Requirements: ALG-INPUT-010a
///
/// Implementations:
/// - CGMManager conformers (DexcomG6Manager, LibreManager, etc.)
/// - MockCGMDataProvider for testing
public protocol CGMDataProvider: Sendable {
    /// Fetch recent glucose readings from the CGM.
    /// - Parameter count: Number of readings to fetch (most recent first)
    /// - Returns: Array of glucose readings, ordered newest to oldest
    func glucoseHistory(count: Int) async throws -> [GlucoseReading]
    
    /// The current glucose reading, if available.
    var latestGlucose: GlucoseReading? { get async }
}

/// Protocol for providing insulin dose data from a pump manager.
/// Requirements: ALG-INPUT-010b
///
/// Implementations:
/// - PumpManager conformers (DanaPumpManager, OmnipodManager, etc.)
/// - MockPumpDataProvider for testing
public protocol PumpDataProvider: Sendable {
    /// Fetch dose history (boluses and temp basals).
    /// - Parameter hours: How far back to fetch
    /// - Returns: Array of insulin doses within the time window
    func doseHistory(hours: Int) async throws -> [InsulinDose]
    
    /// Fetch carb entry history.
    /// - Parameter hours: How far back to fetch
    /// - Returns: Array of carb entries within the time window
    func carbHistory(hours: Int) async throws -> [CarbEntry]
    
    /// The current reservoir level in units, if available.
    var reservoirLevel: Double? { get async }
}

/// Protocol for providing therapy settings from local storage.
/// Requirements: ALG-INPUT-010c
///
/// Implementations:
/// - SettingsStore (local app settings)
/// - MockSettingsProvider for testing
public protocol SettingsProvider: Sendable {
    /// Fetch the current therapy profile (ISF, CR, basal, targets).
    /// - Returns: The active therapy profile
    func currentProfile() async throws -> TherapyProfile
    
    /// Fetch Loop-specific settings (if available).
    /// - Returns: Loop settings or nil for non-Loop users
    func loopSettings() async throws -> LoopSettings?
}

// MARK: - DirectDataSource (ALG-INPUT-010d)

/// Data source that reads directly from connected CGM/pump managers.
/// Requirements: ALG-INPUT-010d
///
/// This is the primary data source for AID apps with direct device connections.
/// Unlike NightscoutDataSource which polls a server, DirectDataSource reads
/// from local managers that maintain real-time device state.
///
/// Usage:
/// ```swift
/// let cgm = DexcomG6Manager()
/// let pump = DanaPumpManager()
/// let settings = SettingsStore.shared
/// let source = DirectDataSource(cgm: cgm, pump: pump, settings: settings)
/// let inputs = try await assembler.assembleInputs(using: source)
/// ```
public final class DirectDataSource: AlgorithmDataSource, @unchecked Sendable {
    
    private let cgmProvider: CGMDataProvider
    private let pumpProvider: PumpDataProvider
    private let settingsProvider: SettingsProvider
    
    /// Create a DirectDataSource from provider implementations.
    /// - Parameters:
    ///   - cgm: Provider for glucose data
    ///   - pump: Provider for dose/carb data
    ///   - settings: Provider for therapy profile and loop settings
    public init(
        cgm: CGMDataProvider,
        pump: PumpDataProvider,
        settings: SettingsProvider
    ) {
        self.cgmProvider = cgm
        self.pumpProvider = pump
        self.settingsProvider = settings
    }
    
    // MARK: - AlgorithmDataSource Protocol
    
    public func glucoseHistory(count: Int) async throws -> [GlucoseReading] {
        try await cgmProvider.glucoseHistory(count: count)
    }
    
    public func doseHistory(hours: Int) async throws -> [InsulinDose] {
        try await pumpProvider.doseHistory(hours: hours)
    }
    
    public func carbHistory(hours: Int) async throws -> [CarbEntry] {
        try await pumpProvider.carbHistory(hours: hours)
    }
    
    public func currentProfile() async throws -> TherapyProfile {
        try await settingsProvider.currentProfile()
    }
    
    public func loopSettings() async throws -> LoopSettings? {
        try await settingsProvider.loopSettings()
    }
}

// MARK: - Mock Providers (ALG-INPUT-010e/f)

/// Mock CGM data provider for testing without hardware.
/// Requirements: ALG-INPUT-010e
public final class MockCGMDataProvider: CGMDataProvider, @unchecked Sendable {
    
    /// Glucose values to return (newest first)
    public var glucoseValues: [GlucoseReading]
    
    /// Latest glucose (first element of glucoseValues)
    public var latestGlucose: GlucoseReading? {
        get async { glucoseValues.first }
    }
    
    /// Create with predefined glucose readings.
    public init(glucoseValues: [GlucoseReading] = []) {
        self.glucoseValues = glucoseValues
    }
    
    /// Create with a stable glucose value.
    public static func stable(glucose: Double, count: Int = 36) -> MockCGMDataProvider {
        let readings = (0..<count).map { i in
            GlucoseReading(
                glucose: glucose,
                timestamp: Date().addingTimeInterval(TimeInterval(-i * 5 * 60)),
                trend: .flat
            )
        }
        return MockCGMDataProvider(glucoseValues: readings)
    }
    
    public func glucoseHistory(count: Int) async throws -> [GlucoseReading] {
        Array(glucoseValues.prefix(count))
    }
}

/// Mock pump data provider for testing without hardware.
/// Requirements: ALG-INPUT-010f
public final class MockPumpDataProvider: PumpDataProvider, @unchecked Sendable {
    
    /// Dose values to return
    public var doses: [InsulinDose]
    
    /// Carb entries to return
    public var carbs: [CarbEntry]
    
    /// Reservoir level in units
    public var reservoirLevel: Double? {
        get async { _reservoirLevel }
    }
    private var _reservoirLevel: Double?
    
    /// Create with predefined data.
    public init(
        doses: [InsulinDose] = [],
        carbs: [CarbEntry] = [],
        reservoirLevel: Double? = 100.0
    ) {
        self.doses = doses
        self.carbs = carbs
        self._reservoirLevel = reservoirLevel
    }
    
    /// Create an empty provider (no IOB/COB).
    public static func empty() -> MockPumpDataProvider {
        MockPumpDataProvider()
    }
    
    /// Create with a recent bolus.
    public static func withBolus(units: Double, minutesAgo: Int = 30) -> MockPumpDataProvider {
        let dose = InsulinDose(
            units: units,
            timestamp: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)),
            type: .novolog,
            source: "mock"
        )
        return MockPumpDataProvider(doses: [dose])
    }
    
    public func doseHistory(hours: Int) async throws -> [InsulinDose] {
        let cutoff = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        return doses.filter { $0.timestamp >= cutoff }
    }
    
    public func carbHistory(hours: Int) async throws -> [CarbEntry] {
        let cutoff = Date().addingTimeInterval(TimeInterval(-hours * 3600))
        return carbs.filter { $0.timestamp >= cutoff }
    }
}

/// Mock settings provider for testing.
public final class MockSettingsProvider: SettingsProvider, @unchecked Sendable {
    
    /// Profile to return
    public var profile: TherapyProfile
    
    /// Loop settings to return
    public var settings: LoopSettings?
    
    /// Create with default profile.
    public init(
        profile: TherapyProfile = .default,
        settings: LoopSettings? = nil
    ) {
        self.profile = profile
        self.settings = settings
    }
    
    public func currentProfile() async throws -> TherapyProfile {
        profile
    }
    
    public func loopSettings() async throws -> LoopSettings? {
        settings
    }
}
