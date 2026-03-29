// VersionCorrelationTests.swift - Tests for firmware version correlation
// Part of BLEKit
// Trace: EVID-003

import Foundation
import Testing
@testable import BLEKit

// MARK: - Test Helpers

func makeDeviceReport(
    deviceId: String = "DEV-abc123",
    deviceType: DeviceType = .dexcomG6,
    version: SemanticVersion = SemanticVersion(major: 1, minor: 0, patch: 0),
    isSuccess: Bool = true,
    errorCount: Int = 0,
    sessionDuration: TimeInterval = 120,
    timestamp: Date = Date()
) -> DeviceReport {
    DeviceReport(
        deviceId: deviceId,
        deviceType: deviceType,
        firmwareVersion: version,
        timestamp: timestamp,
        isSuccess: isSuccess,
        errorCount: errorCount,
        sessionDuration: sessionDuration
    )
}

// MARK: - Firmware Version Tests

@Suite("Firmware Version")
struct SemanticVersionTests {
    
    @Test("Parse version string")
    func parseString() {
        let version = SemanticVersion(string: "1.2.3")
        
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 2)
        #expect(version?.patch == 3)
    }
    
    @Test("Parse version with v prefix")
    func parseWithPrefix() {
        let version = SemanticVersion(string: "v2.5.1")
        
        #expect(version != nil)
        #expect(version?.major == 2)
        #expect(version?.minor == 5)
    }
    
    @Test("Parse version with build number")
    func parseWithBuild() {
        let version = SemanticVersion(string: "3.0.1.456")
        
        #expect(version != nil)
        #expect(version?.major == 3)
        #expect(version?.build == 456)
    }
    
    @Test("Parse minimal version")
    func parseMinimal() {
        let version = SemanticVersion(string: "1.0")
        
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 0)
        #expect(version?.patch == 0)
    }
    
    @Test("Invalid version returns nil")
    func invalidVersion() {
        #expect(SemanticVersion(string: "invalid") == nil)
        #expect(SemanticVersion(string: "1") == nil)
        #expect(SemanticVersion(string: "") == nil)
    }
    
    @Test("Version comparison")
    func comparison() {
        let v1 = SemanticVersion(major: 1, minor: 0, patch: 0)
        let v2 = SemanticVersion(major: 1, minor: 1, patch: 0)
        let v3 = SemanticVersion(major: 2, minor: 0, patch: 0)
        
        #expect(v1 < v2)
        #expect(v2 < v3)
        #expect(v1 < v3)
    }
    
    @Test("Version equality")
    func equality() {
        let v1 = SemanticVersion(major: 1, minor: 2, patch: 3)
        let v2 = SemanticVersion(major: 1, minor: 2, patch: 3)
        
        #expect(v1 == v2)
    }
    
    @Test("Version family")
    func family() {
        let version = SemanticVersion(major: 2, minor: 5, patch: 3)
        
        #expect(version.family == "2.5")
    }
    
    @Test("Display string")
    func displayString() {
        let v1 = SemanticVersion(major: 1, minor: 2, patch: 3)
        let v2 = SemanticVersion(major: 1, minor: 2, patch: 3, build: 100)
        
        #expect(v1.displayString == "1.2.3")
        #expect(v2.displayString == "1.2.3 (build 100)")
    }
    
    @Test("Unknown version")
    func unknown() {
        let version = SemanticVersion.unknown
        
        #expect(version.major == 0)
        #expect(version.minor == 0)
    }
    
    @Test("Version is Codable")
    func codable() throws {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3)
        
        let encoded = try JSONEncoder().encode(version)
        let decoded = try JSONDecoder().decode(SemanticVersion.self, from: encoded)
        
        #expect(decoded == version)
    }
}

// MARK: - Device Type Tests

@Suite("Device Type")
struct DeviceTypeTests {
    
    @Test("All device types exist")
    func allTypes() {
        #expect(DeviceType.allCases.count == 8)
    }
    
    @Test("Detect Dexcom G6")
    func detectG6() {
        #expect(DeviceType.detect(from: "Dexcom G6 Transmitter") == .dexcomG6)
        #expect(DeviceType.detect(from: "G6-ABC123") == .dexcomG6)
    }
    
