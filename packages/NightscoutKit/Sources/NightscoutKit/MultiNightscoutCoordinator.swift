// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// MultiNightscoutCoordinator.swift - Coordinator for multiple Nightscout instances
// Part of NightscoutKit
// Trace: NS-MULTI-002, NS-MULTI-003

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Coordinator State

/// Current state of the multi-instance coordinator
public enum MultiNightscoutState: Sendable {
    case idle
    case syncing
    case failedOver(fromInstanceId: UUID, toInstanceId: UUID)
    case allFailed
}

/// Result of a multi-instance operation
public struct MultiOperationResult<T: Sendable>: Sendable {
    public let instanceId: UUID
    public let instanceLabel: String
    public let result: Result<T, Error>
    public let duration: TimeInterval
    
    public var isSuccess: Bool {
        if case .success = result { return true }
        return false
    }
}

/// Aggregated result from multiple instances
public struct AggregatedResult<T: Sendable>: Sendable {
    public let results: [MultiOperationResult<T>]
    public let successCount: Int
    public let failureCount: Int
    
    public var allSucceeded: Bool { failureCount == 0 }
    public var anySucceeded: Bool { successCount > 0 }
    
    public var firstSuccess: T? {
        results.first { $0.isSuccess }.flatMap { result in
            if case .success(let value) = result.result { return value }
            return nil
        }
    }
    
    public var allSuccessValues: [T] {
        results.compactMap { result in
            if case .success(let value) = result.result { return value }
            return nil
        }
    }
}

// MARK: - Multi-Instance Coordinator

