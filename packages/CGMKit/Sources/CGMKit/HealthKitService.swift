// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// HealthKitService.swift - High-level HealthKit integration service
// Part of CGMKit
// Trace: HEALTH-001

import Foundation
import T1PalCore

#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - HealthKit Service

/// High-level service for HealthKit glucose read/write operations
/// Provides simplified API for common glucose export/import tasks
public actor HealthKitService {
    
    // MARK: - Singleton
    
    public static let shared = HealthKitService()
    
    // MARK: - Configuration
    
    public struct Configuration: Sendable {
        /// Auto-export new readings to HealthKit
        public var autoExportEnabled: Bool
        
        /// Read glucose from HealthKit as a data source
        public var readEnabled: Bool
        
        /// App bundle identifier for HealthKit
        public var bundleIdentifier: String
        
        public init(
            autoExportEnabled: Bool = false,
            readEnabled: Bool = true,
            bundleIdentifier: String = "com.t1pal.mobile"
        ) {
            self.autoExportEnabled = autoExportEnabled
            self.readEnabled = readEnabled
            self.bundleIdentifier = bundleIdentifier
        }
        
        public static let `default` = Configuration()
    }
    
    // MARK: - State
    
    private var config: Configuration
    private var isAuthorized: Bool = false
    private var lastExportDate: Date?
    private var exportCount: Int = 0
    
    #if canImport(HealthKit)
    private let healthStore: HKHealthStore?
    private let glucoseType: HKQuantityType?
    #endif
    
    // MARK: - Initialization
    
    /// Initialize HealthKitService.
    /// Note: HKHealthStore is thread-safe and can be created on any thread (unlike CBCentralManager).
    /// Trace: ARCH-IMPL-005 (verified safe)
    public init(configuration: Configuration = .default) {
        self.config = configuration
        
        #if canImport(HealthKit)
        if HKHealthStore.isHealthDataAvailable() {
            self.healthStore = HKHealthStore()
            self.glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)
        } else {
            self.healthStore = nil
            self.glucoseType = nil
        }
        #endif
    }
    
    // MARK: - Authorization
    
    /// Check if HealthKit is available
    public var isAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }
    
    /// Request authorization for glucose read/write
    public func requestAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard let healthStore = healthStore,
              let glucoseType = glucoseType else {
            return false
        }
        
        do {
            try await healthStore.requestAuthorization(
                toShare: [glucoseType],
                read: [glucoseType]
            )
            isAuthorized = true
            return true
        } catch {
            isAuthorized = false
            return false
        }
        #else
        return false
        #endif
    }
    
    /// Check current authorization status
    public func checkAuthorization() -> HealthKitAuthorizationStatus {
        #if canImport(HealthKit)
        guard let healthStore = healthStore,
              let glucoseType = glucoseType else {
            return .unavailable
        }
        
        let status = healthStore.authorizationStatus(for: glucoseType)
        switch status {
        case .notDetermined:
            return .notDetermined
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        @unknown default:
            return .notDetermined
        }
        #else
        return .unavailable
        #endif
    }
    
    // MARK: - Export (Write to HealthKit)
    
    /// Export a single glucose reading to HealthKit
    public func exportReading(_ reading: GlucoseReading) async -> ExportResult {
        #if canImport(HealthKit)
        guard let healthStore = healthStore,
              let glucoseType = glucoseType else {
            return .failed(.unavailable)
        }
        
        if !isAuthorized {
            let authorized = await requestAuthorization()
            guard authorized else {
                return .failed(.unauthorized)
            }
        }
        
        // Check for duplicate
        let isDuplicate = await hasDuplicate(at: reading.timestamp)
        if isDuplicate {
            return .skipped(.duplicate)
        }
        
        // Create sample
        let unit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        let quantity = HKQuantity(unit: unit, doubleValue: reading.glucose)
        let sample = HKQuantitySample(
            type: glucoseType,
            quantity: quantity,
            start: reading.timestamp,
            end: reading.timestamp
        )
        
        do {
            try await healthStore.save(sample)
            exportCount += 1
            lastExportDate = Date()
            return .success(reading.timestamp)
        } catch {
            return .failed(.writeError(error.localizedDescription))
        }
        #else
        return .failed(.unavailable)
        #endif
    }
    
    /// Export multiple glucose readings to HealthKit
    public func exportReadings(_ readings: [GlucoseReading]) async -> BatchExportResult {
        var results: [ExportResult] = []
        
        for reading in readings {
            let result = await exportReading(reading)
            results.append(result)
        }
        
        return BatchExportResult(results: results)
    }
    
    /// Export readings from a data source for a time range
    public func exportFromSource(
        _ source: any GlucoseDataSource,
        from startDate: Date,
        to endDate: Date
    ) async throws -> BatchExportResult {
        let readings = try await source.fetchReadings(from: startDate, to: endDate)
        return await exportReadings(readings)
    }
    
    // MARK: - Import (Read from HealthKit)
    
    /// Read glucose readings from HealthKit
    public func readReadings(
        from startDate: Date,
        to endDate: Date,
        limit: Int = 500
    ) async throws -> [GlucoseReading] {
        #if canImport(HealthKit)
        guard let healthStore = healthStore,
              let glucoseType = glucoseType else {
            throw HealthKitError.unavailable
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: glucoseType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let readings = (samples as? [HKQuantitySample])?.map { sample -> GlucoseReading in
                    let unit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
                    let value = sample.quantity.doubleValue(for: unit)
                    return GlucoseReading(
                        glucose: value,
                        timestamp: sample.startDate,
                        trend: .flat,
                        source: "HealthKit"
                    )
                } ?? []
                
                continuation.resume(returning: readings)
            }
            
            healthStore.execute(query)
        }
        #else
        throw HealthKitError.unavailable
        #endif
    }
    
    /// Get the most recent glucose reading from HealthKit
    public func latestReading() async throws -> GlucoseReading? {
        let readings = try await readReadings(
            from: Date().addingTimeInterval(-3600),
            to: Date(),
            limit: 1
        )
        return readings.first
    }
    
    // MARK: - Statistics
    
    /// Get export statistics
    public func statistics() -> ExportStatistics {
        ExportStatistics(
            totalExported: exportCount,
            lastExportDate: lastExportDate,
            isAuthorized: isAuthorized,
            autoExportEnabled: config.autoExportEnabled
        )
    }
    
    // MARK: - Private Helpers
    
    #if canImport(HealthKit)
    private func hasDuplicate(at timestamp: Date) async -> Bool {
        guard let healthStore = healthStore,
              let glucoseType = glucoseType else {
            return false
        }
        
        let window: TimeInterval = 60  // 1 minute window
        let predicate = HKQuery.predicateForSamples(
            withStart: timestamp.addingTimeInterval(-window),
            end: timestamp.addingTimeInterval(window),
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: glucoseType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                continuation.resume(returning: !(samples?.isEmpty ?? true))
            }
            
            healthStore.execute(query)
        }
    }
    #endif
}

