// SPDX-License-Identifier: AGPL-3.0-or-later
// AppStoreMetadata.swift
// T1PalCore
//
// App Store Connect metadata for submission
// Trace: APP-RELEASE-001, PRD-011

import Foundation

// MARK: - App Store Category

/// App Store primary category
public enum AppStoreCategory: String, Codable, Sendable {
    case health = "Health & Fitness"
    case medical = "Medical"
    case utilities = "Utilities"
    case lifestyle = "Lifestyle"
}

/// App Store age rating
public enum AgeRating: String, Codable, Sendable {
    case fourPlus = "4+"
    case ninePlus = "9+"
    case twelvePlus = "12+"
    case seventeenPlus = "17+"
}

// MARK: - Screenshot Specification

/// Screenshot device type for App Store
public enum ScreenshotDevice: String, Codable, Sendable, CaseIterable {
    case iPhone6_7 = "iPhone 6.7\""       // iPhone 15 Pro Max, 14 Pro Max
    case iPhone6_5 = "iPhone 6.5\""       // iPhone 11 Pro Max, XS Max
    case iPhone5_5 = "iPhone 5.5\""       // iPhone 8 Plus, 7 Plus
    case iPad12_9 = "iPad 12.9\""         // iPad Pro 12.9
    case iPad11 = "iPad 11\""             // iPad Pro 11
    
    /// Pixel dimensions for screenshot
    public var dimensions: (width: Int, height: Int) {
        switch self {
        case .iPhone6_7: return (1290, 2796)
        case .iPhone6_5: return (1284, 2778)
        case .iPhone5_5: return (1242, 2208)
        case .iPad12_9: return (2048, 2732)
        case .iPad11: return (1668, 2388)
        }
    }
    
    /// Whether this is a required device size
    public var isRequired: Bool {
        switch self {
        case .iPhone6_7, .iPhone6_5: return true
        case .iPhone5_5, .iPad12_9, .iPad11: return false
        }
    }
}

/// Screenshot specification for a single screen
public struct ScreenshotSpec: Codable, Sendable, Identifiable {
    public let id: String
    public let screenName: String
    public let description: String
    public let order: Int
    public let stateDescription: String
    
    public init(id: String, screenName: String, description: String, order: Int, stateDescription: String) {
        self.id = id
        self.screenName = screenName
        self.description = description
        self.order = order
        self.stateDescription = stateDescription
    }
}

// MARK: - Privacy Data Types

/// Privacy data usage types for App Store
public enum PrivacyDataType: String, Codable, Sendable, CaseIterable {
    case healthData = "Health & Fitness"
    case location = "Location"
    case contactInfo = "Contact Info"
    case identifiers = "Identifiers"
    case usageData = "Usage Data"
    case diagnostics = "Diagnostics"
}

/// Privacy data usage purpose
public enum PrivacyUsage: String, Codable, Sendable {
    case appFunctionality = "App Functionality"
    case analytics = "Analytics"
    case productPersonalization = "Product Personalization"
    case thirdPartyAdvertising = "Third-Party Advertising"
}

/// Privacy data declaration
public struct PrivacyDeclaration: Codable, Sendable {
    public let dataType: PrivacyDataType
    public let usage: PrivacyUsage
    public let linkedToUser: Bool
    public let usedForTracking: Bool
    
    public init(dataType: PrivacyDataType, usage: PrivacyUsage, linkedToUser: Bool, usedForTracking: Bool) {
        self.dataType = dataType
        self.usage = usage
        self.linkedToUser = linkedToUser
        self.usedForTracking = usedForTracking
    }
}

// MARK: - App Store Metadata

/// Complete App Store metadata for an app
public struct AppStoreMetadata: Codable, Sendable {
    public let appType: T1PalAppType
    public let name: String
    public let subtitle: String
    public let description: String
    public let keywords: [String]
    public let primaryCategory: AppStoreCategory
    public let secondaryCategory: AppStoreCategory?
    public let ageRating: AgeRating
    public let ageRatingJustification: String
    public let privacyDeclarations: [PrivacyDeclaration]
    public let privacyPolicyURL: String
    public let supportURL: String
    public let marketingURL: String?
    public let screenshotSpecs: [ScreenshotSpec]
    public let whatsNew: String
    
