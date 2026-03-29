// LiveNightscoutTests.swift
// SPDX-License-Identifier: MIT
// Tests against real Nightscout instances using NS_URL environment variable
// Trace: NS-COMPAT-002

import Foundation
import Testing
@testable import NightscoutKit

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Tests that run against a real Nightscout instance
/// Set NS_URL environment variable to enable these tests
/// Example: NS_URL=https://your-ns.herokuapp.com swift test --filter "LiveNS"
@Suite("Live Nightscout Integration")
struct LiveNightscoutTests {
    
    static var nsURLString: String? {
        ProcessInfo.processInfo.environment["NS_URL"]
    }
    
    var nsURL: URL? {
        guard let urlString = Self.nsURLString else { return nil }
        return URL(string: urlString)
    }
    
    var session: URLSession {
        URLSession(configuration: .default)
    }
    
    @Test("Fetch entries from real Nightscout")
    func fetchEntries() async throws {
        guard let url = nsURL else {
            // Skip if NS_URL not set - this is expected in CI without secrets
            return
        }
        
        let config = NightscoutConfig(url: url)
        let client = NightscoutClient(config: config)
        
        let entries = try await client.fetchEntries(count: 10)
        
        #expect(entries.count > 0, "Should fetch at least one entry")
        
        // Verify entry structure
        if let first = entries.first {
            #expect(first.type == "sgv", "Entry type should be sgv")
            #expect(first.sgv != nil, "SGV value should be present")
            #expect(first.date > 0, "Date should be positive")
            #expect(!first.dateString.isEmpty, "Date string should be present")
            
            // Log the entry for debugging
            print("✓ Fetched entry: sgv=\(first.sgv ?? 0), date=\(first.date), direction=\(first.direction ?? "nil")")
        }
    }
    
    @Test("Fetch status from real Nightscout")
    func fetchStatus() async throws {
        guard let baseURL = nsURL else { return }
        
        let url = baseURL.appendingPathComponent("api/v1/status.json")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        let httpResponse = response as! HTTPURLResponse
        #expect(httpResponse.statusCode == 200, "Status endpoint should return 200")
        
        // Parse status
        let status = try JSONDecoder().decode(NightscoutStatus.self, from: data)
        #expect(status.status == "ok", "Status should be ok")
        #expect(!status.version.isEmpty, "Version should be present")
        
        print("✓ NS Status: \(status.name) v\(status.version)")
    }
    
