// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// G6EndToEndTraceTests.swift
// CGMKitTests
//
// End-to-end trace verification for G6 diagnostic logging.
// Verifies: connection → auth → glucose → errors trace path.
//
// Backlog: G6-DIAG-006

import Testing
import Foundation
@testable import CGMKit
@testable import BLEKit

// MARK: - G6 Protocol Logger Tests

@Suite("G6 Protocol Logger End-to-End Trace")
struct G6ProtocolLoggerTraceTests {
    
    @Test("Session lifecycle captures start and end events")
    func sessionLifecycle() async {
        let logger = G6ProtocolLogger()
        
        // Start session
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        // End session successfully
        await logger.endSession(success: true)
        
        let entries = await logger.getEntries()
        
        #expect(entries.count >= 2)
        #expect(entries.first?.event == .authenticationStarted)
        #expect(entries.last?.event == .authenticationCompleted)
    }
    
    @Test("Session captures failed authentication")
    func sessionFailure() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        await logger.endSession(success: false)
        
        let entries = await logger.getEntries()
        
        #expect(entries.last?.event == .authenticationFailed)
        #expect(entries.last?.isSuccess == false)
    }
    
    @Test("Key derivation events are captured")
    func keyDerivationTrace() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        await logger.logKeyDerivation(
            transmitterId: "80AB12",
            keyBytes: [0x30, 0x30, 0x38, 0x30, 0x41, 0x42, 0x31, 0x32,
                       0x30, 0x30, 0x38, 0x30, 0x41, 0x42, 0x31, 0x32],
            variant: .asciiZeros
        )
        
        let entries = await logger.getEntries(category: .keyDerivation)
        
        #expect(entries.count >= 1)
        #expect(entries.first?.event == .keyDerivationCompleted)
        #expect(entries.first?.rawBytes != nil)
        #expect(entries.first?.rawBytes?.count == 4) // Only first 4 bytes for security
    }
    
    @Test("Token generation and verification trace")
    func tokenExchangeTrace() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        // Generate token
        let token: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        await logger.logTokenGeneration(token: token)
        
        // Verify token hash
        let expectedHash: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44]
        let receivedHash: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0x11, 0x22, 0x33, 0x44]
        await logger.logTokenHashVerification(
            expectedHash: expectedHash,
            receivedHash: receivedHash,
            matched: true
        )
        
        let entries = await logger.getEntries(category: .tokenExchange)
        
        #expect(entries.count >= 2)
        #expect(entries.contains { $0.event == .tokenGenerated })
        #expect(entries.contains { $0.event == .tokenHashVerified })
    }
    
    @Test("Token hash failure is captured")
    func tokenHashFailure() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        await logger.logTokenHashVerification(
            expectedHash: [0xAA, 0xBB, 0xCC, 0xDD],
            receivedHash: [0x11, 0x22, 0x33, 0x44],
            matched: false
        )
        
        let entries = await logger.getEntries(category: .tokenExchange)
        
        #expect(entries.contains { $0.event == .tokenHashFailed })
        #expect(entries.first { $0.event == .tokenHashFailed }?.isSuccess == false)
    }
    
    @Test("Challenge-response trace")
    func challengeResponseTrace() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        let challenge: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        let response: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11]
        await logger.logChallengeResponse(challenge: challenge, response: response)
        
        let entries = await logger.getEntries(category: .challenge)
        
        #expect(entries.count >= 2)
        #expect(entries.contains { $0.event == .challengeReceived })
        #expect(entries.contains { $0.event == .challengeResponseComputed })
    }
    
    @Test("AES operation success trace")
    func aesOperationSuccess() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        let input: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                              0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10]
        let output: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11,
                               0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99]
        await logger.logAESOperation(input: input, output: output, success: true)
        
        let entries = await logger.getEntries(category: .crypto)
        
        #expect(entries.contains { $0.event == .aesEncryptCompleted })
        #expect(entries.first?.isSuccess == true)
    }
    
    @Test("AES operation failure trace")
    func aesOperationFailure() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        let input: [UInt8] = [0x01, 0x02, 0x03, 0x04]
        await logger.logAESOperation(input: input, output: nil, success: false)
        
        let entries = await logger.getEntries(category: .crypto)
        
        #expect(entries.contains { $0.event == .aesEncryptFailed })
        #expect(entries.first { $0.event == .aesEncryptFailed }?.isSuccess == false)
    }
    
    @Test("Auth status events captured")
    func authStatusTrace() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        await logger.logAuthStatus(authenticated: true, bonded: true)
        
        let entries = await logger.getEntries(category: .status)
        
        #expect(entries.contains { $0.event == .authStatusReceived })
        #expect(entries.contains { $0.event == .authStatusPaired })
        #expect(entries.contains { $0.event == .authStatusBonded })
    }
    
    @Test("Transmitter type detection trace")
    func transmitterTypeTrace() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        // Standard G6
        await logger.logTransmitterType(transmitterId: "80AB12", isFirefly: false)
        
        var entries = await logger.getEntries(category: .transmitterInfo)
        #expect(entries.contains { $0.event == .transmitterTypeDetected })
        #expect(entries.first?.details["type"] == "G6 Standard")
        
        // Clear and test Firefly
        await logger.clear()
        await logger.startSession(transmitterId: "8GXXXX", variant: .firefly)
        await logger.logTransmitterType(transmitterId: "8GXXXX", isFirefly: true)
        
        entries = await logger.getEntries(category: .transmitterInfo)
        #expect(entries.first?.details["type"] == "G6+ (Firefly)")
    }
    
    @Test("Full authentication sequence trace")
    func fullAuthenticationTrace() async {
        let logger = G6ProtocolLogger()
        
        // Simulate complete authentication flow
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        // 1. Key derivation
        await logger.log(event: .keyDerivationStarted)
        await logger.logKeyDerivation(
            transmitterId: "80AB12",
            keyBytes: Array(repeating: 0x30, count: 16),
            variant: .asciiZeros
        )
        
        // 2. Token exchange
        await logger.logTokenGeneration(token: Array(repeating: 0x01, count: 8))
        await logger.log(event: .tokenSent)
        await logger.log(event: .tokenHashReceived)
        await logger.logTokenHashVerification(
            expectedHash: Array(repeating: 0xAA, count: 8),
            receivedHash: Array(repeating: 0xAA, count: 8),
            matched: true
        )
        
        // 3. Challenge-response
        await logger.logChallengeResponse(
            challenge: Array(repeating: 0x02, count: 8),
            response: Array(repeating: 0xBB, count: 8)
        )
        await logger.log(event: .challengeResponseSent)
        
        // 4. Status check
        await logger.logAuthStatus(authenticated: true, bonded: false)
        
        // 5. Complete
        await logger.endSession(success: true)
        
        // Verify trace
        let entries = await logger.getEntries()
        let eventCount = await logger.eventCount
        
        #expect(eventCount >= 10) // At least 10 events in full flow
        
        // Verify lifecycle
        #expect(entries.first?.event == .authenticationStarted)
        #expect(entries.last?.event == .authenticationCompleted)
        
        // Verify all categories present
        let categories = Set(entries.map { $0.event.category })
        #expect(categories.contains(.lifecycle))
        #expect(categories.contains(.keyDerivation))
        #expect(categories.contains(.tokenExchange))
        #expect(categories.contains(.challenge))
        #expect(categories.contains(.status))
        
        // No failures
        let hasFailures = await logger.hasFailures
        #expect(hasFailures == false)
    }
    
    @Test("Failed events are retrievable")
    func failedEventsRetrieval() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        await logger.logTokenHashVerification(
            expectedHash: [0xAA],
            receivedHash: [0xBB],
            matched: false
        )
        await logger.logAESOperation(input: [], output: nil, success: false)
        await logger.endSession(success: false)
        
        let failedEvents = await logger.getFailedEvents()
        
        #expect(failedEvents.count == 3) // token fail, AES fail, auth fail
    }
    
    @Test("Export JSON produces valid output")
    func jsonExport() async throws {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        await logger.logKeyDerivation(
            transmitterId: "80AB12",
            keyBytes: Array(repeating: 0x30, count: 16),
            variant: .asciiZeros
        )
        await logger.endSession(success: true)
        
        let jsonData = try await logger.exportJSON()
        
        #expect(jsonData.count > 0)
        
        // Verify valid JSON (decoder must match encoder's iso8601 strategy)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([G6ProtocolLogEntry].self, from: jsonData)
        #expect(decoded.count >= 2)
    }
    
    @Test("Text report is human-readable")
    func textReport() async {
        let logger = G6ProtocolLogger()
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        await logger.logAuthStatus(authenticated: true, bonded: true)
        await logger.endSession(success: true)
        
        let report = await logger.generateReport()
        
        #expect(report.contains("G6 Protocol Log Report"))
        #expect(report.contains("Transmitter: 80AB12"))
        #expect(report.contains("Events"))
    }
    
    @Test("Logger respects max entries limit")
    func maxEntriesLimit() async {
        let logger = G6ProtocolLogger(maxEntries: 5)
        
        await logger.startSession(transmitterId: "80AB12", variant: .loopDefault)
        
        // Log 10 events
        for _ in 0..<10 {
            await logger.log(event: .keepAliveSent)
        }
        
        let eventCount = await logger.eventCount
        
        #expect(eventCount == 5) // Should be trimmed to max
    }
}

