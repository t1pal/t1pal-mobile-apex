// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BackgroundBLEManager.swift
// BLEKit
//
// Manages BLE connections in iOS background mode with state restoration.
// Trace: PRD-004, REQ-CGM-005, APP-CGM-002

import Foundation

#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
#endif

// MARK: - Background BLE Configuration

/// Configuration for background BLE operation
public struct BackgroundBLEConfig: Codable, Sendable {
    /// Restoration identifier for state preservation
    public let restorationIdentifier: String
    
    /// Service UUIDs to filter during background scanning
    public let serviceUUIDs: [String]
    
    /// Whether to automatically reconnect on disconnect
    public let autoReconnect: Bool
    
    /// Maximum reconnection attempts before giving up
    public let maxReconnectAttempts: Int
    
    /// Delay between reconnection attempts in seconds
    public let reconnectDelaySeconds: TimeInterval
    
    /// Whether to scan in background after losing connection
    public let backgroundScanOnDisconnect: Bool
    
    public init(
        restorationIdentifier: String = "com.t1pal.cgm.ble",
        serviceUUIDs: [String] = [],
        autoReconnect: Bool = true,
        maxReconnectAttempts: Int = 10,
        reconnectDelaySeconds: TimeInterval = 5.0,
        backgroundScanOnDisconnect: Bool = true
    ) {
        self.restorationIdentifier = restorationIdentifier
        self.serviceUUIDs = serviceUUIDs
        self.autoReconnect = autoReconnect
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectDelaySeconds = reconnectDelaySeconds
        self.backgroundScanOnDisconnect = backgroundScanOnDisconnect
    }
    
    public static let `default` = BackgroundBLEConfig()
    
    /// Config for CGM monitoring
    public static let cgm = BackgroundBLEConfig(
        restorationIdentifier: "com.t1pal.cgm.ble",
        serviceUUIDs: [
            "FEBC", // Dexcom G6/G7 advertisement
            "FDE3", // Libre
        ],
        autoReconnect: true,
        maxReconnectAttempts: 20,
        reconnectDelaySeconds: 3.0,
        backgroundScanOnDisconnect: true
    )
}

// MARK: - Connection State

/// State of a background BLE connection
public enum BackgroundConnectionState: Sendable, Equatable {
    /// Not connected, not attempting
    case disconnected
    
    /// Scanning for device
    case scanning
    
    /// Connecting to device
    case connecting(peripheralId: String)
    
    /// Connected and active
    case connected(peripheralId: String)
    
    /// Reconnecting after disconnect
    case reconnecting(attempt: Int, maxAttempts: Int)
    
    /// Connection interrupted (e.g., by phone call)
    case interrupted(reason: String)
    
    /// Failed to connect after max attempts
    case failed(reason: String)
    
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    
    public var isActive: Bool {
        switch self {
        case .scanning, .connecting, .connected, .reconnecting:
            return true
        default:
            return false
        }
    }
    
    public var description: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .scanning:
            return "Scanning..."
        case .connecting(let id):
            return "Connecting to \(id.prefix(8))..."
        case .connected(let id):
            return "Connected to \(id.prefix(8))"
        case .reconnecting(let attempt, let max):
            return "Reconnecting (\(attempt)/\(max))..."
        case .interrupted(let reason):
            return "Interrupted: \(reason)"
        case .failed(let reason):
            return "Failed: \(reason)"
        }
    }
}

// MARK: - BLEConnectionStateConvertible (COMPL-DUP-001)

extension BackgroundConnectionState: BLEConnectionStateConvertible {
    public var bleConnectionState: BLEConnectionState {
        switch self {
        case .disconnected, .interrupted, .failed:
            return .disconnected
        case .scanning:
            return .scanning
        case .connecting, .reconnecting:
            return .connecting
        case .connected:
            return .connected
        }
    }
}

// MARK: - Restoration State

/// State preserved during app termination/restoration
public struct BLERestorationState: Codable, Sendable {
    /// Peripheral identifiers that were connected
    public let connectedPeripheralIds: [String]
    
    /// Peripheral identifiers that were connecting
    public let connectingPeripheralIds: [String]
    
