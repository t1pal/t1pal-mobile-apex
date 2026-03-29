import XCTest
@testable import T1PalCore

final class DataFreshnessTests: XCTestCase {
    
    // MARK: - Glucose Freshness Tests
    
    func testGlucoseFresh() {
        // 2 minutes old - should be fresh
        let lastReading = Date().addingTimeInterval(-120)
        let freshness = DataFreshness.glucose(lastReading: lastReading)
        
        XCTAssertTrue(freshness.isFresh)
        XCTAssertFalse(freshness.isStale)
        XCTAssertFalse(freshness.isExpired)
        XCTAssertEqual(freshness.level, .fresh)
        XCTAssertTrue(freshness.level.isUsable)
        XCTAssertFalse(freshness.level.needsAttention)
    }
    
    func testGlucoseStale() {
        // 8 minutes old - should be stale (between 5-12 min)
        let lastReading = Date().addingTimeInterval(-480)
        let freshness = DataFreshness.glucose(lastReading: lastReading)
        
        XCTAssertFalse(freshness.isFresh)
        XCTAssertTrue(freshness.isStale)
        XCTAssertFalse(freshness.isExpired)
        XCTAssertEqual(freshness.level, .stale)
        XCTAssertTrue(freshness.level.isUsable)
        XCTAssertTrue(freshness.level.needsAttention)
    }
    
    func testGlucoseExpired() {
        // 15 minutes old - should be expired (>12 min)
        let lastReading = Date().addingTimeInterval(-900)
        let freshness = DataFreshness.glucose(lastReading: lastReading)
        
        XCTAssertFalse(freshness.isFresh)
        XCTAssertFalse(freshness.isStale)
        XCTAssertTrue(freshness.isExpired)
        XCTAssertEqual(freshness.level, .expired)
        XCTAssertFalse(freshness.level.isUsable)
        XCTAssertTrue(freshness.level.needsAttention)
    }
    
    func testGlucoseNoData() {
        let freshness = DataFreshness.glucose(lastReading: nil)
        
        XCTAssertFalse(freshness.hasData)
        XCTAssertTrue(freshness.isExpired)
        XCTAssertEqual(freshness.level, .noData)
        XCTAssertFalse(freshness.level.isUsable)
    }
    
    func testGlucoseThresholdBoundary() {
        // Use fixed reference date to avoid timing issues
        let now = Date()
        
        // Exactly at 5 min boundary - should still be fresh
        let atFresh = DataFreshness.glucose(lastReading: now.addingTimeInterval(-300), checkDate: now)
        XCTAssertTrue(atFresh.isFresh)
        
        // Just past 5 min - should be stale
        let pastFresh = DataFreshness.glucose(lastReading: now.addingTimeInterval(-301), checkDate: now)
        XCTAssertTrue(pastFresh.isStale)
        
        // At 12 min boundary - should still be stale
        let atExpired = DataFreshness.glucose(lastReading: now.addingTimeInterval(-720), checkDate: now)
        XCTAssertTrue(atExpired.isStale)
        
        // Just past 12 min - should be expired
        let pastExpired = DataFreshness.glucose(lastReading: now.addingTimeInterval(-721), checkDate: now)
        XCTAssertTrue(pastExpired.isExpired)
    }
    
    // MARK: - Insulin Freshness Tests
    
    func testInsulinActive() {
        // 2 hours old - should be active
        let lastDose = Date().addingTimeInterval(-7200)
        let freshness = InsulinFreshness(lastDoseDate: lastDose)
        
        XCTAssertTrue(freshness.isActive)
        XCTAssertFalse(freshness.iobIsZero)
        XCTAssertEqual(freshness.elementState, .normalPump)
    }
    
    func testInsulinExpired() {
        // 8 hours old - should be expired (>6h DIA)
        let lastDose = Date().addingTimeInterval(-28800)
        let freshness = InsulinFreshness(lastDoseDate: lastDose)
        
        XCTAssertFalse(freshness.isActive)
        XCTAssertTrue(freshness.iobIsZero)
        XCTAssertEqual(freshness.elementState, .warning)
    }
    
    func testInsulinDIAPercentage() {
        // 3 hours into 6 hour DIA - 50% elapsed
        let lastDose = Date().addingTimeInterval(-10800)
        let freshness = InsulinFreshness(lastDoseDate: lastDose)
        
        XCTAssertEqual(freshness.diaElapsedPercent, 50, accuracy: 1)
    }
    
    func testInsulinCustomDIA() {
        // 5 hour DIA, 4 hours elapsed - still active
        let lastDose = Date().addingTimeInterval(-14400)
        let freshness = InsulinFreshness(lastDoseDate: lastDose, dia: .standard) // 5 hours
        
        XCTAssertTrue(freshness.isActive)
        XCTAssertFalse(freshness.iobIsZero)
    }
    
