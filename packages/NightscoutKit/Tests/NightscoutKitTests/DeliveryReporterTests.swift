// SPDX-License-Identifier: MIT
// DeliveryReporterTests.swift
// NightscoutKitTests
//
// Tests for delivery reporter (CONTROL-003)

import Testing
import Foundation
@testable import NightscoutKit

// MARK: - Delivery Reporter Config Tests

@Suite("Delivery Reporter Config")
struct DeliveryReporterConfigTests {
    @Test("Default configuration values")
    func defaultConfigurationValues() {
        let config = DeliveryReporterConfig.default
        
        #expect(config.appIdentifier == "T1Pal")
        #expect(config.includeNotes == true)
        #expect(config.minimumBolusSize == 0.01)
        #expect(config.reportScheduledBasal == false)
        #expect(config.batchUploads == true)
        #expect(config.maxBatchSize == 50)
    }
    
    @Test("Custom configuration")
    func customConfiguration() {
        let config = DeliveryReporterConfig(
            appIdentifier: "TestApp",
            includeNotes: false,
            minimumBolusSize: 0.05,
            reportScheduledBasal: true,
            maxBatchSize: 100
        )
        
        #expect(config.appIdentifier == "TestApp")
        #expect(config.includeNotes == false)
        #expect(config.minimumBolusSize == 0.05)
        #expect(config.reportScheduledBasal == true)
        #expect(config.maxBatchSize == 100)
    }
}

// MARK: - Delivery Report Result Tests

@Suite("Delivery Report Result")
struct DeliveryReportResultTests {
    @Test("Empty result is success")
    func emptyResultIsSuccess() {
        let result = DeliveryReportResult()
        
        #expect(result.isSuccess == true)
        #expect(result.eventsProcessed == 0)
        #expect(result.treatmentsUploaded == 0)
    }
    
    @Test("Result with errors is not success")
    func resultWithErrorsIsNotSuccess() {
        let result = DeliveryReportResult(
            eventsProcessed: 5,
            treatmentsUploaded: 3,
            errors: ["Upload failed"]
        )
        
        #expect(result.isSuccess == false)
    }
    
    @Test("Merge results")
    func mergeResults() {
        let result1 = DeliveryReportResult(
            eventsProcessed: 5,
            treatmentsUploaded: 4,
            eventsSkipped: 1
        )
        let result2 = DeliveryReportResult(
            eventsProcessed: 3,
            treatmentsUploaded: 3,
            eventsSkipped: 0
        )
        
        let merged = result1.merged(with: result2)
        
        #expect(merged.eventsProcessed == 8)
        #expect(merged.treatmentsUploaded == 7)
        #expect(merged.eventsSkipped == 1)
    }
}

// MARK: - Pending Delivery Event Tests

@Suite("Pending Delivery Event")
struct PendingDeliveryEventTests {
    @Test("Create pending event")
    func createPendingEvent() {
        let event = DeliveryEvent(
            deliveryType: .bolus,
            units: 2.0
        )
        let pending = PendingDeliveryEvent(event: event)
        
        #expect(pending.retryCount == 0)
        #expect(pending.age >= 0)
        #expect(pending.age < 1)
    }
    
    @Test("Age increases over time")
    func ageIncreasesOverTime() {
        let pastDate = Date().addingTimeInterval(-60)
        let event = DeliveryEvent(
            deliveryType: .bolus,
            units: 1.0
        )
        let pending = PendingDeliveryEvent(event: event, queuedAt: pastDate)
        
        #expect(pending.age >= 60)
        #expect(pending.age < 70)
    }
}

// MARK: - Delivery Reporter Logic Tests

@Suite("Delivery Reporter Logic")
struct DeliveryReporterLogicTests {
    let logic = DeliveryReporterLogic()
    
