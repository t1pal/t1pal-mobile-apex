// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// CalibrationEntryView.swift - Calibration entry for CGM
// Part of CGMKit
// Trace: CGM-UI-004

#if canImport(SwiftUI)
import SwiftUI

/// View for entering blood glucose calibration values
@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
public struct CalibrationEntryView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var glucoseValue: String = ""
    @State private var glucoseUnit: GlucoseUnit = .mgdL
    @State private var calibrationTime: Date = Date()
    @State private var isSubmitting: Bool = false
    @State private var showConfirmation: Bool = false
    @State private var errorMessage: String?
    
    public let onSubmit: ((Double, GlucoseUnit, Date) -> Void)?
    
    public init(onSubmit: ((Double, GlucoseUnit, Date) -> Void)? = nil) {
        self.onSubmit = onSubmit
    }
    
    public var body: some View {
        NavigationView {
            Form {
                Section {
                    glucoseInputSection
                } header: {
                    Text("Blood Glucose Reading")
                } footer: {
                    Text("Enter the blood glucose value from your fingerstick meter.")
                }
                
                Section("Calibration Time") {
                    DatePicker(
                        "Time",
                        selection: $calibrationTime,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                
                Section {
                    calibrationTipsSection
                } header: {
                    Text("Calibration Tips")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Enter Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        submitCalibration()
                    }
                    .disabled(!isValidInput || isSubmitting)
                }
            }
            .alert("Calibration Submitted", isPresented: $showConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your calibration value has been recorded.")
            }
        }
    }
    
    // MARK: - Glucose Input
    
    private var glucoseInputSection: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("Value", text: $glucoseValue)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 80)
                
                Picker("Unit", selection: $glucoseUnit) {
                    Text("mg/dL").tag(GlucoseUnit.mgdL)
                    Text("mmol/L").tag(GlucoseUnit.mmolL)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            
            // Visual feedback for glucose range
            if let value = parsedGlucoseValue {
                glucoseRangeIndicator(value: value)
            }
        }
    }
    
    private func glucoseRangeIndicator(value: Double) -> some View {
        let mgdLValue = glucoseUnit == .mgdL ? value : value * 18.0
        
        let (color, label) = glucoseRangeInfo(mgdL: mgdLValue)
        
        return HStack {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.0f mg/dL", mgdLValue))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
    
    private func glucoseRangeInfo(mgdL: Double) -> (Color, String) {
        switch mgdL {
        case ..<54:
            return (.red, "Very Low - Treat immediately")
        case 54..<70:
            return (.orange, "Low")
        case 70..<180:
            return (.green, "In Range")
        case 180..<250:
            return (.yellow, "High")
        default:
            return (.red, "Very High")
        }
    }
    
    // MARK: - Calibration Tips
    
    private var calibrationTipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            tipRow(
                icon: "hand.raised",
                text: "Wash and dry hands before testing"
            )
            tipRow(
                icon: "clock",
                text: "Calibrate when glucose is stable (no arrows)"
            )
            tipRow(
                icon: "arrow.up.arrow.down",
                text: "Avoid calibrating during rapid changes"
            )
            tipRow(
                icon: "drop.fill",
                text: "Use fresh blood sample"
            )
        }
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Validation
    
    private var parsedGlucoseValue: Double? {
        Double(glucoseValue)
    }
    
    private var isValidInput: Bool {
        guard let value = parsedGlucoseValue else { return false }
        
        // Valid ranges
        if glucoseUnit == .mgdL {
            return value >= 20 && value <= 600
        } else {
            return value >= 1.1 && value <= 33.3
        }
    }
    
    // MARK: - Submit
    
    private func submitCalibration() {
        guard let value = parsedGlucoseValue else {
            errorMessage = "Please enter a valid glucose value"
            return
        }
        
        isSubmitting = true
        
        // Simulate async submission
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSubmitting = false
            onSubmit?(value, glucoseUnit, calibrationTime)
            showConfirmation = true
        }
    }
}

// MARK: - Glucose Unit

public enum GlucoseUnit: String, CaseIterable, Sendable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"
    
    public var conversionFactor: Double {
        switch self {
        case .mgdL: return 1.0
        case .mmolL: return 18.0
        }
    }
}

// MARK: - Preview

@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
struct CalibrationEntryView_Previews: PreviewProvider {
    static var previews: some View {
        CalibrationEntryView { value, unit, time in
            print("Calibration: \(value) \(unit.rawValue) at \(time)")
        }
    }
}

#endif
