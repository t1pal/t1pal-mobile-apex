import XCTest
@testable import T1PalCore

final class PumpStatusBadgeTests: XCTestCase {
    
    // MARK: - Badge Type Tests
    
    func testBadgeTypeSymbolNames() {
        for type in PumpStatusBadge.BadgeType.allCases {
            XCTAssertFalse(type.symbolName.isEmpty, "\(type) should have symbol")
        }
    }
    
    func testBadgeTypeDescriptions() {
        for type in PumpStatusBadge.BadgeType.allCases {
            XCTAssertFalse(type.localizedDescription.isEmpty, "\(type) should have description")
        }
    }
    
    func testBadgeTypeDefaultStates() {
        // Warning states
        XCTAssertEqual(PumpStatusBadge.BadgeType.timeSyncNeeded.defaultState, .warning)
        XCTAssertEqual(PumpStatusBadge.BadgeType.lowReservoir.defaultState, .warning)
        XCTAssertEqual(PumpStatusBadge.BadgeType.lowBattery.defaultState, .warning)
        XCTAssertEqual(PumpStatusBadge.BadgeType.podExpiring.defaultState, .warning)
        
        // Critical states
        XCTAssertEqual(PumpStatusBadge.BadgeType.suspended.defaultState, .critical)
        XCTAssertEqual(PumpStatusBadge.BadgeType.emptyReservoir.defaultState, .critical)
        XCTAssertEqual(PumpStatusBadge.BadgeType.criticalBattery.defaultState, .critical)
        XCTAssertEqual(PumpStatusBadge.BadgeType.podExpired.defaultState, .critical)
        XCTAssertEqual(PumpStatusBadge.BadgeType.communicationLost.defaultState, .critical)
        XCTAssertEqual(PumpStatusBadge.BadgeType.occlusion.defaultState, .critical)
    }
    
    // MARK: - Badge Set Evaluation Tests
    
    func testEvaluateEmpty() {
        let set = PumpStatusBadgeSet.evaluate()
        XCTAssertFalse(set.hasBadges)
        XCTAssertEqual(set.count, 0)
        XCTAssertEqual(set.mostSevereState, .normalPump)
    }
    
    func testEvaluateSuspended() {
        let set = PumpStatusBadgeSet.evaluate(suspended: true)
        XCTAssertTrue(set.hasBadges)
        XCTAssertTrue(set.contains(.suspended))
        XCTAssertTrue(set.hasCritical)
        XCTAssertEqual(set.mostSevereState, .critical)
    }
    
    func testEvaluateLowReservoir() {
        let set = PumpStatusBadgeSet.evaluate(reservoirUnits: 15.0)
        XCTAssertTrue(set.contains(.lowReservoir))
        XCTAssertTrue(set.hasWarning)
        XCTAssertFalse(set.hasCritical)
    }
    
    func testEvaluateEmptyReservoir() {
        let set = PumpStatusBadgeSet.evaluate(reservoirUnits: 0.0)
        XCTAssertTrue(set.contains(.emptyReservoir))
        XCTAssertTrue(set.hasCritical)
    }
    
    func testEvaluateReservoirOK() {
        let set = PumpStatusBadgeSet.evaluate(reservoirUnits: 100.0)
        XCTAssertFalse(set.contains(.lowReservoir))
        XCTAssertFalse(set.contains(.emptyReservoir))
    }
    
    func testEvaluateLowBattery() {
        let set = PumpStatusBadgeSet.evaluate(batteryPercent: 15.0)
        XCTAssertTrue(set.contains(.lowBattery))
        XCTAssertTrue(set.hasWarning)
    }
    
    func testEvaluateCriticalBattery() {
        let set = PumpStatusBadgeSet.evaluate(batteryPercent: 3.0)
        XCTAssertTrue(set.contains(.criticalBattery))
        XCTAssertTrue(set.hasCritical)
    }
    
    func testEvaluateBatteryOK() {
        let set = PumpStatusBadgeSet.evaluate(batteryPercent: 80.0)
        XCTAssertFalse(set.contains(.lowBattery))
        XCTAssertFalse(set.contains(.criticalBattery))
    }
    
