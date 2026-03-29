// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ProfileConverter.swift
// NightscoutKit
//
// Converts Nightscout profiles to AlgorithmProfile format for T1Pal
// Trace: CONTROL-001, agent-control-plane-integration.md

import Foundation
import T1PalAlgorithm

// MARK: - Profile Converter

/// Converts between Nightscout ProfileStore and T1Pal AlgorithmProfile formats
public struct ProfileConverter: Sendable {
    
    /// Conversion configuration
    public struct Config: Sendable {
        /// Default DIA when not specified in profile
        public let defaultDIA: Double
        
        /// Default max basal rate when not specified
        public let defaultMaxBasal: Double
        
        /// Default max bolus when not specified
        public let defaultMaxBolus: Double
        
        /// Default max IOB when not specified
        public let defaultMaxIOB: Double
        
        /// Default max COB when not specified
        public let defaultMaxCOB: Double
        
        /// Default autosens max multiplier
        public let defaultAutosensMax: Double
        
        /// Default autosens min multiplier
        public let defaultAutosensMin: Double
        
        /// Factor to convert mmol/L to mg/dL
        public static let mmolToMgdl: Double = 18.0182
        
        public init(
            defaultDIA: Double = 5.0,
            defaultMaxBasal: Double = 2.0,
            defaultMaxBolus: Double = 10.0,
            defaultMaxIOB: Double = 8.0,
            defaultMaxCOB: Double = 120.0,
            defaultAutosensMax: Double = 1.2,
            defaultAutosensMin: Double = 0.8
        ) {
            self.defaultDIA = defaultDIA
            self.defaultMaxBasal = defaultMaxBasal
            self.defaultMaxBolus = defaultMaxBolus
            self.defaultMaxIOB = defaultMaxIOB
            self.defaultMaxCOB = defaultMaxCOB
            self.defaultAutosensMax = defaultAutosensMax
            self.defaultAutosensMin = defaultAutosensMin
        }
        
        public static let `default` = Config()
    }
    
    public let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    // MARK: - Conversion Errors
    
    /// Errors that can occur during conversion
    public enum ConversionError: Error, CustomStringConvertible, Sendable {
        case emptyBasalSchedule
        case emptySensSchedule
        case emptyCarbRatioSchedule
        case emptyTargetSchedule
        case invalidScheduleEntry(String)
        case unsupportedUnits(String)
        
        public var description: String {
            switch self {
            case .emptyBasalSchedule:
                return "Profile has no basal schedule entries"
            case .emptySensSchedule:
                return "Profile has no sensitivity (ISF) schedule entries"
            case .emptyCarbRatioSchedule:
                return "Profile has no carb ratio schedule entries"
            case .emptyTargetSchedule:
                return "Profile has no target schedule entries"
            case .invalidScheduleEntry(let detail):
                return "Invalid schedule entry: \(detail)"
            case .unsupportedUnits(let units):
                return "Unsupported units: \(units)"
            }
        }
    }
    
    // MARK: - ProfileStore → AlgorithmProfile
    
    /// Convert a Nightscout ProfileStore to an AlgorithmProfile
    /// - Parameters:
    ///   - store: The Nightscout profile store
    ///   - name: Profile name (default: "Nightscout Profile")
    /// - Returns: An AlgorithmProfile ready for use with the algorithm
    /// - Throws: ConversionError if required fields are missing
    public func convert(
        _ store: ProfileStore,
        name: String = "Nightscout Profile"
    ) throws -> AlgorithmProfile {
        
        let units = store.units ?? "mg/dL"
        let isMMOL = units.lowercased().contains("mmol")
        
        // Convert basal schedule
        let basalSchedule = try convertBasalSchedule(store.basal)
        
        // Convert sensitivity (ISF) schedule with unit conversion
        let isfSchedule = try convertISFSchedule(store.sens, isMMOL: isMMOL)
        
        // Convert carb ratio schedule
        let icrSchedule = try convertICRSchedule(store.carbratio)
        
        // Convert target schedule with unit conversion
        let targetSchedule = try convertTargetSchedule(
            low: store.target_low,
            high: store.target_high,
            isMMOL: isMMOL
        )
        
        // Get DIA (with default)
        let dia = store.dia ?? config.defaultDIA
        
        // Get timezone (with default)
        let timezone = store.timezone ?? "UTC"
        
        return AlgorithmProfile(
            name: name,
            timezone: timezone,
            dia: dia,
            basalSchedule: basalSchedule,
            isfSchedule: isfSchedule,
            icrSchedule: icrSchedule,
            targetSchedule: targetSchedule,
            maxBasal: config.defaultMaxBasal,
            maxBolus: config.defaultMaxBolus,
            maxIOB: config.defaultMaxIOB,
            maxCOB: config.defaultMaxCOB,
            autosensMax: config.defaultAutosensMax,
            autosensMin: config.defaultAutosensMin
        )
    }
    
    // MARK: - Schedule Conversions
    
    /// Convert Nightscout schedule entries to basal schedule
    private func convertBasalSchedule(_ entries: [ScheduleEntry]?) throws -> Schedule<BasalScheduleEntry> {
        guard let entries = entries, !entries.isEmpty else {
            throw ConversionError.emptyBasalSchedule
        }
        
        let basalEntries = try entries.map { entry -> BasalScheduleEntry in
            let startTime = try parseStartTime(entry)
            let rate = entry.value ?? 0
            return BasalScheduleEntry(startTime: startTime, rate: rate)
        }
        
        return Schedule(entries: basalEntries)
    }
    
