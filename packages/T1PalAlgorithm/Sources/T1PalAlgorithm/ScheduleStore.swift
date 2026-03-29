// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ScheduleStore.swift
// T1PalAlgorithm
//
// Persistence and activation of scheduled proposals
// Architecture: docs/architecture/REMOTE-AGENT-EFFECT-PROPOSALS.md
// Backlog: SCHED-004
//

import Foundation

// MARK: - Schedule Store Protocol

/// Protocol for scheduled proposal persistence
public protocol ScheduleStore: Sendable {
    /// Save a scheduled proposal
    func save(_ proposal: ScheduledProposal) async throws
    
    /// Load all scheduled proposals
    func loadAll() async throws -> [ScheduledProposal]
    
    /// Load only enabled proposals
    func loadEnabled() async throws -> [ScheduledProposal]
    
    /// Delete a proposal by ID
    func delete(id: UUID) async throws
    
    /// Update a proposal (e.g., enable/disable)
    func update(_ proposal: ScheduledProposal) async throws
    
    /// Get proposals that should activate now
    func getActivatable(at time: Date) async throws -> [ScheduledProposal]
    
    /// Clear all proposals
    func clearAll() async throws
}

// MARK: - Schedule Store Errors

public enum ScheduleStoreError: Error, LocalizedError {
    case notFound(UUID)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case fileWriteFailed(Error)
    case fileReadFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Scheduled proposal not found: \(id)"
        case .encodingFailed(let error):
            return "Failed to encode schedule: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to decode schedule: \(error.localizedDescription)"
        case .fileWriteFailed(let error):
            return "Failed to write schedule file: \(error.localizedDescription)"
        case .fileReadFailed(let error):
            return "Failed to read schedule file: \(error.localizedDescription)"
        }
    }
}

// MARK: - In-Memory Store

/// In-memory implementation for testing
public actor InMemoryScheduleStore: ScheduleStore {
    private var proposals: [UUID: ScheduledProposal] = [:]
    
    public init() {}
    
    public func save(_ proposal: ScheduledProposal) async throws {
        proposals[proposal.id] = proposal
    }
    
    public func loadAll() async throws -> [ScheduledProposal] {
        Array(proposals.values).sorted { $0.startTime < $1.startTime }
    }
    
    public func loadEnabled() async throws -> [ScheduledProposal] {
        proposals.values.filter(\.isEnabled).sorted { $0.startTime < $1.startTime }
    }
    
    public func delete(id: UUID) async throws {
        guard proposals.removeValue(forKey: id) != nil else {
            throw ScheduleStoreError.notFound(id)
        }
    }
    
    public func update(_ proposal: ScheduledProposal) async throws {
        guard proposals[proposal.id] != nil else {
            throw ScheduleStoreError.notFound(proposal.id)
        }
        proposals[proposal.id] = proposal
    }
    
    public func getActivatable(at time: Date) async throws -> [ScheduledProposal] {
        proposals.values.filter { $0.shouldActivate(at: time) }
    }
    
    public func clearAll() async throws {
        proposals.removeAll()
    }
}

// MARK: - File-Based Store

