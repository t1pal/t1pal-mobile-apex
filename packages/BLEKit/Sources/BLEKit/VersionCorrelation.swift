// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// VersionCorrelation.swift - Firmware version correlation analysis
// Part of BLEKit
// Trace: EVID-003

import Foundation

// MARK: - Firmware Version

/// Semantic firmware version representation
public struct SemanticVersion: Sendable, Codable, Hashable, Comparable {
    /// Major version number
    public let major: Int
    
    /// Minor version number
    public let minor: Int
    
    /// Patch version number
    public let patch: Int
    
    /// Build number (optional)
    public let build: Int?
    
    /// Original version string
    public let rawValue: String
    
    public init(major: Int, minor: Int, patch: Int = 0, build: Int? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build
        if let build = build {
            self.rawValue = "\(major).\(minor).\(patch).\(build)"
        } else {
            self.rawValue = "\(major).\(minor).\(patch)"
        }
    }
    
    public init?(string: String) {
        self.rawValue = string
        
        // Parse version string
        let cleaned = string.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "v", with: "")
            .replacingOccurrences(of: "V", with: "")
        
        let components = cleaned.split(separator: ".").compactMap { Int($0) }
        
        guard components.count >= 2 else {
            return nil
        }
        
        self.major = components[0]
        self.minor = components[1]
        self.patch = components.count > 2 ? components[2] : 0
        self.build = components.count > 3 ? components[3] : nil
    }
    
    /// Unknown version placeholder
    public static let unknown = SemanticVersion(major: 0, minor: 0, patch: 0)
    
    /// Display string
    public var displayString: String {
        if let build = build {
            return "\(major).\(minor).\(patch) (build \(build))"
        }
        return "\(major).\(minor).\(patch)"
    }
    
    /// Version family (major.minor)
    public var family: String {
        "\(major).\(minor)"
    }
    
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return (lhs.build ?? 0) < (rhs.build ?? 0)
    }
}

// MARK: - Device Type

/// Known device types for version tracking
public enum DeviceType: String, CaseIterable, Sendable, Codable {
    case dexcomG6 = "dexcom_g6"
    case dexcomG7 = "dexcom_g7"
    case libre2 = "libre_2"
    case libre3 = "libre_3"
    case omnipodDash = "omnipod_dash"
    case medtronic = "medtronic"
    case dana = "dana"
    case unknown = "unknown"
    
    /// Display name
    public var displayName: String {
        switch self {
        case .dexcomG6: return "Dexcom G6"
        case .dexcomG7: return "Dexcom G7"
        case .libre2: return "Libre 2"
        case .libre3: return "Libre 3"
        case .omnipodDash: return "Omnipod DASH"
        case .medtronic: return "Medtronic"
        case .dana: return "Dana"
        case .unknown: return "Unknown"
        }
    }
    
    /// Detect device type from device ID or name
    public static func detect(from identifier: String) -> DeviceType {
        let lowercased = identifier.lowercased()
        
        if lowercased.contains("g6") || lowercased.contains("dexcom") && lowercased.contains("6") {
            return .dexcomG6
        }
        if lowercased.contains("g7") || lowercased.contains("dexcom") && lowercased.contains("7") {
            return .dexcomG7
        }
        if lowercased.contains("libre") && lowercased.contains("3") {
            return .libre3
        }
        if lowercased.contains("libre") || lowercased.contains("freestyle") {
            return .libre2
        }
        if lowercased.contains("dash") || lowercased.contains("omnipod") {
            return .omnipodDash
        }
        if lowercased.contains("medtronic") || lowercased.contains("minimed") {
            return .medtronic
        }
        if lowercased.contains("dana") {
            return .dana
        }
        
        return .unknown
    }
}

// MARK: - Version Statistics

/// Statistics for a specific firmware version
public struct VersionStatistics: Sendable, Codable, Equatable {
    /// The firmware version
    public let version: SemanticVersion
    
    /// Device type
    public let deviceType: DeviceType
    
    /// Total reports from this version
    public let reportCount: Int
    
    /// Successful reports (no errors)
    public let successCount: Int
    
    /// Total errors across all reports
    public let errorCount: Int
    
    /// Success rate (0.0-1.0)
    public var successRate: Double {
        guard reportCount > 0 else { return 0 }
        return Double(successCount) / Double(reportCount)
    }
    
    /// Average session duration
    public let averageSessionDuration: TimeInterval
    
    /// First seen date
    public let firstSeen: Date
    
    /// Last seen date
    public let lastSeen: Date
    
    /// Failure modes encountered
    public let failureModes: [String: Int]
    
