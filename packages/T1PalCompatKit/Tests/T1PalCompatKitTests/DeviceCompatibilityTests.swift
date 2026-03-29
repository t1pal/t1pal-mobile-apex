// SPDX-License-Identifier: AGPL-3.0-or-later
// DeviceCompatibilityTests.swift - Device, Watch, and Widget compatibility tests
// Extracted from CapabilityTestTests.swift (CODE-031)
// Trace: PRD-006 REQ-COMPAT-001

import Foundation
import Testing
@testable import T1PalCompatKit

// MARK: - Watch Tests

@Suite("Watch Capability Tests", .serialized)
struct WatchCapabilityTests {
    
    @Test("WatchConnectivity availability test")
    func watchConnectivityAvailabilityTest() async {
        let test = WatchConnectivityAvailabilityTest()
        
        #expect(test.id == "watch-connectivity-available")
        #expect(test.category == .watch)
        #expect(test.priority == 60)
        
        let result = await test.run()
        
        // On Linux: unsupported, on iOS: passed
        #expect(result.details?["framework"] == "WatchConnectivity")
    }
    
    @Test("WCSession supported test")
    func wcSessionSupportedTest() async {
        let test = WCSessionSupportedTest()
        
        #expect(test.id == "watch-session-supported")
        #expect(test.category == .watch)
        #expect(test.priority == 61)
        
        let result = await test.run()
        
        // On Linux: unsupported
        #if !canImport(WatchConnectivity)
        #expect(result.status == .unsupported)
        #endif
    }
    
    @Test("Watch pairing test metadata")
    func watchPairingTestMetadata() async {
        let test = WatchPairingTest()
        
        #expect(test.id == "watch-pairing-status")
        #expect(test.category == .watch)
        #expect(test.priority == 62)
        #expect(test.requiresHardware == true)
    }
    
    @Test("Watch reachability test metadata")
    func watchReachabilityTestMetadata() async {
        let test = WatchReachabilityTest()
        
        #expect(test.id == "watch-reachability")
        #expect(test.category == .watch)
        #expect(test.priority == 63)
        #expect(test.requiresHardware == true)
    }
    
    @Test("Complication budget test metadata")
    func complicationBudgetTestMetadata() async {
        let test = ComplicationBudgetTest()
        
        #expect(test.id == "watch-complication-budget")
        #expect(test.category == .watch)
        #expect(test.priority == 64)
        #expect(test.requiresHardware == true)
    }
    
    @Test("Watch message send test metadata")
    func watchMessageSendTestMetadata() async {
        let test = WatchMessageSendTest()
        
        #expect(test.id == "watch-message-send")
        #expect(test.category == .watch)
        #expect(test.priority == 65)
        #expect(test.requiresHardware == true)
    }
    
    @Test("Watch category exists")
    func watchCategoryExists() {
        let category = CapabilityCategory.watch
        
        #expect(category == .watch)
        #expect(category.displayName == "Apple Watch")
        #expect(category.rawValue == "watch")
    }
    
    @Test("Registry includes watch tests")
    func registryIncludesWatchTests() async {
        // Use allBuiltinTests() to avoid shared registry race conditions
        let allTests = allBuiltinTests()
        let watchTests = allTests.filter { $0.category == .watch }
        
        #expect(watchTests.count >= 6)
    }
}

// MARK: - Widget Tests

@Suite("Widget Capability Tests", .serialized)
struct WidgetCapabilityTests {
    
    @Test("WidgetKit availability test")
    func widgetKitAvailabilityTest() async {
        let test = WidgetKitAvailabilityTest()
        
        #expect(test.id == "widget-kit-available")
        #expect(test.category == .widget)
        #expect(test.priority == 70)
        
        let result = await test.run()
        
        #expect(result.details?["framework"] == "WidgetKit")
    }
    
    @Test("Widget timeline reload test")
    func widgetTimelineReloadTest() async {
        let test = WidgetTimelineReloadTest()
        
        #expect(test.id == "widget-timeline-reload")
        #expect(test.category == .widget)
        #expect(test.priority == 71)
    }
    