// MARK: - G6 Evidence Collector Tests

@Suite("G6 Evidence Collector End-to-End Trace")
struct G6EvidenceCollectorTraceTests {
    
    @Test("Attempt lifecycle is tracked")
    func attemptLifecycle() async {
        let collector = G6EvidenceCollector()
        
        let attemptId = await collector.startAttempt(
            transmitterId: "80AB12",
            variant: .loopDefault,
            isFirefly: false
        )
        
        #expect(!attemptId.isEmpty)
        
        await collector.completeAttempt(success: true)
        
        let attempts = await collector.getAttempts()
        #expect(attempts.count == 1)
        #expect(attempts.first?.success == true)
    }
    
    @Test("Phase results are recorded")
    func phaseRecording() async {
        let collector = G6EvidenceCollector()
        
        _ = await collector.startAttempt(
            transmitterId: "80AB12",
            variant: .loopDefault
        )
        
        // Record all phases
        let phases: [G6AuthPhase] = [.keyDerivation, .tokenSend, .tokenVerify, .challengeResponse, .statusCheck]
        
        for phase in phases {
            let startTime = await collector.startPhase(phase)
            await collector.completePhase(phase, startTime: startTime, success: true)
        }
        
        await collector.completeAttempt(success: true)
        
        let attempts = await collector.getAttempts()
        guard let attempt = attempts.first else {
            Issue.record("No attempt recorded")
            return
        }
        
        #expect(attempt.keyDerivation?.success == true)
        #expect(attempt.tokenSend?.success == true)
        #expect(attempt.tokenVerify?.success == true)
        #expect(attempt.challengeResponse?.success == true)
        #expect(attempt.statusCheck?.success == true)
        #expect(attempt.allPhasesSucceeded == true)
    }
    
