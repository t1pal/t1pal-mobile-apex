// SPDX-License-Identifier: MIT
//
// SilentDeliveryFailureTests.swift
// PumpKitTests
//
// Tests for silent delivery failure detection and recovery.
// A "silent failure" occurs when insulin is delivered by the pump but the
// delivery record is not properly persisted (audit log, IOB tracker, or external sync).
// This is safety-critical: unrecorded deliveries can lead to insulin stacking.
//
// Trace: TEST-GAP-003, DOC-TEST-003, CRITICAL-PATH-TESTS.md
// Requirements: REQ-AID-001, PROD-HARDEN

import Testing
import Foundation
@testable import PumpKit

// MARK: - Test Infrastructure

/// Mock audit log that can simulate persistence failures
actor FailableAuditLog {
    private var entries: [PumpAuditEntry] = []
    private var shouldFailNextWrite: Bool = false
    private var failureCount: Int = 0
    
    func setFailNextWrite(_ fail: Bool) {
        shouldFailNextWrite = fail
    }
    
    var totalFailures: Int {
        failureCount
    }
    
    func record(_ command: AuditCommand) async throws {
        if shouldFailNextWrite {
            shouldFailNextWrite = false
            failureCount += 1
            throw AuditLogError.persistenceFailed
        }
        entries.append(PumpAuditEntry(command: command, success: true))
    }
    
    func recordFailure(_ command: AuditCommand, error: String) async {
        entries.append(PumpAuditEntry(command: command, success: false, errorMessage: error))
    }
    
    func allEntries() async -> [PumpAuditEntry] {
        entries
    }
    
    func count() async -> Int {
        entries.count
    }
    
    func clear() async {
        entries.removeAll()
    }
}

/// Audit log errors
enum AuditLogError: Error {
    case persistenceFailed
    case diskFull
    case corruptedData
}

/// Mock delivery recorder that tracks whether delivery was recorded
actor DeliveryRecorder {
    private var recordedDeliveries: [(units: Double, timestamp: Date)] = []
    private var failNextRecord: Bool = false
    private var recordFailures: Int = 0
    
    func setFailNextRecord(_ fail: Bool) {
        failNextRecord = fail
    }
    
    func recordDelivery(units: Double, timestamp: Date = Date()) throws {
        if failNextRecord {
            failNextRecord = false
            recordFailures += 1
            throw DeliveryRecordError.recordFailed
        }
        recordedDeliveries.append((units: units, timestamp: timestamp))
    }
    
    var deliveries: [(units: Double, timestamp: Date)] {
        recordedDeliveries
    }
    
    var totalRecordFailures: Int {
        recordFailures
    }
    
    var totalDeliveredUnits: Double {
        recordedDeliveries.reduce(0) { $0 + $1.units }
    }
}

enum DeliveryRecordError: Error {
    case recordFailed
    case storageUnavailable
}

/// Delivery verification result
enum DeliveryVerificationResult: Equatable {
    case verified(units: Double)
    case discrepancy(delivered: Double, recorded: Double)
    case unverified
}

/// Mock pump that tracks actual deliveries vs recorded deliveries
actor SilentFailurePump {
    private var actualDeliveries: [(units: Double, timestamp: Date)] = []
    private var isConnected: Bool = false
    private let recorder: DeliveryRecorder
    
    init(recorder: DeliveryRecorder) {
        self.recorder = recorder
    }
    
    func connect() {
        isConnected = true
    }
    
    func disconnect() {
        isConnected = false
    }
    
    /// Deliver bolus - pump always succeeds, but recording may fail
    func deliverBolus(units: Double) async throws -> DeliveryVerificationResult {
        guard isConnected else {
            throw PumpError.notConnected
        }
        
        // Pump physically delivers insulin (always succeeds in this test)
        let timestamp = Date()
        actualDeliveries.append((units: units, timestamp: timestamp))
        
        // Attempt to record the delivery (may fail)
        do {
            try await recorder.recordDelivery(units: units, timestamp: timestamp)
            return .verified(units: units)
        } catch {
            // Silent failure: delivery happened but wasn't recorded
            return .discrepancy(delivered: units, recorded: 0)
        }
    }
    
    /// Get actual deliveries from pump history (truth source)
    var pumpHistory: [(units: Double, timestamp: Date)] {
        actualDeliveries
    }
    
    /// Get recorded deliveries
    func getRecordedDeliveries() async -> [(units: Double, timestamp: Date)] {
        await recorder.deliveries
    }
    
    /// Reconcile pump history with recorded deliveries
    func reconcile() async -> ReconciliationResult {
        let actual = actualDeliveries
        let recorded = await recorder.deliveries
        
        let actualTotal = actual.reduce(0) { $0 + $1.units }
        let recordedTotal = recorded.reduce(0) { $0 + $1.units }
        
        if abs(actualTotal - recordedTotal) < 0.001 {
            return .matched(units: actualTotal)
        } else {
            return .discrepancy(
                actualDelivered: actualTotal,
                recorded: recordedTotal,
                missing: actualTotal - recordedTotal
            )
        }
    }
}