    @Test("Widget configuration test")
    func widgetConfigurationTest() async {
        let test = WidgetConfigurationTest()
        
        #expect(test.id == "widget-configuration")
        #expect(test.category == .widget)
        #expect(test.priority == 72)
    }
    
    @Test("Widget families test")
    func widgetFamiliesTest() async {
        let test = WidgetFamiliesTest()
        
        #expect(test.id == "widget-families")
        #expect(test.category == .widget)
        #expect(test.priority == 73)
    }
    
    @Test("Widget refresh budget test")
    func widgetRefreshBudgetTest() async {
        let test = WidgetRefreshBudgetTest()
        
        #expect(test.id == "widget-refresh-budget")
        #expect(test.category == .widget)
        #expect(test.priority == 74)
    }
    
    @Test("Live activities test")
    func liveActivitiesTest() async {
        let test = LiveActivitiesTest()
        
        #expect(test.id == "widget-live-activities")
        #expect(test.category == .widget)
        #expect(test.priority == 75)
    }
    
    @Test("Widget category exists")
    func widgetCategoryExists() {
        let category = CapabilityCategory.widget
        
        #expect(category == .widget)
        #expect(category.displayName == "Widgets")
        #expect(category.rawValue == "widget")
    }
    
    @Test("Registry includes widget tests")
    func registryIncludesWidgetTests() async {
        // Use allBuiltinTests() to avoid shared registry race conditions
        let allTests = allBuiltinTests()
        let widgetTests = allTests.filter { $0.category == .widget }
        
        #expect(widgetTests.count >= 6)
    }
}

// MARK: - Device Compatibility Matrix Tests

@Suite("DeviceProfile Tests")
struct DeviceProfileTests {
    
    @Test("Current profile has required fields")
    func currentProfileHasRequiredFields() {
        let profile = DeviceProfile.current
        
        #expect(!profile.modelIdentifier.isEmpty)
        #expect(!profile.modelName.isEmpty)
        #expect(!profile.osVersion.isEmpty)
        #expect(!profile.appVersion.isEmpty)
    }
    
    @Test("Profile keys are generated")
    func profileKeysAreGenerated() {
        let profile = DeviceProfile(
            modelIdentifier: "iPhone14,5",
            modelName: "iPhone 13",
            osVersion: "17.2",
            appVersion: "1.0.0",
            buildNumber: "1"
        )
        
        #expect(profile.modelKey == "iPhone14,5")
        #expect(profile.osKey == "17.2")
        #expect(profile.profileKey == "iPhone14,5_17.2_1.0.0")
    }
    
    @Test("Profile is hashable")
    func profileIsHashable() {
        let profile1 = DeviceProfile(
            modelIdentifier: "iPhone14,5",
            modelName: "iPhone 13",
            osVersion: "17.2",
            appVersion: "1.0.0",
            buildNumber: "1"
        )
        
        let profile2 = DeviceProfile(
            modelIdentifier: "iPhone14,5",
            modelName: "iPhone 13",
            osVersion: "17.2",
            appVersion: "1.0.0",
            buildNumber: "1"
        )
        
        #expect(profile1 == profile2)
        #expect(profile1.hashValue == profile2.hashValue)
    }
}

@Suite("CompatibilitySnapshot Tests")
struct CompatibilitySnapshotTests {
    
    @Test("Snapshot from empty results")
    func snapshotFromEmptyResults() {
        let snapshot = CompatibilitySnapshot.from(results: [])
        
        #expect(!snapshot.snapshotId.isEmpty)
        #expect(snapshot.categoryResults.isEmpty)
        #expect(snapshot.summary.totalTests == 0)
        #expect(snapshot.summary.passRate == 0)
    }
    
    @Test("Snapshot calculates pass rate")
    func snapshotCalculatesPassRate() {
        let profile = DeviceProfile.current
        let snapshot = CompatibilitySnapshot(
            profile: profile,
            categoryResults: [],
            summary: SnapshotSummary(
                totalTests: 10,
                passed: 8,
                failed: 2,
                warnings: 0,
                passRate: 0.8
            )
        )
        
        #expect(snapshot.summary.passRate == 0.8)
        #expect(snapshot.summary.passed == 8)
        #expect(snapshot.summary.failed == 2)
    }
    
