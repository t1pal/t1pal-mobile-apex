// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DexcomG6Manager.swift
// CGMKit - DexcomG6
//
// Dexcom G6 CGM driver using BLEKit abstraction.
// Supports active, passive, and HealthKit-only modes for vendor coexistence.
// Trace: PRD-008 REQ-BLE-007, REQ-CGM-001, REQ-CGM-009a, CGM-030, LOG-ADOPT-001

import Foundation
import T1PalCore
import BLEKit

/// Dexcom G6 connection state
public enum G6ConnectionState: String, Sendable {
    case idle
    case scanning
    case connecting
    case authenticating
    case streaming
    case disconnecting
    case error
    /// Passive mode - observing only
    case passive
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension G6ConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .idle: return .disconnected
        case .scanning: return .scanning
        case .connecting, .authenticating, .disconnecting: return .connecting
        case .streaming, .passive: return .connected
        case .error: return .error
        }
    }
}

/// Dexcom G6 Manager Configuration
public struct DexcomG6ManagerConfig: Sendable {
    /// Connection mode - direct, passive BLE, or HealthKit-only
    public let connectionMode: CGMConnectionMode
    
    /// Transmitter ID
    public let transmitterId: TransmitterID
    
    /// Connection slot for authentication (CGM-048)
    public let slot: G6Slot
    
    /// App Level Key for enhanced authentication (CGM-066)
    /// When set, uses ALK-based auth (opcode 0x02) instead of TX ID-derived key.
    /// 16-byte cryptographic key stored from previous `ChangeAppLevelKeyTxMessage`.
    /// Trace: CGM-066b, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    public let appLevelKey: Data?
    
    /// Whether to generate and send a new App Level Key after authentication (CGM-066)
    /// When true, generates a random 16-byte key and sends `ChangeAppLevelKeyTxMessage`.
    /// The new key is emitted via `onAppLevelKeyChanged` callback for persistence.
    /// Trace: CGM-066a, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    public let generateNewAppLevelKey: Bool
    
    /// Whether to fall back to HealthKit when in passive mode and no glucose in ads
    public let passiveFallbackToHealthKit: Bool
    
    /// HealthKit CGM manager for passive mode fallback
    public let healthKitConfig: HealthKitCGMConfig?
    
    /// Whether to automatically reconnect after unexpected disconnect
    public let autoReconnect: Bool
    
    /// Delay before attempting reconnection (seconds)
    public let reconnectDelay: TimeInterval
    
    /// Maximum reconnection attempts before giving up (0 = unlimited)
    public let maxReconnectAttempts: Int
    
    /// Backoff multiplier for exponential backoff (e.g., 2.0 doubles delay each attempt)
    /// Set to 1.0 for fixed delay
    public let backoffMultiplier: Double
    
    /// Maximum delay between reconnection attempts (caps exponential growth)
    public let maxReconnectDelay: TimeInterval
    
    /// G6-COEX-025: Number of transmitter cycles to retry during initial pairing
    /// G6 transmits every 5 minutes; 3 cycles = 15-20 minutes of retry tolerance
    public let initialPairingCycles: Int
    
    /// G6-COEX-025: Transmitter broadcast interval (seconds)
    /// G6 transmits every 5 minutes
    public static let transmitterCycleInterval: TimeInterval = 300.0  // 5 minutes
    
    /// PROD-HARDEN-032: Whether to allow simulated/mock BLE centrals
    /// Default false for production safety. Set true explicitly for testing.
    public let allowSimulation: Bool
    
    public init(
        transmitterId: TransmitterID,
        connectionMode: CGMConnectionMode = .coexistence,
        slot: G6Slot = .auto,
        // CGM-066b: App Level Key for enhanced auth
        appLevelKey: Data? = nil,
        // CGM-066a: Whether to generate new ALK after auth
        generateNewAppLevelKey: Bool = false,
        // G6-COEX-012: Default to false - HealthKit requires entitlement we may not have
        passiveFallbackToHealthKit: Bool = false,
        healthKitConfig: HealthKitCGMConfig? = nil,
        autoReconnect: Bool = true,
        reconnectDelay: TimeInterval = 2.0,
        maxReconnectAttempts: Int = 0,
        backoffMultiplier: Double = 2.0,
        maxReconnectDelay: TimeInterval = 60.0,
        // G6-COEX-025: Default to 3 cycles (15-20 min) for initial pairing tolerance
        initialPairingCycles: Int = 3,
        // PROD-HARDEN-032: Explicit opt-in for simulation
        allowSimulation: Bool = false
    ) {
        // Validate ALK size if provided (CGM-066b)
        if let alk = appLevelKey {
            precondition(alk.count == 16, "App Level Key must be exactly 16 bytes")
        }
        self.transmitterId = transmitterId
        self.connectionMode = connectionMode
        self.slot = slot
        self.appLevelKey = appLevelKey
        self.generateNewAppLevelKey = generateNewAppLevelKey
        self.passiveFallbackToHealthKit = passiveFallbackToHealthKit
        self.healthKitConfig = healthKitConfig
        self.autoReconnect = autoReconnect
        self.reconnectDelay = reconnectDelay
        self.maxReconnectAttempts = maxReconnectAttempts
        self.backoffMultiplier = backoffMultiplier
        self.maxReconnectDelay = maxReconnectDelay
        self.initialPairingCycles = initialPairingCycles
        self.allowSimulation = allowSimulation
    }
}

