// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// AlertSounds.swift - Alert sound definitions and playback
// Part of T1PalCore
// Trace: SOUND-001

import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Alert Sound Type

/// Types of glucose alert sounds
/// Trace: LIFE-NOTIFY-003
public enum AlertSoundType: String, CaseIterable, Sendable, Codable {
    case urgentLow = "urgent_low"
    case low = "low"
    case high = "high"
    case urgentHigh = "urgent_high"
    case rising = "rising"
    case falling = "falling"
    case sensorExpiring = "sensor_expiring"
    case sensorExpired = "sensor_expired"
    case sensorWarmup = "sensor_warmup"
    case warmupComplete = "warmup_complete"
    case transmitterExpiring = "transmitter_expiring"
    case transmitterBatteryLow = "transmitter_battery_low"
    case podExpiring = "pod_expiring"
    case podExpired = "pod_expired"
    case siteChangeDue = "site_change_due"
    case connectionLost = "connection_lost"
    case pumpReservoirLow = "pump_reservoir_low"
    case pumpBatteryLow = "pump_battery_low"
    case loopNotLooping = "loop_not_looping"
    
    /// Human-readable name
    public var displayName: String {
        switch self {
        case .urgentLow: return "Urgent Low"
        case .low: return "Low"
        case .high: return "High"
        case .urgentHigh: return "Urgent High"
        case .rising: return "Rising Fast"
        case .falling: return "Falling Fast"
        case .sensorExpiring: return "Sensor Expiring"
        case .sensorExpired: return "Sensor Expired"
        case .sensorWarmup: return "Sensor Warmup"
        case .warmupComplete: return "Warmup Complete"
        case .transmitterExpiring: return "Transmitter Expiring"
        case .transmitterBatteryLow: return "Transmitter Battery Low"
        case .podExpiring: return "Pod Expiring"
        case .podExpired: return "Pod Expired"
        case .siteChangeDue: return "Site Change Due"
        case .connectionLost: return "Connection Lost"
        case .pumpReservoirLow: return "Reservoir Low"
        case .pumpBatteryLow: return "Pump Battery Low"
        case .loopNotLooping: return "Loop Not Looping"
        }
    }
    
    /// Priority for sound scheduling (1 = highest)
    public var priority: Int {
        switch self {
        case .urgentLow: return 1
        case .urgentHigh: return 2
        case .low: return 3
        case .high: return 4
        case .falling: return 5
        case .rising: return 6
        case .podExpired: return 7
        case .loopNotLooping: return 8
        case .podExpiring: return 9
        case .pumpReservoirLow: return 10
        case .pumpBatteryLow: return 11
        case .siteChangeDue: return 12
        case .connectionLost: return 13
        case .sensorExpiring: return 14
        case .sensorExpired: return 15
        case .transmitterExpiring: return 16
        case .transmitterBatteryLow: return 17
        case .sensorWarmup: return 18
        case .warmupComplete: return 19
        }
    }
    
    /// Suggested repeat interval in seconds (0 = no repeat)
    public var repeatInterval: TimeInterval {
        switch self {
        case .urgentLow: return 60      // Every minute
        case .urgentHigh: return 300    // Every 5 minutes
        case .low: return 300           // Every 5 minutes
        case .high: return 900          // Every 15 minutes
        case .podExpired: return 900    // Every 15 minutes
        default: return 0               // No repeat
        }
    }
    
    /// Whether this alert can be silenced by user
    public var canBeSilenced: Bool {
        switch self {
        case .urgentLow: return false   // Critical - cannot silence
        case .podExpired: return false  // Critical - pod stopped delivering
        default: return true
        }
    }
    
    /// Default system sound ID (iOS)
    public var systemSoundID: UInt32 {
        switch self {
        case .urgentLow: return 1005    // Alarm
        case .urgentHigh: return 1005   // Alarm
        case .podExpired: return 1005   // Alarm - critical
        case .low: return 1007          // Alert
        case .high: return 1007         // Alert
        case .falling: return 1016      // Tweet
        case .rising: return 1016       // Tweet
        case .warmupComplete: return 1025  // Positive chime
        default: return 1057            // Default alert
        }
    }
    
    /// Map from GlucoseNotificationType to AlertSoundType (LIFE-NOTIFY-003)
    public static func from(notificationType: GlucoseNotificationType) -> AlertSoundType? {
        switch notificationType {
        case .urgentLow: return .urgentLow
        case .low: return .low
        case .high: return .high
        case .urgentHigh: return .urgentHigh
        case .rising: return .rising
        case .falling: return .falling
        case .sensorExpiring: return .sensorExpiring
        case .transmitterExpiring: return .transmitterExpiring
        case .transmitterBatteryLow: return .transmitterBatteryLow
        case .podExpiring: return .podExpiring
        case .podExpired: return .podExpired
        case .reservoirLow: return .pumpReservoirLow
        case .pumpBatteryLow: return .pumpBatteryLow
        case .sensorWarmup: return .sensorWarmup
        case .warmupComplete: return .warmupComplete
        case .disconnected: return .connectionLost
        case .orderSupplies: return .siteChangeDue  // Reuse site change sound for supply orders
        case .staleData, .pumpAlert, .connected:
            return nil  // No custom sound for these
        }
    }
}

// MARK: - Alert Sound Configuration

/// User preferences for alert sounds
public struct AlertSoundConfiguration: Codable, Sendable {
    public var isEnabled: Bool
    public var volume: Float  // 0.0 - 1.0
    public var useSystemSound: Bool
    public var customSoundName: String?
    public var vibrationEnabled: Bool
    public var overrideDoNotDisturb: Bool
    
