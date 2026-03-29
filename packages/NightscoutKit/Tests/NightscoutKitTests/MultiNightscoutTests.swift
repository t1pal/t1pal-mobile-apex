// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// MultiNightscoutTests.swift - Tests for multi-instance Nightscout support
// Part of NightscoutKit
// Trace: NS-MULTI-001, NS-MULTI-002, NS-MULTI-003

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - NS-MULTI-001: Instance Configuration Tests

@Suite("NS-MULTI-001: Instance Configuration")
struct InstanceConfigurationTests {
    
    @Test("Create single instance config")
    func createSingleInstance() {
        let config = NightscoutConfig(
            url: URL(string: "https://primary.example.com")!,
            apiSecret: "secret123"
        )
        
        let multiConfig = MultiNightscoutConfig.single(config: config, label: "My NS")
        
        #expect(multiConfig.instances.count == 1)
        #expect(multiConfig.primaryInstance?.label == "My NS")
        #expect(multiConfig.primaryInstance?.role == .readWrite)
        #expect(multiConfig.primaryInstance?.priority == .primary)
    }
    
    @Test("Create primary with backup config")
    func createPrimaryWithBackup() {
        let primary = NightscoutConfig(url: URL(string: "https://primary.example.com")!)
        let backup = NightscoutConfig(url: URL(string: "https://backup.example.com")!)
        
        let multiConfig = MultiNightscoutConfig.withBackup(
            primary: primary,
            backup: backup,
            primaryLabel: "Main",
            backupLabel: "Backup"
        )
        
        #expect(multiConfig.instances.count == 2)
        #expect(multiConfig.primaryInstance?.label == "Main")
        #expect(multiConfig.writableInstances.count == 2)
        
        let backupInstance = multiConfig.instances.first { $0.label == "Backup" }
        #expect(backupInstance?.role == .writeOnly)
        #expect(backupInstance?.priority == .backup)
    }
    
    @Test("Create primary with follower config")
    func createPrimaryWithFollower() {
        let primary = NightscoutConfig(url: URL(string: "https://primary.example.com")!)
        let follower = NightscoutConfig(url: URL(string: "https://follower.example.com")!)
        
        let multiConfig = MultiNightscoutConfig.withFollower(
            primary: primary,
            follower: follower
        )
        
        #expect(multiConfig.instances.count == 2)
        #expect(multiConfig.readableInstances.count == 2)
        
        let followerInstance = multiConfig.instances.first { $0.label == "Follower" }
        #expect(followerInstance?.role == .follower)
        #expect(followerInstance?.role.canRead == true)
        #expect(followerInstance?.role.canWrite == false)
    }
    
    @Test("Instance priority ordering")
    func instancePriorityOrdering() {
        var config = MultiNightscoutConfig()
        
        config.addInstance(NightscoutInstance(
            label: "Tertiary",
            config: NightscoutConfig(url: URL(string: "https://tertiary.example.com")!),
            priority: .tertiary
        ))
        config.addInstance(NightscoutInstance(
            label: "Primary",
            config: NightscoutConfig(url: URL(string: "https://primary.example.com")!),
            priority: .primary
        ))
        config.addInstance(NightscoutInstance(
            label: "Secondary",
            config: NightscoutConfig(url: URL(string: "https://secondary.example.com")!),
            priority: .secondary
        ))
        
        let ordered = config.enabledInstances
        
        #expect(ordered[0].label == "Primary")
        #expect(ordered[1].label == "Secondary")
        #expect(ordered[2].label == "Tertiary")
    }
    
    @Test("Enable and disable instances")
    func enableDisableInstances() {
        var config = MultiNightscoutConfig.single(
            config: NightscoutConfig(url: URL(string: "https://example.com")!),
            label: "Test"
        )
        
        let instanceId = config.instances[0].id
        
        #expect(config.enabledInstances.count == 1)
        
        config.setEnabled(false, forInstanceId: instanceId)
        #expect(config.enabledInstances.count == 0)
        
        config.setEnabled(true, forInstanceId: instanceId)
        #expect(config.enabledInstances.count == 1)
    }
    
    @Test("Instance role capabilities")
    func instanceRoleCapabilities() {
        #expect(NightscoutInstanceRole.readWrite.canRead == true)
        #expect(NightscoutInstanceRole.readWrite.canWrite == true)
        
        #expect(NightscoutInstanceRole.readOnly.canRead == true)
        #expect(NightscoutInstanceRole.readOnly.canWrite == false)
        
        #expect(NightscoutInstanceRole.writeOnly.canRead == false)
        #expect(NightscoutInstanceRole.writeOnly.canWrite == true)
        
        #expect(NightscoutInstanceRole.follower.canRead == true)
        #expect(NightscoutInstanceRole.follower.canWrite == false)
    }
    
