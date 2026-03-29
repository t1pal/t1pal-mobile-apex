// SPDX-License-Identifier: AGPL-3.0-or-later
//
// HealthKitCGMManager.swift
// CGMKit
//
// HealthKit observer CGM source - reads glucose from vendor apps via HealthKit
// Trace: PRD-007, REQ-CGM-010, CGM-024, LOG-ADOPT-004, OBS-013

import Foundation
import T1PalCore

#if canImport(HealthKit)
import HealthKit
#endif

// MARK: - HealthKit CGM Configuration

/// Configuration for HealthKit observer CGM
public struct HealthKitCGMConfig: Codable, Sendable {
    /// Maximum age of readings to consider (default 15 minutes)
    public let maxReadingAgeSeconds: TimeInterval
    
    /// Window for trend calculation (default 15 minutes)
    public let trendWindowMinutes: Double
    
    /// Minimum samples required for trend calculation
    public let minSamplesForTrend: Int
    
    /// Gap detection threshold - alert when no data for this long (default 15 minutes)
    public let gapThresholdSeconds: TimeInterval
    
    /// Expected interval between readings (default 5 minutes for Dexcom/Libre)
    public let expectedIntervalSeconds: TimeInterval
    
    /// Enable background delivery for glucose updates (default true)
    public let enableBackgroundDelivery: Bool
    
    /// Background delivery frequency (default .immediate for CGM data)
    public let backgroundDeliveryFrequency: BackgroundDeliveryFrequency
    
    /// Enable gap-filling - write to HealthKit when vendor app is stale (default false)
    public let enableGapFilling: Bool
    
    /// Gap-fill threshold - write when no vendor data for this long (default 15 minutes)
    public let gapFillThresholdSeconds: TimeInterval
    
    /// Duplicate detection window - check for existing samples within this time (default 2 minutes)
    public let duplicateWindowSeconds: TimeInterval
    
    public init(
        maxReadingAgeSeconds: TimeInterval = 900,
        trendWindowMinutes: Double = 15,
        minSamplesForTrend: Int = 3,
        gapThresholdSeconds: TimeInterval = 900,
        expectedIntervalSeconds: TimeInterval = 300,
        enableBackgroundDelivery: Bool = true,
        backgroundDeliveryFrequency: BackgroundDeliveryFrequency = .immediate,
        enableGapFilling: Bool = false,
        gapFillThresholdSeconds: TimeInterval = 900,
        duplicateWindowSeconds: TimeInterval = 120
    ) {
        self.maxReadingAgeSeconds = maxReadingAgeSeconds
        self.trendWindowMinutes = trendWindowMinutes
        self.minSamplesForTrend = minSamplesForTrend
        self.gapThresholdSeconds = gapThresholdSeconds
        self.expectedIntervalSeconds = expectedIntervalSeconds
        self.enableBackgroundDelivery = enableBackgroundDelivery
        self.backgroundDeliveryFrequency = backgroundDeliveryFrequency
        self.enableGapFilling = enableGapFilling
        self.gapFillThresholdSeconds = gapFillThresholdSeconds
        self.duplicateWindowSeconds = duplicateWindowSeconds
    }
    
    public static let `default` = HealthKitCGMConfig()
}

/// Background delivery frequency options (mirrors HKUpdateFrequency)
public enum BackgroundDeliveryFrequency: Int, Codable, Sendable {
    /// Notify as soon as new data is available
    case immediate = 1
    /// Notify at most once per hour
    case hourly = 2
    /// Notify at most once per day
    case daily = 3
    /// Notify at most once per week
    case weekly = 4
}

// MARK: - Gap Fill (CGM-029)

/// Result of a gap-fill write attempt
public enum GapFillResult: Sendable, Equatable {
    /// Successfully wrote glucose to HealthKit
    case written(timestamp: Date, glucose: Double)
    
    /// Skipped - duplicate sample exists within window
    case skippedDuplicate(existingTimestamp: Date)
    
    /// Skipped - no gap detected (vendor app is up to date)
    case skippedNoGap
    
    /// Skipped - gap filling is disabled
    case skippedDisabled
    
    /// Failed - no write authorization
    case failedUnauthorized
    
    /// Failed - HealthKit error
    case failedError(String)
    
