// SPDX-License-Identifier: AGPL-3.0-or-later
//
// NightscoutClient.swift
// T1Pal Mobile
//
// Nightscout REST API client
// Requirements: REQ-AID-004, REQ-CGM-004

import Foundation
import T1PalCore

// SyncIdentifierGenerator moved to SyncIdentifierGenerator.swift (NS-REFACTOR-003)

/// Nightscout server configuration
public struct NightscoutConfig: Codable, Sendable {
    public let url: URL
    public let apiSecret: String?
    public let token: String?
    
    public init(url: URL, apiSecret: String? = nil, token: String? = nil) {
        self.url = url
        self.apiSecret = apiSecret
        self.token = token
    }
    
    /// API secret hash for authorization header
    public var apiSecretHash: String? {
        guard let secret = apiSecret else { return nil }
        return secret.sha1()
    }
}

/// Entry type enumeration
public enum NightscoutEntryType: String, Codable, Sendable {
    case sgv    // Sensor glucose value
    case mbg    // Meter blood glucose
    case cal    // Calibration
    case sensor // Sensor event
}

/// Query parameters for entries API
public struct EntriesQuery: Sendable {
    public var count: Int?
    public var dateFrom: Date?
    public var dateTo: Date?
    public var type: NightscoutEntryType?
    public var find: String?  // Raw MongoDB find expression
    
    public init(
        count: Int? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        type: NightscoutEntryType? = nil,
        find: String? = nil
    ) {
        self.count = count
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.type = type
        self.find = find
    }
    
    /// Build query items for URL
    func toQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        
        if let count = count {
            items.append(URLQueryItem(name: "count", value: String(count)))
        }
        
        if let dateFrom = dateFrom {
            let ts = Int64(dateFrom.timeIntervalSince1970 * 1000)
            items.append(URLQueryItem(name: "find[date][$gte]", value: String(ts)))
        }
        
        if let dateTo = dateTo {
            let ts = Int64(dateTo.timeIntervalSince1970 * 1000)
            items.append(URLQueryItem(name: "find[date][$lte]", value: String(ts)))
        }
        
        if let type = type {
            items.append(URLQueryItem(name: "find[type]", value: type.rawValue))
        }
        
        if let find = find {
            items.append(URLQueryItem(name: "find", value: find))
        }
        
        return items
    }
}

/// Nightscout entry (glucose reading)
public struct NightscoutEntry: Codable, Sendable, Hashable {
    public let _id: String?
    public let type: String
    public let sgv: Int?
    public let mbg: Int?        // Meter blood glucose value
    public let slope: Double?   // Calibration slope
    public let intercept: Double? // Calibration intercept
    public let scale: Double?   // Calibration scale
    public let direction: String?
    public let dateString: String
    public let date: Double     // Nightscout sends as float (e.g., 1770310430628.767)
    public let device: String?
    public let noise: Int?      // Signal noise level (1-4)
    public let filtered: Double? // Filtered raw value
    public let unfiltered: Double? // Unfiltered raw value
    public let rssi: Int?       // Receiver signal strength
    public let identifier: String?  // Sync identifier for deduplication (Loop/Trio pattern)
    
    public init(
        _id: String? = nil,
        type: String = "sgv",
        sgv: Int? = nil,
        mbg: Int? = nil,
        slope: Double? = nil,
        intercept: Double? = nil,
        scale: Double? = nil,
        direction: String? = nil,
        dateString: String,
        date: Double,
        device: String? = nil,
        noise: Int? = nil,
        filtered: Double? = nil,
        unfiltered: Double? = nil,
        rssi: Int? = nil,
        identifier: String? = nil
    ) {
        self._id = _id
        self.type = type
        self.sgv = sgv
        self.mbg = mbg
        self.slope = slope
        self.intercept = intercept
        self.scale = scale
        self.direction = direction
        self.dateString = dateString
        self.date = date
        self.device = device
        self.noise = noise
        self.filtered = filtered
        self.unfiltered = unfiltered
        self.rssi = rssi
        self.identifier = identifier
    }
    
    /// Generate sync identifier for deduplication
    /// Pattern: "{device}:{type}:{timestamp}" or UUID if no device
    public var syncIdentifier: String {
        identifier ?? SyncIdentifierGenerator.forEntry(date: date, type: type, device: device)
    }
    
    /// Entry type as enum
    public var entryType: NightscoutEntryType? {
        NightscoutEntryType(rawValue: type)
    }
    
    /// Timestamp as Date
    public var timestamp: Date {
        Date(timeIntervalSince1970: date / 1000)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(syncIdentifier)
    }
    
    public static func == (lhs: NightscoutEntry, rhs: NightscoutEntry) -> Bool {
        lhs.syncIdentifier == rhs.syncIdentifier
    }
    
