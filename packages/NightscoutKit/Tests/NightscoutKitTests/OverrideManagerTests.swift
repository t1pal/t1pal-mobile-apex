// SPDX-License-Identifier: MIT
// OverrideManagerTests.swift
// NightscoutKitTests
//
// Tests for override manager (CONTROL-004)

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - Override Preset Tests

@Suite("Override Preset")
struct OverridePresetTests {
    @Test("Create preset with all fields")
    func createPresetWithAllFields() {
        let preset = OverridePreset(
            name: "Test",
            symbol: "⚡",
            settings: OverrideSettings(targetRange: 120...140),
            defaultDuration: 3600
        )
        
        #expect(preset.name == "Test")
        #expect(preset.symbol == "⚡")
        #expect(preset.defaultDuration == 3600)
        #expect(preset.isEnabled == true)
    }
    
    @Test("Default presets exist")
    func defaultPresetsExist() {
        let defaults = OverridePreset.allDefaults
        
        #expect(defaults.count == 4)
        #expect(defaults.contains { $0.name == "Exercise" })
        #expect(defaults.contains { $0.name == "Pre-Meal" })
        #expect(defaults.contains { $0.name == "Sleep" })
        #expect(defaults.contains { $0.name == "Sick Day" })
    }
    
    @Test("Exercise preset has correct settings")
    func exercisePresetHasCorrectSettings() {
        let exercise = OverridePreset.exercise
        
        #expect(exercise.settings.targetRange == 140...160)
        #expect(exercise.settings.insulinSensitivityMultiplier == 1.5)
        #expect(exercise.settings.basalMultiplier == 0.5)
        #expect(exercise.defaultDuration == 3600)
    }
    
    @Test("Pre-meal preset lowers target")
    func preMealPresetLowersTarget() {
        let preMeal = OverridePreset.preMeal
        
        #expect(preMeal.settings.targetRange?.lowerBound == 80)
        #expect(preMeal.settings.targetRange?.upperBound == 100)
    }
    
    @Test("Sick day preset is indefinite")
    func sickDayPresetIsIndefinite() {
        let sick = OverridePreset.sick
        
        #expect(sick.defaultDuration == nil)
        #expect(sick.settings.basalMultiplier == 1.2)
    }
}

// MARK: - Override Settings Tests

@Suite("Override Settings")
struct OverrideSettingsTests {
    @Test("Empty settings has no modifications")
    func emptySettingsHasNoModifications() {
        let settings = OverrideSettings()
        
        #expect(settings.hasModifications == false)
    }
    
    @Test("Settings with target has modifications")
    func settingsWithTargetHasModifications() {
        let settings = OverrideSettings(targetRange: 100...120)
        
        #expect(settings.hasModifications == true)
    }
    
    @Test("Settings with multiplier has modifications")
    func settingsWithMultiplierHasModifications() {
        let settings = OverrideSettings(insulinSensitivityMultiplier: 1.2)
        
        #expect(settings.hasModifications == true)
    }
    
    @Test("Merge settings - other takes precedence")
    func mergeSettingsOtherTakesPrecedence() {
        let base = OverrideSettings(
            targetRange: 100...120,
            insulinSensitivityMultiplier: 1.0
        )
        let other = OverrideSettings(
            targetRange: 140...160
        )
        
        let merged = base.merged(with: other)
        
        #expect(merged.targetRange == 140...160)
        #expect(merged.insulinSensitivityMultiplier == 1.0)
    }
    
    @Test("Merge preserves unset values from base")
    func mergePreservesUnsetValuesFromBase() {
        let base = OverrideSettings(
            basalMultiplier: 0.8
        )
        let other = OverrideSettings(
            targetRange: 100...120
        )
        
        let merged = base.merged(with: other)
        
        #expect(merged.targetRange == 100...120)
        #expect(merged.basalMultiplier == 0.8)
    }
}

// MARK: - Active Override Tests

@Suite("Active Override")
struct ActiveOverrideTests {
    @Test("Create active override")
    func createActiveOverride() {
        let override = ActiveOverride(
            name: "Test",
            settings: OverrideSettings(targetRange: 120...140)
        )
        
        #expect(override.name == "Test")
        #expect(override.source == .local)
        #expect(override.syncedToControlPlane == false)
        #expect(override.isExpired == false)
    }
    
