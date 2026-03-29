// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MockBLE.swift
// BLEKit
//
// Mock BLE implementation for unit testing.
// Trace: PRD-008 REQ-BLE-006

import Foundation

// MARK: - Mock BLE Central

/// Mock BLE central for testing
public actor MockBLECentral: BLECentralProtocol, BLESimulatedProtocol {
    private var _state: BLECentralState
    private var stateStreamContinuation: AsyncStream<BLECentralState>.Continuation?
    private var scanContinuation: AsyncThrowingStream<BLEScanResult, Error>.Continuation?
    
    // Configurable behaviors
    private var mockScanResults: [BLEScanResult] = []
    private var mockConnectError: BLEError?
    private var mockPeripherals: [BLEUUID: MockBLEPeripheral] = [:]
    
    public init(options: BLECentralOptions = .default) {
        self._state = .poweredOn
    }
    
    // MARK: - BLECentralProtocol
    
    public var state: BLECentralState {
        get async { _state }
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLECentralState> {
        AsyncStream { continuation in
            Task { await self.setStateContinuation(continuation) }
        }
    }
    
    private func setStateContinuation(_ continuation: AsyncStream<BLECentralState>.Continuation) {
        stateStreamContinuation = continuation
        continuation.yield(_state)
    }
    
    public nonisolated func scan(for services: [BLEUUID]?) -> AsyncThrowingStream<BLEScanResult, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.startScan(continuation: continuation, services: services) }
        }
    }
    
    private func startScan(continuation: AsyncThrowingStream<BLEScanResult, Error>.Continuation, services: [BLEUUID]?) {
        guard _state == .poweredOn else {
            continuation.finish(throwing: BLEError.notPoweredOn)
            return
        }
        
        scanContinuation = continuation
        
        // Emit mock results
        for result in mockScanResults {
            if let services = services {
                // Filter by service UUID
                let hasMatchingService = result.advertisement.serviceUUIDs.contains { uuid in
                    services.contains(uuid)
                }
                if hasMatchingService {
                    continuation.yield(result)
                }
            } else {
                continuation.yield(result)
            }
        }
    }
    
    public func stopScan() async {
        scanContinuation?.finish()
        scanContinuation = nil
    }
    
    public func connect(to peripheral: BLEPeripheralInfo) async throws -> any BLEPeripheralProtocol {
        guard _state == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        
        if let error = mockConnectError {
            throw error
        }
        
        // Return existing mock peripheral or create new one
        if let existing = mockPeripherals[peripheral.identifier] {
            await existing.setState(.connected)
            return existing
        }
        
        let mockPeripheral = MockBLEPeripheral(identifier: peripheral.identifier, name: peripheral.name)
        mockPeripherals[peripheral.identifier] = mockPeripheral
        await mockPeripheral.setState(.connected)
        return mockPeripheral
    }
    
    public func disconnect(_ peripheral: any BLEPeripheralProtocol) async {
        if let mock = peripheral as? MockBLEPeripheral {
            await mock.setState(.disconnected)
        }
    }
    
    public func retrievePeripheral(identifier: BLEUUID) async -> BLEPeripheralInfo? {
        // Return mock peripheral if it matches
        if let mock = mockPeripherals[identifier] {
            return BLEPeripheralInfo(
                identifier: identifier,
                name: mock.name
            )
        }
        return nil
    }
    
    public func retrieveConnectedPeripherals(withServices serviceUUIDs: [BLEUUID]) async -> [BLEPeripheralInfo] {
        // Mock: return empty for now, can be enhanced for testing
        return []
    }
    
    // MARK: - Connection Events (G7-PASSIVE-001, G7-PASSIVE-003)
    
    /// Mock connection events stream
    public nonisolated var connectionEvents: AsyncStream<BLEConnectionEvent> {
        AsyncStream { continuation in
            Task { await self.setConnectionEventsContinuation(continuation) }
        }
    }
    
    /// G7-COEX-TIMING-001: Prepare connection events stream synchronously
    public nonisolated func prepareConnectionEventsStream() -> AsyncStream<BLEConnectionEvent> {
        AsyncStream { continuation in
            Task { await self.setConnectionEventsContinuation(continuation) }
        }
    }
    
    private var connectionEventsContinuation: AsyncStream<BLEConnectionEvent>.Continuation?
    
    private func setConnectionEventsContinuation(_ continuation: AsyncStream<BLEConnectionEvent>.Continuation) {
        connectionEventsContinuation = continuation
    }
    
    /// Mock: Register for connection events (no-op in mock)
    public func registerForConnectionEvents(matchingServices services: [BLEUUID]) async {
        // No-op in mock - use emitConnectionEvent for testing
    }
    
    // MARK: - Test Configuration
    
    /// Set the mock central state
    public func setState(_ newState: BLECentralState) {
        _state = newState
        stateStreamContinuation?.yield(newState)
    }
    
    /// Add a mock scan result
    public func addScanResult(_ result: BLEScanResult) {
        mockScanResults.append(result)
        scanContinuation?.yield(result)
    }
    
    /// Set mock connect error
    public func setConnectError(_ error: BLEError?) {
        mockConnectError = error
    }
    
    /// Add a pre-configured mock peripheral
    public func addMockPeripheral(_ peripheral: MockBLEPeripheral) {
        mockPeripherals[peripheral.identifier] = peripheral
    }
    
    /// Clear all mock data
    public func reset() {
        mockScanResults = []
        mockConnectError = nil
        mockPeripherals = [:]
    }
    
    /// G7-PASSIVE-003: Emit a mock connection event for testing
    public func emitConnectionEvent(_ event: BLEConnectionEvent) {
        connectionEventsContinuation?.yield(event)
    }
}

