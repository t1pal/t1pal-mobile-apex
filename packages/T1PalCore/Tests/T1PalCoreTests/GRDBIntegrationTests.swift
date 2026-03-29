// GRDBIntegrationTests.swift - Integration tests for all GRDB stores at scale
// Trace: BENCH-IMPL-006
// NOTE: GRDB tests only run on Darwin (iOS/macOS) due to SQLite snapshot limitation

#if canImport(Darwin)
import Foundation
import Testing
@testable import T1PalCore
import CoreFoundation

// MARK: - Test Data Generators

enum IntegrationTestData {
    /// Generate N device status records with realistic values.
    static func generateDeviceStatus(count: Int, baseDate: Date = Date()) -> [DeviceStatus] {
        var statuses: [DeviceStatus] = []
        
        for i in 0..<count {
            let timestamp = baseDate.addingTimeInterval(Double(-i * 300)) // 5 min intervals
            
            statuses.append(DeviceStatus(
                timestamp: timestamp,
                device: "test-device",
                iob: 2.5 + Double.random(in: -1...1),
                cob: 30 + Double.random(in: -10...10),
                eventualBG: 120 + Double.random(in: -20...20),
                recommendedBolus: Double.random(in: 0...0.5),
                pumpBattery: 0.8 + Double.random(in: -0.3...0.2),
                reservoirUnits: 150 + Double.random(in: -50...50),
                suspended: false,
                uploaderBattery: 0.9 + Double.random(in: -0.2...0.1),
                source: "benchmark",
                syncIdentifier: "ds-\(i)"
            ))
        }
        
        return statuses
    }
    
    /// Generate N proposal records with realistic values.
    static func generateProposals(count: Int, baseDate: Date = Date()) -> [PersistenceAgentProposal] {
        let types: [PersistenceProposalType] = [.override, .tempTarget, .carbs, .annotation]
        let statuses: [PersistenceProposalStatus] = [.pending, .approved, .rejected, .executed]
        var proposals: [PersistenceAgentProposal] = []
        
        for i in 0..<count {
            let timestamp = baseDate.addingTimeInterval(Double(-i * 3600)) // 1 hour intervals
            let expiresAt = timestamp.addingTimeInterval(3600) // 1 hour expiry
            
            proposals.append(PersistenceAgentProposal(
                timestamp: timestamp,
                agentId: "agent-\(i % 5)",
                agentName: "Test Agent \(i % 5)",
                proposalType: types[i % types.count],
                description: "Test proposal \(i)",
                rationale: "Testing at scale for benchmark",
                expiresAt: expiresAt,
                status: statuses[i % statuses.count],
                syncIdentifier: "prop-\(i)"
            ))
        }
        
        return proposals
    }
    
    /// Generate N treatment records with realistic values.
    static func generateTreatments(count: Int, baseDate: Date = Date()) -> [Treatment] {
        let types: [PersistenceTreatmentType] = [.bolus, .carbs, .tempBasal, .bgCheck, .note]
        var treatments: [Treatment] = []
        
        for i in 0..<count {
            let timestamp = baseDate.addingTimeInterval(Double(-i * 1800)) // 30 min intervals
            let type = types[i % types.count]
            
            treatments.append(Treatment(
                type: type,
                timestamp: timestamp,
                insulin: type == .bolus ? Double.random(in: 0.5...5) : nil,
                carbs: type == .carbs ? Double.random(in: 10...60) : nil,
                duration: type == .tempBasal ? Double.random(in: 1800...7200) : nil,
                rate: type == .tempBasal ? Double.random(in: 0.5...2) : nil,
                notes: "Benchmark treatment \(i)",
                source: "benchmark",
                syncIdentifier: "treat-\(i)"
            ))
        }
        
        return treatments
    }
}

// MARK: - DeviceStatusStore Integration Tests

@Suite("GRDB DeviceStatusStore Integration")
struct GRDBDeviceStatusStoreIntegrationTests {
    
    @Test("Basic CRUD operations")
    func testBasicCRUD() async throws {
        let store = try GRDBDeviceStatusStore.inMemoryStore()
        
        // Create
        let status = DeviceStatus(
            timestamp: Date(),
            device: "test",
            iob: 2.5,
            cob: 30,
            eventualBG: 120
        )
        try await store.save(status)
        
        // Read
        let count = try await store.count()
        #expect(count == 1)
        
        let fetched = try await store.fetchMostRecent()
        #expect(fetched?.device == "test")
        #expect(fetched?.iob == 2.5)
        
        // Delete
        let deleted = try await store.deleteOlderThan(Date.distantFuture)
        #expect(deleted == 1)
        
        let finalCount = try await store.count()
        #expect(finalCount == 0)
    }
    