// MARK: - Supporting Types

/// HealthKit authorization status
public enum HealthKitAuthorizationStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

/// Result of a single export operation
public enum ExportResult: Sendable {
    case success(Date)
    case skipped(SkipReason)
    case failed(FailureReason)
    
    public enum SkipReason: Sendable {
        case duplicate
        case tooOld
    }
    
    public enum FailureReason: Sendable {
        case unavailable
        case unauthorized
        case writeError(String)
    }
    
    public var wasSuccessful: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Result of a batch export operation
public struct BatchExportResult: Sendable {
    public let results: [ExportResult]
    
    public var successCount: Int {
        results.filter { $0.wasSuccessful }.count
    }
    
    public var skipCount: Int {
        results.filter {
            if case .skipped = $0 { return true }
            return false
        }.count
    }
    
    public var failCount: Int {
        results.filter {
            if case .failed = $0 { return true }
            return false
        }.count
    }
    
    public var summary: String {
        "Exported: \(successCount), Skipped: \(skipCount), Failed: \(failCount)"
    }
}

/// Export statistics
public struct ExportStatistics: Sendable {
    public let totalExported: Int
    public let lastExportDate: Date?
    public let isAuthorized: Bool
    public let autoExportEnabled: Bool
}

/// HealthKit errors
public enum HealthKitError: Error, LocalizedError, Sendable {
    case unavailable
    case unauthorized
    case queryFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HealthKit is not available on this device"
        case .unauthorized:
            return "HealthKit access not authorized"
        case .queryFailed(let message):
            return "HealthKit query failed: \(message)"
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance (COMPL-DUP-004)

extension HealthKitError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .storage }
    
    public var code: String {
        switch self {
        case .unavailable: return "HK-UNAVAIL-001"
        case .unauthorized: return "HK-AUTH-001"
        case .queryFailed: return "HK-QUERY-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .unavailable: return .warning
        case .unauthorized: return .error
        case .queryFailed: return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .unavailable: return .none
        case .unauthorized: return .reauthenticate
        case .queryFailed: return .retry
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "HealthKit error"
    }
}
