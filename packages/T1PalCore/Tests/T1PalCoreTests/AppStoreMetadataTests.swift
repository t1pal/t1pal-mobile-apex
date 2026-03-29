// SPDX-License-Identifier: MIT
// AppStoreMetadataTests.swift
// T1PalCoreTests
//
// Tests for App Store metadata generation
// Trace: APP-RELEASE-001

import Testing
import Foundation
@testable import T1PalCore

// MARK: - Screenshot Device Tests

@Suite("ScreenshotDevice")
struct ScreenshotDeviceTests {
    
    @Test("All devices have valid dimensions")
    func allHaveDimensions() {
        for device in ScreenshotDevice.allCases {
            let dims = device.dimensions
            #expect(dims.width > 0)
            #expect(dims.height > 0)
            #expect(dims.height > dims.width) // Portrait orientation
        }
    }
    
    @Test("Required devices include iPhone 6.7 and 6.5")
    func requiredDevices() {
        #expect(ScreenshotDevice.iPhone6_7.isRequired == true)
        #expect(ScreenshotDevice.iPhone6_5.isRequired == true)
        #expect(ScreenshotDevice.iPhone5_5.isRequired == false)
    }
    
    @Test("iPhone 6.7 has correct dimensions")
    func iPhone67Dimensions() {
        let dims = ScreenshotDevice.iPhone6_7.dimensions
        #expect(dims.width == 1290)
        #expect(dims.height == 2796)
    }
}

// MARK: - Screenshot Spec Tests

@Suite("ScreenshotSpec")
struct ScreenshotSpecTests {
    
    @Test("Spec is identifiable")
    func identifiable() {
        let spec = ScreenshotSpec(
            id: "test-1",
            screenName: "Main Screen",
            description: "Primary view",
            order: 1,
            stateDescription: "Default state"
        )
        
        #expect(spec.id == "test-1")
        #expect(spec.screenName == "Main Screen")
        #expect(spec.order == 1)
    }
    
    @Test("Spec is codable")
    func codable() throws {
        let spec = ScreenshotSpec(
            id: "test-2",
            screenName: "Test",
            description: "Description",
            order: 2,
            stateDescription: "State"
        )
        
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(spec)
        let decoded = try decoder.decode(ScreenshotSpec.self, from: data)
        
        #expect(decoded.id == spec.id)
        #expect(decoded.screenName == spec.screenName)
    }
}

// MARK: - Privacy Declaration Tests

@Suite("PrivacyDeclaration")
struct PrivacyDeclarationTests {
    
    @Test("Declaration has all properties")
    func properties() {
        let declaration = PrivacyDeclaration(
            dataType: .healthData,
            usage: .appFunctionality,
            linkedToUser: true,
            usedForTracking: false
        )
        
        #expect(declaration.dataType == .healthData)
        #expect(declaration.usage == .appFunctionality)
        #expect(declaration.linkedToUser == true)
        #expect(declaration.usedForTracking == false)
    }
    
    @Test("All data types available")
    func allDataTypes() {
        let types = PrivacyDataType.allCases
        #expect(types.count >= 6)
        #expect(types.contains(.healthData))
        #expect(types.contains(.diagnostics))
    }
}

// MARK: - App Store Metadata Tests

@Suite("AppStoreMetadata")
struct AppStoreMetadataTests {
    
    @Test("Metadata validates name length")
    func validateNameLength() {
        let metadata = AppStoreMetadata(
            appType: .demo,
            name: "This App Name Is Way Too Long For App Store Requirements",
            subtitle: "Short",
            description: "Description",
            keywords: ["test"],
            primaryCategory: .health,
            ageRating: .fourPlus,
            ageRatingJustification: "None",
            privacyDeclarations: [],
            privacyPolicyURL: "https://example.com",
            supportURL: "https://example.com",
            screenshotSpecs: [ScreenshotSpec(id: "1", screenName: "Main", description: "Main", order: 1, stateDescription: "Default")],
            whatsNew: "New"
        )
        
        let errors = metadata.validate()
        #expect(errors.contains { $0.contains("name") })
    }
    
