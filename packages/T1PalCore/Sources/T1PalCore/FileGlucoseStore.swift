// SPDX-License-Identifier: AGPL-3.0-or-later
// FileGlucoseStore.swift - File-based glucose reading persistence
// Extracted from DataPersistence.swift (DATA-REFACTOR-001)
// Requirements: DATA-SCALE-001, DATA-FAULT-001, DATA-FAULT-002

import Foundation

// MARK: - File-Based Glucose Store

/// JSON file-based persistence for readings.
/// DATA-SCALE-001: Includes timing instrumentation for performance monitoring
/// DATA-FAULT-001: Supports fault injection for resilience testing
public actor FileGlucoseStore: GlucoseStore {
    private let fileURL: URL
    private var readings: [UUID: GlucoseReading] = [:]
    private var isDirty = false
    
    /// Metrics collector for timing instrumentation (DATA-SCALE-001)
    private let metrics: any MetricsCollector
    
    /// Fault injector for resilience testing (DATA-FAULT-001)
    private let faultInjector: FaultInjector
    
    public init(
        directory: URL,
        filename: String = "glucose-readings.json",
        metrics: (any MetricsCollector)? = nil,
        faultInjector: FaultInjector = .shared
    ) {
        self.fileURL = directory.appendingPathComponent(filename)
        self.metrics = metrics ?? MetricsCollectorFactory.create()
        self.faultInjector = faultInjector
    }
    
    /// Initialize with default app support directory.
    public static func defaultStore() -> FileGlucoseStore {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileGlucoseStore(directory: directory)
    }
    
    private func loadIfNeeded() async throws {
        guard readings.isEmpty else { return }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        
        // DATA-SCALE-001: Time the load operation
        let startTime = Date().timeIntervalSinceReferenceDate
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("glucose_store.load", duration: duration, tags: ["count": "\(readings.count)"])
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let loaded = try JSONDecoder().decode([GlucoseReading].self, from: data)
            for reading in loaded {
                readings[reading.id] = reading
            }
        } catch {
            // DATA-FAULT-002: Attempt recovery from corrupted JSON
            if let recovered = await attemptRecovery() {
                for reading in recovered {
                    readings[reading.id] = reading
                }
                metrics.incrementCounter("glucose_store.corruption_recovered", value: 1, tags: ["count": "\(recovered.count)"])
            } else {
                throw PersistenceError.decodingFailed(error.localizedDescription)
            }
        }
    }
    
    /// DATA-FAULT-002: Attempt to recover from corrupted JSON.
    /// First tries backup file, then attempts partial recovery from main file.
    private func attemptRecovery() async -> [GlucoseReading]? {
        // Check for backup file
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("backup.json")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            do {
                let backupData = try Data(contentsOf: backupURL)
                let recovered = try JSONDecoder().decode([GlucoseReading].self, from: backupData)
                // Restore from backup and create new backup of corrupted file
                try? FileManager.default.moveItem(at: fileURL, to: fileURL.appendingPathExtension("corrupted"))
                try? FileManager.default.copyItem(at: backupURL, to: fileURL)
                return recovered
            } catch {
                // Backup also corrupted, continue to partial recovery
            }
        }
        
        // Attempt partial recovery by finding valid JSON array elements
        do {
            let data = try Data(contentsOf: fileURL)
            let recovered = try partialJSONRecovery(data: data)
            if !recovered.isEmpty {
                return recovered
            }
        } catch {
            // Partial recovery failed
        }
        
        return nil
    }
    
    /// Attempt to recover individual valid reading objects from corrupted JSON.
    private func partialJSONRecovery(data: Data) throws -> [GlucoseReading] {
        guard let jsonString = String(data: data, encoding: .utf8) else { return [] }
        
        // Try to find and parse individual JSON objects within the array
        var recovered: [GlucoseReading] = []
        let pattern = #"\{[^{}]*"glucose"[^{}]*\}"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(jsonString.startIndex..., in: jsonString)
            let matches = regex.matches(in: jsonString, options: [], range: range)
            
            for match in matches {
                if let matchRange = Range(match.range, in: jsonString) {
                    let objectString = String(jsonString[matchRange])
                    if let objectData = objectString.data(using: .utf8),
                       let reading = try? JSONDecoder().decode(GlucoseReading.self, from: objectData) {
                        recovered.append(reading)
                    }
                }
            }
        }
        
        return recovered
    }
    
    private func saveIfDirty() async throws {
        guard isDirty else { return }
        
        // DATA-FAULT-001: Check for fault injection before save
        if faultInjector.shouldFaultOnSave() {
            try faultInjector.injectFault()
        }
        
        // DATA-SCALE-001: Time the save operation
        let startTime = Date().timeIntervalSinceReferenceDate
        let count = readings.count
        defer {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            metrics.recordTiming("glucose_store.save", duration: duration, tags: ["count": "\(count)"])
        }
        
        // DATA-FAULT-002: Create backup before saving
        let backupURL = fileURL.deletingPathExtension().appendingPathExtension("backup.json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        
        let allReadings = Array(readings.values)
        do {
            let data = try JSONEncoder().encode(allReadings)
            try data.write(to: fileURL, options: .atomic)
            isDirty = false
        } catch {
            throw PersistenceError.encodingFailed(error.localizedDescription)
        }
    }
    
    public func save(_ reading: GlucoseReading) async throws {
        try await loadIfNeeded()
        readings[reading.id] = reading
        isDirty = true
        try await saveIfDirty()
    }
    
    public func save(_ readings: [GlucoseReading]) async throws {
        try await loadIfNeeded()
        for reading in readings {
            self.readings[reading.id] = reading
        }
        isDirty = true
        try await saveIfDirty()
    }
    
    public func fetch(from start: Date, to end: Date) async throws -> [GlucoseReading] {
        // DATA-SCALE-001: Time the fetch operation
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = readings.values
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp > $1.timestamp }
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("glucose_store.fetch_range", duration: duration, tags: ["result_count": "\(result.count)"])
        return result
    }
    
    public func fetchLatest(_ count: Int) async throws -> [GlucoseReading] {
        // DATA-SCALE-001: Time the fetch operation
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = Array(readings.values
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(count))
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("glucose_store.fetch_latest", duration: duration, tags: ["requested": "\(count)", "returned": "\(result.count)"])
        return result
    }
    
    public func fetchMostRecent() async throws -> GlucoseReading? {
        // DATA-SCALE-001: Time the fetch operation
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = readings.values.max { $0.timestamp < $1.timestamp }
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("glucose_store.fetch_most_recent", duration: duration, tags: ["found": result != nil ? "true" : "false"])
        return result
    }
    
    /// DATA-COHESIVE-001: Fetch by sync identifier for deduplication
    public func fetch(syncIdentifier: String) async throws -> GlucoseReading? {
        let startTime = Date().timeIntervalSinceReferenceDate
        try await loadIfNeeded()
        let result = readings.values.first { $0.syncIdentifier == syncIdentifier }
        let duration = Date().timeIntervalSinceReferenceDate - startTime
        metrics.recordTiming("glucose_store.fetch_sync_id", duration: duration, tags: ["found": result != nil ? "true" : "false"])
        return result
    }
    
    public func deleteOlderThan(_ date: Date) async throws -> Int {
        try await loadIfNeeded()
        let toDelete = readings.values.filter { $0.timestamp < date }
        for reading in toDelete {
            readings.removeValue(forKey: reading.id)
        }
        if !toDelete.isEmpty {
            isDirty = true
            try await saveIfDirty()
        }
        return toDelete.count
    }
    
    public func deleteAll() async throws {
        readings.removeAll()
        isDirty = true
        try await saveIfDirty()
    }
    
    public func count() async throws -> Int {
        try await loadIfNeeded()
        return readings.count
    }
}
