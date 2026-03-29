// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ClinicOnboardingViews.swift
// T1PalCore
//
// SwiftUI views for clinic/enterprise onboarding flow.
// Trace: ID-ENT-002, PRD-003, REQ-ID-003

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Main Clinic Onboarding View

@available(iOS 17.0, macOS 14.0, *)
public struct ClinicOnboardingView: View {
    @Bindable var manager: ClinicOnboardingManager
    let onComplete: (ClinicUserProfile?) -> Void
    let onCancel: () -> Void
    
    public init(
        manager: ClinicOnboardingManager,
        onComplete: @escaping (ClinicUserProfile?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.manager = manager
        self.onComplete = onComplete
        self.onCancel = onCancel
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                ClinicOnboardingProgress(currentStep: manager.currentStep)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                Divider()
                    .padding(.top, 8)
                
                // Content
                ScrollView {
                    stepContent
                        .padding()
                }
                
                // Error banner
                if let error = manager.state.error {
                    ClinicErrorBanner(error: error) {
                        manager.state.error = nil
                    }
                }
                
                Divider()
                
                // Navigation
                ClinicOnboardingNavigation(
                    currentStep: manager.currentStep,
                    canProceed: manager.canProceed,
                    onBack: { manager.previousStep() },
                    onNext: { manager.nextStep() },
                    onComplete: { onComplete(manager.state.userProfile) }
                )
                .padding()
            }
            .navigationTitle("Clinic Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch manager.currentStep {
        case .welcome:
            ClinicWelcomeStep()
        case .scanQRCode:
            ClinicScanQRStep(manager: manager)
        case .selectProvider:
            ClinicSelectProviderStep(manager: manager)
        case .authenticate:
            ClinicAuthenticateStep(manager: manager)
        case .reviewProfile:
            ClinicReviewProfileStep(manager: manager)
        case .discoverInstances:
            ClinicDiscoverInstancesStep(manager: manager)
        case .selectInstance:
            ClinicSelectInstanceStep(manager: manager)
        case .syncSettings:
            ClinicSyncSettingsStep(manager: manager)
        case .complete:
            ClinicCompleteStep(profile: manager.state.userProfile)
        }
    }
}

// MARK: - Progress Indicator

@available(iOS 15.0, macOS 12.0, *)
struct ClinicOnboardingProgress: View {
    let currentStep: ClinicOnboardingStepType
    
    private var stepIndex: Int {
        ClinicOnboardingStepType.allCases.firstIndex(of: currentStep) ?? 0
    }
    