    @Test("Convert bolus to treatment")
    func convertBolusToTreatment() {
        let event = DeliveryEvent(
            deliveryType: .bolus,
            units: 2.5,
            reason: "Meal bolus"
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Bolus")
        #expect(treatment?.insulin == 2.5)
        #expect(treatment?.enteredBy == "T1Pal")
        #expect(treatment?.notes == "Meal bolus")
    }
    
    @Test("Convert correction bolus to treatment")
    func convertCorrectionBolusToTreatment() {
        let event = DeliveryEvent(
            deliveryType: .correctionBolus,
            units: 1.0
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Correction Bolus")
        #expect(treatment?.insulin == 1.0)
    }
    
    @Test("Convert SMB to treatment")
    func convertSMBToTreatment() {
        let event = DeliveryEvent(
            deliveryType: .smb,
            units: 0.3
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "SMB")
        #expect(treatment?.insulin == 0.3)
        #expect(treatment?.notes == "SMB")
    }
    
    @Test("Convert temp basal to treatment")
    func convertTempBasalToTreatment() {
        let event = DeliveryEvent(
            deliveryType: .tempBasal,
            units: 0,
            duration: 1800, // 30 minutes in seconds
            rate: 0.8
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Temp Basal")
        #expect(treatment?.rate == 0.8)
        #expect(treatment?.duration == 30) // Converted to minutes
    }
    
    @Test("Convert suspend to treatment")
    func convertSuspendToTreatment() {
        let event = DeliveryEvent(
            deliveryType: .suspend,
            units: 0,
            duration: 3600
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Suspend Pump")
        #expect(treatment?.rate == 0)
        #expect(treatment?.duration == 60)
    }
    
    @Test("Convert resume to treatment")
    func convertResumeToTreatment() {
        let event = DeliveryEvent(
            deliveryType: .resume,
            units: 0
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Resume Pump")
    }
    
    @Test("Skip tiny bolus below threshold")
    func skipTinyBolusBelowThreshold() {
        let event = DeliveryEvent(
            deliveryType: .bolus,
            units: 0.005
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment == nil)
    }
    
    @Test("Skip scheduled basal by default")
    func skipScheduledBasalByDefault() {
        let event = DeliveryEvent(
            deliveryType: .scheduledBasal,
            units: 0,
            rate: 1.0
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment == nil)
    }
    
    @Test("Report scheduled basal when configured")
    func reportScheduledBasalWhenConfigured() {
        let config = DeliveryReporterConfig(reportScheduledBasal: true)
        let logic = DeliveryReporterLogic(config: config)
        
        let event = DeliveryEvent(
            deliveryType: .scheduledBasal,
            units: 0,
            rate: 1.0
        )
        
        let treatment = logic.toTreatment(event)
        
        #expect(treatment != nil)
        #expect(treatment?.eventType == "Basal")
    }
    
    @Test("Convert batch of events")
    func convertBatchOfEvents() {
        let events = [
            DeliveryEvent(deliveryType: .bolus, units: 2.0),
            DeliveryEvent(deliveryType: .tempBasal, units: 0, rate: 0.5),
            DeliveryEvent(deliveryType: .bolus, units: 0.001), // Too small
            DeliveryEvent(deliveryType: .smb, units: 0.2)
        ]
        
        let treatments = logic.toTreatments(events)
        
        #expect(treatments.count == 3)
    }
    
    @Test("Should report checks threshold")
    func shouldReportChecksThreshold() {
        #expect(logic.shouldReport(DeliveryEvent(deliveryType: .bolus, units: 1.0)) == true)
        #expect(logic.shouldReport(DeliveryEvent(deliveryType: .bolus, units: 0.005)) == false)
        #expect(logic.shouldReport(DeliveryEvent(deliveryType: .scheduledBasal, units: 0, rate: 1.0)) == false)
        #expect(logic.shouldReport(DeliveryEvent(deliveryType: .tempBasal, units: 0, rate: 0.5)) == true)
    }
    
    @Test("Nightscout event type mapping")
    func nightscoutEventTypeMapping() {
        #expect(logic.nightscoutEventType(for: .bolus) == "Bolus")
        #expect(logic.nightscoutEventType(for: .correctionBolus) == "Correction Bolus")
        #expect(logic.nightscoutEventType(for: .smb) == "SMB")
        #expect(logic.nightscoutEventType(for: .tempBasal) == "Temp Basal")
        #expect(logic.nightscoutEventType(for: .scheduledBasal) == "Basal")
        #expect(logic.nightscoutEventType(for: .suspend) == "Suspend Pump")
        #expect(logic.nightscoutEventType(for: .resume) == "Resume Pump")
    }
}

// MARK: - Delivery Reporter Actor Tests

@Suite("Delivery Reporter")
struct DeliveryReporterTests {
    @Test("Queue event")
    func queueEvent() async {
        let reporter = DeliveryReporter()
        let event = DeliveryEvent(deliveryType: .bolus, units: 2.0)
        
        await reporter.queue(event)
        
        let count = await reporter.pendingCount()
        #expect(count == 1)
    }
    
    @Test("Queue multiple events")
    func queueMultipleEvents() async {
        let reporter = DeliveryReporter()
        let events = [
            DeliveryEvent(deliveryType: .bolus, units: 1.0),
            DeliveryEvent(deliveryType: .bolus, units: 2.0),
            DeliveryEvent(deliveryType: .tempBasal, units: 0, rate: 0.5)
        ]
        
        await reporter.queue(events)
        
        let count = await reporter.pendingCount()
        #expect(count == 3)
    }
    
    @Test("Skip events below threshold")
    func skipEventsBelowThreshold() async {
        let reporter = DeliveryReporter()
        let event = DeliveryEvent(deliveryType: .bolus, units: 0.001)
        
        await reporter.queue(event)
        
        let count = await reporter.pendingCount()
        #expect(count == 0)
        
        let stats = await reporter.getStatistics()
        #expect(stats.totalSkipped == 1)
    }
    
    @Test("Process pending batch")
    func processPendingBatch() async {
        let reporter = DeliveryReporter()
        await reporter.queue([
            DeliveryEvent(deliveryType: .bolus, units: 1.0),
            DeliveryEvent(deliveryType: .bolus, units: 2.0)
        ])
        
        let treatments = await reporter.processPendingBatch()
        
        #expect(treatments.count == 2)
        
        let count = await reporter.pendingCount()
        #expect(count == 0)
    }
    
    @Test("Batch respects max size")
    func batchRespectsMaxSize() async {
        let config = DeliveryReporterConfig(maxBatchSize: 2)
        let reporter = DeliveryReporter(config: config)
        
        await reporter.queue([
            DeliveryEvent(deliveryType: .bolus, units: 1.0),
            DeliveryEvent(deliveryType: .bolus, units: 2.0),
            DeliveryEvent(deliveryType: .bolus, units: 3.0)
        ])
        
        let treatments = await reporter.processPendingBatch()
        
        #expect(treatments.count == 2)
        
        let remaining = await reporter.pendingCount()
        #expect(remaining == 1)
    }
    
    @Test("Get pending events")
    func getPendingEvents() async {
        let reporter = DeliveryReporter()
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        
        let pending = await reporter.getPendingEvents()
        
        #expect(pending.count == 1)
        #expect(pending[0].event.units == 1.0)
    }
    
    @Test("Clear pending")
    func clearPending() async {
        let reporter = DeliveryReporter()
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        await reporter.clearPending()
        
        let count = await reporter.pendingCount()
        #expect(count == 0)
    }
    
    @Test("Statistics tracking")
    func statisticsTracking() async {
        let reporter = DeliveryReporter()
        await reporter.queue([
            DeliveryEvent(deliveryType: .bolus, units: 1.0),
            DeliveryEvent(deliveryType: .bolus, units: 0.001) // Skipped
        ])
        
        _ = await reporter.processPendingBatch()
        await reporter.recordError()
        
        let stats = await reporter.getStatistics()
        
        #expect(stats.totalReported == 1)
        #expect(stats.totalSkipped == 1)
        #expect(stats.totalErrors == 1)
        #expect(stats.lastUploadTime != nil)
    }
    
    @Test("Reset statistics")
    func resetStatistics() async {
        let reporter = DeliveryReporter()
        await reporter.queue(DeliveryEvent(deliveryType: .bolus, units: 1.0))
        _ = await reporter.processPendingBatch()
        
        await reporter.resetStatistics()
        
        let stats = await reporter.getStatistics()
        #expect(stats.totalReported == 0)
        #expect(stats.lastUploadTime == nil)
    }
}

// MARK: - Statistics Tests

@Suite("Delivery Reporter Statistics")
struct DeliveryReporterStatisticsTests {
    @Test("Default statistics")
    func defaultStatistics() {
        let stats = DeliveryReporterStatistics()
        
        #expect(stats.pendingCount == 0)
        #expect(stats.totalReported == 0)
        #expect(stats.totalSkipped == 0)
        #expect(stats.totalErrors == 0)
        #expect(stats.lastUploadTime == nil)
        #expect(stats.timeSinceLastUpload == nil)
    }
    
    @Test("Time since last upload")
    func timeSinceLastUpload() {
        let past = Date().addingTimeInterval(-300)
        let stats = DeliveryReporterStatistics(lastUploadTime: past)
        
        #expect(stats.timeSinceLastUpload != nil)
        #expect(stats.timeSinceLastUpload! >= 300)
        #expect(stats.timeSinceLastUpload! < 310)
    }
}
