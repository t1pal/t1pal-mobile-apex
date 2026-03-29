// TreatmentUploadTests.swift
// Tests for TreatmentDeduplicator and SyncUploader treatment upload
// Trace: NS-UPLOAD-002, PRD-014 REQ-COMPAT-005

import Foundation
import Testing
@testable import NightscoutKit

// MARK: - Test Helpers

private func iso(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func makeBolus(insulin: Double, createdAt: String? = nil, identifier: String? = nil) -> NightscoutTreatment {
    NightscoutTreatment(
        eventType: "Bolus",
        created_at: createdAt ?? iso(Date()),
        insulin: insulin,
        identifier: identifier
    )
}

private func makeCarbs(carbs: Double, createdAt: String? = nil, identifier: String? = nil) -> NightscoutTreatment {
    NightscoutTreatment(
        eventType: "Carb Correction",
        created_at: createdAt ?? iso(Date()),
        carbs: carbs,
        identifier: identifier
    )
}

private func makeMeal(carbs: Double, createdAt: String? = nil, identifier: String? = nil) -> NightscoutTreatment {
    NightscoutTreatment(
        eventType: "Meal",
        created_at: createdAt ?? iso(Date()),
        carbs: carbs,
        identifier: identifier
    )
}

private func makeTempBasal(rate: Double, duration: Double = 30, createdAt: String? = nil, identifier: String? = nil) -> NightscoutTreatment {
    NightscoutTreatment(
        eventType: "Temp Basal",
        created_at: createdAt ?? iso(Date()),
        duration: duration,
        rate: rate,
        identifier: identifier
    )
}

// MARK: - TreatmentDeduplicator Basic

@Suite("TreatmentDeduplicator Basic")
struct TreatmentDeduplicatorBasicTests {
    @Test("Should upload new treatment")
    func shouldUploadNewTreatment() {
        let deduplicator = TreatmentDeduplicator()
        let treatment = makeBolus(insulin: 2.5)
        #expect(deduplicator.shouldUpload(treatment))
    }
    
    @Test("Should not upload after processed")
    func shouldNotUploadAfterProcessed() {
        let deduplicator = TreatmentDeduplicator()
        let treatment = makeBolus(insulin: 2.5)
        
        #expect(deduplicator.shouldUpload(treatment))
        deduplicator.markProcessed(treatment)
        #expect(!deduplicator.shouldUpload(treatment))
    }
    
    @Test("Should not upload duplicate sync ID")
    func shouldNotUploadDuplicateSyncId() {
        let deduplicator = TreatmentDeduplicator()
        let treatment1 = makeBolus(insulin: 2.5, identifier: "t1pal-abc:bolus:12345")
        let treatment2 = makeBolus(insulin: 3.0, identifier: "t1pal-abc:bolus:12345")
        
        deduplicator.markProcessed(treatment1)
        #expect(!deduplicator.shouldUpload(treatment2), "Same sync ID should be duplicate")
    }
}

// MARK: - Similar Treatment Detection

@Suite("TreatmentDeduplicator Similar")
struct TreatmentDeduplicatorSimilarTests {
    @Test("Should detect similar bolus")
    func shouldDetectSimilarBolus() {
        let deduplicator = TreatmentDeduplicator()
        let now = ISO8601DateFormatter().string(from: Date())
        let treatment1 = makeBolus(insulin: 2.5, createdAt: now, identifier: "id1")
        let treatment2 = makeBolus(insulin: 2.55, createdAt: now, identifier: "id2") // +0.05 units
        
        deduplicator.markProcessed(treatment1)
        #expect(!deduplicator.shouldUpload(treatment2), "Similar bolus should be duplicate")
    }
    
    @Test("Should allow different bolus value")
    func shouldAllowDifferentBolusValue() {
        let deduplicator = TreatmentDeduplicator()
        let now = ISO8601DateFormatter().string(from: Date())
        let treatment1 = makeBolus(insulin: 2.5, createdAt: now, identifier: "id1")
        let treatment2 = makeBolus(insulin: 5.0, createdAt: now, identifier: "id2") // Different value
        
        deduplicator.markProcessed(treatment1)
        #expect(deduplicator.shouldUpload(treatment2), "Different bolus value should not be duplicate")
    }
    
    @Test("Should detect similar carbs")
    func shouldDetectSimilarCarbs() {
        let deduplicator = TreatmentDeduplicator()
        let now = ISO8601DateFormatter().string(from: Date())
        let treatment1 = makeCarbs(carbs: 30, createdAt: now, identifier: "id1")
        let treatment2 = makeCarbs(carbs: 30.5, createdAt: now, identifier: "id2") // +0.5g
        
        deduplicator.markProcessed(treatment1)
        #expect(!deduplicator.shouldUpload(treatment2), "Similar carbs should be duplicate")
    }
    
    @Test("Should allow different carbs value")
    func shouldAllowDifferentCarbsValue() {
        let deduplicator = TreatmentDeduplicator()
        let now = ISO8601DateFormatter().string(from: Date())
        let treatment1 = makeCarbs(carbs: 30, createdAt: now, identifier: "id1")
        let treatment2 = makeCarbs(carbs: 50, createdAt: now, identifier: "id2") // Different value
        
        deduplicator.markProcessed(treatment1)
        #expect(deduplicator.shouldUpload(treatment2), "Different carbs value should not be duplicate")
    }
}

// MARK: - Time Window

@Suite("TreatmentDeduplicator Time Window")
struct TreatmentDeduplicatorTimeWindowTests {
    @Test("Should allow treatment outside time window")
    func shouldAllowTreatmentOutsideTimeWindow() {
        let deduplicator = TreatmentDeduplicator()
        let now = Date()
        let withinWindow = now.addingTimeInterval(-3) // 3 seconds ago (within 5s tolerance)
        
        let treatment1 = makeBolus(insulin: 2.5, createdAt: iso(now), identifier: "id1")
        let treatment2 = makeBolus(insulin: 2.5, createdAt: iso(withinWindow), identifier: "id2")
        
        deduplicator.markProcessed(treatment1)
        #expect(!deduplicator.shouldUpload(treatment2), "Within 5s tolerance should be duplicate")
        
        // Outside tolerance window (10 seconds apart)
        let outsideWindow = now.addingTimeInterval(-10)
        let treatment3 = makeBolus(insulin: 2.5, createdAt: iso(outsideWindow), identifier: "id3")
        
        #expect(deduplicator.shouldUpload(treatment3), "Outside time window should not be duplicate")
    }
}

// MARK: - Batch Processing

@Suite("TreatmentDeduplicator Batch")
struct TreatmentDeduplicatorBatchTests {
    @Test("Process batch for upload")
    func processBatchForUpload() {
        let deduplicator = TreatmentDeduplicator()
        let treatments = [
            makeBolus(insulin: 2.5, identifier: "id1"),
            makeCarbs(carbs: 30, identifier: "id2"),
            makeBolus(insulin: 3.0, identifier: "id1"), // Duplicate sync ID
        ]
        
        let result = deduplicator.processBatchForUpload(treatments)
        #expect(result.uploadCount == 2)
        #expect(result.duplicateCount == 1)
    }
    
    @Test("Deduplicate batch")
    func deduplicateBatch() {
        let deduplicator = TreatmentDeduplicator()
        let treatments = [
            makeBolus(insulin: 2.5, identifier: "id1"),
            makeCarbs(carbs: 30, identifier: "id2"),
            makeTempBasal(rate: 1.5, identifier: "id3"),
            makeBolus(insulin: 2.5, identifier: "id1"), // Duplicate
        ]
        
        let deduplicated = deduplicator.deduplicate(treatments)
        #expect(deduplicated.count == 3)
    }
}

// MARK: - Missing Remote/Local

@Suite("TreatmentDeduplicator Missing")
struct TreatmentDeduplicatorMissingTests {
    @Test("Find missing remote")
    func findMissingRemote() {
        let deduplicator = TreatmentDeduplicator()
        let local = [
            makeBolus(insulin: 2.5, identifier: "id1"),
            makeCarbs(carbs: 30, identifier: "id2"),
            makeTempBasal(rate: 1.5, identifier: "id3"),
        ]
        let remote = [
            makeBolus(insulin: 2.5, identifier: "id1"),
        ]
        
        let missing = deduplicator.findMissingRemote(local: local, remote: remote)
        #expect(missing.count == 2)
    }
    
    @Test("Find missing local")
    func findMissingLocal() {
        let deduplicator = TreatmentDeduplicator()
        let local = [
            makeBolus(insulin: 2.5, identifier: "id1"),
        ]
        let remote = [
            makeBolus(insulin: 2.5, identifier: "id1"),
            makeCarbs(carbs: 30, identifier: "id2"),
        ]
        
        let missing = deduplicator.findMissingLocal(local: local, remote: remote)
        #expect(missing.count == 1)
        #expect(missing.first?.syncIdentifier == "id2")
    }
}

// MARK: - Treatment Type Helpers

@Suite("TreatmentDeduplicator Type Detection")
struct TreatmentDeduplicatorTypeTests {
    @Test("Is bolus detection")
    func isBolusDetection() {
        let deduplicator = TreatmentDeduplicator()
        let bolus = makeBolus(insulin: 2.5)
        let carbs = makeCarbs(carbs: 30)
        let tempBasal = makeTempBasal(rate: 1.5)
        
        #expect(deduplicator.isBolus(bolus))
        #expect(!deduplicator.isBolus(carbs))
        #expect(!deduplicator.isBolus(tempBasal))
    }
    
    @Test("Is carb entry detection")
    func isCarbEntryDetection() {
        let deduplicator = TreatmentDeduplicator()
        let bolus = makeBolus(insulin: 2.5)
        let carbs = makeCarbs(carbs: 30)
        let meal = makeMeal(carbs: 50)
        
        #expect(!deduplicator.isCarbEntry(bolus))
        #expect(deduplicator.isCarbEntry(carbs))
        #expect(deduplicator.isCarbEntry(meal))
    }
    
    @Test("Is temp basal detection")
    func isTempBasalDetection() {
        let deduplicator = TreatmentDeduplicator()
        let bolus = makeBolus(insulin: 2.5)
        let tempBasal = makeTempBasal(rate: 1.5)
        
        #expect(!deduplicator.isTempBasal(bolus))
        #expect(deduplicator.isTempBasal(tempBasal))
    }
}

// MARK: - Stats

@Suite("TreatmentDeduplicator Stats")
struct TreatmentDeduplicatorStatsTests {
    @Test("Stats tracking")
    func statsTracking() {
        let deduplicator = TreatmentDeduplicator()
        let treatments = [
            makeBolus(insulin: 2.5, identifier: "id1"),
            makeCarbs(carbs: 30, identifier: "id2"),
        ]
        
        for treatment in treatments {
            deduplicator.markProcessed(treatment)
        }
        
        let stats = deduplicator.stats
        #expect(stats.processedCount == 2)
        #expect(stats.recentCount == 2)
    }
    
    @Test("Reset")
    func reset() {
        let deduplicator = TreatmentDeduplicator()
        let treatment = makeBolus(insulin: 2.5)
        deduplicator.markProcessed(treatment)
        
        #expect(!deduplicator.shouldUpload(treatment))
        
        deduplicator.reset()
        
        #expect(deduplicator.shouldUpload(treatment))
    }
}

// MARK: - Treatment Factory Tests

@Suite("TreatmentFactory")
struct TreatmentFactoryTests {
    @Test("Bolus creation")
    func bolusCreation() {
        let bolus = TreatmentFactory.bolus(units: 2.5, deviceId: "t1pal-abc123")
        
        #expect(bolus.eventType == "Bolus")
        #expect(bolus.insulin == 2.5)
        #expect(bolus.identifier != nil)
        #expect(bolus.identifier!.hasPrefix("t1pal-abc123:bolus:"))
    }
    
    @Test("Carbs creation")
    func carbsCreation() {
        let carbs = TreatmentFactory.carbs(grams: 30, deviceId: "t1pal-abc123")
        
        #expect(carbs.eventType == "Carb Correction")
        #expect(carbs.carbs == 30)
        #expect(carbs.identifier != nil)
        #expect(carbs.identifier!.hasPrefix("t1pal-abc123:carb-correction:"))
    }
    
    @Test("Temp basal creation")
    func tempBasalCreation() {
        let tempBasal = TreatmentFactory.tempBasal(rate: 1.5, durationMinutes: 30, deviceId: "t1pal-abc123")
        
        #expect(tempBasal.eventType == "Temp Basal")
        #expect(tempBasal.rate == 1.5)
        #expect(tempBasal.duration == 30)
        #expect(tempBasal.identifier != nil)
        #expect(tempBasal.identifier!.hasPrefix("t1pal-abc123:temp-basal:"))
    }
    
    @Test("Meal bolus creation")
    func mealBolusCreation() {
        let mealBolus = TreatmentFactory.mealBolus(units: 4.0, carbs: 45, deviceId: "t1pal-abc123")
        
        #expect(mealBolus.eventType == "Meal Bolus")
        #expect(mealBolus.insulin == 4.0)
        #expect(mealBolus.carbs == 45)
        #expect(mealBolus.identifier != nil)
    }
    
    @Test("Correction bolus creation")
    func correctionBolusCreation() {
        let correction = TreatmentFactory.correctionBolus(units: 1.5, deviceId: "t1pal-abc123")
        
        #expect(correction.eventType == "Correction Bolus")
        #expect(correction.insulin == 1.5)
    }
    
    @Test("Profile switch creation")
    func profileSwitchCreation() {
        let profileSwitch = TreatmentFactory.profileSwitch(profileName: "Exercise", deviceId: "t1pal-abc123")
        
        #expect(profileSwitch.eventType == "Profile Switch")
        #expect(profileSwitch.profile == "Exercise")
    }
    
    @Test("Temp target creation")
    func tempTargetCreation() {
        let tempTarget = TreatmentFactory.tempTarget(
            targetLow: 120,
            targetHigh: 140,
            durationMinutes: 60,
            reason: "Exercise",
            deviceId: "t1pal-abc123"
        )
        
        #expect(tempTarget.eventType == "Temporary Target")
        #expect(tempTarget.targetBottom == 120)
        #expect(tempTarget.targetTop == 140)
        #expect(tempTarget.duration == 60)
        #expect(tempTarget.reason == "Exercise")
    }
}