    /// Services that were being scanned
    public let scanningServiceUUIDs: [String]
    
    /// Timestamp of preservation
    public let timestamp: Date
    
    public init(
        connectedPeripheralIds: [String] = [],
        connectingPeripheralIds: [String] = [],
        scanningServiceUUIDs: [String] = [],
        timestamp: Date = Date()
    ) {
        self.connectedPeripheralIds = connectedPeripheralIds
        self.connectingPeripheralIds = connectingPeripheralIds
        self.scanningServiceUUIDs = scanningServiceUUIDs
        self.timestamp = timestamp
    }
}

// MARK: - Background BLE Manager

/// Manager for background BLE operations with state restoration
///
/// Handles:
/// - iOS state restoration after app termination
/// - Automatic reconnection after disconnects
/// - Background scanning for lost devices
/// - Connection interruption handling
#if canImport(CoreBluetooth)
public actor BackgroundBLEManager: NSObject {
    
    // MARK: - Properties
    
    private let config: BackgroundBLEConfig
    private var centralManager: CBCentralManager!
    private let delegate: BackgroundBLEDelegate
    
    private var connectionState: BackgroundConnectionState = .disconnected
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]
    private var reconnectAttempts: Int = 0
    private var lastKnownPeripheralId: UUID?
    
    // MARK: - Callbacks
    
    /// Called when connection state changes
    public var onStateChanged: (@Sendable (BackgroundConnectionState) -> Void)?
    
    /// Called when state restoration occurs
    public var onRestoration: (@Sendable (BLERestorationState) -> Void)?
    
    /// Called when a peripheral connects
    public var onPeripheralConnected: (@Sendable (String) -> Void)?
    
    /// Called when a peripheral disconnects
    public var onPeripheralDisconnected: (@Sendable (String, Error?) -> Void)?
    
    /// Called when data is received from peripheral
    public var onDataReceived: (@Sendable (String, Data) -> Void)?
    
    // MARK: - Public State
    
    /// Current connection state
    public var state: BackgroundConnectionState {
        connectionState
    }
    
    /// Whether background mode is active
    public var isBackgroundModeActive: Bool {
        connectionState.isActive
    }
    
    /// Connected peripheral identifiers
    public var connectedPeripheralIds: [String] {
        connectedPeripherals.keys.map { $0.uuidString }
    }
    
    // MARK: - Initialization
    
    public init(config: BackgroundBLEConfig = .cgm) {
        self.config = config
        self.delegate = BackgroundBLEDelegate()
        super.init()
        
        // Create central manager with restoration identifier
        Task { await setupCentralManager() }
    }
    
    private func setupCentralManager() {
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: config.restorationIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        
        // CBCentralManager MUST be created on main thread (ARCH-IMPL-002)
        if Thread.isMainThread {
            centralManager = CBCentralManager(
                delegate: delegate,
                queue: DispatchQueue.main,
                options: options
            )
        } else {
            DispatchQueue.main.sync {
                centralManager = CBCentralManager(
                    delegate: delegate,
                    queue: DispatchQueue.main,
                    options: options
                )
            }
        }
        
        setupDelegateCallbacks()
    }
    
    private func setupDelegateCallbacks() {
        delegate.onStateUpdate = { [weak self] state in
            Task { await self?.handleCentralStateUpdate(state) }
        }
        
        delegate.onWillRestoreState = { [weak self] dict in
            Task { await self?.handleWillRestoreState(dict) }
        }
        
        delegate.onPeripheralConnected = { [weak self] peripheral in
            Task { await self?.handlePeripheralConnected(peripheral) }
        }
        
        delegate.onPeripheralDisconnected = { [weak self] peripheral, error in
            Task { await self?.handlePeripheralDisconnected(peripheral, error: error) }
        }
        
        delegate.onPeripheralDiscovered = { [weak self] peripheral, advertisementData, rssi in
            Task { await self?.handlePeripheralDiscovered(peripheral, advertisementData: advertisementData, rssi: rssi) }
        }
    }
    
    // MARK: - Public API
    
    /// Start background BLE monitoring
    /// - Parameter peripheralId: Optional specific peripheral to connect to
    public func start(peripheralId: String? = nil) async {
        if let id = peripheralId, let uuid = UUID(uuidString: id) {
            lastKnownPeripheralId = uuid
            await connectToKnownPeripheral(uuid)
        } else {
            await startScanning()
        }
    }
    
    /// Stop background BLE monitoring
    public func stop() async {
        centralManager.stopScan()
        
        for (_, peripheral) in connectedPeripherals {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        connectedPeripherals.removeAll()
        connectionState = .disconnected
        reconnectAttempts = 0
        onStateChanged?(connectionState)
    }
    
    /// Attempt immediate reconnection
    public func reconnect() async {
        guard let peripheralId = lastKnownPeripheralId else {
            await startScanning()
            return
        }
        
        reconnectAttempts = 0
        await connectToKnownPeripheral(peripheralId)
    }
    
    // MARK: - Callback Setters
    
    /// Set callback for state changes (actor-safe)
    public func setStateCallback(_ callback: @escaping @Sendable (BackgroundConnectionState) -> Void) {
        self.onStateChanged = callback
    }
    
    /// Set callback for data received (actor-safe)
    public func setDataCallback(_ callback: @escaping @Sendable (String, Data) -> Void) {
        self.onDataReceived = callback
    }
    
    /// Set callback for restoration events (actor-safe)
    public func setRestorationCallback(_ callback: @escaping @Sendable (BLERestorationState) -> Void) {
        self.onRestoration = callback
    }
    
    // MARK: - Private Methods
    
    private func startScanning() async {
        guard centralManager.state == .poweredOn else {
            connectionState = .disconnected
            onStateChanged?(connectionState)
            return
        }
        
        connectionState = .scanning
        onStateChanged?(connectionState)
        
        let serviceUUIDs = config.serviceUUIDs.compactMap { CBUUID(string: $0) }
        let scanOptions: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        
        centralManager.scanForPeripherals(
            withServices: serviceUUIDs.isEmpty ? nil : serviceUUIDs,
            options: scanOptions
        )
    }
    
    private func connectToKnownPeripheral(_ uuid: UUID) async {
        guard centralManager.state == .poweredOn else {
            connectionState = .disconnected
            onStateChanged?(connectionState)
            return
        }
        
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        
        if let peripheral = peripherals.first {
            connectionState = .connecting(peripheralId: uuid.uuidString)
            onStateChanged?(connectionState)
            centralManager.connect(peripheral, options: nil)
        } else {
            // Peripheral not known, try scanning
            await startScanning()
        }
    }
    
    private func scheduleReconnect() async {
        guard config.autoReconnect else {
            connectionState = .failed(reason: "Auto-reconnect disabled")
            onStateChanged?(connectionState)
            return
        }
        
        guard reconnectAttempts < config.maxReconnectAttempts else {
            connectionState = .failed(reason: "Max reconnection attempts reached")
            onStateChanged?(connectionState)
            return
        }
        
        reconnectAttempts += 1
        connectionState = .reconnecting(attempt: reconnectAttempts, maxAttempts: config.maxReconnectAttempts)
        onStateChanged?(connectionState)
        
        try? await Task.sleep(nanoseconds: UInt64(config.reconnectDelaySeconds * 1_000_000_000))
        
        if let peripheralId = lastKnownPeripheralId {
            await connectToKnownPeripheral(peripheralId)
        } else if config.backgroundScanOnDisconnect {
            await startScanning()
        }
    }
    
    // MARK: - Delegate Handlers
    
    private func handleCentralStateUpdate(_ state: CBManagerState) async {
        switch state {
        case .poweredOn:
            // Resume operations if we have a known peripheral
            if let peripheralId = lastKnownPeripheralId, !connectionState.isConnected {
                await connectToKnownPeripheral(peripheralId)
            }
            
        case .poweredOff:
            connectionState = .interrupted(reason: "Bluetooth powered off")
            onStateChanged?(connectionState)
            
        case .unauthorized:
            connectionState = .failed(reason: "Bluetooth unauthorized")
            onStateChanged?(connectionState)
            
        default:
            break
        }
    }
    
    private func handleWillRestoreState(_ dict: [String: Any]) async {
        var restorationState = BLERestorationState()
        
        // Restore connected peripherals
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            let connectedIds = peripherals.map { $0.identifier.uuidString }
            restorationState = BLERestorationState(
                connectedPeripheralIds: connectedIds,
                timestamp: Date()
            )
            
            for peripheral in peripherals {
                connectedPeripherals[peripheral.identifier] = peripheral
                lastKnownPeripheralId = peripheral.identifier
                connectionState = .connected(peripheralId: peripheral.identifier.uuidString)
            }
        }
        
        // Restore scan services
        if let services = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            restorationState = BLERestorationState(
                connectedPeripheralIds: restorationState.connectedPeripheralIds,
                scanningServiceUUIDs: services.map { $0.uuidString },
                timestamp: Date()
            )
        }
        
        onRestoration?(restorationState)
        onStateChanged?(connectionState)
    }
    
    private func handlePeripheralConnected(_ peripheral: CBPeripheral) async {
        connectedPeripherals[peripheral.identifier] = peripheral
        lastKnownPeripheralId = peripheral.identifier
        reconnectAttempts = 0
        
        connectionState = .connected(peripheralId: peripheral.identifier.uuidString)
        onStateChanged?(connectionState)
        onPeripheralConnected?(peripheral.identifier.uuidString)
        
        // Stop scanning once connected
        centralManager.stopScan()
    }
    
    private func handlePeripheralDisconnected(_ peripheral: CBPeripheral, error: Error?) async {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        
        onPeripheralDisconnected?(peripheral.identifier.uuidString, error)
        
        // Attempt reconnection
        await scheduleReconnect()
    }
    
    private func handlePeripheralDiscovered(
        _ peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) async {
        // If scanning for any device, connect to first found
        // In production, you'd have more sophisticated filtering
        if case .scanning = connectionState {
            centralManager.stopScan()
            lastKnownPeripheralId = peripheral.identifier
            connectionState = .connecting(peripheralId: peripheral.identifier.uuidString)
            onStateChanged?(connectionState)
            centralManager.connect(peripheral, options: nil)
        }
    }
}

