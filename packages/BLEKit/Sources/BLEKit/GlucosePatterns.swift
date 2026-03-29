// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GlucosePatterns.swift
// BLEKit
//
// Dynamic glucose pattern generators for realistic CGM simulation.
// Trace: PRD-007 REQ-SIM-005

import Foundation

// MARK: - Glucose Pattern Protocol

/// Protocol for time-based glucose pattern generation
///
/// Patterns generate glucose values that change over time, enabling
/// realistic CGM simulation without real hardware.
public protocol GlucosePattern: GlucoseProvider {
    /// Pattern start time
    var startTime: Date { get }
    
    /// Get glucose value at a specific time
    func glucose(at time: Date) -> UInt16
    
    /// Get trend at a specific time (-8 to +8, roughly mg/dL/min)
    func trend(at time: Date) -> Int8
    
    /// Reset the pattern (restarts from current time)
    mutating func reset()
}

// Default implementations
extension GlucosePattern {
    public func currentGlucose() -> UInt16 {
        glucose(at: Date())
    }
    
    public func predictedGlucose() -> UInt16 {
        // Predict 15 minutes ahead based on current trend
        let trend = self.trend(at: Date())
        let current = Int(glucose(at: Date()))
        let predicted = current + Int(trend) * 15
        return UInt16(clamping: max(40, min(400, predicted)))
    }
    
    public func currentTrend() -> Int8 {
        trend(at: Date())
    }
}

// MARK: - Flat Pattern

/// Constant glucose value pattern
///
/// Useful for testing or simulating stable blood glucose.
public struct FlatGlucosePattern: GlucosePattern, Sendable {
    public var startTime: Date
    public let baseGlucose: UInt16
    public let noise: UInt16
    
    /// Create a flat glucose pattern
    /// - Parameters:
    ///   - baseGlucose: Target glucose in mg/dL (default: 100)
    ///   - noise: Random variation in mg/dL (default: 0)
    public init(baseGlucose: UInt16 = 100, noise: UInt16 = 0) {
        self.startTime = Date()
        self.baseGlucose = baseGlucose
        self.noise = noise
    }
    
    public func glucose(at time: Date) -> UInt16 {
        if noise == 0 {
            return baseGlucose
        }
        // Add deterministic noise based on time
        let seconds = Int(time.timeIntervalSince1970)
        let variation = Int(seconds % Int(noise * 2 + 1)) - Int(noise)
        return UInt16(clamping: Int(baseGlucose) + variation)
    }
    
    public func trend(at time: Date) -> Int8 {
        0  // Flat pattern has no trend
    }
    
    public mutating func reset() {
        startTime = Date()
    }
}

// MARK: - Sine Wave Pattern

/// Sinusoidal glucose oscillation pattern
///
/// Simulates natural circadian rhythm or post-meal oscillations.
public struct SineWavePattern: GlucosePattern, Sendable {
    public var startTime: Date
    public let baseGlucose: UInt16
    public let amplitude: UInt16
    public let periodMinutes: Double
    public let phaseMinutes: Double
    
    /// Create a sine wave glucose pattern
    /// - Parameters:
    ///   - baseGlucose: Center glucose in mg/dL (default: 120)
    ///   - amplitude: Peak deviation in mg/dL (default: 30)
    ///   - periodMinutes: Wave period in minutes (default: 180 = 3 hours)
    ///   - phaseMinutes: Phase offset in minutes (default: 0)
    public init(
        baseGlucose: UInt16 = 120,
        amplitude: UInt16 = 30,
        periodMinutes: Double = 180,
        phaseMinutes: Double = 0
    ) {
        self.startTime = Date()
        self.baseGlucose = baseGlucose
        self.amplitude = amplitude
        self.periodMinutes = periodMinutes
        self.phaseMinutes = phaseMinutes
    }
    
    public func glucose(at time: Date) -> UInt16 {
        let elapsed = time.timeIntervalSince(startTime) / 60.0  // minutes
        let phase = (elapsed + phaseMinutes) / periodMinutes * 2 * .pi
        let wave = sin(phase)
        let value = Double(baseGlucose) + Double(amplitude) * wave
        return UInt16(clamping: Int(value.rounded()))
    }
    
