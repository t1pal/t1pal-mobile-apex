// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CGMManager.swift
// T1Pal Mobile
//
// CGM driver abstraction
// Requirements: REQ-CGM-*

import Foundation
import T1PalCore
// Re-export CGMKitShare for backward compatibility
// Apps importing CGMKit automatically get Share clients
@_exported import CGMKitShare

// SensorState is re-exported from CGMKitShare
// CGMKit uses the same SensorState type for both local and cloud CGM sources

/// CGM sensor information
public struct SensorInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let type: CGMType
    
    public init(id: String, name: String, type: CGMType) {
        self.id = id
        self.name = name
        self.type = type
    }
}

/// CGM system types
///
/// - Important: This enum is **non-frozen** and may gain new cases in future versions.
///   Switch statements should either:
///   1. Handle all cases exhaustively (recommended for core logic), or
///   2. Use `@unknown default` to future-proof against new cases
///
/// The `.unknown` case provides a catch-all for unrecognized CGM types from
/// external sources (e.g., Nightscout, stored profiles).
///
/// Requirements: REQ-CGM-001
/// Trace: CODE-QUALITY-001 — Enum extension policy documented
public enum CGMType: String, Codable, Sendable, CaseIterable {
    case dexcomG6
    case dexcomG7
    case dexcomShare
    case libre2
    case libre3
    case miaomiao
    case bubble
    case medtronicGuardian
    case nightscoutFollower
    case healthKitObserver  // Read from vendor app via HealthKit
    case simulation
    case unknown  // Unidentified CGM type
}

// MARK: - CGMType Display Properties (ARCH-005)

extension CGMType {
    /// User-facing display name
    /// Trace: ARCH-005 — Consolidated from T1PalAID.CGMModel, T1PalCGMKit.CGMSourceType
    public var displayName: String {
        switch self {
        case .dexcomG6: return "Dexcom G6"
        case .dexcomG7: return "Dexcom G7"
        case .dexcomShare: return "Dexcom Share"
        case .libre2: return "Libre 2"
        case .libre3: return "Libre 3"
        case .miaomiao: return "MiaoMiao"
        case .bubble: return "Bubble"
        case .medtronicGuardian: return "Medtronic Guardian"
        case .nightscoutFollower: return "Nightscout"
        case .healthKitObserver: return "HealthKit"
        case .simulation: return "Simulation"
        case .unknown: return "Unknown"
        }
    }
    
