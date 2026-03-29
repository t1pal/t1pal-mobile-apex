// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpContextManager.swift
// PumpKit
//
// Centralized pump context management following DataContextManager pattern.
// Enables switching between simulated, fixture, mirrored, and real pump sources.
// Trace: PUMP-CTX-001, PRD-005
//
// Usage:
//   let manager = PumpContextManager.shared
//   manager.switchToSimulated(pattern: .normal)
//   manager.switchToFixture(name: "omnipod-session")
//   manager.switchToMirrored(nightscoutURL: url)
//   manager.switchToBLE(pumpType: .omnipodDash, config: bleConfig)

import Foundation

// MARK: - Pump Data Source Type

/// Type of pump data source (how data is obtained)
/// Note: This is different from PumpDataSourceType in T1PalAIDKit which represents pump hardware types
public enum PumpDataSourceType: String, Codable, Sendable, CaseIterable {
    case simulated = "simulated"     // Generated pump patterns
    case fixture = "fixture"          // Replay captured sessions
    case mirrored = "mirrored"        // Mirror from Nightscout devicestatus
    case ble = "ble"                  // Real BLE hardware
    case none = "none"                // No pump configured
    
    public var displayName: String {
        switch self {
        case .simulated: return "Simulated"
        case .fixture: return "Fixture Replay"
        case .mirrored: return "Mirrored (NS)"
        case .ble: return "BLE Hardware"
        case .none: return "None"
        }
    }
    
    public var icon: String {
        switch self {
        case .simulated: return "waveform"
        case .fixture: return "doc.text"
        case .mirrored: return "cloud"
        case .ble: return "antenna.radiowaves.left.and.right"
        case .none: return "minus.circle"
        }
    }
}

// MARK: - Pump Context

/// Immutable pump context configuration
public struct PumpContext: Codable, Sendable, Equatable {
    public let id: UUID
    public let sourceType: PumpDataSourceType
    public let pumpType: PumpType
    public let label: String
    public let createdAt: Date
    public var lastUpdated: Date
    
    // Source-specific configuration
    public var simulatedConfig: SimulatedPumpConfig?
    public var fixtureConfig: FixturePumpConfig?
    public var mirroredConfig: MirroredPumpConfig?
    public var bleConfig: BLEPumpConfig?
    
    public init(
        sourceType: PumpDataSourceType,
        pumpType: PumpType = .simulation,
        label: String = ""
    ) {
        self.id = UUID()
        self.sourceType = sourceType
        self.pumpType = pumpType
        self.label = label.isEmpty ? sourceType.displayName : label
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
    
    public static let none = PumpContext(sourceType: .none)
    public static let simulated = PumpContext(sourceType: .simulated, label: "Demo Pump")
    
    /// Short indicator for UI
    public var indicator: String {
        switch sourceType {
        case .simulated: return "SIM"
        case .fixture: return "FIX"
        case .mirrored: return "NS"
        case .ble: return "BLE"
        case .none: return "—"
        }
    }
}

// MARK: - Source Configurations

/// Configuration for simulated pump
public struct SimulatedPumpConfig: Codable, Sendable, Equatable {
    public var pattern: SimulatedPumpPattern
    public var reservoirLevel: Double
    public var batteryLevel: Double
    public var basalRate: Double
    public var iobBase: Double
    
    public init(
        pattern: SimulatedPumpPattern = .normal,
        reservoirLevel: Double = 150,
        batteryLevel: Double = 0.85,
        basalRate: Double = 1.0,
        iobBase: Double = 2.5
    ) {
        self.pattern = pattern
        self.reservoirLevel = reservoirLevel
        self.batteryLevel = batteryLevel
        self.basalRate = basalRate
        self.iobBase = iobBase
    }
}

/// Simulated pump behavior patterns
public enum SimulatedPumpPattern: String, Codable, Sendable, CaseIterable {
    case normal = "normal"           // Stable operation
    case lowReservoir = "lowReservoir"   // Decreasing reservoir
    case lowBattery = "lowBattery"       // Decreasing battery
    case frequentTempBasal = "frequentTempBasal"  // Active temp basal changes
    case suspended = "suspended"     // Suspended state
    case error = "error"             // Intermittent errors
    
