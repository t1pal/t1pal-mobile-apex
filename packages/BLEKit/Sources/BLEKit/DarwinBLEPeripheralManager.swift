// SPDX-License-Identifier: AGPL-3.0-or-later
// DarwinBLEPeripheralManager.swift - iOS/macOS BLE Peripheral Manager
// Extracted from DarwinBLE.swift (BLE-REFACTOR-002)
// Trace: PRD-007 REQ-SIM-001

#if canImport(CoreBluetooth)

import Foundation
@preconcurrency import CoreBluetooth

// MARK: - Darwin BLE Peripheral Manager

/// iOS/macOS BLE Peripheral Manager using CBPeripheralManager
///
/// Implements GATT server functionality for simulating CGM transmitters.
/// Trace: PRD-007 REQ-SIM-001
public actor DarwinBLEPeripheralManager: BLEPeripheralManagerProtocol {
    
    // MARK: - Properties
    
    private let peripheralManager: CBPeripheralManager
    private let delegate: PeripheralManagerDelegate
    
    private var _state: BLEPeripheralManagerState = .unknown
    private var _isAdvertising: Bool = false
    private var services: [BLEUUID: CBMutableService] = [:]
    private var characteristics: [BLEUUID: CBMutableCharacteristic] = [:]
    private var mutableCharacteristics: [BLEUUID: BLEMutableCharacteristic] = [:]
    
    private var stateStreamContinuation: AsyncStream<BLEPeripheralManagerState>.Continuation?
    private var readRequestContinuation: AsyncStream<BLEATTReadRequest>.Continuation?
    private var writeRequestContinuation: AsyncStream<BLEATTWriteRequest>.Continuation?
    private var subscriptionContinuation: AsyncStream<BLESubscriptionChange>.Continuation?
    
    private var pendingServiceAdd: CheckedContinuation<Void, Error>?
    
    // MARK: - BLEPeripheralManagerProtocol
    
    public var state: BLEPeripheralManagerState {
        _state
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLEPeripheralManagerState> {
        AsyncStream { continuation in
            Task { await self.setStateStreamContinuation(continuation) }
        }
    }
    
    public var isAdvertising: Bool {
        _isAdvertising
    }
    
    public nonisolated var readRequests: AsyncStream<BLEATTReadRequest> {
        AsyncStream { continuation in
            Task { await self.setReadRequestContinuation(continuation) }
        }
    }
    
    public nonisolated var writeRequests: AsyncStream<BLEATTWriteRequest> {
        AsyncStream { continuation in
            Task { await self.setWriteRequestContinuation(continuation) }
        }
    }
    
    public nonisolated var subscriptionChanges: AsyncStream<BLESubscriptionChange> {
        AsyncStream { continuation in
            Task { await self.setSubscriptionContinuation(continuation) }
        }
    }
    
    // MARK: - Initialization
    
    public init(options: BLEPeripheralManagerOptions = .default) {
        let delegate = PeripheralManagerDelegate()
        
        var cbOptions: [String: Any] = [:]
        if options.showPowerAlert {
            cbOptions[CBPeripheralManagerOptionShowPowerAlertKey] = true
        }
        if let restorationId = options.restorationIdentifier {
            cbOptions[CBPeripheralManagerOptionRestoreIdentifierKey] = restorationId
        }
        
        self.delegate = delegate
        self.peripheralManager = CBPeripheralManager(
            delegate: delegate,
            queue: DispatchQueue(label: "com.t1pal.blekit.peripheral"),
            options: cbOptions.isEmpty ? nil : cbOptions
        )
        
        Task { await self.setupDelegateCallbacks() }
    }
    
    private func setStateStreamContinuation(_ continuation: AsyncStream<BLEPeripheralManagerState>.Continuation) {
        stateStreamContinuation = continuation
        continuation.yield(_state)
    }
    
    private func setReadRequestContinuation(_ continuation: AsyncStream<BLEATTReadRequest>.Continuation) {
        readRequestContinuation = continuation
    }
    
    private func setWriteRequestContinuation(_ continuation: AsyncStream<BLEATTWriteRequest>.Continuation) {
        writeRequestContinuation = continuation
    }
    
    private func setSubscriptionContinuation(_ continuation: AsyncStream<BLESubscriptionChange>.Continuation) {
        subscriptionContinuation = continuation
    }
    
    private func setupDelegateCallbacks() {
        delegate.onStateUpdate = { [weak self] state in
            Task { await self?.handleStateUpdate(state) }
        }
        
        delegate.onServiceAdded = { [weak self] service, error in
            Task { await self?.handleServiceAdded(service, error) }
        }
        
        delegate.onReadRequest = { [weak self] request in
            Task { await self?.handleReadRequest(request) }
        }
        
        delegate.onWriteRequests = { [weak self] requests in
            Task { await self?.handleWriteRequests(requests) }
        }
        
        delegate.onSubscribe = { [weak self] central, characteristic in
            Task { await self?.handleSubscribe(central, characteristic) }
        }
        
        delegate.onUnsubscribe = { [weak self] central, characteristic in
            Task { await self?.handleUnsubscribe(central, characteristic) }
        }
    }
    
    // MARK: - Service Management
    
    public func addService(_ service: BLEMutableService) async throws {
        guard _state == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        
        let cbService = CBMutableService(
            type: cbuuid(from: service.uuid),
            primary: service.isPrimary
        )
        
        var cbCharacteristics: [CBMutableCharacteristic] = []
        for char in service.characteristics {
            let cbChar = CBMutableCharacteristic(
                type: cbuuid(from: char.uuid),
                properties: cbProperties(from: char.properties),
                value: char.value,
                permissions: cbPermissions(from: char.permissions)
            )
            cbCharacteristics.append(cbChar)
            characteristics[char.uuid] = cbChar
            mutableCharacteristics[char.uuid] = char
        }
        
        cbService.characteristics = cbCharacteristics
        services[service.uuid] = cbService
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingServiceAdd = continuation
            peripheralManager.add(cbService)
        }
    }
    
    public func removeService(_ serviceUUID: BLEUUID) async {
        if let cbService = services[serviceUUID] {
            peripheralManager.remove(cbService)
            services.removeValue(forKey: serviceUUID)
        }
    }
    
    public func removeAllServices() async {
        peripheralManager.removeAllServices()
        services.removeAll()
        characteristics.removeAll()
        mutableCharacteristics.removeAll()
    }
    
    // MARK: - Advertising
    
    public func startAdvertising(_ advertisement: BLEAdvertisementData) async throws {
        guard _state == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        
        var advertisementData: [String: Any] = [:]
        
        if let localName = advertisement.localName {
            advertisementData[CBAdvertisementDataLocalNameKey] = localName
        }
        
        if !advertisement.serviceUUIDs.isEmpty {
            advertisementData[CBAdvertisementDataServiceUUIDsKey] = advertisement.serviceUUIDs.map { cbuuid(from: $0) }
        }
        
        peripheralManager.startAdvertising(advertisementData)
        _isAdvertising = true
    }
    
    public func stopAdvertising() async {
        peripheralManager.stopAdvertising()
        _isAdvertising = false
    }
    
    // MARK: - Value Updates
    
    public func updateValue(_ value: Data, for characteristic: BLEMutableCharacteristic, onSubscribedCentrals centrals: [BLECentralInfo]?) async -> Bool {
        guard let cbChar = characteristics[characteristic.uuid] else {
            return false
        }
        
        // Note: centrals parameter is not directly supported by CBPeripheralManager
        // It will notify all subscribed centrals
        return peripheralManager.updateValue(value, for: cbChar, onSubscribedCentrals: nil)
    }
    
    // MARK: - Request Handling
    
    public func respond(to request: BLEATTReadRequest, withResult result: BLEATTError) async {
        // Store response for when we get the actual CBATTRequest
        // This is a simplified implementation - full version would track requests
    }
    
    public func respond(to request: BLEATTWriteRequest, withResult result: BLEATTError) async {
        // Store response for when we get the actual CBATTRequest
        // This is a simplified implementation - full version would track requests
    }
    
    // Internal respond that takes CBATTRequest
    private func respondToRequest(_ request: CBATTRequest, result: CBATTError.Code) {
        peripheralManager.respond(to: request, withResult: result)
    }
    
    // MARK: - Delegate Handlers
    
    private func handleStateUpdate(_ cbState: CBManagerState) {
        _state = mapState(cbState)
        stateStreamContinuation?.yield(_state)
    }
    
    private func handleServiceAdded(_ service: CBService?, _ error: Error?) {
        if let error = error {
            pendingServiceAdd?.resume(throwing: BLEError.invalidState(error.localizedDescription))
        } else {
            pendingServiceAdd?.resume()
        }
        pendingServiceAdd = nil
    }
    
    private func handleReadRequest(_ request: CBATTRequest) {
        let centralInfo = BLECentralInfo(
            identifier: BLEUUID(request.central.identifier),
            maximumUpdateValueLength: request.central.maximumUpdateValueLength
        )
        
        let attRequest = BLEATTReadRequest(
            central: centralInfo,
            characteristicUUID: BLEUUID(data: request.characteristic.uuid.data),
            offset: request.offset
        )
        
        readRequestContinuation?.yield(attRequest)
        
        // Auto-respond with characteristic value if available
        if let value = request.characteristic.value {
            request.value = value.suffix(from: request.offset)
            peripheralManager.respond(to: request, withResult: .success)
        } else if let charUUID = BLEUUID(string: request.characteristic.uuid.uuidString),
                  let mutableChar = mutableCharacteristics[charUUID],
                  let value = mutableChar.value {
            request.value = value.suffix(from: request.offset)
            peripheralManager.respond(to: request, withResult: .success)
        } else {
            peripheralManager.respond(to: request, withResult: .attributeNotFound)
        }
    }
    
    private func handleWriteRequests(_ requests: [CBATTRequest]) {
        for request in requests {
            let centralInfo = BLECentralInfo(
                identifier: BLEUUID(request.central.identifier),
                maximumUpdateValueLength: request.central.maximumUpdateValueLength
            )
            
            let attRequest = BLEATTWriteRequest(
                central: centralInfo,
                characteristicUUID: BLEUUID(data: request.characteristic.uuid.data),
                value: request.value ?? Data(),
                offset: request.offset
            )
            
            writeRequestContinuation?.yield(attRequest)
        }
        
        // Respond success to first request (represents all)
        if let first = requests.first {
            peripheralManager.respond(to: first, withResult: .success)
        }
    }
    
    private func handleSubscribe(_ central: CBCentral, _ characteristic: CBCharacteristic) {
        let centralInfo = BLECentralInfo(
            identifier: BLEUUID(central.identifier),
            maximumUpdateValueLength: central.maximumUpdateValueLength
        )
        
        let change = BLESubscriptionChange(
            central: centralInfo,
            characteristicUUID: BLEUUID(data: characteristic.uuid.data),
            isSubscribed: true
        )
        
        subscriptionContinuation?.yield(change)
    }
    
    private func handleUnsubscribe(_ central: CBCentral, _ characteristic: CBCharacteristic) {
        let centralInfo = BLECentralInfo(
            identifier: BLEUUID(central.identifier),
            maximumUpdateValueLength: central.maximumUpdateValueLength
        )
        
        let change = BLESubscriptionChange(
            central: centralInfo,
            characteristicUUID: BLEUUID(data: characteristic.uuid.data),
            isSubscribed: false
        )
        
        subscriptionContinuation?.yield(change)
    }
    
    // MARK: - Helpers
    
    private nonisolated func mapState(_ cbState: CBManagerState) -> BLEPeripheralManagerState {
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
    
    private nonisolated func cbuuid(from bleUUID: BLEUUID) -> CBUUID {
        if let short = bleUUID.shortUUID {
            return CBUUID(string: String(format: "%04X", short))
        }
        return CBUUID(data: bleUUID.data)
    }
    
    private nonisolated func cbProperties(from props: BLECharacteristicProperties) -> CBCharacteristicProperties {
        var cbProps: CBCharacteristicProperties = []
        if props.contains(.read) { cbProps.insert(.read) }
        if props.contains(.writeWithoutResponse) { cbProps.insert(.writeWithoutResponse) }
        if props.contains(.write) { cbProps.insert(.write) }
        if props.contains(.notify) { cbProps.insert(.notify) }
        if props.contains(.indicate) { cbProps.insert(.indicate) }
        return cbProps
    }
    
    private nonisolated func cbPermissions(from perms: BLEAttributePermissions) -> CBAttributePermissions {
        var cbPerms: CBAttributePermissions = []
        if perms.contains(.readable) { cbPerms.insert(.readable) }
        if perms.contains(.writeable) { cbPerms.insert(.writeable) }
        if perms.contains(.readEncryptionRequired) { cbPerms.insert(.readEncryptionRequired) }
        if perms.contains(.writeEncryptionRequired) { cbPerms.insert(.writeEncryptionRequired) }
        return cbPerms
    }
}

// MARK: - Peripheral Manager Delegate

/// Internal delegate for CBPeripheralManager callbacks
///
/// Safety: Closure properties are set once from the owning DarwinBLEPeripheralManager actor.
/// All callbacks execute on CoreBluetooth's internal serial queue.
private final class PeripheralManagerDelegate: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    
    var onStateUpdate: ((CBManagerState) -> Void)?
    var onServiceAdded: ((CBService?, Error?) -> Void)?
    var onReadRequest: ((CBATTRequest) -> Void)?
    var onWriteRequests: (([CBATTRequest]) -> Void)?
    var onSubscribe: ((CBCentral, CBCharacteristic) -> Void)?
    var onUnsubscribe: ((CBCentral, CBCharacteristic) -> Void)?
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        onStateUpdate?(peripheral.state)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        onServiceAdded?(service, error)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        onReadRequest?(request)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        onWriteRequests?(requests)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        onSubscribe?(central, characteristic)
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        onUnsubscribe?(central, characteristic)
    }
}

#endif // canImport(CoreBluetooth)
