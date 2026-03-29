/// Data freshness tracking with configurable thresholds
/// Pattern: Loop/LoopKit staleness monitoring
///
/// Provides generalized freshness tracking for glucose, insulin, and other data types.
/// Integrates with DeviceStatusElementState for UI status representation.

import Foundation

// MARK: - DataFreshness

/// Generalized data freshness tracking with configurable thresholds.
///
/// Used to determine if data is fresh, stale, or expired based on age.
/// Supports different thresholds for different data types (glucose, insulin, pump).
///
/// ## Standard Thresholds (from Loop/Trio)
/// - **Glucose**: Fresh ≤5 min, Stale ≤12 min, Expired >12 min (algorithm skips)
/// - **Insulin/IOB**: Fresh ≤6 hours (DIA), then IOB→0
/// - **Loop Completion**: Fresh ≤6 min, Aging ≤16 min, Stale >16 min
public struct DataFreshness: Sendable, Equatable, Codable {
    
    /// Timestamp of the last data point
    public let lastDataDate: Date?
    
    /// Timestamp when freshness was checked
    public let checkDate: Date
    
    /// Threshold configuration for this data type
    public let thresholds: Thresholds
    
    /// Initialize with data timestamp and optional custom thresholds
    public init(
        lastDataDate: Date?,
        checkDate: Date = Date(),
        thresholds: Thresholds = .glucose
    ) {
        self.lastDataDate = lastDataDate
        self.checkDate = checkDate
        self.thresholds = thresholds
    }
    
    // MARK: - Age Calculation
    
    /// Age of the data in seconds (nil if no data)
    public var ageSeconds: TimeInterval? {
        guard let lastDataDate else { return nil }
        return checkDate.timeIntervalSince(lastDataDate)
    }
    
    /// Age of the data as a Duration (nil if no data)
    @available(iOS 16.0, macOS 13.0, *)
    public var age: Duration? {
        guard let ageSeconds else { return nil }
        return .seconds(ageSeconds)
    }
    
    // MARK: - Freshness State
    
    /// Whether data is fresh (within fresh threshold)
    public var isFresh: Bool {
        guard let age = ageSeconds else { return false }
        return age <= thresholds.freshSeconds
    }
    
    /// Whether data is stale but usable (between fresh and expired)
    public var isStale: Bool {
        guard let age = ageSeconds else { return false }
        return age > thresholds.freshSeconds && age <= thresholds.expiredSeconds
    }
    
    /// Whether data is too old to use (exceeds expired threshold)
    public var isExpired: Bool {
        guard let age = ageSeconds else { return true }
        return age > thresholds.expiredSeconds
    }
    
    /// Whether any data exists
    public var hasData: Bool {
        lastDataDate != nil
    }
    
    /// Freshness level for display
    public var level: Level {
        if !hasData { return .noData }
        if isFresh { return .fresh }
        if isStale { return .stale }
        return .expired
    }
    
    /// Convert to DeviceStatusElementState for UI rendering
    public func toElementState(deviceType: DeviceType = .cgm) -> DeviceStatusElementState {
        switch level {
        case .fresh:
            return deviceType == .cgm ? .normalCGM : .normalPump
        case .stale:
            return .warning
        case .expired, .noData:
            return .critical
        }
    }
    
    // MARK: - Nested Types
    
    /// Device type for determining normal state variant
    public enum DeviceType: String, Sendable, Codable {
        case cgm
        case pump
    }
    
    /// Freshness level enumeration
    public enum Level: String, Sendable, Codable, CaseIterable {
        case fresh      // Data within fresh threshold
        case stale      // Data between fresh and expired thresholds
        case expired    // Data exceeds expired threshold
        case noData     // No data available
        
        /// SF Symbol name for this level
        public var symbolName: String {
            switch self {
            case .fresh: return "checkmark.circle.fill"
            case .stale: return "exclamationmark.triangle.fill"
            case .expired: return "xmark.circle.fill"
            case .noData: return "questionmark.circle.fill"
            }
        }
        
