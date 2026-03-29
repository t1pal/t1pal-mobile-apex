// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TandemBLEManager.swift
// PumpKit
//
// BLE connection manager for Tandem t:slim X2 pumps.
// Handles pump discovery, J-PAKE authentication, and session management.
// Trace: TANDEM-IMPL-001, TANDEM-AUDIT-001..008, PRD-005
//
// Usage:
//   let manager = TandemBLEManager()
//   await manager.startScanning()
//   try await manager.connect(to: pump)
//   let status = try await manager.readBasalStatus()
//
// Reference: externals/pumpX2/, tools/x2-cli/x2_parsers.py

import Foundation
import BLEKit

// MARK: - Pump Discovery

/// Represents a discovered Tandem X2 pump
public struct DiscoveredTandemPump: Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let rssi: Int
    public let serialNumber: String?
    public let discoveredAt: Date
    
    public init(
        id: String,
        name: String,
        rssi: Int,
        serialNumber: String? = nil
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.serialNumber = serialNumber
        self.discoveredAt = Date()
    }
    
    /// Check if this is a Tandem pump based on name
    public var isTandemPump: Bool {
        let lowerName = name.lowercased()
        return lowerName.contains("tslim") ||
               lowerName.contains("t:slim") ||
               lowerName.contains("tandem")
    }
    
    public var displayName: String {
        if let serial = serialNumber {
            return "t:slim X2 (\(serial))"
        }
        return name
    }
}

// MARK: - Connection State

/// Tandem connection state
public enum TandemConnectionState: String, Sendable {
    case disconnected = "disconnected"
    case scanning = "scanning"
    case connecting = "connecting"
    case authenticating = "authenticating"  // J-PAKE key exchange
    case establishing = "establishing"       // Session setup
    case ready = "ready"
    case error = "error"
    
    public var isConnected: Bool {
        switch self {
        case .ready:
            return true
        default:
            return false
        }
    }
    
    public var canSendCommands: Bool {
        self == .ready
    }
    
    public var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning"
        case .connecting: return "Connecting"
        case .authenticating: return "Authenticating (J-PAKE)"
        case .establishing: return "Establishing Session"
        case .ready: return "Ready"
        case .error: return "Error"
        }
    }
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension TandemConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .disconnected: return .disconnected
        case .scanning: return .scanning
        case .connecting, .authenticating, .establishing: return .connecting
        case .ready: return .connected
        case .error: return .error
        }
    }
}

// MARK: - Session

/// Represents an active Tandem communication session
public struct TandemSession: Sendable {
    public let pumpId: String
    public let pumpSerial: String?
    public private(set) var transactionId: UInt8
    public let sessionStarted: Date
    public private(set) var lastActivity: Date
    public private(set) var pumpTimeSinceReset: UInt32
    
    /// Shared secret from J-PAKE authentication (used for HMAC-SHA1)
    public let sessionKey: Data
    
    /// App instance ID used during authentication
    public let appInstanceId: UInt16
    
    public init(pumpId: String, pumpSerial: String? = nil, sessionKey: Data? = nil, appInstanceId: UInt16? = nil) {
        self.pumpId = pumpId
        self.pumpSerial = pumpSerial
        self.transactionId = 0
        self.sessionStarted = Date()
        self.lastActivity = Date()
        self.pumpTimeSinceReset = 0
        self.appInstanceId = appInstanceId ?? UInt16.random(in: 1...0xFFFF)
        // Use provided session key or generate simulated one
        self.sessionKey = sessionKey ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    }
    
    /// Session duration
    public var duration: TimeInterval {
        Date().timeIntervalSince(sessionStarted)
    }
    
    /// Time since last activity
    public var idleTime: TimeInterval {
        Date().timeIntervalSince(lastActivity)
    }
    
    /// Check if session needs token refresh (> 120s idle)
    public var needsTokenRefresh: Bool {
        idleTime > TandemProtocol.tokenRefreshInterval
    }
    
    /// Get next transaction ID and increment
    public mutating func nextTransactionId() -> UInt8 {
        transactionId = transactionId &+ 1
        lastActivity = Date()
        return transactionId
    }
    
    /// Update pump time from response
    public mutating func updatePumpTime(_ time: UInt32) {
        pumpTimeSinceReset = time
        lastActivity = Date()
    }
}

// MARK: - Errors

/// Tandem BLE errors
public enum TandemBLEError: Error, Sendable, Equatable {
    case notConnected
    case alreadyConnected
    case pumpNotFound
    case authenticationFailed
    case jpakeFailed(String)
    case communicationFailed
    case invalidResponse
    case crcMismatch
    case signatureInvalid
    case noSession
    case tokenExpired
    case timeout
    
    public var localizedDescription: String {
        switch self {
        case .notConnected: return "Not connected to pump"
        case .alreadyConnected: return "Already connected to a pump"
        case .pumpNotFound: return "Pump not found"
        case .authenticationFailed: return "Authentication failed"
        case .jpakeFailed(let reason): return "J-PAKE failed: \(reason)"
        case .communicationFailed: return "Communication failed"
        case .invalidResponse: return "Invalid response from pump"
        case .crcMismatch: return "CRC mismatch in message"
        case .signatureInvalid: return "HMAC signature invalid"
        case .noSession: return "No active session"
        case .tokenExpired: return "Session token expired"
        case .timeout: return "Command timeout"
        }
    }
}

// MARK: - Observer

/// Observer for Tandem connection state changes
public struct TandemConnectionObserver: Sendable {
    public let id: String
    public let onStateChange: @Sendable (TandemConnectionState, DiscoveredTandemPump?) -> Void
    
    public init(id: String, onStateChange: @escaping @Sendable (TandemConnectionState, DiscoveredTandemPump?) -> Void) {
        self.id = id
        self.onStateChange = onStateChange
    }
}

