// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LogPersistence.swift
// BLEKit
//
// Log persistence infrastructure for BLE traffic logs.
// Supports file-based storage with rotation and UserDefaults storage.
// Trace: BLE-DIAG-013, PRD-010, REQ-DEBUG
//

import Foundation

// MARK: - Log Persistence Protocol

/// Protocol for persisting BLE traffic logs across app restarts.
public protocol LogPersistence: Sendable {
    /// Save traffic entries
    /// - Parameter entries: Entries to save
    /// - Throws: Persistence errors
    func save(_ entries: [TrafficEntry]) async throws
    
    /// Load persisted traffic entries
    /// - Returns: Previously saved entries
    /// - Throws: Persistence errors
    func load() async throws -> [TrafficEntry]
    
    /// Clear all persisted entries
    /// - Throws: Persistence errors
    func clear() async throws
    
    /// Get metadata about persisted logs
    /// - Returns: Persistence metadata
    func metadata() async -> LogPersistenceMetadata
}

// MARK: - Log Persistence Metadata

/// Metadata about persisted logs
public struct LogPersistenceMetadata: Sendable, Codable {
    /// Number of persisted entries
    public let entryCount: Int
    
    /// Size in bytes (approximate)
    public let sizeBytes: Int
    
    /// Oldest entry timestamp
    public let oldestEntry: Date?
    
    /// Newest entry timestamp
    public let newestEntry: Date?
    
    /// Last save timestamp
    public let lastSaved: Date?
    
    /// Storage location description
    public let storageLocation: String
    
    public init(
        entryCount: Int = 0,
        sizeBytes: Int = 0,
        oldestEntry: Date? = nil,
        newestEntry: Date? = nil,
        lastSaved: Date? = nil,
        storageLocation: String = "unknown"
    ) {
        self.entryCount = entryCount
        self.sizeBytes = sizeBytes
        self.oldestEntry = oldestEntry
        self.newestEntry = newestEntry
        self.lastSaved = lastSaved
        self.storageLocation = storageLocation
    }
    
    public static let empty = LogPersistenceMetadata()
}

// MARK: - Log Persistence Errors

/// Errors from log persistence operations
public enum LogPersistenceError: Error, LocalizedError {
    case encodingFailed(String)
    case decodingFailed(String)
    case writeError(String)
    case readError(String)
    case directoryCreationFailed(String)
    case rotationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let detail):
            return "Failed to encode log entries: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to decode log entries: \(detail)"
        case .writeError(let detail):
            return "Failed to write log file: \(detail)"
        case .readError(let detail):
            return "Failed to read log file: \(detail)"
        case .directoryCreationFailed(let detail):
            return "Failed to create log directory: \(detail)"
        case .rotationFailed(let detail):
            return "Failed to rotate log files: \(detail)"
        }
    }
}

// MARK: - File Log Persistence

