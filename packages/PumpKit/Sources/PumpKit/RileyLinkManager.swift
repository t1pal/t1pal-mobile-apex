// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RileyLinkManager.swift
// PumpKit
//
// RileyLink/OrangeLink BLE-to-RF bridge connection manager.
// Handles BLE connection, RF frequency tuning, and packet framing.
// Trace: PUMP-MDT-004, PRD-005, RL-WIRE-001
//
// Usage:
//   let manager = RileyLinkManager.shared
//   try await manager.connect(to: "OrangeLink-xxxx")
//   let response = try await manager.sendCommand(data, frequency: 916.5)

import Foundation
import BLEKit

// MARK: - RileyLink Device

/// Represents a discovered RileyLink-compatible device
public struct RileyLinkDevice: Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let rssi: Int
    public let deviceType: RileyLinkDeviceType
    public let discoveredAt: Date
    
    public init(id: String, name: String, rssi: Int, deviceType: RileyLinkDeviceType = .unknown) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.deviceType = deviceType
        self.discoveredAt = Date()
    }
    
    public var displayName: String {
        if name.isEmpty {
            return "Unknown Device (\(id.prefix(8)))"
        }
        return name
    }
}

/// Types of RileyLink-compatible devices
public enum RileyLinkDeviceType: String, Codable, Sendable, CaseIterable {
    case rileyLink = "RileyLink"
    case orangeLink = "OrangeLink"
    case emaLink = "EmaLink"
    case unknown = "Unknown"
    
    /// Identify device type from name
    public static func from(name: String) -> RileyLinkDeviceType {
        let lowercased = name.lowercased()
        if lowercased.contains("orangelink") {
            return .orangeLink
        } else if lowercased.contains("emalink") {
            return .emaLink
        } else if lowercased.contains("rileylink") {
            return .rileyLink
        }
        return .unknown
    }
    
    public var icon: String {
        switch self {
        case .rileyLink: return "antenna.radiowaves.left.and.right"
        case .orangeLink: return "antenna.radiowaves.left.and.right.circle"
        case .emaLink: return "antenna.radiowaves.left.and.right.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - RileyLink Connection State

/// Connection state for RileyLink devices
public enum RileyLinkConnectionState: String, Sendable, Codable {
    case disconnected
    case scanning
    case connecting
    case connected
    case tuning      // RF frequency tuning in progress
    case ready       // Ready for pump communication
    case error
    
    public var isConnected: Bool {
        switch self {
        case .connected, .tuning, .ready:
            return true
        default:
            return false
        }
    }
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension RileyLinkConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .disconnected: return .disconnected
        case .scanning: return .scanning
        case .connecting: return .connecting
        case .connected, .tuning, .ready: return .connected
        case .error: return .error
        }
    }
}

// MARK: - Signal Quality (PROTO-RL-002)

/// BLE signal quality based on RSSI values
/// Reference: Bluetooth Core Spec recommendations
public enum SignalQuality: String, Sendable, Codable, CaseIterable {
    case excellent  // > -50 dBm
    case good       // -60 to -50 dBm
    case fair       // -70 to -60 dBm
    case weak       // -80 to -70 dBm
    case poor       // < -80 dBm
    case unknown    // No RSSI available
    
    /// SF Symbol name for UI display
    public var symbolName: String {
        switch self {
        case .excellent: return "wifi.circle.fill"
        case .good: return "wifi.circle"
        case .fair: return "wifi"
        case .weak: return "wifi.exclamationmark"
        case .poor: return "wifi.slash"
        case .unknown: return "questionmark.circle"
        }
    }
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .weak: return "Weak"
        case .poor: return "Poor"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - RileyLink LED Types

/// RileyLink LED type (green or blue)
/// Trace: RL-WIRE-017
public enum RileyLinkLEDType: UInt8, Sendable, CaseIterable {
    case green = 0x00
    case blue = 0x01
}

/// RileyLink LED mode
/// Trace: RL-WIRE-017
public enum RileyLinkLEDMode: UInt8, Sendable, CaseIterable {
    case off = 0x00
    case on = 0x01
    case auto = 0x02
    
    public var description: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .auto: return "Auto (flash on activity)"
        }
    }
}

// MARK: - Simulation Mode (RL-MODE-001)

/// Explicit simulation mode to prevent silent fallback masking real errors
public enum SimulationMode: String, Sendable, Codable, CaseIterable {
    /// Live mode - use real BLE, throw errors on failure (no fallback)
    case live
    
    /// Demo mode - intentionally simulated for UI testing/demos
    case demo
    
    /// Fallback mode - real BLE failed, using simulation as recovery
    /// Should only be used temporarily and logged prominently
    case fallback
    
    /// Test mode - simulated with instant responses (no delays)
    /// Use for unit tests to accelerate execution (WIRE-011)
    case test
    
    public var isSimulated: Bool {
        self != .live
    }
    
    /// Whether delays should be skipped (WIRE-011)
    public var skipDelays: Bool {
        self == .test
    }
    
    public var description: String {
        switch self {
        case .live: return "Live (Real Device)"
        case .demo: return "Demo Mode"
        case .fallback: return "Fallback (BLE Failed)"
        case .test: return "Test Mode (Instant)"
        }
    }
    