    @Test("Phase failure is captured")
    func phaseFailure() async {
        let collector = G6EvidenceCollector()
        
        _ = await collector.startAttempt(
            transmitterId: "80AB12",
            variant: .loopDefault
        )
        
        let startTime = await collector.startPhase(.tokenVerify)
        await collector.completePhase(
            .tokenVerify,
            startTime: startTime,
            success: false,
            error: "Hash mismatch",
            errorCode: "TOKEN_VERIFY_FAILED"
        )
        
        await collector.completeAttempt(success: false, error: "Authentication failed at token verify")
        
        let attempts = await collector.getAttempts()
        guard let attempt = attempts.first else {
            Issue.record("No attempt recorded")
            return
        }
        
        #expect(attempt.success == false)
        #expect(attempt.tokenVerify?.success == false)
        #expect(attempt.tokenVerify?.errorMessage == "Hash mismatch")
        #expect(attempt.tokenVerify?.errorCode == "TOKEN_VERIFY_FAILED")
    }
    
    @Test("Statistics are calculated correctly")
    func statisticsCalculation() async {
        let collector = G6EvidenceCollector()
        
        // Record 3 successful, 2 failed attempts
        for i in 0..<5 {
            _ = await collector.startAttempt(
                transmitterId: "80AB12",
                variant: .loopDefault
            )
            
            let success = i < 3
            if !success {
                let startTime = await collector.startPhase(.challengeResponse)
                await collector.completePhase(.challengeResponse, startTime: startTime, success: false, error: "Failed")
            }
            
            await collector.completeAttempt(success: success, error: success ? nil : "Failed")
        }
        
        let stats = await collector.generateStatistics()
        
        #expect(stats.totalAttempts == 5)
        #expect(stats.successfulAttempts == 3)
        #expect(stats.failedAttempts == 2)
        #expect(stats.successRate == 0.6)
    }
    