    @Test("Override with expiration")
    func overrideWithExpiration() {
        let future = Date().addingTimeInterval(3600)
        let override = ActiveOverride(
            name: "Test",
            settings: OverrideSettings(),
            expiresAt: future
        )
        
        #expect(override.isExpired == false)
        #expect(override.isActive == true)
        #expect(override.remainingDuration != nil)
        #expect(override.remainingDuration! > 3500)
    }
    
    @Test("Expired override detection")
    func expiredOverrideDetection() {
        let past = Date().addingTimeInterval(-100)
        let override = ActiveOverride(
            name: "Expired",
            settings: OverrideSettings(),
            expiresAt: past
        )
        
        #expect(override.isExpired == true)
        #expect(override.isActive == false)
        #expect(override.remainingDuration == 0)
    }
    
    @Test("Indefinite override never expires")
    func indefiniteOverrideNeverExpires() {
        let override = ActiveOverride(
            name: "Indefinite",
            settings: OverrideSettings(),
            expiresAt: nil
        )
        
        #expect(override.isExpired == false)
        #expect(override.remainingDuration == nil)
    }
    
    @Test("Active duration calculation")
    func activeDurationCalculation() {
        let past = Date().addingTimeInterval(-300)
        let override = ActiveOverride(
            name: "Test",
            settings: OverrideSettings(),
            activatedAt: past
        )
        
        #expect(override.activeDuration >= 300)
        #expect(override.activeDuration < 310)
    }
    
    @Test("With sync status")
    func withSyncStatus() {
        let override = ActiveOverride(
            name: "Test",
            settings: OverrideSettings()
        )
        
        let synced = override.withSyncStatus(true)
        
        #expect(synced.syncedToControlPlane == true)
        #expect(synced.name == override.name)
        #expect(synced.id == override.id)
    }
}

// MARK: - Override Source Tests

@Suite("Override Source")
struct OverrideSourceTests {
    @Test("All sources have display names")
    func allSourcesHaveDisplayNames() {
        for source in OverrideSource.allCases {
            #expect(!source.displayName.isEmpty)
        }
    }
    
    @Test("Source count")
    func sourceCount() {
        #expect(OverrideSource.allCases.count == 4)
    }
}

// MARK: - Override History Entry Tests

@Suite("Override History Entry")
struct OverrideHistoryEntryTests {
    @Test("Create history entry")
    func createHistoryEntry() {
        let override = ActiveOverride(
            name: "Test",
            settings: OverrideSettings(),
            activatedAt: Date().addingTimeInterval(-600)
        )
        
        let entry = OverrideHistoryEntry(
            override: override,
            deactivationReason: .userCancelled
        )
        
        #expect(entry.deactivationReason == .userCancelled)
        #expect(entry.totalDuration >= 600)
    }
}

// MARK: - Deactivation Reason Tests

@Suite("Deactivation Reason")
struct DeactivationReasonTests {
    @Test("All reasons have display names")
    func allReasonsHaveDisplayNames() {
        for reason in DeactivationReason.allCases {
            #expect(!reason.displayName.isEmpty)
        }
    }
    
    @Test("Reason count")
    func reasonCount() {
        #expect(DeactivationReason.allCases.count == 5)
    }
}

// MARK: - Override Activation Result Tests

@Suite("Override Activation Result")
struct OverrideActivationResultTests {
    @Test("Success result")
    func successResult() {
        let override = ActiveOverride(name: "Test", settings: OverrideSettings())
        let result = OverrideActivationResult.success(override)
        
        #expect(result.success == true)
        #expect(result.activeOverride != nil)
        #expect(result.error == nil)
    }
    
    @Test("Failure result")
    func failureResult() {
        let result = OverrideActivationResult.failure("Test error")
        
        #expect(result.success == false)
        #expect(result.activeOverride == nil)
        #expect(result.error == "Test error")
    }
    
