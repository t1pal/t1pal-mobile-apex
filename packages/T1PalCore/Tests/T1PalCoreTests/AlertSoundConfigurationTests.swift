// SPDX-License-Identifier: MIT
//
// AlertSoundConfigurationTests.swift
// T1PalCoreTests
//
// Tests for notification sound customization (LIFE-NOTIFY-003)

import Testing
import Foundation
@testable import T1PalCore

@Suite("Alert Sound Configuration Tests")
struct AlertSoundConfigurationTests {
    
    // MARK: - AlertSoundType Tests
    
    @Test("All alert sound types have display names")
    func allTypesHaveDisplayNames() {
        for type in AlertSoundType.allCases {
            #expect(!type.displayName.isEmpty, "\(type) should have a display name")
        }
    }
    
    @Test("All alert sound types have priorities")
    func allTypesHavePriorities() {
        let priorities = AlertSoundType.allCases.map { $0.priority }
        #expect(priorities.count == AlertSoundType.allCases.count)
        // Higher priority = lower number
        #expect(AlertSoundType.urgentLow.priority < AlertSoundType.warmupComplete.priority)
    }
    
    @Test("Critical alerts cannot be silenced")
    func criticalAlertsCannotBeSilenced() {
        #expect(!AlertSoundType.urgentLow.canBeSilenced, "Urgent low cannot be silenced")
        #expect(!AlertSoundType.podExpired.canBeSilenced, "Pod expired cannot be silenced")
    }
    
    @Test("Non-critical alerts can be silenced")
    func nonCriticalAlertsCanBeSilenced() {
        #expect(AlertSoundType.sensorExpiring.canBeSilenced)
        #expect(AlertSoundType.warmupComplete.canBeSilenced)
        #expect(AlertSoundType.transmitterExpiring.canBeSilenced)
    }
    
    @Test("Lifecycle sound types are present")
    func lifecycleSoundTypesPresent() {
        // Pod lifecycle
        #expect(AlertSoundType.allCases.contains(.podExpiring))
        #expect(AlertSoundType.allCases.contains(.podExpired))
        
        // Sensor lifecycle
        #expect(AlertSoundType.allCases.contains(.sensorExpiring))
        #expect(AlertSoundType.allCases.contains(.sensorWarmup))
        #expect(AlertSoundType.allCases.contains(.warmupComplete))
        
        // Transmitter lifecycle
        #expect(AlertSoundType.allCases.contains(.transmitterExpiring))
        #expect(AlertSoundType.allCases.contains(.transmitterBatteryLow))
        
        // Site change
        #expect(AlertSoundType.allCases.contains(.siteChangeDue))
    }
    
    // MARK: - AlertSoundConfiguration Tests
    
    @Test("Default configuration is enabled")
    func defaultConfigIsEnabled() {
        let config = AlertSoundConfiguration.default
        #expect(config.isEnabled)
        #expect(config.volume == 1.0)
        #expect(config.useSystemSound)
        #expect(config.vibrationEnabled)
    }
    
    @Test("Configuration volume is clamped")
    func volumeIsClamped() {
        let highConfig = AlertSoundConfiguration(volume: 1.5)
        #expect(highConfig.volume == 1.0)
        
        let lowConfig = AlertSoundConfiguration(volume: -0.5)
        #expect(lowConfig.volume == 0.0)
    }
    
    @Test("Custom sound name can be set")
    func customSoundNameCanBeSet() {
        let config = AlertSoundConfiguration(
            useSystemSound: false,
            customSoundName: "my_custom_alert.wav"
        )
        #expect(config.customSoundName == "my_custom_alert.wav")
        #expect(!config.useSystemSound)
    }
    
    @Test("Configuration is Codable")
    func configurationIsCodable() throws {
        let config = AlertSoundConfiguration(
            isEnabled: true,
            volume: 0.8,
            useSystemSound: false,
            customSoundName: "test.wav",
            vibrationEnabled: false,
            overrideDoNotDisturb: true
        )
        
        let encoded = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AlertSoundConfiguration.self, from: encoded)
        
        #expect(decoded.isEnabled == config.isEnabled)
        #expect(decoded.volume == config.volume)
        #expect(decoded.useSystemSound == config.useSystemSound)
        #expect(decoded.customSoundName == config.customSoundName)
        #expect(decoded.vibrationEnabled == config.vibrationEnabled)
        #expect(decoded.overrideDoNotDisturb == config.overrideDoNotDisturb)
    }
    
    // MARK: - Notification Type Mapping Tests
    
    @Test("Glucose notification types map to alert sound types")
    func glucoseNotificationTypesMap() {
        #expect(AlertSoundType.from(notificationType: .urgentLow) == .urgentLow)
        #expect(AlertSoundType.from(notificationType: .low) == .low)
        #expect(AlertSoundType.from(notificationType: .high) == .high)
        #expect(AlertSoundType.from(notificationType: .urgentHigh) == .urgentHigh)
    }
    
    @Test("Lifecycle notification types map to alert sound types")
    func lifecycleNotificationTypesMap() {
        #expect(AlertSoundType.from(notificationType: .sensorExpiring) == .sensorExpiring)
        #expect(AlertSoundType.from(notificationType: .transmitterExpiring) == .transmitterExpiring)
        #expect(AlertSoundType.from(notificationType: .transmitterBatteryLow) == .transmitterBatteryLow)
        #expect(AlertSoundType.from(notificationType: .podExpiring) == .podExpiring)
        #expect(AlertSoundType.from(notificationType: .podExpired) == .podExpired)
        #expect(AlertSoundType.from(notificationType: .reservoirLow) == .pumpReservoirLow)
        #expect(AlertSoundType.from(notificationType: .pumpBatteryLow) == .pumpBatteryLow)
        #expect(AlertSoundType.from(notificationType: .sensorWarmup) == .sensorWarmup)
        #expect(AlertSoundType.from(notificationType: .warmupComplete) == .warmupComplete)
    }
    
    @Test("Non-sound notification types return nil")
    func nonSoundNotificationTypesReturnNil() {
        #expect(AlertSoundType.from(notificationType: .staleData) == nil)
        #expect(AlertSoundType.from(notificationType: .pumpAlert) == nil)
        #expect(AlertSoundType.from(notificationType: .connected) == nil)
    }
    
    @Test("Disconnected maps to connection lost")
    func disconnectedMapsToConnectionLost() {
        #expect(AlertSoundType.from(notificationType: .disconnected) == .connectionLost)
    }
    
    // MARK: - AlertSoundManager Tests
    
    @Test("Manager returns default configuration for unconfigured type")
    func managerReturnsDefaultConfig() {
        let manager = AlertSoundManager.shared
        let config = manager.configuration(for: .siteChangeDue)
        #expect(config.isEnabled)
        #expect(config.volume == 1.0)
    }
    
    @Test("Manager persists configuration changes")
    func managerPersistsConfig() {
        let manager = AlertSoundManager.shared
        let customConfig = AlertSoundConfiguration(
            isEnabled: true,
            volume: 0.5,
            useSystemSound: false,
            customSoundName: "test_persistence.wav"
        )
        
        manager.setConfiguration(customConfig, for: .transmitterExpiring)
        
        let retrieved = manager.configuration(for: .transmitterExpiring)
        #expect(retrieved.volume == 0.5)
        #expect(retrieved.customSoundName == "test_persistence.wav")
        
        // Clean up
        manager.setConfiguration(.default, for: .transmitterExpiring)
    }
}
