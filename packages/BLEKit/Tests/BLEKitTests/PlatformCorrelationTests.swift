// PlatformCorrelationTests.swift - Tests for platform version correlation
// Part of BLEKit
// Trace: EVID-004

import Foundation
import Testing
@testable import BLEKit

// MARK: - Platform Version Tests

@Suite("Platform Version")
struct PlatformVersionTests {
    @Test("Parse iOS version")
    func parseIOSVersion() {
        let version = PlatformVersion(string: "17.2.1")
        #expect(version != nil)
        #expect(version?.major == 17)
        #expect(version?.minor == 2)
        #expect(version?.patch == 1)
    }
    
    @Test("Parse version with build")
    func parseVersionWithBuild() {
        let version = PlatformVersion(string: "17.2.1 (21C52)")
        #expect(version != nil)
        #expect(version?.major == 17)
        #expect(version?.minor == 2)
        #expect(version?.patch == 1)
        #expect(version?.build == "21C52")
    }
    
    @Test("Parse version with iOS prefix")
    func parseVersionWithPrefix() {
        let version = PlatformVersion(string: "iOS 16.4")
        #expect(version != nil)
        #expect(version?.major == 16)
        #expect(version?.minor == 4)
    }
    
    @Test("Parse minimal version")
    func parseMinimalVersion() {
        let version = PlatformVersion(string: "15.0")
        #expect(version != nil)
        #expect(version?.major == 15)
        #expect(version?.minor == 0)
        #expect(version?.patch == 0)
    }
    
    @Test("Invalid version returns nil")
    func invalidVersion() {
        #expect(PlatformVersion(string: "invalid") == nil)
        #expect(PlatformVersion(string: "17") == nil)
        #expect(PlatformVersion(string: "") == nil)
    }
    
    @Test("Version comparison")
    func versionComparison() {
        let v16 = PlatformVersion(major: 16, minor: 4, patch: 1)
        let v17 = PlatformVersion(major: 17, minor: 0, patch: 0)
        let v17_2 = PlatformVersion(major: 17, minor: 2, patch: 0)
        
        #expect(v16 < v17)
        #expect(v17 < v17_2)
        #expect(v17_2 > v16)
    }
    
    @Test("Major version string")
    func majorVersionString() {
        let version = PlatformVersion(major: 17, minor: 2, patch: 1)
        #expect(version.majorVersion == "17.x")
    }
    
    @Test("Major minor version string")
    func majorMinorVersionString() {
        let version = PlatformVersion(major: 17, minor: 2, patch: 1)
        #expect(version.majorMinorVersion == "17.2")
    }
    
    @Test("Version is Codable")
    func versionCodable() throws {
        let version = PlatformVersion(major: 17, minor: 2, patch: 1, build: "21C52")
        let data = try JSONEncoder().encode(version)
        let decoded = try JSONDecoder().decode(PlatformVersion.self, from: data)
        #expect(decoded == version)
    }
}

// MARK: - Platform Type Tests

@Suite("Platform Type")
struct PlatformTypeTests {
    @Test("Detect iOS")
    func detectIOS() {
        #expect(PlatformType.detect(from: "iOS 17.2") == .iOS)
        #expect(PlatformType.detect(from: "iPhone") == .iOS)
        #expect(PlatformType.detect(from: "iPad") == .iOS)
    }
    
    @Test("Detect macOS")
    func detectMacOS() {
        #expect(PlatformType.detect(from: "macOS 14.2") == .macOS)
        #expect(PlatformType.detect(from: "Mac OS X") == .macOS)
        #expect(PlatformType.detect(from: "OSX 10.15") == .macOS)
    }
    
    @Test("Detect watchOS")
    func detectWatchOS() {
        #expect(PlatformType.detect(from: "watchOS 10") == .watchOS)
        #expect(PlatformType.detect(from: "Watch OS 9") == .watchOS)
    }
    
    @Test("Detect Linux")
    func detectLinux() {
        #expect(PlatformType.detect(from: "Linux 5.15") == .linux)
        #expect(PlatformType.detect(from: "Ubuntu 22.04") == .linux)
    }
    
    @Test("Unknown platform")
    func unknownPlatform() {
        #expect(PlatformType.detect(from: "SomeOS") == .unknown)
    }
    
