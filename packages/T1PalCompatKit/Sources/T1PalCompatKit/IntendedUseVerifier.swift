// SPDX-License-Identifier: AGPL-3.0-or-later
//
// IntendedUseVerifier.swift
// T1PalCompatKit
//
// Intended use verification for regulatory compliance.
// Trace: PRD-006 REQ-COMPAT-003
//
// Maps device capabilities to intended use claims and verifies
// that the device meets requirements for each operational mode.

import Foundation

// MARK: - Intended Use Modes

/// Operational modes with different capability requirements
public enum IntendedUseMode: String, Codable, Sendable, CaseIterable {
    /// Demo mode - simulated data, no real device connections
    case demo = "demo"
    /// CGM-only mode - reads CGM data, no insulin delivery
    case cgmOnly = "cgm-only"
    /// AID controller mode - full closed-loop operation
    case aidController = "aid-controller"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .demo: return "Demo Mode"
        case .cgmOnly: return "CGM-Only Mode"
        case .aidController: return "AID Controller Mode"
        }
    }
    
    /// Description of the mode
    public var description: String {
        switch self {
        case .demo:
            return "Simulated glucose data for demonstration and training. No real device connections required."
        case .cgmOnly:
            return "Displays glucose readings from connected CGM. Does not control insulin delivery."
        case .aidController:
            return "Automated insulin delivery based on CGM readings. Requires pump connection and algorithm."
        }
    }
    
    /// Risk level for regulatory purposes
    public var riskLevel: RiskLevel {
        switch self {
        case .demo: return .minimal
        case .cgmOnly: return .low
        case .aidController: return .high
        }
    }
}

/// Risk classification for intended use modes
public enum RiskLevel: String, Codable, Sendable {
    case minimal = "minimal"
    case low = "low"
    case moderate = "moderate"
    case high = "high"
}

// MARK: - Capability Requirements

/// Requirements for a specific intended use mode
public struct ModeRequirements: Sendable {
    /// Required capability categories
    public let requiredCategories: Set<CapabilityCategory>
    /// Categories that should pass for full compatibility
    public let recommendedCategories: Set<CapabilityCategory>
    /// Minimum passing tests per category
    public let minimumPassingTests: [CapabilityCategory: Int]
    /// Critical tests that must pass
    public let criticalTestIds: Set<String>
    
    public init(
        requiredCategories: Set<CapabilityCategory>,
        recommendedCategories: Set<CapabilityCategory> = [],
        minimumPassingTests: [CapabilityCategory: Int] = [:],
        criticalTestIds: Set<String> = []
    ) {
        self.requiredCategories = requiredCategories
        self.recommendedCategories = recommendedCategories
        self.minimumPassingTests = minimumPassingTests
        self.criticalTestIds = criticalTestIds
    }
}

/// Database of requirements per mode
public struct IntendedUseRequirements: Sendable {
    
    /// Get requirements for a specific mode
    public static func requirements(for mode: IntendedUseMode) -> ModeRequirements {
        switch mode {
        case .demo:
            return ModeRequirements(
                requiredCategories: [],  // No hardware required
                recommendedCategories: [.notification],
                minimumPassingTests: [:],
                criticalTestIds: []
            )
            
        case .cgmOnly:
            return ModeRequirements(
                requiredCategories: [.bluetooth],
                recommendedCategories: [.notification, .healthkit, .colocatedApps],
                minimumPassingTests: [.bluetooth: 2],
                criticalTestIds: ["ble-availability", "ble-authorization"]
            )
            
        case .aidController:
            return ModeRequirements(
                requiredCategories: [.bluetooth, .notification],
                recommendedCategories: [.healthkit, .colocatedApps],
                minimumPassingTests: [
                    .bluetooth: 3,
                    .notification: 2
                ],
                criticalTestIds: [
                    "ble-availability",
                    "ble-authorization",
                    "notif-authorization",
                    "notif-critical-alerts",
                    "conflict-risk-assessment"
                ]
            )
        }
    }
}

// MARK: - Verification Result

/// Result of verifying a single mode
public struct ModeVerificationResult: Sendable {
    public let mode: IntendedUseMode
    public let status: VerificationStatus
    public let passedCategories: Set<CapabilityCategory>
    public let failedCategories: Set<CapabilityCategory>
    public let missingCategories: Set<CapabilityCategory>
    public let criticalFailures: [String]
    public let warnings: [String]
    public let details: [String: String]
    
    public var isCompatible: Bool {
        status == .compatible || status == .compatibleWithWarnings
    }
    
    public init(
        mode: IntendedUseMode,
        status: VerificationStatus,
        passedCategories: Set<CapabilityCategory> = [],
        failedCategories: Set<CapabilityCategory> = [],
        missingCategories: Set<CapabilityCategory> = [],
        criticalFailures: [String] = [],
        warnings: [String] = [],
        details: [String: String] = [:]
    ) {
        self.mode = mode
        self.status = status
        self.passedCategories = passedCategories
        self.failedCategories = failedCategories
        self.missingCategories = missingCategories
        self.criticalFailures = criticalFailures
        self.warnings = warnings
        self.details = details
    }
}

