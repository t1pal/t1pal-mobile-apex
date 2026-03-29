/// Tests for StaleInsulinState handling
/// AID-PARTIAL-004 verification

import XCTest
@testable import T1PalCore

final class StaleInsulinStateTests: XCTestCase {
    
    // MARK: - Basic State Tests
    
    func testFreshInsulinNotStale() {
        let recentDose = Date().addingTimeInterval(-3600)  // 1 hour ago
        let state = StaleInsulinState.evaluate(
            lastDoseTime: recentDose,
            diaSeconds: 21600  // 6 hours
        )
        
        XCTAssertFalse(state.isStale)
        XCTAssertNotNil(state.lastDoseTime)
    }
    
    func testOldInsulinIsStale() {
        let oldDose = Date().addingTimeInterval(-25200)  // 7 hours ago
        let state = StaleInsulinState.evaluate(
            lastDoseTime: oldDose,
            diaSeconds: 21600  // 6 hours
        )
        
        XCTAssertTrue(state.isStale)
    }
    
    func testNoDoseDataIsStale() {
        let state = StaleInsulinState.evaluate(
            lastDoseTime: nil,
            diaSeconds: 21600
        )
        
        XCTAssertTrue(state.isStale)
        XCTAssertNil(state.lastDoseTime)
    }
    
    func testExactlyAtDIABoundary() {
        let now = Date()
        let atBoundary = now.addingTimeInterval(-21600)  // Exactly 6 hours
        let state = StaleInsulinState.evaluate(
            lastDoseTime: atBoundary,
            diaSeconds: 21600,
            evaluatedAt: now
        )
        
        // At exactly DIA, not stale (boundary is inclusive)
        XCTAssertFalse(state.isStale)
    }
    
    func testJustPastDIABoundary() {
        let now = Date()
        let pastBoundary = now.addingTimeInterval(-21601)  // 6 hours + 1 second
        let state = StaleInsulinState.evaluate(
            lastDoseTime: pastBoundary,
            diaSeconds: 21600,
            evaluatedAt: now
        )
        
        XCTAssertTrue(state.isStale)
    }
    
    // MARK: - IOB Display Tests (Critical)
    
    func testDisplayIOBReturnsZeroWhenStale() {
        let oldDose = Date().addingTimeInterval(-25200)  // 7 hours ago
        let state = StaleInsulinState.evaluate(lastDoseTime: oldDose)
        
        let calculatedIOB = 2.5
        let displayIOB = state.displayIOB(calculatedIOB: calculatedIOB)
        
        XCTAssertEqual(displayIOB, 0.0, "IOB must be 0 when stale")
    }
    
    func testDisplayIOBReturnsActualWhenFresh() {
        let recentDose = Date().addingTimeInterval(-3600)  // 1 hour ago
        let state = StaleInsulinState.evaluate(lastDoseTime: recentDose)
        
        let calculatedIOB = 2.5
        let displayIOB = state.displayIOB(calculatedIOB: calculatedIOB)
        
        XCTAssertEqual(displayIOB, 2.5, "IOB should be actual value when fresh")
    }
    
    func testFormatIOBWhenStale() {
        let oldDose = Date().addingTimeInterval(-25200)
        let state = StaleInsulinState.evaluate(lastDoseTime: oldDose)
        
        let formatted = state.formatIOB(calculatedIOB: 2.5)
        
        XCTAssertEqual(formatted, "0.00 U")
    }
    
    func testFormatIOBWhenFresh() {
        let recentDose = Date().addingTimeInterval(-3600)
        let state = StaleInsulinState.evaluate(lastDoseTime: recentDose)
        
        let formatted = state.formatIOB(calculatedIOB: 2.5)
        
        XCTAssertEqual(formatted, "2.50 U")
    }
    
    // MARK: - Standard DIA Tests
    
    func testEvaluateWithStandardDIA() {
        let now = Date()
        let recentDose = now.addingTimeInterval(-14000)  // ~3.9 hours ago (within 4h DIA)
        
        // With rapid DIA (4h), this should be fresh (just under boundary)
        let rapidState = StaleInsulinState.evaluate(
            lastDoseTime: recentDose,
            dia: .rapid,  // 4 hours
            evaluatedAt: now
        )
        XCTAssertFalse(rapidState.isStale)  // Within DIA, not stale
        
        // With extended DIA (6h), this should also be fresh
        let extendedState = StaleInsulinState.evaluate(
            lastDoseTime: recentDose,
            dia: .extended,  // 6 hours
            evaluatedAt: now
        )
        XCTAssertFalse(extendedState.isStale)
    }
    
    // MARK: - DIA Elapsed Percent Tests
    
    func testDIAElapsedPercent() {
        let now = Date()
        let halfwayDose = now.addingTimeInterval(-10800)  // 3 hours ago (50% of 6h)
        let state = StaleInsulinState.evaluate(
            lastDoseTime: halfwayDose,
            diaSeconds: 21600,
            evaluatedAt: now
        )
        
        XCTAssertEqual(state.diaElapsedPercent, 50, accuracy: 1)
    }
    
    func testDIAElapsedPercentCappedAt100() {
        let now = Date()
        let veryOldDose = now.addingTimeInterval(-50000)  // Way past DIA
        let state = StaleInsulinState.evaluate(
            lastDoseTime: veryOldDose,
            diaSeconds: 21600,
            evaluatedAt: now
        )
        
        XCTAssertEqual(state.diaElapsedPercent, 100)
    }
    
    func testDIAElapsedPercentNoDose() {
        let state = StaleInsulinState.evaluate(lastDoseTime: nil)
        
        XCTAssertEqual(state.diaElapsedPercent, 100)
    }
    
