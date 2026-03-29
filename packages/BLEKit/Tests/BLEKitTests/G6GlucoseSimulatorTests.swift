// SPDX-License-Identifier: MIT
//
// G6GlucoseSimulatorTests.swift
// BLEKitTests
//
// Tests for G6 glucose request handling simulator.

import Testing
import Foundation
@testable import BLEKit

// MARK: - Glucose Status Tests

@Suite("G6 Glucose Status")
struct G6GlucoseStatusTests {
    
    @Test("Status codes have correct values")
    func statusCodeValues() {
        #expect(G6GlucoseStatus.ok.rawValue == 0x00)
        #expect(G6GlucoseStatus.warmingUp.rawValue == 0x01)
        #expect(G6GlucoseStatus.sessionExpired.rawValue == 0x02)
        #expect(G6GlucoseStatus.sensorError.rawValue == 0x03)
        #expect(G6GlucoseStatus.noSession.rawValue == 0x04)
        #expect(G6GlucoseStatus.calibrationRequired.rawValue == 0x05)
        #expect(G6GlucoseStatus.sensorFailed.rawValue == 0x06)
    }
}

// MARK: - Static Glucose Provider Tests

@Suite("Static Glucose Provider")
struct StaticGlucoseProviderTests {
    
    @Test("Provider returns configured values")
    func providerReturnsConfiguredValues() {
        let provider = StaticGlucoseProvider(glucose: 120, predicted: 125, trend: 2)
        #expect(provider.currentGlucose() == 120)
        #expect(provider.predictedGlucose() == 125)
        #expect(provider.currentTrend() == 2)
    }
    
    @Test("Provider uses glucose for predicted if not specified")
    func providerUsesGlucoseForPredicted() {
        let provider = StaticGlucoseProvider(glucose: 100)
        #expect(provider.currentGlucose() == 100)
        #expect(provider.predictedGlucose() == 100)
        #expect(provider.currentTrend() == 0)
    }
    
    @Test("Provider supports negative trend")
    func providerSupportsNegativeTrend() {
        let provider = StaticGlucoseProvider(glucose: 150, trend: -3)
        #expect(provider.currentTrend() == -3)
    }
}

// MARK: - Simulated Glucose Reading Tests

@Suite("Simulated Glucose Reading")
struct SimulatedGlucoseReadingTests {
    
    @Test("Reading stores all values")
    func readingStoresAllValues() {
        let reading = SimulatedGlucoseReading(
            glucose: 120,
            predictedGlucose: 125,
            trend: 2,
            sequence: 42,
            timestamp: 3600
        )
        
        #expect(reading.glucose == 120)
        #expect(reading.predictedGlucose == 125)
        #expect(reading.trend == 2)
        #expect(reading.sequence == 42)
        #expect(reading.timestamp == 3600)
    }
    
    @Test("Reading uses glucose for predicted if not specified")
    func readingUsesGlucoseForPredicted() {
        let reading = SimulatedGlucoseReading(
            glucose: 100,
            sequence: 1,
            timestamp: 0
        )
        #expect(reading.predictedGlucose == 100)
    }
}

// MARK: - Glucose Simulator Initialization Tests

@Suite("G6 Glucose Simulator Init")
struct G6GlucoseSimulatorInitTests {
    
    @Test("Simulator initializes with session")
    func simulatorInitializesWithSession() {
        let session = SensorSession(transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        #expect(simulator.session.state == .warmup)
    }
    
    @Test("Simulator initializes with custom provider")
    func simulatorInitializesWithCustomProvider() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let provider = StaticGlucoseProvider(glucose: 150)
        let simulator = G6GlucoseSimulator(session: session, glucoseProvider: provider)
        
        // Request glucose
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        // Extract glucose value (bytes 10-11, little-endian)
        let glucoseValue = response.subdata(in: 10..<12).withUnsafeBytes { $0.load(as: UInt16.self) }
        #expect(glucoseValue == 150)
    }
    
    @Test("Simulator initializes with config")
    func simulatorInitializesWithConfig() {
        guard let transmitterId = SimulatorTransmitterID("8G1234") else {
            Issue.record("Failed to create transmitter ID")
            return
        }
        let config = SimulatorTransmitterConfig(id: transmitterId)
        let simulator = G6GlucoseSimulator(config: config)
        #expect(simulator.session.state == .active)
    }
    