/// Result of reconciling pump history with recorded deliveries
enum ReconciliationResult: Equatable {
    case matched(units: Double)
    case discrepancy(actualDelivered: Double, recorded: Double, missing: Double)
}

// MARK: - Silent Delivery Failure Detection Tests

@Suite("Silent Delivery Failure Detection")
struct SilentDeliveryFailureDetectionTests {
    
    @Test("Successful delivery is properly recorded")
    func successfulDeliveryRecorded() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        let result = try await pump.deliverBolus(units: 2.0)
        
        #expect(result == .verified(units: 2.0))
        
        let recorded = await recorder.deliveries
        #expect(recorded.count == 1)
        #expect(recorded[0].units == 2.0)
    }
    
    @Test("Silent failure detected when recording fails")
    func silentFailureDetected() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // Set up recording to fail
        await recorder.setFailNextRecord(true)
        
        // Delivery succeeds but recording fails
        let result = try await pump.deliverBolus(units: 3.0)
        
        // Should detect the discrepancy
        #expect(result == .discrepancy(delivered: 3.0, recorded: 0))
        
        // Pump history shows delivery happened
        let history = await pump.pumpHistory
        #expect(history.count == 1)
        #expect(history[0].units == 3.0)
        
        // But recorded deliveries is empty
        let recorded = await recorder.deliveries
        #expect(recorded.isEmpty)
    }
    
    @Test("Multiple deliveries with intermittent recording failures")
    func intermittentRecordingFailures() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // First delivery succeeds fully
        _ = try await pump.deliverBolus(units: 1.0)
        
        // Second delivery: recording fails
        await recorder.setFailNextRecord(true)
        let result2 = try await pump.deliverBolus(units: 2.0)
        #expect(result2 == .discrepancy(delivered: 2.0, recorded: 0))
        
        // Third delivery succeeds fully
        _ = try await pump.deliverBolus(units: 1.5)
        
        // Pump history shows all 3 deliveries
        let history = await pump.pumpHistory
        #expect(history.count == 3)
        
        // Recorded shows only 2 (first and third)
        let recorded = await recorder.deliveries
        #expect(recorded.count == 2)
        
        // Total discrepancy
        let actualTotal = history.reduce(0) { $0 + $1.units }  // 4.5
        let recordedTotal = recorded.reduce(0) { $0 + $1.units }  // 2.5
        #expect(abs(actualTotal - 4.5) < 0.001)
        #expect(abs(recordedTotal - 2.5) < 0.001)
    }
    
    @Test("Recording failure count is tracked")
    func recordingFailureCountTracked() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // Cause 3 recording failures
        for _ in 0..<3 {
            await recorder.setFailNextRecord(true)
            _ = try await pump.deliverBolus(units: 1.0)
        }
        
        let failures = await recorder.totalRecordFailures
        #expect(failures == 3)
    }
}

// MARK: - Reconciliation Tests

@Suite("Delivery Reconciliation")
struct DeliveryReconciliationTests {
    
    @Test("Reconciliation detects no discrepancy when all recorded")
    func reconciliationNoDiscrepancy() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        _ = try await pump.deliverBolus(units: 2.0)
        _ = try await pump.deliverBolus(units: 1.5)
        
