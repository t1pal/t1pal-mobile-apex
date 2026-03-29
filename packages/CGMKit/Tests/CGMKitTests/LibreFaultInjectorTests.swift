// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LibreFaultInjectorTests.swift
// CGMKitTests
//
// Tests for LibreFaultInjector fault injection system.
// Trace: LIBRE-FIX-015, SIM-FAULT-001

import Testing
import Foundation
@testable import CGMKit

@Suite("LibreFaultInjectorTests")
struct LibreFaultInjectorTests {
    
    // MARK: - Basic Injection Tests
    
    @Test("No fault by default")
    func noFaultByDefault() {
        let injector = LibreFaultInjector()
        let result = injector.shouldInject()
        
        if case .noFault = result {
            // Expected
        } else {
            Issue.record("Expected no fault without configuration")
        }
    }
    
    @Test("Immediate fault injection")
    func immediateFaultInjection() {
        let injector = LibreFaultInjector()
        injector.addFault(.unlockTimeout)
        
        let result = injector.shouldInject()
        
        if case .injected(let fault) = result {
            #expect(fault == .unlockTimeout)
        } else {
            Issue.record("Expected immediate fault injection")
        }
    }
    
    @Test("On operation trigger")
    func onOperationTrigger() {
        let injector = LibreFaultInjector()
        injector.addFault(.unlockRejected(code: 0x01), trigger: .onOperation("unlock"))
        
        // Should not trigger for wrong operation
        let wrongOp = injector.shouldInject(for: "connect")
        if case .noFault = wrongOp {
            // Expected
        } else {
            Issue.record("Should not inject for non-matching operation")
        }
        
        // Should trigger for correct operation
        let correctOp = injector.shouldInject(for: "unlock")
        if case .injected(let fault) = correctOp {
            if case .unlockRejected(let code) = fault {
                #expect(code == 0x01)
            } else {
                Issue.record("Expected unlockRejected fault")
            }
        } else {
            Issue.record("Expected fault injection for matching operation")
        }
    }
    
    @Test("Once trigger")
    func onceTrigger() {
        let injector = LibreFaultInjector()
        injector.addFault(.cryptoFailed, trigger: .once)
        
        // First call should inject
        let first = injector.shouldInject()
        if case .injected = first {
            // Expected
        } else {
            Issue.record("Expected first injection to succeed")
        }
        
        // Second call should not inject
        let second = injector.shouldInject()
        if case .noFault = second {
            // Expected - once trigger exhausted
        } else {
            Issue.record("Expected once trigger to be exhausted")
        }
    }
    
    @Test("After operations trigger")
    func afterOperationsTrigger() {
        let injector = LibreFaultInjector()
        injector.addFault(.connectionDrop, trigger: .afterOperations(3))
        
        // Should not inject before 3 operations
        #expect(injector.operationCount == 0)
        let before = injector.shouldInject()
        if case .noFault = before {
            // Expected
        } else {
            Issue.record("Should not inject before threshold")
        }
        
        // Record 3 operations
        injector.recordOperation()
        injector.recordOperation()
        injector.recordOperation()
        #expect(injector.operationCount == 3)
        
        // Now should inject
        let after = injector.shouldInject()
        if case .injected(let fault) = after {
            #expect(fault == .connectionDrop)
        } else {
            Issue.record("Expected injection after reaching threshold")
        }
    }
    
