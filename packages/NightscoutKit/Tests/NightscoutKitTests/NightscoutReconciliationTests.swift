// SPDX-License-Identifier: MIT
//
// NightscoutReconciliationTests.swift
// T1Pal Mobile
//
// Tests for Nightscout reconciliation protocol
// Requirements: REQ-AID-004

import Foundation
import Testing
@testable import NightscoutKit

// MARK: - Test Helpers

private actor UploadCounter {
    var count = 0
    func increment() { count += 1 }
}

// MARK: - DecisionAuditEntry Tests

@Suite("DecisionAuditEntry")
struct DecisionAuditEntryTests {
    @Test("Creation")
    func decisionAuditEntryCreation() {
        let decision = DecisionAuditEntry(
            decisionType: .tempBasal,
            algorithmName: "oref1",
            reason: "BG rising, increase basal",
            glucose: 150.0,
            iob: 1.5,
            cob: 20.0,
            eventualBG: 180.0,
            rate: 1.5,
            duration: 30
        )
        
        #expect(decision.decisionType == .tempBasal)
        #expect(decision.algorithmName == "oref1")
        #expect(decision.status == .pending)
        #expect(decision.rate == 1.5)
        #expect(decision.duration == 30)
        #expect(decision.glucose == 150.0)
        #expect(decision.syncIdentifier.contains("temp_basal"))
    }
    
    @Test("Sync identifier uniqueness")
    func decisionSyncIdentifierUniqueness() {
        let decision1 = DecisionAuditEntry(
            decisionType: .tempBasal,
            algorithmName: "oref1",
            reason: "Test"
        )
        
        let decision2 = DecisionAuditEntry(
            decisionType: .tempBasal,
            algorithmName: "oref1",
            reason: "Test"
        )
        
        // UUIDs are always unique, and sync identifiers include UUID prefix
        #expect(decision1.id != decision2.id)
        #expect(decision1.syncIdentifier != decision2.syncIdentifier)
        #expect(decision1.syncIdentifier.contains("temp_basal"))
        #expect(decision2.syncIdentifier.contains("temp_basal"))
    }
    
    @Test("To device status")
    func decisionToDeviceStatus() {
        let decision = DecisionAuditEntry(
            decisionType: .tempBasal,
            algorithmName: "oref1",
            reason: "BG rising",
            glucose: 150.0,
            iob: 1.5,
            rate: 2.0,
            duration: 30,
            device: "T1Pal"
        )
        
        let status = decision.toDeviceStatus()
        
        #expect(status["device"] as? String == "T1Pal")
        #expect(status["created_at"] != nil)
        #expect(status["identifier"] != nil)
        
        let openaps = status["openaps"] as? [String: Any]
        #expect(openaps != nil)
        
        let enacted = openaps?["enacted"] as? [String: Any]
        #expect(enacted?["rate"] as? Double == 2.0)
        #expect(enacted?["duration"] as? Int == 30)
        #expect(enacted?["reason"] as? String == "BG rising")
        
        let context = openaps?["context"] as? [String: Any]
        #expect(context?["glucose"] as? Double == 150.0)
        #expect(context?["iob"] as? Double == 1.5)
    }
}

// MARK: - ReconciliationManager Tests

@Suite("ReconciliationManager Basic")
struct ReconciliationManagerBasicTests {
    @Test("Submit decision")
    func submitDecision() async {
        let manager = ReconciliationManager()
        
        let decision = DecisionBuilder.tempBasal(
            rate: 1.5,
            duration: 30,
            reason: "Test"
        )
        
        let submitted = await manager.submit(decision)
        
        #expect(submitted.status == .pending)
        
        let pending = await manager.getPending()
        #expect(pending.count == 1)
        #expect(pending.first?.id == decision.id)
    }
    
    @Test("Confirm decision")
    func confirmDecision() async {
        let manager = ReconciliationManager()
        
        let decision = DecisionBuilder.tempBasal(
            rate: 1.5,
            duration: 30,
            reason: "Test"
        )
        
        _ = await manager.submit(decision)
        let confirmed = await manager.confirm(id: decision.id, nightscoutId: "ns123")
        
        #expect(confirmed != nil)
        #expect(confirmed?.status == .confirmed)
        #expect(confirmed?.nightscoutId == "ns123")
        #expect(confirmed?.confirmedAt != nil)
        
        let pending = await manager.getPending()
        #expect(pending.count == 0)
        
        let history = await manager.getHistory()
        #expect(history.count == 1)
    }
    
    @Test("Confirm by sync ID")
    func confirmBySyncId() async {
        let manager = ReconciliationManager()
        
        let decision = DecisionBuilder.smb(
            units: 0.5,
            reason: "BG high"
        )
        
        _ = await manager.submit(decision)
        let confirmed = await manager.confirmBySyncId(decision.syncIdentifier)
        
        #expect(confirmed != nil)
        #expect(confirmed?.status == .confirmed)
    }
    
    @Test("Mark executed")
    func markExecuted() async {
        let manager = ReconciliationManager()
        
        let decision = DecisionBuilder.tempBasal(
            rate: 1.5,
            duration: 30,
            reason: "Test"
        )
        
        _ = await manager.submit(decision)
        _ = await manager.confirm(id: decision.id)
        let executed = await manager.markExecuted(id: decision.id)
        
        #expect(executed != nil)
        #expect(executed?.status == .executed)
        #expect(executed?.executedAt != nil)
    }
    
