// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutAlgorithmDataSource.swift
// NightscoutKit
//
// AlgorithmDataSource implementation that fetches from Nightscout API
// Requirements: ALG-INPUT-008

import Foundation
import T1PalCore
import T1PalAlgorithm

// MARK: - NightscoutAlgorithmDataSource

/// Data source that fetches algorithm inputs from a Nightscout server.
///
/// Implements `AlgorithmDataSource` protocol to provide glucose, doses,
/// carbs, and profile data for algorithm calculations.
///
/// Usage:
/// ```swift
/// let client = NightscoutClient(config: config)
/// let dataSource = NightscoutAlgorithmDataSource(client: client)
/// let assembler = AlgorithmInputAssembler(dataSource: dataSource)
/// let inputs = try await assembler.assembleInputs()
/// ```
public actor NightscoutAlgorithmDataSource: AlgorithmDataSource {
    
    // MARK: - Properties
    
    /// The underlying Nightscout client
    private let client: NightscoutClient
    
    /// Reference time for data fetching (defaults to current time)
    public var referenceTime: Date
    
    /// Cached profile to avoid repeated fetches
    private var cachedProfile: (profile: TherapyProfile, fetchedAt: Date)?
    
    /// Cached loop settings
    private var cachedLoopSettings: (settings: T1PalAlgorithm.LoopSettings?, fetchedAt: Date)?
    
    /// Cache duration in seconds (5 minutes)
    private let cacheDuration: TimeInterval = 300
    
    // MARK: - Initialization
    
    /// Create a data source with a pre-configured Nightscout client.
    /// - Parameters:
    ///   - client: Configured NightscoutClient
    ///   - referenceTime: Reference time for data fetching (default: now)
    public init(client: NightscoutClient, referenceTime: Date = Date()) {
        self.client = client
        self.referenceTime = referenceTime
    }
    
    /// Create a data source with URL and credentials.
    /// - Parameters:
    ///   - url: Nightscout site URL
    ///   - apiSecret: Optional API secret for authentication
    ///   - token: Optional token for authentication
    ///   - referenceTime: Reference time for data fetching (default: now)
    public init(
        url: URL,
        apiSecret: String? = nil,
        token: String? = nil,
        referenceTime: Date = Date()
    ) {
        let config = NightscoutConfig(url: url, apiSecret: apiSecret, token: token)
        self.client = NightscoutClient(config: config)
        self.referenceTime = referenceTime
    }
    
    // MARK: - AlgorithmDataSource Protocol
    
    public func glucoseHistory(count: Int) async throws -> [GlucoseReading] {
        let entries = try await client.fetchEntries(count: count)
        
        let readings = entries.compactMap { entry -> GlucoseReading? in
            entry.toGlucoseReading()
        }
        
        guard !readings.isEmpty else {
            throw AlgorithmDataSourceError.noGlucoseData
        }
        
        // Already sorted newest first by Nightscout
        return readings
    }
    
    public func doseHistory(hours: Int) async throws -> [InsulinDose] {
        let from = referenceTime.addingTimeInterval(-Double(hours) * 3600)
        let to = referenceTime
        
        let query = TreatmentsQuery(
            count: 500,
            dateFrom: from,
            dateTo: to
        )
        
        let treatments = try await client.fetchTreatments(query: query)
        
        // Filter and convert insulin treatments
        let doses = treatments.compactMap { treatment -> InsulinDose? in
            treatment.toInsulinDose()
        }
        
        // Sort newest first
        return doses.sorted { $0.timestamp > $1.timestamp }
    }
    
    public func carbHistory(hours: Int) async throws -> [CarbEntry] {
        let from = referenceTime.addingTimeInterval(-Double(hours) * 3600)
        let to = referenceTime
        
        let query = TreatmentsQuery(
            count: 500,
            dateFrom: from,
            dateTo: to
        )
        
        let treatments = try await client.fetchTreatments(query: query)
        
        // Filter and convert carb treatments
        let carbs = treatments.compactMap { treatment -> CarbEntry? in
            treatment.toCarbEntry()
        }
        
        // Sort newest first
        return carbs.sorted { $0.timestamp > $1.timestamp }
    }
    
    public func currentProfile() async throws -> TherapyProfile {
        // Check cache
        if let cached = cachedProfile,
           referenceTime.timeIntervalSince(cached.fetchedAt) < cacheDuration {
            return cached.profile
        }
        
        // Fetch profiles from Nightscout
        let profiles = try await client.fetchProfiles(count: 1)
        
        guard let latestProfile = profiles.first,
              let activeStore = latestProfile.activeProfile else {
            throw AlgorithmDataSourceError.profileNotAvailable
        }
        
        // Convert to TherapyProfile
        let profile = try convertToTherapyProfile(activeStore, units: latestProfile.units)
        
        // Cache it
        cachedProfile = (profile, referenceTime)
        
        return profile
    }
    
    public func loopSettings() async throws -> T1PalAlgorithm.LoopSettings? {
        // Check cache
        if let cached = cachedLoopSettings,
           referenceTime.timeIntervalSince(cached.fetchedAt) < cacheDuration {
            return cached.settings
        }
        
        // Fetch profiles to get loop settings
        let profiles = try await client.fetchProfiles(count: 1)
        
        guard let latestProfile = profiles.first else {
            cachedLoopSettings = (nil, referenceTime)
            return nil
        }
        
        // Convert Nightscout loop settings to algorithm loop settings
        let settings = latestProfile.loopSettings.map { nsSettings in
            T1PalAlgorithm.LoopSettings(
                maximumBasalRatePerHour: nsSettings.maximumBasalRatePerHour,
                maximumBolus: nsSettings.maximumBolus,
                minimumBGGuard: nsSettings.minimumBGGuard,
                dosingStrategy: nsSettings.dosingStrategy,
                dosingEnabled: nsSettings.dosingEnabled,
                preMealTargetRange: nsSettings.preMealTargetRange
            )
        }
        
        cachedLoopSettings = (settings, referenceTime)
        return settings
    }
    
    // MARK: - Profile Conversion
    
    /// Convert Nightscout ProfileStore to TherapyProfile.
    private func convertToTherapyProfile(
        _ store: ProfileStore,
        units: String?
    ) throws -> TherapyProfile {
        let isMMOL = units?.lowercased().contains("mmol") ?? false
        let mmolFactor = 18.0182
        
        // Convert basal rates
        let basalRates: [BasalRate] = (store.basal ?? []).compactMap { entry in
            guard let rate = entry.value else { return nil }
            let startTime = parseStartTime(entry)
            return BasalRate(startTime: startTime, rate: rate)
        }
        
        // Convert carb ratios
        let carbRatios: [CarbRatio] = (store.carbratio ?? []).compactMap { entry in
            guard let ratio = entry.value else { return nil }
            let startTime = parseStartTime(entry)
            return CarbRatio(startTime: startTime, ratio: ratio)
        }
        
        // Convert sensitivity factors (with unit conversion)
        let sensitivityFactors: [SensitivityFactor] = (store.sens ?? []).compactMap { entry in
            guard var factor = entry.value else { return nil }
            if isMMOL {
                factor *= mmolFactor
            }
            let startTime = parseStartTime(entry)
            return SensitivityFactor(startTime: startTime, factor: factor)
        }
        
        // Convert targets (with unit conversion)
        var targetLow: Double = 100
        var targetHigh: Double = 110
        
        if let lowEntries = store.target_low, let first = lowEntries.first {
            targetLow = first.value ?? 100
            if isMMOL { targetLow *= mmolFactor }
        }
        if let highEntries = store.target_high, let first = highEntries.first {
            targetHigh = first.value ?? 110
            if isMMOL { targetHigh *= mmolFactor }
        }
        
        // Handle case where schedules are empty
        let finalBasalRates = basalRates.isEmpty 
            ? [BasalRate(startTime: 0, rate: 1.0)] 
            : basalRates
        let finalCarbRatios = carbRatios.isEmpty 
            ? [CarbRatio(startTime: 0, ratio: 10)] 
            : carbRatios
        let finalSensFactors = sensitivityFactors.isEmpty 
            ? [SensitivityFactor(startTime: 0, factor: 50)] 
            : sensitivityFactors
        
        return TherapyProfile(
            basalRates: finalBasalRates,
            carbRatios: finalCarbRatios,
            sensitivityFactors: finalSensFactors,
            targetGlucose: TargetRange(low: targetLow, high: targetHigh),
            maxIOB: 8.0,  // Defaults, may be overridden by loop settings
            maxBolus: 10.0
        )
    }
    
    /// Parse start time from ScheduleEntry.
    private func parseStartTime(_ entry: ScheduleEntry) -> TimeInterval {
        // Try timeAsSeconds first
        if let seconds = entry.timeAsSeconds {
            return TimeInterval(seconds)
        }
        
        // Try parsing time string (HH:mm format)
        if let time = entry.time {
            let parts = time.split(separator: ":")
            if parts.count >= 2,
               let hours = Int(parts[0]),
               let minutes = Int(parts[1]) {
                return TimeInterval(hours * 3600 + minutes * 60)
            }
            // Maybe it's already in seconds as a string
            if let seconds = Double(time) {
                return seconds
            }
        }
        
        return 0
    }
    
    // MARK: - Cache Management
    
    /// Clear cached data to force fresh fetches.
    public func clearCache() {
        cachedProfile = nil
        cachedLoopSettings = nil
    }
    
    /// Update the reference time for fetching.
    public func setReferenceTime(_ time: Date) {
        referenceTime = time
    }
}