    public var wasWritten: Bool {
        if case .written = self { return true }
        return false
    }
    
    public var description: String {
        switch self {
        case .written(let timestamp, let glucose):
            return "Wrote \(Int(glucose)) mg/dL at \(timestamp)"
        case .skippedDuplicate(let existing):
            return "Skipped - duplicate exists at \(existing)"
        case .skippedNoGap:
            return "Skipped - no gap detected"
        case .skippedDisabled:
            return "Skipped - gap filling disabled"
        case .failedUnauthorized:
            return "Failed - not authorized to write"
        case .failedError(let msg):
            return "Failed - \(msg)"
        }
    }
}

// MARK: - Trend Calculation (Production version from DEBUG-ETU-002)

/// Linear regression trend calculator for glucose samples
public struct GlucoseTrendCalculator {
    
    /// Calculate trend from glucose readings using linear regression
    /// - Parameters:
    ///   - readings: Recent glucose readings (newest first)
    ///   - windowMinutes: Time window for calculation
    /// - Returns: Calculated trend or .notComputable if insufficient data
    public static func calculateTrend(
        from readings: [GlucoseReading],
        windowMinutes: Double = 15
    ) -> GlucoseTrend {
        guard readings.count >= 3 else { return .notComputable }
        
        let now = Date()
        let windowStart = now.addingTimeInterval(-windowMinutes * 60)
        
        // Filter readings within window
        let windowReadings = readings.filter { $0.timestamp >= windowStart }
        guard windowReadings.count >= 3 else { return .notComputable }
        
        // Convert to (x, y) pairs where x = minutes ago, y = glucose
        let points: [(x: Double, y: Double)] = windowReadings.map { reading in
            let minutesAgo = now.timeIntervalSince(reading.timestamp) / 60.0
            return (x: minutesAgo, y: reading.glucose)
        }
        
        // Linear regression
        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let sumXY = points.reduce(0) { $0 + $1.x * $1.y }
        let sumX2 = points.reduce(0) { $0 + $1.x * $1.x }
        
        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return .notComputable }
        
        // Slope: negative because x is "minutes ago"
        let slope = -((n * sumXY - sumX * sumY) / denominator)
        
        return trendFromSlope(slope)
    }
    
    /// Convert slope (mg/dL/min) to GlucoseTrend
    /// Based on Dexcom thresholds
    public static func trendFromSlope(_ slope: Double) -> GlucoseTrend {
        switch slope {
        case 3...: return .doubleUp
        case 2..<3: return .singleUp
        case 1..<2: return .fortyFiveUp
        case -1..<1: return .flat
        case -2..<(-1): return .fortyFiveDown
        case -3..<(-2): return .singleDown
        default: return .doubleDown
        }
    }
}

// MARK: - HealthKit Source Analysis (DETECT-001)

/// Analysis of glucose sample sources in HealthKit
/// Used to detect colocated AID apps like Loop that write glucose to HealthKit
/// Trace: PRD-004 REQ-CGM-035, DETECT-001
public struct HealthKitSourceAnalysis: Sendable, Equatable {
    /// Bundle identifiers of apps writing glucose to HealthKit
    public let sourceBundleIds: [String]
    
    /// Human-readable names of source apps
    public let sourceNames: [String]
    
    /// Sample count per source (for weighting)
    public let sampleCountsBySource: [String: Int]
    
    /// Analysis timestamp
    public let analyzedAt: Date
    
    public init(
        sourceBundleIds: [String] = [],
        sourceNames: [String] = [],
        sampleCountsBySource: [String: Int] = [:],
        analyzedAt: Date = Date()
    ) {
        self.sourceBundleIds = sourceBundleIds
        self.sourceNames = sourceNames
        self.sampleCountsBySource = sampleCountsBySource
        self.analyzedAt = analyzedAt
    }
    
    // MARK: - Known App Detection
    
    /// True if Loop is writing glucose to HealthKit
    public var loopIsGlucoseSource: Bool {
        sourceBundleIds.contains { $0 == "com.loopkit.Loop" || $0.hasPrefix("com.loopkit.Loop.") }
    }
    
    /// True if Trio is writing glucose to HealthKit
    public var trioIsGlucoseSource: Bool {
        sourceBundleIds.contains { $0 == "org.nightscout.Trio" || $0.hasPrefix("org.nightscout.Trio.") }
    }
    
