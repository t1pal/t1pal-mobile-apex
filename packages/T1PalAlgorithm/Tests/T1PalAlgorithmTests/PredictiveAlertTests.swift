// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PredictiveAlertTests.swift
// T1Pal Mobile
//
// Tests for predictive glucose alerts
// Trace: GLUCOS-IMPL-002

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("Linear Glucose Predictor")
struct LinearGlucosePredictorTests {
    
    let predictor = LinearGlucosePredictor()
    
    // MARK: - Basic Prediction
    
    @Test("Predict stable glucose")
    func predictStableGlucose() {
        // Stable glucose at 120 mg/dL
        let readings = makeReadings([120, 120, 120, 120, 120])
        
        let predicted = predictor.predict(from: readings)
        
        #expect(predicted != nil)
        #expect(abs(predicted! - 120) < 1)
    }
    
    @Test("Predict rising glucose")
    func predictRisingGlucose() {
        // Rising at 2 mg/dL per 5 min = 24 mg/dL per hour
        let readings = makeReadings([100, 102, 104, 106, 108])
        
        let predicted = predictor.predict(from: readings, horizon: 15 * 60)
        
        #expect(predicted != nil)
        // Should predict ~114 (108 + 6 for 15 minutes)
        #expect(abs(predicted! - 114) < 2)
    }
    
    @Test("Predict falling glucose")
    func predictFallingGlucose() {
        // Falling at 3 mg/dL per 5 min
        let readings = makeReadings([130, 127, 124, 121, 118])
        
        let predicted = predictor.predict(from: readings, horizon: 15 * 60)
        
        #expect(predicted != nil)
        // Should predict ~109 (118 - 9 for 15 minutes)
        #expect(abs(predicted! - 109) < 2)
    }
    
    @Test("Predict clamped low")
    func predictClampedLow() {
        // Rapidly falling - should clamp at 20
        let readings = makeReadings([100, 80, 60, 40, 20])
        
        let predicted = predictor.predict(from: readings, horizon: 15 * 60)
        
        #expect(predicted != nil)
        #expect(predicted! == 20) // Clamped minimum
    }
    
    @Test("Predict clamped high")
    func predictClampedHigh() {
        // Rapidly rising - should clamp at 600
        let readings = makeReadings([400, 450, 500, 550, 600])
        
        let predicted = predictor.predict(from: readings, horizon: 30 * 60)
        
        #expect(predicted != nil)
        #expect(predicted! == 600) // Clamped maximum
    }
    
    // MARK: - Edge Cases
    
    @Test("Insufficient readings")
    func insufficientReadings() {
        let readings = makeReadings([100])
        
        let predicted = predictor.predict(from: readings)
        
        #expect(predicted == nil)
    }
    
    @Test("Empty readings")
    func emptyReadings() {
        let predicted = predictor.predict(from: [])
        
        #expect(predicted == nil)
    }
    
    @Test("Two readings")
    func twoReadings() {
        let readings = makeReadings([100, 110])
        
        let predicted = predictor.predict(from: readings)
        
        #expect(predicted != nil) // Should work with 2 readings
    }
    
    // MARK: - Rate of Change
    
    @Test("Rate of change")
    func rateOfChange() {
        // Rising 2 mg/dL per 5 min = 0.4 mg/dL per minute
        let readings = makeReadings([100, 102, 104, 106, 108])
        
        let rate = predictor.rateOfChange(from: readings)
        
        #expect(rate != nil)
        #expect(abs(rate! - 0.4) < 0.1)
    }
    
    // MARK: - Detailed Prediction
    
    @Test("Predict with details")
    func predictWithDetails() {
        let readings = makeReadings([100, 105, 110, 115, 120])
        
        let prediction = predictor.predictWithDetails(from: readings)
        
        #expect(prediction != nil)
        #expect(prediction!.readingsUsed == 5)
        #expect(prediction!.rateOfChange > 0)
        #expect(prediction!.value > 120)
    }
    
    // MARK: - Helpers
    
    private func makeReadings(_ values: [Double]) -> [GlucoseReading] {
        let now = Date()
        return values.enumerated().map { index, glucose in
            GlucoseReading(
                glucose: glucose,
                timestamp: now.addingTimeInterval(TimeInterval(index - values.count + 1) * 5 * 60),
                trend: .flat
            )
        }
    }
}

// MARK: - Alert Service Tests

@Suite("Predictive Alert Service")
struct PredictiveAlertServiceTests {
    
    @Test("Alert on predicted high")
    func alertOnPredictedHigh() async {
        var settings = PredictiveAlertSettings.defaults
        settings.enabled = true
        settings.highThresholdMgDl = 200
        
        let service = PredictiveAlertService(settings: settings)
        
        // Rapidly rising glucose
        let readings = makeReadings([150, 160, 170, 180, 190])
        
        let event = await service.processReadings(readings)
        
        #expect(event != nil)
        #expect(event?.state == .predictedHigh)
    }
    
    @Test("Alert on predicted low")
    func alertOnPredictedLow() async {
        var settings = PredictiveAlertSettings.defaults
        settings.enabled = true
        settings.lowThresholdMgDl = 70
        
        let service = PredictiveAlertService(settings: settings)
        
        // Rapidly falling glucose
        let readings = makeReadings([100, 95, 90, 85, 80])
        
        let event = await service.processReadings(readings)
        
        #expect(event != nil)
        #expect(event?.state == .predictedLow)
    }
    
