// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// AppGroupCGMManager.swift
// CGMKit
//
// Reads CGM data from shared app group (Loop/Trio/xDrip4iOS format).
// Trace: CGM-XDRIP-003

import Foundation
import T1PalCore

/// Configuration for app group CGM reading
public struct AppGroupCGMConfig: Codable, Sendable {
    /// App group identifier (e.g., "group.com.loopkit.LoopGroup")
    public let suiteName: String
    
    /// Key for glucose readings in shared UserDefaults
    public let readingsKey: String
    
    /// Polling interval in seconds
    public let pollIntervalSeconds: Double
    
    /// Default Loop/Trio/xDrip app group identifier
    public static let defaultSuiteName = "group.com.loopkit.LoopGroup"
    
    /// Default key for glucose readings
    public static let defaultReadingsKey = "latestReadings"
    
    public init(
        suiteName: String = defaultSuiteName,
        readingsKey: String = defaultReadingsKey,
        pollIntervalSeconds: Double = 60
    ) {
        self.suiteName = suiteName
        self.readingsKey = readingsKey
        self.pollIntervalSeconds = pollIntervalSeconds
    }
}

/// CGM manager that reads from shared app group (Loop/Trio/xDrip format)
///
/// Data format:
/// ```json
/// [{"Value": 120.0, "DT": "/Date(1707552000000)/", "Trend": 4}]
/// ```
public actor AppGroupCGMManager: CGMManagerProtocol {
    
    // MARK: - CGMManagerProtocol
    
    public let displayName = "App Group"
    public let cgmType = CGMType.healthKitObserver
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    // MARK: - Private Properties
    
    private let config: AppGroupCGMConfig
    private var pollTask: Task<Void, Never>?
    private var userDefaults: UserDefaults?
    
    // MARK: - Init
    
    public init(config: AppGroupCGMConfig = AppGroupCGMConfig()) {
        self.config = config
        self.userDefaults = UserDefaults(suiteName: config.suiteName)
    }
    
    // MARK: - CGMManagerProtocol Methods
    
    public func startScanning() async throws {
        guard userDefaults != nil else {
            setSensorState(.failed)
            throw CGMError.dataUnavailable
        }
        
        setSensorState(.active)
        startPolling()
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        try await startScanning()
    }
    
    public func disconnect() async {
        stopPolling()
        setSensorState(.stopped)
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollForReadings()
                try? await Task.sleep(nanoseconds: UInt64(self?.config.pollIntervalSeconds ?? 60) * 1_000_000_000)
            }
        }
    }
    
    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
    
    private func pollForReadings() {
        guard let userDefaults = userDefaults,
              let data = userDefaults.data(forKey: config.readingsKey) else {
            return
        }
        
        guard let readings = parseReadings(data: data), let latest = readings.first else {
            return
        }
        
        // Only emit if this is a new reading
        if latestReading?.timestamp != latest.timestamp {
            latestReading = latest
            onReadingReceived?(latest)
        }
    }
    
    // MARK: - Parsing
    
    private func parseReadings(data: Data) -> [GlucoseReading]? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        
        return array.compactMap { dict -> GlucoseReading? in
            guard let value = dict["Value"] as? Double,
                  let dtString = dict["DT"] as? String,
                  let timestamp = parseTimestamp(dtString) else {
                return nil
            }
            
            let trendOrdinal = dict["Trend"] as? Int ?? 4
            let trend = trendFromOrdinal(trendOrdinal)
            
            return GlucoseReading(
                glucose: value,
                timestamp: timestamp,
                trend: trend,
                source: "appGroup"
            )
        }
    }
    
    private func parseTimestamp(_ dtString: String) -> Date? {
        // Format: "/Date(1707552000000)/"
        let pattern = #"/Date\((\d+)\)/"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: dtString, range: NSRange(dtString.startIndex..., in: dtString)),
              let millisRange = Range(match.range(at: 1), in: dtString),
              let millis = Double(dtString[millisRange]) else {
            return nil
        }
        return Date(timeIntervalSince1970: millis / 1000.0)
    }
    
    private func trendFromOrdinal(_ ordinal: Int) -> GlucoseTrend {
        switch ordinal {
        case 0: return .notComputable
        case 1: return .doubleUp
        case 2: return .singleUp
        case 3: return .fortyFiveUp
        case 4: return .flat
        case 5: return .fortyFiveDown
        case 6: return .singleDown
        case 7: return .doubleDown
        default: return .notComputable
        }
    }
    
    // MARK: - State Management
    
    private func setSensorState(_ state: SensorState) {
        sensorState = state
        onSensorStateChanged?(state)
    }
}