    public init(
        appType: T1PalAppType,
        name: String,
        subtitle: String,
        description: String,
        keywords: [String],
        primaryCategory: AppStoreCategory,
        secondaryCategory: AppStoreCategory? = nil,
        ageRating: AgeRating,
        ageRatingJustification: String,
        privacyDeclarations: [PrivacyDeclaration],
        privacyPolicyURL: String,
        supportURL: String,
        marketingURL: String? = nil,
        screenshotSpecs: [ScreenshotSpec],
        whatsNew: String
    ) {
        self.appType = appType
        self.name = name
        self.subtitle = subtitle
        self.description = description
        self.keywords = keywords
        self.primaryCategory = primaryCategory
        self.secondaryCategory = secondaryCategory
        self.ageRating = ageRating
        self.ageRatingJustification = ageRatingJustification
        self.privacyDeclarations = privacyDeclarations
        self.privacyPolicyURL = privacyPolicyURL
        self.supportURL = supportURL
        self.marketingURL = marketingURL
        self.screenshotSpecs = screenshotSpecs
        self.whatsNew = whatsNew
    }
    
    /// Keyword string for App Store (comma-separated, max 100 chars)
    public var keywordString: String {
        let joined = keywords.joined(separator: ",")
        if joined.count <= 100 {
            return joined
        }
        // Truncate to fit within 100 characters
        var result = ""
        for keyword in keywords {
            let candidate = result.isEmpty ? keyword : "\(result),\(keyword)"
            if candidate.count <= 100 {
                result = candidate
            } else {
                break
            }
        }
        return result
    }
    
    /// Validate metadata for App Store requirements
    public func validate() -> [String] {
        var errors: [String] = []
        
        if name.count > 30 {
            errors.append("App name exceeds 30 characters")
        }
        
        if subtitle.count > 30 {
            errors.append("Subtitle exceeds 30 characters")
        }
        
        if description.count > 4000 {
            errors.append("Description exceeds 4000 characters")
        }
        
        if keywords.joined(separator: ",").count > 100 {
            errors.append("Keywords exceed 100 characters total")
        }
        
        if whatsNew.count > 4000 {
            errors.append("What's New exceeds 4000 characters")
        }
        
        if screenshotSpecs.count < 1 {
            errors.append("At least 1 screenshot required")
        }
        
        if privacyPolicyURL.isEmpty {
            errors.append("Privacy policy URL required")
        }
        
        return errors
    }
    
    /// Export as JSON for App Store Connect API
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Metadata Factory

/// Factory for generating app-specific metadata
public struct AppStoreMetadataFactory: Sendable {
    
    public init() {}
    
    /// Generate metadata for a specific app type
    public func generate(for appType: T1PalAppType, version: String) -> AppStoreMetadata {
        switch appType {
        case .demo:
            return generateDemoMetadata(version: version)
        case .follower:
            return generateFollowerMetadata(version: version)
        case .cgm:
            return generateCGMMetadata(version: version)
        case .aid:
            return generateAIDMetadata(version: version)
        }
    }
    
    // MARK: - Demo App
    