    @Test("Report generation includes recommendations")
    func reportGeneration() async {
        let collector = G6EvidenceCollector()
        
        // Record some attempts
        for _ in 0..<3 {
            _ = await collector.startAttempt(
                transmitterId: "80AB12",
                variant: .loopDefault
            )
            await collector.completeAttempt(success: true)
        }
        
        let report = await collector.generateReport()
        
        #expect(report.attempts.count == 3)
        #expect(report.statistics.totalAttempts == 3)
        #expect(report.platform.os.count > 0)
    }
    
    @Test("Variant filtering works")
    func variantFiltering() async {
        let collector = G6EvidenceCollector()
        
        // loopDefault attempts
        for _ in 0..<2 {
            _ = await collector.startAttempt(
                transmitterId: "80AB12",
                variant: .loopDefault
            )
            await collector.completeAttempt(success: true)
        }
        
        // firefly attempts
        _ = await collector.startAttempt(
            transmitterId: "8GXXXX",
            variant: .firefly,
            isFirefly: true
        )
        await collector.completeAttempt(success: true)
        
        let loopAttempts = await collector.getAttempts(variant: .loopDefault)
        let fireflyAttempts = await collector.getAttempts(variant: .firefly)
        
        #expect(loopAttempts.count == 2)
        #expect(fireflyAttempts.count == 1)
    }
    
    @Test("Transmitter filtering works")
    func transmitterFiltering() async {
        let collector = G6EvidenceCollector()
        
        _ = await collector.startAttempt(transmitterId: "80AB12", variant: .loopDefault)
        await collector.completeAttempt(success: true)
        
        _ = await collector.startAttempt(transmitterId: "80CD34", variant: .loopDefault)
        await collector.completeAttempt(success: true)
        
        let ab12Attempts = await collector.getAttempts(transmitterId: "80AB12")
        let cd34Attempts = await collector.getAttempts(transmitterId: "80CD34")
        
        #expect(ab12Attempts.count == 1)
        #expect(cd34Attempts.count == 1)
    }
    
    @Test("JSON export is valid")
    func jsonExport() async throws {
        let collector = G6EvidenceCollector()
        
        _ = await collector.startAttempt(transmitterId: "80AB12", variant: .loopDefault)
        await collector.completeAttempt(success: true)
        
        let jsonData = try await collector.exportJSON()
        
        #expect(jsonData.count > 0)
        
        // Decoder must match encoder's iso8601 strategy
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([G6AttemptRecord].self, from: jsonData)
        #expect(decoded.count == 1)
    }
}

// MARK: - BLE Traffic Logger Integration Tests

@Suite("BLE Traffic Logger G6 Integration")
struct BLETrafficLoggerG6Tests {
    
