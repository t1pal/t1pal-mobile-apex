// SPDX-License-Identifier: AGPL-3.0-or-later
// FeatureGate.swift
// T1PalCore
//
// Feature gating framework for tier-based access control
// Requirements: REQ-GATE-001, REQ-GATE-003
// Trace: BIZ-GATE-001, PRD-015
//
// NOTE: With the simplified subscription model (IAP-ALIGN), only managed_hosting
// requires the personal tier. All other features are free (BYONS model).

import Foundation

// MARK: - Gated Features

/// Features that may require subscription tier access
/// Per REQ-GATE-002, safety-critical features are never gated
/// Per IAP-ALIGN, only managedHosting requires personal tier - all others are free
public enum GatedFeature: String, CaseIterable, Sendable, Codable {
    case customAlarms = "custom_alarms"
    case widgets = "widgets"
    case watchComplications = "watch_complications"
    case multiInstance = "multi_instance"
    case managedHosting = "managed_hosting"
    case remoteControl = "remote_control"
    case agentAPI = "agent_api"
    case analytics = "analytics"
    case familySharing = "family_sharing"
    case caregiverAlerts = "caregiver_alerts"
    case betaAccess = "beta_access"
    case prioritySupport = "priority_support"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .customAlarms: return "Custom Alarms"
        case .widgets: return "Widgets"
        case .watchComplications: return "Watch Complications"
        case .multiInstance: return "Multiple Nightscout Instances"
        case .managedHosting: return "Managed Nightscout Hosting"
        case .remoteControl: return "Remote Control"
        case .agentAPI: return "Agent API Access"
        case .analytics: return "Advanced Analytics"
        case .familySharing: return "Family Sharing"
        case .caregiverAlerts: return "Caregiver Alerts"
        case .betaAccess: return "Beta Features"
        case .prioritySupport: return "Priority Support"
        }
    }
    
    /// Feature description for upgrade prompts
    public var featureDescription: String {
        switch self {
        case .customAlarms:
            return "Create personalized glucose alerts with custom thresholds and sounds"
        case .widgets:
            return "Add glucose widgets to your home screen for at-a-glance monitoring"
        case .watchComplications:
            return "View glucose on your Apple Watch face"
        case .multiInstance:
            return "Connect multiple Nightscout instances for family monitoring"
        case .managedHosting:
            return "Let us host your Nightscout instance with automatic updates"
        case .remoteControl:
            return "Send bolus and carb commands remotely"
        case .agentAPI:
            return "Access the Agent API for automated decision support"
        case .analytics:
            return "Detailed reports on time in range, patterns, and trends"
        case .familySharing:
            return "Share your subscription with up to 5 family members"
        case .caregiverAlerts:
            return "Send alerts to caregivers when you need help"
        case .betaAccess:
            return "Get early access to new features before release"
        case .prioritySupport:
            return "Jump to the front of the support queue"
        }
    }
    
    /// Benefits list for upgrade prompts
    public var benefits: [String] {
        switch self {
        case .customAlarms:
            return [
                "Set multiple threshold levels",
                "Choose from 10+ alert sounds",
                "Schedule quiet hours",
                "Customize repeat intervals"
            ]
        case .widgets:
            return [
                "Large, medium, and small widget sizes",
                "Show trend arrows and IOB",
                "Customizable backgrounds",
                "Update every 5 minutes"
            ]
        case .watchComplications:
            return [
                "All watch faces supported",
                "Glucose value always visible",
                "Tap to open full app",
                "Works offline"
            ]
        case .multiInstance:
            return [
                "Monitor up to 5 Nightscout instances",
                "Quick switch between users",
                "Unified alarm management",
                "Perfect for families"
            ]
        case .managedHosting:
            return [
                "We handle all server maintenance",
                "Automatic security updates",
                "99.9% uptime guarantee",
                "No technical knowledge needed"
            ]
        case .remoteControl:
            return [
                "Send bolus commands securely",
                "Log carbs remotely",
                "Override temporary targets",
                "Full audit trail"
            ]
        case .agentAPI:
            return [
                "Automated decision suggestions",
                "Integration with health platforms",
                "Machine learning insights",
                "Research data export"
            ]
        case .analytics:
            return [
                "Weekly and monthly reports",
                "Time in range breakdowns",
                "Pattern detection",
                "PDF export for doctors"
            ]
        case .familySharing:
            return [
                "Share with up to 5 family members",
                "Each gets their own account",
                "Manage from one subscription",
                "Works with Apple Family Sharing"
            ]
        case .caregiverAlerts:
            return [
                "Push notifications to caregivers",
                "SMS alerts as backup",
                "Customizable escalation",
                "Location sharing option"
            ]
        case .betaAccess:
            return [
                "Try new features first",
                "Shape product development",
                "Direct feedback channel",
                "Exclusive founder community"
            ]
        case .prioritySupport:
            return [
                "24-hour response guarantee",
                "Direct email support",
                "Screen sharing sessions",
                "Feature request priority"
            ]
        }
    }
    
    /// Minimum tier required for this feature
    /// Per IAP-ALIGN: Only managedHosting requires personal tier
    /// All other features are FREE (BYONS model)
    public var requiredTier: SubscriptionTier {
        switch self {
        case .managedHosting:
            return .personal  // Only feature that requires subscription
        default:
            return .free  // All other features are free (BYONS)
        }
    }
    
    /// Icon name for the feature
    public var iconName: String {
        switch self {
        case .customAlarms: return "bell.badge"
        case .widgets: return "square.grid.2x2"
        case .watchComplications: return "applewatch"
        case .multiInstance: return "person.3"
        case .managedHosting: return "server.rack"
        case .remoteControl: return "iphone.radiowaves.left.and.right"
        case .agentAPI: return "cpu"
        case .analytics: return "chart.bar.xaxis"
        case .familySharing: return "person.3.fill"
        case .caregiverAlerts: return "heart.text.square"
        case .betaAccess: return "testtube.2"
        case .prioritySupport: return "star.circle"
        }
    }
}