    public init(
        version: SemanticVersion,
        deviceType: DeviceType,
        reportCount: Int,
        successCount: Int,
        errorCount: Int,
        averageSessionDuration: TimeInterval,
        firstSeen: Date,
        lastSeen: Date,
        failureModes: [String: Int] = [:]
    ) {
        self.version = version
        self.deviceType = deviceType
        self.reportCount = reportCount
        self.successCount = successCount
        self.errorCount = errorCount
        self.averageSessionDuration = averageSessionDuration
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.failureModes = failureModes
    }
}

// MARK: - Version Comparison

/// Comparison between two firmware versions
public struct VersionComparison: Sendable, Codable, Equatable {
    /// Older version statistics
    public let olderVersion: VersionStatistics
    
    /// Newer version statistics
    public let newerVersion: VersionStatistics
    
    /// Change in success rate (positive = improvement)
    public let successRateDelta: Double
    
    /// Change in error count
    public let errorCountDelta: Int
    
    /// Change in average session duration
    public let durationDelta: TimeInterval
    
    /// Whether the newer version is an improvement
    public var isImprovement: Bool {
        successRateDelta > 0 || (successRateDelta == 0 && errorCountDelta < 0)
    }
    
    /// Whether this is a significant change (>5% success rate change)
    public var isSignificant: Bool {
        abs(successRateDelta) > 0.05
    }
    
    public init(older: VersionStatistics, newer: VersionStatistics) {
        self.olderVersion = older
        self.newerVersion = newer
        self.successRateDelta = newer.successRate - older.successRate
        self.errorCountDelta = newer.errorCount - older.errorCount
        self.durationDelta = newer.averageSessionDuration - older.averageSessionDuration
    }
}

// MARK: - Correlation Result

/// Result of firmware version correlation analysis
public struct VersionCorrelationResult: Sendable, Codable, Equatable {
    /// Statistics by version
    public let versionStats: [VersionStatistics]
    
    /// Best performing version (highest success rate with sufficient data)
    public let bestVersion: SemanticVersion?
    
    /// Worst performing version
    public let worstVersion: SemanticVersion?
    
    /// Version comparisons (adjacent versions)
    public let comparisons: [VersionComparison]
    
    /// Overall success rate trend (positive = improving over versions)
    public let overallTrend: Double
    
    /// Minimum reports required for reliable statistics
    public let minimumReportsThreshold: Int
    
    /// Versions with sufficient data for analysis
    public var reliableVersions: [SemanticVersion] {
        versionStats
            .filter { $0.reportCount >= minimumReportsThreshold }
            .map { $0.version }
    }
    
    public init(
        versionStats: [VersionStatistics],
        bestVersion: SemanticVersion?,
        worstVersion: SemanticVersion?,
        comparisons: [VersionComparison],
        overallTrend: Double,
        minimumReportsThreshold: Int = 5
    ) {
        self.versionStats = versionStats
        self.bestVersion = bestVersion
        self.worstVersion = worstVersion
        self.comparisons = comparisons
        self.overallTrend = overallTrend
        self.minimumReportsThreshold = minimumReportsThreshold
    }
    
    /// Empty result
    public static let empty = VersionCorrelationResult(
        versionStats: [],
        bestVersion: nil,
        worstVersion: nil,
        comparisons: [],
        overallTrend: 0,
        minimumReportsThreshold: 5
    )
}

// MARK: - Device Report

/// Extended report with device/version metadata
public struct DeviceReport: Sendable, Codable {
    /// Anonymized device ID
    public let deviceId: String
    
    /// Device type
    public let deviceType: DeviceType
    
    /// Firmware version
    public let firmwareVersion: SemanticVersion
    
    /// Report timestamp
    public let timestamp: Date
    
    /// Whether the session was successful
    public let isSuccess: Bool
    
    /// Error count
    public let errorCount: Int
    
    /// Session duration
    public let sessionDuration: TimeInterval
    
    /// Failure modes (if any)
    public let failureModes: [String]
    
    public init(
        deviceId: String,
        deviceType: DeviceType,
        firmwareVersion: SemanticVersion,
        timestamp: Date = Date(),
        isSuccess: Bool,
        errorCount: Int = 0,
        sessionDuration: TimeInterval = 0,
        failureModes: [String] = []
    ) {
        self.deviceId = deviceId
        self.deviceType = deviceType
        self.firmwareVersion = firmwareVersion
        self.timestamp = timestamp
        self.isSuccess = isSuccess
        self.errorCount = errorCount
        self.sessionDuration = sessionDuration
        self.failureModes = failureModes
    }
}

// MARK: - Version Correlation Analyzer

/// Analyzes correlation between firmware versions and success rates
///
/// Trace: EVID-003
///
/// Provides analysis of device firmware versions and their correlation
/// with connection success rates, error patterns, and session quality.
public struct VersionCorrelationAnalyzer: Sendable {
    
    // MARK: - Configuration
    