    @Test("Sequence starts at zero")
    func sequenceStartsAtZero() {
        let session = SensorSession(transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        #expect(simulator.sequenceNumber == 0)
    }
}

// MARK: - Glucose Request Tests

@Suite("G6 Glucose Request")
struct G6GlucoseRequestTests {
    
    @Test("Empty message returns invalid")
    func emptyMessageReturnsInvalid() {
        let session = SensorSession(transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let result = simulator.processMessage(Data())
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("Empty"))
        } else {
            Issue.record("Expected invalidMessage")
        }
    }
    
    @Test("Unknown opcode returns invalid")
    func unknownOpcodeReturnsInvalid() {
        let session = SensorSession(transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let result = simulator.processMessage(Data([0xFF]))
        if case .invalidMessage(let reason) = result {
            #expect(reason.contains("Unknown opcode"))
        } else {
            Issue.record("Expected invalidMessage")
        }
    }
    
    @Test("GlucoseTx returns response")
    func glucoseTxReturnsResponse() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        let result = simulator.processMessage(request)
        
        if case .sendResponse(let response) = result {
            #expect(response.count == 15)
            #expect(response[0] == G6SimOpcode.glucoseRx)
        } else {
            Issue.record("Expected sendResponse")
        }
    }
    
    @Test("Response includes correct opcode")
    func responseIncludesCorrectOpcode() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        #expect(response[0] == 0x31)  // GlucoseRx opcode
    }
    
    @Test("Sequence increments with each request")
    func sequenceIncrementsWithEachRequest() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        
        // First request
        _ = simulator.processMessage(request)
        #expect(simulator.sequenceNumber == 1)
        
        // Second request
        _ = simulator.processMessage(request)
        #expect(simulator.sequenceNumber == 2)
        
        // Third request
        _ = simulator.processMessage(request)
        #expect(simulator.sequenceNumber == 3)
    }
}

// MARK: - Session State Response Tests

@Suite("G6 Session State Responses")
struct G6SessionStateResponseTests {
    
    @Test("Warmup state returns warmingUp status")
    func warmupStateReturnsWarmingUpStatus() {
        let session = SensorSession(state: .warmup, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        #expect(response[1] == G6GlucoseStatus.warmingUp.rawValue)
    }
    
    @Test("Active state returns ok status")
    func activeStateReturnsOkStatus() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        #expect(response[1] == G6GlucoseStatus.ok.rawValue)
    }
    
    @Test("Expired state returns sessionExpired status")
    func expiredStateReturnsSessionExpiredStatus() {
        let session = SensorSession(state: .expired, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        #expect(response[1] == G6GlucoseStatus.sessionExpired.rawValue)
    }
    
    @Test("Stopped state returns noSession status")
    func stoppedStateReturnsNoSessionStatus() {
        let session = SensorSession(state: .inactive, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        #expect(response[1] == G6GlucoseStatus.noSession.rawValue)
    }
    
    @Test("Error state returns sensorError status")
    func errorStateReturnsSensorErrorStatus() {
        let session = SensorSession(state: .error, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        #expect(response[1] == G6GlucoseStatus.sensorError.rawValue)
    }
    
    @Test("Warmup excludes glucose value")
    func warmupExcludesGlucoseValue() {
        let session = SensorSession(state: .warmup, transmitterType: .g6)
        let provider = StaticGlucoseProvider(glucose: 120)
        let simulator = G6GlucoseSimulator(session: session, glucoseProvider: provider)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        // Glucose should be 0 during warmup
        let glucoseValue = response.subdata(in: 10..<12).withUnsafeBytes { $0.load(as: UInt16.self) }
        #expect(glucoseValue == 0)
    }
    
    @Test("Active includes glucose value")
    func activeIncludesGlucoseValue() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let provider = StaticGlucoseProvider(glucose: 120)
        let simulator = G6GlucoseSimulator(session: session, glucoseProvider: provider)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        let glucoseValue = response.subdata(in: 10..<12).withUnsafeBytes { $0.load(as: UInt16.self) }
        #expect(glucoseValue == 120)
    }
}

// MARK: - Response Format Tests

@Suite("G6 Response Format")
struct G6ResponseFormatTests {
    
    @Test("Response has correct length")
    func responseHasCorrectLength() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        // opcode(1) + status(1) + sequence(4) + timestamp(4) + glucose(2) + predicted(2) + trend(1) = 15
        #expect(response.count == 15)
    }
    
    @Test("Response includes trend")
    func responseIncludesTrend() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let provider = StaticGlucoseProvider(glucose: 120, trend: 3)
        let simulator = G6GlucoseSimulator(session: session, glucoseProvider: provider)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        let trend = Int8(bitPattern: response[14])
        #expect(trend == 3)
    }
    
