// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DeviceCompatibilityMatrix.swift
// T1PalCompatKit
//
// Device compatibility matrix for tracking results across devices and iOS versions.
// Trace: PRD-006 REQ-COMPAT-004
//
// Enables regression detection by comparing current results to historical baseline.

import Foundation

// MARK: - Device Profile

/// Unique identifier for a device/OS combination
public struct DeviceProfile: Hashable, Codable, Sendable {
    /// Device model identifier (e.g., "iPhone14,5" for iPhone 13)
    public let modelIdentifier: String
    
    /// Human-readable model name (e.g., "iPhone 13")
    public let modelName: String
    
    /// iOS version (e.g., "17.2")
    public let osVersion: String
    
    /// App version (e.g., "1.0.0")
    public let appVersion: String
    
    /// Build number
    public let buildNumber: String
    
    public init(
        modelIdentifier: String,
        modelName: String,
        osVersion: String,
        appVersion: String,
        buildNumber: String
    ) {
        self.modelIdentifier = modelIdentifier
        self.modelName = modelName
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.buildNumber = buildNumber
    }
    
    /// Create profile from current device
    public static var current: DeviceProfile {
        #if os(iOS)
        return DeviceProfile(
            modelIdentifier: currentModelIdentifier(),
            modelName: currentModelName(),
            osVersion: currentOSVersion(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        )
        #else
        return DeviceProfile(
            modelIdentifier: "Linux",
            modelName: "Linux",
            osVersion: linuxVersion(),
            appVersion: "1.0.0",
            buildNumber: "1"
        )
        #endif
    }
    
    /// Key for grouping by device model
    public var modelKey: String {
        modelIdentifier
    }
    
    /// Key for grouping by OS version
    public var osKey: String {
        osVersion
    }
    
    /// Combined key for unique profile
    public var profileKey: String {
        "\(modelIdentifier)_\(osVersion)_\(appVersion)"
    }
    
    #if os(iOS)
    private static func currentModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    
    private static func currentModelName() -> String {
        // Map common identifiers to names
        let identifier = currentModelIdentifier()
        let modelMap: [String: String] = [
            "iPhone14,5": "iPhone 13",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max"
        ]
        return modelMap[identifier] ?? identifier
    }
    
    private static func currentOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    #else
    private static func linuxVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }
    #endif
}

// MARK: - Compatibility Snapshot

/// A snapshot of compatibility results at a point in time
public struct CompatibilitySnapshot: Codable, Sendable {
    /// Unique identifier for this snapshot
    public let snapshotId: String
    
    /// When this snapshot was captured
    public let capturedAt: Date
    
    /// Device profile for this snapshot
    public let profile: DeviceProfile
    
    /// Summary of test results by category
    public let categoryResults: [CategoryResult]
    
    /// Overall pass/fail counts
    public let summary: SnapshotSummary
    
    public init(
        snapshotId: String = UUID().uuidString,
        capturedAt: Date = Date(),
        profile: DeviceProfile,
        categoryResults: [CategoryResult],
        summary: SnapshotSummary
    ) {
        self.snapshotId = snapshotId
        self.capturedAt = capturedAt
        self.profile = profile
        self.categoryResults = categoryResults
        self.summary = summary
    }
    
