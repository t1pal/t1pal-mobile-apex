// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TandemX2Types.swift
// PumpKit
//
// Tandem t:slim X2 BLE protocol types extracted from pumpX2.
// Trace: X2-SYNTH-002
//
// These types mirror the Java message structure from pumpX2 for
// cross-platform conformance testing.

import Foundation

// MARK: - BLE Characteristics

/// Tandem X2 BLE characteristic identifiers
public enum TandemX2Characteristic: String, CaseIterable, Sendable {
    case currentStatus = "7B83FFF6-9F77-4E5C-8064-AAE2C24838B9"
    case qualifyingEvents = "7B83FFF7-9F77-4E5C-8064-AAE2C24838B9"
    case historyLog = "7B83FFF8-9F77-4E5C-8064-AAE2C24838B9"
    case authorization = "7B83FFF9-9F77-4E5C-8064-AAE2C24838B9"
    case control = "7B83FFFC-9F77-4E5C-8064-AAE2C24838B9"
    case controlStream = "7B83FFFD-9F77-4E5C-8064-AAE2C24838B9"
    
    public var uuid: String { rawValue }
    
    public var description: String {
        switch self {
        case .currentStatus: return "Status queries - IOB, battery, CGM, settings"
        case .qualifyingEvents: return "Event notifications - alerts, alarms, state changes"
        case .historyLog: return "Historical data streaming"
        case .authorization: return "Authentication - J-PAKE and legacy pairing"
        case .control: return "Signed commands - bolus, basal, settings"
        case .controlStream: return "Streaming responses - state machine updates"
        }
    }
}

/// Tandem X2 BLE service UUIDs
public enum TandemX2Service: String, CaseIterable, Sendable {
    case pumpService = "0000fdfb-0000-1000-8000-00805f9b34fb"
    case deviceInformation = "0000180A-0000-1000-8000-00805f9b34fb"
    case genericAccess = "00001800-0000-1000-8000-00805f9b34fb"
    case genericAttribute = "00001801-0000-1000-8000-00805f9b34fb"
    
    public var uuid: String { rawValue }
}

// MARK: - Message Types

/// Message type indicator (even = request, odd = response)
public enum TandemX2MessageType: String, Sendable {
    case request
    case response
    
    public static func from(opcode: Int8) -> TandemX2MessageType {
        opcode % 2 == 0 ? .request : .response
    }
}

/// Supported Tandem devices
public enum TandemX2SupportedDevice: String, CaseIterable, Sendable {
    case tslimX2 = "t:slim X2"
    case mobi = "Mobi"
}

/// Known API versions from pumpX2
public enum TandemX2ApiVersion: String, CaseIterable, Sendable {
    case apiV2_1 = "API_V2_1"
    case apiV2_5 = "API_V2_5"
    case apiV3_2 = "API_V3_2"
    case mobiApiV3_5 = "MOBI_API_V3_5"
}

// MARK: - Message Definition

/// Represents a Tandem X2 message pair (request/response)
public struct TandemX2MessagePair: Sendable {
    public let name: String
    public let requestOpcode: Int8
    public let requestSize: Int
    public let responseOpcode: Int8
    public let responseSize: Int
    public let responseVariableSize: Bool
    public let characteristic: TandemX2Characteristic
    public let signed: Bool
    public let modifiesInsulinDelivery: Bool
    public let minApi: TandemX2ApiVersion?
    
    public init(
        name: String,
        requestOpcode: Int8,
        requestSize: Int,
        responseOpcode: Int8,
        responseSize: Int,
        responseVariableSize: Bool = false,
        characteristic: TandemX2Characteristic = .currentStatus,
        signed: Bool = false,
        modifiesInsulinDelivery: Bool = false,
        minApi: TandemX2ApiVersion? = nil
    ) {
        self.name = name
        self.requestOpcode = requestOpcode
        self.requestSize = requestSize
        self.responseOpcode = responseOpcode
        self.responseSize = responseSize
        self.responseVariableSize = responseVariableSize
        self.characteristic = characteristic
        self.signed = signed
        self.modifiesInsulinDelivery = modifiesInsulinDelivery
        self.minApi = minApi
    }
}