    public var displayName: String {
        switch self {
        case .normal: return "Normal Operation"
        case .lowReservoir: return "Low Reservoir"
        case .lowBattery: return "Low Battery"
        case .frequentTempBasal: return "Active Temp Basal"
        case .suspended: return "Suspended"
        case .error: return "Intermittent Errors"
        }
    }
}

/// Configuration for fixture replay
public struct FixturePumpConfig: Codable, Sendable, Equatable {
    public var fixtureName: String
    public var fixtureURL: URL?
    public var playbackSpeed: Double
    public var loop: Bool
    
    public init(
        fixtureName: String,
        fixtureURL: URL? = nil,
        playbackSpeed: Double = 1.0,
        loop: Bool = true
    ) {
        self.fixtureName = fixtureName
        self.fixtureURL = fixtureURL
        self.playbackSpeed = playbackSpeed
        self.loop = loop
    }
}

/// Configuration for mirrored pump (from Nightscout)
public struct MirroredPumpConfig: Codable, Sendable, Equatable {
    public var nightscoutURL: URL
    public var token: String?
    public var pollIntervalSeconds: Int
    
    public init(
        nightscoutURL: URL,
        token: String? = nil,
        pollIntervalSeconds: Int = 60
    ) {
        self.nightscoutURL = nightscoutURL
        self.token = token
        self.pollIntervalSeconds = pollIntervalSeconds
    }
}

/// Configuration for BLE pump hardware
public struct BLEPumpConfig: Codable, Sendable, Equatable {
    public var pumpType: PumpType
    public var pumpSerial: String?
    public var bridgeType: String?  // RileyLink, OrangeLink, etc.
    public var bridgeId: String?
    
    public init(
        pumpType: PumpType,
        pumpSerial: String? = nil,
        bridgeType: String? = nil,
        bridgeId: String? = nil
    ) {
        self.pumpType = pumpType
        self.pumpSerial = pumpSerial
        self.bridgeType = bridgeType
        self.bridgeId = bridgeId
    }
}

// MARK: - Pump Context Manager

/// Observable pump context manager
/// Follows DataContextManager pattern for pump data sources
public final class PumpContextManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = PumpContextManager()
    
    // MARK: - State
    
    /// Current pump context
    public private(set) var current: PumpContext {
        didSet {
            lastUpdated = Date()
            notifyObservers()
            if persistenceEnabled {
                persist()
            }
        }
    }
    
    /// Active pump source (the actual data provider)
    public private(set) var activeSource: (any PumpSource)?
    
    /// Whether a source switch is in progress
    public private(set) var isSwitching: Bool = false
    
    /// Last error during source switch
    public private(set) var lastError: Error?
    
    /// Last update time
    public private(set) var lastUpdated: Date = Date()
    
    /// Recent contexts for quick switching
    public private(set) var recentContexts: [PumpContext] = []
    
    // MARK: - Configuration
    
    private let persistenceEnabled: Bool
    private let defaults: UserDefaults
    private let persistenceKey = "com.t1pal.pumpkit.context"
    
    /// Observers for context changes
    private var observers: [UUID: (PumpContext) -> Void] = [:]
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    public init(
        initialContext: PumpContext = .none,
        persistenceEnabled: Bool = true,
        userDefaults: UserDefaults = .standard
    ) {
        self.persistenceEnabled = persistenceEnabled
        self.defaults = userDefaults
        
        // Try to restore from persistence
        if persistenceEnabled, let restored = Self.restore(from: userDefaults, key: persistenceKey) {
            self.current = restored
        } else {
            self.current = initialContext
        }
    }
    
    // MARK: - Source Switching
    
    /// Switch to simulated pump
    public func switchToSimulated(
        pattern: SimulatedPumpPattern = .normal,
        config: SimulatedPumpConfig? = nil
    ) async throws {
        isSwitching = true
        defer { isSwitching = false }
        
        let simConfig = config ?? SimulatedPumpConfig(pattern: pattern)
        
        var context = PumpContext(sourceType: .simulated, label: "Simulated (\(pattern.displayName))")
        context.simulatedConfig = simConfig
        
        let source = SimulatedPumpSource(config: simConfig)
        try await source.start()
        
        activeSource = source
        addToRecent(current)
        current = context
    }
    
    /// Switch to fixture replay
    public func switchToFixture(name: String, config: FixturePumpConfig? = nil) async throws {
        isSwitching = true
        defer { isSwitching = false }
        
        let fixConfig = config ?? FixturePumpConfig(fixtureName: name)
        
        var context = PumpContext(sourceType: .fixture, label: "Fixture: \(name)")
        context.fixtureConfig = fixConfig
        
        let source = FixturePumpSource(config: fixConfig)
        try await source.start()
        
        activeSource = source
        addToRecent(current)
        current = context
    }
    
