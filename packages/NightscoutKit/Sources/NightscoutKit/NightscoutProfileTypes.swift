// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutProfileTypes.swift
// NightscoutKit
//
// Profile types for Nightscout API
// Extracted from NightscoutClient.swift (NS-REFACTOR-002)
// Requirements: REQ-NS-006

import Foundation
import T1PalCore

// MARK: - Profile Query

/// Query parameters for profile API
public struct ProfileQuery: Sendable {
    public var count: Int?
    public var dateFrom: Date?
    public var dateTo: Date?
    
    public init(
        count: Int? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil
    ) {
        self.count = count
        self.dateFrom = dateFrom
        self.dateTo = dateTo
    }
    
    /// Build query items for URL
    func toQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        
        if let count = count {
            items.append(URLQueryItem(name: "count", value: String(count)))
        }
        
        if let dateFrom = dateFrom {
            let formatter = ISO8601DateFormatter()
            items.append(URLQueryItem(name: "find[startDate][$gte]", value: formatter.string(from: dateFrom)))
        }
        
        if let dateTo = dateTo {
            let formatter = ISO8601DateFormatter()
            items.append(URLQueryItem(name: "find[startDate][$lte]", value: formatter.string(from: dateTo)))
        }
        
        return items
    }
}

// MARK: - Nightscout Profile

/// Nightscout profile document
public struct NightscoutProfile: Codable, Sendable, Hashable {
    public let _id: String?
    public let defaultProfile: String
    public let startDate: String
    public let mills: Int64?
    public let units: String?
    public let store: [String: ProfileStore]
    public let created_at: String?
    public let enteredBy: String?
    /// Loop-specific settings (optional, present in Loop-uploaded profiles)
    public let loopSettings: LoopSettings?
    
    enum CodingKeys: String, CodingKey {
        case _id, defaultProfile, startDate, mills, units, store, created_at, enteredBy, loopSettings
    }
    
    public init(
        _id: String? = nil,
        defaultProfile: String,
        startDate: String,
        mills: Int64? = nil,
        units: String? = nil,
        store: [String: ProfileStore],
        created_at: String? = nil,
        enteredBy: String? = nil,
        loopSettings: LoopSettings? = nil
    ) {
        self._id = _id
        self.defaultProfile = defaultProfile
        self.startDate = startDate
        self.mills = mills
        self.units = units
        self.store = store
        self.created_at = created_at
        self.enteredBy = enteredBy
        self.loopSettings = loopSettings
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        _id = try container.decodeIfPresent(String.self, forKey: ._id)
        defaultProfile = try container.decode(String.self, forKey: .defaultProfile)
        startDate = try container.decode(String.self, forKey: .startDate)
        units = try container.decodeIfPresent(String.self, forKey: .units)
        store = try container.decode([String: ProfileStore].self, forKey: .store)
        created_at = try container.decodeIfPresent(String.self, forKey: .created_at)
        enteredBy = try container.decodeIfPresent(String.self, forKey: .enteredBy)
        loopSettings = try container.decodeIfPresent(LoopSettings.self, forKey: .loopSettings)
        
        // mills can be Int64 or String in JSON
        if let intMills = try? container.decode(Int64.self, forKey: .mills) {
            mills = intMills
        } else if let stringMills = try? container.decode(String.self, forKey: .mills),
                  let parsed = Int64(stringMills) {
            mills = parsed
        } else {
            mills = nil
        }
    }
    
    /// Get the active profile store
    public var activeProfile: ProfileStore? {
        store[defaultProfile]
    }
    
    /// Start date as Date
    public var timestamp: Date? {
        if let mills = mills {
            return Date(timeIntervalSince1970: Double(mills) / 1000)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: startDate) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: startDate)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(startDate)
        hasher.combine(defaultProfile)
    }
    
    public static func == (lhs: NightscoutProfile, rhs: NightscoutProfile) -> Bool {
        lhs.startDate == rhs.startDate && lhs.defaultProfile == rhs.defaultProfile
    }
}

