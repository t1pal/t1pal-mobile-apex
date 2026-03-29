// SPDX-License-Identifier: MIT
//
// CapabilityTestTests.swift
// T1PalCompatKitTests
//
// Unit tests for capability test framework.
// Trace: PRD-006 REQ-COMPAT-001

import Foundation
import Testing
@testable import T1PalCompatKit

// MARK: - Test Capability Test

struct MockPassingTest: CapabilityTest {
    let id = "mock-passing"
    let name = "Mock Passing Test"
    let category = CapabilityCategory.storage
    
    func run() async -> CapabilityResult {
        passed("Everything is fine")
    }
}

struct MockFailingTest: CapabilityTest {
    let id = "mock-failing"
    let name = "Mock Failing Test"
    let category = CapabilityCategory.bluetooth
    
    func run() async -> CapabilityResult {
        failed("Something went wrong", details: ["code": "ERR001"])
    }
}

struct MockHardwareTest: CapabilityTest {
    let id = "mock-hardware"
    let name = "Mock Hardware Test"
    let category = CapabilityCategory.bluetooth
    let requiresHardware = true
    
    func run() async -> CapabilityResult {
        passed("Hardware detected")
    }
}

// MARK: - CapabilityCategory Tests

@Suite("CapabilityCategory Tests")
struct CapabilityCategoryTests {
    
    @Test("All categories have display names")
    func allCategoriesHaveDisplayNames() {
        for category in CapabilityCategory.allCases {
            #expect(!category.displayName.isEmpty)
        }
    }
    
    @Test("Category count matches expected")
    func categoryCount() {
        #expect(CapabilityCategory.allCases.count == 10)
    }
}

// MARK: - CapabilityStatus Tests

@Suite("CapabilityStatus Tests")
struct CapabilityStatusTests {
    
    @Test("Status indicators are single characters")
    func statusIndicators() {
        #expect(CapabilityStatus.passed.indicator == "✓")
        #expect(CapabilityStatus.failed.indicator == "✗")
        #expect(CapabilityStatus.skipped.indicator == "○")
        #expect(CapabilityStatus.unsupported.indicator == "−")
    }
    
    @Test("Status has color codes")
    func statusColorCodes() {
        #expect(CapabilityStatus.passed.colorCode.contains("[32m"))  // Green
        #expect(CapabilityStatus.failed.colorCode.contains("[31m"))  // Red
    }
}

// MARK: - CapabilityResult Tests

@Suite("CapabilityResult Tests")
struct CapabilityResultTests {
    
    @Test("Result can be created")
    func resultCreation() {
        let result = CapabilityResult(
            testId: "test-1",
            testName: "Test One",
            category: .bluetooth,
            status: .passed,
            message: "Success"
        )
        
        #expect(result.testId == "test-1")
        #expect(result.testName == "Test One")
        #expect(result.category == .bluetooth)
        #expect(result.status == .passed)
        #expect(result.message == "Success")
    }
    
    @Test("Result formats for display")
    func resultFormatting() {
        let result = CapabilityResult(
            testId: "test-1",
            testName: "Test One",
            category: .bluetooth,
            status: .passed,
            message: "Success"
        )
        
        let formatted = result.formatted(useColor: false)
        #expect(formatted.contains("✓"))
        #expect(formatted.contains("Bluetooth"))
        #expect(formatted.contains("Test One"))
        #expect(formatted.contains("Success"))
    }
}

// MARK: - CapabilityTest Protocol Tests

@Suite("CapabilityTest Protocol Tests")
struct CapabilityTestProtocolTests {
    
    @Test("Test can create passed result")
    func testPassedResult() async {
        let test = MockPassingTest()
        let result = await test.run()
        
        #expect(result.status == .passed)
        #expect(result.testId == "mock-passing")
    }
    
    @Test("Test can create failed result")
    func testFailedResult() async {
        let test = MockFailingTest()
        let result = await test.run()
        
        #expect(result.status == .failed)
        #expect(result.details?["code"] == "ERR001")
    }
    
    @Test("Default priority is 100")
    func defaultPriority() {
        let test = MockPassingTest()
        #expect(test.priority == 100)
    }
    
    @Test("Default requiresHardware is false")
    func defaultRequiresHardware() {
        let test = MockPassingTest()
        #expect(test.requiresHardware == false)
    }
}

// MARK: - CapabilityRegistry Tests

