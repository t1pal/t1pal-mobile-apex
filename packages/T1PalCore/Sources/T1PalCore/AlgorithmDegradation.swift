/// Algorithm graceful degradation for CGM-only and pump-disconnected modes
/// AID-PARTIAL-005: Run if CGM exists, show limited predictions
///
/// When pump/insulin data is unavailable, the algorithm can still provide:
/// - Glucose display (always available with CGM)
/// - Trend arrows (from CGM data)
/// - Limited predictions (glucose-only, no insulin effect)
/// - Nightscout sync (CGM data)
///
/// What's unavailable without insulin data:
/// - IOB calculations (show as 0 or "stale")
/// - Full prediction curves (require insulin model)
/// - Dosing recommendations (require IOB)
/// - Temp basal/SMB enactments (require pump)
///
/// ## Usage
/// ```swift
/// let degradation = AlgorithmDegradation.evaluate(
///     loopMode: .cgmOnly,
///     cgmConnected: true,
///     pumpConnected: false,
///     insulinFreshness: nil
/// )
///
/// if degradation.canShowPredictions {
///     showLimitedPredictions()
/// } else {
///     hidePredictionCurve()
/// }
/// ```

import Foundation

// MARK: - AlgorithmDegradation

/// Represents the degradation level of algorithm output
public struct AlgorithmDegradation: Sendable, Equatable, Codable {
    
    /// Current degradation level
    public let level: DegradationLevel
    
    /// What capabilities are available
    public let capabilities: Capabilities
    
    /// Reason for degradation (if any)
    public let reason: DegradationReason?
    
    /// When degradation was evaluated
    public let evaluatedAt: Date
    
    /// Initialize
    public init(
        level: DegradationLevel,
        capabilities: Capabilities,
        reason: DegradationReason? = nil,
        evaluatedAt: Date = Date()
    ) {
        self.level = level
        self.capabilities = capabilities
        self.reason = reason
        self.evaluatedAt = evaluatedAt
    }
    
    // MARK: - Degradation Level
    
    /// Level of algorithm degradation
    public enum DegradationLevel: String, Sendable, Codable, CaseIterable {
        /// Full functionality - all data available
        case full
        
        /// Limited predictions - CGM available but insulin data stale
        case limitedPredictions
        
        /// CGM only - no insulin/pump data at all
        case cgmOnly
        
        /// Offline - no data available
        case offline
        
        /// Human-readable description
        public var localizedDescription: String {
            switch self {
            case .full:
                return "Full algorithm"
            case .limitedPredictions:
                return "Limited predictions"
            case .cgmOnly:
                return "CGM only"
            case .offline:
                return "Offline"
            }
        }
        
        /// Whether any data is available
        public var hasData: Bool {
            self != .offline
        }
        
        /// Whether predictions are available (even limited)
        public var hasPredictions: Bool {
            switch self {
            case .full:
                return true
            case .limitedPredictions, .cgmOnly, .offline:
                return false
            }
        }
    }
    
    // MARK: - Degradation Reason
    
    /// Why the algorithm is degraded
    public enum DegradationReason: String, Sendable, Codable {
        /// User selected CGM-only mode
        case userSelectedCGMOnly
        
        /// Pump disconnected
        case pumpDisconnected
        
        /// Insulin data stale (>6h)
        case insulinDataStale
        
        /// CGM disconnected
        case cgmDisconnected
        
        /// No configuration available
        case noConfiguration
        
        /// Human-readable description
        public var localizedDescription: String {
            switch self {
            case .userSelectedCGMOnly:
                return "CGM-only mode selected"
            case .pumpDisconnected:
                return "Pump disconnected"
            case .insulinDataStale:
                return "Insulin data is stale"
            case .cgmDisconnected:
                return "CGM disconnected"
            case .noConfiguration:
                return "Configuration unavailable"
            }
        }
        
        /// SF Symbol for this reason
        public var symbolName: String {
            switch self {
            case .userSelectedCGMOnly:
                return "drop.fill"
            case .pumpDisconnected:
                return "cross.circle"
            case .insulinDataStale:
                return "clock.badge.exclamationmark"
            case .cgmDisconnected:
                return "drop.triangle"
            case .noConfiguration:
                return "gearshape"
            }
        }
    }
    
    // MARK: - Capabilities
    
    /// What capabilities are available at this degradation level
    public struct Capabilities: Sendable, Equatable, Codable {
        
        /// Can display glucose value
        public let canShowGlucose: Bool
        
        /// Can show trend arrows
        public let canShowTrend: Bool
        