    /// SF Symbol icon for UI display
    /// Trace: ARCH-005 — Consolidated from T1PalAID.CGMModel
    public var icon: String {
        switch self {
        case .dexcomG6, .dexcomG7, .dexcomShare:
            return "sensor.tag.radiowaves.forward.fill"
        case .libre2, .libre3:
            return "circle.circle.fill"
        case .miaomiao, .bubble:
            return "wave.3.right"
        case .medtronicGuardian:
            return "wave.3.right"
        case .nightscoutFollower:
            return "cloud.fill"
        case .healthKitObserver:
            return "heart.text.square"
        case .simulation:
            return "play.circle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    /// Manufacturer name for UI display
    /// Trace: ARCH-005 — Consolidated from T1PalAID.CGMModel
    public var manufacturer: String {
        switch self {
        case .dexcomG6, .dexcomG7, .dexcomShare:
            return "Dexcom"
        case .libre2, .libre3:
            return "Abbott"
        case .miaomiao:
            return "MiaoMiao"
        case .bubble:
            return "Bubble"
        case .medtronicGuardian:
            return "Medtronic"
        case .nightscoutFollower:
            return "Remote"
        case .healthKitObserver:
            return "Apple"
        case .simulation:
            return "Demo"
        case .unknown:
            return "Unknown"
        }
    }
}

/// CGM connection mode - user's choice of who controls the sensor
public enum CGMConnectionMode: String, Codable, Sendable, CaseIterable {
    /// T1Pal connects directly to sensor via BLE (exclusive)
    case direct
    /// T1Pal connects and subscribes while vendor app authenticates (Loop/xDrip pattern)
    /// Real-time glucose via BLE notifications (<10s latency)
    /// Trace: G7-COEX-001
    case coexistence
    /// T1Pal observes BLE advertisements only (no connection)
    case passiveBLE
    /// Vendor app controls sensor; T1Pal reads from HealthKit only
    case healthKitObserver
    /// Read from cloud service (Dexcom Share, LibreLinkUp)
    case cloudFollower
    /// Read from Nightscout
    case nightscoutFollower
}

// MARK: - CGMConnectionMode Display Properties (ARCH-005)

extension CGMConnectionMode {
    /// User-facing display name
    /// Trace: ARCH-005 — Consolidated from T1PalCGMKit, T1PalAID
    public var displayName: String {
        switch self {
        case .direct: return "Direct BLE"
        case .coexistence: return "Coexistence"
        case .passiveBLE: return "Passive BLE"
        case .healthKitObserver: return "HealthKit Observer"
        case .cloudFollower: return "Cloud Follower"
        case .nightscoutFollower: return "Nightscout Follower"
        }
    }
    
    /// SF Symbol icon for UI display
    /// Trace: ARCH-005 — Consolidated from T1PalAID.CGMConnectionModeAID
    public var icon: String {
        switch self {
        case .direct: return "antenna.radiowaves.left.and.right"
        case .coexistence: return "app.badge"
        case .passiveBLE: return "eye"
        case .healthKitObserver: return "heart.fill"
        case .cloudFollower: return "icloud.fill"
        case .nightscoutFollower: return "cloud.fill"
        }
    }
    
    /// User-facing description of what this mode does
    /// Trace: ARCH-005 — Consolidated from T1PalAID.CGMConnectionModeAID
    public var modeDescription: String {
        switch self {
        case .direct: return "Exclusive connection to transmitter"
        case .coexistence: return "Reading data while vendor app runs"
        case .passiveBLE: return "Observing BLE advertisements only"
        case .healthKitObserver: return "Polling from Apple Health"
        case .cloudFollower: return "Reading from cloud service"
        case .nightscoutFollower: return "Remote data via Nightscout"
        }
    }
    
    /// Display name with device context (e.g., "G6 via Dexcom App")
    /// Trace: ARCH-005, G6-APP-007
    public func displayName(for cgmType: CGMType) -> String {
        switch self {
        case .coexistence:
            switch cgmType {
            case .dexcomG6: return "G6 via Dexcom App"
            case .dexcomG7: return "G7 via Dexcom App"
            case .libre2, .libre3: return "Libre via App"
            default: return displayName
            }
        default:
            return displayName
        }
    }
    
    /// Whether this mode requires BLE hardware
    /// Trace: CGM-MODE-WIRE-004
    public var requiresBLE: Bool {
        switch self {
        case .direct, .coexistence, .passiveBLE:
            return true
        case .healthKitObserver, .cloudFollower, .nightscoutFollower:
            return false
        }
    }
}

/// CGM error types
public enum CGMError: Error, Sendable, LocalizedError, Equatable {
    case connectionFailed
    case sensorNotFound
    case sensorExpired
    case bluetoothUnavailable
    case unauthorized
    case dataUnavailable
    case deviceNotFound
    case serviceNotFound
    case characteristicNotFound
    case notConnected
    case dataCorrupted
    case invalidTransmitterId
    case unsupportedDevice(String)
    /// Invalid sensor code - user should re-enter (BLE-QUIRK-001)
    case invalidSensorCode
    /// Configuration error (G6-WIRE-003)
    case configurationError(String)
    /// Manager not configured
    case notConfigured
    /// CGM-GAP-002: Configuration required - user input needed
    case configurationRequired(String)
    /// Authentication timeout (PROD-HARDEN-022)
    case authenticationTimeout
    /// Discovery timeout (PROD-HARDEN-022)
    case discoveryTimeout
    /// Authentication failed (CGM-PG-005: ECDH/crypto error)
    case authenticationFailed
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to CGM sensor"
        case .sensorNotFound:
            return "CGM sensor not found"
        case .sensorExpired:
            return "CGM sensor has expired"
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable"
        case .unauthorized:
            return "CGM access not authorized"
        case .dataUnavailable:
            return "CGM data is unavailable"
        case .deviceNotFound:
            return "CGM device not found"
        case .serviceNotFound:
            return "CGM service not found on device"
        case .characteristicNotFound:
            return "CGM characteristic not found"
        case .notConnected:
            return "CGM is not connected"
        case .dataCorrupted:
            return "CGM data is corrupted"
        case .invalidTransmitterId:
            return "Invalid transmitter ID format"
        case .unsupportedDevice(let reason):
            return "Unsupported device: \(reason)"
        case .invalidSensorCode:
            return "Invalid sensor code. Please check and re-enter the 4-digit code from your sensor."
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .notConfigured:
            return "CGM manager not configured"
        case .configurationRequired(let message):
            return message
        case .authenticationTimeout:
            return "CGM authentication timed out. Please try again."
        case .discoveryTimeout:
            return "CGM service discovery timed out. Please try again."
        case .authenticationFailed:
            return "CGM authentication failed. Please try reconnecting."
        }
    }
    