    /// Convert Nightscout schedule entries to ISF schedule
    private func convertISFSchedule(_ entries: [ScheduleEntry]?, isMMOL: Bool) throws -> Schedule<ISFScheduleEntry> {
        guard let entries = entries, !entries.isEmpty else {
            throw ConversionError.emptySensSchedule
        }
        
        let isfEntries = try entries.map { entry -> ISFScheduleEntry in
            let startTime = try parseStartTime(entry)
            var sensitivity = entry.value ?? 50
            
            // Convert from mmol/L to mg/dL if needed
            if isMMOL {
                sensitivity *= Config.mmolToMgdl
            }
            
            return ISFScheduleEntry(startTime: startTime, sensitivity: sensitivity)
        }
        
        return Schedule(entries: isfEntries)
    }
    
    /// Convert Nightscout schedule entries to ICR schedule
    private func convertICRSchedule(_ entries: [ScheduleEntry]?) throws -> Schedule<ICRScheduleEntry> {
        guard let entries = entries, !entries.isEmpty else {
            throw ConversionError.emptyCarbRatioSchedule
        }
        
        let icrEntries = try entries.map { entry -> ICRScheduleEntry in
            let startTime = try parseStartTime(entry)
            let ratio = entry.value ?? 10
            return ICRScheduleEntry(startTime: startTime, ratio: ratio)
        }
        
        return Schedule(entries: icrEntries)
    }
    
    /// Convert Nightscout target_low and target_high to target schedule
    private func convertTargetSchedule(
        low: [ScheduleEntry]?,
        high: [ScheduleEntry]?,
        isMMOL: Bool
    ) throws -> Schedule<TargetScheduleEntry> {
        guard let lowEntries = low, !lowEntries.isEmpty else {
            throw ConversionError.emptyTargetSchedule
        }
        
        // If high is not provided, use low as both
        let highEntries = high ?? lowEntries
        
        // Match low and high entries by time
        var targetEntries: [TargetScheduleEntry] = []
        
        for lowEntry in lowEntries {
            let startTime = try parseStartTime(lowEntry)
            var lowValue = lowEntry.value ?? 100
            
            // Find matching high entry (or use low + 10)
            var highValue = lowValue + 10
            for highEntry in highEntries {
                let highStartTime = try parseStartTime(highEntry)
                if abs(highStartTime - startTime) < 60 { // Within 1 minute
                    highValue = highEntry.value ?? highValue
                    break
                }
            }
            
            // Convert from mmol/L to mg/dL if needed
            if isMMOL {
                lowValue *= Config.mmolToMgdl
                highValue *= Config.mmolToMgdl
            }
            
            targetEntries.append(TargetScheduleEntry(
                startTime: startTime,
                low: lowValue,
                high: highValue
            ))
        }
        
        return Schedule(entries: targetEntries)
    }
    
    /// Parse start time from Nightscout ScheduleEntry
    private func parseStartTime(_ entry: ScheduleEntry) throws -> TimeInterval {
        // Try timeAsSeconds first
        if let seconds = entry.timeAsSeconds {
            return TimeInterval(seconds)
        }
        
        // Try parsing time string (HH:mm format)
        if let time = entry.time {
            if let seconds = parseTimeString(time) {
                return seconds
            }
            // Maybe it's already in seconds as a string?
            if let seconds = Double(time) {
                return seconds
            }
        }
        
        throw ConversionError.invalidScheduleEntry("Could not parse start time")
    }
    
    /// Parse time string in HH:mm format
    private func parseTimeString(_ time: String) -> TimeInterval? {
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else {
            return nil
        }
        return TimeInterval(hours * 3600 + minutes * 60)
    }
}

// MARK: - NightscoutProfile Extension

extension NightscoutProfile {
    
    /// Convert the active profile to an AlgorithmProfile
    /// - Parameters:
    ///   - converter: Profile converter with configuration
    /// - Returns: AlgorithmProfile if active profile exists and converts successfully
    /// - Throws: ConversionError if conversion fails
    public func toAlgorithmProfile(
        using converter: ProfileConverter = ProfileConverter()
    ) throws -> AlgorithmProfile? {
        guard let store = activeProfile else { return nil }
        return try converter.convert(store, name: defaultProfile)
    }
    
    /// Get all profiles as AlgorithmProfiles
    /// - Parameters:
    ///   - converter: Profile converter with configuration
    /// - Returns: Dictionary mapping profile names to AlgorithmProfiles
    public func allAsAlgorithmProfiles(
        using converter: ProfileConverter = ProfileConverter()
    ) -> [String: Result<AlgorithmProfile, Error>] {
        var results: [String: Result<AlgorithmProfile, Error>] = [:]
        
        for (name, store) in store {
            do {
                let profile = try converter.convert(store, name: name)
                results[name] = .success(profile)
            } catch {
                results[name] = .failure(error)
            }
        }
        
        return results
    }
}

// MARK: - Convenience Initializers

extension AlgorithmProfile {
    
    /// Create an AlgorithmProfile from a Nightscout ProfileStore
    /// - Parameters:
    ///   - nightscoutStore: The Nightscout profile store to convert
    ///   - name: Profile name
    ///   - config: Conversion configuration
    /// - Throws: ProfileConverter.ConversionError if required fields are missing
    public init(
        fromNightscout nightscoutStore: ProfileStore,
        name: String = "Nightscout Profile",
        config: ProfileConverter.Config = .default
    ) throws {
        let converter = ProfileConverter(config: config)
        self = try converter.convert(nightscoutStore, name: name)
    }
}