/// Verification status for a mode
public enum VerificationStatus: String, Codable, Sendable {
    case compatible = "compatible"
    case compatibleWithWarnings = "compatible-with-warnings"
    case incompatible = "incompatible"
    case notTested = "not-tested"
    
    public var displayName: String {
        switch self {
        case .compatible: return "Compatible"
        case .compatibleWithWarnings: return "Compatible (with warnings)"
        case .incompatible: return "Not Compatible"
        case .notTested: return "Not Tested"
        }
    }
    
    public var indicator: String {
        switch self {
        case .compatible: return "✓"
        case .compatibleWithWarnings: return "⚠"
        case .incompatible: return "✗"
        case .notTested: return "○"
        }
    }
}

// MARK: - Intended Use Verifier

/// Verifies device compatibility for intended use modes
public struct IntendedUseVerifier: Sendable {
    
    public init() {}
    
    /// Verify compatibility for a specific mode
    public func verify(
        mode: IntendedUseMode,
        testResults: [CapabilityResult],
        testMetadata: [String: CapabilityCategory] = [:]
    ) -> ModeVerificationResult {
        let requirements = IntendedUseRequirements.requirements(for: mode)
        
        // Group results by category
        var resultsByCategory: [CapabilityCategory: [CapabilityResult]] = [:]
        for (testId, category) in testMetadata {
            if let result = testResults.first(where: { $0.testId == testId }) {
                resultsByCategory[category, default: []].append(result)
            }
        }
        
        // Check required categories
        var passedCategories: Set<CapabilityCategory> = []
        var failedCategories: Set<CapabilityCategory> = []
        var missingCategories: Set<CapabilityCategory> = []
        var criticalFailures: [String] = []
        var warnings: [String] = []
        var details: [String: String] = [:]
        
        for category in requirements.requiredCategories {
            guard let results = resultsByCategory[category], !results.isEmpty else {
                missingCategories.insert(category)
                continue
            }
            
            let passedCount = results.filter { $0.status == .passed }.count
            let minRequired = requirements.minimumPassingTests[category] ?? 1
            
            if passedCount >= minRequired {
                passedCategories.insert(category)
            } else {
                failedCategories.insert(category)
            }
            
            details["\(category.rawValue)_passed"] = String(passedCount)
            details["\(category.rawValue)_total"] = String(results.count)
        }
        
        // Check critical tests
        for criticalId in requirements.criticalTestIds {
            if let result = testResults.first(where: { $0.testId == criticalId }) {
                if result.status == .failed {
                    criticalFailures.append("Critical test failed: \(criticalId)")
                }
            } else {
                criticalFailures.append("Critical test not run: \(criticalId)")
            }
        }
        
        // Check recommended categories for warnings
        for category in requirements.recommendedCategories {
            if let results = resultsByCategory[category] {
                let failedCount = results.filter { $0.status == .failed }.count
                if failedCount > 0 {
                    warnings.append("\(category.displayName): \(failedCount) test(s) failed")
                }
            } else {
                warnings.append("\(category.displayName): not tested")
            }
        }
        
        // Determine overall status
        let status: VerificationStatus
        if !criticalFailures.isEmpty || !failedCategories.isEmpty {
            status = .incompatible
        } else if !missingCategories.isEmpty {
            status = .notTested
        } else if !warnings.isEmpty {
            status = .compatibleWithWarnings
        } else {
            status = .compatible
        }
        
        return ModeVerificationResult(
            mode: mode,
            status: status,
            passedCategories: passedCategories,
            failedCategories: failedCategories,
            missingCategories: missingCategories,
            criticalFailures: criticalFailures,
            warnings: warnings,
            details: details
        )
    }
    
    /// Verify all modes
    public func verifyAllModes(
        testResults: [CapabilityResult],
        testMetadata: [String: CapabilityCategory] = [:]
    ) -> [ModeVerificationResult] {
        IntendedUseMode.allCases.map { mode in
            verify(mode: mode, testResults: testResults, testMetadata: testMetadata)
        }
    }
}

// MARK: - Device Compatibility Report

/// Comprehensive device compatibility report for export
public struct DeviceCompatibilityReport: Sendable, Codable {
    public let reportId: String
    public let generatedAt: Date
    public let deviceInfo: DeviceReportInfo
    public let modeResults: [ModeReportEntry]
    public let overallCompatibility: OverallCompatibility
    public let testSummary: TestSummary
    public let recommendations: [String]
    
    public init(
        reportId: String = UUID().uuidString,
        generatedAt: Date = Date(),
        deviceInfo: DeviceReportInfo,
        modeResults: [ModeReportEntry],
        overallCompatibility: OverallCompatibility,
        testSummary: TestSummary,
        recommendations: [String] = []
    ) {
        self.reportId = reportId
        self.generatedAt = generatedAt
        self.deviceInfo = deviceInfo
        self.modeResults = modeResults
        self.overallCompatibility = overallCompatibility
        self.testSummary = testSummary
        self.recommendations = recommendations
    }
}