    /// Whether this error suggests user should re-enter credentials
    public var requiresCodeReentry: Bool {
        switch self {
        case .invalidSensorCode, .unauthorized, .configurationRequired:
            return true
        default:
            return false
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance (PROD-HARDEN-033)

extension CGMError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .cgm }
    
    public var code: String {
        switch self {
        case .connectionFailed: return "CONNECTION_FAILED"
        case .sensorNotFound: return "SENSOR_NOT_FOUND"
        case .sensorExpired: return "SENSOR_EXPIRED"
        case .bluetoothUnavailable: return "BT_UNAVAILABLE"
        case .unauthorized: return "UNAUTHORIZED"
        case .dataUnavailable: return "DATA_UNAVAILABLE"
        case .deviceNotFound: return "DEVICE_NOT_FOUND"
        case .serviceNotFound: return "SERVICE_NOT_FOUND"
        case .characteristicNotFound: return "CHAR_NOT_FOUND"
        case .notConnected: return "NOT_CONNECTED"
        case .dataCorrupted: return "DATA_CORRUPTED"
        case .invalidTransmitterId: return "INVALID_TX_ID"
        case .unsupportedDevice: return "UNSUPPORTED_DEVICE"
        case .invalidSensorCode: return "INVALID_SENSOR_CODE"
        case .configurationError: return "CONFIG_ERROR"
        case .notConfigured: return "NOT_CONFIGURED"
        case .configurationRequired: return "CONFIG_REQUIRED"
        case .authenticationTimeout: return "AUTH_TIMEOUT"
        case .discoveryTimeout: return "DISCOVERY_TIMEOUT"
        case .authenticationFailed: return "AUTH_FAILED"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .sensorExpired:
            return .warning
        case .dataCorrupted, .invalidSensorCode:
            return .error
        case .bluetoothUnavailable, .unauthorized:
            return .warning
        default:
            return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .connectionFailed, .notConnected, .sensorNotFound, .deviceNotFound:
            return .reconnect
        case .bluetoothUnavailable:
            return .checkDevice
        case .invalidSensorCode, .configurationRequired:
            return .none  // UI should prompt for input
        case .sensorExpired:
            return .none  // Need new sensor
        case .authenticationTimeout, .discoveryTimeout:
            return .retry  // PROD-HARDEN-022: Timeouts are transient
        default:
            return .retry
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "CGM error"
    }
}

/// Protocol for CGM drivers
/// Requirements: REQ-CGM-001
public protocol CGMManagerProtocol: Actor {
    var displayName: String { get }
    var cgmType: CGMType { get }
    var sensorState: SensorState { get }
    var latestReading: GlucoseReading? { get }
    
    func startScanning() async throws
    func connect(to sensor: SensorInfo) async throws
    func disconnect() async
    
    var onReadingReceived: (@Sendable (GlucoseReading) -> Void)? { get set }
    var onSensorStateChanged: (@Sendable (SensorState) -> Void)? { get set }
    var onError: (@Sendable (CGMError) -> Void)? { get set }
    
    /// Set callbacks for reading and state change events (actor-isolated setter)
    func setCallbacks(
        onReading: (@Sendable (GlucoseReading) -> Void)?,
        onStateChange: (@Sendable (SensorState) -> Void)?
    )
}

/// Default implementation for setCallbacks
public extension CGMManagerProtocol {
    func setCallbacks(
        onReading: (@Sendable (GlucoseReading) -> Void)?,
        onStateChange: (@Sendable (SensorState) -> Void)?
    ) {
        self.onReadingReceived = onReading
        self.onSensorStateChanged = onStateChange
    }
}

// MARK: - Unified Callback Naming (ARCH-001)

/// Unified callback aliases for cross-protocol consistency
/// Trace: ARCH-001 — Service protocol naming unification
public extension CGMManagerProtocol {
    /// Unified alias for onReadingReceived (matches pump onDataReceived pattern)
    var onDataReceived: (@Sendable (GlucoseReading) -> Void)? {
        get { onReadingReceived }
        set { onReadingReceived = newValue }
    }
    
    /// Unified alias for onSensorStateChanged (matches pump onStateChanged pattern)
    var onStateChanged: (@Sendable (SensorState) -> Void)? {
        get { onSensorStateChanged }
        set { onSensorStateChanged = newValue }
    }
}

/// Configuration for Nightscout follower CGM
public struct NightscoutFollowerConfig: Codable, Sendable {
    public let url: URL
    public let apiSecret: String?
    public let token: String?
    public let fetchIntervalSeconds: Int
    
    public init(
        url: URL,
        apiSecret: String? = nil,
        token: String? = nil,
        fetchIntervalSeconds: Int = 60
    ) {
        self.url = url
        self.apiSecret = apiSecret
        self.token = token
        self.fetchIntervalSeconds = fetchIntervalSeconds
    }
}

/// Nightscout follower CGM (fetches from remote Nightscout)
/// Requirements: REQ-CGM-001, REQ-CGM-004
public actor NightscoutFollowerCGM: CGMManagerProtocol {
    public let displayName = "Nightscout Follower"
    public let cgmType = CGMType.nightscoutFollower
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    private let config: NightscoutFollowerConfig
    private var fetchTask: Task<Void, Never>?
    
    /// Create with full config
    public init(config: NightscoutFollowerConfig) {
        self.config = config
    }
    
    /// Create with just URL (for simple public Nightscout sites)
    public init(nightscoutURL: URL) {
        self.config = NightscoutFollowerConfig(url: nightscoutURL)
    }
    
    public func startScanning() async throws {
        // Validate connection by fetching once
        await fetchLatest()
        if latestReading != nil {
            sensorState = .active
            onSensorStateChanged?(.active)
        } else {
            sensorState = .failed
            onSensorStateChanged?(.failed)
            throw CGMError.connectionFailed
        }
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        try await startScanning()
        startFetching()
    }
    
    public func disconnect() async {
        fetchTask?.cancel()
        fetchTask = nil
        sensorState = .stopped
        onSensorStateChanged?(.stopped)
    }
    
    /// Fetch history (multiple readings)
    public func fetchHistory(count: Int = 36) async -> [GlucoseReading] {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        var components = URLComponents(url: config.url.appendingPathComponent("api/v1/entries/sgv.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "count", value: String(count))]
        
        var request = URLRequest(url: components.url!)
        addAuthHeaders(&request)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
            return entries.compactMap { $0.toGlucoseReading() }
        } catch {
            return []
        }
        #else
        return []
        #endif
    }
    
    private func startFetching() {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        fetchTask = Task {
            while !Task.isCancelled {
                await fetchLatest()
                try? await Task.sleep(nanoseconds: UInt64(config.fetchIntervalSeconds) * 1_000_000_000)
            }
        }
        #endif
    }
    
    private func fetchLatest() async {
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
        var request = URLRequest(url: config.url.appendingPathComponent("api/v1/entries/current.json"))
        addAuthHeaders(&request)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let entries = try JSONDecoder().decode([NightscoutEntry].self, from: data)
            
            if let entry = entries.first, let reading = entry.toGlucoseReading() {
                latestReading = reading
                onReadingReceived?(reading)
            }
        } catch {
            onError?(.dataUnavailable)
        }
        #endif
    }
    
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)
    private func addAuthHeaders(_ request: inout URLRequest) {
        if let secret = config.apiSecret {
            // SHA1 hash the secret
            request.setValue(sha1(secret), forHTTPHeaderField: "api-secret")
        }
        if let token = config.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    #endif
    
    /// Simple SHA1 for API secret (matches NightscoutKit implementation)
    private nonisolated func sha1(_ string: String) -> String {
        let data = Array(string.utf8)
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0
        
        var message = data
        let ml = UInt64(data.count * 8)
        message.append(0x80)
        while (message.count % 64) != 56 { message.append(0x00) }
        for i in (0..<8).reversed() { message.append(UInt8((ml >> (i * 8)) & 0xFF)) }
        
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let o = chunkStart + i * 4
                w[i] = UInt32(message[o]) << 24 | UInt32(message[o+1]) << 16 | UInt32(message[o+2]) << 8 | UInt32(message[o+3])
            }
            for i in 16..<80 { w[i] = (w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]).rotateLeft(1) }
            
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let (f, k): (UInt32, UInt32) = switch i {
                case 0..<20: ((b & c) | ((~b) & d), 0x5A827999)
                case 20..<40: (b ^ c ^ d, 0x6ED9EBA1)
                case 40..<60: ((b & c) | (b & d) | (c & d), 0x8F1BBCDC)
                default: (b ^ c ^ d, 0xCA62C1D6)
                }
                let temp = a.rotateLeft(5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = b.rotateLeft(30); b = a; a = temp
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d; h4 = h4 &+ e
        }
        return String(format: "%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
    }
}

private extension UInt32 {
    func rotateLeft(_ n: UInt32) -> UInt32 {
        return (self << n) | (self >> (32 - n))
    }
}

/// Nightscout entry for decoding (simplified)
private struct NightscoutEntry: Codable {
    let sgv: Int?
    let direction: String?
    let date: Int64
    let device: String?
    
