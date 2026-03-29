// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// PlatformCorrelation.swift - iOS/platform version correlation analysis
// Part of BLEKit
// Trace: EVID-004

import Foundation

// MARK: - Platform Version

/// Platform/OS version representation (iOS, macOS, etc.)
public struct PlatformVersion: Sendable, Codable, Hashable, Comparable {
    /// Major version number (e.g., 17 in iOS 17.2.1)
    public let major: Int
    
    /// Minor version number (e.g., 2 in iOS 17.2.1)
    public let minor: Int
    
    /// Patch version number (e.g., 1 in iOS 17.2.1)
    public let patch: Int
    
    /// Build identifier (optional, e.g., "21C52")
    public let build: String?
    
    /// Original version string
    public let rawValue: String
    
    public init(major: Int, minor: Int, patch: Int = 0, build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build
        if let build = build {
            self.rawValue = "\(major).\(minor).\(patch) (\(build))"
        } else {
            self.rawValue = "\(major).\(minor).\(patch)"
        }
    }
    
    public init?(string: String) {
        self.rawValue = string
        
        // Extract build if present (e.g., "17.2.1 (21C52)")
        var versionPart = string
        var buildPart: String? = nil
        
        if let parenStart = string.firstIndex(of: "("),
           let parenEnd = string.firstIndex(of: ")") {
            buildPart = String(string[string.index(after: parenStart)..<parenEnd])
            versionPart = String(string[..<parenStart]).trimmingCharacters(in: .whitespaces)
        }
        
        // Parse version numbers
        let cleaned = versionPart
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "iOS ", with: "")
            .replacingOccurrences(of: "macOS ", with: "")
            .replacingOccurrences(of: "v", with: "")
        
        let components = cleaned.split(separator: ".").compactMap { Int($0) }
        
        guard components.count >= 2 else {
            return nil
        }
        