    @Test("Instance lookup by label and ID")
    func instanceLookup() {
        let config = MultiNightscoutConfig.withBackup(
            primary: NightscoutConfig(url: URL(string: "https://primary.example.com")!),
            backup: NightscoutConfig(url: URL(string: "https://backup.example.com")!),
            primaryLabel: "Main NS",
            backupLabel: "Backup NS"
        )
        
        // Lookup by label
        let byLabel = config.instance(withLabel: "Main NS")
        #expect(byLabel != nil)
        #expect(byLabel?.priority == .primary)
        
        // Lookup by ID
        let primaryId = config.primaryInstance!.id
        let byId = config.instance(withId: primaryId)
        #expect(byId != nil)
        #expect(byId?.label == "Main NS")
    }
}

// MARK: - NS-MULTI-002: Sync Coordination Tests

@Suite("NS-MULTI-002: Sync Coordination")
struct SyncCoordinationTests {
    
    @Test("Coordinator initializes with config")
    func coordinatorInitializes() async {
        let config = MultiNightscoutConfig.single(
            config: NightscoutConfig(url: URL(string: "https://example.com")!),
            label: "Test"
        )
        
        let coordinator = await MultiNightscoutCoordinator.create(config: config)
        
        let state = await coordinator.getState()
        #expect(state == .idle)
        
        let activeInstance = await coordinator.getActiveInstance()
        #expect(activeInstance?.label == "Test")
    }
    
    @Test("Config can be updated")
    func configCanBeUpdated() async {
        let initialConfig = MultiNightscoutConfig.single(
            config: NightscoutConfig(url: URL(string: "https://initial.example.com")!),
            label: "Initial"
        )
        
        let coordinator = MultiNightscoutCoordinator(config: initialConfig)
        
        var updatedConfig = initialConfig
        updatedConfig.addInstance(NightscoutInstance(
            label: "Added",
            config: NightscoutConfig(url: URL(string: "https://added.example.com")!),
            priority: .secondary
        ))
        
        await coordinator.updateConfig(updatedConfig)
        
        let currentConfig = await coordinator.getConfig()
        #expect(currentConfig.instances.count == 2)
    }
    
    @Test("Single convenience factory")
    func singleConvenienceFactory() async {
        let config = NightscoutConfig(url: URL(string: "https://example.com")!)
        let coordinator = await MultiNightscoutCoordinator.createSingle(config: config, label: "Solo")
        
        let activeInstance = await coordinator.getActiveInstance()
        #expect(activeInstance?.label == "Solo")
    }
    
    @Test("Read mode defaults")
    func readModeDefaults() {
        let settings = MultiSyncSettings()
        
        #expect(settings.readMode == .primaryOnly)
        #expect(settings.writeMode == .primaryOnly)
        #expect(settings.deduplicateAcrossInstances == true)
        #expect(settings.conflictResolution == .newerWins)
    }
    
    @Test("Aggregated result helpers")
    func aggregatedResultHelpers() {
        let successResult = MultiOperationResult<Int>(
            instanceId: UUID(),
            instanceLabel: "Test1",
            result: .success(42),
            duration: 0.1
        )
        let failureResult = MultiOperationResult<Int>(
            instanceId: UUID(),
            instanceLabel: "Test2",
            result: .failure(NSError(domain: "test", code: 1)),
            duration: 0.2
        )
        
        let aggregated = AggregatedResult(
            results: [successResult, failureResult],
            successCount: 1,
            failureCount: 1
        )
        
        #expect(aggregated.anySucceeded == true)
        #expect(aggregated.allSucceeded == false)
        #expect(aggregated.firstSuccess == 42)
        #expect(aggregated.allSuccessValues == [42])
    }
}

// MARK: - NS-MULTI-003: Failover Tests

@Suite("NS-MULTI-003: Failover Logic")
struct FailoverTests {
    
    @Test("Failover settings defaults")
    func failoverSettingsDefaults() {
        let settings = FailoverSettings()
        
        #expect(settings.isEnabled == true)
        #expect(settings.failureThreshold == 3)
        #expect(settings.retryDelay == 60)
        #expect(settings.autoRestore == true)
        #expect(settings.autoRestoreDelay == 300)
    }
    
    @Test("Record success resets failure count")
    func recordSuccessResetsFailures() {
        var config = MultiNightscoutConfig.single(
            config: NightscoutConfig(url: URL(string: "https://example.com")!),
            label: "Test"
        )
        
        let instanceId = config.instances[0].id
        
        // Record some failures
        config.recordFailure(forInstanceId: instanceId, error: "Test error 1")
        config.recordFailure(forInstanceId: instanceId, error: "Test error 2")
        
        #expect(config.instances[0].failureCount == 2)
        #expect(config.instances[0].lastError == "Test error 2")
        
        // Record success
        config.recordSuccess(forInstanceId: instanceId)
        
        #expect(config.instances[0].failureCount == 0)
        #expect(config.instances[0].lastError == nil)
        #expect(config.instances[0].lastSyncTime != nil)
    }
    