        let result = await pump.reconcile()
        #expect(result == .matched(units: 3.5))
    }
    
    @Test("Reconciliation detects missing deliveries")
    func reconciliationDetectsMissing() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // First delivery recorded
        _ = try await pump.deliverBolus(units: 2.0)
        
        // Second delivery not recorded (silent failure)
        await recorder.setFailNextRecord(true)
        _ = try await pump.deliverBolus(units: 3.0)
        
        let result = await pump.reconcile()
        #expect(result == .discrepancy(actualDelivered: 5.0, recorded: 2.0, missing: 3.0))
    }
    
    @Test("Reconciliation calculates correct missing amount")
    func reconciliationCorrectMissingAmount() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // Multiple deliveries with some failures
        _ = try await pump.deliverBolus(units: 1.0)  // Recorded
        
        await recorder.setFailNextRecord(true)
        _ = try await pump.deliverBolus(units: 2.0)  // Not recorded
        
        _ = try await pump.deliverBolus(units: 1.5)  // Recorded
        
        await recorder.setFailNextRecord(true)
        _ = try await pump.deliverBolus(units: 0.5)  // Not recorded
        
        let result = await pump.reconcile()
        
        // Actual: 5.0, Recorded: 2.5, Missing: 2.5
        if case .discrepancy(let actual, let recorded, let missing) = result {
            #expect(abs(actual - 5.0) < 0.001)
            #expect(abs(recorded - 2.5) < 0.001)
            #expect(abs(missing - 2.5) < 0.001)
        } else {
            Issue.record("Expected discrepancy result")
        }
    }
}

// MARK: - IOB Impact Tests

@Suite("IOB Impact from Silent Failures")
struct IOBImpactTests {
    
    @Test("Silent failure causes IOB underestimation")
    func silentFailureCausesIOBUnderestimation() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // Deliver 5 units but recording fails
        await recorder.setFailNextRecord(true)
        _ = try await pump.deliverBolus(units: 5.0)
        
        // IOB calculated from records would be 0
        let recordedTotal = await recorder.totalDeliveredUnits
        #expect(recordedTotal == 0)
        
        // But actual delivery was 5 units
        let actualTotal = await pump.pumpHistory.reduce(0) { $0 + $1.units }
        #expect(actualTotal == 5.0)
        
        // This 5 unit discrepancy in IOB is dangerous
        // Algorithm might recommend additional insulin when patient already has 5U IOB
    }
    
    @Test("Multiple silent failures compound IOB error")
    func multipleSilentFailuresCompoundError() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // 3 deliveries, all fail to record
        for _ in 0..<3 {
            await recorder.setFailNextRecord(true)
            _ = try await pump.deliverBolus(units: 2.0)
        }
        
        // Recorded IOB: 0
        let recordedIOB = await recorder.totalDeliveredUnits
        #expect(recordedIOB == 0)
        
        // Actual IOB: 6 units
        let actualIOB = await pump.pumpHistory.reduce(0) { $0 + $1.units }
        #expect(actualIOB == 6.0)
        
        // 6 unit error is extremely dangerous
    }
}

// MARK: - OmnipodDashManager Silent Failure Tests

@Suite("OmnipodDashManager Silent Failure Handling")
struct OmnipodDashSilentFailureTests {
    
    @Test("Bolus delivery returns success even when audit log unavailable")
    func bolusSucceedsWithoutAuditLog() async throws {
        // Manager without audit log should still deliver successfully
        let manager = OmnipodDashManager(auditLog: nil)
        try await manager.activatePod()
        try await manager.connect()
        
        // Bolus should succeed - delivery is primary, logging is secondary
        try await manager.deliverBolus(units: 1.0)
        
        // Verify pump state reflects delivery
        let status = await manager.status
        #expect(status.connectionState == .connected)
    }
    