    public func trend(at time: Date) -> Int8 {
        // Derivative of sin is cos, scaled to mg/dL/min
        let elapsed = time.timeIntervalSince(startTime) / 60.0
        let phase = (elapsed + phaseMinutes) / periodMinutes * 2 * .pi
        let derivative = cos(phase) * Double(amplitude) * 2 * .pi / periodMinutes
        // Scale: typically -8 to +8 represents roughly mg/dL/min
        let trend = derivative.clamped(to: -8...8)
        return Int8(trend.rounded())
    }
    
    public mutating func reset() {
        startTime = Date()
    }
}

// MARK: - Meal Response Pattern

/// Simulates glucose response to a meal
///
/// Models the typical rise and fall after eating:
/// - Rise phase: glucose increases to peak
/// - Peak: maximum glucose reached
/// - Decay phase: glucose returns toward baseline
public struct MealResponsePattern: GlucosePattern, Sendable {
    public var startTime: Date
    public let baseGlucose: UInt16
    public let peakGlucose: UInt16
    public let riseMinutes: Double
    public let peakMinutes: Double
    public let decayMinutes: Double
    
    /// Create a meal response pattern
    /// - Parameters:
    ///   - baseGlucose: Pre-meal glucose in mg/dL (default: 100)
    ///   - peakGlucose: Peak glucose after meal in mg/dL (default: 180)
    ///   - riseMinutes: Time to reach peak (default: 45)
    ///   - peakMinutes: Time at peak plateau (default: 15)
    ///   - decayMinutes: Time to return to baseline (default: 120)
    public init(
        baseGlucose: UInt16 = 100,
        peakGlucose: UInt16 = 180,
        riseMinutes: Double = 45,
        peakMinutes: Double = 15,
        decayMinutes: Double = 120
    ) {
        self.startTime = Date()
        self.baseGlucose = baseGlucose
        self.peakGlucose = peakGlucose
        self.riseMinutes = riseMinutes
        self.peakMinutes = peakMinutes
        self.decayMinutes = decayMinutes
    }
    
    /// Total duration of the meal response
    public var totalDuration: Double {
        riseMinutes + peakMinutes + decayMinutes
    }
    
    public func glucose(at time: Date) -> UInt16 {
        let elapsed = time.timeIntervalSince(startTime) / 60.0  // minutes
        
        // Before meal (or after complete cycle)
        if elapsed < 0 || elapsed > totalDuration {
            return baseGlucose
        }
        
        let rise = Double(peakGlucose) - Double(baseGlucose)
        
        // Rise phase
        if elapsed < riseMinutes {
            let progress = elapsed / riseMinutes
            // Smooth rise using ease-out curve
            let eased = 1 - pow(1 - progress, 2)
            let value = Double(baseGlucose) + rise * eased
            return UInt16(clamping: Int(value.rounded()))
        }
        
        // Peak phase
        if elapsed < riseMinutes + peakMinutes {
            return peakGlucose
        }
        
        // Decay phase
        let decayElapsed = elapsed - riseMinutes - peakMinutes
        let progress = decayElapsed / decayMinutes
        // Smooth decay using exponential curve
        let decay = exp(-3 * progress)  // 3 time constants
        let value = Double(baseGlucose) + rise * decay
        return UInt16(clamping: Int(value.rounded()))
    }
    
    public func trend(at time: Date) -> Int8 {
        let elapsed = time.timeIntervalSince(startTime) / 60.0
        
        // No trend outside meal response
        if elapsed < 0 || elapsed > totalDuration {
            return 0
        }
        
        let rise = Double(peakGlucose) - Double(baseGlucose)
        
        // Rise phase - positive trend
        if elapsed < riseMinutes {
            let progress = elapsed / riseMinutes
            // Derivative of ease-out: 2 * (1 - progress)
            let rate = rise * 2 * (1 - progress) / riseMinutes
            return Int8(rate.clamped(to: -8...8).rounded())
        }
        
        // Peak phase - no trend
        if elapsed < riseMinutes + peakMinutes {
            return 0
        }
        
        // Decay phase - negative trend
        let decayElapsed = elapsed - riseMinutes - peakMinutes
        let progress = decayElapsed / decayMinutes
        // Derivative of exponential decay
        let rate = -3 * rise * exp(-3 * progress) / decayMinutes
        return Int8(rate.clamped(to: -8...8).rounded())
    }
    