/// File-based implementation for production
public actor FileScheduleStore: ScheduleStore {
    private let fileURL: URL
    private var cache: [UUID: ScheduledProposal]?
    
    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileURL = dir.appendingPathComponent("scheduled_proposals.json")
    }
    
    public func save(_ proposal: ScheduledProposal) async throws {
        var proposals = try await loadCache()
        proposals[proposal.id] = proposal
        try await persist(proposals)
    }
    
    public func loadAll() async throws -> [ScheduledProposal] {
        let proposals = try await loadCache()
        return Array(proposals.values).sorted { $0.startTime < $1.startTime }
    }
    
    public func loadEnabled() async throws -> [ScheduledProposal] {
        let proposals = try await loadCache()
        return proposals.values.filter(\.isEnabled).sorted { $0.startTime < $1.startTime }
    }
    
    public func delete(id: UUID) async throws {
        var proposals = try await loadCache()
        guard proposals.removeValue(forKey: id) != nil else {
            throw ScheduleStoreError.notFound(id)
        }
        try await persist(proposals)
    }
    
    public func update(_ proposal: ScheduledProposal) async throws {
        var proposals = try await loadCache()
        guard proposals[proposal.id] != nil else {
            throw ScheduleStoreError.notFound(proposal.id)
        }
        proposals[proposal.id] = proposal
        try await persist(proposals)
    }
    
    public func getActivatable(at time: Date) async throws -> [ScheduledProposal] {
        let proposals = try await loadCache()
        return proposals.values.filter { $0.shouldActivate(at: time) }
    }
    
    public func clearAll() async throws {
        cache = [:]
        try await persist([:])
    }
    
    // MARK: - Private
    
    private func loadCache() async throws -> [UUID: ScheduledProposal] {
        if let cache = cache {
            return cache
        }
        
        let proposals = try await loadFromDisk()
        cache = proposals
        return proposals
    }
    
    private func loadFromDisk() async throws -> [UUID: ScheduledProposal] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let list = try decoder.decode([ScheduledProposal].self, from: data)
            return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch {
            throw ScheduleStoreError.decodingFailed(error)
        }
    }
    
    private func persist(_ proposals: [UUID: ScheduledProposal]) async throws {
        cache = proposals
        
        let list = Array(proposals.values)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(list)
            try data.write(to: fileURL, options: .atomic)
        } catch let error as EncodingError {
            throw ScheduleStoreError.encodingFailed(error)
        } catch {
            throw ScheduleStoreError.fileWriteFailed(error)
        }
    }
}

// MARK: - Schedule Manager

/// Manager for checking and activating scheduled proposals
public actor ScheduleManager {
    private let store: ScheduleStore
    private var lastCheckTime: Date?
    
    public init(store: ScheduleStore) {
        self.store = store
    }
    
    /// Check for proposals that should activate now
    public func checkAndActivate() async throws -> [EffectBundle] {
        let now = Date()
        lastCheckTime = now
        
        let activatable = try await store.getActivatable(at: now)
        var bundles: [EffectBundle] = []
        
        for proposal in activatable {
            bundles.append(proposal.effectBundle)
            
            // Handle recurring proposals - update next occurrence
            if let nextTime = proposal.nextOccurrence(after: now) {
                // For recurring, track next activation time
                // (State tracking would be added when BGTaskScheduler integration is done)
                _ = nextTime
            } else if proposal.isOneTime {
                // One-time proposal completed - could mark as done or delete
                // For now, leave it (UI should handle cleanup)
            }
        }
        
        return bundles
    }
    
    /// Get upcoming proposals sorted by next occurrence
    public func getUpcoming(limit: Int = 10) async throws -> [(proposal: ScheduledProposal, nextTime: Date)] {
        let now = Date()
        let proposals = try await store.loadEnabled()
        
        var upcoming: [(ScheduledProposal, Date)] = []
        for proposal in proposals {
            if let nextTime = proposal.nextOccurrence(after: now) {
                upcoming.append((proposal, nextTime))
            }
        }
        
        return upcoming
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { (proposal: $0.0, nextTime: $0.1) }
    }
    
    /// Schedule a new proposal
    public func schedule(_ proposal: ScheduledProposal) async throws {
        try await store.save(proposal)
    }
    
    /// Cancel a scheduled proposal
    public func cancel(id: UUID) async throws {
        try await store.delete(id: id)
    }
    
    /// Enable or disable a proposal
    public func setEnabled(_ enabled: Bool, for id: UUID) async throws {
        let proposals = try await store.loadAll()
        guard var proposal = proposals.first(where: { $0.id == id }) else {
            throw ScheduleStoreError.notFound(id)
        }
        proposal.isEnabled = enabled
        try await store.update(proposal)
    }
}