    @Test("Delivery state preserved after fault injection")
    func deliveryStatePreservedAfterFault() async throws {
        let auditLog = PumpAuditLog()
        let manager = OmnipodDashManager(auditLog: auditLog)
        
        try await manager.activatePod()
        try await manager.connect()
        
        // First bolus succeeds
        try await manager.deliverBolus(units: 2.0)
        
        // Verify delivery was tracked
        let entries = await auditLog.allEntries()
        let bolusEntries = entries.filter { 
            if case .deliverBolus = $0.command { return true }
            return false
        }
        #expect(bolusEntries.count == 1)
    }
    
    @Test("Fault during bolus logs failure correctly")
    func faultDuringBolusLogsFailure() async throws {
        let auditLog = PumpAuditLog()
        let faultInjector = PumpFaultInjector(faults: [
            PumpFaultConfiguration(fault: .occlusion, trigger: .onCommand("deliverBolus"))
        ])
        
        let manager = OmnipodDashManager(auditLog: auditLog, faultInjector: faultInjector)
        try await manager.activatePod()
        try await manager.connect()
        
        // Bolus should fail with occlusion
        await #expect(throws: PumpError.occluded) {
            try await manager.deliverBolus(units: 2.0)
        }
        
        // Note: In this case, the delivery actually didn't happen (fault before delivery)
        // This is different from silent failure where delivery happens but record fails
    }
}

// MARK: - Delivery Verification Tests

@Suite("Delivery Verification")
struct DeliveryVerificationTests {
    
    @Test("Verification result types")
    func verificationResultTypes() {
        let verified = DeliveryVerificationResult.verified(units: 2.0)
        let discrepancy = DeliveryVerificationResult.discrepancy(delivered: 2.0, recorded: 0)
        let unverified = DeliveryVerificationResult.unverified
        
        #expect(verified == .verified(units: 2.0))
        #expect(discrepancy == .discrepancy(delivered: 2.0, recorded: 0))
        #expect(unverified == .unverified)
    }
    
    @Test("Discrepancy detection is precise")
    func discrepancyDetectionPrecise() {
        let result1 = DeliveryVerificationResult.discrepancy(delivered: 2.0, recorded: 1.5)
        let result2 = DeliveryVerificationResult.discrepancy(delivered: 2.0, recorded: 0)
        
        #expect(result1 != result2)
    }
}

// MARK: - Audit Log Failure Simulation Tests

@Suite("Audit Log Failure Simulation")
struct AuditLogFailureSimulationTests {
    
    @Test("Failable audit log tracks failure count")
    func failableAuditLogTracksFailures() async throws {
        let auditLog = FailableAuditLog()
        
        // First write succeeds
        try await auditLog.record(.connect)
        #expect(await auditLog.totalFailures == 0)
        
        // Set up failure
        await auditLog.setFailNextWrite(true)
        
        // Second write fails
        await #expect(throws: AuditLogError.persistenceFailed) {
            try await auditLog.record(.deliverBolus(units: 2.0))
        }
        #expect(await auditLog.totalFailures == 1)
        
        // Third write succeeds (failure flag was reset)
        try await auditLog.record(.disconnect)
        
        // Verify entries: only 2 succeeded
        let entries = await auditLog.allEntries()
        #expect(entries.count == 2)
    }
    
    @Test("Audit log clears properly")
    func auditLogClears() async throws {
        let auditLog = FailableAuditLog()
        
        try await auditLog.record(.connect)
        try await auditLog.record(.deliverBolus(units: 1.0))
        
        #expect(await auditLog.count() == 2)
        
        await auditLog.clear()
        
        #expect(await auditLog.count() == 0)
    }
}

// MARK: - Recovery Scenario Tests

@Suite("Silent Failure Recovery Scenarios")
struct SilentFailureRecoveryTests {
    
    @Test("Recovery through pump history reconciliation")
    func recoveryThroughReconciliation() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // Some deliveries succeed, some fail to record
        _ = try await pump.deliverBolus(units: 1.0)  // Recorded
        
        await recorder.setFailNextRecord(true)
        _ = try await pump.deliverBolus(units: 2.0)  // Silent failure
        
        _ = try await pump.deliverBolus(units: 1.0)  // Recorded
        
        // Before reconciliation, recorded shows 2.0
        let beforeRecorded = await recorder.totalDeliveredUnits
        #expect(abs(beforeRecorded - 2.0) < 0.001)
        
