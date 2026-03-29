// SPDX-License-Identifier: AGPL-3.0-or-later
// ReviewNotes.swift
// T1PalCore
//
// Apple App Store review notes generator.
// Trace: APP-REVIEW-ONBOARDING-STRATEGY, APP-ONBOARD-006

import Foundation

// MARK: - App Type

/// Type of T1Pal app for review notes generation
public enum T1PalAppType: String, Codable, Sendable {
    case demo = "T1PalDemo"
    case follower = "T1PalFollower"
    case cgm = "T1PalCGM"
    case aid = "T1PalAID"
    
    public var displayName: String {
        switch self {
        case .demo: return "T1Pal Demo"
        case .follower: return "T1Pal Hub"
        case .cgm: return "T1Pal CGM"
        case .aid: return "T1Pal AID"
        }
    }
    
    public var riskLevel: AppRiskLevel {
        switch self {
        case .demo: return .none
        case .follower: return .low
        case .cgm: return .medium
        case .aid: return .high
        }
    }
    
    public var distributionPath: DistributionPath {
        switch self {
        case .demo: return .testFlightOnly
        case .follower: return .appStore
        case .cgm: return .appStore
        case .aid: return .testFlightOnly
        }
    }
}

/// Risk level for medical device classification
public enum AppRiskLevel: String, Codable, Sendable {
    case none = "None"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

/// App distribution path
public enum DistributionPath: String, Codable, Sendable {
    case appStore = "App Store"
    case testFlightOnly = "TestFlight Only"
}

// MARK: - Review Notes

/// Apple App Store review notes generator
public struct ReviewNotesGenerator: Sendable {
    
    public let appType: T1PalAppType
    public let version: String
    public let buildNumber: String
    
    public init(appType: T1PalAppType, version: String, buildNumber: String) {
        self.appType = appType
        self.version = version
        self.buildNumber = buildNumber
    }
    
    // MARK: - Generate Full Notes
    
    /// Generate complete review notes for App Store submission
    public func generateReviewNotes() -> String {
        var sections: [String] = []
        
        sections.append(generateHeader())
        sections.append(generateAppDescription())
        sections.append(generateIntendedUse())
        sections.append(generateTestingInstructions())
        sections.append(generateCapabilityVerification())
        
        if appType == .cgm || appType == .aid {
            sections.append(generateMedicalDeviceNotes())
        }
        
        if appType == .aid {
            sections.append(generateAIDSpecificNotes())
        }
        
        sections.append(generateDemoCredentials())
        
        return sections.joined(separator: "\n\n---\n\n")
    }
    
    // MARK: - Sections
    
    private func generateHeader() -> String {
        """
        # \(appType.displayName) - App Store Review Notes
        
        **Version:** \(version) (\(buildNumber))
        **Distribution:** \(appType.distributionPath.rawValue)
        **Medical Device Risk:** \(appType.riskLevel.rawValue)
        **Generated:** \(ISO8601DateFormatter().string(from: Date()))
        """
    }
    
    private func generateAppDescription() -> String {
        switch appType {
        case .demo:
            return """
            ## App Description
            
            T1Pal Demo is a demonstration app showing simulated glucose data for 
            people with Type 1 Diabetes. It uses realistic simulation patterns 
            to demonstrate the app's capabilities without requiring real medical 
            devices.
            
            **Key Points:**
            - No real medical data or devices are used
            - All glucose readings are simulated
            - Debug tab allows verification of iOS platform integration
            - Intended for developer testing and demonstration
            """
            
        case .follower:
            return """
            ## App Description
            
            T1Pal Hub displays glucose data from remote cloud services for 
            caregivers and family members of people with Type 1 Diabetes.
            
            **Key Points:**
            - Displays glucose data from Nightscout, Dexcom Share, or LibreLinkUp
            - No direct sensor connection - reads from cloud services only
            - Notifications alert caregivers to glucose events
            - Designed for remote monitoring, not therapy decisions
            """
            
        case .cgm:
            return """
            ## App Description
            
            T1Pal CGM connects to FDA-cleared Continuous Glucose Monitoring sensors 
            via Bluetooth to display real-time glucose readings for people with 
            Type 1 Diabetes.
            
            **Key Points:**
            - Connects to FDA-cleared CGM sensors (Dexcom G6/G7, FreeStyle Libre)
            - Device compatibility is verified before sensor connection
            - Users can choose to use alongside vendor apps or as primary display
            - Provides glucose trend information and customizable alerts
            """
            
        case .aid:
            return """
            ## App Description
            
            T1Pal AID is an Automated Insulin Delivery system that connects to 
            CGM sensors and insulin pumps to automate basal insulin delivery for 
            people with Type 1 Diabetes.
            
            **Key Points:**
            - Connects to CGM sensors and insulin pumps via Bluetooth
            - Implements oref0/oref1 algorithm for automated insulin adjustments
            - Requires user acknowledgment of risks before enabling
            - Currently distributed via TestFlight only (not FDA-cleared)
            """
        }
    }
    
