import XCTest
@testable import T1PalCore

final class DeviceStatusTypesTests: XCTestCase {
    
    // MARK: - DeviceStatusElementState Tests
    
    func testElementStateIsNormal() {
        XCTAssertTrue(DeviceStatusElementState.normalCGM.isNormal)
        XCTAssertTrue(DeviceStatusElementState.normalPump.isNormal)
        XCTAssertFalse(DeviceStatusElementState.warning.isNormal)
        XCTAssertFalse(DeviceStatusElementState.critical.isNormal)
    }
    
    func testElementStateNeedsAttention() {
        XCTAssertTrue(DeviceStatusElementState.critical.needsAttention)
        XCTAssertTrue(DeviceStatusElementState.warning.needsAttention)
        XCTAssertFalse(DeviceStatusElementState.normalCGM.needsAttention)
        XCTAssertFalse(DeviceStatusElementState.normalPump.needsAttention)
    }
    
    func testElementStateSortPriority() {
        // Critical sorts first (0), then warning (1), then normal (2)
        XCTAssertEqual(DeviceStatusElementState.critical.sortPriority, 0)
        XCTAssertEqual(DeviceStatusElementState.warning.sortPriority, 1)
        XCTAssertEqual(DeviceStatusElementState.normalCGM.sortPriority, 2)
        XCTAssertEqual(DeviceStatusElementState.normalPump.sortPriority, 2)
        
        // Verify sort ordering works
        let states: [DeviceStatusElementState] = [.normalCGM, .critical, .normalPump, .warning]
        let sorted = states.sorted { $0.sortPriority < $1.sortPriority }
        XCTAssertEqual(sorted.first, .critical)
        XCTAssertEqual(sorted.last, .normalPump) // or normalCGM, both have same priority
    }
    
    func testElementStateCodable() throws {
        let states: [DeviceStatusElementState] = [.critical, .warning, .normalCGM, .normalPump]
        
        for state in states {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(DeviceStatusElementState.self, from: encoded)
            XCTAssertEqual(state, decoded)
        }
    }
    
    func testElementStateRawValues() {
        XCTAssertEqual(DeviceStatusElementState.critical.rawValue, "critical")
        XCTAssertEqual(DeviceStatusElementState.warning.rawValue, "warning")
        XCTAssertEqual(DeviceStatusElementState.normalCGM.rawValue, "normalCGM")
        XCTAssertEqual(DeviceStatusElementState.normalPump.rawValue, "normalPump")
    }
    
    func testElementStateCaseIterable() {
        XCTAssertEqual(DeviceStatusElementState.allCases.count, 4)
        XCTAssertTrue(DeviceStatusElementState.allCases.contains(.critical))
        XCTAssertTrue(DeviceStatusElementState.allCases.contains(.warning))
        XCTAssertTrue(DeviceStatusElementState.allCases.contains(.normalCGM))
        XCTAssertTrue(DeviceStatusElementState.allCases.contains(.normalPump))
    }
    
    // MARK: - DeviceLifecycleProgressState Tests
    
    func testLifecycleProgressStateToElementState() {
        XCTAssertEqual(DeviceLifecycleProgressState.critical.elementState, .critical)
        XCTAssertEqual(DeviceLifecycleProgressState.warning.elementState, .warning)
        XCTAssertEqual(DeviceLifecycleProgressState.normalCGM.elementState, .normalCGM)
        XCTAssertEqual(DeviceLifecycleProgressState.normalPump.elementState, .normalPump)
        XCTAssertEqual(DeviceLifecycleProgressState.dimmed.elementState, .normalCGM) // dimmed defaults to normalCGM
    }
    
    func testLifecycleProgressStateIsActive() {
        XCTAssertTrue(DeviceLifecycleProgressState.critical.isActive)
        XCTAssertTrue(DeviceLifecycleProgressState.warning.isActive)
        XCTAssertTrue(DeviceLifecycleProgressState.normalCGM.isActive)
        XCTAssertTrue(DeviceLifecycleProgressState.normalPump.isActive)
        XCTAssertFalse(DeviceLifecycleProgressState.dimmed.isActive)
    }
    
    func testLifecycleProgressStateCodable() throws {
        let states: [DeviceLifecycleProgressState] = [.critical, .dimmed, .normalCGM, .normalPump, .warning]
        
        for state in states {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(DeviceLifecycleProgressState.self, from: encoded)
            XCTAssertEqual(state, decoded)
        }
    }
    
    func testLifecycleProgressStateCaseIterable() {
        XCTAssertEqual(DeviceLifecycleProgressState.allCases.count, 5)
        XCTAssertTrue(DeviceLifecycleProgressState.allCases.contains(.dimmed))
    }
    
    // MARK: - Sendable Conformance
    
    func testSendableConformance() async {
        // Verify types can be safely passed across concurrency boundaries
        let elementState: DeviceStatusElementState = .critical
        let progressState: DeviceLifecycleProgressState = .warning
        
        let result = await Task.detached {
            return (elementState.isNormal, progressState.isActive)
        }.value
        
        XCTAssertFalse(result.0)
        XCTAssertTrue(result.1)
    }
}
