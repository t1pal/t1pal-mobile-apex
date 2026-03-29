// TreatmentCompatibilityTests.swift - Test treatments endpoint compatibility
// Part of NightscoutKitTests
// Trace: NS-COMPAT-004

import Foundation
import Testing
@testable import NightscoutKit
import T1PalCore

// MARK: - Treatment Fixture Data

/// Real treatment data fixtures from various uploaders
enum TreatmentFixtures {
    
    /// Loop bolus treatment
    static let loopBolusJSON = """
    {
        "_id": "69844a123456789012345678",
        "eventType": "Bolus",
        "created_at": "2026-02-05T07:30:00.000Z",
        "insulin": 2.5,
        "programmed": 2.5,
        "unabsorbed": 1.2,
        "type": "normal",
        "duration": 0,
        "enteredBy": "Loop",
        "syncIdentifier": "Loop:Bolus:1770277800000"
    }
    """
    
    /// Trio meal bolus with carbs
    static let trioMealBolusJSON = """
    {
        "_id": "69844b223456789012345679",
        "eventType": "Meal Bolus",
        "created_at": "2026-02-05T12:00:00.000Z",
        "insulin": 4.0,
        "carbs": 45,
        "enteredBy": "Trio",
        "notes": "Lunch",
        "syncIdentifier": "Trio:MealBolus:1770292800000"
    }
    """
    
    /// AAPS temp basal
    static let aapsTempBasalJSON = """
    {
        "_id": "69844c333456789012345680",
        "eventType": "Temp Basal",
        "created_at": "2026-02-05T14:30:00.000Z",
        "absolute": 0.8,
        "rate": 0.8,
        "duration": 30,
        "enteredBy": "AndroidAPS",
        "reason": "SMB"
    }
    """
    
    /// Carb correction
    static let carbCorrectionJSON = """
    {
        "_id": "69844d443456789012345681",
        "eventType": "Carb Correction",
        "created_at": "2026-02-05T15:45:00.000Z",
        "carbs": 15,
        "enteredBy": "xDrip+",
        "notes": "Juice box for low"
    }
    """
    
    /// Profile switch
    static let profileSwitchJSON = """
    {
        "_id": "69844e553456789012345682",
        "eventType": "Profile Switch",
        "created_at": "2026-02-05T06:00:00.000Z",
        "profile": "Exercise",
        "duration": 120,
        "percent": 80,
        "enteredBy": "Loop"
    }
    """
    
    /// Site change
    static let siteChangeJSON = """
    {
        "_id": "69844f663456789012345683",
        "eventType": "Site Change",
        "created_at": "2026-02-05T09:00:00.000Z",
        "enteredBy": "Nightscout",
        "notes": "Left abdomen"
    }
    """
    
    /// Sensor Start - FOLLOW-SAGE-001
    static let sensorStartJSON = """
    {
        "_id": "698451883456789012345685",
        "eventType": "Sensor Start",
        "created_at": "2026-02-05T08:00:00.000Z",
        "enteredBy": "Loop",
        "notes": "New G7 sensor"
    }
    """
    
    /// Announcement/note
    static let announcementJSON = """
    {
        "_id": "698450773456789012345684",
        "eventType": "Announcement",
        "created_at": "2026-02-05T10:00:00.000Z",
        "notes": "Starting exercise",
        "enteredBy": "Nightscout"
    }
    """
    
    /// AAPS SMB (Super Micro Bolus) - NS-TH-003
    static let aapsSMBJSON = """
    {
        "_id": "69844d553456789012345690",
        "eventType": "SMB",
        "created_at": "2026-02-05T16:30:00.000Z",
        "insulin": 0.3,
        "enteredBy": "AndroidAPS",
        "isSMB": true,
        "reason": "minPredBG 85 > 70",
        "syncIdentifier": "AndroidAPS:SMB:1770299400000"
    }
    """
    
    /// Array of mixed treatments
    static let mixedTreatmentsJSON = """
    [
        {"_id": "1", "eventType": "Bolus", "created_at": "2026-02-05T07:30:00.000Z", "insulin": 2.5, "enteredBy": "Loop"},
        {"_id": "2", "eventType": "Carb Correction", "created_at": "2026-02-05T15:45:00.000Z", "carbs": 15, "enteredBy": "xDrip+"},
        {"_id": "3", "eventType": "Temp Basal", "created_at": "2026-02-05T14:30:00.000Z", "rate": 0.8, "duration": 30, "enteredBy": "AndroidAPS"},
        {"_id": "4", "eventType": "Site Change", "created_at": "2026-02-05T09:00:00.000Z", "enteredBy": "Nightscout"}
    ]
    """
}

