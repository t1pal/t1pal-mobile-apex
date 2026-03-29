// SPDX-License-Identifier: MIT
// ReviewNotesTests.swift
// T1PalCoreTests
//
// Tests for Apple App Store review notes generator.
// Trace: APP-ONBOARD-006

import Testing
import Foundation
@testable import T1PalCore

@Suite("Review Notes Generator")
struct ReviewNotesGeneratorTests {
    
    // MARK: - App Type Tests
    
    @Test("Demo app has correct properties")
    func demoAppProperties() {
        let appType = T1PalAppType.demo
        #expect(appType.displayName == "T1Pal Demo")
        #expect(appType.riskLevel == .none)
        #expect(appType.distributionPath == .testFlightOnly)
    }
    
    @Test("Follower app has correct properties")
    func followerAppProperties() {
        let appType = T1PalAppType.follower
        #expect(appType.displayName == "T1Pal Follower")
        #expect(appType.riskLevel == .low)
        #expect(appType.distributionPath == .appStore)
    }
    
    @Test("CGM app has correct properties")
    func cgmAppProperties() {
        let appType = T1PalAppType.cgm
        #expect(appType.displayName == "T1Pal CGM")
        #expect(appType.riskLevel == .medium)
        #expect(appType.distributionPath == .appStore)
    }
    
    @Test("AID app has correct properties")
    func aidAppProperties() {
        let appType = T1PalAppType.aid
        #expect(appType.displayName == "T1Pal AID")
        #expect(appType.riskLevel == .high)
        #expect(appType.distributionPath == .testFlightOnly)
    }
    
    // MARK: - Generator Tests
    
    @Test("Generator creates notes for demo app")
    func generatorCreatesNotesForDemo() {
        let generator = ReviewNotesGenerator(
            appType: .demo,
            version: "1.0.0",
            buildNumber: "42"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("T1Pal Demo"))
        #expect(notes.contains("1.0.0"))
        #expect(notes.contains("simulation"))
        #expect(notes.contains("Debug"))
    }
    
    @Test("Generator creates notes for follower app")
    func generatorCreatesNotesForFollower() {
        let generator = ReviewNotesGenerator(
            appType: .follower,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("T1Pal Follower"))
        #expect(notes.contains("Nightscout"))
        #expect(notes.contains("cloud"))
        #expect(notes.contains("version number 7 times"))
    }
    
    @Test("Generator creates notes for CGM app")
    func generatorCreatesNotesForCGM() {
        let generator = ReviewNotesGenerator(
            appType: .cgm,
            version: "2.0.0",
            buildNumber: "100"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("T1Pal CGM"))
        #expect(notes.contains("FDA-cleared"))
        #expect(notes.contains("BLE Central"))
        #expect(notes.contains("Background BLE"))
        #expect(notes.contains("Medical Device"))
    }
    
    @Test("Generator creates notes for AID app")
    func generatorCreatesNotesForAID() {
        let generator = ReviewNotesGenerator(
            appType: .aid,
            version: "0.1.0",
            buildNumber: "1"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("T1Pal AID"))
        #expect(notes.contains("NOT FDA-cleared"))
        #expect(notes.contains("Colocated App"))
        #expect(notes.contains("Suspend Delivery"))
        #expect(notes.contains("Safety"))
        #expect(notes.contains("oref"))
    }
    
    // MARK: - Section Tests
    
    @Test("Notes include version and build number")
    func notesIncludeVersion() {
        let generator = ReviewNotesGenerator(
            appType: .demo,
            version: "3.2.1",
            buildNumber: "789"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("3.2.1"))
        #expect(notes.contains("789"))
    }
    
    @Test("Notes include capability table")
    func notesIncludeCapabilityTable() {
        let generator = ReviewNotesGenerator(
            appType: .cgm,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("| Capability |"))
        #expect(notes.contains("| Required |"))
        #expect(notes.contains("| Purpose |"))
    }
    