    private func generateIntendedUse() -> String {
        """
        ## Intended Use Verification
        
        The app verifies device capability before enabling features:
        
        \(capabilityTable())
        
        Users cannot enable features their device doesn't support. The app 
        performs capability checks during onboarding and prevents access to 
        features that require unavailable capabilities.
        """
    }
    
    private func capabilityTable() -> String {
        switch appType {
        case .demo:
            return """
            | Capability | Required | Purpose |
            |------------|----------|---------|
            | None | - | Demo mode uses simulation only |
            """
            
        case .follower:
            return """
            | Capability | Required | Purpose |
            |------------|----------|---------|
            | Network | Yes | Fetch glucose from cloud |
            | Notifications | Recommended | Alert to glucose events |
            | Critical Alerts | Optional | High-priority alerts |
            """
            
        case .cgm:
            return """
            | Capability | Required | Purpose |
            |------------|----------|---------|
            | BLE Central | Yes | Connect to CGM sensor |
            | Background BLE | Yes | Receive readings in background |
            | Notifications | Recommended | Alert to glucose events |
            | Critical Alerts | Recommended | High-priority alerts |
            | HealthKit Write | Recommended | Sync to Health app |
            """
            
        case .aid:
            return """
            | Capability | Required | Purpose |
            |------------|----------|---------|
            | BLE Central | Critical | Connect to CGM and pump |
            | Background BLE | Critical | Maintain therapy loop |
            | BLE State Restoration | Critical | Resume after reboot |
            | Notifications | Critical | Alert to therapy events |
            | Critical Alerts | Recommended | Urgent safety alerts |
            | HealthKit Read/Write | Required | Therapy data sync |
            | Background App Refresh | Required | Algorithm execution |
            """
        }
    }
    
    private func generateTestingInstructions() -> String {
        """
        ## Compatibility Testing Instructions
        
        This app includes a built-in compatibility testing system to verify 
        iOS platform integration.
        
        ### To Access Compatibility Tests:
        
        \(testAccessInstructions())
        
        ### Running Tests:
        
        1. Tap "Run Quick Check" for basic capability verification (~30 seconds)
        2. Tap "Run Full Test" for comprehensive testing (~2 minutes)
        3. All tests should pass on review devices
        4. If any test fails, tap "Export Diagnostics" to generate a report
        
        ### Expected Results:
        
        - All BLE tests should show ✅ on devices with Bluetooth
        - Notification tests require user authorization
        - HealthKit tests require user authorization
        - Background mode tests verify Info.plist configuration
        """
    }
    
    private func testAccessInstructions() -> String {
        switch appType {
        case .demo, .aid:
            return """
            1. Open app
            2. Tap "Debug" tab at bottom
            3. Tap "Compatibility Tests"
            """
            
        case .follower:
            return """
            1. Open app
            2. Go to Settings tab
            3. Tap version number 7 times to enable debug mode
            4. Tap "Debug" which now appears
            5. Tap "Compatibility Tests"
            """
            
        case .cgm:
            return """
            1. Open app
            2. Go to Settings tab
            3. Tap "Debug" (visible in TestFlight builds)
               - For App Store builds: Tap version number 7 times
            4. Tap "Compatibility Tests"
            """
        }
    }
    
