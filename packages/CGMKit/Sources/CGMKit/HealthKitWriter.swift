// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HealthKitWriter.swift
// CGMKit
//
// Writes glucose readings to HealthKit from any CGM source.
// Trace: PRD-004, REQ-HK-001, APP-CGM-003

import Foundation
import T1PalCore

#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - Write Configuration

/// Configuration for HealthKit writing
public struct HealthKitWriteConfig: Codable, Sendable {
    /// Enable duplicate detection before writing (default true)
    public let enableDuplicateDetection: Bool
    
    /// Window for duplicate detection in seconds (default 2 minutes)
    public let duplicateWindowSeconds: TimeInterval
    
    /// Bundle identifier suffix for source tracking (default "T1Pal")
    public let sourceIdentifier: String
    
    /// Maximum batch size for batch writes (default 100)
    public let maxBatchSize: Int
    
    public init(
        enableDuplicateDetection: Bool = true,
        duplicateWindowSeconds: TimeInterval = 120,
        sourceIdentifier: String = "T1Pal",
        maxBatchSize: Int = 100
    ) {
        self.enableDuplicateDetection = enableDuplicateDetection
        self.duplicateWindowSeconds = duplicateWindowSeconds
        self.sourceIdentifier = sourceIdentifier
        self.maxBatchSize = maxBatchSize
    }
    
    public static let `default` = HealthKitWriteConfig()
}

// MARK: - Write Result

/// Result of a HealthKit write operation
public enum HealthKitWriteResult: Sendable, Equatable {
    /// Successfully wrote glucose sample
    case success(timestamp: Date, glucose: Double)
    
    /// Skipped - duplicate sample exists
    case skippedDuplicate(existingTimestamp: Date)
    
    /// Failed - not authorized to write
    case failedUnauthorized
    
    /// Failed - HealthKit unavailable
    case failedUnavailable
    
    /// Failed - error during write
    case failedError(String)
    
    public var wasSuccessful: Bool {
        if case .success = self { return true }
        return false
    }
    
    public var description: String {
        switch self {
        case .success(let timestamp, let glucose):
            return "Wrote \(Int(glucose)) mg/dL at \(timestamp)"
        case .skippedDuplicate(let existing):
            return "Skipped - duplicate at \(existing)"
        case .failedUnauthorized:
            return "Failed - not authorized"
        case .failedUnavailable:
            return "Failed - HealthKit unavailable"
        case .failedError(let msg):
            return "Failed - \(msg)"
        }
    }
}

/// Result of a batch write operation
public struct HealthKitBatchWriteResult: Sendable {
    public let written: Int
    public let skipped: Int
    public let failed: Int
    public let results: [HealthKitWriteResult]
    
    public init(results: [HealthKitWriteResult]) {
        self.results = results
        self.written = results.filter { $0.wasSuccessful }.count
        self.skipped = results.filter {
            if case .skippedDuplicate = $0 { return true }
            return false
        }.count
        self.failed = results.filter {
            switch $0 {
            case .failedUnauthorized, .failedUnavailable, .failedError:
                return true
            default:
                return false
            }
        }.count
    }
    
    public var summary: String {
        "Written: \(written), Skipped: \(skipped), Failed: \(failed)"
    }
}

// MARK: - Authorization Status

/// HealthKit authorization status for glucose writing
public enum HealthKitWriteAuthStatus: Sendable {
    /// Not yet determined - need to request
    case notDetermined
    
    /// Authorized to write
    case authorized
    
    /// Denied by user
    case denied
    
    /// HealthKit unavailable on this device
    case unavailable
}

// MARK: - HealthKit Writer

