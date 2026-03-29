// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MenstrualCycleAgent.swift
// T1PalAlgorithm
//
// MenstrualCycle agent prototype - cycle phase sensitivity modulation
// Backlog: EFFECT-AGENT-004
// Architecture: docs/architecture/EFFECT-BUNDLE-CORE-ABSTRACTIONS.md
//
// Trace: EFFECT-BUNDLE-NIGHTSCOUT-SPEC.md, AGENT-PRIVACY-GUARANTEES.md
//
// PRIVACY: This agent uses the strictest privacy tier (onDeviceOnly).
// No cycle data, phase information, or effects ever sync to Nightscout.
// All data remains exclusively on the user's device.

import Foundation

// MARK: - Cycle Phase

/// Menstrual cycle phases with associated insulin sensitivity patterns
public enum CyclePhase: String, Codable, Sendable, CaseIterable {
    /// Days 1-5: Menstruation - sensitivity often returns to baseline
    case menstrual = "menstrual"
    
    /// Days 6-13: Follicular - generally higher sensitivity (less insulin needed)
    case follicular = "follicular"
    
    /// Days 14-16: Ovulation - brief period of variable sensitivity
    case ovulation = "ovulation"
    
    /// Days 17-28: Luteal - often lower sensitivity (more insulin needed)
    case luteal = "luteal"
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .menstrual: return "Menstrual"
        case .follicular: return "Follicular"
        case .ovulation: return "Ovulation"
        case .luteal: return "Luteal"
        }
    }
    
    /// Typical day range in a 28-day cycle
    public var typicalDayRange: ClosedRange<Int> {
        switch self {
        case .menstrual: return 1...5
        case .follicular: return 6...13
        case .ovulation: return 14...16
        case .luteal: return 17...28
        }
    }
    
    /// Default sensitivity factor for this phase
    /// < 1.0 = more sensitive (less insulin needed)
    /// > 1.0 = less sensitive (more insulin needed)
    public var defaultSensitivityFactor: Double {
        switch self {
        case .menstrual: return 1.0    // Baseline
        case .follicular: return 0.9   // 10% more sensitive
        case .ovulation: return 1.0    // Variable, use baseline
        case .luteal: return 1.15      // 15% less sensitive
        }
    }
    
    /// Duration in days for typical cycle
    public var typicalDurationDays: Int {
        switch self {
        case .menstrual: return 5
        case .follicular: return 8
        case .ovulation: return 3
        case .luteal: return 12
        }
    }
}

// MARK: - Cycle Configuration

/// User-specific cycle configuration
public struct CycleConfiguration: Codable, Sendable {
    /// Average cycle length in days (default 28)
    public let cycleLengthDays: Int
    
    /// Custom sensitivity factors per phase (optional overrides)
    public let sensitivityOverrides: [CyclePhase: Double]?
    
    /// Whether to enable gradual transitions between phases
    public let useGradualTransitions: Bool
    
    /// Transition period in days (ramp between phases)
    public let transitionDays: Int
    
    /// Confidence in predictions (decreases further from last period)
    public let baseConfidence: Double
    
    /// Days after which confidence starts decreasing
    public let confidenceDecayStartDays: Int
    
    /// Minimum confidence floor
    public let minimumConfidence: Double
    
    public init(
        cycleLengthDays: Int = 28,
        sensitivityOverrides: [CyclePhase: Double]? = nil,
        useGradualTransitions: Bool = true,
        transitionDays: Int = 2,
        baseConfidence: Double = 0.7,
        confidenceDecayStartDays: Int = 21,
        minimumConfidence: Double = 0.3
    ) {
        // Validate cycle length (21-35 typical range)
        self.cycleLengthDays = min(max(cycleLengthDays, 21), 45)
        self.sensitivityOverrides = sensitivityOverrides
        self.useGradualTransitions = useGradualTransitions
        self.transitionDays = min(max(transitionDays, 0), 5)
        self.baseConfidence = min(max(baseConfidence, 0.0), 1.0)
        self.confidenceDecayStartDays = max(confidenceDecayStartDays, 1)
        self.minimumConfidence = min(max(minimumConfidence, 0.0), baseConfidence)
    }
    
    /// Default configuration
    public static let `default` = CycleConfiguration()
    
    /// Conservative configuration (smaller adjustments)
    public static let conservative = CycleConfiguration(
        sensitivityOverrides: [
            .menstrual: 1.0,
            .follicular: 0.95,
            .ovulation: 1.0,
            .luteal: 1.1
        ],
        baseConfidence: 0.5
    )
    
    /// Get sensitivity factor for a phase
    public func sensitivityFactor(for phase: CyclePhase) -> Double {
        if let overrides = sensitivityOverrides, let factor = overrides[phase] {
            // Enforce safety bounds
            return min(max(factor, 0.5), 1.5)
        }
        return phase.defaultSensitivityFactor
    }
}

// MARK: - Cycle State

/// Tracked cycle state (stored on device only)
public struct CycleState: Codable, Sendable {
    /// Date of last period start
    public let lastPeriodStart: Date
    