    @Test("Reject decision")
    func rejectDecision() async {
        let manager = ReconciliationManager()
        
        let decision = DecisionBuilder.tempBasal(
            rate: 5.0,
            duration: 30,
            reason: "Test"
        )
        
        _ = await manager.submit(decision)
        let rejected = await manager.reject(id: decision.id, reason: "Rate too high")
        
        #expect(rejected != nil)
        #expect(rejected?.status == .rejected)
        
        let pending = await manager.getPending()
        #expect(pending.count == 0)
    }
    
    @Test("Get decision")
    func getDecision() async {
        let manager = ReconciliationManager()
        
        let decision = DecisionBuilder.resume(glucose: 100)
        
        _ = await manager.submit(decision)
        
        let found = await manager.getDecision(id: decision.id)
        #expect(found != nil)
        #expect(found?.id == decision.id)
        
        let notFound = await manager.getDecision(id: UUID())
        #expect(notFound == nil)
    }
    
    @Test("Clear")
    func clear() async {
        let manager = ReconciliationManager()
        
        let decision = DecisionBuilder.tempBasal(
            rate: 1.0,
            duration: 30,
            reason: "Test"
        )
        
        _ = await manager.submit(decision)
        _ = await manager.confirm(id: decision.id)
        
        await manager.clear()
        
        let pending = await manager.getPending()
        let history = await manager.getHistory()
        
        #expect(pending.count == 0)
        #expect(history.count == 0)
    }
}

@Suite("ReconciliationManager Expiry")
struct ReconciliationManagerExpiryTests {
    @Test("Expire old decisions")
    func expireOldDecisions() async {
        // Use very short expiry for testing
        let manager = ReconciliationManager(expiryInterval: 0.05)
        
        let decision = DecisionBuilder.suspend(reason: "Low BG")
        
        _ = await manager.submit(decision)
        
        // Wait for expiry
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let expiredCount = await manager.expireOldDecisions()
        
        #expect(expiredCount == 1)
        
        let pending = await manager.getPending()
        #expect(pending.count == 0)
        
        let history = await manager.getHistory()
        #expect(history.first?.status == .expired)
    }
    
    @Test("History limit")
    func historyLimit() async {
        let manager = ReconciliationManager(maxConfirmedHistory: 5)
        
        // Submit and confirm 10 decisions
        for i in 0..<10 {
            let decision = DecisionBuilder.tempBasal(
                rate: Double(i),
                duration: 30,
                reason: "Test \(i)"
            )
            _ = await manager.submit(decision)
            _ = await manager.confirm(id: decision.id)
        }
        
        let history = await manager.getHistory(limit: 100)
        #expect(history.count == 5, "Should trim to max history")
    }
}

// MARK: - Upload Callback Tests

@Suite("ReconciliationManager Upload")
struct ReconciliationManagerUploadTests {
    @Test("Submit with upload callback")
    func submitWithUploadCallback() async {
        let uploadCounter = UploadCounter()
        
        let manager = ReconciliationManager { decision in
            await uploadCounter.increment()
            return "ns_\(decision.id)"
        }
        
        let decision = DecisionBuilder.tempBasal(
            rate: 1.5,
            duration: 30,
            reason: "Test"
        )
        
        let submitted = await manager.submit(decision)
        
        let count = await uploadCounter.count
        #expect(count == 1)
        #expect(submitted.status == .uploaded)
        #expect(submitted.nightscoutId != nil)
        #expect(submitted.uploadedAt != nil)
    }
    
    @Test("Submit with failed upload")
    func submitWithFailedUpload() async {
        let manager = ReconciliationManager { _ in
            throw NSError(domain: "test", code: 1)
        }
        
        let decision = DecisionBuilder.tempBasal(
            rate: 1.5,
            duration: 30,
            reason: "Test"
        )
        
        let submitted = await manager.submit(decision)
        
        // Should stay pending when upload fails
        #expect(submitted.status == .pending)
        #expect(submitted.nightscoutId == nil)
    }
}

// MARK: - Decision Builder Tests

@Suite("DecisionBuilder")
struct DecisionBuilderTests {
    @Test("Temp basal builder")
    func tempBasalBuilder() {
        let decision = DecisionBuilder.tempBasal(
            rate: 2.5,
            duration: 45,
            reason: "High BG",
            algorithm: "oref1",
            glucose: 200.0,
            iob: 2.0,
            cob: 30.0,
            eventualBG: 150.0
        )
        
        #expect(decision.decisionType == .tempBasal)
        #expect(decision.rate == 2.5)
        #expect(decision.duration == 45)
        #expect(decision.glucose == 200.0)
        #expect(decision.algorithmName == "oref1")
    }
    
    @Test("SMB builder")
    func smbBuilder() {
        let decision = DecisionBuilder.smb(
            units: 0.3,
            reason: "High and rising",
            glucose: 180.0,
            iob: 1.0
        )
        
        #expect(decision.decisionType == .smb)
        #expect(decision.units == 0.3)
        #expect(decision.rate == nil)
    }
    
    @Test("Suspend builder")
    func suspendBuilder() {
        let decision = DecisionBuilder.suspend(
            reason: "Low BG predicted",
            glucose: 70.0
        )
        
        #expect(decision.decisionType == .suspend)
        #expect(decision.rate == 0)
        #expect(decision.glucose == 70.0)
    }
    
    @Test("Resume builder")
    func resumeBuilder() {
        let decision = DecisionBuilder.resume(glucose: 100.0)
        
        #expect(decision.decisionType == .resume)
        #expect(decision.reason == "BG in range")
    }
}
