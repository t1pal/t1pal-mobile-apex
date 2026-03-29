// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6PeripheralEmulator.swift
// BLEKit
//
// Complete Dexcom G6 transmitter BLE peripheral emulator for hardware-free testing.
// Acts as a G6 transmitter on Linux or any platform with BLE peripheral support.
// Trace: PRD-007 REQ-SIM-001, CLI-SIM-004

import Foundation

// MARK: - Emulator State

/// State of the peripheral emulator
public enum G6EmulatorState: String, Sendable, Codable {
    /// Emulator not started
    case idle
    
    /// Advertising, waiting for connection
    case advertising
    
    /// Central connected, awaiting authentication
    case connected
    
    /// Authenticated, streaming glucose
    case streaming
    
    /// Error state
    case error
    
    /// Stopped
    case stopped
}

// MARK: - Emulator Event

/// Events emitted by the emulator
public enum G6EmulatorEvent: Sendable {
    /// State changed
    case stateChanged(G6EmulatorState)
    
    /// Central connected
    case centralConnected(BLECentralInfo)
    
    /// Central disconnected
    case centralDisconnected(BLECentralInfo)
    
    /// Authentication completed
    case authenticated(bonded: Bool)
    
    /// Glucose reading sent
    case glucoseSent(SimulatedGlucoseReading)
    
    /// Error occurred
    case error(String)
}

// MARK: - Emulator Configuration

/// Configuration for the G6 peripheral emulator
public struct G6EmulatorConfig: Sendable, Codable {
    /// Transmitter ID (6 characters, e.g., "80H123")
    public var transmitterId: String
    
    /// Glucose pattern to use
    public var pattern: GlucosePatternType
    
    /// Pattern configuration
    public var patternConfig: PatternConfig
    
    /// Whether to skip sensor warmup
    public var skipWarmup: Bool
    
    /// Reading interval in seconds
    public var intervalSeconds: Int
    
    /// Whether to auto-start advertising
    public var autoAdvertise: Bool
    
    public init(
        transmitterId: String = "80H123",
        pattern: GlucosePatternType = .flat,
        patternConfig: PatternConfig = PatternConfig(),
        skipWarmup: Bool = true,
        intervalSeconds: Int = 300,
        autoAdvertise: Bool = true
    ) {
        self.transmitterId = transmitterId
        self.pattern = pattern
        self.patternConfig = patternConfig
        self.skipWarmup = skipWarmup
        self.intervalSeconds = intervalSeconds
        self.autoAdvertise = autoAdvertise
    }
    
    /// Default configuration for testing
    public static let `default` = G6EmulatorConfig()
}

/// Glucose pattern types
public enum GlucosePatternType: String, Sendable, Codable, CaseIterable {
    case flat
    case sine
    case meal
    case random
}

// MARK: - G6 Peripheral Emulator