    @Test("Detect Dexcom G7")
    func detectG7() {
        #expect(DeviceType.detect(from: "Dexcom G7") == .dexcomG7)
        #expect(DeviceType.detect(from: "G7-XYZ789") == .dexcomG7)
    }
    
    @Test("Detect Libre")
    func detectLibre() {
        #expect(DeviceType.detect(from: "Libre 2") == .libre2)
        #expect(DeviceType.detect(from: "FreeStyle Libre") == .libre2)
        #expect(DeviceType.detect(from: "Libre 3") == .libre3)
    }
    
    @Test("Detect Omnipod")
    func detectOmnipod() {
        #expect(DeviceType.detect(from: "Omnipod DASH") == .omnipodDash)
    }
    
    @Test("Detect Medtronic")
    func detectMedtronic() {
        #expect(DeviceType.detect(from: "Medtronic 780G") == .medtronic)
        #expect(DeviceType.detect(from: "MiniMed") == .medtronic)
    }
    
    @Test("Unknown device")
    func detectUnknown() {
        #expect(DeviceType.detect(from: "Random Device") == .unknown)
    }
    
    @Test("Display name")
    func displayName() {
        #expect(DeviceType.dexcomG6.displayName == "Dexcom G6")
        #expect(DeviceType.libre2.displayName == "Libre 2")
    }
}

// MARK: - Version Statistics Tests

@Suite("Version Statistics")
struct VersionStatisticsTests {
    
    @Test("Success rate calculation")
    func successRate() {
        let stats = VersionStatistics(
            version: SemanticVersion(major: 1, minor: 0),
            deviceType: .dexcomG6,
            reportCount: 10,
            successCount: 8,
            errorCount: 2,
            averageSessionDuration: 120,
            firstSeen: Date(),
            lastSeen: Date()
        )
        
        #expect(stats.successRate == 0.8)
    }
    
    @Test("Zero reports has zero success rate")
    func zeroReports() {
        let stats = VersionStatistics(
            version: SemanticVersion(major: 1, minor: 0),
            deviceType: .dexcomG6,
            reportCount: 0,
            successCount: 0,
            errorCount: 0,
            averageSessionDuration: 0,
            firstSeen: Date(),
            lastSeen: Date()
        )
        
        #expect(stats.successRate == 0)
    }
    
    @Test("Statistics are Equatable")
    func equatable() {
        let now = Date()
        let stats1 = VersionStatistics(
            version: SemanticVersion(major: 1, minor: 0),
            deviceType: .dexcomG6,
            reportCount: 10,
            successCount: 8,
            errorCount: 2,
            averageSessionDuration: 120,
            firstSeen: now,
            lastSeen: now
        )
        let stats2 = VersionStatistics(
            version: SemanticVersion(major: 1, minor: 0),
            deviceType: .dexcomG6,
            reportCount: 10,
            successCount: 8,
            errorCount: 2,
            averageSessionDuration: 120,
            firstSeen: now,
            lastSeen: now
        )
        
        #expect(stats1 == stats2)
    }
}

// MARK: - Version Comparison Tests

@Suite("Version Comparison")
struct VersionComparisonTests {
    
    @Test("Comparison detects improvement")
    func detectImprovement() {
        let now = Date()
        let older = VersionStatistics(
            version: SemanticVersion(major: 1, minor: 0),
            deviceType: .dexcomG6,
            reportCount: 10,
            successCount: 5,
            errorCount: 5,
            averageSessionDuration: 100,
            firstSeen: now,
            lastSeen: now
        )
        let newer = VersionStatistics(
            version: SemanticVersion(major: 1, minor: 1),
            deviceType: .dexcomG6,
            reportCount: 10,
            successCount: 9,
            errorCount: 1,
            averageSessionDuration: 120,
            firstSeen: now,
            lastSeen: now
        )
        
        let comparison = VersionComparison(older: older, newer: newer)
        
        #expect(comparison.isImprovement == true)
        #expect(comparison.successRateDelta == 0.4)
    }
    
