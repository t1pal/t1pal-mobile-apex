// SPDX-License-Identifier: MIT
// RileyLinkSession.swift - Unified RileyLink communication session
//
// DESIGN: Matches Python verification (tools/medtronic-rf/test_quick.py)
// and Loop's patterns (RileyLinkBLEKit + MinimedKit)
//
// FLOW: connect → discover chars → detect firmware → tune → send commands
//
// References:
// - PYTHON-COMPAT-001: Byte-for-byte compatibility with Python
// - RL-SESSION-001: Session-based design (not singleton)

import Foundation
#if canImport(BLEKit)
import BLEKit
#endif

// MARK: - RileyLink Session

/// A session with a connected RileyLink/OrangeLink device
///
/// Usage:
/// ```swift
/// let session = try await RileyLinkSession(peripheral: peripheral)
/// let firmware = try await session.readFirmwareVersion()
/// try await session.tune(to: 916.5)
/// let model = try await session.getPumpModel(serial: "208850")
/// ```
///
/// Design: One session per connected device. No global state.
/// Matches Loop's PumpOpsSession pattern.
public actor RileyLinkSession {
    
    // MARK: - GATT UUIDs (RL-GATT-001)
    
    /// Main RileyLink service UUID
    public static let serviceUUID = "0235733B-99C5-4197-B856-69219C2A3845"
    
    /// Data characteristic - write commands, read responses
    public static let dataCharUUID = "C842E849-5028-42E2-867C-016ADADA9155"
    
    /// Response count - increments when response ready
    public static let responseCountUUID = "6E6C7910-B89E-43A5-A0FE-50C5E2B81F4A"
    
    /// Firmware version characteristic
    public static let firmwareCharUUID = "30D99DC9-7C91-4295-A051-0A104D238CF2"
    
    // MARK: - State
    
    /// The connected BLE peripheral
    public let peripheral: any BLEPeripheralProtocol
    
    /// Detected firmware version
    public private(set) var firmwareVersion: RadioFirmwareVersion = .unknown
    
    /// Raw firmware string (for display)
    public private(set) var firmwareString: String?
    
    /// Current radio frequency (MHz)
    public private(set) var currentFrequency: Double?
    
    // MARK: - Characteristics (discovered once)
    
    private var dataChar: BLECharacteristic?
    private var responseCountChar: BLECharacteristic?
    private var firmwareChar: BLECharacteristic?
    
    // MARK: - Configuration
    
    /// Poll interval for responseCount (matches Python: 100ms)
    public var pollInterval: TimeInterval = 0.1
    
    /// Maximum BLE timeout (seconds)
    public var bleTimeout: TimeInterval = 5.0
    
    /// RF retry count for pump commands
    public var retryCount: Int = 3
    
    /// Optional config object for UI bindings
    /// When set, session reads config values and publishes state updates
    /// Trace: RL-CONFIG-ARCH-001
    private var config: RileyLinkConfig?
    
    // MARK: - Fault Injection (Testing)
    
    /// Optional fault injector for testing error paths
    /// Trace: MDT-FAULT-002, SIM-FAULT-001
    private var faultInjector: PumpFaultInjector?
    
    // MARK: - Session Recovery State (MDT-FAULT-005)
    
    /// Whether the session needs recovery after a BLE disconnect
    public private(set) var needsRecovery: Bool = false
    
    /// Number of recovery attempts made
    public private(set) var recoveryAttempts: Int = 0
    
    /// Maximum recovery attempts before giving up
    public var maxRecoveryAttempts: Int = 3
    
    // MARK: - Initialization
    
    /// Create session with connected peripheral
    /// Automatically discovers characteristics and detects firmware
    /// - Parameters:
    ///   - peripheral: Connected BLE peripheral
    ///   - config: Optional config for UI bindings (reads settings, publishes state)
    ///   - faultInjector: Optional fault injector for testing (default: nil)
    public init(
        peripheral: any BLEPeripheralProtocol,
        config: RileyLinkConfig? = nil,
        faultInjector: PumpFaultInjector? = nil
    ) async throws {
        self.peripheral = peripheral
        self.config = config
        self.faultInjector = faultInjector
        
        RileyLinkLogger.connection.info("Creating session, discovering characteristics...")
        
        // Discover characteristics
        do {
            try await discoverCharacteristics()
        } catch {
            RileyLinkLogger.connection.error("Characteristic discovery failed: \(error.localizedDescription)")
            throw error
        }
        
        // Detect firmware version
        do {
            try await detectFirmware()
        } catch {
            RileyLinkLogger.connection.error("Firmware detection failed: \(error.localizedDescription)")
            throw error
        }
        
        // Update config state
        if let config = config {
            let fwString = self.firmwareString  // Capture outside MainActor
            await MainActor.run {
                config.setConnected(true)
                config.setFirmwareVersion(fwString)
            }
        }
        
        RileyLinkLogger.connection.info("Session created: \(self.firmwareString ?? "unknown")")
    }
    
    // MARK: - Characteristic Discovery
    
    /// Discover RileyLink GATT characteristics
    /// Uses same approach as RileyLink Playground (which works)
    private func discoverCharacteristics() async throws {
        RileyLinkLogger.connection.debug("Discovering RileyLink service...")
        
        // Discover service first (matching RileyLink Playground)
        let services = try await peripheral.discoverServices([.rileyLinkService])
        
        guard let service = services.first(where: { $0.uuid == .rileyLinkService }) else {
            RileyLinkLogger.connection.error("RileyLink service NOT found")
            throw RileyLinkSessionError.missingCharacteristic("service")
        }
        
        RileyLinkLogger.connection.debug("Found RileyLink service, discovering characteristics...")
        
        // Discover all characteristics we need
        let allChars: [BLEUUID] = [.rileyLinkData, .rileyLinkResponseCount, .rileyLinkFirmwareVersion]
        let characteristics = try await peripheral.discoverCharacteristics(allChars, for: service)
        
        // Find data characteristic (required)
        if let char = characteristics.first(where: { $0.uuid == .rileyLinkData }) {
            dataChar = char
            RileyLinkLogger.connection.debug("Data characteristic found")
        } else {
            RileyLinkLogger.connection.error("Data characteristic NOT found")
            throw RileyLinkSessionError.missingCharacteristic("data")
        }
        
        // Find responseCount characteristic (optional)
        responseCountChar = characteristics.first(where: { $0.uuid == .rileyLinkResponseCount })
        
        // Find firmware characteristic (optional)
        firmwareChar = characteristics.first(where: { $0.uuid == .rileyLinkFirmwareVersion })
        
        RileyLinkLogger.connection.debug("Discovered: data=✓ responseCount=\(self.responseCountChar != nil ? "✓" : "✗") firmware=\(self.firmwareChar != nil ? "✓" : "✗")")
    }
    
    /// Detect firmware version from characteristic
    private func detectFirmware() async throws {
        guard let fwChar = firmwareChar else {
            // No firmware characteristic - assume v2+
            firmwareVersion = .assumeV2
            firmwareString = "unknown (assuming v2+)"
            return
        }
        
        let data = try await peripheral.readValue(for: fwChar)
        
        if let str = String(data: data, encoding: .utf8) {
            firmwareString = str.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let version = RadioFirmwareVersion(versionString: str) {
                firmwareVersion = version
            } else {
                // Parse failed but we have string - assume v2+
                firmwareVersion = .assumeV2
            }
        } else {
            // Binary response - store hex, assume v2+
            firmwareString = data.map { String(format: "%02X", $0) }.joined()
            firmwareVersion = .assumeV2
        }
    }
    
    // MARK: - RileyLink Commands
    
    /// Read firmware version string
    public func readFirmwareVersion() async throws -> String {
        guard let fwChar = firmwareChar else {
            return firmwareString ?? "unknown"
        }
        
        let data = try await peripheral.readValue(for: fwChar)
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }
    
    /// Tune radio to frequency (MHz)
    /// Matches Python: 3 register writes for FREQ0/1/2
    public func tune(to frequency: Double) async throws {
        let registers = FrequencyRegisters(mhz: frequency)
        
        // Write FREQ2, FREQ1, FREQ0 (matches Python build_freq_cmds)
        for command in registers.updateCommands(firmwareVersion: firmwareVersion) {
            _ = try await sendCommand(command)
        }
        
        currentFrequency = frequency
        
        // RL-CONFIG-ARCH-001: Update config if available
        if let config = config {
            await MainActor.run {
                config.setCurrentFrequency(frequency)
            }
        }
        
        RileyLinkLogger.connection.info("Tuned to \(frequency) MHz")
    }
    
    /// Send RileyLink command and get response
    /// Low-level method - use higher-level methods when possible
    /// Trace: RL-DIAG-005 (timing instrumentation)
    public func sendCommand(_ command: any RileyLinkCommandProtocol, timeout: TimeInterval? = nil) async throws -> Data {
        guard let dataChar = dataChar else {
            throw RileyLinkSessionError.notConnected
        }
        
        // MDT-FAULT-002: Check for injected faults at BLE layer
        if let injector = faultInjector {
            injector.recordCommand()
            if case .injected(let fault) = injector.shouldInject(for: "sendCommand") {
                RileyLinkLogger.tx.warning("RileyLinkSession: Fault injected - \(fault.displayName)")
                switch fault {
                case .connectionDrop, .connectionTimeout:
                    throw RileyLinkSessionError.timeout("Fault injected: \(fault.displayName)")
                case .communicationError(let code):
                    throw RileyLinkSessionError.unknownResponse(code)
                case .packetCorruption:
                    // Continue but data will be corrupted downstream
                    break
                case .bleDisconnectMidCommand:
                    // MDT-FAULT-005: Simulate BLE disconnect during command
                    // Mark session as requiring recovery
                    self.needsRecovery = true
                    throw RileyLinkSessionError.bleDisconnected(recoverable: true)
                default:
                    throw RileyLinkSessionError.faultInjected(fault.displayName)
                }
            }
        }
        
        // RL-DIAG-005: Start timing trace
        let commandStart = Date()
        var timingPhases: [TimingTraceEntry.Phase] = []
        
        // Frame command with length prefix (matches Python with_len)
        let commandData = command.data
        var framedBuffer = Data([UInt8(commandData.count)])
        framedBuffer.append(commandData)
        let framed = framedBuffer
        
        // Log what we're sending
        let hex = framed.map { String(format: "%02X", $0) }.joined(separator: " ")
        RileyLinkLogger.tx.info("TX: [\(hex)] (\(framed.count) bytes)")
        
        // RL-CONFIG-ARCH-001: Log to config if available
        if let config = config {
            await MainActor.run {
                config.addPacket(direction: .tx, data: framed, label: String(describing: type(of: command)))
            }
        }
        
        // RL-DIAG-005: Time responseCount read
        let rcReadStart = Date()
        
        // Read initial responseCount
        var initialRC: UInt8 = 0
        if let rcChar = responseCountChar {
            let rcData = try await peripheral.readValue(for: rcChar)
            initialRC = rcData.first ?? 0
        }
        
        timingPhases.append(TimingTraceEntry.Phase(
            name: "Read Initial RC",
            duration: Date().timeIntervalSince(rcReadStart)
        ))
        
        // RL-DIAG-005: Time BLE write
        let writeStart = Date()
        
        // Write command
        try await peripheral.writeValue(framed, for: dataChar, type: .withResponse)
        
        timingPhases.append(TimingTraceEntry.Phase(
            name: "BLE Write",
            duration: Date().timeIntervalSince(writeStart)
        ))
        
        // Use command-specific timeout if provided, otherwise default
        // For wakeup commands with 12s RF timeout, BLE must wait at least that long
        let effectiveTimeout = timeout ?? bleTimeout
        var responseReady = false
        var pollCount = 0
        
        // RL-DIAG-005: Time response polling
        // PROD-HARDEN-021: Use structured polling with proper timeout
        let pollStart = Date()
        
        if let rcChar = responseCountChar {
            // Poll until responseCount changes from initial value
            let startTime = Date()
            while Date().timeIntervalSince(startTime) < effectiveTimeout {
                let rcData = try await peripheral.readValue(for: rcChar)
                pollCount += 1
                if let current = rcData.first, current != initialRC {
                    RileyLinkLogger.rx.debug("responseCount changed: \(initialRC) → \(current) after \(pollCount) polls")
                    responseReady = true
                    break
                }
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
            
            if !responseReady {
                timingPhases.append(TimingTraceEntry.Phase(
                    name: "Poll Response (\(pollCount)x)",
                    duration: Date().timeIntervalSince(pollStart)
                ))
                throw RileyLinkSessionError.timeout("responseCount stuck at \(initialRC)")
            }
        }
        
        timingPhases.append(TimingTraceEntry.Phase(
            name: "Poll Response (\(pollCount)x)",
            duration: Date().timeIntervalSince(pollStart)
        ))
        
        // RL-DIAG-005: Time response read
        let readStart = Date()
        
        // Read response
        let response = try await peripheral.readValue(for: dataChar)
        
        timingPhases.append(TimingTraceEntry.Phase(
            name: "Read Response",
            duration: Date().timeIntervalSince(readStart)
        ))
        
        let responseHex = response.map { String(format: "%02X", $0) }.joined(separator: " ")
        RileyLinkLogger.rx.info("RX: [\(responseHex)] (\(response.count) bytes)")
        
        // RL-CONFIG-ARCH-001: Log response to config if available
        // RL-DIAG-005: Log timing trace
        let totalDuration = Date().timeIntervalSince(commandStart)
        let commandName = String(describing: type(of: command))
        
        if let config = config {
            let capturedPhases = timingPhases
            await MainActor.run {
                config.addPacket(direction: .rx, data: response, label: "Response")
                config.addTimingTrace(commandName: commandName, phases: capturedPhases, totalDuration: totalDuration)
            }
        }
        
        RileyLinkLogger.tx.debug("Timing: \(commandName) completed in \(String(format: "%.1f", totalDuration * 1000))ms")
        
        return response
    }
    
    // MARK: - Pump Commands (Medtronic)
    
    /// Send pump message via RF and get response
    /// Handles 4b6b encoding, CRC, and response parsing
    public func sendPumpMessage(
        _ message: PumpMessage,
        repeatCount: Int = 0,
        timeout: TimeInterval = 0.5,
        retries: Int? = nil
    ) async throws -> PumpMessage {
        // MDT-FAULT-002: Check for injected faults at RF layer
        if let injector = faultInjector {
            if case .injected(let fault) = injector.shouldInject(for: "sendPumpMessage") {
                RileyLinkLogger.tx.warning("RileyLinkSession: Pump fault injected - \(fault.displayName)")
                switch fault {
                case .occlusion:
                    throw RileyLinkSessionError.faultInjected("Occlusion detected")
                case .connectionTimeout:
                    throw RileyLinkSessionError.rfTimeout
                case .communicationError(let code):
                    throw RileyLinkSessionError.unknownResponse(code)
                case .motorStall:
                    throw RileyLinkSessionError.faultInjected("Motor stall")
                case .emptyReservoir:
                    throw RileyLinkSessionError.faultInjected("Empty reservoir")
                case .batteryDepleted:
                    throw RileyLinkSessionError.faultInjected("Battery depleted")
                default:
                    throw RileyLinkSessionError.faultInjected(fault.displayName)
                }
            }
        }
        
        // Encode message with 4b6b
        let packet = MinimedPacket(outgoingData: message.txData)
        let encoded = packet.encodedData()
        
        // Log raw message and encoded packet
        let rawHex = message.txData.map { String(format: "%02X", $0) }.joined(separator: " ")
        let encodedHex = encoded.map { String(format: "%02X", $0) }.joined(separator: " ")
        RileyLinkLogger.tx.info("Pump TX \(message.messageType.displayName): [\(rawHex)]")
        RileyLinkLogger.tx.debug("4b6b encoded (\(encoded.count) bytes): [\(encodedHex)]")
        
        // Use explicit retries if provided, otherwise default
        let effectiveRetries = retries ?? retryCount
        
        // Build SendAndListen command
        let command = SendAndListenCommand(
            outgoing: encoded,
            sendChannel: 0,
            repeatCount: UInt8(clamping: repeatCount),
            delayBetweenPacketsMS: 0,
            listenChannel: 0,
            timeoutMS: UInt32(timeout * 1000),
            retryCount: UInt8(effectiveRetries),
            preambleExtensionMS: 0,
            firmwareVersion: firmwareVersion
        )
        
        // Send and get response
        // BLE timeout must be at least as long as RF timeout + buffer
        let bleWaitTime = timeout + 1.0  // RF timeout + 1 second buffer
        let response = try await sendCommand(command, timeout: bleWaitTime)
        
        // Parse response code
        guard response.count >= 1 else {
            throw RileyLinkSessionError.emptyResponse
        }
        
        let code = response[0]
        switch code {
        case 0xDD:
            // Success - decode 4b6b response
            let rfData = response.dropFirst(3)  // Skip status, RSSI, counter
            let rfHex = rfData.map { String(format: "%02X", $0) }.joined(separator: " ")
            RileyLinkLogger.rx.debug("RF response (\(rfData.count) bytes): [\(rfHex)]")
            
            guard let decodedPacket = MinimedPacket(encodedData: Data(rfData)) else {
                RileyLinkLogger.rx.error("4b6b decode FAILED for: [\(rfHex)]")
                throw RileyLinkSessionError.decodeError("4b6b decode failed")
            }
            
            let decodedHex = decodedPacket.data.map { String(format: "%02X", $0) }.joined(separator: " ")
            RileyLinkLogger.rx.info("Pump RX decoded: [\(decodedHex)]")
            
            guard let responseMsg = PumpMessage(rxData: decodedPacket.data) else {
                RileyLinkLogger.rx.error("PumpMessage parse FAILED for: [\(decodedHex)]")
                throw RileyLinkSessionError.decodeError("PumpMessage parse failed")
            }
            
            RileyLinkLogger.rx.info("Pump RX \(responseMsg.messageType.displayName) from \(responseMsg.addressHex): body=\(responseMsg.body.count) bytes")
            
            // Validate address matches (crosstalk detection)
            guard responseMsg.addressHex == message.addressHex else {
                throw RileyLinkSessionError.crosstalk(
                    expected: message.addressHex,
                    received: responseMsg.addressHex
                )
            }
            
            return responseMsg
            
        case 0xAA:
            throw RileyLinkSessionError.rfTimeout
            
        default:
            throw RileyLinkSessionError.unknownResponse(code)
        }
    }
    
    /// Wake pump and read model number
    /// Complete flow matching Loop and Python
    public func getPumpModel(
        serial: String,
        frequency: Double = 916.5,
        wakeFirst: Bool = true
    ) async throws -> String {
        // Tune if needed
        if currentFrequency != frequency {
            try await tune(to: frequency)
        }
        
        // Wake pump if requested
        if wakeFirst {
            try await wakePump(serial: serial)
        }
        
        // Send READ_MODEL command
        let message = PumpMessage.readCommand(
            address: serial,
            messageType: .getPumpModel
        )
        
        let response = try await sendPumpMessage(
            message,
            repeatCount: 0,
            timeout: 0.5
        )
        
        // Extract model from response body
        // Format: [length][model ASCII bytes]
        guard response.body.count >= 2 else {
            throw RileyLinkSessionError.invalidResponse("Model response too short")
        }
        
        let modelBytes = response.body.dropFirst()  // Skip length byte
        return String(bytes: modelBytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? "Unknown"
    }
    
    /// Wake pump with RF burst
    /// Loop uses a 2-step process:
    /// 1. Short wake burst (255 repeats) - alerts pump radio
    /// 2. Long power message with 65-byte body - sets duration
    /// 
    /// Trace: RL-CONFIG-ARCH-001 - reads from config if available
    public func wakePump(serial: String, durationMinutes: Int? = nil) async throws {
        // Check config for skipWakeup
        if let config = config {
            let configSnapshot = await MainActor.run { config.snapshot }
            if configSnapshot.skipWakeup {
                RileyLinkLogger.tx.info("Skipping wakeup (config.skipWakeup=true)")
                return
            }
        }
        
        // Use config values if available, otherwise defaults
        let duration: Int
        let repeats: Int
        if let config = config {
            let configSnapshot = await MainActor.run { config.snapshot }
            duration = durationMinutes ?? configSnapshot.wakeupDurationMinutes
            repeats = configSnapshot.wakeupRepeatCount
        } else {
            duration = durationMinutes ?? 2
            repeats = 255
        }
        
        RileyLinkLogger.tx.info("Waking pump \(serial) (duration=\(duration)min, repeats=\(repeats))...")
        
        // Step 1: Short wake burst - body MUST be [0x00], not empty!
        // SWIFT-RL-002: Medtronic requires body byte even for wakeup
        let shortWakeMessage = PumpMessage(
            address: serial,
            messageType: .powerOn,
            body: Data([0x00])  // Single zero byte required
        )
        
        // Send N repeats with 12 second timeout to catch sleeping pump
        // Loop: getResponse(shortPowerMessage, repeatCount: 255, timeout: 12s, retryCount: 0)
        RileyLinkLogger.tx.info("Sending short wake burst (\(repeats) repeats, 12s)...")
        _ = try? await sendPumpMessage(
            shortWakeMessage,
            repeatCount: repeats,
            timeout: 12.0,
            retries: 0  // No retries for wakeup burst
        )
        
        // Step 2: Long power message with proper 65-byte body
        let powerBody = PowerOnCarelinkMessageBody(durationMinutes: UInt8(duration))
        let longPowerMessage = PumpMessage(
            address: serial,
            messageType: .powerOn,
            messageBody: powerBody
        )
        
        // Send and wait for ACK
        // Loop: getResponse(longPowerMessage, repeatCount: 0, timeout: 200ms, retryCount: 3)
        RileyLinkLogger.tx.info("Sending power on for \(duration) minutes...")
        _ = try? await sendPumpMessage(
            longPowerMessage,
            repeatCount: 0,
            timeout: 0.2,  // 200ms per Loop (standardPumpResponseWindow)
            retries: 3     // Normal retry count
        )
        
        // PROD-HARDEN-021: Use constant for post-wakeup delay
        try? await Task.sleep(nanoseconds: PumpTimingConstants.postWakeupDelayNanos)
        RileyLinkLogger.tx.info("Pump should be awake")
    }
    
    /// Read pump status (bolusing, suspended, etc.)
    /// RL-SESSION-003: Session-based status reading
    /// MDT-DIAG: Match Loop's getPumpStatus - use 200ms timeout with 3 retries
    public func readPumpStatus(
        serial: String,
        frequency: Double = 916.5,
        wakeFirst: Bool = true
    ) async throws -> MedtronicStatusResponse {
        // Tune if needed
        if currentFrequency != frequency {
            try await tune(to: frequency)
        }
        
        // Wake pump if requested - Loop's getPumpStatus() ALWAYS wakes
        if wakeFirst {
            try await wakePump(serial: serial)
        }
        
        // Send READ_PUMP_STATUS command (0xCE)
        let message = PumpMessage.readCommand(
            address: serial,
            messageType: .readPumpStatus
        )
        
        RileyLinkLogger.tx.info("Reading pump status...")
        // MDT-DIAG: Use 200ms timeout with 3 retries (matches Loop)
        let response = try await sendPumpMessage(
            message,
            repeatCount: 0,
            timeout: 0.2,
            retries: 3
        )
        
        // Parse status response (3 bytes expected)
        guard let status = MedtronicStatusResponse.parse(from: response.body) else {
            throw RileyLinkSessionError.invalidResponse("Failed to parse pump status")
        }
        
        RileyLinkLogger.tx.info("Pump status: bolusing=\(status.bolusing), suspended=\(status.suspended)")
        return status
    }
    
    /// Read reservoir level (remaining insulin)
    /// RL-SESSION-004: Session-based reservoir reading
    /// MDT-DIAG: Match Loop's getResponse - use 200ms timeout with 3 retries
    public func readReservoir(
        serial: String,
        frequency: Double = 916.5,
        wakeFirst: Bool = true,
        pumpModel: String? = nil
    ) async throws -> MedtronicReservoirResponse {
        // Tune if needed
        if currentFrequency != frequency {
            try await tune(to: frequency)
        }
        
        // Wake pump if requested
        if wakeFirst {
            try await wakePump(serial: serial)
        }
        
        // Send READ_REMAINING_INSULIN command (0x73)
        let message = PumpMessage.readCommand(
            address: serial,
            messageType: .readRemainingInsulin
        )
        
        RileyLinkLogger.tx.info("Reading reservoir level...")
        // MDT-DIAG: Use 200ms timeout with 3 retries (matches Loop)
        let response = try await sendPumpMessage(
            message,
            repeatCount: 0,
            timeout: 0.2,
            retries: 3
        )
        
        // Determine scale based on pump model (523+ uses scale 40, older uses 10)
        // MDT-DIAG-FIX: Use MinimedPumpModel.isPre523 instead of hasPrefix("5")
        // hasPrefix("5") incorrectly treats 515, 522 as newer pumps
        let scale: Int
        if let modelStr = pumpModel, let model = MinimedPumpModel(rawValue: modelStr) {
            scale = model.insulinBitPackingScale
        } else {
            // Default to scale 10 for unknown models (safer - larger value = less insulin displayed)
            scale = 10
        }
        
        // Parse reservoir response
        guard let reservoir = MedtronicReservoirResponse.parse(from: response.body, scale: scale) else {
            throw RileyLinkSessionError.invalidResponse("Failed to parse reservoir level")
        }
        
        RileyLinkLogger.tx.info("Reservoir: \(reservoir.unitsRemaining)U remaining")
        return reservoir
    }
    
    /// Read pump history page
    /// MDT-HIST-031: Implement history page retrieval
    /// - Parameters:
    ///   - serial: Pump serial number
    ///   - pageNumber: History page to read (0 = most recent)
    ///   - frequency: RF frequency in MHz
    ///   - wakeFirst: Whether to wake the pump first
    ///   - pumpModel: Optional pump model string for parsing
    /// - Returns: Parsed history events
    public func readHistoryPage(
        serial: String,
        pageNumber: Int = 0,
        frequency: Double = 916.5,
        wakeFirst: Bool = true,
        pumpModel: String? = nil
    ) async throws -> [MinimedHistoryEvent] {
        // Tune if needed
        if currentFrequency != frequency {
            try await tune(to: frequency)
        }
        
        // Wake pump if requested
        if wakeFirst {
            try await wakePump(serial: serial)
        }
        
        // MDT-DIAG-002: Use runCommandWithArguments pattern from Loop
        // Step 1: Send SHORT message (opcode only, empty body) → get ACK
        // Step 2: Send FULL message (with pageNum argument in 65-byte body) → get response
        // This 2-step pattern is required for commands with arguments
        
        // Step 1: Short message to prepare pump
        let shortMessage = PumpMessage.readCommand(address: serial, messageType: .getHistoryPage)
        RileyLinkLogger.tx.info("Reading history page \(pageNumber) (short message)...")
        _ = try await sendPumpMessage(shortMessage, repeatCount: 0, timeout: 0.2, retries: 3)
        
        // Step 2: Full message with page number argument
        // MDT-DIAG-FIX: Body must be 65 bytes (CarelinkLongMessageBody), not 2 bytes!
        // Format: [numArgs=0x01][pageNumber] + 63 zero-byte padding = 65 bytes total
        // Matches Loop's GetHistoryPageCarelinkMessageBody.init(pageNum:)
        var pageRequestBody = Data([0x01, UInt8(clamping: pageNumber)])
        pageRequestBody.append(Data(repeating: 0, count: 63))  // Pad to 65 bytes
        let message = PumpMessage(
            address: serial,
            messageType: .getHistoryPage,
            messageBody: GenericMessageBody(data: pageRequestBody)
        )
        
        RileyLinkLogger.tx.info("Sending history page \(pageNumber) arguments...")
        
        // Collect frames - history page is 1024 bytes = 16 frames × 64 bytes
        var pageData = Data()
        var expectedFrameNum = 1
        
        // Send full request - use standard 200ms timeout with retries
        var response = try await sendPumpMessage(message, repeatCount: 0, timeout: 0.2, retries: 3)
        
        while pageData.count < 1024 {
            // Parse frame response
            guard response.body.count >= 65 else {
                throw RileyLinkSessionError.invalidResponse("Short frame: \(response.body.count) bytes, expected 65")
            }
            
            let frameHeader = response.body[0]
            let frameNumber = Int(frameHeader & 0x7F)
            let isLastFrame = (frameHeader & 0x80) != 0
            let frameData = response.body.subdata(in: 1..<65)
            
            guard frameNumber == expectedFrameNum else {
                throw RileyLinkSessionError.invalidResponse("Frame sequence error: got \(frameNumber), expected \(expectedFrameNum)")
            }
            
            pageData.append(frameData)
            expectedFrameNum += 1
            
            RileyLinkLogger.tx.debug("Received frame \(frameNumber)/16, \(frameData.count) bytes")
            
            if isLastFrame || pageData.count >= 1024 {
                // Send final ACK
                let ackMessage = PumpMessage.readCommand(address: serial, messageType: .pumpAck)
                _ = try? await sendPumpMessage(ackMessage, repeatCount: 0, timeout: 0.2)
                break
            }
            
            // ACK and request next frame - use standard 200ms timeout with retries
            let ackMessage = PumpMessage.readCommand(address: serial, messageType: .pumpAck)
            response = try await sendPumpMessage(ackMessage, repeatCount: 0, timeout: 0.2, retries: 3)
        }
        
        guard pageData.count == 1024 else {
            throw RileyLinkSessionError.invalidResponse("Short history page: \(pageData.count) bytes, expected 1024")
        }
        
        // Validate CRC16 - last 2 bytes are CRC of first 1022 bytes
        let dataPart = pageData.subdata(in: 0..<1022)
        let expectedCRC = (UInt16(pageData[1022]) << 8) | UInt16(pageData[1023])
        let computedCRC = CRC16.compute(dataPart)
        
        guard expectedCRC == computedCRC else {
            RileyLinkLogger.tx.warning("History page CRC mismatch: expected \(String(format: "%04X", expectedCRC)), got \(String(format: "%04X", computedCRC))")
            throw RileyLinkSessionError.invalidResponse("History page CRC mismatch")
        }
        
        RileyLinkLogger.tx.info("History page \(pageNumber) received: \(pageData.count) bytes, CRC valid")
        
        // Parse events using MinimedHistoryParser
        let isLargerPump = pumpModel.map { model in
            guard model.count >= 3,
                  let generation = Int(model.suffix(2)) else { return false }
            return generation >= 23
        } ?? false
        
        let parser = MinimedHistoryParser(isLargerPump: isLargerPump)
        let events = parser.parse(dataPart)
        
        RileyLinkLogger.tx.info("Parsed \(events.count) history events from page \(pageNumber)")
        return events
    }
    
    /// Read basal schedule from pump
    /// CRIT-PROFILE-011: Port getBasalSchedule from PumpOpsSession
    /// - Parameters:
    ///   - serial: Pump serial number
    ///   - profile: Which basal profile to read (standard, A, or B)
    ///   - frequency: RF frequency in MHz
    ///   - wakeFirst: Whether to wake the pump first
    /// - Returns: Array of basal schedule entries
    public func readBasalSchedule(
        serial: String,
        profile: MedtronicBasalProfile = .standard,
        frequency: Double = 916.5,
        wakeFirst: Bool = true
    ) async throws -> [MedtronicBasalScheduleEntry] {
        // Tune if needed
        if currentFrequency != frequency {
            try await tune(to: frequency)
        }
        
        // Wake pump if requested
        if wakeFirst {
            try await wakePump(serial: serial)
        }
        
        // Select message type based on profile
        let messageType: MessageType
        switch profile {
        case .standard: messageType = .readProfileSTD512
        case .profileA: messageType = .readProfileA512
        case .profileB: messageType = .readProfileB512
        }
        
        RileyLinkLogger.tx.info("Reading basal schedule (profile: \(String(describing: profile)))...")
        
        // Multi-frame read loop per Loop's getBasalSchedule pattern
        // Schedule is 192 bytes = 3 frames × 64 bytes
        var scheduleData = Data()
        var isFinished = false
        var isFirstFrame = true
        
        while !isFinished {
            // Build message - first request or ACK for continuation
            let message: PumpMessage
            if isFirstFrame {
                message = PumpMessage.readCommand(address: serial, messageType: messageType)
                isFirstFrame = false
            } else {
                // ACK to request next frame
                message = PumpMessage.readCommand(address: serial, messageType: .pumpAck)
            }
            
            // Send and get response
            let response = try await sendPumpMessage(message, repeatCount: 0, timeout: 0.2, retries: 3)
            
            // Parse frame header
            guard response.body.count >= 1 else {
                throw RileyLinkSessionError.invalidResponse("Empty basal schedule frame")
            }
            
            let frameHeader = response.body[0]
            isFinished = (frameHeader & 0x80) != 0
            
            // Extract frame content (skip header byte)
            let contentEnd = min(response.body.count, 65)
            let frameContent = response.body.subdata(in: 1..<contentEnd)
            scheduleData.append(frameContent)
            
            RileyLinkLogger.tx.debug("Basal frame: \(frameContent.count) bytes, last=\(isFinished)")
        }
        
        // Parse schedule data into entries
        // Each entry is 3 bytes: [rate_lo][rate_hi][time_slot]
        let entries = Self.parseBasalScheduleData(scheduleData)
        
        RileyLinkLogger.tx.info("Parsed \(entries.count) basal entries from profile \(String(describing: profile))")
        return entries
    }
    
    /// Parse raw basal schedule data into entries
    /// Each entry is 3 bytes: [rate_lo][rate_hi][time_slot]
    /// Parsing stops when time_slot >= 48 (invalid/end marker)
    private static func parseBasalScheduleData(_ data: Data) -> [MedtronicBasalScheduleEntry] {
        var entries: [MedtronicBasalScheduleEntry] = []
        var offset = 0
        
        while offset + 3 <= data.count {
            let entryData = data.subdata(in: offset..<(offset + 3))
            
            // Check for end marker (time_slot byte = 0x3F or >= 48)
            let timeSlot = entryData[2]
            if timeSlot >= 48 {
                break
            }
            
            if let entry = MedtronicBasalScheduleEntry(rawValue: entryData) {
                entries.append(entry)
            }
            
            offset += 3
        }
        
        return entries
    }
    
    /// Write basal schedule to pump
    /// CRIT-PROFILE-012: Port setBasalSchedule from PumpOpsSession
    /// - Parameters:
    ///   - serial: Pump serial number
    ///   - entries: Basal schedule entries to write
    ///   - profile: Which basal profile to write (standard, A, or B)
    ///   - frequency: RF frequency in MHz
    ///   - wakeFirst: Whether to wake the pump first
    /// - Throws: RileyLinkSessionError on communication failure
    public func writeBasalSchedule(
        serial: String,
        entries: [MedtronicBasalScheduleEntry],
        profile: MedtronicBasalProfile = .standard,
        frequency: Double = 916.5,
        wakeFirst: Bool = true
    ) async throws {
        // Validate entries
        guard !entries.isEmpty else {
            throw RileyLinkSessionError.invalidResponse("Empty basal schedule")
        }
        
        // Tune if needed
        if currentFrequency != frequency {
            try await tune(to: frequency)
        }
        
        // Wake pump if requested
        if wakeFirst {
            try await wakePump(serial: serial)
        }
        
        // Build command
        let command = MedtronicBasalScheduleCommand(entries: entries, profile: profile)
        
        // Select opcode based on profile
        let opcode: MessageType
        switch profile {
        case .standard: opcode = .setBasalProfileSTD
        case .profileA: opcode = .setBasalProfileA
        case .profileB: opcode = .setBasalProfileB
        }
        
        RileyLinkLogger.tx.info("Writing basal schedule (profile: \(String(describing: profile)), \(entries.count) entries)...")
        
        // Multi-frame write per Loop's setBasalSchedule pattern
        // Schedule is 192 bytes = 3 frames × 64 bytes
        let frames = command.frames
        
        for (index, frame) in frames.enumerated() {
            let isLast = index == frames.count - 1
            RileyLinkLogger.tx.info("Sending basal schedule frame \(index + 1)/\(frames.count)")
            
            // Build the pump message with frame data
            // Frame format: 65 bytes (1 header + 64 content)
            let message = PumpMessage(
                address: serial,
                messageType: opcode,
                messageBody: GenericMessageBody(data: frame)
            )
            
            // Send the frame
            let response = try await sendPumpMessage(message, repeatCount: 0, timeout: 0.2, retries: 3)
            
            // Verify ACK response (pump returns 0x06 ACK)
            guard response.body.count >= 1 else {
                RileyLinkLogger.tx.error("Empty response for frame \(index + 1)")
                throw RileyLinkSessionError.invalidResponse("Empty response for frame \(index + 1)")
            }
            
            // Last frame should have a longer timeout for pump processing
            if isLast {
                // Allow extra time for pump to apply schedule
                try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            }
        }
        
        RileyLinkLogger.tx.info("Basal schedule written successfully")
    }
    
    // MARK: - Fault Injection (Testing)
    
    /// Set fault injector for testing error paths
    /// - Parameter injector: The fault injector to use, or nil to disable
    /// Trace: MDT-FAULT-002, SIM-FAULT-001
    public func setFaultInjector(_ injector: PumpFaultInjector?) {
        self.faultInjector = injector
    }
    
    /// Get current fault injector
    public var currentFaultInjector: PumpFaultInjector? {
        faultInjector
    }
    
    // MARK: - Session Recovery (MDT-FAULT-005)
    
    /// Attempt to recover the session after a BLE disconnect
    /// - Returns: True if recovery was successful
    /// - Throws: RileyLinkSessionError if recovery fails
    /// Trace: MDT-FAULT-005
    public func attemptRecovery() async throws -> Bool {
        guard needsRecovery else {
            return true  // No recovery needed
        }
        
        recoveryAttempts += 1
        let currentAttempt = recoveryAttempts
        let maxAttempts = maxRecoveryAttempts
        RileyLinkLogger.tx.info("RileyLinkSession: Recovery attempt \(currentAttempt)/\(maxAttempts)")
        
        if currentAttempt > maxAttempts {
            RileyLinkLogger.tx.error("RileyLinkSession: Max recovery attempts exceeded")
            throw RileyLinkSessionError.bleDisconnected(recoverable: false)
        }
        
        // Re-discover characteristics to verify connection is valid
        do {
            try await discoverCharacteristics()
            
            // Verify we can still communicate
            _ = try await readFirmwareVersion()
            
            // Reset recovery state on success
            needsRecovery = false
            recoveryAttempts = 0
            RileyLinkLogger.tx.info("RileyLinkSession: Recovery successful")
            return true
        } catch {
            RileyLinkLogger.tx.warning("RileyLinkSession: Recovery failed - \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Reset recovery state (for testing)
    /// Trace: MDT-FAULT-005
    public func resetRecoveryState() {
        needsRecovery = false
        recoveryAttempts = 0
    }
    
    /// Check if session is in a healthy state
    /// Trace: MDT-FAULT-005
    public var isHealthy: Bool {
        !needsRecovery && dataChar != nil
    }
}

// MARK: - Session Errors

public enum RileyLinkSessionError: LocalizedError, Sendable {
    case notConnected
    case missingCharacteristic(String)
    case timeout(String)
    case emptyResponse
    case decodeError(String)
    case rfTimeout
    case unknownResponse(UInt8)
    case crosstalk(expected: String, received: String)
    case invalidResponse(String)
    case faultInjected(String)  // MDT-FAULT-002: Injected test fault
    case bleDisconnected(recoverable: Bool)  // MDT-FAULT-005: BLE disconnect mid-command
    case wrongChannelResponse(sent: UInt8, received: UInt8)  // MDT-FAULT-006: RF channel mismatch
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to RileyLink"
        case .missingCharacteristic(let name):
            return "Missing \(name) characteristic"
        case .timeout(let details):
            return "BLE timeout: \(details)"
        case .emptyResponse:
            return "Empty response from RileyLink"
        case .decodeError(let details):
            return "Decode error: \(details)"
        case .rfTimeout:
            return "RF timeout - pump did not respond"
        case .unknownResponse(let code):
            return "Unknown response code: 0x\(String(format: "%02X", code))"
        case .crosstalk(let expected, let received):
            return "Crosstalk detected: expected \(expected), got \(received)"
        case .invalidResponse(let details):
            return "Invalid response: \(details)"
        case .faultInjected(let details):
            return "Fault injected: \(details)"
        case .bleDisconnected(let recoverable):
            return recoverable ? "BLE disconnected (recoverable)" : "BLE disconnected"
        case .wrongChannelResponse(let sent, let received):
            return "Wrong channel response: sent on \(sent), received on \(received)"
        }
    }
}

// MARK: - RileyLink Command Protocol

/// Protocol for RileyLink firmware commands
public protocol RileyLinkCommandProtocol: Sendable {
    /// Serialized command bytes (without length prefix)
    var data: Data { get }
}

// Conform existing commands
extension GetVersionCommand: RileyLinkCommandProtocol {}
extension UpdateRegisterCommand: RileyLinkCommandProtocol {}
extension SendAndListenCommand: RileyLinkCommandProtocol {}
extension SetSoftwareEncodingCommand: RileyLinkCommandProtocol {}