    @Test("Success with previous override")
    func successWithPreviousOverride() {
        let current = ActiveOverride(name: "New", settings: OverrideSettings())
        let previous = ActiveOverride(name: "Old", settings: OverrideSettings())
        
        let result = OverrideActivationResult.success(current, replacing: previous)
        
        #expect(result.success == true)
        #expect(result.activeOverride?.name == "New")
        #expect(result.previousOverride?.name == "Old")
    }
}

// MARK: - Override Manager Tests

@Suite("Override Manager")
struct OverrideManagerTests {
    @Test("Get default presets")
    func getDefaultPresets() async {
        let manager = OverrideManager()
        let presets = await manager.getPresets()
        
        #expect(presets.count == 4)
    }
    
    @Test("Add custom preset")
    func addCustomPreset() async {
        let manager = OverrideManager(presets: [])
        let preset = OverridePreset(
            name: "Custom",
            settings: OverrideSettings(targetRange: 100...120)
        )
        
        await manager.addPreset(preset)
        
        let presets = await manager.getPresets()
        #expect(presets.count == 1)
        #expect(presets[0].name == "Custom")
    }
    
    @Test("Remove preset")
    func removePreset() async {
        let manager = OverrideManager()
        let presets = await manager.getPresets()
        let firstId = presets[0].id
        
        await manager.removePreset(id: firstId)
        
        let remaining = await manager.getPresets()
        #expect(remaining.count == 3)
    }
    
    @Test("Activate preset override")
    func activatePresetOverride() async {
        let manager = OverrideManager()
        let result = await manager.activate(preset: .exercise)
        
        #expect(result.success == true)
        #expect(result.activeOverride?.name == "Exercise")
        
        let active = await manager.getActiveOverride()
        #expect(active != nil)
    }
    
    @Test("Activate custom override")
    func activateCustomOverride() async {
        let manager = OverrideManager()
        let result = await manager.activateCustom(
            name: "Custom",
            settings: OverrideSettings(targetRange: 150...170),
            duration: 1800
        )
        
        #expect(result.success == true)
        #expect(result.activeOverride?.name == "Custom")
        #expect(result.activeOverride?.settings.targetRange == 150...170)
    }
    
    @Test("Activate replaces previous override")
    func activateReplacesPreviousOverride() async {
        let manager = OverrideManager()
        
        _ = await manager.activate(preset: .exercise)
        let result = await manager.activate(preset: .sleep)
        
        #expect(result.previousOverride?.name == "Exercise")
        #expect(result.activeOverride?.name == "Sleep")
        
        let history = await manager.getHistory()
        #expect(history.count == 1)
        #expect(history[0].deactivationReason == .replacedByNew)
    }
    
    @Test("Deactivate override")
    func deactivateOverride() async {
        let manager = OverrideManager()
        _ = await manager.activate(preset: .exercise)
        
        let deactivated = await manager.deactivate()
        
        #expect(deactivated?.name == "Exercise")
        
        let active = await manager.getActiveOverride()
        #expect(active == nil)
        
        let history = await manager.getHistory()
        #expect(history.count == 1)
        #expect(history[0].deactivationReason == .userCancelled)
    }
    
    @Test("Deactivate returns nil when no override")
    func deactivateReturnsNilWhenNoOverride() async {
        let manager = OverrideManager()
        let deactivated = await manager.deactivate()
        
        #expect(deactivated == nil)
    }
    
    @Test("Has active override")
    func hasActiveOverride() async {
        let manager = OverrideManager()
        
        #expect(await manager.hasActiveOverride() == false)
        
        _ = await manager.activate(preset: .exercise)
        
        #expect(await manager.hasActiveOverride() == true)
    }
    
    @Test("Get recent history")
    func getRecentHistory() async {
        let manager = OverrideManager()
        
        _ = await manager.activate(preset: .exercise)
        _ = await manager.activate(preset: .sleep)
        _ = await manager.activate(preset: .preMeal)
        
        let recent = await manager.getRecentHistory(count: 2)
        
        #expect(recent.count == 2)
    }
    
    @Test("Clear history")
    func clearHistory() async {
        let manager = OverrideManager()
        _ = await manager.activate(preset: .exercise)
        _ = await manager.deactivate()
        
        await manager.clearHistory()
        
        let history = await manager.getHistory()
        #expect(history.isEmpty)
    }
    