    /// True if xDrip4iOS is writing glucose to HealthKit
    public var xdripIsGlucoseSource: Bool {
        sourceBundleIds.contains { $0.contains("xdrip") }
    }
    
    /// True if Dexcom app is writing glucose to HealthKit
    public var dexcomIsGlucoseSource: Bool {
        sourceBundleIds.contains { $0.hasPrefix("com.dexcom") }
    }
    
    /// True if Abbott/Libre app is writing glucose to HealthKit
    public var libreIsGlucoseSource: Bool {
        sourceBundleIds.contains { $0.hasPrefix("com.abbott") }
    }
    
    /// True if any AID app is writing glucose (Loop, Trio, OpenAPS variants)
    public var aidAppIsGlucoseSource: Bool {
        loopIsGlucoseSource || trioIsGlucoseSource || sourceBundleIds.contains { 
            $0.contains("openaps") || $0.contains("freeaps")
        }
    }
    
    /// True if T1Pal should use passive mode (avoid direct CGM connection)
    public var shouldUsePassiveMode: Bool {
        loopIsGlucoseSource || dexcomIsGlucoseSource || trioIsGlucoseSource
    }
    
    /// Get the primary glucose source (most samples)
    public var primarySource: String? {
        sampleCountsBySource.max(by: { $0.value < $1.value })?.key
    }
    
    /// Detection confidence (0.0-1.0) based on sample count
    public var confidence: Double {
        let totalSamples = sampleCountsBySource.values.reduce(0, +)
        if totalSamples == 0 { return 0.0 }
        if totalSamples >= 12 { return 1.0 }  // 1 hour of CGM data
        if totalSamples >= 6 { return 0.8 }   // 30 minutes
        if totalSamples >= 3 { return 0.5 }   // 15 minutes
        return 0.3
    }
    
    /// Human-readable summary
    public var summary: String {
        if sourceBundleIds.isEmpty {
            return "No glucose sources detected"
        }
        
        var parts: [String] = []
        if loopIsGlucoseSource { parts.append("Loop") }
        if trioIsGlucoseSource { parts.append("Trio") }
        if dexcomIsGlucoseSource { parts.append("Dexcom") }
        if libreIsGlucoseSource { parts.append("Libre") }
        if xdripIsGlucoseSource { parts.append("xDrip") }
        
        // Add any unknown sources
        let knownPrefixes = ["com.loopkit", "org.nightscout", "com.dexcom", "com.abbott", "xdrip"]
        for bundleId in sourceBundleIds {
            if !knownPrefixes.contains(where: { bundleId.contains($0) }) {
                // Extract app name from bundle ID
                let name = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
                if !parts.contains(name) {
                    parts.append(name)
                }
            }
        }
        
        return parts.joined(separator: ", ")
    }
}

// MARK: - Gap Detection (CGM-032)

/// Status of data gap detection
public enum GapStatus: Sendable, Equatable {
    /// No gap detected, data is flowing normally
    case noGap
    
    /// Gap detected - no data received for specified duration
    case gapDetected(since: Date, duration: TimeInterval)
    
    /// No data has ever been received
    case noDataYet
    
    public var isGap: Bool {
        switch self {
        case .gapDetected: return true
        case .noGap, .noDataYet: return false
        }
    }
    
    public var description: String {
        switch self {
        case .noGap:
            return "Data flowing normally"
        case .gapDetected(_, let duration):
            let minutes = Int(duration / 60)
            return "No data for \(minutes) minutes"
        case .noDataYet:
            return "Waiting for first reading"
        }
    }
}

// MARK: - HealthKit CGM Manager