    @Test("Minimum BLE version")
    func minimumBLEVersion() {
        #expect(PlatformType.iOS.minimumBLEVersion.major == 13)
        #expect(PlatformType.macOS.minimumBLEVersion.major == 10)
        #expect(PlatformType.watchOS.minimumBLEVersion.major == 6)
    }
}

// MARK: - Platform Statistics Tests

@Suite("Platform Statistics")
struct PlatformStatisticsTests {
    @Test("Success rate calculation")
    func successRateCalculation() {
        let stats = PlatformStatistics(
            platform: .iOS,
            version: PlatformVersion(major: 17, minor: 2),
            reportCount: 100,
            successCount: 85,
            failureCount: 15,
            avgConnectionTime: 2.5
        )
        
        #expect(stats.successRate == 0.85)
    }
    
    @Test("Zero reports has zero success rate")
    func zeroReports() {
        let stats = PlatformStatistics(
            platform: .iOS,
            version: PlatformVersion(major: 17, minor: 0),
            reportCount: 0,
            successCount: 0,
            failureCount: 0,
            avgConnectionTime: 0.0
        )
        
        #expect(stats.successRate == 0.0)
    }
    
    @Test("Statistics are Equatable")
    func statisticsEquatable() {
        let stats1 = PlatformStatistics(
            platform: .iOS,
            version: PlatformVersion(major: 17, minor: 2),
            reportCount: 10,
            successCount: 8,
            failureCount: 2,
            avgConnectionTime: 1.5
        )
        
        let stats2 = PlatformStatistics(
            platform: .iOS,
            version: PlatformVersion(major: 17, minor: 2),
            reportCount: 10,
            successCount: 8,
            failureCount: 2,
            avgConnectionTime: 1.5
        )
        
        #expect(stats1 == stats2)
    }
}

// MARK: - Platform Comparison Tests

@Suite("Platform Comparison")
struct PlatformComparisonTests {
    @Test("Detect regression")
    func detectRegression() {
        let comparison = PlatformComparison(
            fromVersion: PlatformVersion(major: 17, minor: 0),
            toVersion: PlatformVersion(major: 17, minor: 1),
            successRateDelta: -0.10,
            connectionTimeDelta: 0.5
        )
        
        #expect(comparison.isRegression)
        #expect(!comparison.isImprovement)
    }
    
    @Test("Detect improvement")
    func detectImprovement() {
        let comparison = PlatformComparison(
            fromVersion: PlatformVersion(major: 16, minor: 4),
            toVersion: PlatformVersion(major: 17, minor: 0),
            successRateDelta: 0.15,
            connectionTimeDelta: -0.3
        )
        
        #expect(comparison.isImprovement)
        #expect(!comparison.isRegression)
    }
    
    @Test("Comparison is Equatable")
    func comparisonEquatable() {
        let c1 = PlatformComparison(
            fromVersion: PlatformVersion(major: 17, minor: 0),
            toVersion: PlatformVersion(major: 17, minor: 1),
            successRateDelta: 0.05,
            connectionTimeDelta: -0.1
        )
        
        let c2 = PlatformComparison(
            fromVersion: PlatformVersion(major: 17, minor: 0),
            toVersion: PlatformVersion(major: 17, minor: 1),
            successRateDelta: 0.05,
            connectionTimeDelta: -0.1
        )
        
        #expect(c1 == c2)
    }
}

// MARK: - Platform Report Tests

@Suite("Platform Report")
struct PlatformReportTests {
    @Test("Create success report")
    func createSuccessReport() {
        let report = PlatformReport(
            platform: .iOS,
            platformVersion: PlatformVersion(major: 17, minor: 2),
            deviceType: .dexcomG7,
            success: true,
            connectionTime: 2.5
        )
        
        #expect(report.success)
        #expect(report.connectionTime == 2.5)
        #expect(report.failureReason == nil)
    }
    
    @Test("Create failure report")
    func createFailureReport() {
        let report = PlatformReport(
            platform: .iOS,
            platformVersion: PlatformVersion(major: 16, minor: 4),
            deviceType: .libre2,
            success: false,
            failureReason: "Connection timeout"
        )
        
        #expect(!report.success)
        #expect(report.failureReason == "Connection timeout")
    }
    
    @Test("Report is Codable")
    func reportCodable() throws {
        let report = PlatformReport(
            platform: .iOS,
            platformVersion: PlatformVersion(major: 17, minor: 2),
            deviceType: .dexcomG7,
            success: true,
            connectionTime: 2.5,
            deviceModel: "iPhone 15 Pro"
        )
        
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PlatformReport.self, from: data)
        #expect(decoded == report)
    }
}

