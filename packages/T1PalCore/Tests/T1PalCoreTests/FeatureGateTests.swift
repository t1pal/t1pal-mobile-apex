// SPDX-License-Identifier: MIT
// FeatureGateTests.swift
// T1PalCoreTests
//
// Tests for feature gating framework
// Requirements: REQ-GATE-001, REQ-GATE-002, REQ-GATE-003
// Trace: BIZ-GATE-001, PRD-015, IAP-ALIGN

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Gated Feature Tests

@Suite("GatedFeature")
struct GatedFeatureTests {
    
    @Test("All features have display names")
    func allFeaturesHaveDisplayNames() {
        for feature in GatedFeature.allCases {
            #expect(!feature.displayName.isEmpty)
        }
    }
    
    @Test("All features have descriptions")
    func allFeaturesHaveDescriptions() {
        for feature in GatedFeature.allCases {
            #expect(!feature.featureDescription.isEmpty)
        }
    }
    
    @Test("All features have benefits lists")
    func allFeaturesHaveBenefits() {
        for feature in GatedFeature.allCases {
            #expect(!feature.benefits.isEmpty)
            #expect(feature.benefits.count >= 3)
        }
    }
    
    @Test("All features have icon names")
    func allFeaturesHaveIcons() {
        for feature in GatedFeature.allCases {
            #expect(!feature.iconName.isEmpty)
        }
    }
    
    @Test("Only managedHosting is gated per IAP-ALIGN")
    func onlyManagedHostingIsGated() {
        // Per IAP-ALIGN: Only managed hosting requires personal tier
        #expect(GatedFeature.managedHosting.requiredTier == .personal)
        
        // All other features should be free
        for feature in GatedFeature.allCases where feature != .managedHosting {
            #expect(feature.requiredTier == .free, "Feature \(feature) should be free")
        }
    }
    
    @Test("isGated returns true only for managedHosting")
    func isGatedReturnsTrueOnlyForManagedHosting() {
        for feature in GatedFeature.allCases {
            if feature == .managedHosting {
                #expect(feature.isGated == true)
            } else {
                #expect(feature.isGated == false, "Feature \(feature) should not be gated")
            }
        }
    }
    
    @Test("requiresHosting returns true only for managedHosting")
    func requiresHostingCorrect() {
        #expect(GatedFeature.managedHosting.requiresHosting == true)
        
        for feature in GatedFeature.allCases where feature != .managedHosting {
            #expect(feature.requiresHosting == false)
        }
    }
}

// MARK: - Feature Gate State Tests

@Suite("FeatureGateState")
struct FeatureGateStateTests {
    
    @Test("isAccessible when tier meets requirement")
    func isAccessibleWhenTierMeetsRequirement() {
        let state = FeatureGateState(
            feature: .managedHosting,
            requiredTier: .personal,
            currentTier: .personal,
            featureDescription: "Test",
            benefitsList: ["Benefit 1"]
        )
        #expect(state.isAccessible == true)
    }
    
    @Test("Free features are always accessible")
    func freeFeaturesAlwaysAccessible() {
        // Per IAP-ALIGN: All features except managedHosting are free
        let state = FeatureGateState(
            feature: .widgets,
            requiredTier: .free,
            currentTier: .free,
            featureDescription: "Test",
            benefitsList: ["Benefit 1"]
        )
        #expect(state.isAccessible == true)
    }
    
    @Test("Not accessible when tier below requirement")
    func notAccessibleWhenTierBelowRequirement() {
        let state = FeatureGateState(
            feature: .managedHosting,
            requiredTier: .personal,
            currentTier: .free,
            featureDescription: "Test",
            benefitsList: ["Benefit 1"]
        )
        #expect(state.isAccessible == false)
    }
    
    @Test("upgradeActionText for personal tier")
    func upgradeActionTextForPersonalTier() {
        let state = FeatureGateState.state(for: .managedHosting, currentTier: .free)
        #expect(state.upgradeActionText == "Get Hosted Nightscout")
    }
    
    @Test("upgradeActionText for free tier")
    func upgradeActionTextForFreeTier() {
        let state = FeatureGateState.state(for: .widgets, currentTier: .free)
        #expect(state.upgradeActionText == "Already Available")
    }
    
    @Test("state(for:) creates correct state")
    func stateForCreatesCorrectState() {
        let state = FeatureGateState.state(for: .managedHosting, currentTier: .free, upgradePrice: "$11.99")
        
        #expect(state.feature == .managedHosting)
        #expect(state.requiredTier == .personal)
        #expect(state.currentTier == .free)
        #expect(state.featureDescription == GatedFeature.managedHosting.featureDescription)
        #expect(state.benefitsList == GatedFeature.managedHosting.benefits)
        #expect(state.upgradePrice == "$11.99")
    }
    
    @Test("defaultState is valid")
    func defaultStateIsValid() {
        let state = FeatureGateState.defaultState
        #expect(state.feature == .widgets)
        #expect(state.currentTier == .free)
        // Widgets is now free, so it's accessible
        #expect(state.isAccessible == true)
    }
}

// MARK: - Feature Gate Result Tests

@Suite("FeatureGateResult")
struct FeatureGateResultTests {
    
    @Test("allowed result returns isAllowed true")
    func allowedResultReturnsTrue() {
        let result = FeatureGateResult.allowed
        #expect(result.isAllowed == true)
    }
    
