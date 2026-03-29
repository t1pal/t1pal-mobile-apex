#if canImport(SwiftUI)
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutQRScannerView.swift
// T1Pal Mobile
//
// SwiftUI view for Nightscout QR code scanning
// Requirements: NS-QR-003
//
// NOTE: Actual camera capture requires AVFoundation (iOS only).
// This view provides the UI wrapper and result handling.
// Wire to CodeScannerView or similar on iOS.

import SwiftUI

/// SwiftUI view for scanning Nightscout QR codes
///
/// This view handles the UI and result processing for Nightscout QR scanning.
/// On iOS, wire the `onScanCode` callback to your camera scanner.
///
/// Usage:
/// ```swift
/// NightscoutQRScannerView { config in
///     nightscoutClient.configure(config)
///     dismiss()
/// }
/// ```
public struct NightscoutQRScannerView: View {
    @StateObject private var handler = NightscoutQRHandler()
    @Environment(\.dismiss) private var dismiss
    
    /// Callback when configuration is successfully extracted
    private let onConfigured: (NightscoutConfig) -> Void
    
    /// Optional custom scanner view (for iOS camera integration)
    private let customScanner: AnyView?
    
    /// For demo/testing: manual text entry
    @State private var manualEntry: String = ""
    @State private var showManualEntry: Bool = false
    
    public init(
        onConfigured: @escaping (NightscoutConfig) -> Void
    ) {
        self.onConfigured = onConfigured
        self.customScanner = nil
    }
    
    /// Initialize with a custom scanner view
    ///
    /// Use this to integrate with iOS camera scanning:
    /// ```swift
    /// NightscoutQRScannerView(
    ///     scanner: AnyView(CodeScannerView(codeTypes: [.qr]) { result in
    ///         handler.handleScan(result: result.string)
    ///     }),
    ///     onConfigured: { config in ... }
    /// )
    /// ```
    public init<Scanner: View>(
        scanner: Scanner,
        onConfigured: @escaping (NightscoutConfig) -> Void
    ) {
        self.customScanner = AnyView(scanner)
        self.onConfigured = onConfigured
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Scanner area
                if let scanner = customScanner {
                    scanner
                        .frame(maxWidth: .infinity)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Placeholder for non-camera platforms
                    scannerPlaceholder
                }
                
                // Status display
                statusView
                
                // Manual entry option
                if showManualEntry {
                    manualEntryView
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Scan Nightscout QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(showManualEntry ? "Scan" : "Manual") {
                        showManualEntry.toggle()
                    }
                }
            }
            .onChange(of: handler.state) { _, newState in
                if case .success = newState {
                    // Config was extracted, callback already fired by handler
                }
            }
            .onAppear {
                handler.onCredentialsExtracted = { config in
                    onConfigured(config)
                }
            }
        }
    }
    
    @ViewBuilder
    private var scannerPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("Camera Scanner")
                .font(.headline)
            
            Text("Use Manual entry below, or integrate with CodeScannerView on iOS")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch handler.state {
        case .idle:
            Label("Point camera at Nightscout QR code", systemImage: "viewfinder")
                .foregroundStyle(.secondary)
            
        case .processing:
            HStack {
                ProgressView()
                Text("Processing...")
            }
            
        case .validating:
            HStack {
                ProgressView()
                Text("Validating connection...")
            }
            
        case .success(let url, let hasSecret, let validated):
            VStack(spacing: 8) {
                Label("Success!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                
                Text(url.host ?? url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                if hasSecret {
                    Label("API secret found", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
                if validated {
                    Label("Connection verified", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
        case .error(let error):
            VStack(spacing: 8) {
                Label("Error", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Try Again") {
                    handler.reset()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    @ViewBuilder
    private var manualEntryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paste QR code content:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            TextEditor(text: $manualEntry)
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
            
            Button("Process") {
                handler.handleScan(result: manualEntry)
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualEntry.isEmpty)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NightscoutQRScannerView_Previews: PreviewProvider {
    static var previews: some View {
        NightscoutQRScannerView { config in
            print("Configured: \(config.url)")
        }
    }
}
#endif

#endif // canImport(SwiftUI)