    @Test("Batch insert 10K device statuses")
    func testBatchInsert10K() async throws {
        let store = try GRDBDeviceStatusStore.inMemoryStore()
        let statuses = IntegrationTestData.generateDeviceStatus(count: 10_000)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        try await store.save(statuses)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        let count = try await store.count()
        #expect(count == 10_000)
        
        let rate = Double(10_000) / (elapsed / 1000)
        print("[BENCH] DeviceStatus 10K insert: \(String(format: "%.0f", elapsed))ms (\(String(format: "%.0f", rate))/sec)")
        
        // Should complete in reasonable time
        #expect(elapsed < 30_000, "10K inserts should complete in < 30 seconds")
    }
    
    @Test("Query range from 50K records")
    func testQueryRange50K() async throws {
        let store = try GRDBDeviceStatusStore.inMemoryStore()
        let statuses = IntegrationTestData.generateDeviceStatus(count: 50_000)
        try await store.save(statuses)
        
        // Query 1 week of data (2016 records at 5-min intervals)
        let now = Date()
        let weekAgo = now.addingTimeInterval(-7 * 86400)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let results = try await store.fetch(from: weekAgo, to: now)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        print("[BENCH] DeviceStatus 50K query 1-week range: \(String(format: "%.1f", elapsed))ms, \(results.count) results")
        
        // Query should be fast with index
        #expect(elapsed < 1000, "1-week query should complete in < 1 second")
    }
}

// MARK: - ProposalStore Integration Tests

@Suite("GRDB ProposalStore Integration")
struct GRDBProposalStoreIntegrationTests {
    
    @Test("Basic CRUD operations")
    func testBasicCRUD() async throws {
        let store = try GRDBProposalStore.inMemoryStore()
        
        // Create
        let proposal = PersistenceAgentProposal(
            timestamp: Date(),
            agentId: "test-agent",
            agentName: "Test Agent",
            proposalType: .override,
            description: "Test proposal",
            rationale: "Testing CRUD",
            expiresAt: Date().addingTimeInterval(3600),
            status: .pending
        )
        try await store.save(proposal)
        
        // Read
        let count = try await store.count()
        #expect(count == 1)
        
        let pending = try await store.countPending()
        #expect(pending == 1)
        
        let fetched = try await store.fetch(id: proposal.id)
        #expect(fetched?.agentName == "Test Agent")
        
        // Update
        var updated = proposal
        updated.status = .approved
        try await store.update(updated)
        
        let afterUpdate = try await store.countPending()
        #expect(afterUpdate == 0)
        
        // Delete
        try await store.deleteAll()
        let finalCount = try await store.count()
        #expect(finalCount == 0)
    }
    
    @Test("Filter by status")
    func testFilterByStatus() async throws {
        let store = try GRDBProposalStore.inMemoryStore()
        let proposals = IntegrationTestData.generateProposals(count: 100)
        try await store.save(proposals)
        
        let pending = try await store.fetch(status: .pending)
        let approved = try await store.fetch(status: .approved)
        let rejected = try await store.fetch(status: .rejected)
        let executed = try await store.fetch(status: .executed)
        
        let total = pending.count + approved.count + rejected.count + executed.count
        #expect(total == 100, "All statuses should sum to total")
        
        print("[BENCH] Proposal status distribution: pending=\(pending.count), approved=\(approved.count), rejected=\(rejected.count), executed=\(executed.count)")
    }
    
    @Test("Scale test 10K proposals")
    func testScale10K() async throws {
        let store = try GRDBProposalStore.inMemoryStore()
        let proposals = IntegrationTestData.generateProposals(count: 10_000)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        try await store.save(proposals)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        let count = try await store.count()
        #expect(count == 10_000)
        
        print("[BENCH] Proposal 10K insert: \(String(format: "%.0f", elapsed))ms")
        
        // Query pending
        let queryStart = CFAbsoluteTimeGetCurrent()
        let pending = try await store.fetchPending()
        let queryElapsed = (CFAbsoluteTimeGetCurrent() - queryStart) * 1000
        
        print("[BENCH] Proposal 10K pending query: \(String(format: "%.1f", queryElapsed))ms, \(pending.count) results")
    }
}

// MARK: - TreatmentStore Integration Tests

@Suite("GRDB TreatmentStore Integration")
struct GRDBTreatmentStoreIntegrationTests {
    