    @Test("After readings trigger")
    func afterReadingsTrigger() {
        let injector = LibreFaultInjector()
        injector.addFault(.invalidDataFrame, trigger: .afterReadings(2))
        
        // Record 2 readings
        injector.recordReading()
        injector.recordReading()
        #expect(injector.readingCount == 2)
        
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .invalidDataFrame)
        } else {
            Issue.record("Expected injection after readings threshold")
        }
    }
    
    // MARK: - Fault Type Tests
    
    @Test("Fault categories")
    func faultCategories() {
        #expect(LibreFaultType.unlockTimeout.category == .authentication)
        #expect(LibreFaultType.connectionDrop.category == .connection)
        #expect(LibreFaultType.sensorExpired.category == .sensor)
        #expect(LibreFaultType.packetCorruption(probability: 0.5).category == .communication)
        #expect(LibreFaultType.regionLocked.category == .firmware)
    }
    
    @Test("Stops streaming property")
    func stopsStreamingProperty() {
        #expect(LibreFaultType.unlockTimeout.stopsStreaming)
        #expect(LibreFaultType.sensorExpired.stopsStreaming)
        #expect(LibreFaultType.cryptoFailed.stopsStreaming)
        
        #expect(!LibreFaultType.sensorWarmup.stopsStreaming)
        #expect(!LibreFaultType.responseDelay(milliseconds: 100).stopsStreaming)
        #expect(!LibreFaultType.packetCorruption(probability: 0.1).stopsStreaming)
    }
    
    @Test("Fault display names")
    func faultDisplayNames() {
        #expect(LibreFaultType.unlockTimeout.displayName == "Unlock Timeout")
        #expect(LibreFaultType.sensorExpired.displayName == "Sensor Expired")
        #expect(LibreFaultType.unlockRejected(code: 0xFF).displayName == "Unlock Rejected (0xff)")
        #expect(LibreFaultType.responseDelay(milliseconds: 500).displayName == "Response Delay (500ms)")
        #expect(LibreFaultType.packetCorruption(probability: 0.25).displayName == "Packet Corruption (25%)")
    }
    
    // MARK: - Preset Tests
    
    @Test("Preset unlock timeout")
    func presetUnlockTimeout() {
        let injector = LibreFaultInjector.unlockTimeout
        
        let result = injector.shouldInject(for: "unlock")
        if case .injected(let fault) = result {
            #expect(fault == .unlockTimeout)
        } else {
            Issue.record("Expected unlockTimeout preset to inject")
        }
    }
    
    @Test("Preset sensor expired")
    func presetSensorExpired() {
        let injector = LibreFaultInjector.sensorExpired
        
        let result = injector.shouldInject(for: "readGlucose")
        if case .injected(let fault) = result {
            #expect(fault == .sensorExpired)
        } else {
            Issue.record("Expected sensorExpired preset to inject")
        }
    }
    
    @Test("Preset sensor warmup")
    func presetSensorWarmup() {
        let injector = LibreFaultInjector.sensorWarmup
        
        // Should inject immediately
        let result = injector.shouldInject()
        if case .injected(let fault) = result {
            #expect(fault == .sensorWarmup)
        } else {
            Issue.record("Expected sensorWarmup preset to inject immediately")
        }
    }
    
    @Test("Preset NFC required")
    func presetNfcRequired() {
        let injector = LibreFaultInjector.nfcRequired
        
        let result = injector.shouldInject(for: "connect")
        if case .injected(let fault) = result {
            #expect(fault == .nfcRequired)
        } else {
            Issue.record("Expected nfcRequired preset to inject on connect")
        }
    }
    
    @Test("Preset unreliable connection")
    func presetUnreliableConnection() {
        let injector = LibreFaultInjector.unreliableConnection
        
        // This preset has 3 faults with probabilistic behavior
        #expect(injector.faults.count == 3)
    }
    
    // MARK: - Configuration Tests
    
    @Test("Add and remove fault")
    func addAndRemoveFault() {
        let injector = LibreFaultInjector()
        
        let config = LibreFaultConfiguration(
            id: "test-fault",
            fault: .sensorWarmup,
            trigger: .immediate
        )
        injector.addFault(config)
        #expect(injector.faults.count == 1)
        
        injector.removeFault(id: "test-fault")
        #expect(injector.faults.count == 0)
    }
    
    @Test("Clear faults")
    func clearFaults() {
        let injector = LibreFaultInjector()
        injector.addFault(.sensorExpired)
        injector.addFault(.connectionDrop)
        #expect(injector.faults.count == 2)
        
        injector.clearFaults()
        #expect(injector.faults.count == 0)
    }
    
    @Test("Reset")
    func reset() {
        let injector = LibreFaultInjector()
        injector.recordOperation()
        injector.recordOperation()
        injector.recordReading()
        
        #expect(injector.operationCount == 2)
        #expect(injector.readingCount == 1)
        
        injector.reset()
        
        #expect(injector.operationCount == 0)
        #expect(injector.readingCount == 0)
    }
    
    // MARK: - All Libre Fault Types Coverage
    
    @Test("All fault types have display names")
    func allFaultTypesHaveDisplayNames() {
        let allFaults: [LibreFaultType] = [
            .unlockTimeout,
            .unlockRejected(code: 0x01),
            .cryptoFailed,
            .unlockCountMismatch,
            .connectionDrop,
            .connectionTimeout,
            .scanTimeout,
            .nfcRequired,
            .sensorExpired,
            .sensorWarmup,
            .sensorFailed(code: 0x02),
            .sensorNotActivated,
            .sensorReplaced,
            .packetCorruption(probability: 0.5),
            .responseDelay(milliseconds: 100),
            .characteristicNotFound,
            .invalidDataFrame,
            .regionLocked,
            .firmwareUnsupported,
            .patchInfoMismatch
        ]
        
        for fault in allFaults {
            #expect(!fault.displayName.isEmpty, "Fault \(fault) should have display name")
        }
    }
    
    @Test("All fault categories covered")
    func allFaultCategoriesCovered() {
        let categories = LibreFaultCategory.allCases
        #expect(categories.count == 5)
        #expect(categories.contains(.authentication))
        #expect(categories.contains(.connection))
        #expect(categories.contains(.sensor))
        #expect(categories.contains(.communication))
        #expect(categories.contains(.firmware))
    }
}