    /// Convert to core GlucoseReading
    public func toGlucoseReading() -> GlucoseReading? {
        guard let glucose = sgv else { return nil }
        
        let trend: GlucoseTrend
        switch direction?.lowercased() {
        case "doubleup": trend = .doubleUp
        case "singleup": trend = .singleUp
        case "fortyfiveup": trend = .fortyFiveUp
        case "flat": trend = .flat
        case "fortyfivedown": trend = .fortyFiveDown
        case "singledown": trend = .singleDown
        case "doubledown": trend = .doubleDown
        default: trend = .notComputable
        }
        
        return GlucoseReading(
            glucose: Double(glucose),
            timestamp: Date(timeIntervalSince1970: Double(date) / 1000),
            trend: trend,
            source: device ?? "nightscout"
        )
    }
}

/// Treatment event types from Nightscout
public enum TreatmentEventType: String, Codable, Sendable, CaseIterable {
    // Insulin
    case correctionBolus = "Correction Bolus"
    case mealBolus = "Meal Bolus"
    case snackBolus = "Snack Bolus"
    case bolus = "Bolus"
    case comboBolus = "Combo Bolus"
    case smb = "SMB"  // AAPS Super Micro Bolus (NS-TH-003)
    
    // Temp basal
    case tempBasal = "Temp Basal"
    case tempBasalStart = "Temp Basal Start"
    case tempBasalEnd = "Temp Basal End"
    
    // Carbs
    case carbCorrection = "Carb Correction"
    case mealCarbs = "Meal"
    case snackCarbs = "Snack"
    
    // Profile
    case profileSwitch = "Profile Switch"
    case temporaryTarget = "Temporary Target"
    
    // Pump events
    case pumpSiteChange = "Site Change"
    case pumpBatteryChange = "Pump Battery Change"
    case insulinChange = "Insulin Change"
    case sensorStart = "Sensor Start"
    case sensorChange = "Sensor Change"
    
    // CGM calibration
    case bgCheck = "BG Check"
    case fingerBG = "Finger"
    
    // Notes/announcements
    case note = "Note"
    case announcement = "Announcement"
    case question = "Question"
    case exercise = "Exercise"
    case suspend = "Suspend Pump"
    case resume = "Resume Pump"
    
    // OpenAPS/Loop specific
    case openapsOffline = "OpenAPS Offline"
    case loopOffline = "Loop Offline"
}

/// Query parameters for treatments API
public struct TreatmentsQuery: Sendable {
    public var count: Int?
    public var dateFrom: Date?
    public var dateTo: Date?
    public var eventType: TreatmentEventType?
    public var eventTypes: [TreatmentEventType]?
    public var find: String?
    
    public init(
        count: Int? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        eventType: TreatmentEventType? = nil,
        eventTypes: [TreatmentEventType]? = nil,
        find: String? = nil
    ) {
        self.count = count
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.eventType = eventType
        self.eventTypes = eventTypes
        self.find = find
    }
    
    /// Build query items for URL
    func toQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        
        if let count = count {
            items.append(URLQueryItem(name: "count", value: String(count)))
        }
        
        if let dateFrom = dateFrom {
            let formatter = ISO8601DateFormatter()
            items.append(URLQueryItem(name: "find[created_at][$gte]", value: formatter.string(from: dateFrom)))
        }
        
        if let dateTo = dateTo {
            let formatter = ISO8601DateFormatter()
            items.append(URLQueryItem(name: "find[created_at][$lte]", value: formatter.string(from: dateTo)))
        }
        
        if let eventType = eventType {
            items.append(URLQueryItem(name: "find[eventType]", value: eventType.rawValue))
        }
        
        if let find = find {
            items.append(URLQueryItem(name: "find", value: find))
        }
        
        return items
    }
}

/// Nightscout treatment (bolus, temp basal, etc)
public struct NightscoutTreatment: Codable, Sendable, Hashable {
    public let _id: String?
    public let eventType: String
    public let created_at: String
    public let insulin: Double?
    public let carbs: Double?
    public let duration: Double?
    public let absolute: Double?
    public let rate: Double?
    public let percent: Double?         // For temp basal percentage
    public let profileIndex: Int?       // For profile switch
    public let profile: String?         // Profile name for profile switch
    public let targetTop: Double?       // For temp target
    public let targetBottom: Double?    // For temp target
    public let glucose: Double?         // For BG check
    public let glucoseType: String?     // "Finger", "Sensor"
    public let units: String?           // mg/dL or mmol/L
    public let enteredBy: String?       // Source device/app
    public let notes: String?
    public let reason: String?          // For temp target
    public let preBolus: Double?        // Pre-bolus time in minutes
    public let splitNow: Double?        // Combo bolus split now %
    public let splitExt: Double?        // Combo bolus split extended %
    public let identifier: String?      // Sync identifier for deduplication (Loop/Trio pattern)
    