/// File-based log persistence with rotation support.
/// Stores logs as JSON files in a designated directory.
public actor FileLogPersistence: LogPersistence {
    
    // MARK: - Configuration
    
    /// Configuration for file-based persistence
    public struct Config: Sendable {
        /// Maximum file size before rotation (bytes)
        public let maxFileSize: Int
        
        /// Maximum number of rotated files to keep
        public let maxRotatedFiles: Int
        
        /// Maximum age of log files (seconds, 0 = no limit)
        public let maxAge: TimeInterval
        
        /// Base filename for logs
        public let baseFilename: String
        
        /// Directory for log files
        public let directory: URL
        
        public init(
            maxFileSize: Int = 5 * 1024 * 1024, // 5 MB
            maxRotatedFiles: Int = 5,
            maxAge: TimeInterval = 7 * 24 * 3600, // 7 days
            baseFilename: String = "ble-traffic",
            directory: URL? = nil
        ) {
            self.maxFileSize = maxFileSize
            self.maxRotatedFiles = maxRotatedFiles
            self.maxAge = maxAge
            self.baseFilename = baseFilename
            self.directory = directory ?? FileLogPersistence.defaultDirectory
        }
        
        /// Default configuration
        public static let `default` = Config()
        
        /// Testing configuration (smaller limits)
        public static let testing = Config(
            maxFileSize: 1024, // 1 KB
            maxRotatedFiles: 2,
            maxAge: 60, // 1 minute
            baseFilename: "test-ble-traffic"
        )
    }
    
    // MARK: - Properties
    
    private let config: Config
    private var lastSaved: Date?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    /// Default log directory
    public static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("BLEKit/Logs", isDirectory: true)
    }
    
    /// Current log file URL
    private var currentLogFile: URL {
        config.directory.appendingPathComponent("\(config.baseFilename).json")
    }
    
    // MARK: - Initialization
    
    public init(config: Config = .default) {
        self.config = config
        
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - LogPersistence
    
    public func save(_ entries: [TrafficEntry]) async throws {
        // Ensure directory exists
        try ensureDirectoryExists()
        
        // Encode entries
        let data: Data
        do {
            data = try encoder.encode(entries)
        } catch {
            throw LogPersistenceError.encodingFailed(error.localizedDescription)
        }
        
        // Check if rotation needed
        if shouldRotate(newDataSize: data.count) {
            try rotate()
        }
        
        // Write to file
        do {
            try data.write(to: currentLogFile, options: .atomic)
            lastSaved = Date()
        } catch {
            throw LogPersistenceError.writeError(error.localizedDescription)
        }
        
        // Clean old files
        try cleanOldFiles()
    }
    
    public func load() async throws -> [TrafficEntry] {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: currentLogFile.path) else {
            return []
        }
        
        let data: Data
        do {
            data = try Data(contentsOf: currentLogFile)
        } catch {
            throw LogPersistenceError.readError(error.localizedDescription)
        }
        
        do {
            return try decoder.decode([TrafficEntry].self, from: data)
        } catch {
            throw LogPersistenceError.decodingFailed(error.localizedDescription)
        }
    }
    
    public func clear() async throws {
        let fileManager = FileManager.default
        
        // Remove current log file
        if fileManager.fileExists(atPath: currentLogFile.path) {
            try fileManager.removeItem(at: currentLogFile)
        }
        
        // Remove rotated files
        let rotatedFiles = try listRotatedFiles()
        for file in rotatedFiles {
            try? fileManager.removeItem(at: file)
        }
        
        lastSaved = nil
    }
    
    public func metadata() async -> LogPersistenceMetadata {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: currentLogFile.path) else {
            return LogPersistenceMetadata(storageLocation: config.directory.path)
        }
        
        do {
            let entries = try await load()
            let attributes = try fileManager.attributesOfItem(atPath: currentLogFile.path)
            let fileSize = attributes[.size] as? Int ?? 0
            
            return LogPersistenceMetadata(
                entryCount: entries.count,
                sizeBytes: fileSize,
                oldestEntry: entries.first?.timestamp,
                newestEntry: entries.last?.timestamp,
                lastSaved: lastSaved,
                storageLocation: config.directory.path
            )
        } catch {
            return LogPersistenceMetadata(storageLocation: config.directory.path)
        }
    }
    
    // MARK: - File Management
    
    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: config.directory.path) {
            do {
                try fileManager.createDirectory(at: config.directory, withIntermediateDirectories: true)
            } catch {
                throw LogPersistenceError.directoryCreationFailed(error.localizedDescription)
            }
        }
    }
    
    private func shouldRotate(newDataSize: Int) -> Bool {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: currentLogFile.path) else {
            return false
        }
        
        do {
            let attributes = try fileManager.attributesOfItem(atPath: currentLogFile.path)
            let currentSize = attributes[.size] as? Int ?? 0
            return currentSize + newDataSize > config.maxFileSize
        } catch {
            return false
        }
    }
    
    private func rotate() throws {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: currentLogFile.path) else {
            return
        }
        
        // Generate rotated filename with timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        
        let rotatedFile = config.directory
            .appendingPathComponent("\(config.baseFilename)-\(timestamp).json")
        
        do {
            try fileManager.moveItem(at: currentLogFile, to: rotatedFile)
        } catch {
            throw LogPersistenceError.rotationFailed(error.localizedDescription)
        }
        
        // Trim excess rotated files
        try trimRotatedFiles()
    }
    
    private func listRotatedFiles() throws -> [URL] {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: config.directory.path) else {
            return []
        }
        
        let contents = try fileManager.contentsOfDirectory(at: config.directory, includingPropertiesForKeys: [.creationDateKey])
        
        return contents.filter { url in
            let filename = url.lastPathComponent
            return filename.hasPrefix(config.baseFilename + "-") && filename.hasSuffix(".json")
        }.sorted { url1, url2 in
            // Sort by creation date, newest first
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return date1 > date2
        }
    }
    
    private func trimRotatedFiles() throws {
        let fileManager = FileManager.default
        let rotatedFiles = try listRotatedFiles()
        
        // Remove excess files
        if rotatedFiles.count > config.maxRotatedFiles {
            for file in rotatedFiles.dropFirst(config.maxRotatedFiles) {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    private func cleanOldFiles() throws {
        guard config.maxAge > 0 else { return }
        
        let fileManager = FileManager.default
        let cutoffDate = Date().addingTimeInterval(-config.maxAge)
        
        let rotatedFiles = try listRotatedFiles()
        
        for file in rotatedFiles {
            if let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               creationDate < cutoffDate {
                try? fileManager.removeItem(at: file)
            }
        }
    }
    
    // MARK: - Additional Methods
    
    /// Load all entries from current and rotated files
    public func loadAll() async throws -> [TrafficEntry] {
        var allEntries: [TrafficEntry] = []
        
        // Load current file
        allEntries.append(contentsOf: try await load())
        
        // Load rotated files
        let rotatedFiles = try listRotatedFiles()
        for file in rotatedFiles {
            if let data = try? Data(contentsOf: file),
               let entries = try? decoder.decode([TrafficEntry].self, from: data) {
                allEntries.append(contentsOf: entries)
            }
        }
        
        // Sort by timestamp
        return allEntries.sorted { $0.timestamp < $1.timestamp }
    }
    
    /// Get total size of all log files
    public func totalSize() -> Int {
        let fileManager = FileManager.default
        var total = 0
        
        // Current file
        if let attrs = try? fileManager.attributesOfItem(atPath: currentLogFile.path),
           let size = attrs[.size] as? Int {
            total += size
        }
        
        // Rotated files
        if let rotated = try? listRotatedFiles() {
            for file in rotated {
                if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                   let size = attrs[.size] as? Int {
                    total += size
                }
            }
        }
        
        return total
    }
}

// MARK: - UserDefaults Log Persistence

/// Simple UserDefaults-based log persistence.
/// Suitable for smaller log volumes where file I/O overhead isn't justified.
public actor UserDefaultsLogPersistence: LogPersistence {
    
    // MARK: - Configuration
    
    /// Configuration for UserDefaults persistence
    public struct Config: Sendable {
        /// Maximum entries to persist
        public let maxEntries: Int
        
        /// UserDefaults suite name (nil for standard)
        public let suiteName: String?
        
        /// Key for storing entries
        public let storageKey: String
        
        public init(
            maxEntries: Int = 1000,
            suiteName: String? = nil,
            storageKey: String = "com.t1pal.blekit.traffic-log"
        ) {
            self.maxEntries = maxEntries
            self.suiteName = suiteName
            self.storageKey = storageKey
        }
        
        /// Default configuration
        public static let `default` = Config()
        
        /// Testing configuration
        public static let testing = Config(
            maxEntries: 100,
            storageKey: "com.t1pal.blekit.traffic-log-test"
        )
    }
    
    // MARK: - Properties
    
    private let config: Config
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastSaved: Date?
    private var cachedEntries: [TrafficEntry] = []  // Cache for metadata
    
    // MARK: - Initialization
    
    public init(config: Config = .default) {
        self.config = config
        self.userDefaults = config.suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - LogPersistence
    
    public func save(_ entries: [TrafficEntry]) async throws {
        // Trim to max entries
        let entriesToSave = entries.count > config.maxEntries
            ? Array(entries.suffix(config.maxEntries))
            : entries
        
        // Encode
        let data: Data
        do {
            data = try encoder.encode(entriesToSave)
        } catch {
            throw LogPersistenceError.encodingFailed(error.localizedDescription)
        }
        
        // Save
        userDefaults.set(data, forKey: config.storageKey)
        userDefaults.synchronize()  // Force immediate write (helps on Linux)
        cachedEntries = entriesToSave  // Cache for immediate metadata access
        lastSaved = Date()
    }
    
    public func load() async throws -> [TrafficEntry] {
        guard let data = userDefaults.data(forKey: config.storageKey) else {
            return []
        }
        
        do {
            return try decoder.decode([TrafficEntry].self, from: data)
        } catch {
            throw LogPersistenceError.decodingFailed(error.localizedDescription)
        }
    }
    
    public func clear() async throws {
        userDefaults.removeObject(forKey: config.storageKey)
        userDefaults.synchronize()
        cachedEntries = []
        lastSaved = nil
    }
    
    public func metadata() async -> LogPersistenceMetadata {
        // Use cached entries if available (avoids Linux UserDefaults sync issues)
        if !cachedEntries.isEmpty {
            let data = try? encoder.encode(cachedEntries)
            return LogPersistenceMetadata(
                entryCount: cachedEntries.count,
                sizeBytes: data?.count ?? 0,
                oldestEntry: cachedEntries.first?.timestamp,
                newestEntry: cachedEntries.last?.timestamp,
                lastSaved: lastSaved,
                storageLocation: "UserDefaults:\(config.storageKey)"
            )
        }
        
        // Fall back to reading from UserDefaults
        guard let data = userDefaults.data(forKey: config.storageKey) else {
            return LogPersistenceMetadata(storageLocation: "UserDefaults")
        }
        
        do {
            let entries = try decoder.decode([TrafficEntry].self, from: data)
            
            return LogPersistenceMetadata(
                entryCount: entries.count,
                sizeBytes: data.count,
                oldestEntry: entries.first?.timestamp,
                newestEntry: entries.last?.timestamp,
                lastSaved: lastSaved,
                storageLocation: "UserDefaults:\(config.storageKey)"
            )
        } catch {
            return LogPersistenceMetadata(storageLocation: "UserDefaults")
        }
    }
}

// MARK: - In-Memory Persistence (for testing)

/// In-memory persistence for testing purposes.
public actor InMemoryLogPersistence: LogPersistence {
    private var entries: [TrafficEntry] = []
    private var lastSaved: Date?
    
    public init() {}
    
    public func save(_ entries: [TrafficEntry]) async throws {
        self.entries = entries
        self.lastSaved = Date()
    }
    
    public func load() async throws -> [TrafficEntry] {
        return entries
    }
    
    public func clear() async throws {
        entries.removeAll()
        lastSaved = nil
    }
    
    public func metadata() async -> LogPersistenceMetadata {
        LogPersistenceMetadata(
            entryCount: entries.count,
            sizeBytes: 0,
            oldestEntry: entries.first?.timestamp,
            newestEntry: entries.last?.timestamp,
            lastSaved: lastSaved,
            storageLocation: "InMemory"
        )
    }
}

// MARK: - BLETrafficLogger Persistence Extension

extension BLETrafficLogger {
    
    /// Save current entries to persistence
    /// - Parameter persistence: Persistence provider
    public func save(to persistence: any LogPersistence) async throws {
        let entriesToSave = allEntries()
        try await persistence.save(entriesToSave)
    }
    
    /// Load entries from persistence
    /// - Parameter persistence: Persistence provider
    /// - Parameter append: If true, append to existing entries; if false, replace
    public func load(from persistence: any LogPersistence, append: Bool = false) async throws {
        let loadedEntries = try await persistence.load()
        
        if append {
            appendEntries(loadedEntries)
        } else {
            replaceEntries(loadedEntries)
        }
    }
    
    /// Clear persistence
    /// - Parameter persistence: Persistence provider
    public func clearPersistence(_ persistence: any LogPersistence) async throws {
        try await persistence.clear()
    }
    
    /// Get persistence metadata
    /// - Parameter persistence: Persistence provider
    /// - Returns: Metadata about persisted logs
    public func persistenceMetadata(_ persistence: any LogPersistence) async -> LogPersistenceMetadata {
        await persistence.metadata()
    }
}

// MARK: - Auto-Persisting Logger State

/// Actor to track auto-persist state safely
private actor AutoPersistState {
    var unsavedCount: Int = 0
    
    func increment() -> Int {
        unsavedCount += 1
        return unsavedCount
    }
    
    func reset() {
        unsavedCount = 0
    }
}

// MARK: - Auto-Persisting Logger

/// A traffic logger that automatically persists entries.
public final class AutoPersistingTrafficLogger: @unchecked Sendable {
    
    /// The underlying logger
    public let logger: BLETrafficLogger
    
    /// Persistence provider
    private let persistence: any LogPersistence
    
    /// Auto-save interval (seconds, 0 = disabled)
    public var autoSaveInterval: TimeInterval
    
    /// Timer for auto-save (uses Task-based approach)
    private var autoSaveTask: Task<Void, Never>?
    
    /// State tracking actor
    private let state = AutoPersistState()
    
    /// Save after this many new entries (0 = disabled)
    public var saveThreshold: Int
    
    public init(
        persistence: any LogPersistence,
        maxEntries: Int = 10000,
        autoSaveInterval: TimeInterval = 60, // 1 minute
        saveThreshold: Int = 100
    ) {
        self.logger = BLETrafficLogger(maxEntries: maxEntries)
        self.persistence = persistence
        self.autoSaveInterval = autoSaveInterval
        self.saveThreshold = saveThreshold
        
        // Start auto-save if interval > 0
        if autoSaveInterval > 0 {
            startAutoSave()
        }
    }
    
    deinit {
        autoSaveTask?.cancel()
    }
    
    /// Log and optionally trigger save
    @discardableResult
    public func log(
        direction: TrafficDirection,
        data: Data,
        characteristic: String? = nil,
        service: String? = nil,
        note: String? = nil
    ) -> TrafficEntry? {
        let entry = logger.log(
            direction: direction,
            data: data,
            characteristic: characteristic,
            service: service,
            note: note
        )
        
        if entry != nil {
            Task {
                let count = await state.increment()
                let shouldSave = saveThreshold > 0 && count >= saveThreshold
                
                if shouldSave {
                    await saveNow()
                }
            }
        }
        
        return entry
    }
    
    /// Save immediately
    public func saveNow() async {
        do {
            try await logger.save(to: persistence)
            await state.reset()
        } catch {
            // Log error but don't throw
            BLELogger.data.error("Auto-save failed: \(error.localizedDescription)")
        }
    }
    
    /// Load from persistence
    public func loadFromPersistence() async throws {
        try await logger.load(from: persistence)
    }
    
    /// Start auto-save timer
    public func startAutoSave() {
        guard autoSaveInterval > 0 else { return }
        
        autoSaveTask?.cancel()
        
        autoSaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.autoSaveInterval ?? 60) * 1_000_000_000)
                
                if Task.isCancelled { break }
                
                await self?.saveNow()
            }
        }
    }
    
    /// Stop auto-save timer
    public func stopAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }
    
    /// Get persistence metadata
    public func metadata() async -> LogPersistenceMetadata {
        await persistence.metadata()
    }
}