    /// Conditional delay that skips in test mode (WIRE-011)
    public func delay(nanoseconds: UInt64) async throws {
        guard !skipDelays else { return }
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

// MARK: - RileyLink Manager

/// Manages BLE connection to RileyLink-compatible devices
/// Handles RF frequency tuning and packet transmission/reception
public actor RileyLinkManager {
    
    // MARK: - Singleton
    
    /// Shared instance - BLE central now uses dedicated queue (Loop/Trio pattern)
    /// so no @MainActor requirement (RL-WIRE-008)
    public static let shared = RileyLinkManager()
    
    // MARK: - State
    
    /// Current connection state
    public private(set) var state: RileyLinkConnectionState = .disconnected
    
    /// Currently connected device
    public private(set) var connectedDevice: RileyLinkDevice?
    
    /// Discovered devices from scanning
    public private(set) var discoveredDevices: [RileyLinkDevice] = []
    
    /// Current RF frequency
    public private(set) var currentFrequency: Double?
    
    /// Last RSSI reading
    public private(set) var lastRSSI: Int?
    
    /// PROTO-RL-002: Signal quality based on RSSI
    /// Useful for UI display and connection quality monitoring
    public var signalQuality: SignalQuality {
        guard let rssi = lastRSSI else { return .unknown }
        switch rssi {
        case -50...0: return .excellent
        case -60..<(-50): return .good
        case -70..<(-60): return .fair
        case -80..<(-70): return .weak
        default: return .poor
        }
    }
    
    /// Battery level (if available)
    public private(set) var batteryLevel: Int?
    
    /// Error if in error state
    public private(set) var lastError: RileyLinkError?
    
    /// Current simulation mode (RL-MODE-001)
    /// Set to .live for real device communication, .demo for testing
    public private(set) var simulationMode: SimulationMode = .live
    
    // MARK: - Configuration
    
    /// Timeout for BLE connection
    public var connectionTimeout: TimeInterval = 10.0
    
    /// Timeout for RF commands
    public var commandTimeout: TimeInterval = 2.0
    
    /// Timeout for BLE notification response (RL-WIRE-009)
    public var responseTimeout: TimeInterval = 5.0
    
    /// Retry count for failed commands
    public var retryCount: Int = 3
    
    /// RL-CONFIG-001: Set response timeout from UI
    public func setResponseTimeout(_ timeout: TimeInterval) {
        responseTimeout = max(1.0, min(30.0, timeout))
        RileyLinkLogger.connection.info("Response timeout set to \(self.responseTimeout)s")
    }
    
    // WIRE-008: Fault injection support
    public var faultInjector: PumpFaultInjector?
    
    // WIRE-008: Metrics support
    private let metrics: PumpMetrics
    
    // PROD-HARDEN-032: Whether simulation is allowed
    private let allowSimulation: Bool
    
    // MARK: - Private State
    
    private var observers: [UUID: (RileyLinkConnectionState) -> Void] = [:]
    private var scanTask: Task<Void, Never>?
    
    /// BLE central for real device scanning and connection
    /// Must be injected at app startup via setBLECentral() - NOT lazy created
    /// iOS 26 requires synchronous main thread context for CBCentralManager creation
    /// nonisolated(unsafe) allows synchronous access from App.init() before actor is used
    private nonisolated(unsafe) var _central: (any BLECentralProtocol)?
    private var centralOptions: BLECentralOptions
    
    /// Get the BLE central
    /// Must have been injected via setBLECentral() at app startup
    private var central: any BLECentralProtocol {
        guard let c = _central else {
            fatalError("BLE central not initialized - call setBLECentral() at app startup")
        }
        return c
    }
    
    /// Inject BLE central created at app startup (BLE-ARCH-001)
    /// iOS 26 requires CBCentralManager to be created from synchronous main context
    /// NOT from Task/async/MainActor.run
    /// 
    /// Call this from App.init() or similar synchronous startup context
    /// nonisolated: Safe because this is called once at startup before actor is used
    public nonisolated func setBLECentral(_ central: any BLECentralProtocol) {
        _central = central
    }
    
    /// Check if BLE central has been injected
    public var hasBLECentral: Bool {
        _central != nil
    }
    
    /// Whether the manager is currently using simulation mode (no real BLE peripheral)
    /// True when: 1) No BLE central, 2) No connected peripheral, or 3) No data characteristic
    /// Trace: RL-WIRE-021
    public var isSimulationMode: Bool {
        connectedPeripheral == nil || dataCharacteristic == nil
    }
    
    /// Whether we have a real BLE peripheral connected (not simulation)
    /// Trace: MDT-PLAYGROUND-FIX-001
    public var hasRealPeripheral: Bool {
        connectedPeripheral != nil && dataCharacteristic != nil
    }
    
    /// MDT-WIRE-001: Expose connected peripheral for session creation
    /// Allows playgrounds to create RileyLinkSession from shared connection
    public var currentPeripheral: (any BLEPeripheralProtocol)? {
        connectedPeripheral
    }
    
    /// PROTO-RL-001: Whether using Nordic UART Service (OrangeLink compatibility mode)
    public var isUsingNUSMode: Bool {
        isNUSMode
    }
    
    /// Connected BLE peripheral (for real device communication)
    private var connectedPeripheral: (any BLEPeripheralProtocol)?
    
    /// Discovered BLE peripherals (for connection lookup)
    private var discoveredPeripherals: [String: BLEPeripheralInfo] = [:]
    
    /// Discovered BLE characteristics for RF communication
    private var dataCharacteristic: BLECharacteristic?
    private var responseCountCharacteristic: BLECharacteristic?
    private var firmwareCharacteristic: BLECharacteristic?  // RL-GATT-001
    
    /// PROTO-RL-001: NUS mode for OrangeLink compatibility
    /// When true, using Nordic UART Service instead of RileyLink service
    private var isNUSMode: Bool = false
    /// NUS RX characteristic for receiving data (notifications)
    private var nusRXCharacteristic: BLECharacteristic?
    
    /// Detected RileyLink firmware version (RL-CMD-004)
    private var detectedFirmwareVersion: RadioFirmwareVersion = .unknown
    
    /// Raw firmware version string from device (for display/debugging)
    /// Stored even if parsing fails, so we can see what device actually returns
    private var rawFirmwareString: String?
    
    // MARK: - Initialization
    
    /// Create manager with custom BLE central (for testing)
    /// - Parameters:
    ///   - central: BLE central implementation (real or mock)
    ///   - faultInjector: Optional fault injector for testing
    ///   - metrics: Metrics collector
    ///   - allowSimulation: Allow simulated BLE central (default: false for production safety)
    public init(central: any BLECentralProtocol, faultInjector: PumpFaultInjector? = nil, metrics: PumpMetrics = .shared, allowSimulation: Bool = false) {
        self._central = central
        self.centralOptions = .default
        self.faultInjector = faultInjector
        self.metrics = metrics
        self.allowSimulation = allowSimulation
    }
    
    /// Create manager with platform-default BLE central (lazy initialization)
    public init(faultInjector: PumpFaultInjector? = nil, metrics: PumpMetrics = .shared) {
        // Don't create BLE central here - defer until first use (RL-WIRE-008)
        self._central = nil
        self.centralOptions = BLECentralOptions(
            showPowerAlert: true,
            restorationIdentifier: "com.t1pal.pumpkit.rileylink"
        )
        self.faultInjector = faultInjector
        self.metrics = metrics
        self.allowSimulation = false  // Production mode - no simulation
    }
    
    // MARK: - Scanning
    
    /// Start scanning for RileyLink devices
    public func startScanning() async {
        guard state == .disconnected else { return }
        
        // BLE-ARCH-001: BLE central must be injected at app startup
        guard hasBLECentral else {
            RileyLinkLogger.connection.error("BLE central not initialized - call setBLECentral() at app startup")
            return
        }
        
        // PROD-HARDEN-032: Validate simulation settings before starting
        do {
            try validateBLECentral(central, allowSimulation: allowSimulation, component: "RileyLinkManager")
        } catch {
            RileyLinkLogger.connection.error("Simulation validation failed: \(error)")
            return
        }
        
        state = .scanning
        discoveredDevices = []
        notifyObservers()
        
        RileyLinkLogger.connection.info("Starting RileyLink scan")
        
        // PROTO-RL-001: Scan for both RileyLink and NUS services (OrangeLink compatibility)
        scanTask = Task {
            do {
                // Scan for devices advertising RileyLink or Nordic UART Service
                let scanStream = central.scan(for: [.rileyLinkService, .nordicUARTService])
                
                for try await result in scanStream {
                    guard !Task.isCancelled else { break }
                    
                    // Store peripheral info for later connection
                    let deviceId = result.peripheral.identifier.description
                    discoveredPeripherals[deviceId] = result.peripheral
                    
                    // RL-WIRE-019: Log when real device is discovered
                    RileyLinkLogger.connection.info("🔗 REAL BLE: Discovered device '\(result.peripheral.name ?? "unknown")' id=\(deviceId)")
                    
                    // Convert BLE scan result to RileyLinkDevice
                    let deviceType = RileyLinkDeviceType.from(name: result.peripheral.name ?? "")
                    let device = RileyLinkDevice(
                        id: deviceId,
                        name: result.peripheral.name ?? "RileyLink",
                        rssi: result.rssi,
                        deviceType: deviceType
                    )
                    
                    addDiscoveredDevice(device)
                }
            } catch {
                RileyLinkLogger.connection.error("BLE scan error: \(error.localizedDescription)")
                // RL-WIRE-019: Log when falling back to simulated device
                RileyLinkLogger.connection.warning("⚠️ BLE scan failed - falling back to simulated device for testing")
                // Fall back to simulated device for testing when BLE unavailable
                // NOTE: Simulated device is NOT added to discoveredPeripherals
                // so connect() will use simulation path
                if !Task.isCancelled {
                    // WIRE-010: Use simulationDelay instead of Task.sleep
                    try? await simulationDelay(nanoseconds: 500_000_000)
                    let simDevice = RileyLinkDevice(
                        id: "sim-orangelink-001",
                        name: "OrangeLink-DEMO",
                        rssi: -65,
                        deviceType: .orangeLink
                    )
                    addDiscoveredDevice(simDevice)
                    RileyLinkLogger.connection.warning("⚠️ SIMULATION: Added fake OrangeLink-DEMO device")
                }
            }
        }
    }
    
    /// Stop scanning
    public func stopScanning() async {
        scanTask?.cancel()
        scanTask = nil
        
        // Stop the BLE central scan (only if initialized)
        if _central != nil {
            await central.stopScan()
        }
        
        if state == .scanning {
            state = .disconnected
            notifyObservers()
        }
        
        RileyLinkLogger.connection.info("Stopped RileyLink scan")
    }
    
    private func addDiscoveredDevice(_ device: RileyLinkDevice) {
        // Update or add device
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
        }
        
        RileyLinkLogger.connection.rileyLinkConnected(name: device.name, rssi: device.rssi)
    }
    
    // MARK: - Connection
    
    /// Connect to a RileyLink device
    /// Trace: WIRE-008 (fault injection + metrics)
    public func connect(to device: RileyLinkDevice) async throws {
        let startTime = Date()
        
        // WIRE-008: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "connect")
            if case .injected(let fault) = result {
                await metrics.recordCommand("connect", duration: 0, success: false, pumpType: .medtronic)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .disconnected || state == .scanning else {
            throw RileyLinkError.alreadyConnected
        }
        
        await stopScanning()
        
        state = .connecting
        notifyObservers()
        
        RileyLinkLogger.connection.info("Connecting to \(device.name)")
        
        // BLE-ARCH-001: Try real BLE connection if central is available
        if hasBLECentral, let peripheralInfo = discoveredPeripherals[device.id] {
            RileyLinkLogger.connection.info("🔗 REAL BLE: Found peripheral in discoveredPeripherals, attempting connection")
            do {
                let peripheral = try await central.connect(to: peripheralInfo)
                connectedPeripheral = peripheral
                
                // Discover RileyLink service and characteristics (RL-WIRE-003)
                try await discoverCharacteristics(on: peripheral)
                
                // RL-CMD-004: Get firmware version after connection
                await detectFirmwareVersion()
                
                connectedDevice = device
                lastRSSI = device.rssi  // PROTO-RL-002: Store initial RSSI
                state = .connected
                notifyObservers()
                RileyLinkLogger.connection.rileyLinkConnected(name: device.name, rssi: device.rssi)
                RileyLinkLogger.connection.info("✅ REAL BLE: Connection successful with characteristics discovered")
                
                // WIRE-008: Record metrics
                let duration = Date().timeIntervalSince(startTime)
                await metrics.recordCommand("connect", duration: duration, success: true, pumpType: .medtronic)
                return
            } catch {
                RileyLinkLogger.connection.error("BLE connect error: \(error.localizedDescription)")
                // PG-AUDIT-022: In live mode, propagate real BLE errors instead of falling back
                if simulationMode == .live {
                    state = .disconnected
                    throw error
                }
                // Fall through to simulated connection for demo/testing only
            }
        } else if hasBLECentral {
            // Has BLE but device not in discovered list
            // RL-WIRE-019: Log when device not found in discoveredPeripherals
            let peripheralCount = discoveredPeripherals.count
            let peripheralKeys = discoveredPeripherals.keys.joined(separator: ", ")
            RileyLinkLogger.connection.warning("⚠️ Device '\(device.name)' (id=\(device.id)) not found in discoveredPeripherals (count=\(peripheralCount), keys=\(peripheralKeys))")
            
            // RL-DEBUG-008: In live mode, throw error instead of falling back to simulation
            if simulationMode == .live {
                state = .disconnected
                throw RileyLinkError.deviceNotFound
            }
        } else {
            // No BLE central - testing/demo mode
            RileyLinkLogger.connection.warning("⚠️ SIMULATION: No BLE central available - using simulation mode")
        }
        
        // Simulated connection for testing/demo mode
        // RL-WIRE-020: Log when falling back to simulation
        RileyLinkLogger.connection.warning("⚠️ SIMULATION MODE: Using simulated connection for '\(device.name)' (no real BLE peripheral)")
        // WIRE-010: Use simulationDelay instead of Task.sleep
        try await simulationDelay(nanoseconds: 500_000_000)
        try Task.checkCancellation()
        
        connectedDevice = device
        lastRSSI = device.rssi  // PROTO-RL-002: Store initial RSSI
        state = .connected
        notifyObservers()
        
        RileyLinkLogger.connection.rileyLinkConnected(name: device.name, rssi: device.rssi)
    }
    
    /// Discover RileyLink service and characteristics
    /// PROTO-RL-001: Falls back to Nordic UART Service (NUS) for OrangeLink compatibility
    private func discoverCharacteristics(on peripheral: any BLEPeripheralProtocol) async throws {
        RileyLinkLogger.connection.info("Discovering RileyLink characteristics")
        
        // Reset NUS mode flag
        isNUSMode = false
        nusRXCharacteristic = nil
        
        // Try RileyLink service first, then fall back to NUS
        let services = try await peripheral.discoverServices([.rileyLinkService, .nordicUARTService])
        
        // PROTO-RL-001: Prefer RileyLink service, fall back to NUS
        if let rlService = services.first(where: { $0.uuid == .rileyLinkService }) {
            // Standard RileyLink service discovery
            let characteristics = try await peripheral.discoverCharacteristics(
                nil,  // Discover all - more reliable than specific UUIDs
                for: rlService
            )
            
            RileyLinkLogger.connection.debug("Discovered \(characteristics.count) RileyLink characteristics")
            
            // Store discovered characteristics
            for char in characteristics {
                RileyLinkLogger.connection.debug("  - \(char.uuid.description)")
                if char.uuid == .rileyLinkData {
                    dataCharacteristic = char
                    RileyLinkLogger.connection.info("Found data characteristic")
                } else if char.uuid == .rileyLinkResponseCount {
                    responseCountCharacteristic = char
                    RileyLinkLogger.connection.info("Found response count characteristic")
                } else if char.uuid == .rileyLinkFirmwareVersion {
                    firmwareCharacteristic = char
                    RileyLinkLogger.connection.info("Found firmware version characteristic")
                }
            }
        } else if let nusService = services.first(where: { $0.uuid == .nordicUARTService }) {
            // PROTO-RL-001: Nordic UART Service fallback for OrangeLink
            RileyLinkLogger.connection.info("Using NUS fallback for OrangeLink compatibility")
            isNUSMode = true
            
            let characteristics = try await peripheral.discoverCharacteristics(
                nil,
                for: nusService
            )
            
            RileyLinkLogger.connection.debug("Discovered \(characteristics.count) NUS characteristics")
            
            for char in characteristics {
                RileyLinkLogger.connection.debug("  - \(char.uuid.description)")
                if char.uuid == .nordicUARTTX {
                    // NUS TX is where we write commands (named from peripheral's perspective)
                    dataCharacteristic = char
                    RileyLinkLogger.connection.info("Found NUS TX characteristic (data write)")
                } else if char.uuid == .nordicUARTRX {
                    // NUS RX is where we receive responses (named from peripheral's perspective)
                    nusRXCharacteristic = char
                    RileyLinkLogger.connection.info("Found NUS RX characteristic (data read)")
                }
            }
        } else {
            throw RileyLinkError.deviceNotFound
        }
        
        guard dataCharacteristic != nil else {
            throw RileyLinkError.communicationFailed
        }
        
        // PROTO-RL-001: Subscribe to NUS RX for responses in NUS mode
        if isNUSMode, let rxChar = nusRXCharacteristic {
            _ = peripheral.subscribe(to: rxChar)
            RileyLinkLogger.connection.info("Subscribed to NUS RX notifications")
        }
        
        // RL-NOTIFY-001: Subscribe to responseCount notifications at connect time
        // This is how Loop does it - responseCount increments when response is ready
        // NOTE: Currently using polling (RL-POLL-002) instead of notifications
        // Uncomment when switching to notification-based approach:
        // if let rcChar = responseCountCharacteristic {
        //     _ = peripheral.subscribe(to: rcChar)
        //     RileyLinkLogger.connection.info("Subscribed to responseCount notifications")
        // }
    }
    
    /// Detect RileyLink firmware version (RL-CMD-004, RL-DEBUG-001, RL-CRASH-006)
    /// Uses GATT characteristic read with FRESH discovery (matches RileyLink Playground pattern)
    /// RL-CRASH-006: Discover characteristic fresh each time to avoid stale reference crash
    private func detectFirmwareVersion() async {
        // RL-DEBUG-009: Entry logging
        RileyLinkLogger.connection.info("detectFirmwareVersion called - peripheral=\(self.connectedPeripheral != nil ? "connected" : "nil")")
        
        guard let peripheral = connectedPeripheral else {
            RileyLinkLogger.connection.warning("Cannot detect firmware version: no connection")
            return
        }
        
        do {
            // RL-CRASH-006: Discover services FRESH (like RileyLink Playground)
            RileyLinkLogger.connection.debug("Discovering RileyLink service for firmware read...")
            let services = try await peripheral.discoverServices([.rileyLinkService])
            
            guard let rlService = services.first(where: { $0.uuid == .rileyLinkService }) else {
                RileyLinkLogger.connection.warning("RileyLink service not found for firmware read")
                return
            }
            
            // RL-CRASH-006: Discover firmware characteristic FRESH (like RileyLink Playground)
            RileyLinkLogger.connection.debug("Discovering firmware characteristic...")
            let characteristics = try await peripheral.discoverCharacteristics(
                [.rileyLinkFirmwareVersion],
                for: rlService
            )
            
            guard let fwChar = characteristics.first(where: { $0.uuid == .rileyLinkFirmwareVersion }) else {
                RileyLinkLogger.connection.warning("Firmware characteristic not found")
                return
            }
            
            // RL-DEBUG-009: Log characteristic details
            RileyLinkLogger.connection.debug("Reading firmware from fresh characteristic: \(fwChar.uuid.description)")
            
            // RL-GATT-001: Read firmware version directly from GATT characteristic
            let data = try await peripheral.readValue(for: fwChar)
            
            // RL-DEBUG-002: Log response bytes
            RileyLinkLogger.connection.debug("Firmware GATT read: \(data.hexDump)")
            
            // Parse version string - handles "subg_rfspy X.Y", "ble_rfspy X.Y", and fallback formats
            if let versionString = String(data: data, encoding: .utf8) {
                // Store raw string for display (like RileyLink Playground does)
                rawFirmwareString = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
                RileyLinkLogger.connection.info("Firmware version string: \(versionString)")
                
                if let version = RadioFirmwareVersion(versionString: versionString) {
                    detectedFirmwareVersion = version
                    RileyLinkLogger.connection.info("Detected firmware: \(version.description)")
                } else {
                    // Parser failed but we have raw string - assume v2+ for modern devices
                    RileyLinkLogger.connection.warning("Could not parse version from: \(versionString) - assuming v2+")
                    detectedFirmwareVersion = .assumeV2
                }
            } else {
                RileyLinkLogger.connection.warning("Firmware data not UTF-8: \(data.hexDump)")
                // Binary firmware response (OrangeLink?) - assume v2+
                rawFirmwareString = data.hexDump
                detectedFirmwareVersion = .assumeV2
            }
        } catch {
            RileyLinkLogger.connection.warning("Failed to detect firmware version: \(error.localizedDescription)")
            // Use assumeV2 for modern devices when detection fails
            detectedFirmwareVersion = .assumeV2
        }
    }
    
    /// Connect to a device by name prefix
    public func connect(namePrefix: String) async throws {
        await startScanning()
        
        // WIRE-010: Use simulationDelay instead of Task.sleep
        try await simulationDelay(nanoseconds: 2_000_000_000)
        
        guard let device = discoveredDevices.first(where: { 
            $0.name.lowercased().hasPrefix(namePrefix.lowercased())
        }) else {
            await stopScanning()
            throw RileyLinkError.deviceNotFound
        }
        
        try await connect(to: device)
    }
    
    /// Disconnect from current device
    public func disconnect() async {
        guard let device = connectedDevice else { return }
        
        RileyLinkLogger.connection.rileyLinkDisconnected(name: device.name)
        
        // Disconnect real BLE peripheral if connected
        if let peripheral = connectedPeripheral {
            await peripheral.disconnect()
            connectedPeripheral = nil
        }
        
        // Clear discovered characteristics
        dataCharacteristic = nil
        responseCountCharacteristic = nil
        firmwareCharacteristic = nil  // RL-GATT-001
        isNUSMode = false  // PROTO-RL-001
        nusRXCharacteristic = nil  // PROTO-RL-001
        
        connectedDevice = nil
        currentFrequency = nil
        lastRSSI = nil
        batteryLevel = nil
        state = .disconnected
        simulationMode = .live  // Reset to live mode on disconnect
        notifyObservers()
    }
    
    // MARK: - Simulation Mode (RL-MODE-001)
    
    /// Set simulation mode explicitly
    /// - Parameter mode: The simulation mode to use
    public func setSimulationMode(_ mode: SimulationMode) {
        let previous = simulationMode
        simulationMode = mode
        if previous != mode {
            RileyLinkLogger.connection.info("Simulation mode changed: \(previous.rawValue) → \(mode.rawValue)")
        }
    }
    
    /// Enable demo mode for UI testing (convenience method)
    public func enableDemoMode() {
        setSimulationMode(.demo)
    }
    
    /// Enable live mode for real device communication (convenience method)  
    public func enableLiveMode() {
        setSimulationMode(.live)
    }
    
    /// Enable test mode for instant responses (WIRE-011)
    public func enableTestMode() {
        setSimulationMode(.test)
    }
    
    /// Conditional delay based on simulation mode (WIRE-011)
    /// Skips delay in test mode for faster test execution
    private func simulationDelay(nanoseconds: UInt64) async throws {
        try await simulationMode.delay(nanoseconds: nanoseconds)
    }
    
    // MARK: - RF Operations
    
    /// Get firmware version (RL-DEBUG-004)
    /// Public method to verify basic BLE response pattern works before RF commands
    /// Returns the detected firmware version string, or nil if detection failed
    public func getFirmwareVersion() async -> String? {
        // RL-DEBUG-009: Log entry to getFirmwareVersion
        RileyLinkLogger.connection.info("getFirmwareVersion() called - current version: \(self.detectedFirmwareVersion.description)")
        await detectFirmwareVersion()
        // Return raw firmware string if available (like RileyLink Playground does)
        // Fall back to parsed version description if raw string not available
        let result = rawFirmwareString ?? (detectedFirmwareVersion.isUnknown ? nil : detectedFirmwareVersion.description)
        RileyLinkLogger.connection.info("getFirmwareVersion() returning: \(result ?? "nil")")
        return result
    }
    
    /// Set RileyLink LED mode
    /// Trace: RL-WIRE-017
    /// - Parameters:
    ///   - led: Which LED to control (green or blue)
    ///   - mode: LED mode (off, on, or auto)
    public func setLEDMode(led: RileyLinkLEDType, mode: RileyLinkLEDMode) async throws {
        guard state.isConnected else {
            throw RileyLinkError.notConnected
        }
        
        // Use the proper SetLEDModeCommand
        let command = SetLEDModeCommand(led, mode: mode)
        
        guard let peripheral = connectedPeripheral,
              let dataChar = dataCharacteristic else {
            throw RileyLinkError.notConnected
        }
        
        // RL-DEBUG-002/003: Log LED command bytes and state
        RileyLinkLogger.connection.debug("SetLEDMode: \(command.data.hexDump) (\(String(describing: led))=\(String(describing: mode)))")
        
        // SWIFT-RL-001: Write command with length prefix
        let framedData = try prepareForBLEWrite(command.data)
        try await peripheral.writeValue(framedData, for: dataChar, type: .withResponse)
        
        // RL-DEBUG-003: Explain LED meaning for debugging
        if mode == .on || mode == .auto {
            RileyLinkLogger.connection.info("💡 LED \(String(describing: led)) active — blink indicates RF activity")
        }
    }
    
    /// Tune to a specific RF frequency
    public func tune(to frequency: Double) async throws {
        guard state.isConnected else {
            throw RileyLinkError.notConnected
        }
        
        state = .tuning
        notifyObservers()
        
        RileyLinkLogger.signal.frequencyTuned(frequency: frequency, rssi: lastRSSI ?? -100)
        
        // RL-CMD-003: Use UpdateRegister commands to set frequency
        if let peripheral = connectedPeripheral,
           let dataChar = dataCharacteristic {
            do {
                // Calculate CC1110 frequency register values
                let freqRegs = FrequencyRegisters(mhz: frequency)
                
                // Send register update commands
                for command in freqRegs.updateCommands(firmwareVersion: detectedFirmwareVersion) {
                    // RL-DEBUG-002: Log exact bytes being written
                    RileyLinkLogger.signal.debug("UpdateRegister: \(command.data.hexDump)")
                    // SWIFT-RL-001: Write command with length prefix
                    let framedData = try prepareForBLEWrite(command.data)
                    try await peripheral.writeValue(framedData, for: dataChar, type: .withResponse)
                }
                
                RileyLinkLogger.signal.info("Set frequency registers for \(frequency) MHz")
            } catch {
                RileyLinkLogger.signal.warning("Failed to set frequency registers: \(error.localizedDescription)")
                // Continue with simulated tuning
            }
        }
        
        currentFrequency = frequency
        state = .ready
        notifyObservers()
    }
    
    /// Send RF command and receive response
    /// Trace: WIRE-008 (fault injection + metrics)
    public func sendCommand(_ data: Data, frequency: Double? = nil, repeatCount: Int = 0, timeout: TimeInterval? = nil) async throws -> Data {
        let startTime = Date()
        
        // WIRE-008: Check fault injection
        if let injector = faultInjector {
            let result = injector.shouldInject(for: "rileylink.command")
            if case .injected(let fault) = result {
                await metrics.recordCommand("rileylink.command", duration: 0, success: false, pumpType: .medtronic)
                throw mapFaultToError(fault)
            }
        }
        
        guard state == .ready || state == .connected else {
            throw RileyLinkError.notConnected
        }
        
        // Tune if frequency changed
        if let freq = frequency, freq != currentFrequency {
            try await tune(to: freq)
        }
        
        guard currentFrequency != nil else {
            throw RileyLinkError.notTuned
        }
        
        // Use provided timeout or default (this is the RF listen window)
        let rfListenTimeout = timeout ?? responseTimeout
        
        // BLE timeout must account for RF transmission time:
        // - Each packet takes ~2.5ms at 16384 bps
        // - Plus 17ms gap between packets (per RileyLink firmware)
        // - repeatCount=200 → ~4-5 seconds of RF time
        // - Plus RF listen time (rfListenTimeout)
        // - Plus 1 second margin for BLE overhead
        let estimatedRfTxTime = Double(repeatCount) * 0.020  // 20ms per repeat (conservative)
        let bleTimeout = max(5.0, estimatedRfTxTime + rfListenTimeout + 1.0)
        
        // Log transmission
        RileyLinkLogger.tx.packetSent(bytes: data.count, frequency: currentFrequency!)
        RileyLinkLogger.tx.debug("repeatCount=\(repeatCount), rfTimeout=\(rfListenTimeout)s, bleTimeout=\(bleTimeout)s")
        
        // Use real BLE GATT if we have connected peripheral and data characteristic (RL-WIRE-004)
        // RL-POLL-001: Using poll-based reading instead of notifications
        if let peripheral = connectedPeripheral, 
           let dataChar = dataCharacteristic {
            do {
                // RL-CMD-005: Wrap RF packet in SendAndListen command
                // The RileyLink firmware expects command format, not raw RF data
                // RL-CHAN-001/002: Use channel 0 to match Loop (channel 2 causes rxTimeout)
                // RL-REPEAT-001: Pass repeatCount to firmware, don't loop externally
                // SWIFT-RL-006: Assume v2+ format when firmware unknown (all modern devices support it)
                let effectiveFirmware = detectedFirmwareVersion.isUnknown 
                    ? RadioFirmwareVersion.assumeV2  // Assume v2+ for unknown
                    : detectedFirmwareVersion
                let command = SendAndListenCommand(
                    outgoing: data,
                    sendChannel: 0,      // Channel 0 per Loop (not 2!)
                    repeatCount: UInt8(clamping: repeatCount),  // RF repeats handled by firmware
                    delayBetweenPacketsMS: 0,
                    listenChannel: 0,    // Channel 0 per Loop (not 2!)
                    timeoutMS: UInt32(rfListenTimeout * 1000),  // RF listen window
                    retryCount: UInt8(retryCount),
                    preambleExtensionMS: 0,
                    firmwareVersion: effectiveFirmware
                )
                
                // RL-DEBUG-002: Log exact bytes being written to BLE
                RileyLinkLogger.tx.debug("BLE write to 0x0011: \(command.data.hexDump)")
                
                // RL-POLL-002: Read responseCount BEFORE writing command
                // RileyLink increments responseCount when response is ready
                var initialResponseCount: UInt8 = 0
                if let rcChar = responseCountCharacteristic {
                    let rcData = try await peripheral.readValue(for: rcChar)
                    if rcData.count > 0 {
                        initialResponseCount = rcData[0]
                    }
                    RileyLinkLogger.rx.debug("Initial responseCount: \(initialResponseCount)")
                } else {
                    RileyLinkLogger.rx.warning("⚠️ responseCountCharacteristic is nil - will poll data char instead")
                }
                
                // SWIFT-RL-001: Write wrapped command with length prefix to data characteristic
                let framedData = try prepareForBLEWrite(command.data)
                // SWIFT-RL-005: Log framed command for protocol debugging
                let frameHex = framedData.map { String(format: "%02X", $0) }.joined(separator: " ")
                RileyLinkLogger.tx.info("BLE TX framed: [\(frameHex)] (\(framedData.count) bytes)")
                try await peripheral.writeValue(framedData, for: dataChar, type: .withResponse)
                RileyLinkLogger.tx.debug("Command written, waiting for response...")
                
                // RL-NOTIFY-001: Use subscribe stream to wait for responseCount notification
                // This is more reliable than polling - the notification fires when response is ready
                let response: Data
                
                if let rcChar = responseCountCharacteristic {
                    // PROD-HARDEN-021: Use PumpResponsePoller for responseCount polling
                    RileyLinkLogger.rx.debug("Waiting for responseCount notification (timeout: \(bleTimeout)s)...")
                    
                    do {
                        let newRC = try await PumpResponsePoller.pollResponseCount(
                            initialValue: initialResponseCount,
                            timeout: bleTimeout,
                            readValue: { try await peripheral.readValue(for: rcChar) }
                        )
                        RileyLinkLogger.rx.debug("responseCount changed: \(initialResponseCount) -> \(newRC)")
                    } catch let error as PumpTimeoutError {
                        throw RileyLinkError.timeoutWithDetails("responseCount stayed at \(initialResponseCount): \(error.detail ?? "")")
                    }
                    
                    // Read the actual response
                    response = try await peripheral.readValue(for: dataChar)
                } else {
                    // PROD-HARDEN-021: Use PumpResponsePoller for data char polling
                    do {
                        response = try await PumpResponsePoller.pollForResponseCode(
                            timeout: bleTimeout,
                            pollInterval: PumpTimingConstants.dataCharPollInterval,
                            operation: "data characteristic",
                            readValue: { try await peripheral.readValue(for: dataChar) }
                        )
                        if let code = response.first {
                            RileyLinkLogger.rx.debug("Got response code \(String(format: "0x%02X", code))")
                        }
                    } catch let error as PumpTimeoutError {
                        throw RileyLinkError.timeoutWithDetails(error.detail ?? "data char timeout")
                    }
                }
                
                // RL-DEBUG-002: Log response bytes
                RileyLinkLogger.rx.debug("BLE read from 0x0011: \(response.hexDump)")
                
                RileyLinkLogger.rx.packetReceived(bytes: response.count, rssi: lastRSSI ?? -70)
                
                // WIRE-008: Record metrics
                let duration = Date().timeIntervalSince(startTime)
                await metrics.recordCommand("rileylink.command", duration: duration, success: true, pumpType: .medtronic)
                
                return response
            } catch {
                RileyLinkLogger.signal.error("RF TX/RX error: \(error.localizedDescription)")
                // RL-MODE-001: Check simulation mode before falling back
                if simulationMode == .live {
                    // In live mode, throw the error - don't silently fall back
                    throw error
                }
                // In demo or fallback mode, fall through to simulated response
            }
        }
        
        // RL-MODE-001: Only simulate if in demo, fallback, or test mode
        switch simulationMode {
        case .live:
            // No BLE connection and in live mode - this is an error
            RileyLinkLogger.signal.error("❌ LIVE MODE: BLE not connected, cannot simulate")
            throw RileyLinkError.notConnected
            
        case .demo:
            RileyLinkLogger.signal.info("📱 DEMO MODE: Using simulated response (expected)")
            
        case .fallback:
            let peripheralStatus = self.connectedPeripheral == nil ? "nil" : "connected"
            let charStatus = self.dataCharacteristic == nil ? "nil" : "ok"
            RileyLinkLogger.signal.warning("⚠️ FALLBACK MODE: BLE failed, using simulated response (connectedPeripheral=\(peripheralStatus), dataChar=\(charStatus))")
            
        case .test:
            RileyLinkLogger.signal.debug("🧪 TEST MODE: Using instant simulated response")
        }
        
        // WIRE-011: Use simulationDelay for test mode acceleration
        try await simulationDelay(nanoseconds: 100_000_000)
        
        // Simulate response (ACK)
        let response = Data([0x06, data[0], 0x00])
        
        RileyLinkLogger.rx.packetReceived(bytes: response.count, rssi: lastRSSI ?? -70)
        
        // WIRE-008: Record metrics
        let duration = Date().timeIntervalSince(startTime)
        await metrics.recordCommand("rileylink.command", duration: duration, success: true, pumpType: .medtronic)
        
        return response
    }
    
    // MARK: - Send and Listen (RL-PROTO-002)
    
    /// Standard pump response window (200ms per Loop MinimedKit)
    public static let standardPumpResponseWindow: TimeInterval = 0.200
    
    /// Send RF packet and listen for response with retry
    /// Implements the Loop/Trio sendAndListen pattern.
    ///
    /// - Parameters:
    ///   - data: 4b6b encoded packet data to send
    ///   - repeatCount: Number of times to repeat before listening (0 = send once)
    ///   - timeout: Time to listen for response (default 200ms)
    ///   - retryCount: Number of send+listen cycles before giving up
    ///   - frequency: RF frequency (optional, uses current if nil)
    /// - Returns: Decoded response packet data
    /// - Throws: RileyLinkError on timeout or communication failure
    public func sendAndListen(
        _ data: Data,
        repeatCount: Int = 0,
        timeout: TimeInterval = standardPumpResponseWindow,
        retryCount: Int = 3,
        frequency: Double? = nil
    ) async throws -> Data {
        // Tune if frequency specified
        if let freq = frequency, freq != currentFrequency {
            try await tune(to: freq)
        }
        
        var lastError: Error?
        
        for attempt in 0..<max(1, retryCount) {
            do {
                // RL-REPEAT-001: Pass repeatCount to sendCommand, not loop externally
                // RileyLink firmware handles the repeats internally via RF
                let response = try await sendCommand(data, repeatCount: repeatCount, timeout: timeout)
                
                RileyLinkLogger.rx.debug("sendAndListen success on attempt \(attempt + 1)")
                return response
                
            } catch {
                lastError = error
                RileyLinkLogger.protocol_.debug("sendAndListen attempt \(attempt + 1) failed: \(error)")
                
                // PROD-HARDEN-021: Use constant for retry backoff
                if attempt < retryCount - 1 {
                    try? await Task.sleep(nanoseconds: PumpTimingConstants.responseCountPollIntervalNanos)
                }
            }
        }
        
        throw lastError ?? RileyLinkError.communicationFailed
    }
    
    /// Listen for a response packet with timeout
    /// RL-POLL-001: Poll-based reading instead of notifications
    /// PROD-HARDEN-021: Refactored to use PumpResponsePoller
    private func listenForResponse(timeout: TimeInterval) async throws -> Data {
        // Use real BLE if connected
        if let peripheral = connectedPeripheral, 
           let dataChar = dataCharacteristic {
            
            // Get initial responseCount
            var initialResponseCount: UInt8 = 0
            if let rcChar = responseCountCharacteristic {
                let rcData = try await peripheral.readValue(for: rcChar)
                if rcData.count > 0 {
                    initialResponseCount = rcData[0]
                }
            }
            
            // PROD-HARDEN-021: Use PumpResponsePoller
            if let rcChar = responseCountCharacteristic {
                do {
                    _ = try await PumpResponsePoller.pollResponseCount(
                        initialValue: initialResponseCount,
                        timeout: timeout,
                        pollInterval: PumpTimingConstants.dataCharPollInterval,
                        readValue: { try await peripheral.readValue(for: rcChar) }
                    )
                    // Response ready - read data
                    let data = try await peripheral.readValue(for: dataChar)
                    if data.count > 0 && data[0] == 0xDD {
                        return data
                    }
                    throw RileyLinkError.timeout  // Non-DD response
                } catch is PumpTimeoutError {
                    throw RileyLinkError.timeout
                }
            }
            throw RileyLinkError.timeout
        }
        
        // Simulated response for testing/demo (WIRE-010: use simulationDelay)
        try await simulationDelay(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw RileyLinkError.timeout  // Simulate no response in demo mode
    }
    
    /// Send Medtronic command with retry logic
    /// Uses 4b6b encoding per RL-PROTO-001 and sendAndListen per RL-PROTO-002
    public func sendMedtronicCommand(
        pumpId: String,
        opcode: UInt8,
        params: Data = Data(),
        frequency: Double,
        repeatCount: Int = 0,
        timeout: TimeInterval = standardPumpResponseWindow
    ) async throws -> Data {
        // Parse pump ID as 3 hex bytes (e.g., "A71234" → [0xA7, 0x12, 0x34])
        guard pumpId.count == 6 else {
            throw RileyLinkError.invalidPumpId
        }
        var pumpIdBytes = Data()
        var idx = pumpId.startIndex
        for _ in 0..<3 {
            let nextIdx = pumpId.index(idx, offsetBy: 2)
            guard let byte = UInt8(pumpId[idx..<nextIdx], radix: 16) else {
                throw RileyLinkError.invalidPumpId
            }
            pumpIdBytes.append(byte)
            idx = nextIdx
        }
        
        // Build raw packet: [packetType][address 3B][opcode][body]
        // PacketType 0xA7 = carelink (standard pump command)
        // SWIFT-RL-002: Body MUST be at least 1 byte (CarelinkShortMessageBody = 0x00)
        // Loop's MinimedKit always includes body, even if just [0x00] for read commands
        var rawPacket = Data()
        rawPacket.append(0xA7)  // PacketType.carelink
        rawPacket.append(pumpIdBytes)
        rawPacket.append(opcode)
        // If no params provided, use [0x00] as CarelinkShortMessageBody
        rawPacket.append(params.isEmpty ? Data([0x00]) : params)
        
        // 4b6b encode with CRC (RL-PROTO-001)
        let minimedPacket = MinimedPacket(outgoingData: rawPacket)
        let encodedPacket = minimedPacket.encodedData()
        
        RileyLinkLogger.tx.debug("TX 4b6b: \(rawPacket.count)B raw → \(encodedPacket.count)B encoded, opcode=0x\(String(format: "%02X", opcode))")
        
        // Use sendAndListen for proper send→listen flow (RL-PROTO-002)
        let response = try await sendAndListen(
            encodedPacket,
            repeatCount: repeatCount,
            timeout: timeout,
            retryCount: retryCount,
            frequency: frequency
        )
        
        // Decode 4b6b response
        if let decoded = MinimedPacket(encodedData: response) {
            RileyLinkLogger.rx.debug("RX 4b6b: \(response.count)B encoded → \(decoded.data.count)B raw")
            return decoded.data
        } else {
            // Response may not be 4b6b encoded (e.g., raw ACK)
            return response
        }
    }
    
    /// Send Medtronic message and return parsed response (RL-PROTO-003/004)
    /// Validates address match and extracts message body
    public func sendMessage(
        _ message: PumpMessage,
        frequency: Double,
        repeatCount: Int = 0,
        timeout: TimeInterval = standardPumpResponseWindow
    ) async throws -> PumpMessage {
        // Encode message with 4b6b
        let packet = MinimedPacket(outgoingData: message.txData)
        let encoded = packet.encodedData()
        
        // SWIFT-RL-004: Log raw bytes for protocol debugging
        let rawHex = message.txData.map { String(format: "%02X", $0) }.joined(separator: " ")
        RileyLinkLogger.tx.info("TX \(message.messageType.displayName): raw=[\(rawHex)] (\(message.txData.count)B → \(encoded.count)B encoded)")
        
        // Send and receive
        let response = try await sendAndListen(
            encoded,
            repeatCount: repeatCount,
            timeout: timeout,
            retryCount: retryCount,
            frequency: frequency
        )
        
        // Decode response
        guard let decodedPacket = MinimedPacket(encodedData: response) else {
            throw RileyLinkError.invalidResponse("Could not decode 4b6b response")
        }
        
        // Parse as PumpMessage
        guard let responseMsg = PumpMessage(rxData: decodedPacket.data) else {
            throw RileyLinkError.invalidResponse("Could not parse pump message")
        }
        
        // Validate address matches (RL-PROTO-004)
        guard responseMsg.address == message.address else {
            throw RileyLinkError.crosstalk(expected: message.addressHex, received: responseMsg.addressHex)
        }
        
        // Check for error response
        if responseMsg.messageType == .errorResponse {
            throw RileyLinkError.pumpError(code: responseMsg.body.first ?? 0)
        }
        
        RileyLinkLogger.rx.debug("RX \(responseMsg.messageType.displayName): \(responseMsg.body.count)B body")
        
        return responseMsg
    }
    
    /// Send message and extract validated body data (RL-PROTO-004/005)
    /// Validates expected response type and length
    public func sendAndGetBody(
        _ message: PumpMessage,
        expectedType: MessageType,
        expectedLength: Int? = nil,
        frequency: Double,
        repeatCount: Int = 0,
        timeout: TimeInterval = standardPumpResponseWindow
    ) async throws -> Data {
        let response = try await sendMessage(
            message,
            frequency: frequency,
            repeatCount: repeatCount,
            timeout: timeout
        )
        
        // Validate response type
        guard response.messageType == expectedType || response.messageType == .pumpAck else {
            throw RileyLinkError.unexpectedResponse(
                expected: expectedType.displayName,
                received: response.messageType.displayName
            )
        }
        
        // Validate response length if specified (RL-PROTO-004)
        if let expected = expectedLength {
            guard response.body.count >= expected else {
                throw RileyLinkError.invalidResponse(
                    "Response too short: \(response.body.count) bytes, expected \(expected)"
                )
            }
        }
        
        return response.body
    }
    
    // MARK: - Observers
    
    /// Add observer for state changes
    @discardableResult
    public func addObserver(_ handler: @escaping (RileyLinkConnectionState) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }
    
    /// Remove observer
    public func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }
    
    private func notifyObservers() {
        for handler in observers.values {
            handler(state)
        }
    }
    
    // MARK: - BLE Command Framing (SWIFT-RL-001)
    
    /// Prepare command data with length prefix for RileyLink BLE writes.
    /// RileyLink firmware expects: [length byte][command bytes...]
    /// This matches Loop's `writableData()` pattern in PeripheralManager+RileyLink.swift:174
    private func prepareForBLEWrite(_ data: Data) throws -> Data {
        guard data.count <= 220 else {
            throw RileyLinkError.commandTooLong(size: data.count, maxSize: 220)
        }
        var framedData = data
        framedData.insert(UInt8(clamping: data.count), at: 0)
        return framedData
    }
    
    // MARK: - Diagnostics
    
    /// Get diagnostic info
    public func diagnosticInfo() -> RileyLinkDiagnostics {
        RileyLinkDiagnostics(
            state: state,
            connectedDevice: connectedDevice,
            currentFrequency: currentFrequency,
            lastRSSI: lastRSSI,
            batteryLevel: batteryLevel,
            discoveredDeviceCount: discoveredDevices.count
        )
    }
    
    // MARK: - Fault Handling (WIRE-008)
    
    /// Map fault type to RileyLink error
    private func mapFaultToError(_ fault: PumpFaultType) -> Error {
        switch fault {
        case .connectionDrop, .connectionTimeout:
            return RileyLinkError.deviceNotFound
        case .communicationError, .bleDisconnectMidCommand:
            return RileyLinkError.communicationFailed
        case .packetCorruption:
            return RileyLinkError.invalidResponse("Packet corruption injected")
        default:
            return RileyLinkError.communicationFailed
        }
    }
}

// MARK: - RileyLink Diagnostics

/// Diagnostic information about RileyLink connection
public struct RileyLinkDiagnostics: Sendable {
    public let state: RileyLinkConnectionState
    public let connectedDevice: RileyLinkDevice?
    public let currentFrequency: Double?
    public let lastRSSI: Int?
    public let batteryLevel: Int?
    public let discoveredDeviceCount: Int
    
    public var description: String {
        var lines: [String] = []
        lines.append("State: \(state.rawValue)")
        if let device = connectedDevice {
            lines.append("Device: \(device.displayName)")
            lines.append("Type: \(device.deviceType.rawValue)")
        }
        if let freq = currentFrequency {
            lines.append("Frequency: \(String(format: "%.2f", freq)) MHz")
        }
        if let rssi = lastRSSI {
            lines.append("RSSI: \(rssi) dBm")
        }
        if let battery = batteryLevel {
            lines.append("Battery: \(battery)%")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - RileyLink Errors

/// RileyLink-specific errors
public enum RileyLinkError: Error, Sendable, Equatable {
    case deviceNotFound
    case alreadyConnected
    case notConnected
    case notTuned
    case invalidPumpId
    case communicationFailed
    case timeout
    case timeoutWithDetails(String)  // RL-DEBUG-003: Timeout with debug info
    case invalidResponse(String)
    case bleNotAvailable
    case bleNotAuthorized
    // RL-PROTO-004: Response validation errors
    case crosstalk(expected: String, received: String)
    case unexpectedResponse(expected: String, received: String)
    case pumpError(code: UInt8)
    // SWIFT-RL-001: Command size validation
    case commandTooLong(size: Int, maxSize: Int)
}

extension RileyLinkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "RileyLink device not found"
        case .alreadyConnected:
            return "Already connected to a RileyLink"
        case .notConnected:
            return "Not connected to RileyLink"
        case .notTuned:
            return "RF frequency not tuned"
        case .invalidPumpId:
            return "Invalid pump ID format"
        case .communicationFailed:
            return "RF communication failed"
        case .timeout:
            return "Command timed out"
        case .timeoutWithDetails(let details):
            return "Timeout: \(details)"
        case .invalidResponse(let reason):
            return "Invalid response: \(reason)"
        case .bleNotAvailable:
            return "Bluetooth is not available"
        case .bleNotAuthorized:
            return "Bluetooth permission not granted"
        case .crosstalk(let expected, let received):
            return "Crosstalk detected: expected \(expected), received \(received)"
        case .unexpectedResponse(let expected, let received):
            return "Unexpected response: expected \(expected), received \(received)"
        case .pumpError(let code):
            return "Pump error: 0x\(String(format: "%02X", code))"
        case .commandTooLong(let size, let maxSize):
            return "Command too long: \(size) bytes exceeds max \(maxSize)"
        }
    }
}

// MARK: - BLE Service UUIDs

/// RileyLink BLE service and characteristic UUIDs
public struct RileyLinkBLEUUIDs {
    /// Main RileyLink service
    public static let service = "0235733B-99C5-4197-B856-69219C2A3845"
    
    /// Data characteristic (TX/RX)
    public static let data = "C842E849-5028-42E2-867C-016ADADA9155"
    
    /// Response count characteristic
    public static let responseCount = "6E6C7910-B89E-43A5-A0FE-50C5E2B81F4A"
    
    /// Timer tick characteristic
    public static let timerTick = "6E6C7910-B89E-43A5-78AF-50C5E2B86F7E"
    
    /// Custom name characteristic
    public static let customName = "D93B2AF0-1E28-11E4-8C21-0800200C9A66"
    
    /// Firmware version characteristic
    public static let firmwareVersion = "30D99DC9-7C91-4295-A051-0A104D238CF2"
    
    /// Battery service
    public static let batteryService = "180F"
    
    /// Battery level characteristic
    public static let batteryLevel = "2A19"
}

// MARK: - Data Hex Dump Extension (RL-DEBUG-002)

extension Data {
    /// Returns a hex dump string for debugging BLE writes
    var hexDump: String {
        if isEmpty { return "(empty)" }
        let hex = map { String(format: "%02X", $0) }.joined(separator: " ")
        return "[\(count)B] \(hex)"
    }
}