@Suite("CapabilityRegistry Tests", .serialized)
struct CapabilityRegistryTests {
    
    @Test("Registry can register and retrieve tests")
    func registerTests() async {
        let registry = CapabilityRegistry.shared
        let initialCount = await registry.count
        
        await registry.register(MockPassingTest())
        await registry.register(MockFailingTest())
        
        let finalCount = await registry.count
        #expect(finalCount >= initialCount + 2)
        
        // Clean up by clearing
        await registry.clear()
    }
    
    @Test("Registry filters by category")
    func filterByCategory() async {
        let registry = CapabilityRegistry.shared
        await registry.clear()
        
        await registry.register(MockPassingTest())  // storage
        await registry.register(MockFailingTest())  // bluetooth
        
        let btTests = await registry.tests(in: .bluetooth)
        #expect(btTests.count == 1)
        #expect(btTests[0].id == "mock-failing")
        
        await registry.clear()
    }
    
    @Test("Registry runs all tests")
    func runAllTests() async {
        let registry = CapabilityRegistry.shared
        await registry.clear()
        
        await registry.register(MockPassingTest())
        await registry.register(MockFailingTest())
        
        let report = await registry.runAll()
        
        #expect(report.results.count == 2)
        #expect(report.passedCount == 1)
        #expect(report.failedCount == 1)
        #expect(!report.allPassed)
        
        await registry.clear()
    }
    
    @Test("Registry skips hardware tests when requested")
    func skipHardwareTests() async {
        let registry = CapabilityRegistry.shared
        await registry.clear()
        
        await registry.register(MockPassingTest())
        await registry.register(MockHardwareTest())
        
        let report = await registry.runAll(skipHardware: true)
        
        #expect(report.results.count == 2)
        #expect(report.skippedCount == 1)
        
        await registry.clear()
    }
}

// MARK: - CapabilityReport Tests

@Suite("CapabilityReport Tests")
struct CapabilityReportTests {
    
    @Test("Report calculates counts correctly")
    func reportCounts() {
        let results = [
            CapabilityResult(testId: "t1", testName: "T1", category: .storage, status: .passed, message: "ok"),
            CapabilityResult(testId: "t2", testName: "T2", category: .storage, status: .passed, message: "ok"),
            CapabilityResult(testId: "t3", testName: "T3", category: .bluetooth, status: .failed, message: "fail"),
            CapabilityResult(testId: "t4", testName: "T4", category: .network, status: .skipped, message: "skip"),
        ]
        
        let report = CapabilityReport(results: results, startTime: Date(), endTime: Date())
        
        #expect(report.passedCount == 2)
        #expect(report.failedCount == 1)
        #expect(report.skippedCount == 1)
        #expect(!report.allPassed)
    }
    
    @Test("Report groups by category")
    func reportGroupsByCategory() {
        let results = [
            CapabilityResult(testId: "t1", testName: "T1", category: .storage, status: .passed, message: "ok"),
            CapabilityResult(testId: "t2", testName: "T2", category: .bluetooth, status: .passed, message: "ok"),
            CapabilityResult(testId: "t3", testName: "T3", category: .storage, status: .passed, message: "ok"),
        ]
        
        let report = CapabilityReport(results: results, startTime: Date(), endTime: Date())
        let byCategory = report.byCategory
        
        #expect(byCategory[.storage]?.count == 2)
        #expect(byCategory[.bluetooth]?.count == 1)
    }
    
    @Test("Report exports to JSON")
    func reportExportsJSON() throws {
        let results = [
            CapabilityResult(testId: "t1", testName: "T1", category: .storage, status: .passed, message: "ok"),
        ]
        
        let report = CapabilityReport(results: results, startTime: Date(), endTime: Date())
        let json = try report.toJSON()
        
        #expect(json.count > 0)
        let str = String(data: json, encoding: .utf8)!
        #expect(str.contains("passed"))
        #expect(str.contains("storage"))
    }
    
    @Test("Report generates summary")
    func reportGeneratesSummary() {
        let results = [
            CapabilityResult(testId: "t1", testName: "T1", category: .storage, status: .passed, message: "ok"),
        ]
        
        let report = CapabilityReport(results: results, startTime: Date(), endTime: Date())
        let summary = report.summary(useColor: false)
        
        #expect(summary.contains("Capability Test Report"))
        #expect(summary.contains("1 passed"))
        #expect(summary.contains("✓"))
    }
}