    @Test("No alert when disabled")
    func noAlertWhenDisabled() async {
        var settings = PredictiveAlertSettings.defaults
        settings.enabled = false
        
        let service = PredictiveAlertService(settings: settings)
        
        // Would trigger alert if enabled
        let readings = makeReadings([100, 95, 90, 85, 80])
        
        let event = await service.processReadings(readings)
        
        #expect(event == nil)
    }
    
    @Test("No alert when in range")
    func noAlertWhenInRange() async {
        var settings = PredictiveAlertSettings.defaults
        settings.enabled = true
        
        let service = PredictiveAlertService(settings: settings)
        
        // Stable in range
        let readings = makeReadings([100, 100, 100, 100, 100])
        
        let event = await service.processReadings(readings)
        
        #expect(event == nil)
    }
    
    @Test("State transitions")
    func stateTransitions() async {
        var settings = PredictiveAlertSettings.defaults
        settings.enabled = true
        settings.lowThresholdMgDl = 70
        
        let service = PredictiveAlertService(settings: settings)
        
        // Start in range
        let inRange = makeReadings([100, 100, 100, 100, 100])
        _ = await service.processReadings(inRange)
        
        var state = await service.currentState
        #expect(state == .inRange)
        
        // Transition to low
        let goingLow = makeReadings([90, 85, 80, 75, 70])
        _ = await service.processReadings(goingLow)
        
        state = await service.currentState
        #expect(state == .predictedLow)
    }
    
    // MARK: - Helpers
    
    private func makeReadings(_ values: [Double]) -> [GlucoseReading] {
        let now = Date()
        return values.enumerated().map { index, glucose in
            GlucoseReading(
                glucose: glucose,
                timestamp: now.addingTimeInterval(TimeInterval(index - values.count + 1) * 5 * 60),
                trend: .flat
            )
        }
    }
}

// MARK: - Alert Notification Dispatcher Tests

@Suite("Alert Notification Dispatcher")
struct AlertNotificationDispatcherTests {
    
    @Test("Dispatch predicted low")
    func dispatchPredictedLow() async {
        let dispatcher = AlertNotificationDispatcher()
        
        let event = PredictiveAlertEvent(
            state: .predictedLow,
            currentGlucose: 80,
            predictedGlucose: 60
        )
        
        // Should not throw
        await dispatcher.dispatch(event)
    }
    
    @Test("Dispatch predicted high")
    func dispatchPredictedHigh() async {
        let dispatcher = AlertNotificationDispatcher()
        
        let event = PredictiveAlertEvent(
            state: .predictedHigh,
            currentGlucose: 180,
            predictedGlucose: 260
        )
        
        // Should not throw
        await dispatcher.dispatch(event)
    }
    
    @Test("No dispatch for in range")
    func noDispatchForInRange() async {
        let dispatcher = AlertNotificationDispatcher()
        
        let event = PredictiveAlertEvent(
            state: .inRange,
            currentGlucose: 100,
            predictedGlucose: 110
        )
        
        // Should not dispatch (no-op for in-range)
        await dispatcher.dispatch(event)
    }
}

// MARK: - Predictive Alert Notifier Tests

@Suite("Predictive Alert Notifier")
struct PredictiveAlertNotifierTests {
    
    @Test("Process and notify")
    func processAndNotify() async {
        var settings = PredictiveAlertSettings.defaults
        settings.enabled = true
        settings.lowThresholdMgDl = 70
        
        let alertService = PredictiveAlertService(settings: settings)
        let notifier = PredictiveAlertNotifier(
            alertService: alertService,
            dispatcher: AlertNotificationDispatcher()
        )
        
        // Rapidly falling glucose
        let readings = makeReadings([100, 95, 90, 85, 80])
        
        // Process readings
        await notifier.processAndNotify(readings)
        
        // Verify state changed
        let state = await notifier.currentState()
        #expect(state == .predictedLow)
    }
    
    @Test("Update settings")
    func updateSettings() async {
        let alertService = PredictiveAlertService()
        let notifier = PredictiveAlertNotifier(alertService: alertService)
        
        var newSettings = PredictiveAlertSettings.defaults
        newSettings.enabled = true
        newSettings.highThresholdMgDl = 200
        
        await notifier.updateSettings(newSettings)
        
        // Process readings that would trigger high
        let readings = makeReadings([180, 185, 190, 195, 200])
        await notifier.processAndNotify(readings)
        
        let state = await notifier.currentState()
        #expect(state == .predictedHigh)
    }
    
    @Test("Factory default")
    func factoryDefault() async {
        let notifier = PredictiveAlertNotifierFactory.createDefault()
        
        // Default should be disabled
        let readings = makeReadings([100, 90, 80, 70, 60])
        await notifier.processAndNotify(readings)
        
        // State should still be inRange because alerts are disabled
        let state = await notifier.currentState()
        #expect(state == .inRange)
    }
    
    // MARK: - Helpers
    
    private func makeReadings(_ values: [Double]) -> [GlucoseReading] {
        let now = Date()
        return values.enumerated().map { index, glucose in
            GlucoseReading(
                glucose: glucose,
                timestamp: now.addingTimeInterval(TimeInterval(index - values.count + 1) * 5 * 60),
                trend: .flat
            )
        }
    }
}