// MARK: - Profile Store

/// Profile store containing therapy settings
public struct ProfileStore: Codable, Sendable, Hashable {
    public let dia: Double?                     // Duration of Insulin Action (hours)
    public let carbratio: [ScheduleEntry]?      // Carb ratios (g/U)
    public let sens: [ScheduleEntry]?           // Insulin sensitivity (mg/dL/U or mmol/L/U)
    public let basal: [ScheduleEntry]?          // Basal rates (U/hr)
    public let target_low: [ScheduleEntry]?     // Target low
    public let target_high: [ScheduleEntry]?    // Target high
    public let timezone: String?
    public let units: String?                   // "mg/dL" or "mmol/L"
    public let startDate: String?
    public let carbs_hr: Double?                // Max carbs absorption rate (g/hr)
    public let delay: Double?                   // Carb absorption delay (minutes)
    
    enum CodingKeys: String, CodingKey {
        case dia, carbratio, sens, basal, target_low, target_high
        case timezone, units, startDate, carbs_hr, delay
    }
    
    public init(
        dia: Double? = nil,
        carbratio: [ScheduleEntry]? = nil,
        sens: [ScheduleEntry]? = nil,
        basal: [ScheduleEntry]? = nil,
        target_low: [ScheduleEntry]? = nil,
        target_high: [ScheduleEntry]? = nil,
        timezone: String? = nil,
        units: String? = nil,
        startDate: String? = nil,
        carbs_hr: Double? = nil,
        delay: Double? = nil
    ) {
        self.dia = dia
        self.carbratio = carbratio
        self.sens = sens
        self.basal = basal
        self.target_low = target_low
        self.target_high = target_high
        self.timezone = timezone
        self.units = units
        self.startDate = startDate
        self.carbs_hr = carbs_hr
        self.delay = delay
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        dia = try container.decodeIfPresent(Double.self, forKey: .dia)
        carbratio = try container.decodeIfPresent([ScheduleEntry].self, forKey: .carbratio)
        sens = try container.decodeIfPresent([ScheduleEntry].self, forKey: .sens)
        basal = try container.decodeIfPresent([ScheduleEntry].self, forKey: .basal)
        target_low = try container.decodeIfPresent([ScheduleEntry].self, forKey: .target_low)
        target_high = try container.decodeIfPresent([ScheduleEntry].self, forKey: .target_high)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        units = try container.decodeIfPresent(String.self, forKey: .units)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        
        // carbs_hr can be Double or String in JSON (NS-ALGO-020)
        if let doubleVal = try? container.decode(Double.self, forKey: .carbs_hr) {
            carbs_hr = doubleVal
        } else if let stringVal = try? container.decode(String.self, forKey: .carbs_hr),
                  let parsed = Double(stringVal) {
            carbs_hr = parsed
        } else {
            carbs_hr = nil
        }
        
        // delay can be Double or String in JSON (NS-ALGO-020)
        if let doubleVal = try? container.decode(Double.self, forKey: .delay) {
            delay = doubleVal
        } else if let stringVal = try? container.decode(String.self, forKey: .delay),
                  let parsed = Double(stringVal) {
            delay = parsed
        } else {
            delay = nil
        }
    }
    
    /// Total daily basal rate
    public var totalDailyBasal: Double? {
        guard let basal = basal, !basal.isEmpty else { return nil }
        
        var total: Double = 0
        for i in 0..<basal.count {
            let entry = basal[i]
            let nextStart = i + 1 < basal.count ? basal[i + 1].timeAsSeconds ?? 86400 : 86400
            let duration = Double(nextStart - (entry.timeAsSeconds ?? 0)) / 3600
            total += (entry.value ?? 0) * duration
        }
        return total
    }
    
    // MARK: - NS-ALGO-022: Time-of-day Schedule Lookup
    