// MARK: - Message Catalog (subset for conformance testing)

/// Key message pairs extracted from pumpX2 for conformance testing
public enum TandemX2Messages {
    
    // MARK: Current Status Messages
    
    public static let apiVersion = TandemX2MessagePair(
        name: "ApiVersion",
        requestOpcode: 32,
        requestSize: 0,
        responseOpcode: 33,
        responseSize: 16,
        responseVariableSize: true
    )
    
    public static let insulinStatus = TandemX2MessagePair(
        name: "InsulinStatus",
        requestOpcode: 36,
        requestSize: 0,
        responseOpcode: 37,
        responseSize: 4
    )
    
    public static let currentBatteryV1 = TandemX2MessagePair(
        name: "CurrentBatteryV1",
        requestOpcode: 34,
        requestSize: 0,
        responseOpcode: 35,
        responseSize: 4
    )
    
    public static let pumpVersion = TandemX2MessagePair(
        name: "PumpVersion",
        requestOpcode: 38,
        requestSize: 0,
        responseOpcode: 39,
        responseSize: 44
    )
    
    public static let cgmStatus = TandemX2MessagePair(
        name: "CGMStatus",
        requestOpcode: 66,
        requestSize: 0,
        responseOpcode: 67,
        responseSize: 10
    )
    
    public static let controlIQIOB = TandemX2MessagePair(
        name: "ControlIQIOB",
        requestOpcode: 60,
        requestSize: 0,
        responseOpcode: 61,
        responseSize: 16
    )
    
    public static let currentBasalStatus = TandemX2MessagePair(
        name: "CurrentBasalStatus",
        requestOpcode: 86,
        requestSize: 0,
        responseOpcode: 87,
        responseSize: 10
    )
    
    public static let currentBolusStatus = TandemX2MessagePair(
        name: "CurrentBolusStatus",
        requestOpcode: 84,
        requestSize: 0,
        responseOpcode: 85,
        responseSize: 14
    )
    
    // MARK: Authorization Messages
    
    public static let centralChallenge = TandemX2MessagePair(
        name: "CentralChallenge",
        requestOpcode: 16,
        requestSize: 10,
        responseOpcode: 17,
        responseSize: 26,
        characteristic: .authorization
    )
    
    public static let pumpChallenge = TandemX2MessagePair(
        name: "PumpChallenge",
        requestOpcode: 18,
        requestSize: 22,
        responseOpcode: 19,
        responseSize: 2,
        characteristic: .authorization
    )
    
    public static let jpake1a = TandemX2MessagePair(
        name: "Jpake1a",
        requestOpcode: 32,
        requestSize: 167,
        responseOpcode: 33,
        responseSize: 167,
        characteristic: .authorization,
        minApi: .apiV3_2
    )
    
    public static let jpake1b = TandemX2MessagePair(
        name: "Jpake1b",
        requestOpcode: 34,
        requestSize: 167,
        responseOpcode: 35,
        responseSize: 167,
        characteristic: .authorization,
        minApi: .apiV3_2
    )
    
    public static let jpake2 = TandemX2MessagePair(
        name: "Jpake2",
        requestOpcode: 36,
        requestSize: 167,
        responseOpcode: 37,
        responseSize: 167,
        characteristic: .authorization,
        minApi: .apiV3_2
    )
    
    public static let jpake3SessionKey = TandemX2MessagePair(
        name: "Jpake3SessionKey",
        requestOpcode: 38,
        requestSize: 2,
        responseOpcode: 39,
        responseSize: 18,
        characteristic: .authorization,
        minApi: .apiV3_2
    )
    
    public static let jpake4KeyConfirmation = TandemX2MessagePair(
        name: "Jpake4KeyConfirmation",
        requestOpcode: 40,
        requestSize: 50,
        responseOpcode: 41,
        responseSize: 2,
        characteristic: .authorization,
        minApi: .apiV3_2
    )
    
