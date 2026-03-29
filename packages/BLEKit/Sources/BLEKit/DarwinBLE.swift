// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DarwinBLE.swift
// BLEKit
//
// iOS/macOS Bluetooth Low Energy implementation using CoreBluetooth.
// Only compiled on Darwin platforms.
// Trace: PRD-008 REQ-BLE-004

#if canImport(CoreBluetooth)

import Foundation
@preconcurrency import CoreBluetooth

// MARK: - Darwin BLE Central

/// iOS/macOS BLE Central implementation using CoreBluetooth
///
/// Thread-safe wrapper for `CBCentralManager` conforming to `BLECentralProtocol`.
/// Uses Loop/Trio pattern: dedicated DispatchQueue + sync initialization.
///
/// **Thread Safety** (BLE-ARCH-001):
/// - All CBCentralManager operations run on `centralQueue`
/// - Mutable state protected by `stateLock`
/// - `dispatchPrecondition` guards validate queue context
///
/// **Features**:
/// - State restoration for iOS background operation
/// - Async scanning with service filtering
/// - Connection management with timeout
/// - Automatic delegate bridging
///
/// Trace: PRD-008 REQ-BLE-004, BLE-ARCH-001-004
public final class DarwinBLECentral: NSObject, BLECentralProtocol, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var centralManager: CBCentralManager!
    private let delegate: CentralDelegate
    
    /// Dedicated queue for CBCentralManager (Loop/Trio pattern - BLE-ARCH-002)
    private let centralQueue: DispatchQueue
    
    /// Lock for mutable state (replaces actor isolation)
    private let stateLock = NSLock()
    
    private var stateStreamContinuation: AsyncStream<BLECentralState>.Continuation?
    private var scanContinuation: AsyncThrowingStream<BLEScanResult, Error>.Continuation?
    private var pendingConnections: [UUID: CheckedContinuation<any BLEPeripheralProtocol, Error>] = [:]
    private var connectedPeripherals: [UUID: DarwinBLEPeripheral] = [:]
    
    /// G6-COEX-018: Restored peripheral UUIDs from iOS state restoration
    private var restoredPeripheralIds: [UUID] = []
    
    /// G6-COEX-019: Service UUIDs being scanned when app was terminated
    private var restoredScanServices: [BLEUUID]?
    
    /// G6-COEX-018: Callback for state restoration events
    /// Called when iOS restores BLE state after app relaunch from background
    public var onStateRestored: ((_ restoredPeripherals: [BLEPeripheralInfo], _ scanServices: [BLEUUID]?) -> Void)?
    
    /// G7-PASSIVE-003: Connection events stream continuation
    private var connectionEventsContinuation: AsyncStream<BLEConnectionEvent>.Continuation?
    
    // MARK: - BLECentralProtocol
    
    public var state: BLECentralState {
        get async {
            centralQueue.sync { mapState(centralManager.state) }
        }
    }
    
    public var stateUpdates: AsyncStream<BLECentralState> {
        AsyncStream { [weak self] continuation in
            self?.setStateStreamContinuation(continuation)
        }
    }
    
    /// G7-PASSIVE-003: Stream of connection events from other apps
    /// WARNING: This is a computed property that creates a new stream each time.
    /// For time-critical coexistence, use prepareConnectionEventsStream() instead.
    public var connectionEvents: AsyncStream<BLEConnectionEvent> {
        AsyncStream { [weak self] continuation in
            self?.setConnectionEventsContinuation(continuation)
        }
    }
    
    /// G7-COEX-TIMING-001: Prepare connection events stream SYNCHRONOUSLY
    /// This avoids the race condition where Task body hasn't run before the event fires.
    /// The continuation is registered immediately in the closure, not in a queued Task.
    ///
    /// Usage:
    ///   let stream = central.prepareConnectionEventsStream()
    ///   await central.registerForConnectionEvents(matchingServices: [...])
    ///   // Now iterate - continuation is already set
    ///   for await event in stream { ... }
    public func prepareConnectionEventsStream() -> AsyncStream<BLEConnectionEvent> {
        AsyncStream { [weak self] continuation in
            // Register synchronously in the closure - NOT in a Task
            self?.setConnectionEventsContinuation(continuation)
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize DarwinBLE central synchronously.
    /// iOS 26 requires CBCentralManager to be created from synchronous main runloop context,
    /// NOT from async/await contexts (even MainActor.run fails).
    /// 
    /// Use from: App init, @main, viewDidLoad, or other synchronous UIKit contexts.
    /// Do NOT use from: Task { }, async functions, or actor methods.
    /// Trace: BLE-ARCH-001, BLE-ARCH-002, RL-WIRE-008
    public init(options: BLECentralOptions = .default) {
        // Create dedicated queue for all BLE callbacks (Loop/Trio pattern)
        let queue = DispatchQueue(label: "com.t1pal.BLEKit.centralQueue", qos: .userInitiated)
        self.centralQueue = queue
        self.delegate = CentralDelegate()
        
        super.init()
        
        var cbOptions: [String: Any] = [:]
        if options.showPowerAlert {
            cbOptions[CBCentralManagerOptionShowPowerAlertKey] = true
        }
        if let restorationId = options.restorationIdentifier {
            cbOptions[CBCentralManagerOptionRestoreIdentifierKey] = restorationId
        }
        
        // BLE-ARCH-002: iOS 26 requires synchronous main thread context
        // Must NOT be called from async context (Task, MainActor.run, etc.)
        precondition(Thread.isMainThread, "DarwinBLECentral must be initialized on main thread")
        
        self.centralManager = CBCentralManager(
            delegate: self.delegate,
            queue: queue,  // Delegate callbacks go to dedicated queue
            options: cbOptions.isEmpty ? nil : cbOptions
        )
        
        setupDelegateCallbacks()
    }
    
    private func setStateStreamContinuation(_ continuation: AsyncStream<BLECentralState>.Continuation) {
        stateLock.withLock {
            self.stateStreamContinuation = continuation
        }
        let currentState = centralQueue.sync { mapState(centralManager.state) }
        continuation.yield(currentState)
    }
    
    private func setupDelegateCallbacks() {
        delegate.onStateUpdate = { [weak self] state in
            self?.handleStateUpdate(state)
        }
        
        delegate.onDiscover = { [weak self] peripheral, advertisementData, rssi in
            self?.handleDiscover(peripheral, advertisementData, rssi)
        }
        
        delegate.onConnect = { [weak self] peripheral in
            self?.handleConnect(peripheral)
        }
        
        delegate.onDisconnect = { [weak self] peripheral, error in
            self?.handleDisconnect(peripheral, error)
        }
        
        delegate.onConnectFailed = { [weak self] peripheral, error in
            self?.handleConnectFailed(peripheral, error)
        }
        
        // G6-COEX-018: State restoration callback
        delegate.onWillRestoreState = { [weak self] dict in
            self?.handleWillRestoreState(dict)
        }
        
        // G7-PASSIVE-004: Connection events callback
        delegate.onConnectionEvent = { [weak self] event, peripheral in
            self?.handleConnectionEvent(event, peripheral)
        }
    }
    
    /// G7-PASSIVE-003: Set continuation for connection events stream
    private func setConnectionEventsContinuation(_ continuation: AsyncStream<BLEConnectionEvent>.Continuation) {
        stateLock.withLock {
            self.connectionEventsContinuation = continuation
        }
    }
    
    // MARK: - State Restoration (G6-COEX-018)
    
    /// Handle iOS state restoration after app relaunch from background termination.
    /// Called by iOS before centralManagerDidUpdateState when using restoration identifier.
    /// 
    /// Reference: Loop's CGMBLEKit/BluetoothManager.swift:centralManager(_:willRestoreState:)
    private func handleWillRestoreState(_ dict: [String: Any]) {
        // This is called on centralQueue by CoreBluetooth
        dispatchPrecondition(condition: .onQueue(centralQueue))
        
        var restoredPeripherals: [BLEPeripheralInfo] = []
        
        // Restore previously connected/connecting peripherals
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                restoredPeripheralIds.append(peripheral.identifier)
                restoredPeripherals.append(BLEPeripheralInfo(
                    identifier: BLEUUID(peripheral.identifier),
                    name: peripheral.name
                ))
                
                // Log restoration (BLE-DIAG-001)
                BLELogger.general.info("State restoration: peripheral \(peripheral.identifier.uuidString) (\(peripheral.name ?? "unknown"))")
            }
        }
        
        // Restore scan services (G6-COEX-019)
        if let services = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            restoredScanServices = services.map { BLEUUID(data: $0.data) }
            BLELogger.general.info("State restoration: scan services \(services.map { $0.uuidString })")
        }
        
        // Notify callback if set
        if !restoredPeripherals.isEmpty || restoredScanServices != nil {
            onStateRestored?(restoredPeripherals, restoredScanServices)
        }
    }
    
    /// Get peripherals restored by iOS state restoration.
    /// Call this after receiving onStateRestored callback to reconnect.
    public func getRestoredPeripherals() -> [UUID] {
        stateLock.withLock { restoredPeripheralIds }
    }
    
    /// Resume scanning with services from before app termination (G6-COEX-019).
    /// Call this in response to state restoration if background scan should continue.
    public func resumeRestoredScan() {
        guard let services = restoredScanServices else { return }
        
        centralQueue.async {
            guard self.centralManager.state == .poweredOn else { return }
            
            let cbUUIDs = services.map { self.cbuuid(from: $0) }
            BLELogger.general.scanStarted(services: services)
            
            self.centralManager.scanForPeripherals(
                withServices: cbUUIDs,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }
    
    // MARK: - Scanning
    
    public func scan(for services: [BLEUUID]?) -> AsyncThrowingStream<BLEScanResult, Error> {
        AsyncThrowingStream { [weak self] continuation in
            self?.startScan(for: services, continuation: continuation)
        }
    }
    
    private func startScan(
        for services: [BLEUUID]?,
        continuation: AsyncThrowingStream<BLEScanResult, Error>.Continuation
    ) {
        // BLE-ARCH-003: Validate not on queue before sync to prevent deadlock
        dispatchPrecondition(condition: .notOnQueue(centralQueue))
        
        centralQueue.sync {
            guard centralManager.state == .poweredOn else {
                continuation.finish(throwing: BLEError.notPoweredOn)
                return
            }
            
            stateLock.withLock {
                self.scanContinuation = continuation
            }
            
            let cbUUIDs = services?.map { cbuuid(from: $0) }
            
            // Log scan start (BLE-DIAG-001)
            BLELogger.general.scanStarted(services: services)
            
            centralManager.scanForPeripherals(
                withServices: cbUUIDs,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
        
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.stopScan() }
        }
    }
    
    public func stopScan() async {
        // BLE-ARCH-003: Validate not on queue before sync
        dispatchPrecondition(condition: .notOnQueue(centralQueue))
        
        centralQueue.sync {
            centralManager.stopScan()
        }
        
        stateLock.withLock {
            scanContinuation?.finish()
            scanContinuation = nil
        }
        
        // Log scan stop (BLE-DIAG-001)
        BLELogger.general.scanStopped()
    }
    
    // MARK: - Connection
    
    public func connect(to peripheral: BLEPeripheralInfo) async throws -> any BLEPeripheralProtocol {
        // BLE-ARCH-003: Validate not on queue before sync
        dispatchPrecondition(condition: .notOnQueue(centralQueue))
        
        let currentState = centralQueue.sync { centralManager.state }
        guard currentState == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        
        // Find the CBPeripheral by UUID
        guard let uuid = UUID(uuidString: peripheral.identifier.description) else {
            throw BLEError.connectionFailed("Invalid peripheral identifier")
        }
        
        let cbPeripheral: CBPeripheral? = centralQueue.sync {
            centralManager.retrievePeripherals(withIdentifiers: [uuid]).first
        }
        
        guard let cbPeripheral = cbPeripheral else {
            throw BLEError.connectionFailed("Peripheral not found")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            stateLock.withLock {
                pendingConnections[uuid] = continuation
            }
            
            centralQueue.async {
                self.centralManager.connect(cbPeripheral, options: nil)
            }
            
            // Connection timeout - G6-COEX-024: 5 minutes for transmitter cycle
            // G6 transmitter sleeps ~4.5 min every 5 min cycle. Previous 30s timeout
            // was too short - we'd give up before Dexcom app woke the transmitter.
            // Device-specific timeouts defined in BLETimingConstants
            Task {
                try await Task.sleep(nanoseconds: BLETimingConstants.cgmConnectionTimeoutNanos) // 5 minutes
                let pending = self.stateLock.withLock { () -> CheckedContinuation<any BLEPeripheralProtocol, Error>? in
                    let p = self.pendingConnections[uuid]
                    if p != nil {
                        self.pendingConnections[uuid] = nil
                    }
                    return p
                }
                
                if let pending = pending {
                    pending.resume(throwing: BLEError.connectionTimeout)
                    self.centralQueue.async {
                        self.centralManager.cancelPeripheralConnection(cbPeripheral)
                    }
                }
            }
        }
    }
    
    public func disconnect(_ peripheral: any BLEPeripheralProtocol) async {
        await peripheral.disconnect()
        
        if let darwin = peripheral as? DarwinBLEPeripheral {
            if let uuid = UUID(uuidString: darwin.identifier.description) {
                stateLock.withLock {
                    connectedPeripherals[uuid] = nil
                }
                
                let cbPeripheral = await darwin.cbPeripheral
                centralQueue.async {
                    self.centralManager.cancelPeripheralConnection(cbPeripheral)
                }
            }
        }
    }
    
    public func retrievePeripheral(identifier: BLEUUID) async -> BLEPeripheralInfo? {
        guard let uuid = UUID(uuidString: identifier.description) else {
            return nil
        }
        
        let cbPeripheral: CBPeripheral? = centralQueue.sync {
            centralManager.retrievePeripherals(withIdentifiers: [uuid]).first
        }
        
        guard let cbPeripheral = cbPeripheral else {
            return nil
        }
        
        return BLEPeripheralInfo(
            identifier: BLEUUID(cbPeripheral.identifier),
            name: cbPeripheral.name
        )
    }
    
    /// G6-COEX-013: Find peripherals already connected by other apps
    /// This enables fast coexistence by joining an existing connection
    public func retrieveConnectedPeripherals(withServices serviceUUIDs: [BLEUUID]) async -> [BLEPeripheralInfo] {
        let cbUUIDs = serviceUUIDs.map { cbuuid(from: $0) }
        
        let cbPeripherals: [CBPeripheral] = centralQueue.sync {
            centralManager.retrieveConnectedPeripherals(withServices: cbUUIDs)
        }
        
        return cbPeripherals.map { peripheral in
            BLEPeripheralInfo(
                identifier: BLEUUID(peripheral.identifier),
                name: peripheral.name
            )
        }
    }
    
    // MARK: - Connection Events (G7-PASSIVE-001, G7-PASSIVE-002)
    
    /// Register for connection events matching the specified services.
    /// Enables background wake-up when Dexcom (or other) app connects to G7 sensor.
    /// 
    /// Reference: Loop's G7BluetoothManager.managerQueue_scanForPeripheral()
    /// Trace: G7-PASSIVE-001, G7-PASSIVE-002
    public func registerForConnectionEvents(matchingServices services: [BLEUUID]) async {
        let cbUUIDs = services.map { cbuuid(from: $0) }
        
        centralQueue.async {
            // iOS 13+ API: Register for connection events matching service UUIDs
            self.centralManager.registerForConnectionEvents(options: [
                CBConnectionEventMatchingOption.serviceUUIDs: cbUUIDs
            ])
            
            BLELogger.general.info("Registered for connection events: \(services.map { $0.description })")
        }
    }
    
    // MARK: - Delegate Handlers (called on centralQueue)
    
    private func handleStateUpdate(_ cbState: CBManagerState) {
        // This is called on centralQueue by CoreBluetooth
        dispatchPrecondition(condition: .onQueue(centralQueue))
        
        let oldState = mapState(centralManager.state)
        let newState = mapState(cbState)
        
        // Log state change (BLE-DIAG-001)
        BLELogger.general.stateChanged(from: oldState.rawValue, to: newState.rawValue)
        
        stateLock.withLock {
            stateStreamContinuation?.yield(newState)
            
            if cbState != .poweredOn {
                scanContinuation?.finish(throwing: BLEError.notPoweredOn)
                scanContinuation = nil
            }
        }
    }
    
    private func handleDiscover(
        _ cbPeripheral: CBPeripheral,
        _ advertisementData: [String: Any],
        _ rssi: NSNumber
    ) {
        // This is called on centralQueue by CoreBluetooth
        dispatchPrecondition(condition: .onQueue(centralQueue))
        
        let deviceName = cbPeripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let advertisement = parseAdvertisement(advertisementData)
        
        let result = BLEScanResult(
            peripheral: BLEPeripheralInfo(
                identifier: BLEUUID(cbPeripheral.identifier),
                name: deviceName
            ),
            rssi: rssi.intValue,
            advertisement: advertisement
        )
        
        // Log discovery (BLE-DIAG-001)
        BLELogger.discovery.deviceDiscovered(
            name: deviceName,
            uuid: cbPeripheral.identifier.uuidString,
            rssi: rssi.intValue,
            services: advertisement.serviceUUIDs.map { $0.description }
        )
        
        stateLock.withLock {
            _ = scanContinuation?.yield(result)
        }
    }
    
    private func handleConnect(_ cbPeripheral: CBPeripheral) {
        // This is called on centralQueue by CoreBluetooth
        dispatchPrecondition(condition: .onQueue(centralQueue))
        
        let uuid = cbPeripheral.identifier
        
        // Log connection success (BLE-DIAG-001)
        BLELogger.connection.connected(name: cbPeripheral.name, uuid: uuid.uuidString)
        
        let peripheral = DarwinBLEPeripheral(cbPeripheral: cbPeripheral)
        
        let continuation = stateLock.withLock { () -> CheckedContinuation<any BLEPeripheralProtocol, Error>? in
            connectedPeripherals[uuid] = peripheral
            let c = pendingConnections[uuid]
            pendingConnections[uuid] = nil
            return c
        }
        
        continuation?.resume(returning: peripheral)
    }
    
    private func handleDisconnect(_ cbPeripheral: CBPeripheral, _ error: Error?) {
        // This is called on centralQueue by CoreBluetooth
        dispatchPrecondition(condition: .onQueue(centralQueue))
        
        let uuid = cbPeripheral.identifier
        
        // Log disconnection (BLE-DIAG-001)
        BLELogger.connection.disconnected(
            name: cbPeripheral.name,
            uuid: uuid.uuidString,
            reason: error?.localizedDescription
        )
        
        let (peripheral, continuation) = stateLock.withLock { () -> (DarwinBLEPeripheral?, CheckedContinuation<any BLEPeripheralProtocol, Error>?) in
            let p = connectedPeripherals[uuid]
            connectedPeripherals[uuid] = nil
            let c = pendingConnections[uuid]
            pendingConnections[uuid] = nil
            return (p, c)
        }
        
        if let peripheral = peripheral {
            Task { await peripheral.handleDisconnect() }
        }
        
        continuation?.resume(throwing: error ?? BLEError.disconnected)
    }
    
    private func handleConnectFailed(_ cbPeripheral: CBPeripheral, _ error: Error?) {
        // This is called on centralQueue by CoreBluetooth
        dispatchPrecondition(condition: .onQueue(centralQueue))
        
        let uuid = cbPeripheral.identifier
        
        // Log connection failure (BLE-DIAG-001)
        BLELogger.connection.connectionError(
            name: cbPeripheral.name,
            uuid: uuid.uuidString,
            error: error?.localizedDescription ?? "Unknown error"
        )
        
        let continuation = stateLock.withLock { () -> CheckedContinuation<any BLEPeripheralProtocol, Error>? in
            let c = pendingConnections[uuid]
            pendingConnections[uuid] = nil
            return c
        }
        
        continuation?.resume(throwing: error ?? BLEError.connectionFailed("Connection failed"))
    }
    
    /// G7-PASSIVE-004: Handle connection event from other app
    /// Called when Dexcom app (or other) connects/disconnects from a registered peripheral
    private func handleConnectionEvent(_ event: CBConnectionEvent, _ cbPeripheral: CBPeripheral) {
        // This is called on centralQueue by CoreBluetooth
        dispatchPrecondition(condition: .onQueue(centralQueue))
        
        let eventType: BLEConnectionEventType = event == .peerConnected ? .peerConnected : .peerDisconnected
        let peripheralInfo = BLEPeripheralInfo(
            identifier: BLEUUID(cbPeripheral.identifier),
            name: cbPeripheral.name
        )
        
        let bleEvent = BLEConnectionEvent(eventType: eventType, peripheral: peripheralInfo)
        
        // Log the event (BLE-DIAG-001)
        let eventTypeStr = eventType == .peerConnected ? "peerConnected" : "peerDisconnected"
        BLELogger.general.info("Connection event: \(eventTypeStr) for \(cbPeripheral.name ?? cbPeripheral.identifier.uuidString)")
        
        // Emit to stream
        stateLock.withLock {
            connectionEventsContinuation?.yield(bleEvent)
        }
    }
    
    // MARK: - Helpers
    
    private func mapState(_ cbState: CBManagerState) -> BLECentralState {
        switch cbState {
        case .unknown: return .unknown
        case .resetting: return .resetting
        case .unsupported: return .unsupported
        case .unauthorized: return .unauthorized
        case .poweredOff: return .poweredOff
        case .poweredOn: return .poweredOn
        @unknown default: return .unknown
        }
    }
    
    private func cbuuid(from bleUUID: BLEUUID) -> CBUUID {
        if let short = bleUUID.shortUUID {
            return CBUUID(string: String(format: "%04X", short))
        }
        return CBUUID(data: bleUUID.data)
    }
    
    private func parseAdvertisement(_ data: [String: Any]) -> BLEAdvertisement {
        let localName = data[CBAdvertisementDataLocalNameKey] as? String
        
        var serviceUUIDs: [BLEUUID] = []
        if let cbUUIDs = data[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            serviceUUIDs = cbUUIDs.map { BLEUUID(data: $0.data) }
        }
        
        let manufacturerData = data[CBAdvertisementDataManufacturerDataKey] as? Data
        let isConnectable = data[CBAdvertisementDataIsConnectable] as? Bool ?? true
        
        return BLEAdvertisement(
            localName: localName,
            serviceUUIDs: serviceUUIDs,
            manufacturerData: manufacturerData,
            isConnectable: isConnectable
        )
    }
}

// MARK: - Central Delegate

/// Internal delegate for CBCentralManager callbacks
///
/// Safety: Closure properties are set once from the owning DarwinBLECentral actor
/// before any callbacks occur. All callbacks execute on CoreBluetooth's internal
/// serial queue, ensuring sequential access to the closures.
private final class CentralDelegate: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    
    var onStateUpdate: ((CBManagerState) -> Void)?
    var onDiscover: ((CBPeripheral, [String: Any], NSNumber) -> Void)?
    var onConnect: ((CBPeripheral) -> Void)?
    var onDisconnect: ((CBPeripheral, Error?) -> Void)?
    var onConnectFailed: ((CBPeripheral, Error?) -> Void)?
    /// G6-COEX-018: State restoration callback
    var onWillRestoreState: (([String: Any]) -> Void)?
    /// G7-PASSIVE-004: Connection event callback (peer app connected/disconnected)
    var onConnectionEvent: ((CBConnectionEvent, CBPeripheral) -> Void)?
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateUpdate?(central.state)
    }
    
    /// G6-COEX-018: Called by iOS when restoring BLE state after app relaunch
    /// This is critical for background CGM monitoring - iOS will call this before
    /// centralManagerDidUpdateState when restoring from termination.
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        onWillRestoreState?(dict)
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        onDiscover?(peripheral, advertisementData, RSSI)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnect?(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onDisconnect?(peripheral, error)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onConnectFailed?(peripheral, error)
    }
    
    /// G7-PASSIVE-004: Called when a peer app connects/disconnects from a registered peripheral
    /// This is critical for G7 coexistence - allows detecting when Dexcom app connects to sensor
    /// Reference: Loop's G7BluetoothManager.centralManager(_:connectionEventDidOccur:for:)
    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        onConnectionEvent?(event, peripheral)
    }
}

// DarwinBLEPeripheral, PeripheralDelegate moved to DarwinBLEPeripheral.swift (BLE-REFACTOR-001)

// DarwinBLEPeripheralManager, PeripheralManagerDelegate moved to DarwinBLEPeripheralManager.swift (BLE-REFACTOR-002)

#endif