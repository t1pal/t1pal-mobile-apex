// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// G7SessionStateTests.swift
// CGMKit Tests
//
// Tests for G7 session state machine (G7-DIAG-003)
// Validates state transitions match Python g7-jpake.py SessionState

import Testing
import Foundation
@testable import CGMKit

// MARK: - G7 Session State Tests

@Suite("G7 Session State Machine")
struct G7SessionStateTests {
    
    // MARK: - State Enum Tests
    
    @Test("All 16 states are defined")
    func allStatesDefined() {
        let allStates = G7SessionState.allCases
        #expect(allStates.count == 16)
        
        // Verify key states exist
        #expect(allStates.contains(.initial))
        #expect(allStates.contains(.round1Generated))
        #expect(allStates.contains(.round1Received))
        #expect(allStates.contains(.round1Verified))
        #expect(allStates.contains(.round2Generated))
        #expect(allStates.contains(.round2Received))
        #expect(allStates.contains(.round2Verified))
        #expect(allStates.contains(.keyDerived))
        #expect(allStates.contains(.confirmGenerated))
        #expect(allStates.contains(.confirmReceived))
        #expect(allStates.contains(.confirmVerified))
        #expect(allStates.contains(.authenticated))
        #expect(allStates.contains(.failed))
    }
    
    @Test("State raw values match Python")
    func stateRawValuesMatchPython() {
        // These must match Python SessionState enum exactly
        #expect(G7SessionState.initial.rawValue == "INIT")
        #expect(G7SessionState.round1Generated.rawValue == "ROUND1_GENERATED")
        #expect(G7SessionState.round1Sent.rawValue == "ROUND1_SENT")
        #expect(G7SessionState.round1Received.rawValue == "ROUND1_RECEIVED")
        #expect(G7SessionState.round1Verified.rawValue == "ROUND1_VERIFIED")
        #expect(G7SessionState.round2Generated.rawValue == "ROUND2_GENERATED")
        #expect(G7SessionState.round2Sent.rawValue == "ROUND2_SENT")
        #expect(G7SessionState.round2Received.rawValue == "ROUND2_RECEIVED")
        #expect(G7SessionState.round2Verified.rawValue == "ROUND2_VERIFIED")
        #expect(G7SessionState.keyDerived.rawValue == "KEY_DERIVED")
        #expect(G7SessionState.confirmGenerated.rawValue == "CONFIRM_GENERATED")
        #expect(G7SessionState.confirmSent.rawValue == "CONFIRM_SENT")
        #expect(G7SessionState.confirmReceived.rawValue == "CONFIRM_RECEIVED")
        #expect(G7SessionState.confirmVerified.rawValue == "CONFIRM_VERIFIED")
        #expect(G7SessionState.authenticated.rawValue == "AUTHENTICATED")
        #expect(G7SessionState.failed.rawValue == "FAILED")
    }
    
    // MARK: - Valid Transitions
    
    @Test("INIT can transition to ROUND1_GENERATED or ROUND1_RECEIVED")
    func initValidTransitions() {
        let state = G7SessionState.initial
        #expect(state.canTransition(to: .round1Generated))
        #expect(state.canTransition(to: .round1Received))
        #expect(!state.canTransition(to: .authenticated))
        #expect(!state.canTransition(to: .round2Generated))
    }
    
    @Test("ROUND1_RECEIVED can transition to ROUND1_VERIFIED or FAILED")
    func round1ReceivedTransitions() {
        let state = G7SessionState.round1Received
        #expect(state.canTransition(to: .round1Verified))
        #expect(state.canTransition(to: .failed))
        #expect(!state.canTransition(to: .authenticated))
        #expect(!state.canTransition(to: .round2Verified))
    }
    
    @Test("ROUND2_VERIFIED transitions to KEY_DERIVED")
    func round2VerifiedTransitions() {
        let state = G7SessionState.round2Verified
        #expect(state.canTransition(to: .keyDerived))
        #expect(!state.canTransition(to: .authenticated))
    }
    
    @Test("CONFIRM_VERIFIED transitions to AUTHENTICATED")
    func confirmVerifiedTransitions() {
        let state = G7SessionState.confirmVerified
        #expect(state.canTransition(to: .authenticated))
        #expect(!state.canTransition(to: .failed))
    }
    
    @Test("Terminal states have no transitions")
    func terminalStates() {
        #expect(G7SessionState.authenticated.validTransitions.isEmpty)
        #expect(G7SessionState.failed.validTransitions.isEmpty)
    }
}

// MARK: - Session Context Tests

@Suite("G7 Session Context")
struct G7SessionContextTests {
    
