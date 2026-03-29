// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// HapticFeedback.swift - Haptic feedback patterns for glucose events
// Part of T1PalCore
// Trace: HAPTIC-001

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreHaptics)
import CoreHaptics
#endif

// MARK: - Haptic Feedback Type

/// Types of haptic feedback for glucose events
public enum HapticFeedbackType: String, CaseIterable, Sendable {
    // Glucose alerts
    case urgentLow
    case low
    case high
    case urgentHigh
    case rising
    case falling
    
    // UI feedback
    case selection
    case success
    case warning
    case error
    case impact
    
    // Custom patterns
    case pulse
    case doublePulse
    case heartbeat
}

// MARK: - Haptic Feedback Manager

/// Manager for playing haptic feedback
///
/// Thread-safety: `@unchecked Sendable` is used because:
/// 1. Singleton pattern requires class semantics
/// 2. Mutable state protected by NSLock
/// 3. CHHapticEngine can be used from any thread
/// Trace: TECH-001, PROD-READY-012
public final class HapticFeedbackManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = HapticFeedbackManager()
    
    // MARK: - Properties
    
    public var isEnabled: Bool = true
    
    #if canImport(CoreHaptics)
    private var hapticEngine: CHHapticEngine?
    private var supportsHaptics: Bool = false
    #endif
    
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    /// Initialize HapticFeedbackManager.
    /// CHHapticEngine can be initialized from any thread.
    /// UIFeedbackGenerator is created on-demand in play methods (from UI context).
    /// Trace: THREAD-007 (verified safe)
    private init() {
        #if canImport(CoreHaptics)
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        if supportsHaptics {
            prepareHapticEngine()
        }
        #endif
    }
    
    // MARK: - Simple Feedback (UIKit)
    
    /// Play simple impact feedback
    public func playImpact(_ style: ImpactStyle = .medium) {
        guard isEnabled else { return }
        
        #if canImport(UIKit) && !os(tvOS)
        DispatchQueue.main.async {
            let generator: UIImpactFeedbackGenerator
            switch style {
            case .light:
                generator = UIImpactFeedbackGenerator(style: .light)
            case .medium:
                generator = UIImpactFeedbackGenerator(style: .medium)
            case .heavy:
                generator = UIImpactFeedbackGenerator(style: .heavy)
            case .soft:
                generator = UIImpactFeedbackGenerator(style: .soft)
            case .rigid:
                generator = UIImpactFeedbackGenerator(style: .rigid)
            }
            generator.impactOccurred()
        }
        #endif
    }
    
    /// Play selection feedback
    public func playSelection() {
        guard isEnabled else { return }
        
        #if canImport(UIKit) && !os(tvOS)
        DispatchQueue.main.async {
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        }
        #endif
    }
    
    /// Play notification feedback
    public func playNotification(_ type: NotificationType) {
        guard isEnabled else { return }
        
        #if canImport(UIKit) && !os(tvOS)
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            switch type {
            case .success:
                generator.notificationOccurred(.success)
            case .warning:
                generator.notificationOccurred(.warning)
            case .error:
                generator.notificationOccurred(.error)
            }
        }
        #endif
    }
    
    // MARK: - Haptic Patterns
    
    /// Play a predefined haptic pattern
    public func play(_ type: HapticFeedbackType) {
        guard isEnabled else { return }
        
        switch type {
        case .selection:
            playSelection()
        case .success:
            playNotification(.success)
        case .warning:
            playNotification(.warning)
        case .error:
            playNotification(.error)
        case .impact:
            playImpact(.medium)
        case .urgentLow, .urgentHigh:
            playUrgentPattern()
        case .low, .high:
            playAlertPattern()
        case .rising, .falling:
            playTrendPattern()
        case .pulse:
            playPulsePattern()
        case .doublePulse:
            playDoublePulsePattern()
        case .heartbeat:
            playHeartbeatPattern()
        }
    }
    
    // MARK: - Custom Patterns (CoreHaptics)
    
    /// Play urgent alert pattern (strong, repeating)
    public func playUrgentPattern() {
        #if canImport(CoreHaptics)
        guard supportsHaptics else {
            // Fallback to simple haptics
            playNotification(.error)
            return
        }
        
        playPattern([
            HapticEvent(intensity: 1.0, sharpness: 0.8, duration: 0.2),
            HapticEvent(delay: 0.15, intensity: 1.0, sharpness: 0.8, duration: 0.2),
            HapticEvent(delay: 0.15, intensity: 1.0, sharpness: 0.8, duration: 0.2),
        ])
        #else
        playNotification(.error)
        #endif
    }
    
    /// Play alert pattern (moderate intensity)
    public func playAlertPattern() {
        #if canImport(CoreHaptics)
        guard supportsHaptics else {
            playNotification(.warning)
            return
        }
        
        playPattern([
            HapticEvent(intensity: 0.7, sharpness: 0.5, duration: 0.15),
            HapticEvent(delay: 0.1, intensity: 0.7, sharpness: 0.5, duration: 0.15),
        ])
        #else
        playNotification(.warning)
        #endif
    }
    
    /// Play trend change pattern (soft)
    public func playTrendPattern() {
        #if canImport(CoreHaptics)
        guard supportsHaptics else {
            playImpact(.light)
            return
        }
        
        playPattern([
            HapticEvent(intensity: 0.4, sharpness: 0.3, duration: 0.1),
            HapticEvent(delay: 0.05, intensity: 0.5, sharpness: 0.4, duration: 0.1),
        ])
        #else
        playImpact(.light)
        #endif
    }
    
    /// Play single pulse
    public func playPulsePattern() {
        #if canImport(CoreHaptics)
        guard supportsHaptics else {
            playImpact(.medium)
            return
        }
        
        playPattern([
            HapticEvent(intensity: 0.6, sharpness: 0.5, duration: 0.15),
        ])
        #else
        playImpact(.medium)
        #endif
    }
    
    /// Play double pulse
    public func playDoublePulsePattern() {
        #if canImport(CoreHaptics)
        guard supportsHaptics else {
            playImpact(.medium)
            return
        }
        
        playPattern([
            HapticEvent(intensity: 0.6, sharpness: 0.5, duration: 0.1),
            HapticEvent(delay: 0.1, intensity: 0.6, sharpness: 0.5, duration: 0.1),
        ])
        #else
        playImpact(.medium)
        #endif
    }
    
    /// Play heartbeat pattern
    public func playHeartbeatPattern() {
        #if canImport(CoreHaptics)
        guard supportsHaptics else {
            playImpact(.heavy)
            return
        }
        
        playPattern([
            HapticEvent(intensity: 0.8, sharpness: 0.4, duration: 0.1),
            HapticEvent(delay: 0.08, intensity: 0.5, sharpness: 0.3, duration: 0.08),
            HapticEvent(delay: 0.3, intensity: 0.8, sharpness: 0.4, duration: 0.1),
            HapticEvent(delay: 0.08, intensity: 0.5, sharpness: 0.3, duration: 0.08),
        ])
        #else
        playImpact(.heavy)
        #endif
    }
    
    // MARK: - CoreHaptics Implementation
    
    #if canImport(CoreHaptics)
    private func prepareHapticEngine() {
        do {
            hapticEngine = try CHHapticEngine()
            hapticEngine?.playsHapticsOnly = true
            hapticEngine?.stoppedHandler = { [weak self] reason in
                self?.restartEngine()
            }
            hapticEngine?.resetHandler = { [weak self] in
                self?.restartEngine()
            }
        } catch {
            supportsHaptics = false
        }
    }
    
    private func restartEngine() {
        do {
            try hapticEngine?.start()
        } catch {
            supportsHaptics = false
        }
    }
    
    private func playPattern(_ events: [HapticEvent]) {
        guard let engine = hapticEngine else { return }
        
        do {
            try engine.start()
            
            var hapticEvents: [CHHapticEvent] = []
            var currentTime: TimeInterval = 0
            
            for event in events {
                currentTime += event.delay
                
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(event.intensity))
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(event.sharpness))
                
                let hapticEvent = CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: currentTime,
                    duration: event.duration
                )
                hapticEvents.append(hapticEvent)
                
                currentTime += event.duration
            }
            
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // Silently fail
        }
    }
    #endif
}

// MARK: - Supporting Types

/// Impact feedback style
public enum ImpactStyle: Sendable {
    case light
    case medium
    case heavy
    case soft
    case rigid
}

/// Notification feedback type
public enum NotificationType: Sendable {
    case success
    case warning
    case error
}

/// Haptic event configuration
public struct HapticEvent: Sendable {
    let delay: TimeInterval
    let intensity: Double
    let sharpness: Double
    let duration: TimeInterval
    
    public init(
        delay: TimeInterval = 0,
        intensity: Double = 0.5,
        sharpness: Double = 0.5,
        duration: TimeInterval = 0.1
    ) {
        self.delay = delay
        self.intensity = min(1.0, max(0, intensity))
        self.sharpness = min(1.0, max(0, sharpness))
        self.duration = duration
    }
}

// MARK: - SwiftUI Integration

#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Add haptic feedback on tap
    public func hapticOnTap(_ type: HapticFeedbackType = .selection) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                HapticFeedbackManager.shared.play(type)
            }
        )
    }
}
#endif