    @Test("Metadata validates subtitle length")
    func validateSubtitleLength() {
        let metadata = AppStoreMetadata(
            appType: .demo,
            name: "Short Name",
            subtitle: "This Subtitle Is Also Way Too Long For Requirements",
            description: "Description",
            keywords: ["test"],
            primaryCategory: .health,
            ageRating: .fourPlus,
            ageRatingJustification: "None",
            privacyDeclarations: [],
            privacyPolicyURL: "https://example.com",
            supportURL: "https://example.com",
            screenshotSpecs: [ScreenshotSpec(id: "1", screenName: "Main", description: "Main", order: 1, stateDescription: "Default")],
            whatsNew: "New"
        )
        
        let errors = metadata.validate()
        #expect(errors.contains { $0.contains("Subtitle") })
    }
    
    @Test("Valid metadata passes validation")
    func validMetadataPasses() {
        let factory = AppStoreMetadataFactory()
        let metadata = factory.generate(for: .demo, version: "1.0")
        
        let errors = metadata.validate()
        #expect(errors.isEmpty)
    }
    
    @Test("Keyword string truncates to 100 chars")
    func keywordTruncation() {
        let metadata = AppStoreMetadata(
            appType: .demo,
            name: "Test",
            subtitle: "Test",
            description: "Description",
            keywords: ["diabetes", "glucose", "CGM", "insulin", "pump", "health", "fitness", "medical", "monitor", "tracking", "wellness", "T1D", "T2D", "blood", "sugar"],
            primaryCategory: .health,
            ageRating: .fourPlus,
            ageRatingJustification: "None",
            privacyDeclarations: [],
            privacyPolicyURL: "https://example.com",
            supportURL: "https://example.com",
            screenshotSpecs: [],
            whatsNew: "New"
        )
        
        let keywordString = metadata.keywordString
        #expect(keywordString.count <= 100)
    }
    
    @Test("Export produces valid JSON")
    func exportJSON() throws {
        let factory = AppStoreMetadataFactory()
        let metadata = factory.generate(for: .follower, version: "1.0")
        
        let data = try metadata.exportJSON()
        #expect(data.count > 0)
        
        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data)
        #expect(json is [String: Any])
    }
}

// MARK: - Metadata Factory Tests

@Suite("AppStoreMetadataFactory")
struct AppStoreMetadataFactoryTests {
    
    let factory = AppStoreMetadataFactory()
    
    @Test("Generates Demo metadata")
    func generateDemo() {
        let metadata = factory.generate(for: .demo, version: "1.0.0")
        
        #expect(metadata.appType == .demo)
        #expect(metadata.name == "T1Pal Demo")
        #expect(metadata.primaryCategory == .health)
        #expect(metadata.ageRating == .fourPlus)
        #expect(metadata.screenshotSpecs.count >= 5)
    }
    
    @Test("Generates Follower metadata")
    func generateFollower() {
        let metadata = factory.generate(for: .follower, version: "1.0.0")
        
        #expect(metadata.appType == .follower)
        #expect(metadata.name == "T1Pal Follower")
        #expect(metadata.keywords.contains("Nightscout"))
        #expect(metadata.screenshotSpecs.count >= 5)
    }
    
    @Test("Generates CGM metadata")
    func generateCGM() {
        let metadata = factory.generate(for: .cgm, version: "1.0.0")
        
        #expect(metadata.appType == .cgm)
        #expect(metadata.name == "T1Pal CGM")
        #expect(metadata.primaryCategory == .medical)
        #expect(metadata.privacyDeclarations.contains { $0.dataType == .healthData })
        #expect(metadata.screenshotSpecs.count >= 6)
    }
    
    @Test("Generates AID metadata")
    func generateAID() {
        let metadata = factory.generate(for: .aid, version: "1.0.0")
        
        #expect(metadata.appType == .aid)
        #expect(metadata.name == "T1Pal AID")
        #expect(metadata.ageRating == .seventeenPlus)
        #expect(metadata.primaryCategory == .medical)
        #expect(metadata.screenshotSpecs.count >= 7)
    }
    
    @Test("All app types have valid metadata")
    func allTypesValid() {
        for appType in [T1PalAppType.demo, .follower, .cgm, .aid] {
            let metadata = factory.generate(for: appType, version: "1.0")
            let errors = metadata.validate()
            
            #expect(errors.isEmpty, "Errors for \(appType): \(errors)")
        }
    }
    