    /// Get the schedule value active at a specific time of day.
    /// Schedules are sorted by timeAsSeconds; returns the last entry whose start time <= query time.
    /// - Parameters:
    ///   - date: The date/time to query (uses time-of-day component)
    ///   - schedule: The schedule array to search (e.g., sens, carbratio, basal)
    ///   - profileTimezone: Optional timezone identifier for the profile (defaults to current)
    /// - Returns: The value from the active schedule entry, or nil if schedule is empty
    public func valueAt(date: Date, from schedule: [ScheduleEntry]?, profileTimezone: String? = nil) -> Double? {
        guard let schedule = schedule, !schedule.isEmpty else { return nil }
        
        // Get seconds from midnight in the profile's timezone
        let tz: TimeZone
        if let tzId = profileTimezone ?? timezone, let parsedTz = TimeZone(identifier: tzId) {
            tz = parsedTz
        } else {
            tz = TimeZone.current
        }
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let secondsFromMidnight = (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
        
        // Find the last entry whose start time <= current time
        // Schedule entries should be sorted by timeAsSeconds
        var activeEntry: ScheduleEntry? = nil
        for entry in schedule {
            let entrySeconds = entry.timeAsSeconds ?? entry.minutesFromMidnight.map { $0 * 60 } ?? 0
            if entrySeconds <= secondsFromMidnight {
                activeEntry = entry
            } else {
                break
            }
        }
        
        // If no entry found (current time before first entry), wrap to last entry of previous day
        if activeEntry == nil {
            activeEntry = schedule.last
        }
        
        return activeEntry?.value
    }
    
    /// Convenience: Get ISF at a specific time
    public func isfAt(date: Date) -> Double? {
        valueAt(date: date, from: sens)
    }
    
    /// Convenience: Get carb ratio at a specific time
    public func carbRatioAt(date: Date) -> Double? {
        valueAt(date: date, from: carbratio)
    }
    
    /// Convenience: Get basal rate at a specific time
    public func basalAt(date: Date) -> Double? {
        valueAt(date: date, from: basal)
    }
    
    /// Convenience: Get target low at a specific time
    public func targetLowAt(date: Date) -> Double? {
        valueAt(date: date, from: target_low)
    }
    
    /// Convenience: Get target high at a specific time
    public func targetHighAt(date: Date) -> Double? {
        valueAt(date: date, from: target_high)
    }
}

// MARK: - Schedule Entry

/// Schedule entry for time-based values
public struct ScheduleEntry: Codable, Sendable, Hashable {
    public let time: String?           // "HH:mm" or seconds from midnight
    public let timeAsSeconds: Int?     // Seconds from midnight
    public let value: Double?
    
    public init(time: String? = nil, timeAsSeconds: Int? = nil, value: Double? = nil) {
        self.time = time
        self.timeAsSeconds = timeAsSeconds
        self.value = value
    }
    
    /// Time as minutes from midnight
    public var minutesFromMidnight: Int? {
        if let seconds = timeAsSeconds {
            return seconds / 60
        }
        guard let time = time else { return nil }
        let parts = time.split(separator: ":")
        guard parts.count >= 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else { return nil }
        return hours * 60 + minutes
    }
}

// MARK: - Loop Settings

/// Loop-specific settings stored in Nightscout profile
/// Includes dosing constraints, strategy, and override presets
public struct LoopSettings: Codable, Sendable, Hashable {
    /// Maximum basal rate the algorithm can set (U/hr)
    public let maximumBasalRatePerHour: Double?
    
    /// Maximum bolus the algorithm can recommend (U)
    public let maximumBolus: Double?
    
    /// Suspend threshold - glucose below this suspends delivery (mg/dL or mmol/L)
    public let minimumBGGuard: Double?
    
    /// Dosing strategy: "tempBasalOnly" or "automaticBolus"
    public let dosingStrategy: String?
    
    /// Whether closed-loop dosing is enabled
    public let dosingEnabled: Bool?
    
    /// Pre-meal target override range
    public let preMealTargetRange: [Double]?
    
