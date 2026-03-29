// NightscoutKitTests.swift
// Tests for NightscoutKit

import Foundation
import Testing
@testable import NightscoutKit
import T1PalCore

// MARK: - Config Tests

@Suite("Config Tests")
struct ConfigTests {
    
    @Test("Config initialization")
    func configInitialization() {
        let url = URL(string: "https://test.nightscout.example")!
        let config = NightscoutConfig(url: url, apiSecret: "mysecret", token: nil)
        
        #expect(config.url == url)
        #expect(config.apiSecret == "mysecret")
        #expect(config.token == nil)
    }
    
    @Test("API secret hash")
    func apiSecretHash() {
        let config = NightscoutConfig(
            url: URL(string: "https://test.example")!,
            apiSecret: "my-test-secret"
        )
        
        // Should produce a 40-char hex SHA1 hash
        let hash = config.apiSecretHash
        #expect(hash != nil)
        #expect(hash?.count == 40)
        
        // Same secret should produce same hash
        let config2 = NightscoutConfig(
            url: URL(string: "https://other.example")!,
            apiSecret: "my-test-secret"
        )
        #expect(config.apiSecretHash == config2.apiSecretHash)
    }
}

// MARK: - Entry Tests

@Suite("Entry Tests")
struct EntryTests {
    
    @Test("Entry decoding")
    func entryDecoding() throws {
        let json = """
        {
            "_id": "abc123",
            "type": "sgv",
            "sgv": 120,
            "direction": "Flat",
            "dateString": "2026-02-01T12:00:00Z",
            "date": 1769860800000,
            "device": "dexcom"
        }
        """
        
        let entry = try JSONDecoder().decode(NightscoutEntry.self, from: json.data(using: .utf8)!)
        
        #expect(entry._id == "abc123")
        #expect(entry.type == "sgv")
        #expect(entry.sgv == 120)
        #expect(entry.direction == "Flat")
        #expect(entry.device == "dexcom")
    }
    
    @Test("Entry to glucose reading")
    func entryToGlucoseReading() {
        let entry = NightscoutEntry(
            _id: "test123",
            type: "sgv",
            sgv: 110,
            direction: "FortyFiveUp",
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000,
            device: "dexcom"
        )
        
        let reading = entry.toGlucoseReading()
        
        #expect(reading != nil)
        #expect(reading?.glucose == 110)
        #expect(reading?.trend == .fortyFiveUp)
        #expect(reading?.source == "dexcom")
    }
    
    @Test("Entry to glucose reading trends")
    func entryToGlucoseReadingTrends() {
        let trends: [(String, GlucoseTrend)] = [
            ("DoubleUp", .doubleUp),
            ("SingleUp", .singleUp),
            ("FortyFiveUp", .fortyFiveUp),
            ("Flat", .flat),
            ("FortyFiveDown", .fortyFiveDown),
            ("SingleDown", .singleDown),
            ("DoubleDown", .doubleDown),
            ("Unknown", .notComputable),
        ]
        
        for (direction, expectedTrend) in trends {
            let entry = NightscoutEntry(
                type: "sgv",
                sgv: 100,
                direction: direction,
                dateString: "2026-02-01T12:00:00Z",
                date: 1769860800000
            )
            let reading = entry.toGlucoseReading()
            #expect(reading?.trend == expectedTrend, "Direction \(direction) should map to \(expectedTrend)")
        }
    }
    
    @Test("Entry without SGV returns nil")
    func entryWithoutSgvReturnsNil() {
        let entry = NightscoutEntry(
            type: "cal",
            sgv: nil,
            direction: nil,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000
        )
        
        #expect(entry.toGlucoseReading() == nil)
    }
}

// MARK: - Treatment Tests

@Suite("Treatment Tests")
struct TreatmentTests {
    
    @Test("Treatment decoding")
    func treatmentDecoding() throws {
        let json = """
        {
            "_id": "treat123",
            "eventType": "Correction Bolus",
            "created_at": "2026-02-01T12:00:00Z",
            "insulin": 2.5,
            "carbs": null,
            "notes": "Test bolus"
        }
        """
        
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: json.data(using: .utf8)!)
        
        #expect(treatment._id == "treat123")
        #expect(treatment.eventType == "Correction Bolus")
        #expect(treatment.insulin == 2.5)
        #expect(treatment.carbs == nil)
        #expect(treatment.notes == "Test bolus")
    }
    
    @Test("Treatment temp basal")
    func treatmentTempBasal() throws {
        let json = """
        {
            "eventType": "Temp Basal",
            "created_at": "2026-02-01T12:00:00Z",
            "duration": 30,
            "absolute": 0.8,
            "rate": 0.8
        }
        """
        
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: json.data(using: .utf8)!)
        
        #expect(treatment.eventType == "Temp Basal")
        #expect(treatment.duration == 30)
        #expect(treatment.absolute == 0.8)
    }
}

// MARK: - DeviceStatus Tests

@Suite("DeviceStatus Tests")
struct DeviceStatusTests {
    