    private func generateDemoMetadata(version: String) -> AppStoreMetadata {
        AppStoreMetadata(
            appType: .demo,
            name: "T1Pal Demo",
            subtitle: "Diabetes Management Preview",
            description: """
            T1Pal Demo showcases simulated glucose monitoring and insulin delivery features for educational purposes.
            
            KEY FEATURES:
            • View simulated CGM glucose data with trend arrows
            • Explore demo insulin pump controls
            • Preview AID algorithm visualizations
            • Learn about closed-loop diabetes management
            
            IMPORTANT: This app uses SIMULATED DATA ONLY. It does not connect to real medical devices and is intended for demonstration and educational purposes.
            
            Perfect for:
            • Healthcare providers learning about AID systems
            • Developers exploring diabetes technology
            • Patients curious about closed-loop systems
            • Educators teaching about diabetes management
            
            No real medical data is collected or processed.
            """,
            keywords: ["diabetes", "glucose", "CGM", "demo", "simulation", "insulin", "T1D", "education", "health"],
            primaryCategory: .health,
            secondaryCategory: .medical,
            ageRating: .fourPlus,
            ageRatingJustification: "App contains no objectionable content. Uses only simulated demo data.",
            privacyDeclarations: [
                PrivacyDeclaration(dataType: .diagnostics, usage: .analytics, linkedToUser: false, usedForTracking: false)
            ],
            privacyPolicyURL: "https://t1pal.com/privacy",
            supportURL: "https://t1pal.com/support",
            marketingURL: "https://t1pal.com",
            screenshotSpecs: demoScreenshots(),
            whatsNew: "Version \(version): Initial release with demo glucose monitoring and simulated AID features."
        )
    }
    
    // MARK: - Follower App
    
    private func generateFollowerMetadata(version: String) -> AppStoreMetadata {
        AppStoreMetadata(
            appType: .follower,
            name: "T1Pal Hub",
            subtitle: "Remote Glucose Monitoring",
            description: """
            T1Pal Hub lets caregivers and family members remotely monitor glucose levels from Nightscout or Dexcom Share.
            
            KEY FEATURES:
            • Real-time glucose display from Nightscout
            • Dexcom Share integration
            • Trend arrows and delta values
            • Customizable alert thresholds
            • Widget support for quick glances
            • Apple Watch complications
            
            REMOTE MONITORING:
            Follow your loved one's glucose levels in real-time. Set up notifications for high and low glucose events to stay informed.
            
            NIGHTSCOUT INTEGRATION:
            Connect to any Nightscout instance to view glucose data, treatments, and device status.
            
            REQUIREMENTS:
            • Active Nightscout site OR
            • Dexcom Share enabled account
            • Internet connection
            
            This app is for MONITORING ONLY and does not control any medical devices.
            """,
            keywords: ["diabetes", "glucose", "follower", "Nightscout", "CGM", "Dexcom", "caregiver", "T1D", "monitor"],
            primaryCategory: .health,
            secondaryCategory: nil,
            ageRating: .fourPlus,
            ageRatingJustification: "App displays health data for monitoring purposes. No objectionable content.",
            privacyDeclarations: [
                PrivacyDeclaration(dataType: .healthData, usage: .appFunctionality, linkedToUser: true, usedForTracking: false),
                PrivacyDeclaration(dataType: .diagnostics, usage: .analytics, linkedToUser: false, usedForTracking: false)
            ],
            privacyPolicyURL: "https://t1pal.com/privacy",
            supportURL: "https://t1pal.com/support",
            marketingURL: "https://t1pal.com",
            screenshotSpecs: followerScreenshots(),
            whatsNew: "Version \(version): Remote glucose monitoring with Nightscout and Dexcom Share support."
        )
    }
    
    // MARK: - CGM App
    
