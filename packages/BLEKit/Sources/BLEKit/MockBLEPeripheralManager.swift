// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MockBLEPeripheralManager.swift
// BLEKit
//
// Mock BLE peripheral manager for testing GATT server functionality.
// Trace: PRD-007 REQ-SIM-001

import Foundation

// MARK: - Mock BLE Peripheral Manager

/// Mock peripheral manager for testing
public actor MockBLEPeripheralManager: BLEPeripheralManagerProtocol, BLESimulatedProtocol {
    private var _state: BLEPeripheralManagerState
    private var _isAdvertising: Bool = false
    private var services: [BLEUUID: BLEMutableService] = [:]
    private var advertisementData: BLEAdvertisementData?
    private var subscribedCentrals: [BLEUUID: Set<BLECentralInfo>] = [:]
    
    // Continuations for streams
    private var stateContinuation: AsyncStream<BLEPeripheralManagerState>.Continuation?
    private var readRequestContinuation: AsyncStream<BLEATTReadRequest>.Continuation?
    private var writeRequestContinuation: AsyncStream<BLEATTWriteRequest>.Continuation?
    private var subscriptionContinuation: AsyncStream<BLESubscriptionChange>.Continuation?
    
    // Pending requests for response validation
    private var pendingReadRequests: [UUID: BLEATTReadRequest] = [:]
    private var pendingWriteRequests: [UUID: BLEATTWriteRequest] = [:]
    
    // Test hooks
    public var addedServices: [BLEMutableService] { Array(services.values) }
    public var currentAdvertisement: BLEAdvertisementData? { advertisementData }
    public var updateHistory: [(Data, BLEUUID)] = []
    
    public init(options: BLEPeripheralManagerOptions = .default) {
        self._state = .poweredOn // Start powered on for testing
    }
    
    // MARK: - BLEPeripheralManagerProtocol
    
    public var state: BLEPeripheralManagerState {
        _state
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLEPeripheralManagerState> {
        AsyncStream { continuation in
            Task { await self.setStateContinuation(continuation) }
        }
    }
    
    private func setStateContinuation(_ continuation: AsyncStream<BLEPeripheralManagerState>.Continuation) {
        stateContinuation = continuation
        continuation.yield(_state)
    }
    
    public func addService(_ service: BLEMutableService) async throws {
        guard _state == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        services[service.uuid] = service
    }
    
    public func removeService(_ serviceUUID: BLEUUID) async {
        services.removeValue(forKey: serviceUUID)
    }
    
    public func removeAllServices() async {
        services.removeAll()
    }
    
    public func startAdvertising(_ advertisement: BLEAdvertisementData) async throws {
        guard _state == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        advertisementData = advertisement
        _isAdvertising = true
    }
    
    public func stopAdvertising() async {
        _isAdvertising = false
        advertisementData = nil
    }
    
    public var isAdvertising: Bool {
        _isAdvertising
    }
    
    public func updateValue(_ value: Data, for characteristic: BLEMutableCharacteristic, onSubscribedCentrals centrals: [BLECentralInfo]?) async -> Bool {
        updateHistory.append((value, characteristic.uuid))
        return true
    }
    
    public nonisolated var readRequests: AsyncStream<BLEATTReadRequest> {
        AsyncStream { continuation in
            Task { await self.setReadRequestContinuation(continuation) }
        }
    }
    
    private func setReadRequestContinuation(_ continuation: AsyncStream<BLEATTReadRequest>.Continuation) {
        readRequestContinuation = continuation
    }
    
    public nonisolated var writeRequests: AsyncStream<BLEATTWriteRequest> {
        AsyncStream { continuation in
            Task { await self.setWriteRequestContinuation(continuation) }
        }
    }
    
    private func setWriteRequestContinuation(_ continuation: AsyncStream<BLEATTWriteRequest>.Continuation) {
        writeRequestContinuation = continuation
    }
    
    public nonisolated var subscriptionChanges: AsyncStream<BLESubscriptionChange> {
        AsyncStream { continuation in
            Task { await self.setSubscriptionContinuation(continuation) }
        }
    }
    
    private func setSubscriptionContinuation(_ continuation: AsyncStream<BLESubscriptionChange>.Continuation) {
        subscriptionContinuation = continuation
    }
    
    public func respond(to request: BLEATTReadRequest, withResult result: BLEATTError) async {
        pendingReadRequests.removeValue(forKey: request.id)
    }
    
    public func respond(to request: BLEATTWriteRequest, withResult result: BLEATTError) async {
        pendingWriteRequests.removeValue(forKey: request.id)
    }
    
    // MARK: - Test Helpers
    
    /// Simulate state change for testing
    public func simulateStateChange(_ newState: BLEPeripheralManagerState) {
        _state = newState
        stateContinuation?.yield(newState)
    }
    
    /// Simulate a central connecting and subscribing
    public func simulateCentralSubscribe(central: BLECentralInfo, to characteristicUUID: BLEUUID) {
        var subs = subscribedCentrals[characteristicUUID] ?? Set()
        subs.insert(central)
        subscribedCentrals[characteristicUUID] = subs
        
        let change = BLESubscriptionChange(central: central, characteristicUUID: characteristicUUID, isSubscribed: true)
        subscriptionContinuation?.yield(change)
    }
    
    /// Simulate a central unsubscribing
    public func simulateCentralUnsubscribe(central: BLECentralInfo, from characteristicUUID: BLEUUID) {
        subscribedCentrals[characteristicUUID]?.remove(central)
        
        let change = BLESubscriptionChange(central: central, characteristicUUID: characteristicUUID, isSubscribed: false)
        subscriptionContinuation?.yield(change)
    }
    
    /// Simulate a read request from a central
    public func simulateReadRequest(_ request: BLEATTReadRequest) {
        pendingReadRequests[request.id] = request
        readRequestContinuation?.yield(request)
    }
    
    /// Simulate a write request from a central
    public func simulateWriteRequest(_ request: BLEATTWriteRequest) {
        pendingWriteRequests[request.id] = request
        writeRequestContinuation?.yield(request)
    }
    
    /// Get services registered
    public func getService(uuid: BLEUUID) -> BLEMutableService? {
        services[uuid]
    }
}