    func testEvaluatePodExpiring() {
        let set = PumpStatusBadgeSet.evaluate(podHoursRemaining: 6.0)
        XCTAssertTrue(set.contains(.podExpiring))
        XCTAssertTrue(set.hasWarning)
    }
    
    func testEvaluatePodExpired() {
        let set = PumpStatusBadgeSet.evaluate(podHoursRemaining: 0.0)
        XCTAssertTrue(set.contains(.podExpired))
        XCTAssertTrue(set.hasCritical)
    }
    
    func testEvaluatePodOK() {
        let set = PumpStatusBadgeSet.evaluate(podHoursRemaining: 48.0)
        XCTAssertFalse(set.contains(.podExpiring))
        XCTAssertFalse(set.contains(.podExpired))
    }
    
    func testEvaluateTimeSyncNeeded() {
        let set = PumpStatusBadgeSet.evaluate(timeSyncNeeded: true)
        XCTAssertTrue(set.contains(.timeSyncNeeded))
        XCTAssertTrue(set.hasWarning)
    }
    
    func testEvaluateCommunicationLost() {
        let set = PumpStatusBadgeSet.evaluate(communicationLost: true)
        XCTAssertTrue(set.contains(.communicationLost))
        XCTAssertTrue(set.hasCritical)
    }
    
    func testEvaluateOcclusion() {
        let set = PumpStatusBadgeSet.evaluate(occlusionDetected: true)
        XCTAssertTrue(set.contains(.occlusion))
        XCTAssertTrue(set.hasCritical)
    }
    
    func testEvaluateMultipleBadges() {
        let set = PumpStatusBadgeSet.evaluate(
            suspended: true,
            reservoirUnits: 10.0,
            batteryPercent: 15.0
        )
        XCTAssertEqual(set.count, 3)
        XCTAssertTrue(set.contains(.suspended))
        XCTAssertTrue(set.contains(.lowReservoir))
        XCTAssertTrue(set.contains(.lowBattery))
    }
    
    func testEvaluateCustomThresholds() {
        // Default threshold is 20, using 10 - should not trigger low
        let set = PumpStatusBadgeSet.evaluate(
            reservoirUnits: 15.0,
            lowReservoirThreshold: 10.0
        )
        XCTAssertFalse(set.contains(.lowReservoir))
        
        // With higher threshold - should trigger
        let set2 = PumpStatusBadgeSet.evaluate(
            reservoirUnits: 15.0,
            lowReservoirThreshold: 20.0
        )
        XCTAssertTrue(set2.contains(.lowReservoir))
    }
    
    // MARK: - Badge Set Properties
    
    func testBadgesByState() {
        let set = PumpStatusBadgeSet.evaluate(
            suspended: true,
            reservoirUnits: 15.0,
            timeSyncNeeded: true
        )
        
        let critical = set.criticalBadges
        let warning = set.warningBadges
        
        XCTAssertEqual(critical.count, 1)
        XCTAssertEqual(warning.count, 2)
    }
    
    func testSingleBadge() {
        let set = PumpStatusBadgeSet.single(.suspended)
        XCTAssertEqual(set.count, 1)
        XCTAssertTrue(set.contains(.suspended))
        XCTAssertEqual(set.badges[0].state, .critical)
    }
    
    func testSingleBadgeCustomState() {
        let set = PumpStatusBadgeSet.single(.needsAttention, state: .critical)
        XCTAssertEqual(set.badges[0].state, .critical)
    }
    
    // MARK: - ReservoirAlertState Tests
    
    func testReservoirAlertStateEvaluate() {
        XCTAssertEqual(ReservoirAlertState.evaluate(units: 100), .ok)
        XCTAssertEqual(ReservoirAlertState.evaluate(units: 15), .low)
        XCTAssertEqual(ReservoirAlertState.evaluate(units: 0), .empty)
        XCTAssertEqual(ReservoirAlertState.evaluate(units: nil), .ok)
    }
    
    func testReservoirAlertStateElementState() {
        XCTAssertEqual(ReservoirAlertState.ok.elementState, .normalPump)
        XCTAssertEqual(ReservoirAlertState.low.elementState, .warning)
        XCTAssertEqual(ReservoirAlertState.empty.elementState, .critical)
    }
    