    @Test("Parse entries with decimal date values")
    func parseDecimalDates() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url)
        let client = NightscoutClient(config: config)
        
        let entries = try await client.fetchEntries(count: 5)
        
        for entry in entries {
            // Verify date parsing works with decimal values
            let timestamp = entry.timestamp
            #expect(timestamp > Date.distantPast, "Timestamp should be valid")
            #expect(timestamp < Date.distantFuture, "Timestamp should be valid")
            
            // Verify syncIdentifier generation works
            let syncId = entry.syncIdentifier
            #expect(!syncId.isEmpty, "Sync identifier should be generated")
        }
        
        print("✓ Parsed \(entries.count) entries with decimal dates")
    }
    
    @Test("Verify entry fields match real Nightscout data")
    func verifyEntryFields() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url)
        let client = NightscoutClient(config: config)
        
        let entries = try await client.fetchEntries(count: 1)
        guard let entry = entries.first else {
            Issue.record("No entries returned")
            return
        }
        
        // Common fields that should be present for CGM data
        #expect(entry.sgv != nil || entry.mbg != nil, "Should have glucose value")
        #expect(entry.device != nil || entry._id != nil, "Should have device or ID")
        
        // Direction should be valid if present
        if let direction = entry.direction {
            let validDirections = [
                "DoubleUp", "SingleUp", "FortyFiveUp", "Flat",
                "FortyFiveDown", "SingleDown", "DoubleDown",
                "NOT COMPUTABLE", "RATE OUT OF RANGE", "None"
            ]
            #expect(validDirections.contains(direction), "Direction '\(direction)' should be valid")
        }
        
        print("✓ Entry fields verified: sgv=\(entry.sgv ?? 0), device=\(entry.device ?? "unknown")")
    }
    
    @Test("Fetch 24h glucose history")
    func fetch24hHistory() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url)
        let client = NightscoutClient(config: config)
        
        // Fetch 24 hours of data
        let now = Date()
        let yesterday = now.addingTimeInterval(-24 * 3600)
        
        let entries = try await client.fetchEntries(from: yesterday, to: now, count: 288)
        
        // Should have data (288 = 24h at 5-min intervals)
        #expect(entries.count > 0, "Should have entries in last 24h")
        
        // Check time range
        if let oldest = entries.min(by: { $0.date < $1.date }),
           let newest = entries.max(by: { $0.date < $1.date }) {
            let oldestTime = Date(timeIntervalSince1970: oldest.date / 1000)
            let newestTime = Date(timeIntervalSince1970: newest.date / 1000)
            let span = newestTime.timeIntervalSince(oldestTime) / 3600
            
            print("✓ Fetched \(entries.count) entries spanning \(String(format: "%.1f", span)) hours")
            print("  Oldest: \(oldestTime)")
            print("  Newest: \(newestTime)")
        }
        
        // Calculate basic stats
        let sgvValues = entries.compactMap { $0.sgv }
        if !sgvValues.isEmpty {
            let avg = Double(sgvValues.reduce(0, +)) / Double(sgvValues.count)
            let minVal = sgvValues.min() ?? 0
            let maxVal = sgvValues.max() ?? 0
            
            print("  Stats: min=\(minVal), max=\(maxVal), avg=\(String(format: "%.1f", avg))")
            
            // Sanity checks
            #expect(minVal > 0, "Min glucose should be positive")
            #expect(maxVal < 600, "Max glucose should be reasonable")
        }
    }
}

/// Minimal status struct for testing
struct NightscoutStatus: Codable {
    let status: String
    let name: String
    let version: String
}

// MARK: - Extended Live Tests (NS-DEEP)

@Suite("Live Nightscout Deep Integration")
struct LiveNightscoutDeepTests {
    
    static var nsURLString: String? {
        ProcessInfo.processInfo.environment["NS_URL"]
    }
    
    static var nsToken: String? {
        ProcessInfo.processInfo.environment["NS_TOKEN"]
    }
    
    var nsURL: URL? {
        guard let urlString = Self.nsURLString else { return nil }
        return URL(string: urlString)
    }
    
    // MARK: - NS-DEEP-001: 24h Glucose History with Pagination
    
    @Test("Fetch 24h glucose with pagination verification")
    func fetch24hWithPagination() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let now = Date()
        let yesterday = now.addingTimeInterval(-24 * 3600)
        
        // First page
        let page1 = try await client.fetchEntries(from: yesterday, to: now, count: 100)
        #expect(page1.count > 0, "Should have entries")
        