    @Test("Comparison detects regression")
    func detectRegression() {
        let now = Date()
        let older = VersionStatistics(
            version: SemanticVersion(major: 1, minor: 0),
            deviceType: .dexcomG6,
            reportCount: 10,
            successCount: 9,
            errorCount: 1,
            averageSessionDuration: 120,
            firstSeen: now,
            lastSeen: now
        )
        let newer = VersionStatistics(
            version: SemanticVersion(major: 1, minor: 1),
            deviceType: .dexcomG6,
            reportCount: 10,
            successCount: 5,
            errorCount: 5,
            averageSessionDuration: 100,
            firstSeen: now,
            lastSeen: now
        )
        
        let comparison = VersionComparison(older: older, newer: newer)
        
        #expect(comparison.isImprovement == false)
        #expect(comparison.isSignificant == true)
    }
}

// MARK: - Version Correlation Analyzer Tests

@Suite("Version Correlation Analyzer")
struct VersionCorrelationAnalyzerTests {
    
    @Test("Analyze empty reports")
    func analyzeEmpty() {
        let analyzer = VersionCorrelationAnalyzer()
        let result = analyzer.analyze([])
        
        #expect(result == .empty)
    }
    
    @Test("Analyze single version")
    func analyzeSingle() {
        let analyzer = VersionCorrelationAnalyzer()
        let reports = [
            makeDeviceReport(version: SemanticVersion(major: 1, minor: 0), isSuccess: true),
            makeDeviceReport(version: SemanticVersion(major: 1, minor: 0), isSuccess: true),
            makeDeviceReport(version: SemanticVersion(major: 1, minor: 0), isSuccess: false)
        ]
        
        let result = analyzer.analyze(reports)
        
        #expect(result.versionStats.count == 1)
        #expect(result.versionStats.first?.reportCount == 3)
        #expect(result.versionStats.first?.successCount == 2)
    }
    
    @Test("Analyze multiple versions")
    func analyzeMultiple() {
        let analyzer = VersionCorrelationAnalyzer()
        let v1 = SemanticVersion(major: 1, minor: 0)
        let v2 = SemanticVersion(major: 1, minor: 1)
        
        let reports = [
            makeDeviceReport(version: v1, isSuccess: true),
            makeDeviceReport(version: v1, isSuccess: false),
            makeDeviceReport(version: v2, isSuccess: true),
            makeDeviceReport(version: v2, isSuccess: true)
        ]
        
        let result = analyzer.analyze(reports)
        
        #expect(result.versionStats.count == 2)
    }
    
    @Test("Find best version")
    func findBest() {
        let config = VersionCorrelationAnalyzer.Config(minimumReports: 2)
        let analyzer = VersionCorrelationAnalyzer(config: config)
        
        let v1 = SemanticVersion(major: 1, minor: 0)
        let v2 = SemanticVersion(major: 1, minor: 1)
        
        let reports = [
            makeDeviceReport(version: v1, isSuccess: true),
            makeDeviceReport(version: v1, isSuccess: false),
            makeDeviceReport(version: v2, isSuccess: true),
            makeDeviceReport(version: v2, isSuccess: true)
        ]
        
        let result = analyzer.analyze(reports)
        
        #expect(result.bestVersion == v2)
    }
    
    @Test("Find worst version")
    func findWorst() {
        let config = VersionCorrelationAnalyzer.Config(minimumReports: 2)
        let analyzer = VersionCorrelationAnalyzer(config: config)
        
        let v1 = SemanticVersion(major: 1, minor: 0)
        let v2 = SemanticVersion(major: 1, minor: 1)
        
        let reports = [
            makeDeviceReport(version: v1, isSuccess: false),
            makeDeviceReport(version: v1, isSuccess: false),
            makeDeviceReport(version: v2, isSuccess: true),
            makeDeviceReport(version: v2, isSuccess: true)
        ]
        
        let result = analyzer.analyze(reports)
        
        #expect(result.worstVersion == v1)
    }
    
    @Test("Compute comparisons")
    func computeComparisons() {
        let config = VersionCorrelationAnalyzer.Config(minimumReports: 1)
        let analyzer = VersionCorrelationAnalyzer(config: config)
        
        let v1 = SemanticVersion(major: 1, minor: 0)
        let v2 = SemanticVersion(major: 1, minor: 1)
        let v3 = SemanticVersion(major: 1, minor: 2)
        
        let reports = [
            makeDeviceReport(version: v1, isSuccess: false),
            makeDeviceReport(version: v2, isSuccess: true),
            makeDeviceReport(version: v3, isSuccess: true)
        ]
        
        let result = analyzer.analyze(reports)
        
        #expect(result.comparisons.count == 2)
    }
    