    @Test("Perform failover to next instance")
    func performFailoverToNext() async {
        let config = MultiNightscoutConfig.withBackup(
            primary: NightscoutConfig(url: URL(string: "https://primary.example.com")!),
            backup: NightscoutConfig(url: URL(string: "https://backup.example.com")!),
            primaryLabel: "Primary",
            backupLabel: "Backup"
        )
        
        let coordinator = await MultiNightscoutCoordinator.create(config: config)
        
        // Initially on primary
        var active = await coordinator.getActiveInstance()
        #expect(active?.label == "Primary")
        
        // Perform failover
        let success = await coordinator.performFailover()
        #expect(success == true)
        
        // Now on backup
        active = await coordinator.getActiveInstance()
        #expect(active?.label == "Backup")
        
        let state = await coordinator.getState()
        if case .failedOver(_, let toId) = state {
            let toInstance = config.instance(withId: toId)
            #expect(toInstance?.label == "Backup")
        } else {
            Issue.record("Expected failedOver state")
        }
    }
    
    @Test("Failover fails when no more instances")
    func failoverFailsWhenNoMore() async {
        let config = MultiNightscoutConfig.single(
            config: NightscoutConfig(url: URL(string: "https://example.com")!),
            label: "Only"
        )
        
        let coordinator = MultiNightscoutCoordinator(config: config)
        
        // No backup, failover should fail
        let success = await coordinator.performFailover()
        #expect(success == false)
        
        let state = await coordinator.getState()
        #expect(state == .allFailed)
    }
    
    @Test("Failover disabled in settings")
    func failoverDisabledInSettings() async {
        var config = MultiNightscoutConfig.withBackup(
            primary: NightscoutConfig(url: URL(string: "https://primary.example.com")!),
            backup: NightscoutConfig(url: URL(string: "https://backup.example.com")!)
        )
        config.failoverSettings.isEnabled = false
        
        let coordinator = MultiNightscoutCoordinator(config: config)
        
        let success = await coordinator.performFailover()
        #expect(success == false)
    }
    
    @Test("Priority comparison")
    func priorityComparison() {
        #expect(NightscoutInstancePriority.primary < NightscoutInstancePriority.secondary)
        #expect(NightscoutInstancePriority.secondary < NightscoutInstancePriority.tertiary)
        #expect(NightscoutInstancePriority.tertiary < NightscoutInstancePriority.backup)
    }
}

// MARK: - Fixture Tests

@Suite("Multi-Nightscout Fixtures")
struct MultiNightscoutFixtureTests {
    
    @Test("Instance is codable")
    func instanceIsCodable() throws {
        let instance = NightscoutInstance(
            label: "Test",
            config: NightscoutConfig(
                url: URL(string: "https://example.com")!,
                apiSecret: "secret"
            ),
            priority: .primary,
            role: .readWrite,
            notes: "My primary NS"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(instance)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NightscoutInstance.self, from: data)
        
        #expect(decoded.label == "Test")
        #expect(decoded.priority == .primary)
        #expect(decoded.role == .readWrite)
        #expect(decoded.notes == "My primary NS")
    }
    
    @Test("MultiConfig is codable")
    func multiConfigIsCodable() throws {
        let config = MultiNightscoutConfig.withBackup(
            primary: NightscoutConfig(url: URL(string: "https://primary.example.com")!),
            backup: NightscoutConfig(url: URL(string: "https://backup.example.com")!)
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MultiNightscoutConfig.self, from: data)
        
        #expect(decoded.instances.count == 2)
        #expect(decoded.failoverSettings.isEnabled == true)
    }
    
    @Test("Settings are codable")
    func settingsAreCodable() throws {
        let settings = MultiSyncSettings(
            readMode: .mergeAll,
            writeMode: .writeAll,
            conflictResolution: .primaryWins
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MultiSyncSettings.self, from: data)
        
        #expect(decoded.readMode == .mergeAll)
        #expect(decoded.writeMode == .writeAll)
        #expect(decoded.conflictResolution == .primaryWins)
    }
}

// MARK: - State Equality

extension MultiNightscoutState: Equatable {
    public static func == (lhs: MultiNightscoutState, rhs: MultiNightscoutState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.syncing, .syncing):
            return true
        case (.allFailed, .allFailed):
            return true
        case (.failedOver(let lFrom, let lTo), .failedOver(let rFrom, let rTo)):
            return lFrom == rFrom && lTo == rTo
        default:
            return false
        }
    }
}