// MARK: - Background Task Scheduler Integration
// Trace: SCHED-008

#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks

/// Background task identifier for scheduled proposals
public enum ScheduleTaskIdentifier {
    /// Background task for checking scheduled proposals
    public static let scheduleCheck = "com.t1pal.schedule.check"
}

/// Background scheduler for scheduled proposals
/// Uses BGAppRefreshTask to wake the app and check for activatable schedules
@available(iOS 13.0, *)
public final class ScheduleBackgroundManager: @unchecked Sendable {
    public static let shared = ScheduleBackgroundManager()
    
    private let scheduleManager: ScheduleManager
    private var isRegistered = false
    
    public init(scheduleManager: ScheduleManager? = nil) {
        self.scheduleManager = scheduleManager ?? ScheduleManager(store: FileScheduleStore())
    }
    
    /// Register background task with the system
    /// Must be called during app launch, before applicationDidFinishLaunching returns
    public func registerBackgroundTask() {
        guard !isRegistered else { return }
        
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ScheduleTaskIdentifier.scheduleCheck,
            using: nil
        ) { [weak self] task in
            self?.handleScheduleCheck(task: task as! BGAppRefreshTask)
        }
        
        isRegistered = true
    }
    
    /// Schedule the next background check
    /// Should be called after saving/updating schedules
    public func scheduleNextCheck() async {
        do {
            let upcoming = try await scheduleManager.getUpcoming(limit: 1)
            guard let next = upcoming.first else {
                // No upcoming schedules, cancel any pending requests
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: ScheduleTaskIdentifier.scheduleCheck)
                return
            }
            
            let request = BGAppRefreshTaskRequest(identifier: ScheduleTaskIdentifier.scheduleCheck)
            // Schedule slightly before the target time to ensure we wake in time
            request.earliestBeginDate = next.nextTime.addingTimeInterval(-60)
            
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Log error but don't throw - background scheduling is best-effort
            AlgorithmLogger.general.error("Failed to schedule background check: \(error.localizedDescription)")
        }
    }
    
    /// Cancel all pending background tasks
    public func cancelPendingTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: ScheduleTaskIdentifier.scheduleCheck)
    }
    
    // MARK: - Private
    
    private func handleScheduleCheck(task: BGAppRefreshTask) {
        // Schedule the next check before we start processing
        Task {
            await scheduleNextCheck()
        }
        
        // Set up expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // Process activatable schedules
        Task {
            do {
                let bundles = try await scheduleManager.checkAndActivate()
                
                // If we activated any bundles, post a notification for the app to handle
                if !bundles.isEmpty {
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .scheduledProposalsActivated,
                            object: nil,
                            userInfo: ["bundles": bundles]
                        )
                    }
                }
                
                task.setTaskCompleted(success: true)
            } catch {
                AlgorithmLogger.general.error("Background check failed: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Posted when scheduled proposals are activated in the background
    static let scheduledProposalsActivated = Notification.Name("com.t1pal.scheduledProposalsActivated")
}

#endif

// MARK: - Schedule Manager Extension for Background Integration

public extension ScheduleManager {
    /// Schedule a proposal and update background task
    func scheduleWithBackgroundUpdate(_ proposal: ScheduledProposal) async throws {
        try await schedule(proposal)
        
        #if canImport(BackgroundTasks) && os(iOS)
        if #available(iOS 13.0, *) {
            await ScheduleBackgroundManager.shared.scheduleNextCheck()
        }
        #endif
    }
    
    /// Cancel a proposal and update background task
    func cancelWithBackgroundUpdate(id: UUID) async throws {
        try await cancel(id: id)
        
        #if canImport(BackgroundTasks) && os(iOS)
        if #available(iOS 13.0, *) {
            await ScheduleBackgroundManager.shared.scheduleNextCheck()
        }
        #endif
    }
}