    @Test("Basic CRUD operations")
    func testBasicCRUD() async throws {
        let store = try GRDBTreatmentStore.inMemoryStore()
        
        // Create
        let treatment = Treatment.bolus(units: 2.5, timestamp: Date(), source: "test")
        try await store.save(treatment)
        
        // Read
        let count = try await store.count()
        #expect(count == 1)
        
        let fetched = try await store.fetchMostRecent()
        #expect(fetched?.insulin == 2.5)
        
        // Fetch by sync ID
        let bySync = try await store.fetch(syncIdentifier: treatment.syncIdentifier ?? "")
        #expect(bySync != nil || treatment.syncIdentifier == nil)
        
        // Delete
        try await store.deleteAll()
        let finalCount = try await store.count()
        #expect(finalCount == 0)
    }
    
    @Test("Filter by type")
    func testFilterByType() async throws {
        let store = try GRDBTreatmentStore.inMemoryStore()
        let treatments = IntegrationTestData.generateTreatments(count: 100)
        try await store.save(treatments)
        
        let now = Date()
        let yearAgo = now.addingTimeInterval(-365 * 86400)
        
        let boluses = try await store.fetch(type: .bolus, from: yearAgo, to: now)
        let carbs = try await store.fetch(type: .carbs, from: yearAgo, to: now)
        
        print("[BENCH] Treatment type distribution: bolus=\(boluses.count), carbs=\(carbs.count)")
        
        #expect(boluses.count > 0)
        #expect(carbs.count > 0)
    }
    
    @Test("Scale test 50K treatments")
    func testScale50K() async throws {
        let store = try GRDBTreatmentStore.inMemoryStore()
        let treatments = IntegrationTestData.generateTreatments(count: 50_000)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        try await store.save(treatments)
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        let count = try await store.count()
        #expect(count == 50_000)
        
        let rate = Double(50_000) / (elapsed / 1000)
        print("[BENCH] Treatment 50K insert: \(String(format: "%.0f", elapsed))ms (\(String(format: "%.0f", rate))/sec)")
    }
}

// MARK: - Cross-Store Integration Tests

@Suite("GRDB Cross-Store Integration")
struct GRDBCrossStoreIntegrationTests {
    
    @Test("All stores work together")
    func testAllStoresTogether() async throws {
        let glucoseStore = try GRDBGlucoseStore.inMemoryStore()
        let deviceStore = try GRDBDeviceStatusStore.inMemoryStore()
        let proposalStore = try GRDBProposalStore.inMemoryStore()
        let treatmentStore = try GRDBTreatmentStore.inMemoryStore()
        
        // Simulate 1 day of data
        let now = Date()
        
        // 288 glucose readings (5 min intervals)
        let readings = GlucoseTestDataGenerator.generateReadings(count: 288)
        try await glucoseStore.save(readings)
        
        // 288 device statuses (5 min intervals)
        let statuses = IntegrationTestData.generateDeviceStatus(count: 288)
        try await deviceStore.save(statuses)
        
        // 24 proposals (1 per hour)
        let proposals = IntegrationTestData.generateProposals(count: 24, baseDate: now)
        try await proposalStore.save(proposals)
        
        // 48 treatments (30 min intervals)
        let treatments = IntegrationTestData.generateTreatments(count: 48)
        try await treatmentStore.save(treatments)
        
        // Verify counts
        #expect(try await glucoseStore.count() == 288)
        #expect(try await deviceStore.count() == 288)
        #expect(try await proposalStore.count() == 24)
        #expect(try await treatmentStore.count() == 48)
        
        print("[BENCH] 1-day simulation: 288 glucose, 288 device status, 24 proposals, 48 treatments")
    }
    
    @Test("100K records across stores")
    func test100KRecordsTotal() async throws {
        let glucoseStore = try GRDBGlucoseStore.inMemoryStore()
        let deviceStore = try GRDBDeviceStatusStore.inMemoryStore()
        let treatmentStore = try GRDBTreatmentStore.inMemoryStore()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // 40K glucose readings (~140 days)
        let readings = GlucoseTestDataGenerator.generateReadings(count: 40_000)
        try await glucoseStore.save(readings)
        
        // 40K device statuses (~140 days)
        let statuses = IntegrationTestData.generateDeviceStatus(count: 40_000)
        try await deviceStore.save(statuses)
        
        // 20K treatments (~1 year at 50/day)
        let treatments = IntegrationTestData.generateTreatments(count: 20_000)
        try await treatmentStore.save(treatments)
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        let totalCount = try await glucoseStore.count() + 
                        try await deviceStore.count() + 
                        try await treatmentStore.count()
        
        #expect(totalCount == 100_000)
        
        print("[BENCH] 100K total records inserted in \(String(format: "%.0f", elapsed))ms")
        print("  Glucose: 40K, DeviceStatus: 40K, Treatments: 20K")
        
        // 100K inserts should complete in under 2 minutes
        #expect(elapsed < 120_000, "100K inserts should complete in < 2 minutes")
    }
}