        /// Can show IOB (may be 0 if stale)
        public let canShowIOB: Bool
        
        /// Can show full prediction curve
        public let canShowPredictions: Bool
        
        /// Can show limited predictions (glucose-only momentum)
        public let canShowLimitedPredictions: Bool
        
        /// Can enact temp basals
        public let canEnactTempBasal: Bool
        
        /// Can deliver SMB
        public let canDeliverSMB: Bool
        
        /// Can upload to Nightscout
        public let canUploadToNightscout: Bool
        
        /// Initialize with explicit values
        public init(
            canShowGlucose: Bool,
            canShowTrend: Bool,
            canShowIOB: Bool,
            canShowPredictions: Bool,
            canShowLimitedPredictions: Bool,
            canEnactTempBasal: Bool,
            canDeliverSMB: Bool,
            canUploadToNightscout: Bool
        ) {
            self.canShowGlucose = canShowGlucose
            self.canShowTrend = canShowTrend
            self.canShowIOB = canShowIOB
            self.canShowPredictions = canShowPredictions
            self.canShowLimitedPredictions = canShowLimitedPredictions
            self.canEnactTempBasal = canEnactTempBasal
            self.canDeliverSMB = canDeliverSMB
            self.canUploadToNightscout = canUploadToNightscout
        }
        
        // MARK: - Presets
        
        /// Full capabilities
        public static let full = Capabilities(
            canShowGlucose: true,
            canShowTrend: true,
            canShowIOB: true,
            canShowPredictions: true,
            canShowLimitedPredictions: true,
            canEnactTempBasal: true,
            canDeliverSMB: true,
            canUploadToNightscout: true
        )
        
        /// Limited predictions (CGM + stale insulin)
        public static let limitedPredictions = Capabilities(
            canShowGlucose: true,
            canShowTrend: true,
            canShowIOB: false,      // IOB stale, show 0
            canShowPredictions: false,
            canShowLimitedPredictions: true,  // Momentum only
            canEnactTempBasal: false,
            canDeliverSMB: false,
            canUploadToNightscout: true
        )
        
        /// CGM only (no pump/insulin data)
        public static let cgmOnly = Capabilities(
            canShowGlucose: true,
            canShowTrend: true,
            canShowIOB: false,
            canShowPredictions: false,
            canShowLimitedPredictions: false,
            canEnactTempBasal: false,
            canDeliverSMB: false,
            canUploadToNightscout: true  // CGM always uploads
        )
        
        /// Offline (nothing available)
        public static let offline = Capabilities(
            canShowGlucose: false,
            canShowTrend: false,
            canShowIOB: false,
            canShowPredictions: false,
            canShowLimitedPredictions: false,
            canEnactTempBasal: false,
            canDeliverSMB: false,
            canUploadToNightscout: false
        )
    }
    
    // MARK: - Convenience Properties
    
    /// Whether glucose display is available
    public var canShowGlucose: Bool { capabilities.canShowGlucose }
    
    /// Whether any predictions are available
    public var canShowPredictions: Bool { capabilities.canShowPredictions }
    
    /// Whether limited predictions are available
    public var canShowLimitedPredictions: Bool { capabilities.canShowLimitedPredictions }
    
    /// Whether IOB is available
    public var canShowIOB: Bool { capabilities.canShowIOB }
    
    /// Whether dosing is possible
    public var canEnact: Bool { capabilities.canEnactTempBasal || capabilities.canDeliverSMB }
    
    /// Whether this is a degraded state (not full)
    public var isDegraded: Bool { level != .full }
    
    /// Convert to DeviceStatusElementState
    public var elementState: DeviceStatusElementState {
        switch level {
        case .full:
            return .normalCGM
        case .limitedPredictions:
            return .warning
        case .cgmOnly:
            return .warning
        case .offline:
            return .critical
        }
    }
}

// MARK: - Factory Methods

extension AlgorithmDegradation {
    