    public init(
        _id: String? = nil,
        eventType: String,
        created_at: String,
        insulin: Double? = nil,
        carbs: Double? = nil,
        duration: Double? = nil,
        absolute: Double? = nil,
        rate: Double? = nil,
        percent: Double? = nil,
        profileIndex: Int? = nil,
        profile: String? = nil,
        targetTop: Double? = nil,
        targetBottom: Double? = nil,
        glucose: Double? = nil,
        glucoseType: String? = nil,
        units: String? = nil,
        enteredBy: String? = nil,
        notes: String? = nil,
        reason: String? = nil,
        preBolus: Double? = nil,
        splitNow: Double? = nil,
        splitExt: Double? = nil,
        identifier: String? = nil
    ) {
        self._id = _id
        self.eventType = eventType
        self.created_at = created_at
        self.insulin = insulin
        self.carbs = carbs
        self.duration = duration
        self.absolute = absolute
        self.rate = rate
        self.percent = percent
        self.profileIndex = profileIndex
        self.profile = profile
        self.targetTop = targetTop
        self.targetBottom = targetBottom
        self.glucose = glucose
        self.glucoseType = glucoseType
        self.units = units
        self.enteredBy = enteredBy
        self.notes = notes
        self.reason = reason
        self.preBolus = preBolus
        self.splitNow = splitNow
        self.splitExt = splitExt
        self.identifier = identifier
    }
    
    /// Generate sync identifier for deduplication
    /// Pattern: "{enteredBy}:{eventType}:{timestamp}" or UUID if no enteredBy
    public var syncIdentifier: String {
        identifier ?? SyncIdentifierGenerator.forTreatment(createdAt: created_at, eventType: eventType, enteredBy: enteredBy)
    }
    
    /// Event type as enum
    public var treatmentEventType: TreatmentEventType? {
        TreatmentEventType(rawValue: eventType)
    }
    
    /// Timestamp as Date
    public var timestamp: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: created_at) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: created_at)
    }
    
    /// Check if this is an insulin treatment
    public var isInsulinTreatment: Bool {
        insulin != nil && insulin! > 0
    }
    
    /// Check if this is a carb treatment
    public var isCarbTreatment: Bool {
        carbs != nil && carbs! > 0
    }
    
    /// Check if this is a temp basal
    public var isTempBasal: Bool {
        eventType.contains("Temp Basal") && (absolute != nil || rate != nil || percent != nil)
    }
    
    /// Check if this is a pump suspend event
    /// IOB-SUSPEND-001: Suspend events represent rate=0 delivery
    public var isSuspend: Bool {
        eventType == "Suspend Pump"
    }
    
    /// Check if this is a pump resume event
    public var isResume: Bool {
        eventType == "Resume Pump"
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(syncIdentifier)
    }
    
    public static func == (lhs: NightscoutTreatment, rhs: NightscoutTreatment) -> Bool {
        lhs.syncIdentifier == rhs.syncIdentifier
    }
}

// DeviceStatusQuery and NightscoutDeviceStatus moved to DeviceStatusTypes.swift (NS-REFACTOR-001)

// ProfileQuery, NightscoutProfile, ProfileStore, ScheduleEntry, NightscoutError moved to NightscoutProfileTypes.swift (NS-REFACTOR-002)

// MARK: - Network Client (Apple platforms only)

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if os(iOS) || os(macOS) || os(watchOS) || os(tvOS)