    @Test("Filter by device type")
    func filterByDeviceType() {
        let config = VersionCorrelationAnalyzer.Config(deviceTypes: [.dexcomG6])
        let analyzer = VersionCorrelationAnalyzer(config: config)
        
        let reports = [
            makeDeviceReport(deviceType: .dexcomG6, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG7, isSuccess: true),
            makeDeviceReport(deviceType: .libre2, isSuccess: true)
        ]
        
        let result = analyzer.analyze(reports)
        
        #expect(result.versionStats.count == 1)
    }
    
    @Test("Group by version family")
    func groupByFamily() {
        let config = VersionCorrelationAnalyzer.Config(minimumReports: 1, groupByFamily: true)
        let analyzer = VersionCorrelationAnalyzer(config: config)
        
        let v1a = SemanticVersion(major: 1, minor: 0, patch: 0)
        let v1b = SemanticVersion(major: 1, minor: 0, patch: 1)
        let v2 = SemanticVersion(major: 1, minor: 1, patch: 0)
        
        let reports = [
            makeDeviceReport(version: v1a, isSuccess: true),
            makeDeviceReport(version: v1b, isSuccess: true),
            makeDeviceReport(version: v2, isSuccess: true)
        ]
        
        let result = analyzer.analyze(reports)
        
        // v1a and v1b should be grouped together (1.0 family)
        #expect(result.versionStats.count == 2)
    }
    
    @Test("Compare two versions")
    func compareTwoVersions() {
        let analyzer = VersionCorrelationAnalyzer()
        let v1 = SemanticVersion(major: 1, minor: 0)
        let v2 = SemanticVersion(major: 1, minor: 1)
        
        let reports = [
            makeDeviceReport(version: v1, isSuccess: false),
            makeDeviceReport(version: v2, isSuccess: true)
        ]
        
        let comparison = analyzer.compare(v1, v2, in: reports)
        
        #expect(comparison != nil)
        #expect(comparison?.isImprovement == true)
    }
    
    @Test("Find regressions")
    func findRegressions() {
        let config = VersionCorrelationAnalyzer.Config(minimumReports: 1)
        let analyzer = VersionCorrelationAnalyzer(config: config)
        
        let v1 = SemanticVersion(major: 1, minor: 0)
        let v2 = SemanticVersion(major: 1, minor: 1)
        
        let reports = [
            makeDeviceReport(version: v1, isSuccess: true),
            makeDeviceReport(version: v2, isSuccess: false)
        ]
        
        let result = analyzer.analyze(reports)
        let regressions = analyzer.findRegressions(in: result, threshold: 0.5)
        
        #expect(regressions.count == 1)
    }
    
    @Test("Find improvements")
    func findImprovements() {
        let config = VersionCorrelationAnalyzer.Config(minimumReports: 1)
        let analyzer = VersionCorrelationAnalyzer(config: config)
        
        let v1 = SemanticVersion(major: 1, minor: 0)
        let v2 = SemanticVersion(major: 1, minor: 1)
        
        let reports = [
            makeDeviceReport(version: v1, isSuccess: false),
            makeDeviceReport(version: v2, isSuccess: true)
        ]
        
        let result = analyzer.analyze(reports)
        let improvements = analyzer.findImprovements(in: result, threshold: 0.5)
        
        #expect(improvements.count == 1)
    }
}

// MARK: - Correlation Result Tests

@Suite("Correlation Result")
struct CorrelationResultTests {
    
    @Test("Empty result")
    func emptyResult() {
        let result = VersionCorrelationResult.empty
        
        #expect(result.versionStats.isEmpty)
        #expect(result.bestVersion == nil)
        #expect(result.worstVersion == nil)
    }
    