    public mutating func reset() {
        startTime = Date()
    }
    
    /// Start a new meal at the current time
    public mutating func startMeal() {
        startTime = Date()
    }
}

// MARK: - Random Walk Pattern

/// Brownian motion / random walk glucose pattern
///
/// Simulates natural glucose variability with configurable volatility.
/// Uses deterministic pseudo-random sequence for reproducibility.
public struct RandomWalkPattern: GlucosePattern, Sendable {
    public var startTime: Date
    public let baseGlucose: UInt16
    public let volatility: Double
    public let minGlucose: UInt16
    public let maxGlucose: UInt16
    public let seed: UInt64
    
    // Current state
    private var currentValue: Double
    private var lastUpdateTime: Date
    
    /// Create a random walk glucose pattern
    /// - Parameters:
    ///   - baseGlucose: Starting glucose in mg/dL (default: 120)
    ///   - volatility: Standard deviation of changes per minute (default: 1.0)
    ///   - minGlucose: Minimum allowed glucose (default: 70)
    ///   - maxGlucose: Maximum allowed glucose (default: 250)
    ///   - seed: Random seed for reproducibility (default: current time)
    public init(
        baseGlucose: UInt16 = 120,
        volatility: Double = 1.0,
        minGlucose: UInt16 = 70,
        maxGlucose: UInt16 = 250,
        seed: UInt64? = nil
    ) {
        self.startTime = Date()
        self.baseGlucose = baseGlucose
        self.volatility = volatility
        self.minGlucose = minGlucose
        self.maxGlucose = maxGlucose
        self.seed = seed ?? UInt64(Date().timeIntervalSince1970 * 1000)
        self.currentValue = Double(baseGlucose)
        self.lastUpdateTime = Date()
    }
    
    public func glucose(at time: Date) -> UInt16 {
        // Use deterministic random based on time and seed
        let elapsed = time.timeIntervalSince(startTime)
        let minutes = max(0, Int(elapsed / 60))  // Ensure non-negative for range
        
        var value = Double(baseGlucose)
        var rng = seed
        
        // Simulate random walk up to current minute
        for _ in 0..<minutes {
            rng = xorshift64(rng)
            let random = gaussianFromUniform(rng)
            value += random * volatility
            value = value.clamped(to: Double(minGlucose)...Double(maxGlucose))
        }
        
        return UInt16(clamping: Int(value.rounded()))
    }
    
    public func trend(at time: Date) -> Int8 {
        // Calculate trend from recent change
        let current = glucose(at: time)
        let previous = glucose(at: time.addingTimeInterval(-300))  // 5 minutes ago
        let change = Int(current) - Int(previous)
        let rate = Double(change) / 5.0  // mg/dL per minute
        return Int8(rate.clamped(to: -8...8).rounded())
    }
    
    public mutating func reset() {
        startTime = Date()
        currentValue = Double(baseGlucose)
        lastUpdateTime = Date()
    }
    
    // Simple xorshift64 PRNG
    private func xorshift64(_ x: UInt64) -> UInt64 {
        var x = x
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        return x
    }
    
    // Box-Muller transform for Gaussian from uniform
    private func gaussianFromUniform(_ x: UInt64) -> Double {
        let u1 = Double(x & 0xFFFFFFFF) / Double(0xFFFFFFFF)
        let u2 = Double((x >> 32) & 0xFFFFFFFF) / Double(0xFFFFFFFF)
        let u1Safe = max(0.0001, u1)  // Avoid log(0)
        return sqrt(-2 * log(u1Safe)) * cos(2 * .pi * u2)
    }
}