    private var progress: Double {
        Double(stepIndex) / Double(ClinicOnboardingStepType.allCases.count - 1)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            
            Text("Step \(stepIndex + 1) of \(ClinicOnboardingStepType.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Welcome Step

@available(iOS 15.0, macOS 12.0, *)
struct ClinicWelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Connect to Your Clinic")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Sign in with your healthcare organization to sync your therapy settings and connect with your care team.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "qrcode", text: "Scan your clinic's QR code")
                FeatureRow(icon: "lock.shield", text: "Sign in securely with your organization")
                FeatureRow(icon: "arrow.triangle.2.circlepath", text: "Sync your therapy settings")
                FeatureRow(icon: "person.2", text: "Connect with your care team")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .padding(.vertical)
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30)
            
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Scan QR Step

@available(iOS 17.0, macOS 14.0, *)
struct ClinicScanQRStep: View {
    @Bindable var manager: ClinicOnboardingManager
    @State private var showingManualEntry = false
    @State private var manualJSON = ""
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Scan Clinic QR Code")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Ask your clinic for a QR code to quickly connect your account.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // QR Scanner placeholder (actual scanner would use AVFoundation)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(height: 200)
                
                VStack(spacing: 8) {
                    Image(systemName: "camera")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Camera preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Button("Enter Code Manually") {
                showingManualEntry = true
            }
            .font(.subheadline)
            
            Button("I don't have a QR code") {
                manager.currentStep = .selectProvider
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualCodeEntrySheet(
                json: $manualJSON,
                onSubmit: {
                    Task {
                        try? await manager.processQRCode(manualJSON)
                    }
                    showingManualEntry = false
                }
            )
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct ManualCodeEntrySheet: View {
    @Binding var json: String
    let onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Paste the clinic configuration JSON below:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $json)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Button("Submit") {
                    onSubmit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(json.isEmpty)
            }
            .padding()
            .navigationTitle("Manual Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Select Provider Step

@available(iOS 17.0, macOS 14.0, *)
struct ClinicSelectProviderStep: View {
    @Bindable var manager: ClinicOnboardingManager
    @State private var selectedProvider: KnownOIDCProvider?
    @State private var clientId = ""
    @State private var isLoading = false
    
    private let healthcareProviders = KnownOIDCProvider.providers(for: .healthcare)
    private let enterpriseProviders = KnownOIDCProvider.providers(for: .enterprise)
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Select Your Provider")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose your healthcare organization's identity provider.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Healthcare providers
            if !healthcareProviders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Healthcare")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ForEach(healthcareProviders, id: \.rawValue) { provider in
                        ProviderRow(
                            provider: provider,
                            isSelected: selectedProvider == provider
                        ) {
                            selectedProvider = provider
                        }
                    }
                }
            }
            
            // Enterprise providers
            if !enterpriseProviders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enterprise SSO")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ForEach(enterpriseProviders, id: \.rawValue) { provider in
                        ProviderRow(
                            provider: provider,
                            isSelected: selectedProvider == provider
                        ) {
                            selectedProvider = provider
                        }
                    }
                }
            }
            
            // Client ID input (required for most providers)
            if selectedProvider != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Client ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Enter client ID", text: $clientId)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            }
            