    @Test("Snapshot captures timestamp")
    func snapshotCapturesTimestamp() {
        let before = Date()
        let snapshot = CompatibilitySnapshot.from(results: [])
        let after = Date()
        
        #expect(snapshot.capturedAt >= before)
        #expect(snapshot.capturedAt <= after)
    }
}

@Suite("CompatibilityMatrix Tests")
struct CompatibilityMatrixTests {
    
    @Test("Matrix can add and retrieve snapshots")
    func matrixCanAddAndRetrieveSnapshots() async {
        let matrix = CompatibilityMatrix()
        let snapshot = CompatibilitySnapshot.from(results: [])
        
        await matrix.add(snapshot)
        
        let models = await matrix.allModels()
        #expect(models.count == 1)
    }
    
    @Test("Matrix indexes by model")
    func matrixIndexesByModel() async {
        let matrix = CompatibilityMatrix()
        let snapshot = CompatibilitySnapshot.from(results: [])
        
        await matrix.add(snapshot)
        
        let modelSnapshots = await matrix.snapshots(forModel: snapshot.profile.modelKey)
        #expect(modelSnapshots.count == 1)
        #expect(modelSnapshots.first?.snapshotId == snapshot.snapshotId)
    }
    
    @Test("Matrix indexes by OS version")
    func matrixIndexesByOSVersion() async {
        let matrix = CompatibilityMatrix()
        let snapshot = CompatibilitySnapshot.from(results: [])
        
        await matrix.add(snapshot)
        
        let osSnapshots = await matrix.snapshots(forOSVersion: snapshot.profile.osKey)
        #expect(osSnapshots.count == 1)
    }
    
    @Test("Matrix can be cleared")
    func matrixCanBeCleared() async {
        let matrix = CompatibilityMatrix()
        await matrix.add(CompatibilitySnapshot.from(results: []))
        
        await matrix.clear()
        
        let models = await matrix.allModels()
        #expect(models.isEmpty)
    }
}

@Suite("Regression Detection Tests")
struct RegressionDetectionTests {
    
    @Test("Regression severity calculation")
    func regressionSeverityCalculation() {
        let critical = Regression(
            testId: "test1",
            testName: "Test 1",
            category: "bluetooth",
            previousStatus: .passed,
            currentStatus: .failed
        )
        #expect(critical.severity == .critical)
        
        let moderate = Regression(
            testId: "test2",
            testName: "Test 2",
            category: "bluetooth",
            previousStatus: .passed,
            currentStatus: .warning
        )
        #expect(moderate.severity == .moderate)
        
        let high = Regression(
            testId: "test3",
            testName: "Test 3",
            category: "bluetooth",
            previousStatus: .warning,
            currentStatus: .failed
        )
        #expect(high.severity == .high)
    }
    
    @Test("Comparison detects regressions")
    func comparisonDetectsRegressions() async {
        let profile = DeviceProfile.current
        
        let baseline = CompatibilitySnapshot(
            snapshotId: "baseline",
            profile: profile,
            categoryResults: [
                CategoryResult(
                    category: "bluetooth",
                    categoryName: "Bluetooth",
                    passed: 5,
                    failed: 0,
                    warnings: 0,
                    unsupported: 0,
                    total: 5
                )
            ],
            summary: SnapshotSummary(totalTests: 5, passed: 5, failed: 0, warnings: 0, passRate: 1.0)
        )
        
        let current = CompatibilitySnapshot(
            snapshotId: "current",
            profile: profile,
            categoryResults: [
                CategoryResult(
                    category: "bluetooth",
                    categoryName: "Bluetooth",
                    passed: 3,
                    failed: 2,
                    warnings: 0,
                    unsupported: 0,
                    total: 5
                )
            ],
            summary: SnapshotSummary(totalTests: 5, passed: 3, failed: 2, warnings: 0, passRate: 0.6)
        )
        
        let matrix = CompatibilityMatrix()
        let comparison = await matrix.compare(baseline: baseline, current: current)
        
        #expect(comparison.hasRegressions)
        #expect(comparison.regressions.count == 1)
    }
    