    /// Configuration for correlation analysis
    public struct Config: Sendable {
        /// Minimum reports required for a version to be included
        public let minimumReports: Int
        
        /// Whether to group by version family (major.minor)
        public let groupByFamily: Bool
        
        /// Device types to include (empty = all)
        public let deviceTypes: Set<DeviceType>
        
        public init(
            minimumReports: Int = 5,
            groupByFamily: Bool = false,
            deviceTypes: Set<DeviceType> = []
        ) {
            self.minimumReports = minimumReports
            self.groupByFamily = groupByFamily
            self.deviceTypes = deviceTypes
        }
        
        /// Default configuration
        public static let `default` = Config()
        
        /// Strict configuration (more data required)
        public static let strict = Config(minimumReports: 20)
        
        /// Lenient configuration (less data required)
        public static let lenient = Config(minimumReports: 3)
    }
    
    // MARK: - Properties
    
    private let config: Config
    
    // MARK: - Initialization
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Analysis
    
    /// Analyze version correlation from device reports
    public func analyze(_ reports: [DeviceReport]) -> VersionCorrelationResult {
        // Filter by device type if specified
        let filteredReports: [DeviceReport]
        if config.deviceTypes.isEmpty {
            filteredReports = reports
        } else {
            filteredReports = reports.filter { config.deviceTypes.contains($0.deviceType) }
        }
        
        guard !filteredReports.isEmpty else {
            return .empty
        }
        
        // Group by version
        let grouped = groupByVersion(filteredReports)
        
        // Compute statistics per version
        var versionStats = grouped.map { (version, reports) -> VersionStatistics in
            computeStatistics(version: version, reports: reports)
        }
        
        // Sort by version
        versionStats.sort { $0.version < $1.version }
        
        // Find best/worst versions (with sufficient data)
        let reliableStats = versionStats.filter { $0.reportCount >= config.minimumReports }
        let bestVersion = reliableStats.max(by: { $0.successRate < $1.successRate })?.version
        let worstVersion = reliableStats.min(by: { $0.successRate < $1.successRate })?.version
        
        // Compute comparisons between adjacent versions
        var comparisons: [VersionComparison] = []
        for i in 0..<(versionStats.count - 1) {
            let comparison = VersionComparison(older: versionStats[i], newer: versionStats[i + 1])
            comparisons.append(comparison)
        }
        
        // Compute overall trend
        let overallTrend = computeTrend(versionStats)
        
        return VersionCorrelationResult(
            versionStats: versionStats,
            bestVersion: bestVersion,
            worstVersion: worstVersion,
            comparisons: comparisons,
            overallTrend: overallTrend,
            minimumReportsThreshold: config.minimumReports
        )
    }
    
    /// Group reports by firmware version
    private func groupByVersion(_ reports: [DeviceReport]) -> [SemanticVersion: [DeviceReport]] {
        var grouped: [SemanticVersion: [DeviceReport]] = [:]
        
        for report in reports {
            let key: SemanticVersion
            if config.groupByFamily {
                // Group by major.minor
                key = SemanticVersion(major: report.firmwareVersion.major, minor: report.firmwareVersion.minor)
            } else {
                key = report.firmwareVersion
            }
            grouped[key, default: []].append(report)
        }
        
        return grouped
    }
    
    /// Compute statistics for a version
    private func computeStatistics(version: SemanticVersion, reports: [DeviceReport]) -> VersionStatistics {
        let successCount = reports.filter { $0.isSuccess }.count
        let totalErrors = reports.reduce(0) { $0 + $1.errorCount }
        let totalDuration = reports.reduce(0.0) { $0 + $1.sessionDuration }
        let avgDuration = reports.isEmpty ? 0 : totalDuration / Double(reports.count)
        
        let dates = reports.map { $0.timestamp }
        let firstSeen = dates.min() ?? Date()
        let lastSeen = dates.max() ?? Date()
        
        // Count failure modes
        var failureModes: [String: Int] = [:]
        for report in reports {
            for mode in report.failureModes {
                failureModes[mode, default: 0] += 1
            }
        }
        
        // Get device type (assume all same for a version)
        let deviceType = reports.first?.deviceType ?? .unknown
        
        return VersionStatistics(
            version: version,
            deviceType: deviceType,
            reportCount: reports.count,
            successCount: successCount,
            errorCount: totalErrors,
            averageSessionDuration: avgDuration,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            failureModes: failureModes
        )
    }
    
    /// Compute overall trend across versions
    private func computeTrend(_ stats: [VersionStatistics]) -> Double {
        guard stats.count >= 2 else { return 0 }
        
        // Simple linear regression on success rates
        let n = Double(stats.count)
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumX2 = 0.0
        
        for (i, stat) in stats.enumerated() {
            let x = Double(i)
            let y = stat.successRate
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }
        
        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return 0 }
        
