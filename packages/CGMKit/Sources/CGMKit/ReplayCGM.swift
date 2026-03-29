// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ReplayCGM.swift
// T1Pal Mobile
//
// Replay CGM readings from Nightscout history file
// Requirements: REQ-DEMO-001, CLI-SIM-001

import Foundation
import T1PalCore

/// Lenient Nightscout entry for parsing various export formats
/// Handles both Int64 and Double date fields
private struct ReplayEntry: Codable {
    let sgv: Int?
    let glucose: Int?  // Alternative field name
    let direction: String?
    let date: Double   // Use Double to handle both int and float
    let device: String?
    
    func toGlucoseReading() -> GlucoseReading? {
        guard let glucose = sgv ?? glucose else { return nil }
        
        let trend: GlucoseTrend
        switch direction?.lowercased() {
        case "doubleup": trend = .doubleUp
        case "singleup": trend = .singleUp
        case "fortyfiveup": trend = .fortyFiveUp
        case "flat": trend = .flat
        case "fortyfivedown": trend = .fortyFiveDown
        case "singledown": trend = .singleDown
        case "doubledown": trend = .doubleDown
        default: trend = .notComputable
        }
        
        return GlucoseReading(
            glucose: Double(glucose),
            timestamp: Date(timeIntervalSince1970: date / 1000),
            trend: trend,
            source: device ?? "replay"
        )
    }
}

/// Configuration for replay CGM
public struct ReplayCGMConfig: Sendable {
    /// Path to JSON file containing Nightscout entries
    public let filePath: String
    /// Time compression factor (1.0 = realtime, 60.0 = 1 hour in 1 minute)
    public let timeCompression: Double
    /// Whether to loop back to start when replay completes
    public let loopPlayback: Bool
    
    public init(
        filePath: String,
        timeCompression: Double = 1.0,
        loopPlayback: Bool = false
    ) {
        self.filePath = filePath
        self.timeCompression = max(1.0, timeCompression)
        self.loopPlayback = loopPlayback
    }
}

/// Replay CGM from Nightscout history export
/// Requirements: REQ-DEMO-001
public actor ReplayCGM: CGMManagerProtocol {
    public let displayName = "Replay CGM"
    public let cgmType = CGMType.simulation
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    private let config: ReplayCGMConfig
    private var readings: [GlucoseReading] = []
    private var currentIndex: Int = 0
    private var replayTask: Task<Void, Never>?
    
    public init(config: ReplayCGMConfig) {
        self.config = config
    }
    
    /// Convenience initializer for simple file path
    public init(filePath: String, timeCompression: Double = 1.0) {
        self.config = ReplayCGMConfig(
            filePath: filePath,
            timeCompression: timeCompression
        )
    }
    
    /// Load readings from file
    public func loadReadings() async throws -> Int {
        let data: Data
        do {
            let url = URL(fileURLWithPath: config.filePath)
            data = try Data(contentsOf: url)
        } catch {
            throw CGMError.connectionFailed
        }
        
        let decoder = JSONDecoder()
        let entries: [ReplayEntry]
        do {
            entries = try decoder.decode([ReplayEntry].self, from: data)
        } catch {
            throw CGMError.dataUnavailable
        }
        
        // Convert to GlucoseReading and sort by timestamp (oldest first)
        readings = entries
            .compactMap { $0.toGlucoseReading() }
            .sorted { $0.timestamp < $1.timestamp }
        
        currentIndex = 0
        return readings.count
    }
    
    /// Get reading at specific index without advancing
    public func reading(at index: Int) -> GlucoseReading? {
        guard index >= 0, index < readings.count else { return nil }
        return readings[index]
    }
    
    /// Get total number of loaded readings
    public var readingCount: Int { readings.count }
    
    /// Get current playback position
    public var currentPosition: Int { currentIndex }
    
    // MARK: - CGMManagerProtocol
    
    public func startScanning() async throws {
        let count = try await loadReadings()
        guard count > 0 else {
            sensorState = .failed
            onSensorStateChanged?(.failed)
            throw CGMError.connectionFailed
        }
        
        sensorState = .active
        onSensorStateChanged?(.active)
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        try await startScanning()
        startReplay()
    }
    
    public func disconnect() async {
        replayTask?.cancel()
        replayTask = nil
        sensorState = .stopped
        onSensorStateChanged?(.stopped)
    }
    
    /// Emit next reading immediately (for manual stepping)
    public func nextReading() -> GlucoseReading? {
        guard !readings.isEmpty else { return nil }
        
        let reading = readings[currentIndex]
        currentIndex = (currentIndex + 1) % readings.count
        
        latestReading = reading
        return reading
    }
    
    // MARK: - Private
    
    private func startReplay() {
        guard readings.count >= 2 else { return }
        
        replayTask = Task {
            while !Task.isCancelled {
                guard currentIndex < readings.count - 1 else {
                    if config.loopPlayback {
                        currentIndex = 0
                        continue
                    } else {
                        sensorState = .expired
                        onSensorStateChanged?(.expired)
                        return
                    }
                }
                
                let current = readings[currentIndex]
                let next = readings[currentIndex + 1]
                
                // Calculate delay based on actual time gap and compression
                let actualGap = next.timestamp.timeIntervalSince(current.timestamp)
                let compressedGap = actualGap / config.timeCompression
                let delayNanos = UInt64(max(0.1, compressedGap) * 1_000_000_000)
                
                // Emit current reading
                latestReading = current
                onReadingReceived?(current)
                
                currentIndex += 1
                
                try? await Task.sleep(nanoseconds: delayNanos)
            }
        }
    }
}