/// Service for writing glucose readings to HealthKit
/// Thread-safe actor for managing HealthKit write operations
public actor HealthKitWriter {
    
    private let config: HealthKitWriteConfig
    
    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    private var writeAuthorizationStatus: HealthKitWriteAuthStatus = .notDetermined
    #endif
    
    /// Callback when write completes
    public var onWriteResult: (@Sendable (HealthKitWriteResult) -> Void)?
    
    /// Callback when batch write completes
    public var onBatchWriteResult: (@Sendable (HealthKitBatchWriteResult) -> Void)?
    
    public init(config: HealthKitWriteConfig = .default) {
        self.config = config
    }
    
    // MARK: - Authorization
    
    /// Check current write authorization status
    public func checkAuthorizationStatus() -> HealthKitWriteAuthStatus {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }
        
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
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
    
    /// Request write authorization for glucose samples
    /// - Returns: true if authorized, false otherwise
    public func requestWriteAuthorization() async throws -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            writeAuthorizationStatus = .unavailable
            return false
        }
        
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            writeAuthorizationStatus = .unavailable
            return false
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [glucoseType], read: [glucoseType])
            let status = healthStore.authorizationStatus(for: glucoseType)
            
            if status == .sharingAuthorized {
                writeAuthorizationStatus = .authorized
                return true
            } else {
                writeAuthorizationStatus = .denied
                return false
            }
        } catch {
            writeAuthorizationStatus = .denied
            throw error
        }
        #else
        return false
        #endif
    }
    
    /// Whether write authorization has been granted
    public var isAuthorized: Bool {
        #if canImport(HealthKit)
        return writeAuthorizationStatus == .authorized || checkAuthorizationStatus() == .authorized
        #else
        return false
        #endif
    }
    
    // MARK: - Write Single Sample
    
    /// Write a single glucose reading to HealthKit
    /// - Parameter reading: The glucose reading to write
    /// - Returns: Result of the write operation
    public func write(reading: GlucoseReading) async -> HealthKitWriteResult {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return .failedUnavailable
        }
        
        guard checkAuthorizationStatus() == .authorized else {
            return .failedUnauthorized
        }
        
        // Check for duplicate if enabled
        if config.enableDuplicateDetection {
            if let existingTimestamp = await checkForExistingSample(near: reading.timestamp) {
                let result = HealthKitWriteResult.skippedDuplicate(existingTimestamp: existingTimestamp)
                onWriteResult?(result)
                return result
            }
        }
        
        // Write the sample
        let result = await writeGlucoseSample(reading: reading)
        onWriteResult?(result)
        return result
        #else
        return .failedUnavailable
        #endif
    }
    
    /// Write a glucose value to HealthKit at the specified time
    /// - Parameters:
    ///   - glucose: Glucose value in mg/dL
    ///   - timestamp: Time of the reading
    ///   - source: Source identifier for the reading
    /// - Returns: Result of the write operation
    public func write(glucose: Double, at timestamp: Date, source: String? = nil) async -> HealthKitWriteResult {
        let reading = GlucoseReading(
            glucose: glucose,
            timestamp: timestamp,
            trend: .notComputable,
            source: source ?? config.sourceIdentifier
        )
        return await write(reading: reading)
    }
    
    // MARK: - Batch Write
    
    /// Write multiple glucose readings to HealthKit
    /// - Parameter readings: Array of glucose readings to write
    /// - Returns: Batch result with per-reading status
    public func writeBatch(readings: [GlucoseReading]) async -> HealthKitBatchWriteResult {
        guard !readings.isEmpty else {
            return HealthKitBatchWriteResult(results: [])
        }
        
        // Limit batch size
        let limitedReadings = Array(readings.prefix(config.maxBatchSize))
        
        var results: [HealthKitWriteResult] = []
        
        for reading in limitedReadings {
            let result = await write(reading: reading)
            results.append(result)
        }
        
        let batchResult = HealthKitBatchWriteResult(results: results)
        onBatchWriteResult?(batchResult)
        return batchResult
    }
    
    // MARK: - Private Helpers
    
    #if canImport(HealthKit)
    /// Check if a sample already exists within the duplicate window
    private func checkForExistingSample(near timestamp: Date) async -> Date? {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return nil
        }
        
        let windowStart = timestamp.addingTimeInterval(-config.duplicateWindowSeconds)
        let windowEnd = timestamp.addingTimeInterval(config.duplicateWindowSeconds)
        
        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart,
            end: windowEnd,
            options: .strictStartDate
        )
        
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: glucoseType,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: nil
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results as? [HKQuantitySample] ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            return samples.first?.endDate
        } catch {
            return nil
        }
    }
    
    /// Write a glucose sample to HealthKit
    private func writeGlucoseSample(reading: GlucoseReading) async -> HealthKitWriteResult {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return .failedUnavailable
        }
        
        let mgdLUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        let quantity = HKQuantity(unit: mgdLUnit, doubleValue: reading.glucose)
        
        // Add metadata for tracking
        var metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: false,
            "com.t1pal.source": config.sourceIdentifier
        ]
        
        // Preserve original source if different
        if reading.source != config.sourceIdentifier {
            metadata["com.t1pal.originalSource"] = reading.source
        }
        
        let sample = HKQuantitySample(
            type: glucoseType,
            quantity: quantity,
            start: reading.timestamp,
            end: reading.timestamp,
            metadata: metadata
        )
        
        do {
            try await healthStore.save(sample)
            return .success(timestamp: reading.timestamp, glucose: reading.glucose)
        } catch {
            return .failedError(error.localizedDescription)
        }
    }
    #endif
}

// MARK: - CGM Manager Extension

/// Protocol for CGM managers that can write to HealthKit
public protocol HealthKitWritingCGM {
    /// Write the latest reading to HealthKit
    func writeToHealthKit() async -> HealthKitWriteResult
    
    /// Whether HealthKit writing is enabled
    var isHealthKitWritingEnabled: Bool { get }
}

// MARK: - Convenience Initializer for Readings with Write

extension GlucoseReading {
    /// Write this reading to HealthKit
    /// - Parameter writer: HealthKitWriter instance
    /// - Returns: Result of the write operation
    public func writeToHealthKit(using writer: HealthKitWriter) async -> HealthKitWriteResult {
        await writer.write(reading: self)
    }
}