/// Nightscout REST client (Apple platforms)
/// Requirements: REQ-AID-004, REQ-CGM-004
/// Trace: OBS-011 - Fault injection support via NetworkConditionSimulator
public actor NightscoutClient {
    private let config: NightscoutConfig
    private let session: URLSession
    
    /// Optional fault injector for testing network conditions (OBS-011)
    public var faultInjector: NetworkConditionSimulator?
    
    public init(config: NightscoutConfig, session: URLSession = .shared, faultInjector: NetworkConditionSimulator? = nil) {
        self.config = config
        self.session = session
        self.faultInjector = faultInjector
    }
    
    /// Set the fault injector for testing (OBS-011)
    public func setFaultInjector(_ injector: NetworkConditionSimulator?) {
        self.faultInjector = injector
    }
    
    /// Apply fault injection before a network request (OBS-011)
    private func applyFaultInjection(for path: String) async throws {
        if let injector = faultInjector {
            try await injector.applyAndWait(for: path)
        }
    }
    
    /// Fetch recent entries (glucose readings)
    public func fetchEntries(count: Int = 36) async throws -> [NightscoutEntry] {
        try await fetchEntries(query: EntriesQuery(count: count))
    }
    
    /// Fetch entries with query parameters
    public func fetchEntries(query: EntriesQuery) async throws -> [NightscoutEntry] {
        // Use entries.json for all types, sgv.json only for SGV-specific
        let endpoint = query.type == nil || query.type == .sgv ? "api/v1/entries/sgv.json" : "api/v1/entries.json"
        var url = config.url.appendingPathComponent(endpoint)
        url.append(queryItems: query.toQueryItems())
        
        // Apply fault injection (OBS-011)
        try await applyFaultInjection(for: endpoint)
        
        var request = URLRequest(url: url)
        addAuthHeaders(&request)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NightscoutError.invalidResponse
        }
        
        let rawString = String(data: data, encoding: .utf8)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.httpError(statusCode: httpResponse.statusCode, body: rawString)
        }
        
        do {
            return try JSONDecoder().decode([NightscoutEntry].self, from: data)
        } catch {
            throw NightscoutError.decodingError(underlyingError: error, rawResponse: rawString)
        }
    }
    
    /// Fetch entries in date range
    public func fetchEntries(from: Date, to: Date, count: Int = 1000) async throws -> [NightscoutEntry] {
        try await fetchEntries(query: EntriesQuery(count: count, dateFrom: from, dateTo: to))
    }
    
    /// Upload entries
    public func uploadEntries(_ entries: [NightscoutEntry]) async throws {
        let url = config.url.appendingPathComponent("api/v1/entries")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        
        request.httpBody = try JSONEncoder().encode(entries)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.uploadFailed
        }
    }
    
    /// Fetch treatments
    public func fetchTreatments(count: Int = 100) async throws -> [NightscoutTreatment] {
        try await fetchTreatments(query: TreatmentsQuery(count: count))
    }
    
    /// Fetch treatments with query parameters
    public func fetchTreatments(query: TreatmentsQuery) async throws -> [NightscoutTreatment] {
        let endpoint = "api/v1/treatments.json"
        var url = config.url.appendingPathComponent(endpoint)
        url.append(queryItems: query.toQueryItems())
        
        // Apply fault injection (OBS-011)
        try await applyFaultInjection(for: endpoint)
        
        var request = URLRequest(url: url)
        addAuthHeaders(&request)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.fetchFailed
        }
        return try JSONDecoder().decode([NightscoutTreatment].self, from: data)
    }
    
    /// Fetch treatments in date range
    public func fetchTreatments(from: Date, to: Date, count: Int = 1000) async throws -> [NightscoutTreatment] {
        try await fetchTreatments(query: TreatmentsQuery(count: count, dateFrom: from, dateTo: to))
    }
    
    /// Fetch treatments by event type
    public func fetchTreatments(eventType: TreatmentEventType, count: Int = 100) async throws -> [NightscoutTreatment] {
        try await fetchTreatments(query: TreatmentsQuery(count: count, eventType: eventType))
    }
    
    /// Upload treatments
    public func uploadTreatments(_ treatments: [NightscoutTreatment]) async throws {
        let url = config.url.appendingPathComponent("api/v1/treatments")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        
        request.httpBody = try JSONEncoder().encode(treatments)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.uploadFailed
        }
    }
    
    /// Upload device status (for control plane reconciliation)
    public func uploadDeviceStatus(_ status: NightscoutDeviceStatus) async throws {
        let url = config.url.appendingPathComponent("api/v1/devicestatus")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        
        request.httpBody = try JSONEncoder().encode(status)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.uploadFailed
        }
    }
    
    /// Fetch device status
    public func fetchDeviceStatus(count: Int = 10) async throws -> [NightscoutDeviceStatus] {
        try await fetchDeviceStatus(query: DeviceStatusQuery(count: count))
    }
    
    /// Fetch device status with query parameters
    public func fetchDeviceStatus(query: DeviceStatusQuery) async throws -> [NightscoutDeviceStatus] {
        let endpoint = "api/v1/devicestatus.json"
        var url = config.url.appendingPathComponent(endpoint)
        url.append(queryItems: query.toQueryItems())
        
        // Apply fault injection (OBS-011)
        try await applyFaultInjection(for: endpoint)
        
        var request = URLRequest(url: url)
        addAuthHeaders(&request)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.fetchFailed
        }
        return try JSONDecoder().decode([NightscoutDeviceStatus].self, from: data)
    }
    
    /// Fetch device status in date range
    public func fetchDeviceStatus(from: Date, to: Date, count: Int = 100) async throws -> [NightscoutDeviceStatus] {
        try await fetchDeviceStatus(query: DeviceStatusQuery(count: count, dateFrom: from, dateTo: to))
    }
    
    /// Fetch profiles
    public func fetchProfiles(count: Int = 10) async throws -> [NightscoutProfile] {
        try await fetchProfiles(query: ProfileQuery(count: count))
    }
    
    /// Fetch profiles with query parameters
    public func fetchProfiles(query: ProfileQuery) async throws -> [NightscoutProfile] {
        var url = config.url.appendingPathComponent("api/v1/profile.json")
        url.append(queryItems: query.toQueryItems())
        
        var request = URLRequest(url: url)
        addAuthHeaders(&request)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.fetchFailed
        }
        return try JSONDecoder().decode([NightscoutProfile].self, from: data)
    }
    
    /// Upload profile
    public func uploadProfile(_ profile: NightscoutProfile) async throws {
        let url = config.url.appendingPathComponent("api/v1/profile")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        
        request.httpBody = try JSONEncoder().encode(profile)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NightscoutError.uploadFailed
        }
    }
    
    private func addAuthHeaders(_ request: inout URLRequest) {
        if let hash = config.apiSecretHash {
            request.setValue(hash, forHTTPHeaderField: "api-secret")
        }
        if let token = config.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

#else

/// Linux-compatible client using synchronous networking
/// Requirements: REQ-AID-004, REQ-CGM-004
/// Trace: OBS-011 - Fault injection support via NetworkConditionSimulator
public actor NightscoutClient {
    private let config: NightscoutConfig
    private let session: URLSession
    
    /// Optional fault injector for testing network conditions (OBS-011)
    public var faultInjector: NetworkConditionSimulator?
    
    public init(config: NightscoutConfig, session: URLSession = .shared, faultInjector: NetworkConditionSimulator? = nil) {
        self.config = config
        self.session = session
        self.faultInjector = faultInjector
    }
    
    /// Set the fault injector for testing (OBS-011)
    public func setFaultInjector(_ injector: NetworkConditionSimulator?) {
        self.faultInjector = injector
    }
    
    /// Apply fault injection before a network request (OBS-011)
    private func applyFaultInjection(for path: String) async throws {
        if let injector = faultInjector {
            try await injector.applyAndWait(for: path)
        }
    }
    
    /// Fetch recent entries (glucose readings)
    public func fetchEntries(count: Int = 36) async throws -> [NightscoutEntry] {
        try await fetchEntries(query: EntriesQuery(count: count))
    }
    
    /// Fetch entries with query parameters
    public func fetchEntries(query: EntriesQuery) async throws -> [NightscoutEntry] {
        let endpoint = query.type == nil || query.type == .sgv ? "api/v1/entries/sgv.json" : "api/v1/entries.json"
        var components = URLComponents(url: config.url.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = query.toQueryItems()
        
        // Apply fault injection (OBS-011)
        try await applyFaultInjection(for: endpoint)
        
        var request = URLRequest(url: components.url!)
        addAuthHeaders(&request)
        
        let (data, statusCode) = try performSyncRequestWithStatus(request)
        let rawString = String(data: data, encoding: .utf8)
        
        guard (200...299).contains(statusCode) else {
            throw NightscoutError.httpError(statusCode: statusCode, body: rawString)
        }
        
        do {
            return try JSONDecoder().decode([NightscoutEntry].self, from: data)
        } catch {
            throw NightscoutError.decodingError(underlyingError: error, rawResponse: rawString)
        }
    }
    
    /// Fetch entries in date range
    public func fetchEntries(from: Date, to: Date, count: Int = 1000) async throws -> [NightscoutEntry] {
        try await fetchEntries(query: EntriesQuery(count: count, dateFrom: from, dateTo: to))
    }
    
    /// Upload entries
    public func uploadEntries(_ entries: [NightscoutEntry]) async throws {
        let url = config.url.appendingPathComponent("api/v1/entries")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        
        request.httpBody = try JSONEncoder().encode(entries)
        
        let (_, statusCode) = try performSyncRequestWithStatus(request)
        guard (200...299).contains(statusCode) else {
            throw NightscoutError.uploadFailed
        }
    }
    
    /// Fetch treatments
    public func fetchTreatments(count: Int = 100) async throws -> [NightscoutTreatment] {
        try await fetchTreatments(query: TreatmentsQuery(count: count))
    }
    
    /// Fetch treatments with query parameters
    public func fetchTreatments(query: TreatmentsQuery) async throws -> [NightscoutTreatment] {
        let endpoint = "api/v1/treatments.json"
        var components = URLComponents(url: config.url.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = query.toQueryItems()
        
        // Apply fault injection (OBS-011)
        try await applyFaultInjection(for: endpoint)
        
        var request = URLRequest(url: components.url!)
        addAuthHeaders(&request)
        
        let (data, statusCode) = try performSyncRequestWithStatus(request)
        guard (200...299).contains(statusCode) else {
            throw NightscoutError.fetchFailed
        }
        return try JSONDecoder().decode([NightscoutTreatment].self, from: data)
    }
    
    /// Fetch treatments in date range
    public func fetchTreatments(from: Date, to: Date, count: Int = 1000) async throws -> [NightscoutTreatment] {
        try await fetchTreatments(query: TreatmentsQuery(count: count, dateFrom: from, dateTo: to))
    }
    
    /// Fetch treatments by event type
    public func fetchTreatments(eventType: TreatmentEventType, count: Int = 100) async throws -> [NightscoutTreatment] {
        try await fetchTreatments(query: TreatmentsQuery(count: count, eventType: eventType))
    }
    
    /// Upload treatments
    public func uploadTreatments(_ treatments: [NightscoutTreatment]) async throws {
        let url = config.url.appendingPathComponent("api/v1/treatments")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        
        request.httpBody = try JSONEncoder().encode(treatments)
        
        let (_, statusCode) = try performSyncRequestWithStatus(request)
        guard (200...299).contains(statusCode) else {
            throw NightscoutError.uploadFailed
        }
    }
    
    /// Upload device status (for control plane reconciliation)
    public func uploadDeviceStatus(_ status: NightscoutDeviceStatus) async throws {
        let url = config.url.appendingPathComponent("api/v1/devicestatus")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        
        request.httpBody = try JSONEncoder().encode(status)
        
        let (_, statusCode) = try performSyncRequestWithStatus(request)
        guard (200...299).contains(statusCode) else {
            throw NightscoutError.uploadFailed
        }
    }
    
    /// Fetch device status
    public func fetchDeviceStatus(count: Int = 10) async throws -> [NightscoutDeviceStatus] {
        try await fetchDeviceStatus(query: DeviceStatusQuery(count: count))
    }
    
    /// Fetch device status with query parameters
    public func fetchDeviceStatus(query: DeviceStatusQuery) async throws -> [NightscoutDeviceStatus] {
        let endpoint = "api/v1/devicestatus.json"
        var components = URLComponents(url: config.url.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        components.queryItems = query.toQueryItems()
        
        // Apply fault injection (OBS-011)
        try await applyFaultInjection(for: endpoint)
        
        var request = URLRequest(url: components.url!)
        addAuthHeaders(&request)
        
        let (data, statusCode) = try performSyncRequestWithStatus(request)
        guard (200...299).contains(statusCode) else {
            throw NightscoutError.fetchFailed
        }
        return try JSONDecoder().decode([NightscoutDeviceStatus].self, from: data)
    }
    
    /// Fetch device status in date range
    public func fetchDeviceStatus(from: Date, to: Date, count: Int = 100) async throws -> [NightscoutDeviceStatus] {
        try await fetchDeviceStatus(query: DeviceStatusQuery(count: count, dateFrom: from, dateTo: to))
    }
    
    /// Fetch profiles
    public func fetchProfiles(count: Int = 10) async throws -> [NightscoutProfile] {
        try await fetchProfiles(query: ProfileQuery(count: count))
    }
    
    /// Fetch profiles with query parameters
    public func fetchProfiles(query: ProfileQuery) async throws -> [NightscoutProfile] {
        var components = URLComponents(url: config.url.appendingPathComponent("api/v1/profile.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.toQueryItems()
        guard let url = components.url else { throw NightscoutError.invalidResponse }
        
        var request = URLRequest(url: url)
        addAuthHeaders(&request)
        
        let (data, statusCode) = try performSyncRequestWithStatus(request)
        guard (200...299).contains(statusCode) else {
            throw NightscoutError.fetchFailed
        }
        return try JSONDecoder().decode([NightscoutProfile].self, from: data)
    }
    
    /// Upload profile
    public func uploadProfile(_ profile: NightscoutProfile) async throws {
        let url = config.url.appendingPathComponent("api/v1/profile")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeaders(&request)
        
        request.httpBody = try JSONEncoder().encode(profile)
        
        let (_, statusCode) = try performSyncRequestWithStatus(request)
        guard (200...299).contains(statusCode) else {
            throw NightscoutError.uploadFailed
        }
    }
    
    private func addAuthHeaders(_ request: inout URLRequest) {
        if let hash = config.apiSecretHash {
            request.setValue(hash, forHTTPHeaderField: "api-secret")
        }
        if let token = config.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
    
    // MARK: - Sync Networking (Linux Compatibility)
    
    /// Synchronous network request for cross-platform compatibility
    ///
    /// **Why semaphores here?**
    /// - Linux's FoundationNetworking doesn't support async URLSession.data(for:)
    /// - These methods enable the same code to run on Darwin and Linux
    /// - The semaphore is intentional and necessary for cross-platform support
    ///
    /// **Thread Safety:**
    /// - ResultHolder writes occur before semaphore.signal()
    /// - ResultHolder reads occur after semaphore.wait()
    /// - This guarantees happens-before ordering per Swift memory model
    ///
    /// See: CONC-IMPL-002 in docs/backlogs/LIVE-BACKLOG.md
    private nonisolated func performSyncRequest(_ request: URLRequest) throws -> Data {
        let holder = ResultHolder()
        let semaphore = DispatchSemaphore(value: 0)
        
        let task = session.dataTask(with: request) { data, response, error in
            holder.data = data
            holder.error = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        
        if let error = holder.error {
            throw error
        }
        guard let data = holder.data else {
            throw NightscoutError.invalidResponse
        }
        return data
    }
    
    private nonisolated func performSyncRequestWithStatus(_ request: URLRequest) throws -> (Data, Int) {
        let holder = ResultHolder()
        let semaphore = DispatchSemaphore(value: 0)
        
        let task = session.dataTask(with: request) { data, response, error in
            holder.data = data
            holder.error = error
            if let httpResponse = response as? HTTPURLResponse {
                holder.statusCode = httpResponse.statusCode
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        
        if let error = holder.error {
            throw error
        }
        return (holder.data ?? Data(), holder.statusCode)
    }
}

/// Thread-safe result holder for sync network calls
/// 
/// Safety: Mutable state is protected by DispatchSemaphore ordering:
/// - All writes occur before semaphore.signal() in the callback
/// - All reads occur after semaphore.wait() on the calling thread
/// - This guarantees happens-before ordering per Swift memory model
private final class ResultHolder: @unchecked Sendable {
    var data: Data?
    var error: Error?
    var statusCode: Int = 0
}

#endif

// EntriesSyncState, EntriesSyncResult, EntriesSyncDelegate, EntriesSyncManager moved to EntriesSyncManager.swift (NS-REFACTOR-004)

// TreatmentsSyncState, TreatmentsSyncResult, TreatmentsSyncManager moved to TreatmentsSyncManager.swift (NS-REFACTOR-005)

// DeviceStatusSyncState, DeviceStatusSyncResult, DeviceStatusSyncManager moved to DeviceStatusSyncManager.swift (NS-REFACTOR-006)

// ProfileSyncState, ProfileSyncResult, ProfileSyncManager moved to ProfileSyncManager.swift (NS-REFACTOR-007)

// SHA1 implementation for API secret
extension String {
    func sha1() -> String {
        // Use pure Swift SHA1 for cross-platform support
        return SHA1.hash(self)
    }
}

// Pure Swift SHA1 implementation for cross-platform support
enum SHA1 {
    static func hash(_ string: String) -> String {
        let data = Array(string.utf8)
        return hash(data)
    }
    
    static func hash(_ data: [UInt8]) -> String {
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0
        
        // Pre-processing: adding padding bits
        var message = data
        let ml = UInt64(data.count * 8)
        
        message.append(0x80)
        while (message.count % 64) != 56 {
            message.append(0x00)
        }
        
        // Append original length in bits as 64-bit big-endian
        for i in (0..<8).reversed() {
            message.append(UInt8((ml >> (i * 8)) & 0xFF))
        }
        
        // Process each 64-byte chunk
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            
            // Break chunk into sixteen 32-bit big-endian words
            for i in 0..<16 {
                let offset = chunkStart + i * 4
                w[i] = UInt32(message[offset]) << 24 |
                       UInt32(message[offset + 1]) << 16 |
                       UInt32(message[offset + 2]) << 8 |
                       UInt32(message[offset + 3])
            }
            
            // Extend the sixteen 32-bit words into eighty 32-bit words
            for i in 16..<80 {
                w[i] = leftRotate(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], by: 1)
            }
            
            var a = h0, b = h1, c = h2, d = h3, e = h4
            
            for i in 0..<80 {
                var f: UInt32
                var k: UInt32
                
                switch i {
                case 0..<20:
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                
                let temp = leftRotate(a, by: 5) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = leftRotate(b, by: 30)
                b = a
                a = temp
            }
            
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }
        
        return String(format: "%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
    }
    
    private static func leftRotate(_ value: UInt32, by bits: UInt32) -> UInt32 {
        return (value << bits) | (value >> (32 - bits))
    }
}


// NightscoutSocketEvent, NightscoutSocketMessage, NightscoutSocketState, NightscoutSocketDelegate, NightscoutSocket, NightscoutRealtimeCoordinator moved to NightscoutWebSocket.swift (NS-REFACTOR-008)
// RemoteCommandType, RemoteCommand, RemoteCommandResult, RemoteCommandError, RemoteCommandManager moved to RemoteCommandHandler.swift (NS-REFACTOR-009)
// NetworkState, OfflineOperationType, OfflineQueueItem, OfflineQueueResult, OfflineQueue, OfflineSyncCoordinator moved to OfflineSupport.swift (NS-REFACTOR-010)
// NightscoutDiscoveryResult, NightscoutDiscoveryError, NightscoutServerStatus, NightscoutSettings, NightscoutAuthResult, NightscoutDiscovery, NightscoutUrlParser moved to NightscoutDiscovery.swift (NS-REFACTOR-011)
// NightscoutAuthMode, NightscoutJWTClaims, JWTDecoder, JWTTokenManager, NightscoutPermissions, NightscoutAuthState moved to JWTTokenManager.swift (NS-REFACTOR-012)
// Note: NightscoutAuth actor and getStatusWithAuth() extension kept here due to CredentialStoring/config dependencies
// LooperProfile, InstanceRegistryEvent, InstanceRegistryObserver, InstanceRegistry, InstanceRegistryError, InstanceSwitcher, MultiInstanceAggregator, LooperQuickStatus moved to MultiLooperSupport.swift (NS-REFACTOR-013)
// CaregiverPermission, InviteStatus, CaregiverInvite, CaregiverRelationship, InviteCodeGenerator, InviteManager, InviteError, CaregiverAccessChecker moved to CaregiverInvitations.swift (NS-REFACTOR-014)

// MARK: - Nightscout Auth Manager

/// Nightscout direct authentication manager
/// Requirements: REQ-ID-005
/// Note: Kept in NightscoutClient.swift due to dependencies on CredentialStoring (T1PalCore) and private config access
public actor NightscoutAuth {
    private let discovery: NightscoutDiscovery
    private let credentialStore: any CredentialStoring
    private var authStates: [URL: NightscoutAuthState] = [:]
    
    public init(
        discovery: NightscoutDiscovery = NightscoutDiscovery(),
        credentialStore: any CredentialStoring = MemoryCredentialStore()
    ) {
        self.discovery = discovery
        self.credentialStore = credentialStore
    }
    
    /// Authenticate with API secret
    public func authenticateWithSecret(
        url: URL,
        apiSecret: String
    ) async throws -> NightscoutAuthState {
        // Validate the secret against the server
        let result = try await discovery.discover(url: url, apiSecret: apiSecret)
        
        guard result.authValid else {
            throw NightscoutDiscoveryError.authenticationFailed
        }
        
        // Create credential
        let credential = AuthCredential(
            tokenType: .apiSecret,
            value: apiSecret,
            expiresAt: nil  // API secrets don't expire
        )
        
        // Store credential
        let key = CredentialKey.nightscout(url: url)
        try await credentialStore.store(credential, for: key)
        
        // Build auth state
        let permissions = NightscoutPermissions.from(strings: Array(result.permissions))
        let state = NightscoutAuthState(
            url: url,
            mode: .apiSecret,
            isAuthenticated: true,
            permissions: permissions,
            serverName: result.serverName
        )
        
        authStates[url] = state
        return state
    }
    
    /// Authenticate with JWT token
    public func authenticateWithToken(
        url: URL,
        token: String,
        expiresAt: Date? = nil
    ) async throws -> NightscoutAuthState {
        // Validate the token
        let config = NightscoutConfig(url: url, token: token)
        let client = NightscoutClient(config: config)
        
        // Try to fetch status to validate token
        let (status, permissions) = try await client.getStatusWithAuth()
        
        guard status.apiEnabled ?? true else {
            throw NightscoutDiscoveryError.insufficientPermissions([])
        }
        
        // Create credential
        let credential = AuthCredential(
            tokenType: .access,
            value: token,
            expiresAt: expiresAt
        )
        
        // Store credential
        let key = CredentialKey.nightscout(url: url)
        try await credentialStore.store(credential, for: key)
        
        // Build auth state
        let permSet = NightscoutPermissions.from(strings: permissions)
        let state = NightscoutAuthState(
            url: url,
            mode: .jwtToken,
            isAuthenticated: true,
            permissions: permSet,
            serverName: status.name,
            expiresAt: expiresAt
        )
        
        authStates[url] = state
        return state
    }
    
    /// Get current auth state for URL
    public func getAuthState(for url: URL) -> NightscoutAuthState? {
        authStates[url]
    }
    
    /// Check if authenticated for URL
    public func isAuthenticated(for url: URL) -> Bool {
        authStates[url]?.isValid ?? false
    }
    
    /// Get stored credential for URL
    public func getCredential(for url: URL) async throws -> AuthCredential {
        let key = CredentialKey.nightscout(url: url)
        return try await credentialStore.retrieve(for: key)
    }
    
    /// Logout from URL
    public func logout(from url: URL) async throws {
        let key = CredentialKey.nightscout(url: url)
        try await credentialStore.delete(for: key)
        authStates.removeValue(forKey: url)
    }
    
    /// Get all authenticated URLs
    public func getAuthenticatedUrls() -> [URL] {
        authStates.filter { $0.value.isValid }.map { $0.key }
    }
}

// MARK: - NightscoutClient Auth Extension

/// Extension to NightscoutClient for auth validation
extension NightscoutClient {
    /// Get status with authentication info
    public func getStatusWithAuth() async throws -> (NightscoutServerStatus, [String]) {
        let statusUrl = config.url.appendingPathComponent("/api/v1/status.json")
        
        var request = URLRequest(url: statusUrl)
        request.httpMethod = "GET"
        
        // Add auth header if available
        if let token = config.token {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        } else if let hash = config.apiSecretHash {
            request.setValue("api-secret " + hash, forHTTPHeaderField: "Authorization")
        }
        
        #if canImport(FoundationNetworking)
        // Linux implementation would go here - using sync networking
        throw NightscoutDiscoveryError.networkError("Not implemented on Linux")
        #else
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NightscoutDiscoveryError.serverNotFound
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NightscoutDiscoveryError.authenticationFailed
        }
        
        let status = try JSONDecoder().decode(NightscoutServerStatus.self, from: data)
        
        // Check verifyauth endpoint for permissions
        let authUrl = config.url.appendingPathComponent("/api/v1/verifyauth")
        var authRequest = URLRequest(url: authUrl)
        authRequest.httpMethod = "GET"
        
        if let token = config.token {
            authRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        } else if let hash = config.apiSecretHash {
            authRequest.setValue("api-secret " + hash, forHTTPHeaderField: "Authorization")
        }
        
        var permissions: [String] = []
        
        if let (authData, authResponse) = try? await URLSession.shared.data(for: authRequest),
           let authHttp = authResponse as? HTTPURLResponse,
           authHttp.statusCode == 200,
           let authResult = try? JSONDecoder().decode(NightscoutAuthResult.self, from: authData) {
            permissions = authResult.permissions ?? []
        }
        
        return (status, permissions)
        #endif
    }
}