    // MARK: Control Messages (Signed)
    
    public static let bolusPermission = TandemX2MessagePair(
        name: "BolusPermission",
        requestOpcode: -78,
        requestSize: 0,
        responseOpcode: -77,
        responseSize: 6,
        characteristic: .control,
        signed: true
    )
    
    public static let initiateBolus = TandemX2MessagePair(
        name: "InitiateBolus",
        requestOpcode: -80,
        requestSize: 23,
        responseOpcode: -79,
        responseSize: 11,
        characteristic: .control,
        signed: true,
        modifiesInsulinDelivery: true
    )
    
    public static let cancelBolus = TandemX2MessagePair(
        name: "CancelBolus",
        requestOpcode: -74,
        requestSize: 2,
        responseOpcode: -73,
        responseSize: 2,
        characteristic: .control,
        signed: true,
        modifiesInsulinDelivery: true
    )
    
    public static let suspendPumping = TandemX2MessagePair(
        name: "SuspendPumping",
        requestOpcode: -76,
        requestSize: 0,
        responseOpcode: -75,
        responseSize: 2,
        characteristic: .control,
        signed: true,
        modifiesInsulinDelivery: true
    )
    
    public static let resumePumping = TandemX2MessagePair(
        name: "ResumePumping",
        requestOpcode: -62,
        requestSize: 0,
        responseOpcode: -61,
        responseSize: 2,
        characteristic: .control,
        signed: true,
        modifiesInsulinDelivery: true
    )
    
    public static let setTempRate = TandemX2MessagePair(
        name: "SetTempRate",
        requestOpcode: -66,
        requestSize: 4,
        responseOpcode: -65,
        responseSize: 2,
        characteristic: .control,
        signed: true
    )
    
    public static let stopTempRate = TandemX2MessagePair(
        name: "StopTempRate",
        requestOpcode: -64,
        requestSize: 0,
        responseOpcode: -63,
        responseSize: 2,
        characteristic: .control,
        signed: true
    )
    
    /// All defined message pairs for catalog testing
    public static let allMessages: [TandemX2MessagePair] = [
        // Status
        apiVersion, insulinStatus, currentBatteryV1, pumpVersion,
        cgmStatus, controlIQIOB, currentBasalStatus, currentBolusStatus,
        // Auth
        centralChallenge, pumpChallenge,
        jpake1a, jpake1b, jpake2, jpake3SessionKey, jpake4KeyConfirmation,
        // Control
        bolusPermission, initiateBolus, cancelBolus,
        suspendPumping, resumePumping, setTempRate, stopTempRate
    ]
}

// MARK: - Fixture Loading

/// Loads Tandem X2 message fixtures from JSON
public struct TandemX2FixtureLoader {
    
    public struct MessageFixture: Decodable {
        public let name: String
        public let request: RequestInfo
        public let response: ResponseInfo?
        public let signed: Bool?
        public let modifiesInsulinDelivery: Bool?
        public let minApi: String?
        
        public struct RequestInfo: Decodable {
            public let opcode: Int
            public let size: Int
            public let characteristic: String?
        }
        
        public struct ResponseInfo: Decodable {
            public let opcode: Int
            public let size: Int
            public let variableSize: Bool?
        }
    }
    
    public struct Fixture: Decodable {
        public let sessionId: String
        public let statistics: Statistics
        public let messagePairs: [MessageFixture]
        
        public struct Statistics: Decodable {
            public let totalMessagePairs: Int
            public let totalOpcodes: Int
        }
        
        private enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case statistics
            case messagePairs = "message_pairs"
        }
    }
    
    public static func loadFromBundle(_ bundle: Bundle = .main) throws -> Fixture {
        guard let url = bundle.url(forResource: "fixture_x2_messages", withExtension: "json") else {
            throw FixtureError.notFound
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(Fixture.self, from: data)
    }
    
    public enum FixtureError: Error {
        case notFound
    }
}