// MARK: - Built-in Tests

@Suite("Built-in Tests", .serialized)
struct BuiltinTestsTests {
    
    @Test("PlatformInfoTest detects platform")
    func platformInfoTest() async {
        let test = PlatformInfoTest()
        let result = await test.run()
        
        #expect(result.status == .passed)
        #expect(result.details?["platform"] != nil)
    }
    
    @Test("StorageWriteTest can write files")
    func storageWriteTest() async {
        let test = StorageWriteTest()
        let result = await test.run()
        
        #expect(result.status == .passed)
    }
    
    @Test("UserDefaultsTest can read/write")
    func userDefaultsTest() async {
        let test = UserDefaultsTest()
        let result = await test.run()
        
        #expect(result.status == .passed)
    }
    
    @Test("registerBuiltinTests registers multiple tests")
    func registerBuiltinTestsAddsTests() async {
        // Use allBuiltinTests() to avoid shared registry race conditions
        let allTests = allBuiltinTests()
        #expect(allTests.count >= 27)  // 4 original + 4 bluetooth + 6 notification + 6 healthkit + 3 colocated + 4 quirks tests
    }
}

// MARK: - Bluetooth Tests

@Suite("Bluetooth Tests")
struct BluetoothTestsTests {
    
    @Test("BLECentralStateTest returns result")
    func bleCentralStateTest() async {
        let test = BLECentralStateTest()
        let result = await test.run()
        
        // On Linux, should be unsupported; on macOS/iOS, should have a status
        #expect(result.testId == "ble-central-state")
        #expect(result.category == .bluetooth)
        #if canImport(CoreBluetooth)
        // On Apple platforms, we get a real result
        #expect(result.status == .passed || result.status == .failed || result.status == .unsupported)
        #else
        #expect(result.status == .unsupported)
        #endif
    }
    
    @Test("BLEBackgroundModeTest returns result")
    func bleBackgroundModeTest() async {
        let test = BLEBackgroundModeTest()
        let result = await test.run()
        
        #expect(result.testId == "ble-background-mode")
        #expect(result.category == .bluetooth)
    }
    
    @Test("BLEStateRestorationTest returns result")
    func bleStateRestorationTest() async {
        let test = BLEStateRestorationTest()
        let result = await test.run()
        
        #expect(result.testId == "ble-state-restoration")
        #expect(result.category == .bluetooth)
    }
    
    @Test("BLEAuthorizationTest returns result")
    func bleAuthorizationTest() async {
        let test = BLEAuthorizationTest()
        let result = await test.run()
        
        #expect(result.testId == "ble-authorization")
        #expect(result.category == .bluetooth)
    }
    
    @Test("All BLE tests have correct priority order")
    func blePriorityOrder() {
        let central = BLECentralStateTest()
        let background = BLEBackgroundModeTest()
        let restoration = BLEStateRestorationTest()
        let auth = BLEAuthorizationTest()
        
        #expect(central.priority < background.priority)
        #expect(background.priority < restoration.priority)
        #expect(restoration.priority < auth.priority)
    }
}

// MARK: - Quirks Database Tests

@Suite("Quirks Database Tests")
struct QuirksDatabaseTests {
    
    @Test("QuirksRegistry has all quirks loaded")
    func registryHasQuirks() {
        let registry = QuirksRegistry.shared
        #expect(registry.quirks.count >= 20)
    }
    
    @Test("Quirks can be filtered by category")
    func filterByCategory() {
        let registry = QuirksRegistry.shared
        let bleQuirks = registry.quirks(in: .bluetooth)
        
        #expect(bleQuirks.count >= 5)
        #expect(bleQuirks.allSatisfy { $0.category == .bluetooth })
    }
    
    @Test("Quirks can be filtered by severity")
    func filterBySeverity() {
        let registry = QuirksRegistry.shared
        let criticalQuirks = registry.quirks(severity: .critical)
        
        #expect(criticalQuirks.count >= 1)
        #expect(criticalQuirks.allSatisfy { $0.severity == .critical })
    }
    
    @Test("IOSVersionRange contains works correctly")
    func versionRangeContains() {
        let range = IOSVersionRange(min: "17.0", max: "17.1")
        
        #expect(range.contains("17.0") == true)
        #expect(range.contains("17.0.1") == true)
        #expect(range.contains("17.1") == true)
        #expect(range.contains("16.5") == false)
        #expect(range.contains("17.2") == false)
    }
    