    /// Workout/exercise target override range
    public let legacyWorkoutTargetRange: [Double]?
    
    public init(
        maximumBasalRatePerHour: Double? = nil,
        maximumBolus: Double? = nil,
        minimumBGGuard: Double? = nil,
        dosingStrategy: String? = nil,
        dosingEnabled: Bool? = nil,
        preMealTargetRange: [Double]? = nil,
        legacyWorkoutTargetRange: [Double]? = nil
    ) {
        self.maximumBasalRatePerHour = maximumBasalRatePerHour
        self.maximumBolus = maximumBolus
        self.minimumBGGuard = minimumBGGuard
        self.dosingStrategy = dosingStrategy
        self.dosingEnabled = dosingEnabled
        self.preMealTargetRange = preMealTargetRange
        self.legacyWorkoutTargetRange = legacyWorkoutTargetRange
    }
    
    /// Whether using automatic bolus dosing (SMB-like)
    public var isAutomaticBolus: Bool {
        dosingStrategy == "automaticBolus"
    }
    
    /// Whether using temp basal only dosing
    public var isTempBasalOnly: Bool {
        dosingStrategy == "tempBasalOnly" || dosingStrategy == nil
    }
}

// MARK: - Nightscout Error

/// Errors that can occur during Nightscout API operations.
public enum NightscoutError: Error, LocalizedError, @unchecked Sendable {
    case uploadFailed
    case fetchFailed
    case unauthorized
    case invalidResponse
    case notAvailableOnLinux
    case httpError(statusCode: Int, body: String?)
    case decodingError(underlyingError: Error, rawResponse: String?)
    
    public var errorDescription: String? {
        switch self {
        case .uploadFailed:
            return "Failed to upload data to Nightscout"
        case .fetchFailed:
            return "Failed to fetch data from Nightscout"
        case .unauthorized:
            return "Unauthorized - check API secret"
        case .invalidResponse:
            return "Invalid response from server"
        case .notAvailableOnLinux:
            return "This feature is not available on Linux"
        case .httpError(let statusCode, let body):
            var msg = "HTTP \(statusCode)"
            if let body = body, !body.isEmpty {
                msg += ": \(body.prefix(200))"
            }
            return msg
        case .decodingError(let error, let rawResponse):
            var msg = "JSON decoding failed: \(error.localizedDescription)"
            if let raw = rawResponse {
                msg += "\nRaw response: \(raw.prefix(500))"
            }
            return msg
        }
    }
}

// MARK: - T1PalErrorProtocol Conformance

extension NightscoutError: T1PalErrorProtocol {
    public var domain: T1PalErrorDomain { .network }
    
    public var code: String {
        switch self {
        case .uploadFailed: return "NS-UPLOAD-001"
        case .fetchFailed: return "NS-FETCH-001"
        case .unauthorized: return "NS-AUTH-001"
        case .invalidResponse: return "NS-RESPONSE-001"
        case .notAvailableOnLinux: return "NS-PLATFORM-001"
        case .httpError(let statusCode, _): return "NS-HTTP-\(statusCode)"
        case .decodingError: return "NS-DECODE-001"
        }
    }
    
    public var severity: T1PalErrorSeverity {
        switch self {
        case .unauthorized: return .critical
        case .notAvailableOnLinux: return .warning
        default: return .error
        }
    }
    
    public var recoveryAction: T1PalRecoveryAction {
        switch self {
        case .uploadFailed, .fetchFailed: return .checkNetwork
        case .unauthorized: return .reauthenticate
        case .invalidResponse, .decodingError: return .retry
        case .notAvailableOnLinux: return .none
        case .httpError(let statusCode, _):
            if statusCode >= 500 { return .waitAndRetry }
            if statusCode == 401 || statusCode == 403 { return .reauthenticate }
            return .checkNetwork
        }
    }
    
    public var userDescription: String {
        errorDescription ?? "Unknown Nightscout error"
    }
}