    @Test("Device status decoding")
    func deviceStatusDecoding() throws {
        let json = """
        {
            "device": "t1pal://demo",
            "created_at": "2026-02-01T12:00:00Z",
            "loop": {
                "iob": { "iob": 1.5, "timestamp": "2026-02-01T12:00:00Z" },
                "cob": { "cob": 20.0, "timestamp": "2026-02-01T12:00:00Z" }
            },
            "pump": {
                "reservoir": 150.5,
                "battery": { "percent": 85 }
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status.device == "t1pal://demo")
        #expect(status.loop?.iob?.iob == 1.5)
        #expect(status.loop?.cob?.cob == 20.0)
        #expect(status.pump?.reservoir == 150.5)
        #expect(status.pump?.battery?.percent == 85)
    }
}

// MARK: - SHA1 Tests

@Suite("SHA1 Tests")
struct SHA1Tests {
    
    @Test("SHA1 known vector")
    func sha1KnownVector() {
        // Known SHA1 test vector: "abc" -> a9993e364706816aba3e25717850c26c9cd0d89d
        let result = "abc".sha1()
        #expect(result == "a9993e364706816aba3e25717850c26c9cd0d89d")
    }
    
    @Test("SHA1 empty string")
    func sha1EmptyString() {
        // SHA1 of empty string
        let result = "".sha1()
        #expect(result == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    }
    
    @Test("SHA1 consistency")
    func sha1Consistency() {
        let secret = "my-api-secret-12345"
        let hash1 = secret.sha1()
        let hash2 = secret.sha1()
        #expect(hash1 == hash2)
        #expect(hash1.count == 40)
    }
}

// MARK: - EntriesQuery Tests

@Suite("EntriesQuery Tests")
struct EntriesQueryTests {
    
    @Test("Entries query basic")
    func entriesQueryBasic() {
        let query = EntriesQuery(count: 100)
        let items = query.toQueryItems()
        
        #expect(items.count == 1)
        #expect(items.first?.name == "count")
        #expect(items.first?.value == "100")
    }
    
    @Test("Entries query date range")
    func entriesQueryDateRange() {
        let from = Date(timeIntervalSince1970: 1700000000)
        let to = Date(timeIntervalSince1970: 1700100000)
        
        let query = EntriesQuery(dateFrom: from, dateTo: to)
        let items = query.toQueryItems()
        
        #expect(items.count == 2)
        #expect(items.contains { $0.name == "find[date][$gte]" && $0.value == "1700000000000" })
        #expect(items.contains { $0.name == "find[date][$lte]" && $0.value == "1700100000000" })
    }
    
    @Test("Entries query type filter")
    func entriesQueryTypeFilter() {
        let query = EntriesQuery(type: .mbg)
        let items = query.toQueryItems()
        
        #expect(items.contains { $0.name == "find[type]" && $0.value == "mbg" })
    }
    
    @Test("Entries query combined")
    func entriesQueryCombined() {
        let from = Date(timeIntervalSince1970: 1700000000)
        
        let query = EntriesQuery(count: 50, dateFrom: from, type: .sgv)
        let items = query.toQueryItems()
        
        #expect(items.count == 3)
        #expect(items.contains { $0.name == "count" })
        #expect(items.contains { $0.name == "find[date][$gte]" })
        #expect(items.contains { $0.name == "find[type]" })
    }
}

// MARK: - Entry Type Tests

@Suite("Entry Type Tests")
struct EntryTypeTests {
    
    @Test("Entry type enum")
    func entryTypeEnum() {
        #expect(NightscoutEntryType.sgv.rawValue == "sgv")
        #expect(NightscoutEntryType.mbg.rawValue == "mbg")
        #expect(NightscoutEntryType.cal.rawValue == "cal")
        #expect(NightscoutEntryType.sensor.rawValue == "sensor")
    }
    
    @Test("Entry timestamp")
    func entryTimestamp() {
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 100,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000
        )
        
        #expect(entry.timestamp.timeIntervalSince1970 == 1769860800)
    }
    
    @Test("Entry equatable")
    func entryEquatable() {
        let entry1 = NightscoutEntry(
            type: "sgv",
            sgv: 100,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000
        )
        
        let entry2 = NightscoutEntry(
            type: "sgv",
            sgv: 100,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000
        )
        
        // Different timestamp = different entry
        let entry3 = NightscoutEntry(
            type: "sgv",
            sgv: 110,
            dateString: "2026-02-01T12:05:00Z",
            date: 1769861100000  // 5 minutes later
        )
        
        #expect(entry1 == entry2)
        #expect(entry1 != entry3)
    }
    
    @Test("Entry hashable")
    func entryHashable() {
        let entry1 = NightscoutEntry(
            type: "sgv",
            sgv: 100,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000
        )
        
        let entry2 = NightscoutEntry(
            type: "sgv",
            sgv: 100,
            dateString: "2026-02-01T12:00:00Z",
            date: 1769860800000
        )
        
        var set = Set<NightscoutEntry>()
        set.insert(entry1)
        set.insert(entry2)
        
        #expect(set.count == 1) // Duplicates removed
    }
}

// MARK: - Extended Entry Fields Tests

@Suite("Extended Entry Fields Tests")
struct ExtendedEntryFieldsTests {
    
    @Test("Entry with MBG decoding")
    func entryWithMBGDecoding() throws {
        let json = """
        {
            "type": "mbg",
            "mbg": 105,
            "dateString": "2026-02-01T12:00:00Z",
            "date": 1769860800000,
            "device": "meter"
        }
        """
        
        let entry = try JSONDecoder().decode(NightscoutEntry.self, from: json.data(using: .utf8)!)
        
        #expect(entry.type == "mbg")
        #expect(entry.mbg == 105)
        #expect(entry.entryType == .mbg)
    }
    
    @Test("Entry with calibration decoding")
    func entryWithCalibrationDecoding() throws {
        let json = """
        {
            "type": "cal",
            "slope": 850.5,
            "intercept": 32000.0,
            "scale": 1.0,
            "dateString": "2026-02-01T12:00:00Z",
            "date": 1769860800000
        }
        """
        
        let entry = try JSONDecoder().decode(NightscoutEntry.self, from: json.data(using: .utf8)!)
        
        #expect(entry.type == "cal")
        #expect(entry.slope == 850.5)
        #expect(entry.intercept == 32000.0)
        #expect(entry.scale == 1.0)
    }
    
    @Test("Entry with noise and raw")
    func entryWithNoiseAndRaw() throws {
        let json = """
        {
            "type": "sgv",
            "sgv": 120,
            "noise": 1,
            "filtered": 180000.0,
            "unfiltered": 182000.0,
            "rssi": -65,
            "dateString": "2026-02-01T12:00:00Z",
            "date": 1769860800000
        }
        """
        
        let entry = try JSONDecoder().decode(NightscoutEntry.self, from: json.data(using: .utf8)!)
        
        #expect(entry.noise == 1)
        #expect(entry.filtered == 180000.0)
        #expect(entry.unfiltered == 182000.0)
        #expect(entry.rssi == -65)
    }
}

// MARK: - Sync State Tests

@Suite("Sync State Tests")
struct SyncStateTests {
    
    @Test("Sync state initialization")
    func syncStateInitialization() {
        let state = EntriesSyncState()
        
        #expect(state.lastSyncDate == nil)
        #expect(state.lastUploadedDate == nil)
        #expect(state.lastDownloadedDate == nil)
        #expect(state.uploadedCount == 0)
        #expect(state.downloadedCount == 0)
    }
    
    @Test("Sync state encoding")
    func syncStateEncoding() throws {
        var state = EntriesSyncState()
        state.lastSyncDate = Date(timeIntervalSince1970: 1700000000)
        state.uploadedCount = 100
        state.downloadedCount = 50
        
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(EntriesSyncState.self, from: data)
        
        #expect(decoded.lastSyncDate?.timeIntervalSince1970 == 1700000000)
        #expect(decoded.uploadedCount == 100)
        #expect(decoded.downloadedCount == 50)
    }
    
}

// MARK: - Sync Result Tests

@Suite("Sync Result Tests")
struct SyncResultTests {
    
    @Test("Sync result success")
    func syncResultSuccess() {
        let result = EntriesSyncResult(uploaded: 10, downloaded: 20, duplicatesSkipped: 5)
        
        #expect(result.success)
        #expect(result.uploaded == 10)
        #expect(result.downloaded == 20)
        #expect(result.duplicatesSkipped == 5)
    }
    
    @Test("Sync result with errors")
    func syncResultWithErrors() {
        let result = EntriesSyncResult(errors: [NightscoutError.fetchFailed])
        
        #expect(!result.success)
        #expect(result.errors.count == 1)
    }
    
}

// MARK: - Entry Conversion Tests

@Suite("Entry Conversion Tests")
struct EntryConversionTests {
    
    @Test("Entries from readings")
    func entriesFromReadings() {
        let reading = GlucoseReading(
            glucose: 120,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            trend: .flat,
            source: "test"
        )
        
        let entries = EntriesSyncManager.entriesFromReadings([reading], device: "t1pal-test")
        
        #expect(entries.count == 1)
        #expect(entries[0].sgv == 120)
        #expect(entries[0].direction == "Flat")
        #expect(entries[0].device == "t1pal-test")
        #expect(entries[0].date == 1700000000000)
    }
    
    @Test("Entries from readings all trends")
    func entriesFromReadingsAllTrends() {
        let trends: [(GlucoseTrend, String)] = [
            (.doubleUp, "DoubleUp"),
            (.singleUp, "SingleUp"),
            (.fortyFiveUp, "FortyFiveUp"),
            (.flat, "Flat"),
            (.fortyFiveDown, "FortyFiveDown"),
            (.singleDown, "SingleDown"),
            (.doubleDown, "DoubleDown"),
            (.notComputable, "NOT COMPUTABLE"),
        ]
        
        for (trend, expectedDirection) in trends {
            let reading = GlucoseReading(
                glucose: 100,
                timestamp: Date(),
                trend: trend,
                source: "test"
            )
            
            let entries = EntriesSyncManager.entriesFromReadings([reading])
            #expect(entries[0].direction == expectedDirection, "Trend \(trend) should map to \(expectedDirection)")
        }
    }
    
}

// MARK: - TreatmentEventType Tests

@Suite("TreatmentEventType Tests")
struct TreatmentEventTypeTests {
    
    @Test("Treatment event type enum values")
    func treatmentEventTypeEnumValues() {
        #expect(TreatmentEventType.correctionBolus.rawValue == "Correction Bolus")
        #expect(TreatmentEventType.mealBolus.rawValue == "Meal Bolus")
        #expect(TreatmentEventType.tempBasal.rawValue == "Temp Basal")
        #expect(TreatmentEventType.mealCarbs.rawValue == "Meal")
        #expect(TreatmentEventType.profileSwitch.rawValue == "Profile Switch")
        #expect(TreatmentEventType.bgCheck.rawValue == "BG Check")
        #expect(TreatmentEventType.suspend.rawValue == "Suspend Pump")
        #expect(TreatmentEventType.resume.rawValue == "Resume Pump")
    }
    
    @Test("Treatment event type all cases")
    func treatmentEventTypeAllCases() {
        // Ensure all cases are defined
        #expect(TreatmentEventType.allCases.count >= 20)
    }
    
}

// MARK: - TreatmentsQuery Tests

@Suite("TreatmentsQuery Tests")
struct TreatmentsQueryTests {
    
    @Test("Treatments query basic")
    func treatmentsQueryBasic() {
        let query = TreatmentsQuery(count: 50)
        let items = query.toQueryItems()
        
        #expect(items.count == 1)
        #expect(items.first?.name == "count")
        #expect(items.first?.value == "50")
    }
    
    @Test("Treatments query date range")
    func treatmentsQueryDateRange() {
        let from = Date(timeIntervalSince1970: 1700000000)
        let to = Date(timeIntervalSince1970: 1700100000)
        
        let query = TreatmentsQuery(dateFrom: from, dateTo: to)
        let items = query.toQueryItems()
        
        #expect(items.count == 2)
        #expect(items.contains { $0.name == "find[created_at][$gte]" })
        #expect(items.contains { $0.name == "find[created_at][$lte]" })
    }
    
    @Test("Treatments query event type filter")
    func treatmentsQueryEventTypeFilter() {
        let query = TreatmentsQuery(eventType: .correctionBolus)
        let items = query.toQueryItems()
        
        #expect(items.contains { $0.name == "find[eventType]" && $0.value == "Correction Bolus" })
    }
    
}

// MARK: - Extended NightscoutTreatment Tests

@Suite("Extended NightscoutTreatment Tests")
struct ExtendedNightscoutTreatmentTests {
    
    @Test("Treatment timestamp")
    func treatmentTimestamp() {
        let treatment = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5
        )
        
        #expect(treatment.timestamp != nil)
        #expect(abs(treatment.timestamp!.timeIntervalSince1970 - 1769947200) < 1)
    }
    
    @Test("Treatment timestamp with fractional seconds")
    func treatmentTimestampWithFractionalSeconds() {
        let treatment = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00.123Z",
            insulin: 2.5
        )
        
        #expect(treatment.timestamp != nil)
    }
    
    @Test("Treatment event type enum")
    func treatmentEventTypeEnum() {
        let treatment = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5
        )
        
        #expect(treatment.treatmentEventType == .correctionBolus)
    }
    
    @Test("Treatment is insulin")
    func treatmentIsInsulin() {
        let bolus = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5
        )
        
        let carb = NightscoutTreatment(
            eventType: "Meal",
            created_at: "2026-02-01T12:00:00Z",
            carbs: 30
        )
        
        #expect(bolus.isInsulinTreatment)
        #expect(!bolus.isCarbTreatment)
        #expect(!carb.isInsulinTreatment)
        #expect(carb.isCarbTreatment)
    }
    
    @Test("Treatment is temp basal")
    func treatmentIsTempBasal() {
        let tempBasal = NightscoutTreatment(
            eventType: "Temp Basal",
            created_at: "2026-02-01T12:00:00Z",
            duration: 30,
            absolute: 0.8,
            rate: 0.8
        )
        
        let bolus = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5
        )
        
        #expect(tempBasal.isTempBasal)
        #expect(!bolus.isTempBasal)
    }
    
    @Test("Treatment equatable")
    func treatmentEquatable() {
        let t1 = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5
        )
        
        let t2 = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5
        )
        
        // Different timestamp = different treatment
        let t3 = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:05:00Z",  // 5 minutes later
            insulin: 3.0
        )
        
        #expect(t1 == t2)
        #expect(t1 != t3)
    }
    
    @Test("Treatment hashable")
    func treatmentHashable() {
        let t1 = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5
        )
        
        let t2 = NightscoutTreatment(
            eventType: "Correction Bolus",
            created_at: "2026-02-01T12:00:00Z",
            insulin: 2.5
        )
        
        var set = Set<NightscoutTreatment>()
        set.insert(t1)
        set.insert(t2)
        
        #expect(set.count == 1) // Duplicates removed
    }
    
    @Test("Treatment with all fields")
    func treatmentWithAllFields() throws {
        let json = """
        {
            "_id": "treat123",
            "eventType": "Temp Basal",
            "created_at": "2026-02-01T12:00:00Z",
            "duration": 30,
            "absolute": 0.8,
            "rate": 0.8,
            "percent": -20,
            "enteredBy": "t1pal",
            "notes": "Test temp basal"
        }
        """
        
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: json.data(using: .utf8)!)
        
        #expect(treatment.eventType == "Temp Basal")
        #expect(treatment.duration == 30)
        #expect(treatment.absolute == 0.8)
        #expect(treatment.percent == -20)
        #expect(treatment.enteredBy == "t1pal")
    }
    
    @Test("Treatment profile switch")
    func treatmentProfileSwitch() throws {
        let json = """
        {
            "eventType": "Profile Switch",
            "created_at": "2026-02-01T12:00:00Z",
            "profile": "Exercise",
            "profileIndex": 1
        }
        """
        
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: json.data(using: .utf8)!)
        
        #expect(treatment.eventType == "Profile Switch")
        #expect(treatment.profile == "Exercise")
        #expect(treatment.profileIndex == 1)
    }
    
    @Test("Treatment temp target")
    func treatmentTempTarget() throws {
        let json = """
        {
            "eventType": "Temporary Target",
            "created_at": "2026-02-01T12:00:00Z",
            "targetTop": 150,
            "targetBottom": 120,
            "duration": 60,
            "reason": "Exercise"
        }
        """
        
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: json.data(using: .utf8)!)
        
        #expect(treatment.targetTop == 150)
        #expect(treatment.targetBottom == 120)
        #expect(treatment.reason == "Exercise")
    }
    
    @Test("Treatment b g check")
    func treatmentBGCheck() throws {
        let json = """
        {
            "eventType": "BG Check",
            "created_at": "2026-02-01T12:00:00Z",
            "glucose": 120,
            "glucoseType": "Finger",
            "units": "mg/dL"
        }
        """
        
        let treatment = try JSONDecoder().decode(NightscoutTreatment.self, from: json.data(using: .utf8)!)
        
        #expect(treatment.glucose == 120)
        #expect(treatment.glucoseType == "Finger")
        #expect(treatment.units == "mg/dL")
    }
    
}

// MARK: - TreatmentsSyncState Tests

@Suite("TreatmentsSyncState Tests")
struct TreatmentsSyncStateTests {
    
    @Test("Treatments sync state initialization")
    func treatmentsSyncStateInitialization() {
        let state = TreatmentsSyncState()
        
        #expect(state.lastSyncDate == nil)
        #expect(state.lastUploadedDate == nil)
        #expect(state.lastDownloadedDate == nil)
        #expect(state.uploadedCount == 0)
        #expect(state.downloadedCount == 0)
    }
    
    @Test("Treatments sync state encoding")
    func treatmentsSyncStateEncoding() throws {
        var state = TreatmentsSyncState()
        state.lastSyncDate = Date(timeIntervalSince1970: 1700000000)
        state.uploadedCount = 50
        state.downloadedCount = 100
        
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TreatmentsSyncState.self, from: data)
        
        #expect(decoded.lastSyncDate?.timeIntervalSince1970 == 1700000000)
        #expect(decoded.uploadedCount == 50)
        #expect(decoded.downloadedCount == 100)
    }
    
}

// MARK: - TreatmentsSyncResult Tests

@Suite("TreatmentsSyncResult Tests")
struct TreatmentsSyncResultTests {
    
    @Test("Treatments sync result success")
    func treatmentsSyncResultSuccess() {
        let result = TreatmentsSyncResult(uploaded: 5, downloaded: 10, duplicatesSkipped: 2)
        
        #expect(result.success)
        #expect(result.uploaded == 5)
        #expect(result.downloaded == 10)
        #expect(result.duplicatesSkipped == 2)
    }
    
    @Test("Treatments sync result with errors")
    func treatmentsSyncResultWithErrors() {
        let result = TreatmentsSyncResult(errors: [NightscoutError.uploadFailed])
        
        #expect(!result.success)
        #expect(result.errors.count == 1)
    }
    
}

// MARK: - TreatmentsSyncManager Factory Methods Tests

@Suite("TreatmentsSyncManager Factory Methods Tests")
struct TreatmentsSyncManagerFactoryMethodsTests {
    
    @Test("Bolus from insulin")
    func bolusFromInsulin() {
        let bolus = TreatmentsSyncManager.bolusFromInsulin(
            units: 2.5,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            type: .correctionBolus,
            device: "t1pal-test",
            notes: "Test bolus"
        )
        
        #expect(bolus.eventType == "Correction Bolus")
        #expect(bolus.insulin == 2.5)
        #expect(bolus.enteredBy == "t1pal-test")
        #expect(bolus.notes == "Test bolus")
        #expect(bolus.timestamp != nil)
    }
    
    @Test("Carb entry")
    func carbEntry() {
        let carb = TreatmentsSyncManager.carbEntry(
            grams: 45,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            device: "t1pal-test",
            notes: "Lunch"
        )
        
        #expect(carb.eventType == "Meal")
        #expect(carb.carbs == 45)
        #expect(carb.enteredBy == "t1pal-test")
        #expect(carb.notes == "Lunch")
    }
    
    @Test("Temp basal factory")
    func tempBasalFactory() {
        let tempBasal = TreatmentsSyncManager.tempBasal(
            rate: 0.5,
            duration: 30,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            device: "t1pal-test"
        )
        
        #expect(tempBasal.eventType == "Temp Basal")
        #expect(tempBasal.rate == 0.5)
        #expect(tempBasal.absolute == 0.5)
        #expect(tempBasal.duration == 30)
        #expect(tempBasal.enteredBy == "t1pal-test")
    }
    
}

// MARK: - DeviceStatusQuery Tests

@Suite("DeviceStatusQuery Tests")
struct DeviceStatusQueryTests {
    
    @Test("Device status query basic")
    func deviceStatusQueryBasic() {
        let query = DeviceStatusQuery(count: 20)
        let items = query.toQueryItems()
        
        #expect(items.count == 1)
        #expect(items.first?.name == "count")
        #expect(items.first?.value == "20")
    }
    
    @Test("Device status query date range")
    func deviceStatusQueryDateRange() {
        let from = Date(timeIntervalSince1970: 1700000000)
        let to = Date(timeIntervalSince1970: 1700100000)
        
        let query = DeviceStatusQuery(dateFrom: from, dateTo: to)
        let items = query.toQueryItems()
        
        #expect(items.count == 2)
        #expect(items.contains { $0.name == "find[created_at][$gte]" })
        #expect(items.contains { $0.name == "find[created_at][$lte]" })
    }
    
    @Test("Device status query device filter")
    func deviceStatusQueryDeviceFilter() {
        let query = DeviceStatusQuery(device: "t1pal")
        let items = query.toQueryItems()
        
        #expect(items.contains { $0.name == "find[device]" && $0.value == "t1pal" })
    }
    
}

// MARK: - NightscoutDeviceStatus Tests

@Suite("NightscoutDeviceStatus Tests")
struct NightscoutDeviceStatusTests {
    
    @Test("Device status basic decoding")
    func deviceStatusBasicDecoding() throws {
        let json = """
        {
            "_id": "status123",
            "device": "t1pal://demo",
            "created_at": "2026-02-01T12:00:00Z",
            "mills": 1769947200000
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status._id == "status123")
        #expect(status.device == "t1pal://demo")
        #expect(status.mills == 1769947200000)
    }
    
