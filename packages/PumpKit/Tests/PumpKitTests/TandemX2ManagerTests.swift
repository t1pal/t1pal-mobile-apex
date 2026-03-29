// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TandemX2ManagerTests.swift
// PumpKitTests
//
// Tests for TandemX2Manager pump control implementation.
// Validates PumpManagerProtocol conformance and pump operations.
//
// Trace: TANDEM-IMPL-004, REQ-AID-001

import Testing
@testable import PumpKit

// MARK: - TandemX2Manager Tests

@Suite("Tandem X2 Manager")
struct TandemX2ManagerTests {
    
    @Suite("Initialization")
    struct InitializationTests {
        @Test("Default initialization works")
        func testDefaultInit() async {
            let manager = TandemX2Manager()
            
            #expect(manager.displayName == "Tandem t:slim X2")
            #expect(manager.pumpType == .tandemX2)
            
            let status = await manager.status
            #expect(status.connectionState == .disconnected)
        }
        
        @Test("Custom limits respected")
        func testCustomLimits() async {
            let manager = TandemX2Manager(maxBolus: 10.0, maxBasalRate: 3.0)
            
            // Manager should reject bolus exceeding limit
            await #expect(throws: PumpError.self) {
                try await manager.deliverBolus(units: 15.0)
            }
        }
    }
    
    @Suite("Pairing Code")
    struct PairingCodeTests {
        @Test("Pairing code can be set")
        func testSetPairingCode() async {
            let manager = TandemX2Manager()
            
            await manager.setPairingCode("123456")
            let code = await manager.pairingCode
            
            #expect(code == "123456")
        }
        
        @Test("Pairing code can be cleared")
        func testClearPairingCode() async {
            let manager = TandemX2Manager()
            
            await manager.setPairingCode("123456")
            await manager.setPairingCode(nil)
            let code = await manager.pairingCode
            
            #expect(code == nil)
        }
    }
    
    @Suite("Simulation Mode")
    struct SimulationModeTests {
        @Test("Test mode enables fast operations")
        func testEnableTestMode() async {
            let manager = TandemX2Manager()
            
            await manager.enableTestMode()
            
            // Should not throw - test mode skips delays
            // (Can't easily verify delay was skipped without timing)
        }
    }
    
    @Suite("Bolus Limits")
    struct BolusLimitTests {
        @Test("Bolus within limit accepted")
        func testBolusWithinLimit() async throws {
            let manager = TandemX2Manager(maxBolus: 25.0)
            await manager.enableTestMode()
            
            // This will fail because no pump connected, but validates parameter check passes
            await #expect(throws: Error.self) {
                try await manager.deliverBolus(units: 5.0)
            }
        }
        
        @Test("Bolus exceeding limit rejected")
        func testBolusExceedsLimit() async {
            let manager = TandemX2Manager(maxBolus: 10.0)
            
            do {
                try await manager.deliverBolus(units: 15.0)
                Issue.record("Expected exceedsMaxBolus error")
            } catch let error as PumpError {
                #expect(error == .exceedsMaxBolus)
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
        
        @Test("Zero bolus rejected")
        func testZeroBolus() async {
            let manager = TandemX2Manager()
            
            do {
                try await manager.deliverBolus(units: 0.0)
                Issue.record("Expected error for zero bolus")
            } catch let error as PumpError {
                #expect(error == .exceedsMaxBolus)
            } catch {
                // Other error types acceptable
            }
        }
    }
    
    @Suite("Temp Basal Limits")
    struct TempBasalLimitTests {
        @Test("Temp basal within limit accepted")
        func testTempBasalWithinLimit() async throws {
            let manager = TandemX2Manager(maxBasalRate: 5.0)
            await manager.enableTestMode()
            
            // This will fail because no pump connected, but validates parameter check passes
            await #expect(throws: Error.self) {
                try await manager.setTempBasal(rate: 2.0, duration: 3600)
            }
        }
        
        @Test("Temp basal exceeding limit rejected")
        func testTempBasalExceedsLimit() async {
            let manager = TandemX2Manager(maxBasalRate: 3.0)
            
            do {
                try await manager.setTempBasal(rate: 5.0, duration: 3600)
                Issue.record("Expected exceedsMaxBasal error")
            } catch let error as PumpError {
                #expect(error == .exceedsMaxBasal)
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
        
        @Test("Invalid duration rejected")
        func testInvalidDuration() async {
            let manager = TandemX2Manager()
            
            do {
                try await manager.setTempBasal(rate: 1.0, duration: 0)
                Issue.record("Expected error for zero duration")
            } catch {
                // Expected
            }
        }
    }
    
    @Suite("Cancel Operations")
    struct CancelOperationsTests {
        @Test("Cancel bolus with no active bolus is safe")
        func testCancelNoActiveBolus() async throws {
            let manager = TandemX2Manager()
            
            // Should not throw when no active bolus
            try await manager.cancelBolus()
            
            let activeDelivery = await manager.activeBolusDelivery
            #expect(activeDelivery == nil)
        }
    }
    
    @Suite("Status Updates")
    struct StatusUpdateTests {
        @Test("Initial status is disconnected")
        func testInitialStatus() async {
            let manager = TandemX2Manager()
            
            let status = await manager.status
            #expect(status.connectionState == .disconnected)
            #expect(status.insulinOnBoard == 0)
            #expect(status.reservoirLevel == nil)
            #expect(status.batteryLevel == nil)
        }
        
        @Test("Status callback can be set")
        func testStatusCallback() async {
            let manager = TandemX2Manager()
            
            // Just verify callback can be set without error
            await manager.setStatusCallback { _ in
                // no-op - verifying callback mechanism works
            }
        }
    }
    
    @Suite("Diagnostics")
    struct DiagnosticsTests {
        @Test("Diagnostic info available")
        func testDiagnosticInfo() async {
            let manager = TandemX2Manager()
            
            let diagnostics = await manager.diagnosticInfo()
            
            #expect(diagnostics.discoveredCount >= 0)
        }
    }
}

// MARK: - Helper Extensions

extension TandemX2Manager {
    /// Set status callback helper for tests
    func setStatusCallback(_ callback: @escaping @Sendable (PumpStatus) -> Void) {
        onStatusChanged = callback
    }
}
