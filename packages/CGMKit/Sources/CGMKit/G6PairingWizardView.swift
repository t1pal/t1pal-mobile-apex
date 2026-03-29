// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// G6PairingWizardView.swift - Dexcom G6 pairing wizard
// Part of CGMKit
// Trace: CGM-UI-003, G6-WIRE-003

#if canImport(SwiftUI)
import SwiftUI

/// Callback when pairing completes successfully
public typealias G6PairingCompletion = (String) -> Void

/// Wizard for pairing a Dexcom G6 transmitter
/// 
/// Can operate in two modes:
/// - Demo mode (default): Simulates scanning/pairing for UI testing
/// - Live mode: Uses actual BLE via DexcomG6Manager bridge
@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
public struct G6PairingWizardView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStep: PairingStep = .intro
    @State private var transmitterID: String = ""
    @State private var sensorCode: String = ""
    @State private var isScanning: Bool = false
    @State private var scanError: String?
    @State private var foundDevice: Bool = false
    @State private var isPairing: Bool = false
    @State private var pairingComplete: Bool = false
    
    /// Whether to use live BLE (requires bridge to be set)
    private let isLiveMode: Bool
    
    /// Bridge for live mode operations
    private let bridge: G6PairingBridge?
    
    /// Completion callback with transmitter ID
    private let onComplete: G6PairingCompletion?
    
    /// Initialize in demo mode
    public init(onComplete: G6PairingCompletion? = nil) {
        self.isLiveMode = false
        self.bridge = nil
        self.onComplete = onComplete
    }
    
    /// Initialize in live mode with bridge
    public init(bridge: G6PairingBridge, onComplete: G6PairingCompletion? = nil) {
        self.isLiveMode = true
        self.bridge = bridge
        self.onComplete = onComplete
    }
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress indicator
                progressBar
                    .padding(.horizontal)
                    .padding(.top)
                
                // Content
                ScrollView {
                    stepContent
                        .padding()
                }
                
                Spacer()
                
                // Navigation buttons
                navigationButtons
                    .padding()
            }
            .navigationTitle("Pair Dexcom G6")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(PairingStep.allCases, id: \.self) { step in
                Rectangle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)
            }
        }
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .intro:
            introContent
        case .transmitterID:
            transmitterIDContent
        case .sensorCode:
            sensorCodeContent
        case .scanning:
            scanningContent
        case .pairing:
            pairingContent
        case .complete:
            completeContent
        }
    }
    
    private var introContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            
            Text("Pair Your Dexcom G6")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("This wizard will help you connect your Dexcom G6 transmitter to T1Pal.")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                requirementRow(icon: "checkmark.circle", text: "G6 transmitter attached to sensor")
                requirementRow(icon: "iphone.radiowaves.left.and.right", text: "Bluetooth enabled")
                requirementRow(icon: "number", text: "Transmitter ID (on transmitter box)")
                requirementRow(icon: "barcode", text: "Sensor code (optional)")
            }
            .padding(.vertical)
            
            Text("Note: You cannot use the Dexcom app simultaneously. Please stop sharing from the Dexcom app before continuing.")
                .font(.caption)
                .foregroundColor(.orange)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private func requirementRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
    
    private var transmitterIDContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter Transmitter ID")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Find the 6-character transmitter ID on the back of your transmitter or on the transmitter box.")
                .foregroundColor(.secondary)
            
            // Transmitter ID image placeholder
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 120)
                .overlay {
                    VStack {
                        Image(systemName: "sensor.tag.radiowaves.forward.fill")
                            .font(.largeTitle)
                        Text("Example: 8G1234")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            
            TextField("Transmitter ID", text: $transmitterID)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: transmitterID) { newValue in
                    // Limit to 6 characters, uppercase
                    transmitterID = String(newValue.uppercased().prefix(6))
                }
            
            if !isTransmitterIDValid && !transmitterID.isEmpty {
                Text("Transmitter ID must be 6 alphanumeric characters")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private var sensorCodeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter Sensor Code (Optional)")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("The 4-digit sensor code is printed on the sensor applicator. It enables factory calibration.")
                .foregroundColor(.secondary)
            
            TextField("Sensor Code", text: $sensorCode)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospaced())
                .keyboardType(.numberPad)
                .onChange(of: sensorCode) { newValue in
                    sensorCode = String(newValue.filter { $0.isNumber }.prefix(4))
                }
            
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text("If you skip this, you may need to calibrate with a fingerstick.")
                    .font(.caption)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            Button("Skip - I'll calibrate manually") {
                sensorCode = ""
                currentStep = .scanning
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
    
    private var scanningContent: some View {
        VStack(spacing: 24) {
            if isScanning {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                
                Text("Scanning for G6 Transmitter...")
                    .font(.headline)
                
                Text("Make sure your transmitter is within range and attached to the sensor.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Looking for: \(transmitterID)")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            } else if let error = scanError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                
                Text("Scan Failed")
                    .font(.headline)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Try Again") {
                    startScanning()
                }
                .buttonStyle(.borderedProminent)
            } else if foundDevice {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.green)
                
                Text("Transmitter Found!")
                    .font(.headline)
                
                Text("Ready to pair with \(transmitterID)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear {
            if !foundDevice {
                startScanning()
            }
        }
    }
    
    private var pairingContent: some View {
        VStack(spacing: 24) {
            if isPairing {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                
                Text("Pairing with Transmitter...")
                    .font(.headline)
                
                Text("This may take up to 30 seconds. Keep your phone near the transmitter.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onAppear {
            startPairing()
        }
    }
    
    private var completeContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Pairing Complete!")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Your Dexcom G6 is now connected to T1Pal.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                detailRow(label: "Transmitter", value: transmitterID)
                if !sensorCode.isEmpty {
                    detailRow(label: "Sensor Code", value: sensorCode)
                }
                detailRow(label: "Status", value: "Connected")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            Text("Glucose readings will appear on your dashboard within 5 minutes.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep != .intro && currentStep != .complete {
                Button("Back") {
                    goBack()
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            if currentStep == .complete {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            } else if canProceed {
                Button(nextButtonTitle) {
                    goNext()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var nextButtonTitle: String {
        switch currentStep {
        case .intro: return "Get Started"
        case .transmitterID: return "Next"
        case .sensorCode: return sensorCode.isEmpty ? "Skip" : "Next"
        case .scanning: return "Pair"
        case .pairing: return ""
        case .complete: return "Done"
        }
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .intro: return true
        case .transmitterID: return isTransmitterIDValid
        case .sensorCode: return true
        case .scanning: return foundDevice
        case .pairing: return false
        case .complete: return true
        }
    }
    
    private var isTransmitterIDValid: Bool {
        transmitterID.count == 6 && transmitterID.allSatisfy { $0.isLetter || $0.isNumber }
    }
    
    // MARK: - Navigation
    
    private func goNext() {
        withAnimation {
            switch currentStep {
            case .intro:
                currentStep = .transmitterID
            case .transmitterID:
                currentStep = .sensorCode
            case .sensorCode:
                currentStep = .scanning
            case .scanning:
                currentStep = .pairing
            case .pairing:
                currentStep = .complete
            case .complete:
                dismiss()
            }
        }
    }
    
    private func goBack() {
        withAnimation {
            switch currentStep {
            case .transmitterID:
                currentStep = .intro
            case .sensorCode:
                currentStep = .transmitterID
            case .scanning:
                currentStep = .sensorCode
                foundDevice = false
                scanError = nil
            case .pairing:
                currentStep = .scanning
            default:
                break
            }
        }
    }
    
    // MARK: - Scanning & Pairing
    
    private func startScanning() {
        isScanning = true
        scanError = nil
        foundDevice = false
        
        if isLiveMode, let bridge = bridge {
            // Live mode: use real BLE via bridge
            Task { @MainActor in
                do {
                    try await bridge.configureAndScan(transmitterId: transmitterID)
                    // Monitor bridge state for device found
                    startMonitoringBridge()
                } catch {
                    isScanning = false
                    scanError = error.localizedDescription
                }
            }
        } else {
            // Demo mode: Simulate scanning
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                isScanning = false
                foundDevice = true
            }
        }
    }
    
    private func startMonitoringBridge() {
        guard let bridge = bridge else { return }
        
        // Poll bridge state until connected or error
        Task { @MainActor in
            while isScanning {
                try? await Task.sleep(for: .milliseconds(300))
                
                if bridge.isConnected {
                    isScanning = false
                    foundDevice = true
                    break
                }
                
                if let error = bridge.errorMessage {
                    isScanning = false
                    scanError = error
                    break
                }
                
                // Timeout after 30 seconds
                // (handled by bridge's internal timeout)
            }
        }
    }
    
    private func startPairing() {
        isPairing = true
        
        if isLiveMode, let bridge = bridge {
            // Live mode: connection already established during scan
            // Just verify we're connected and complete
            Task { @MainActor in
                // Give a moment for any final handshake
                try? await Task.sleep(for: .milliseconds(500))
                
                if bridge.isConnected {
                    isPairing = false
                    pairingComplete = true
                    currentStep = .complete
                    onComplete?(transmitterID)
                } else if let error = bridge.errorMessage {
                    isPairing = false
                    scanError = error
                    currentStep = .scanning
                } else {
                    // Still connecting, wait a bit more
                    try? await Task.sleep(for: .seconds(2))
                    isPairing = false
                    if bridge.isConnected {
                        pairingComplete = true
                        currentStep = .complete
                        onComplete?(transmitterID)
                    } else {
                        scanError = "Connection timed out"
                        currentStep = .scanning
                    }
                }
            }
        } else {
            // Demo mode: Simulate pairing
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                isPairing = false
                pairingComplete = true
                currentStep = .complete
                onComplete?(transmitterID)
            }
        }
    }
}

// MARK: - G6 Pairing Bridge Protocol

/// Protocol for bridging G6 pairing wizard to real BLE manager
@MainActor
public protocol G6PairingBridge: AnyObject {
    /// Whether currently connected to transmitter
    var isConnected: Bool { get }
    
    /// Last error message, if any
    var errorMessage: String? { get }
    
    /// Configure manager with transmitter ID and start scanning
    func configureAndScan(transmitterId: String) async throws
    
    /// Stop scanning/disconnect
    func disconnect()
}

// MARK: - Pairing Step

enum PairingStep: Int, CaseIterable {
    case intro = 0
    case transmitterID = 1
    case sensorCode = 2
    case scanning = 3
    case pairing = 4
    case complete = 5
}

// MARK: - Preview

@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
struct G6PairingWizardView_Previews: PreviewProvider {
    static var previews: some View {
        G6PairingWizardView()
    }
}

#endif