    @Test("Device status timestamp")
    func deviceStatusTimestamp() {
        let status = NightscoutDeviceStatus(
            device: "test",
            created_at: "2026-02-01T12:00:00Z",
            mills: 1769947200000
        )
        
        #expect(status.timestamp != nil)
        #expect(abs(status.timestamp!.timeIntervalSince1970 - 1769947200) < 1)
    }
    
    @Test("Device status equatable")
    func deviceStatusEquatable() {
        let s1 = NightscoutDeviceStatus(
            device: "test",
            created_at: "2026-02-01T12:00:00Z"
        )
        
        let s2 = NightscoutDeviceStatus(
            device: "test",
            created_at: "2026-02-01T12:00:00Z"
        )
        
        let s3 = NightscoutDeviceStatus(
            device: "other",
            created_at: "2026-02-01T12:00:00Z"
        )
        
        #expect(s1 == s2)
        #expect(s1 != s3)
    }
    
    @Test("Device status is loop status")
    func deviceStatusIsLoopStatus() {
        let loopStatus = NightscoutDeviceStatus(
            device: "loop://test",
            created_at: "2026-02-01T12:00:00Z",
            loop: NightscoutDeviceStatus.LoopStatus(
                iob: NightscoutDeviceStatus.LoopStatus.IOBStatus(iob: 1.5)
            )
        )
        
        let openapsStatus = NightscoutDeviceStatus(
            device: "openaps://test",
            created_at: "2026-02-01T12:00:00Z",
            openaps: NightscoutDeviceStatus.OpenAPSStatus(
                iob: NightscoutDeviceStatus.OpenAPSStatus.IOBData(iob: 2.0)
            )
        )
        
        #expect(loopStatus.isLoopStatus)
        #expect(!loopStatus.isOpenAPSStatus)
        #expect(!openapsStatus.isLoopStatus)
        #expect(openapsStatus.isOpenAPSStatus)
    }
    