    // MARK: - Status Text Tests
    
    func testIOBStatusTextStale() {
        let oldDose = Date().addingTimeInterval(-25200)
        let state = StaleInsulinState.evaluate(lastDoseTime: oldDose)
        
        XCTAssertEqual(state.iobStatusText, "stale")
    }
    
    func testIOBStatusTextActive() {
        let recentDose = Date().addingTimeInterval(-3600)
        let state = StaleInsulinState.evaluate(lastDoseTime: recentDose)
        
        XCTAssertEqual(state.iobStatusText, "active")
    }
    
    func testStatusMessageNoData() {
        let state = StaleInsulinState.evaluate(lastDoseTime: nil)
        
        XCTAssertEqual(state.statusMessage, "No insulin data available")
    }
    
    func testStatusMessageStale() {
        let oldDose = Date().addingTimeInterval(-25200)  // 7 hours
        let state = StaleInsulinState.evaluate(lastDoseTime: oldDose)
        
        XCTAssertTrue(state.statusMessage.contains("stale"))
        XCTAssertTrue(state.statusMessage.contains("7.0"))
    }
    
    func testStatusMessageActive() {
        let recentDose = Date().addingTimeInterval(-3600)  // 1 hour ago
        let state = StaleInsulinState.evaluate(
            lastDoseTime: recentDose,
            diaSeconds: 21600
        )
        
        XCTAssertTrue(state.statusMessage.contains("Active"))
        XCTAssertTrue(state.statusMessage.contains("remaining"))
    }
    
    // MARK: - Element State Tests
    
    func testElementStateStale() {
        let oldDose = Date().addingTimeInterval(-25200)
        let state = StaleInsulinState.evaluate(lastDoseTime: oldDose)
        
        XCTAssertEqual(state.elementState, .warning)  // Warning, not error
    }
    
    func testElementStateFresh() {
        let recentDose = Date().addingTimeInterval(-3600)
        let state = StaleInsulinState.evaluate(lastDoseTime: recentDose)
        
        XCTAssertEqual(state.elementState, .normalPump)
    }
    
    // MARK: - Indicator Tests
    
    func testShowStaleIndicator() {
        let oldDose = Date().addingTimeInterval(-25200)
        let state = StaleInsulinState.evaluate(lastDoseTime: oldDose)
        
        XCTAssertTrue(state.showStaleIndicator)
    }
    
    func testIconName() {
        let oldDose = Date().addingTimeInterval(-25200)
        let staleState = StaleInsulinState.evaluate(lastDoseTime: oldDose)
        XCTAssertEqual(staleState.iconName, "clock.badge.exclamationmark")
        
        let recentDose = Date().addingTimeInterval(-3600)
        let freshState = StaleInsulinState.evaluate(lastDoseTime: recentDose)
        XCTAssertEqual(freshState.iconName, "drop.fill")
    }
    
    // MARK: - IOBDisplayValue Tests
    
    func testIOBDisplayValueStale() {
        let oldDose = Date().addingTimeInterval(-25200)
        let display = IOBDisplayValue(
            calculatedIOB: 2.5,
            lastDoseTime: oldDose
        )
        
        XCTAssertEqual(display.displayValue, 0.0)
        XCTAssertEqual(display.formatted, "0.00 U")
        XCTAssertTrue(display.isStale)
    }
    
    func testIOBDisplayValueFresh() {
        let recentDose = Date().addingTimeInterval(-3600)
        let display = IOBDisplayValue(
            calculatedIOB: 2.5,
            lastDoseTime: recentDose
        )
        
        XCTAssertEqual(display.displayValue, 2.5)
        XCTAssertEqual(display.formatted, "2.50 U")
        XCTAssertFalse(display.isStale)
    }
    
    // MARK: - InsulinFreshness Integration Tests
    
    func testFromInsulinFreshness() {
        let freshness = InsulinFreshness(
            lastDoseDate: Date().addingTimeInterval(-25200),
            dia: .extended
        )
        
        let state = StaleInsulinState.from(freshness)
        
        XCTAssertTrue(state.isStale)
        XCTAssertEqual(state.diaSeconds, InsulinFreshness.StandardDIA.extended.rawValue)
    }
    
    func testInsulinFreshnessStaleStateProperty() {
        let freshness = InsulinFreshness(
            lastDoseDate: Date().addingTimeInterval(-3600),
            dia: .standard
        )
        
        let state = freshness.staleState
        
        XCTAssertFalse(state.isStale)
    }
    
    func testInsulinFreshnessIOBDisplay() {
        let freshness = InsulinFreshness(
            lastDoseDate: Date().addingTimeInterval(-25200),
            dia: .extended
        )
        
        let display = freshness.iobDisplay(calculatedIOB: 2.5)
        
        XCTAssertEqual(display.displayValue, 0.0)
        XCTAssertTrue(display.isStale)
    }
    
    // MARK: - Codable Tests
    
    func testCodable() throws {
        let state = StaleInsulinState.evaluate(
            lastDoseTime: Date().addingTimeInterval(-3600),
            diaSeconds: 21600
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StaleInsulinState.self, from: data)
        
        XCTAssertEqual(decoded.isStale, state.isStale)
        XCTAssertEqual(decoded.diaSeconds, state.diaSeconds)
    }
    
    // MARK: - Description Tests
    
    func testDescription() {
        let recentDose = Date().addingTimeInterval(-10800)  // 3 hours (50%)
        let state = StaleInsulinState.evaluate(
            lastDoseTime: recentDose,
            diaSeconds: 21600
        )
        
        XCTAssertTrue(state.description.contains("active"))
        XCTAssertTrue(state.description.contains("50%"))
    }
}