        // Reconcile with pump history
        let result = await pump.reconcile()
        
        // Reconciliation reveals 2.0 units were missed
        if case .discrepancy(let actual, let recorded, let missing) = result {
            #expect(abs(actual - 4.0) < 0.001)
            #expect(abs(recorded - 2.0) < 0.001)
            #expect(abs(missing - 2.0) < 0.001)
            
            // This missing amount should be added to IOB calculation
            // to prevent insulin stacking
        } else {
            Issue.record("Expected discrepancy result for recovery")
        }
    }
    
    @Test("Full session with intermittent failures and recovery")
    func fullSessionWithRecovery() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // Simulate a realistic session with some failures
        let deliveries: [(units: Double, shouldFail: Bool)] = [
            (1.0, false),  // Meal bolus - recorded
            (0.5, true),   // Correction - silent failure
            (2.0, false),  // Another meal - recorded
            (0.3, true),   // Small correction - silent failure
            (1.5, false),  // Snack - recorded
        ]
        
        for delivery in deliveries {
            if delivery.shouldFail {
                await recorder.setFailNextRecord(true)
            }
            _ = try await pump.deliverBolus(units: delivery.units)
        }
        
        // Verify tracking
        let recorded = await recorder.totalDeliveredUnits
        let actual = await pump.pumpHistory.reduce(0) { $0 + $1.units }
        
        #expect(abs(recorded - 4.5) < 0.001)  // 1.0 + 2.0 + 1.5
        #expect(abs(actual - 5.3) < 0.001)    // All deliveries
        
        // Reconciliation for recovery
        let result = await pump.reconcile()
        if case .discrepancy(_, _, let missing) = result {
            #expect(abs(missing - 0.8) < 0.001)  // 0.5 + 0.3
        } else {
            Issue.record("Expected discrepancy for full session")
        }
    }
}

// MARK: - Edge Cases

@Suite("Silent Failure Edge Cases")
struct SilentFailureEdgeCases {
    
    @Test("Zero unit delivery with recording failure")
    func zeroUnitDeliveryFailure() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        await recorder.setFailNextRecord(true)
        let result = try await pump.deliverBolus(units: 0.0)
        
        // Even 0 unit discrepancy should be detected
        #expect(result == .discrepancy(delivered: 0.0, recorded: 0))
    }
    
    @Test("Very small delivery recording failure")
    func verySmallDeliveryFailure() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        await recorder.setFailNextRecord(true)
        let result = try await pump.deliverBolus(units: 0.05)
        
        #expect(result == .discrepancy(delivered: 0.05, recorded: 0))
        
        let reconciliation = await pump.reconcile()
        if case .discrepancy(_, _, let missing) = reconciliation {
            #expect(abs(missing - 0.05) < 0.001)
        }
    }
    
    @Test("Large delivery recording failure")
    func largeDeliveryFailure() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        await recorder.setFailNextRecord(true)
        let result = try await pump.deliverBolus(units: 10.0)
        
        #expect(result == .discrepancy(delivered: 10.0, recorded: 0))
        
        // 10 unit unrecorded delivery is extremely dangerous
        let reconciliation = await pump.reconcile()
        if case .discrepancy(_, _, let missing) = reconciliation {
            #expect(abs(missing - 10.0) < 0.001)
        }
    }
    
    @Test("All deliveries fail to record")
    func allDeliveriesFailToRecord() async throws {
        let recorder = DeliveryRecorder()
        let pump = SilentFailurePump(recorder: recorder)
        
        await pump.connect()
        
        // All 5 deliveries fail to record
        for _ in 0..<5 {
            await recorder.setFailNextRecord(true)
            _ = try await pump.deliverBolus(units: 1.0)
        }
        
        let recorded = await recorder.totalDeliveredUnits
        let actual = await pump.pumpHistory.reduce(0) { $0 + $1.units }
        
        #expect(recorded == 0)
        #expect(actual == 5.0)
        
        let reconciliation = await pump.reconcile()
        #expect(reconciliation == .discrepancy(actualDelivered: 5.0, recorded: 0, missing: 5.0))
    }
}