    @Test("Device status i o b accessor")
    func deviceStatusIOBAccessor() {
        let loopStatus = NightscoutDeviceStatus(
            device: "loop://test",
            created_at: "2026-02-01T12:00:00Z",
            loop: NightscoutDeviceStatus.LoopStatus(
                iob: NightscoutDeviceStatus.LoopStatus.IOBStatus(iob: 1.5)
            )
        )
        
        let openapsStatus = NightscoutDeviceStatus(
            device: "openaps://test",
            created_at: "2026-02-01T12:00:00Z",
            openaps: NightscoutDeviceStatus.OpenAPSStatus(
                iob: NightscoutDeviceStatus.OpenAPSStatus.IOBData(iob: 2.0)
            )
        )
        
        #expect(loopStatus.iob == 1.5)
        #expect(openapsStatus.iob == 2.0)
    }
    
    @Test("Device status c o b accessor")
    func deviceStatusCOBAccessor() {
        let loopStatus = NightscoutDeviceStatus(
            device: "loop://test",
            created_at: "2026-02-01T12:00:00Z",
            loop: NightscoutDeviceStatus.LoopStatus(
                cob: NightscoutDeviceStatus.LoopStatus.COBStatus(cob: 30)
            )
        )
        
        let openapsStatus = NightscoutDeviceStatus(
            device: "openaps://test",
            created_at: "2026-02-01T12:00:00Z",
            openaps: NightscoutDeviceStatus.OpenAPSStatus(
                suggested: NightscoutDeviceStatus.OpenAPSStatus.SuggestedStatus(COB: 45)
            )
        )
        
        #expect(loopStatus.cob == 30)
        #expect(openapsStatus.cob == 45)
    }
    