    private func generateCapabilityVerification() -> String {
        """
        ## Capability Verification
        
        The app's onboarding flow includes mandatory capability verification:
        
        ### First Launch:
        - Full compatibility test runs automatically
        - Critical capabilities must pass to proceed
        - Recommended capabilities show warnings if unavailable
        
        ### Subsequent Launches:
        - Quick check verifies essential capabilities
        - Full re-test after iOS updates\(appType == .aid ? " (mandatory for AID)" : "")
        
        ### Manual Testing:
        - Users can re-run tests anytime from Settings → Debug
        - Diagnostic export available for troubleshooting
        """
    }
    
    private func generateMedicalDeviceNotes() -> String {
        """
        ## Medical Device Information
        
        \(appType == .cgm ? cgmMedicalNotes() : aidMedicalNotes())
        
        ### Regulatory Status:
        \(regulatoryStatus())
        
        ### Safety Measures:
        \(safetyMeasures())
        """
    }
    
    private func cgmMedicalNotes() -> String {
        """
        This app displays data from FDA-cleared CGM devices. The app itself 
        is a secondary display and does not make therapy recommendations.
        
        **Supported Devices:**
        - Dexcom G6 (FDA K173467)
        - Dexcom G7 (FDA K222027)
        - FreeStyle Libre 2 (FDA K200201)
        - FreeStyle Libre 3 (FDA K220527)
        """
    }
    
    private func aidMedicalNotes() -> String {
        """
        This app implements Automated Insulin Delivery using open-source 
        algorithms. It connects to FDA-cleared CGM sensors and insulin pumps 
        to automate basal insulin delivery.
        
        **Algorithm Implementation:**
        - Based on OpenAPS oref0/oref1 algorithms
        - Safety limits enforced in software
        - User configurable therapy parameters
        """
    }
    
    private func regulatoryStatus() -> String {
        switch appType {
        case .demo:
            return "- N/A - Demonstration app with simulated data only"
        case .follower:
            return "- Secondary display app - not a medical device"
        case .cgm:
            return """
            - Secondary display for FDA-cleared CGM devices
            - Not a medical device - does not make therapy recommendations
            """
        case .aid:
            return """
            - NOT FDA-cleared
            - Distributed via TestFlight only
            - Users must acknowledge experimental nature
            - Requires healthcare provider consultation
            """
        }
    }
    
    private func safetyMeasures() -> String {
        switch appType {
        case .demo:
            return "- Clear labeling as simulation/demo"
        case .follower:
            return """
            - Clear labeling as display-only
            - Latency warnings for time-delayed data
            """
        case .cgm:
            return """
            - Capability verification before sensor connection
            - Vendor app coexistence detection
            - Connection mode recommendations
            """
        case .aid:
            return """
            - Mandatory safety acknowledgments before use
            - Colocated AID app detection and blocking
            - Insulin delivery safety limits
            - Suspend/resume controls always accessible
            - Bolus cancellation available
            """
        }
    }
    
    private func generateAIDSpecificNotes() -> String {
        """
        ## AID-Specific Safety Information
        
        ### Colocated App Detection:
        
        The app detects if other AID apps (Loop, Trio, iAPS) are installed 
        and shows a critical warning:
        
        - Only ONE AID app should control insulin delivery at a time
        - Running multiple AID apps simultaneously can cause dangerous dosing
        - Users must confirm they have disabled other AID apps
        
        ### Safety Controls:
        
        The app provides immediate access to safety controls:
        
        - **Suspend Delivery**: Immediately stops all insulin delivery
        - **Resume Delivery**: Resumes automated delivery after suspend
        - **Cancel Bolus**: Stops any in-progress bolus
        - **Override Management**: Temporary therapy adjustments
        
        ### User Acknowledgments:
        
        Before enabling AID mode, users must acknowledge:
        
        1. The app is not FDA-cleared
        2. They accept responsibility for therapy decisions
        3. They have consulted with their healthcare provider
        """
    }
    
