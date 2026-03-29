import Testing
import Foundation
@testable import PumpKit

/// Tests for ReservoirMonitor - reservoir and battery lifecycle tracking
/// Trace: LIFE-PUMP-004, LIFE-PUMP-005
@Suite("ReservoirMonitor Tests", .serialized)
struct ReservoirMonitorTests {
    
    // MARK: - ReservoirWarning Tests
    
    @Test("Reservoir warning thresholds are correct")
    func reservoirWarningThresholds() {
        #expect(ReservoirWarning.units50.rawValue == 50)
        #expect(ReservoirWarning.units20.rawValue == 20)
        #expect(ReservoirWarning.units10.rawValue == 10)
        #expect(ReservoirWarning.empty.rawValue == 0)
    }
    
    @Test("Reservoir warning for level returns correct warning")
    func reservoirWarningForLevel() {
        // Above all thresholds
        #expect(ReservoirWarning.forUnitsRemaining(60) == nil)
        #expect(ReservoirWarning.forUnitsRemaining(50.1) == nil)
        
        // At/below 50U
        #expect(ReservoirWarning.forUnitsRemaining(50) == .units50)
        #expect(ReservoirWarning.forUnitsRemaining(49) == .units50)
        #expect(ReservoirWarning.forUnitsRemaining(21) == .units50)
        
        // At/below 20U
        #expect(ReservoirWarning.forUnitsRemaining(20) == .units20)
        #expect(ReservoirWarning.forUnitsRemaining(19) == .units20)
        #expect(ReservoirWarning.forUnitsRemaining(11) == .units20)
        
        // At/below 10U
        #expect(ReservoirWarning.forUnitsRemaining(10) == .units10)
        #expect(ReservoirWarning.forUnitsRemaining(5) == .units10)
        #expect(ReservoirWarning.forUnitsRemaining(1) == .units10)
        
        // Empty
        #expect(ReservoirWarning.forUnitsRemaining(0) == .empty)
    }
    
    @Test("Reservoir warning messages contain threshold values")
    func reservoirWarningMessages() {
        #expect(ReservoirWarning.units50.message.contains("50"))
        #expect(ReservoirWarning.units20.message.contains("20"))
        #expect(ReservoirWarning.units10.message.contains("10"))
        #expect(ReservoirWarning.empty.message.lowercased().contains("empty"))
    }
    
    // MARK: - PumpBatteryWarning Tests
    
    @Test("Battery warning thresholds are correct")
    func batteryWarningThresholds() {
        #expect(PumpBatteryWarning.low.rawValue == 20)
        #expect(PumpBatteryWarning.critical.rawValue == 10)
        #expect(PumpBatteryWarning.empty.rawValue == 0)
    }
    
    @Test("Battery warning for level returns correct warning")
    func batteryWarningForLevel() {
        // Above all thresholds
        #expect(PumpBatteryWarning.forBatteryLevel(0.5) == nil)
        #expect(PumpBatteryWarning.forBatteryLevel(0.21) == nil)
        
        // At/below 20%
        #expect(PumpBatteryWarning.forBatteryLevel(0.20) == .low)
        #expect(PumpBatteryWarning.forBatteryLevel(0.15) == .low)
        #expect(PumpBatteryWarning.forBatteryLevel(0.11) == .low)
        
        // At/below 10%
        #expect(PumpBatteryWarning.forBatteryLevel(0.10) == .critical)
        #expect(PumpBatteryWarning.forBatteryLevel(0.05) == .critical)
        #expect(PumpBatteryWarning.forBatteryLevel(0.01) == .critical)
        
        // Dead
        #expect(PumpBatteryWarning.forBatteryLevel(0.0) == .empty)
    }
    
    @Test("Battery warning messages contain severity")
    func batteryWarningMessages() {
        #expect(PumpBatteryWarning.low.message.lowercased().contains("low"))
        #expect(PumpBatteryWarning.critical.message.lowercased().contains("critical"))
        #expect(PumpBatteryWarning.empty.message.lowercased().contains("empty"))
    }
    
    // MARK: - ReservoirStatus Tests
    
    @Test("Reservoir status initialization")
    func reservoirStatusInitialization() {
        let now = Date()
        let status = ReservoirStatus(
            pumpId: "123456",
            currentLevel: 120,
            capacity: 300,
            timestamp: now
        )
        
        #expect(status.pumpId == "123456")
        #expect(status.currentLevel == 120)
        #expect(status.capacity == 300)
        #expect(status.timestamp == now)
    }
    