    @Test("Captures G6 auth characteristic traffic")
    func authCharacteristicTraffic() {
        let logger = BLETrafficLogger()
        
        // Simulate outgoing auth request
        let authRequest = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x02])
        logger.log(
            direction: .outgoing,
            data: authRequest,
            characteristic: G6Constants.authenticationUUID,
            service: G6Constants.cgmServiceUUID
        )
        
        // Simulate incoming auth response
        let authResponse = Data([0x05, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11])
        logger.log(
            direction: .incoming,
            data: authResponse,
            characteristic: G6Constants.authenticationUUID,
            service: G6Constants.cgmServiceUUID
        )
        
        let entries = logger.entries
        
        #expect(entries.count == 2)
        #expect(entries[0].direction == .outgoing)
        #expect(entries[0].opcode == 0x01)
        #expect(entries[1].direction == .incoming)
        #expect(entries[1].opcode == 0x05)
    }
    
    @Test("Captures G6 control characteristic traffic")
    func controlCharacteristicTraffic() {
        let logger = BLETrafficLogger()
        
        // Glucose command
        let glucoseCmd = Data([0x30]) // GlucoseTx opcode
        logger.log(
            direction: .outgoing,
            data: glucoseCmd,
            characteristic: G6Constants.controlUUID,
            service: G6Constants.cgmServiceUUID
        )
        
        // Glucose response with value
        let glucoseRx = Data([0x31, 0x00, 0x78, 0x00, 0x64, 0x00, 0x00, 0x00])
        logger.log(
            direction: .incoming,
            data: glucoseRx,
            characteristic: G6Constants.controlUUID,
            service: G6Constants.cgmServiceUUID
        )
        
        let stats = logger.statistics
        
        #expect(stats.totalEntries == 2)
        #expect(stats.outgoingCount == 1)
        #expect(stats.incomingCount == 1)
    }
    
    @Test("Filters by characteristic")
    func characteristicFiltering() {
        let logger = BLETrafficLogger()
        
        // Auth traffic
        logger.log(
            direction: .outgoing,
            data: Data([0x01, 0x02]),
            characteristic: G6Constants.authenticationUUID
        )
        
        // Control traffic
        logger.log(
            direction: .outgoing,
            data: Data([0x30]),
            characteristic: G6Constants.controlUUID
        )
        
        var authFilter = TrafficFilter()
        authFilter.characteristic = G6Constants.authenticationUUID
        let authOnly = logger.filter(authFilter)
        
        var controlFilter = TrafficFilter()
        controlFilter.characteristic = G6Constants.controlUUID
        let controlOnly = logger.filter(controlFilter)
        
        #expect(authOnly.count == 1)
        #expect(authOnly[0].opcode == 0x01)
        #expect(controlOnly.count == 1)
        #expect(controlOnly[0].opcode == 0x30)
    }
    
    @Test("Hex dump export format")
    func hexDumpExport() {
        let logger = BLETrafficLogger()
        
        logger.log(
            direction: .outgoing,
            data: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            characteristic: G6Constants.authenticationUUID
        )
        
        let hexDump = logger.export(format: .hexDump)
        
        #expect(hexDump.contains("01 02 03 04 05 06 07 08"))
        #expect(hexDump.contains("TX"))
    }
    
    @Test("CSV export format")
    func csvExport() {
        let logger = BLETrafficLogger()
        
        logger.log(direction: .outgoing, data: Data([0x01, 0x02]))
        logger.log(direction: .incoming, data: Data([0x05, 0x06]))
        
        let csv = logger.export(format: .csv)
        let lines = csv.split(separator: "\n")
        
        #expect(lines.count >= 3) // Header + 2 rows
        #expect(lines[0].contains("direction"))
        #expect(lines[0].contains("opcode"))
    }
}

// MARK: - Integrated End-to-End Trace

@Suite("G6 Complete End-to-End Trace")
struct G6CompleteTraceTests {
    