/// Device information for the report
public struct DeviceReportInfo: Sendable, Codable {
    public let model: String
    public let osVersion: String
    public let appVersion: String
    public let buildNumber: String
    
    public init(
        model: String,
        osVersion: String,
        appVersion: String,
        buildNumber: String
    ) {
        self.model = model
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }
    
    #if os(iOS)
    public static var current: DeviceReportInfo {
        DeviceReportInfo(
            model: "iOS Device",
            osVersion: "iOS",
            appVersion: "1.0.0",
            buildNumber: "1"
        )
    }
    #else
    public static var current: DeviceReportInfo {
        DeviceReportInfo(
            model: "Linux",
            osVersion: "Linux",
            appVersion: "1.0.0",
            buildNumber: "1"
        )
    }
    #endif
}

/// Mode result entry for the report
public struct ModeReportEntry: Sendable, Codable {
    public let mode: String
    public let modeName: String
    public let status: String
    public let statusIndicator: String
    public let riskLevel: String
    public let passedCount: Int
    public let failedCount: Int
    public let warningCount: Int
    public let criticalFailures: [String]
    
    public init(from result: ModeVerificationResult) {
        self.mode = result.mode.rawValue
        self.modeName = result.mode.displayName
        self.status = result.status.displayName
        self.statusIndicator = result.status.indicator
        self.riskLevel = result.mode.riskLevel.rawValue
        self.passedCount = result.passedCategories.count
        self.failedCount = result.failedCategories.count + result.missingCategories.count
        self.warningCount = result.warnings.count
        self.criticalFailures = result.criticalFailures
    }
}

/// Overall compatibility summary
public struct OverallCompatibility: Sendable, Codable {
    public let highestCompatibleMode: String?
    public let compatibleModes: [String]
    public let incompatibleModes: [String]
    
    public init(
        highestCompatibleMode: String?,
        compatibleModes: [String],
        incompatibleModes: [String]
    ) {
        self.highestCompatibleMode = highestCompatibleMode
        self.compatibleModes = compatibleModes
        self.incompatibleModes = incompatibleModes
    }
}

/// Test summary for the report
public struct TestSummary: Sendable, Codable {
    public let totalTests: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let unsupported: Int
    
    public init(
        totalTests: Int,
        passed: Int,
        failed: Int,
        skipped: Int,
        unsupported: Int
    ) {
        self.totalTests = totalTests
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.unsupported = unsupported
    }
    
    public static func from(results: [CapabilityResult]) -> TestSummary {
        TestSummary(
            totalTests: results.count,
            passed: results.filter { $0.status == .passed }.count,
            failed: results.filter { $0.status == .failed }.count,
            skipped: results.filter { $0.status == .skipped }.count,
            unsupported: results.filter { $0.status == .unsupported }.count
        )
    }
}

// MARK: - Report Generator

/// Generates device compatibility reports
public struct DeviceCompatibilityReportGenerator: Sendable {
    private let verifier: IntendedUseVerifier
    
    public init(verifier: IntendedUseVerifier = IntendedUseVerifier()) {
        self.verifier = verifier
    }
    
    /// Generate a compatibility report
    public func generate(
        testResults: [CapabilityResult],
        testMetadata: [String: CapabilityCategory],
        deviceInfo: DeviceReportInfo = .current
    ) -> DeviceCompatibilityReport {
        let modeResults = verifier.verifyAllModes(
            testResults: testResults,
            testMetadata: testMetadata
        )
        
        let modeEntries = modeResults.map { ModeReportEntry(from: $0) }
        
        // Determine compatible modes
        let compatibleModes = modeResults
            .filter { $0.isCompatible }
            .map { $0.mode.rawValue }
        
        let incompatibleModes = modeResults
            .filter { !$0.isCompatible }
            .map { $0.mode.rawValue }
        
        // Find highest compatible mode (AID > CGM > Demo)
        let modeOrder: [IntendedUseMode] = [.aidController, .cgmOnly, .demo]
        let highestCompatible = modeOrder.first { mode in
            modeResults.first { $0.mode == mode }?.isCompatible == true
        }
        
        // Generate recommendations
        var recommendations: [String] = []
        for result in modeResults where !result.isCompatible {
            if !result.criticalFailures.isEmpty {
                recommendations.append("For \(result.mode.displayName): Address critical failures first")
            }
            for missing in result.missingCategories {
                recommendations.append("Run \(missing.displayName) tests for \(result.mode.displayName)")
            }
        }
        
        return DeviceCompatibilityReport(
            deviceInfo: deviceInfo,
            modeResults: modeEntries,
            overallCompatibility: OverallCompatibility(
                highestCompatibleMode: highestCompatible?.rawValue,
                compatibleModes: compatibleModes,
                incompatibleModes: incompatibleModes
            ),
            testSummary: TestSummary.from(results: testResults),
            recommendations: recommendations
        )
    }
    
    /// Export report as JSON
    public func exportJSON(report: DeviceCompatibilityReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}