    func toGlucoseReading() -> GlucoseReading? {
        guard let glucose = sgv else { return nil }
        
        let trend: GlucoseTrend
        switch direction?.lowercased() {
        case "flat": trend = .flat
        case "singleup": trend = .singleUp
        case "singledown": trend = .singleDown
        default: trend = .notComputable
        }
        
        return GlucoseReading(
            glucose: Double(glucose),
            timestamp: Date(timeIntervalSince1970: Double(date) / 1000),
            trend: trend,
            source: device ?? "nightscout"
        )
    }
}

// MARK: - Simulation CGM

/// Simulation CGM for testing (uses internal pattern generator)
/// Requirements: REQ-CGM-001
public actor SimulationCGM: CGMManagerProtocol {
    public let displayName = "Simulation"
    public let cgmType = CGMType.simulation
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    private var generateTask: Task<Void, Never>?
    private var lastGlucose: Double = 100.0
    private let intervalSeconds: TimeInterval
    
    /// Create simulation CGM
    /// - Parameter intervalSeconds: Interval between readings (default 300 = 5 min)
    public init(intervalSeconds: TimeInterval = 300) {
        self.intervalSeconds = intervalSeconds
    }
    
    public func startScanning() async throws {
        // Simulation doesn't need scanning
        sensorState = .active
        onSensorStateChanged?(.active)
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        sensorState = .active
        onSensorStateChanged?(.active)
        startGenerating()
    }
    
    public func disconnect() async {
        generateTask?.cancel()
        generateTask = nil
        sensorState = .stopped
        onSensorStateChanged?(.stopped)
    }
    
    /// Generate a single reading (for manual control)
    public func generateReading() -> GlucoseReading {
        // Simple random walk simulation
        let delta = Double.random(in: -5...5)
        lastGlucose = max(40, min(400, lastGlucose + delta))
        
        let trend = calculateTrend(delta: delta)
        let reading = GlucoseReading(
            glucose: lastGlucose,
            timestamp: Date(),
            trend: trend,
            source: "SimulationCGM"
        )
        
        latestReading = reading
        return reading
    }
    
    private func startGenerating() {
        generateTask = Task {
            while !Task.isCancelled {
                let reading = generateReading()
                onReadingReceived?(reading)
                
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
        }
    }
    
    private func calculateTrend(delta: Double) -> GlucoseTrend {
        switch delta {
        case ..<(-3): return .doubleDown
        case -3..<(-2): return .singleDown
        case -2..<(-1): return .fortyFiveDown
        case -1...1: return .flat
        case 1..<2: return .fortyFiveUp
        case 2..<3: return .singleUp
        default: return .doubleUp
        }
    }
}
