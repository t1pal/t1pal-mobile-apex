// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// CGMAlertsConfigurationView.swift - CGM alerts configuration
// Part of CGMKit
// Trace: CGM-UI-005

#if canImport(SwiftUI)
import SwiftUI

/// Configuration for CGM glucose alerts
public struct CGMAlertConfiguration: Codable, Sendable, Equatable {
    public var lowThreshold: Double          // mg/dL
    public var urgentLowThreshold: Double    // mg/dL
    public var highThreshold: Double         // mg/dL
    public var urgentHighThreshold: Double   // mg/dL
    
    public var lowAlertEnabled: Bool
    public var urgentLowAlertEnabled: Bool
    public var highAlertEnabled: Bool
    public var urgentHighAlertEnabled: Bool
    
    public var repeatInterval: TimeInterval  // seconds
    public var snoozeDuration: TimeInterval  // seconds
    
    public var soundEnabled: Bool
    public var vibrationEnabled: Bool
    
    public init(
        lowThreshold: Double = 70,
        urgentLowThreshold: Double = 55,
        highThreshold: Double = 180,
        urgentHighThreshold: Double = 250,
        lowAlertEnabled: Bool = true,
        urgentLowAlertEnabled: Bool = true,
        highAlertEnabled: Bool = true,
        urgentHighAlertEnabled: Bool = true,
        repeatInterval: TimeInterval = 300,
        snoozeDuration: TimeInterval = 1800,
        soundEnabled: Bool = true,
        vibrationEnabled: Bool = true
    ) {
        self.lowThreshold = lowThreshold
        self.urgentLowThreshold = urgentLowThreshold
        self.highThreshold = highThreshold
        self.urgentHighThreshold = urgentHighThreshold
        self.lowAlertEnabled = lowAlertEnabled
        self.urgentLowAlertEnabled = urgentLowAlertEnabled
        self.highAlertEnabled = highAlertEnabled
        self.urgentHighAlertEnabled = urgentHighAlertEnabled
        self.repeatInterval = repeatInterval
        self.snoozeDuration = snoozeDuration
        self.soundEnabled = soundEnabled
        self.vibrationEnabled = vibrationEnabled
    }
    
    public static let `default` = CGMAlertConfiguration()
}

/// View for configuring CGM alerts
@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
public struct CGMAlertsConfigurationView: View {
    @Binding public var configuration: CGMAlertConfiguration
    @State private var showingResetConfirmation = false
    
    public init(configuration: Binding<CGMAlertConfiguration>) {
        self._configuration = configuration
    }
    
    public var body: some View {
        Form {
            // Low Alerts
            Section {
                alertThresholdRow(
                    title: "Low Alert",
                    threshold: $configuration.lowThreshold,
                    enabled: $configuration.lowAlertEnabled,
                    color: .orange,
                    range: 60...100
                )
                
                alertThresholdRow(
                    title: "Urgent Low Alert",
                    threshold: $configuration.urgentLowThreshold,
                    enabled: $configuration.urgentLowAlertEnabled,
                    color: .red,
                    range: 40...70
                )
            } header: {
                Text("Low Glucose Alerts")
            } footer: {
                Text("Urgent low alerts cannot be silenced and will repeat until acknowledged.")
            }
            
            // High Alerts
            Section {
                alertThresholdRow(
                    title: "High Alert",
                    threshold: $configuration.highThreshold,
                    enabled: $configuration.highAlertEnabled,
                    color: .yellow,
                    range: 140...250
                )
                
                alertThresholdRow(
                    title: "Urgent High Alert",
                    threshold: $configuration.urgentHighThreshold,
                    enabled: $configuration.urgentHighAlertEnabled,
                    color: .red,
                    range: 200...400
                )
            } header: {
                Text("High Glucose Alerts")
            }
            
            // Alert Behavior
            Section("Alert Behavior") {
                repeatIntervalPicker
                snoozeDurationPicker
            }
            
            // Sound & Vibration
            Section("Notification Style") {
                Toggle("Sound", isOn: $configuration.soundEnabled)
                Toggle("Vibration", isOn: $configuration.vibrationEnabled)
            }
            
            // Visual Preview
            Section("Threshold Preview") {
                thresholdPreview
            }
            
            // Reset
            Section {
                Button("Reset to Defaults", role: .destructive) {
                    showingResetConfirmation = true
                }
            }
        }
        .navigationTitle("CGM Alerts")
        .alert("Reset Alerts?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                configuration = .default
            }
        } message: {
            Text("This will reset all alert settings to their default values.")
        }
    }
    
    // MARK: - Alert Threshold Row
    
    private func alertThresholdRow(
        title: String,
        threshold: Binding<Double>,
        enabled: Binding<Bool>,
        color: Color,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                Text(title)
                Spacer()
                Toggle("", isOn: enabled)
                    .labelsHidden()
            }
            
            if enabled.wrappedValue {
                HStack {
                    Slider(value: threshold, in: range, step: 5)
                    Text("\(Int(threshold.wrappedValue)) mg/dL")
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Repeat Interval
    
    private var repeatIntervalPicker: some View {
        Picker("Repeat Interval", selection: $configuration.repeatInterval) {
            Text("Never").tag(TimeInterval(0))
            Text("5 minutes").tag(TimeInterval(300))
            Text("10 minutes").tag(TimeInterval(600))
            Text("15 minutes").tag(TimeInterval(900))
            Text("30 minutes").tag(TimeInterval(1800))
        }
    }
    
    // MARK: - Snooze Duration
    
    private var snoozeDurationPicker: some View {
        Picker("Snooze Duration", selection: $configuration.snoozeDuration) {
            Text("15 minutes").tag(TimeInterval(900))
            Text("30 minutes").tag(TimeInterval(1800))
            Text("1 hour").tag(TimeInterval(3600))
            Text("2 hours").tag(TimeInterval(7200))
        }
    }
    
    // MARK: - Threshold Preview
    
    private var thresholdPreview: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background gradient
                LinearGradient(
                    colors: [.red, .orange, .green, .yellow, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 20)
                .cornerRadius(10)
                
                // Threshold markers
                thresholdMarker(
                    value: configuration.urgentLowThreshold,
                    label: "UL",
                    width: geometry.size.width
                )
                thresholdMarker(
                    value: configuration.lowThreshold,
                    label: "L",
                    width: geometry.size.width
                )
                thresholdMarker(
                    value: configuration.highThreshold,
                    label: "H",
                    width: geometry.size.width
                )
                thresholdMarker(
                    value: configuration.urgentHighThreshold,
                    label: "UH",
                    width: geometry.size.width
                )
            }
        }
        .frame(height: 40)
        .padding(.vertical, 8)
    }
    
    private func thresholdMarker(value: Double, label: String, width: CGFloat) -> some View {
        let position = (value - 40) / (400 - 40) * width
        
        return VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            Rectangle()
                .fill(.white)
                .frame(width: 2, height: 20)
        }
        .offset(x: position - 5)
    }
}

// MARK: - Preview

@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
struct CGMAlertsConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CGMAlertsConfigurationView(
                configuration: .constant(.default)
            )
        }
    }
}

#endif