    @Test("Reservoir status percentage calculation")
    func reservoirStatusPercentage() {
        let status = ReservoirStatus(
            pumpId: "123456",
            currentLevel: 150,
            capacity: 300,
            timestamp: Date()
        )
        #expect(abs(status.percentRemaining - 0.5) < 0.001)
    }
    
    @Test("Reservoir status current warning")
    func reservoirStatusCurrentWarning() {
        let highStatus = ReservoirStatus(pumpId: "123456", currentLevel: 100, capacity: 300, timestamp: Date())
        #expect(highStatus.warningLevel == nil)
        
        let lowStatus = ReservoirStatus(pumpId: "123456", currentLevel: 15, capacity: 300, timestamp: Date())
        #expect(lowStatus.warningLevel == .units20)
    }
    
    // MARK: - PumpBatteryStatus Tests
    
    @Test("Battery status initialization")
    func batteryStatusInitialization() {
        let now = Date()
        let status = PumpBatteryStatus(
            pumpId: "123456",
            level: 0.75,
            timestamp: now
        )
        
        #expect(status.pumpId == "123456")
        #expect(status.level == 0.75)
        #expect(status.timestamp == now)
    }
    
    @Test("Battery status current warning")
    func batteryStatusCurrentWarning() {
        let highStatus = PumpBatteryStatus(pumpId: "123456", level: 0.50, timestamp: Date())
        #expect(highStatus.warningLevel == nil)
        
        let lowStatus = PumpBatteryStatus(pumpId: "123456", level: 0.08, timestamp: Date())
        #expect(lowStatus.warningLevel == .critical)
    }
    
    // MARK: - ReservoirWarningState Tests
    
    @Test("Reservoir warning state sent tracking")
    func reservoirWarningStateSentTracking() {
        var state = ReservoirWarningState(pumpId: "123456")
        
        // Initially empty
        #expect(!state.wasReservoirWarningSent(.units50))
        #expect(!state.wasBatteryWarningSent(.low))
        
        // Mark warnings as sent
        state.markReservoirWarningSent(.units50)
        state.markBatteryWarningSent(.low)
        
        #expect(state.wasReservoirWarningSent(.units50))
        #expect(state.wasBatteryWarningSent(.low))
        #expect(!state.wasReservoirWarningSent(.units20))
        #expect(!state.wasBatteryWarningSent(.critical))
    }
    
    @Test("Reservoir warning state reset")
    func reservoirWarningStateReset() {
        var state = ReservoirWarningState(pumpId: "123456")
        
        state.markReservoirWarningSent(.units50)
        state.markReservoirWarningSent(.units20)
        state.markBatteryWarningSent(.low)
        state.markBatteryWarningSent(.critical)
        
        // Reset reservoir warnings only
        state.resetReservoirWarnings()
        #expect(!state.wasReservoirWarningSent(.units50))
        #expect(!state.wasReservoirWarningSent(.units20))
        #expect(state.wasBatteryWarningSent(.low))
        #expect(state.wasBatteryWarningSent(.critical))
        
        // Reset battery warnings
        state.resetBatteryWarnings()
        #expect(!state.wasBatteryWarningSent(.low))
        #expect(!state.wasBatteryWarningSent(.critical))
    }
    
    // MARK: - ReservoirMonitor Actor Tests
    