    @Test("Full connection → auth → glucose → disconnect trace")
    func fullTraceSequence() async throws {
        // Set up all three logging components
        let protocolLogger = G6ProtocolLogger()
        let evidenceCollector = G6EvidenceCollector()
        let trafficLogger = BLETrafficLogger()
        
        let transmitterId = "80AB12"
        
        // === PHASE 1: Connection ===
        
        // BLE traffic: discovery/connect (simulated)
        trafficLogger.log(
            direction: .outgoing,
            data: Data([0x00]), // Connection indicator
            note: "Connection established"
        )
        
        // === PHASE 2: Authentication ===
        
        // Start protocol logging
        await protocolLogger.startSession(transmitterId: transmitterId, variant: .loopDefault)
        
        // Start evidence collection
        let attemptId = await evidenceCollector.startAttempt(
            transmitterId: transmitterId,
            variant: .loopDefault,
            isFirefly: false
        )
        #expect(!attemptId.isEmpty)
        
        // Key derivation
        var phaseStart = await evidenceCollector.startPhase(.keyDerivation)
        await protocolLogger.log(event: .keyDerivationStarted)
        await protocolLogger.logKeyDerivation(
            transmitterId: transmitterId,
            keyBytes: Array(repeating: 0x30, count: 16),
            variant: .asciiZeros
        )
        await evidenceCollector.completePhase(.keyDerivation, startTime: phaseStart, success: true)
        
        // Token send
        phaseStart = await evidenceCollector.startPhase(.tokenSend)
        let token: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        await protocolLogger.logTokenGeneration(token: token)
        
        // BLE traffic: auth request
        trafficLogger.log(
            direction: .outgoing,
            data: Data([0x01] + token + [0x02]),
            characteristic: G6Constants.authenticationUUID
        )
        
        await protocolLogger.log(event: .tokenSent)
        await evidenceCollector.completePhase(.tokenSend, startTime: phaseStart, success: true)
        
        // Token verify
        phaseStart = await evidenceCollector.startPhase(.tokenVerify)
        
        // BLE traffic: auth response
        let tokenHash: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11]
        trafficLogger.log(
            direction: .incoming,
            data: Data([0x03] + tokenHash),
            characteristic: G6Constants.authenticationUUID
        )
        
        await protocolLogger.log(event: .tokenHashReceived)
        await protocolLogger.logTokenHashVerification(
            expectedHash: tokenHash,
            receivedHash: tokenHash,
            matched: true
        )
        await evidenceCollector.completePhase(.tokenVerify, startTime: phaseStart, success: true)
        
        // Challenge-response
        phaseStart = await evidenceCollector.startPhase(.challengeResponse)
        
        let challenge: [UInt8] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
        trafficLogger.log(
            direction: .incoming,
            data: Data([0x04] + challenge),
            characteristic: G6Constants.authenticationUUID
        )
        
        let response: [UInt8] = [0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00]
        await protocolLogger.logChallengeResponse(challenge: challenge, response: response)
        
        trafficLogger.log(
            direction: .outgoing,
            data: Data([0x04] + response),
            characteristic: G6Constants.authenticationUUID
        )
        
        await protocolLogger.log(event: .challengeResponseSent)
        await evidenceCollector.completePhase(.challengeResponse, startTime: phaseStart, success: true)
        
        // Status check
        phaseStart = await evidenceCollector.startPhase(.statusCheck)
        
        trafficLogger.log(
            direction: .incoming,
            data: Data([0x05, 0x01, 0x00]), // Auth status: authenticated, not bonded
            characteristic: G6Constants.authenticationUUID
        )
        
        await protocolLogger.logAuthStatus(authenticated: true, bonded: false)
        await evidenceCollector.completePhase(.statusCheck, startTime: phaseStart, success: true)
        
        // Complete auth
        await protocolLogger.endSession(success: true)
        await evidenceCollector.completeAttempt(success: true)
        
        // === PHASE 3: Glucose Reading ===
        
        // Request glucose
        trafficLogger.log(
            direction: .outgoing,
            data: Data([0x30]), // GlucoseTx
            characteristic: G6Constants.controlUUID
        )
        
        // Receive glucose
        trafficLogger.log(
            direction: .incoming,
            data: Data([0x31, 0x00, 0x78, 0x00, 0x64, 0x00, 0x00, 0x00]), // 120 mg/dL
            characteristic: G6Constants.controlUUID
        )
        
        // === VERIFICATION ===
        
        // Protocol logger verification
        let protocolEntries = await protocolLogger.getEntries()
        #expect(protocolEntries.count >= 10)
        #expect(protocolEntries.first?.event == .authenticationStarted)
        #expect(protocolEntries.last?.event == .authenticationCompleted)
        
