// SPDX-License-Identifier: MIT
// PumpNightscoutIntegrationTests.swift
// NightscoutKitTests
//
// Integration tests for Pump→Nightscout flow (INT-002)
// Validates end-to-end delivery event → treatment upload flow

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - Pump→Nightscout Integration Tests (INT-002)

@Suite("Pump Nightscout Integration")
struct PumpNightscoutIntegrationTests {
    
    // MARK: - Bolus Flow Tests
    
    @Test("Bolus delivery creates valid Nightscout treatment")
    func bolusDeliveryCreatesValidTreatment() async {
        // Simulate pump delivering a bolus
        let bolusEvent = DeliveryEvent(
            deliveryType: .bolus,
            units: 2.5,
            reason: "Meal bolus for 30g carbs"
        )
        
        // Convert to Nightscout treatment
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(bolusEvent)
        
        // Verify treatment is valid
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Bolus")
        #expect(treatment?.insulin == 2.5)
        #expect(treatment?.enteredBy == "T1Pal")
        #expect(treatment?.notes == "Meal bolus for 30g carbs")
        
        // Verify serialization works
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try? encoder.encode(treatment)
        #expect(data != nil)
        
        // Verify JSON contains required fields
        let json = String(data: data!, encoding: .utf8)!
        #expect(json.contains("\"eventType\":\"Bolus\""))
        #expect(json.contains("\"insulin\":2.5"))
        #expect(json.contains("\"enteredBy\":\"T1Pal\""))
    }
    
    @Test("Correction bolus creates valid treatment")
    func correctionBolusCreatesValidTreatment() async {
        let event = DeliveryEvent(
            deliveryType: .correctionBolus,
            units: 1.0,
            reason: "Correction for 180 mg/dL"
        )
        
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Correction Bolus")
        #expect(treatment?.insulin == 1.0)
    }
    