        self.major = components[0]
        self.minor = components[1]
        self.patch = components.count > 2 ? components[2] : 0
        self.build = buildPart
    }
    
    /// Unknown version placeholder
    public static let unknown = PlatformVersion(major: 0, minor: 0, patch: 0)
    
    /// Major version only (e.g., "17.x")
    public var majorVersion: String {
        "\(major).x"
    }
    
    /// Major.minor version (e.g., "17.2")
    public var majorMinorVersion: String {
        "\(major).\(minor)"
    }
    
    public static func < (lhs: PlatformVersion, rhs: PlatformVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

// MARK: - Platform Type

/// Operating system platform
public enum PlatformType: String, Sendable, Codable, CaseIterable {
    case iOS
    case macOS
    case watchOS
    case tvOS
    case visionOS
    case linux
    case unknown
    
    /// Detect platform from string
    public static func detect(from string: String) -> PlatformType {
        let lowered = string.lowercased()
        
        if lowered.contains("ios") || lowered.contains("iphone") || lowered.contains("ipad") {
            return .iOS
        }
        if lowered.contains("macos") || lowered.contains("mac os") || lowered.contains("osx") {
            return .macOS
        }
        if lowered.contains("watchos") || lowered.contains("watch os") {
            return .watchOS
        }
        if lowered.contains("tvos") || lowered.contains("apple tv") {
            return .tvOS
        }
        if lowered.contains("visionos") || lowered.contains("vision pro") {
            return .visionOS
        }
        if lowered.contains("linux") || lowered.contains("ubuntu") || lowered.contains("debian") {
            return .linux
        }
        
        return .unknown
    }
    
    /// Minimum supported version for BLE operations
    public var minimumBLEVersion: PlatformVersion {
        switch self {
        case .iOS: return PlatformVersion(major: 13, minor: 0)
        case .macOS: return PlatformVersion(major: 10, minor: 15)
        case .watchOS: return PlatformVersion(major: 6, minor: 0)
        case .tvOS: return PlatformVersion(major: 13, minor: 0)
        case .visionOS: return PlatformVersion(major: 1, minor: 0)
        case .linux: return PlatformVersion(major: 5, minor: 0) // Kernel version
        case .unknown: return .unknown
        }
    }
}

// MARK: - Platform Statistics

/// Statistics for a specific platform version
public struct PlatformStatistics: Sendable, Codable, Equatable {
    /// Platform type
    public let platform: PlatformType
    
    /// Platform version
    public let version: PlatformVersion
    
    /// Total number of reports
    public let reportCount: Int
    
    /// Number of successful connections
    public let successCount: Int
    
    /// Number of failed connections
    public let failureCount: Int
    
    /// Success rate (0.0 - 1.0)
    public var successRate: Double {
        guard reportCount > 0 else { return 0.0 }
        return Double(successCount) / Double(reportCount)
    }
    
    /// Average connection time in seconds
    public let avgConnectionTime: Double
    
    /// Common failure modes on this platform version
    public let commonFailures: [String: Int]
    
    /// Device types tested on this version
    public let deviceTypes: [DeviceType]
    
    public init(
        platform: PlatformType,
        version: PlatformVersion,
        reportCount: Int,
        successCount: Int,
        failureCount: Int,
        avgConnectionTime: Double,
        commonFailures: [String: Int] = [:],
        deviceTypes: [DeviceType] = []
    ) {
        self.platform = platform
        self.version = version
        self.reportCount = reportCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.avgConnectionTime = avgConnectionTime
        self.commonFailures = commonFailures
        self.deviceTypes = deviceTypes
    }
}

// MARK: - Platform Comparison

/// Comparison between two platform versions
public struct PlatformComparison: Sendable, Codable, Equatable {
    /// Earlier platform version
    public let fromVersion: PlatformVersion
    
    /// Later platform version
    public let toVersion: PlatformVersion
    
    /// Change in success rate (positive = improvement)
    public let successRateDelta: Double
    
    /// Change in average connection time (negative = faster)
    public let connectionTimeDelta: Double
    
    /// New failure modes introduced
    public let newFailures: [String]
    
    /// Failure modes resolved
    public let resolvedFailures: [String]
    
    /// Whether this represents a regression
    public var isRegression: Bool {
        successRateDelta < -0.05 // More than 5% drop
    }
    
    /// Whether this represents an improvement
    public var isImprovement: Bool {
        successRateDelta > 0.05 // More than 5% increase
    }
    
    public init(
        fromVersion: PlatformVersion,
        toVersion: PlatformVersion,
        successRateDelta: Double,
        connectionTimeDelta: Double,
        newFailures: [String] = [],
        resolvedFailures: [String] = []
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.successRateDelta = successRateDelta
        self.connectionTimeDelta = connectionTimeDelta
        self.newFailures = newFailures
        self.resolvedFailures = resolvedFailures
    }
}

// MARK: - Platform Correlation Result

/// Result of platform version correlation analysis
public struct PlatformCorrelationResult: Sendable, Codable, Equatable {
    /// Statistics by platform version
    public let platformStats: [PlatformStatistics]
    
    /// Best performing version (highest success rate with sufficient data)
    public let bestVersion: PlatformVersion?
    
    /// Worst performing version
    public let worstVersion: PlatformVersion?
    
    /// Version comparisons (adjacent versions)
    public let comparisons: [PlatformComparison]
    
    /// Overall success rate trend (positive = improving over versions)
    public let overallTrend: Double
    
    /// Minimum reports required for reliable statistics
    public let minimumReportsThreshold: Int
    
    /// Versions with sufficient data for analysis
    public var reliableVersions: [PlatformVersion] {
        platformStats
            .filter { $0.reportCount >= minimumReportsThreshold }
            .map { $0.version }
    }
    
    /// Platform-specific issues
    public let platformIssues: [PlatformIssue]
    
    public init(
        platformStats: [PlatformStatistics],
        bestVersion: PlatformVersion?,
        worstVersion: PlatformVersion?,
        comparisons: [PlatformComparison],
        overallTrend: Double,
        minimumReportsThreshold: Int = 5,
        platformIssues: [PlatformIssue] = []
    ) {
        self.platformStats = platformStats
        self.bestVersion = bestVersion
        self.worstVersion = worstVersion
        self.comparisons = comparisons
        self.overallTrend = overallTrend
        self.minimumReportsThreshold = minimumReportsThreshold
        self.platformIssues = platformIssues
    }
    
    /// Empty result
    public static let empty = PlatformCorrelationResult(
        platformStats: [],
        bestVersion: nil,
        worstVersion: nil,
        comparisons: [],
        overallTrend: 0.0
    )
}

// MARK: - Platform Issue

/// Known issue on a specific platform version
public struct PlatformIssue: Sendable, Codable, Equatable {
    /// Platform type
    public let platform: PlatformType
    
    /// Affected version range
    public let affectedVersions: VersionRange
    
    /// Issue description
    public let description: String
    
    /// Severity level
    public let severity: IssueSeverity
    
    /// Workaround if available
    public let workaround: String?
    
    /// Apple radar/feedback ID if reported
    public let radarId: String?
    
    public init(
        platform: PlatformType,
        affectedVersions: VersionRange,
        description: String,
        severity: IssueSeverity,
        workaround: String? = nil,
        radarId: String? = nil
    ) {
        self.platform = platform
        self.affectedVersions = affectedVersions
        self.description = description
        self.severity = severity
        self.workaround = workaround
        self.radarId = radarId
    }
}

/// Version range for affected versions
public struct VersionRange: Sendable, Codable, Equatable {
    public let minimum: PlatformVersion
    public let maximum: PlatformVersion?
    
    public init(minimum: PlatformVersion, maximum: PlatformVersion? = nil) {
        self.minimum = minimum
        self.maximum = maximum
    }
    
    /// Check if version is in range
    public func contains(_ version: PlatformVersion) -> Bool {
        if version < minimum { return false }
        if let max = maximum, version > max { return false }
        return true
    }
    
    /// Single version range
    public static func single(_ version: PlatformVersion) -> VersionRange {
        VersionRange(minimum: version, maximum: version)
    }
    
    /// Open-ended range (minimum and above)
    public static func from(_ version: PlatformVersion) -> VersionRange {
        VersionRange(minimum: version, maximum: nil)
    }
}

/// Issue severity level
public enum IssueSeverity: String, Sendable, Codable, CaseIterable {
    case critical   // Complete BLE failure
    case major      // Significant functionality loss
    case moderate   // Some features affected
    case minor      // Cosmetic or rare issues
}

// MARK: - Platform Report

/// Report of BLE connection attempt with platform info
public struct PlatformReport: Sendable, Codable, Equatable {
    /// Unique report identifier
    public let id: String
    
    /// Platform type
    public let platform: PlatformType
    
    /// Platform version
    public let platformVersion: PlatformVersion
    
    /// Device type being connected
    public let deviceType: DeviceType
    
    /// Whether connection was successful
    public let success: Bool
    
    /// Connection duration in seconds (if successful)
    public let connectionTime: Double?
    
    /// Failure reason (if failed)
    public let failureReason: String?
    
    /// Timestamp
    public let timestamp: Date
    
    /// Device model (e.g., "iPhone 15 Pro")
    public let deviceModel: String?
    
    public init(
        id: String = UUID().uuidString,
        platform: PlatformType,
        platformVersion: PlatformVersion,
        deviceType: DeviceType,
        success: Bool,
        connectionTime: Double? = nil,
        failureReason: String? = nil,
        timestamp: Date = Date(),
        deviceModel: String? = nil
    ) {
        self.id = id
        self.platform = platform
        self.platformVersion = platformVersion
        self.deviceType = deviceType
        self.success = success
        self.connectionTime = connectionTime
        self.failureReason = failureReason
        self.timestamp = timestamp
        self.deviceModel = deviceModel
    }
}

// MARK: - Platform Correlation Analyzer

/// Analyzes BLE success rates correlated with platform versions
public struct PlatformCorrelationAnalyzer: Sendable {
    /// Minimum reports required for reliable statistics
    public let minimumReportsThreshold: Int
    
    /// Known platform issues database
    public let knownIssues: [PlatformIssue]
    
    public init(
        minimumReportsThreshold: Int = 5,
        knownIssues: [PlatformIssue] = []
    ) {
        self.minimumReportsThreshold = minimumReportsThreshold
        self.knownIssues = knownIssues
    }
    
    /// Analyze reports and produce correlation result
    public func analyze(reports: [PlatformReport]) -> PlatformCorrelationResult {
        guard !reports.isEmpty else {
            return .empty
        }
        
        // Group by platform version
        var versionGroups: [PlatformVersion: [PlatformReport]] = [:]
        for report in reports {
            versionGroups[report.platformVersion, default: []].append(report)
        }
        
        // Calculate statistics for each version
        var stats: [PlatformStatistics] = []
        for (version, versionReports) in versionGroups {
            let platform = versionReports.first?.platform ?? .unknown
            let successReports = versionReports.filter { $0.success }
            let failureReports = versionReports.filter { !$0.success }
            
            // Calculate average connection time
            let connectionTimes = successReports.compactMap { $0.connectionTime }
            let avgTime = connectionTimes.isEmpty ? 0.0 :
                connectionTimes.reduce(0.0, +) / Double(connectionTimes.count)
            
            // Count failure reasons
            var failureCounts: [String: Int] = [:]
            for report in failureReports {
                if let reason = report.failureReason {
                    failureCounts[reason, default: 0] += 1
                }
            }
            
            // Get unique device types
            let deviceTypes = Array(Set(versionReports.map { $0.deviceType }))
            
            let stat = PlatformStatistics(
                platform: platform,
                version: version,
                reportCount: versionReports.count,
                successCount: successReports.count,
                failureCount: failureReports.count,
                avgConnectionTime: avgTime,
                commonFailures: failureCounts,
                deviceTypes: deviceTypes
            )
            stats.append(stat)
        }
        
        // Sort by version
        stats.sort { $0.version < $1.version }
        
        // Find best/worst versions (with sufficient data)
        let reliableStats = stats.filter { $0.reportCount >= minimumReportsThreshold }
        let bestVersion = reliableStats.max(by: { $0.successRate < $1.successRate })?.version
        let worstVersion = reliableStats.min(by: { $0.successRate < $1.successRate })?.version
        
        // Generate comparisons between adjacent versions
        var comparisons: [PlatformComparison] = []
        for i in 0..<(stats.count - 1) {
            let from = stats[i]
            let to = stats[i + 1]
            
            let successDelta = to.successRate - from.successRate
            let timeDelta = to.avgConnectionTime - from.avgConnectionTime
            
            // Find new and resolved failures
            let fromFailures = Set(from.commonFailures.keys)
            let toFailures = Set(to.commonFailures.keys)
            let newFailures = Array(toFailures.subtracting(fromFailures))
            let resolvedFailures = Array(fromFailures.subtracting(toFailures))
            
            let comparison = PlatformComparison(
                fromVersion: from.version,
                toVersion: to.version,
                successRateDelta: successDelta,
                connectionTimeDelta: timeDelta,
                newFailures: newFailures,
                resolvedFailures: resolvedFailures
            )
            comparisons.append(comparison)
        }
        
        // Calculate overall trend
        let overallTrend: Double
        if let first = reliableStats.first, let last = reliableStats.last, first.version != last.version {
            overallTrend = last.successRate - first.successRate
        } else {
            overallTrend = 0.0
        }
        
        // Find applicable known issues
        let versions = Set(reports.map { $0.platformVersion })
        let applicableIssues = knownIssues.filter { issue in
            versions.contains { issue.affectedVersions.contains($0) }
        }
        
        return PlatformCorrelationResult(
            platformStats: stats,
            bestVersion: bestVersion,
            worstVersion: worstVersion,
            comparisons: comparisons,
            overallTrend: overallTrend,
            minimumReportsThreshold: minimumReportsThreshold,
            platformIssues: applicableIssues
        )
    }
    
    /// Analyze by major version only (grouping minor versions)
    public func analyzeByMajorVersion(reports: [PlatformReport]) -> [String: PlatformStatistics] {
        var majorGroups: [String: [PlatformReport]] = [:]
        
        for report in reports {
            let majorKey = "\(report.platform.rawValue) \(report.platformVersion.major)"
            majorGroups[majorKey, default: []].append(report)
        }
        
        var result: [String: PlatformStatistics] = [:]
        
        for (majorKey, groupReports) in majorGroups {
            guard let first = groupReports.first else { continue }
            
            let successReports = groupReports.filter { $0.success }
            let failureReports = groupReports.filter { !$0.success }
            
            let connectionTimes = successReports.compactMap { $0.connectionTime }
            let avgTime = connectionTimes.isEmpty ? 0.0 :
                connectionTimes.reduce(0.0, +) / Double(connectionTimes.count)
            
            var failureCounts: [String: Int] = [:]
            for report in failureReports {
                if let reason = report.failureReason {
                    failureCounts[reason, default: 0] += 1
                }
            }
            
            let deviceTypes = Array(Set(groupReports.map { $0.deviceType }))
            
            // Use a representative version (lowest in the major)
            let representativeVersion = PlatformVersion(
                major: first.platformVersion.major,
                minor: 0,
                patch: 0
            )
            
            result[majorKey] = PlatformStatistics(
                platform: first.platform,
                version: representativeVersion,
                reportCount: groupReports.count,
                successCount: successReports.count,
                failureCount: failureReports.count,
                avgConnectionTime: avgTime,
                commonFailures: failureCounts,
                deviceTypes: deviceTypes
            )
        }
        
        return result
    }
}

// MARK: - Platform Compatibility Matrix

/// Compatibility matrix: device type × platform version
public struct PlatformCompatibilityMatrix: Sendable, Codable, Equatable {
    /// Matrix entries: [DeviceType: [PlatformVersion: CompatibilityStatus]]
    public let entries: [DeviceType: [String: CompatibilityStatus]]
    
    /// Overall compatibility score (0.0 - 1.0)
    public var overallScore: Double {
        var totalScore = 0.0
        var count = 0
        
        for (_, versionMap) in entries {
            for (_, status) in versionMap {
                totalScore += status.score
                count += 1
            }
        }
        
        return count > 0 ? totalScore / Double(count) : 0.0
    }
    
    public init(entries: [DeviceType: [String: CompatibilityStatus]]) {
        self.entries = entries
    }
    
    /// Build matrix from reports
    public static func build(from reports: [PlatformReport]) -> PlatformCompatibilityMatrix {
        var entries: [DeviceType: [String: [PlatformReport]]] = [:]
        
        // Group by device type and platform version
        for report in reports {
            let versionKey = report.platformVersion.majorMinorVersion
            entries[report.deviceType, default: [:]][versionKey, default: []].append(report)
        }
        
        // Convert to compatibility status
        var matrix: [DeviceType: [String: CompatibilityStatus]] = [:]
        
        for (deviceType, versionMap) in entries {
            var deviceMatrix: [String: CompatibilityStatus] = [:]
            
            for (version, versionReports) in versionMap {
                let successCount = versionReports.filter { $0.success }.count
                let totalCount = versionReports.count
                let successRate = Double(successCount) / Double(totalCount)
                
                let status: CompatibilityStatus
                if successRate >= 0.95 {
                    status = .fullSupport(successRate: successRate, reportCount: totalCount)
                } else if successRate >= 0.70 {
                    status = .partialSupport(successRate: successRate, reportCount: totalCount)
                } else if successRate > 0 {
                    status = .knownIssues(successRate: successRate, reportCount: totalCount)
                } else {
                    status = .unsupported(reportCount: totalCount)
                }
                
                deviceMatrix[version] = status
            }
            
            matrix[deviceType] = deviceMatrix
        }
        
        return PlatformCompatibilityMatrix(entries: matrix)
    }
    
    /// Get compatibility for specific device and platform
    public func compatibility(device: DeviceType, platform: PlatformVersion) -> CompatibilityStatus? {
        entries[device]?[platform.majorMinorVersion]
    }
    
    /// Get best platform version for a device
    public func bestPlatform(for device: DeviceType) -> String? {
        guard let versions = entries[device] else { return nil }
        return versions.max(by: { $0.value.score < $1.value.score })?.key
    }
    
    /// Get problematic device/platform combinations
    public func problematicCombinations() -> [(DeviceType, String, CompatibilityStatus)] {
        var problems: [(DeviceType, String, CompatibilityStatus)] = []
        
        for (device, versions) in entries {
            for (version, status) in versions {
                if case .knownIssues = status {
                    problems.append((device, version, status))
                } else if case .unsupported = status {
                    problems.append((device, version, status))
                }
            }
        }
        
        return problems.sorted { $0.2.score < $1.2.score }
    }
}

/// Compatibility status for a device/platform combination
public enum CompatibilityStatus: Sendable, Codable, Equatable {
    case fullSupport(successRate: Double, reportCount: Int)
    case partialSupport(successRate: Double, reportCount: Int)
    case knownIssues(successRate: Double, reportCount: Int)
    case unsupported(reportCount: Int)
    case untested
    
    /// Numeric score for comparison
    public var score: Double {
        switch self {
        case .fullSupport(let rate, _): return rate
        case .partialSupport(let rate, _): return rate
        case .knownIssues(let rate, _): return rate
        case .unsupported: return 0.0
        case .untested: return 0.5 // Neutral
        }
    }
    
    /// Report count
    public var reportCount: Int {
        switch self {
        case .fullSupport(_, let count): return count
        case .partialSupport(_, let count): return count
        case .knownIssues(_, let count): return count
        case .unsupported(let count): return count
        case .untested: return 0
        }
    }
}

// MARK: - Device Model Detection

/// Detect device model from identifier
public struct DeviceModelDetector: Sendable {
    /// Known iPhone models
    public static let iPhoneModels: [String: String] = [
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone14,5": "iPhone 13",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone13,2": "iPhone 12",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max"
    ]
    
    /// Detect model name from identifier
    public static func modelName(for identifier: String) -> String {
        if let name = iPhoneModels[identifier] {
            return name
        }
        
        // Generic parsing
        if identifier.hasPrefix("iPhone") {
            return "iPhone (Unknown Model)"
        }
        if identifier.hasPrefix("iPad") {
            return "iPad (Unknown Model)"
        }
        if identifier.hasPrefix("Watch") {
            return "Apple Watch (Unknown Model)"
        }
        
        return identifier
    }
}

// MARK: - Platform Recommendations

/// Generate recommendations based on platform analysis
public struct PlatformRecommendations: Sendable {
    /// Analyze and generate recommendations
    public static func generate(
        from result: PlatformCorrelationResult,
        matrix: PlatformCompatibilityMatrix
    ) -> [PlatformRecommendation] {
        var recommendations: [PlatformRecommendation] = []
        
        // Check for regressions
        for comparison in result.comparisons {
            if comparison.isRegression {
                recommendations.append(PlatformRecommendation(
                    type: .avoidVersion,
                    version: comparison.toVersion,
                    reason: "Regression detected: \(String(format: "%.1f%%", comparison.successRateDelta * 100)) drop in success rate",
                    priority: .high
                ))
            }
        }
        
        // Recommend best version
        if let best = result.bestVersion {
            recommendations.append(PlatformRecommendation(
                type: .recommendVersion,
                version: best,
                reason: "Highest success rate among tested versions",
                priority: .medium
            ))
        }
        
        // Flag problematic combinations
        for (device, version, status) in matrix.problematicCombinations() {
            if case .unsupported = status {
                recommendations.append(PlatformRecommendation(
                    type: .deviceIssue,
                    version: PlatformVersion(string: version) ?? .unknown,
                    reason: "\(device.rawValue) is unsupported on \(version)",
                    priority: .high
                ))
            }
        }
        
        // Include known issues
        for issue in result.platformIssues {
            recommendations.append(PlatformRecommendation(
                type: .knownIssue,
                version: issue.affectedVersions.minimum,
                reason: issue.description,
                priority: issue.severity == .critical ? .critical : .high
            ))
        }
        
        return recommendations.sorted { $0.priority.rawValue < $1.priority.rawValue }
    }
}

/// Platform recommendation
public struct PlatformRecommendation: Sendable, Codable, Equatable {
    public let type: RecommendationType
    public let version: PlatformVersion
    public let reason: String
    public let priority: RecommendationPriority
    
    public init(type: RecommendationType, version: PlatformVersion, reason: String, priority: RecommendationPriority) {
        self.type = type
        self.version = version
        self.reason = reason
        self.priority = priority
    }
}

/// Recommendation type
public enum RecommendationType: String, Sendable, Codable, CaseIterable {
    case recommendVersion
    case avoidVersion
    case deviceIssue
    case knownIssue
    case updateRequired
}

/// Recommendation priority
public enum RecommendationPriority: Int, Sendable, Codable, CaseIterable {
    case critical = 0
    case high = 1
    case medium = 2
    case low = 3
}