    @Test("IOSVersionRange all matches everything")
    func versionRangeAll() {
        let range = IOSVersionRange.all
        
        #expect(range.contains("14.0") == true)
        #expect(range.contains("17.0") == true)
        #expect(range.contains("99.0") == true)
    }
    
    @Test("Quirk can be found by ID")
    func findQuirkById() {
        let registry = QuirksRegistry.shared
        let quirk = registry.quirk(id: "QUIRK-BLE-001")
        
        #expect(quirk != nil)
        #expect(quirk?.title == "Background Scan Delay")
    }
    
    @Test("QuirkDetectionTest returns result")
    func quirkDetectionTest() async {
        let test = QuirkDetectionTest()
        let result = await test.run()
        
        #expect(result.testId == "quirk-detection")
        #expect(result.status == .passed)
        #expect(result.details?["totalQuirks"] != nil)
    }
    
    @Test("QuirkSummaryTest returns category counts")
    func quirkSummaryTest() async {
        let test = QuirkSummaryTest()
        let result = await test.run()
        
        #expect(result.testId == "quirk-summary")
        #expect(result.status == .passed)
        #expect(result.details?["bluetooth"] != nil)
    }
    
    @Test("LowPowerModeTest returns result")
    func lowPowerModeTest() async {
        let test = LowPowerModeTest()
        let result = await test.run()
        
        #expect(result.testId == "low-power-mode")
        // On Linux it's unsupported, on macOS/iOS it's passed
    }
    
    @Test("BackgroundAppRefreshTest returns result")
    func backgroundAppRefreshTest() async {
        let test = BackgroundAppRefreshTest()
        let result = await test.run()
        
        #expect(result.testId == "background-app-refresh")
    }
}

// MARK: - Notification Tests

@Suite("Notification Tests", .serialized)
struct NotificationTestsTests {
    
    @Test("NotificationAuthorizationTest returns result")
    func notificationAuthorizationTest() async {
        let test = NotificationAuthorizationTest()
        let result = await test.run()
        
        #expect(result.testId == "notif-authorization")
        #expect(result.category == .notification)
        #if canImport(UserNotifications)
        #expect(result.status == .passed || result.status == .skipped || result.status == .failed)
        #else
        #expect(result.status == .unsupported)
        #endif
    }
    
    @Test("CriticalAlertsTest returns result")
    func criticalAlertsTest() async {
        let test = CriticalAlertsTest()
        let result = await test.run()
        
        #expect(result.testId == "notif-critical-alerts")
        #expect(result.category == .notification)
    }
    
    @Test("TimeSensitiveTest returns result")
    func timeSensitiveTest() async {
        let test = TimeSensitiveTest()
        let result = await test.run()
        
        #expect(result.testId == "notif-time-sensitive")
        #expect(result.category == .notification)
        #expect(test.minimumIOSVersion == "15.0")
    }
    
    @Test("NotificationSoundTest returns result")
    func notificationSoundTest() async {
        let test = NotificationSoundTest()
        let result = await test.run()
        
        #expect(result.testId == "notif-sound")
        #expect(result.category == .notification)
    }
    
    @Test("AlertStyleTest returns result")
    func alertStyleTest() async {
        let test = AlertStyleTest()
        let result = await test.run()
        
        #expect(result.testId == "notif-alert-style")
        #expect(result.category == .notification)
    }
    
    @Test("ScheduledDeliveryTest returns result")
    func scheduledDeliveryTest() async {
        let test = ScheduledDeliveryTest()
        let result = await test.run()
        
        #expect(result.testId == "notif-scheduled-delivery")
        #expect(result.category == .notification)
    }
    
    @Test("All notification tests have correct priority order")
    func notificationPriorityOrder() {
        let auth = NotificationAuthorizationTest()
        let critical = CriticalAlertsTest()
        let timeSensitive = TimeSensitiveTest()
        let sound = NotificationSoundTest()
        let alertStyle = AlertStyleTest()
        let scheduled = ScheduledDeliveryTest()
        
        #expect(auth.priority < critical.priority)
        #expect(critical.priority < timeSensitive.priority)
        #expect(timeSensitive.priority < sound.priority)
        #expect(sound.priority < alertStyle.priority)
        #expect(alertStyle.priority < scheduled.priority)
    }
    