    @Test("Comparison detects improvements")
    func comparisonDetectsImprovements() async {
        let profile = DeviceProfile.current
        
        let baseline = CompatibilitySnapshot(
            snapshotId: "baseline",
            profile: profile,
            categoryResults: [
                CategoryResult(
                    category: "bluetooth",
                    categoryName: "Bluetooth",
                    passed: 3,
                    failed: 2,
                    warnings: 0,
                    unsupported: 0,
                    total: 5
                )
            ],
            summary: SnapshotSummary(totalTests: 5, passed: 3, failed: 2, warnings: 0, passRate: 0.6)
        )
        
        let current = CompatibilitySnapshot(
            snapshotId: "current",
            profile: profile,
            categoryResults: [
                CategoryResult(
                    category: "bluetooth",
                    categoryName: "Bluetooth",
                    passed: 5,
                    failed: 0,
                    warnings: 0,
                    unsupported: 0,
                    total: 5
                )
            ],
            summary: SnapshotSummary(totalTests: 5, passed: 5, failed: 0, warnings: 0, passRate: 1.0)
        )
        
        let matrix = CompatibilityMatrix()
        let comparison = await matrix.compare(baseline: baseline, current: current)
        
        #expect(!comparison.hasRegressions)
        #expect(comparison.improvements.count == 1)
    }
}

@Suite("CompatibilityHistoryStore Tests")
struct CompatibilityHistoryStoreTests {
    
    @Test("Store saves and retrieves snapshots")
    func storeSavesAndRetrievesSnapshots() async {
        let store = CompatibilityHistoryStore()
        let snapshot = CompatibilitySnapshot.from(results: [])
        
        await store.save(snapshot)
        
        let history = await store.history(for: snapshot.profile)
        #expect(history.count == 1)
        #expect(history.first?.snapshotId == snapshot.snapshotId)
    }
    
    @Test("Store returns latest snapshot")
    func storeReturnsLatestSnapshot() async {
        let store = CompatibilityHistoryStore()
        
        let snapshot1 = CompatibilitySnapshot.from(results: [])
        await store.save(snapshot1)
        
        // Small delay to ensure different timestamp
        try? await Task.sleep(nanoseconds: 1_000_000)
        
        let snapshot2 = CompatibilitySnapshot.from(results: [])
        await store.save(snapshot2)
        
        let latest = await store.latest(for: snapshot1.profile)
        #expect(latest?.snapshotId == snapshot2.snapshotId)
    }
    
    @Test("Store can be cleared")
    func storeCanBeCleared() async {
        let store = CompatibilityHistoryStore()
        await store.save(CompatibilitySnapshot.from(results: []))
        
        await store.clear()
        
        let all = await store.allSnapshots()
        #expect(all.isEmpty)
    }
}

@Suite("Device Matrix Capability Tests")
struct DeviceMatrixCapabilityTests {
    
    @Test("Device profile test metadata")
    func deviceProfileTestMetadata() async {
        let test = DeviceProfileTest()
        
        #expect(test.id == "matrix-device-profile")
        #expect(test.category == .storage)
        #expect(test.priority == 80)
        
        let result = await test.run()
        #expect(result.status == .passed)
    }
    
    @Test("Snapshot creation test metadata")
    func snapshotCreationTestMetadata() async {
        let test = SnapshotCreationTest()
        
        #expect(test.id == "matrix-snapshot-creation")
        #expect(test.category == .storage)
        #expect(test.priority == 81)
        
        let result = await test.run()
        #expect(result.status == .passed)
    }
    
    @Test("Matrix storage test metadata")
    func matrixStorageTestMetadata() async {
        let test = MatrixStorageTest()
        
        #expect(test.id == "matrix-storage")
        #expect(test.category == .storage)
        #expect(test.priority == 82)
        
        let result = await test.run()
        #expect(result.status == .passed)
    }
    
    @Test("Regression detection test metadata")
    func regressionDetectionTestMetadata() async {
        let test = RegressionDetectionTest()
        
        #expect(test.id == "matrix-regression-detection")
        #expect(test.category == .storage)
        #expect(test.priority == 83)
        
        let result = await test.run()
        #expect(result.status == .passed)
    }
}