    @Test("Loop status decoding")
    func loopStatusDecoding() throws {
        let json = """
        {
            "device": "loop://demo",
            "created_at": "2026-02-01T12:00:00Z",
            "loop": {
                "iob": { "iob": 1.5, "basaliob": 0.8, "timestamp": "2026-02-01T12:00:00Z" },
                "cob": { "cob": 30.0, "carbs_hr": 5.0, "timestamp": "2026-02-01T12:00:00Z" },
                "predicted": { "startDate": "2026-02-01T12:00:00Z", "values": [120, 115, 110, 108] },
                "enacted": { "rate": 0.5, "duration": 30, "received": true },
                "recommendedBolus": 1.2,
                "version": "3.0.0"
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status.loop != nil)
        #expect(status.loop?.iob?.iob == 1.5)
        #expect(status.loop?.iob?.basaliob == 0.8)
        #expect(status.loop?.cob?.cob == 30.0)
        #expect(status.loop?.cob?.carbs_hr == 5.0)
        #expect(status.loop?.predicted?.values?.count == 4)
        #expect(status.loop?.enacted?.rate == 0.5)
        #expect(status.loop?.enacted?.received == true)
        #expect(status.loop?.recommendedBolus == 1.2)
        #expect(status.loop?.version == "3.0.0")
    }
    
    @Test("Open a p s status decoding")
    func openAPSStatusDecoding() throws {
        let json = """
        {
            "device": "openaps://rig",
            "created_at": "2026-02-01T12:00:00Z",
            "openaps": {
                "iob": { "iob": 2.0, "basaliob": 1.2, "activity": 0.05 },
                "suggested": {
                    "bg": 120,
                    "temp": "absolute",
                    "rate": 0.8,
                    "duration": 30,
                    "reason": "COB: 30g, IOB: 2U",
                    "eventualBG": 110,
                    "sensitivityRatio": 0.9,
                    "predBGs": { "IOB": [120, 115, 110], "COB": [125, 120, 115] }
                },
                "enacted": {
                    "bg": 120,
                    "rate": 0.8,
                    "duration": 30,
                    "received": true
                }
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status.openaps != nil)
        #expect(status.openaps?.iob?.iob == 2.0)
        #expect(status.openaps?.iob?.activity == 0.05)
        #expect(status.openaps?.suggested?.bg == 120)
        #expect(status.openaps?.suggested?.rate == 0.8)
        #expect(status.openaps?.suggested?.sensitivityRatio == 0.9)
        #expect(status.openaps?.suggested?.predBGs?.IOB?.count == 3)
        #expect(status.openaps?.enacted?.received == true)
    }
    
    @Test("Pump status decoding")
    func pumpStatusDecoding() throws {
        let json = """
        {
            "device": "t1pal://demo",
            "created_at": "2026-02-01T12:00:00Z",
            "pump": {
                "clock": "2026-02-01T12:00:00Z",
                "reservoir": 150.5,
                "battery": { "percent": 85, "voltage": 1.35 },
                "status": { "status": "normal", "bolusing": false, "suspended": false },
                "suspended": false
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status.pump != nil)
        #expect(status.pump?.reservoir == 150.5)
        #expect(status.pump?.battery?.percent == 85)
        #expect(status.pump?.battery?.voltage == 1.35)
        #expect(status.pump?.status?.bolusing == false)
        #expect(status.pump?.suspended == false)
    }
    
    @Test("Uploader status decoding")
    func uploaderStatusDecoding() throws {
        let json = """
        {
            "device": "t1pal://demo",
            "created_at": "2026-02-01T12:00:00Z",
            "uploader": {
                "battery": 75,
                "batteryVoltage": 4.1,
                "isCharging": true,
                "name": "iPhone 15 Pro"
            }
        }
        """
        
        let status = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: json.data(using: .utf8)!)
        
        #expect(status.uploader != nil)
        #expect(status.uploader?.battery == 75)
        #expect(status.uploader?.batteryVoltage == 4.1)
        #expect(status.uploader?.isCharging == true)
        #expect(status.uploader?.name == "iPhone 15 Pro")
    }
    
}

// MARK: - DeviceStatusSyncState Tests

@Suite("DeviceStatusSyncState Tests")
struct DeviceStatusSyncStateTests {
    
    @Test("Device status sync state initialization")
    func deviceStatusSyncStateInitialization() {
        let state = DeviceStatusSyncState()
        
        #expect(state.lastSyncDate == nil)
        #expect(state.lastUploadedDate == nil)
        #expect(state.lastDownloadedDate == nil)
        #expect(state.uploadedCount == 0)
        #expect(state.downloadedCount == 0)
    }
    
    @Test("Device status sync state encoding")
    func deviceStatusSyncStateEncoding() throws {
        var state = DeviceStatusSyncState()
        state.lastSyncDate = Date(timeIntervalSince1970: 1700000000)
        state.uploadedCount = 25
        state.downloadedCount = 10
        
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(DeviceStatusSyncState.self, from: data)
        
        #expect(decoded.lastSyncDate?.timeIntervalSince1970 == 1700000000)
        #expect(decoded.uploadedCount == 25)
        #expect(decoded.downloadedCount == 10)
    }
    
}

// MARK: - DeviceStatusSyncResult Tests

@Suite("DeviceStatusSyncResult Tests")
struct DeviceStatusSyncResultTests {
    
    @Test("Device status sync result success")
    func deviceStatusSyncResultSuccess() {
        let result = DeviceStatusSyncResult(uploaded: 5, downloaded: 3)
        
        #expect(result.success)
        #expect(result.uploaded == 5)
        #expect(result.downloaded == 3)
    }
    
    @Test("Device status sync result with errors")
    func deviceStatusSyncResultWithErrors() {
        let result = DeviceStatusSyncResult(errors: [NightscoutError.uploadFailed])
        
        #expect(!result.success)
        #expect(result.errors.count == 1)
    }
    
}

// MARK: - DeviceStatusSyncManager Factory Methods Tests

@Suite("DeviceStatusSyncManager Factory Methods Tests")
struct DeviceStatusSyncManagerFactoryMethodsTests {
    
    @Test("Loop status factory")
    func loopStatusFactory() {
        let status = DeviceStatusSyncManager.loopStatus(
            iob: 1.5,
            cob: 30,
            predictedBGs: [120, 115, 110, 105],
            tempBasalRate: 0.5,
            tempBasalDuration: 30,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            reservoir: 150.5,
            batteryPercent: 85,
            device: "t1pal-test"
        )
        
        #expect(status.device == "t1pal-test")
        #expect(status.loop != nil)
        #expect(status.loop?.iob?.iob == 1.5)
        #expect(status.loop?.cob?.cob == 30)
        #expect(status.loop?.predicted?.values?.count == 4)
        #expect(status.loop?.enacted?.rate == 0.5)
        #expect(status.pump?.reservoir == 150.5)
        #expect(status.pump?.battery?.percent == 85)
    }
    
    @Test("Open a p s status factory")
    func openAPSStatusFactory() {
        let predBGs = NightscoutDeviceStatus.OpenAPSStatus.SuggestedStatus.PredBGs(
            IOB: [120, 115, 110],
            COB: [125, 120, 115]
        )
        
        let status = DeviceStatusSyncManager.openapsStatus(
            bg: 120,
            iob: 2.0,
            cob: 30,
            tempBasalRate: 0.8,
            tempBasalDuration: 30,
            eventualBG: 110,
            reason: "COB: 30g, IOB: 2U",
            predBGs: predBGs,
            timestamp: Date(timeIntervalSince1970: 1700000000),
            reservoir: 150,
            batteryPercent: 80,
            device: "openaps-test"
        )
        
        #expect(status.device == "openaps-test")
        #expect(status.openaps != nil)
        #expect(status.openaps?.suggested?.bg == 120)
        #expect(status.openaps?.suggested?.IOB == 2.0)
        #expect(status.openaps?.suggested?.COB == 30)
        #expect(status.openaps?.suggested?.rate == 0.8)
        #expect(status.openaps?.suggested?.eventualBG == 110)
        #expect(status.openaps?.enacted?.rate == 0.8)
        #expect(status.pump?.reservoir == 150)
    }
    
}

// MARK: - Profile (NS-006) Tests

@Suite("Profile (NS-006) Tests")
struct ProfileTests {
    
    @Test("Profile query builds correctly")
    func profileQueryBuildsCorrectly() {
        let query = ProfileQuery(count: 5)
        let items = query.toQueryItems()
        
        #expect(items.count == 1)
        #expect(items[0].name == "count")
        #expect(items[0].value == "5")
    }
    
    @Test("Profile query with date range")
    func profileQueryWithDateRange() {
        let from = Date(timeIntervalSince1970: 1700000000)
        let to = Date(timeIntervalSince1970: 1700100000)
        let query = ProfileQuery(count: 10, dateFrom: from, dateTo: to)
        let items = query.toQueryItems()
        
        #expect(items.count == 3)
        #expect(items.contains { $0.name == "count" && $0.value == "10" })
        #expect(items.contains { $0.name == "find[startDate][$gte]" })
        #expect(items.contains { $0.name == "find[startDate][$lte]" })
    }
    
    @Test("Schedule entry decoding")
    func scheduleEntryDecoding() throws {
        let json = """
        {"time": "08:00", "timeAsSeconds": 28800, "value": 0.8}
        """.data(using: .utf8)!
        
        let entry = try JSONDecoder().decode(ScheduleEntry.self, from: json)
        
        #expect(entry.time == "08:00")
        #expect(entry.timeAsSeconds == 28800)
        #expect(entry.value == 0.8)
        #expect(entry.minutesFromMidnight == 480)
    }
    
    @Test("Schedule entry minutes calculation")
    func scheduleEntryMinutesCalculation() {
        let entry1 = ScheduleEntry(time: "08:30", timeAsSeconds: nil, value: 1.0)
        #expect(entry1.minutesFromMidnight == 510)
        
        let entry2 = ScheduleEntry(time: nil, timeAsSeconds: 43200, value: 1.5)
        #expect(entry2.minutesFromMidnight == 720)
    }
    
    @Test("Profile store decoding")
    func profileStoreDecoding() throws {
        let json = """
        {
            "dia": 5.0,
            "carbratio": [{"time": "00:00", "timeAsSeconds": 0, "value": 10}],
            "sens": [{"time": "00:00", "timeAsSeconds": 0, "value": 50}],
            "basal": [{"time": "00:00", "timeAsSeconds": 0, "value": 0.8}],
            "target_low": [{"time": "00:00", "timeAsSeconds": 0, "value": 100}],
            "target_high": [{"time": "00:00", "timeAsSeconds": 0, "value": 120}],
            "timezone": "America/New_York",
            "units": "mg/dL",
            "carbs_hr": 30
        }
        """.data(using: .utf8)!
        
        let store = try JSONDecoder().decode(ProfileStore.self, from: json)
        
        #expect(store.dia == 5.0)
        #expect(store.carbratio?.count == 1)
        #expect(store.carbratio?[0].value == 10)
        #expect(store.sens?.count == 1)
        #expect(store.sens?[0].value == 50)
        #expect(store.basal?.count == 1)
        #expect(store.basal?[0].value == 0.8)
        #expect(store.timezone == "America/New_York")
        #expect(store.units == "mg/dL")
        #expect(store.carbs_hr == 30)
    }
    
    @Test("Profile store total daily basal")
    func profileStoreTotalDailyBasal() {
        let store = ProfileStore(
            basal: [
                ScheduleEntry(timeAsSeconds: 0, value: 0.5),      // 0-6: 6hr * 0.5 = 3.0
                ScheduleEntry(timeAsSeconds: 21600, value: 1.0), // 6-12: 6hr * 1.0 = 6.0
                ScheduleEntry(timeAsSeconds: 43200, value: 0.8), // 12-18: 6hr * 0.8 = 4.8
                ScheduleEntry(timeAsSeconds: 64800, value: 0.6)  // 18-24: 6hr * 0.6 = 3.6
            ]
        )
        
        #expect(store.totalDailyBasal != nil)
        #expect(abs(store.totalDailyBasal! - 17.4) < 0.01)
    }
    
    @Test("Profile decoding")
    func profileDecoding() throws {
        let json = """
        {
            "_id": "abc123",
            "defaultProfile": "Default",
            "startDate": "2024-01-01T00:00:00.000Z",
            "mills": 1704067200000,
            "units": "mg/dL",
            "store": {
                "Default": {
                    "dia": 5.0,
                    "basal": [{"timeAsSeconds": 0, "value": 0.8}],
                    "carbratio": [{"timeAsSeconds": 0, "value": 10}],
                    "sens": [{"timeAsSeconds": 0, "value": 50}],
                    "timezone": "UTC"
                }
            },
            "created_at": "2024-01-01T00:00:00.000Z",
            "enteredBy": "test-device"
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        
        #expect(profile._id == "abc123")
        #expect(profile.defaultProfile == "Default")
        #expect(profile.mills == 1704067200000)
        #expect(profile.units == "mg/dL")
        #expect(profile.activeProfile != nil)
        #expect(profile.activeProfile?.dia == 5.0)
        #expect(profile.enteredBy == "test-device")
    }
    
    @Test("Profile timestamp")
    func profileTimestamp() {
        let profile = NightscoutProfile(
            defaultProfile: "test",
            startDate: "2024-01-01T00:00:00Z",
            mills: 1704067200000,
            store: [:]
        )
        
        #expect(profile.timestamp != nil)
        #expect(abs(profile.timestamp!.timeIntervalSince1970 - 1704067200) < 1)
    }
    
    @Test("Profile encoding")
    func profileEncoding() throws {
        let store = ProfileStore(
            dia: 5.0,
            carbratio: [ScheduleEntry(timeAsSeconds: 0, value: 10)],
            sens: [ScheduleEntry(timeAsSeconds: 0, value: 50)],
            basal: [ScheduleEntry(timeAsSeconds: 0, value: 0.8)],
            timezone: "UTC",
            units: "mg/dL"
        )
        
        let profile = NightscoutProfile(
            defaultProfile: "Default",
            startDate: "2024-01-01T00:00:00.000Z",
            mills: 1704067200000,
            units: "mg/dL",
            store: ["Default": store],
            enteredBy: "T1Pal"
        )
        
        let encoded = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(NightscoutProfile.self, from: encoded)
        
        #expect(decoded.defaultProfile == "Default")
        #expect(decoded.activeProfile?.dia == 5.0)
        #expect(decoded.activeProfile?.basal?.count == 1)
    }
    
    @Test("Profile sync state init")
    func profileSyncStateInit() {
        let state = ProfileSyncState()
        
        #expect(state.lastSyncDate == nil)
        #expect(state.lastUploadDate == nil)
        #expect(state.lastDownloadDate == nil)
        #expect(state.profileCount == 0)
    }
    
    @Test("Profile sync state encoding")
    func profileSyncStateEncoding() throws {
        let now = Date()
        let state = ProfileSyncState(
            lastSyncDate: now,
            lastUploadDate: now,
            lastDownloadDate: now,
            profileCount: 5
        )
        
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ProfileSyncState.self, from: encoded)
        
        #expect(decoded.profileCount == 5)
        #expect(decoded.lastSyncDate != nil)
    }
    
    @Test("Profile sync result init")
    func profileSyncResultInit() {
        let result = ProfileSyncResult(
            success: true,
            profiles: [],
            uploadedCount: 3,
            downloadedCount: 2,
            errors: []
        )
        
        #expect(result.success)
        #expect(result.uploadedCount == 3)
        #expect(result.downloadedCount == 2)
        #expect(result.errors.isEmpty)
    }
    
    @Test("Profile from settings factory")
    func profileFromSettingsFactory() {
        let profile = ProfileSyncManager.profileFromSettings(
            basalRates: [(0, 0.5), (21600, 0.8), (43200, 0.6)],
            carbRatios: [(0, 10), (43200, 12)],
            sensitivities: [(0, 50), (43200, 45)],
            targetLow: [(0, 100)],
            targetHigh: [(0, 120)],
            dia: 5.0,
            units: "mg/dL",
            timezone: "America/New_York",
            profileName: "T1Pal",
            enteredBy: "T1Pal"
        )
        
        #expect(profile.defaultProfile == "T1Pal")
        #expect(profile.units == "mg/dL")
        #expect(profile.enteredBy == "T1Pal")
        #expect(profile.activeProfile != nil)
        
        let store = profile.activeProfile!
        #expect(store.dia == 5.0)
        #expect(store.basal?.count == 3)
        #expect(store.basal?[0].value == 0.5)
        #expect(store.basal?[1].timeAsSeconds == 21600)
        #expect(store.carbratio?.count == 2)
        #expect(store.sens?.count == 2)
        #expect(store.target_low?.count == 1)
        #expect(store.target_high?.count == 1)
        #expect(store.timezone == "America/New_York")
    }
    
    @Test("Profile sync manager queue upload")
    func profileSyncManagerQueueUpload() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let manager = ProfileSyncManager(client: client)
        
        let profile = NightscoutProfile(
            defaultProfile: "test",
            startDate: "2024-01-01T00:00:00Z",
            store: [:]
        )
        
        await manager.queueUpload(profile)
        let state = await manager.getState()
        
        #expect(state.profileCount == 0)  // Not uploaded yet
    }
    
