// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DexcomG7Manager.swift
// CGMKit - DexcomG7
//
// Dexcom G7 CGM driver using BLEKit abstraction.
// G7 uses J-PAKE authentication and is a one-piece sensor.
// Supports active, passive, and HealthKit-only modes for vendor coexistence.
// Trace: PRD-008 REQ-BLE-008, REQ-CGM-002, REQ-CGM-009a, CGM-031, LOG-ADOPT-002

import Foundation
import T1PalCore
import BLEKit

/// Dexcom G7 connection state
public enum G7ConnectionState: String, Sendable {
    case idle
    case scanning
    case connecting
    case pairing
    case authenticating
    case streaming
    case disconnecting
    case error
    /// Passive mode - observing only
    case passive
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension G7ConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .idle: return .disconnected
        case .scanning: return .scanning
        case .connecting, .pairing, .authenticating, .disconnecting: return .connecting
        case .streaming, .passive: return .connected
        case .error: return .error
        }
    }
}

/// Dexcom G7 Manager Configuration
public struct DexcomG7ManagerConfig: Sendable {
    /// Connection mode - direct, passive BLE, or HealthKit-only
    public let connectionMode: CGMConnectionMode
    
    /// Sensor serial number (10 characters)
    public let sensorSerial: String
    
    /// 4-digit sensor code for J-PAKE authentication
    public let sensorCode: String
    
    /// Whether to fall back to HealthKit when in passive mode
    public let passiveFallbackToHealthKit: Bool
    
    /// PROD-HARDEN-032: Whether to allow simulated/mock BLE centrals
    /// Default false for production safety. Set true explicitly for testing.
    public let allowSimulation: Bool
    
    public init(
        sensorSerial: String,
        sensorCode: String,
        connectionMode: CGMConnectionMode = .direct,
        passiveFallbackToHealthKit: Bool = true,
        allowSimulation: Bool = false
    ) {
        self.sensorSerial = sensorSerial
        self.sensorCode = sensorCode
        self.connectionMode = connectionMode
        self.passiveFallbackToHealthKit = passiveFallbackToHealthKit
        self.allowSimulation = allowSimulation
    }
}