    @Test("Pending sync events created on activation")
    func pendingSyncEventsCreatedOnActivation() async {
        let manager = OverrideManager()
        _ = await manager.activate(preset: .exercise)
        
        let pending = await manager.getPendingSyncEvents()
        
        #expect(pending.count == 1)
        #expect(pending[0].overrideName == "Exercise")
    }
    
    @Test("Clear pending sync events")
    func clearPendingSyncEvents() async {
        let manager = OverrideManager()
        _ = await manager.activate(preset: .exercise)
        
        await manager.clearPendingSyncEvents()
        
        let pending = await manager.getPendingSyncEvents()
        #expect(pending.isEmpty)
        
        let active = await manager.getActiveOverride()
        #expect(active?.syncedToControlPlane == true)
    }
    
    @Test("Apply remote override")
    func applyRemoteOverride() async {
        let manager = OverrideManager()
        
        let event = OverrideInstanceEvent(
            source: .caregiver,
            overrideName: "Remote Override",
            duration: 3600,
            targetRange: 130...150
        )
        
        let result = await manager.applyRemoteOverride(event: event)
        
        #expect(result.success == true)
        #expect(result.activeOverride?.name == "Remote Override")
        #expect(result.activeOverride?.source == .caregiver)
        #expect(result.activeOverride?.syncedToControlPlane == true)
    }
    
    @Test("Apply remote cancellation")
    func applyRemoteCancellation() async {
        let manager = OverrideManager()
        _ = await manager.activate(preset: .exercise)
        
        let event = OverrideCancelEvent(
            source: .caregiver,
            overrideInstanceId: UUID()
        )
        
        let cancelled = await manager.applyRemoteCancellation(event: event)
        
        #expect(cancelled != nil)
        
        let active = await manager.getActiveOverride()
        #expect(active == nil)
        
        let history = await manager.getHistory()
        #expect(history.last?.deactivationReason == .remoteCancelled)
    }
}

// MARK: - Override Logic Tests

@Suite("Override Logic")
struct OverrideLogicTests {
    let logic = OverrideLogic()
    
    @Test("Apply target range")
    func applyTargetRange() {
        let base: ClosedRange<Double> = 100...120
        let override = OverrideSettings(targetRange: 140...160)
        
        let result = logic.applyTarget(base: base, override: override)
        
        #expect(result == 140...160)
    }
    
    @Test("Apply target - no override uses base")
    func applyTargetNoOverrideUsesBase() {
        let base: ClosedRange<Double> = 100...120
        let override = OverrideSettings()
        
        let result = logic.applyTarget(base: base, override: override)
        
        #expect(result == 100...120)
    }
    
    @Test("Apply ISF multiplier")
    func applyISFMultiplier() {
        let override = OverrideSettings(insulinSensitivityMultiplier: 1.5)
        
        let result = logic.applyISF(base: 50, override: override)
        
        #expect(result == 75)
    }
    
    @Test("Apply carb ratio multiplier")
    func applyCarbRatioMultiplier() {
        let override = OverrideSettings(carbRatioMultiplier: 0.8)
        
        let result = logic.applyCarbRatio(base: 10, override: override)
        
        #expect(result == 8)
    }
    
    @Test("Apply basal multiplier")
    func applyBasalMultiplier() {
        let override = OverrideSettings(basalMultiplier: 0.5)
        
        let result = logic.applyBasal(base: 1.0, override: override)
        
        #expect(result == 0.5)
    }
    
    @Test("Format remaining time - minutes")
    func formatRemainingTimeMinutes() {
        let formatted = logic.formatRemainingTime(1800)
        #expect(formatted == "30 min")
    }
    
    @Test("Format remaining time - hours")
    func formatRemainingTimeHours() {
        let formatted = logic.formatRemainingTime(7200)
        #expect(formatted == "2h")
    }
    
    @Test("Format remaining time - hours and minutes")
    func formatRemainingTimeHoursAndMinutes() {
        let formatted = logic.formatRemainingTime(5400)
        #expect(formatted == "1h 30m")
    }
    
    @Test("Format remaining time - less than minute")
    func formatRemainingTimeLessThanMinute() {
        let formatted = logic.formatRemainingTime(45)
        #expect(formatted == "<1 min")
    }
}