    private func generateCGMMetadata(version: String) -> AppStoreMetadata {
        AppStoreMetadata(
            appType: .cgm,
            name: "T1Pal CGM",
            subtitle: "Continuous Glucose Monitor",
            description: """
            T1Pal CGM connects directly to your continuous glucose monitor to display real-time glucose readings.
            
            SUPPORTED DEVICES:
            • Dexcom G6 and G7
            • Freestyle Libre 2 and 3
            • Nightscout remote data
            
            KEY FEATURES:
            • Real-time glucose with trend arrows
            • HealthKit integration
            • Customizable high/low alerts
            • Critical alerts for urgent events
            • Widget and Watch complications
            • Data export to Nightscout
            
            HEALTH DATA:
            Your glucose data is stored locally and can optionally sync to HealthKit or Nightscout. You control your data.
            
            REQUIREMENTS:
            • Compatible CGM sensor
            • iPhone with Bluetooth
            • iOS 16.0 or later
            
            NOTE: This app displays glucose data but does not make treatment decisions. Always follow your healthcare provider's guidance.
            """,
            keywords: ["CGM", "glucose", "Dexcom", "Libre", "diabetes", "T1D", "monitor", "health", "BLE"],
            primaryCategory: .medical,
            secondaryCategory: .health,
            ageRating: .fourPlus,
            ageRatingJustification: "Medical app for glucose monitoring. Requires parental guidance for minors.",
            privacyDeclarations: [
                PrivacyDeclaration(dataType: .healthData, usage: .appFunctionality, linkedToUser: true, usedForTracking: false),
                PrivacyDeclaration(dataType: .identifiers, usage: .appFunctionality, linkedToUser: true, usedForTracking: false),
                PrivacyDeclaration(dataType: .diagnostics, usage: .analytics, linkedToUser: false, usedForTracking: false)
            ],
            privacyPolicyURL: "https://t1pal.com/privacy",
            supportURL: "https://t1pal.com/support",
            marketingURL: "https://t1pal.com",
            screenshotSpecs: cgmScreenshots(),
            whatsNew: "Version \(version): Direct CGM connectivity with Dexcom and Libre support."
        )
    }
    
    // MARK: - AID App
    
    private func generateAIDMetadata(version: String) -> AppStoreMetadata {
        AppStoreMetadata(
            appType: .aid,
            name: "T1Pal AID",
            subtitle: "Automated Insulin Delivery",
            description: """
            T1Pal AID provides automated insulin delivery by connecting your CGM and insulin pump for closed-loop diabetes management.
            
            ⚠️ TESTFLIGHT ONLY - NOT FOR APP STORE ⚠️
            
            This app is distributed via TestFlight for qualified users who have completed required training.
            
            AUTOMATED FEATURES:
            • Closed-loop glucose control
            • Predictive glucose algorithms
            • Automatic basal adjustments
            • SMB and UAM support
            • Safety overrides and limits
            
            SUPPORTED DEVICES:
            • Dexcom G6/G7, Libre 2/3
            • Omnipod DASH
            • Medtronic (via RileyLink)
            
            SAFETY:
            • Multiple safety interlocks
            • Suspend on low predictions
            • Maximum delivery limits
            • Complete audit logging
            
            REQUIREMENTS:
            • Completed training attestation
            • Healthcare provider authorization
            • Compatible CGM and pump
            • iOS 16.0 or later
            
            DISCLAIMER: This is investigational software. Use at your own risk. Always have backup insulin delivery method available.
            """,
            keywords: ["AID", "Loop", "insulin", "pump", "diabetes", "T1D", "closed-loop", "algorithm", "Omnipod"],
            primaryCategory: .medical,
            secondaryCategory: .health,
            ageRating: .seventeenPlus,
            ageRatingJustification: "Medical device software for automated insulin delivery. Requires training and adult supervision. Misuse could result in serious harm.",
            privacyDeclarations: [
                PrivacyDeclaration(dataType: .healthData, usage: .appFunctionality, linkedToUser: true, usedForTracking: false),
                PrivacyDeclaration(dataType: .identifiers, usage: .appFunctionality, linkedToUser: true, usedForTracking: false),
                PrivacyDeclaration(dataType: .usageData, usage: .appFunctionality, linkedToUser: true, usedForTracking: false),
                PrivacyDeclaration(dataType: .diagnostics, usage: .analytics, linkedToUser: false, usedForTracking: false)
            ],
            privacyPolicyURL: "https://t1pal.com/privacy",
            supportURL: "https://t1pal.com/support",
            marketingURL: "https://t1pal.com",
            screenshotSpecs: aidScreenshots(),
            whatsNew: "Version \(version): Automated insulin delivery with Omnipod DASH support."
        )
    }
    
    // MARK: - Screenshot Specs
    
