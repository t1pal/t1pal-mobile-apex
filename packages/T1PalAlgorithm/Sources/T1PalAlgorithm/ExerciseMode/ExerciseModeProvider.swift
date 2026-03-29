// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ExerciseModeProvider.swift
// T1Pal Mobile
//
// Exercise mode service for target adjustment
// Source: GlucOS WorkoutStatusService, TargetGlucoseService
// Trace: GLUCOS-IMPL-004, ADR-010

import Foundation

// MARK: - Exercise State

/// Exercise session state
public enum ExerciseState: String, Codable, Sendable {
    case inactive
    case active
    case expired
}

// MARK: - Exercise Settings

/// Settings for exercise mode
public struct ExerciseModeSettings: Codable, Sendable, Equatable {
    /// Whether exercise mode adjusts glucose target
    public var adjustTargetDuringExercise: Bool
    
    /// Target glucose during exercise (mg/dL)
    public var exerciseTargetGlucose: Double
    
    /// Auto-expiration interval (seconds)
    public var expirationInterval: TimeInterval
    
    /// Default settings
    public static let defaults = ExerciseModeSettings(
        adjustTargetDuringExercise: true,
        exerciseTargetGlucose: 140,
        expirationInterval: 60 * 60  // 60 minutes
    )
    
    public init(
        adjustTargetDuringExercise: Bool = true,
        exerciseTargetGlucose: Double = 140,
        expirationInterval: TimeInterval = 60 * 60
    ) {
        self.adjustTargetDuringExercise = adjustTargetDuringExercise
        self.exerciseTargetGlucose = exerciseTargetGlucose
        self.expirationInterval = expirationInterval
    }
}

// MARK: - Protocol

/// Protocol for exercise mode provider
public protocol ExerciseModeProviderProtocol: Sendable {
    /// Check if currently exercising
    func isExercising(at date: Date) async -> Bool
    
    /// Start exercise mode
    func startExercise() async
    
    /// End exercise mode
    func endExercise() async
    
    /// Get effective target glucose considering exercise state
    func effectiveTarget(baseTarget: Double, at date: Date) async -> Double
    
    /// Current state
    var state: ExerciseState { get async }
    
    /// Last message timestamp
    var lastMessageTime: Date? { get async }
}

// MARK: - Implementation

/// Local exercise mode provider with persistence
/// Source: GlucOS WorkoutStatusService
public actor ExerciseModeProvider: ExerciseModeProviderProtocol {
    
    // MARK: - State
    
    private var _state: ExerciseState = .inactive
    private var _lastMessageTime: Date?
    private var settings: ExerciseModeSettings
    private let storage: ExerciseModeStorage
    
    // MARK: - Init
    
    public init(
        settings: ExerciseModeSettings = .defaults,
        storage: ExerciseModeStorage = UserDefaultsExerciseStorage()
    ) {
        self.settings = settings
        self.storage = storage
        
        // Restore state from storage
        if let savedState = storage.loadState() {
            self._state = savedState.state
            self._lastMessageTime = savedState.lastMessageTime
        }
    }
    
    // MARK: - Public
    
    public var state: ExerciseState {
        updateStateIfExpired()
        return _state
    }
    
    public var lastMessageTime: Date? {
        _lastMessageTime
    }
    
    public func isExercising(at date: Date) -> Bool {
        guard let lastMessage = _lastMessageTime else { return false }
        
        // Check if session has expired
        guard date.timeIntervalSince(lastMessage) < settings.expirationInterval else {
            return false
        }
        
        return _state == .active
    }
    
    public func startExercise() {
        _lastMessageTime = Date()
        _state = .active
        persistState()
    }
    
    public func endExercise() {
        _state = .inactive
        persistState()
    }
    
    public func effectiveTarget(baseTarget: Double, at date: Date) -> Double {
        guard settings.adjustTargetDuringExercise else {
            return baseTarget
        }
        
        if isExercising(at: date) {
            return max(baseTarget, settings.exerciseTargetGlucose)
        }
        
        return baseTarget
    }
    
    /// Update settings
    public func updateSettings(_ newSettings: ExerciseModeSettings) {
        settings = newSettings
    }
    
    // MARK: - Private
    
    private func updateStateIfExpired() {
        guard let lastMessage = _lastMessageTime else { return }
        
        if _state == .active {
            let elapsed = Date().timeIntervalSince(lastMessage)
            if elapsed >= settings.expirationInterval {
                _state = .expired
            }
        }
    }
    
    private func persistState() {
        storage.saveState(ExercisePersistentState(
            state: _state,
            lastMessageTime: _lastMessageTime
        ))
    }
}

// MARK: - Persistence

/// Persistent state for exercise mode
public struct ExercisePersistentState: Codable, Sendable {
    public let state: ExerciseState
    public let lastMessageTime: Date?
}

/// Storage protocol for exercise mode persistence
public protocol ExerciseModeStorage: Sendable {
    func saveState(_ state: ExercisePersistentState)
    func loadState() -> ExercisePersistentState?
}

/// UserDefaults-based storage for exercise mode
public final class UserDefaultsExerciseStorage: ExerciseModeStorage, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "T1Pal.ExerciseMode.State"
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public func saveState(_ state: ExercisePersistentState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: key)
        }
    }
    
    public func loadState() -> ExercisePersistentState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ExercisePersistentState.self, from: data)
    }
}

// MARK: - Watch Integration

/// Watch message for exercise events
/// Integration point for T1PalWatch app
public struct ExerciseWatchMessage: Codable, Sendable {
    public let type: ExerciseMessageType
    public let timestamp: Date
    
    public enum ExerciseMessageType: String, Codable, Sendable {
        case started
        case ended
    }
    
    public init(type: ExerciseMessageType, timestamp: Date = Date()) {
        self.type = type
        self.timestamp = timestamp
    }
}

extension ExerciseModeProvider {
    /// Handle incoming Watch message
    public func handleWatchMessage(_ message: ExerciseWatchMessage) {
        _lastMessageTime = message.timestamp
        switch message.type {
        case .started:
            _state = .active
        case .ended:
            _state = .inactive
        }
        persistState()
    }
}

// MARK: - Algorithm Integration

/// Extension for algorithm inputs to consider exercise mode
public struct ExerciseAdjustedTarget: Sendable {
    public let originalTarget: Double
    public let effectiveTarget: Double
    public let isExercising: Bool
    
    public init(originalTarget: Double, effectiveTarget: Double, isExercising: Bool) {
        self.originalTarget = originalTarget
        self.effectiveTarget = effectiveTarget
        self.isExercising = isExercising
    }
}
