// SPDX-License-Identifier: AGPL-3.0-or-later
// LibreNFCReader.swift
// CGMKit - Libre NFC Activation
//
// CoreNFC wrapper for reading FreeStyle Libre sensor data.
// Required for initial Libre 2 BLE connection setup.
// Trace: PRD-004, REQ-CGM-002, CGM-022

import Foundation

#if canImport(CoreNFC)
import CoreNFC
#endif

// MARK: - NFC Read Result

/// Result of NFC sensor read
public struct LibreNFCReadResult: Sendable {
    /// Sensor UID (8 bytes)
    public let sensorUID: Data
    
    /// Patch info (6 bytes from command 0xA1)
    public let patchInfo: Data
    
    /// Full FRAM data (344 bytes)
    public let fram: Data
    
    /// Sensor type derived from patchInfo
    public let sensorType: LibreSensorFamily
    
    /// Serial number derived from UID
    public let serialNumber: String
    
    /// Sensor state
    public let sensorState: LibreNFCSensorState
    
    public init(
        sensorUID: Data,
        patchInfo: Data,
        fram: Data,
        sensorType: LibreSensorFamily,
        serialNumber: String,
        sensorState: LibreNFCSensorState
    ) {
        self.sensorUID = sensorUID
        self.patchInfo = patchInfo
        self.fram = fram
        self.sensorType = sensorType
        self.serialNumber = serialNumber
        self.sensorState = sensorState
    }
}

/// Libre sensor family
public enum LibreSensorFamily: String, Sendable, Codable {
    case libre1 = "Libre 1"
    case libre1US = "Libre 1 US"
    case libre2 = "Libre 2"
    case libre2US = "Libre 2 US"
    case libre3 = "Libre 3"
    case librePro = "Libre Pro"
    case libreProH = "Libre Pro H"
    case unknown = "Unknown"
    
    /// Initialize from patchInfo bytes
    public init(patchInfo: Data) {
        guard patchInfo.count >= 6 else {
            self = .unknown
            return
        }
        
        let byte0 = patchInfo[0]
        let byte3 = patchInfo[3]
        
        switch (byte0, byte3) {
        case (0xDF, _):
            self = .libre1
        case (0xA2, _):
            self = .libre1US
        case (0x9D, 0x00):
            self = .libre2
        case (0x9D, 0x01):
            self = .libre2US
        case (0x70, _):
            self = .librePro
        case (0x76, _):
            self = .libreProH
        default:
            self = .unknown
        }
    }
}

/// Sensor state from FRAM byte
public enum LibreNFCSensorState: UInt8, Sendable, Codable {
    case notActivated = 0x01
    case warmingUp = 0x02
    case active = 0x03
    case expired = 0x04
    case shutdown = 0x05
    case failure = 0x06
    case unknown = 0xFF
    
    public var displayName: String {
        switch self {
        case .notActivated: return "Not Activated"
        case .warmingUp: return "Warming Up"
        case .active: return "Active"
        case .expired: return "Expired"
        case .shutdown: return "Shutdown"
        case .failure: return "Failure"
        case .unknown: return "Unknown"
        }
    }
    
    public var isUsable: Bool {
        self == .active || self == .warmingUp
    }
}

// MARK: - NFC Reader Error

/// NFC reading errors
public enum LibreNFCError: Error, Sendable {
    case nfcNotSupported
    case nfcNotAvailable
    case sessionTimeout
    case tagConnectionFailed
    case commandFailed(String)
    case invalidResponse
    case sensorNotFound
    case unsupportedSensorType
    case userCancelled
}

// MARK: - NFC Reader Protocol

/// Protocol for NFC sensor reading
public protocol LibreNFCReaderProtocol: Sendable {
    func startReading() async throws -> LibreNFCReadResult
    func isNFCAvailable() -> Bool
}

// MARK: - iOS Implementation

#if canImport(CoreNFC) && os(iOS)

/// CoreNFC-based Libre sensor reader
public final class LibreNFCReader: NSObject, LibreNFCReaderProtocol, @unchecked Sendable {
    
    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<LibreNFCReadResult, Error>?
    
    /// Session logger for verbose NFC tracing (PROTO-LIBRE-DIAG)
    public var sessionLogger: LibreSessionLogger?
    
