// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LinuxBLE.swift
// BLEKit
//
// Linux Bluetooth Low Energy implementation using PureSwift/BluetoothLinux.
// Only compiled on Linux targets when PureSwift packages are available.
// Trace: PRD-008 REQ-BLE-005

#if os(Linux)

// Check if PureSwift packages are available by attempting to import
// If not available, provide stub implementations that throw "not available" errors
#if canImport(Bluetooth) && canImport(BluetoothLinux)

import Foundation
import Bluetooth
import BluetoothLinux
import BluetoothHCI

// MARK: - Linux BLE Central (Full Implementation)

/// Linux BLE Central implementation using BluetoothLinux
///
/// Uses PureSwift's BluetoothLinux package to provide BLE central
/// functionality on Linux systems with Bluetooth hardware.
///
/// **Implementation Status**:
/// - [x] Host controller detection and initialization
/// - [ ] BLE scanning via HCI LE Scan (scaffold)
/// - [ ] L2CAP connection (requires GATT integration)
/// - [ ] GATT client operations
///
/// **Requirements**:
/// - Linux with Bluetooth adapter (USB dongle or built-in)
/// - CAP_NET_ADMIN capability for raw HCI access
/// - BlueZ not blocking the adapter (may need `hciconfig hci0 down`)
public actor LinuxBLECentral: BLECentralProtocol {
    
    // MARK: - Properties
    
    private var _state: BLECentralState = .unknown
    private var stateStreamContinuation: AsyncStream<BLECentralState>.Continuation?
    private var hostController: HostController?
    private var isScanning = false
    
    // MARK: - BLECentralProtocol
    
    public var state: BLECentralState {
        get async { _state }
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLECentralState> {
        AsyncStream { continuation in
            Task {
                await self.setStateStreamContinuation(continuation)
            }
        }
    }
    
    // MARK: - Initialization
    
    public init(options: BLECentralOptions = .default) {
        Task {
            await initializeHostController()
        }
    }
    
    private func setStateStreamContinuation(_ continuation: AsyncStream<BLECentralState>.Continuation) {
        self.stateStreamContinuation = continuation
    }
    
    private func initializeHostController() async {
        do {
            // Find the first available Bluetooth adapter (hci0)
            let controller = try await HostController(id: HostController.ID(rawValue: 0))
            self.hostController = controller
            setState(.poweredOn)
        } catch {
            // No Bluetooth adapter found or permission denied
            setState(.unsupported)
        }
    }
    
    // MARK: - Scanning
    
    public nonisolated func scan(for services: [BLEUUID]?) -> AsyncThrowingStream<BLEScanResult, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.performScan(for: services, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func performScan(
        for services: [BLEUUID]?,
        continuation: AsyncThrowingStream<BLEScanResult, Error>.Continuation
    ) async throws {
        guard hostController != nil, _state == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        
        self.isScanning = true
        
        // TODO: Implement HCI LE Scan using PureSwift API
        // The actual API is:
        //   for try await report in hostController.lowEnergyScan() {
        //       // Convert report to BLEScanResult
        //   }
        // 
        // For now, this is a scaffold that waits indefinitely.
        // Real implementation requires:
        // 1. Call hostController.lowEnergyScan() to get AsyncSequence
        // 2. Iterate over reports and convert to BLEScanResult
        // 3. Filter by service UUIDs if specified
        
        while isScanning {
            try await Task.sleep(nanoseconds: BLETimingConstants.linuxScanPollIntervalNanos) // 100ms
        }
        
        continuation.finish()
    }
    
    public func stopScan() async {
        isScanning = false
    }
    
    // MARK: - Connection
    
    public func connect(to peripheral: BLEPeripheralInfo) async throws -> any BLEPeripheralProtocol {
        guard _state == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        
        // TODO: Implement L2CAP ATT connection
        // Steps:
        // 1. Parse BluetoothAddress from peripheral.identifier
        // 2. Create L2CAPSocket with ATT channel (PSM 0x001F)
        // 3. Wrap in LinuxBLEPeripheral
        throw BLEError.connectionFailed("L2CAP connection not yet implemented")
    }
    
    public func disconnect(_ peripheral: any BLEPeripheralProtocol) async {
        await peripheral.disconnect()
    }
    
    public func retrievePeripheral(identifier: BLEUUID) async -> BLEPeripheralInfo? {
        // Linux stub - not implemented
        return nil
    }
    
    public func retrieveConnectedPeripherals(withServices serviceUUIDs: [BLEUUID]) async -> [BLEPeripheralInfo] {
        // Linux stub - not implemented
        return []
    }
    
    // MARK: - Connection Events (G7-PASSIVE-001, G7-PASSIVE-003)
    
    public nonisolated var connectionEvents: AsyncStream<BLEConnectionEvent> {
        // Linux: Connection events not available (iOS-only API)
        AsyncStream { $0.finish() }
    }
    
    public nonisolated func prepareConnectionEventsStream() -> AsyncStream<BLEConnectionEvent> {
        // Linux: Connection events not available (iOS-only API)
        AsyncStream { $0.finish() }
    }
    
    public func registerForConnectionEvents(matchingServices services: [BLEUUID]) async {
        // Linux: Not supported - CBConnectionEvent is iOS-only
    }
    
    // MARK: - Helpers
    
    private func setState(_ newState: BLECentralState) {
        _state = newState
        stateStreamContinuation?.yield(newState)
    }
}

// MARK: - Linux BLE Peripheral

/// Linux BLE Peripheral implementation (scaffold)
///
/// **Implementation Status**:
/// - [ ] L2CAP ATT socket connection
/// - [ ] GATT client service discovery
/// - [ ] Characteristic read/write
/// - [ ] Notifications/indications
public actor LinuxBLEPeripheral: BLEPeripheralProtocol {
    
    // MARK: - Properties
    
    public let identifier: BLEUUID
    public let name: String?
    
    private var _state: BLEPeripheralState = .connected
    private var stateStreamContinuation: AsyncStream<BLEPeripheralState>.Continuation?
    private var notificationContinuations: [BLEUUID: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    
    // MARK: - BLEPeripheralProtocol
    
    public var state: BLEPeripheralState {
        get async { _state }
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLEPeripheralState> {
        AsyncStream { continuation in
            Task {
                await self.setStateStreamContinuation(continuation)
            }
        }
    }
    
    // G6-COEX-016: Cached services/characteristics (not available on Linux stub)
    public nonisolated var cachedServices: [BLEService]? { nil }
    public nonisolated func cachedCharacteristics(for service: BLEService) -> [BLECharacteristic]? { nil }
    
    // MARK: - Initialization
    
    init(identifier: BLEUUID, name: String?) {
        self.identifier = identifier
        self.name = name
    }
    
    private func setStateStreamContinuation(_ continuation: AsyncStream<BLEPeripheralState>.Continuation) {
        self.stateStreamContinuation = continuation
    }
    
    // MARK: - Service Discovery
    
    public func discoverServices(_ uuids: [BLEUUID]?) async throws -> [BLEService] {
        throw BLEError.serviceNotFound(BLEUUID(short: 0))
    }
    
    public func discoverCharacteristics(_ uuids: [BLEUUID]?, for service: BLEService) async throws -> [BLECharacteristic] {
        throw BLEError.serviceNotFound(service.uuid)
    }
    
    // MARK: - Read/Write
    
    public func readValue(for characteristic: BLECharacteristic) async throws -> Data {
        throw BLEError.readFailed("Linux GATT not implemented")
    }
    
    public func writeValue(_ data: Data, for characteristic: BLECharacteristic, type: BLEWriteType) async throws {
        throw BLEError.writeFailed("Linux GATT not implemented")
    }
    
    // MARK: - Notifications
    
    public nonisolated func subscribe(to characteristic: BLECharacteristic) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: BLEError.readFailed("Notifications not implemented"))
        }
    }
    
    public func enableNotifications(for characteristic: BLECharacteristic) async throws {
        // Linux stub: not implemented
        throw BLEError.notificationFailed("Notifications not implemented")
    }
    
    public func prepareNotificationStream(for characteristic: BLECharacteristic) async -> AsyncThrowingStream<Data, Error> {
        // Linux stub: return empty stream
        AsyncThrowingStream { $0.finish(throwing: BLEError.notificationFailed("Notifications not implemented")) }
    }
    
    public func unsubscribe(from characteristic: BLECharacteristic) async throws {
        notificationContinuations[characteristic.uuid]?.finish()
        notificationContinuations[characteristic.uuid] = nil
    }
    
    // MARK: - Disconnect
    
    public func disconnect() async {
        _state = .disconnected
        stateStreamContinuation?.yield(.disconnected)
        
        for (_, continuation) in notificationContinuations {
            continuation.finish()
        }
        notificationContinuations.removeAll()
    }
}

#else // PureSwift packages not available

import Foundation

// MARK: - Linux BLE Central (Stub)

/// Stub implementation when PureSwift packages are not available.
/// 
/// To enable Linux BLE support, uncomment the PureSwift dependencies
/// in Package.swift and packages/BLEKit/Package.swift, then run
/// `swift package resolve`.
public actor LinuxBLECentral: BLECentralProtocol {
    
    public var state: BLECentralState {
        get async { .unsupported }
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLECentralState> {
        AsyncStream { continuation in
            continuation.yield(.unsupported)
            continuation.finish()
        }
    }
    
    public init(options: BLECentralOptions = .default) {
        // No-op - BLE not available
    }
    
    public nonisolated func scan(for services: [BLEUUID]?) -> AsyncThrowingStream<BLEScanResult, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: BLEError.notSupported("Linux BLE requires PureSwift packages. See BUILD.md for setup."))
        }
    }
    
    public func stopScan() async {
        // No-op
    }
    
    public func connect(to peripheral: BLEPeripheralInfo) async throws -> any BLEPeripheralProtocol {
        throw BLEError.notSupported("Linux BLE requires PureSwift packages. See BUILD.md for setup.")
    }
    
    public func retrievePeripheral(identifier: BLEUUID) async -> BLEPeripheralInfo? {
        return nil  // Stub - not implemented
    }
    
    public func retrieveConnectedPeripherals(withServices serviceUUIDs: [BLEUUID]) async -> [BLEPeripheralInfo] {
        return []  // Stub - not implemented
    }
    
    // MARK: - Connection Events (G7-PASSIVE-001, G7-PASSIVE-003)
    
    public nonisolated var connectionEvents: AsyncStream<BLEConnectionEvent> {
        // Linux: Connection events not available (iOS-only API)
        AsyncStream { $0.finish() }
    }
    
    public nonisolated func prepareConnectionEventsStream() -> AsyncStream<BLEConnectionEvent> {
        // Linux: Connection events not available (iOS-only API)
        AsyncStream { $0.finish() }
    }
    
    public func registerForConnectionEvents(matchingServices services: [BLEUUID]) async {
        // Linux: Not supported - CBConnectionEvent is iOS-only
    }
    
    public func disconnect(_ peripheral: any BLEPeripheralProtocol) async {
        // No-op
    }
}