    @Test("Context starts in INIT state")
    func contextStartsInInit() async {
        let context = G7SessionContext()
        let state = await context.state
        #expect(state == .initial)
    }
    
    @Test("Valid transition succeeds")
    func validTransitionSucceeds() async {
        let context = G7SessionContext()
        let success = await context.transition(to: .round1Received, context: "Test")
        #expect(success)
        
        let state = await context.state
        #expect(state == .round1Received)
    }
    
    @Test("Invalid transition moves to FAILED")
    func invalidTransitionFails() async {
        let context = G7SessionContext()
        // Try to skip directly to authenticated
        let success = await context.transition(to: .authenticated, context: "Invalid")
        #expect(!success)
        
        let state = await context.state
        #expect(state == .failed)
        
        let error = await context.errorContext
        #expect(error != nil)
    }
    
    @Test("Transitions are recorded")
    func transitionsRecorded() async {
        let context = G7SessionContext()
        await context.transition(to: .round1Received, context: "Step 1")
        await context.transition(to: .round1Verified, context: "Step 2")
        
        let transitions = await context.transitions
        #expect(transitions.count == 2)
        #expect(transitions[0].fromState == .initial)
        #expect(transitions[0].toState == .round1Received)
        #expect(transitions[1].fromState == .round1Received)
        #expect(transitions[1].toState == .round1Verified)
    }
    
    @Test("Full successful flow")
    func fullSuccessfulFlow() async {
        let context = G7SessionContext()
        
        // Simulate initiator flow
        await context.transition(to: .round1Generated)
        await context.transition(to: .round1Sent)
        await context.transition(to: .round1Received)
        await context.transition(to: .round1Verified)
        await context.transition(to: .round2Generated)
        await context.transition(to: .round2Sent)
        await context.transition(to: .round2Received)
        await context.transition(to: .round2Verified)
        await context.transition(to: .keyDerived)
        await context.transition(to: .confirmGenerated)
        await context.transition(to: .confirmSent)
        await context.transition(to: .confirmReceived)
        await context.transition(to: .confirmVerified)
        await context.transition(to: .authenticated)
        
        let state = await context.state
        #expect(state == .authenticated)
        #expect(await context.isAuthenticated)
        #expect(!(await context.isFailed))
    }
    
    @Test("Crypto state can be set and retrieved")
    func cryptoStateStorage() async {
        let context = G7SessionContext()
        let testKey = Data([0x01, 0x02, 0x03, 0x04])
        
        await context.setSharedKey(testKey)
        let retrieved = await context.sharedKey
        #expect(retrieved == testKey)
    }
    
    @Test("Session can be exported to JSON")
    func jsonExport() async throws {
        let context = G7SessionContext()
        await context.transition(to: .round1Received)
        await context.setSharedKey(Data([0xAB, 0xCD]))
        
        let json = try await context.exportJSON()
        #expect(json.count > 0)
        
        // Verify it's valid JSON
        let parsed = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        #expect(parsed != nil)
        #expect(parsed?["state"] as? String == "ROUND1_RECEIVED")
    }
}

// MARK: - Message Direction Tests

@Suite("Message Direction")
struct MessageDirectionTests {
    
    @Test("TX direction has correct prefix")
    func txDirection() {
        let direction = MessageDirection.tx
        #expect(direction.prefix == "[TX →]")
        #expect(direction.emoji == "📤")
        #expect(direction.rawValue == "TX")
    }
    
    @Test("RX direction has correct prefix")
    func rxDirection() {
        let direction = MessageDirection.rx
        #expect(direction.prefix == "[← RX]")
        #expect(direction.emoji == "📥")
        #expect(direction.rawValue == "RX")
    }
}

// MARK: - Protocol Log Entry Tests

@Suite("G7 Protocol Log Entry")
struct G7ProtocolLogEntryTests {
    
    @Test("Entry includes direction in formatted output")
    func entryFormattedWithDirection() {
        let entry = G7ProtocolLogEntry(
            event: .round1RemoteReceived,
            message: "Test message",
            direction: .rx,
            sessionState: .round1Received
        )
        
        let formatted = entry.formatted
        #expect(formatted.contains("[← RX]"))
        #expect(formatted.contains("[ROUND1_RECEIVED]"))
        #expect(formatted.contains("Test message"))
    }
    
    @Test("Entry without direction has no prefix")
    func entryWithoutDirection() {
        let entry = G7ProtocolLogEntry(
            event: .authenticationStarted,
            message: "Test"
        )
        
        let formatted = entry.formatted
        #expect(!formatted.contains("[TX"))
        #expect(!formatted.contains("[← RX]"))
    }
}