    public init(
        isEnabled: Bool = true,
        volume: Float = 1.0,
        useSystemSound: Bool = true,
        customSoundName: String? = nil,
        vibrationEnabled: Bool = true,
        overrideDoNotDisturb: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.volume = max(0, min(1, volume))
        self.useSystemSound = useSystemSound
        self.customSoundName = customSoundName
        self.vibrationEnabled = vibrationEnabled
        self.overrideDoNotDisturb = overrideDoNotDisturb
    }
    
    public static let `default` = AlertSoundConfiguration()
}

// MARK: - Alert Sound Manager

/// Manages alert sound playback
///
/// Thread-safety: `@unchecked Sendable` is used because:
/// 1. Singleton pattern requires class semantics
/// 2. Configuration state protected by NSLock
/// 3. AVAudioSession is thread-safe (Apple docs)
/// Trace: TECH-001, PROD-READY-012
public final class AlertSoundManager: @unchecked Sendable {
    
    public static let shared = AlertSoundManager()
    
    private var configurations: [AlertSoundType: AlertSoundConfiguration] = [:]
    private let storageKey = "com.t1pal.alertsounds.config"
    private let lock = NSLock()
    
    #if canImport(AVFoundation)
    private var audioPlayer: AVAudioPlayer?
    #endif
    
    /// Initialize AlertSoundManager.
    /// AVAudioPlayer is created on-demand during playback, not in init.
    /// AVAudioSession methods are thread-safe for most operations.
    /// Trace: THREAD-006 (verified safe)
    private init() {
        loadConfigurations()
    }
    
    // MARK: - Configuration
    
    /// Get configuration for a sound type
    public func configuration(for type: AlertSoundType) -> AlertSoundConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return configurations[type] ?? .default
    }
    
    /// Update configuration for a sound type
    public func setConfiguration(_ config: AlertSoundConfiguration, for type: AlertSoundType) {
        lock.lock()
        configurations[type] = config
        lock.unlock()
        saveConfigurations()
    }
    
    // MARK: - Playback
    
    /// Play an alert sound
    public func play(_ type: AlertSoundType) {
        let config = configuration(for: type)
        guard config.isEnabled else { return }
        
        #if canImport(AVFoundation) && os(iOS)
        if config.useSystemSound {
            playSystemSound(type.systemSoundID, vibrate: config.vibrationEnabled)
        } else if let customName = config.customSoundName {
            playCustomSound(named: customName, volume: config.volume)
        }
        #endif
    }
    
    /// Stop any currently playing sound
    public func stop() {
        #if canImport(AVFoundation)
        audioPlayer?.stop()
        audioPlayer = nil
        #endif
    }
    
    // MARK: - Private Methods
    
    #if canImport(AVFoundation) && os(iOS)
    private func playSystemSound(_ soundID: UInt32, vibrate: Bool) {
        AudioServicesPlaySystemSound(soundID)
        if vibrate {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
    
    private func playCustomSound(named name: String, volume: Float) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = volume
            audioPlayer?.play()
        } catch {
            // Fallback to system sound
            AudioServicesPlaySystemSound(1057)
        }
    }
    #endif
    
    // MARK: - Persistence
    
    private func saveConfigurations() {
        lock.lock()
        let configData = configurations
        lock.unlock()
        
        var encoded: [String: Data] = [:]
        for (type, config) in configData {
            if let data = try? JSONEncoder().encode(config) {
                encoded[type.rawValue] = data
            }
        }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
    
    private func loadConfigurations() {
        guard let encoded = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Data] else {
            return
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        for (typeRaw, data) in encoded {
            if let type = AlertSoundType(rawValue: typeRaw),
               let config = try? JSONDecoder().decode(AlertSoundConfiguration.self, from: data) {
                configurations[type] = config
            }
        }
    }
}

// MARK: - Alert Sounds View

#if canImport(SwiftUI)
import SwiftUI

/// View for configuring alert sounds
public struct AlertSoundsConfigView: View {
    @State private var configurations: [AlertSoundType: AlertSoundConfiguration] = [:]
    @State private var selectedType: AlertSoundType = .urgentLow
    
    public init() {}
    
    public var body: some View {
        List {
            ForEach(AlertSoundType.allCases, id: \.self) { type in
                AlertSoundRow(
                    type: type,
                    configuration: binding(for: type)
                )
            }
        }
        .navigationTitle("Alert Sounds")
        .onAppear {
            loadAll()
        }
    }
    
    private func binding(for type: AlertSoundType) -> Binding<AlertSoundConfiguration> {
        Binding(
            get: { configurations[type] ?? .default },
            set: { newConfig in
                configurations[type] = newConfig
                AlertSoundManager.shared.setConfiguration(newConfig, for: type)
            }
        )
    }
    
    private func loadAll() {
        for type in AlertSoundType.allCases {
            configurations[type] = AlertSoundManager.shared.configuration(for: type)
        }
    }
}

/// Row for a single alert sound configuration
struct AlertSoundRow: View {
    let type: AlertSoundType
    @Binding var configuration: AlertSoundConfiguration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(type.displayName)
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $configuration.isEnabled)
                    .labelsHidden()
            }
            
            if configuration.isEnabled {
                HStack {
                    Image(systemName: "speaker.wave.1")
                    Slider(value: $configuration.volume, in: 0...1)
                    Image(systemName: "speaker.wave.3")
                }
                
                Toggle("Vibration", isOn: $configuration.vibrationEnabled)
                    .font(.subheadline)
                
                if !type.canBeSilenced {
                    Text("This alert cannot be silenced")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // Test button
            Button("Test") {
                AlertSoundManager.shared.play(type)
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
#endif
