// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlertNotificationDispatcher.swift
// T1Pal Mobile
//
// Wires PredictiveAlertService to NotificationService
// Trace: GLUCOS-INT-002, ADR-010

import Foundation
import T1PalCore

// MARK: - Predictive Notification Types

/// Extended notification types for predictive alerts
public enum PredictiveNotificationType: String, Sendable {
    case predictedLow = "glucose.predictedLow"
    case predictedHigh = "glucose.predictedHigh"
    
    /// Map to GlucoseNotificationType for notification dispatch
    public var glucoseNotificationType: GlucoseNotificationType {
        switch self {
        case .predictedLow: return .falling  // Use falling as proxy for predicted low
        case .predictedHigh: return .rising  // Use rising as proxy for predicted high
        }
    }
    
    /// Interruption level
    public var interruptionLevel: NotificationInterruptionLevel {
        switch self {
        case .predictedLow: return .timeSensitive
        case .predictedHigh: return .active
        }
    }
}

// MARK: - Protocol

/// Protocol for dispatching predictive alerts to notifications
public protocol AlertNotificationDispatcherProtocol: Sendable {
    /// Dispatch a predictive alert event to the notification system
    func dispatch(_ event: PredictiveAlertEvent) async
    
    /// Check if notifications are authorized
    func isAuthorized() async -> Bool
}

// MARK: - Implementation

/// Dispatcher that bridges PredictiveAlertService to NotificationService
public actor AlertNotificationDispatcher: AlertNotificationDispatcherProtocol {
    
    // MARK: - Dependencies
    
    private let notificationService: NotificationService
    
    // MARK: - Configuration
    
    /// Whether to use critical alerts for predicted lows
    public var useCriticalForPredictedLow: Bool = false
    
    // MARK: - Init
    
    public init(notificationService: NotificationService = .shared) {
        self.notificationService = notificationService
    }
    
    // MARK: - Public
    
    public func dispatch(_ event: PredictiveAlertEvent) async {
        // Don't dispatch for in-range state
        guard event.state != .inRange else { return }
        
        let content = createNotificationContent(from: event)
        await notificationService.scheduleNotification(content)
    }
    
    public func isAuthorized() async -> Bool {
        let status = await notificationService.checkAuthorization()
        return status == .authorized || status == .provisional
    }
    
    // MARK: - Private
    
    private func createNotificationContent(from event: PredictiveAlertEvent) -> GlucoseNotificationContent {
        let type: GlucoseNotificationType
        let title: String
        let body: String
        
        switch event.state {
        case .predictedLow:
            type = .falling
            title = "📉 Predicted Low"
            body = String(format: "Current: %.0f → Predicted: %.0f mg/dL in 15 min",
                         event.currentGlucose, event.predictedGlucose)
            
        case .predictedHigh:
            type = .rising
            title = "📈 Predicted High"
            body = String(format: "Current: %.0f → Predicted: %.0f mg/dL in 15 min",
                         event.currentGlucose, event.predictedGlucose)
            
        case .inRange:
            // Should not reach here due to guard above
            type = .connected
            title = "Glucose In Range"
            body = "Predicted to stay in range"
        }
        
        return GlucoseNotificationContent(
            type: type,
            title: title,
            body: body,
            glucoseValue: event.currentGlucose,
            trend: event.state == .predictedLow ? "falling" : "rising",
            timestamp: event.timestamp,
            userInfo: [
                "predicted": String(format: "%.0f", event.predictedGlucose),
                "alertType": "predictive"
            ]
        )
    }
}

// MARK: - Integration Helper

/// Extension to connect PredictiveAlertService with notification dispatch
public actor PredictiveAlertNotifier {
    
    private let alertService: PredictiveAlertService
    private let dispatcher: AlertNotificationDispatcher
    
    public init(
        alertService: PredictiveAlertService,
        dispatcher: AlertNotificationDispatcher = AlertNotificationDispatcher()
    ) {
        self.alertService = alertService
        self.dispatcher = dispatcher
    }
    
    /// Process readings and dispatch any resulting alerts
    public func processAndNotify(_ readings: [GlucoseReading]) async {
        if let event = await alertService.processReadings(readings) {
            await dispatcher.dispatch(event)
        }
    }
    
    /// Get current alert state
    public func currentState() async -> PredictiveAlertState {
        await alertService.currentState
    }
    
    /// Update alert settings
    public func updateSettings(_ settings: PredictiveAlertSettings) async {
        await alertService.updateSettings(settings)
    }
}

// MARK: - Factory

/// Factory for creating configured predictive alert notifiers
public enum PredictiveAlertNotifierFactory {
    
    /// Create a default predictive alert notifier
    public static func createDefault() -> PredictiveAlertNotifier {
        var settings = PredictiveAlertSettings.defaults
        settings.enabled = false  // Disabled by default, user must enable
        
        let alertService = PredictiveAlertService(settings: settings)
        let dispatcher = AlertNotificationDispatcher()
        
        return PredictiveAlertNotifier(
            alertService: alertService,
            dispatcher: dispatcher
        )
    }
    
    /// Create a predictive alert notifier with custom settings
    public static func create(with settings: PredictiveAlertSettings) -> PredictiveAlertNotifier {
        let alertService = PredictiveAlertService(settings: settings)
        let dispatcher = AlertNotificationDispatcher()
        
        return PredictiveAlertNotifier(
            alertService: alertService,
            dispatcher: dispatcher
        )
    }
}
