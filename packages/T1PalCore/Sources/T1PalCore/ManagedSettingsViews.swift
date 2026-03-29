// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// ManagedSettingsViews.swift
// T1PalCore
//
// SwiftUI views for displaying and interacting with provider-managed settings.
// Shows read-only indicators for locked fields and provider attribution.
// Trace: ID-ENT-003, PRD-003

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Managed Settings Badge

/// Badge showing that a setting is managed by a provider
public struct ManagedSettingsBadge: View {
    public let providerName: String
    
    public init(providerName: String) {
        self.providerName = providerName
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "building.2.fill")
                .font(.caption2)
            Text("Managed by \(providerName)")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

// MARK: - Policy Indicator

/// Visual indicator for a setting's policy
public struct SettingsPolicyIndicator: View {
    public let policy: SettingsPolicy
    public let showLabel: Bool
    
    public init(policy: SettingsPolicy, showLabel: Bool = false) {
        self.policy = policy
        self.showLabel = showLabel
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: policy.iconName)
                .font(.caption)
            
            if showLabel {
                Text(policyLabel)
                    .font(.caption)
            }
        }
        .foregroundStyle(policyColor)
    }
    
    private var policyLabel: String {
        switch policy {
        case .locked: return "Locked"
        case .suggested: return "Suggested"
        case .default: return "Custom"
        }
    }
    
    private var policyColor: Color {
        switch policy {
        case .locked: return .orange
        case .suggested: return .blue
        case .default: return .secondary
        }
    }
}

// MARK: - Managed Setting Row

/// A settings row that shows managed/locked state
public struct ManagedSettingRow<Content: View>: View {
    public let title: String
    public let policy: SettingsPolicy
    public let reason: String?
    public let content: () -> Content
    
    @State private var showingInfo = false
    
    public init(
        title: String,
        policy: SettingsPolicy,
        reason: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.policy = policy
        self.reason = reason
        self.content = content
    }
    
    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                    
                    if policy != .default {
                        SettingsPolicyIndicator(policy: policy)
                    }
                }
                
                if let reason = reason, policy == .locked {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            content()
                .disabled(policy == .locked)
                .opacity(policy == .locked ? 0.6 : 1.0)
            
            if policy == .locked {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Setting Locked", isPresented: $showingInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(policy.description + (reason.map { ": \($0)" } ?? ""))
        }
    }
}

// MARK: - Managed Settings Summary

/// Summary view showing all managed settings
public struct ManagedSettingsSummary: View {
    public let payload: ManagedSettingsPayload
    
    public init(payload: ManagedSettingsPayload) {
        self.payload = payload
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "building.2.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading) {
                    Text("Managed by \(payload.providerName)")
                        .font(.headline)
                    
                    Text("Updated \(payload.issuedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let expiresAt = payload.expiresAt {
                    VStack(alignment: .trailing) {
                        Text("Expires")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Settings counts by policy
            HStack(spacing: 16) {
                PolicyCount(policy: .locked, count: lockedCount)
                PolicyCount(policy: .suggested, count: suggestedCount)
            }
        }
    }
    
    private var lockedCount: Int {
        var count = 0
        if payload.glucoseUnit?.policy == .locked { count += 1 }
        if payload.highGlucoseThreshold?.policy == .locked { count += 1 }
        if payload.lowGlucoseThreshold?.policy == .locked { count += 1 }
        if payload.urgentHighThreshold?.policy == .locked { count += 1 }
        if payload.urgentLowThreshold?.policy == .locked { count += 1 }
        if payload.highAlertEnabled?.policy == .locked { count += 1 }
        if payload.lowAlertEnabled?.policy == .locked { count += 1 }
        if payload.urgentAlertEnabled?.policy == .locked { count += 1 }
        if payload.staleDataAlertEnabled?.policy == .locked { count += 1 }
        if payload.staleDataMinutes?.policy == .locked { count += 1 }
        if payload.targetGlucose?.policy == .locked { count += 1 }
        if payload.correctionRangeLow?.policy == .locked { count += 1 }
        if payload.correctionRangeHigh?.policy == .locked { count += 1 }
        if payload.maxBasalRate?.policy == .locked { count += 1 }
        if payload.maxBolus?.policy == .locked { count += 1 }
        if payload.suspendThreshold?.policy == .locked { count += 1 }
        return count
    }
    
    private var suggestedCount: Int {
        var count = 0
        if payload.glucoseUnit?.policy == .suggested { count += 1 }
        if payload.highGlucoseThreshold?.policy == .suggested { count += 1 }
        if payload.lowGlucoseThreshold?.policy == .suggested { count += 1 }
        if payload.urgentHighThreshold?.policy == .suggested { count += 1 }
        if payload.urgentLowThreshold?.policy == .suggested { count += 1 }
        if payload.highAlertEnabled?.policy == .suggested { count += 1 }
        if payload.lowAlertEnabled?.policy == .suggested { count += 1 }
        if payload.urgentAlertEnabled?.policy == .suggested { count += 1 }
        if payload.staleDataAlertEnabled?.policy == .suggested { count += 1 }
        if payload.staleDataMinutes?.policy == .suggested { count += 1 }
        if payload.targetGlucose?.policy == .suggested { count += 1 }
        if payload.correctionRangeLow?.policy == .suggested { count += 1 }
        if payload.correctionRangeHigh?.policy == .suggested { count += 1 }
        if payload.maxBasalRate?.policy == .suggested { count += 1 }
        if payload.maxBolus?.policy == .suggested { count += 1 }
        if payload.suspendThreshold?.policy == .suggested { count += 1 }
        return count
    }
}

// MARK: - Policy Count Badge

private struct PolicyCount: View {
    let policy: SettingsPolicy
    let count: Int
    