    @Test("gated result returns isAllowed false")
    func gatedResultReturnsFalse() {
        let state = FeatureGateState.state(for: .managedHosting, currentTier: .free)
        let result = FeatureGateResult.gated(state)
        #expect(result.isAllowed == false)
    }
}

// MARK: - Feature Gate Manager Tests

@Suite("FeatureGateManager")
struct FeatureGateManagerTests {
    
    @Test("Free tier can access all features except managedHosting")
    func freeTierCanAccessMostFeatures() async {
        let manager = FeatureGateManager.mock(tier: .free)
        
        // managedHosting is gated
        let hostingResult = await manager.checkAccess(to: .managedHosting)
        #expect(hostingResult.isAllowed == false)
        
        // widgets is free
        let widgetsResult = await manager.checkAccess(to: .widgets)
        #expect(widgetsResult.isAllowed == true)
        
        // customAlarms is free
        let alarmsResult = await manager.checkAccess(to: .customAlarms)
        #expect(alarmsResult.isAllowed == true)
    }
    
    @Test("Personal tier can access all features")
    func personalTierCanAccessAllFeatures() async {
        let manager = FeatureGateManager.mock(tier: .personal)
        
        for feature in GatedFeature.allCases {
            let result = await manager.checkAccess(to: feature)
            #expect(result.isAllowed == true, "Feature \(feature) should be accessible")
        }
    }
    
    @Test("accessibleFeatures returns correct list")
    func accessibleFeaturesReturnsCorrectList() async {
        let freeManager = FeatureGateManager.mock(tier: .free)
        let freeFeatures = await freeManager.accessibleFeatures()
        // All features except managedHosting should be accessible
        #expect(freeFeatures.count == GatedFeature.allCases.count - 1)
        #expect(!freeFeatures.contains(.managedHosting))
        #expect(freeFeatures.contains(.widgets))
        
        let personalManager = FeatureGateManager.mock(tier: .personal)
        let personalFeatures = await personalManager.accessibleFeatures()
        #expect(personalFeatures.count == GatedFeature.allCases.count)
    }
    
    @Test("gatedFeatures returns correct list")
    func gatedFeaturesReturnsCorrectList() async {
        let freeManager = FeatureGateManager.mock(tier: .free)
        let freeGated = await freeManager.gatedFeatures()
        // Only managedHosting should be gated
        #expect(freeGated.count == 1)
        #expect(freeGated.contains(.managedHosting))
        
        let personalManager = FeatureGateManager.mock(tier: .personal)
        let personalGated = await personalManager.gatedFeatures()
        #expect(personalGated.isEmpty)
    }
}

// MARK: - Critical Features Tests

@Suite("CriticalFeature")
struct CriticalFeatureTests {
    
    @Test("All critical features have display names")
    func allCriticalFeaturesHaveDisplayNames() {
        for feature in CriticalFeature.allCases {
            #expect(!feature.displayName.isEmpty)
        }
    }
    
    @Test("All critical features have reasons")
    func allCriticalFeaturesHaveReasons() {
        for feature in CriticalFeature.allCases {
            #expect(!feature.reason.isEmpty)
        }
    }
    
    @Test("Safety-critical features are marked as such")
    func safetyCriticalFeaturesMarkedCorrectly() {
        let safetyFeatures: [CriticalFeature] = [.basicGlucoseDisplay, .urgentLowAlarm, .urgentHighAlarm]
        for feature in safetyFeatures {
            #expect(feature.reason == "Safety-critical")
        }
    }
    
    @Test("Critical features list matches REQ-GATE-002")
    func criticalFeaturesMatchRequirement() {
        // REQ-GATE-002 specifies these features must remain free
        let required: Set<CriticalFeature> = [
            .basicGlucoseDisplay,
            .urgentLowAlarm,
            .urgentHighAlarm,
            .singleNightscoutConnection,
            .demoMode
        ]
        
        let actual = Set(CriticalFeature.allCases)
        #expect(actual == required)
    }
}

// MARK: - Tier Comparison Tests

@Suite("Tier Comparisons")
struct TierComparisonTests {
    
    @Test("Tier ordering is correct")
    func tierOrderingIsCorrect() {
        #expect(SubscriptionTier.free < .personal)
    }
    
    @Test("Free tier has all features except managed_hosting")
    func freeTierHasAllFeaturesExceptHosting() {
        let freeFeatures = SubscriptionTier.free.features
        let personalFeatures = SubscriptionTier.personal.features
        
        // Free should have everything except managed_hosting
        #expect(freeFeatures.contains("cgm_connection"))
        #expect(freeFeatures.contains("widgets"))
        #expect(freeFeatures.contains("watch_app"))
        #expect(freeFeatures.contains("family_sharing"))
        #expect(!freeFeatures.contains("managed_hosting"))
        
        // Personal should include managed_hosting
        #expect(personalFeatures.contains("managed_hosting"))
        
        // Personal should include all free features
        for feature in freeFeatures {
            #expect(personalFeatures.contains(feature))
        }
    }
    
    @Test("hasFeature works correctly")
    func hasFeatureWorksCorrectly() {
        // Free tier
        #expect(SubscriptionTier.free.hasFeature("cgm_connection") == true)
        #expect(SubscriptionTier.free.hasFeature("managed_hosting") == false)
        
        // Personal tier
        #expect(SubscriptionTier.personal.hasFeature("cgm_connection") == true)
        #expect(SubscriptionTier.personal.hasFeature("managed_hosting") == true)
    }
}