/// Complete Dexcom G6 transmitter emulator acting as a BLE peripheral
///
/// This actor emulates a G6 transmitter on BLE, handling:
/// - BLE advertising with Dexcom service UUID
/// - GATT service/characteristic setup
/// - Authentication handshake (G6AuthSimulator)
/// - Glucose data streaming (G6GlucoseSimulator)
/// - Backfill requests (G6BackfillSimulator)
///
/// ## Usage
/// ```swift
/// let emulator = await G6PeripheralEmulator(
///     config: G6EmulatorConfig(transmitterId: "80H123", pattern: .sine),
///     peripheralManager: BLEPeripheralManagerFactory.create()
/// )
/// 
/// // Start advertising
/// try await emulator.start()
/// 
/// // Monitor events
/// for await event in await emulator.events {
///     switch event {
///     case .glucoseSent(let reading):
///         print("Glucose: \(reading.glucose)")
///     }
/// }
/// ```
public actor G6PeripheralEmulator {
    
    // MARK: - Properties
    
    /// Configuration
    public private(set) var config: G6EmulatorConfig
    
    /// Current state
    public private(set) var state: G6EmulatorState = .idle
    
    /// BLE peripheral manager
    private let peripheralManager: any BLEPeripheralManagerProtocol
    
    /// Authentication simulator
    private let authSimulator: G6AuthSimulator
    
    /// Glucose simulator
    private var glucoseSimulator: G6GlucoseSimulator?
    
    /// Backfill simulator
    private var backfillSimulator: G6BackfillSimulator?
    
    /// Backfill provider for historical data
    private var backfillProvider: GeneratedBackfillProvider?
    
    /// Traffic logger
    public let trafficLogger: BLETrafficLogger
    
    /// Fault injector for testing error scenarios
    public var faultInjector: FaultInjector?
    
    /// Connected central (if any)
    private var connectedCentral: BLECentralInfo?
    
    /// Subscribed characteristics
    private var subscriptions: Set<BLEUUID> = []
    
    /// Reading count
    public private(set) var readingCount: Int = 0
    
    /// Event stream continuation
    private var eventContinuation: AsyncStream<G6EmulatorEvent>.Continuation?
    
    /// Glucose streaming timer task
    private var streamingTask: Task<Void, Never>?
    
    /// Request processing task
    private var requestTask: Task<Void, Never>?
    
    // MARK: - Service and Characteristics
    
    /// Authentication characteristic (read/write/indicate)
    private let authCharacteristic = BLEMutableCharacteristic(
        uuid: .dexcomAuthentication,
        properties: [.read, .write, .indicate],
        permissions: [.readable, .writeable]
    )
    
    /// Control characteristic (read/write/notify)
    private let controlCharacteristic = BLEMutableCharacteristic(
        uuid: .dexcomControl,
        properties: [.read, .write, .notify],
        permissions: [.readable, .writeable]
    )
    
    /// Backfill characteristic (read/notify)
    private let backfillCharacteristic = BLEMutableCharacteristic(
        uuid: .dexcomBackfill,
        properties: [.read, .notify],
        permissions: .readable
    )
    
    // MARK: - Initialization
    
    /// Create a G6 peripheral emulator
    /// - Parameters:
    ///   - config: Emulator configuration
    ///   - peripheralManager: BLE peripheral manager to use
    public init(
        config: G6EmulatorConfig = .default,
        peripheralManager: any BLEPeripheralManagerProtocol
    ) {
        self.config = config
        self.peripheralManager = peripheralManager
        self.authSimulator = G6AuthSimulator(transmitterId: config.transmitterId)
        self.trafficLogger = BLETrafficLogger()
        
        // Create glucose provider
        let provider = Self.createGlucoseProvider(config: config)
        
        // Create sensor session
        let initialState: TransmitterState = config.skipWarmup ? .active : .warmup
        let session = SensorSession(
            startTime: config.skipWarmup ? Date().addingTimeInterval(-3 * 3600) : Date(),
            state: initialState,
            transmitterType: .g6
        )
        
        self.glucoseSimulator = G6GlucoseSimulator(
            session: session,
            glucoseProvider: provider
        )
        
        // Create backfill provider and simulator
        self.backfillProvider = GeneratedBackfillProvider(glucoseProvider: provider)
        self.backfillSimulator = G6BackfillSimulator(backfillProvider: self.backfillProvider!)
    }
    
    /// Create with mock peripheral manager for testing
    public static func forTesting(config: G6EmulatorConfig = .default) -> G6PeripheralEmulator {
        G6PeripheralEmulator(
            config: config,
            peripheralManager: MockBLEPeripheralManager()
        )
    }
    
    // MARK: - Events
    
    /// Event stream for monitoring emulator activity
    public var events: AsyncStream<G6EmulatorEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { _ in
                Task { await self.clearEventContinuation() }
            }
        }
    }
    
    private func clearEventContinuation() {
        eventContinuation = nil
    }
    
    private func emit(_ event: G6EmulatorEvent) {
        eventContinuation?.yield(event)
    }
    
    // MARK: - Lifecycle
    
    /// Start the emulator
    public func start() async throws {
        guard state == .idle || state == .stopped else {
            throw G6EmulatorError.invalidState("Cannot start from state: \(state)")
        }
        
        // Wait for peripheral manager to be powered on
        let pmState = await peripheralManager.state
        guard pmState == .poweredOn else {
            throw G6EmulatorError.notPoweredOn
        }
        
        // Add GATT service
        let service = BLEMutableService(
            uuid: .dexcomService,
            isPrimary: true,
            characteristics: [authCharacteristic, controlCharacteristic, backfillCharacteristic]
        )
        try await peripheralManager.addService(service)
        
        // Start request processing
        startRequestProcessing()
        
        // Start advertising
        if config.autoAdvertise {
            try await startAdvertising()
        }
        
        state = .advertising
        emit(.stateChanged(.advertising))
    }
    
    /// Stop the emulator
    public func stop() async {
        streamingTask?.cancel()
        streamingTask = nil
        requestTask?.cancel()
        requestTask = nil
        
        await peripheralManager.stopAdvertising()
        await peripheralManager.removeAllServices()
        
        state = .stopped
        emit(.stateChanged(.stopped))
    }
    
    /// Start advertising
    public func startAdvertising() async throws {
        let advertisement = BLEAdvertisementData.dexcom(
            transmitterID: config.transmitterId,
            isG7: false
        )
        try await peripheralManager.startAdvertising(advertisement)
    }
    
    /// Stop advertising
    public func stopAdvertising() async {
        await peripheralManager.stopAdvertising()
    }
    
    /// Check if currently advertising
    public var isAdvertising: Bool {
        get async {
            await peripheralManager.isAdvertising
        }
    }
    
    // MARK: - Request Processing
    
    private func startRequestProcessing() {
        requestTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Process write requests
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await request in self.peripheralManager.writeRequests {
                        await self.handleWriteRequest(request)
                    }
                }
                
                group.addTask {
                    for await change in self.peripheralManager.subscriptionChanges {
                        await self.handleSubscriptionChange(change)
                    }
                }
            }
        }
    }
    
    private func handleWriteRequest(_ request: BLEATTWriteRequest) async {
        trafficLogger.logIncoming(request.value)
        
        let response: Data?
        
        switch request.characteristicUUID {
        case .dexcomAuthentication:
            response = handleAuthMessage(request.value)
            
        case .dexcomControl:
            response = handleControlMessage(request.value)
            
        case .dexcomBackfill:
            response = handleBackfillMessage(request.value)
            
        default:
            response = nil
        }
        
        // Respond to request
        await peripheralManager.respond(to: request, withResult: .success)
        
        // Send notification if we have a response
        if let response = response {
            trafficLogger.logOutgoing(response)
            await sendNotification(response, on: request.characteristicUUID)
        }
    }
    
    private func handleSubscriptionChange(_ change: BLESubscriptionChange) async {
        if change.isSubscribed {
            subscriptions.insert(change.characteristicUUID)
            
            // Track connected central
            if connectedCentral == nil {
                connectedCentral = change.central
                state = .connected
                emit(.stateChanged(.connected))
                emit(.centralConnected(change.central))
            }
        } else {
            subscriptions.remove(change.characteristicUUID)
            
            // Check if all subscriptions removed
            if subscriptions.isEmpty {
                if let central = connectedCentral {
                    emit(.centralDisconnected(central))
                }
                connectedCentral = nil
                state = .advertising
                emit(.stateChanged(.advertising))
            }
        }
    }
    
    // MARK: - Message Handlers
    
    private func handleAuthMessage(_ data: Data) -> Data? {
        let result = authSimulator.processMessage(data)
        
        switch result {
        case .sendResponse(let response):
            return response
            
        case .authenticated(let bonded):
            state = .streaming
            emit(.stateChanged(.streaming))
            emit(.authenticated(bonded: bonded))
            startGlucoseStreaming()
            return nil
            
        case .failed(let reason):
            emit(.error("Auth failed: \(reason)"))
            return nil
            
        case .invalidMessage(let reason):
            emit(.error("Invalid auth message: \(reason)"))
            return nil
        }
    }
    
    private func handleControlMessage(_ data: Data) -> Data? {
        guard let simulator = glucoseSimulator else { return nil }
        
        let result = simulator.processMessage(data)
        
        switch result {
        case .sendResponse(let response):
            // Check if this is a glucose response
            if !response.isEmpty && response[0] == 0x31 {  // GlucoseRx
                if let reading = parseGlucoseReading(response) {
                    readingCount += 1
                    emit(.glucoseSent(reading))
                }
            }
            return response
            
        case .invalidMessage(let reason):
            emit(.error("Control error: \(reason)"))
            return nil
        }
    }
    
    private func handleBackfillMessage(_ data: Data) -> Data? {
        guard let simulator = backfillSimulator else { return nil }
        
        let result = simulator.processMessage(data)
        
        switch result {
        case .sendBackfill(let header, let dataPackets):
            // Send header first, then each data packet
            Task {
                await sendNotification(header, on: .dexcomBackfill)
                for packet in dataPackets {
                    await sendNotification(packet, on: .dexcomBackfill)
                }
            }
            return nil  // Sending asynchronously
            
        case .noData(let response):
            return response
            
        case .invalidMessage(let reason):
            emit(.error("Backfill error: \(reason)"))
            return nil
        }
    }
    
    // MARK: - Glucose Streaming
    
    private func startGlucoseStreaming() {
        streamingTask?.cancel()
        
        streamingTask = Task { [weak self] in
            guard let self = self else { return }
            
            let interval = TimeInterval(await self.config.intervalSeconds)
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                // Generate and send reading
                await self.sendGlucoseReading()
            }
        }
    }
    
    private func sendGlucoseReading() async {
        guard let simulator = glucoseSimulator else { return }
        
        // Check for fault injection
        if let injector = faultInjector {
            injector.recordPacket()
            let result = injector.shouldInject(for: "sendGlucose")
            
            switch result {
            case .injected(let fault):
                if await handleInjectedFault(fault) {
                    return // Fault handled, skip normal operation
                }
            case .noFault, .skipped, .error:
                break
            }
        }
        
        // Build glucose request
        let request = Data([0x30])  // GlucoseTx opcode
        trafficLogger.logIncoming(request)
        
        let result = simulator.processMessage(request)
        
        if case .sendResponse(let response) = result {
            trafficLogger.logOutgoing(response)
            
            if let reading = parseGlucoseReading(response) {
                readingCount += 1
                emit(.glucoseSent(reading))
            }
            
            // Notify subscribed centrals
            if subscriptions.contains(.dexcomControl) {
                await sendNotification(response, on: .dexcomControl)
            }
        }
    }
    
    private func sendNotification(_ data: Data, on characteristicUUID: BLEUUID) async {
        let characteristic: BLEMutableCharacteristic
        
        switch characteristicUUID {
        case .dexcomAuthentication:
            characteristic = authCharacteristic
        case .dexcomControl:
            characteristic = controlCharacteristic
        case .dexcomBackfill:
            characteristic = backfillCharacteristic
        default:
            return
        }
        
        _ = await peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
    }
    
    // MARK: - Helpers
    
    private func parseGlucoseReading(_ data: Data) -> SimulatedGlucoseReading? {
        // Response format: opcode(1) + status(1) + sequence(4) + timestamp(4) + glucose(2) + predicted(2) + trend(1)
        guard data.count >= 15, data[0] == 0x31 else { return nil }
        
        let sequence = UInt32(data[2]) | (UInt32(data[3]) << 8) | (UInt32(data[4]) << 16) | (UInt32(data[5]) << 24)
        let timestamp = UInt32(data[6]) | (UInt32(data[7]) << 8) | (UInt32(data[8]) << 16) | (UInt32(data[9]) << 24)
        let glucose = UInt16(data[10]) | (UInt16(data[11]) << 8)
        
        return SimulatedGlucoseReading(
            glucose: glucose,
            sequence: sequence,
            timestamp: timestamp
        )
    }
    
    private static func createGlucoseProvider(config: G6EmulatorConfig) -> GlucoseProvider {
        let base = UInt16(config.patternConfig.baseGlucose)
        
        switch config.pattern {
        case .sine:
            return SineWavePattern(
                baseGlucose: base,
                amplitude: UInt16(config.patternConfig.amplitude),
                periodMinutes: Double(config.patternConfig.periodMinutes)
            )
        case .meal:
            return MealResponsePattern(baseGlucose: base)
        case .random:
            return RandomWalkPattern(
                baseGlucose: base,
                volatility: Double(config.patternConfig.stepSize)
            )
        case .flat:
            return FlatGlucosePattern(baseGlucose: base)
        }
    }
    
    // MARK: - Fault Injection
    
    /// Handle an injected fault
    /// - Returns: true if the fault was handled and normal operation should be skipped
    private func handleInjectedFault(_ fault: FaultType) async -> Bool {
        switch fault {
        case .dropConnection, .dropConnectionAfterTime:
            // Simulate connection drop
            await disconnectCentral(reason: "Fault injection: connection drop")
            return true
            
        case .timeout:
            // Simulate timeout - don't respond
            return true
            
        case .delayResponse(let ms):
            // Delay before responding
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            return false // Continue with normal operation after delay
            
        case .randomDelay(let minMs, let maxMs):
            let delay = Int.random(in: minMs...maxMs)
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            return false
            
        case .forceWarmup:
            // Force sensor into warmup state
            glucoseSimulator?.setSessionState(.warmup)
            return false
            
        case .forceExpired:
            // Force sensor into expired state
            glucoseSimulator?.setSessionState(.expired)
            return false
            
        case .sensorFailure(let code):
            // Emit sensor failure event
            emit(.error("Sensor failure: code 0x\(String(code, radix: 16))"))
            return true
            
        case .lowBattery(let level):
            // Low battery is informational, continue operation
            emit(.error("Low battery: \(level)%"))
            return false
            
        case .returnError(let code):
            // Send error response
            let errorResponse = Data([0xFF, code])
            trafficLogger.logOutgoing(errorResponse)
            if subscriptions.contains(.dexcomControl) {
                await sendNotification(errorResponse, on: .dexcomControl)
            }
            return true
            
        case .corruptChecksum, .corruptData, .duplicatePacket, .dropPacket, .reorderPackets:
            // These require packet-level manipulation, handled elsewhere
            return false
            
        case .occlusion:
            // Pump-specific fault, not applicable to CGM
            return false
            
        case .custom:
            // Custom faults need external handling
            return false
        }
    }
    
    /// Disconnect the connected central
    private func disconnectCentral(reason: String) async {
        if let central = connectedCentral {
            emit(.centralDisconnected(central))
            connectedCentral = nil
            state = .advertising
            emit(.stateChanged(state))
            emit(.error(reason))
        }
    }
    
    // MARK: - Statistics
    
    /// Get current emulator status
    public var status: G6EmulatorStatus {
        G6EmulatorStatus(
            state: state,
            transmitterId: config.transmitterId,
            pattern: config.pattern,
            readingCount: readingCount,
            isAuthenticated: authSimulator.isAuthenticated,
            isBonded: authSimulator.isBonded,
            hasConnectedCentral: connectedCentral != nil,
            subscriptionCount: subscriptions.count,
            trafficEntries: trafficLogger.count
        )
    }
    
    /// Export traffic log
    public func exportTraffic(format: TrafficExportFormat = .json) -> String {
        trafficLogger.export(format: format)
    }
    
    /// Update configuration (only when idle)
    public func updateConfig(_ newConfig: G6EmulatorConfig) throws {
        guard state == .idle || state == .stopped else {
            throw G6EmulatorError.invalidState("Cannot update config while running")
        }
        
        config = newConfig
        authSimulator.reset()
        
        // Recreate glucose provider
        let provider = Self.createGlucoseProvider(config: newConfig)
        let initialState: TransmitterState = newConfig.skipWarmup ? .active : .warmup
        let session = SensorSession(
            startTime: newConfig.skipWarmup ? Date().addingTimeInterval(-3 * 3600) : Date(),
            state: initialState,
            transmitterType: .g6
        )
        
        glucoseSimulator = G6GlucoseSimulator(
            session: session,
            glucoseProvider: provider
        )
        
        // Create backfill provider and simulator
        backfillProvider = GeneratedBackfillProvider(glucoseProvider: provider)
        backfillSimulator = G6BackfillSimulator(backfillProvider: backfillProvider!)
    }
    
    // MARK: - Fault Injection Configuration
    
    /// Set the fault injector for testing error scenarios
    /// - Parameter injector: Fault injector to use
    public func setFaultInjector(_ injector: FaultInjector?) {
        self.faultInjector = injector
    }
    
    /// Check if a fault injector is configured
    public var hasFaultInjector: Bool {
        faultInjector != nil
    }
}

// MARK: - Emulator Status

/// Status of the G6 peripheral emulator
public struct G6EmulatorStatus: Sendable, Codable {
    public let state: G6EmulatorState
    public let transmitterId: String
    public let pattern: GlucosePatternType
    public let readingCount: Int
    public let isAuthenticated: Bool
    public let isBonded: Bool
    public let hasConnectedCentral: Bool
    public let subscriptionCount: Int
    public let trafficEntries: Int
}

// MARK: - Emulator Errors

/// Errors from the G6 peripheral emulator
public enum G6EmulatorError: Error, Sendable {
    case invalidState(String)
    case notPoweredOn
    case advertisingFailed(String)
    case serviceFailed(String)
}