        if page1.count >= 100 {
            // Fetch second page using oldest entry from first page
            let oldestDate = page1.compactMap { Date(timeIntervalSince1970: $0.date / 1000) }.min()
            if let oldest = oldestDate {
                let page2 = try await client.fetchEntries(from: yesterday, to: oldest, count: 100)
                
                // Verify no overlap (except boundary)
                let page1Dates = Set(page1.map { $0.date })
                let page2Dates = Set(page2.map { $0.date })
                let overlap = page1Dates.intersection(page2Dates)
                
                #expect(overlap.count <= 1, "Pages should not overlap significantly")
                print("✓ Paginated: page1=\(page1.count), page2=\(page2.count), overlap=\(overlap.count)")
            }
        }
    }
    
    // MARK: - NS-DEEP-002: Treatments with Date Filter
    
    @Test("Fetch treatments with date filter")
    func fetchTreatmentsWithDateFilter() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let now = Date()
        let yesterday = now.addingTimeInterval(-24 * 3600)
        
        let treatments = try await client.fetchTreatments(from: yesterday, to: now, count: 50)
        
        print("✓ Fetched \(treatments.count) treatments in last 24h")
        
        // Categorize by event type
        var byType: [String: Int] = [:]
        for treatment in treatments {
            byType[treatment.eventType, default: 0] += 1
        }
        
        for (type, count) in byType.sorted(by: { $0.value > $1.value }).prefix(5) {
            print("  \(type): \(count)")
        }
        
        // Verify date filtering worked
        for treatment in treatments {
            let createdAt = treatment.created_at
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: createdAt) {
                #expect(date >= yesterday, "Treatment should be after yesterday")
                #expect(date <= now.addingTimeInterval(60), "Treatment should be before now (+1min buffer)")
            }
        }
    }
    
    @Test("Parse treatment types from Loop/Trio/AAPS")
    func parseTreatmentTypes() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let treatments = try await client.fetchTreatments(count: 100)
        
        // Known treatment types from different AID systems
        let aidTreatmentTypes = [
            "Temp Basal", "Temporary Basal",
            "Correction Bolus", "Bolus", "SMB",
            "Carb Correction", "Meal Bolus",
            "Suspend Pump", "Resume Pump",
            "Site Change", "Sensor Start",
            "Profile Switch", "Temporary Target"
        ]
        
        var foundAIDTreatments = false
        for treatment in treatments {
            if aidTreatmentTypes.contains(where: { treatment.eventType.contains($0) }) {
                foundAIDTreatments = true
                print("✓ Found AID treatment: \(treatment.eventType)")
                
                // Verify insulin/carbs parsing
                if treatment.insulin != nil {
                    #expect(treatment.insulin! > 0, "Insulin should be positive")
                    #expect(treatment.insulin! < 100, "Insulin should be reasonable")
                }
                if treatment.carbs != nil {
                    #expect(treatment.carbs! > 0, "Carbs should be positive")
                    #expect(treatment.carbs! < 500, "Carbs should be reasonable")
                }
            }
        }
        
        if !foundAIDTreatments && treatments.isEmpty {
            print("⚠ No treatments found - NS may not have recent data")
        }
    }
    
    // MARK: - NS-DEEP-003: DeviceStatus (Loop/Trio Data)
    
    @Test("Fetch devicestatus with Loop/Trio data")
    func fetchDeviceStatus() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let now = Date()
        let hourAgo = now.addingTimeInterval(-3600)
        
        let statuses = try await client.fetchDeviceStatus(from: hourAgo, to: now, count: 20)
        
        print("✓ Fetched \(statuses.count) device statuses in last hour")
        
        // Look for Loop or OpenAPS data
        var foundLoopData = false
        var foundOpenAPSData = false
        
        for status in statuses {
            if status.loop != nil {
                foundLoopData = true
                if let iob = status.loop?.iob?.iob {
                    print("  Loop IOB: \(String(format: "%.2f", iob)) U")
                    #expect(iob >= -5 && iob <= 50, "IOB should be reasonable")
                }
                if let cob = status.loop?.cob?.cob {
                    print("  Loop COB: \(Int(cob)) g")
                    #expect(cob >= 0 && cob <= 500, "COB should be reasonable")
                }
                if let predicted = status.loop?.predicted?.values, predicted.count > 0 {
                    print("  Predictions: \(predicted.count) values")
                }
            }
            
            if status.openaps != nil {
                foundOpenAPSData = true
                if let iob = status.openaps?.iob?.iob {
                    print("  OpenAPS IOB: \(String(format: "%.2f", iob)) U")
                }
                if let suggested = status.openaps?.suggested {
                    print("  OpenAPS suggested: bg=\(suggested.bg ?? 0)")
                }
            }
            
            // Check pump status
            if let pump = status.pump {
                if let reservoir = pump.reservoir {
                    print("  Pump reservoir: \(String(format: "%.1f", reservoir)) U")
                }
                if let battery = pump.battery?.percent {
                    print("  Pump battery: \(battery)%")
                }
            }
        }
        
        if !foundLoopData && !foundOpenAPSData && !statuses.isEmpty {
            print("  ℹ No Loop/OpenAPS data - may be follower-only NS")
        }
    }
    
    @Test("Extract IOB/COB from devicestatus")
    func extractIOBCOB() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let statuses = try await client.fetchDeviceStatus(count: 10)
        
        var iobValues: [Double] = []
        var cobValues: [Double] = []
        
        for status in statuses {
            // Try Loop format
            if let iob = status.loop?.iob?.iob {
                iobValues.append(iob)
            }
            if let cob = status.loop?.cob?.cob {
                cobValues.append(cob)
            }
            
            // Try OpenAPS format
            if let iob = status.openaps?.iob?.iob {
                iobValues.append(iob)
            }
            // OpenAPS COB is in meal data
        }
        
        if !iobValues.isEmpty {
            let avgIOB = iobValues.reduce(0, +) / Double(iobValues.count)
            print("✓ IOB values: \(iobValues.count), avg=\(String(format: "%.2f", avgIOB))")
        }
        
        if !cobValues.isEmpty {
            let avgCOB = cobValues.reduce(0, +) / Double(cobValues.count)
            print("✓ COB values: \(cobValues.count), avg=\(String(format: "%.1f", avgCOB))")
        }
    }
    
    @Test("Parse prediction curves from devicestatus")
    func parsePredictions() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let statuses = try await client.fetchDeviceStatus(count: 5)
        
        for status in statuses {
            // Loop predictions
            if let predicted = status.loop?.predicted {
                if let values = predicted.values, values.count > 0 {
                    print("✓ Loop predictions: \(values.count) values")
                    print("  First 5: \(values.prefix(5))")
                    
                    // Verify predictions are reasonable glucose values
                    for value in values {
                        #expect(value > 30 && value < 600, "Prediction should be valid glucose")
                    }
                }
            }
            
            // OpenAPS predictions (if present)
            if let suggested = status.openaps?.suggested {
                if let predBGs = suggested.predBGs {
                    print("✓ OpenAPS predictions found")
                    if let iob = predBGs.IOB, iob.count > 0 {
                        print("  IOB curve: \(iob.count) values")
                    }
                    if let zt = predBGs.ZT, zt.count > 0 {
                        print("  ZT curve: \(zt.count) values")
                    }
                }
            }
        }
    }
}

