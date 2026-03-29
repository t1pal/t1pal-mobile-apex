// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CGMSourceSwitcher.swift
// T1Pal Mobile
//
// Hot-swap between CGM sources at runtime
// Requirements: REQ-CGM-009, DEBUG-ETU-003

import Foundation
import T1PalCore

/// Registered CGM source with identifier
public struct RegisteredCGMSource: Sendable {
    public let id: String
    public let name: String
    public let source: any CGMManagerProtocol
    
    public init(id: String, name: String, source: any CGMManagerProtocol) {
        self.id = id
        self.name = name
        self.source = source
    }
}

/// CGM source switcher - enables runtime hot-swap between CGM sources
/// Requirements: REQ-CGM-009, DEBUG-ETU-003
public actor CGMSourceSwitcher: CGMManagerProtocol {
    public let displayName = "CGM Source Switcher"
    public let cgmType = CGMType.simulation
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    /// Callback when source is switched
    public var onSourceSwitched: (@Sendable (String) -> Void)?
    
    /// All registered sources
    private var sources: [String: any CGMManagerProtocol] = [:]
    private var sourceNames: [String: String] = [:]
    
    /// Currently active source ID
    private var activeSourceId: String?
    
    public init() {}
    
    /// Register a CGM source
    /// - Parameters:
    ///   - id: Unique identifier for this source
    ///   - name: Human-readable name
    ///   - source: The CGM manager instance
    public func register(id: String, name: String, source: any CGMManagerProtocol) {
        sources[id] = source
        sourceNames[id] = name
    }
    
    /// Register a source using RegisteredCGMSource
    public func register(_ registered: RegisteredCGMSource) {
        sources[registered.id] = registered.source
        sourceNames[registered.id] = registered.name
    }
    
    /// Remove a registered source
    public func unregister(id: String) async {
        // Disconnect if this is the active source
        if activeSourceId == id {
            await disconnect()
        }
        sources.removeValue(forKey: id)
        sourceNames.removeValue(forKey: id)
    }
    
    /// Get list of registered source IDs
    public var registeredSourceIds: [String] {
        Array(sources.keys).sorted()
    }
    
    /// Get name for a source ID
    public func sourceName(for id: String) -> String? {
        sourceNames[id]
    }
    
    /// Get the currently active source ID
    public var currentSourceId: String? {
        activeSourceId
    }
    
    /// Switch to a different CGM source
    /// - Parameter id: The source ID to switch to
    /// - Throws: CGMError if source not found or switch fails
    public func switchTo(id: String) async throws {
        guard let newSource = sources[id] else {
            throw CGMError.deviceNotFound
        }
        
        // Disconnect current source if any
        if let currentId = activeSourceId, let currentSource = sources[currentId] {
            await currentSource.disconnect()
        }
        
        // Connect new source
        let cgmType = await newSource.cgmType
        let sensorInfo = SensorInfo(id: id, name: sourceNames[id] ?? id, type: cgmType)
        try await newSource.connect(to: sensorInfo)
        
        activeSourceId = id
        sensorState = await newSource.sensorState
        onSourceSwitched?(id)
    }
    
    /// Switch to a source by index in the registered list
    public func switchTo(index: Int) async throws {
        let ids = registeredSourceIds
        guard index >= 0 && index < ids.count else {
            throw CGMError.deviceNotFound
        }
        try await switchTo(id: ids[index])
    }
    
    /// Cycle to the next source (wraps around)
    public func cycleNext() async throws {
        let ids = registeredSourceIds
        guard !ids.isEmpty else {
            throw CGMError.deviceNotFound
        }
        
        if let currentId = activeSourceId,
           let currentIndex = ids.firstIndex(of: currentId) {
            let nextIndex = (currentIndex + 1) % ids.count
            try await switchTo(id: ids[nextIndex])
        } else {
            try await switchTo(id: ids[0])
        }
    }
    
    // MARK: - CGMManagerProtocol
    
    public func startScanning() async throws {
        // Start scanning on first registered source
        guard let firstId = registeredSourceIds.first,
              let source = sources[firstId] else {
            sensorState = .failed
            onSensorStateChanged?(.failed)
            throw CGMError.deviceNotFound
        }
        
        try await source.startScanning()
        sensorState = await source.sensorState
        onSensorStateChanged?(sensorState)
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        // Connect using the sensor ID as source ID
        try await switchTo(id: sensor.id)
    }
    
    public func disconnect() async {
        if let currentId = activeSourceId,
           let source = sources[currentId] {
            await source.disconnect()
        }
        activeSourceId = nil
        sensorState = .stopped
        onSensorStateChanged?(.stopped)
    }
    
    // MARK: - Reading forwarding
    
    /// Poll the active source for latest reading and forward it
    /// Call this periodically to get readings from the active source
    public func pollActiveSource() async -> GlucoseReading? {
        guard let currentId = activeSourceId,
              let source = sources[currentId] else {
            return nil
        }
        
        let reading = await source.latestReading
        if let reading = reading, reading.timestamp != latestReading?.timestamp {
            latestReading = reading
            onReadingReceived?(reading)
        }
        
        // Also sync state
        let state = await source.sensorState
        if state != sensorState {
            sensorState = state
            onSensorStateChanged?(state)
        }
        
        return reading
    }
    
    /// Get the active source for direct access
    public func activeSource() -> (any CGMManagerProtocol)? {
        guard let currentId = activeSourceId else { return nil }
        return sources[currentId]
    }
}

// MARK: - Convenience Extensions

extension CGMSourceSwitcher {
    /// Create a switcher pre-populated with sources
    public static func withSources(_ sources: [RegisteredCGMSource]) async -> CGMSourceSwitcher {
        let switcher = CGMSourceSwitcher()
        for source in sources {
            await switcher.register(source)
        }
        return switcher
    }
    
    /// Get summary of registered sources
    public var summary: String {
        let active = activeSourceId ?? "none"
        let count = sources.count
        return "CGMSourceSwitcher: \(count) sources, active=\(active)"
    }
}