// MARK: - Linux BLE Peripheral (Stub)

/// Stub implementation when PureSwift packages are not available.
public actor LinuxBLEPeripheral: BLEPeripheralProtocol {
    
    public let identifier: BLEUUID
    public let name: String?
    
    public var state: BLEPeripheralState {
        get async { .disconnected }
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLEPeripheralState> {
        AsyncStream { $0.finish() }
    }
    
    // G6-COEX-016: Cached services/characteristics (not available on Linux stub)
    public nonisolated var cachedServices: [BLEService]? { nil }
    public nonisolated func cachedCharacteristics(for service: BLEService) -> [BLECharacteristic]? { nil }
    
    init(identifier: BLEUUID, name: String?) {
        self.identifier = identifier
        self.name = name
    }
    
    public func discoverServices(_ uuids: [BLEUUID]?) async throws -> [BLEService] {
        throw BLEError.notSupported("Linux BLE requires PureSwift packages")
    }
    
    public func discoverCharacteristics(_ uuids: [BLEUUID]?, for service: BLEService) async throws -> [BLECharacteristic] {
        throw BLEError.notSupported("Linux BLE requires PureSwift packages")
    }
    
    public func readValue(for characteristic: BLECharacteristic) async throws -> Data {
        throw BLEError.notSupported("Linux BLE requires PureSwift packages")
    }
    
    public func writeValue(_ data: Data, for characteristic: BLECharacteristic, type: BLEWriteType) async throws {
        throw BLEError.notSupported("Linux BLE requires PureSwift packages")
    }
    
    public nonisolated func subscribe(to characteristic: BLECharacteristic) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish(throwing: BLEError.notSupported("Linux BLE requires PureSwift packages")) }
    }
    
    public func enableNotifications(for characteristic: BLECharacteristic) async throws {
        throw BLEError.notSupported("Linux BLE requires PureSwift packages")
    }
    
    public func prepareNotificationStream(for characteristic: BLECharacteristic) async -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish(throwing: BLEError.notSupported("Linux BLE requires PureSwift packages")) }
    }
    
    public func unsubscribe(from characteristic: BLECharacteristic) async throws {
        // No-op
    }
    
    public func disconnect() async {
        // No-op
    }
}

#endif // canImport(Bluetooth)

#endif // os(Linux)