    @Test("registerBuiltinTests includes notification tests")
    func builtinIncludesNotificationTests() async {
        // Use allBuiltinTests() to avoid shared registry race conditions
        let allTests = allBuiltinTests()
        let notifTests = allTests.filter { $0.category == .notification }
        #expect(notifTests.count >= 6)
    }
}

// MARK: - HealthKit Tests

@Suite("HealthKit Tests", .serialized)
struct HealthKitTestsTests {
    
    @Test("HealthKitAvailabilityTest returns result")
    func healthKitAvailabilityTest() async {
        let test = HealthKitAvailabilityTest()
        let result = await test.run()
        
        #expect(result.testId == "hk-availability")
        #expect(result.category == .healthkit)
        #if canImport(HealthKit)
        #expect(result.status == .passed || result.status == .failed)
        #else
        #expect(result.status == .unsupported)
        #endif
    }
    
    @Test("HealthKitAuthorizationTest returns result")
    func healthKitAuthorizationTest() async {
        let test = HealthKitAuthorizationTest()
        let result = await test.run()
        
        #expect(result.testId == "hk-authorization")
        #expect(result.category == .healthkit)
    }
    
    @Test("HealthKitGlucoseWriteTest returns result")
    func healthKitGlucoseWriteTest() async {
        let test = HealthKitGlucoseWriteTest()
        let result = await test.run()
        
        #expect(result.testId == "hk-glucose-write")
        #expect(result.category == .healthkit)
    }
    
    @Test("HealthKitBackgroundDeliveryTest returns result")
    func healthKitBackgroundDeliveryTest() async {
        let test = HealthKitBackgroundDeliveryTest()
        let result = await test.run()
        
        #expect(result.testId == "hk-background-delivery")
        #expect(result.category == .healthkit)
    }
    
    @Test("HealthKitInsulinTypeTest returns result")
    func healthKitInsulinTypeTest() async {
        let test = HealthKitInsulinTypeTest()
        let result = await test.run()
        
        #expect(result.testId == "hk-insulin-type")
        #expect(result.category == .healthkit)
    }
    
    @Test("HealthKitCarbsTypeTest returns result")
    func healthKitCarbsTypeTest() async {
        let test = HealthKitCarbsTypeTest()
        let result = await test.run()
        
        #expect(result.testId == "hk-carbs-type")
        #expect(result.category == .healthkit)
    }
    
    @Test("All HealthKit tests have correct priority order")
    func healthKitPriorityOrder() {
        let availability = HealthKitAvailabilityTest()
        let authorization = HealthKitAuthorizationTest()
        let glucoseWrite = HealthKitGlucoseWriteTest()
        let backgroundDelivery = HealthKitBackgroundDeliveryTest()
        let insulinType = HealthKitInsulinTypeTest()
        let carbsType = HealthKitCarbsTypeTest()
        
        #expect(availability.priority < authorization.priority)
        #expect(authorization.priority < glucoseWrite.priority)
        #expect(glucoseWrite.priority < backgroundDelivery.priority)
        #expect(backgroundDelivery.priority < insulinType.priority)
        #expect(insulinType.priority < carbsType.priority)
    }
    
    @Test("registerBuiltinTests includes HealthKit tests")
    func builtinIncludesHealthKitTests() async {
        // Use allBuiltinTests() to avoid shared registry race conditions
        let allTests = allBuiltinTests()
        let hkTests = allTests.filter { $0.category == .healthkit }
        #expect(hkTests.count >= 6)
    }
}

// MARK: - Colocated App Tests

@Suite("Colocated App Detection Tests")
struct ColocatedAppDetectionTestsTests {
    
    @Test("CGMAppDetectionTest has correct properties")
    func cgmAppTestProperties() {
        let test = CGMAppDetectionTest()
        
        #expect(test.id == "colocated-cgm-apps")
        #expect(test.name == "CGM App Detection")
        #expect(test.category == .colocatedApps)
        #expect(test.priority == 40)
    }
    
    @Test("AIDAppDetectionTest has correct properties")
    func aidAppTestProperties() {
        let test = AIDAppDetectionTest()
        
        #expect(test.id == "colocated-aid-apps")
        #expect(test.name == "AID Controller Detection")
        #expect(test.category == .colocatedApps)
        #expect(test.priority == 41)
    }
    