// MARK: - Feature Gate State

/// State for feature gate UI (per REQ-GATE-003)
public struct FeatureGateState: Sendable, Equatable {
    public let feature: GatedFeature
    public let requiredTier: SubscriptionTier
    public let currentTier: SubscriptionTier
    public let featureDescription: String
    public let benefitsList: [String]
    public let upgradePrice: String?
    
    /// Whether the feature is accessible
    public var isAccessible: Bool {
        currentTier >= requiredTier
    }
    
    /// Upgrade action text
    public var upgradeActionText: String {
        switch requiredTier {
        case .free:
            return "Already Available"
        case .personal:
            return "Get Hosted Nightscout"
        }
    }
    
    public init(
        feature: GatedFeature,
        requiredTier: SubscriptionTier,
        currentTier: SubscriptionTier,
        featureDescription: String,
        benefitsList: [String],
        upgradePrice: String? = nil
    ) {
        self.feature = feature
        self.requiredTier = requiredTier
        self.currentTier = currentTier
        self.featureDescription = featureDescription
        self.benefitsList = benefitsList
        self.upgradePrice = upgradePrice
    }
    
    /// Create state from a gated feature
    public static func state(
        for feature: GatedFeature,
        currentTier: SubscriptionTier,
        upgradePrice: String? = nil
    ) -> FeatureGateState {
        FeatureGateState(
            feature: feature,
            requiredTier: feature.requiredTier,
            currentTier: currentTier,
            featureDescription: feature.featureDescription,
            benefitsList: feature.benefits,
            upgradePrice: upgradePrice
        )
    }
    
    /// Default state for previews
    public static var defaultState: FeatureGateState {
        state(for: .widgets, currentTier: .free, upgradePrice: "$9.99/month")
    }
}

// MARK: - Feature Gate Result