    var body: some View {
        HStack(spacing: 4) {
            SettingsPolicyIndicator(policy: policy)
            Text("\(count) \(policy == .locked ? "locked" : "suggested")")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .clipShape(Capsule())
    }
    
    private var backgroundColor: Color {
        switch policy {
        case .locked: return .orange.opacity(0.15)
        case .suggested: return .blue.opacity(0.15)
        case .default: return .secondary.opacity(0.15)
        }
    }
}

// MARK: - Settings Section with Managed Support

/// A settings section that shows provider management status
public struct ManagedSettingsSection<Content: View>: View {
    public let title: String
    public let providerName: String?
    public let content: () -> Content
    
    public init(
        title: String,
        providerName: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.providerName = providerName
        self.content = content
    }
    
    public var body: some View {
        Section {
            content()
        } header: {
            HStack {
                Text(title)
                
                Spacer()
                
                if let providerName = providerName {
                    ManagedSettingsBadge(providerName: providerName)
                }
            }
        }
    }
}

// MARK: - Disconnect Provider Button

/// Button to disconnect from managed settings provider
public struct DisconnectProviderButton: View {
    public let providerName: String
    public let action: () async -> Void
    
    @State private var showingConfirmation = false
    @State private var isDisconnecting = false
    
    public init(providerName: String, action: @escaping () async -> Void) {
        self.providerName = providerName
        self.action = action
    }
    
    public var body: some View {
        Button(role: .destructive) {
            showingConfirmation = true
        } label: {
            HStack {
                if isDisconnecting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "link.badge.xmark")
                }
                Text("Disconnect from \(providerName)")
            }
        }
        .disabled(isDisconnecting)
        .confirmationDialog(
            "Disconnect from \(providerName)?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    isDisconnecting = true
                    await action()
                    isDisconnecting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your settings will no longer be managed by \(providerName). You can modify all settings yourself.")
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct ManagedSettingsViews_Previews: PreviewProvider {
    static var previews: some View {
        List {
            ManagedSettingsBadge(providerName: "Acme Clinic")
            
            ManagedSettingRow(
                title: "High Threshold",
                policy: .locked,
                reason: "Required for safety"
            ) {
                Text("180 mg/dL")
            }
            
            ManagedSettingRow(
                title: "Low Threshold",
                policy: .suggested
            ) {
                Text("70 mg/dL")
            }
            
            ManagedSettingRow(
                title: "Chart Range",
                policy: .default
            ) {
                Text("3 hours")
            }
            
            Section {
                SettingsPolicyIndicator(policy: .locked, showLabel: true)
                SettingsPolicyIndicator(policy: .suggested, showLabel: true)
                SettingsPolicyIndicator(policy: .default, showLabel: true)
            } header: {
                Text("Policy Indicators")
            }
        }
    }
}
#endif

#endif // canImport(SwiftUI)