// MARK: - Factory Integration Tests

@Suite("Store Factory Integration")
struct StoreFactoryIntegrationTests {
    
    @Test("GlucoseStoreFactory creates valid store")
    func testGlucoseFactory() async throws {
        let store = GlucoseStoreFactory.createDefault()
        
        let reading = GlucoseReading(
            glucose: 120,
            timestamp: Date(),
            trend: .flat,
            source: "factory-test"
        )
        
        try await store.save(reading)
        let count = try await store.count()
        #expect(count >= 1) // May have other data from previous tests
    }
    
    @Test("TreatmentStoreFactory creates valid store")
    func testTreatmentFactory() async throws {
        let store = TreatmentStoreFactory.createDefault()
        
        let treatment = Treatment.bolus(units: 1.0, source: "factory-test")
        try await store.save(treatment)
        
        let count = try await store.count()
        #expect(count >= 1)
    }
    
    @Test("DeviceStatusStoreFactory creates valid store")
    func testDeviceStatusFactory() async throws {
        let store = DeviceStatusStoreFactory.createDefault()
        
        let status = DeviceStatus(
            timestamp: Date(),
            device: "factory-test",
            iob: 1.0
        )
        try await store.save(status)
        
        let count = try await store.count()
        #expect(count >= 1)
    }
    
