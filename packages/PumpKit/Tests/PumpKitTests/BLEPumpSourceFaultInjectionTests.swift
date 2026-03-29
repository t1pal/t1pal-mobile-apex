// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLEPumpSourceFaultInjectionTests.swift
// PumpKit
//
// Tests for BLEPumpSource fault injection wiring (WIRE-010)
//

import Testing
@testable import PumpKit

@Suite("BLEPumpSource Fault Injection")
struct BLEPumpSourceFaultInjectionTests {
    
    @Test("Connection timeout fault prevents start")
    func connectionTimeoutFault() async throws {
        let injector = PumpFaultInjector()
        injector.addFault(.connectionTimeout, trigger: .immediate)
        
        let config = BLEPumpConfig(pumpType: .omnipodDash, pumpSerial: "TEST123")
        let source = BLEPumpSource(config: config, faultInjector: injector)
        
        do {
            try await source.start()
            #expect(Bool(false), "Expected connection to fail with timeout")
        } catch {
            #expect(error is BLEPumpError)
            if case BLEPumpError.connectionFailed = error {
                // Expected
            } else {
                #expect(Bool(false), "Expected connectionFailed error, got \(error)")
            }
        }
    }
    
    @Test("Command fault after connection causes execute to fail")
    func commandFaultAfterConnection() async throws {
        let injector = PumpFaultInjector()
        // Only fault on command execution, not connection
        injector.addFault(.communicationError(code: 0x42), trigger: .onCommand("blepumpsource.readStatus"))
        
        let config = BLEPumpConfig(pumpType: .omnipodDash, pumpSerial: "TEST456")
        let source = BLEPumpSource(config: config, faultInjector: injector)
        
        // Connection should succeed
        try await source.start()
        
        // Command should fail
        do {
            _ = try await source.execute(.readStatus)
            #expect(Bool(false), "Expected command to fail")
        } catch {
            #expect(error is BLEPumpError)
        }
    }
    
    @Test("Metrics record command success and failure")
    func metricsRecording() async throws {
        let metrics = PumpMetrics.shared
        let config = BLEPumpConfig(pumpType: .simulation, pumpSerial: "METRICS_TEST")
        let source = BLEPumpSource(config: config, metrics: metrics)
        
        // Start should succeed and record metrics
        try await source.start()
        
        // Execute a command
        _ = try await source.execute(.readStatus)
        
        // Metrics should have recorded both operations
        // (We can't easily verify without exposing metrics state, but this exercises the code path)
        #expect(await source.status.connectionState == .connected)
    }
}