    @Test("ConflictRiskAssessmentTest has correct properties")
    func conflictRiskTestProperties() {
        let test = ConflictRiskAssessmentTest()
        
        #expect(test.id == "conflict-risk-assessment")
        #expect(test.name == "Conflict Risk Assessment")
        #expect(test.category == .colocatedApps)
        #expect(test.priority == 42)
    }
    
    @Test("CGMAppDetectionTest returns unsupported on Linux")
    func cgmAppTestLinux() async {
        let test = CGMAppDetectionTest()
        let result = await test.run()
        
        // On Linux, should return unsupported
        #expect(result.status == .unsupported)
    }
    
    @Test("AIDAppDetectionTest returns unsupported on Linux")
    func aidAppTestLinux() async {
        let test = AIDAppDetectionTest()
        let result = await test.run()
        
        // On Linux, should return unsupported
        #expect(result.status == .unsupported)
    }
    
    @Test("ConflictRiskAssessmentTest returns unsupported on Linux")
    func conflictRiskTestLinux() async {
        let test = ConflictRiskAssessmentTest()
        let result = await test.run()
        
        // On Linux, should return unsupported
        #expect(result.status == .unsupported)
    }
}

// MARK: - Known Apps Database Tests

@Suite("Known Apps Database Tests")
struct KnownAppsDatabaseTests {
    
    @Test("CGM apps database is populated")
    func cgmAppsPopulated() {
        let cgmApps = KnownAppsDatabase.cgmApps
        
        #expect(cgmApps.count >= 8)
    }
    
    @Test("AID apps database is populated")
    func aidAppsPopulated() {
        let aidApps = KnownAppsDatabase.aidApps
        
        #expect(aidApps.count >= 7)
    }
    
    @Test("Dexcom G6 is in CGM database")
    func dexcomG6InDatabase() {
        let g6 = KnownAppsDatabase.cgmApps.first { $0.id == "dexcom-g6" }
        
        #expect(g6 != nil)
        #expect(g6?.name == "Dexcom G6")
        #expect(g6?.bundleId == "com.dexcom.G6")
        #expect(g6?.conflictRisk == .high)
    }
    
    @Test("Loop is in AID database")
    func loopInDatabase() {
        let loop = KnownAppsDatabase.aidApps.first { $0.id == "loop" }
        
        #expect(loop != nil)
        #expect(loop?.name == "Loop")
        #expect(loop?.bundleId == "com.loopkit.Loop")
        #expect(loop?.conflictRisk == .critical)
    }
    
    @Test("Trio is in AID database")
    func trioInDatabase() {
        let trio = KnownAppsDatabase.aidApps.first { $0.id == "trio" }
        
        #expect(trio != nil)
        #expect(trio?.name == "Trio")
        #expect(trio?.conflictRisk == .critical)
    }
    
    @Test("All AID apps have guidance")
    func aidAppsHaveGuidance() {
        for app in KnownAppsDatabase.aidApps {
            #expect(!app.guidance.isEmpty, "AID app \(app.name) should have guidance")
        }
    }
    
    @Test("Critical AID apps mention disabling")
    func criticalAppsHaveDisableGuidance() {
        let criticalApps = KnownAppsDatabase.aidApps.filter { $0.conflictRisk == .critical }
        
        #expect(criticalApps.count >= 4)
        
        for app in criticalApps {
            let guidanceLower = app.guidance.lowercased()
            let hasDisable = guidanceLower.contains("disable") || 
                             guidanceLower.contains("only one") ||
                             guidanceLower.contains("cannot use")
            #expect(hasDisable, "Critical app \(app.name) guidance should mention disabling")
        }
    }
}

// MARK: - App Detection Result Tests

@Suite("App Detection Result Tests")
struct AppDetectionResultTests {
    
    @Test("Empty result has no conflicts")
    func emptyResultNoConflicts() {
        let result = AppDetectionResult()
        
        #expect(!result.hasAnyConflicts)
        #expect(!result.hasCGMConflicts)
        #expect(!result.hasAIDConflicts)
        #expect(!result.hasCriticalConflicts)
        #expect(result.totalDetected == 0)
    }
    
    @Test("Result with CGM app has CGM conflicts")
    func resultWithCGMConflicts() {
        let cgmApp = KnownAppsDatabase.cgmApps[0]
        let result = AppDetectionResult(detectedCGMApps: [cgmApp])
        
        #expect(result.hasCGMConflicts)
        #expect(!result.hasAIDConflicts)
        #expect(result.hasAnyConflicts)
        #expect(result.totalDetected == 1)
    }
    