    @Test("Profile sync manager get state")
    func profileSyncManagerGetState() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let initialState = ProfileSyncState(profileCount: 3)
        let manager = ProfileSyncManager(client: client, initialState: initialState)
        
        let state = await manager.getState()
        
        #expect(state.profileCount == 3)
    }
    
    @Test("Multiple profile stores decoding")
    func multipleProfileStoresDecoding() throws {
        let json = """
        {
            "defaultProfile": "Day",
            "startDate": "2024-01-01T00:00:00Z",
            "store": {
                "Day": {"dia": 5.0, "basal": [{"timeAsSeconds": 0, "value": 0.8}]},
                "Night": {"dia": 5.0, "basal": [{"timeAsSeconds": 0, "value": 0.6}]},
                "Exercise": {"dia": 5.0, "basal": [{"timeAsSeconds": 0, "value": 0.4}]}
            }
        }
        """.data(using: .utf8)!
        
        let profile = try JSONDecoder().decode(NightscoutProfile.self, from: json)
        
        #expect(profile.store.count == 3)
        #expect(profile.activeProfile?.basal?[0].value == 0.8)
        #expect(profile.store["Night"]?.basal?[0].value == 0.6)
        #expect(profile.store["Exercise"]?.basal?[0].value == 0.4)
    }
    
    @Test("Profile hash equality")
    func profileHashEquality() {
        let profile1 = NightscoutProfile(
            defaultProfile: "Default",
            startDate: "2024-01-01T00:00:00Z",
            store: [:]
        )
        
        let profile2 = NightscoutProfile(
            _id: "different",
            defaultProfile: "Default",
            startDate: "2024-01-01T00:00:00Z",
            mills: 999999,
            store: ["test": ProfileStore()]
        )
        
        #expect(profile1 == profile2)  // Same startDate and defaultProfile
    }
    
}

// MARK: - WebSocket (NS-007) Tests

@Suite("WebSocket (NS-007) Tests")
struct WebSocketTests {
    
    @Test("Nightscout socket event decoding")
    func nightscoutSocketEventDecoding() {
        #expect(NightscoutSocketEvent(rawValue: "sgv") == .sgv)
        #expect(NightscoutSocketEvent(rawValue: "treatment") == .treatment)
        #expect(NightscoutSocketEvent(rawValue: "devicestatus") == .devicestatus)
        #expect(NightscoutSocketEvent(rawValue: "profileSwitch") == .profileSwitch)
        #expect(NightscoutSocketEvent(rawValue: "alarm") == .alarm)
        #expect(NightscoutSocketEvent(rawValue: "connect") == .connect)
        #expect(NightscoutSocketEvent(rawValue: "disconnect") == .disconnect)
        #expect(NightscoutSocketEvent(rawValue: "unknown_event") == nil)
    }
    
    @Test("Nightscout socket message init")
    func nightscoutSocketMessageInit() {
        let message = NightscoutSocketMessage(event: .sgv, data: nil)
        
        #expect(message.event == .sgv)
        #expect(message.data == nil)
        #expect(message.timestamp != nil)
    }
    
    @Test("Nightscout socket message parse entries")
    func nightscoutSocketMessageParseEntries() throws {
        let entriesJson = """
        [{"type":"sgv","sgv":120,"direction":"Flat","date":1700000000000,"dateString":"2023-11-14T22:13:20.000Z"}]
        """.data(using: .utf8)!
        
        let message = NightscoutSocketMessage(event: .sgv, data: entriesJson)
        let entries = try message.parseEntries()
        
        #expect(entries != nil)
        #expect(entries?.count == 1)
        #expect(entries?[0].sgv == 120)
    }
    
    @Test("Nightscout socket message parse treatments")
    func nightscoutSocketMessageParseTreatments() throws {
        let treatmentsJson = """
        [{"eventType":"Meal Bolus","insulin":2.5,"carbs":30,"created_at":"2024-01-01T12:00:00Z"}]
        """.data(using: .utf8)!
        
        let message = NightscoutSocketMessage(event: .treatment, data: treatmentsJson)
        let treatments = try message.parseTreatments()
        
        #expect(treatments != nil)
        #expect(treatments?.count == 1)
        #expect(treatments?[0].insulin == 2.5)
        #expect(treatments?[0].carbs == 30)
    }
    