/// Dexcom G6 CGM Manager
///
/// Full Dexcom G6 BLE driver using BLEKit abstraction.
/// Can be used with MockBLE for testing or real BLE implementations.
public actor DexcomG6Manager: CGMManagerProtocol {
    
    // MARK: - CGMManagerProtocol
    
    public let displayName = "Dexcom G6"
    public let cgmType = CGMType.dexcomG6
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    /// Actor-isolated setCallbacks implementation
    /// The protocol extension's setCallbacks doesn't work for actors because
    /// it's not actor-isolated. This override ensures callbacks are set
    /// within the actor's isolation context.
    /// Trace: G6-CALLBACK-FIX-001
    public func setCallbacks(
        onReading: (@Sendable (GlucoseReading) -> Void)?,
        onStateChange: (@Sendable (SensorState) -> Void)?
    ) {
        self.onReadingReceived = onReading
        self.onSensorStateChanged = onStateChange
        emitDiagnostic("📲 setCallbacks: onReading=\(onReading != nil ? "set" : "nil"), onStateChange=\(onStateChange != nil ? "set" : "nil")")
    }
    
    // MARK: - G6-Specific
    
    /// Current connection state
    public private(set) var connectionState: G6ConnectionState = .idle
    
    /// Connection state change callback
    public var onConnectionStateChanged: (@Sendable (G6ConnectionState) -> Void)?
    
    /// G6-COEX-DIAG-001: Diagnostic callback for coexistence debugging
    /// Emits detailed logs visible in playground UI
    public var onDiagnostic: (@Sendable (String) -> Void)?
    
    /// Set the diagnostic callback (for Swift 6 actor isolation compatibility)
    public func setOnDiagnostic(_ callback: (@Sendable (String) -> Void)?) {
        onDiagnostic = callback
    }
    
    /// Emit diagnostic message to callback and os.log
    private func emitDiagnostic(_ message: String) {
        CGMLogger.transmitter.debug("G6-DIAG: \(message)")
        onDiagnostic?(message)
    }
    
    /// The transmitter ID
    public let transmitterId: TransmitterID
    
    // MARK: - Private
    
    private let central: any BLECentralProtocol
    private var peripheral: (any BLEPeripheralProtocol)?
    private var authenticator: G6Authenticator
    private var authToken: Data?
    private var scanTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    
    // Discovered characteristics
    private var authCharacteristic: BLECharacteristic?
    private var controlCharacteristic: BLECharacteristic?
    private var backfillCharacteristic: BLECharacteristic?
    
    // G6-COEX-009: Track if discovery has succeeded before for this transmitter
    // When true, we can skip verbose logging on reconnection and expect fast discovery
    private var hasDiscoveredServicesBefore: Bool {
        get { UserDefaults.standard.bool(forKey: servicesDiscoveredKey) }
        set { UserDefaults.standard.set(newValue, forKey: servicesDiscoveredKey) }
    }
    
    /// UserDefaults key for services discovered flag
    private var servicesDiscoveredKey: String {
        "com.t1pal.cgmkit.g6.servicesDiscovered.\(transmitterId.id)"
    }
    
    // Cached peripheral UUID for fast reconnection (like Loop)
    // G6-COEX-008: Persist across app restarts
    private var cachedPeripheralUUID: BLEUUID? {
        didSet {
            // Only persist if value actually changed (avoid write on load)
            guard oldValue != cachedPeripheralUUID else { return }
            
            // Persist to UserDefaults when changed
            if let uuid = cachedPeripheralUUID {
                UserDefaults.standard.set(uuid.description, forKey: peripheralUUIDKey)
                CGMLogger.transmitter.debug("DexcomG6Manager: Persisted peripheral UUID \(uuid.description.prefix(8))...")
            } else {
                UserDefaults.standard.removeObject(forKey: peripheralUUIDKey)
                CGMLogger.transmitter.debug("DexcomG6Manager: Cleared cached peripheral UUID")
            }
        }
    }
    
    /// UserDefaults key for persisted peripheral UUID (includes transmitter ID for uniqueness)
    private var peripheralUUIDKey: String {
        "com.t1pal.cgmkit.g6.peripheralUUID.\(transmitterId.id)"
    }
    
    /// Load cached peripheral UUID from UserDefaults (G6-COEX-008)
    private func loadCachedPeripheralUUID() {
        guard cachedPeripheralUUID == nil else { return }  // Already loaded
        if let uuidString = UserDefaults.standard.string(forKey: peripheralUUIDKey),
           let uuid = UUID(uuidString: uuidString) {
            cachedPeripheralUUID = BLEUUID(uuid)
            CGMLogger.transmitter.info("DexcomG6Manager: Loaded cached peripheral UUID \(uuidString.prefix(8))...")
        }
    }
    
    // MARK: - Auto-Reconnection
    
    /// Current reconnection attempt count
    private var reconnectAttempts: Int = 0
    
    /// Task for auto-reconnection
    private var reconnectTask: Task<Void, Never>?
    
    /// Whether user explicitly disconnected (don't auto-reconnect)
    private var userDisconnected: Bool = false
    
    /// G6-COEX-025: When initial connection attempt started (for cycle tracking)
    private var initialConnectionStartTime: Date?
    
    /// G6-COEX-025: Whether we've ever successfully connected (affects retry strategy)
    private var hasEverConnected: Bool = false
    
    // MARK: - Passive Mode
    
    /// Configuration
    public let config: DexcomG6ManagerConfig
    
    /// Connection mode from config
    public var connectionMode: CGMConnectionMode { config.connectionMode }
    
    /// Passive scanner for coexistence mode
    private var passiveScanner: PassiveBLEScanner?
    
    /// Callback for vendor connection status
    public var onVendorConnectionDetected: (@Sendable (Bool) -> Void)?
    
    /// Whether vendor app is detected as connected
    public private(set) var vendorAppConnected: Bool = false
    
    // MARK: - HealthKit Fallback (G6-CONNECT-005)
    
    /// HealthKit CGM manager for fallback when BLE unavailable
    private var healthKitManager: HealthKitCGMManager?
    
    /// Whether we're currently in HealthKit fallback mode
    public private(set) var isHealthKitFallbackActive: Bool = false
    
    /// Callback for fallback mode changes
    public var onFallbackModeChanged: (@Sendable (Bool) -> Void)?
    
    // MARK: - App Level Key (CGM-066)
    
    /// Callback when a new App Level Key is generated and accepted by transmitter (CGM-066a)
    /// App should persist this key to Keychain for future sessions.
    /// Trace: CGM-066a, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    public var onAppLevelKeyChanged: (@Sendable (Data) -> Void)?
    
    // MARK: - Session Tracking (G6-DIRECT-034)
    
    /// G6 timing constants
    public static let warmupDuration: TimeInterval = 2 * 60 * 60  // 2 hours
    public static let sessionDuration: TimeInterval = 10 * 24 * 60 * 60  // 10 days
    public static let gracePeriod: TimeInterval = 12 * 60 * 60  // 12 hours
    
    /// Session start date computed from transmitter time
    /// Set when TransmitterTimeRxMessage is received
    public private(set) var sessionStartDate: Date?
    
    /// Transmitter activation date (when transmitter was first powered on)
    public private(set) var transmitterActivationDate: Date?
    
    /// Last session age in seconds (from TransmitterTimeRxMessage)
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
    /// Trace: G6-FIX-016, SIM-FAULT-001
    private var faultInjector: G6FaultInjector?
    
    // MARK: - Initialization
    
    /// Create a G6 manager with a BLE central
    /// - Parameters:
    ///   - transmitterId: The 6-character transmitter ID
    ///   - central: BLE central implementation (real or mock)
    ///   - faultInjector: Optional fault injector for testing (default: nil)
    ///   - allowSimulation: Allow simulated BLE central (default: false for production safety)
    public init(
        transmitterId: TransmitterID,
        central: any BLECentralProtocol,
        faultInjector: G6FaultInjector? = nil,
        allowSimulation: Bool = false
    ) {
        self.transmitterId = transmitterId
        self.central = central
        self.authenticator = G6Authenticator(transmitterId: transmitterId)
        self.config = DexcomG6ManagerConfig(transmitterId: transmitterId, allowSimulation: allowSimulation)
        self.faultInjector = faultInjector
        CGMLogger.general.info("DexcomG6Manager: initialized with transmitter \(transmitterId.id)")
    }
    
    /// Create a G6 manager with full configuration
    /// - Parameters:
    ///   - config: Full configuration including connection mode
    ///   - central: BLE central implementation (real or mock)
    ///   - faultInjector: Optional fault injector for testing (default: nil)
    public init(
        config: DexcomG6ManagerConfig,
        central: any BLECentralProtocol,
        faultInjector: G6FaultInjector? = nil
    ) {
        self.transmitterId = config.transmitterId
        self.central = central
        // CGM-066a: Use App Level Key if provided in config
        if let appLevelKey = config.appLevelKey {
            self.authenticator = G6Authenticator(transmitterId: config.transmitterId, appLevelKey: appLevelKey)
            CGMLogger.general.info("DexcomG6Manager: initialized with ALK authentication")
        } else {
            self.authenticator = G6Authenticator(transmitterId: config.transmitterId)
        }
        self.config = config
        self.faultInjector = faultInjector
        CGMLogger.general.info("DexcomG6Manager: initialized with transmitter \(config.transmitterId.id) mode=\(config.connectionMode.rawValue)")
    }
    
    // MARK: - CGMManagerProtocol Implementation
    
    public func startScanning() async throws {
        emitDiagnostic("startScanning() called - connectionState=\(connectionState.rawValue), mode=\(config.connectionMode)")
        
        // PROD-HARDEN-032: Validate simulation settings before starting
        try validateBLECentral(central, allowSimulation: config.allowSimulation, component: "DexcomG6Manager")
        
        // G6/G7-COEX-FIX-016: Allow re-entry when already scanning/streaming/passive
        // These states mean we're already active - just continue
        switch connectionState {
        case .idle, .error:
            // OK to start fresh
            break
        case .scanning, .connecting, .streaming, .passive, .authenticating:
            // Already active - just log and continue (callbacks may have been updated)
            emitDiagnostic("Already active (state=\(connectionState.rawValue)) - continuing with existing scan")
            return
        case .disconnecting:
            // Wait for disconnect to complete before starting fresh
            emitDiagnostic("Disconnecting in progress - cannot start scan")
            throw CGMError.connectionFailed
        }
        
        // G6-COEX-008: Load cached peripheral UUID for fast reconnection
        loadCachedPeripheralUUID()
        
        // Route to appropriate mode
        emitDiagnostic("Routing to mode: \(config.connectionMode)")
        switch config.connectionMode {
        case .direct:
            try await startActiveScanning()
        case .coexistence:
            // G6-COEX-001: Implement G6 coexistence mode (Loop pattern)
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
        
        // Start scanning for Dexcom devices
        let scanStream = central.scan(for: [.dexcomAdvertisement])
        
        scanTask = Task {
            do {
                for try await result in scanStream {
                    // Check if this is our transmitter
                    if isMatchingTransmitter(result) {
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
    
    // MARK: - Coexistence Mode (Connect + Subscribe, No Auth)
    // Trace: G6-COEX-001, G6-COEX-002, G6-COEX-003
    // Reference: G7 coexistence pattern, externals/CGMBLEKit/CGMBLEKit/Transmitter.swift
    
    /// Start coexistence mode - connect and observe authenticated session
    /// This mode connects to the transmitter but doesn't perform authentication.
    /// Instead, it subscribes to the auth characteristic and waits for the vendor app
    /// (Dexcom) to authenticate. Once authenticated, it subscribes to control for glucose.
    private func startCoexistenceScanning() async throws {
        let state = await central.state
        guard state == .poweredOn else {
            throw CGMError.bluetoothUnavailable
        }
        
        // Fast path: Try to reconnect using cached peripheral (like Loop does)
        // This avoids scanning delay and may have cached services
        if let cachedUUID = cachedPeripheralUUID,
           let cachedInfo = await central.retrievePeripheral(identifier: cachedUUID) {
            CGMLogger.transmitter.info("DexcomG6Manager: Re-connecting to cached peripheral")
            setConnectionState(.connecting)
            do {
                try await connectForCoexistence(cachedInfo)
                return  // Successfully reconnected using cache
            } catch {
                CGMLogger.transmitter.debug("DexcomG6Manager: Cached reconnect failed, scanning instead")
                // Fall through to scan
            }
        }
        
        // G6-COEX-013: Try to find already-connected peripherals (Dexcom app may have connected)
        // This is the key Loop pattern for fast coexistence
        let connectedPeripherals = await central.retrieveConnectedPeripherals(withServices: [.dexcomService, .dexcomAdvertisement])
        let txSuffix = transmitterId.id.suffix(2)
        for peripheral in connectedPeripherals {
            // Check if name matches our transmitter (DexcomXY where XY is last 2 chars)
            if let name = peripheral.name, name.suffix(2) == txSuffix {
                CGMLogger.transmitter.info("DexcomG6Manager: Found system-connected peripheral \(name)")
                setConnectionState(.connecting)
                do {
                    try await connectForCoexistence(peripheral)
                    return  // Successfully joined existing connection
                } catch {
                    CGMLogger.transmitter.debug("DexcomG6Manager: System-connected join failed, scanning instead")
                    // Fall through to scan
                }
            }
        }
        
        setConnectionState(.scanning)
        CGMLogger.general.info("DexcomG6Manager: Starting coexistence mode scan for \(self.transmitterId.id)")
        
        // Start scanning for G6 devices
        let scanStream = central.scan(for: [.dexcomAdvertisement])
        
        scanTask = Task {
            var devicesFound = 0
            do {
                for try await result in scanStream {
                    devicesFound += 1
                    // DATA-PIPE-002: Log scan progress
                    CGMLogger.general.debug("DexcomG6Manager: Scan found device \(devicesFound): \(result.peripheral.identifier.description.prefix(8))...")
                    
                    // Check if this is our transmitter
                    if isMatchingTransmitter(result) {
                        CGMLogger.general.info("DexcomG6Manager: Found matching transmitter \(self.transmitterId.id)")
                        await central.stopScan()
                        try await connectForCoexistence(result.peripheral)
                        break
                    }
                }
            } catch {
                CGMLogger.general.error("DexcomG6Manager: Scan error after \(devicesFound) devices - \(error.localizedDescription)")
                setConnectionState(.error)
                onError?(.connectionFailed)
            }
        }
    }
    
    /// Connect and set up coexistence observation
    private func connectForCoexistence(_ info: BLEPeripheralInfo) async throws {
        setConnectionState(.connecting)
        CGMLogger.transmitter.info("DexcomG6Manager: Coexistence connect to \(self.transmitterId.id)")
        
        do {
            peripheral = try await central.connect(to: info)
            // Cache the peripheral UUID for fast reconnection
            cachedPeripheralUUID = info.identifier
            try await discoverServices()
            try await startCoexistenceObservation()
        } catch {
            CGMLogger.general.error("DexcomG6Manager: Coexistence connection failed - \(error.localizedDescription)")
            setConnectionState(.error)
            throw CGMError.connectionFailed
        }
    }
    
    /// Start observing authenticated session (G6-COEX-002)
    /// Subscribe to auth characteristic and wait for authenticated && bonded
    private func startCoexistenceObservation() async throws {
        guard let peripheral = peripheral,
              let authChar = authCharacteristic else {
            throw CGMError.connectionFailed
        }
        
        emitDiagnostic("Starting coexistence observation...")
        
        // G6-COEX-023: Use prepareNotificationStream to register continuation SYNCHRONOUSLY
        // before enabling notifications. This fixes the race condition where:
        //   1. subscribe() queues a Task to register continuation
        //   2. enableNotifications() starts
        //   3. GATT indication arrives
        //   4. Task hasn't run yet → continuation not registered → data lost!
        // 
        // prepareNotificationStream registers the continuation inline, no Task queuing.
        let authStream = await peripheral.prepareNotificationStream(for: authChar)
        emitDiagnostic("Auth stream prepared, enabling notifications...")
        
        // Now enable notifications - continuation is already registered
        try await peripheral.enableNotifications(for: authChar)
        emitDiagnostic("Auth notifications enabled, waiting for vendor app to authenticate...")
        
        // Enter passive state while waiting for vendor app to authenticate
        setConnectionState(.passive)
        CGMLogger.transmitter.info("DexcomG6Manager: Coexistence waiting for vendor auth")
        
        streamTask = Task { [weak self] in
            guard let self = self else { return }
            var authMsgCount = 0
            
            do {
                for try await data in authStream {
                    authMsgCount += 1
                    // G6-COEX-022: Log raw auth notification for debugging
                    let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                    await self.emitDiagnostic("Auth data #\(authMsgCount): \(data.count)B [\(hexString)]")
                    CGMLogger.transmitter.debug("DexcomG6Manager: Auth notification received: \(hexString) (len=\(data.count))")
                    
                    // Check for AuthStatusRx message (opcode 0x05)
                    // Format: [0x05, authenticated, bonded]
                    if let statusRx = AuthStatusRxMessage(data: data) {
                        await self.emitDiagnostic("Auth status: bonded=\(statusRx.bonded) auth=\(statusRx.authenticated)")
                        CGMLogger.transmitter.info("DexcomG6Manager: Auth status - bonded=\(statusRx.bonded) auth=\(statusRx.authenticated)")
                        
                        // G6-COEX-002: Wait for both bonded and authenticated
                        if statusRx.bonded && statusRx.authenticated {
                            await self.emitDiagnostic("Auth OK! Enabling control notifications...")
                            CGMLogger.transmitter.info("DexcomG6Manager: Observed authenticated session, enabling control notifications")
                            // Now subscribe to control for glucose (G6-COEX-003)
                            try await self.startCoexistenceStreaming()
                            break
                        }
                    } else {
                        await self.emitDiagnostic("Non-auth opcode: \(data.first.map { String(format: "0x%02X", $0) } ?? "nil")")
                        CGMLogger.transmitter.warning("DexcomG6Manager: Auth notification not parsed as AuthStatusRx (opcode=\(data.first ?? 0))")
                    }
                }
                await self.emitDiagnostic("Auth stream ended after \(authMsgCount) messages")
            } catch {
                if !Task.isCancelled {
                    await self.emitDiagnostic("Auth stream error: \(error.localizedDescription)")
                    CGMLogger.general.error("DexcomG6Manager: Coexistence auth observation failed: \(error)")
                    // G6-CONNECT-005: Fall back to HealthKit when coexistence fails
                    if self.config.passiveFallbackToHealthKit {
                        await self.activateHealthKitFallback()
                    } else {
                        await self.setConnectionState(.error)
                        await self.onError?(.connectionFailed)
                    }
                }
            }
        }
    }
    
    /// Start streaming glucose after vendor authentication (G6-COEX-003)
    private func startCoexistenceStreaming() async throws {
        guard let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            throw CGMError.connectionFailed
        }
        
        emitDiagnostic("Enabling control notifications...")
        
        // Enable control notifications and await confirmation
        try await peripheral.enableNotifications(for: controlChar)
        
        setConnectionState(.streaming)
        setSensorState(.active)
        emitDiagnostic("Control notifications enabled, streaming started!")
        CGMLogger.transmitter.info("DexcomG6Manager: Coexistence streaming started")
        
        // Deactivate HealthKit fallback if it was active
        if isHealthKitFallbackActive {
            await deactivateHealthKitFallback()
        }
        
        // Subscribe to control notifications for glucose readings
        // In coexistence mode, glucose is PUSHED by the sensor - no request needed
        // Use prepareNotificationStream for synchronous registration (G6-COEX-023)
        let glucoseStream = await peripheral.prepareNotificationStream(for: controlChar)
        
        // Replace the auth stream task with glucose streaming
        streamTask?.cancel()
        var gotGlucose = false  // Track if we received valid glucose
        streamTask = Task { [weak self] in
            guard let self = self else { return }
            var dataCount = 0
            
            do {
                for try await data in glucoseStream {
                    dataCount += 1
                    // Debug logging for control notifications
                    let hexString = data.prefix(10).map { String(format: "%02X", $0) }.joined(separator: " ")
                    await self.emitDiagnostic("Control data #\(dataCount): \(data.count)B [\(hexString)...]")
                    CGMLogger.transmitter.debug("DexcomG6Manager: Control notification received: \(hexString) (len=\(data.count))")
                    
                    // G6-COEX-003: Same glucose handling as direct mode
                    if let glucoseRx = GlucoseRxMessage(data: data) {
                        gotGlucose = true
                        await self.emitDiagnostic("✅ Glucose: \(glucoseRx.glucose) mg/dL (trend: \(glucoseRx.trend))")
                        CGMLogger.transmitter.info("DexcomG6Manager: Glucose parsed: \(glucoseRx.glucose) mg/dL")
                        await self.handleGlucoseReading(glucoseRx)
                    } else {
                        let opcode = data.first.map { String(format: "0x%02X", $0) } ?? "nil"
                        await self.emitDiagnostic("ℹ️ Other G6 message (opcode: \(opcode)) - ignored")
                        CGMLogger.transmitter.warning("DexcomG6Manager: Control notification not parsed as GlucoseRx (opcode=\(data.first ?? 0))")
                    }
                }
                await self.emitDiagnostic("Control stream ended after \(dataCount) messages")
            } catch {
                if !Task.isCancelled {
                    // G6-COEX-FIX-015: In coexistence mode, disconnection after receiving data is NORMAL
                    // The G6 intentionally disconnects after sending glucose. Don't treat this as error.
                    if gotGlucose {
                        // We got glucose data before disconnect - this is successful coexistence
                        await self.emitDiagnostic("✅ Session complete (\(dataCount) messages, disconnect normal)")
                        CGMLogger.transmitter.info("DexcomG6Manager: Coexistence session complete (disconnect normal)")
                        // Stay in passive state, ready for next connection
                        await self.setConnectionState(.passive)
                        
                        // CGM-CONT-001: Schedule reconnection for next G6 broadcast cycle (~5 min)
                        // G6 broadcasts every 5 minutes. Schedule reconnect ~4.5 min from now
                        // to catch the next window with margin.
                        await self.scheduleNextCoexistenceConnection()
                    } else if self.config.passiveFallbackToHealthKit {
                        await self.emitDiagnostic("❌ No glucose received, falling back to HealthKit")
                        // No glucose received - fall back to HealthKit
                        await self.activateHealthKitFallback()
                    } else {
                        await self.emitDiagnostic("❌ Control stream error (no glucose): \(error.localizedDescription)")
                        await self.setConnectionState(.error)
                        await self.onError?(.dataUnavailable)
                    }
                }
            }
        }
    }
    
    // MARK: - Continuous Data Flow (CGM-CONT-001)
    
    /// Schedule next coexistence connection for continuous data flow
    /// G6 broadcasts every ~5 minutes. This schedules reconnection to catch the next window.
    private func scheduleNextCoexistenceConnection() async {
        // Cancel any existing scheduled reconnection
        reconnectTask?.cancel()
        
        // G6 broadcasts every 5 minutes (300 seconds)
        // Schedule reconnection ~4.5 minutes from now to have margin before next broadcast
        let nextConnectionDelay: TimeInterval = 270  // 4.5 minutes
        
        CGMLogger.general.info("DexcomG6Manager: Scheduling next coexistence connection in \(Int(nextConnectionDelay))s")
        emitDiagnostic("⏰ Next connection in \(Int(nextConnectionDelay/60))m \(Int(nextConnectionDelay.truncatingRemainder(dividingBy: 60)))s")
        
        // Capture current state for the task
        let shouldReconnect = !userDisconnected
        
        reconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(nextConnectionDelay * 1_000_000_000))
                
                guard !Task.isCancelled else { return }
                guard let self = self else { return }
                
                // Check state on actor
                let canReconnect = await self.canPerformScheduledReconnect()
                guard canReconnect && shouldReconnect else {
                    CGMLogger.general.info("DexcomG6Manager: Skipping scheduled reconnect (state changed)")
                    return
                }
                
                CGMLogger.general.info("DexcomG6Manager: Starting scheduled coexistence reconnection")
                await self.emitDiagnostic("🔄 Reconnecting for next reading...")
                
                try await self.startScanning()
            } catch {
                if !Task.isCancelled {
                    CGMLogger.general.error("DexcomG6Manager: Scheduled reconnection failed - \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Check if we can perform a scheduled reconnection
    private func canPerformScheduledReconnect() -> Bool {
        !userDisconnected && (connectionState == .passive || connectionState == .idle)
    }
    
    // MARK: - HealthKit Fallback (G6-CONNECT-005)
    
    /// Activate HealthKit fallback mode for graceful degradation
    /// Called when coexistence mode fails or BLE is unavailable
    private func activateHealthKitFallback() async {
        guard !isHealthKitFallbackActive else { return }
        
        CGMLogger.general.info("DexcomG6Manager: Activating HealthKit fallback (graceful degradation)")
        
        isHealthKitFallbackActive = true
        setConnectionState(.passive)
        setSensorState(.active)
        onFallbackModeChanged?(true)
        
        // Create HealthKit manager if not already created
        if healthKitManager == nil {
            let hkConfig = config.healthKitConfig ?? HealthKitCGMConfig.default
            healthKitManager = HealthKitCGMManager(config: hkConfig)
        }
        
        // Configure callback (must be done on actor)
        await healthKitManager?.setReadingCallback { [weak self] reading in
            Task { [weak self] in
                guard let self = self else { return }
                // Re-tag source to indicate fallback
                let fallbackReading = GlucoseReading(
                    glucose: reading.glucose,
                    timestamp: reading.timestamp,
                    trend: reading.trend,
                    source: "Dexcom G6 (HealthKit)"
                )
                await self.handleHealthKitReading(fallbackReading)
            }
        }
        
        // Start HealthKit observation
        do {
            try await healthKitManager?.startScanning()
            CGMLogger.general.info("DexcomG6Manager: HealthKit fallback active")
        } catch {
            CGMLogger.general.error("DexcomG6Manager: HealthKit fallback failed - \(error.localizedDescription)")
            onError?(.dataUnavailable)
        }
    }
    
    /// Handle glucose reading from HealthKit fallback
    private func handleHealthKitReading(_ reading: GlucoseReading) {
        latestReading = reading
        onReadingReceived?(reading)
    }
    
    /// Deactivate HealthKit fallback when BLE becomes available
    private func deactivateHealthKitFallback() async {
        guard isHealthKitFallbackActive else { return }
        
        CGMLogger.general.info("DexcomG6Manager: Deactivating HealthKit fallback (BLE restored)")
        
        await healthKitManager?.disconnect()
        isHealthKitFallbackActive = false
        onFallbackModeChanged?(false)
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
        // Check if this is our transmitter
        guard result.transmitterId == transmitterId.id else { return }
        
        // Update vendor connection status
        if vendorAppConnected != result.vendorConnected {
            vendorAppConnected = result.vendorConnected
            onVendorConnectionDetected?(result.vendorConnected)
        }
        
        // Try to extract glucose from advertisement data
        if let data = result.advertisementData,
           let glucose = parseGlucoseFromAdvertisement(data) {
            let reading = GlucoseReading(
                glucose: glucose.value,
                timestamp: Date(),
                trend: glucose.trend,
                source: "Dexcom G6 (Passive)"
            )
            latestReading = reading
            onReadingReceived?(reading)
        }
    }
    
    /// Handle vendor connection status change
    private func handleVendorConnectionChange(_ transmitterId: String, connected: Bool) {
        guard transmitterId == self.transmitterId.id else { return }
        vendorAppConnected = connected
        onVendorConnectionDetected?(connected)
    }
    
    /// Parse glucose from G6 advertisement data
    /// Note: G6 doesn't broadcast glucose in advertisements, so this typically returns nil
    /// Passive mode relies on HealthKit for glucose data
    private func parseGlucoseFromAdvertisement(_ data: Data) -> (value: Double, trend: GlucoseTrend)? {
        // G6 advertisements don't contain glucose data
        // This is a placeholder for potential future transmitter types that do
        // In passive mode, glucose comes from HealthKit via the vendor app
        return nil
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        // For G6, we scan and auto-connect based on transmitter ID
        userDisconnected = false
        reconnectAttempts = 0
        // G6-COEX-025: Reset cycle tracking for new connection attempt
        initialConnectionStartTime = nil
        try await startScanning()
    }
    
    public func disconnect() async {
        CGMLogger.general.info("DexcomG6Manager: User-initiated disconnect")
        userDisconnected = true
        reconnectTask?.cancel()
        reconnectTask = nil
        await performDisconnect()
    }
    
    /// Internal disconnect without setting userDisconnected flag
    private func performDisconnect() async {
        scanTask?.cancel()
        streamTask?.cancel()
        
        // Stop passive scanner if active
        if let scanner = passiveScanner {
            await scanner.stopScanning()
        }
        
        if let peripheral = peripheral {
            setConnectionState(.disconnecting)
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
    
    /// Handle unexpected disconnection and attempt auto-reconnect
    private func handleUnexpectedDisconnect() {
        // G6-COEX-020: Clear stale characteristic references before reconnect
        // The old BLECharacteristic objects are invalid for the new connection
        peripheral = nil
        authCharacteristic = nil
        controlCharacteristic = nil
        backfillCharacteristic = nil
        
        guard config.autoReconnect && !userDisconnected else {
            CGMLogger.general.info("DexcomG6Manager: Auto-reconnect disabled or user disconnected")
            return
        }
        
        // G6-COEX-025: Use cycle-aware retry for initial pairing
        // During initial pairing, give extra time for transmitter to become available
        let shouldUseInitialPairingStrategy = !hasEverConnected
        
        if shouldUseInitialPairingStrategy {
            // Initialize start time on first disconnect during pairing
            if initialConnectionStartTime == nil {
                initialConnectionStartTime = Date()
            }
            
            // Check if we've exceeded allowed cycles
            let elapsed = Date().timeIntervalSince(initialConnectionStartTime!)
            let maxRetryDuration = TimeInterval(config.initialPairingCycles) * DexcomG6ManagerConfig.transmitterCycleInterval
            let cyclesElapsed = Int(elapsed / DexcomG6ManagerConfig.transmitterCycleInterval)
            
            if elapsed >= maxRetryDuration {
                CGMLogger.general.warning("DexcomG6Manager: Initial pairing failed after \(cyclesElapsed) transmitter cycles (\(Int(elapsed/60)) min)")
                onError?(CGMError.connectionFailed)
                return
            }
            
            CGMLogger.general.info("DexcomG6Manager: Initial pairing retry - cycle \(cyclesElapsed + 1)/\(self.config.initialPairingCycles), \(Int((maxRetryDuration - elapsed)/60)) min remaining")
        } else {
            // Standard retry logic for established connections
            if config.maxReconnectAttempts > 0 && reconnectAttempts >= config.maxReconnectAttempts {
                CGMLogger.general.warning("DexcomG6Manager: Max reconnect attempts reached (\(self.config.maxReconnectAttempts))")
                onError?(CGMError.connectionFailed)
                return
            }
        }
        
        reconnectAttempts += 1
        
        // Calculate delay with exponential backoff
        let backoffDelay = calculateBackoffDelay()
        CGMLogger.general.info("DexcomG6Manager: Auto-reconnect attempt \(self.reconnectAttempts), delay: \(backoffDelay)s")
        
        reconnectTask?.cancel()
        reconnectTask = Task {
            // Wait before attempting reconnection (exponential backoff)
            try? await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
            
            guard !Task.isCancelled && !userDisconnected else { return }
            
            do {
                try await startScanning()
            } catch {
                CGMLogger.general.error("DexcomG6Manager: Reconnection failed - \(error.localizedDescription)")
            }
        }
    }
    
    /// Calculate reconnect delay with exponential backoff
    /// - Returns: Delay in seconds, capped at maxReconnectDelay
    /// G6-COEX-026: For initial pairing, align delays to transmitter 5-min cycle
    private func calculateBackoffDelay() -> TimeInterval {
        // delay = baseDelay * (multiplier ^ (attempt - 1)), capped at max
        let exponent = Double(reconnectAttempts - 1)
        let rawDelay = config.reconnectDelay * pow(config.backoffMultiplier, exponent)
        let cappedDelay = min(rawDelay, config.maxReconnectDelay)
        
        // G6-COEX-026: During initial pairing, align to transmitter cycle
        // This reduces battery drain by waiting for the next broadcast window
        if !hasEverConnected && reconnectAttempts > 3 {
            // After a few quick retries, snap to cycle boundary
            return alignToCycleBoundary(cappedDelay)
        }
        
        return cappedDelay
    }
    
    /// G6-COEX-026: Align delay to next transmitter broadcast window
    /// Transmitter broadcasts every 5 minutes; syncing reduces missed connections
    private func alignToCycleBoundary(_ suggestedDelay: TimeInterval) -> TimeInterval {
        let cycleInterval = DexcomG6ManagerConfig.transmitterCycleInterval
        
        // If suggested delay is already longer than a cycle, use it directly
        guard suggestedDelay < cycleInterval else {
            return suggestedDelay
        }
        
        // Otherwise, wait until the next cycle boundary
        // This gives the transmitter time to wake up and broadcast
        return cycleInterval
    }
    
    // MARK: - Connection Flow
    
    private func isMatchingTransmitter(_ result: BLEScanResult) -> Bool {
        // Dexcom transmitters advertise as "DexcomXY" where XY is last 2 chars of transmitter ID
        // Match by suffix like Loop does (CGMBLEKit/Transmitter.swift:232)
        let txSuffix = transmitterId.id.suffix(2)
        
        // Check advertisement name suffix
        if let name = result.advertisement.localName, name.suffix(2) == txSuffix {
            return true
        }
        // Also check peripheral name suffix
        if let name = result.peripheral.name, name.suffix(2) == txSuffix {
            return true
        }
        return false
    }
    
    private func connectToPeripheral(_ info: BLEPeripheralInfo) async throws {
        setConnectionState(.connecting)
        CGMLogger.transmitter.info("DexcomG6Manager: Connecting to \(self.transmitterId.id)")
        
        do {
            peripheral = try await central.connect(to: info)
            try await discoverServices()
            try await authenticate()
            try await startStreaming()
        } catch {
            CGMLogger.general.error("DexcomG6Manager: Connection failed - \(error.localizedDescription)")
            setConnectionState(.error)
            throw CGMError.connectionFailed
        }
    }
    
    private func discoverServices() async throws {
        guard let peripheral = peripheral else {
            throw CGMError.connectionFailed
        }
        
        // Skip discovery if we already have cached characteristics (like Loop does)
        if authCharacteristic != nil && controlCharacteristic != nil {
            CGMLogger.transmitter.debug("DexcomG6Manager: Using cached characteristics")
            return
        }
        
        // G6-COEX-016: Try to use CoreBluetooth's cached services/characteristics first
        // This enables single-cycle initialization instead of requiring two G6 windows
        if let cachedServices = peripheral.cachedServices,
           let cgmService = cachedServices.first(where: { $0.uuid == .dexcomService }),
           let cachedChars = peripheral.cachedCharacteristics(for: cgmService) {
            
            for char in cachedChars {
                switch char.uuid {
                case .dexcomAuthentication:
                    authCharacteristic = char
                case .dexcomControl:
                    controlCharacteristic = char
                case .dexcomBackfill:
                    backfillCharacteristic = char
                default:
                    break
                }
            }
            
            if authCharacteristic != nil && controlCharacteristic != nil {
                CGMLogger.transmitter.info("DexcomG6Manager: Using CoreBluetooth cached characteristics (fast path)")
                return
            }
        }
        
        // G6-COEX-009: Log discovery mode based on whether we've succeeded before
        if hasDiscoveredServicesBefore {
            CGMLogger.transmitter.debug("DexcomG6Manager: Rediscovering services (previously succeeded)")
        } else {
            CGMLogger.transmitter.info("DexcomG6Manager: First-time service discovery")
        }
        
        // Discover the Dexcom CGM service
        let services = try await peripheral.discoverServices([.dexcomService])
        
        guard let cgmService = services.first(where: { $0.uuid == .dexcomService }) else {
            throw CGMError.sensorNotFound
        }
        
        // Discover characteristics
        let characteristics = try await peripheral.discoverCharacteristics(
            [.dexcomAuthentication, .dexcomControl, .dexcomBackfill],
            for: cgmService
        )
        
        for char in characteristics {
            switch char.uuid {
            case .dexcomAuthentication:
                authCharacteristic = char
            case .dexcomControl:
                controlCharacteristic = char
            case .dexcomBackfill:
                backfillCharacteristic = char
            default:
                break
            }
        }
        
        guard authCharacteristic != nil, controlCharacteristic != nil else {
            throw CGMError.sensorNotFound
        }
        
        // G6-COEX-009: Mark that discovery has succeeded for this transmitter
        if !hasDiscoveredServicesBefore {
            hasDiscoveredServicesBefore = true
            CGMLogger.transmitter.info("DexcomG6Manager: Service discovery succeeded, cached for fast reconnect")
        }
    }
    
    // MARK: - Authentication
    
    private func authenticate() async throws {
        guard let peripheral = peripheral,
              let authChar = authCharacteristic else {
            throw CGMError.connectionFailed
        }
        
        // Check for injected auth faults
        if let injector = faultInjector {
            injector.recordOperation()
            if case .injected(let fault) = injector.shouldInject(for: "authenticate") {
                CGMLogger.transmitter.warning("DexcomG6Manager: Fault injected - \(fault.displayName)")
                switch fault {
                case .authTimeout:
                    throw CGMError.connectionFailed  // Timeout maps to connection failure
                case .authRejected:
                    throw CGMError.unauthorized
                case .bondLost:
                    throw CGMError.connectionFailed
                case .challengeFailed:
                    throw CGMError.unauthorized
                case .connectionDrop, .connectionTimeout:
                    throw CGMError.connectionFailed
                default:
                    break  // Non-auth faults don't interrupt here
                }
            }
        }
        
        setConnectionState(.authenticating)
        CGMLogger.transmitter.info("DexcomG6Manager: Authenticating with \(self.transmitterId.id) slot=\(self.config.slot.displayName)")
        
        // Subscribe to auth notifications (sync registration for fast BLE windows)
        let authStream = await peripheral.prepareNotificationStream(for: authChar)
        
        // Send auth request with configured slot (CGM-046a)
        let (authRequest, token) = authenticator.createAuthRequest(slot: config.slot)
        authToken = token
        
        try await peripheral.writeValue(authRequest.data, for: authChar, type: .withResponse)
        
        // Wait for challenge response
        var authenticated = false
        
        for try await data in authStream {
            if let challengeRx = AuthChallengeRxMessage(data: data) {
                // Process challenge and send response
                guard let challengeTx = authenticator.processChallenge(challengeRx, sentToken: token) else {
                    CGMLogger.transmitter.error("DexcomG6Manager: Auth challenge failed")
                    throw CGMError.unauthorized
                }
                
                try await peripheral.writeValue(challengeTx.data, for: authChar, type: .withResponse)
                
            } else if let statusRx = AuthStatusRxMessage(data: data) {
                if statusRx.authenticated {
                    authenticated = true
                    CGMLogger.transmitter.transmitterPaired(id: transmitterId.id, model: "G6")
                    
                    // CGM-051: Bond request flow when not bonded
                    if !statusRx.bonded {
                        CGMLogger.transmitter.info("DexcomG6Manager: Not bonded, sending KeepAlive + BondRequest")
                        // Send KeepAlive immediately to extend 5s → 25s window
                        let keepAlive = KeepAliveTxMessage()
                        try await peripheral.writeValue(keepAlive.data, for: authChar, type: .withResponse)
                        
                        // Send BondRequest to trigger BLE-level pairing
                        let bondRequest = BondRequestTxMessage()
                        try await peripheral.writeValue(bondRequest.data, for: authChar, type: .withResponse)
                        CGMLogger.transmitter.info("DexcomG6Manager: BondRequest sent, awaiting BLE pairing")
                    }
                    
                    break
                } else {
                    CGMLogger.transmitter.error("DexcomG6Manager: Authentication rejected")
                    throw CGMError.unauthorized
                }
            }
        }
        
        guard authenticated else {
            throw CGMError.unauthorized
        }
        
        // CGM-066a: Send new App Level Key if configured
        // This must happen after auth success but before streaming starts
        if config.generateNewAppLevelKey, let controlChar = controlCharacteristic {
            try await sendNewAppLevelKey(peripheral: peripheral, controlChar: controlChar)
        }
        
        // Send keep-alive to extend connection window
        // Note: Already sent in unbonded case above, but safe to send again
        let keepAlive = KeepAliveTxMessage()
        try await peripheral.writeValue(keepAlive.data, for: authChar, type: .withResponse)
    }
    
    // MARK: - App Level Key (CGM-066)
    
    /// Send a new App Level Key to the transmitter (CGM-066a)
    /// Generates a random 16-byte key, sends ChangeAppLevelKeyTxMessage, and waits for confirmation.
    /// On success, invokes onAppLevelKeyChanged callback for persistence.
    /// Trace: CGM-066a, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    private func sendNewAppLevelKey(
        peripheral: any BLEPeripheralProtocol,
        controlChar: BLECharacteristic
    ) async throws {
        // Generate random 16-byte key
        let newKey = ChangeAppLevelKeyTxMessage.generateRandomKey()
        let message = ChangeAppLevelKeyTxMessage(key: newKey)
        
        CGMLogger.transmitter.info("DexcomG6Manager: Sending ChangeAppLevelKeyTxMessage")
        emitDiagnostic("Sending ALK (16 bytes) to transmitter...")
        
        // Subscribe to control notifications to receive response
        let notificationStream = await peripheral.prepareNotificationStream(for: controlChar)
        
        // Send the ALK message on control characteristic
        try await peripheral.writeValue(message.data, for: controlChar, type: .withResponse)
        
        // Wait for AppLevelKeyAcceptedRxMessage (opcode 0x10)
        // Timeout after 5 seconds
        let deadline = Date().addingTimeInterval(5.0)
        var keyAccepted = false
        
        do {
            for try await notification in notificationStream {
                guard Date() < deadline else {
                    CGMLogger.transmitter.warning("DexcomG6Manager: ALK response timeout")
                    emitDiagnostic("ALK response timeout after 5s")
                    break
                }
                
                if let acceptedRx = AppLevelKeyAcceptedRxMessage(data: notification) {
                    if acceptedRx.accepted {
                        keyAccepted = true
                        CGMLogger.transmitter.info("DexcomG6Manager: App Level Key accepted by transmitter")
                        emitDiagnostic("ALK accepted by transmitter ✓")
                        break
                    }
                }
            }
        } catch {
            CGMLogger.transmitter.warning("DexcomG6Manager: ALK notification stream error: \(error)")
            emitDiagnostic("ALK stream error: \(error.localizedDescription)")
        }
        
        if keyAccepted {
            // Notify callback so app can persist the new key
            onAppLevelKeyChanged?(newKey)
        } else {
            CGMLogger.transmitter.warning("DexcomG6Manager: ALK not confirmed, continuing without ALK")
            emitDiagnostic("ALK not confirmed - continuing without persistent key")
        }
    }
    
    // MARK: - Streaming
    
    private func startStreaming() async throws {
        guard let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            throw CGMError.connectionFailed
        }
        
        // Reset reconnect attempts on successful connection
        reconnectAttempts = 0
        
        // G6-COEX-025: Mark successful first connection (affects retry strategy)
        hasEverConnected = true
        initialConnectionStartTime = nil
        
        setConnectionState(.streaming)
        setSensorState(.active)
        
        // Subscribe to control notifications for glucose readings (sync registration)
        let glucoseStream = await peripheral.prepareNotificationStream(for: controlChar)
        
        streamTask = Task {
            do {
                // Per CGMBLEKit: TransmitterTime (0x24) must be sent before Glucose (0x30)
                // This synchronizes session timing before requesting readings
                // Trace: CGM-053, externals/CGMBLEKit/CGMBLEKit/Transmitter.swift:188-205
                let timeTx = TransmitterTimeTxMessage()
                try await peripheral.writeValue(timeTx.data, for: controlChar, type: .withResponse)
                
                // Wait for time response (indicates transmitter is ready)
                let timeData = try await peripheral.readValue(for: controlChar)
                if let timeRx = TransmitterTimeRxMessage(data: timeData) {
                    CGMLogger.general.debug("DexcomG6Manager: TransmitterTime session age: \(timeRx.sessionAge)s")
                    // G6-DIRECT-034: Update session tracking
                    updateSessionTracking(from: timeRx)
                }
                
                // Now request initial glucose reading
                let glucoseTx = GlucoseTxMessage()
                try await peripheral.writeValue(glucoseTx.data, for: controlChar, type: .withResponse)
                
                for try await data in glucoseStream {
                    if let glucoseRx = GlucoseRxMessage(data: data) {
                        handleGlucoseReading(glucoseRx)
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
    
    private func handleGlucoseReading(_ message: GlucoseRxMessage) {
        // Check for injected sensor faults
        if let injector = faultInjector {
            injector.recordReading()
            if case .injected(let fault) = injector.shouldInject(for: "readGlucose") {
                CGMLogger.readings.warning("DexcomG6Manager: Fault injected - \(fault.displayName)")
                switch fault {
                case .sensorExpired:
                    setSensorState(.expired)
                    onError?(.sensorExpired)
                    return
                case .sensorWarmup:
                    setSensorState(.warmingUp)
                    return
                case .sensorFailed:
                    setSensorState(.failed)
                    onError?(.dataUnavailable)  // sensorFailed maps to dataUnavailable
                    return
                case .noSignal:
                    onError?(.dataUnavailable)
                    return
                case .connectionDrop:
                    setConnectionState(.error)
                    onError?(.connectionFailed)
                    return
                default:
                    break  // Non-reading faults don't interrupt here
                }
            }
        }
        
        guard message.isValid else {
            CGMLogger.readings.warning("DexcomG6Manager: Invalid glucose message received")
            return
        }
        
        // APP-COEX-008: Source label indicates provenance
        let sourceLabel: String
        switch connectionMode {
        case .coexistence:
            sourceLabel = "Dexcom G6 (via Dexcom App)"
        case .direct:
            sourceLabel = "Dexcom G6"
        case .passiveBLE:
            sourceLabel = "Dexcom G6 (Passive)"
        case .healthKitObserver:
            sourceLabel = "Dexcom G6 (HealthKit)"
        case .cloudFollower:
            sourceLabel = "Dexcom G6 (Cloud)"
        case .nightscoutFollower:
            sourceLabel = "Dexcom G6 (Nightscout)"
        }
        
        let reading = GlucoseReading(
            glucose: message.glucose,
            timestamp: Date(),
            trend: mapTrend(message.trend),
            source: sourceLabel
        )
        
        CGMLogger.readings.glucoseReading(
            value: message.glucose,
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
    
    private func mapTrend(_ rawTrend: Int8) -> GlucoseTrend {
        // CGM-TREND-003: G6 trend is rate of change in mg/dL per 10 minutes (signed Int8)
        // This matches Loop's CGMBLEKit/Glucose+SensorDisplayable.swift interpretation
        // NOT discrete 1-7 values like some documentation suggests
        switch rawTrend {
        case ...(-30): return .doubleDown      // Falling very fast (>= 3 mg/dL/min)
        case (-29)...(-20): return .singleDown // Falling fast (2-3 mg/dL/min)
        case (-19)...(-10): return .fortyFiveDown // Falling (1-2 mg/dL/min)
        case (-9)..<10: return .flat           // Stable (-1 to +1 mg/dL/min)
        case 10..<20: return .fortyFiveUp      // Rising (1-2 mg/dL/min)
        case 20..<30: return .singleUp         // Rising fast (2-3 mg/dL/min)
        default: return .doubleUp              // Rising very fast (>= 3 mg/dL/min)
        }
    }
    
    // MARK: - State Management
    
    private func setConnectionState(_ state: G6ConnectionState) {
        let oldState = connectionState
        connectionState = state
        CGMLogger.general.info("DexcomG6Manager: \(oldState.rawValue) → \(state.rawValue)")
        onConnectionStateChanged?(state)
        
        // Trigger auto-reconnect on error if we were previously streaming
        if state == .error && oldState == .streaming {
            handleUnexpectedDisconnect()
        }
    }
    
    private func setSensorState(_ state: SensorState) {
        sensorState = state
        onSensorStateChanged?(state)
    }
    
    /// Update session tracking from TransmitterTimeRxMessage (G6-DIRECT-034)
    /// Trace: GAP-API-021 (future-dated entries fix)
    private func updateSessionTracking(from timeMessage: TransmitterTimeRxMessage) {
        // Compute transmitter activation date (always valid)
        transmitterActivationDate = Date(timeIntervalSinceNow: -TimeInterval(timeMessage.currentTime))
        
        // Check for active session before computing session-related values
        // Trace: GAP-API-021 - Guard against 0xFFFFFFFF sentinel causing corrupt dates
        guard timeMessage.hasActiveSession else {
            // No active session - clear session data, don't compute corrupt dates
            lastSessionAge = nil
            sessionStartDate = nil
            CGMLogger.general.warning("DexcomG6Manager: No active session (sessionStartTime is sentinel 0xFFFFFFFF)")
            setSensorState(.noSensor)
            return
        }
        
        // Use safe session age to guard against underflow
        guard let safeAge = timeMessage.safeSessionAge else {
            // Session age unreasonable (possible underflow) - clear session data
            lastSessionAge = nil
            sessionStartDate = nil
            CGMLogger.general.warning("DexcomG6Manager: Unreasonable session age detected, clearing session data")
            setSensorState(.noSensor)
            return
        }
        
        // Store validated session age for computed properties
        lastSessionAge = safeAge
        
        // Compute session start date from validated age
        sessionStartDate = Date(timeIntervalSinceNow: -TimeInterval(safeAge))
        
        // Update sensor state based on session timing
        if isCompletelyExpired {
            setSensorState(.expired)
        } else if isInWarmup {
            setSensorState(.warmingUp)
        } else if isSessionExpired && isInGracePeriod {
            // In grace period - still active but warn user
            setSensorState(.active)
        }
        
        let warmup = isInWarmup
        let expired = isSessionExpired
        CGMLogger.general.info("DexcomG6Manager: Session tracking updated - age: \(safeAge)s, warmup: \(warmup), expired: \(expired)")
    }
    
    // MARK: - Public Methods
    
    /// Request a glucose reading immediately
    public func requestGlucose() async throws {
        guard connectionState == .streaming,
              let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            throw CGMError.dataUnavailable
        }
        
        let glucoseTx = GlucoseTxMessage()
        try await peripheral.writeValue(glucoseTx.data, for: controlChar, type: .withResponse)
    }
    
    /// Get battery status
    public func getBatteryStatus() async throws -> BatteryStatusRxMessage? {
        guard connectionState == .streaming,
              let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            throw CGMError.dataUnavailable
        }
        
        let batteryTx = BatteryStatusTxMessage()
        try await peripheral.writeValue(batteryTx.data, for: controlChar, type: .withResponse)
        
        // Read response
        let data = try await peripheral.readValue(for: controlChar)
        return BatteryStatusRxMessage(data: data)
    }
    
    /// Get transmitter time
    public func getTransmitterTime() async throws -> TransmitterTimeRxMessage? {
        guard connectionState == .streaming,
              let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            throw CGMError.dataUnavailable
        }
        
        let timeTx = TransmitterTimeTxMessage()
        try await peripheral.writeValue(timeTx.data, for: controlChar, type: .withResponse)
        
        let data = try await peripheral.readValue(for: controlChar)
        return TransmitterTimeRxMessage(data: data)
    }
    
    /// Set vendor connection callback
    /// - Parameter callback: Called when vendor app connection status changes
    public func setVendorCallback(_ callback: @escaping @Sendable (Bool) -> Void) {
        self.onVendorConnectionDetected = callback
    }
    
    /// Set App Level Key changed callback (CGM-066f)
    /// - Parameter callback: Called when a new ALK is generated and accepted by transmitter
    /// Trace: CGM-066f, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    public func setOnAppLevelKeyChanged(_ callback: @escaping @Sendable (Data) -> Void) {
        self.onAppLevelKeyChanged = callback
    }
    
    // MARK: - Sensor Session Control (G6-DIRECT-031, G6-DIRECT-032)
    
    /// Start a new sensor session (direct mode only)
    /// 
    /// This tells the transmitter to begin a new 10-day sensor session.
    /// The transmitter will enter warmup mode for 2 hours before providing glucose readings.
    /// 
    /// - Parameter sensorStartDate: When the sensor was physically inserted (default: now)
    /// - Returns: The session start response from the transmitter
    /// - Throws: CGMError.dataUnavailable if not connected, or CGMError.sensorExpired if already in session
    /// 
    /// Trace: G6-DIRECT-031 - Loop-compatible startSensor command
    public func startSensorSession(at sensorStartDate: Date = Date()) async throws -> SessionStartRxMessage {
        guard connectionState == .streaming,
              let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            throw CGMError.dataUnavailable
        }
        
        guard config.connectionMode == .direct else {
            CGMLogger.general.warning("DexcomG6Manager: startSensorSession requires direct mode")
            throw CGMError.configurationError("startSensorSession requires direct connection mode")
        }
        
        // Need transmitter activation date to calculate relative time
        var activationDate = transmitterActivationDate
        if activationDate == nil {
            // Get transmitter time first if we don't have activation date
            CGMLogger.general.info("DexcomG6Manager: Getting transmitter time before session start")
            if let timeMsg = try await getTransmitterTime() {
                let activation = Date(timeIntervalSinceNow: -TimeInterval(timeMsg.currentTime))
                transmitterActivationDate = activation
                activationDate = activation
            } else {
                throw CGMError.dataUnavailable
            }
        }
        
        let sessionStartTx = SessionStartTxMessage(
            sensorStartDate: sensorStartDate,
            transmitterActivationDate: activationDate!
        )
        
        CGMLogger.general.info("DexcomG6Manager: Starting sensor session at \(sensorStartDate)")
        try await peripheral.writeValue(sessionStartTx.data, for: controlChar, type: .withResponse)
        
        // Read response
        let data = try await peripheral.readValue(for: controlChar)
        guard let response = SessionStartRxMessage(data: data) else {
            CGMLogger.general.error("DexcomG6Manager: Invalid session start response")
            throw CGMError.dataUnavailable
        }
        
        if response.isSuccess {
            // Update session tracking state
            sessionStartDate = sensorStartDate
            lastSessionAge = 0
            setSensorState(.warmingUp)
            CGMLogger.general.info("DexcomG6Manager: Sensor session started successfully")
        } else {
            CGMLogger.general.warning("DexcomG6Manager: Session start failed with status=\(response.status)")
        }
        
        return response
    }
    
    /// Stop the current sensor session (direct mode only)
    /// 
    /// This tells the transmitter to end the current sensor session.
    /// The sensor will need to be replaced and a new session started.
    /// 
    /// - Parameter stopDate: When to stop the session (default: now)
    /// - Returns: The session stop response from the transmitter
    /// - Throws: CGMError.dataUnavailable if not connected
    /// 
    /// Trace: G6-DIRECT-032 - Loop-compatible stopSensor command
    public func stopSensorSession(at stopDate: Date = Date()) async throws -> SessionStopRxMessage {
        guard connectionState == .streaming,
              let peripheral = peripheral,
              let controlChar = controlCharacteristic else {
            throw CGMError.dataUnavailable
        }
        
        guard config.connectionMode == .direct else {
            CGMLogger.general.warning("DexcomG6Manager: stopSensorSession requires direct mode")
            throw CGMError.configurationError("stopSensorSession requires direct connection mode")
        }
        
        // Need transmitter activation date to calculate relative time
        var activationDate = transmitterActivationDate
        if activationDate == nil {
            // Get transmitter time first if we don't have activation date
            CGMLogger.general.info("DexcomG6Manager: Getting transmitter time before session stop")
            if let timeMsg = try await getTransmitterTime() {
                let activation = Date(timeIntervalSinceNow: -TimeInterval(timeMsg.currentTime))
                transmitterActivationDate = activation
                activationDate = activation
            } else {
                throw CGMError.dataUnavailable
            }
        }
        
        let sessionStopTx = SessionStopTxMessage(
            stopDate: stopDate,
            transmitterActivationDate: activationDate!
        )
        
        CGMLogger.general.info("DexcomG6Manager: Stopping sensor session")
        try await peripheral.writeValue(sessionStopTx.data, for: controlChar, type: .withResponse)
        
        // Read response
        let data = try await peripheral.readValue(for: controlChar)
        guard let response = SessionStopRxMessage(data: data) else {
            CGMLogger.general.error("DexcomG6Manager: Invalid session stop response")
            throw CGMError.dataUnavailable
        }
        
        if response.isSuccess {
            // Clear session state
            sessionStartDate = nil
            lastSessionAge = nil
            setSensorState(.stopped)
            CGMLogger.general.info("DexcomG6Manager: Sensor session stopped successfully")
        } else {
            CGMLogger.general.warning("DexcomG6Manager: Session stop failed with status=\(response.status)")
        }
        
        return response
    }
    
    // MARK: - Fault Injection (Testing)
    
    /// Set fault injector for testing error paths
    /// - Parameter injector: The fault injector to use, or nil to disable
    /// Trace: G6-FIX-016, SIM-FAULT-001
    public func setFaultInjector(_ injector: G6FaultInjector?) {
        self.faultInjector = injector
    }
    
    /// Get current fault injector
    public var currentFaultInjector: G6FaultInjector? {
        faultInjector
    }
    
    // MARK: - Testing Support
    
    /// Current reconnection attempt count (for testing)
    public var currentReconnectAttempts: Int {
        reconnectAttempts
    }
    
    /// Calculate backoff delay for given attempt number (for testing)
    /// - Parameter attempt: Attempt number (1-based)
    /// - Parameter isInitialPairing: Whether this is during initial pairing (affects cycle alignment)
    /// - Returns: Delay in seconds
    public func backoffDelayForAttempt(_ attempt: Int, isInitialPairing: Bool = false) -> TimeInterval {
        let exponent = Double(max(0, attempt - 1))
        let rawDelay = config.reconnectDelay * pow(config.backoffMultiplier, exponent)
        let cappedDelay = min(rawDelay, config.maxReconnectDelay)
        
        // G6-COEX-026: Cycle alignment during initial pairing
        if isInitialPairing && attempt > 3 && cappedDelay < DexcomG6ManagerConfig.transmitterCycleInterval {
            return DexcomG6ManagerConfig.transmitterCycleInterval
        }
        
        return cappedDelay
    }
    
    /// Reset reconnect attempts counter (for testing)
    public func resetReconnectAttempts() {
        reconnectAttempts = 0
    }
    
    /// G6-COEX-026: Reset initial pairing state (for testing)
    public func resetPairingState() {
        hasEverConnected = false
        initialConnectionStartTime = nil
    }
    
    // MARK: - Test Helpers
    
    /// CGM-TREND-004: Create a GlucoseReading for testing trend mapping
    /// - Parameters:
    ///   - glucose: Glucose value in mg/dL
    ///   - rawTrend: Raw Dexcom trend byte (1-7)
    ///   - source: Source label
    /// - Returns: GlucoseReading with mapped trend
    public func testCreateGlucoseReading(glucose: Double, rawTrend: Int8, source: String) -> GlucoseReading {
        GlucoseReading(
            glucose: glucose,
            timestamp: Date(),
            trend: mapTrend(rawTrend),
            source: source
        )
    }
}
