// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TandemJPAKEMessages.swift
// PumpKit
//
// J-PAKE (EC-JPAKE) message structures for Tandem t:slim X2 authentication.
// Uses P-256 curve with 6-digit numeric pairing code.
//
// Reference: conformance/protocol/tandem/fixture_x2_auth.json
// Trace: TANDEM-IMPL-002, TANDEM-AUDIT-003
//
// Protocol flow (10 steps):
//   1-4: Round 1 exchange (330 bytes split into 1a/1b)
//   5-6: Round 2 exchange
//   7-8: Session key derivation
//   9-10: Key confirmation

import Foundation

// MARK: - J-PAKE Opcodes

/// J-PAKE authentication opcodes (API ≥ 3.2)
/// Range: 32-41 on AUTHORIZATION characteristic
public enum TandemJPAKEOpcode: UInt8, Sendable, CaseIterable {
    case jpake1aRequest = 32
    case jpake1aResponse = 33
    case jpake1bRequest = 34
    case jpake1bResponse = 35
    case jpake2Request = 36
    case jpake2Response = 37
    case jpake3SessionKeyRequest = 38
    case jpake3SessionKeyResponse = 39
    case jpake4KeyConfirmationRequest = 40
    case jpake4KeyConfirmationResponse = 41
    
    /// True if this is a request (client → pump)
    public var isRequest: Bool {
        switch self {
        case .jpake1aRequest, .jpake1bRequest, .jpake2Request,
             .jpake3SessionKeyRequest, .jpake4KeyConfirmationRequest:
            return true
        default:
            return false
        }
    }
    
    /// Human-readable name
    public var displayName: String {
        switch self {
        case .jpake1aRequest: return "Jpake1aRequest"
        case .jpake1aResponse: return "Jpake1aResponse"
        case .jpake1bRequest: return "Jpake1bRequest"
        case .jpake1bResponse: return "Jpake1bResponse"
        case .jpake2Request: return "Jpake2Request"
        case .jpake2Response: return "Jpake2Response"
        case .jpake3SessionKeyRequest: return "Jpake3SessionKeyRequest"
        case .jpake3SessionKeyResponse: return "Jpake3SessionKeyResponse"
        case .jpake4KeyConfirmationRequest: return "Jpake4KeyConfirmationRequest"
        case .jpake4KeyConfirmationResponse: return "Jpake4KeyConfirmationResponse"
        }
    }
}

// MARK: - J-PAKE State Machine

/// State machine for J-PAKE authentication flow
/// Matches JpakeStep enum from pumpX2
public enum TandemJPAKEState: String, Sendable, CaseIterable {
    /// Initial state for new pairing
    case bootstrapInitial = "BOOTSTRAP_INITIAL"
    
    /// Round 1a sent, awaiting response
    case round1aSent = "ROUND_1A_SENT"
    
    /// Round 1a response received
    case round1aReceived = "ROUND_1A_RECEIVED"
    
    /// Round 1b sent, awaiting response
    case round1bSent = "ROUND_1B_SENT"
    
    /// Round 1b response received (full round 1 complete)
    case round1bReceived = "ROUND_1B_RECEIVED"
    
    /// Round 2 sent, awaiting response
    case round2Sent = "ROUND_2_SENT"
    
    /// Round 2 response received
    case round2Received = "ROUND_2_RECEIVED"
    
    /// Initial state for re-auth with existing secret
    case confirmInitial = "CONFIRM_INITIAL"
    
    /// Session key request sent
    case confirm3Sent = "CONFIRM_3_SENT"
    
    /// Session key response received
    case confirm3Received = "CONFIRM_3_RECEIVED"
    
    /// Key confirmation sent
    case confirm4Sent = "CONFIRM_4_SENT"
    
    /// Key confirmation response received
    case confirm4Received = "CONFIRM_4_RECEIVED"
    
    /// Authentication successful
    case complete = "COMPLETE"
    
    /// Authentication failed
    case invalid = "INVALID"
    
    /// Progress percentage (0-100)
    public var progress: Int {
        switch self {
        case .bootstrapInitial: return 0
        case .round1aSent: return 0
        case .round1aReceived: return 10
        case .round1bSent: return 20
        case .round1bReceived: return 30
        case .round2Sent: return 40
        case .round2Received: return 50
        case .confirmInitial: return 50
        case .confirm3Sent: return 60
        case .confirm3Received: return 70
        case .confirm4Sent: return 80
        case .confirm4Received: return 90
        case .complete: return 100
        case .invalid: return 0
        }
    }
    