        let hasFailures = await protocolLogger.hasFailures
        #expect(hasFailures == false)
        
        // Evidence collector verification
        let attempts = await evidenceCollector.getAttempts()
        #expect(attempts.count == 1)
        
        let attempt = attempts[0]
        #expect(attempt.success == true)
        #expect(attempt.allPhasesSucceeded == true)
        #expect(attempt.transmitterId == transmitterId)
        
        // BLE traffic verification
        let stats = trafficLogger.statistics
        #expect(stats.totalEntries >= 8)
        #expect(stats.outgoingCount >= 3)
        #expect(stats.incomingCount >= 4)
        
        // Verify auth characteristic traffic
        var authFilter = TrafficFilter()
        authFilter.characteristic = G6Constants.authenticationUUID
        let authTraffic = trafficLogger.filter(authFilter)
        #expect(authTraffic.count >= 5)
        
        // Verify control characteristic traffic
        var controlFilter = TrafficFilter()
        controlFilter.characteristic = G6Constants.controlUUID
        let controlTraffic = trafficLogger.filter(controlFilter)
        #expect(controlTraffic.count >= 2)
        
        // Export verification
        let protocolJSON = try await protocolLogger.exportJSON()
        #expect(protocolJSON.count > 0)
        
        let evidenceJSON = try await evidenceCollector.exportJSON()
        #expect(evidenceJSON.count > 0)
        
        let bleCSV = trafficLogger.export(format: .csv)
        #expect(bleCSV.contains("direction"))
    }
    
    @Test("Error trace captures failure context")
    func errorTraceCapture() async {
        let protocolLogger = G6ProtocolLogger()
        let evidenceCollector = G6EvidenceCollector()
        
        let transmitterId = "80AB12"
        
        // Start auth
        await protocolLogger.startSession(transmitterId: transmitterId, variant: .loopDefault)
        _ = await evidenceCollector.startAttempt(
            transmitterId: transmitterId,
            variant: .loopDefault
        )
        
        // Key derivation succeeds
        var phaseStart = await evidenceCollector.startPhase(.keyDerivation)
        await protocolLogger.logKeyDerivation(
            transmitterId: transmitterId,
            keyBytes: Array(repeating: 0x30, count: 16),
            variant: .asciiZeros
        )
        await evidenceCollector.completePhase(.keyDerivation, startTime: phaseStart, success: true)
        
        // Token send succeeds
        phaseStart = await evidenceCollector.startPhase(.tokenSend)
        await protocolLogger.logTokenGeneration(token: Array(repeating: 0x01, count: 8))
        await evidenceCollector.completePhase(.tokenSend, startTime: phaseStart, success: true)
        
        // Token verify FAILS
        phaseStart = await evidenceCollector.startPhase(.tokenVerify)
        await protocolLogger.logTokenHashVerification(
            expectedHash: [0xAA, 0xBB, 0xCC, 0xDD],
            receivedHash: [0x11, 0x22, 0x33, 0x44],
            matched: false
        )
        await evidenceCollector.completePhase(
            .tokenVerify,
            startTime: phaseStart,
            success: false,
            error: "Token hash mismatch",
            errorCode: "E_TOKEN_VERIFY"
        )
        
        // Complete with failure
        await protocolLogger.endSession(success: false)
        await evidenceCollector.completeAttempt(
            success: false,
            error: "Authentication failed: token hash mismatch"
        )
        
        // Verify error trace
        let failedEvents = await protocolLogger.getFailedEvents()
        #expect(failedEvents.count >= 2) // tokenHashFailed + authenticationFailed
        
        let hasFailures = await protocolLogger.hasFailures
        #expect(hasFailures == true)
        
        let attempts = await evidenceCollector.getAttempts()
        let attempt = attempts[0]
        
        #expect(attempt.success == false)
        #expect(attempt.tokenVerify?.success == false)
        #expect(attempt.tokenVerify?.errorMessage == "Token hash mismatch")
        #expect(attempt.firstFailedPhase?.phase == .tokenVerify)
    }
}