// MARK: - Platform Correlation Analyzer Tests

@Suite("Platform Correlation Analyzer")
struct PlatformCorrelationAnalyzerTests {
    @Test("Empty reports returns empty result")
    func emptyReports() {
        let analyzer = PlatformCorrelationAnalyzer()
        let result = analyzer.analyze(reports: [])
        
        #expect(result.platformStats.isEmpty)
        #expect(result.bestVersion == nil)
        #expect(result.worstVersion == nil)
    }
    
    @Test("Analyze single version")
    func analyzeSingleVersion() {
        let analyzer = PlatformCorrelationAnalyzer(minimumReportsThreshold: 1)
        let reports = [
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 17, minor: 2),
                deviceType: .dexcomG7,
                success: true,
                connectionTime: 2.0
            ),
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 17, minor: 2),
                deviceType: .dexcomG7,
                success: true,
                connectionTime: 3.0
            )
        ]
        
        let result = analyzer.analyze(reports: reports)
        
        #expect(result.platformStats.count == 1)
        #expect(result.platformStats[0].successRate == 1.0)
        #expect(result.platformStats[0].avgConnectionTime == 2.5)
    }
    
    @Test("Analyze multiple versions")
    func analyzeMultipleVersions() {
        let analyzer = PlatformCorrelationAnalyzer(minimumReportsThreshold: 2)
        let reports = [
            // iOS 16.4 - 50% success
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 16, minor: 4),
                deviceType: .dexcomG7,
                success: true
            ),
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 16, minor: 4),
                deviceType: .dexcomG7,
                success: false,
                failureReason: "Timeout"
            ),
            // iOS 17.0 - 100% success
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 17, minor: 0),
                deviceType: .dexcomG7,
                success: true
            ),
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 17, minor: 0),
                deviceType: .dexcomG7,
                success: true
            )
        ]
        
        let result = analyzer.analyze(reports: reports)
        
        #expect(result.platformStats.count == 2)
        #expect(result.bestVersion == PlatformVersion(major: 17, minor: 0))
        #expect(result.worstVersion == PlatformVersion(major: 16, minor: 4))
    }
    
    @Test("Generate version comparisons")
    func generateComparisons() {
        let analyzer = PlatformCorrelationAnalyzer(minimumReportsThreshold: 1)
        let reports = [
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 16, minor: 4),
                deviceType: .dexcomG7,
                success: false,
                failureReason: "Timeout"
            ),
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 17, minor: 0),
                deviceType: .dexcomG7,
                success: true
            )
        ]
        
        let result = analyzer.analyze(reports: reports)
        
        #expect(result.comparisons.count == 1)
        #expect(result.comparisons[0].isImprovement)
    }
    
    @Test("Reliable versions filtered")
    func reliableVersionsFiltered() {
        let analyzer = PlatformCorrelationAnalyzer(minimumReportsThreshold: 5)
        let reports = [
            // iOS 16.4 - only 2 reports (not reliable)
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 16, minor: 4),
                deviceType: .dexcomG7,
                success: true
            ),
            PlatformReport(
                platform: .iOS,
                platformVersion: PlatformVersion(major: 16, minor: 4),
                deviceType: .dexcomG7,
                success: true
            ),
            // iOS 17.0 - 5 reports (reliable)
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 0), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 0), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 0), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 0), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 0), deviceType: .dexcomG7, success: true)
        ]
        
        let result = analyzer.analyze(reports: reports)
        
        #expect(result.reliableVersions.count == 1)
        #expect(result.reliableVersions[0] == PlatformVersion(major: 17, minor: 0))
    }
    
    @Test("Analyze by major version")
    func analyzeByMajorVersion() {
        let analyzer = PlatformCorrelationAnalyzer()
        let reports = [
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 0), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 1), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 2), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 16, minor: 4), deviceType: .dexcomG7, success: false)
        ]
        
        let majorStats = analyzer.analyzeByMajorVersion(reports: reports)
        
        #expect(majorStats.count == 2)
        #expect(majorStats["iOS 17"]?.successRate == 1.0)
        #expect(majorStats["iOS 16"]?.successRate == 0.0)
    }
}

// MARK: - Platform Compatibility Matrix Tests