    // MARK: - BatteryAlertState Tests
    
    func testBatteryAlertStateEvaluate() {
        XCTAssertEqual(BatteryAlertState.evaluate(percent: 80), .ok)
        XCTAssertEqual(BatteryAlertState.evaluate(percent: 15), .low)
        XCTAssertEqual(BatteryAlertState.evaluate(percent: 3), .critical)
        XCTAssertEqual(BatteryAlertState.evaluate(percent: nil), .ok)
    }
    
    func testBatteryAlertStateElementState() {
        XCTAssertEqual(BatteryAlertState.ok.elementState, .normalPump)
        XCTAssertEqual(BatteryAlertState.low.elementState, .warning)
        XCTAssertEqual(BatteryAlertState.critical.elementState, .critical)
    }
    
    // MARK: - PodLifecycleState Tests
    
    func testPodLifecycleStateEvaluate() {
        // Active
        if case .active(let hours) = PodLifecycleState.evaluate(hoursRemaining: 48) {
            XCTAssertEqual(hours, 48)
        } else {
            XCTFail("Expected active state")
        }
        
        // Expiring soon
        if case .expiringSoon(let hours) = PodLifecycleState.evaluate(hoursRemaining: 6) {
            XCTAssertEqual(hours, 6)
        } else {
            XCTFail("Expected expiringSoon state")
        }
        
        // Expired
        XCTAssertEqual(PodLifecycleState.evaluate(hoursRemaining: 0), .expired)
        XCTAssertEqual(PodLifecycleState.evaluate(hoursRemaining: -1), .expired)
        
        // Deactivated
        XCTAssertEqual(PodLifecycleState.evaluate(hoursRemaining: 48, isDeactivated: true), .deactivated)
        
        // Not configured
        XCTAssertEqual(PodLifecycleState.evaluate(hoursRemaining: nil), .notConfigured)
    }
    
    func testPodLifecycleStateCanDeliver() {
        XCTAssertTrue(PodLifecycleState.active(hoursRemaining: 48).canDeliver)
        XCTAssertTrue(PodLifecycleState.expiringSoon(hoursRemaining: 6).canDeliver)
        XCTAssertFalse(PodLifecycleState.expired.canDeliver)
        XCTAssertFalse(PodLifecycleState.deactivated.canDeliver)
        XCTAssertFalse(PodLifecycleState.notConfigured.canDeliver)
    }
    
    func testPodLifecycleStateElementState() {
        XCTAssertEqual(PodLifecycleState.active(hoursRemaining: 48).elementState, .normalPump)
        XCTAssertEqual(PodLifecycleState.expiringSoon(hoursRemaining: 6).elementState, .warning)
        XCTAssertEqual(PodLifecycleState.expired.elementState, .critical)
    }
    
    // MARK: - Codable Tests
    
    func testBadgeCodable() throws {
        let badge = PumpStatusBadge(type: .suspended, state: .critical)
        let encoded = try JSONEncoder().encode(badge)
        let decoded = try JSONDecoder().decode(PumpStatusBadge.self, from: encoded)
        
        XCTAssertEqual(badge.type, decoded.type)
        XCTAssertEqual(badge.state, decoded.state)
    }
    
    func testBadgeSetCodable() throws {
        let set = PumpStatusBadgeSet.evaluate(suspended: true, reservoirUnits: 15.0)
        let encoded = try JSONEncoder().encode(set)
        let decoded = try JSONDecoder().decode(PumpStatusBadgeSet.self, from: encoded)
        
        XCTAssertEqual(set.count, decoded.count)
        XCTAssertTrue(decoded.contains(.suspended))
    }
    
    // MARK: - Description Tests
    
    func testDescription() {
        let empty = PumpStatusBadgeSet.empty()
        XCTAssertTrue(empty.description.contains("empty"))
        
        let set = PumpStatusBadgeSet.evaluate(suspended: true)
        XCTAssertTrue(set.description.contains("suspended"))
    }
    
    // MARK: - Sendable Conformance
    
    func testSendableConformance() async {
        let set = PumpStatusBadgeSet.evaluate(suspended: true)
        
        let result = await Task.detached {
            return set.hasCritical
        }.value
        
        XCTAssertTrue(result)
    }
}