/// CGM manager that reads glucose from HealthKit (written by vendor apps)
/// Requirements: REQ-CGM-010, CGM-032, CGM-033
public actor HealthKitCGMManager: CGMManagerProtocol {
    public let displayName = "HealthKit Observer"
    public let cgmType = CGMType.healthKitObserver
    
    public private(set) var sensorState: SensorState = .notStarted
    public private(set) var latestReading: GlucoseReading?
    
    public var onReadingReceived: (@Sendable (GlucoseReading) -> Void)?
    public var onSensorStateChanged: (@Sendable (SensorState) -> Void)?
    public var onError: (@Sendable (CGMError) -> Void)?
    
    /// Set reading callback from actor isolation context
    /// Required for cross-actor callback configuration (G6-CONNECT-005)
    public func setReadingCallback(_ callback: @escaping @Sendable (GlucoseReading) -> Void) {
        onReadingReceived = callback
    }
    
    // MARK: - Gap Detection (CGM-032)
    
    /// Current gap detection status
    public private(set) var gapStatus: GapStatus = .noDataYet
    
    /// Callback when gap is detected or resolved
    public var onGapStatusChanged: (@Sendable (GapStatus) -> Void)?
    
    // MARK: - Background Delivery (CGM-033)
    
    /// Whether background delivery is currently enabled
    public private(set) var isBackgroundDeliveryEnabled: Bool = false
    
    /// Callback when background delivery state changes
    public var onBackgroundDeliveryStateChanged: (@Sendable (Bool) -> Void)?
    
    // MARK: - Gap Filling (CGM-029)
    
    /// Whether gap-fill write authorization has been granted
    public private(set) var hasGapFillWriteAuthorization: Bool = false
    
    /// Last gap-fill result
    public private(set) var lastGapFillResult: GapFillResult?
    
    /// Callback when gap-fill write occurs
    public var onGapFillResult: (@Sendable (GapFillResult) -> Void)?
    
    // MARK: - Source Analysis (DETECT-001)
    
    /// Last source analysis result
    public private(set) var lastSourceAnalysis: HealthKitSourceAnalysis?
    
    /// Callback when source analysis completes
    public var onSourceAnalysisCompleted: (@Sendable (HealthKitSourceAnalysis) -> Void)?
    
    // MARK: - Fault Injection (OBS-013)
    
    /// Optional fault injector for testing HealthKit error scenarios
    /// Trace: PRD-025, OBS-013
    public private(set) var faultInjector: HealthKitFaultInjector?
    
    /// Callback when fault is injected
    public var onFaultInjected: (@Sendable (DataFaultType) -> Void)?
    
    private let config: HealthKitCGMConfig
    private var recentReadings: [GlucoseReading] = []
    
    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    private var observerQuery: HKObserverQuery?
    private var anchoredQuery: HKAnchoredObjectQuery?
    private var queryAnchor: HKQueryAnchor?
    #endif
    
    public init(config: HealthKitCGMConfig = .default) {
        self.config = config
        CGMLogger.general.info("HealthKitCGMManager: initialized")
    }
    
    // MARK: - CGMManagerProtocol
    
    public func startScanning() async throws {
        #if canImport(HealthKit)
        CGMLogger.general.info("HealthKitCGMManager: Starting HealthKit observer")
        guard HKHealthStore.isHealthDataAvailable() else {
            CGMLogger.general.error("HealthKitCGMManager: HealthKit not available")
            sensorState = .failed
            onSensorStateChanged?(.failed)
            throw CGMError.dataUnavailable
        }
        
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            throw CGMError.dataUnavailable
        }
        
        // Request read authorization
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [glucoseType])
            CGMLogger.general.info("HealthKitCGMManager: Authorization granted")
        } catch {
            CGMLogger.general.error("HealthKitCGMManager: Authorization failed")
            sensorState = .failed
            onSensorStateChanged?(.failed)
            throw CGMError.unauthorized
        }
        
        // Check if we have any recent data
        await fetchRecentReadings()
        
        // Setup background delivery if configured (CGM-033)
        await setupBackgroundDeliveryIfNeeded()
        
        if latestReading != nil {
            sensorState = .active
            onSensorStateChanged?(.active)
        } else {
            // No data yet, but that's OK - we'll wait for observer
            sensorState = .warmingUp
            onSensorStateChanged?(.warmingUp)
        }
        #else
        throw CGMError.dataUnavailable
        #endif
    }
    
    public func connect(to sensor: SensorInfo) async throws {
        try await startScanning()
        startObserver()
    }
    
    public func disconnect() async {
        CGMLogger.general.info("HealthKitCGMManager: Disconnecting")
        stopObserver()
        sensorState = .stopped
        onSensorStateChanged?(.stopped)
    }
    
    // MARK: - HealthKit Observer
    
    private func startObserver() {
        #if canImport(HealthKit)
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        
        // Observer query for real-time notifications
        observerQuery = HKObserverQuery(
            sampleType: glucoseType,
            predicate: nil
        ) { [weak self] _, completionHandler, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    await self.handleError(error)
                } else {
                    await self.fetchRecentReadings()
                }
            }
            completionHandler()
        }
        
        if let query = observerQuery {
            healthStore.execute(query)
        }
        #endif
    }
    
    private func stopObserver() {
        #if canImport(HealthKit)
        if let query = observerQuery {
            healthStore.stop(query)
            observerQuery = nil
        }
        if let query = anchoredQuery {
            healthStore.stop(query)
            anchoredQuery = nil
        }
        #endif
    }
    
    // MARK: - Data Fetching
    
    private func fetchRecentReadings() async {
        #if canImport(HealthKit)
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        
        let now = Date()
        let startDate = now.addingTimeInterval(-config.maxReadingAgeSeconds * 4) // Fetch extra for trend
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: now,
            options: .strictEndDate
        )
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierEndDate,
            ascending: false
        )
        
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: glucoseType,
                    predicate: predicate,
                    limit: 50,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: results as? [HKQuantitySample] ?? [])
                    }
                }
                healthStore.execute(query)
            }
            
            // Convert to GlucoseReading
            let mgdLUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
            
            recentReadings = samples.map { sample in
                let glucose = sample.quantity.doubleValue(for: mgdLUnit)
                let source = sample.sourceRevision.source.bundleIdentifier ?? "HealthKit"
                
                return GlucoseReading(
                    glucose: glucose,
                    timestamp: sample.endDate,
                    trend: .notComputable, // Will calculate below
                    source: source
                )
            }
            
            // Calculate trend from recent readings
            if !recentReadings.isEmpty {
                let calculatedTrend = GlucoseTrendCalculator.calculateTrend(
                    from: recentReadings,
                    windowMinutes: config.trendWindowMinutes
                )
                
                // Update latest reading with calculated trend
                if let latest = recentReadings.first {
                    let updatedReading = GlucoseReading(
                        glucose: latest.glucose,
                        timestamp: latest.timestamp,
                        trend: calculatedTrend,
                        source: latest.source
                    )
                    
                    // Only notify if this is a new reading
                    if latestReading?.timestamp != updatedReading.timestamp {
                        CGMLogger.readings.glucoseReading(
                            value: updatedReading.glucose,
                            trend: updatedReading.trend.rawValue,
                            timestamp: updatedReading.timestamp
                        )
                        latestReading = updatedReading
                        onReadingReceived?(updatedReading)
                        
                        if sensorState != .active {
                            sensorState = .active
                            onSensorStateChanged?(.active)
                        }
                        
                        // Check for gap based on reading timestamp (CGM-032)
                        checkForGap(lastReadingTime: updatedReading.timestamp)
                    }
                }
            } else {
                // No readings found - check for gap
                checkForGap(lastReadingTime: nil)
            }
        } catch {
            await handleError(error)
        }
        #endif
    }
    
    // MARK: - Gap Detection (CGM-032)
    
    /// Check for data gap based on last reading time
    private func checkForGap(lastReadingTime: Date?) {
        let now = Date()
        let oldStatus = gapStatus
        
        guard let lastTime = lastReadingTime else {
            // No data received yet
            if case .noDataYet = gapStatus {
                // Already in noDataYet, no change needed
                return
            }
            gapStatus = .noDataYet
            if gapStatus != oldStatus {
                onGapStatusChanged?(gapStatus)
            }
            return
        }
        
        let timeSinceLastReading = now.timeIntervalSince(lastTime)
        
        if timeSinceLastReading >= config.gapThresholdSeconds {
            // Gap detected
            let newStatus = GapStatus.gapDetected(since: lastTime, duration: timeSinceLastReading)
            gapStatus = newStatus
            
            // Always notify on gap (even if already in gap state with different duration)
            let wasGap = oldStatus.isGap
            if !wasGap || timeSinceLastReading >= config.gapThresholdSeconds * 2 {
                // Notify when gap first detected or doubles in severity
                onGapStatusChanged?(newStatus)
            }
        } else {
            // No gap
            let wasGap = oldStatus.isGap
            gapStatus = .noGap
            
            if wasGap {
                // Gap resolved - notify
                onGapStatusChanged?(.noGap)
            }
        }
    }
    
    /// Check gap status on demand (useful for background refresh)
    public func checkGapStatus() -> GapStatus {
        // Recompute based on current latestReading
        let now = Date()
        guard let lastReading = latestReading else {
            return .noDataYet
        }
        
        let timeSinceLastReading = now.timeIntervalSince(lastReading.timestamp)
        if timeSinceLastReading >= config.gapThresholdSeconds {
            return .gapDetected(since: lastReading.timestamp, duration: timeSinceLastReading)
        }
        return .noGap
    }
    
    private func handleError(_ error: Error) async {
        CGMLogger.general.error("HealthKitCGMManager: Error - \(error.localizedDescription)")
        onError?(.dataUnavailable)
    }
    
    // MARK: - Public API
    
    /// Get recent readings for display
    /// Trace: OBS-013 - Applies fault injection if configured
    public func getRecentReadings() -> [GlucoseReading] {
        // Apply fault injection if configured (OBS-013)
        if let injector = faultInjector, injector.isEnabled {
            return injector.applyFaults(to: recentReadings)
        }
        return recentReadings
    }
    
    /// Set the fault injector for testing (OBS-013)
    public func setFaultInjector(_ injector: HealthKitFaultInjector?) {
        self.faultInjector = injector
        if let injector = injector {
            CGMLogger.general.info("HealthKitCGMManager: Fault injector configured with \(injector.activeFaults.count) faults")
        } else {
            CGMLogger.general.info("HealthKitCGMManager: Fault injector cleared")
        }
    }
    
    /// Manually refresh readings
    public func refresh() async {
        await fetchRecentReadings()
    }
    
    // MARK: - Background Delivery (CGM-033)
    
    /// Enable background delivery for glucose data
    /// Should be called on app launch for background updates
    /// - Throws: CGMError if HealthKit is unavailable or authorization fails
    public func enableBackgroundDelivery() async throws {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CGMError.dataUnavailable
        }
        
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            throw CGMError.dataUnavailable
        }
        
        let hkFrequency: HKUpdateFrequency
        switch config.backgroundDeliveryFrequency {
        case .immediate:
            hkFrequency = .immediate
        case .hourly:
            hkFrequency = .hourly
        case .daily:
            hkFrequency = .daily
        case .weekly:
            hkFrequency = .weekly
        }
        
        do {
            try await healthStore.enableBackgroundDelivery(for: glucoseType, frequency: hkFrequency)
            isBackgroundDeliveryEnabled = true
            onBackgroundDeliveryStateChanged?(true)
        } catch {
            isBackgroundDeliveryEnabled = false
            onBackgroundDeliveryStateChanged?(false)
            throw CGMError.unauthorized
        }
        #else
        throw CGMError.dataUnavailable
        #endif
    }
    
    /// Disable background delivery for glucose data
    /// Call when the user disables CGM monitoring or app is shutting down
    public func disableBackgroundDelivery() async {
        #if canImport(HealthKit)
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return
        }
        
        do {
            try await healthStore.disableBackgroundDelivery(for: glucoseType)
            isBackgroundDeliveryEnabled = false
            onBackgroundDeliveryStateChanged?(false)
        } catch {
            // Log error but don't throw - best effort cleanup
            onError?(.dataUnavailable)
        }
        #endif
    }
    
    /// Disable all background delivery for this app
    /// Useful for complete cleanup on app termination
    public func disableAllBackgroundDelivery() async {
        #if canImport(HealthKit)
        do {
            try await healthStore.disableAllBackgroundDelivery()
            isBackgroundDeliveryEnabled = false
            onBackgroundDeliveryStateChanged?(false)
        } catch {
            onError?(.dataUnavailable)
        }
        #endif
    }
    
    /// Setup background delivery if configured
    /// Called automatically during startScanning if config.enableBackgroundDelivery is true
    private func setupBackgroundDeliveryIfNeeded() async {
        guard config.enableBackgroundDelivery else { return }
        
        do {
            try await enableBackgroundDelivery()
        } catch {
            // Non-fatal - observer will still work in foreground
            onError?(.dataUnavailable)
        }
    }
    
    // MARK: - Gap Filling (CGM-029)
    
    /// Request write authorization for gap-filling
    /// Must be called before gap-fill writes will work
    public func requestGapFillWriteAuthorization() async throws {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CGMError.dataUnavailable
        }
        
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            throw CGMError.dataUnavailable
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [glucoseType], read: [glucoseType])
            // Check if we actually got write permission
            let authStatus = healthStore.authorizationStatus(for: glucoseType)
            hasGapFillWriteAuthorization = (authStatus == .sharingAuthorized)
        } catch {
            hasGapFillWriteAuthorization = false
            throw CGMError.unauthorized
        }
        #else
        throw CGMError.dataUnavailable
        #endif
    }
    
    /// Attempt to gap-fill a glucose reading to HealthKit
    /// - Parameters:
    ///   - reading: The glucose reading to write
    ///   - lastVendorTimestamp: Timestamp of last vendor app sample (for gap detection)
    /// - Returns: Result of the gap-fill attempt
    public func gapFillIfNeeded(reading: GlucoseReading, lastVendorTimestamp: Date?) async -> GapFillResult {
        guard config.enableGapFilling else {
            let result = GapFillResult.skippedDisabled
            lastGapFillResult = result
            return result
        }
        
        // Check if there's actually a gap
        let now = Date()
        if let vendorTime = lastVendorTimestamp {
            let vendorAge = now.timeIntervalSince(vendorTime)
            if vendorAge < config.gapFillThresholdSeconds {
                let result = GapFillResult.skippedNoGap
                lastGapFillResult = result
                return result
            }
        }
        
        #if canImport(HealthKit)
        guard hasGapFillWriteAuthorization else {
            let result = GapFillResult.failedUnauthorized
            lastGapFillResult = result
            onGapFillResult?(result)
            return result
        }
        
        // Check for duplicate within window
        if let existingTimestamp = await checkForExistingSample(near: reading.timestamp) {
            let result = GapFillResult.skippedDuplicate(existingTimestamp: existingTimestamp)
            lastGapFillResult = result
            return result
        }
        
        // Write the sample
        let writeResult = await writeGlucoseToHealthKit(reading: reading)
        lastGapFillResult = writeResult
        onGapFillResult?(writeResult)
        return writeResult
        #else
        let result = GapFillResult.failedError("HealthKit not available")
        lastGapFillResult = result
        return result
        #endif
    }
    
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
    
    /// Write a glucose reading to HealthKit
    private func writeGlucoseToHealthKit(reading: GlucoseReading) async -> GapFillResult {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return .failedError("Glucose type unavailable")
        }
        
        let mgdLUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        let quantity = HKQuantity(unit: mgdLUnit, doubleValue: reading.glucose)
        
        let sample = HKQuantitySample(
            type: glucoseType,
            quantity: quantity,
            start: reading.timestamp,
            end: reading.timestamp,
            metadata: [
                HKMetadataKeyWasUserEntered: false,
                "com.t1pal.source": "GapFill",
                "com.t1pal.originalSource": reading.source
            ]
        )
        
        do {
            try await healthStore.save(sample)
            return .written(timestamp: reading.timestamp, glucose: reading.glucose)
        } catch {
            return .failedError(error.localizedDescription)
        }
    }
    
    // MARK: - Source Analysis (DETECT-001)
    
    /// Analyze glucose sample sources in HealthKit
    /// Detects which apps are writing glucose data (Loop, Dexcom, Libre, etc.)
    /// - Parameter windowHours: How far back to analyze (default 1 hour)
    /// - Returns: Analysis of glucose sources
    public func analyzeGlucoseSources(windowHours: Double = 1.0) async -> HealthKitSourceAnalysis {
        guard let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            let empty = HealthKitSourceAnalysis()
            lastSourceAnalysis = empty
            return empty
        }
        
        let now = Date()
        let startDate = now.addingTimeInterval(-windowHours * 3600)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: now,
            options: .strictEndDate
        )
        
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
                let query = HKSampleQuery(
                    sampleType: glucoseType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
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
            
            // Extract unique sources and count samples per source
            var bundleIds = Set<String>()
            var names = Set<String>()
            var counts: [String: Int] = [:]
            
            for sample in samples {
                let source = sample.sourceRevision.source
                let bundleId = source.bundleIdentifier ?? "unknown"
                bundleIds.insert(bundleId)
                names.insert(source.name)
                counts[bundleId, default: 0] += 1
            }
            
            let analysis = HealthKitSourceAnalysis(
                sourceBundleIds: Array(bundleIds).sorted(),
                sourceNames: Array(names).sorted(),
                sampleCountsBySource: counts,
                analyzedAt: now
            )
            
            lastSourceAnalysis = analysis
            onSourceAnalysisCompleted?(analysis)
            return analysis
        } catch {
            let empty = HealthKitSourceAnalysis()
            lastSourceAnalysis = empty
            return empty
        }
    }
    #endif
}