// MARK: - Diagnostics

/// Diagnostic information for Tandem connection
public struct TandemDiagnostics: Sendable {
    public let state: TandemConnectionState
    public let connectedPump: DiscoveredTandemPump?
    public let session: TandemSession?
    public let discoveredCount: Int
    
    public var isHealthy: Bool {
        state == .ready && session != nil
    }
    
    public var sessionAge: TimeInterval? {
        session?.duration
    }
}

// MARK: - Tandem BLE Manager

/// Manager for Tandem t:slim X2 pump BLE connections
/// Trace: TANDEM-IMPL-001, TANDEM-AUDIT-001..008, PRD-005, PUMP-PG-007
public actor TandemBLEManager {
    // MARK: - Properties
    
    private(set) var state: TandemConnectionState = .disconnected
    private(set) var connectedPump: DiscoveredTandemPump?
    private(set) var discoveredPumps: [DiscoveredTandemPump] = []
    private(set) var session: TandemSession?
    
    private var observers: [TandemConnectionObserver] = []
    private var scanTask: Task<Void, Never>?
    
    // J-PAKE engine for authentication
    private var jpakeEngine: TandemJPAKEEngine?
    
    // Pairing code for J-PAKE authentication (6 numeric digits)
    // Set before calling connect() for hardware authentication
    public var pairingCode: String?
    
    // Fault injection support
    public var faultInjector: PumpFaultInjector?
    
    // Metrics support
    private let metrics: PumpMetrics
    
    // MARK: - BLE Transport (PUMP-PG-007)
    
    /// BLE central manager for real hardware communication
    private var central: (any BLECentralProtocol)?
    
    /// Connected BLE peripheral handle
    private var peripheral: (any BLEPeripheralProtocol)?
    
    /// Discovered BLE characteristics by type
    private var characteristics: [TandemCharacteristic: BLECharacteristic] = [:]
    
    /// Whether to use simulation when no real BLE is available
    /// When true, falls back to mock responses if peripheral is nil
    public var allowSimulation: Bool = true
    
    /// Notification streams for each characteristic
    private var notificationTasks: [TandemCharacteristic: Task<Void, Never>] = [:]
    
    /// Pending notification continuations for request/response pattern
    private var pendingNotification: CheckedContinuation<Data, Error>?
    
    public init(faultInjector: PumpFaultInjector? = nil, metrics: PumpMetrics = .shared) {
        self.faultInjector = faultInjector
        self.metrics = metrics
    }
    
    /// Initialize with BLE central for real hardware communication
    /// Trace: PUMP-PG-007
    public init(central: any BLECentralProtocol, faultInjector: PumpFaultInjector? = nil, metrics: PumpMetrics = .shared) {
        self.central = central
        self.faultInjector = faultInjector
        self.metrics = metrics
        self.allowSimulation = false
    }
    
    /// Set BLE central manager for real hardware communication
    /// Call this before startScanning() to enable real BLE
    /// Trace: PUMP-PG-007
    public func setCentral(_ central: any BLECentralProtocol) {
        self.central = central
        self.allowSimulation = false
    }
    
    /// Set whether simulation fallback is allowed
    /// When false, real BLE central is required for operations
    /// Trace: PUMP-PG-007
    public func setAllowSimulation(_ allow: Bool) {
        self.allowSimulation = allow
    }
    
    // MARK: - Factory Methods (PUMP-PG-009)
    
    /// Create manager in demo mode for playground testing
    /// Trace: PUMP-PG-009
    public static func forDemo() -> TandemBLEManager {
        TandemBLEManager()
    }
    
    /// Create manager for unit testing
    public static func forTesting() -> TandemBLEManager {
        TandemBLEManager()
    }
    
    /// Set state directly for testing/demo (PUMP-PG-009)
    public func setTestState(_ newState: TandemConnectionState) {
        state = newState
        notifyObservers()
    }
    
    /// Resume session for demo mode (PUMP-PG-009)
    /// Sets up authenticated session with simulated pump
    public func resumeSession(pumpId: String, serial: String? = nil) {
        connectedPump = DiscoveredTandemPump(
            id: pumpId,
            name: "t:slim X2",
            rssi: -55,
            serialNumber: serial ?? "TP12345678"
        )
        session = TandemSession(pumpId: pumpId, pumpSerial: serial)
        state = .ready
        notifyObservers()
    }
    
    /// Set pairing code for J-PAKE authentication (PUMP-PG-009)
    public func setPairingCode(_ code: String) {
        pairingCode = code
    }
    
    /// Get discovered pumps (PUMP-PG-009)
    public func getDiscoveredPumps() -> [DiscoveredTandemPump] {
        discoveredPumps
    }
    
    // MARK: - Scanning
    
    /// Start scanning for Tandem pumps
    /// Uses real BLE when central is available, otherwise falls back to simulation
    /// Trace: PUMP-PG-007
    public func startScanning() {
        guard state == .disconnected else { return }
        
        state = .scanning
        discoveredPumps = []
        notifyObservers()
        
        PumpLogger.connection.info("Starting Tandem X2 pump scan")
        
        // Discovery task
        scanTask = Task {
            guard !Task.isCancelled else { return }
            
            // Use real BLE if central is available
            if let central = central {
                PumpLogger.connection.info("Scanning with real BLE central")
                await scanWithRealBLE(central)
            } else if allowSimulation {
                // Simulated discovery
                PumpLogger.connection.info("Using simulated pump discovery")
                let simulatedPump = DiscoveredTandemPump(
                    id: "tandem-sim-001",
                    name: "t:slim X2",
                    rssi: -60,
                    serialNumber: "TP12345678"
                )
                addDiscoveredPump(simulatedPump)
            } else {
                PumpLogger.connection.error("No BLE central available and simulation disabled")
                state = .error
                notifyObservers()
            }
        }
    }
    
    /// Scan for pumps using real BLE central
    /// Trace: PUMP-PG-007
    private func scanWithRealBLE(_ central: any BLECentralProtocol) async {
        guard let serviceUUID = BLEUUID(string: TandemServiceUUID) else {
            PumpLogger.connection.error("Invalid Tandem service UUID")
            return
        }
        let scanStream = central.scan(for: [serviceUUID])
        
        do {
            for try await result in scanStream {
                guard !Task.isCancelled else { break }
                
                // Convert BLEScanResult to DiscoveredTandemPump
                let pump = DiscoveredTandemPump(
                    id: result.peripheral.identifier.description,
                    name: result.peripheral.name ?? "Unknown Tandem",
                    rssi: result.rssi,
                    serialNumber: extractSerialFromAdvertisement(result.advertisement)
                )
                
                addDiscoveredPump(pump)
            }
        } catch {
            PumpLogger.connection.error("BLE scan error: \(error)")
        }
    }
    
    /// Extract serial number from advertisement data
    private func extractSerialFromAdvertisement(_ advertisement: BLEAdvertisement) -> String? {
        // Tandem pumps may advertise serial in local name or manufacturer data
        if let localName = advertisement.localName {
            // Parse "t:slim X2 SN12345678" format
            let parts = localName.components(separatedBy: " ")
            if let last = parts.last, last.hasPrefix("SN") {
                return String(last.dropFirst(2))
            }
        }
        return nil
    }
    
    /// Stop scanning
    /// Trace: PUMP-PG-007
    public func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        
        // Stop real BLE scan if active
        if let central = central {
            Task {
                await central.stopScan()
            }
        }
        
        if state == .scanning {
            state = .disconnected
            notifyObservers()
        }
        
        PumpLogger.connection.info("Stopped Tandem X2 pump scan")
    }
    
    /// Add a discovered pump
    public func addDiscoveredPump(_ pump: DiscoveredTandemPump) {
        guard pump.isTandemPump else { return }
        
        if !discoveredPumps.contains(where: { $0.id == pump.id }) {
            discoveredPumps.append(pump)
            PumpLogger.connection.info("Discovered Tandem pump: \(pump.displayName)")
            notifyObservers()
        }
    }
    
    // MARK: - Connection
    
    /// Connect to a Tandem pump
    /// Uses real BLE when central is available, otherwise simulates connection
    /// Trace: PUMP-PG-007
    public func connect(to pump: DiscoveredTandemPump) async throws {
        let startTime = Date()
        
        // Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "tandem.connect")
            if case .injected(let fault) = result {
                await metrics.recordCommand("tandem.connect", duration: 0, success: false, pumpType: .tandemX2)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .disconnected || state == .scanning else {
            throw TandemBLEError.alreadyConnected
        }
        
        stopScanning()
        
        PumpLogger.connection.info("Connecting to Tandem pump: \(pump.displayName)")
        
        state = .connecting
        connectedPump = pump
        notifyObservers()
        
        // Connect via real BLE if central available
        if let central = central {
            try await connectWithRealBLE(central, pump: pump)
        } else if !allowSimulation {
            throw TandemBLEError.pumpNotFound
        }
        // If simulation allowed and no central, proceed with simulated session
        
        // Perform J-PAKE authentication
        try await performJPAKEAuthentication(with: pump)
        
        // Establish session
        try await establishSession(with: pump)
        
        // Create session
        session = TandemSession(pumpId: pump.id, pumpSerial: pump.serialNumber)
        
        state = .ready
        notifyObservers()
        
        // Record metrics
        let duration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("tandem.connect", duration: duration, success: true, pumpType: .tandemX2)
        
        PumpLogger.connection.info("Tandem pump connected and ready: \(pump.displayName)")
    }
    
    /// Connect to pump using real BLE
    /// Trace: PUMP-PG-007
    private func connectWithRealBLE(_ central: any BLECentralProtocol, pump: DiscoveredTandemPump) async throws {
        // Create peripheral info from discovered pump
        guard let peripheralUUID = BLEUUID(string: pump.id) else {
            throw TandemBLEError.pumpNotFound
        }
        let peripheralInfo = BLEPeripheralInfo(
            identifier: peripheralUUID,
            name: pump.name
        )
        
        PumpLogger.connection.info("Connecting to BLE peripheral: \(pump.id)")
        
        // Connect to peripheral
        let connectedPeripheral = try await central.connect(to: peripheralInfo)
        self.peripheral = connectedPeripheral
        
        // Discover Tandem service and characteristics
        try await discoverCharacteristics(on: connectedPeripheral)
        
        PumpLogger.connection.info("BLE characteristics discovered for Tandem pump")
    }
    
    /// Discover Tandem service and characteristics on connected peripheral
    /// Trace: PUMP-PG-007
    private func discoverCharacteristics(on peripheral: any BLEPeripheralProtocol) async throws {
        guard let serviceUUID = BLEUUID(string: TandemServiceUUID) else {
            throw TandemBLEError.pumpNotFound
        }
        
        // Discover Tandem service
        let services = try await peripheral.discoverServices([serviceUUID])
        guard let tandemService = services.first else {
            throw TandemBLEError.pumpNotFound
        }
        
        // Discover all Tandem characteristics
        let charUUIDs = TandemCharacteristic.allCases.compactMap { BLEUUID(string: $0.rawValue) }
        let discoveredChars = try await peripheral.discoverCharacteristics(charUUIDs, for: tandemService)
        
        // Map discovered characteristics
        for char in discoveredChars {
            if let tandemChar = TandemCharacteristic.allCases.first(where: { 
                BLEUUID(string: $0.rawValue) == char.uuid 
            }) {
                characteristics[tandemChar] = char
                PumpLogger.connection.debug("Found characteristic: \(tandemChar.displayName)")
            }
        }
        
        // Subscribe to notification-capable characteristics
        try await setupNotifications(on: peripheral)
    }
    
    /// Setup notifications for characteristics that support it
    /// Trace: PUMP-PG-007
    private func setupNotifications(on peripheral: any BLEPeripheralProtocol) async throws {
        // Subscribe to AUTHORIZATION for J-PAKE responses
        if let authChar = characteristics[.authorization] {
            let stream = peripheral.subscribe(to: authChar)
            notificationTasks[.authorization] = Task { [weak self] in
                do {
                    for try await data in stream {
                        await self?.handleNotification(data, for: .authorization)
                    }
                } catch {
                    PumpLogger.connection.error("Authorization notification error: \(error)")
                }
            }
        }
        
        // Subscribe to CURRENT_STATUS for status responses
        if let statusChar = characteristics[.currentStatus] {
            let stream = peripheral.subscribe(to: statusChar)
            notificationTasks[.currentStatus] = Task { [weak self] in
                do {
                    for try await data in stream {
                        await self?.handleNotification(data, for: .currentStatus)
                    }
                } catch {
                    PumpLogger.connection.error("Status notification error: \(error)")
                }
            }
        }
        
        // Subscribe to CONTROL for signed command responses
        if let controlChar = characteristics[.control] {
            let stream = peripheral.subscribe(to: controlChar)
            notificationTasks[.control] = Task { [weak self] in
                do {
                    for try await data in stream {
                        await self?.handleNotification(data, for: .control)
                    }
                } catch {
                    PumpLogger.connection.error("Control notification error: \(error)")
                }
            }
        }
    }
    
    /// Handle incoming notification data
    private func handleNotification(_ data: Data, for characteristic: TandemCharacteristic) async {
        PumpLogger.protocol_.debug("Received \(data.count) bytes on \(characteristic.displayName)")
        
        // Resume pending continuation if waiting for response
        if let continuation = pendingNotification {
            pendingNotification = nil
            continuation.resume(returning: data)
        }
    }
    
    /// Map fault type to Tandem error
    private func mapFaultToError(_ fault: PumpFaultType) -> Error {
        switch fault {
        case .connectionDrop, .connectionTimeout:
            return TandemBLEError.pumpNotFound
        case .communicationError, .bleDisconnectMidCommand:
            return TandemBLEError.communicationFailed
        case .packetCorruption:
            return TandemBLEError.crcMismatch
        default:
            return TandemBLEError.communicationFailed
        }
    }
    
    /// Perform J-PAKE authentication (P-256 curve)
    /// Reference: TANDEM-AUDIT-003, TANDEM-IMPL-002, externals/pumpX2/
    ///
    /// When pairingCode is set, performs full 10-step J-PAKE protocol:
    /// 1-4: Round 1 exchange (Jpake1a/1b)
    /// 5-6: Round 2 exchange (Jpake2)
    /// 7-8: Session key derivation (Jpake3)
    /// 9-10: Key confirmation (Jpake4)
    ///
    /// When pairingCode is nil, uses simulated instant success for testing.
    private func performJPAKEAuthentication(with pump: DiscoveredTandemPump) async throws {
        state = .authenticating
        notifyObservers()
        
        PumpLogger.connection.info("Performing J-PAKE authentication with \(pump.displayName)")
        
        // Check if we have a pairing code for real authentication
        guard let code = pairingCode, code.count == 6 else {
            // Simulation mode: instant success with random session key
            PumpLogger.connection.info("J-PAKE simulation mode (no pairing code)")
            jpakeEngine = nil
            return
        }
        
        // Initialize J-PAKE engine with pairing code
        let engine: TandemJPAKEEngine
        do {
            engine = try TandemJPAKEEngine(pairingCode: code)
            jpakeEngine = engine
        } catch {
            throw TandemBLEError.jpakeFailed("Invalid pairing code: \(error.localizedDescription)")
        }
        
        PumpLogger.connection.info("Starting J-PAKE round 1 exchange")
        
        // Generate Round 1 data (330 bytes, split into two chunks)
        _ = await engine.generateRound1()
        
        // Step 1-2: Jpake1a exchange
        let jpake1aRequest = await engine.createJpake1aRequest()
        let jpake1aResponseData = try await sendJPAKEMessage(jpake1aRequest)
        let jpake1aResponse = try Jpake1aResponse.decode(from: jpake1aResponseData)
        await engine.handleJpake1aResponse(jpake1aResponse)
        
        // Step 3-4: Jpake1b exchange
        let jpake1bRequest = await engine.createJpake1bRequest()
        let jpake1bResponseData = try await sendJPAKEMessage(jpake1bRequest)
        let jpake1bResponse = try Jpake1bResponse.decode(from: jpake1bResponseData)
        try await engine.handleJpake1bResponse(jpake1bResponse)
        
        PumpLogger.connection.info("J-PAKE round 1 complete, starting round 2")
        
        // Step 5-6: Jpake2 exchange
        let jpake2Request = try await engine.createJpake2Request()
        let jpake2ResponseData = try await sendJPAKEMessage(jpake2Request)
        let jpake2Response = try Jpake2Response.decode(from: jpake2ResponseData)
        try await engine.handleJpake2Response(jpake2Response)
        
        PumpLogger.connection.info("J-PAKE round 2 complete, deriving session key")
        
        // Step 7-8: Session key derivation
        let jpake3Request = await engine.createJpake3SessionKeyRequest()
        let jpake3ResponseData = try await sendJPAKEMessage(jpake3Request)
        let jpake3Response = try Jpake3SessionKeyResponse.decode(from: jpake3ResponseData)
        _ = try await engine.handleJpake3SessionKeyResponse(jpake3Response)
        
        PumpLogger.connection.info("Session key derived, confirming")
        
        // Step 9-10: Key confirmation
        let jpake4Request = try await engine.createJpake4KeyConfirmationRequest()
        let jpake4ResponseData = try await sendJPAKEMessage(jpake4Request)
        let jpake4Response = try Jpake4KeyConfirmationResponse.decode(from: jpake4ResponseData)
        let confirmed = try await engine.handleJpake4KeyConfirmationResponse(jpake4Response)
        
        guard confirmed, await engine.isAuthenticated else {
            throw TandemBLEError.jpakeFailed("Key confirmation failed")
        }
        
        PumpLogger.connection.info("J-PAKE authentication successful")
    }
    
    /// Send a J-PAKE message and wait for response
    /// Uses real BLE when peripheral is available, otherwise simulates
    /// Trace: PUMP-PG-007
    private func sendJPAKEMessage<M: TandemJPAKEMessage>(_ message: M) async throws -> Data {
        // Use real BLE if peripheral is connected
        if let peripheral = peripheral, let authChar = characteristics[.authorization] {
            return try await sendBLEMessage(message.encode(), to: authChar, on: peripheral)
        }
        
        // Simulation fallback
        guard allowSimulation else {
            throw TandemBLEError.notConnected
        }
        return generateMockJPAKEResponse(for: M.opcode)
    }
    
    /// Send data to characteristic and wait for notification response
    /// Trace: PUMP-PG-007
    private func sendBLEMessage(_ data: Data, to characteristic: BLECharacteristic, on peripheral: any BLEPeripheralProtocol) async throws -> Data {
        PumpLogger.protocol_.debug("Sending \(data.count) bytes to \(characteristic.uuid)")
        
        // Write data to characteristic
        try await peripheral.writeValue(data, for: characteristic, type: .withResponse)
        
        // Wait for notification response with timeout (5 seconds)
        return try await withTimeout(seconds: 5.0) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                Task { @MainActor in
                    await self.setPendingNotification(continuation)
                }
            }
        }
    }
    
    /// Set pending notification continuation (called from nonisolated context)
    private func setPendingNotification(_ continuation: CheckedContinuation<Data, Error>) {
        pendingNotification = continuation
    }
    
    /// Timeout wrapper for async operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TandemBLEError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    /// Generate mock J-PAKE response for simulation
    private func generateMockJPAKEResponse(for opcode: TandemJPAKEOpcode) -> Data {
        switch opcode {
        case .jpake1aRequest:
            // Jpake1aResponse: appInstanceId (2) + serverRound1Part1 (165)
            var response = Data()
            response.append(contentsOf: [0x01, 0x00])  // appInstanceId = 1
            response.append(Data(count: TandemJPAKEConstants.round1ChunkSize))
            return response
            
        case .jpake1bRequest:
            // Jpake1bResponse: appInstanceId (2) + serverRound1Part2 (165)
            var response = Data()
            response.append(contentsOf: [0x01, 0x00])
            response.append(Data(count: TandemJPAKEConstants.round1ChunkSize))
            return response
            
        case .jpake2Request:
            // Jpake2Response: appInstanceId (2) + serverRound2 (168)
            var response = Data()
            response.append(contentsOf: [0x01, 0x00])
            response.append(Data(count: 168))
            return response
            
        case .jpake3SessionKeyRequest:
            // Jpake3SessionKeyResponse: appInstanceId (2) + serverNonce (16)
            var response = Data()
            response.append(contentsOf: [0x01, 0x00])
            response.append(Data((0..<TandemJPAKEConstants.serverNonceSize).map { _ in UInt8.random(in: 0...255) }))
            return response
            
        case .jpake4KeyConfirmationRequest:
            // Jpake4KeyConfirmationResponse: appInstanceId (2) + hash (32)
            var response = Data()
            response.append(contentsOf: [0x01, 0x00])
            response.append(Data(count: TandemJPAKEConstants.confirmationHashSize))
            return response
            
        default:
            return Data()
        }
    }
    
    /// Establish session after authentication
    private func establishSession(with pump: DiscoveredTandemPump) async throws {
        state = .establishing
        notifyObservers()
        
        PumpLogger.connection.info("Establishing session with \(pump.displayName)")
        
        // Get session key from J-PAKE engine or use simulated one
        var sessionKey: Data?
        var appInstanceId: UInt16?
        
        if let engine = jpakeEngine {
            sessionKey = await engine.sessionKey
            appInstanceId = engine.appInstanceId  // let property of Sendable type
        }
        
        // Create session with authenticated key
        session = TandemSession(
            pumpId: pump.id,
            pumpSerial: pump.serialNumber,
            sessionKey: sessionKey,
            appInstanceId: appInstanceId
        )
        
        PumpLogger.connection.info("Session established with \(sessionKey != nil ? "authenticated" : "simulated") key")
    }
    
    /// Disconnect from pump
    /// Trace: PUMP-PG-007
    public func disconnect() async {
        guard let pump = connectedPump else { return }
        
        PumpLogger.connection.info("Disconnecting from Tandem pump: \(pump.displayName)")
        
        // Cancel notification tasks
        for (_, task) in notificationTasks {
            task.cancel()
        }
        notificationTasks.removeAll()
        
        // Disconnect BLE peripheral
        if let peripheral = peripheral, let central = central {
            await central.disconnect(peripheral)
        }
        
        // Clear state
        peripheral = nil
        characteristics.removeAll()
        pendingNotification = nil
        
        connectedPump = nil
        session = nil
        state = .disconnected
        notifyObservers()
    }
    
    // MARK: - Commands
    
    /// Send an unsigned command (CURRENT_STATUS characteristic)
    public func sendUnsignedCommand(opcode: TandemUnsignedOpcode, cargo: Data = Data()) async throws -> TandemMessage {
        let startTime = Date()
        let commandName = "tandem.\(opcode.displayName)"
        
        // Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: commandName)
            if case .injected(let fault) = result {
                await metrics.recordCommand(commandName, duration: 0, success: false, pumpType: .tandemX2)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .ready else {
            throw TandemBLEError.notConnected
        }
        
        guard var currentSession = session else {
            throw TandemBLEError.noSession
        }
        
        let txId = currentSession.nextTransactionId()
        session = currentSession
        
        PumpLogger.protocol_.info("Sending \(opcode.displayName) (txId: \(txId))")
        
        // Build message
        let messageData = buildMessage(opcode: opcode.rawValue, transactionId: txId, cargo: cargo, signed: false)
        
        // Use real BLE if peripheral is connected, otherwise simulate
        let responseData: Data
        if let peripheral = peripheral, let statusChar = characteristics[.currentStatus] {
            responseData = try await sendBLEMessage(messageData, to: statusChar, on: peripheral)
        } else if allowSimulation {
            responseData = buildMockResponse(for: opcode)
        } else {
            throw TandemBLEError.notConnected
        }
        
        guard let response = parseTandemMessage(responseData, signed: false) else {
            throw TandemBLEError.invalidResponse
        }
        
        guard response.crcValid else {
            throw TandemBLEError.crcMismatch
        }
        
        // Record metrics
        let duration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand(commandName, duration: duration, success: true, pumpType: .tandemX2)
        
        return response
    }
    
    /// Send a signed command (CONTROL characteristic)
    /// Trace: PUMP-PG-007
    public func sendSignedCommand(opcode: TandemSignedOpcode, cargo: Data = Data()) async throws -> TandemMessage {
        let startTime = Date()
        let commandName = "tandem.\(opcode.displayName)"
        
        // Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: commandName)
            if case .injected(let fault) = result {
                await metrics.recordCommand(commandName, duration: 0, success: false, pumpType: .tandemX2)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .ready else {
            throw TandemBLEError.notConnected
        }
        
        guard var currentSession = session else {
            throw TandemBLEError.noSession
        }
        
        // Check token expiry
        if currentSession.needsTokenRefresh {
            PumpLogger.connection.warning("Session token needs refresh")
            // In production: perform token refresh
        }
        
        let txId = currentSession.nextTransactionId()
        session = currentSession
        
        PumpLogger.protocol_.info("Sending signed \(opcode.displayName) (txId: \(txId))")
        
        // Build signed message with HMAC-SHA1
        let messageData = buildSignedMessage(opcode: opcode.rawValue, transactionId: txId, cargo: cargo, sessionKey: currentSession.sessionKey)
        
        // Use real BLE if peripheral is connected, otherwise simulate
        let responseData: Data
        if let peripheral = peripheral, let controlChar = characteristics[.control] {
            responseData = try await sendBLEMessage(messageData, to: controlChar, on: peripheral)
        } else if allowSimulation {
            responseData = buildMockSignedResponse(for: opcode)
        } else {
            throw TandemBLEError.notConnected
        }
        
        guard let response = parseTandemMessage(responseData, signed: true) else {
            throw TandemBLEError.invalidResponse
        }
        
        guard response.crcValid else {
            throw TandemBLEError.crcMismatch
        }
        
        // Update pump time from response signature
        if let pumpTime = response.pumpTimeSinceReset {
            session?.updatePumpTime(pumpTime)
        }
        
        // Record metrics
        let duration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand(commandName, duration: duration, success: true, pumpType: .tandemX2)
        
        return response
    }
    
    // MARK: - High-Level Commands
    
    /// Read current basal status
    public func readBasalStatus() async throws -> TandemBasalStatus {
        let response = try await sendUnsignedCommand(opcode: .currentBasalStatusRequest)
        
        guard let status = TandemBasalStatus.parse(from: response.cargo) else {
            throw TandemBLEError.invalidResponse
        }
        
        return status
    }
    
    /// Read temp rate status
    public func readTempRateStatus() async throws -> TandemTempRateStatus {
        let response = try await sendUnsignedCommand(opcode: .tempRateRequest)
        
        guard let status = TandemTempRateStatus.parse(from: response.cargo) else {
            throw TandemBLEError.invalidResponse
        }
        
        return status
    }
    
    /// Read IOB
    public func readIOB() async throws -> TandemIOBStatus {
        let response = try await sendUnsignedCommand(opcode: .iobRequest)
        
        guard let status = TandemIOBStatus.parse(from: response.cargo) else {
            throw TandemBLEError.invalidResponse
        }
        
        return status
    }
    
    // MARK: - Profile (IDP) Commands
    
    /// Read profile status - lists available insulin delivery profiles
    public func readProfileStatus() async throws -> TandemProfileStatus {
        let response = try await sendUnsignedCommand(opcode: .profileStatusRequest)
        
        guard let status = TandemProfileStatus.parse(from: response.cargo) else {
            throw TandemBLEError.invalidResponse
        }
        
        return status
    }
    
    /// Read IDP settings for a profile
    /// - Parameter idpId: Profile ID (not slot index)
    public func readIDPSettings(idpId: Int) async throws -> TandemIDPSettings {
        var cargo = Data()
        cargo.append(UInt8(idpId & 0xFF))
        
        let response = try await sendUnsignedCommand(opcode: .idpSettingsRequest, cargo: cargo)
        
        guard let settings = TandemIDPSettings.parse(from: response.cargo) else {
            throw TandemBLEError.invalidResponse
        }
        
        return settings
    }
    
    /// Read a single segment from a profile
    /// - Parameters:
    ///   - idpId: Profile ID
    ///   - segmentIndex: Segment index (0-based)
    public func readIDPSegment(idpId: Int, segmentIndex: Int) async throws -> TandemIDPSegment {
        var cargo = Data()
        cargo.append(UInt8(idpId & 0xFF))
        cargo.append(UInt8(segmentIndex & 0xFF))
        
        let response = try await sendUnsignedCommand(opcode: .idpSegmentRequest, cargo: cargo)
        
        guard let segment = TandemIDPSegment.parse(from: response.cargo) else {
            throw TandemBLEError.invalidResponse
        }
        
        return segment
    }
    
    /// Read all segments for a profile
    /// - Parameter idpId: Profile ID
    public func readAllIDPSegments(idpId: Int) async throws -> [TandemIDPSegment] {
        let settings = try await readIDPSettings(idpId: idpId)
        
        var segments: [TandemIDPSegment] = []
        for i in 0..<settings.numberOfSegments {
            let segment = try await readIDPSegment(idpId: idpId, segmentIndex: i)
            segments.append(segment)
        }
        
        return segments
    }
    
    /// Read basal schedule from a profile (Loop-compatible format)
    /// - Parameter idpId: Profile ID
    public func readBasalSchedule(idpId: Int) async throws -> TandemBasalSchedule {
        let settings = try await readIDPSettings(idpId: idpId)
        let segments = try await readAllIDPSegments(idpId: idpId)
        
        return TandemBasalSchedule(
            idpId: idpId,
            profileName: settings.name,
            segments: segments
        )
    }
    
    /// Modify an IDP segment (signed command)
    /// - Parameters:
    ///   - idpId: Profile ID
    ///   - segmentIndex: Segment index to modify
    ///   - operation: Create, modify, or delete
    ///   - startTimeMinutes: Start time in minutes since midnight
    ///   - basalRateMilliunits: Basal rate in milliunits/hr
    ///   - carbRatio: Carb ratio encoded (× 1000)
    ///   - targetBG: Target BG in mg/dL
    ///   - isf: Insulin sensitivity factor
    ///   - statusFlags: Which fields to set
    public func setIDPSegment(
        idpId: Int,
        segmentIndex: Int,
        operation: TandemIDPSegmentOperation,
        startTimeMinutes: Int,
        basalRateMilliunits: Int,
        carbRatio: Int,
        targetBG: Int,
        isf: Int,
        statusFlags: TandemIDPSegmentStatus
    ) async throws {
        // Build cargo (17 bytes)
        // Format: [idpId, unknownId, segmentIndex, operationId, startTime(2), basalRate(2), carbRatio(4), targetBG(2), isf(2), statusId]
        var cargo = Data()
        cargo.append(UInt8(idpId & 0xFF))
        cargo.append(0x00)  // unknownId - always 0 in pumpX2
        cargo.append(UInt8(segmentIndex & 0xFF))
        cargo.append(UInt8(operation.rawValue))
        cargo.append(UInt8(startTimeMinutes & 0xFF))
        cargo.append(UInt8((startTimeMinutes >> 8) & 0xFF))
        cargo.append(UInt8(basalRateMilliunits & 0xFF))
        cargo.append(UInt8((basalRateMilliunits >> 8) & 0xFF))
        cargo.append(UInt8(carbRatio & 0xFF))
        cargo.append(UInt8((carbRatio >> 8) & 0xFF))
        cargo.append(UInt8((carbRatio >> 16) & 0xFF))
        cargo.append(UInt8((carbRatio >> 24) & 0xFF))
        cargo.append(UInt8(targetBG & 0xFF))
        cargo.append(UInt8((targetBG >> 8) & 0xFF))
        cargo.append(UInt8(isf & 0xFF))
        cargo.append(UInt8((isf >> 8) & 0xFF))
        cargo.append(statusFlags.rawValue)
        
        let response = try await sendSignedCommand(opcode: .setIDPSegmentRequest, cargo: cargo)
        
        // Check response status byte
        if response.cargo.isEmpty || response.cargo[0] != 0 {
            throw TandemBLEError.communicationFailed
        }
        
        PumpLogger.protocol_.info("IDP segment \(segmentIndex) modified for profile \(idpId)")
    }
    
    /// Set temp basal rate
    /// - Parameters:
    ///   - percentage: Rate percentage (0-250)
    ///   - durationMinutes: Duration in minutes
    public func setTempRate(percentage: Int, durationMinutes: Int) async throws {
        var cargo = Data()
        cargo.append(UInt8(percentage))
        cargo.append(UInt8(durationMinutes & 0xFF))
        cargo.append(UInt8((durationMinutes >> 8) & 0xFF))
        
        let response = try await sendSignedCommand(opcode: .setTempRateRequest, cargo: cargo)
        
        // Check response status byte
        if response.cargo.isEmpty || response.cargo[0] != 0 {
            throw TandemBLEError.communicationFailed
        }
        
        PumpLogger.protocol_.info("Temp rate set: \(percentage)% for \(durationMinutes) min")
    }
    
    /// Cancel temp basal rate
    public func cancelTempRate() async throws {
        let response = try await sendSignedCommand(opcode: .stopTempRateRequest)
        
        // Check response status byte
        if response.cargo.isEmpty || response.cargo[0] != 0 {
            throw TandemBLEError.communicationFailed
        }
        
        PumpLogger.protocol_.info("Temp rate cancelled")
    }
    
    // MARK: - Message Building
    
    /// Build unsigned message
    private func buildMessage(opcode: Int, transactionId: UInt8, cargo: Data, signed: Bool) -> Data {
        var message = Data()
        message.append(UInt8(opcode & 0xFF))
        message.append(transactionId)
        message.append(UInt8(cargo.count))
        message.append(cargo)
        
        // Append CRC-16
        let crc = TandemCRC16.calculate(message)
        message.append(UInt8((crc >> 8) & 0xFF))
        message.append(UInt8(crc & 0xFF))
        
        return message
    }
    
    /// Build signed message with HMAC-SHA1
    /// Trace: TANDEM-IMPL-003
    private func buildSignedMessage(opcode: Int, transactionId: UInt8, cargo: Data, sessionKey: Data) -> Data {
        // Get pump time from session (or use current time for simulation)
        let pumpTime = session?.pumpTimeSinceReset ?? UInt32(Date().timeIntervalSince1970) & 0xFFFFFFFF
        
        // Build signature using real HMAC-SHA1
        let signature = TandemHMAC.buildSignature(
            cargo: cargo,
            pumpTimeSinceReset: pumpTime,
            sessionKey: sessionKey
        )
        
        // Build full cargo (original cargo + signature)
        var signedCargo = cargo
        signedCargo.append(signature)
        
        return buildMessage(opcode: opcode, transactionId: transactionId, cargo: signedCargo, signed: true)
    }
    
    /// Build mock response for unsigned command
    private func buildMockResponse(for opcode: TandemUnsignedOpcode) -> Data {
        var cargo: Data
        
        switch opcode {
        case .currentBasalStatusRequest:
            // Mock basal status: 800 mU/hr profile, 800 mU/hr current, no flags
            cargo = Data([0x20, 0x03, 0x20, 0x03, 0x00, 0x00])
        case .tempRateRequest:
            // Mock temp rate: not active
            cargo = Data([0x00, 0x64, 0x00, 0x00])
        case .iobRequest:
            // Mock IOB: 2500 mU (2.5 U)
            cargo = Data([0xC4, 0x09, 0x00, 0x00])
        case .profileStatusRequest:
            // Mock profile status: 2 profiles, IDs 1 and 0, active segment 0
            // Format: [numProfiles, slot0Id, slot1Id, slot2Id, slot3Id, slot4Id, slot5Id, activeSegmentIndex]
            cargo = Data([0x02, 0x01, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
        case .idpSettingsRequest:
            // Mock IDP settings for profile ID 1: "Profile1", 2 segments, 300min DIA, 25000mU max bolus
            // Format: [idpId, name(16), numSegments, insulinDuration(2), maxBolus(2), carbEntry]
            var settings = Data([0x01])  // idpId
            settings.append(contentsOf: "Profile1".padding(toLength: 16, withPad: "\0", startingAt: 0).utf8.prefix(16))
            settings.append(0x02)  // 2 segments
            settings.append(contentsOf: [0x2C, 0x01])  // 300 minutes DIA
            settings.append(contentsOf: [0xA8, 0x61])  // 25000 mU max bolus
            settings.append(0x01)  // carb entry enabled
            cargo = settings
        case .idpSegmentRequest:
            // Mock IDP segment 0: midnight start, 800 mU/hr, 10:1 carb ratio, 100 target, 50 ISF
            // Format: [idpId, segmentIndex, startTime(2), basalRate(2), carbRatio(4), targetBG(2), isf(2), statusId]
            cargo = Data([
                0x01,        // idpId
                0x00,        // segmentIndex
                0x00, 0x00,  // startTime = 0 (midnight)
                0x20, 0x03,  // basalRate = 800 mU/hr
                0x10, 0x27, 0x00, 0x00,  // carbRatio = 10000 (10:1)
                0x64, 0x00,  // targetBG = 100
                0x32, 0x00,  // ISF = 50
                0x0F        // statusId = all flags set
            ])
        default:
            cargo = Data([0x00])
        }
        
        // Response opcode is request + 1
        let responseOpcode = opcode.rawValue + 1
        
        var message = Data()
        message.append(UInt8(responseOpcode))
        message.append(0x01) // transaction ID
        message.append(UInt8(cargo.count))
        message.append(cargo)
        
        let crc = TandemCRC16.calculate(message)
        message.append(UInt8((crc >> 8) & 0xFF))
        message.append(UInt8(crc & 0xFF))
        
        return message
    }
    
    /// Build mock response for signed command
    private func buildMockSignedResponse(for opcode: TandemSignedOpcode) -> Data {
        // Success response
        var cargo = Data([0x00])
        
        // Add signature (24 bytes)
        let time = UInt32(Date().timeIntervalSince1970) & 0xFFFFFFFF
        cargo.append(contentsOf: withUnsafeBytes(of: time.littleEndian) { Array($0) })
        cargo.append(Data((0..<20).map { _ in UInt8.random(in: 0...255) }))
        
        let responseOpcode = opcode.rawValue + 1
        
        var message = Data()
        message.append(UInt8(responseOpcode))
        message.append(0x01)
        message.append(UInt8(cargo.count))
        message.append(cargo)
        
        let crc = TandemCRC16.calculate(message)
        message.append(UInt8((crc >> 8) & 0xFF))
        message.append(UInt8(crc & 0xFF))
        
        return message
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic information
    public func diagnosticInfo() -> TandemDiagnostics {
        TandemDiagnostics(
            state: state,
            connectedPump: connectedPump,
            session: session,
            discoveredCount: discoveredPumps.count
        )
    }
    
    // MARK: - Observers
    
    /// Add a connection observer
    public func addObserver(_ observer: TandemConnectionObserver) {
        observers.append(observer)
    }
    
    /// Remove a connection observer
    public func removeObserver(_ observer: TandemConnectionObserver) {
        observers.removeAll { $0.id == observer.id }
    }
    
    private func notifyObservers() {
        let currentState = state
        let pump = connectedPump
        
        for observer in observers {
            observer.onStateChange(currentState, pump)
        }
    }
}