    @Test("SMB creates valid treatment with notes")
    func smbCreatesValidTreatment() async {
        let event = DeliveryEvent(
            deliveryType: .smb,
            units: 0.3
        )
        
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "SMB")
        #expect(treatment?.insulin == 0.3)
        #expect(treatment?.notes == "SMB")
    }
    
    // MARK: - Temp Basal Flow Tests
    
    @Test("Temp basal creates valid treatment with duration")
    func tempBasalCreatesValidTreatment() async {
        let event = DeliveryEvent(
            deliveryType: .tempBasal,
            units: 0,
            duration: 1800, // 30 minutes in seconds
            rate: 0.8
        )
        
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Temp Basal")
        #expect(treatment?.rate == 0.8)
        #expect(treatment?.absolute == 0.8)
        #expect(treatment?.duration == 30) // Converted to minutes
    }
    
    @Test("Zero temp basal (suspend) creates valid treatment")
    func zeroTempBasalCreatesValidTreatment() async {
        let event = DeliveryEvent(
            deliveryType: .tempBasal,
            units: 0,
            duration: 3600, // 60 minutes
            rate: 0.0
        )
        
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.rate == 0.0)
        #expect(treatment?.duration == 60)
    }
    
    // MARK: - Suspend/Resume Flow Tests
    
    @Test("Suspend creates valid treatment")
    func suspendCreatesValidTreatment() async {
        let event = DeliveryEvent(
            deliveryType: .suspend,
            units: 0,
            duration: 7200 // 2 hours
        )
        
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Suspend Pump")
        #expect(treatment?.rate == 0)
        #expect(treatment?.duration == 120) // 2 hours in minutes
        #expect(treatment?.notes == "Pump suspended")
    }
    
    @Test("Resume creates valid treatment")
    func resumeCreatesValidTreatment() async {
        let event = DeliveryEvent(
            deliveryType: .resume,
            units: 0
        )
        
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Resume Pump")
        #expect(treatment?.notes == "Pump resumed")
    }
    
    // MARK: - Batch Upload Flow Tests
    
    @Test("Multiple deliveries batch to treatments")
    func multipleDeliveriesBatchToTreatments() async {
        let reporter = DeliveryReporter()
        
        // Simulate a typical closed-loop sequence
        let events: [DeliveryEvent] = [
            DeliveryEvent(deliveryType: .tempBasal, units: 0, duration: 1800, rate: 1.2),
            DeliveryEvent(deliveryType: .smb, units: 0.2),
            DeliveryEvent(deliveryType: .smb, units: 0.3),
            DeliveryEvent(deliveryType: .tempBasal, units: 0, duration: 1800, rate: 0.4),
            DeliveryEvent(deliveryType: .bolus, units: 3.0, reason: "Meal")
        ]
        
        // Queue events
        await reporter.queue(events)
        
        // Process batch
        let treatments = await reporter.processPendingBatch()
        
        #expect(treatments.count == 5)
        
        // Verify all can be serialized
        let encoder = JSONEncoder()
        for treatment in treatments {
            let data = try? encoder.encode(treatment)
            #expect(data != nil, "Failed to encode treatment: \(treatment.eventType)")
        }
        
        // Check statistics
        let stats = await reporter.getStatistics()
        #expect(stats.totalReported == 5)
        #expect(stats.pendingCount == 0)
    }
    
    @Test("Delivery reporter respects batch size limit")
    func batchSizeLimit() async {
        let config = DeliveryReporterConfig(maxBatchSize: 3)
        let reporter = DeliveryReporter(config: config)
        
        // Queue 5 events
        for i in 1...5 {
            await reporter.queue(DeliveryEvent(deliveryType: .smb, units: Double(i) * 0.1))
        }
        
        // First batch should be 3
        let batch1 = await reporter.processPendingBatch()
        #expect(batch1.count == 3)
        
        // Second batch should be 2
        let batch2 = await reporter.processPendingBatch()
        #expect(batch2.count == 2)
        
        // No more remaining
        let remaining = await reporter.pendingCount()
        #expect(remaining == 0)
    }
    
    // MARK: - Filter/Skip Tests
    
    @Test("Tiny boluses are filtered out")
    func tinyBolusesFiltered() async {
        let reporter = DeliveryReporter()
        
        await reporter.queue([
            DeliveryEvent(deliveryType: .bolus, units: 0.001), // Too small
            DeliveryEvent(deliveryType: .smb, units: 0.005),   // Too small
            DeliveryEvent(deliveryType: .bolus, units: 0.05)   // Should pass
        ])
        
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 1)
        
        let stats = await reporter.getStatistics()
        #expect(stats.totalSkipped == 2)
    }
    
    @Test("Scheduled basal skipped by default")
    func scheduledBasalSkippedByDefault() async {
        let reporter = DeliveryReporter()
        
        await reporter.queue([
            DeliveryEvent(deliveryType: .scheduledBasal, units: 0, rate: 1.0),
            DeliveryEvent(deliveryType: .tempBasal, units: 0, duration: 1800, rate: 0.8)
        ])
        
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 1)
        #expect(treatments[0].eventType == "Temp Basal")
    }
    
    @Test("Scheduled basal reported when configured")
    func scheduledBasalReportedWhenConfigured() async {
        let config = DeliveryReporterConfig(reportScheduledBasal: true)
        let reporter = DeliveryReporter(config: config)
        
        await reporter.queue(DeliveryEvent(deliveryType: .scheduledBasal, units: 0, rate: 1.0))
        
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 1)
        #expect(treatments[0].eventType == "Basal")
    }
    
    // MARK: - Treatment Format Validation Tests
    
    @Test("Treatment created_at is ISO8601 format")
    func treatmentCreatedAtIsISO8601() async {
        let event = DeliveryEvent(deliveryType: .bolus, units: 1.0)
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)!
        
        // Verify ISO8601 format (e.g., "2026-02-05T18:30:00.000Z")
        #expect(treatment.created_at.contains("T"))
        #expect(treatment.created_at.contains("Z") || treatment.created_at.contains("+"))
        
        // Verify it can be parsed back
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: treatment.created_at)
        #expect(parsed != nil)
    }
    
    @Test("Treatment JSON matches Nightscout API format")
    func treatmentJSONMatchesNightscoutFormat() async throws {
        let event = DeliveryEvent(
            deliveryType: .bolus,
            units: 2.0,
            reason: "Test bolus"
        )
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)!
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(treatment)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // Required fields for Nightscout treatments API
        #expect(json["eventType"] as? String == "Bolus")
        #expect(json["insulin"] as? Double == 2.0)
        #expect(json["enteredBy"] as? String == "T1Pal")
        #expect(json["created_at"] as? String != nil)
        
        // Optional fields should be present when set
        #expect(json["notes"] as? String == "Test bolus")
    }
    
    @Test("Temp basal treatment has required fields")
    func tempBasalTreatmentHasRequiredFields() async throws {
        let event = DeliveryEvent(
            deliveryType: .tempBasal,
            units: 0,
            duration: 1800,
            rate: 1.5
        )
        let logic = DeliveryReporterLogic()
        let treatment = logic.toTreatment(event)!
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(treatment)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        // Required fields for temp basal
        #expect(json["eventType"] as? String == "Temp Basal")
        #expect(json["rate"] as? Double == 1.5)
        #expect(json["absolute"] as? Double == 1.5)
        #expect(json["duration"] as? Double == 30) // Minutes
    }
    
    // MARK: - End-to-End Simulation Tests
    
    @Test("Full closed-loop cycle creates valid treatments")
    func fullClosedLoopCycleCreatesValidTreatments() async {
        let reporter = DeliveryReporter()
        let now = Date()
        
        // Simulate a 30-minute closed-loop session
        let events: [DeliveryEvent] = [
            // Algorithm sets high temp basal
            DeliveryEvent(
                timestamp: now.addingTimeInterval(-1800),
                source: .app,
                deliveryType: .tempBasal,
                units: 0,
                duration: 1800,
                rate: 2.0,
                reason: "High glucose"
            ),
            // Algorithm delivers SMB
            DeliveryEvent(
                timestamp: now.addingTimeInterval(-1500),
                source: .app,
                deliveryType: .smb,
                units: 0.4,
                reason: "Predicted high"
            ),
            // User delivers meal bolus
            DeliveryEvent(
                timestamp: now.addingTimeInterval(-1200),
                source: .user,
                deliveryType: .bolus,
                units: 4.5,
                reason: "Lunch 45g"
            ),
            // Algorithm reduces basal
            DeliveryEvent(
                timestamp: now.addingTimeInterval(-600),
                source: .app,
                deliveryType: .tempBasal,
                units: 0,
                duration: 1800,
                rate: 0.3,
                reason: "IOB high"
            ),
            // Algorithm delivers another SMB
            DeliveryEvent(
                timestamp: now.addingTimeInterval(-300),
                source: .app,
                deliveryType: .smb,
                units: 0.2,
                reason: "Predicted high"
            )
        ]
        
        await reporter.queue(events)
        let treatments = await reporter.processPendingBatch()
        
        #expect(treatments.count == 5)
        
        // Verify all treatments can be serialized as a batch
        let encoder = JSONEncoder()
        let batchData = try? encoder.encode(treatments)
        #expect(batchData != nil)
        
        // Verify batch is a valid JSON array
        let batchJson = try? JSONSerialization.jsonObject(with: batchData!) as? [[String: Any]]
        #expect(batchJson != nil)
        #expect(batchJson?.count == 5)
    }
    
    @Test("Reporter handles concurrent queue operations")
    func concurrentQueueOperations() async {
        let reporter = DeliveryReporter()
        
        // Simulate concurrent delivery events (e.g., from algorithm + user)
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    await reporter.queue(DeliveryEvent(
                        deliveryType: .smb,
                        units: Double(i) * 0.1
                    ))
                }
            }
        }
        
        let count = await reporter.pendingCount()
        #expect(count == 10)
        
        // Process all
        let treatments = await reporter.processPendingBatch()
        #expect(treatments.count == 10)
    }
}