        /// Whether this level represents usable data
        public var isUsable: Bool {
            switch self {
            case .fresh, .stale:
                return true
            case .expired, .noData:
                return false
            }
        }
        
        /// Whether this level requires user attention
        public var needsAttention: Bool {
            switch self {
            case .fresh:
                return false
            case .stale, .expired, .noData:
                return true
            }
        }
    }
}

// MARK: - Thresholds

extension DataFreshness {
    /// Configurable thresholds for data freshness
    public struct Thresholds: Sendable, Equatable, Codable {
        /// Maximum age in seconds for data to be considered fresh
        public let freshSeconds: TimeInterval
        
        /// Maximum age in seconds for data to be usable (beyond this is expired)
        public let expiredSeconds: TimeInterval
        
        /// Human-readable name for this threshold configuration
        public let name: String
        
        public init(freshSeconds: TimeInterval, expiredSeconds: TimeInterval, name: String = "custom") {
            self.freshSeconds = freshSeconds
            self.expiredSeconds = expiredSeconds
            self.name = name
        }
        
        // MARK: - Standard Configurations
        
        /// Glucose data thresholds: 5 min fresh, 12 min expired (algorithm skips)
        /// Based on Loop/Trio behavior
        public static let glucose = Thresholds(
            freshSeconds: 300,      // 5 minutes
            expiredSeconds: 720,    // 12 minutes
            name: "glucose"
        )
        
        /// Glucose data thresholds: 5 min fresh, 15 min expired (UI display)
        /// More lenient for display purposes
        public static let glucoseDisplay = Thresholds(
            freshSeconds: 300,      // 5 minutes
            expiredSeconds: 900,    // 15 minutes
            name: "glucoseDisplay"
        )
        
        /// Insulin/IOB thresholds: 6 hours (standard DIA)
        /// IOB becomes 0 when all doses are older than DIA
        public static let insulin = Thresholds(
            freshSeconds: 3600,     // 1 hour (recent activity)
            expiredSeconds: 21600,  // 6 hours (DIA)
            name: "insulin"
        )
        
        /// Pump communication thresholds: 5 min fresh, 30 min expired
        public static let pump = Thresholds(
            freshSeconds: 300,      // 5 minutes
            expiredSeconds: 1800,   // 30 minutes
            name: "pump"
        )
        
        /// Loop completion thresholds: 6 min fresh, 16 min expired
        /// Based on LoopCompletionFreshness from Loop
        public static let loopCompletion = Thresholds(
            freshSeconds: 360,      // 6 minutes
            expiredSeconds: 960,    // 16 minutes
            name: "loopCompletion"
        )
        
        /// Sensor session thresholds (for 10-day sensors)
        public static let sensorSession = Thresholds(
            freshSeconds: 604800,   // 7 days (week 1)
            expiredSeconds: 864000, // 10 days (session end)
            name: "sensorSession"
        )
        
        /// Create custom thresholds from Duration values (iOS 16+)
        @available(iOS 16.0, macOS 13.0, *)
        public static func custom(fresh: Duration, expired: Duration, name: String = "custom") -> Thresholds {
            Thresholds(
                freshSeconds: Double(fresh.components.seconds) + Double(fresh.components.attoseconds) / 1e18,
                expiredSeconds: Double(expired.components.seconds) + Double(expired.components.attoseconds) / 1e18,
                name: name
            )
        }
    }
}

// MARK: - Convenience Initializers

extension DataFreshness {
    /// Create glucose freshness (5/12 min thresholds)
    public static func glucose(lastReading: Date?, checkDate: Date = Date()) -> DataFreshness {
        DataFreshness(lastDataDate: lastReading, checkDate: checkDate, thresholds: .glucose)
    }
    
