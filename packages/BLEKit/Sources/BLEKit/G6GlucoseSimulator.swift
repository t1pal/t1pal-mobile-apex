// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G6GlucoseSimulator.swift
// BLEKit
//
// Server-side Dexcom G6 glucose request handling for transmitter simulation.
// Trace: PRD-007 REQ-SIM-004

import Foundation

// MARK: - Glucose Status

/// Status codes for glucose responses
public enum G6GlucoseStatus: UInt8, Sendable, Codable {
    /// Valid glucose reading
    case ok = 0x00
    
    /// Sensor warmup in progress
    case warmingUp = 0x01
    
    /// Sensor session expired
    case sessionExpired = 0x02
    
    /// Sensor error
    case sensorError = 0x03
    
    /// No sensor session
    case noSession = 0x04
    
    /// Calibration required (G5/early G6)
    case calibrationRequired = 0x05
    
    /// Sensor failed
    case sensorFailed = 0x06
}

// MARK: - Glucose Reading

/// A simulated glucose reading
public struct SimulatedGlucoseReading: Sendable, Codable {
    /// Glucose value in mg/dL
    public let glucose: UInt16
    
    /// Predicted glucose in mg/dL
    public let predictedGlucose: UInt16
    
    /// Trend value (-8 to +8, roughly mg/dL/min)
    public let trend: Int8
    
    /// Sequence number (increments each reading)
    public let sequence: UInt32
    
    /// Timestamp in transmitter time (seconds since activation)
    public let timestamp: UInt32
    
    /// Create a glucose reading
    public init(
        glucose: UInt16,
        predictedGlucose: UInt16? = nil,
        trend: Int8 = 0,
        sequence: UInt32,
        timestamp: UInt32
    ) {
        self.glucose = glucose
        self.predictedGlucose = predictedGlucose ?? glucose
        self.trend = trend
        self.sequence = sequence
        self.timestamp = timestamp
    }
}

// MARK: - Glucose Result

/// Result of processing a glucose request
public enum G6GlucoseResult: Sendable {
    /// Send this response to the client
    case sendResponse(Data)
    
    /// Invalid or unexpected message
    case invalidMessage(String)
}

// MARK: - Glucose Provider Protocol

/// Protocol for providing glucose values to the simulator
public protocol GlucoseProvider: Sendable {
    /// Get the current glucose value
    func currentGlucose() -> UInt16
    
    /// Get the predicted glucose value
    func predictedGlucose() -> UInt16
    
    /// Get the current trend (-8 to +8)
    func currentTrend() -> Int8
}

// MARK: - Static Glucose Provider

/// Simple glucose provider with static values
public struct StaticGlucoseProvider: GlucoseProvider, Sendable {
    public let glucose: UInt16
    public let predicted: UInt16
    public let trend: Int8
    
    public init(glucose: UInt16, predicted: UInt16? = nil, trend: Int8 = 0) {
        self.glucose = glucose
        self.predicted = predicted ?? glucose
        self.trend = trend
    }
    
    public func currentGlucose() -> UInt16 { glucose }
    public func predictedGlucose() -> UInt16 { predicted }
    public func currentTrend() -> Int8 { trend }
}

// MARK: - G6 Glucose Simulator