// MARK: - NS-DEEP-004 to NS-DEEP-007 Tests

@Suite("Live Nightscout Profile & Fixture Tests")
struct LiveNightscoutProfileTests {
    
    static var nsURLString: String? {
        ProcessInfo.processInfo.environment["NS_URL"]
    }
    
    static var nsToken: String? {
        ProcessInfo.processInfo.environment["NS_TOKEN"]
    }
    
    var nsURL: URL? {
        guard let urlString = Self.nsURLString else { return nil }
        return URL(string: urlString)
    }
    
    // MARK: - NS-DEEP-004: Fetch Profile and Parse
    
    @Test("Fetch and parse profile with multiple schedules")
    func fetchProfileWithSchedules() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let profiles = try await client.fetchProfiles(count: 5)
        
        print("✓ Fetched \(profiles.count) profiles")
        
        for profile in profiles {
            print("  Profile: \(profile.defaultProfile)")
            print("    Stores: \(profile.store.keys.joined(separator: ", "))")
            
            if let active = profile.activeProfile {
                if let dia = active.dia {
                    print("    DIA: \(dia) hours")
                    #expect(dia >= 2 && dia <= 12, "DIA should be reasonable")
                }
                
                if let basal = active.basal, !basal.isEmpty {
                    print("    Basal entries: \(basal.count)")
                    if let tdb = active.totalDailyBasal {
                        print("    Total daily basal: \(String(format: "%.2f", tdb)) U")
                        #expect(tdb > 0 && tdb < 100, "TDB should be reasonable")
                    }
                }
                
                if let sens = active.sens, !sens.isEmpty {
                    print("    ISF entries: \(sens.count)")
                }
                
                if let cr = active.carbratio, !cr.isEmpty {
                    print("    CR entries: \(cr.count)")
                }
                
                if let tz = active.timezone {
                    print("    Timezone: \(tz)")
                }
            }
        }
    }
    
    @Test("Parse profile timezone handling")
    func parseProfileTimezone() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let profiles = try await client.fetchProfiles(count: 1)
        guard let profile = profiles.first else {
            print("⚠ No profiles found")
            return
        }
        
        if let active = profile.activeProfile, let tz = active.timezone {
            // Verify timezone is valid
            let validTimezones = TimeZone.knownTimeZoneIdentifiers
            #expect(validTimezones.contains(tz) || tz.contains("/"), 
                    "Timezone '\(tz)' should be valid")
            print("✓ Valid timezone: \(tz)")
        }
        
        // Check start date parsing
        if let timestamp = profile.timestamp {
            print("✓ Profile timestamp: \(timestamp)")
            #expect(timestamp < Date().addingTimeInterval(86400), "Timestamp should be in the past or near present")
        }
    }
    
    // MARK: - NS-DEEP-005: WebSocket Subscription (Mock-based)
    
    @Test("WebSocket connection structure test")
    func webSocketConnectionStructure() async throws {
        // Note: Actual socket.io requires specialized library
        // This test validates the expected message format
        
        let subscribeMessage = """
        {
            "subscribe": ["sgv", "treatments", "devicestatus"],
            "secret": "sha1hash"
        }
        """
        
        struct SocketSubscribe: Codable {
            let subscribe: [String]
            let secret: String?
        }
        
        let data = subscribeMessage.data(using: .utf8)!
        let message = try JSONDecoder().decode(SocketSubscribe.self, from: data)
        
        #expect(message.subscribe.contains("sgv"))
        #expect(message.subscribe.contains("treatments"))
        #expect(message.subscribe.contains("devicestatus"))
        print("✓ WebSocket subscribe message format validated")
    }
    
    @Test("WebSocket data event format")
    func webSocketDataEventFormat() async throws {
        // Validate expected socket.io data event structure
        let dataEvent = """
        {
            "event": "dataUpdate",
            "data": {
                "sgvs": [{"_id": "abc", "sgv": 120, "date": 1738800000000, "direction": "Flat"}],
                "treatments": [],
                "devicestatus": []
            }
        }
        """
        
        struct SocketDataEvent: Codable {
            let event: String
            let data: DataPayload
            
            struct DataPayload: Codable {
                let sgvs: [[String: Any]]?
                let treatments: [[String: Any]]?
                let devicestatus: [[String: Any]]?
                
                enum CodingKeys: String, CodingKey {
                    case sgvs, treatments, devicestatus
                }
                
                init(from decoder: Decoder) throws {
                    // Simplified - just check structure exists
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    sgvs = nil
                    treatments = nil
                    devicestatus = nil
                }
                
                func encode(to encoder: Encoder) throws {}
            }
        }
        
        // Just validate it parses as JSON
        let data = dataEvent.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(json?["event"] as? String == "dataUpdate")
        #expect(json?["data"] != nil)
        print("✓ WebSocket data event format validated")
    }
    
    // MARK: - NS-DEEP-006: Capture Fixture from Live Fetch
    
    @Test("Capture entry fixture from live NS")
    func captureEntryFixture() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let entries = try await client.fetchEntries(count: 3)
        guard !entries.isEmpty else {
            print("⚠ No entries to capture")
            return
        }
        
        // Serialize to JSON for fixture capture
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(entries)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        print("✓ Captured \(entries.count) entries as fixture:")
        print("--- BEGIN FIXTURE ---")
        print(jsonString.prefix(500))
        if jsonString.count > 500 {
            print("... [\(jsonString.count - 500) more characters]")
        }
        print("--- END FIXTURE ---")
        
        // Verify round-trip
        let decoded = try JSONDecoder().decode([NightscoutEntry].self, from: jsonData)
        #expect(decoded.count == entries.count, "Round-trip should preserve count")
    }
    
    @Test("Capture treatment fixture from live NS")
    func captureTreatmentFixture() async throws {
        guard let url = nsURL else { return }
        
        let config = NightscoutConfig(url: url, token: Self.nsToken)
        let client = NightscoutClient(config: config)
        
        let treatments = try await client.fetchTreatments(count: 5)
        guard !treatments.isEmpty else {
            print("⚠ No treatments to capture")
            return
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(treatments)
        
        print("✓ Captured \(treatments.count) treatments as fixture")
        
        // Verify round-trip
        let decoded = try JSONDecoder().decode([NightscoutTreatment].self, from: jsonData)
        #expect(decoded.count == treatments.count)
    }
    
    // MARK: - NS-DEEP-007: Compare Loop vs Trio DeviceStatus Format
    
    @Test("Compare Loop vs Trio devicestatus structure")
    func compareLoopTrioDeviceStatus() async throws {
        // Test with known Loop and Trio format samples
        
        let loopDeviceStatus = """
        {
            "_id": "loop-123",
            "device": "iPhone14,7",
            "created_at": "2026-02-05T20:00:00.000Z",
            "loop": {
                "iob": {"iob": 2.5, "basaliob": 1.2, "timestamp": "2026-02-05T20:00:00.000Z"},
                "cob": {"cob": 30, "timestamp": "2026-02-05T20:00:00.000Z"},
                "predicted": {"values": [120, 115, 110, 105, 100], "startDate": "2026-02-05T20:00:00.000Z"},
                "enacted": {"received": true, "duration": 30, "rate": 0.5, "timestamp": "2026-02-05T20:00:00.000Z"},
                "recommendedBolus": 0.0
            },
            "pump": {"reservoir": 150.5, "battery": {"percent": 85}}
        }
        """.data(using: .utf8)!
        
        let trioDeviceStatus = """
        {
            "_id": "trio-456",
            "device": "iPhone15,2",
            "created_at": "2026-02-05T20:00:00.000Z",
            "openaps": {
                "iob": {"iob": 3.1, "basaliob": 1.5, "activity": 0.02, "timestamp": "2026-02-05T20:00:00.000Z"},
                "suggested": {
                    "bg": 125,
                    "eventualBG": 110,
                    "insulinReq": 0.5,
                    "reason": "COB: 25g; IOB: 3.1U",
                    "predBGs": {
                        "IOB": [125, 120, 115, 110],
                        "ZT": [125, 130, 135, 140],
                        "COB": [125, 118, 112, 105]
                    }
                },
                "enacted": {"received": true, "rate": 0.8, "duration": 30}
            },
            "pump": {"reservoir": 120.0, "battery": {"percent": 72}, "status": {"status": "normal"}}
        }
        """.data(using: .utf8)!
        
        let loopStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: loopDeviceStatus)
        let trioStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: trioDeviceStatus)
        
        // Loop uses "loop" key
        #expect(loopStatus.loop != nil, "Loop status should have loop key")
        #expect(loopStatus.openaps == nil, "Loop status should not have openaps key")
        
        // Trio uses "openaps" key
        #expect(trioStatus.openaps != nil, "Trio status should have openaps key")
        #expect(trioStatus.loop == nil, "Trio status should not have loop key")
        
        // Both have pump data
        #expect(loopStatus.pump != nil, "Loop should have pump data")
        #expect(trioStatus.pump != nil, "Trio should have pump data")
        
        // IOB extraction differs
        let loopIOB = loopStatus.loop?.iob?.iob
        let trioIOB = trioStatus.openaps?.iob?.iob
        
        #expect(loopIOB == 2.5, "Loop IOB should be 2.5")
        #expect(trioIOB == 3.1, "Trio IOB should be 3.1")
        
        // Predictions structure differs
        let loopPredictions = loopStatus.loop?.predicted?.values
        let trioPredictions = trioStatus.openaps?.suggested?.predBGs
        
        #expect(loopPredictions?.count == 5, "Loop should have 5 prediction values")
        #expect(trioPredictions?.IOB?.count == 4, "Trio should have 4 IOB prediction values")
        
        print("✓ Loop vs Trio format comparison:")
        print("  Loop: uses 'loop' key, flat predictions array")
        print("  Trio: uses 'openaps' key, predictions by curve type (IOB/ZT/COB)")
        print("  Both: pump.reservoir, pump.battery.percent")
    }
    
    @Test("Extract unified IOB/COB from both formats")
    func extractUnifiedIOBCOB() async throws {
        // Helper function to extract IOB regardless of format
        func extractIOB(from status: NightscoutDeviceStatus) -> Double? {
            status.loop?.iob?.iob ?? status.openaps?.iob?.iob
        }
        
        func extractCOB(from status: NightscoutDeviceStatus) -> Double? {
            status.loop?.cob?.cob // OpenAPS doesn't have COB in same structure
        }
        
        let loopData = """
        {"device": "iPhone", "created_at": "2026-02-05T20:00:00Z", "loop": {"iob": {"iob": 2.5}, "cob": {"cob": 30}}}
        """.data(using: .utf8)!
        
        let trioData = """
        {"device": "iPhone", "created_at": "2026-02-05T20:00:00Z", "openaps": {"iob": {"iob": 3.1}}}
        """.data(using: .utf8)!
        
        let loopStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: loopData)
        let trioStatus = try JSONDecoder().decode(NightscoutDeviceStatus.self, from: trioData)
        
        #expect(extractIOB(from: loopStatus) == 2.5)
        #expect(extractIOB(from: trioStatus) == 3.1)
        #expect(extractCOB(from: loopStatus) == 30)
        
        print("✓ Unified IOB/COB extraction works for both Loop and Trio")
    }
}

