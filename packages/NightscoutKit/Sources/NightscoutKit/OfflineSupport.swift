// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OfflineSupport.swift
// NightscoutKit
//
// Offline queue and sync coordination for Nightscout operations
// Extracted from NightscoutClient.swift (NS-REFACTOR-010)
// Requirements: REQ-NS-009

import Foundation

// MARK: - Network State

/// Network connectivity state
public enum NetworkState: Sendable, Equatable {
    case unknown
    case online
    case offline
}

// MARK: - Offline Operation Type

/// Type of queued operation
public enum OfflineOperationType: String, Codable, Sendable {
    case uploadEntry
    case uploadTreatment
    case uploadDeviceStatus
    case uploadProfile
    case remoteCommand
}

// MARK: - Offline Queue Item

/// Queued offline operation
public struct OfflineQueueItem: Codable, Sendable, Identifiable {
    public let id: UUID
    public let operationType: OfflineOperationType
    public let payload: Data
    public let createdAt: Date
    public var retryCount: Int
    public var lastRetryAt: Date?
    public var error: String?
    
    public init(
        id: UUID = UUID(),
        operationType: OfflineOperationType,
        payload: Data,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastRetryAt: Date? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.operationType = operationType
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastRetryAt = lastRetryAt
        self.error = error
    }
}

// MARK: - Offline Queue Result

/// Result of processing offline queue
public struct OfflineQueueResult: Sendable {
    public let processed: Int
    public let succeeded: Int
    public let failed: Int
    public let remaining: Int
    public let errors: [String]
    
    public init(
        processed: Int,
        succeeded: Int,
        failed: Int,
        remaining: Int,
        errors: [String] = []
    ) {
        self.processed = processed
        self.succeeded = succeeded
        self.failed = failed
        self.remaining = remaining
        self.errors = errors
    }
}

// MARK: - Offline Queue

/// Offline queue manager for Nightscout operations
/// Requirements: REQ-NS-009
public actor OfflineQueue {
    private var queue: [OfflineQueueItem] = []
    private let client: NightscoutClient
    private var networkState: NetworkState = .unknown
    private let maxRetries: Int
    private let baseRetryDelay: TimeInterval
    private let maxRetryDelay: TimeInterval
    private var stateHandlers: [(NetworkState) async -> Void] = []
    
    public init(
        client: NightscoutClient,
        maxRetries: Int = 5,
        baseRetryDelay: TimeInterval = 5.0,
        maxRetryDelay: TimeInterval = 300.0
    ) {
        self.client = client
        self.maxRetries = maxRetries
        self.baseRetryDelay = baseRetryDelay
        self.maxRetryDelay = maxRetryDelay
    }
    
    /// Get current network state
    public func getNetworkState() -> NetworkState {
        networkState
    }
    
    /// Set network state (called by network monitor)
    public func setNetworkState(_ state: NetworkState) async {
        let oldState = networkState
        networkState = state
        
        if oldState != state {
            for handler in stateHandlers {
                await handler(state)
            }
            
            // Auto-process queue when coming online
            if state == .online && !queue.isEmpty {
                _ = await processQueue()
            }
        }
    }
    
    /// Add handler for network state changes
    public func onNetworkStateChange(_ handler: @escaping (NetworkState) async -> Void) {
        stateHandlers.append(handler)
    }
    
    /// Get queue size
    public func getQueueSize() -> Int {
        queue.count
    }
    
    /// Get all queued items
    public func getQueueItems() -> [OfflineQueueItem] {
        queue
    }
    
    /// Queue an entry for upload
    public func queueEntry(_ entry: NightscoutEntry) throws {
        let payload = try JSONEncoder().encode([entry])
        let item = OfflineQueueItem(operationType: .uploadEntry, payload: payload)
        queue.append(item)
    }
    
    /// Queue a treatment for upload
    public func queueTreatment(_ treatment: NightscoutTreatment) throws {
        let payload = try JSONEncoder().encode([treatment])
        let item = OfflineQueueItem(operationType: .uploadTreatment, payload: payload)
        queue.append(item)
    }
    
    /// Queue a device status for upload
    public func queueDeviceStatus(_ status: NightscoutDeviceStatus) throws {
        let payload = try JSONEncoder().encode(status)
        let item = OfflineQueueItem(operationType: .uploadDeviceStatus, payload: payload)
        queue.append(item)
    }
    
    /// Queue a profile for upload
    public func queueProfile(_ profile: NightscoutProfile) throws {
        let payload = try JSONEncoder().encode(profile)
        let item = OfflineQueueItem(operationType: .uploadProfile, payload: payload)
        queue.append(item)
    }
    
    /// Process the offline queue
    public func processQueue() async -> OfflineQueueResult {
        guard networkState == .online || networkState == .unknown else {
            return OfflineQueueResult(
                processed: 0,
                succeeded: 0,
                failed: 0,
                remaining: queue.count
            )
        }
        
        var processed = 0
        var succeeded = 0
        var failed = 0
        var errors: [String] = []
        var itemsToRemove: [UUID] = []
        var itemsToRetry: [UUID: OfflineQueueItem] = [:]
        
        for item in queue {
            processed += 1
            
            do {
                try await processItem(item)
                succeeded += 1
                itemsToRemove.append(item.id)
            } catch {
                var updatedItem = item
                updatedItem.retryCount += 1
                updatedItem.lastRetryAt = Date()
                updatedItem.error = error.localizedDescription
                
                if updatedItem.retryCount >= maxRetries {
                    failed += 1
                    errors.append("[\(item.operationType.rawValue)] Max retries exceeded: \(error.localizedDescription)")
                    itemsToRemove.append(item.id)
                } else {
                    itemsToRetry[item.id] = updatedItem
                }
            }
        }
        
        // Remove processed items
        queue.removeAll { itemsToRemove.contains($0.id) }
        
        // Update retry items
        for i in queue.indices {
            if let updated = itemsToRetry[queue[i].id] {
                queue[i] = updated
            }
        }
        
        return OfflineQueueResult(
            processed: processed,
            succeeded: succeeded,
            failed: failed,
            remaining: queue.count,
            errors: errors
        )
    }
    
    private func processItem(_ item: OfflineQueueItem) async throws {
        switch item.operationType {
        case .uploadEntry:
            let entries = try JSONDecoder().decode([NightscoutEntry].self, from: item.payload)
            try await client.uploadEntries(entries)
            
        case .uploadTreatment:
            let treatments = try JSONDecoder().decode([NightscoutTreatment].self, from: item.payload)
            try await client.uploadTreatments(treatments)
            
        case .uploadDeviceStatus:
            let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: item.payload)
            try await client.uploadDeviceStatus(status)
            
        case .uploadProfile:
            let profile = try JSONDecoder().decode(NightscoutProfile.self, from: item.payload)
            try await client.uploadProfile(profile)
            
        case .remoteCommand:
            // Remote commands are uploaded as treatments
            let treatments = try JSONDecoder().decode([NightscoutTreatment].self, from: item.payload)
            try await client.uploadTreatments(treatments)
        }
    }
    
    /// Calculate retry delay with exponential backoff
    public func calculateRetryDelay(for item: OfflineQueueItem) -> TimeInterval {
        let delay = baseRetryDelay * pow(2, Double(item.retryCount))
        return min(delay, maxRetryDelay)
    }
    
    /// Clear the queue
    public func clearQueue() {
        queue = []
    }
    
    /// Remove a specific item from the queue
    public func removeItem(_ id: UUID) {
        queue.removeAll { $0.id == id }
    }
    
    /// Export queue for persistence
    public func exportQueue() throws -> Data {
        try JSONEncoder().encode(queue)
    }
    
    /// Import queue from persistence
    public func importQueue(_ data: Data) throws {
        queue = try JSONDecoder().decode([OfflineQueueItem].self, from: data)
    }
}