    @Test("Monitor start tracking")
    func monitorStartTracking() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        
        let reservoirStatus = await monitor.currentReservoirStatus()
        #expect(reservoirStatus?.pumpId == "123456")
        #expect(reservoirStatus?.capacity == 300)
    }
    
    @Test("Monitor update reservoir level")
    func monitorUpdateReservoirLevel() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateReservoirLevel(150)
        
        let status = await monitor.currentReservoirStatus()
        #expect(status?.currentLevel == 150)
    }
    
    @Test("Monitor update battery level")
    func monitorUpdateBatteryLevel() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateBatteryLevel(0.75)
        
        let status = await monitor.currentBatteryStatus()
        #expect(status?.level == 0.75)
    }
    
    @Test("Monitor check reservoir no warning")
    func monitorCheckReservoirNoWarning() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateReservoirLevel(100) // Above 50U threshold
        
        let result = await monitor.checkReservoir()
        switch result {
        case .healthy:
            break // Expected
        default:
            Issue.record("Expected .healthy for high reservoir level")
        }
    }
    
    @Test("Monitor check reservoir warning")
    func monitorCheckReservoirWarning() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateReservoirLevel(15) // Below 20U threshold
        
        let result = await monitor.checkReservoir()
        switch result {
        case .warning(let notification):
            #expect(notification.warning == .units20)
        default:
            Issue.record("Expected warning for low reservoir")
        }
    }
    
    @Test("Monitor check reservoir already sent")
    func monitorCheckReservoirAlreadySent() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateReservoirLevel(15) // Below 20U threshold
        await monitor.markReservoirWarningSent(.units20)
        
        let result = await monitor.checkReservoir()
        switch result {
        case .alreadySent:
            break // Expected
        default:
            Issue.record("Expected .alreadySent for already notified warning")
        }
    }
    
    @Test("Monitor check battery no warning")
    func monitorCheckBatteryNoWarning() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateBatteryLevel(0.50) // Above 20% threshold
        
        let result = await monitor.checkBattery()
        switch result {
        case .healthy:
            break // Expected
        default:
            Issue.record("Expected .healthy for high battery level")
        }
    }
    
    @Test("Monitor check battery warning")
    func monitorCheckBatteryWarning() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateBatteryLevel(0.08) // Below 10% threshold
        
        let result = await monitor.checkBattery()
        switch result {
        case .warning(let notification):
            #expect(notification.warning == .critical)
        default:
            Issue.record("Expected warning for low battery")
        }
    }
    
    @Test("Monitor check battery already sent")
    func monitorCheckBatteryAlreadySent() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateBatteryLevel(0.08) // Below 10% threshold
        await monitor.markBatteryWarningSent(.critical)
        
        let result = await monitor.checkBattery()
        switch result {
        case .alreadySent:
            break // Expected
        default:
            Issue.record("Expected .alreadySent for already notified warning")
        }
    }
    
    @Test("Monitor reservoir changed resets warnings")
    func monitorReservoirChanged() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateReservoirLevel(15)
        await monitor.markReservoirWarningSent(.units20)
        
        // Verify warning was sent
        var result = await monitor.checkReservoir()
        switch result {
        case .alreadySent:
            break // Expected
        default:
            Issue.record("Expected .alreadySent before reservoir change")
        }
        
        // Change reservoir
        await monitor.reservoirChanged()
        await monitor.updateReservoirLevel(15) // Same level
        
        // Warning should trigger again
        result = await monitor.checkReservoir()
        switch result {
        case .warning(let notification):
            #expect(notification.warning == .units20)
        default:
            Issue.record("Expected warning after reservoir change")
        }
    }
    
    @Test("Monitor battery changed resets warnings")
    func monitorBatteryChanged() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.updateBatteryLevel(0.08)
        await monitor.markBatteryWarningSent(.critical)
        
        // Verify warning was sent
        var result = await monitor.checkBattery()
        switch result {
        case .alreadySent:
            break // Expected
        default:
            Issue.record("Expected .alreadySent before battery change")
        }
        
        // Change battery
        await monitor.batteryChanged()
        await monitor.updateBatteryLevel(0.08) // Same level
        
        // Warning should trigger again
        result = await monitor.checkBattery()
        switch result {
        case .warning(let notification):
            #expect(notification.warning == .critical)
        default:
            Issue.record("Expected warning after battery change")
        }
    }
    
    @Test("Monitor stop tracking clears state")
    func monitorStopTracking() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        await monitor.stopTracking()
        
        let status = await monitor.currentReservoirStatus()
        #expect(status == nil)
    }
    
    // MARK: - Warning Escalation Tests
    
    @Test("Warning escalation through thresholds")
    func warningEscalation() async {
        let persistence = InMemoryReservoirPersistence()
        let monitor = ReservoirMonitor(persistence: persistence)
        
        await monitor.startTracking(pumpId: "123456", reservoirCapacity: 300)
        
        // Start with units50 warning
        await monitor.updateReservoirLevel(40)
        var result = await monitor.checkReservoir()
        switch result {
        case .warning(let n): #expect(n.warning == .units50)
        default: Issue.record("Expected units50 warning")
        }
        await monitor.markReservoirWarningSent(.units50)
        
        // Drop to units20 - should get new warning
        await monitor.updateReservoirLevel(15)
        result = await monitor.checkReservoir()
        switch result {
        case .warning(let n): #expect(n.warning == .units20)
        default: Issue.record("Expected units20 warning (escalation)")
        }
        await monitor.markReservoirWarningSent(.units20)
        
        // Drop to units10 - should get new warning
        await monitor.updateReservoirLevel(5)
        result = await monitor.checkReservoir()
        switch result {
        case .warning(let n): #expect(n.warning == .units10)
        default: Issue.record("Expected units10 warning (escalation)")
        }
        await monitor.markReservoirWarningSent(.units10)
        
        // Drop to empty - should get new warning
        await monitor.updateReservoirLevel(0)
        result = await monitor.checkReservoir()
        switch result {
        case .warning(let n): #expect(n.warning == .empty)
        default: Issue.record("Expected empty warning (escalation)")
        }
    }
    
    // MARK: - Persistence Tests
    
    @Test("In-memory persistence save and load")
    func inMemoryPersistence() async {
        let persistence = InMemoryReservoirPersistence()
        
        // Initially nil
        var state = await persistence.loadWarningState()
        #expect(state == nil)
        
        // Save and load
        var newState = ReservoirWarningState(pumpId: "123456")
        newState.markReservoirWarningSent(.units50)
        await persistence.saveWarningState(newState)
        
        state = await persistence.loadWarningState()
        #expect(state != nil)
        #expect(state!.wasReservoirWarningSent(.units50))
        
        // Clear
        await persistence.clearState()
        state = await persistence.loadWarningState()
        #expect(state == nil)
    }
    
    // MARK: - MinimedManager Integration Tests
    
    @Test("MinimedManager reservoir monitoring")
    func minimedManagerReservoirMonitoring() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model722)
        
        // Check initial reservoir status
        let status = await manager.getReservoirStatus()
        #expect(status != nil)
        #expect(status?.pumpId == "123456")
        #expect(status?.capacity == MinimedPumpModel.model722.reservoirCapacity)
        
        // Update reservoir level
        await manager.updateReservoirLevel(50)
        let updatedStatus = await manager.getReservoirStatus()
        #expect(updatedStatus?.currentLevel == 50)
        
        try await manager.unpairPump()
    }
    
    @Test("MinimedManager battery monitoring")
    func minimedManagerBatteryMonitoring() async throws {
        let manager = MinimedManager()
        
        try await manager.pairPump(pumpId: "123456", model: .model722)
        
        // Check initial battery status
        let status = await manager.getBatteryStatus()
        #expect(status != nil)
        #expect(status?.level == 1.0)
        
        // Update battery level
        await manager.updateBatteryLevel(0.5)
        let updatedStatus = await manager.getBatteryStatus()
        #expect(updatedStatus?.level == 0.5)
        
        try await manager.unpairPump()
    }
    
    @Test("MinimedManager warning callbacks")
    func minimedManagerWarningCallbacks() async throws {
        let manager = MinimedManager()
        
        actor WarningCollector {
            var reservoirWarnings: [ReservoirNotification] = []
            var batteryWarnings: [PumpBatteryNotification] = []
            
            func addReservoir(_ n: ReservoirNotification) {
                reservoirWarnings.append(n)
            }
            
            func addBattery(_ n: PumpBatteryNotification) {
                batteryWarnings.append(n)
            }
        }
        
        let collector = WarningCollector()
        
        await manager.setReservoirWarningHandler { notification in
            await collector.addReservoir(notification)
        }
        
        await manager.setBatteryWarningHandler { notification in
            await collector.addBattery(notification)
        }
        
        try await manager.pairPump(pumpId: "123456", model: .model722)
        
        // Set low reservoir
        await manager.updateReservoirLevel(15)
        await manager.checkConsumables()
        
        let rWarnings = await collector.reservoirWarnings
        #expect(rWarnings.count == 1)
        #expect(rWarnings.first?.warning == .units20)
        
        // Set low battery
        await manager.updateBatteryLevel(0.08)
        await manager.checkConsumables()
        
        let bWarnings = await collector.batteryWarnings
        #expect(bWarnings.count == 1)
        #expect(bWarnings.first?.warning == .critical)
        
        try await manager.unpairPump()
    }
}