// MARK: - Background BLE Delegate

private final class BackgroundBLEDelegate: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    
    var onStateUpdate: ((CBManagerState) -> Void)?
    var onWillRestoreState: (([String: Any]) -> Void)?
    var onPeripheralConnected: ((CBPeripheral) -> Void)?
    var onPeripheralDisconnected: ((CBPeripheral, Error?) -> Void)?
    var onPeripheralDiscovered: ((CBPeripheral, [String: Any], NSNumber) -> Void)?
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateUpdate?(central.state)
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        onWillRestoreState?(dict)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onPeripheralConnected?(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onPeripheralDisconnected?(peripheral, error)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onPeripheralDisconnected?(peripheral, error)
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        onPeripheralDiscovered?(peripheral, advertisementData, RSSI)
    }
}
#endif

// MARK: - Cross-Platform Stub

#if !canImport(CoreBluetooth)
/// Stub for non-Darwin platforms
public actor BackgroundBLEManager {
    
    public var onStateChanged: (@Sendable (BackgroundConnectionState) -> Void)?
    public var onRestoration: (@Sendable (BLERestorationState) -> Void)?
    public var onPeripheralConnected: (@Sendable (String) -> Void)?
    public var onPeripheralDisconnected: (@Sendable (String, Error?) -> Void)?
    public var onDataReceived: (@Sendable (String, Data) -> Void)?
    
    public var state: BackgroundConnectionState { .disconnected }
    public var isBackgroundModeActive: Bool { false }
    public var connectedPeripheralIds: [String] { [] }
    
    public init(config: BackgroundBLEConfig = .cgm) {}
    
    public func start(peripheralId: String? = nil) async {}
    public func stop() async {}
    public func reconnect() async {}
    
    public func setStateCallback(_ callback: @escaping @Sendable (BackgroundConnectionState) -> Void) {
        self.onStateChanged = callback
    }
    
    public func setDataCallback(_ callback: @escaping @Sendable (String, Data) -> Void) {
        self.onDataReceived = callback
    }
    
    public func setRestorationCallback(_ callback: @escaping @Sendable (BLERestorationState) -> Void) {
        self.onRestoration = callback
    }
}
#endif