    private func generateDemoCredentials() -> String {
        """
        ## Demo Credentials & Test Data
        
        \(demoCredentials())
        
        ### Test Scenarios:
        
        \(testScenarios())
        """
    }
    
    private func demoCredentials() -> String {
        switch appType {
        case .demo:
            return """
            No credentials required. The app uses built-in simulation data.
            
            **Simulation Patterns Available:**
            - Stable (70-120 mg/dL range)
            - Post-meal rise
            - Nighttime hypoglycemia
            - Exercise pattern
            - Real-world realistic
            """
            
        case .follower:
            return """
            **Test Nightscout Site:**
            - URL: https://demo.nightscout.info
            - No authentication required for read access
            
            **Note:** For Dexcom Share testing, use your own credentials 
            or request demo credentials from Dexcom Developer portal.
            """
            
        case .cgm:
            return """
            **For BLE Testing:**
            A real CGM transmitter is required for full BLE testing. 
            The app's simulation mode can demonstrate UI without hardware.
            
            **Simulation Mode:**
            - Settings → Debug → Enable Simulation
            - Provides simulated glucose data for UI testing
            """
            
        case .aid:
            return """
            **Hardware Requirements:**
            Full AID testing requires real CGM and pump hardware.
            
            **Simulation Mode:**
            - Settings → Debug → Enable Simulation
            - Simulates CGM + pump for UI and algorithm testing
            - No real insulin delivery in simulation mode
            """
        }
    }
    
    private func testScenarios() -> String {
        switch appType {
        case .demo:
            return """
            1. Launch app, observe simulated glucose display
            2. Switch simulation patterns in Settings
            3. Run compatibility tests in Debug tab
            4. Export diagnostics
            """
            
        case .follower:
            return """
            1. Connect to demo Nightscout site
            2. Verify glucose display updates
            3. Test notification permissions
            4. Run compatibility tests
            """
            
        case .cgm:
            return """
            1. Complete onboarding flow
            2. Verify capability checks pass
            3. Test connection mode selection
            4. (With hardware) Verify sensor pairing
            5. Test HealthKit integration
            """
            
        case .aid:
            return """
            1. Complete safety acknowledgments
            2. Verify colocated app warning (if applicable)
            3. Complete CGM setup
            4. Complete pump setup (simulation mode)
            5. Verify safety controls (suspend/resume)
            6. Test algorithm operation
            """
        }
    }
}

// MARK: - Structured Export

extension ReviewNotesGenerator {
    
    /// Export notes as structured data for programmatic use
    public func exportAsJSON() throws -> Data {
        let notes = ReviewNotesData(
            appType: appType,
            version: version,
            buildNumber: buildNumber,
            generatedAt: Date(),
            riskLevel: appType.riskLevel,
            distributionPath: appType.distributionPath,
            requiredCapabilities: requiredCapabilities(),
            testAccessPath: testAccessPath()
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(notes)
    }
    
    private func requiredCapabilities() -> [String] {
        switch appType {
        case .demo:
            return []
        case .follower:
            return ["Network"]
        case .cgm:
            return ["BLE Central", "Background BLE"]
        case .aid:
            return ["BLE Central", "Background BLE", "BLE State Restoration", 
                    "Notifications", "HealthKit", "Background App Refresh"]
        }
    }
    
    private func testAccessPath() -> [String] {
        switch appType {
        case .demo, .aid:
            return ["Debug Tab", "Compatibility Tests"]
        case .follower:
            return ["Settings", "Tap version 7x", "Debug", "Compatibility Tests"]
        case .cgm:
            return ["Settings", "Debug", "Compatibility Tests"]
        }
    }
}

/// Structured review notes data
public struct ReviewNotesData: Codable, Sendable {
    public let appType: T1PalAppType
    public let version: String
    public let buildNumber: String
    public let generatedAt: Date
    public let riskLevel: AppRiskLevel
    public let distributionPath: DistributionPath
    public let requiredCapabilities: [String]
    public let testAccessPath: [String]
}