    @Test("Reliable versions filtered")
    func reliableVersions() {
        let now = Date()
        let stats = [
            VersionStatistics(
                version: SemanticVersion(major: 1, minor: 0),
                deviceType: .dexcomG6,
                reportCount: 10,
                successCount: 8,
                errorCount: 2,
                averageSessionDuration: 120,
                firstSeen: now,
                lastSeen: now
            ),
            VersionStatistics(
                version: SemanticVersion(major: 1, minor: 1),
                deviceType: .dexcomG6,
                reportCount: 2,  // Below threshold
                successCount: 2,
                errorCount: 0,
                averageSessionDuration: 120,
                firstSeen: now,
                lastSeen: now
            )
        ]
        
        let result = VersionCorrelationResult(
            versionStats: stats,
            bestVersion: nil,
            worstVersion: nil,
            comparisons: [],
            overallTrend: 0,
            minimumReportsThreshold: 5
        )
        
        #expect(result.reliableVersions.count == 1)
    }
    
    @Test("Result is Codable")
    func codable() throws {
        let result = VersionCorrelationResult.empty
        
        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(VersionCorrelationResult.self, from: encoded)
        
        #expect(decoded.versionStats.count == result.versionStats.count)
    }
}

// MARK: - Compatibility Matrix Tests

@Suite("Compatibility Matrix")
struct CompatibilityMatrixTests {
    
    @Test("Empty matrix")
    func emptyMatrix() {
        let matrix = CompatibilityMatrix.empty
        
        #expect(matrix.entries.isEmpty)
        #expect(matrix.overallScore == 0)
    }
    
    @Test("Build matrix from reports")
    func buildMatrix() {
        let analyzer = CompatibilityAnalyzer(minimumReports: 1)
        
        let reports = [
            makeDeviceReport(deviceType: .dexcomG6, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG6, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG7, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG7, isSuccess: false)
        ]
        
        let matrix = analyzer.buildMatrix(reports)
        
        #expect(matrix.entries.count == 2)
        #expect(matrix.entries[.dexcomG6] != nil)
        #expect(matrix.entries[.dexcomG7] != nil)
    }
    
    @Test("Identify problematic devices")
    func identifyProblematic() {
        let analyzer = CompatibilityAnalyzer(problemThreshold: 0.8, minimumReports: 2)
        
        let reports = [
            makeDeviceReport(deviceType: .dexcomG6, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG6, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG7, isSuccess: false),
            makeDeviceReport(deviceType: .dexcomG7, isSuccess: false)
        ]
        
        let matrix = analyzer.buildMatrix(reports)
        
        #expect(matrix.problematicDevices.contains(.dexcomG7))
        #expect(!matrix.problematicDevices.contains(.dexcomG6))
    }
    
    @Test("Recommend versions")
    func recommendVersions() {
        let analyzer = CompatibilityAnalyzer(minimumReports: 1)
        
        let v1 = SemanticVersion(major: 1, minor: 0)
        let v2 = SemanticVersion(major: 1, minor: 1)
        
        let reports = [
            makeDeviceReport(deviceType: .dexcomG6, version: v1, isSuccess: false),
            makeDeviceReport(deviceType: .dexcomG6, version: v2, isSuccess: true)
        ]
        
        let matrix = analyzer.buildMatrix(reports)
        
        #expect(matrix.recommendedVersions[.dexcomG6] == v2)
    }
    
    @Test("Overall score calculation")
    func overallScore() {
        let analyzer = CompatibilityAnalyzer(minimumReports: 2)
        
        let reports = [
            makeDeviceReport(deviceType: .dexcomG6, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG6, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG7, isSuccess: true),
            makeDeviceReport(deviceType: .dexcomG7, isSuccess: false)
        ]
        
        let matrix = analyzer.buildMatrix(reports)
        
        // G6: 100%, G7: 50%, average: 75%
        #expect(matrix.overallScore == 0.75)
    }
}

// MARK: - Device Report Tests

@Suite("Device Report")
struct DeviceReportTests {
    
    @Test("Create device report")
    func create() {
        let report = DeviceReport(
            deviceId: "DEV-123",
            deviceType: .dexcomG6,
            firmwareVersion: SemanticVersion(major: 1, minor: 0),
            isSuccess: true,
            errorCount: 0,
            sessionDuration: 120
        )
        
        #expect(report.deviceId == "DEV-123")
        #expect(report.deviceType == .dexcomG6)
        #expect(report.isSuccess == true)
    }
    
    @Test("Report is Codable")
    func codable() throws {
        let report = makeDeviceReport()
        
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(DeviceReport.self, from: encoded)
        
        #expect(decoded.deviceId == report.deviceId)
        #expect(decoded.deviceType == report.deviceType)
    }
}