/// Actor that coordinates operations across multiple Nightscout instances
public actor MultiNightscoutCoordinator {
    
    // MARK: - Properties
    
    private var config: MultiNightscoutConfig
    private var clients: [UUID: NightscoutClient] = [:]
    private var v3Clients: [UUID: NightscoutV3Client] = [:]
    private var state: MultiNightscoutState = .idle
    private var activeInstanceId: UUID?
    private var lastFailoverTime: Date?
    
    // MARK: - Initialization
    
    /// Creates a coordinator with the given config.
    /// Note: Use `create(config:)` factory method for deterministic initialization in async contexts.
    public init(config: MultiNightscoutConfig) {
        self.config = config
        // Defer initialization to async context
        Task { await self.initializeClientsAsync() }
    }
    
    /// Async factory method for deterministic initialization
    /// Preferred over init for test and async code paths
    public static func create(config: MultiNightscoutConfig) async -> MultiNightscoutCoordinator {
        let coordinator = MultiNightscoutCoordinator(config: config)
        // Force synchronous initialization within actor context
        await coordinator.forceInitialize()
        return coordinator
    }
    
    /// Force initialization synchronously within actor context
    private func forceInitialize() {
        initializeClientsSync()
    }
    
    /// Ensure initialization is complete (no-op, but forces actor hop)
    public func ensureInitialized() {
        // Actor-isolated method - calling this ensures any pending init is complete
    }
    
    private func initializeClientsAsync() {
        initializeClientsSync()
    }
    
    private func initializeClientsSync() {
        clients.removeAll()
        v3Clients.removeAll()
        
        for instance in config.enabledInstances {
            clients[instance.id] = instance.createClient()
            if let v3 = instance.createV3Client() {
                v3Clients[instance.id] = v3
            }
        }
        
        activeInstanceId = config.primaryInstance?.id
    }
    
    private func initializeClients() {
        clients.removeAll()
        v3Clients.removeAll()
        
        for instance in config.enabledInstances {
            clients[instance.id] = instance.createClient()
            if let v3 = instance.createV3Client() {
                v3Clients[instance.id] = v3
            }
        }
        
        activeInstanceId = config.primaryInstance?.id
    }
    
    // MARK: - Configuration
    
    /// Get current configuration
    public func getConfig() -> MultiNightscoutConfig {
        config
    }
    
    /// Update configuration
    public func updateConfig(_ newConfig: MultiNightscoutConfig) {
        config = newConfig
        initializeClients()
    }
    
    /// Get current state
    public func getState() -> MultiNightscoutState {
        state
    }
    
    /// Get active instance
    public func getActiveInstance() -> NightscoutInstance? {
        guard let id = activeInstanceId else { return nil }
        return config.instance(withId: id)
    }
    
    // MARK: - Read Operations
    
    /// Fetch entries using configured read mode
    public func fetchEntries(count: Int = 288) async -> AggregatedResult<[NightscoutEntry]> {
        switch config.syncSettings.readMode {
        case .primaryOnly:
            return await fetchFromPrimary { client in
                try await client.fetchEntries(count: count)
            }
            
        case .primaryWithFallback:
            return await fetchWithFallback { client in
                try await client.fetchEntries(count: count)
            }
            
        case .mergeAll:
            return await fetchFromAll { client in
                try await client.fetchEntries(count: count)
            }
            
        case .fastest:
            return await fetchFastest { client in
                try await client.fetchEntries(count: count)
            }
        }
    }
    
    /// Fetch treatments using configured read mode
    public func fetchTreatments(count: Int = 100) async -> AggregatedResult<[NightscoutTreatment]> {
        switch config.syncSettings.readMode {
        case .primaryOnly:
            return await fetchFromPrimary { client in
                try await client.fetchTreatments(count: count)
            }
            
        case .primaryWithFallback:
            return await fetchWithFallback { client in
                try await client.fetchTreatments(count: count)
            }
            
        case .mergeAll:
            return await fetchFromAll { client in
                try await client.fetchTreatments(count: count)
            }
            
        case .fastest:
            return await fetchFastest { client in
                try await client.fetchTreatments(count: count)
            }
        }
    }
    
    // MARK: - Write Operations
    
    /// Upload entries using configured write mode
    public func uploadEntries(_ entries: [NightscoutEntry]) async -> AggregatedResult<Void> {
        switch config.syncSettings.writeMode {
        case .primaryOnly:
            return await writeToPrimary { client in
                try await client.uploadEntries(entries)
            }
            
        case .writeAll:
            return await writeToAll { client in
                try await client.uploadEntries(entries)
            }
            
        case .primaryWithMirror:
            return await writeWithMirror { client in
                try await client.uploadEntries(entries)
            }
        }
    }
    
    /// Upload treatments using configured write mode
    public func uploadTreatments(_ treatments: [NightscoutTreatment]) async -> AggregatedResult<Void> {
        switch config.syncSettings.writeMode {
        case .primaryOnly:
            return await writeToPrimary { client in
                try await client.uploadTreatments(treatments)
            }
            
        case .writeAll:
            return await writeToAll { client in
                try await client.uploadTreatments(treatments)
            }
            
        case .primaryWithMirror:
            return await writeWithMirror { client in
                try await client.uploadTreatments(treatments)
            }
        }
    }
    
    /// Upload device status using configured write mode
    public func uploadDeviceStatus(_ status: NightscoutDeviceStatus) async -> AggregatedResult<Void> {
        switch config.syncSettings.writeMode {
        case .primaryOnly:
            return await writeToPrimary { client in
                try await client.uploadDeviceStatus(status)
            }
            
        case .writeAll:
            return await writeToAll { client in
                try await client.uploadDeviceStatus(status)
            }
            
        case .primaryWithMirror:
            return await writeWithMirror { client in
                try await client.uploadDeviceStatus(status)
            }
        }
    }
    
    // MARK: - Failover Logic (NS-MULTI-003)
    
    /// Attempt to failover to next available instance
    public func performFailover() async -> Bool {
        guard config.failoverSettings.isEnabled else { return false }
        
        let enabledInstances = config.enabledInstances
        guard let currentId = activeInstanceId,
              let currentIndex = enabledInstances.firstIndex(where: { $0.id == currentId }),
              currentIndex + 1 < enabledInstances.count else {
            state = .allFailed
            return false
        }
        
        let nextInstance = enabledInstances[currentIndex + 1]
        let previousId = activeInstanceId!
        activeInstanceId = nextInstance.id
        lastFailoverTime = Date()
        state = .failedOver(fromInstanceId: previousId, toInstanceId: nextInstance.id)
        
        return true
    }
    
    /// Check if primary is healthy and restore if configured
    public func checkAndRestorePrimary() async -> Bool {
        guard config.failoverSettings.autoRestore,
              let primary = config.primaryInstance,
              activeInstanceId != primary.id,
              let lastFailover = lastFailoverTime else {
            return false
        }
        
        // Check if enough time has passed
        let elapsed = Date().timeIntervalSince(lastFailover)
        guard elapsed >= config.failoverSettings.autoRestoreDelay else {
            return false
        }
        
        // Try to reach primary
        guard let client = clients[primary.id] else { return false }
        
        do {
            // Health check via minimal entries fetch
            _ = try await client.fetchEntries(count: 1)
            
            // Primary is healthy, restore
            activeInstanceId = primary.id
            state = .idle
            config.recordSuccess(forInstanceId: primary.id)
            return true
        } catch {
            // Primary still unhealthy
            return false
        }
    }
    
    /// Record operation success
    private func recordSuccess(instanceId: UUID) {
        config.recordSuccess(forInstanceId: instanceId)
    }
    
    /// Record operation failure and potentially trigger failover
    private func recordFailure(instanceId: UUID, error: Error) async {
        config.recordFailure(forInstanceId: instanceId, error: error.localizedDescription)
        
        // Check if failover is needed
        if let instance = config.instance(withId: instanceId),
           instance.failureCount >= config.failoverSettings.failureThreshold,
           instanceId == activeInstanceId {
            _ = await performFailover()
        }
    }
    
    // MARK: - Read Strategies
    
    private func fetchFromPrimary<T: Sendable>(
        operation: @escaping (NightscoutClient) async throws -> T
    ) async -> AggregatedResult<T> {
        guard let primary = config.primaryInstance,
              let client = clients[primary.id] else {
            return AggregatedResult(results: [], successCount: 0, failureCount: 1)
        }
        
        let start = Date()
        do {
            let value = try await operation(client)
            recordSuccess(instanceId: primary.id)
            
            let result = MultiOperationResult<T>(
                instanceId: primary.id,
                instanceLabel: primary.label,
                result: .success(value),
                duration: Date().timeIntervalSince(start)
            )
            return AggregatedResult(results: [result], successCount: 1, failureCount: 0)
        } catch {
            await recordFailure(instanceId: primary.id, error: error)
            
            let result = MultiOperationResult<T>(
                instanceId: primary.id,
                instanceLabel: primary.label,
                result: .failure(error),
                duration: Date().timeIntervalSince(start)
            )
            return AggregatedResult(results: [result], successCount: 0, failureCount: 1)
        }
    }
    
    private func fetchWithFallback<T: Sendable>(
        operation: @escaping (NightscoutClient) async throws -> T
    ) async -> AggregatedResult<T> {
        var results: [MultiOperationResult<T>] = []
        
        for instance in config.readableInstances {
            guard let client = clients[instance.id] else { continue }
            
            let start = Date()
            do {
                let value = try await operation(client)
                recordSuccess(instanceId: instance.id)
                
                let result = MultiOperationResult<T>(
                    instanceId: instance.id,
                    instanceLabel: instance.label,
                    result: .success(value),
                    duration: Date().timeIntervalSince(start)
                )
                results.append(result)
                
                // Success on first working instance
                return AggregatedResult(
                    results: results,
                    successCount: 1,
                    failureCount: results.count - 1
                )
            } catch {
                await recordFailure(instanceId: instance.id, error: error)
                
                let result = MultiOperationResult<T>(
                    instanceId: instance.id,
                    instanceLabel: instance.label,
                    result: .failure(error),
                    duration: Date().timeIntervalSince(start)
                )
                results.append(result)
                // Continue to next instance
            }
        }
        
        return AggregatedResult(
            results: results,
            successCount: 0,
            failureCount: results.count
        )
    }
    
    private func fetchFromAll<T: Sendable>(
        operation: @escaping (NightscoutClient) async throws -> T
    ) async -> AggregatedResult<T> {
        let instances = config.readableInstances
        var results: [MultiOperationResult<T>] = []
        var successCount = 0
        var failureCount = 0
        
        await withTaskGroup(of: MultiOperationResult<T>.self) { group in
            for instance in instances {
                guard let client = clients[instance.id] else { continue }
                
                group.addTask {
                    let start = Date()
                    do {
                        let value = try await operation(client)
                        return MultiOperationResult(
                            instanceId: instance.id,
                            instanceLabel: instance.label,
                            result: .success(value),
                            duration: Date().timeIntervalSince(start)
                        )
                    } catch {
                        return MultiOperationResult(
                            instanceId: instance.id,
                            instanceLabel: instance.label,
                            result: .failure(error),
                            duration: Date().timeIntervalSince(start)
                        )
                    }
                }
            }
            
            for await result in group {
                results.append(result)
                if result.isSuccess {
                    successCount += 1
                    recordSuccess(instanceId: result.instanceId)
                } else {
                    failureCount += 1
                    if case .failure(let error) = result.result {
                        await recordFailure(instanceId: result.instanceId, error: error)
                    }
                }
            }
        }
        
        return AggregatedResult(
            results: results,
            successCount: successCount,
            failureCount: failureCount
        )
    }
    
    private func fetchFastest<T: Sendable>(
        operation: @escaping (NightscoutClient) async throws -> T
    ) async -> AggregatedResult<T> {
        let instances = config.readableInstances
        
        // Race all instances, return first success
        return await withTaskGroup(of: MultiOperationResult<T>?.self) { group in
            for instance in instances {
                guard let client = clients[instance.id] else { continue }
                
                group.addTask {
                    let start = Date()
                    do {
                        let value = try await operation(client)
                        return MultiOperationResult(
                            instanceId: instance.id,
                            instanceLabel: instance.label,
                            result: .success(value),
                            duration: Date().timeIntervalSince(start)
                        )
                    } catch {
                        return MultiOperationResult(
                            instanceId: instance.id,
                            instanceLabel: instance.label,
                            result: .failure(error),
                            duration: Date().timeIntervalSince(start)
                        )
                    }
                }
            }
            
            var results: [MultiOperationResult<T>] = []
            var foundSuccess = false
            
            for await result in group {
                guard let result = result else { continue }
                results.append(result)
                
                if result.isSuccess && !foundSuccess {
                    foundSuccess = true
                    recordSuccess(instanceId: result.instanceId)
                    // Cancel remaining tasks implicitly by returning
                    group.cancelAll()
                    return AggregatedResult(
                        results: [result],
                        successCount: 1,
                        failureCount: 0
                    )
                }
            }
            
            // All failed
            return AggregatedResult(
                results: results,
                successCount: 0,
                failureCount: results.count
            )
        }
    }
    
    // MARK: - Write Strategies
    
    private func writeToPrimary(
        operation: @escaping (NightscoutClient) async throws -> Void
    ) async -> AggregatedResult<Void> {
        guard let primary = config.writableInstances.first,
              let client = clients[primary.id] else {
            return AggregatedResult(results: [], successCount: 0, failureCount: 1)
        }
        
        let start = Date()
        do {
            try await operation(client)
            recordSuccess(instanceId: primary.id)
            
            let result = MultiOperationResult<Void>(
                instanceId: primary.id,
                instanceLabel: primary.label,
                result: .success(()),
                duration: Date().timeIntervalSince(start)
            )
            return AggregatedResult(results: [result], successCount: 1, failureCount: 0)
        } catch {
            await recordFailure(instanceId: primary.id, error: error)
            
            let result = MultiOperationResult<Void>(
                instanceId: primary.id,
                instanceLabel: primary.label,
                result: .failure(error),
                duration: Date().timeIntervalSince(start)
            )
            return AggregatedResult(results: [result], successCount: 0, failureCount: 1)
        }
    }
    
    private func writeToAll(
        operation: @escaping (NightscoutClient) async throws -> Void
    ) async -> AggregatedResult<Void> {
        let instances = config.writableInstances
        var results: [MultiOperationResult<Void>] = []
        var successCount = 0
        var failureCount = 0
        
        await withTaskGroup(of: MultiOperationResult<Void>.self) { group in
            for instance in instances {
                guard let client = clients[instance.id] else { continue }
                
                group.addTask {
                    let start = Date()
                    do {
                        try await operation(client)
                        return MultiOperationResult(
                            instanceId: instance.id,
                            instanceLabel: instance.label,
                            result: .success(()),
                            duration: Date().timeIntervalSince(start)
                        )
                    } catch {
                        return MultiOperationResult(
                            instanceId: instance.id,
                            instanceLabel: instance.label,
                            result: .failure(error),
                            duration: Date().timeIntervalSince(start)
                        )
                    }
                }
            }
            
            for await result in group {
                results.append(result)
                if result.isSuccess {
                    successCount += 1
                    recordSuccess(instanceId: result.instanceId)
                } else {
                    failureCount += 1
                    if case .failure(let error) = result.result {
                        await recordFailure(instanceId: result.instanceId, error: error)
                    }
                }
            }
        }
        
        return AggregatedResult(
            results: results,
            successCount: successCount,
            failureCount: failureCount
        )
    }
    
    private func writeWithMirror(
        operation: @escaping (NightscoutClient) async throws -> Void
    ) async -> AggregatedResult<Void> {
        let instances = config.writableInstances
        guard let primary = instances.first,
              let primaryClient = clients[primary.id] else {
            return AggregatedResult(results: [], successCount: 0, failureCount: 1)
        }
        
        var results: [MultiOperationResult<Void>] = []
        
        // Write to primary first (synchronous)
        let start = Date()
        do {
            try await operation(primaryClient)
            recordSuccess(instanceId: primary.id)
            
            let result = MultiOperationResult<Void>(
                instanceId: primary.id,
                instanceLabel: primary.label,
                result: .success(()),
                duration: Date().timeIntervalSince(start)
            )
            results.append(result)
        } catch {
            await recordFailure(instanceId: primary.id, error: error)
            
            let result = MultiOperationResult<Void>(
                instanceId: primary.id,
                instanceLabel: primary.label,
                result: .failure(error),
                duration: Date().timeIntervalSince(start)
            )
            results.append(result)
            
            return AggregatedResult(
                results: results,
                successCount: 0,
                failureCount: 1
            )
        }
        
        // Mirror to others asynchronously (fire and forget)
        let otherInstances = Array(instances.dropFirst())
        Task {
            await withTaskGroup(of: Void.self) { group in
                for instance in otherInstances {
                    guard let client = clients[instance.id] else { continue }
                    
                    group.addTask {
                        do {
                            try await operation(client)
                        } catch {
                            // Log but don't fail - this is async mirror
                        }
                    }
                }
            }
        }
        
        return AggregatedResult(
            results: results,
            successCount: 1,
            failureCount: 0
        )
    }
}

// MARK: - Convenience Extensions

extension MultiNightscoutCoordinator {
    
    /// Create a coordinator from a single config (wraps in multi-config)
    public static func single(config: NightscoutConfig, label: String = "Primary") -> MultiNightscoutCoordinator {
        MultiNightscoutCoordinator(config: .single(config: config, label: label))
    }
    
    /// Async factory for single config - ensures initialization is complete
    public static func createSingle(config: NightscoutConfig, label: String = "Primary") async -> MultiNightscoutCoordinator {
        await create(config: .single(config: config, label: label))
    }
    
    /// Get health status of all instances (verified via entries fetch)
    public func getAllHealthStatus() async -> [UUID: Result<Bool, Error>] {
        var results: [UUID: Result<Bool, Error>] = [:]
        
        for instance in config.enabledInstances {
            guard let client = clients[instance.id] else { continue }
            
            do {
                // Health check via minimal entries fetch
                _ = try await client.fetchEntries(count: 1)
                results[instance.id] = .success(true)
            } catch {
                results[instance.id] = .failure(error)
            }
        }
        
        return results
    }
}