    @Test("Result with AID app has AID conflicts")
    func resultWithAIDConflicts() {
        let aidApp = KnownAppsDatabase.aidApps[0]
        let result = AppDetectionResult(detectedAIDApps: [aidApp])
        
        #expect(!result.hasCGMConflicts)
        #expect(result.hasAIDConflicts)
        #expect(result.hasAnyConflicts)
        #expect(result.totalDetected == 1)
    }
    
    @Test("Critical risk is calculated correctly")
    func criticalRiskCalculation() {
        let loopApp = KnownAppsDatabase.aidApps.first { $0.id == "loop" }!
        let result = AppDetectionResult(detectedAIDApps: [loopApp])
        
        #expect(result.highestRisk == .critical)
        #expect(result.hasCriticalConflicts)
    }
    
    @Test("Highest risk takes precedence")
    func highestRiskPrecedence() {
        let lowRiskCGM = KnownAppsDatabase.cgmApps.first { $0.conflictRisk == .low }!
        let criticalAID = KnownAppsDatabase.aidApps.first { $0.conflictRisk == .critical }!
        
        let result = AppDetectionResult(
            detectedCGMApps: [lowRiskCGM],
            detectedAIDApps: [criticalAID]
        )
        
        #expect(result.highestRisk == .critical)
    }
}

// MARK: - Conflict Risk Tests

@Suite("Conflict Risk Tests")
struct ConflictRiskTests {
    
    @Test("All risk levels exist")
    func allRiskLevels() {
        let risks: [ConflictRisk] = [.low, .medium, .high, .critical]
        #expect(risks.count == 4)
    }
    
    @Test("Risk is codable")
    func riskCodable() throws {
        let risk = ConflictRisk.critical
        let encoded = try JSONEncoder().encode(risk)
        let decoded = try JSONDecoder().decode(ConflictRisk.self, from: encoded)
        
        #expect(decoded == risk)
    }
}

// MARK: - Colocated Apps Category Tests

@Suite("Colocated Apps Category Tests", .serialized)
struct ColocatedAppsCategoryTests {
    
    @Test("Category has correct properties")
    func categoryProperties() {
        let category = CapabilityCategory.colocatedApps
        
        #expect(category == .colocatedApps)
        #expect(category.displayName == "Colocated Apps")
        #expect(category.rawValue == "colocated-apps")
    }
    
    @Test("Registry includes colocated app tests")
    func registryIncludesColocatedTests() async {
        // Use allBuiltinTests() to avoid shared registry race conditions
        let allTests = allBuiltinTests()
        let colocatedTests = allTests.filter { $0.category == .colocatedApps }
        
        #expect(colocatedTests.count >= 3)
    }
}

// MARK: - Intended Use Tests

@Suite("IntendedUseModeTests")
struct IntendedUseModeTests {
    
    @Test("Mode raw values")
    func modeRawValues() {
        #expect(IntendedUseMode.demo.rawValue == "demo")
        #expect(IntendedUseMode.cgmOnly.rawValue == "cgm-only")
        #expect(IntendedUseMode.aidController.rawValue == "aid-controller")
    }
    
    @Test("Mode display names")
    func modeDisplayNames() {
        #expect(IntendedUseMode.demo.displayName == "Demo Mode")
        #expect(IntendedUseMode.cgmOnly.displayName == "CGM-Only Mode")
        #expect(IntendedUseMode.aidController.displayName == "AID Controller Mode")
    }
    
    @Test("Mode risk levels")
    func modeRiskLevels() {
        #expect(IntendedUseMode.demo.riskLevel == .minimal)
        #expect(IntendedUseMode.cgmOnly.riskLevel == .low)
        #expect(IntendedUseMode.aidController.riskLevel == .high)
    }
    
    @Test("Risk level raw values")
    func riskLevelRawValues() {
        #expect(RiskLevel.minimal.rawValue == "minimal")
        #expect(RiskLevel.low.rawValue == "low")
        #expect(RiskLevel.moderate.rawValue == "moderate")
        #expect(RiskLevel.high.rawValue == "high")
    }
}

@Suite("IntendedUseVerifier Tests")
struct IntendedUseVerifierTests {
    
    @Test("Demo mode verification")
    func demoModeVerification() {
        let verifier = IntendedUseVerifier()
        let results: [CapabilityResult] = []
        
        let verification = verifier.verify(mode: .demo, testResults: results)
        
        #expect(verification.mode == .demo)
        #expect(verification.criticalFailures.isEmpty)
    }
    
