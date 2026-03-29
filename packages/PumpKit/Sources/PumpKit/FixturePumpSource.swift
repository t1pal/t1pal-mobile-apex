// SPDX-License-Identifier: AGPL-3.0-or-later
//
// FixturePumpSource.swift
// PumpKit
//
// Fixture-based pump source for replaying captured sessions.
// Loads pump session data from JSON fixtures for testing.
// Trace: PUMP-CTX-003, PRD-005
//
// Usage:
//   let source = FixturePumpSource(config: .init(fixtureName: "omnipod-session"))
//   try await source.start()
//   let status = await source.status

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Fixture Pump Source

/// Pump source that replays captured session data
public actor FixturePumpSource: PumpSource {
    
    public nonisolated let sourceType: PumpDataSourceType = .fixture
    
    // MARK: - State
    
    private var config: FixturePumpConfig
    private var isRunning: Bool = false
    private var playbackTask: Task<Void, Never>?
    
    // Fixture data
    private var fixtureData: PumpFixtureData?
    private var currentEventIndex: Int = 0
    private var currentStatus: PumpStatus
    
    // Protocol logger for replay visibility
    private let protocolLogger: PumpProtocolLogger
    
    // MARK: - Initialization
    
    public init(config: FixturePumpConfig) {
        self.config = config
        self.protocolLogger = PumpProtocolLogger(pumpType: "fixture", pumpId: config.fixtureName)
        
        self.currentStatus = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: nil,
            batteryLevel: nil,
            insulinOnBoard: 0
        )
    }
    
    // MARK: - PumpSource Protocol
    
    public var status: PumpStatus {
        currentStatus
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        
        // Load fixture
        fixtureData = try await loadFixture()
        
        guard let fixture = fixtureData else {
            throw FixtureError.fixtureNotFound(config.fixtureName)
        }
        
        isRunning = true
        currentEventIndex = 0
        
        // Apply initial state from fixture
        if let initial = fixture.initialStatus {
            currentStatus = initial.toPumpStatus()
        } else {
            currentStatus = PumpStatus(
                connectionState: .connected,
                reservoirLevel: fixture.metadata.reservoirLevel,
                batteryLevel: fixture.metadata.batteryLevel,
                insulinOnBoard: fixture.metadata.iob ?? 0
            )
        }
        
        // Start playback
        startPlayback()
    }
    
    public func stop() async {
        isRunning = false
        playbackTask?.cancel()
        playbackTask = nil
        
        currentStatus = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: currentStatus.reservoirLevel,
            batteryLevel: currentStatus.batteryLevel,
            insulinOnBoard: currentStatus.insulinOnBoard,
            lastDelivery: currentStatus.lastDelivery
        )
    }
    
    public func execute(_ command: PumpSourceCommand) async throws -> PumpSourceResult {
        guard isRunning else {
            return PumpSourceResult(success: false, command: command, message: "Fixture not loaded")
        }
        
        // In fixture mode, commands are logged but use fixture-defined responses
        switch command {
        case .readStatus:
            return PumpSourceResult(success: true, command: command, updatedStatus: currentStatus)
            
        default:
            // Log command attempt
            protocolLogger.tx(commandToBytes(command), context: "Command: \(command)")
            
            // Fixtures don't actually execute commands - return success with current status
            return PumpSourceResult(
                success: true,
                command: command,
                message: "Fixture mode: command logged but not executed",
                updatedStatus: currentStatus
            )
        }
    }
    
    // MARK: - Fixture Loading
    
    private func loadFixture() async throws -> PumpFixtureData {
        // Try URL first
        if let url = config.fixtureURL {
            return try await loadFromURL(url)
        }
        
        // Try bundle
        if let bundleData = loadFromBundle(name: config.fixtureName) {
            return bundleData
        }
        
        // Try fixtures directory
        if let fileData = loadFromFile(name: config.fixtureName) {
            return fileData
        }
        
        // Generate synthetic fixture
        return generateSyntheticFixture()
    }
    
    private func loadFromURL(_ url: URL) async throws -> PumpFixtureData {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(PumpFixtureData.self, from: data)
    }
    
    private func loadFromBundle(name: String) -> PumpFixtureData? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PumpFixtureData.self, from: data)
        } catch {
            return nil
        }
    }
    
    private func loadFromFile(name: String) -> PumpFixtureData? {
        let paths = [
            "conformance/fixtures/pump/\(name).json",
            "fixtures/pump/\(name).json",
            "\(name).json"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    return try JSONDecoder().decode(PumpFixtureData.self, from: data)
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    private func generateSyntheticFixture() -> PumpFixtureData {
        // Generate a synthetic fixture with realistic events
        var events: [PumpFixtureEvent] = []
        var offset: TimeInterval = 0
        
        // Generate events over 1 hour
        for _ in 0..<12 {
            // Status update every 5 minutes
            let status = PumpStatus(
                connectionState: .connected,
                reservoirLevel: Double.random(in: 80...150),
                batteryLevel: Double.random(in: 0.5...1.0),
                insulinOnBoard: Double.random(in: 1.0...5.0),
                lastDelivery: Date()
            )
            events.append(PumpFixtureEvent(
                offsetSeconds: offset,
                type: .statusUpdate,
                status: CodablePumpStatus(from: status),
                protocolBytes: nil
            ))
            offset += 300  // 5 minutes
        }
        
        // Add a few temp basals
        events.insert(PumpFixtureEvent(
            offsetSeconds: 60,
            type: .tempBasalSet,
            status: nil,
            protocolBytes: ProtocolBytes(tx: "4c 00 32 00 1e", rx: "06 4c 00")
        ), at: 1)
        
        events.insert(PumpFixtureEvent(
            offsetSeconds: 1860,
            type: .tempBasalCancelled,
            status: nil,
            protocolBytes: ProtocolBytes(tx: "4d 00", rx: "06 4d 00")
        ), at: 5)
        
        return PumpFixtureData(
            metadata: PumpFixtureMetadata(
                name: config.fixtureName,
                pumpType: "synthetic",
                capturedAt: Date(),
                durationSeconds: 3600,
                reservoirLevel: 120,
                batteryLevel: 0.85,
                iob: 2.5
            ),
            events: events,
            initialStatus: nil
        )
    }
    
    // MARK: - Playback
    
    private func startPlayback() {
        guard let fixture = fixtureData else { return }
        
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, await self.isRunning else { break }
                
                await self.playNextEvent()
                
                // Check if we should loop
                if await self.currentEventIndex >= fixture.events.count {
                    if await self.shouldLoop() {
                        await self.resetPlayback()
                    } else {
                        break
                    }
                }
            }
        }
    }
    
    private func shouldLoop() -> Bool {
        config.loop
    }
    
    private func playNextEvent() async {
        guard let fixture = fixtureData else { return }
        guard currentEventIndex < fixture.events.count else { return }
        
        let event = fixture.events[currentEventIndex]
        
        // Calculate delay to next event (with playback speed)
        let delay: UInt64
        if currentEventIndex > 0 {
            let prevEvent = fixture.events[currentEventIndex - 1]
            let interval = event.offsetSeconds - prevEvent.offsetSeconds
            delay = UInt64((interval / config.playbackSpeed) * 1_000_000_000)
        } else {
            delay = UInt64(event.offsetSeconds * 1_000_000_000 / config.playbackSpeed)
        }
        
        if delay > 0 {
            try? await Task.sleep(nanoseconds: min(delay, 5_000_000_000))  // Cap at 5s
        }
        
        // Apply event
        applyEvent(event)
        currentEventIndex += 1
    }
    
    private func applyEvent(_ event: PumpFixtureEvent) {
        // Log protocol bytes if present
        if let bytes = event.protocolBytes {
            if let txHex = bytes.tx {
                protocolLogger.tx(hexToData(txHex), context: event.type.rawValue)
            }
            if let rxHex = bytes.rx {
                protocolLogger.rx(hexToData(rxHex), context: "\(event.type.rawValue) response")
            }
        }
        
        // Update status if present
        if let status = event.status {
            currentStatus = status.toPumpStatus()
        }
    }
    
    private func resetPlayback() {
        currentEventIndex = 0
        if let initial = fixtureData?.initialStatus {
            currentStatus = initial.toPumpStatus()
        }
    }
    
    // MARK: - Helpers
    
    private func commandToBytes(_ command: PumpSourceCommand) -> Data {
        switch command {
        case .setTempBasal(let rate, let duration):
            let rateBytes = UInt16(rate * 100)
            let durationBytes = UInt16(duration)
            return Data([0x4C, UInt8(rateBytes >> 8), UInt8(rateBytes & 0xFF), UInt8(durationBytes >> 8), UInt8(durationBytes & 0xFF)])
        case .cancelTempBasal:
            return Data([0x4D, 0x00])
        case .deliverBolus(let units):
            let unitsBytes = UInt16(units * 40)
            return Data([0x4E, UInt8(unitsBytes >> 8), UInt8(unitsBytes & 0xFF)])
        case .suspend:
            return Data([0x4F, 0x01])
        case .resume:
            return Data([0x50, 0x01])
        case .readStatus:
            return Data([0x03, 0x00])
        }
    }
    
    private func hexToData(_ hex: String) -> Data {
        let bytes = hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        return Data(bytes)
    }
}