    /// True if authentication is complete (success or failure)
    public var isTerminal: Bool {
        self == .complete || self == .invalid
    }
}

// MARK: - J-PAKE Protocol Constants

/// Protocol constants for Tandem J-PAKE
public enum TandemJPAKEConstants {
    /// Pairing code length (6 numeric digits)
    public static let pairingCodeLength = 6
    
    /// EC-JPAKE round 1 total size (330 bytes, split into 1a/1b)
    public static let round1TotalSize = 330
    
    /// EC-JPAKE round 1 chunk size (165 bytes each)
    public static let round1ChunkSize = 165
    
    /// EC-JPAKE round 2 max size
    public static let round2MaxSize = 165
    
    /// Session key size (32 bytes from HKDF-SHA256)
    public static let sessionKeySize = 32
    
    /// Server nonce size in Jpake3 response
    public static let serverNonceSize = 16
    
    /// Key confirmation hash size (HMAC-SHA256)
    public static let confirmationHashSize = 32
    
    /// AUTHORIZATION characteristic UUID
    public static let authorizationCharUUID = "7B83FFF9-9F77-4E5C-8064-AAE2C24838B9"
    
    /// Field size for P-256 curve (32 bytes)
    public static let fieldSize = 32
    
    /// Uncompressed EC point size (65 bytes: 0x04 + x + y)
    public static let uncompressedPointSize = 65
}

// MARK: - J-PAKE Message Protocol

/// Protocol for all J-PAKE messages
public protocol TandemJPAKEMessage: Sendable {
    /// The opcode for this message
    static var opcode: TandemJPAKEOpcode { get }
    
    /// Encode this message to wire format
    func encode() -> Data
    
    /// Decode a message from wire format
    static func decode(from data: Data) throws -> Self
}

// MARK: - J-PAKE Errors

/// Errors during J-PAKE authentication
public enum TandemJPAKEError: Error, Sendable, LocalizedError {
    case invalidPairingCode
    case invalidMessageFormat
    case invalidOpcode(UInt8)
    case messageTooShort(expected: Int, got: Int)
    case round1Failed
    case round2Failed
    case keyDerivationFailed
    case confirmationFailed
    case zkProofInvalid
    case unexpectedState(TandemJPAKEState)
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .invalidPairingCode:
            return "Invalid pairing code. Please enter the 6-digit code from your pump."
        case .invalidMessageFormat:
            return "Invalid J-PAKE message format."
        case .invalidOpcode(let opcode):
            return "Invalid J-PAKE opcode: \(opcode)"
        case .messageTooShort(let expected, let got):
            return "J-PAKE message too short: expected \(expected) bytes, got \(got)"
        case .round1Failed:
            return "J-PAKE round 1 exchange failed."
        case .round2Failed:
            return "J-PAKE round 2 exchange failed."
        case .keyDerivationFailed:
            return "J-PAKE key derivation failed."
        case .confirmationFailed:
            return "J-PAKE key confirmation failed."
        case .zkProofInvalid:
            return "J-PAKE zero-knowledge proof verification failed."
        case .unexpectedState(let state):
            return "Unexpected J-PAKE state: \(state.rawValue)"
        case .timeout:
            return "J-PAKE authentication timed out."
        }
    }
}

// MARK: - Round 1a Request

/// Jpake1aRequest: First half of round 1 client challenge
/// Opcode: 32, Size: 167 bytes (2 appInstanceId + 165 round1[0:165])
public struct Jpake1aRequest: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake1aRequest
    
    /// App instance identifier
    public let appInstanceId: UInt16
    
    /// First 165 bytes of EC-JPAKE round 1 data
    public let centralChallenge: Data
    
    public init(appInstanceId: UInt16, centralChallenge: Data) {
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(centralChallenge.prefix(TandemJPAKEConstants.round1ChunkSize))
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake1aRequest {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let challenge = data.dropFirst(2)
        return Jpake1aRequest(appInstanceId: appInstanceId, centralChallenge: Data(challenge))
    }
}

// MARK: - Round 1a Response