    /// Create snapshot from capability results
    public static func from(
        results: [CapabilityResult],
        profile: DeviceProfile = .current
    ) -> CompatibilitySnapshot {
        // Group by category
        var categoryMap: [CapabilityCategory: [CapabilityResult]] = [:]
        for result in results {
            categoryMap[result.category, default: []].append(result)
        }
        
        var categoryResultsList: [CategoryResult] = []
        for (category, catResults) in categoryMap {
            let passed = catResults.filter { $0.status == .passed }.count
            let failed = catResults.filter { $0.status == .failed }.count
            let warnings = catResults.filter { $0.status == .warning }.count
            let unsupported = catResults.filter { $0.status == .unsupported }.count
            
            let result = CategoryResult(
                category: category.rawValue,
                categoryName: category.displayName,
                passed: passed,
                failed: failed,
                warnings: warnings,
                unsupported: unsupported,
                total: catResults.count
            )
            categoryResultsList.append(result)
        }
        categoryResultsList.sort { $0.category < $1.category }
        
        let totalPassed = results.filter { $0.status == .passed }.count
        let totalFailed = results.filter { $0.status == .failed }.count
        let totalWarnings = results.filter { $0.status == .warning }.count
        
        let summary = SnapshotSummary(
            totalTests: results.count,
            passed: totalPassed,
            failed: totalFailed,
            warnings: totalWarnings,
            passRate: results.isEmpty ? 0 : Double(totalPassed) / Double(results.count)
        )
        
        return CompatibilitySnapshot(
            profile: profile,
            categoryResults: categoryResultsList,
            summary: summary
        )
    }
}

/// Results for a single category
public struct CategoryResult: Codable, Sendable {
    public let category: String
    public let categoryName: String
    public let passed: Int
    public let failed: Int
    public let warnings: Int
    public let unsupported: Int
    public let total: Int
    
    public var passRate: Double {
        let applicable = total - unsupported
        guard applicable > 0 else { return 1.0 }
        return Double(passed) / Double(applicable)
    }
}

/// Summary statistics for a snapshot
public struct SnapshotSummary: Codable, Sendable {
    public let totalTests: Int
    public let passed: Int
    public let failed: Int
    public let warnings: Int
    public let passRate: Double
    
    public init(
        totalTests: Int,
        passed: Int,
        failed: Int,
        warnings: Int,
        passRate: Double
    ) {
        self.totalTests = totalTests
        self.passed = passed
        self.failed = failed
        self.warnings = warnings
        self.passRate = passRate
    }
}

// MARK: - Regression Detection

/// Represents a detected regression between snapshots
public struct Regression: Sendable {
    /// Test that regressed
    public let testId: String
    
    /// Test name
    public let testName: String
    
    /// Category
    public let category: String
    
    /// Previous status
    public let previousStatus: CapabilityStatus
    
    /// Current status
    public let currentStatus: CapabilityStatus
    
    /// Severity of the regression
    public let severity: RegressionSeverity
    
    public init(
        testId: String,
        testName: String,
        category: String,
        previousStatus: CapabilityStatus,
        currentStatus: CapabilityStatus
    ) {
        self.testId = testId
        self.testName = testName
        self.category = category
        self.previousStatus = previousStatus
        self.currentStatus = currentStatus
        self.severity = Self.calculateSeverity(from: previousStatus, to: currentStatus)
    }
    
    private static func calculateSeverity(
        from previous: CapabilityStatus,
        to current: CapabilityStatus
    ) -> RegressionSeverity {
        switch (previous, current) {
        case (.passed, .failed):
            return .critical
        case (.passed, .warning):
            return .moderate
        case (.warning, .failed):
            return .high
        default:
            return .low
        }
    }
}

/// Severity level for regressions
public enum RegressionSeverity: String, Sendable, CaseIterable {
    case critical = "critical"  // passed → failed
    case high = "high"          // warning → failed
    case moderate = "moderate"  // passed → warning
    case low = "low"            // other changes
    
    public var displayName: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .moderate: return "Moderate"
        case .low: return "Low"
        }
    }
    
    public var indicator: String {
        switch self {
        case .critical: return "🔴"
        case .high: return "🟠"
        case .moderate: return "🟡"
        case .low: return "🟢"
        }
    }
}

/// Result of comparing two snapshots
public struct ComparisonResult: Sendable {
    /// Baseline snapshot
    public let baseline: CompatibilitySnapshot
    
    /// Current snapshot
    public let current: CompatibilitySnapshot
    
    /// Detected regressions
    public let regressions: [Regression]
    
    /// Improvements (tests that got better)
    public let improvements: [String]
    