            if let provider = selectedProvider, !clientId.isEmpty {
                Button {
                    Task {
                        isLoading = true
                        try? await manager.selectProvider(provider, clientId: clientId)
                        isLoading = false
                    }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Continue with \(provider.displayName)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct ProviderRow: View {
    let provider: KnownOIDCProvider
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: provider.iconName)
                    .font(.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading) {
                    Text(provider.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let notes = provider.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Authenticate Step

@available(iOS 17.0, macOS 14.0, *)
struct ClinicAuthenticateStep: View {
    @Bindable var manager: ClinicOnboardingManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Sign In")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let config = manager.state.providerConfig {
                Text("Sign in with \(config.displayName) to continue.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                // In a real implementation, this would trigger ASWebAuthenticationSession
                Button {
                    // Simulate authentication for demo purposes
                    manager.completeAuthentication(
                        accessToken: "demo_token",
                        refreshToken: "demo_refresh"
                    )
                    manager.setUserProfile(ClinicUserProfile(
                        subject: "user_123",
                        name: "Demo User",
                        email: "user@clinic.example.com",
                        emailVerified: true,
                        organizationName: config.displayName,
                        role: "patient"
                    ))
                } label: {
                    Label("Sign in with \(config.displayName)", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            if manager.isAuthenticating {
                ProgressView("Authenticating...")
            }
        }
    }
}

// MARK: - Review Profile Step

@available(iOS 17.0, macOS 14.0, *)
struct ClinicReviewProfileStep: View {
    @Bindable var manager: ClinicOnboardingManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("Review Your Profile")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let profile = manager.state.userProfile {
                VStack(alignment: .leading, spacing: 12) {
                    ProfileRow(label: "Name", value: profile.name ?? "—")
                    ProfileRow(label: "Email", value: profile.email ?? "—")
                    ProfileRow(label: "Organization", value: profile.organizationName ?? "—")
                    ProfileRow(label: "Role", value: profile.role ?? "—")
                    
                    if let verified = profile.emailVerified {
                        HStack {
                            Text("Email Verified")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: verified ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(verified ? .green : .red)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            Text("This information was provided by your healthcare organization.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct ProfileRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - Discover Instances Step

@available(iOS 17.0, macOS 14.0, *)
struct ClinicDiscoverInstancesStep: View {
    @Bindable var manager: ClinicOnboardingManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Finding Your Nightscout")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Discovering Nightscout instances linked to your account...")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if manager.state.isDiscoveringInstances {
                ProgressView()
                    .progressViewStyle(.circular)
            } else if manager.state.discoveredInstances.isEmpty {
                VStack(spacing: 16) {
                    Text("No instances found")
                        .foregroundStyle(.secondary)
                    
                    Button("Search Again") {
                        Task {
                            try? await manager.discoverInstances()
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Skip for Now") {
                        manager.skipInstanceSelection()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else {
                // Auto-advances if instances found
                ProgressView("Found \(manager.state.discoveredInstances.count) instance(s)")
            }
        }
        .task {
            try? await manager.discoverInstances()
        }
    }
}

// MARK: - Select Instance Step

@available(iOS 17.0, macOS 14.0, *)
struct ClinicSelectInstanceStep: View {
    @Bindable var manager: ClinicOnboardingManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Select Nightscout Instance")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose which Nightscout site to connect.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(manager.state.discoveredInstances) { instance in
                        NSInstanceRow(
                            instance: instance,
                            isSelected: manager.state.selectedInstance?.id == instance.id,
                            onSelect: {
                                manager.selectInstance(instance)
                            }
                        )
                    }
                }
            }
            
            if manager.state.discoveredInstances.count > 1 {
                Button("Skip for Now") {
                    manager.skipInstanceSelection()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct NSInstanceRow: View {
    let instance: NSInstanceBinding
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(instance.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(instance.url.host ?? instance.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        Text(instance.role.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                        
                        if instance.isPrimary {
                            Text("Primary")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sync Settings Step

@available(iOS 17.0, macOS 14.0, *)
struct ClinicSyncSettingsStep: View {
    @Bindable var manager: ClinicOnboardingManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            
            Text("Sync Settings")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Import your therapy settings from your healthcare provider.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 12) {
                SyncItem(icon: "chart.line.uptrend.xyaxis", text: "Target glucose ranges")
                SyncItem(icon: "syringe", text: "Basal rates")
                SyncItem(icon: "fork.knife", text: "Carb ratios")
                SyncItem(icon: "gauge", text: "Sensitivity factors")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            if manager.isSyncing {
                ProgressView("Syncing settings...")
            } else {
                Button {
                    Task {
                        try? await manager.syncSettings()
                    }
                } label: {
                    Text("Sync Now")
                }
                .buttonStyle(.borderedProminent)
                
                Button("Skip for Now") {
                    manager.skipSettingsSync()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct SyncItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Complete Step

@available(iOS 15.0, macOS 12.0, *)
struct ClinicCompleteStep: View {
    let profile: ClinicUserProfile?
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("All Set!")
                .font(.title)
                .fontWeight(.bold)
            
            if let org = profile?.organizationName {
                Text("You're now connected to \(org).")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                CompletionRow(icon: "checkmark.circle.fill", text: "Account linked", color: .green)
                CompletionRow(icon: "checkmark.circle.fill", text: "Profile synced", color: .green)
                CompletionRow(icon: "checkmark.circle.fill", text: "Ready to use", color: .green)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
struct CompletionRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Error Banner

@available(iOS 15.0, macOS 12.0, *)
struct ClinicErrorBanner: View {
    let error: ClinicOnboardingError
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            
            Text(error.localizedDescription)
                .font(.subheadline)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
    }
}

// MARK: - Navigation Bar

@available(iOS 15.0, macOS 12.0, *)
struct ClinicOnboardingNavigation: View {
    let currentStep: ClinicOnboardingStepType
    let canProceed: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onComplete: () -> Void
    
    var body: some View {
        HStack {
            if currentStep != .welcome {
                Button("Back", action: onBack)
            }
            
            Spacer()
            
            if currentStep == .complete {
                Button("Done", action: onComplete)
                    .buttonStyle(.borderedProminent)
            } else if currentStep != .authenticate && currentStep != .syncSettings {
                Button("Next", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
            }
        }
    }
}

#endif