        let slope = (n * sumXY - sumX * sumY) / denominator
        return slope
    }
    
    // MARK: - Comparison
    
    /// Compare two specific versions
    public func compare(_ version1: SemanticVersion, _ version2: SemanticVersion, in reports: [DeviceReport]) -> VersionComparison? {
        let v1Reports = reports.filter { $0.firmwareVersion == version1 }
        let v2Reports = reports.filter { $0.firmwareVersion == version2 }
        
        guard !v1Reports.isEmpty && !v2Reports.isEmpty else {
            return nil
        }
        
        let stats1 = computeStatistics(version: version1, reports: v1Reports)
        let stats2 = computeStatistics(version: version2, reports: v2Reports)
        
        let older = version1 < version2 ? stats1 : stats2
        let newer = version1 < version2 ? stats2 : stats1
        
        return VersionComparison(older: older, newer: newer)
    }
    
    /// Find versions with degraded performance
    public func findRegressions(in result: VersionCorrelationResult, threshold: Double = 0.1) -> [VersionComparison] {
        result.comparisons.filter { $0.successRateDelta < -threshold }
    }
    
    /// Find versions with improved performance
    public func findImprovements(in result: VersionCorrelationResult, threshold: Double = 0.1) -> [VersionComparison] {
        result.comparisons.filter { $0.successRateDelta > threshold }
    }
}

// MARK: - Compatibility Matrix

/// Compatibility matrix across device types and versions
public struct CompatibilityMatrix: Sendable, Codable {
    /// Matrix entries by device type
    public let entries: [DeviceType: [VersionStatistics]]
    
    /// Overall compatibility score (0.0-1.0)
    public let overallScore: Double
    
    /// Device types with issues (success rate < threshold)
    public let problematicDevices: [DeviceType]
    
    /// Recommended versions per device type
    public let recommendedVersions: [DeviceType: SemanticVersion]
    
    public init(
        entries: [DeviceType: [VersionStatistics]],
        overallScore: Double,
        problematicDevices: [DeviceType],
        recommendedVersions: [DeviceType: SemanticVersion]
    ) {
        self.entries = entries
        self.overallScore = overallScore
        self.problematicDevices = problematicDevices
        self.recommendedVersions = recommendedVersions
    }
    
    /// Empty matrix
    public static let empty = CompatibilityMatrix(
        entries: [:],
        overallScore: 0,
        problematicDevices: [],
        recommendedVersions: [:]
    )
}

// MARK: - Compatibility Analyzer

/// Builds compatibility matrix across devices and versions
public struct CompatibilityAnalyzer: Sendable {
    
    /// Threshold for considering a device problematic
    public let problemThreshold: Double
    
    /// Minimum reports for reliable data
    public let minimumReports: Int
    
    public init(problemThreshold: Double = 0.8, minimumReports: Int = 5) {
        self.problemThreshold = problemThreshold
        self.minimumReports = minimumReports
    }
    
    /// Build compatibility matrix from device reports
    public func buildMatrix(_ reports: [DeviceReport]) -> CompatibilityMatrix {
        guard !reports.isEmpty else {
            return .empty
        }
        
        // Group by device type
        var byDevice: [DeviceType: [DeviceReport]] = [:]
        for report in reports {
            byDevice[report.deviceType, default: []].append(report)
        }
        
        // Analyze each device type
        let analyzer = VersionCorrelationAnalyzer(config: .init(minimumReports: minimumReports))
        var entries: [DeviceType: [VersionStatistics]] = [:]
        var recommendedVersions: [DeviceType: SemanticVersion] = [:]
        var problematicDevices: [DeviceType] = []
        var totalSuccessRate = 0.0
        var deviceCount = 0
        
        for (deviceType, deviceReports) in byDevice {
            let result = analyzer.analyze(deviceReports)
            entries[deviceType] = result.versionStats
            
            if let best = result.bestVersion {
                recommendedVersions[deviceType] = best
            }
            
            // Check if device type is problematic
            let overallSuccess = result.versionStats.reduce(0) { $0 + $1.successCount }
            let overallTotal = result.versionStats.reduce(0) { $0 + $1.reportCount }
            let deviceSuccessRate = overallTotal > 0 ? Double(overallSuccess) / Double(overallTotal) : 0
            
            if deviceSuccessRate < problemThreshold && overallTotal >= minimumReports {
                problematicDevices.append(deviceType)
            }
            
            if overallTotal >= minimumReports {
                totalSuccessRate += deviceSuccessRate
                deviceCount += 1
            }
        }
        
        let overallScore = deviceCount > 0 ? totalSuccessRate / Double(deviceCount) : 0
        
        return CompatibilityMatrix(
            entries: entries,
            overallScore: overallScore,
            problematicDevices: problematicDevices,
            recommendedVersions: recommendedVersions
        )
    }
}