// MARK: - HealthKit Fault Injector (OBS-013)

/// Fault injector for HealthKit data testing
/// Trace: PRD-025, OBS-013
public final class HealthKitFaultInjector: @unchecked Sendable {
    /// Active faults to apply
    public private(set) var activeFaults: [DataFaultType] = []
    
    /// Whether fault injection is enabled
    public var isEnabled: Bool = true
    
    /// Probability of applying faults (0.0 to 1.0)
    public var faultProbability: Double = 1.0
    
    public init() {}
    
    /// Add an active fault
    public func addFault(_ fault: DataFaultType) {
        activeFaults.append(fault)
    }
    
    /// Remove all faults of a specific type
    public func removeFault(_ fault: DataFaultType) {
        activeFaults.removeAll { $0 == fault }
    }
    
    /// Clear all active faults
    public func clearFaults() {
        activeFaults.removeAll()
    }
    
    /// Apply faults to a reading array
    /// - Parameter readings: Original readings from HealthKit
    /// - Returns: Modified readings with faults applied
    public func applyFaults(to readings: [GlucoseReading]) -> [GlucoseReading] {
        guard isEnabled, !activeFaults.isEmpty else { return readings }
        guard Double.random(in: 0...1) <= faultProbability else { return readings }
        
        var result = readings
        
        for fault in activeFaults {
            switch fault {
            case .staleData(let gapMinutes):
                // Return empty if simulating stale data
                if gapMinutes > 0 {
                    result = []
                }
                
            case .dataGap(let startMinutesAgo, let durationMinutes):
                // Remove readings within the gap window
                let now = Date()
                let gapStart = now.addingTimeInterval(-Double(startMinutesAgo) * 60)
                let gapEnd = now.addingTimeInterval(-Double(startMinutesAgo - durationMinutes) * 60)
                result = result.filter { $0.timestamp < gapStart || $0.timestamp > gapEnd }
                
            case .invalidValue(let value):
                // Replace latest reading with invalid value
                if !result.isEmpty {
                    let latest = result[0]
                    result[0] = GlucoseReading(
                        glucose: value,
                        timestamp: latest.timestamp,
                        trend: latest.trend,
                        source: latest.source
                    )
                }
                
            case .duplicateReadings(let count):
                // Duplicate the latest reading
                if let first = result.first {
                    for _ in 0..<count {
                        result.insert(first, at: 0)
                    }
                }
                
            case .outOfOrderReadings:
                // Shuffle the readings
                result.shuffle()
                
            case .futureReadings(let minutesAhead):
                // Shift all readings into the future
                result = result.map { reading in
                    GlucoseReading(
                        glucose: reading.glucose,
                        timestamp: reading.timestamp.addingTimeInterval(Double(minutesAhead) * 60),
                        trend: reading.trend,
                        source: reading.source
                    )
                }
                
            case .missingTrend:
                // Remove trend arrows
                result = result.map { reading in
                    GlucoseReading(
                        glucose: reading.glucose,
                        timestamp: reading.timestamp,
                        trend: .notComputable,
                        source: reading.source
                    )
                }
                
            case .conflictingSource(let deltaMilligrams):
                // Add delta to glucose values to simulate source mismatch
                result = result.map { reading in
                    GlucoseReading(
                        glucose: reading.glucose + Double(deltaMilligrams),
                        timestamp: reading.timestamp,
                        trend: reading.trend,
                        source: reading.source
                    )
                }
            }
        }
        
        return result
    }
}