// MARK: - Fixture Data Types

/// Complete fixture data structure
public struct PumpFixtureData: Codable, Sendable {
    public let metadata: PumpFixtureMetadata
    public let events: [PumpFixtureEvent]
    public let initialStatus: CodablePumpStatus?
}

/// Fixture metadata
public struct PumpFixtureMetadata: Codable, Sendable {
    public let name: String
    public let pumpType: String
    public let capturedAt: Date
    public let durationSeconds: TimeInterval
    public let reservoirLevel: Double?
    public let batteryLevel: Double?
    public let iob: Double?
}

/// Codable representation of PumpStatus for fixtures
public struct CodablePumpStatus: Codable, Sendable {
    public let connectionState: String
    public let reservoirLevel: Double?
    public let batteryLevel: Double?
    public let insulinOnBoard: Double
    public let lastDelivery: Date?
    
    public init(from status: PumpStatus) {
        self.connectionState = status.connectionState.rawValue
        self.reservoirLevel = status.reservoirLevel
        self.batteryLevel = status.batteryLevel
        self.insulinOnBoard = status.insulinOnBoard
        self.lastDelivery = status.lastDelivery
    }
    
    public func toPumpStatus() -> PumpStatus {
        PumpStatus(
            connectionState: PumpConnectionState(rawValue: connectionState) ?? .disconnected,
            reservoirLevel: reservoirLevel,
            batteryLevel: batteryLevel,
            insulinOnBoard: insulinOnBoard,
            lastDelivery: lastDelivery
        )
    }
}

/// Single fixture event
public struct PumpFixtureEvent: Codable, Sendable {
    public let offsetSeconds: TimeInterval
    public let type: PumpFixtureEventType
    public let status: CodablePumpStatus?
    public let protocolBytes: ProtocolBytes?
}

/// Event type
public enum PumpFixtureEventType: String, Codable, Sendable {
    case statusUpdate
    case tempBasalSet
    case tempBasalCancelled
    case bolusStarted
    case bolusCompleted
    case suspended
    case resumed
    case error
}

/// Protocol byte pairs
public struct ProtocolBytes: Codable, Sendable {
    public let tx: String?
    public let rx: String?
}

/// Fixture errors
public enum FixtureError: Error, LocalizedError, Sendable {
    case fixtureNotFound(String)
    case invalidFixtureFormat
    case playbackFailed
    
    public var errorDescription: String? {
        switch self {
        case .fixtureNotFound(let name):
            return "Fixture not found: \(name)"
        case .invalidFixtureFormat:
            return "Invalid fixture format"
        case .playbackFailed:
            return "Playback failed"
        }
    }
}
