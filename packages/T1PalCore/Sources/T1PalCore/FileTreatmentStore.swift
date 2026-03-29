// SPDX-License-Identifier: AGPL-3.0-or-later
// FileTreatmentStore.swift - File-based treatment persistence
// Extracted from DataPersistence.swift (DATA-REFACTOR-002)
// Requirements: DATA-SCALE-002, DATA-FAULT-005

import Foundation

// MARK: - File-Based Treatment Store

/// JSON file-based persistence for treatments.
/// DATA-SCALE-002: Includes timing instrumentation for performance monitoring
/// DATA-FAULT-005: Supports fault injection for resilience testing
public actor FileTreatmentStore: TreatmentStore {
    private let fileURL: URL
    private var treatments: [UUID: Treatment] = [:]
    private var isDirty = false
    
    /// Metrics collector for timing instrumentation (DATA-SCALE-002)
    private let metrics: any MetricsCollector
    
    /// Fault injector for resilience testing (DATA-FAULT-005)
    private let faultInjector: FaultInjector
    
    public init(
        directory: URL,
        filename: String = "treatments.json",
        metrics: (any MetricsCollector)? = nil,
        faultInjector: FaultInjector = .shared
    ) {
        self.fileURL = directory.appendingPathComponent(filename)
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        self.faultInjector = faultInjector
    }
    
    /// Initialize with default app support directory.
    public static func defaultStore() -> FileTreatmentStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileTreatmentStore(directory: directory)
    }
    
    private func loadIfNeeded() async throws {
        guard treatments.isEmpty else { return }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        // DATA-SCALE-002: Time the load operation
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("treatment_store.load", duration: duration, tags: ["count": "\(treatments.count)"])
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([Treatment].self, from: data)
            for treatment in loaded {
                treatments[treatment.id] = treatment
            }
        } catch {
            throw PersistenceError.decodingFailed(error.localizedDescription)
        }
    }
    
    private func saveIfDirty() async throws {
        guard isDirty else { return }
        
        // DATA-FAULT-005: Check for fault injection before save
        if faultInjector.shouldFaultOnSave() {
            try faultInjector.injectFault()
        }
        
        // DATA-SCALE-002: Time the save operation
        let startTime = Date().timeIntervalSinceReferenceDate
        let count = treatments.count
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("treatment_store.save", duration: duration, tags: ["count": "\(count)"])
        }
        
        let allTreatments = Array(treatments.values)
        do {
            let data = try JSONEncoder().encode(allTreatments)
            try data.write(to: fileURL, options: .atomic)
            isDirty = false
        } catch {
            throw PersistenceError.encodingFailed(error.localizedDescription)
        }
    }
    
    public func save(_ treatment: Treatment) async throws {
        try await loadIfNeeded()
        treatments[treatment.id] = treatment
        isDirty = true
        try await saveIfDirty()
    }
    
    public func save(_ treatments: [Treatment]) async throws {
        try await loadIfNeeded()
        for treatment in treatments {
            self.treatments[treatment.id] = treatment
        }
        isDirty = true
        try await saveIfDirty()
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [Treatment] {
        // DATA-SCALE-002: Time the fetch operation
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = treatments.values
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp > $1.timestamp }
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("treatment_store.fetch_range", duration: duration, tags: ["result_count": "\(result.count)"])
        return result
    }
    
    public func fetch(type: PersistenceTreatmentType, from start: Date, to end: Date) async throws -> [Treatment] {
        // DATA-SCALE-002: Time the fetch operation
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = treatments.values
            .filter { $0.type == type && $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp > $1.timestamp }
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("treatment_store.fetch_by_type", duration: duration, tags: ["type": "\(type)", "result_count": "\(result.count)"])
        return result
    }
    
    public func fetchLatest(_ count: Int) async throws -> [Treatment] {
        // DATA-SCALE-002: Time the fetch operation
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = Array(treatments.values
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(count))
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("treatment_store.fetch_latest", duration: duration, tags: ["requested": "\(count)", "returned": "\(result.count)"])
        return result
    }
    
    /// DATA-COHESIVE-001: Fetch the most recent treatment
    public func fetchMostRecent() async throws -> Treatment? {
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = treatments.values.max { $0.timestamp < $1.timestamp }
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("treatment_store.fetch_most_recent", duration: duration, tags: ["found": result != nil ? "true" : "false"])
        return result
    }
    
    public func fetch(syncIdentifier: String) async throws -> Treatment? {
        // DATA-SCALE-002: Time the fetch operation
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = treatments.values.first { $0.syncIdentifier == syncIdentifier }
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("treatment_store.fetch_by_sync_id", duration: duration, tags: ["found": result != nil ? "true" : "false"])
        return result
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        try await loadIfNeeded()
        let toDelete = treatments.values.filter { $0.timestamp < date }
        for treatment in toDelete {
            treatments.removeValue(forKey: treatment.id)
        }
        if !toDelete.isEmpty {
            isDirty = true
            try await saveIfDirty()
        }
        return toDelete.count
    }
    
    public func deleteAll() async throws {
        treatments.removeAll()
        isDirty = true
        try await saveIfDirty()
    }
    
    public func count() async throws -> Int {
        try await loadIfNeeded()
        return treatments.count
    }
}