    @Test("Notes include testing instructions")
    func notesIncludeTestingInstructions() {
        let generator = ReviewNotesGenerator(
            appType: .cgm,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("Compatibility Testing"))
        #expect(notes.contains("Quick Check"))
        #expect(notes.contains("Full Test"))
        #expect(notes.contains("Export Diagnostics"))
    }
    
    @Test("AID notes include safety controls")
    func aidNotesIncludeSafetyControls() {
        let generator = ReviewNotesGenerator(
            appType: .aid,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("Suspend Delivery"))
        #expect(notes.contains("Resume Delivery"))
        #expect(notes.contains("Cancel Bolus"))
        #expect(notes.contains("Override Management"))
    }
    
    @Test("AID notes include user acknowledgments")
    func aidNotesIncludeAcknowledgments() {
        let generator = ReviewNotesGenerator(
            appType: .aid,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let notes = generator.generateReviewNotes()
        
        #expect(notes.contains("not FDA-cleared"))
        #expect(notes.contains("responsibility"))
        #expect(notes.contains("healthcare provider"))
    }
    
    // MARK: - JSON Export Tests
    
    @Test("JSON export creates valid data")
    func jsonExportCreatesValidData() throws {
        let generator = ReviewNotesGenerator(
            appType: .cgm,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let data = try generator.exportAsJSON()
        #expect(data.count > 0)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ReviewNotesData.self, from: data)
        #expect(decoded.appType == .cgm)
        #expect(decoded.version == "1.0.0")
        #expect(decoded.buildNumber == "1")
        #expect(decoded.riskLevel == .medium)
    }
    
    @Test("JSON export includes required capabilities")
    func jsonExportIncludesCapabilities() throws {
        let generator = ReviewNotesGenerator(
            appType: .aid,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let data = try generator.exportAsJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ReviewNotesData.self, from: data)
        
        #expect(decoded.requiredCapabilities.contains("BLE Central"))
        #expect(decoded.requiredCapabilities.contains("Background BLE"))
        #expect(decoded.requiredCapabilities.contains("Notifications"))
    }
    
    @Test("JSON export includes test access path")
    func jsonExportIncludesTestPath() throws {
        let generator = ReviewNotesGenerator(
            appType: .follower,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let data = try generator.exportAsJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ReviewNotesData.self, from: data)
        
        #expect(decoded.testAccessPath.contains("Settings"))
        #expect(decoded.testAccessPath.contains("Tap version 7x"))
    }
    
    // MARK: - Edge Cases
    
    @Test("Demo app has no required capabilities")
    func demoAppNoRequiredCapabilities() throws {
        let generator = ReviewNotesGenerator(
            appType: .demo,
            version: "1.0.0",
            buildNumber: "1"
        )
        
        let data = try generator.exportAsJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ReviewNotesData.self, from: data)
        
        #expect(decoded.requiredCapabilities.isEmpty)
    }
    
    @Test("All app types generate valid notes")
    func allAppTypesGenerateValidNotes() {
        for appType in [T1PalAppType.demo, .follower, .cgm, .aid] {
            let generator = ReviewNotesGenerator(
                appType: appType,
                version: "1.0.0",
                buildNumber: "1"
            )
            
            let notes = generator.generateReviewNotes()
            #expect(notes.contains(appType.displayName))
            #expect(notes.contains("Compatibility Testing"))
            #expect(notes.contains("Intended Use"))
        }
    }
}

@Suite("Risk Level")
struct RiskLevelTests {
    
    @Test("Risk levels are ordered correctly")
    func riskLevelsOrdered() {
        #expect(AppRiskLevel.none.rawValue == "None")
        #expect(AppRiskLevel.low.rawValue == "Low")
        #expect(AppRiskLevel.medium.rawValue == "Medium")
        #expect(AppRiskLevel.high.rawValue == "High")
    }
}

@Suite("Distribution Path")
struct DistributionPathTests {
    
    @Test("Distribution paths have correct raw values")
    func distributionPathsCorrect() {
        #expect(DistributionPath.appStore.rawValue == "App Store")
        #expect(DistributionPath.testFlightOnly.rawValue == "TestFlight Only")
    }
}
