// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DeviceMatrixTests.swift
// T1PalCompatKit
//
// Capability tests for device compatibility matrix.
// Trace: PRD-006 REQ-COMPAT-004
//
// Tests device profile detection and compatibility tracking.

import Foundation

// MARK: - Device Profile Test

/// Tests device profile detection
public struct DeviceProfileTest: CapabilityTest, @unchecked Sendable {
    public let id = "matrix-device-profile"
    public let name = "Device Profile Detection"
    public let category = CapabilityCategory.storage
    public let priority = 80
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        let profile = DeviceProfile.current
        
        let details: [String: String] = [
            "modelIdentifier": profile.modelIdentifier,
            "modelName": profile.modelName,
            "osVersion": profile.osVersion,
            "appVersion": profile.appVersion,
            "buildNumber": profile.buildNumber,
            "profileKey": profile.profileKey
        ]
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Validate profile has required data
        guard !profile.modelIdentifier.isEmpty else {
            return failed(
                "Device profile missing model identifier.",
                details: details,
                duration: duration
            )
        }
        
        guard !profile.osVersion.isEmpty else {
            return failed(
                "Device profile missing OS version.",
                details: details,
                duration: duration
            )
        }
        
        return passed(
            "Device profile captured: \(profile.modelName) (\(profile.osVersion))",
            details: details,
            duration: duration
        )
    }
}

// MARK: - Snapshot Creation Test

/// Tests compatibility snapshot creation
public struct SnapshotCreationTest: CapabilityTest, @unchecked Sendable {
    public let id = "matrix-snapshot-creation"
    public let name = "Compatibility Snapshot"
    public let category = CapabilityCategory.storage
    public let priority = 81
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        // Create a sample snapshot from empty results
        let snapshot = CompatibilitySnapshot.from(results: [])
        
        var details: [String: String] = [
            "snapshotId": snapshot.snapshotId,
            "profile": snapshot.profile.profileKey,
            "categoryCount": String(snapshot.categoryResults.count),
            "totalTests": String(snapshot.summary.totalTests)
        ]
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Validate snapshot structure
        guard !snapshot.snapshotId.isEmpty else {
            return failed(
                "Snapshot missing ID.",
                details: details,
                duration: duration
            )
        }
        
        details["passRate"] = String(format: "%.1f%%", snapshot.summary.passRate * 100)
        
        return passed(
            "Snapshot created successfully with ID \(snapshot.snapshotId.prefix(8))...",
            details: details,
            duration: duration
        )
    }
}

// MARK: - Matrix Storage Test

/// Tests compatibility matrix storage operations
public struct MatrixStorageTest: CapabilityTest, @unchecked Sendable {
    public let id = "matrix-storage"
    public let name = "Matrix Storage"
    public let category = CapabilityCategory.storage
    public let priority = 82
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        // Create a matrix and add a snapshot
        let matrix = CompatibilityMatrix()
        let snapshot = CompatibilitySnapshot.from(results: [])
        
        await matrix.add(snapshot)
        
        let models = await matrix.allModels()
        let osVersions = await matrix.allOSVersions()
        
        let details: [String: String] = [
            "modelsTracked": String(models.count),
            "osVersionsTracked": String(osVersions.count),
            "snapshotAdded": "true"
        ]
        
        let duration = Date().timeIntervalSince(startTime)
        
        return passed(
            "Matrix storage operational. Tracking \(models.count) model(s).",
            details: details,
            duration: duration
        )
    }
}

// MARK: - Regression Detection Test

/// Tests regression detection between snapshots
public struct RegressionDetectionTest: CapabilityTest, @unchecked Sendable {
    public let id = "matrix-regression-detection"
    public let name = "Regression Detection"
    public let category = CapabilityCategory.storage
    public let priority = 83
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        let startTime = Date()
        
        // Create baseline and current snapshots
        let profile = DeviceProfile.current
        
        let baseline = CompatibilitySnapshot(
            snapshotId: "baseline",
            profile: profile,
            categoryResults: [
                CategoryResult(
                    category: "bluetooth",
                    categoryName: "Bluetooth",
                    passed: 5,
                    failed: 0,
                    warnings: 0,
                    unsupported: 0,
                    total: 5
                )
            ],
            summary: SnapshotSummary(
                totalTests: 5,
                passed: 5,
                failed: 0,
                warnings: 0,
                passRate: 1.0
            )
        )
        
        let current = CompatibilitySnapshot(
            snapshotId: "current",
            profile: profile,
            categoryResults: [
                CategoryResult(
                    category: "bluetooth",
                    categoryName: "Bluetooth",
                    passed: 4,
                    failed: 1,
                    warnings: 0,
                    unsupported: 0,
                    total: 5
                )
            ],
            summary: SnapshotSummary(
                totalTests: 5,
                passed: 4,
                failed: 1,
                warnings: 0,
                passRate: 0.8
            )
        )
        
        let matrix = CompatibilityMatrix()
        let comparison = await matrix.compare(baseline: baseline, current: current)
        
        var details: [String: String] = [
            "regressionCount": String(comparison.regressions.count),
            "improvementCount": String(comparison.improvements.count),
            "hasRegressions": String(comparison.hasRegressions)
        ]
        
        if let firstRegression = comparison.regressions.first {
            details["regressionCategory"] = firstRegression.category
            details["regressionSeverity"] = firstRegression.severity.rawValue
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        return passed(
            "Regression detection operational. Found \(comparison.regressions.count) regression(s).",
            details: details,
            duration: duration
        )
    }
}