    /// New tests (not in baseline)
    public let newTests: [String]
    
    /// Removed tests (in baseline but not current)
    public let removedTests: [String]
    
    public var hasRegressions: Bool {
        !regressions.isEmpty
    }
    
    public var criticalRegressions: [Regression] {
        regressions.filter { $0.severity == .critical }
    }
    
    public init(
        baseline: CompatibilitySnapshot,
        current: CompatibilitySnapshot,
        regressions: [Regression],
        improvements: [String],
        newTests: [String],
        removedTests: [String]
    ) {
        self.baseline = baseline
        self.current = current
        self.regressions = regressions
        self.improvements = improvements
        self.newTests = newTests
        self.removedTests = removedTests
    }
}

// MARK: - Compatibility Matrix

/// Main compatibility matrix for tracking and comparing results
public actor CompatibilityMatrix {
    /// Storage for snapshots
    private var snapshots: [String: CompatibilitySnapshot] = [:]
    
    /// Index by device model
    private var byModel: [String: [String]] = [:]
    
    /// Index by OS version
    private var byOSVersion: [String: [String]] = [:]
    
    public init() {}
    
    /// Add a snapshot to the matrix
    public func add(_ snapshot: CompatibilitySnapshot) {
        snapshots[snapshot.snapshotId] = snapshot
        
        // Index by model
        byModel[snapshot.profile.modelKey, default: []].append(snapshot.snapshotId)
        
        // Index by OS version
        byOSVersion[snapshot.profile.osKey, default: []].append(snapshot.snapshotId)
    }
    
    /// Get all snapshots for a device model
    public func snapshots(forModel model: String) -> [CompatibilitySnapshot] {
        let ids = byModel[model] ?? []
        return ids.compactMap { snapshots[$0] }
    }
    
    /// Get all snapshots for an OS version
    public func snapshots(forOSVersion version: String) -> [CompatibilitySnapshot] {
        let ids = byOSVersion[version] ?? []
        return ids.compactMap { snapshots[$0] }
    }
    
    /// Get latest snapshot for current device
    public func latestSnapshot(for profile: DeviceProfile) -> CompatibilitySnapshot? {
        let matching = snapshots.values.filter { 
            $0.profile.modelKey == profile.modelKey && 
            $0.profile.osKey == profile.osKey 
        }
        return matching.max { $0.capturedAt < $1.capturedAt }
    }
    
    /// Get all unique device models
    public func allModels() -> [String] {
        Array(byModel.keys).sorted()
    }
    
    /// Get all unique OS versions
    public func allOSVersions() -> [String] {
        Array(byOSVersion.keys).sorted()
    }
    
    /// Clear all snapshots
    public func clear() {
        snapshots.removeAll()
        byModel.removeAll()
        byOSVersion.removeAll()
    }
    
    /// Compare two snapshots for regressions
    public func compare(
        baseline: CompatibilitySnapshot,
        current: CompatibilitySnapshot
    ) -> ComparisonResult {
        // This is a simplified comparison based on category results
        // A full implementation would compare individual test results
        
        var regressions: [Regression] = []
        var improvements: [String] = []
        
        let baselineCategories = Dictionary(
            uniqueKeysWithValues: baseline.categoryResults.map { ($0.category, $0) }
        )
        let currentCategories = Dictionary(
            uniqueKeysWithValues: current.categoryResults.map { ($0.category, $0) }
        )
        
        for (category, currentResult) in currentCategories {
            if let baselineResult = baselineCategories[category] {
                // Check for regressions (more failures)
                if currentResult.failed > baselineResult.failed {
                    regressions.append(Regression(
                        testId: category,
                        testName: currentResult.categoryName,
                        category: category,
                        previousStatus: .passed,
                        currentStatus: .failed
                    ))
                }
                
                // Check for improvements (fewer failures)
                if currentResult.failed < baselineResult.failed {
                    improvements.append(category)
                }
            }
        }
        
        let newTests = currentCategories.keys.filter { !baselineCategories.keys.contains($0) }
        let removedTests = baselineCategories.keys.filter { !currentCategories.keys.contains($0) }
        
        return ComparisonResult(
            baseline: baseline,
            current: current,
            regressions: regressions,
            improvements: Array(improvements),
            newTests: Array(newTests),
            removedTests: Array(removedTests)
        )
    }
}