/// Jpake1aResponse: First half of pump's round 1 response
/// Opcode: 33, Size: 167 bytes
public struct Jpake1aResponse: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake1aResponse
    
    /// App instance identifier (echoed)
    public let appInstanceId: UInt16
    
    /// First 165 bytes of server round 1 data
    public let serverRound1Part1: Data
    
    public init(appInstanceId: UInt16, serverRound1Part1: Data) {
        self.appInstanceId = appInstanceId
        self.serverRound1Part1 = serverRound1Part1
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(serverRound1Part1)
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake1aResponse {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let serverPart = data.dropFirst(2)
        return Jpake1aResponse(appInstanceId: appInstanceId, serverRound1Part1: Data(serverPart))
    }
}

// MARK: - Round 1b Request

/// Jpake1bRequest: Second half of round 1 client challenge
/// Opcode: 34, Size: 167 bytes
public struct Jpake1bRequest: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake1bRequest
    
    /// App instance identifier
    public let appInstanceId: UInt16
    
    /// Second 165 bytes of EC-JPAKE round 1 data (round1[165:330])
    public let centralChallenge: Data
    
    public init(appInstanceId: UInt16, centralChallenge: Data) {
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(centralChallenge.prefix(TandemJPAKEConstants.round1ChunkSize))
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake1bRequest {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let challenge = data.dropFirst(2)
        return Jpake1bRequest(appInstanceId: appInstanceId, centralChallenge: Data(challenge))
    }
}

// MARK: - Round 1b Response

/// Jpake1bResponse: Second half of pump's round 1 response
/// Opcode: 35, Size: 167 bytes
public struct Jpake1bResponse: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake1bResponse
    
    /// App instance identifier (echoed)
    public let appInstanceId: UInt16
    
    /// Second 165 bytes of server round 1 data
    public let serverRound1Part2: Data
    
    public init(appInstanceId: UInt16, serverRound1Part2: Data) {
        self.appInstanceId = appInstanceId
        self.serverRound1Part2 = serverRound1Part2
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(serverRound1Part2)
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake1bResponse {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let serverPart = data.dropFirst(2)
        return Jpake1bResponse(appInstanceId: appInstanceId, serverRound1Part2: Data(serverPart))
    }
}

// MARK: - Round 2 Request

/// Jpake2Request: Round 2 client value
/// Opcode: 36, Size: 167 bytes max
public struct Jpake2Request: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake2Request
    
    /// App instance identifier
    public let appInstanceId: UInt16
    
    /// EC-JPAKE round 2 data (≤165 bytes)
    public let centralChallenge: Data
    
    public init(appInstanceId: UInt16, centralChallenge: Data) {
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(centralChallenge.prefix(TandemJPAKEConstants.round2MaxSize))
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake2Request {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let challenge = data.dropFirst(2)
        return Jpake2Request(appInstanceId: appInstanceId, centralChallenge: Data(challenge))
    }
}

// MARK: - Round 2 Response

/// Jpake2Response: Round 2 pump response
/// Opcode: 37, Size: 170 bytes
public struct Jpake2Response: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake2Response
    
    /// App instance identifier (echoed)
    public let appInstanceId: UInt16
    
    /// Server round 2 data
    public let serverRound2: Data
    
    public init(appInstanceId: UInt16, serverRound2: Data) {
        self.appInstanceId = appInstanceId
        self.serverRound2 = serverRound2
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(serverRound2)
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake2Response {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let serverData = data.dropFirst(2)
        return Jpake2Response(appInstanceId: appInstanceId, serverRound2: Data(serverData))
    }
}

// MARK: - Session Key Request

/// Jpake3SessionKeyRequest: Request session key derivation
/// Opcode: 38, Size: 2 bytes
public struct Jpake3SessionKeyRequest: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake3SessionKeyRequest
    
    /// Challenge parameter (always 0)
    public let challengeParam: UInt16
    
    public init(challengeParam: UInt16 = 0) {
        self.challengeParam = challengeParam
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: challengeParam.littleEndian) { Array($0) })
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake3SessionKeyRequest {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let param = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        return Jpake3SessionKeyRequest(challengeParam: param)
    }
}

// MARK: - Session Key Response

/// Jpake3SessionKeyResponse: Session key response with server nonce
/// Opcode: 39, Size: 18 bytes (2 appInstanceId + 16 nonce)
public struct Jpake3SessionKeyResponse: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake3SessionKeyResponse
    
    /// App instance identifier
    public let appInstanceId: UInt16
    
    /// Server nonce for HKDF key derivation (16 bytes)
    public let serverNonce: Data
    
    public init(appInstanceId: UInt16, serverNonce: Data) {
        self.appInstanceId = appInstanceId
        self.serverNonce = serverNonce
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(serverNonce.prefix(TandemJPAKEConstants.serverNonceSize))
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake3SessionKeyResponse {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let nonce = data.dropFirst(2).prefix(TandemJPAKEConstants.serverNonceSize)
        return Jpake3SessionKeyResponse(appInstanceId: appInstanceId, serverNonce: Data(nonce))
    }
}