/// Dexcom G7 CGM Manager
///
/// Full Dexcom G7 BLE driver using BLEKit abstraction.
/// Uses J-PAKE authentication with 4-digit sensor code.
/// Can be used with MockBLE for testing or real BLE implementations.
public actor DexcomG7Manager: CGMManagerProtocol {
    
    // MARK: - CGMManagerProtocol
    
    public let displayName = "Dexcom G7"
    public let cgmType = CGMType.dexcomG7
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    /// Actor-isolated setCallbacks implementation
    /// The protocol extension's setCallbacks doesn't work for actors because
    /// it's not actor-isolated. This override ensures callbacks are set
    /// within the actor's isolation context.
    /// Trace: G7-CALLBACK-FIX-001
    public func setCallbacks(
        onReading: (@Sendable (GlucoseReading) -> Void)?,
        onStateChange: (@Sendable (SensorState) -> Void)?
    ) {
        self.onReadingReceived = onReading
        self.onSensorStateChanged = onStateChange
        emitDiagnostic("📲 setCallbacks: onReading=\(onReading != nil ? "set" : "nil"), onStateChange=\(onStateChange != nil ? "set" : "nil")")
    }
    
    /// Callback for authentication failure with code mismatch - enables graceful re-prompt.
    /// Trace: BLE-QUIRK-001
    public var onCodeMismatch: (@Sendable () -> Void)?
    
    // MARK: - G7-Specific
    
    /// Current connection state
    public private(set) var connectionState: G7ConnectionState = .idle
    
    /// Connection state change callback
    public var onConnectionStateChanged: (@Sendable (G7ConnectionState) -> Void)?
    
    /// The sensor serial number
    public let sensorSerial: String
    
    /// The 4-digit sensor code for J-PAKE authentication
    public private(set) var sensorCode: String
    
    /// Current sensor info
    public private(set) var sensorInfo: G7SensorInfo?
    
    // MARK: - Private
    
    private let central: any BLECentralProtocol
    private var peripheral: (any BLEPeripheralProtocol)?
    private var authenticator: G7Authenticator?
    private var scanTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    
    // Discovered characteristics
    private var authCharacteristic: BLECharacteristic?
    private var controlCharacteristic: BLECharacteristic?
    private var backfillCharacteristic: BLECharacteristic?
    
    // MARK: - Passive Mode
    
    /// Configuration
    public let config: DexcomG7ManagerConfig
    
    /// Connection mode from config
    public var connectionMode: CGMConnectionMode { config.connectionMode }
    
    /// Passive scanner for coexistence mode
    private var passiveScanner: PassiveBLEScanner?
    
    /// G7-PASSIVE-005: Task monitoring connection events for coexistence
    private var connectionEventsTask: Task<Void, Never>?
    
    /// Callback for vendor connection status
    public var onVendorConnectionDetected: (@Sendable (Bool) -> Void)?
    
    /// G7-COEX-DIAG-001: Diagnostic callback for coexistence debugging
    /// Emits detailed logs visible in playground UI
    public var onDiagnostic: (@Sendable (String) -> Void)?
    
    /// Emit diagnostic message to callback and os.log
    private func emitDiagnostic(_ message: String) {
        CGMLogger.general.debug("G7Diag: \(message)")
        onDiagnostic?(message)
    }
    
    /// Helper to emit error from within Tasks (crosses actor boundary)
    private func emitError(_ error: CGMError) {
        onError?(error)
    }
    
    /// Whether vendor app is detected as connected
    public private(set) var vendorAppConnected: Bool = false
    
    // MARK: - Session Tracking (G6-DIRECT-036)
    
    /// G7 timing constants (in seconds for consistency with G6)
    /// Note: G7 warmup is 27 min (vs G6's 2 hours)
    public static let warmupDuration: TimeInterval = 27 * 60  // 27 minutes
    public static let sessionDuration: TimeInterval = 10 * 24 * 60 * 60  // 10 days
    public static let gracePeriod: TimeInterval = 12 * 60 * 60  // 12 hours
    
    /// Session start date computed from sensor time
    /// Set when G7SensorTimeRxMessage is received
    public private(set) var sessionStartDate: Date?
    
    /// Sensor activation date (when sensor was first powered on)
    public private(set) var sensorActivationDate: Date?
    
    /// Last session age in seconds (from G7SensorTimeRxMessage)
    public private(set) var lastSessionAge: UInt32?
    
    /// Time remaining until sensor warmup completes
    /// Returns nil if not in warmup, or warmup already complete
    public var warmupTimeRemaining: TimeInterval? {
        guard let sessionAge = lastSessionAge else { return nil }
        let warmupSeconds = Self.warmupDuration
        let remaining = warmupSeconds - TimeInterval(sessionAge)
        return remaining > 0 ? remaining : nil
    }
    
    /// Time remaining until sensor session expires (before grace period)
    /// Returns nil if no session or already expired
    public var sessionTimeRemaining: TimeInterval? {
        guard let sessionAge = lastSessionAge else { return nil }
        let sessionSeconds = Self.sessionDuration
        let remaining = sessionSeconds - TimeInterval(sessionAge)
        return remaining > 0 ? remaining : nil
    }
    
    /// Time remaining until sensor is completely unusable (end of grace period)
    /// Returns nil if no session or already past grace period
    public var totalTimeRemaining: TimeInterval? {
        guard let sessionAge = lastSessionAge else { return nil }
        let totalSeconds = Self.sessionDuration + Self.gracePeriod
        let remaining = totalSeconds - TimeInterval(sessionAge)
        return remaining > 0 ? remaining : nil
    }
    
    /// Whether sensor is currently in warmup period
    public var isInWarmup: Bool {
        guard let sessionAge = lastSessionAge else { return false }
        return TimeInterval(sessionAge) < Self.warmupDuration
    }
    
    /// Whether sensor session has expired (past 10 days but may be in grace period)
    public var isSessionExpired: Bool {
        guard let sessionAge = lastSessionAge else { return false }
        return TimeInterval(sessionAge) >= Self.sessionDuration
    }
    
    /// Whether sensor is in grace period (past 10 days but within 12 hours)
    public var isInGracePeriod: Bool {
        guard let sessionAge = lastSessionAge else { return false }
        let age = TimeInterval(sessionAge)
        return age >= Self.sessionDuration && age < (Self.sessionDuration + Self.gracePeriod)
    }
    
    /// Whether sensor is completely expired (past grace period)
    public var isCompletelyExpired: Bool {
        guard let sessionAge = lastSessionAge else { return false }
        return TimeInterval(sessionAge) >= (Self.sessionDuration + Self.gracePeriod)
    }
    
    // MARK: - Fault Injection (Testing)
    
    /// Optional fault injector for testing error paths
    /// Trace: G7-FIX-016, SIM-FAULT-001
    private var faultInjector: G7FaultInjector?
    
    // MARK: - Protocol Logging (G7-DIAG-004)
    
    /// Protocol logger for J-PAKE authentication tracing
    /// Trace: G7-DIAG-004
    private var protocolLogger: G7ProtocolLogger?
    
    // MARK: - Initialization
    
    /// Create a G7 manager with a BLE central
    /// - Parameters:
    ///   - sensorSerial: The sensor serial number (10 characters)
    ///   - sensorCode: The 4-digit sensor code for authentication
    ///   - central: BLE central implementation (real or mock)
    ///   - faultInjector: Optional fault injector for testing (default: nil)
    ///   - protocolLogger: Optional protocol logger for J-PAKE tracing (default: nil)
    ///   - allowSimulation: Allow simulated BLE central (default: false for production safety)
    public init(
        sensorSerial: String,
        sensorCode: String,
        central: any BLECentralProtocol,
        faultInjector: G7FaultInjector? = nil,
        protocolLogger: G7ProtocolLogger? = nil,
        allowSimulation: Bool = false
    ) throws {
        self.sensorSerial = sensorSerial
        self.sensorCode = sensorCode
        self.central = central
        self.authenticator = try G7Authenticator(sensorCode: sensorCode)
        self.sensorInfo = G7SensorInfo(sensorSerial: sensorSerial, sensorCode: sensorCode)
        self.config = DexcomG7ManagerConfig(sensorSerial: sensorSerial, sensorCode: sensorCode, allowSimulation: allowSimulation)
        self.faultInjector = faultInjector
        self.protocolLogger = protocolLogger
        CGMLogger.general.info("DexcomG7Manager: initialized with sensor \(sensorSerial)")
    }
    
    /// Create a G7 manager with full configuration
    /// - Parameters:
    ///   - config: Full configuration including connection mode
    ///   - central: BLE central implementation (real or mock)
    ///   - faultInjector: Optional fault injector for testing (default: nil)
    ///   - protocolLogger: Optional protocol logger for J-PAKE tracing (default: nil)
    public init(
        config: DexcomG7ManagerConfig,
        central: any BLECentralProtocol,
        faultInjector: G7FaultInjector? = nil,
        protocolLogger: G7ProtocolLogger? = nil
    ) throws {
        self.sensorSerial = config.sensorSerial
        self.sensorCode = config.sensorCode
        self.central = central
        self.config = config
        self.faultInjector = faultInjector
        self.protocolLogger = protocolLogger
        // Only create authenticator for active mode
        if config.connectionMode == .direct {
            self.authenticator = try G7Authenticator(sensorCode: config.sensorCode)
        }
        self.sensorInfo = G7SensorInfo(sensorSerial: config.sensorSerial, sensorCode: config.sensorCode)
        CGMLogger.general.info("DexcomG7Manager: initialized with sensor \(config.sensorSerial) mode=\(config.connectionMode.rawValue)")
    }
    
    // MARK: - CGMManagerProtocol Implementation
    
    public func startScanning() async throws {
        emitDiagnostic("startScanning() called - connectionState=\(connectionState.rawValue), mode=\(config.connectionMode)")
        
        // PROD-HARDEN-032: Validate simulation settings before starting
        try validateBLECentral(central, allowSimulation: config.allowSimulation, component: "DexcomG7Manager")
        
        // G6/G7-COEX-FIX-016: Allow re-entry when already scanning/streaming/passive
        // These states mean we're already active - just continue
        switch connectionState {
        case .idle, .error:
            // OK to start fresh
            break
        case .scanning, .connecting, .streaming, .passive, .authenticating, .pairing:
            // Already active - just log and continue (callbacks may have been updated)
            emitDiagnostic("Already active (state=\(connectionState.rawValue)) - continuing with existing scan")
            return
        case .disconnecting:
            // Wait for disconnect to complete before starting fresh
            emitDiagnostic("Disconnecting in progress - cannot start scan")
            throw CGMError.connectionFailed
        }
        
        // Route to appropriate mode
        emitDiagnostic("Routing to mode: \(config.connectionMode)")
        switch config.connectionMode {
        case .direct:
            try await startActiveScanning()
        case .coexistence:
            try await startCoexistenceScanning()
        case .passiveBLE:
            try await startPassiveScanning()
        case .healthKitObserver:
            // HealthKit-only mode doesn't scan BLE
            setConnectionState(.passive)
            setSensorState(.active)
        case .cloudFollower, .nightscoutFollower:
            // Cloud modes don't use direct BLE
            setConnectionState(.passive)
            setSensorState(.active)
        }
    }
    
    // MARK: - Active Mode (Direct BLE Connection)
    
    private func startActiveScanning() async throws {
        let state = await central.state
        guard state == .poweredOn else {
            throw CGMError.bluetoothUnavailable
        }
        
        setConnectionState(.scanning)
        
        // Start scanning for G7 devices (uses different advertisement UUID)
        let scanStream = central.scan(for: [.dexcomG7Advertisement])
        
        scanTask = Task {
            do {
                for try await result in scanStream {
                    // Check if this is our sensor
                    if isMatchingSensor(result) {
                        await central.stopScan()
                        try await connectToPeripheral(result.peripheral)
                        break
                    }
                }
            } catch {
                setConnectionState(.error)
                onError?(.connectionFailed)
            }
        }
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        // For G7, we scan and auto-connect based on sensor serial
        try await startScanning()
    }
    
    // MARK: - Coexistence Mode (Connect + Subscribe, No Auth)
    // Trace: G7-COEX-001, G7-COEX-002, G7-COEX-003
    // Reference: externals/G7SensorKit/G7SensorKit/G7CGMManager/G7Sensor.swift:315-333
    
    /// Start coexistence mode - connect and observe authenticated session
    /// This mode connects to the sensor but doesn't perform J-PAKE authentication.
    /// Instead, it subscribes to the auth characteristic and waits for the vendor app
    /// (Dexcom) to authenticate. Once authenticated, it subscribes to control for glucose.
    private func startCoexistenceScanning() async throws {
        let state = await central.state
        emitDiagnostic("startCoexistenceScanning - BLE state: \(state)")
        guard state == .poweredOn else {
            emitDiagnostic("ERROR: BLE not powered on")
            throw CGMError.bluetoothUnavailable
        }
        
        // G7-COEX-FIX-007: Try to find already-connected peripherals FIRST
        // When the Dexcom G7 app is connected, the sensor doesn't advertise.
        // This matches Loop's G7SensorKit pattern: retrieveConnectedPeripherals before scanning.
        // Reference: externals/G7SensorKit/G7SensorKit/G7CGMManager/G7BluetoothManager.swift:206-212
        emitDiagnostic("Calling retrieveConnectedPeripherals...")
        let connectedPeripherals = await central.retrieveConnectedPeripherals(
            withServices: [.dexcomService, .dexcomG7Advertisement]
        )
        emitDiagnostic("retrieveConnectedPeripherals: \(connectedPeripherals.count) found")
        for (i, p) in connectedPeripherals.enumerated() {
            emitDiagnostic("  [\(i)] \(p.name ?? "nil") - \(p.identifier.description.prefix(8))")
        }
        
        if !connectedPeripherals.isEmpty {
            CGMLogger.general.info("DexcomG7Manager: Found \(connectedPeripherals.count) system-connected G7 peripheral(s)")
            
            for peripheral in connectedPeripherals {
                // In coexistence mode, connect to any G7 sensor found
                let shouldConnect: Bool
                if sensorSerial == "COEXISTENCE" || sensorSerial.isEmpty {
                    shouldConnect = true
                    emitDiagnostic("Joining system-connected: \(peripheral.name ?? "?")")
                    CGMLogger.general.info("DexcomG7Manager: Coexistence joining system-connected peripheral \(peripheral.name ?? peripheral.identifier.description.prefix(8).description)")
                } else {
                    // Match by sensor serial if provided (G7 name format: "DEXCOM XX" or serial-based)
                    if let name = peripheral.name {
                        shouldConnect = name.contains(sensorSerial.suffix(2))
                    } else {
                        shouldConnect = false
                    }
                }
                
                if shouldConnect {
                    setConnectionState(.connecting)
                    do {
                        try await connectForCoexistence(peripheral)
                        return  // Successfully joined existing connection
                    } catch {
                        emitDiagnostic("System-connected join failed: \(error.localizedDescription)")
                        CGMLogger.transmitter.debug("DexcomG7Manager: System-connected join failed: \(error.localizedDescription), trying next")
                        // Try next peripheral
                    }
                }
            }
        }
        
        // Fall back to scanning if no connected peripherals found or join failed
        setConnectionState(.scanning)
        emitDiagnostic("No connected peripherals - starting scan")
        CGMLogger.general.info("DexcomG7Manager: Starting coexistence mode scan (no connected peripherals found)")
        
        // G7-COEX-TIMING-001: CRITICAL - Prepare the stream BEFORE registering.
        // The Dexcom transmitter only has a ~5 second operating window.
        // We must have the AsyncStream continuation ready BEFORE iOS sends events.
        emitDiagnostic("Preparing connection events stream...")
        let connectionEventsStream = central.prepareConnectionEventsStream()
        
        // G7-PASSIVE-005: Register for connection events BEFORE scanning
        // This ensures we get notified if Dexcom app connects to G7 after we start scanning
        // Reference: Loop's G7BluetoothManager.managerQueue_scanForPeripheral()
        emitDiagnostic("Registering for connection events...")
        await central.registerForConnectionEvents(matchingServices: [
            .dexcomG7Advertisement,
            .dexcomService
        ])
        emitDiagnostic("Registered for connection events")
        CGMLogger.general.info("DexcomG7Manager: Registered for G7 connection events")
        
        // G7-PASSIVE-006: Start monitoring connection events in background
        // Now the stream is already prepared with its continuation set
        emitDiagnostic("Starting connection events monitoring...")
        startConnectionEventsMonitoring(stream: connectionEventsStream)
        
        // Start scanning for G7 devices
        emitDiagnostic("Starting BLE scan for 0xFEBC...")
        let scanStream = central.scan(for: [.dexcomG7Advertisement])
        emitDiagnostic("Scan stream created, iterating...")
        
        scanTask = Task { [weak self] in
            guard let self = self else { return }
            var deviceCount = 0
            do {
                for try await result in scanStream {
                    deviceCount += 1
                    await self.emitDiagnostic("Scan found device #\(deviceCount): \(result.peripheral.name ?? result.peripheral.identifier.description.prefix(8).description)")
                    
                    // G7-COEX-005: In coexistence mode without a known serial,
                    // connect to any G7 sensor found (user has one active)
                    let shouldConnect: Bool
                    if self.sensorSerial == "COEXISTENCE" || self.sensorSerial.isEmpty {
                        // Connect to first G7 found
                        shouldConnect = true
                        await self.emitDiagnostic("Connecting to first G7 found")
                        CGMLogger.general.info("DexcomG7Manager: Coexistence connecting to first G7 found")
                    } else {
                        // Match by sensor serial if provided
                        shouldConnect = await self.isMatchingSensor(result)
                    }
                    
                    if shouldConnect {
                        await self.central.stopScan()
                        try await self.connectForCoexistence(result.peripheral)
                        break
                    }
                }
                await self.emitDiagnostic("Scan iteration ended (found \(deviceCount) devices)")
            } catch {
                await self.emitDiagnostic("Scan error: \(error.localizedDescription)")
                await self.setConnectionState(.error)
                await self.onError?(.connectionFailed)
            }
        }
    }
    
    // MARK: - Connection Events Monitoring (G7-PASSIVE-005, G7-PASSIVE-006)
    // Reference: Loop's G7BluetoothManager.centralManager(_:connectionEventDidOccur:for:)
    
    /// G7-PASSIVE-006: Start monitoring connection events for coexistence
    /// Detects when Dexcom app connects to G7 sensor after we start scanning
    /// G7-COEX-TIMING-001: Start monitoring with a pre-prepared stream
    /// The stream must be prepared BEFORE registering for events to avoid race conditions.
    private func startConnectionEventsMonitoring(stream: AsyncStream<BLEConnectionEvent>) {
        // Cancel any existing monitoring task
        connectionEventsTask?.cancel()
        
        connectionEventsTask = Task { [weak self] in
            guard let self = self else { return }
            
            await self.emitDiagnostic("Connection events monitoring started")
            
            // Use the pre-prepared stream (continuation already set)
            for await event in stream {
                // G7-COEX-FIX-008: Handle BOTH peerConnected and peerDisconnected events
                // Like Loop's G7SensorKit, we use ANY connection event to discover the peripheral.
                // - peerConnected: Dexcom app connected - we can join the connection
                // - peerDisconnected: Dexcom app disconnected - sensor now available for us
                // Reference: G7BluetoothManager.centralManager(_:connectionEventDidOccur:for:)
                
                let eventTypeStr = event.eventType == .peerConnected ? "peerConnected" : "peerDisconnected"
                await self.emitDiagnostic("CONNECTION EVENT: \(eventTypeStr) - \(event.peripheral.name ?? "?")")
                CGMLogger.general.info("DexcomG7Manager: Connection event - \(eventTypeStr) for \(event.peripheral.name ?? event.peripheral.identifier.description.prefix(8).description)")
                
                // Check if we're still scanning (not already connected)
                let currentState = await self.connectionState
                guard currentState == .scanning else {
                    await self.emitDiagnostic("Ignoring event - state is \(currentState.rawValue)")
                    CGMLogger.general.debug("DexcomG7Manager: Ignoring connection event - already in state \(currentState.rawValue)")
                    continue
                }
                
                // Handle the connection event on the actor
                await self.emitDiagnostic("Handling connection event...")
                await self.handleConnectionEvent(event)
            }
            
            await self.emitDiagnostic("Connection events stream ended")
        }
    }
    
    /// Handle a connection event by stopping scan and joining the connection
    private func handleConnectionEvent(_ event: BLEConnectionEvent) async {
        // Stop the regular scan
        await central.stopScan()
        scanTask?.cancel()
        
        do {
            emitDiagnostic("Joining via connection event...")
            try await connectForCoexistence(event.peripheral)
            emitDiagnostic("Successfully joined via connection event")
            CGMLogger.general.info("DexcomG7Manager: Successfully joined via connection event")
            // Stop monitoring since we're now connected
            stopConnectionEventsMonitoring()
        } catch {
            emitDiagnostic("Connection event join failed: \(error.localizedDescription)")
            CGMLogger.general.error("DexcomG7Manager: Failed to join via connection event: \(error.localizedDescription)")
            // Resume scanning on failure
            setConnectionState(.scanning)
        }
    }
    
    /// Stop connection events monitoring
    private func stopConnectionEventsMonitoring() {
        connectionEventsTask?.cancel()
        connectionEventsTask = nil
    }
    
    /// Connect and set up coexistence observation
    private func connectForCoexistence(_ info: BLEPeripheralInfo) async throws {
        setConnectionState(.connecting)
        CGMLogger.transmitter.info("DexcomG7Manager: Coexistence connect to \(self.sensorSerial)")
        
        do {
            peripheral = try await central.connect(to: info)
            try await discoverServices()
            try await startCoexistenceObservation()
        } catch {
            CGMLogger.general.error("DexcomG7Manager: Coexistence connection failed - \(error.localizedDescription)")
            setConnectionState(.error)
            throw CGMError.connectionFailed
        }
    }
    
    /// Start observing authenticated session (G7-COEX-002)
    /// G7-COEX-FIX-014: Match Loop's exact protocol - auth first, then control on auth callback
    /// This ensures we don't violate G7 protocol by subscribing to control before auth.
    private func startCoexistenceObservation() async throws {
        guard let peripheral = peripheral,
              let authChar = authCharacteristic,
              let controlChar = controlCharacteristic else {
            throw CGMError.connectionFailed
        }
        
        setConnectionState(.passive)
        emitDiagnostic("G7-COEX-FIX-014: Auth first, then control on auth callback (Loop-exact)")
        CGMLogger.transmitter.info("DexcomG7Manager: Coexistence - sequential auth→control (Loop pattern)")
        
        // Step 1: Prepare auth stream and enable notifications
        let authStream = await peripheral.prepareNotificationStream(for: authChar)
        emitDiagnostic("Enabling auth notifications...")
        try await peripheral.enableNotifications(for: authChar)
        emitDiagnostic("Auth notifications enabled, waiting for auth status...")
        
        // Step 2: Prepare control stream NOW (before auth arrives) so we can enable it instantly
        // This is the key optimization - the stream is ready, we just need to enable notifications
        let controlStream = await peripheral.prepareNotificationStream(for: controlChar)
        emitDiagnostic("Control stream pre-prepared, ready for instant subscription")
        
        // Track if we've started control streaming
        var controlStarted = false
        
        // Auth monitoring and control triggering
        streamTask = Task { [weak self] in
            guard let self = self else { return }
            var authMsgCount = 0
            
            do {
                for try await data in authStream {
                    authMsgCount += 1
                    let hexStr = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                    await self.emitDiagnostic("Auth data #\(authMsgCount): \(data.count)B [\(hexStr)]")
                    
                    // Check for AuthChallengeRx message (opcode 0x05)
                    if data.count >= 3 && data[0] == 0x05 {
                        let isAuthenticated = data[1] != 0
                        let isBonded = data[2] != 0
                        
                        await self.emitDiagnostic("Auth status: bonded=\(isBonded) auth=\(isAuthenticated)")
                        CGMLogger.transmitter.info("DexcomG7Manager: Auth status - bonded=\(isBonded) auth=\(isAuthenticated)")
                        
                        // G7-COEX-FIX-014: IMMEDIATELY enable control notifications on auth success
                        // This matches Loop's didReceiveAuthenticationResponse callback behavior
                        if isBonded && isAuthenticated && !controlStarted {
                            controlStarted = true
                            await self.emitDiagnostic("Auth OK! Immediately enabling control notifications...")
                            
                            do {
                                try await peripheral.enableNotifications(for: controlChar)
                                await self.emitDiagnostic("Control notifications enabled!")
                                await self.setConnectionState(.streaming)
                                await self.setSensorState(.active)
                                
                                // Start control stream processing in parallel
                                await self.startControlStreamProcessing(controlStream)
                            } catch {
                                await self.emitDiagnostic("Failed to enable control: \(error.localizedDescription)")
                                await self.emitError(.connectionFailed)
                            }
                        }
                    } else {
                        await self.emitDiagnostic("Non-auth opcode: \(data.first.map { String(format: "0x%02X", $0) } ?? "nil")")
                    }
                }
                await self.emitDiagnostic("Auth stream ended after \(authMsgCount) messages")
            } catch {
                if !Task.isCancelled {
                    await self.emitDiagnostic("Auth stream error: \(error.localizedDescription)")
                    await self.setConnectionState(.error)
                    await self.emitError(.connectionFailed)
                }
            }
        }
    }
    
    /// Process control stream for glucose data (separated for clarity)
    private func startControlStreamProcessing(_ controlStream: AsyncThrowingStream<Data, Error>) async {
        Task { [weak self] in
            guard let self = self else { return }
            var dataCount = 0
            var gotGlucose = false  // Track if we received valid glucose
            
            do {
                for try await data in controlStream {
                    dataCount += 1
                    let hexStr = data.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " ")
                    await self.emitDiagnostic("Control data #\(dataCount): \(data.count)B [\(hexStr)...]")
                    
                    // G7-COEX-006: Parse glucose messages
                    if let glucoseRx = G7GlucoseRxMessage(data: data) {
                        gotGlucose = true
                        await self.emitDiagnostic("✅ Glucose: \(glucoseRx.glucose) mg/dL (trend: \(glucoseRx.trend))")
                        await self.handleGlucoseReading(glucoseRx)
                    } else if let egvRx = G7EGVRxMessage(data: data) {
                        gotGlucose = true
                        await self.emitDiagnostic("✅ EGV: \(egvRx.glucose) mg/dL")
                        await self.handleEGVReading(egvRx)
                    } else {
                        // G7 sends additional info messages (0x32, 0xEA, etc.) that we don't need
                        // Loop also ignores these (default: break)
                        let opcode = data.first.map { String(format: "0x%02X", $0) } ?? "nil"
                        await self.emitDiagnostic("ℹ️ Other G7 message (opcode: \(opcode)) - ignored")
                    }
                }
                await self.emitDiagnostic("Control stream ended after \(dataCount) messages")
            } catch {
                // G7-COEX-FIX-015: In coexistence mode, disconnection after receiving data is NORMAL
                // The G7 intentionally disconnects after sending glucose. Don't treat this as error.
                if !Task.isCancelled {
                    if gotGlucose {
                        // We got glucose data before disconnect - this is successful coexistence
                        await self.emitDiagnostic("✅ Session complete (\(dataCount) messages, disconnect normal)")
                        // Stay in passive state, ready for next connection
                        await self.setConnectionState(.passive)
                    } else {
                        // No glucose received before error - this is a real error
                        await self.emitDiagnostic("❌ Control stream error (no glucose): \(error.localizedDescription)")
                        await self.setConnectionState(.error)
                        await self.emitError(.dataUnavailable)
                    }
                }
            }
        }
    }
    
    
    // MARK: - Passive Mode (Observe Without Connecting)
    
    private func startPassiveScanning() async throws {
        let state = await central.state
        guard state == .poweredOn else {
            throw CGMError.bluetoothUnavailable
        }
        
        setConnectionState(.passive)
        setSensorState(.active)
        
        // Create passive scanner if needed
        if passiveScanner == nil {
            passiveScanner = PassiveBLEScanner(central: central)
        }
        
        guard let scanner = passiveScanner else { return }
        
        // Set up callbacks
        await scanner.setCallbacks(
            onDiscovered: { [weak self] result in
                guard let self = self else { return }
                Task {
                    await self.handlePassiveScanResult(result)
                }
            },
            onVendorConnection: { [weak self] transmitterId, connected in
                guard let self = self else { return }
                Task {
                    await self.handleVendorConnectionChange(transmitterId, connected: connected)
                }
            }
        )
        
        // Start scanning
        try await scanner.startScanning()
    }
    
    /// Handle passive scan result
    private func handlePassiveScanResult(_ result: PassiveScanResult) {
        // Check if this is our sensor (G7 uses sensor serial in name)
        guard result.transmitterId == sensorSerial else { return }
        
        // Update vendor connection status
        if vendorAppConnected != result.vendorConnected {
            vendorAppConnected = result.vendorConnected
            onVendorConnectionDetected?(result.vendorConnected)
        }
        
        // G7 doesn't broadcast glucose in advertisements
        // In passive mode, glucose comes from HealthKit via the vendor app
    }
    
    /// Handle vendor connection status change
    private func handleVendorConnectionChange(_ transmitterId: String, connected: Bool) {
        guard transmitterId == self.sensorSerial else { return }
        vendorAppConnected = connected
        onVendorConnectionDetected?(connected)
    }
    
    /// Set vendor connection callback
    public func setVendorCallback(_ callback: @escaping @Sendable (Bool) -> Void) {
        self.onVendorConnectionDetected = callback
    }
    
    /// Update sensor code for retry after code mismatch.
    /// Resets authenticator with new code.
    /// Trace: BLE-QUIRK-001
    public func updateSensorCode(_ newCode: String) throws {
        guard newCode.count == 4, newCode.allSatisfy({ $0.isNumber }) else {
            throw G7Authenticator.AuthError.invalidSensorCode
        }
        sensorCode = newCode
        authenticator = try G7Authenticator(sensorCode: newCode)
        CGMLogger.transmitter.info("DexcomG7Manager: Sensor code updated for retry")
    }
    
    public func disconnect() async {
        CGMLogger.general.info("DexcomG7Manager: Disconnecting")
        scanTask?.cancel()
        streamTask?.cancel()
        
        // G7-PASSIVE-006: Stop connection events monitoring
        stopConnectionEventsMonitoring()
        
        // Stop passive scanner if active
        if let scanner = passiveScanner {
            await scanner.stopScanning()
        }
        
        if let peripheral = peripheral {
            setConnectionState(.disconnecting)
            
            // Send disconnect message
            if let controlChar = controlCharacteristic {
                let disconnectMsg = G7DisconnectTxMessage()
                try? await peripheral.writeValue(disconnectMsg.data, for: controlChar, type: .withResponse)
            }
            
            await central.disconnect(peripheral)
        }
        
        peripheral = nil
        authCharacteristic = nil
        controlCharacteristic = nil
        backfillCharacteristic = nil
        passiveScanner = nil
        
        setConnectionState(.idle)
        setSensorState(.stopped)
    }
    
    // MARK: - Connection Flow
    
    private func isMatchingSensor(_ result: BLEScanResult) -> Bool {
        // Check advertisement name contains sensor serial
        if let name = result.advertisement.localName {
            return name.contains(sensorSerial)
        }
        // Also check peripheral name
        if let name = result.peripheral.name {
            return name.contains(sensorSerial)
        }
        return false
    }
    
    /// Connect to G7 peripheral with overall timeout
    /// PROD-HARDEN-022: Wrap entire connection flow with timeout
    private func connectToPeripheral(_ info: BLEPeripheralInfo) async throws {
        setConnectionState(.connecting)
        CGMLogger.transmitter.info("DexcomG7Manager: Connecting to \(self.sensorSerial)")
        
        do {
            // PROD-HARDEN-022: Connect with timeout (actor-isolated, so connect separately)
            let connectedPeripheral = try await withTimeout(
                seconds: G7Constants.connectionTimeout,
                operation: "G7 BLE connect"
            ) {
                try await self.central.connect(to: info)
            }
            peripheral = connectedPeripheral
            
            // Discovery, auth, and streaming have their own timeouts
            try await discoverServices()
            try await authenticateJPAKE()
            try await startStreaming()
        } catch is BLETimeoutError {
            CGMLogger.transmitter.error("DexcomG7Manager: Connection timeout")
            setConnectionState(.error)
            throw CGMError.connectionFailed
        } catch {
            CGMLogger.general.error("DexcomG7Manager: Connection failed - \(error.localizedDescription)")
            setConnectionState(.error)
            throw error  // Re-throw specific errors (auth timeout, discovery timeout, etc.)
        }
    }
    
    /// Discover G7 services and characteristics
    /// PROD-HARDEN-022: Wrapped with timeout
    private func discoverServices() async throws {
        guard let peripheral = peripheral else {
            throw CGMError.connectionFailed
        }
        
        // PROD-HARDEN-022: Wrap discovery with timeout
        do {
            try await withTimeout(
                seconds: G7Constants.discoveryTimeout,
                operation: "G7 service discovery"
            ) { [self] in
                try await performServiceDiscovery(peripheral: peripheral)
            }
        } catch is BLETimeoutError {
            CGMLogger.transmitter.error("DexcomG7Manager: Service discovery timeout after \(G7Constants.discoveryTimeout)s")
            throw CGMError.discoveryTimeout
        }
    }
    
    /// Internal service discovery implementation
    private func performServiceDiscovery(peripheral: any BLEPeripheralProtocol) async throws {
        // Discover the G7 CGM service
        guard let serviceUUID = BLEUUID(string: G7Constants.cgmServiceUUID) else {
            throw CGMError.sensorNotFound
        }
        let services = try await peripheral.discoverServices([serviceUUID])
        
        guard let cgmService = services.first(where: { $0.uuid == serviceUUID }) else {
            throw CGMError.sensorNotFound
        }
        
        // Discover characteristics
        guard let authUUID = BLEUUID(string: G7Constants.authenticationUUID),
              let controlUUID = BLEUUID(string: G7Constants.controlUUID),
              let backfillUUID = BLEUUID(string: G7Constants.backfillUUID) else {
            throw CGMError.sensorNotFound
        }
        
        let characteristics = try await peripheral.discoverCharacteristics(
            [authUUID, controlUUID, backfillUUID],
            for: cgmService
        )
        
        for char in characteristics {
            if char.uuid == authUUID {
                authCharacteristic = char
            } else if char.uuid == controlUUID {
                controlCharacteristic = char
            } else if char.uuid == backfillUUID {
                backfillCharacteristic = char
            }
        }
        
        guard authCharacteristic != nil, controlCharacteristic != nil else {
            throw CGMError.sensorNotFound
        }
    }
    
    // MARK: - J-PAKE Authentication
    
    /// Perform J-PAKE authentication with timeout
    /// PROD-HARDEN-022: Wrap auth flow with timeout to prevent hanging
    private func authenticateJPAKE() async throws {
        guard let peripheral = peripheral,
              let authChar = authCharacteristic,
              let authenticator = authenticator else {
            throw CGMError.connectionFailed
        }
        
        setConnectionState(.pairing)
        CGMLogger.transmitter.info("DexcomG7Manager: Starting J-PAKE auth with \(self.sensorSerial)")
        
        // PROD-HARDEN-022: Wrap auth flow with timeout
        do {
            try await withTimeout(
                seconds: G7Constants.authenticationTimeout,
                operation: "G7 J-PAKE authentication"
            ) { [self] in
                try await performJPAKEAuth(peripheral: peripheral, authChar: authChar, authenticator: authenticator)
            }
        } catch is BLETimeoutError {
            CGMLogger.transmitter.error("DexcomG7Manager: J-PAKE auth timeout after \(G7Constants.authenticationTimeout)s")
            await protocolLogger?.logAuthenticationFailed(error: "Authentication timeout", atRound: nil)
            setConnectionState(.error)
            throw CGMError.authenticationTimeout
        }
    }
    
    /// Internal J-PAKE authentication implementation
    /// Separated from authenticateJPAKE() to allow timeout wrapping
    private func performJPAKEAuth(
        peripheral: any BLEPeripheralProtocol,
        authChar: BLECharacteristic,
        authenticator: G7Authenticator
    ) async throws {
        // Initialize protocol logging session (G7-DIAG-004)
        let authStartTime = Date()
        if let logger = protocolLogger {
            _ = await logger.getOrCreateSessionContext()
            await logger.logEvent(.authenticationStarted, message: "J-PAKE auth with \(self.sensorSerial)")
        }
        
        // Subscribe to auth notifications (sync registration for fast BLE windows)
        let authStream = await peripheral.prepareNotificationStream(for: authChar)
        
        // Start J-PAKE Round 1
        await protocolLogger?.logRound1Start()
        let round1Msg = await authenticator.startAuthentication()
        await protocolLogger?.logRound1LocalGenerated(publicKeySize: round1Msg.gx1.count + round1Msg.gx2.count)
        try await peripheral.writeValue(round1Msg.data, for: authChar, type: .withResponse)
        await protocolLogger?.logTx("Round 1 message sent", data: round1Msg.data, event: .round1LocalGenerated)
        
        setConnectionState(.authenticating)
        
        var authenticated = false
        
        for try await data in authStream {
            do {
                // Process J-PAKE responses
                if let round1Response = G7JPAKERound1Response(data: data) {
                    // Log Round 1 received (G7-DIAG-004)
                    await protocolLogger?.logRound1RemoteReceived(dataSize: data.count)
                    await protocolLogger?.logZKProof(generated: false, verified: true, proofSize: round1Response.zkp3.data.count)
                    await protocolLogger?.logRound1Completed()
                    
                    // Process Round 1, send Round 2
                    await protocolLogger?.logRound2Start()
                    let round2Msg = try await authenticator.processRound1Response(round1Response)
                    try await peripheral.writeValue(round2Msg.data, for: authChar, type: .withResponse)
                    await protocolLogger?.logTx("Round 2 message sent", data: round2Msg.data, event: .round2LocalComputed)
                    
                } else if let round2Response = G7JPAKERound2Response(data: data) {
                    // Log Round 2 received (G7-DIAG-004)
                    await protocolLogger?.logRound2RemoteReceived(dataSize: data.count)
                    await protocolLogger?.logZKProof(generated: false, verified: true, proofSize: round2Response.zkpB.data.count)
                    await protocolLogger?.logRound2Completed()
                    
                    // Process Round 2, send confirmation
                    await protocolLogger?.logKeyConfirmationStart()
                    let confirmMsg = try await authenticator.processRound2Response(round2Response)
                    try await peripheral.writeValue(confirmMsg.data, for: authChar, type: .withResponse)
                    await protocolLogger?.logKeyConfirmationSent()
                    
                } else if let confirmResponse = G7JPAKEConfirmResponse(data: data) {
                    // Log confirmation received (G7-DIAG-004)
                    await protocolLogger?.logKeyConfirmationReceived(dataSize: data.count)
                    
                    // Verify confirmation
                    let success = try await authenticator.processConfirmation(confirmResponse)
                    if success {
                        authenticated = true
                        let totalDuration = Date().timeIntervalSince(authStartTime) * 1000.0
                        await protocolLogger?.logKeyConfirmationCompleted()
                        await protocolLogger?.logAuthenticationCompleted(totalDurationMs: totalDuration)
                        CGMLogger.transmitter.transmitterPaired(id: self.sensorSerial, model: "G7")
                        break
                    } else {
                        CGMLogger.transmitter.error("DexcomG7Manager: J-PAKE confirmation failed - wrong sensor code?")
                        await protocolLogger?.logKeyConfirmationFailed(error: "Confirmation hash mismatch")
                        // Trigger code mismatch callback for graceful re-prompt (BLE-QUIRK-001)
                        onCodeMismatch?()
                        throw CGMError.invalidSensorCode
                    }
                } else if let authStatus = G7AuthStatusMessage(data: data) {
                    // Direct auth status response
                    if authStatus.authenticated && authStatus.pairingComplete {
                        authenticated = true
                        let totalDuration = Date().timeIntervalSince(authStartTime) * 1000.0
                        await protocolLogger?.logAuthenticationCompleted(totalDurationMs: totalDuration)
                        CGMLogger.transmitter.transmitterPaired(id: self.sensorSerial, model: "G7")
                        break
                    }
                }
            } catch let error as G7Authenticator.AuthError {
                // J-PAKE errors often mean wrong code (BLE-QUIRK-001)
                CGMLogger.transmitter.error("DexcomG7Manager: J-PAKE error: \(error.localizedDescription)")
                await protocolLogger?.logAuthenticationFailed(error: error.localizedDescription, atRound: nil)
                onCodeMismatch?()
                throw CGMError.invalidSensorCode
            }
        }
        
        guard authenticated else {
            CGMLogger.transmitter.error("DexcomG7Manager: Authentication failed")
            await protocolLogger?.logAuthenticationFailed(error: "Authentication not completed", atRound: nil)
            // Trigger code mismatch callback for graceful re-prompt (BLE-QUIRK-001)
            onCodeMismatch?()
            throw CGMError.invalidSensorCode
        }
        
        // Send keep-alive
        let keepAlive = G7KeepAliveTxMessage()
        try await peripheral.writeValue(keepAlive.data, for: authChar, type: .withResponse)
    }
    
    // MARK: - Streaming
    
    private func startStreaming() async throws {
        guard let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            throw CGMError.connectionFailed
        }
        
        setConnectionState(.streaming)
        setSensorState(.active)
        
        // Request sensor info first
        try await requestSensorInfo()
        
        // Subscribe to control notifications for glucose readings (sync registration)
        let glucoseStream = await peripheral.prepareNotificationStream(for: controlChar)
        
        streamTask = Task {
            do {
                // Request initial glucose reading
                let glucoseTx = G7GlucoseTxMessage()
                try await peripheral.writeValue(glucoseTx.data, for: controlChar, type: .withResponse)
                
                for try await data in glucoseStream {
                    if let glucoseRx = G7GlucoseRxMessage(data: data) {
                        handleGlucoseReading(glucoseRx)
                    } else if let egvRx = G7EGVRxMessage(data: data) {
                        handleEGVReading(egvRx)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    setConnectionState(.error)
                    onError?(.dataUnavailable)
                }
            }
        }
    }
    
    private func requestSensorInfo() async throws {
        guard let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            return
        }
        
        let infoTx = G7SensorInfoTxMessage()
        try await peripheral.writeValue(infoTx.data, for: controlChar, type: .withResponse)
    }
    
    private func handleGlucoseReading(_ message: G7GlucoseRxMessage) {
        guard message.isValid else {
            // Update sensor state based on algorithm state
            let algState = message.parsedAlgorithmState
            
            // G7-COEX-FIX-002: Add diagnostic for rejected readings
            emitDiagnostic("⚠️ Glucose rejected: value=\(message.glucose), algState=\(algState) (0x\(String(format: "%02X", message.algorithmState))), isReliable=\(algState.isReliable)")
            
            // PROTO-G7-DIAG: Log invalid glucose with raw data
            Task {
                await protocolLogger?.logGlucoseInvalid(
                    algorithmState: Int(message.algorithmState),
                    rawData: message.rawData,
                    reason: algState == .warmup ? "Sensor warming up" : "Unreliable reading (state=\(algState))"
                )
            }
            
            if algState == .warmup {
                CGMLogger.sensor.sensorWarmup(remaining: 3600) // G7 warmup is ~60 min
                Task { await protocolLogger?.logSensorStateChanged(from: nil, to: "warmingUp", reason: "algorithmState=warmup") }
                setSensorState(.warmingUp)
            } else if !algState.isReliable {
                CGMLogger.sensor.warning("DexcomG7Manager: Unreliable reading")
                Task { await protocolLogger?.logSensorStateChanged(from: nil, to: "failed", reason: "algorithmState=unreliable") }
                setSensorState(.failed)
            }
            return
        }
        
        // PROTO-G7-DIAG: Log valid glucose reading with raw hex
        Task {
            await protocolLogger?.logGlucoseReceived(
                glucose: message.glucose,
                trend: Int(message.trend),
                algorithmState: Int(message.algorithmState),
                rawData: message.rawData
            )
        }
        
        let reading = GlucoseReading(
            glucose: Double(message.glucose),
            timestamp: Date(),
            trend: mapTrend(message.trend),
            source: "Dexcom G7"
        )
        
        CGMLogger.readings.glucoseReading(
            value: Double(message.glucose),
            trend: reading.trend.rawValue,
            timestamp: reading.timestamp
        )
        
        latestReading = reading
        emitDiagnostic("📤 Invoking onReadingReceived callback with \(Int(reading.glucose)) mg/dL")
        if let callback = onReadingReceived {
            callback(reading)
        } else {
            emitDiagnostic("⚠️ onReadingReceived callback is nil!")
        }
    }
    
    private func handleEGVReading(_ message: G7EGVRxMessage) {
        guard message.isValid else {
            // PROTO-G7-DIAG: Log invalid EGV
            Task {
                await protocolLogger?.logEGVInvalid(
                    rawData: message.rawData,
                    reason: "Invalid EGV message"
                )
            }
            CGMLogger.readings.warning("DexcomG7Manager: Invalid EGV message received")
            return
        }
        
        // PROTO-G7-DIAG: Log valid EGV reading with raw hex
        Task {
            await protocolLogger?.logEGVReceived(
                glucose: message.glucose,
                trend: Int(message.trend),
                timestamp: message.timestamp,
                rawData: message.rawData
            )
        }
        
        let reading = GlucoseReading(
            glucose: Double(message.glucose),
            timestamp: Date(),
            trend: mapTrend(message.trend),
            source: "Dexcom G7"
        )
        
        CGMLogger.readings.glucoseReading(
            value: Double(message.glucose),
            trend: reading.trend.rawValue,
            timestamp: reading.timestamp
        )
        
        latestReading = reading
        onReadingReceived?(reading)
    }
    
    private func mapTrend(_ rawTrend: Int8) -> GlucoseTrend {
        // CGM-TREND-003: Fix trend mapping per Dexcom protocol
        // Raw values from Dexcom: 1=rising fast → 4=flat → 7=falling fast
        switch rawTrend {
        case 1: return .doubleUp       // Rising very fast
        case 2: return .singleUp       // Rising fast
        case 3: return .fortyFiveUp    // Rising
        case 4: return .flat           // Flat
        case 5: return .fortyFiveDown  // Falling
        case 6: return .singleDown     // Falling fast
        case 7: return .doubleDown     // Falling very fast
        default: return .notComputable
        }
    }
    
    // MARK: - State Management
    
    private func setConnectionState(_ newState: G7ConnectionState) {
        let oldState = connectionState
        connectionState = newState
        CGMLogger.general.info("DexcomG7Manager: \(oldState.rawValue) → \(newState.rawValue)")
        onConnectionStateChanged?(newState)
    }
    
    private func setSensorState(_ newState: SensorState) {
        sensorState = newState
        onSensorStateChanged?(newState)
    }
    
    // MARK: - G7-Specific Methods
    
    /// Request historical glucose data
    /// - Parameters:
    ///   - startTime: Start of backfill range (transmitter time)
    ///   - endTime: End of backfill range (transmitter time)
    public func requestBackfill(startTime: UInt32, endTime: UInt32) async throws {
        guard let peripheral = peripheral,
              let backfillChar = backfillCharacteristic else {
            throw CGMError.dataUnavailable
        }
        
        let backfillTx = G7BackfillTxMessage(startTime: startTime, endTime: endTime)
        try await peripheral.writeValue(backfillTx.data, for: backfillChar, type: .withResponse)
    }
    
    /// Get session key after successful authentication
    public func getSessionKey() async -> Data? {
        return await authenticator?.sessionKey
    }
    
    /// Check if sensor is expired
    public var isSensorExpired: Bool {
        sensorInfo?.isExpired ?? false
    }
    
    /// Remaining sensor life in hours
    public var remainingSensorHours: Double? {
        sensorInfo?.remainingHours
    }
    
    /// Update session tracking from sensor time response
    /// Called when G7SensorTimeRxMessage is received
    /// Trace: G6-DIRECT-036, GAP-API-021 (future-dated entries fix)
    public func updateSessionTracking(from timeMessage: G7SensorTimeRxMessage) {
        // Compute sensor activation date (always valid)
        let now = Date()
        let currentTimeInterval = TimeInterval(timeMessage.currentTime)
        self.sensorActivationDate = now.addingTimeInterval(-currentTimeInterval)
        
        // Check for active session before computing session-related values
        // Trace: GAP-API-021 - Guard against 0xFFFFFFFF sentinel causing corrupt dates
        guard timeMessage.hasActiveSession else {
            // No active session - clear session data, don't compute corrupt dates
            self.lastSessionAge = nil
            self.sessionStartDate = nil
            CGMLogger.general.warning("DexcomG7Manager: No active session (sessionStartTime is sentinel 0xFFFFFFFF)")
            return
        }
        
        // Use safe session age to guard against underflow
        guard let safeAge = timeMessage.safeSessionAge else {
            // Session age unreasonable (possible underflow) - clear session data
            self.lastSessionAge = nil
            self.sessionStartDate = nil
            CGMLogger.general.warning("DexcomG7Manager: Unreasonable session age detected, clearing session data")
            return
        }
        
        // Store validated session age
        self.lastSessionAge = safeAge
        
        // Compute session start date from validated age
        let sessionAgeInterval = TimeInterval(safeAge)
        self.sessionStartDate = now.addingTimeInterval(-sessionAgeInterval)
        
        // Extract values for logging to avoid closure capture issues
        let warmup = isInWarmup
        let expired = isSessionExpired
        let remaining = sessionTimeRemaining ?? 0
        
        CGMLogger.general.debug("G7 session tracking: age=\(safeAge)s warmup=\(warmup) expired=\(expired) remaining=\(remaining)s")
    }
    
    // MARK: - Fault Injection (Testing)
    
    /// Set fault injector for testing error paths
    /// - Parameter injector: The fault injector to use, or nil to disable
    /// Trace: G7-FIX-016, SIM-FAULT-001
    public func setFaultInjector(_ injector: G7FaultInjector?) {
        self.faultInjector = injector
    }
    
    /// Get current fault injector
    public var currentFaultInjector: G7FaultInjector? {
        faultInjector
    }
    
    // MARK: - Protocol Logging (G7-DIAG-004)
    
    /// Set protocol logger for J-PAKE authentication tracing
    /// - Parameter logger: The protocol logger to use, or nil to disable
    /// Trace: G7-DIAG-004
    public func setProtocolLogger(_ logger: G7ProtocolLogger?) {
        self.protocolLogger = logger
    }
    
    /// Get current protocol logger
    public var currentProtocolLogger: G7ProtocolLogger? {
        protocolLogger
    }
    
    /// Get session context from protocol logger (for diagnostics)
    /// Trace: G7-DIAG-004
    public func getSessionContext() async -> G7SessionContext? {
        await protocolLogger?.getSessionContext()
    }
    
    /// Get current session state from protocol logger
    /// Trace: G7-DIAG-004
    public func getCurrentSessionState() async -> G7SessionState? {
        await protocolLogger?.currentSessionState()
    }
}