    @Test("Nightscout socket message parse device status")
    func nightscoutSocketMessageParseDeviceStatus() throws {
        let statusJson = """
        [{"device":"loop","created_at":"2024-01-01T12:00:00Z"}]
        """.data(using: .utf8)!
        
        let message = NightscoutSocketMessage(event: .devicestatus, data: statusJson)
        let statuses = try message.parseDeviceStatus()
        
        #expect(statuses != nil)
        #expect(statuses?.count == 1)
        #expect(statuses?[0].device == "loop")
    }
    
    @Test("Nightscout socket message parse wrong event returns nil")
    func nightscoutSocketMessageParseWrongEventReturnsNil() throws {
        let entriesJson = """
        [{"type":"sgv","sgv":120}]
        """.data(using: .utf8)!
        
        let message = NightscoutSocketMessage(event: .treatment, data: entriesJson)  // Wrong event type
        let entries = try message.parseEntries()
        
        #expect(entries == nil)  // Should return nil because event is .treatment, not .sgv
    }
    
    @Test("Nightscout socket state equality")
    func nightscoutSocketStateEquality() {
        #expect(NightscoutSocketState.disconnected == NightscoutSocketState.disconnected)
        #expect(NightscoutSocketState.connected == NightscoutSocketState.connected)
        #expect(NightscoutSocketState.connecting == NightscoutSocketState.connecting)
        #expect(NightscoutSocketState.reconnecting(attempt: 1) == NightscoutSocketState.reconnecting(attempt: 1))
        #expect(NightscoutSocketState.reconnecting(attempt: 1) != NightscoutSocketState.reconnecting(attempt: 2))
    }
    
    @Test("Nightscout socket state is failed or reconnecting")
    func nightscoutSocketStateIsFailedOrReconnecting() {
        #expect(NightscoutSocketState.failed(reason: "test").isFailedOrReconnecting)
        #expect(NightscoutSocketState.reconnecting(attempt: 1).isFailedOrReconnecting)
        #expect(!NightscoutSocketState.connected.isFailedOrReconnecting)
        #expect(!NightscoutSocketState.disconnected.isFailedOrReconnecting)
    }
    
    @Test("Nightscout socket init")
    func nightscoutSocketInit() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let socket = NightscoutSocket(config: config)
        
        let state = await socket.getState()
        #expect(state == .disconnected)
    }
    
    @Test("Nightscout realtime coordinator init")
    func nightscoutRealtimeCoordinatorInit() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let socket = NightscoutSocket(config: config)
        let client = NightscoutClient(config: config)
        let entriesManager = EntriesSyncManager(client: client)
        
        let coordinator = NightscoutRealtimeCoordinator(
            socket: socket,
            entriesSyncManager: entriesManager
        )
        
        let isRunning = await coordinator.getIsRunning()
        #expect(!isRunning)
    }
    
    @Test("Entries sync manager queue download")
    func entriesSyncManagerQueueDownload() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let manager = EntriesSyncManager(client: client)
        
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            direction: "Flat",
            dateString: "2024-01-01T12:00:00Z",
            date: 1704110400000,
            device: "test"
        )
        
        await manager.queueDownload(entry)
        let state = await manager.syncState
        
        #expect(state.downloadedCount == 1)
    }
    
    @Test("Treatments sync manager queue download")
    func treatmentsSyncManagerQueueDownload() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let manager = TreatmentsSyncManager(client: client)
        
        let treatment = NightscoutTreatment(
            eventType: "Meal Bolus",
            created_at: "2024-01-01T12:00:00Z",
            insulin: 2.5,
            carbs: 30
        )
        
        await manager.queueDownload(treatment)
        let state = await manager.syncState
        
        #expect(state.downloadedCount == 1)
    }
    
    @Test("Device status sync manager queue download")
    func deviceStatusSyncManagerQueueDownload() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let manager = DeviceStatusSyncManager(client: client)
        
        let status = NightscoutDeviceStatus(
            device: "test",
            created_at: "2024-01-01T12:00:00Z"
        )
        
        await manager.queueDownload(status)
        let state = await manager.syncState
        
        #expect(state.downloadedCount == 1)
    }
    
}

// MARK: - Remote Commands (NS-008) Tests

@Suite("Remote Commands (NS-008) Tests")
struct RemoteCommandsTests {
    
    @Test("Remote command type requires o t p")
    func remoteCommandTypeRequiresOTP() {
        #expect(RemoteCommandType.tempTarget.requiresOTP)
        #expect(RemoteCommandType.cancelTempTarget.requiresOTP)
        #expect(RemoteCommandType.profileSwitch.requiresOTP)
        #expect(RemoteCommandType.openapsOffline.requiresOTP)
        
        #expect(!RemoteCommandType.announcement.requiresOTP)
        #expect(!RemoteCommandType.note.requiresOTP)
        #expect(!RemoteCommandType.bgCheck.requiresOTP)
        #expect(!RemoteCommandType.exercise.requiresOTP)
        #expect(!RemoteCommandType.pumpSiteChange.requiresOTP)
        #expect(!RemoteCommandType.cgmSensorInsert.requiresOTP)
    }
    
    @Test("Remote command type all cases")
    func remoteCommandTypeAllCases() {
        #expect(RemoteCommandType.allCases.count == 13)
    }
    
    @Test("Remote command init")
    func remoteCommandInit() {
        let command = RemoteCommand(
            commandType: .tempTarget,
            duration: 60,
            targetTop: 150,
            targetBottom: 120,
            reason: "Exercise",
            otp: "123456"
        )
        
        #expect(command.commandType == .tempTarget)
        #expect(command.duration == 60)
        #expect(command.targetTop == 150)
        #expect(command.targetBottom == 120)
        #expect(command.reason == "Exercise")
        #expect(command.otp == "123456")
        #expect(command.enteredBy == "T1Pal")
    }
    
    @Test("Remote command to treatment")
    func remoteCommandToTreatment() {
        let command = RemoteCommand(
            commandType: .tempTarget,
            duration: 60,
            targetTop: 150,
            targetBottom: 120,
            reason: "Exercise"
        )
        
        let treatment = command.toTreatment()
        
        #expect(treatment.eventType == "Temporary Target")
        #expect(treatment.duration == 60)
        #expect(treatment.targetTop == 150)
        #expect(treatment.targetBottom == 120)
        #expect(treatment.reason == "Exercise")
        #expect(treatment.enteredBy == "T1Pal")
    }
    
    @Test("Remote command result init")
    func remoteCommandResultInit() {
        let command = RemoteCommand(commandType: .note, notes: "Test")
        let result = RemoteCommandResult(success: true, command: command)
        
        #expect(result.success)
        #expect(result.command.commandType == .note)
        #expect(result.error == nil)
        #expect(!result.requiresOTP)
    }
    
    @Test("Remote command result with o t p required")
    func remoteCommandResultWithOTPRequired() {
        let command = RemoteCommand(commandType: .tempTarget)
        let result = RemoteCommandResult(
            success: false,
            command: command,
            error: RemoteCommandError.otpRequired,
            requiresOTP: true
        )
        
        #expect(!result.success)
        #expect(result.requiresOTP)
        #expect(result.error != nil)
    }
    
    @Test("Remote command manager init")
    func remoteCommandManagerInit() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let manager = RemoteCommandManager(client: client)
        
        let history = await manager.getHistory()
        let pending = await manager.getPendingCount()
        
        #expect(history.count == 0)
        #expect(pending == 0)
    }
    
    @Test("Remote command manager queue")
    func remoteCommandManagerQueue() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let manager = RemoteCommandManager(client: client)
        
        let command = RemoteCommand(commandType: .note, notes: "Test")
        await manager.queue(command)
        
        let pending = await manager.getPendingCount()
        #expect(pending == 1)
    }
    
    @Test("Remote command manager clear history")
    func remoteCommandManagerClearHistory() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let manager = RemoteCommandManager(client: client)
        
        await manager.clearHistory()
        let history = await manager.getHistory()
        
        #expect(history.count == 0)
    }
    
    @Test("Announcement command")
    func announcementCommand() {
        let command = RemoteCommand(
            commandType: .announcement,
            notes: "Important message",
            enteredBy: "Caregiver"
        )
        
        let treatment = command.toTreatment()
        
        #expect(treatment.eventType == "Announcement")
        #expect(treatment.notes == "Important message")
        #expect(treatment.enteredBy == "Caregiver")
    }
    
    @Test("B g check command")
    func bGCheckCommand() {
        let command = RemoteCommand(
            commandType: .bgCheck,
            glucose: 120,
            glucoseType: "Finger"
        )
        
        let treatment = command.toTreatment()
        
        #expect(treatment.eventType == "BG Check")
        #expect(treatment.glucose == 120)
        #expect(treatment.glucoseType == "Finger")
    }
    
    @Test("Profile switch command")
    func profileSwitchCommand() {
        let command = RemoteCommand(
            commandType: .profileSwitch,
            profile: "Exercise",
            otp: "654321"
        )
        
        #expect(command.commandType == .profileSwitch)
        #expect(command.profile == "Exercise")
        #expect(command.commandType.requiresOTP)
    }
    
    @Test("Exercise command")
    func exerciseCommand() {
        let command = RemoteCommand(
            commandType: .exercise,
            notes: "Running",
            duration: 45
        )
        
        let treatment = command.toTreatment()
        
        #expect(treatment.eventType == "Exercise")
        #expect(treatment.notes == "Running")
        #expect(treatment.duration == 45)
    }
    
    @Test("Site change command")
    func siteChangeCommand() {
        let command = RemoteCommand(
            commandType: .pumpSiteChange,
            notes: "Left abdomen"
        )
        
        let treatment = command.toTreatment()
        
        #expect(treatment.eventType == "Site Change")
        #expect(treatment.notes == "Left abdomen")
    }
    
    @Test("Sensor start command")
    func sensorStartCommand() {
        let command = RemoteCommand(
            commandType: .cgmSensorInsert,
            notes: "New G7 sensor"
        )
        
        let treatment = command.toTreatment()
        
        #expect(treatment.eventType == "Sensor Start")
        #expect(treatment.notes == "New G7 sensor")
    }
    
}