    func testInsulinNoData() {
        let freshness = InsulinFreshness(lastDoseDate: nil)
        
        XCTAssertFalse(freshness.isActive)
        XCTAssertTrue(freshness.iobIsZero)
        XCTAssertEqual(freshness.diaElapsedPercent, 100)
    }
    
    // MARK: - Thresholds Tests
    
    func testGlucoseThresholds() {
        XCTAssertEqual(DataFreshness.Thresholds.glucose.freshSeconds, 300)
        XCTAssertEqual(DataFreshness.Thresholds.glucose.expiredSeconds, 720)
        XCTAssertEqual(DataFreshness.Thresholds.glucose.name, "glucose")
    }
    
    func testInsulinThresholds() {
        XCTAssertEqual(DataFreshness.Thresholds.insulin.freshSeconds, 3600)
        XCTAssertEqual(DataFreshness.Thresholds.insulin.expiredSeconds, 21600)
    }
    
    func testPumpThresholds() {
        XCTAssertEqual(DataFreshness.Thresholds.pump.freshSeconds, 300)
        XCTAssertEqual(DataFreshness.Thresholds.pump.expiredSeconds, 1800)
    }
    
    func testLoopCompletionThresholds() {
        XCTAssertEqual(DataFreshness.Thresholds.loopCompletion.freshSeconds, 360)
        XCTAssertEqual(DataFreshness.Thresholds.loopCompletion.expiredSeconds, 960)
    }
    
    // MARK: - DeviceStatusElementState Integration
    
    func testToElementStateCGM() {
        let fresh = DataFreshness.glucose(lastReading: Date())
        XCTAssertEqual(fresh.toElementState(deviceType: .cgm), .normalCGM)
        
        let stale = DataFreshness.glucose(lastReading: Date().addingTimeInterval(-480))
        XCTAssertEqual(stale.toElementState(deviceType: .cgm), .warning)
        
        let expired = DataFreshness.glucose(lastReading: Date().addingTimeInterval(-900))
        XCTAssertEqual(expired.toElementState(deviceType: .cgm), .critical)
    }
    
    func testToElementStatePump() {
        let fresh = DataFreshness.pump(lastCommunication: Date())
        XCTAssertEqual(fresh.toElementState(deviceType: .pump), .normalPump)
        
        let expired = DataFreshness.pump(lastCommunication: Date().addingTimeInterval(-3600))
        XCTAssertEqual(expired.toElementState(deviceType: .pump), .critical)
    }
    
    // MARK: - Codable Tests
    
    func testDataFreshnessCodable() throws {
        let original = DataFreshness.glucose(lastReading: Date())
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DataFreshness.self, from: encoded)
        
        XCTAssertEqual(original.thresholds, decoded.thresholds)
        XCTAssertEqual(original.level, decoded.level)
    }
    
    func testInsulinFreshnessCodable() throws {
        let original = InsulinFreshness(lastDoseDate: Date())
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InsulinFreshness.self, from: encoded)
        
        XCTAssertEqual(original.diaSeconds, decoded.diaSeconds)
        XCTAssertEqual(original.isActive, decoded.isActive)
    }
    
    // MARK: - Description Tests
    
    func testDescription() {
        let fresh = DataFreshness.glucose(lastReading: Date().addingTimeInterval(-30))
        XCTAssertTrue(fresh.description.contains("glucose"))
        XCTAssertTrue(fresh.description.contains("fresh"))
        
        let noData = DataFreshness.glucose(lastReading: nil)
        XCTAssertTrue(noData.description.contains("noData"))
    }
    
    // MARK: - Symbol Names
    
    func testLevelSymbolNames() {
        XCTAssertFalse(DataFreshness.Level.fresh.symbolName.isEmpty)
        XCTAssertFalse(DataFreshness.Level.stale.symbolName.isEmpty)
        XCTAssertFalse(DataFreshness.Level.expired.symbolName.isEmpty)
        XCTAssertFalse(DataFreshness.Level.noData.symbolName.isEmpty)
        
        // Each should be different
        let symbols = DataFreshness.Level.allCases.map { $0.symbolName }
        XCTAssertEqual(Set(symbols).count, 4)
    }
    
    // MARK: - Sendable Conformance
    
    func testSendableConformance() async {
        let freshness = DataFreshness.glucose(lastReading: Date())
        let insulinFreshness = InsulinFreshness(lastDoseDate: Date())
        
        let result = await Task.detached {
            return (freshness.isFresh, insulinFreshness.isActive)
        }.value
        
        XCTAssertTrue(result.0)
        XCTAssertTrue(result.1)
    }
}