    /// Evaluate degradation from system state
    public static func evaluate(
        loopMode: LoopMode,
        cgmConnected: Bool,
        pumpConnected: Bool,
        insulinFreshness: InsulinFreshness?,
        evaluatedAt: Date = Date()
    ) -> AlgorithmDegradation {
        
        // No CGM = offline
        guard cgmConnected else {
            return AlgorithmDegradation(
                level: .offline,
                capabilities: .offline,
                reason: .cgmDisconnected,
                evaluatedAt: evaluatedAt
            )
        }
        
        // CGM-only mode (user choice)
        if loopMode == .cgmOnly {
            return AlgorithmDegradation(
                level: .cgmOnly,
                capabilities: .cgmOnly,
                reason: .userSelectedCGMOnly,
                evaluatedAt: evaluatedAt
            )
        }
        
        // No pump when required
        if loopMode.requiresPump && !pumpConnected {
            return AlgorithmDegradation(
                level: .cgmOnly,
                capabilities: .cgmOnly,
                reason: .pumpDisconnected,
                evaluatedAt: evaluatedAt
            )
        }
        
        // Check insulin data freshness
        if let insulin = insulinFreshness, insulin.iobIsZero {
            return AlgorithmDegradation(
                level: .limitedPredictions,
                capabilities: .limitedPredictions,
                reason: .insulinDataStale,
                evaluatedAt: evaluatedAt
            )
        }
        
        // Full functionality
        return AlgorithmDegradation(
            level: .full,
            capabilities: .full,
            reason: nil,
            evaluatedAt: evaluatedAt
        )
    }
    
    /// Create full functionality state
    public static func full(evaluatedAt: Date = Date()) -> AlgorithmDegradation {
        AlgorithmDegradation(
            level: .full,
            capabilities: .full,
            reason: nil,
            evaluatedAt: evaluatedAt
        )
    }
    
    /// Create CGM-only state
    public static func cgmOnly(reason: DegradationReason, evaluatedAt: Date = Date()) -> AlgorithmDegradation {
        AlgorithmDegradation(
            level: .cgmOnly,
            capabilities: .cgmOnly,
            reason: reason,
            evaluatedAt: evaluatedAt
        )
    }
    
    /// Create offline state
    public static func offline(evaluatedAt: Date = Date()) -> AlgorithmDegradation {
        AlgorithmDegradation(
            level: .offline,
            capabilities: .offline,
            reason: .cgmDisconnected,
            evaluatedAt: evaluatedAt
        )
    }
}

// MARK: - LimitedPrediction

/// Represents a limited prediction when full algorithm isn't available
public struct LimitedPrediction: Sendable, Equatable, Codable {
    
    /// Current glucose value
    public let currentGlucose: Double
    
    /// Glucose trend (mg/dL per minute)
    public let trend: Double?
    
    /// Simple momentum-based prediction points
    public let momentumPrediction: [PredictionPoint]
    
    /// Why prediction is limited
    public let limitation: String
    
    /// Initialize
    public init(
        currentGlucose: Double,
        trend: Double?,
        momentumPrediction: [PredictionPoint],
        limitation: String
    ) {
        self.currentGlucose = currentGlucose
        self.trend = trend
        self.momentumPrediction = momentumPrediction
        self.limitation = limitation
    }
    
    /// Create momentum-only prediction from current glucose and trend
    public static func fromMomentum(
        currentGlucose: Double,
        trend: Double?,
        minutes: Int = 30
    ) -> LimitedPrediction {
        var points: [PredictionPoint] = []
        
        // Generate simple momentum projection
        if let trend = trend {
            let now = Date()
            for minute in stride(from: 5, through: minutes, by: 5) {
                let predicted = currentGlucose + (trend * Double(minute))
                let clampedPrediction = max(40, min(400, predicted))
                points.append(PredictionPoint(
                    date: now.addingTimeInterval(TimeInterval(minute * 60)),
                    value: clampedPrediction
                ))
            }
        }
        
        return LimitedPrediction(
            currentGlucose: currentGlucose,
            trend: trend,
            momentumPrediction: points,
            limitation: "Based on glucose momentum only. IOB/COB effects not included."
        )
    }
    
    /// Prediction point
    public struct PredictionPoint: Sendable, Equatable, Codable {
        public let date: Date
        public let value: Double
        
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }
}

// MARK: - CustomStringConvertible

extension AlgorithmDegradation: CustomStringConvertible {
    public var description: String {
        if let reason = reason {
            return "AlgorithmDegradation(\(level.rawValue): \(reason.rawValue))"
        }
        return "AlgorithmDegradation(\(level.rawValue))"
    }
}

extension AlgorithmDegradation.Capabilities: CustomStringConvertible {
    public var description: String {
        var flags: [String] = []
        if canShowGlucose { flags.append("glucose") }
        if canShowTrend { flags.append("trend") }
        if canShowIOB { flags.append("IOB") }
        if canShowPredictions { flags.append("predictions") }
        if canEnactTempBasal { flags.append("tempBasal") }
        if canDeliverSMB { flags.append("SMB") }
        return "Capabilities(\(flags.joined(separator: ", ")))"
    }
}