@Suite("Platform Compatibility Matrix")
struct PlatformCompatibilityMatrixTests {
    @Test("Build matrix from reports")
    func buildMatrixFromReports() {
        let reports = [
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 2), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 2), deviceType: .dexcomG7, success: true),
            PlatformReport(platform: .iOS, platformVersion: PlatformVersion(major: 17, minor: 2), deviceType: .libre2, success: false)
        ]
        
        let matrix = PlatformCompatibilityMatrix.build(from: reports)
        
        #expect(matrix.entries.count == 2)
        #expect(matrix.entries[.dexcomG7]?["17.2"] != nil)
        #expect(matrix.entries[.libre2]?["17.2"] != nil)
    }
    
    @Test("Overall score calculation")
    func overallScoreCalculation() {
        let entries: [DeviceType: [String: CompatibilityStatus]] = [
            .dexcomG7: [
                "17.2": .fullSupport(successRate: 1.0, reportCount: 10)
            ],
            .libre2: [
                "17.2": .partialSupport(successRate: 0.8, reportCount: 10)
            ]
        ]
        
        let matrix = PlatformCompatibilityMatrix(entries: entries)
        
        #expect(matrix.overallScore == 0.9)
    }
    
    @Test("Get best platform for device")
    func bestPlatformForDevice() {
        let entries: [DeviceType: [String: CompatibilityStatus]] = [
            .dexcomG7: [
                "16.4": .partialSupport(successRate: 0.7, reportCount: 10),
                "17.0": .fullSupport(successRate: 0.95, reportCount: 10),
                "17.2": .fullSupport(successRate: 0.98, reportCount: 10)
            ]
        ]
        
        let matrix = PlatformCompatibilityMatrix(entries: entries)
        
        #expect(matrix.bestPlatform(for: .dexcomG7) == "17.2")
    }
    
    @Test("Identify problematic combinations")
    func identifyProblematicCombinations() {
        let entries: [DeviceType: [String: CompatibilityStatus]] = [
            .dexcomG7: [
                "17.2": .fullSupport(successRate: 0.98, reportCount: 10)
            ],
            .libre2: [
                "16.4": .knownIssues(successRate: 0.5, reportCount: 10),
                "17.2": .unsupported(reportCount: 5)
            ]
        ]
        
        let matrix = PlatformCompatibilityMatrix(entries: entries)
        let problems = matrix.problematicCombinations()
        
        #expect(problems.count == 2)
    }
}

// MARK: - Version Range Tests

@Suite("Version Range")
struct VersionRangeTests {
    @Test("Contains version")
    func containsVersion() {
        let range = VersionRange(
            minimum: PlatformVersion(major: 16, minor: 0),
            maximum: PlatformVersion(major: 17, minor: 0)
        )
        
        #expect(range.contains(PlatformVersion(major: 16, minor: 4)))
        #expect(range.contains(PlatformVersion(major: 17, minor: 0)))
        #expect(!range.contains(PlatformVersion(major: 15, minor: 0)))
        #expect(!range.contains(PlatformVersion(major: 17, minor: 1)))
    }
    
    @Test("Open-ended range")
    func openEndedRange() {
        let range = VersionRange.from(PlatformVersion(major: 17, minor: 0))
        
        #expect(range.contains(PlatformVersion(major: 17, minor: 0)))
        #expect(range.contains(PlatformVersion(major: 18, minor: 0)))
        #expect(!range.contains(PlatformVersion(major: 16, minor: 4)))
    }
    
    @Test("Single version range")
    func singleVersionRange() {
        let range = VersionRange.single(PlatformVersion(major: 17, minor: 2))
        
        #expect(range.contains(PlatformVersion(major: 17, minor: 2)))
        #expect(!range.contains(PlatformVersion(major: 17, minor: 1)))
        #expect(!range.contains(PlatformVersion(major: 17, minor: 3)))
    }
}

// MARK: - Correlation Result Tests

@Suite("Platform Correlation Result")
struct PlatformCorrelationResultTests {
    @Test("Empty result")
    func emptyResult() {
        let result = PlatformCorrelationResult.empty
        
        #expect(result.platformStats.isEmpty)
        #expect(result.bestVersion == nil)
        #expect(result.worstVersion == nil)
    }
    