    /// Create insulin freshness (6h DIA threshold)
    public static func insulin(lastDose: Date?, checkDate: Date = Date()) -> DataFreshness {
        DataFreshness(lastDataDate: lastDose, checkDate: checkDate, thresholds: .insulin)
    }
    
    /// Create pump communication freshness
    public static func pump(lastCommunication: Date?, checkDate: Date = Date()) -> DataFreshness {
        DataFreshness(lastDataDate: lastCommunication, checkDate: checkDate, thresholds: .pump)
    }
    
    /// Create loop completion freshness
    public static func loopCompletion(lastCompletion: Date?, checkDate: Date = Date()) -> DataFreshness {
        DataFreshness(lastDataDate: lastCompletion, checkDate: checkDate, thresholds: .loopCompletion)
    }
}

// MARK: - Debug Description

extension DataFreshness: CustomStringConvertible {
    public var description: String {
        guard let age = ageSeconds else {
            return "DataFreshness(\(thresholds.name): noData)"
        }
        let ageStr = age < 60 ? "\(Int(age))s" : "\(Int(age / 60))m"
        return "DataFreshness(\(thresholds.name): \(level.rawValue), age=\(ageStr))"
    }
}

// MARK: - InsulinFreshness

/// Specialized freshness tracking for insulin/IOB with DIA awareness.
///
/// Tracks when insulin data becomes stale based on Duration of Insulin Action (DIA).
/// When all doses are older than DIA, IOB is effectively 0.
public struct InsulinFreshness: Sendable, Equatable, Codable {
    /// Duration of Insulin Action in seconds (default 6 hours)
    public let diaSeconds: TimeInterval
    
    /// Timestamp of the most recent insulin dose
    public let lastDoseDate: Date?
    
    /// Timestamp when freshness was checked
    public let checkDate: Date
    
    /// Initialize with dose timestamp and DIA
    public init(
        lastDoseDate: Date?,
        diaSeconds: TimeInterval = 21600, // 6 hours default
        checkDate: Date = Date()
    ) {
        self.lastDoseDate = lastDoseDate
        self.diaSeconds = diaSeconds
        self.checkDate = checkDate
    }
    
    /// Age of the most recent dose in seconds
    public var doseAgeSeconds: TimeInterval? {
        guard let lastDoseDate else { return nil }
        return checkDate.timeIntervalSince(lastDoseDate)
    }
    
    /// Whether insulin data is active (last dose within DIA)
    public var isActive: Bool {
        guard let age = doseAgeSeconds else { return false }
        return age <= diaSeconds
    }
    
    /// Whether IOB should be considered zero (all doses older than DIA)
    public var iobIsZero: Bool {
        !isActive
    }
    
    /// Percentage of DIA elapsed since last dose (0-100+)
    public var diaElapsedPercent: Double {
        guard let age = doseAgeSeconds else { return 100 }
        return min(100, (age / diaSeconds) * 100)
    }
    
    /// Convert to DeviceStatusElementState
    public var elementState: DeviceStatusElementState {
        if isActive {
            return .normalPump
        }
        return .warning
    }
    
    /// Convert to general DataFreshness
    public var asDataFreshness: DataFreshness {
        DataFreshness(
            lastDataDate: lastDoseDate,
            checkDate: checkDate,
            thresholds: .insulin
        )
    }
}

// MARK: - InsulinFreshness Convenience

extension InsulinFreshness {
    /// Standard DIA values
    public enum StandardDIA: TimeInterval, Sendable {
        case rapid = 14400      // 4 hours (Fiasp, Lyumjev)
        case standard = 18000   // 5 hours (Novolog, Humalog)
        case extended = 21600   // 6 hours (default, conservative)
        case ultraLong = 28800  // 8 hours (some pumpers)
    }
    
    /// Initialize with standard DIA preset
    public init(lastDoseDate: Date?, dia: StandardDIA, checkDate: Date = Date()) {
        self.init(lastDoseDate: lastDoseDate, diaSeconds: dia.rawValue, checkDate: checkDate)
    }
}
