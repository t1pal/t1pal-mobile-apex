/// Tests for LoopMode enum
/// AID-PARTIAL-001 and AID-PARTIAL-002 verification

import XCTest
@testable import T1PalCore

final class LoopModeTests: XCTestCase {
    
    // MARK: - Basic Enum Tests
    
    func testAllCases() {
        let allCases = LoopMode.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.cgmOnly))
        XCTAssertTrue(allCases.contains(.openLoop))
        XCTAssertTrue(allCases.contains(.tempBasalOnly))
        XCTAssertTrue(allCases.contains(.closedLoop))
    }
    
    func testRawValues() {
        XCTAssertEqual(LoopMode.cgmOnly.rawValue, "CGM Only")
        XCTAssertEqual(LoopMode.openLoop.rawValue, "Open Loop")
        XCTAssertEqual(LoopMode.tempBasalOnly.rawValue, "Temp Basal Only")
        XCTAssertEqual(LoopMode.closedLoop.rawValue, "Closed Loop")
    }
    
    // MARK: - RequiresPump Tests (AID-PARTIAL-002)
    
    func testCgmOnlyDoesNotRequirePump() {
        XCTAssertFalse(LoopMode.cgmOnly.requiresPump, "cgmOnly must not require pump")
    }
    
    func testOpenLoopRequiresPump() {
        XCTAssertTrue(LoopMode.openLoop.requiresPump)
    }
    
    func testTempBasalOnlyRequiresPump() {
        XCTAssertTrue(LoopMode.tempBasalOnly.requiresPump)
    }
    
    func testClosedLoopRequiresPump() {
        XCTAssertTrue(LoopMode.closedLoop.requiresPump)
    }
    
    // MARK: - RequiresCGM Tests
    
    func testAllModesRequireCGM() {
        for mode in LoopMode.allCases {
            XCTAssertTrue(mode.requiresCGM, "\(mode) should require CGM")
        }
    }
    
    // MARK: - Automation Tests
    
    func testCgmOnlyNotAutomated() {
        XCTAssertFalse(LoopMode.cgmOnly.isAutomationEnabled)
        XCTAssertFalse(LoopMode.cgmOnly.tempBasalEnabled)
        XCTAssertFalse(LoopMode.cgmOnly.automatedBolusEnabled)
    }
    
    func testOpenLoopNotAutomated() {
        XCTAssertFalse(LoopMode.openLoop.isAutomationEnabled)
        XCTAssertFalse(LoopMode.openLoop.tempBasalEnabled)
        XCTAssertFalse(LoopMode.openLoop.automatedBolusEnabled)
    }
    
    func testTempBasalOnlyPartialAutomation() {
        XCTAssertTrue(LoopMode.tempBasalOnly.isAutomationEnabled)
        XCTAssertTrue(LoopMode.tempBasalOnly.tempBasalEnabled)
        XCTAssertFalse(LoopMode.tempBasalOnly.automatedBolusEnabled)
    }
    
    func testClosedLoopFullAutomation() {
        XCTAssertTrue(LoopMode.closedLoop.isAutomationEnabled)
        XCTAssertTrue(LoopMode.closedLoop.tempBasalEnabled)
        XCTAssertTrue(LoopMode.closedLoop.automatedBolusEnabled)
    }
    
    // MARK: - Automation Level Tests
    
    func testAutomationLevelOrdering() {
        XCTAssertEqual(LoopMode.cgmOnly.automationLevel, 0)
        XCTAssertEqual(LoopMode.openLoop.automationLevel, 1)
        XCTAssertEqual(LoopMode.tempBasalOnly.automationLevel, 2)
        XCTAssertEqual(LoopMode.closedLoop.automationLevel, 3)
        
        // Verify ordering
        XCTAssertTrue(LoopMode.cgmOnly.automationLevel < LoopMode.openLoop.automationLevel)
        XCTAssertTrue(LoopMode.openLoop.automationLevel < LoopMode.tempBasalOnly.automationLevel)
        XCTAssertTrue(LoopMode.tempBasalOnly.automationLevel < LoopMode.closedLoop.automationLevel)
    }
    
    func testModesAtOrAbove() {
        let cgmOnlyAbove = LoopMode.cgmOnly.modesAtOrAbove
        XCTAssertEqual(cgmOnlyAbove.count, 4)  // All modes
        
        let closedLoopAbove = LoopMode.closedLoop.modesAtOrAbove
        XCTAssertEqual(closedLoopAbove.count, 1)
        XCTAssertTrue(closedLoopAbove.contains(.closedLoop))
    }
    
    func testFallbackModes() {
        let closedLoopFallbacks = LoopMode.closedLoop.fallbackModes
        XCTAssertEqual(closedLoopFallbacks.count, 3)
        XCTAssertTrue(closedLoopFallbacks.contains(.tempBasalOnly))
        XCTAssertTrue(closedLoopFallbacks.contains(.openLoop))
        XCTAssertTrue(closedLoopFallbacks.contains(.cgmOnly))
        
        let cgmOnlyFallbacks = LoopMode.cgmOnly.fallbackModes
        XCTAssertEqual(cgmOnlyFallbacks.count, 0)  // No fallback from minimum
    }
    
    func testBestFallback() {
        XCTAssertEqual(LoopMode.closedLoop.bestFallback, .tempBasalOnly)
        XCTAssertEqual(LoopMode.tempBasalOnly.bestFallback, .openLoop)
        XCTAssertEqual(LoopMode.openLoop.bestFallback, .cgmOnly)
        XCTAssertEqual(LoopMode.cgmOnly.bestFallback, .cgmOnly)
    }
    
    // MARK: - Display Properties Tests
    
    func testShortNames() {
        XCTAssertEqual(LoopMode.cgmOnly.shortName, "CGM")
        XCTAssertEqual(LoopMode.openLoop.shortName, "Open")
        XCTAssertEqual(LoopMode.tempBasalOnly.shortName, "Temp")
        XCTAssertEqual(LoopMode.closedLoop.shortName, "Closed")
    }
    
    func testIconNames() {
        for mode in LoopMode.allCases {
            XCTAssertFalse(mode.iconName.isEmpty)
        }
    }
    
    func testModeDescriptions() {
        for mode in LoopMode.allCases {
            XCTAssertFalse(mode.modeDescription.isEmpty)
        }
    }
    
    func testDescription() {
        XCTAssertEqual(LoopMode.cgmOnly.description, "CGM Only")
    }
    
    // MARK: - Status Element State Tests
    
    func testStatusElementState() {
        XCTAssertEqual(LoopMode.cgmOnly.statusElementState, .normalCGM)
        XCTAssertEqual(LoopMode.openLoop.statusElementState, .warning)
        XCTAssertEqual(LoopMode.tempBasalOnly.statusElementState, .normalPump)
        XCTAssertEqual(LoopMode.closedLoop.statusElementState, .normalPump)
    }
    
    // MARK: - Activation Tests
    
    func testCgmOnlyCanActivateWithoutPump() {
        let result = LoopMode.cgmOnly.canActivate(
            hasCGM: true,
            hasPump: false  // No pump!
        )
        XCTAssertTrue(result.canActivate, "cgmOnly should work without pump")
    }
    
    func testCgmOnlyRequiresCGM() {
        let result = LoopMode.cgmOnly.canActivate(
            hasCGM: false,
            hasPump: false
        )
        XCTAssertFalse(result.canActivate)
        
        if case .missingRequirements(let missing) = result {
            XCTAssertTrue(missing.contains("CGM"))
        } else {
            XCTFail("Expected missing requirements")
        }
    }
    
    func testClosedLoopRequiresAllConfiguration() {
        let result = LoopMode.closedLoop.canActivate(
            hasCGM: true,
            hasPump: true,
            hasBasalSchedule: false,
            hasInsulinSensitivity: true,
            hasCarbRatio: true,
            hasGlucoseTarget: true
        )
        
        XCTAssertFalse(result.canActivate)
        if case .missingRequirements(let missing) = result {
            XCTAssertTrue(missing.contains("Basal Schedule"))
        }
    }
    
    func testOpenLoopDoesNotRequireConfiguration() {
        // Open loop doesn't automate, so doesn't need full config
        let result = LoopMode.openLoop.canActivate(
            hasCGM: true,
            hasPump: true,
            hasBasalSchedule: false,
            hasInsulinSensitivity: false,
            hasCarbRatio: false,
            hasGlucoseTarget: false
        )
        
        XCTAssertTrue(result.canActivate)
    }
    
    // MARK: - Transition Tests
    
    func testTransitionCreation() {
        let transition = LoopModeTransition(
            from: .closedLoop,
            to: .cgmOnly,
            reason: .pumpDisconnected
        )
        
        XCTAssertEqual(transition.from, .closedLoop)
        XCTAssertEqual(transition.to, .cgmOnly)
        XCTAssertEqual(transition.reason, .pumpDisconnected)
        XCTAssertNotNil(transition.timestamp)
    }
    
    func testTransitionIsDowngrade() {
        let downgrade = LoopModeTransition(from: .closedLoop, to: .openLoop)
        XCTAssertTrue(downgrade.isDowngrade)
        XCTAssertFalse(downgrade.isUpgrade)
    }
    
    func testTransitionIsUpgrade() {
        let upgrade = LoopModeTransition(from: .openLoop, to: .closedLoop)
        XCTAssertTrue(upgrade.isUpgrade)
        XCTAssertFalse(upgrade.isDowngrade)
    }
    
    func testTransitionSameLevel() {
        let same = LoopModeTransition(from: .closedLoop, to: .closedLoop)
        XCTAssertFalse(same.isUpgrade)
        XCTAssertFalse(same.isDowngrade)
    }
    
    // MARK: - Codable Tests
    
    func testCodable() throws {
        let mode = LoopMode.closedLoop
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(mode)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LoopMode.self, from: data)
        
        XCTAssertEqual(decoded, mode)
    }
    
    func testTransitionReasonCodable() throws {
        let reason = LoopModeTransition.Reason.pumpDisconnected
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(reason)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LoopModeTransition.Reason.self, from: data)
        
        XCTAssertEqual(decoded, reason)
    }
}