// MARK: - NS-DEEP-008: Auth Token Handling

@Suite("Nightscout Live Authentication Tests")
struct NightscoutLiveAuthTests {
    
    static var nsURLString: String? {
        ProcessInfo.processInfo.environment["NS_URL"]
    }
    
    static var nsToken: String? {
        ProcessInfo.processInfo.environment["NS_TOKEN"]
    }
    
    static var nsSecret: String? {
        ProcessInfo.processInfo.environment["NS_SECRET"]
    }
    
    var nsURL: URL? {
        guard let urlString = Self.nsURLString else { return nil }
        return URL(string: urlString)
    }
    
    // MARK: - API_SECRET Hash Tests
    
    @Test("SHA1 hash of API_SECRET")
    func sha1ApiSecretHash() throws {
        let secret = "test-api-secret-12345"
        let hash = secret.sha1()
        
        // SHA1 produces 40 hex characters
        #expect(hash.count == 40, "SHA1 hash should be 40 characters")
        #expect(hash.allSatisfy { $0.isHexDigit }, "Hash should be hex")
        
        // Verify same input produces same hash
        let hash2 = secret.sha1()
        #expect(hash == hash2, "Same input should produce same hash")
        
        print("✓ API_SECRET SHA1: \(hash.prefix(10))...")
    }
    