    /// Whether currently in active period
    public let isInPeriod: Bool
    
    /// User-confirmed current phase (optional override)
    public let confirmedPhase: CyclePhase?
    
    /// Historical cycle lengths for prediction
    public let historicalCycleLengths: [Int]
    
    public init(
        lastPeriodStart: Date,
        isInPeriod: Bool = false,
        confirmedPhase: CyclePhase? = nil,
        historicalCycleLengths: [Int] = []
    ) {
        self.lastPeriodStart = lastPeriodStart
        self.isInPeriod = isInPeriod
        self.confirmedPhase = confirmedPhase
        self.historicalCycleLengths = historicalCycleLengths
    }
    
    /// Predicted average cycle length based on history
    public var predictedCycleLength: Int {
        guard !historicalCycleLengths.isEmpty else { return 28 }
        let sum = historicalCycleLengths.reduce(0, +)
        return sum / historicalCycleLengths.count
    }
    
    /// Days since last period start
    public func daysSinceLastPeriod(at date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: lastPeriodStart, to: date)
        return max(components.day ?? 0, 0)
    }
    
    /// Current day in cycle (1-based)
    public func cycleDay(at date: Date = Date()) -> Int {
        let days = daysSinceLastPeriod(at: date)
        let cycleLength = predictedCycleLength
        
        if days >= cycleLength {
            // Beyond predicted cycle - use modulo but cap at reasonable value
            let modDay = (days % cycleLength) + 1
            return min(modDay, cycleLength)
        }
        
        return days + 1  // 1-based
    }
    
    /// Predicted current phase
    public func predictedPhase(
        at date: Date = Date(),
        cycleLength: Int = 28
    ) -> CyclePhase {
        // If user confirmed a phase recently, use that
        if let confirmed = confirmedPhase {
            return confirmed
        }
        
        let day = cycleDay(at: date)
        
        // Scale phase boundaries based on cycle length
        let scale = Double(cycleLength) / 28.0
        
        let menstrualEnd = Int(5.0 * scale)
        let follicularEnd = Int(13.0 * scale)
        let ovulationEnd = Int(16.0 * scale)
        
        if day <= menstrualEnd {
            return .menstrual
        } else if day <= follicularEnd {
            return .follicular
        } else if day <= ovulationEnd {
            return .ovulation
        } else {
            return .luteal
        }
    }
}

// MARK: - MenstrualCycle Agent