// MARK: - Offline Sync Coordinator

/// Sync manager wrapper that adds offline support
/// Requirements: REQ-NS-009
public actor OfflineSyncCoordinator {
    private let offlineQueue: OfflineQueue
    private let entriesSyncManager: EntriesSyncManager?
    private let treatmentsSyncManager: TreatmentsSyncManager?
    private let deviceStatusSyncManager: DeviceStatusSyncManager?
    private let profileSyncManager: ProfileSyncManager?
    
    public init(
        offlineQueue: OfflineQueue,
        entriesSyncManager: EntriesSyncManager? = nil,
        treatmentsSyncManager: TreatmentsSyncManager? = nil,
        deviceStatusSyncManager: DeviceStatusSyncManager? = nil,
        profileSyncManager: ProfileSyncManager? = nil
    ) {
        self.offlineQueue = offlineQueue
        self.entriesSyncManager = entriesSyncManager
        self.treatmentsSyncManager = treatmentsSyncManager
        self.deviceStatusSyncManager = deviceStatusSyncManager
        self.profileSyncManager = profileSyncManager
    }
    
    /// Upload entry with offline fallback
    public func uploadEntry(_ entry: NightscoutEntry) async throws {
        let networkState = await offlineQueue.getNetworkState()
        
        if networkState == .offline {
            try await offlineQueue.queueEntry(entry)
        } else {
            do {
                await entriesSyncManager?.queueForUpload([entry])
                _ = try await entriesSyncManager?.uploadPending()
            } catch {
                // Network failed, queue for later
                try await offlineQueue.queueEntry(entry)
                throw error
            }
        }
    }
    
    /// Upload treatment with offline fallback
    public func uploadTreatment(_ treatment: NightscoutTreatment) async throws {
        let networkState = await offlineQueue.getNetworkState()
        
        if networkState == .offline {
            try await offlineQueue.queueTreatment(treatment)
        } else {
            do {
                await treatmentsSyncManager?.queueForUpload([treatment])
                _ = try await treatmentsSyncManager?.uploadPending()
            } catch {
                try await offlineQueue.queueTreatment(treatment)
                throw error
            }
        }
    }
    
    /// Upload device status with offline fallback
    public func uploadDeviceStatus(_ status: NightscoutDeviceStatus) async throws {
        let networkState = await offlineQueue.getNetworkState()
        
        if networkState == .offline {
            try await offlineQueue.queueDeviceStatus(status)
        } else {
            do {
                try await deviceStatusSyncManager?.upload(status)
            } catch {
                try await offlineQueue.queueDeviceStatus(status)
                throw error
            }
        }
    }
    
    /// Get pending queue size
    public func getPendingCount() async -> Int {
        await offlineQueue.getQueueSize()
    }
    
    /// Process offline queue
    public func processPendingQueue() async -> OfflineQueueResult {
        await offlineQueue.processQueue()
    }
}