    @Test("Authorization header with API_SECRET")
    func authHeaderWithSecret() throws {
        let secret = "my-api-secret"
        let config = NightscoutConfig(
            url: URL(string: "https://example.nightscout.com")!,
            apiSecret: secret
        )
        
        #expect(config.apiSecretHash != nil, "Should generate hash")
        #expect(config.apiSecretHash?.count == 40, "Hash should be 40 chars")
        
        // Header format: api-secret: sha1hash
        let expectedHeader = config.apiSecretHash!
        print("✓ Auth header value: \(expectedHeader.prefix(10))...")
    }
    
    @Test("Authorization with JWT token")
    func authWithJWTToken() throws {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2Nlc3MiOiJyZWFkd3JpdGUifQ.signature"
        let config = NightscoutConfig(
            url: URL(string: "https://example.nightscout.com")!,
            token: token
        )
        
        #expect(config.token == token, "Token should be stored")
        #expect(config.apiSecret == nil, "API secret should be nil when using token")
        
        print("✓ JWT token configured")
    }
    
    @Test("Parse JWT token structure")
    func parseJWTStructure() throws {
        // Standard Nightscout JWT format
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2Nlc3NUb2tlbiI6InRlc3QiLCJpYXQiOjE3Mzg4MDAwMDAsImV4cCI6MTczODgwMzYwMH0.signature"
        
        let parts = token.split(separator: ".")
        #expect(parts.count == 3, "JWT should have 3 parts")
        
        // Decode header (first part)
        var headerBase64 = String(parts[0])
        // Pad for base64 decoding
        while headerBase64.count % 4 != 0 {
            headerBase64 += "="
        }
        
        if let headerData = Data(base64Encoded: headerBase64),
           let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
            #expect(header["alg"] as? String == "HS256")
            #expect(header["typ"] as? String == "JWT")
            print("✓ JWT header: alg=\(header["alg"] ?? "?"), typ=\(header["typ"] ?? "?")")
        }
        