    private func demoScreenshots() -> [ScreenshotSpec] {
        [
            ScreenshotSpec(id: "demo-1", screenName: "Main Dashboard", description: "Simulated glucose display with trend", order: 1, stateDescription: "Glucose: 120 mg/dL, trend: flat"),
            ScreenshotSpec(id: "demo-2", screenName: "Glucose Graph", description: "24-hour glucose history", order: 2, stateDescription: "Normal day pattern"),
            ScreenshotSpec(id: "demo-3", screenName: "Pump Controls", description: "Demo pump interface", order: 3, stateDescription: "Basal running"),
            ScreenshotSpec(id: "demo-4", screenName: "Algorithm View", description: "AID predictions", order: 4, stateDescription: "Predictions shown"),
            ScreenshotSpec(id: "demo-5", screenName: "Settings", description: "Demo settings", order: 5, stateDescription: "Default settings")
        ]
    }
    
    private func followerScreenshots() -> [ScreenshotSpec] {
        [
            ScreenshotSpec(id: "follow-1", screenName: "Live Glucose", description: "Real-time glucose from Nightscout", order: 1, stateDescription: "Connected, glucose: 110 mg/dL"),
            ScreenshotSpec(id: "follow-2", screenName: "Trend Graph", description: "Glucose history with predictions", order: 2, stateDescription: "3-hour view"),
            ScreenshotSpec(id: "follow-3", screenName: "Alerts", description: "Customizable alert settings", order: 3, stateDescription: "Alert config screen"),
            ScreenshotSpec(id: "follow-4", screenName: "Widget", description: "Home screen widget", order: 4, stateDescription: "Medium widget"),
            ScreenshotSpec(id: "follow-5", screenName: "Setup", description: "Nightscout connection", order: 5, stateDescription: "URL entry")
        ]
    }
    
    private func cgmScreenshots() -> [ScreenshotSpec] {
        [
            ScreenshotSpec(id: "cgm-1", screenName: "Glucose Display", description: "Live CGM reading", order: 1, stateDescription: "Dexcom connected, 105 mg/dL"),
            ScreenshotSpec(id: "cgm-2", screenName: "Sensor Status", description: "CGM sensor details", order: 2, stateDescription: "Sensor: 5 days remaining"),
            ScreenshotSpec(id: "cgm-3", screenName: "Graph View", description: "Glucose trends", order: 3, stateDescription: "24-hour graph"),
            ScreenshotSpec(id: "cgm-4", screenName: "Alerts", description: "Critical alert settings", order: 4, stateDescription: "Alert configuration"),
            ScreenshotSpec(id: "cgm-5", screenName: "HealthKit", description: "HealthKit integration", order: 5, stateDescription: "Sync enabled"),
            ScreenshotSpec(id: "cgm-6", screenName: "Device Pairing", description: "CGM connection", order: 6, stateDescription: "Scanning for devices")
        ]
    }
    
    private func aidScreenshots() -> [ScreenshotSpec] {
        [
            ScreenshotSpec(id: "aid-1", screenName: "Loop Status", description: "Closed-loop dashboard", order: 1, stateDescription: "Looping, glucose: 115 mg/dL"),
            ScreenshotSpec(id: "aid-2", screenName: "Predictions", description: "Algorithm predictions", order: 2, stateDescription: "4-hour prediction curve"),
            ScreenshotSpec(id: "aid-3", screenName: "Pump Status", description: "Insulin delivery", order: 3, stateDescription: "Omnipod active, 150U remaining"),
            ScreenshotSpec(id: "aid-4", screenName: "Bolus", description: "Bolus calculator", order: 4, stateDescription: "Meal bolus entry"),
            ScreenshotSpec(id: "aid-5", screenName: "Safety", description: "Safety controls", order: 5, stateDescription: "Override options"),
            ScreenshotSpec(id: "aid-6", screenName: "Settings", description: "Algorithm settings", order: 6, stateDescription: "ISF, CR, targets"),
            ScreenshotSpec(id: "aid-7", screenName: "History", description: "Delivery history", order: 7, stateDescription: "24-hour log")
        ]
    }
}