// MARK: - Key Confirmation Request

/// Jpake4KeyConfirmationRequest: Key confirmation with client hash
/// Opcode: 40, Size: varies (typically 50 bytes)
public struct Jpake4KeyConfirmationRequest: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake4KeyConfirmationRequest
    
    /// App instance identifier
    public let appInstanceId: UInt16
    
    /// Client confirmation hash (HMAC-SHA256 of session data)
    public let confirmationHash: Data
    
    public init(appInstanceId: UInt16, confirmationHash: Data) {
        self.appInstanceId = appInstanceId
        self.confirmationHash = confirmationHash
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(confirmationHash)
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake4KeyConfirmationRequest {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let hash = data.dropFirst(2)
        return Jpake4KeyConfirmationRequest(appInstanceId: appInstanceId, confirmationHash: Data(hash))
    }
}

// MARK: - Key Confirmation Response

/// Jpake4KeyConfirmationResponse: Server key confirmation
/// Opcode: 41, Size: varies (typically 50 bytes)
public struct Jpake4KeyConfirmationResponse: TandemJPAKEMessage, Equatable {
    public static let opcode = TandemJPAKEOpcode.jpake4KeyConfirmationResponse
    
    /// App instance identifier
    public let appInstanceId: UInt16
    
    /// Server confirmation hash
    public let serverConfirmationHash: Data
    
    /// Success flag (true if authentication succeeded)
    public var success: Bool {
        // Non-empty hash indicates success
        !serverConfirmationHash.isEmpty
    }
    
    public init(appInstanceId: UInt16, serverConfirmationHash: Data) {
        self.appInstanceId = appInstanceId
        self.serverConfirmationHash = serverConfirmationHash
    }
    
    public func encode() -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: appInstanceId.littleEndian) { Array($0) })
        data.append(serverConfirmationHash)
        return data
    }
    
    public static func decode(from data: Data) throws -> Jpake4KeyConfirmationResponse {
        guard data.count >= 2 else {
            throw TandemJPAKEError.messageTooShort(expected: 2, got: data.count)
        }
        let appInstanceId = UInt16(littleEndian: data.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) })
        let hash = data.dropFirst(2)
        return Jpake4KeyConfirmationResponse(appInstanceId: appInstanceId, serverConfirmationHash: Data(hash))
    }
}

// MARK: - Message Codec

/// Helper for encoding/decoding J-PAKE messages with opcode framing
public enum TandemJPAKECodec {
    
    /// Frame a J-PAKE message with opcode header
    /// Format: [opcode: 1 byte][transactionId: 1 byte][cargo length: 1 byte][cargo]
    public static func frame<M: TandemJPAKEMessage>(_ message: M, transactionId: UInt8) -> Data {
        let cargo = message.encode()
        var framed = Data()
        framed.append(M.opcode.rawValue)
        framed.append(transactionId)
        framed.append(UInt8(cargo.count))
        framed.append(cargo)
        return framed
    }
    
    /// Extract opcode from framed message
    public static func peekOpcode(from data: Data) -> TandemJPAKEOpcode? {
        guard !data.isEmpty else { return nil }
        return TandemJPAKEOpcode(rawValue: data[0])
    }
    
    /// Decode a framed response message
    /// Strips framing header and returns cargo
    public static func unframe(_ data: Data) throws -> (opcode: TandemJPAKEOpcode, transactionId: UInt8, cargo: Data) {
        guard data.count >= 3 else {
            throw TandemJPAKEError.messageTooShort(expected: 3, got: data.count)
        }
        
        guard let opcode = TandemJPAKEOpcode(rawValue: data[0]) else {
            throw TandemJPAKEError.invalidOpcode(data[0])
        }
        
        let transactionId = data[1]
        let cargoLength = Int(data[2])
        
        guard data.count >= 3 + cargoLength else {
            throw TandemJPAKEError.messageTooShort(expected: 3 + cargoLength, got: data.count)
        }
        
        let cargo = Data(data[3..<(3 + cargoLength)])
        return (opcode, transactionId, cargo)
    }
}