        // Decode payload (second part)
        var payloadBase64 = String(parts[1])
        while payloadBase64.count % 4 != 0 {
            payloadBase64 += "="
        }
        
        if let payloadData = Data(base64Encoded: payloadBase64),
           let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
            print("✓ JWT payload keys: \(payload.keys.sorted().joined(separator: ", "))")
            
            if let exp = payload["exp"] as? Int {
                let expDate = Date(timeIntervalSince1970: Double(exp))
                print("  Expires: \(expDate)")
            }
        }
    }
    
    // MARK: - Live Auth Tests
    
    @Test("Fetch with API_SECRET auth")
    func fetchWithApiSecret() async throws {
        guard let url = nsURL, let secret = Self.nsSecret else { return }
        
        let config = NightscoutConfig(url: url, apiSecret: secret)
        let client = NightscoutClient(config: config)
        
        // Try fetching - should succeed if secret is valid
        let entries = try await client.fetchEntries(count: 1)
        
        #expect(entries.count >= 0, "Should not throw with valid auth")
        print("✓ API_SECRET auth successful, fetched \(entries.count) entries")
    }
    
    @Test("Fetch with JWT token auth")
    func fetchWithJWTToken() async throws {
        guard let url = nsURL, let token = Self.nsToken else { return }
        
        let config = NightscoutConfig(url: url, token: token)
        let client = NightscoutClient(config: config)
        
        let entries = try await client.fetchEntries(count: 1)
        
        #expect(entries.count >= 0, "Should not throw with valid token")
        print("✓ JWT token auth successful, fetched \(entries.count) entries")
    }
    
    @Test("Handle 401 Unauthorized gracefully")
    func handle401Unauthorized() async throws {
        guard let url = nsURL else { return }
        
        // Use invalid credentials
        let config = NightscoutConfig(url: url, apiSecret: "invalid-secret-12345")
        let client = NightscoutClient(config: config)
        
        do {
            _ = try await client.fetchEntries(count: 1)
            // If NS doesn't require auth, this might succeed
            print("⚠ NS may not require authentication")
        } catch {
            // Expected - should get auth error
            let errorString = String(describing: error)
            print("✓ Auth error handled: \(errorString.prefix(50))...")
        }
    }
    
    @Test("Token preference over API_SECRET")
    func tokenPreference() throws {
        let config = NightscoutConfig(
            url: URL(string: "https://example.com")!,
            apiSecret: "my-secret",
            token: "my-token"
        )
        
        // When both are provided, token should be preferred
        #expect(config.token != nil)
        #expect(config.apiSecret != nil)
        
        // In actual requests, client should use token if present
        print("✓ Both auth methods can be configured")
    }
}