// MARK: - Persistence

/// Storage for compatibility history
public actor CompatibilityHistoryStore {
    /// File URL for persistent storage
    private let storageURL: URL?
    
    /// In-memory history
    private var history: [CompatibilitySnapshot] = []
    
    /// Maximum snapshots to keep per device
    public let maxSnapshotsPerDevice: Int
    
    public init(storageURL: URL? = nil, maxSnapshotsPerDevice: Int = 10) {
        self.storageURL = storageURL
        self.maxSnapshotsPerDevice = maxSnapshotsPerDevice
    }
    
    /// Save a snapshot
    public func save(_ snapshot: CompatibilitySnapshot) {
        history.append(snapshot)
        
        // Trim old snapshots for this device
        let profileKey = snapshot.profile.profileKey
        let matching = history.filter { $0.profile.profileKey == profileKey }
        if matching.count > maxSnapshotsPerDevice {
            let toRemove = matching.sorted { $0.capturedAt < $1.capturedAt }
                .prefix(matching.count - maxSnapshotsPerDevice)
            history.removeAll { snapshot in
                toRemove.contains { $0.snapshotId == snapshot.snapshotId }
            }
        }
        
        // Persist to disk if URL provided
        if let url = storageURL {
            persistToDisk(url: url)
        }
    }
    
    /// Get history for a device profile
    public func history(for profile: DeviceProfile) -> [CompatibilitySnapshot] {
        history.filter { $0.profile.profileKey == profile.profileKey }
            .sorted { $0.capturedAt > $1.capturedAt }
    }
    
    /// Get latest snapshot for a profile
    public func latest(for profile: DeviceProfile) -> CompatibilitySnapshot? {
        history(for: profile).first
    }
    
    /// Get all snapshots
    public func allSnapshots() -> [CompatibilitySnapshot] {
        history.sorted { $0.capturedAt > $1.capturedAt }
    }
    
    /// Clear history
    public func clear() {
        history.removeAll()
    }
    
    private func persistToDisk(url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            try data.write(to: url)
        } catch {
            // Log error but don't throw - persistence is best-effort
        }
    }
    
    /// Load from disk
    public func loadFromDisk() {
        guard let url = storageURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            history = try decoder.decode([CompatibilitySnapshot].self, from: data)
        } catch {
            // File might not exist yet, that's OK
        }
    }
}

// MARK: - Matrix Export

/// Export format for compatibility matrix
public struct MatrixExport: Codable, Sendable {
    public let exportedAt: Date
    public let snapshotCount: Int
    public let models: [String]
    public let osVersions: [String]
    public let snapshots: [CompatibilitySnapshot]
    
    public init(
        exportedAt: Date = Date(),
        snapshotCount: Int,
        models: [String],
        osVersions: [String],
        snapshots: [CompatibilitySnapshot]
    ) {
        self.exportedAt = exportedAt
        self.snapshotCount = snapshotCount
        self.models = models
        self.osVersions = osVersions
        self.snapshots = snapshots
    }
}

/// Export the matrix to JSON
public func exportMatrix(_ matrix: CompatibilityMatrix) async -> Data? {
    let models = await matrix.allModels()
    let osVersions = await matrix.allOSVersions()
    
    var allSnapshots: [CompatibilitySnapshot] = []
    for model in models {
        allSnapshots.append(contentsOf: await matrix.snapshots(forModel: model))
    }
    
    let export = MatrixExport(
        snapshotCount: allSnapshots.count,
        models: models,
        osVersions: osVersions,
        snapshots: allSnapshots
    )
    
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    
    return try? encoder.encode(export)
}