    @Test("ProposalStoreFactory creates valid store")
    func testProposalFactory() async throws {
        let store = ProposalStoreFactory.createDefault()
        
        let proposal = PersistenceAgentProposal(
            agentId: "factory-test",
            agentName: "Factory Test",
            proposalType: .annotation,
            description: "Test",
            rationale: "Testing factory",
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await store.save(proposal)
        
        let count = try await store.count()
        #expect(count >= 1)
    }
    
    @Test("GRDBGlucoseStore.createForUser creates isolated per-user store (FOLLOW-CACHE-001)")
    func testCreateForUser() async throws {
        let userId1 = UUID()
        let userId2 = UUID()
        
        // Create stores for two different users
        let store1 = try GRDBGlucoseStore.createForUser(userId1)
        let store2 = try GRDBGlucoseStore.createForUser(userId2)
        
        // Save to user 1 only
        let reading = GlucoseReading(
            glucose: 145,
            timestamp: Date(),
            trend: .risingSlightly,
            source: "follow-cache-test"
        )
        try await store1.save(reading)
        
        // User 1 should have 1, user 2 should have 0
        let count1 = try await store1.count()
        let count2 = try await store2.count()
        #expect(count1 == 1, "User 1 store should have the reading")
        #expect(count2 == 0, "User 2 store should be isolated (empty)")
        
        // Cleanup: remove test directories
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal/followed")
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(userId1.uuidString))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(userId2.uuidString))
    }
    
    @Test("RetentionPolicy configuration (FOLLOW-CACHE-003)")
    func testRetentionPolicyConfig() {
        let standard = GRDBGlucoseStore.RetentionPolicy.standard
        #expect(standard.maxInactivityDays == 30)
        
        let aggressive = GRDBGlucoseStore.RetentionPolicy.aggressive
        #expect(aggressive.maxInactivityDays == 1)
        
        let custom = GRDBGlucoseStore.RetentionPolicy(maxInactivityDays: 7)
        #expect(custom.maxInactivityDays == 7)
    }
    
    @Test("listUserCaches returns cache info (FOLLOW-CACHE-003)")
    func testListUserCaches() async throws {
        let userId = UUID()
        
        // Create a store to ensure directory exists
        let store = try GRDBGlucoseStore.createForUser(userId)
        let reading = GlucoseReading(glucose: 120, timestamp: Date(), trend: .flat, source: "test")
        try await store.save(reading)
        
        // List should include our user
        let caches = try GRDBGlucoseStore.listUserCaches()
        let found = caches.first { $0.userId == userId }
        #expect(found != nil, "Should find the test user's cache")
        #expect(found?.sizeBytes ?? 0 > 0, "Cache should have some data")
        
        // Cleanup
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal/followed/\(userId.uuidString)")
        try? FileManager.default.removeItem(at: directory)
    }
    
    @Test("cleanupInactiveUserCaches removes old caches (FOLLOW-CACHE-003)")
    func testCleanupInactiveUserCaches() async throws {
        let oldUserId = UUID()
        let recentUserId = UUID()
        let fileManager = FileManager.default
        let followedDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("T1Pal/followed", isDirectory: true)
        
        // Create both stores
        _ = try GRDBGlucoseStore.createForUser(oldUserId)
        _ = try GRDBGlucoseStore.createForUser(recentUserId)
        
        // Make the "old" user's directory appear old (40 days ago)
        let oldDate = Date().addingTimeInterval(-40 * 24 * 60 * 60)
        let oldDir = followedDir.appendingPathComponent(oldUserId.uuidString)
        try fileManager.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldDir.path)
        
        // Run cleanup with standard 30-day policy
        let deleted = try GRDBGlucoseStore.cleanupInactiveUserCaches(policy: .standard)
        
        // Old cache should be deleted, recent should remain
        #expect(deleted >= 1, "Should delete at least the old cache")
        #expect(!fileManager.fileExists(atPath: oldDir.path), "Old cache should be removed")
        #expect(fileManager.fileExists(atPath: followedDir.appendingPathComponent(recentUserId.uuidString).path), 
                "Recent cache should remain")
        
        // Cleanup remaining
        try? fileManager.removeItem(at: followedDir.appendingPathComponent(recentUserId.uuidString))
    }
    
    @Test("FollowerCacheMigration clears legacy shared cache (FOLLOW-CACHE-005)")
    func testFollowerCacheMigration() throws {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let t1palDir = appSupport.appendingPathComponent("T1Pal")
        let followedDir = t1palDir.appendingPathComponent("followed")
        let legacyGlucosePath = t1palDir.appendingPathComponent("glucose.sqlite")
        
        // Reset migration state
        FollowerCacheMigration.shared.reset()
        
        // Create the "followed" directory to simulate per-user mode
        try fileManager.createDirectory(at: followedDir, withIntermediateDirectories: true)
        
        // Create a legacy shared cache file
        fileManager.createFile(atPath: legacyGlucosePath.path, contents: "test".data(using: .utf8))
        #expect(fileManager.fileExists(atPath: legacyGlucosePath.path), "Legacy file should exist before migration")
        
        // Run migration
        let cleared = FollowerCacheMigration.shared.runIfNeeded()
        
        // Should have cleared the legacy file
        #expect(cleared, "Migration should report data was cleared")
        #expect(!fileManager.fileExists(atPath: legacyGlucosePath.path), "Legacy file should be removed")
        #expect(FollowerCacheMigration.shared.isComplete, "Migration should be marked complete")
        #expect(FollowerCacheMigration.shared.legacyCacheWasCleared, "Should record that legacy cache was cleared")
        
        // Running again should be a no-op
        let clearedAgain = FollowerCacheMigration.shared.runIfNeeded()
        #expect(!clearedAgain, "Second run should not clear anything")
        
        // Cleanup
        FollowerCacheMigration.shared.reset()
        try? fileManager.removeItem(at: followedDir)
    }
    
    @Test("FollowerCacheMigration skips when no followed directory (FOLLOW-CACHE-005)")
    func testMigrationSkipsNonFollowerContext() throws {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let t1palDir = appSupport.appendingPathComponent("T1Pal")
        let followedDir = t1palDir.appendingPathComponent("followed")
        let legacyGlucosePath = t1palDir.appendingPathComponent("glucose.sqlite")
        
        // Reset migration state
        FollowerCacheMigration.shared.reset()
        
        // Ensure followed directory does NOT exist
        try? fileManager.removeItem(at: followedDir)
        
        // Create a legacy cache file (simulating main app, not follower)
        try fileManager.createDirectory(at: t1palDir, withIntermediateDirectories: true)
        fileManager.createFile(atPath: legacyGlucosePath.path, contents: "test".data(using: .utf8))
        
        // Run migration
        let cleared = FollowerCacheMigration.shared.runIfNeeded()
        
        // Should NOT clear (no followed directory = not follower context)
        #expect(!cleared, "Should not clear in non-follower context")
        #expect(fileManager.fileExists(atPath: legacyGlucosePath.path), "Legacy file should remain")
        
        // Cleanup
        FollowerCacheMigration.shared.reset()
        try? fileManager.removeItem(at: legacyGlucosePath)
    }
}

#endif // canImport(Darwin)