    @Test("Result is Codable")
    func resultCodable() throws {
        let result = PlatformCorrelationResult(
            platformStats: [
                PlatformStatistics(
                    platform: .iOS,
                    version: PlatformVersion(major: 17, minor: 2),
                    reportCount: 10,
                    successCount: 8,
                    failureCount: 2,
                    avgConnectionTime: 2.5
                )
            ],
            bestVersion: PlatformVersion(major: 17, minor: 2),
            worstVersion: nil,
            comparisons: [],
            overallTrend: 0.1
        )
        
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(PlatformCorrelationResult.self, from: data)
        #expect(decoded == result)
    }
}

// MARK: - Platform Issue Tests

@Suite("Platform Issue")
struct PlatformIssueTests {
    @Test("Create platform issue")
    func createPlatformIssue() {
        let issue = PlatformIssue(
            platform: .iOS,
            affectedVersions: VersionRange(
                minimum: PlatformVersion(major: 17, minor: 0),
                maximum: PlatformVersion(major: 17, minor: 1)
            ),
            description: "BLE connection drops after 30 seconds",
            severity: .major,
            workaround: "Disable Bluetooth optimization",
            radarId: "FB12345678"
        )
        
        #expect(issue.severity == .major)
        #expect(issue.workaround != nil)
        #expect(issue.radarId == "FB12345678")
    }
}

// MARK: - Compatibility Status Tests

@Suite("Compatibility Status")
struct CompatibilityStatusTests {
    @Test("Score calculation")
    func scoreCalculation() {
        let full = CompatibilityStatus.fullSupport(successRate: 0.98, reportCount: 10)
        let partial = CompatibilityStatus.partialSupport(successRate: 0.75, reportCount: 10)
        let issues = CompatibilityStatus.knownIssues(successRate: 0.4, reportCount: 10)
        let unsupported = CompatibilityStatus.unsupported(reportCount: 5)
        let untested = CompatibilityStatus.untested
        
        #expect(full.score == 0.98)
        #expect(partial.score == 0.75)
        #expect(issues.score == 0.4)
        #expect(unsupported.score == 0.0)
        #expect(untested.score == 0.5)
    }
    
    @Test("Report count")
    func reportCount() {
        let status = CompatibilityStatus.fullSupport(successRate: 0.98, reportCount: 42)
        #expect(status.reportCount == 42)
    }
}

// MARK: - Device Model Detector Tests

@Suite("Device Model Detector")
struct DeviceModelDetectorTests {
    @Test("Detect iPhone 15 Pro")
    func detectIPhone15Pro() {
        let name = DeviceModelDetector.modelName(for: "iPhone16,1")
        #expect(name == "iPhone 15 Pro")
    }
    
    @Test("Unknown iPhone model")
    func unknownIPhoneModel() {
        let name = DeviceModelDetector.modelName(for: "iPhone99,1")
        #expect(name == "iPhone (Unknown Model)")
    }
    
    @Test("Unknown iPad model")
    func unknownIPadModel() {
        let name = DeviceModelDetector.modelName(for: "iPad99,1")
        #expect(name == "iPad (Unknown Model)")
    }
}

// MARK: - Platform Recommendations Tests

@Suite("Platform Recommendations")
struct PlatformRecommendationsTests {
    @Test("Generate regression recommendation")
    func generateRegressionRecommendation() {
        let result = PlatformCorrelationResult(
            platformStats: [],
            bestVersion: nil,
            worstVersion: nil,
            comparisons: [
                PlatformComparison(
                    fromVersion: PlatformVersion(major: 17, minor: 0),
                    toVersion: PlatformVersion(major: 17, minor: 1),
                    successRateDelta: -0.15,
                    connectionTimeDelta: 0.5
                )
            ],
            overallTrend: -0.15
        )
        
        let matrix = PlatformCompatibilityMatrix(entries: [:])
        let recommendations = PlatformRecommendations.generate(from: result, matrix: matrix)
        
        #expect(recommendations.count >= 1)
        #expect(recommendations[0].type == .avoidVersion)
    }
    
    @Test("Recommend best version")
    func recommendBestVersion() {
        let result = PlatformCorrelationResult(
            platformStats: [],
            bestVersion: PlatformVersion(major: 17, minor: 2),
            worstVersion: nil,
            comparisons: [],
            overallTrend: 0.1
        )
        
        let matrix = PlatformCompatibilityMatrix(entries: [:])
        let recommendations = PlatformRecommendations.generate(from: result, matrix: matrix)
        
        let recommendVersions = recommendations.filter { $0.type == .recommendVersion }
        #expect(recommendVersions.count == 1)
        #expect(recommendVersions[0].version == PlatformVersion(major: 17, minor: 2))
    }
}
