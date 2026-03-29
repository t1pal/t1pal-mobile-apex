// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// DataSourceManager.swift - Manages multiple glucose data sources
// Part of T1PalCore
//
// Provides a unified interface for switching between data sources
// and accessing glucose data from the active source.

import Foundation

// MARK: - DataSourceManager

/// Manages multiple glucose data sources with a single active source
public actor DataSourceManager: DataSourceManagerProtocol {
    // MARK: - Properties
    
    private var registeredSources: [String: any GlucoseDataSource] = [:]
    private var activeSourceId: String?
    
    // Observers for source changes
    private var observers: [SourceChangeObserver] = []
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide data source management
    public static let shared = DataSourceManager()
    
    public init() {}
    
    // MARK: - DataSourceManagerProtocol
    
    public var sources: [any GlucoseDataSource] {
        get async { Array(registeredSources.values) }
    }
    
    public var activeSource: (any GlucoseDataSource)? {
        get async {
            guard let id = activeSourceId else { return nil }
            return registeredSources[id]
        }
    }
    
    public func setActiveSource(_ source: any GlucoseDataSource) async {
        activeSourceId = source.id
        notifyObservers()
    }
    
    public func fetchRecentReadings(count: Int) async throws -> [GlucoseReading] {
        guard let source = await activeSource else {
            throw DataSourceError.notConfigured
        }
        return try await source.fetchRecentReadings(count: count)
    }
    
    // MARK: - Source Registration
    
    /// Register a data source
    public func register(_ source: any GlucoseDataSource) {
        registeredSources[source.id] = source
        
        // Auto-activate if first source
        if activeSourceId == nil {
            activeSourceId = source.id
            notifyObservers()
        }
    }
    
    /// Unregister a data source
    public func unregister(id: String) {
        registeredSources.removeValue(forKey: id)
        
        // Clear active if it was unregistered
        if activeSourceId == id {
            activeSourceId = registeredSources.keys.first
            notifyObservers()
        }
    }
    
    /// Get a specific source by ID
    public func source(withId id: String) -> (any GlucoseDataSource)? {
        registeredSources[id]
    }
    
    /// Set active source by ID
    public func setActiveSource(id: String) -> Bool {
        guard registeredSources[id] != nil else { return false }
        activeSourceId = id
        notifyObservers()
        return true
    }
    
    // MARK: - Convenience Methods
    
    /// Fetch readings from the active source within a time range
    public func fetchReadings(from: Date, to: Date) async throws -> [GlucoseReading] {
        guard let source = await activeSource else {
            throw DataSourceError.notConfigured
        }
        return try await source.fetchReadings(from: from, to: to)
    }
    
    /// Get the latest reading from the active source
    public func latestReading() async throws -> GlucoseReading? {
        guard let source = await activeSource else {
            throw DataSourceError.notConfigured
        }
        return try await source.latestReading()
    }
    
    /// Get status of the active source
    public func activeSourceStatus() async -> DataSourceStatus {
        guard let source = await activeSource else {
            return .configurationRequired
        }
        return await source.status
    }
    
    // MARK: - Observers
    
    /// Observer callback type
    public typealias SourceChangeObserver = @Sendable () -> Void
    
    /// Add an observer for source changes
    public func addObserver(_ observer: @escaping SourceChangeObserver) {
        observers.append(observer)
    }
    
    /// Remove all observers
    public func removeAllObservers() {
        observers.removeAll()
    }
    
    private func notifyObservers() {
        for observer in observers {
            observer()
        }
    }
}

// MARK: - Source List View Model Support

public extension DataSourceManager {
    /// Get source info for UI display
    struct SourceInfo: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let isActive: Bool
        public let status: DataSourceStatus
    }
    
    /// Get all source info for UI
    func allSourceInfo() async -> [SourceInfo] {
        var infos: [SourceInfo] = []
        for source in registeredSources.values {
            let status = await source.status
            infos.append(SourceInfo(
                id: source.id,
                name: source.name,
                isActive: source.id == activeSourceId,
                status: status
            ))
        }
        return infos.sorted { $0.name < $1.name }
    }
}