    @Test("All apps have privacy policy URL")
    func allHavePrivacyPolicy() {
        for appType in [T1PalAppType.demo, .follower, .cgm, .aid] {
            let metadata = factory.generate(for: appType, version: "1.0")
            
            #expect(!metadata.privacyPolicyURL.isEmpty)
            #expect(metadata.privacyPolicyURL.hasPrefix("https://"))
        }
    }
    
    @Test("All apps have support URL")
    func allHaveSupportURL() {
        for appType in [T1PalAppType.demo, .follower, .cgm, .aid] {
            let metadata = factory.generate(for: appType, version: "1.0")
            
            #expect(!metadata.supportURL.isEmpty)
            #expect(metadata.supportURL.hasPrefix("https://"))
        }
    }
    
    @Test("Keywords under 100 characters")
    func keywordsUnderLimit() {
        for appType in [T1PalAppType.demo, .follower, .cgm, .aid] {
            let metadata = factory.generate(for: appType, version: "1.0")
            
            #expect(metadata.keywordString.count <= 100)
        }
    }
    
    @Test("AID has more privacy declarations than Demo")
    func aidHasMorePrivacy() {
        let demoMeta = factory.generate(for: .demo, version: "1.0")
        let aidMeta = factory.generate(for: .aid, version: "1.0")
        
        #expect(aidMeta.privacyDeclarations.count > demoMeta.privacyDeclarations.count)
    }
    
    @Test("CGM and AID are medical category")
    func medicalCategory() {
        let cgmMeta = factory.generate(for: .cgm, version: "1.0")
        let aidMeta = factory.generate(for: .aid, version: "1.0")
        
        #expect(cgmMeta.primaryCategory == .medical)
        #expect(aidMeta.primaryCategory == .medical)
    }
    
    @Test("Screenshot specs have unique IDs")
    func uniqueScreenshotIds() {
        for appType in [T1PalAppType.demo, .follower, .cgm, .aid] {
            let metadata = factory.generate(for: appType, version: "1.0")
            let ids = metadata.screenshotSpecs.map(\.id)
            let uniqueIds = Set(ids)
            
            #expect(ids.count == uniqueIds.count, "Duplicate IDs in \(appType)")
        }
    }
    
    @Test("Screenshot specs are ordered")
    func screenshotsOrdered() {
        for appType in [T1PalAppType.demo, .follower, .cgm, .aid] {
            let metadata = factory.generate(for: appType, version: "1.0")
            let orders = metadata.screenshotSpecs.map(\.order)
            
            #expect(orders == orders.sorted(), "Screenshots not ordered in \(appType)")
        }
    }
}

// MARK: - Age Rating Tests

@Suite("AgeRating")
struct AgeRatingTests {
    
    @Test("All age ratings are codable")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for rating in [AgeRating.fourPlus, .ninePlus, .twelvePlus, .seventeenPlus] {
            let data = try encoder.encode(rating)
            let decoded = try decoder.decode(AgeRating.self, from: data)
            #expect(decoded == rating)
        }
    }
    
    @Test("Demo has lowest age rating")
    func demoLowestRating() {
        let factory = AppStoreMetadataFactory()
        let metadata = factory.generate(for: .demo, version: "1.0")
        
        #expect(metadata.ageRating == .fourPlus)
    }
    
    @Test("AID has highest age rating")
    func aidHighestRating() {
        let factory = AppStoreMetadataFactory()
        let metadata = factory.generate(for: .aid, version: "1.0")
        
        #expect(metadata.ageRating == .seventeenPlus)
    }
}

// MARK: - App Store Category Tests

@Suite("AppStoreCategory")
struct AppStoreCategoryTests {
    
    @Test("Categories have display values")
    func displayValues() {
        #expect(AppStoreCategory.health.rawValue == "Health & Fitness")
        #expect(AppStoreCategory.medical.rawValue == "Medical")
    }
    
    @Test("Categories are codable")
    func codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        for category in [AppStoreCategory.health, .medical, .utilities, .lifestyle] {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(AppStoreCategory.self, from: data)
            #expect(decoded == category)
        }
    }
}