// MARK: - Replay Pattern

/// Replays glucose values from a recorded sequence
///
/// Useful for testing with real patient data or specific scenarios.
public struct ReplayPattern: GlucosePattern, Sendable {
    public var startTime: Date
    public let readings: [(offsetMinutes: Double, glucose: UInt16)]
    public let loop: Bool
    
    /// Create a replay pattern from recorded readings
    /// - Parameters:
    ///   - readings: Array of (offsetMinutes, glucose) tuples
    ///   - loop: Whether to loop back to start after last reading
    public init(readings: [(offsetMinutes: Double, glucose: UInt16)], loop: Bool = false) {
        self.startTime = Date()
        self.readings = readings.sorted { $0.offsetMinutes < $1.offsetMinutes }
        self.loop = loop
    }
    
    /// Total duration of the replay
    public var duration: Double {
        readings.last?.offsetMinutes ?? 0
    }
    
    public func glucose(at time: Date) -> UInt16 {
        guard !readings.isEmpty else { return 100 }
        
        var elapsed = time.timeIntervalSince(startTime) / 60.0
        
        if loop && duration > 0 {
            elapsed = elapsed.truncatingRemainder(dividingBy: duration)
        }
        
        // Find surrounding readings
        var lower: (offsetMinutes: Double, glucose: UInt16)?
        var upper: (offsetMinutes: Double, glucose: UInt16)?
        
        for reading in readings {
            if reading.offsetMinutes <= elapsed {
                lower = reading
            }
            if reading.offsetMinutes >= elapsed && upper == nil {
                upper = reading
            }
        }
        
        guard let l = lower else {
            return readings.first?.glucose ?? 100
        }
        
        guard let u = upper, u.offsetMinutes > l.offsetMinutes else {
            return l.glucose
        }
        
        // Linear interpolation
        let progress = (elapsed - l.offsetMinutes) / (u.offsetMinutes - l.offsetMinutes)
        let interpolated = Double(l.glucose) + progress * (Double(u.glucose) - Double(l.glucose))
        return UInt16(clamping: Int(interpolated.rounded()))
    }
    
    public func trend(at time: Date) -> Int8 {
        let current = glucose(at: time)
        let previous = glucose(at: time.addingTimeInterval(-300))
        let change = Int(current) - Int(previous)
        let rate = Double(change) / 5.0
        return Int8(rate.clamped(to: -8...8).rounded())
    }
    
    public mutating func reset() {
        startTime = Date()
    }
}

// MARK: - Composite Pattern

/// Combines multiple patterns with weights
public struct CompositePattern: GlucosePattern, Sendable {
    public var startTime: Date
    public let patterns: [any GlucosePattern]
    public let weights: [Double]
    
    /// Create a composite pattern
    /// - Parameters:
    ///   - patterns: Array of patterns to combine
    ///   - weights: Weights for each pattern (normalized internally)
    public init(patterns: [any GlucosePattern], weights: [Double]? = nil) {
        self.startTime = Date()
        self.patterns = patterns
        
        let w = weights ?? Array(repeating: 1.0, count: patterns.count)
        let total = w.reduce(0, +)
        self.weights = total > 0 ? w.map { $0 / total } : w
    }
    
    public func glucose(at time: Date) -> UInt16 {
        guard !patterns.isEmpty else { return 100 }
        
        var total = 0.0
        for (pattern, weight) in zip(patterns, weights) {
            total += Double(pattern.glucose(at: time)) * weight
        }
        return UInt16(clamping: Int(total.rounded()))
    }
    
    public func trend(at time: Date) -> Int8 {
        guard !patterns.isEmpty else { return 0 }
        
        var total = 0.0
        for (pattern, weight) in zip(patterns, weights) {
            total += Double(pattern.trend(at: time)) * weight
        }
        return Int8(total.clamped(to: -8...8).rounded())
    }
    
    public mutating func reset() {
        startTime = Date()
    }
}

// MARK: - Helper Extension

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