// MARK: - Offline Support (NS-009) Tests

@Suite("Offline Support (NS-009) Tests")
struct OfflineSupportTests {
    
    @Test("Network state equality")
    func networkStateEquality() {
        #expect(NetworkState.online == NetworkState.online)
        #expect(NetworkState.offline == NetworkState.offline)
        #expect(NetworkState.unknown == NetworkState.unknown)
        #expect(NetworkState.online != NetworkState.offline)
    }
    
    @Test("Offline operation type")
    func offlineOperationType() {
        #expect(OfflineOperationType.uploadEntry.rawValue == "uploadEntry")
        #expect(OfflineOperationType.uploadTreatment.rawValue == "uploadTreatment")
        #expect(OfflineOperationType.uploadDeviceStatus.rawValue == "uploadDeviceStatus")
        #expect(OfflineOperationType.uploadProfile.rawValue == "uploadProfile")
        #expect(OfflineOperationType.remoteCommand.rawValue == "remoteCommand")
    }
    
    @Test("Offline queue item init")
    func offlineQueueItemInit() {
        let item = OfflineQueueItem(
            operationType: .uploadEntry,
            payload: Data()
        )
        
        #expect(item.operationType == .uploadEntry)
        #expect(item.retryCount == 0)
        #expect(item.lastRetryAt == nil)
        #expect(item.error == nil)
    }
    
    @Test("Offline queue item encoding")
    func offlineQueueItemEncoding() throws {
        let item = OfflineQueueItem(
            operationType: .uploadTreatment,
            payload: "test".data(using: .utf8)!,
            retryCount: 2
        )
        
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(OfflineQueueItem.self, from: encoded)
        
        #expect(decoded.operationType == .uploadTreatment)
        #expect(decoded.retryCount == 2)
    }
    
    @Test("Offline queue result init")
    func offlineQueueResultInit() {
        let result = OfflineQueueResult(
            processed: 5,
            succeeded: 3,
            failed: 1,
            remaining: 1,
            errors: ["test error"]
        )
        
        #expect(result.processed == 5)
        #expect(result.succeeded == 3)
        #expect(result.failed == 1)
        #expect(result.remaining == 1)
        #expect(result.errors.count == 1)
    }
    
    @Test("Offline queue init")
    func offlineQueueInit() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        let size = await queue.getQueueSize()
        let state = await queue.getNetworkState()
        
        #expect(size == 0)
        #expect(state == .unknown)
    }
    
    @Test("Offline queue set network state")
    func offlineQueueSetNetworkState() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        await queue.setNetworkState(.online)
        var state = await queue.getNetworkState()
        #expect(state == .online)
        
        await queue.setNetworkState(.offline)
        state = await queue.getNetworkState()
        #expect(state == .offline)
    }
    
    @Test("Offline queue entry")
    func offlineQueueEntry() async throws {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            direction: "Flat",
            dateString: "2024-01-01T12:00:00Z",
            date: 1704110400000,
            device: "test"
        )
        
        try await queue.queueEntry(entry)
        let size = await queue.getQueueSize()
        
        #expect(size == 1)
    }
    
    @Test("Offline queue treatment")
    func offlineQueueTreatment() async throws {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        let treatment = NightscoutTreatment(
            eventType: "Note",
            created_at: "2024-01-01T12:00:00Z",
            notes: "Test note"
        )
        
        try await queue.queueTreatment(treatment)
        let size = await queue.getQueueSize()
        
        #expect(size == 1)
    }
    
    @Test("Offline queue device status")
    func offlineQueueDeviceStatus() async throws {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        let status = NightscoutDeviceStatus(
            device: "test",
            created_at: "2024-01-01T12:00:00Z"
        )
        
        try await queue.queueDeviceStatus(status)
        let size = await queue.getQueueSize()
        
        #expect(size == 1)
    }
    
    @Test("Offline queue clear")
    func offlineQueueClear() async throws {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            direction: "Flat",
            dateString: "2024-01-01T12:00:00Z",
            date: 1704110400000,
            device: "test"
        )
        
        try await queue.queueEntry(entry)
        try await queue.queueEntry(entry)
        var size = await queue.getQueueSize()
        #expect(size == 2)
        
        await queue.clearQueue()
        size = await queue.getQueueSize()
        #expect(size == 0)
    }
    
    @Test("Offline queue export import")
    func offlineQueueExportImport() async throws {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            direction: "Flat",
            dateString: "2024-01-01T12:00:00Z",
            date: 1704110400000,
            device: "test"
        )
        
        try await queue.queueEntry(entry)
        let exported = try await queue.exportQueue()
        
        await queue.clearQueue()
        var size = await queue.getQueueSize()
        #expect(size == 0)
        
        try await queue.importQueue(exported)
        size = await queue.getQueueSize()
        #expect(size == 1)
    }
    
    @Test("Offline queue process when offline")
    func offlineQueueProcessWhenOffline() async throws {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            direction: "Flat",
            dateString: "2024-01-01T12:00:00Z",
            date: 1704110400000,
            device: "test"
        )
        
        try await queue.queueEntry(entry)
        await queue.setNetworkState(.offline)
        
        let result = await queue.processQueue()
        
        #expect(result.processed == 0)
        #expect(result.remaining == 1)
    }
    
    @Test("Offline queue calculate retry delay")
    func offlineQueueCalculateRetryDelay() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client, baseRetryDelay: 5.0, maxRetryDelay: 300.0)
        
        let item0 = OfflineQueueItem(operationType: .uploadEntry, payload: Data(), retryCount: 0)
        let item1 = OfflineQueueItem(operationType: .uploadEntry, payload: Data(), retryCount: 1)
        let item2 = OfflineQueueItem(operationType: .uploadEntry, payload: Data(), retryCount: 2)
        let item10 = OfflineQueueItem(operationType: .uploadEntry, payload: Data(), retryCount: 10)
        
        let delay0 = await queue.calculateRetryDelay(for: item0)
        let delay1 = await queue.calculateRetryDelay(for: item1)
        let delay2 = await queue.calculateRetryDelay(for: item2)
        let delay10 = await queue.calculateRetryDelay(for: item10)
        
        #expect(delay0 == 5.0)   // 5 * 2^0 = 5
        #expect(delay1 == 10.0)  // 5 * 2^1 = 10
        #expect(delay2 == 20.0)  // 5 * 2^2 = 20
        #expect(delay10 == 300.0) // Capped at max
    }
    
    @Test("Offline queue remove item")
    func offlineQueueRemoveItem() async throws {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        
        let entry = NightscoutEntry(
            type: "sgv",
            sgv: 120,
            direction: "Flat",
            dateString: "2024-01-01T12:00:00Z",
            date: 1704110400000,
            device: "test"
        )
        
        try await queue.queueEntry(entry)
        let items = await queue.getQueueItems()
        #expect(items.count == 1)
        
        let itemId = items[0].id
        await queue.removeItem(itemId)
        
        let size = await queue.getQueueSize()
        #expect(size == 0)
    }
    
    @Test("Offline sync coordinator init")
    func offlineSyncCoordinatorInit() async {
        let config = NightscoutConfig(url: URL(string: "https://example.nightscout.io")!)
        let client = NightscoutClient(config: config)
        let queue = OfflineQueue(client: client)
        let coordinator = OfflineSyncCoordinator(offlineQueue: queue)
        
        let pending = await coordinator.getPendingCount()
        #expect(pending == 0)
    }
}

// Identity tests moved to NightscoutIdentityTests.swift (CODE-028)