    @Test("Response includes negative trend")
    func responseIncludesNegativeTrend() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let provider = StaticGlucoseProvider(glucose: 120, trend: -5)
        let simulator = G6GlucoseSimulator(session: session, glucoseProvider: provider)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        let trend = Int8(bitPattern: response[14])
        #expect(trend == -5)
    }
    
    @Test("Response includes predicted glucose")
    func responseIncludesPredictedGlucose() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let provider = StaticGlucoseProvider(glucose: 120, predicted: 130)
        let simulator = G6GlucoseSimulator(session: session, glucoseProvider: provider)
        
        let request = Data([G6SimOpcode.glucoseTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        let predicted = response.subdata(in: 12..<14).withUnsafeBytes { $0.load(as: UInt16.self) }
        #expect(predicted == 130)
    }
}

// MARK: - Session Management Tests

@Suite("G6 Session Management")
struct G6SessionManagementTests {
    
    @Test("Start session resets state")
    func startSessionResetsState() {
        let session = SensorSession(state: .expired, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        simulator.startSession()
        
        #expect(simulator.session.state == .warmup)
        #expect(simulator.sequenceNumber == 0)
    }
    
    @Test("Stop session sets stopped state")
    func stopSessionSetsStoppedState() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        simulator.stopSession()
        
        #expect(simulator.session.state == .inactive)
    }
    
    @Test("Set error sets error state")
    func setErrorSetsErrorState() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        simulator.setError()
        
        #expect(simulator.session.state == .error)
    }
    
    @Test("Get last reading returns nil when not active")
    func getLastReadingReturnsNilWhenNotActive() {
        let session = SensorSession(state: .warmup, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        #expect(simulator.getLastReading() == nil)
    }
    
    @Test("Get last reading returns reading when active")
    func getLastReadingReturnsReadingWhenActive() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let provider = StaticGlucoseProvider(glucose: 120, trend: 2)
        let simulator = G6GlucoseSimulator(session: session, glucoseProvider: provider)
        
        // Make a request to set sequence
        _ = simulator.processMessage(Data([G6SimOpcode.glucoseTx]))
        
        let reading = simulator.getLastReading()
        #expect(reading != nil)
        #expect(reading?.glucose == 120)
        #expect(reading?.trend == 2)
        #expect(reading?.sequence == 1)
    }
}

// MARK: - Transmitter Time Tests

@Suite("G6 Transmitter Time")
struct G6TransmitterTimeTests {
    
    @Test("TransmitterTimeTx returns response")
    func transmitterTimeTxReturnsResponse() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.transmitterTimeTx])
        let result = simulator.processMessage(request)
        
        if case .sendResponse(let response) = result {
            #expect(response.count == 10)
            #expect(response[0] == G6SimOpcode.transmitterTimeRx)
        } else {
            Issue.record("Expected sendResponse")
        }
    }
    
    @Test("Time response has correct opcode")
    func timeResponseHasCorrectOpcode() {
        let session = SensorSession(state: .active, transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        let request = Data([G6SimOpcode.transmitterTimeTx])
        guard case .sendResponse(let response) = simulator.processMessage(request) else {
            Issue.record("Expected response")
            return
        }
        
        #expect(response[0] == 0x25)  // TransmitterTimeRx opcode
    }
}

// MARK: - G7 Transmitter Type Tests

@Suite("G7 Transmitter Type")
struct G7TransmitterTypeTests {
    
    @Test("G7 session has shorter warmup")
    func g7SessionHasShorterWarmup() {
        let session = SensorSession(transmitterType: .g7)
        #expect(session.warmupDuration == 30 * 60)  // 30 minutes
    }
    
    @Test("G7 session has longer max duration")
    func g7SessionHasLongerMaxDuration() {
        let session = SensorSession(transmitterType: .g7)
        #expect(session.maxSessionDuration == 10.5 * 24 * 60 * 60)  // 10.5 days
    }
    
    @Test("Start session uses specified transmitter type")
    func startSessionUsesSpecifiedTransmitterType() {
        let session = SensorSession(transmitterType: .g6)
        let simulator = G6GlucoseSimulator(session: session)
        
        simulator.startSession(transmitterType: .g7)
        
        #expect(simulator.session.warmupDuration == 30 * 60)
    }
}