// MARK: - Mock BLE Peripheral

/// Mock BLE peripheral for testing
public actor MockBLEPeripheral: BLEPeripheralProtocol, BLESimulatedProtocol {
    public nonisolated let identifier: BLEUUID
    public nonisolated let name: String?
    
    private var _state: BLEPeripheralState = .disconnected
    private var stateStreamContinuation: AsyncStream<BLEPeripheralState>.Continuation?
    
    // Mock data
    private var mockServices: [BLEService] = []
    private var mockCharacteristics: [BLEUUID: [BLECharacteristic]] = [:]
    private var mockValues: [BLEUUID: Data] = [:]
    private var notificationContinuations: [BLEUUID: AsyncThrowingStream<Data, Error>.Continuation] = [:]
    
    public init(identifier: BLEUUID, name: String? = nil) {
        self.identifier = identifier
        self.name = name
    }
    
    // MARK: - BLEPeripheralProtocol
    
    public var state: BLEPeripheralState {
        get async { _state }
    }
    
    public nonisolated var stateUpdates: AsyncStream<BLEPeripheralState> {
        AsyncStream { continuation in
            Task { await self.setStateContinuation(continuation) }
        }
    }
    
    // G6-COEX-016: Cached services/characteristics (mock returns nil)
    public nonisolated var cachedServices: [BLEService]? { nil }
    public nonisolated func cachedCharacteristics(for service: BLEService) -> [BLECharacteristic]? { nil }
    
    private func setStateContinuation(_ continuation: AsyncStream<BLEPeripheralState>.Continuation) {
        stateStreamContinuation = continuation
        continuation.yield(_state)
    }
    
    public func discoverServices(_ uuids: [BLEUUID]?) async throws -> [BLEService] {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        if let uuids = uuids {
            return mockServices.filter { uuids.contains($0.uuid) }
        }
        return mockServices
    }
    
    public func discoverCharacteristics(_ uuids: [BLEUUID]?, for service: BLEService) async throws -> [BLECharacteristic] {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        guard let characteristics = mockCharacteristics[service.uuid] else {
            throw BLEError.serviceNotFound(service.uuid)
        }
        
        if let uuids = uuids {
            return characteristics.filter { uuids.contains($0.uuid) }
        }
        return characteristics
    }
    
    public func readValue(for characteristic: BLECharacteristic) async throws -> Data {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        guard let value = mockValues[characteristic.uuid] else {
            throw BLEError.characteristicNotFound(characteristic.uuid)
        }
        
        return value
    }
    
    public func writeValue(_ data: Data, for characteristic: BLECharacteristic, type: BLEWriteType) async throws {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        
        mockValues[characteristic.uuid] = data
    }
    
    public nonisolated func subscribe(to characteristic: BLECharacteristic) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.startSubscription(characteristic: characteristic, continuation: continuation) }
        }
    }
    
    public func enableNotifications(for characteristic: BLECharacteristic) async throws {
        guard _state == .connected else {
            throw BLEError.disconnected
        }
        // Mock: notifications are enabled immediately
    }
    
    public func prepareNotificationStream(for characteristic: BLECharacteristic) async -> AsyncThrowingStream<Data, Error> {
        return AsyncThrowingStream { continuation in
            self.notificationContinuations[characteristic.uuid] = continuation
        }
    }
    
    private func startSubscription(characteristic: BLECharacteristic, continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        guard _state == .connected else {
            continuation.finish(throwing: BLEError.disconnected)
            return
        }
        
        notificationContinuations[characteristic.uuid] = continuation
    }
    
    public func unsubscribe(from characteristic: BLECharacteristic) async throws {
        notificationContinuations[characteristic.uuid]?.finish()
        notificationContinuations[characteristic.uuid] = nil
    }
    
    public func disconnect() async {
        _state = .disconnected
        stateStreamContinuation?.yield(.disconnected)
        
        // End all subscriptions
        for (_, continuation) in notificationContinuations {
            continuation.finish(throwing: BLEError.disconnected)
        }
        notificationContinuations = [:]
    }
    
    // MARK: - Test Configuration
    
    /// Set the mock peripheral state
    public func setState(_ newState: BLEPeripheralState) {
        _state = newState
        stateStreamContinuation?.yield(newState)
    }
    
    /// Add a mock service
    public func addService(_ service: BLEService) {
        mockServices.append(service)
    }
    
    /// Add mock characteristics for a service
    public func addCharacteristics(_ characteristics: [BLECharacteristic], for serviceUUID: BLEUUID) {
        mockCharacteristics[serviceUUID] = characteristics
    }
    
    /// Set mock value for a characteristic
    public func setValue(_ data: Data, for characteristicUUID: BLEUUID) {
        mockValues[characteristicUUID] = data
    }
    
    /// Emit a notification value
    public func emitNotification(_ data: Data, for characteristicUUID: BLEUUID) {
        notificationContinuations[characteristicUUID]?.yield(data)
    }
}