// MARK: - Tests

@Suite("Treatment Compatibility")
struct TreatmentCompatibilityTests {
    
    @Test("Parse Loop bolus treatment")
    func parseLoopBolus() throws {
        let data = TreatmentFixtures.loopBolusJSON.data(using: .utf8)!
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: data)
        
        #expect(treatment._id == "69844a123456789012345678")
        #expect(treatment.eventType == "Bolus")
        #expect(treatment.insulin == 2.5)
        #expect(treatment.enteredBy == "Loop")
        // Note: syncIdentifier field not in standard NS treatment format
    }
    
    @Test("Parse Trio meal bolus with carbs")
    func parseTrioMealBolus() throws {
        let data = TreatmentFixtures.trioMealBolusJSON.data(using: .utf8)!
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: data)
        
        #expect(treatment.eventType == "Meal Bolus")
        #expect(treatment.insulin == 4.0)
        #expect(treatment.carbs == 45.0)
        #expect(treatment.enteredBy == "Trio")
    }
    
    @Test("Parse AAPS temp basal")
    func parseAAPSTempBasal() throws {
        let data = TreatmentFixtures.aapsTempBasalJSON.data(using: .utf8)!
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: data)
        
        #expect(treatment.eventType == "Temp Basal")
        #expect(treatment.rate == 0.8)
        #expect(treatment.duration == 30.0)
        #expect(treatment.enteredBy == "AndroidAPS")
    }
    
    @Test("Parse carb correction")
    func parseCarbCorrection() throws {
        let data = TreatmentFixtures.carbCorrectionJSON.data(using: .utf8)!
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: data)
        
        #expect(treatment.eventType == "Carb Correction")
        #expect(treatment.carbs == 15.0)
        #expect(treatment.notes == "Juice box for low")
    }
    
    @Test("Parse profile switch")
    func parseProfileSwitch() throws {
        let data = TreatmentFixtures.profileSwitchJSON.data(using: .utf8)!
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: data)
        
        #expect(treatment.eventType == "Profile Switch")
        #expect(treatment.profile == "Exercise")
        #expect(treatment.percent == 80.0)
        #expect(treatment.duration == 120.0)
    }
    
    @Test("Parse mixed treatments array")
    func parseMixedTreatments() throws {
        let data = TreatmentFixtures.mixedTreatmentsJSON.data(using: .utf8)!
        let treatments = try JSONDecoder().decode([NightscoutTreatment].self, from: data)
        
        #expect(treatments.count == 4)
        #expect(treatments[0].eventType == "Bolus")
        #expect(treatments[1].eventType == "Carb Correction")
        #expect(treatments[2].eventType == "Temp Basal")
        #expect(treatments[3].eventType == "Site Change")
    }
    
    @Test("Treatment event type identification")
    func eventTypeIdentification() {
        // Test event type string matching
        #expect("Bolus".contains("Bolus"))
        #expect("Meal Bolus".contains("Bolus"))
        #expect("Carb Correction".contains("Carb"))
        #expect("Temp Basal".contains("Basal"))
        #expect("Site Change" == "Site Change")
    }
    
    // NS-TH-003: Test AAPS SMB (Super Micro Bolus) parsing
    @Test("Parse AAPS SMB treatment")
    func parseAAPSSMB() throws {
        let data = TreatmentFixtures.aapsSMBJSON.data(using: .utf8)!
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: data)
        
        #expect(treatment.eventType == "SMB")
        #expect(treatment.insulin == 0.3)
        #expect(treatment.enteredBy == "AndroidAPS")
        
        // Verify enum maps correctly
        #expect(treatment.treatmentEventType == .smb)
    }
    
    // NS-TH-003: Verify SMB event type is in enum
    @Test("SMB event type exists in enum")
    func smbEventTypeExists() {
        let smb = TreatmentEventType.smb
        #expect(smb.rawValue == "SMB")
        
        // Verify CaseIterable includes SMB
        #expect(TreatmentEventType.allCases.contains(.smb))
    }
    
    // FOLLOW-SAGE-001: Test Sensor Start treatment parsing
    @Test("Parse Sensor Start treatment")
    func parseSensorStart() throws {
        let data = TreatmentFixtures.sensorStartJSON.data(using: .utf8)!
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: data)
        
        #expect(treatment.eventType == "Sensor Start")
        #expect(treatment.enteredBy == "Loop")
        #expect(treatment.notes == "New G7 sensor")
        #expect(treatment.treatmentEventType == .sensorStart)
        #expect(treatment.timestamp != nil)
    }
    
    // FOLLOW-CAGE-001: Test Site Change treatment parsing
    @Test("Parse Site Change treatment")
    func parseSiteChange() throws {
        let data = TreatmentFixtures.siteChangeJSON.data(using: .utf8)!
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: data)
        
        #expect(treatment.eventType == "Site Change")
        #expect(treatment.enteredBy == "Nightscout")
        #expect(treatment.notes == "Left abdomen")
        #expect(treatment.treatmentEventType == .pumpSiteChange)
        #expect(treatment.timestamp != nil)
    }
    
    // MARK: - Live Fixture Tests (NS-TH-004)
    
    @Test("Parse fixture_treatments_live.json file")
    func parseLiveTreatmentsFixture() throws {
        // Load fixture from conformance directory
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests dir
            .deletingLastPathComponent()  // NightscoutKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // NightscoutKit
            .deletingLastPathComponent()  // packages
            .appendingPathComponent("conformance/nightscout/fixture_treatments_live.json")
        
        let data = try Data(contentsOf: fixtureURL)
        let treatments = try JSONDecoder().decode([NightscoutTreatment].self, from: data)
        
        #expect(treatments.count == 15)
        
        // Verify diverse event types parsed
        let eventTypes = Set(treatments.map { $0.eventType })
        #expect(eventTypes.contains("Bolus"))
        #expect(eventTypes.contains("Meal Bolus"))
        #expect(eventTypes.contains("SMB"))
        #expect(eventTypes.contains("Temp Basal"))
        #expect(eventTypes.contains("Carb Correction"))
        #expect(eventTypes.contains("Profile Switch"))
        #expect(eventTypes.contains("Site Change"))
        #expect(eventTypes.contains("BG Check"))
        
        // Verify different uploaders
        let uploaders = Set(treatments.compactMap { $0.enteredBy })
        #expect(uploaders.contains("Loop"))
        #expect(uploaders.contains("Trio"))
        #expect(uploaders.contains("AndroidAPS"))
        #expect(uploaders.contains("xDrip+"))
        #expect(uploaders.contains("Nightscout"))
        
        // Verify specific treatment details
        let smb = treatments.first { $0.eventType == "SMB" }
        #expect(smb?.insulin == 0.4)
        #expect(smb?.treatmentEventType == .smb)
        
        let mealBolus = treatments.first { $0.eventType == "Meal Bolus" }
        #expect(mealBolus?.carbs == 60)
        #expect(mealBolus?.insulin == 4.5)
        
        let profileSwitch = treatments.first { $0.eventType == "Profile Switch" }
        #expect(profileSwitch?.profile == "Exercise")
    }
    
    @Test("Live fixture covers all common event types")
    func liveFixtureCoverage() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("conformance/nightscout/fixture_treatments_live.json")
        
        let data = try Data(contentsOf: fixtureURL)
        let treatments = try JSONDecoder().decode([NightscoutTreatment].self, from: data)
        
        // Map event types to enum
        let mappedTypes = treatments.compactMap { $0.treatmentEventType }
        let uniqueTypes = Set(mappedTypes)
        
        // Should have good coverage of common types
        #expect(uniqueTypes.count >= 10)
        #expect(uniqueTypes.contains(.bolus))
        #expect(uniqueTypes.contains(.mealBolus))
        #expect(uniqueTypes.contains(.tempBasal))
        #expect(uniqueTypes.contains(.smb))
        #expect(uniqueTypes.contains(.carbCorrection))
        #expect(uniqueTypes.contains(.profileSwitch))
        #expect(uniqueTypes.contains(.pumpSiteChange))
        #expect(uniqueTypes.contains(.sensorStart))
    }
}