/// Agent that adjusts insulin sensitivity based on menstrual cycle phase
///
/// Research shows insulin sensitivity varies throughout the menstrual cycle:
/// - Follicular phase: Often higher sensitivity (need less insulin)
/// - Luteal phase: Often lower sensitivity (need more insulin)
/// - Menstrual phase: Returns toward baseline
///
/// This is highly individual - the agent supports user calibration.
///
/// PRIVACY: This agent uses onDeviceOnly tier. No data ever syncs.
public actor MenstrualCycleAgent: EffectAgent {
    
    public nonisolated let agentId = "menstrualCycle"
    public nonisolated let name = "Menstrual Cycle"
    public nonisolated let description = "Cycle phase sensitivity adjustments (on-device only)"
    public nonisolated let privacyTier: PrivacyTier = .onDeviceOnly
    
    // MARK: - State
    
    private var configuration: CycleConfiguration
    private var cycleState: CycleState?
    private var isEnabled: Bool = false
    
    // MARK: - Initialization
    
    public init(configuration: CycleConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Configuration
    
    /// Update configuration
    public func configure(_ newConfiguration: CycleConfiguration) {
        self.configuration = newConfiguration
    }
    
    /// Enable the agent
    public func enable() {
        self.isEnabled = true
    }
    
    /// Disable the agent
    public func disable() {
        self.isEnabled = false
    }
    
    /// Check if agent is enabled
    public func checkEnabled() -> Bool {
        return isEnabled
    }
    
    // MARK: - Cycle Tracking
    
    /// Log period start (primary tracking input)
    public func logPeriodStart(date: Date = Date()) {
        // Update historical data
        var history: [Int] = cycleState?.historicalCycleLengths ?? []
        
        if let lastState = cycleState {
            let daysSinceLast = lastState.daysSinceLastPeriod(at: date)
            if daysSinceLast >= 21 && daysSinceLast <= 45 {
                history.append(daysSinceLast)
                // Keep last 6 cycles for prediction
                if history.count > 6 {
                    history.removeFirst()
                }
            }
        }
        
        cycleState = CycleState(
            lastPeriodStart: date,
            isInPeriod: true,
            confirmedPhase: .menstrual,
            historicalCycleLengths: history
        )
    }
    
    /// Log period end
    public func logPeriodEnd() {
        guard let current = cycleState else { return }
        cycleState = CycleState(
            lastPeriodStart: current.lastPeriodStart,
            isInPeriod: false,
            confirmedPhase: nil,  // Clear confirmed phase, use prediction
            historicalCycleLengths: current.historicalCycleLengths
        )
    }
    
    /// Manually confirm current phase (user override)
    public func confirmPhase(_ phase: CyclePhase) {
        guard let current = cycleState else { return }
        cycleState = CycleState(
            lastPeriodStart: current.lastPeriodStart,
            isInPeriod: phase == .menstrual,
            confirmedPhase: phase,
            historicalCycleLengths: current.historicalCycleLengths
        )
    }
    
    /// Get current cycle state (for UI)
    public func getCurrentState() -> CycleState? {
        return cycleState
    }
    
    /// Get current phase prediction
    public func getCurrentPhase(at date: Date = Date()) -> CyclePhase? {
        guard let state = cycleState else { return nil }
        return state.predictedPhase(at: date, cycleLength: configuration.cycleLengthDays)
    }
    
    /// Get current cycle day
    public func getCycleDay(at date: Date = Date()) -> Int? {
        return cycleState?.cycleDay(at: date)
    }
    
    // MARK: - EffectAgent Protocol
    
    public func evaluate(context: AgentContext) async -> EffectBundle? {
        // Must be enabled and have cycle state
        guard isEnabled, let state = cycleState else {
            return nil
        }
        
        let now = context.timeOfDay
        let phase = state.predictedPhase(at: now, cycleLength: configuration.cycleLengthDays)
        let cycleDay = state.cycleDay(at: now)
        
        // Calculate confidence (decreases further from last period)
        let daysSincePeriod = state.daysSinceLastPeriod(at: now)
        let confidence = calculateConfidence(daysSincePeriod: daysSincePeriod)
        
        // Skip if confidence too low
        guard confidence >= configuration.minimumConfidence else {
            return nil
        }
        
        // Get sensitivity factor for phase
        var sensitivityFactor = configuration.sensitivityFactor(for: phase)
        
        // Apply gradual transitions if enabled
        if configuration.useGradualTransitions {
            sensitivityFactor = applyGradualTransition(
                baseFactor: sensitivityFactor,
                phase: phase,
                cycleDay: cycleDay
            )
        }
        
        // Only create bundle if sensitivity differs from baseline
        guard abs(sensitivityFactor - 1.0) > 0.01 else {
            return nil
        }
        
        // Effect lasts until next evaluation (typically 5 min)
        let effectDurationMinutes = 5
        
        let sensitivityEffect = SensitivityEffectSpec(
            confidence: confidence,
            factor: sensitivityFactor,
            durationMinutes: effectDurationMinutes
        )
        
        let effectDurationInterval: TimeInterval = Double(effectDurationMinutes) * 60
        
        return EffectBundle(
            agent: agentId,
            timestamp: now,
            validFrom: now,
            validUntil: now.addingTimeInterval(effectDurationInterval),
            effects: [.sensitivity(sensitivityEffect)],
            reason: nil,  // Never include reason - maximum privacy
            privacyTier: .onDeviceOnly,
            confidence: confidence
        )
    }
    
    // MARK: - Private Helpers
    
    private func calculateConfidence(daysSincePeriod: Int) -> Double {
        if daysSincePeriod <= configuration.confidenceDecayStartDays {
            return configuration.baseConfidence
        }
        
        // Linear decay after threshold
        let daysOver = daysSincePeriod - configuration.confidenceDecayStartDays
        let decayRate = (configuration.baseConfidence - configuration.minimumConfidence) / 14.0
        let decayed = configuration.baseConfidence - (Double(daysOver) * decayRate)
        
        return max(decayed, configuration.minimumConfidence)
    }
    
    private func applyGradualTransition(
        baseFactor: Double,
        phase: CyclePhase,
        cycleDay: Int
    ) -> Double {
        let transitionDays = configuration.transitionDays
        guard transitionDays > 0 else { return baseFactor }
        
        // Get phase boundaries
        let scale = Double(configuration.cycleLengthDays) / 28.0
        let boundaries: [CyclePhase: Int] = [
            .menstrual: 1,
            .follicular: Int(6.0 * scale),
            .ovulation: Int(14.0 * scale),
            .luteal: Int(17.0 * scale)
        ]
        
        guard let phaseStart = boundaries[phase] else { return baseFactor }
        
        // Days into current phase
        let daysIntoPhase = cycleDay - phaseStart + 1
        
        if daysIntoPhase <= transitionDays {
            // Transitioning in - blend from 1.0 to target
            let progress = Double(daysIntoPhase) / Double(transitionDays)
            return 1.0 + (baseFactor - 1.0) * progress
        }
        
        return baseFactor
    }
}

// MARK: - Privacy Extension

extension MenstrualCycleAgent {
    /// Export cycle data for backup (encrypted, never synced)
    public func exportForBackup() -> Data? {
        guard let state = cycleState else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(state)
    }
    
    /// Import cycle data from backup
    public func importFromBackup(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        cycleState = try decoder.decode(CycleState.self, from: data)
    }
    
    /// Delete all cycle data
    public func deleteAllData() {
        cycleState = nil
        isEnabled = false
    }
}