/// Server-side G6 glucose request handler for transmitter simulation
///
/// Handles GlucoseTx (0x30) requests and generates GlucoseRx (0x31) responses
/// with appropriate status codes based on session state.
///
/// ## Usage
/// ```swift
/// let session = SensorSession(transmitterType: .g6)
/// let simulator = G6GlucoseSimulator(session: session)
/// 
/// // When client sends GlucoseTx:
/// let result = simulator.processMessage(clientData)
/// switch result {
/// case .sendResponse(let data):
///     // Send GlucoseRx back to client
/// case .invalidMessage(let reason):
///     // Handle error
/// }
/// ```
public final class G6GlucoseSimulator: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Current sensor session
    public private(set) var session: SensorSession
    
    /// Glucose value provider
    public var glucoseProvider: GlucoseProvider
    
    /// Current sequence number (increments each reading)
    public private(set) var sequenceNumber: UInt32 = 0
    
    /// Transmitter activation time (for timestamp calculation)
    public let activationTime: Date
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    /// Create a glucose simulator
    /// - Parameters:
    ///   - session: Sensor session for state tracking
    ///   - glucoseProvider: Provider for glucose values
    ///   - activationTime: Transmitter activation time
    public init(
        session: SensorSession,
        glucoseProvider: GlucoseProvider = StaticGlucoseProvider(glucose: 120),
        activationTime: Date = Date()
    ) {
        self.session = session
        self.glucoseProvider = glucoseProvider
        self.activationTime = activationTime
    }
    
    /// Create with transmitter config
    public convenience init(
        config: SimulatorTransmitterConfig,
        glucoseProvider: GlucoseProvider = StaticGlucoseProvider(glucose: 120)
    ) {
        let session = SensorSession(
            startTime: Date(),
            state: .active,
            transmitterType: config.type
        )
        self.init(
            session: session,
            glucoseProvider: glucoseProvider,
            activationTime: config.activationDate
        )
    }
    
    // MARK: - State Management
    
    /// Set the sensor session state (for testing/fault injection)
    /// - Parameter state: New transmitter state
    public func setSessionState(_ state: TransmitterState) {
        lock.lock()
        defer { lock.unlock() }
        session.state = state
    }
    
    // MARK: - Message Processing
    
    /// Process an incoming glucose-related message
    /// - Parameter data: Raw message data from client
    /// - Returns: Result indicating what action to take
    public func processMessage(_ data: Data) -> G6GlucoseResult {
        lock.lock()
        defer { lock.unlock() }
        
        guard !data.isEmpty else {
            return .invalidMessage("Empty message")
        }
        
        let opcode = data[0]
        
        switch opcode {
        case G6SimOpcode.glucoseTx:
            return handleGlucoseRequest(data)
            
        case G6SimOpcode.transmitterTimeTx:
            return handleTransmitterTimeRequest(data)
            
        default:
            return .invalidMessage("Unknown opcode: \(String(format: "0x%02X", opcode))")
        }
    }
    
    // MARK: - Glucose Request
    
    /// Handle GlucoseTx (0x30) from client
    private func handleGlucoseRequest(_ data: Data) -> G6GlucoseResult {
        // Update session state
        session.updateState()
        
        // Determine status based on session state
        let status: G6GlucoseStatus
        let shouldIncludeGlucose: Bool
        
        switch session.state {
        case .warmup:
            status = .warmingUp
            shouldIncludeGlucose = false
            
        case .active:
            status = .ok
            shouldIncludeGlucose = true
            
        case .expired:
            status = .sessionExpired
            shouldIncludeGlucose = false
            
        case .inactive:
            status = .noSession
            shouldIncludeGlucose = false
            
        case .lowBattery:
            // Still return glucose with low battery
            status = .ok
            shouldIncludeGlucose = true
            
        case .error:
            status = .sensorError
            shouldIncludeGlucose = false
        }
        
        // Generate response
        let response = buildGlucoseResponse(
            status: status,
            includeGlucose: shouldIncludeGlucose
        )
        
        return .sendResponse(response)
    }
    
    /// Build a GlucoseRx response
    private func buildGlucoseResponse(status: G6GlucoseStatus, includeGlucose: Bool) -> Data {
        // Increment sequence for each request
        sequenceNumber += 1
        
        // Calculate timestamp (seconds since activation)
        let timestamp = UInt32(Date().timeIntervalSince(activationTime))
        
        // Get glucose values if we should include them
        let glucoseValue: UInt16
        let predictedValue: UInt16
        let trendValue: Int8
        
        if includeGlucose {
            glucoseValue = glucoseProvider.currentGlucose()
            predictedValue = glucoseProvider.predictedGlucose()
            trendValue = glucoseProvider.currentTrend()
        } else {
            glucoseValue = 0
            predictedValue = 0
            trendValue = 0
        }
        
        // Build response: opcode(1) + status(1) + sequence(4) + timestamp(4) + glucose(2) + predicted(2) + trend(1) = 15 bytes
        var response = Data(count: 15)
        response[0] = G6SimOpcode.glucoseRx
        response[1] = status.rawValue
        
        // Sequence (little-endian)
        withUnsafeBytes(of: sequenceNumber.littleEndian) { bytes in
            response.replaceSubrange(2..<6, with: bytes)
        }
        
        // Timestamp (little-endian)
        withUnsafeBytes(of: timestamp.littleEndian) { bytes in
            response.replaceSubrange(6..<10, with: bytes)
        }
        
        // Glucose (little-endian)
        withUnsafeBytes(of: glucoseValue.littleEndian) { bytes in
            response.replaceSubrange(10..<12, with: bytes)
        }
        
        // Predicted glucose (little-endian)
        withUnsafeBytes(of: predictedValue.littleEndian) { bytes in
            response.replaceSubrange(12..<14, with: bytes)
        }
        
        // Trend
        response[14] = UInt8(bitPattern: trendValue)
        
        return response
    }
    
    // MARK: - Transmitter Time Request
    
    /// Handle TransmitterTimeTx (0x24) from client
    private func handleTransmitterTimeRequest(_ data: Data) -> G6GlucoseResult {
        // Update session state
        session.updateState()
        
        // Calculate times
        let currentTime = UInt32(Date().timeIntervalSince(activationTime))
        let sessionStartTime = UInt32(session.startTime.timeIntervalSince(activationTime))
        
        // Determine status
        let status: UInt8 = session.state == .active ? 0x00 : 0x01
        
        // Build response: opcode(1) + status(1) + currentTime(4) + sessionStartTime(4) = 10 bytes
        var response = Data(count: 10)
        response[0] = G6SimOpcode.transmitterTimeRx
        response[1] = status
        
        withUnsafeBytes(of: currentTime.littleEndian) { bytes in
            response.replaceSubrange(2..<6, with: bytes)
        }
        
        withUnsafeBytes(of: sessionStartTime.littleEndian) { bytes in
            response.replaceSubrange(6..<10, with: bytes)
        }
        
        return .sendResponse(response)
    }
    
    // MARK: - Session Management
    
    /// Start a new sensor session
    public func startSession(transmitterType: TransmitterType = .g6) {
        lock.lock()
        defer { lock.unlock() }
        
        session = SensorSession(
            startTime: Date(),
            state: .warmup,
            transmitterType: transmitterType
        )
        sequenceNumber = 0
    }
    
    /// Stop the current session
    public func stopSession() {
        lock.lock()
        defer { lock.unlock() }
        
        session.state = .inactive
    }
    
    /// Set session to error state
    public func setError() {
        lock.lock()
        defer { lock.unlock() }
        
        session.state = .error
    }
    
    /// Get the last reading
    public func getLastReading() -> SimulatedGlucoseReading? {
        lock.lock()
        defer { lock.unlock() }
        
        guard session.state == .active || session.state == .lowBattery else {
            return nil
        }
        
        return SimulatedGlucoseReading(
            glucose: glucoseProvider.currentGlucose(),
            predictedGlucose: glucoseProvider.predictedGlucose(),
            trend: glucoseProvider.currentTrend(),
            sequence: sequenceNumber,
            timestamp: UInt32(Date().timeIntervalSince(activationTime))
        )
    }
}

// MARK: - Additional Opcodes

extension G6SimOpcode {
    public static let glucoseTx: UInt8 = 0x30
    public static let glucoseRx: UInt8 = 0x31
    public static let transmitterTimeTx: UInt8 = 0x24
    public static let transmitterTimeRx: UInt8 = 0x25
}
