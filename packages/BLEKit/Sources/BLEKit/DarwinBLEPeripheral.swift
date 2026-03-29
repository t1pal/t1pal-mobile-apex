// SPDX-License-Identifier: AGPL-3.0-or-later
// DarwinBLEPeripheral.swift - iOS/macOS BLE Peripheral wrapper
// Extracted from DarwinBLE.swift (BLE-REFACTOR-001)
// Trace: PRD-008 REQ-BLE-004

#if canImport(CoreBluetooth)

import Foundation
@preconcurrency import CoreBluetooth

// MARK: - Darwin BLE Peripheral

/// iOS/macOS peripheral wrapper
public actor DarwinBLEPeripheral: BLEPeripheralProtocol {
    
    // MARK: - Properties
    
    // Note: nonisolated(unsafe) needed for cachedServices/cachedCharacteristics access
    // CBPeripheral.services is thread-safe for read-only cached data access
    private nonisolated(unsafe) let _cbPeripheral: CBPeripheral
    private let delegate: PeripheralDelegate
    
    private var _state: BLEPeripheralState = .connected
    private var stateStreamContinuation: AsyncStream<BLEPeripheralState>.Continuation?
    private var discoveredServices: [CBUUID: CBService] = [:]
    private var discoveredCharacteristics: [CBUUID: CBCharacteristic] = [:]
    private var notificationContinuations: [CBUUID: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    
    private var serviceDiscoveryContinuation: CheckedContinuation<[BLEService], Error>?
    private var characteristicDiscoveryContinuation: CheckedContinuation<[BLECharacteristic], Error>?
    private var readContinuation: CheckedContinuation<Data, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var notifyStateContinuation: CheckedContinuation<Void, Error>?
    
    // MARK: - BLEPeripheralProtocol
    
    public let identifier: BLEUUID
    public let name: String?
    
    public var state: BLEPeripheralState {
        get async { _state }
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLEPeripheralState> {
        AsyncStream { continuation in
            Task { await self.setStateStreamContinuation(continuation) }
        }
    }
    
    /// Access to underlying CBPeripheral for disconnect
    var cbPeripheral: CBPeripheral {
        _cbPeripheral
    }
    
    // MARK: - G6-COEX-016: Cached Services/Characteristics
    
    /// Get cached services from CoreBluetooth (if available)
    /// Returns services that CoreBluetooth has cached from prior connections.
    public nonisolated var cachedServices: [BLEService]? {
        guard let services = _cbPeripheral.services, !services.isEmpty else {
            return nil
        }
        return services.map { BLEService(uuid: BLEUUID(data: $0.uuid.data)) }
    }
    
    /// Get cached characteristics for a service (if available)
    /// Returns characteristics that CoreBluetooth has cached from prior connections.
    public nonisolated func cachedCharacteristics(for service: BLEService) -> [BLECharacteristic]? {
        let serviceUUID = CBUUID(data: service.uuid.data)
        guard let cbService = _cbPeripheral.services?.first(where: { $0.uuid == serviceUUID }),
              let chars = cbService.characteristics, !chars.isEmpty else {
            return nil
        }
        return chars.map { cbChar in
            let properties = BLECharacteristicProperties(rawValue: UInt8(cbChar.properties.rawValue & 0xFF))
            return BLECharacteristic(
                uuid: BLEUUID(data: cbChar.uuid.data),
                properties: properties,
                serviceUUID: service.uuid
            )
        }
    }
    
    // MARK: - Initialization
    
    init(cbPeripheral: CBPeripheral) {
        self._cbPeripheral = cbPeripheral
        self.identifier = BLEUUID(cbPeripheral.identifier)
        self.name = cbPeripheral.name
        self.delegate = PeripheralDelegate()
        
        cbPeripheral.delegate = delegate
        
        Task { await self.setupDelegateCallbacks() }
    }
    
    private func setStateStreamContinuation(_ continuation: AsyncStream<BLEPeripheralState>.Continuation) {
        self.stateStreamContinuation = continuation
        continuation.yield(_state)
    }
    
    private func setupDelegateCallbacks() {
        delegate.onServicesDiscovered = { [weak self] services, error in
            Task { await self?.handleServicesDiscovered(services, error) }
        }
        
        delegate.onCharacteristicsDiscovered = { [weak self] service, characteristics, error in
            Task { await self?.handleCharacteristicsDiscovered(service, characteristics, error) }
        }
        
        delegate.onValueUpdated = { [weak self] characteristic, error in
            Task { await self?.handleValueUpdated(characteristic, error) }
        }
        
        delegate.onValueWritten = { [weak self] characteristic, error in
            Task { await self?.handleValueWritten(characteristic, error) }
        }
        
        delegate.onNotificationStateChanged = { [weak self] characteristic, error in
            Task { await self?.handleNotificationStateChanged(characteristic, error) }
        }
    }
    
    // MARK: - Service Discovery
    
    public func discoverServices(_ uuids: [BLEUUID]?) async throws -> [BLEService] {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        let cbUUIDs = uuids?.map { cbuuid(from: $0) }
        
        // G6-COEX-011: Check if services are already cached in CoreBluetooth (Loop pattern)
        // This enables fast reconnection - CoreBluetooth often keeps services from prior connections
        if let requestedUUIDs = cbUUIDs, let existingServices = _cbPeripheral.services {
            let knownUUIDs = Set(existingServices.map { $0.uuid })
            let neededUUIDs = requestedUUIDs.filter { !knownUUIDs.contains($0) }
            
            // If all requested services are already known, return them immediately
            if neededUUIDs.isEmpty {
                let matchedServices = existingServices.filter { requestedUUIDs.contains($0.uuid) }
                // Cache discovered services for characteristic lookup
                for service in matchedServices {
                    discoveredServices[service.uuid] = service
                }
                return matchedServices.map { BLEService(uuid: BLEUUID(data: $0.uuid.data)) }
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            serviceDiscoveryContinuation = continuation
            _cbPeripheral.discoverServices(cbUUIDs)
        }
    }
    
    public func discoverCharacteristics(_ uuids: [BLEUUID]?, for service: BLEService) async throws -> [BLECharacteristic] {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        let cbServiceUUID = cbuuid(from: service.uuid)
        guard let cbService = discoveredServices[cbServiceUUID] else {
            throw BLEError.serviceNotFound(service.uuid)
        }
        
        let cbUUIDs = uuids?.map { cbuuid(from: $0) }
        
        // G6-COEX-011: Check if characteristics are already cached (Loop pattern)
        // CBService retains characteristics from prior discovery
        if let requestedUUIDs = cbUUIDs, let existingChars = cbService.characteristics {
            let knownUUIDs = Set(existingChars.map { $0.uuid })
            let neededUUIDs = requestedUUIDs.filter { !knownUUIDs.contains($0) }
            
            // If all requested characteristics are already known, return them immediately
            if neededUUIDs.isEmpty {
                let matchedChars = existingChars.filter { requestedUUIDs.contains($0.uuid) }
                // Cache for later operations
                for char in matchedChars {
                    discoveredCharacteristics[char.uuid] = char
                }
                return matchedChars.map {
                    BLECharacteristic(
                        uuid: BLEUUID(data: $0.uuid.data),
                        properties: BLECharacteristicProperties(rawValue: UInt8(truncatingIfNeeded: $0.properties.rawValue)),
                        serviceUUID: service.uuid
                    )
                }
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            characteristicDiscoveryContinuation = continuation
            _cbPeripheral.discoverCharacteristics(cbUUIDs, for: cbService)
        }
    }
    
    // MARK: - Read/Write
    
    public func readValue(for characteristic: BLECharacteristic) async throws -> Data {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        let cbCharUUID = cbuuid(from: characteristic.uuid)
        guard let cbChar = discoveredCharacteristics[cbCharUUID] else {
            throw BLEError.characteristicNotFound(characteristic.uuid)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            readContinuation = continuation
            _cbPeripheral.readValue(for: cbChar)
        }
    }
    
    public func writeValue(_ data: Data, for characteristic: BLECharacteristic, type: BLEWriteType) async throws {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        let cbCharUUID = cbuuid(from: characteristic.uuid)
        guard let cbChar = discoveredCharacteristics[cbCharUUID] else {
            throw BLEError.characteristicNotFound(characteristic.uuid)
        }
        
        let cbType: CBCharacteristicWriteType = type == .withResponse ? .withResponse : .withoutResponse
        
        if type == .withResponse {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                writeContinuation = continuation
                _cbPeripheral.writeValue(data, for: cbChar, type: cbType)
            }
        } else {
            _cbPeripheral.writeValue(data, for: cbChar, type: cbType)
        }
    }
    
    // MARK: - Notifications
    
    public nonisolated func subscribe(to characteristic: BLECharacteristic) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.startNotifications(for: characteristic, continuation: continuation) }
        }
    }
    
    /// G6-COEX-023: Prepare to receive notifications synchronously before enabling.
    /// This registers the continuation IMMEDIATELY (not in a queued Task) to avoid
    /// the race condition where data arrives before the Task runs.
    /// 
    /// Usage:
    ///   let stream = await peripheral.prepareNotificationStream(for: char)
    ///   try await peripheral.enableNotifications(for: char)
    ///   for try await data in stream { ... }
    public func prepareNotificationStream(for characteristic: BLECharacteristic) -> AsyncThrowingStream<Data, Error> {
        let cbCharUUID = cbuuid(from: characteristic.uuid)
        
        return AsyncThrowingStream { continuation in
            // Register synchronously in the closure - NOT in a Task
            self.notificationContinuations[cbCharUUID] = continuation
            
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.stopNotifications(for: characteristic) }
            }
        }
    }
    
    /// Enable notifications and await confirmation from CoreBluetooth.
    /// Use this in passive/coexistence mode where timing is critical.
    public func enableNotifications(for characteristic: BLECharacteristic) async throws {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        let cbCharUUID = cbuuid(from: characteristic.uuid)
        guard let cbChar = discoveredCharacteristics[cbCharUUID] else {
            throw BLEError.characteristicNotFound(characteristic.uuid)
        }
        
        // Already notifying - no need to wait
        if cbChar.isNotifying {
            return
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            notifyStateContinuation = continuation
            _cbPeripheral.setNotifyValue(true, for: cbChar)
        }
    }
    
    private func startNotifications(
        for characteristic: BLECharacteristic,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        let cbCharUUID = cbuuid(from: characteristic.uuid)
        guard let cbChar = discoveredCharacteristics[cbCharUUID] else {
            continuation.finish(throwing: BLEError.characteristicNotFound(characteristic.uuid))
            return
        }
        
        notificationContinuations[cbCharUUID] = continuation
        
        // G6-COEX-014: Skip redundant setNotifyValue if already notifying
        // This avoids race conditions when enableNotifications() was called first
        if !cbChar.isNotifying {
            _cbPeripheral.setNotifyValue(true, for: cbChar)
        }
        
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.stopNotifications(for: characteristic) }
        }
    }
    
    public func unsubscribe(from characteristic: BLECharacteristic) async throws {
        await stopNotifications(for: characteristic)
    }
    
    private func stopNotifications(for characteristic: BLECharacteristic) {
        let cbCharUUID = cbuuid(from: characteristic.uuid)
        
        if let cbChar = discoveredCharacteristics[cbCharUUID] {
            _cbPeripheral.setNotifyValue(false, for: cbChar)
        }
        
        notificationContinuations[cbCharUUID]?.finish()
        notificationContinuations[cbCharUUID] = nil
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
    
    func handleDisconnect() {
        _state = .disconnected
        stateStreamContinuation?.yield(.disconnected)
        
        for (_, continuation) in notificationContinuations {
            continuation.finish(throwing: BLEError.disconnected)
        }
        notificationContinuations.removeAll()
        
        serviceDiscoveryContinuation?.resume(throwing: BLEError.disconnected)
        serviceDiscoveryContinuation = nil
        characteristicDiscoveryContinuation?.resume(throwing: BLEError.disconnected)
        characteristicDiscoveryContinuation = nil
        readContinuation?.resume(throwing: BLEError.disconnected)
        readContinuation = nil
        writeContinuation?.resume(throwing: BLEError.disconnected)
        writeContinuation = nil
        notifyStateContinuation?.resume(throwing: BLEError.disconnected)
        notifyStateContinuation = nil
    }
    
    // MARK: - Delegate Handlers
    
    private func handleServicesDiscovered(_ services: [CBService]?, _ error: Error?) {
        if let error = error {
            serviceDiscoveryContinuation?.resume(throwing: BLEError.scanFailed(error.localizedDescription))
            serviceDiscoveryContinuation = nil
            return
        }
        
        guard let services = services else {
            serviceDiscoveryContinuation?.resume(returning: [])
            serviceDiscoveryContinuation = nil
            return
        }
        
        for service in services {
            discoveredServices[service.uuid] = service
        }
        
        let bleServices = services.map { service in
            BLEService(uuid: BLEUUID(data: service.uuid.data), isPrimary: service.isPrimary)
        }
        
        serviceDiscoveryContinuation?.resume(returning: bleServices)
        serviceDiscoveryContinuation = nil
    }
    
    private func handleCharacteristicsDiscovered(_ service: CBService, _ characteristics: [CBCharacteristic]?, _ error: Error?) {
        if let error = error {
            characteristicDiscoveryContinuation?.resume(throwing: BLEError.scanFailed(error.localizedDescription))
            characteristicDiscoveryContinuation = nil
            return
        }
        
        guard let characteristics = characteristics else {
            characteristicDiscoveryContinuation?.resume(returning: [])
            characteristicDiscoveryContinuation = nil
            return
        }
        
        for char in characteristics {
            discoveredCharacteristics[char.uuid] = char
        }
        
        let bleChars = characteristics.map { char in
            BLECharacteristic(
                uuid: BLEUUID(data: char.uuid.data),
                properties: mapProperties(char.properties),
                serviceUUID: BLEUUID(data: service.uuid.data)
            )
        }
        
        characteristicDiscoveryContinuation?.resume(returning: bleChars)
        characteristicDiscoveryContinuation = nil
    }
    
    private func handleValueUpdated(_ characteristic: CBCharacteristic, _ error: Error?) {
        if let readContinuation = readContinuation {
            self.readContinuation = nil
            if let error = error {
                readContinuation.resume(throwing: BLEError.readFailed(error.localizedDescription))
            } else if let value = characteristic.value {
                readContinuation.resume(returning: value)
            } else {
                readContinuation.resume(returning: Data())
            }
            return
        }
        
        // Notification
        if let continuation = notificationContinuations[characteristic.uuid] {
            if let error = error {
                continuation.finish(throwing: BLEError.notificationFailed(error.localizedDescription))
                notificationContinuations[characteristic.uuid] = nil
            } else if let value = characteristic.value {
                continuation.yield(value)
            }
        }
    }
    
    private func handleValueWritten(_ characteristic: CBCharacteristic, _ error: Error?) {
        if let writeContinuation = writeContinuation {
            self.writeContinuation = nil
            if let error = error {
                writeContinuation.resume(throwing: BLEError.writeFailed(error.localizedDescription))
            } else {
                writeContinuation.resume()
            }
        }
    }
    
    private func handleNotificationStateChanged(_ characteristic: CBCharacteristic, _ error: Error?) {
        // Handle awaiting enableNotifications() call
        if let continuation = notifyStateContinuation {
            notifyStateContinuation = nil
            if let error = error {
                continuation.resume(throwing: BLEError.notificationFailed(error.localizedDescription))
            } else {
                continuation.resume()
            }
        }
        
        // Handle error for existing notification streams
        if let error = error {
            notificationContinuations[characteristic.uuid]?.finish(throwing: BLEError.notificationFailed(error.localizedDescription))
            notificationContinuations[characteristic.uuid] = nil
        }
    }
    
    // MARK: - Helpers
    
    private nonisolated func cbuuid(from bleUUID: BLEUUID) -> CBUUID {
        if let short = bleUUID.shortUUID {
            return CBUUID(string: String(format: "%04X", short))
        }
        return CBUUID(data: bleUUID.data)
    }
    
    private nonisolated func mapProperties(_ cbProps: CBCharacteristicProperties) -> BLECharacteristicProperties {
        var props = BLECharacteristicProperties()
        if cbProps.contains(.read) { props.insert(.read) }
        if cbProps.contains(.writeWithoutResponse) { props.insert(.writeWithoutResponse) }
        if cbProps.contains(.write) { props.insert(.write) }
        if cbProps.contains(.notify) { props.insert(.notify) }
        if cbProps.contains(.indicate) { props.insert(.indicate) }
        return props
    }
}

// MARK: - Peripheral Delegate

/// Internal delegate for CBPeripheral callbacks
///
/// Safety: Closure properties are set once from the owning DarwinBLEPeripheral actor.
/// All callbacks execute on CoreBluetooth's internal serial queue.
private final class PeripheralDelegate: NSObject, CBPeripheralDelegate, @unchecked Sendable {
    
    var onServicesDiscovered: (([CBService]?, Error?) -> Void)?
    var onCharacteristicsDiscovered: ((CBService, [CBCharacteristic]?, Error?) -> Void)?
    var onValueUpdated: ((CBCharacteristic, Error?) -> Void)?
    var onValueWritten: ((CBCharacteristic, Error?) -> Void)?
    var onNotificationStateChanged: ((CBCharacteristic, Error?) -> Void)?
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        onServicesDiscovered?(peripheral.services, error)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        onCharacteristicsDiscovered?(service, service.characteristics, error)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        onValueUpdated?(characteristic, error)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        onValueWritten?(characteristic, error)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        onNotificationStateChanged?(characteristic, error)
    }
}

#endif
