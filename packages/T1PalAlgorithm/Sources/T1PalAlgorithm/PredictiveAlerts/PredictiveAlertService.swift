// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PredictiveAlertService.swift
// T1Pal Mobile
//
// Predictive glucose alert state machine
// Source: GlucOS PredictiveGlucoseAlertStorage
// Trace: GLUCOS-IMPL-002, ADR-010

import Foundation
import T1PalCore

// MARK: - Alert State

/// Predictive alert state
public enum PredictiveAlertState: String, Codable, Sendable {
    case inRange
    case predictedHigh
    case predictedLow
}

// MARK: - Alert Settings

/// Settings for predictive glucose alerts
public struct PredictiveAlertSettings: Codable, Sendable, Equatable {
    /// Whether predictive alerts are enabled
    public var enabled: Bool
    
    /// High glucose threshold (mg/dL)
    public var highThresholdMgDl: Double
    
    /// Low glucose threshold (mg/dL)
    public var lowThresholdMgDl: Double
    
    /// Minimum time between high alerts (seconds)
    public var highRepeatInterval: TimeInterval
    
    /// Minimum time between low alerts (seconds)
    public var lowRepeatInterval: TimeInterval
    
    /// Prediction horizon (seconds)
    public var predictionHorizon: TimeInterval
    
    /// Default settings
    public static let defaults = PredictiveAlertSettings(
        enabled: false,
        highThresholdMgDl: 250,
        lowThresholdMgDl: 70,
        highRepeatInterval: 30 * 60,
        lowRepeatInterval: 30 * 60,
        predictionHorizon: 15 * 60
    )
    
    public init(
        enabled: Bool = false,
        highThresholdMgDl: Double = 250,
        lowThresholdMgDl: Double = 70,
        highRepeatInterval: TimeInterval = 30 * 60,
        lowRepeatInterval: TimeInterval = 30 * 60,
        predictionHorizon: TimeInterval = 15 * 60
    ) {
        self.enabled = enabled
        self.highThresholdMgDl = highThresholdMgDl
        self.lowThresholdMgDl = lowThresholdMgDl
        self.highRepeatInterval = highRepeatInterval
        self.lowRepeatInterval = lowRepeatInterval
        self.predictionHorizon = predictionHorizon
    }
}

// MARK: - Alert Event

/// Alert event for notification dispatch
public struct PredictiveAlertEvent: Sendable {
    public let state: PredictiveAlertState
    public let currentGlucose: Double
    public let predictedGlucose: Double
    public let timestamp: Date
    
    public init(
        state: PredictiveAlertState,
        currentGlucose: Double,
        predictedGlucose: Double,
        timestamp: Date = Date()
    ) {
        self.state = state
        self.currentGlucose = currentGlucose
        self.predictedGlucose = predictedGlucose
        self.timestamp = timestamp
    }
}

// MARK: - Protocol

/// Protocol for predictive alert service
public protocol PredictiveAlertServiceProtocol: Sendable {
    /// Process new glucose readings and check for alerts
    func processReadings(_ readings: [GlucoseReading]) async -> PredictiveAlertEvent?
    
    /// Current alert state
    var currentState: PredictiveAlertState { get async }
    
    /// Update settings
    func updateSettings(_ settings: PredictiveAlertSettings) async
}

// MARK: - Implementation

/// Predictive glucose alert service with state machine
/// Source: GlucOS PredictiveGlucoseAlertStorage
public actor PredictiveAlertService: PredictiveAlertServiceProtocol {
    
    // MARK: - State
    
    private var state: PredictiveAlertState = .inRange
    private var settings: PredictiveAlertSettings = .defaults
    private var lastAlertTime: Date?
    private let predictor: LinearGlucosePredictor
    
    // MARK: - Init
    
    public init(
        settings: PredictiveAlertSettings = .defaults,
        predictor: LinearGlucosePredictor = LinearGlucosePredictor()
    ) {
        self.settings = settings
        self.predictor = predictor
    }
    
    // MARK: - Public
    
    public var currentState: PredictiveAlertState {
        state
    }
    
    public func updateSettings(_ newSettings: PredictiveAlertSettings) {
        settings = newSettings
    }
    
    /// Process new glucose readings and determine if alert should fire
    public func processReadings(_ readings: [GlucoseReading]) -> PredictiveAlertEvent? {
        guard settings.enabled else { return nil }
        guard let current = readings.last else { return nil }
        
        // Get prediction
        guard let predicted = predictor.predict(
            from: readings,
            horizon: settings.predictionHorizon
        ) else { return nil }
        
        // Determine next state
        let nextState = determineState(predictedGlucose: predicted)
        let shouldAlert = shouldSendAlert(from: state, to: nextState)
        
        // Update state
        let previousState = state
        state = nextState
        
        // Return alert event if needed
        if shouldAlert {
            lastAlertTime = Date()
            return PredictiveAlertEvent(
                state: nextState,
                currentGlucose: current.glucose,
                predictedGlucose: predicted
            )
        }
        
        // Log state transition even if no alert
        if previousState != nextState {
            // State changed but alert suppressed (repeat interval)
        }
        
        return nil
    }
    
    // MARK: - Private
    
    private func determineState(predictedGlucose: Double) -> PredictiveAlertState {
        if predictedGlucose >= settings.highThresholdMgDl {
            return .predictedHigh
        } else if predictedGlucose <= settings.lowThresholdMgDl {
            return .predictedLow
        }
        return .inRange
    }
    
    private func shouldSendAlert(
        from current: PredictiveAlertState,
        to next: PredictiveAlertState
    ) -> Bool {
        // No alert when returning to range
        guard next != .inRange else { return false }
        
        // State transition → immediate alert
        if current != next { return true }
        
        // Same state → check repeat interval
        guard let lastAlert = lastAlertTime else { return true }
        
        let elapsed = Date().timeIntervalSince(lastAlert)
        let interval = next == .predictedHigh
            ? settings.highRepeatInterval
            : settings.lowRepeatInterval
        
        return elapsed >= interval
    }
}

// MARK: - Alert Message Formatting

extension PredictiveAlertEvent {
    /// Human-readable alert title
    public var title: String {
        switch state {
        case .inRange:
            return "Glucose In Range"
        case .predictedHigh:
            return "Predicted High"
        case .predictedLow:
            return "Predicted Low"
        }
    }
    
    /// Human-readable alert body
    public var body: String {
        let horizon = 15 // minutes
        switch state {
        case .inRange:
            return "Glucose predicted to stay in range"
        case .predictedHigh:
            return String(format: "Current: %.0f mg/dL → Predicted: %.0f mg/dL in %d min",
                         currentGlucose, predictedGlucose, horizon)
        case .predictedLow:
            return String(format: "Current: %.0f mg/dL → Predicted: %.0f mg/dL in %d min",
                         currentGlucose, predictedGlucose, horizon)
        }
    }
    
    /// Alert priority (for notification importance)
    public var priority: AlertPriority {
        switch state {
        case .inRange:
            return .low
        case .predictedHigh:
            return .normal
        case .predictedLow:
            return .high  // Low glucose is more urgent
        }
    }
}

/// Alert priority levels
public enum AlertPriority: Int, Sendable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3
    
    public static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