/// Result of a feature gate check
public enum FeatureGateResult: Sendable, Equatable {
    /// Feature is accessible
    case allowed
    /// Feature requires upgrade
    case gated(FeatureGateState)
    
    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

// MARK: - Feature Gate Manager

/// Manages feature access based on subscription tier
/// Per REQ-GATE-001, shows graceful upgrade prompts
/// Per REQ-GATE-002, never gates safety-critical features
public actor FeatureGateManager {
    
    private let subscriptionManager: any SubscriptionManaging
    private var cachedTier: SubscriptionTier?
    private var priceCache: [SubscriptionTier: String] = [:]
    
    public init(subscriptionManager: any SubscriptionManaging) {
        self.subscriptionManager = subscriptionManager
    }
    
    /// Check if a feature is accessible
    public func checkAccess(to feature: GatedFeature) async -> FeatureGateResult {
        let status = await subscriptionManager.currentStatus
        let currentTier = status.tier
        cachedTier = currentTier
        
        if currentTier >= feature.requiredTier {
            return .allowed
        }
        
        let price = await getUpgradePrice(for: feature.requiredTier)
        let state = FeatureGateState.state(
            for: feature,
            currentTier: currentTier,
            upgradePrice: price
        )
        return .gated(state)
    }
    
    /// Quick check without building full state
    public func hasAccess(to feature: GatedFeature) async -> Bool {
        let status = await subscriptionManager.currentStatus
        return status.tier >= feature.requiredTier
    }
    
    /// Get all accessible features for current tier
    public func accessibleFeatures() async -> [GatedFeature] {
        let status = await subscriptionManager.currentStatus
        return GatedFeature.allCases.filter { $0.requiredTier <= status.tier }
    }
    
    /// Get all gated features for current tier
    public func gatedFeatures() async -> [GatedFeature] {
        let status = await subscriptionManager.currentStatus
        return GatedFeature.allCases.filter { $0.requiredTier > status.tier }
    }
    
    /// Get upgrade price for a tier
    private func getUpgradePrice(for tier: SubscriptionTier) async -> String? {
        if let cached = priceCache[tier] {
            return cached
        }
        
        // Get product info for the tier
        guard let products = try? await subscriptionManager.availableProducts() else {
            return nil
        }
        
        // Find product matching tier
        let product = products.first { product in
            if let t1palProduct = T1PalProduct(rawValue: product.id) {
                return t1palProduct.tierLevel == tier
            }
            return false
        }
        
        if let price = product?.price {
            priceCache[tier] = price
        }
        
        return product?.price
    }
    
    /// Invalidate cache (call after subscription changes)
    public func invalidateCache() {
        cachedTier = nil
        priceCache.removeAll()
    }
}

// MARK: - Critical Features (Never Gated)

/// Features that must never be gated per REQ-GATE-002
public enum CriticalFeature: String, CaseIterable, Sendable {
    case basicGlucoseDisplay = "basic_glucose_display"
    case urgentLowAlarm = "urgent_low_alarm"
    case urgentHighAlarm = "urgent_high_alarm"
    case singleNightscoutConnection = "single_nightscout_connection"
    case demoMode = "demo_mode"
    
    public var displayName: String {
        switch self {
        case .basicGlucoseDisplay: return "Basic Glucose Display"
        case .urgentLowAlarm: return "Urgent Low Alarm"
        case .urgentHighAlarm: return "Urgent High Alarm"
        case .singleNightscoutConnection: return "Nightscout Connection"
        case .demoMode: return "Demo Mode"
        }
    }
    
    public var reason: String {
        switch self {
        case .basicGlucoseDisplay, .urgentLowAlarm, .urgentHighAlarm:
            return "Safety-critical"
        case .singleNightscoutConnection:
            return "Core functionality"
        case .demoMode:
            return "Evaluation"
        }
    }
}

// MARK: - Feature Gate Convenience Extensions

extension FeatureGateManager {
    
    /// Create with mock manager for testing
    public static func mock(tier: SubscriptionTier = .free) -> FeatureGateManager {
        FeatureGateManager(subscriptionManager: MockSubscriptionManager(initialTier: tier))
    }
}

extension GatedFeature {
    
    /// Check if this feature is gated (requires paid tier)
    public var isGated: Bool {
        requiredTier != .free
    }
    
    /// Check if the feature requires personal (hosted NS) tier
    public var requiresHosting: Bool {
        requiredTier == .personal
    }
}