    /// Switch to mirrored pump (from Nightscout)
    public func switchToMirrored(
        nightscoutURL: URL,
        token: String? = nil,
        pollIntervalSeconds: Int = 60
    ) async throws {
        isSwitching = true
        defer { isSwitching = false }
        
        let mirConfig = MirroredPumpConfig(
            nightscoutURL: nightscoutURL,
            token: token,
            pollIntervalSeconds: pollIntervalSeconds
        )
        
        var context = PumpContext(sourceType: .mirrored, label: "NS: \(nightscoutURL.host ?? "remote")")
        context.mirroredConfig = mirConfig
        
        let source = MirroredPumpSource(config: mirConfig)
        try await source.start()
        
        activeSource = source
        addToRecent(current)
        current = context
    }
    
    /// Switch to BLE hardware pump
    public func switchToBLE(pumpType: PumpType, config: BLEPumpConfig) async throws {
        isSwitching = true
        defer { isSwitching = false }
        
        var context = PumpContext(sourceType: .ble, pumpType: pumpType, label: pumpType.rawValue)
        context.bleConfig = config
        
        let source = BLEPumpSource(config: config)
        try await source.start()
        
        activeSource = source
        addToRecent(current)
        current = context
    }
    
    /// Disconnect current pump source
    public func disconnect() async {
        await activeSource?.stop()
        activeSource = nil
        addToRecent(current)
        current = .none
    }
    
    // MARK: - Observers
    
    /// Add observer for context changes
    @discardableResult
    public func addObserver(_ handler: @escaping (PumpContext) -> Void) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        observers[id] = handler
        return id
    }
    
    /// Remove observer
    public func removeObserver(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        observers.removeValue(forKey: id)
    }
    
    private func notifyObservers() {
        lock.lock()
        let handlers = observers.values
        lock.unlock()
        
        for handler in handlers {
            handler(current)
        }
    }
    
    // MARK: - Recent Contexts
    
    private func addToRecent(_ context: PumpContext) {
        guard context.sourceType != .none else { return }
        
        // Remove if already exists
        recentContexts.removeAll { $0.id == context.id }
        
        // Add to front
        recentContexts.insert(context, at: 0)
        
        // Trim to max 5
        if recentContexts.count > 5 {
            recentContexts = Array(recentContexts.prefix(5))
        }
    }
    
    // MARK: - Persistence
    
    private func persist() {
        guard persistenceEnabled else { return }
        
        do {
            let data = try JSONEncoder().encode(current)
            defaults.set(data, forKey: persistenceKey)
        } catch {
            PumpLogger.general.error("Failed to persist pump context: \(error.localizedDescription)")
        }
    }
    
    private static func restore(from defaults: UserDefaults, key: String) -> PumpContext? {
        guard let data = defaults.data(forKey: key) else { return nil }
        
        do {
            return try JSONDecoder().decode(PumpContext.self, from: data)
        } catch {
            PumpLogger.general.error("Failed to restore pump context: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Pump Source Protocol

/// Protocol for pump data sources
public protocol PumpSource: Sendable {
    /// Source type identifier
    var sourceType: PumpDataSourceType { get }
    
    /// Current pump status
    var status: PumpStatus { get async }
    
    /// Start the source
    func start() async throws
    
    /// Stop the source
    func stop() async
    
    /// Execute a pump command
    func execute(_ command: PumpSourceCommand) async throws -> PumpSourceResult
}

/// Pump commands that can be executed via PumpSource
public enum PumpSourceCommand: Sendable {
    case setTempBasal(rate: Double, durationMinutes: Double)
    case cancelTempBasal
    case deliverBolus(units: Double)
    case suspend
    case resume
    case readStatus
}

/// Result of a pump command
public struct PumpSourceResult: Sendable {
    public let success: Bool
    public let command: PumpSourceCommand
    public let timestamp: Date
    public let message: String?
    public let updatedStatus: PumpStatus?
    
    public init(
        success: Bool,
        command: PumpSourceCommand,
        message: String? = nil,
        updatedStatus: PumpStatus? = nil
    ) {
        self.success = success
        self.command = command
        self.timestamp = Date()
        self.message = message
        self.updatedStatus = updatedStatus
    }
}