    @Test("CGM mode verification")
    func cgmModeVerification() {
        let verifier = IntendedUseVerifier()
        let results: [CapabilityResult] = []
        
        let verification = verifier.verify(mode: .cgmOnly, testResults: results)
        
        #expect(verification.mode == .cgmOnly)
    }
    
    @Test("AID mode verification")
    func aidModeVerification() {
        let verifier = IntendedUseVerifier()
        let results: [CapabilityResult] = []
        
        let verification = verifier.verify(mode: .aidController, testResults: results)
        
        #expect(verification.mode == .aidController)
    }
    
    @Test("All modes verified together")
    func allModesVerifiedTogether() {
        let verifier = IntendedUseVerifier()
        let results: [CapabilityResult] = []
        
        let verifications = verifier.verifyAllModes(testResults: results)
        
        #expect(verifications.count == 3)
        #expect(verifications.contains { $0.mode == .demo })
        #expect(verifications.contains { $0.mode == .cgmOnly })
        #expect(verifications.contains { $0.mode == .aidController })
    }
}

@Suite("Intended Use Capability Tests", .serialized)
struct IntendedUseCapabilityTests {
    
    @Test("Demo mode test passes")
    func demoModeTestPasses() async {
        let test = DemoModeCompatibilityTest()
        
        #expect(test.id == "intended-use-demo")
        #expect(test.category == .intendedUse)
        #expect(test.priority == 50)
        
        let result = await test.run()
        
        #expect(result.status == .passed)
        #expect(result.message.contains("Demo Mode"))
        #expect(result.details?["mode"] == "demo")
        #expect(result.details?["riskLevel"] == "minimal")
    }
    
    @Test("CGM-Only mode test")
    func cgmOnlyModeTest() async {
        let registry = CapabilityRegistry.shared
        await registry.clear()
        
        let test = CGMOnlyCompatibilityTest(registry: registry)
        
        #expect(test.id == "intended-use-cgm-only")
        #expect(test.category == .intendedUse)
        #expect(test.priority == 51)
        
        let result = await test.run()
        
        // On Linux, CoreBluetooth unavailable → failed
        // On iOS, CoreBluetooth available → passed
        #expect(result.details?["mode"] == "cgm-only")
    }
    
    @Test("AID controller mode test")
    func aidControllerModeTest() async {
        let registry = CapabilityRegistry.shared
        await registry.clear()
        
        let test = AIDControllerCompatibilityTest(registry: registry)
        
        #expect(test.id == "intended-use-aid-controller")
        #expect(test.category == .intendedUse)
        #expect(test.priority == 52)
        
        let result = await test.run()
        
        #expect(result.details?["mode"] == "aid-controller")
        #expect(result.details?["riskLevel"] == "high")
    }
    
    @Test("Device report test")
    func deviceReportTest() async {
        let test = DeviceCompatibilityReportTest()
        
        #expect(test.id == "device-compatibility-report")
        #expect(test.category == .intendedUse)
        #expect(test.priority == 53)
        
        let result = await test.run()
        
        #expect(result.status == .passed)
        #expect(result.message.contains("Device report generated"))
        #expect(result.details?["compatibleModeCount"] != nil)
    }
    
    @Test("intendedUse category exists")
    func intendedUseCategoryExists() {
        let category = CapabilityCategory.intendedUse
        
        #expect(category == .intendedUse)
        #expect(category.displayName == "Intended Use")
        #expect(category.rawValue == "intended-use")
    }
    
    @Test("Registry includes intended use tests")
    func registryIncludesIntendedUseTests() async {
        // Use allBuiltinTests() to avoid shared registry race conditions
        let allTests = allBuiltinTests()
        let intendedUseTests = allTests.filter { $0.category == .intendedUse }
        
        #expect(intendedUseTests.count >= 4)
    }
}

@Suite("DeviceReportInfo Tests")
struct DeviceReportInfoTests {
    
    @Test("Current device info captures values")
    func currentDeviceInfoCapturesValues() {
        let info = DeviceReportInfo.current
        
        #expect(!info.model.isEmpty)
        #expect(!info.osVersion.isEmpty)
        #expect(!info.appVersion.isEmpty)
    }
}

// Watch/Widget/Device tests moved to DeviceCompatibilityTests.swift (CODE-031)