// MARK: - Treatment Conversions

extension NightscoutTreatment {
    
    /// Convert a Nightscout treatment to an InsulinDose if applicable.
    public func toInsulinDose() -> InsulinDose? {
        // Check if this is an insulin treatment
        guard let insulin = self.insulin, insulin > 0 else {
            return nil
        }
        
        // Parse timestamp
        guard let timestamp = parseTimestamp() else {
            return nil
        }
        
        return InsulinDose(
            units: insulin,
            timestamp: timestamp,
            type: .novolog,  // Default type
            source: enteredBy ?? "nightscout"
        )
    }
    
    /// Convert a Nightscout treatment to a CarbEntry if applicable.
    public func toCarbEntry() -> CarbEntry? {
        // Check if this is a carb treatment
        guard let carbs = self.carbs, carbs > 0 else {
            return nil
        }
        
        // Parse timestamp
        guard let timestamp = parseTimestamp() else {
            return nil
        }
        
        // Determine absorption type from event type
        let absorptionType: CarbAbsorptionType
        switch eventType.lowercased() {
        case let t where t.contains("snack"):
            absorptionType = .fast
        case let t where t.contains("slow"):
            absorptionType = .slow
        default:
            absorptionType = .medium
        }
        
        return CarbEntry(
            grams: carbs,
            timestamp: timestamp,
            absorptionType: absorptionType,
            source: enteredBy ?? "nightscout",
            foodType: notes
        )
    }
    
    /// Parse the created_at timestamp.
    private func parseTimestamp() -> Date? {
        // ISO 8601 format
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: created_at) {
            return date
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: created_at) {
            return date
        }
        
        // Try common alternate formats
        let altFormatter = DateFormatter()
        altFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        if let date = altFormatter.date(from: created_at) {
            return date
        }
        
        altFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return altFormatter.date(from: created_at)
    }
}

// MARK: - Factory Methods

public extension NightscoutAlgorithmDataSource {
    
    /// Create from URL string with optional credentials.
    /// - Parameters:
    ///   - urlString: Nightscout site URL as string
    ///   - apiSecret: Optional API secret
    /// - Returns: NightscoutAlgorithmDataSource or nil if URL is invalid
    static func create(
        urlString: String,
        apiSecret: String? = nil
    ) -> NightscoutAlgorithmDataSource? {
        guard let url = URL(string: urlString) else { return nil }
        return NightscoutAlgorithmDataSource(url: url, apiSecret: apiSecret)
    }
}