    public override init() {
        super.init()
    }
    
    /// Initialize with optional session logger
    public init(sessionLogger: LibreSessionLogger? = nil) {
        self.sessionLogger = sessionLogger
        super.init()
    }
    
    public func isNFCAvailable() -> Bool {
        NFCTagReaderSession.readingAvailable
    }
    
    @MainActor
    public func startReading() async throws -> LibreNFCReadResult {
        guard isNFCAvailable() else {
            throw LibreNFCError.nfcNotSupported
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            // Create NFC session for ISO15693 tags (Libre uses this)
            self.session = NFCTagReaderSession(
                pollingOption: .iso15693,
                delegate: self,
                queue: .main
            )
            self.session?.alertMessage = "Hold your iPhone near the sensor"
            self.session?.begin()
        }
    }
    
    private func finishWithError(_ error: LibreNFCError) {
        session?.invalidate(errorMessage: error.localizedDescription)
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    private func finishWithResult(_ result: LibreNFCReadResult) {
        session?.invalidate()
        continuation?.resume(returning: result)
        continuation = nil
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension LibreNFCReader: NFCTagReaderSessionDelegate {
    
    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // Session is active, waiting for tag
        sessionLogger?.transitionTo(.nfcScanning, reason: "NFC session active")
    }
    
    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nsError = error as NSError
        
        // Check if user cancelled
        if nsError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            sessionLogger?.transitionTo(.idle, reason: "User cancelled")
            continuation?.resume(throwing: LibreNFCError.userCancelled)
        } else if nsError.code == NFCReaderError.readerSessionInvalidationErrorSessionTimeout.rawValue {
            sessionLogger?.transitionTo(.error, reason: "Session timeout")
            continuation?.resume(throwing: LibreNFCError.sessionTimeout)
        } else {
            sessionLogger?.transitionTo(.error, reason: error.localizedDescription)
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
    
    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            sessionLogger?.transitionTo(.error, reason: "Sensor not found")
            finishWithError(.sensorNotFound)
            return
        }
        
        // Must be ISO15693 tag
        guard case .iso15693(let iso15693Tag) = tag else {
            sessionLogger?.transitionTo(.error, reason: "Unsupported sensor type")
            finishWithError(.unsupportedSensorType)
            return
        }
        
        session.alertMessage = "Reading sensor..."
        
        Task {
            do {
                try await session.connect(to: tag)
                let result = try await readSensorData(iso15693Tag)
                finishWithResult(result)
            } catch {
                sessionLogger?.transitionTo(.error, reason: error.localizedDescription)
                if let nfcError = error as? LibreNFCError {
                    finishWithError(nfcError)
                } else {
                    finishWithError(.commandFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private func readSensorData(_ tag: NFCISO15693Tag) async throws -> LibreNFCReadResult {
        // Get sensor UID (8 bytes)
        let uid = tag.identifier
        
        // Log NFC session start
        sessionLogger?.transitionTo(.nfcReading, reason: "readSensorData started")
        
        // Read patch info using custom command 0xA1
        let patchInfo = try await readPatchInfo(tag)
        
        // Read FRAM (344 bytes across multiple blocks)
        let fram = try await readFRAM(tag)
        
        // Log complete FRAM read
        sessionLogger?.logFRAMRead(fram: fram)
        
        // Parse sensor type from patchInfo
        let sensorType = LibreSensorFamily(patchInfo: patchInfo)
        
        // Generate serial number from UID
        let serialNumber = generateSerialNumber(from: uid)
        
        // Get sensor state from FRAM byte 4
        let stateRaw = fram.count > 4 ? fram[4] : 0xFF
        let sensorState = LibreNFCSensorState(rawValue: stateRaw) ?? .unknown
        
        sessionLogger?.transitionTo(.nfcComplete, reason: "FRAM read complete: \(fram.count) bytes")
        
        return LibreNFCReadResult(
            sensorUID: uid,
            patchInfo: patchInfo,
            fram: fram,
            sensorType: sensorType,
            serialNumber: serialNumber,
            sensorState: sensorState
        )
    }
    
    private func readPatchInfo(_ tag: NFCISO15693Tag) async throws -> Data {
        // Custom command 0xA1 to get patch info
        // Manufacturer code 0x07 is Texas Instruments (Libre sensors)
        let response = try await tag.customCommand(
            requestFlags: [.highDataRate],
            customCommandCode: 0xA1,
            customRequestParameters: Data()
        )
        
        guard response.count >= 6 else {
            throw LibreNFCError.invalidResponse
        }
        
        return response
    }
    
    private func readFRAM(_ tag: NFCISO15693Tag) async throws -> Data {
        // Libre FRAM is 344 bytes = 43 blocks of 8 bytes
        // Read in chunks for reliability
        var framData = Data()
        
        // Read blocks 0-42 (43 blocks total)
        let blockCount = 43
        let blocksPerRead = 3  // Read 3 blocks at a time for stability
        
        for startBlock in stride(from: 0, to: blockCount, by: blocksPerRead) {
            let endBlock = min(startBlock + blocksPerRead - 1, blockCount - 1)
            let range = NSRange(location: startBlock, length: endBlock - startBlock + 1)
            
            let blocks = try await tag.readMultipleBlocks(
                requestFlags: [.highDataRate],
                blockRange: range
            )
            
            for block in blocks {
                framData.append(block)
            }
        }
        
        return framData
    }
    
    private func generateSerialNumber(from uid: Data) -> String {
        // Libre serial number is derived from UID using base32-like encoding
        // Simplified version - actual algorithm is more complex
        guard uid.count >= 8 else { return "UNKNOWN" }
        
        let chars = "0123456789ACDEFGHJKLMNPQRTUVWXYZ"
        var serial = ""
        
        // Use bytes 1-7 of UID (byte 0 is manufacturer code)
        let bytes = Array(uid[1...7])
        
        // Encode as base32-ish
        for byte in bytes.prefix(5) {
            let index = Int(byte) % chars.count
            serial.append(chars[chars.index(chars.startIndex, offsetBy: index)])
        }
        
        return serial
    }
}

#else

// MARK: - Non-iOS Stub

/// Stub implementation for non-iOS platforms
public final class LibreNFCReader: LibreNFCReaderProtocol, Sendable {
    
    public init() {}
    
    public func isNFCAvailable() -> Bool {
        false
    }
    
    public func startReading() async throws -> LibreNFCReadResult {
        throw LibreNFCError.nfcNotSupported
    }
}

#endif

// MARK: - Libre2SensorInfo Conversion

extension LibreNFCReadResult {
    /// Convert to Libre2SensorInfo for BLE connection
    public func toLibre2SensorInfo() -> Libre2SensorInfo {
        // Extract enableTime from FRAM (bytes 317-320, little endian)
        var enableTime: UInt32 = 0
        if fram.count >= 321 {
            enableTime = UInt32(fram[317]) |
                         (UInt32(fram[318]) << 8) |
                         (UInt32(fram[319]) << 16) |
                         (UInt32(fram[320]) << 24)
        }
        
        let sensorType: Libre2SensorType
        switch self.sensorType {
        case .libre2:
            sensorType = .libre2
        case .libre2US, .libre1US:
            sensorType = .libreUS14day
        case .libre3:
            sensorType = .libre3
        default:
            sensorType = .libre2  // Default to libre2
        }
        
        return Libre2SensorInfo(
            sensorUID: sensorUID,
            patchInfo: patchInfo,
            enableTime: enableTime,
            serialNumber: serialNumber,
            sensorType: sensorType
        )
    }
}

// MARK: - Error Descriptions

extension LibreNFCError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .nfcNotSupported:
            return "NFC is not supported on this device"
        case .nfcNotAvailable:
            return "NFC is not available (check airplane mode)"
        case .sessionTimeout:
            return "NFC session timed out"
        case .tagConnectionFailed:
            return "Failed to connect to sensor"
        case .commandFailed(let msg):
            return "Command failed: \(msg)"
        case .invalidResponse:
            return "Invalid response from sensor"
        case .sensorNotFound:
            return "No sensor detected"
        case .unsupportedSensorType:
            return "Unsupported sensor type"
        case .userCancelled:
            return "Scan cancelled"
        }
    }
}
