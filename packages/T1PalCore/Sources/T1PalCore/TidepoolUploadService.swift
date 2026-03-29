// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TidepoolUploadService.swift
// T1PalCore
//
// Tidepool data upload service for diabetes data synchronization
// Requirements: AID-TIDEPOOL-001
// Trace: PRD-009, apps.md

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Tidepool Upload Types

/// Tidepool datum base type for all uploads
public struct TidepoolDatum: Codable, Sendable {
    public let type: String
    public let time: String  // ISO 8601
    public let deviceId: String
    public let uploadId: String?
    
    public init(type: String, time: Date, deviceId: String, uploadId: String? = nil) {
        self.type = type
        self.time = ISO8601DateFormatter().string(from: time)
        self.deviceId = deviceId
        self.uploadId = uploadId
    }
}

/// Tidepool CBG (continuous blood glucose) datum
public struct TidepoolCBG: Codable, Sendable {
    public let type: String = "cbg"
    public let time: String
    public let deviceId: String
    public let uploadId: String?
    public let value: Double  // mmol/L
    public let units: String = "mmol/L"
    public let payload: TidepoolCBGPayload?
    
    private enum CodingKeys: String, CodingKey {
        case type, time, deviceId, uploadId, value, units, payload
    }
    
    public init(
        time: Date,
        glucoseMgDl: Double,
        deviceId: String,
        uploadId: String? = nil,
        trend: String? = nil
    ) {
        self.time = ISO8601DateFormatter().string(from: time)
        self.value = glucoseMgDl / 18.0182  // Convert mg/dL to mmol/L
        self.deviceId = deviceId
        self.uploadId = uploadId
        self.payload = trend != nil ? TidepoolCBGPayload(trend: trend) : nil
    }
}

/// CBG payload for trend data
public struct TidepoolCBGPayload: Codable, Sendable {
    public let trend: String?
    
    public init(trend: String?) {
        self.trend = trend
    }
}

/// Tidepool bolus datum
public struct TidepoolBolus: Codable, Sendable {
    public let type: String = "bolus"
    public let subType: String
    public let time: String
    public let deviceId: String
    public let uploadId: String?
    public let normal: Double?
    public let extended: Double?
    public let duration: Int?  // milliseconds
    public let expectedNormal: Double?
    public let expectedExtended: Double?
    public let expectedDuration: Int?
    
    private enum CodingKeys: String, CodingKey {
        case type, subType, time, deviceId, uploadId, normal, extended, duration
        case expectedNormal, expectedExtended, expectedDuration
    }
    
    /// Create a normal bolus
    public static func normal(
        time: Date,
        units: Double,
        deviceId: String,
        uploadId: String? = nil
    ) -> TidepoolBolus {
        TidepoolBolus(
            subType: "normal",
            time: ISO8601DateFormatter().string(from: time),
            deviceId: deviceId,
            uploadId: uploadId,
            normal: units,
            extended: nil,
            duration: nil,
            expectedNormal: units,
            expectedExtended: nil,
            expectedDuration: nil
        )
    }
    
    /// Create an extended/square bolus
    public static func extended(
        time: Date,
        units: Double,
        durationMinutes: Int,
        deviceId: String,
        uploadId: String? = nil
    ) -> TidepoolBolus {
        TidepoolBolus(
            subType: "square",
            time: ISO8601DateFormatter().string(from: time),
            deviceId: deviceId,
            uploadId: uploadId,
            normal: nil,
            extended: units,
            duration: durationMinutes * 60 * 1000,
            expectedNormal: nil,
            expectedExtended: units,
            expectedDuration: durationMinutes * 60 * 1000
        )
    }
}

/// Tidepool basal datum
public struct TidepoolBasal: Codable, Sendable {
    public let type: String = "basal"
    public let deliveryType: String
    public let time: String
    public let deviceId: String
    public let uploadId: String?
    public let duration: Int  // milliseconds
    public let rate: Double  // U/hr
    public let suppressed: TidepoolSuppressedBasal?
    
    private enum CodingKeys: String, CodingKey {
        case type, deliveryType, time, deviceId, uploadId, duration, rate, suppressed
    }
    
    /// Create a temp basal
    public static func temp(
        time: Date,
        rate: Double,
        durationMinutes: Int,
        scheduledRate: Double?,
        deviceId: String,
        uploadId: String? = nil
    ) -> TidepoolBasal {
        let suppressed: TidepoolSuppressedBasal?
        if let scheduled = scheduledRate {
            suppressed = TidepoolSuppressedBasal(
                type: "basal",
                deliveryType: "scheduled",
                rate: scheduled
            )
        } else {
            suppressed = nil
        }
        
        return TidepoolBasal(
            deliveryType: "temp",
            time: ISO8601DateFormatter().string(from: time),
            deviceId: deviceId,
            uploadId: uploadId,
            duration: durationMinutes * 60 * 1000,
            rate: rate,
            suppressed: suppressed
        )
    }
    
    /// Create a scheduled basal
    public static func scheduled(
        time: Date,
        rate: Double,
        durationMinutes: Int,
        deviceId: String,
        uploadId: String? = nil
    ) -> TidepoolBasal {
        TidepoolBasal(
            deliveryType: "scheduled",
            time: ISO8601DateFormatter().string(from: time),
            deviceId: deviceId,
            uploadId: uploadId,
            duration: durationMinutes * 60 * 1000,
            rate: rate,
            suppressed: nil
        )
    }
}

/// Suppressed basal info for temp basals
public struct TidepoolSuppressedBasal: Codable, Sendable {
    public let type: String
    public let deliveryType: String
    public let rate: Double
}

/// Tidepool food/carb datum
public struct TidepoolFood: Codable, Sendable {
    public let type: String = "food"
    public let time: String
    public let deviceId: String
    public let uploadId: String?
    public let nutrition: TidepoolNutrition
    
    private enum CodingKeys: String, CodingKey {
        case type, time, deviceId, uploadId, nutrition
    }
    
    public init(
        time: Date,
        carbsGrams: Double,
        deviceId: String,
        uploadId: String? = nil
    ) {
        self.time = ISO8601DateFormatter().string(from: time)
        self.deviceId = deviceId
        self.uploadId = uploadId
        self.nutrition = TidepoolNutrition(
            carbohydrate: TidepoolCarbohydrate(net: carbsGrams, units: "grams")
        )
    }
}

/// Nutrition info for food
public struct TidepoolNutrition: Codable, Sendable {
    public let carbohydrate: TidepoolCarbohydrate
}

/// Carbohydrate info
public struct TidepoolCarbohydrate: Codable, Sendable {
    public let net: Double
    public let units: String
}

/// Upload dataset response
public struct TidepoolUploadDatasetResponse: Codable, Sendable {
    public let data: TidepoolDataSet?
    public let uploadId: String?
}

// MARK: - Upload Service

/// Service for uploading diabetes data to Tidepool
public actor TidepoolUploadService {
    
    // MARK: - Properties
    
    private let auth: TidepoolAuth
    private var currentDataset: TidepoolDataSet?
    private var pendingUploads: [[String: Any]] = []
    private let deviceId: String
    private let batchSize: Int
    
    /// UserDefaults key for upload enabled state
    private static let uploadEnabledKey = "tidepool.uploadEnabled"
    
    /// UserDefaults key for last upload time
    private static let lastUploadKey = "tidepool.lastUploadTime"
    
    // MARK: - Initialization
    
    public init(
        config: TidepoolConfig,
        deviceId: String = "T1Pal-\(UUID().uuidString.prefix(8))",
        batchSize: Int = 100
    ) {
        self.auth = TidepoolAuth(config: config)
        self.deviceId = deviceId
        self.batchSize = batchSize
    }
    
    // MARK: - Settings
    
    /// Whether upload is enabled
    public static var isUploadEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: uploadEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: uploadEnabledKey) }
    }
    
    /// Last successful upload time
    public static var lastUploadTime: Date? {
        get { UserDefaults.standard.object(forKey: lastUploadKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastUploadKey) }
    }
    
    // MARK: - Session Management
    
    /// Check if we have a valid session
    public func hasValidSession() async -> Bool {
        await auth.getCurrentSession() != nil
    }
    
    /// Set session from OAuth callback
    public func setSession(_ session: TidepoolSession) async {
        await auth.setSession(session)
    }
    
    /// Clear session (logout)
    public func clearSession() async {
        await auth.clearSession()
        currentDataset = nil
    }
    
    // MARK: - Dataset Management
    
    /// Create or get current upload dataset
    public func getOrCreateDataset() async throws -> TidepoolDataSet {
        if let dataset = currentDataset {
            return dataset
        }
        
        guard let session = await auth.getCurrentSession() else {
            throw TidepoolError.sessionExpired
        }
        
        // Create new dataset
        let dataset = try await createDataset(session: session)
        currentDataset = dataset
        return dataset
    }
    
    private func createDataset(session: TidepoolSession) async throws -> TidepoolDataSet {
        let url = await auth.apiUrl
            .appendingPathComponent("v1")
            .appendingPathComponent("users")
            .appendingPathComponent(session.userId)
            .appendingPathComponent("data_sets")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client": [
                "name": "T1Pal Mobile",
                "version": "1.0.0",
                "platform": "iOS"
            ],
            "dataSetType": "continuous",
            "deviceId": deviceId,
            "deviceManufacturers": ["T1Pal"],
            "deviceModel": "T1Pal AID",
            "deviceTags": ["cgm", "insulin-pump"],
            "time": ISO8601DateFormatter().string(from: Date()),
            "timezone": TimeZone.current.identifier
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TidepoolError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...201:
            let decoded = try JSONDecoder().decode(TidepoolUploadDatasetResponse.self, from: data)
            guard let dataset = decoded.data else {
                throw TidepoolError.invalidResponse
            }
            return dataset
        case 401:
            throw TidepoolError.sessionExpired
        case 403:
            throw TidepoolError.accessDenied
        case 429:
            throw TidepoolError.rateLimited
        default:
            throw TidepoolError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Data Upload
    
    /// Upload CGM glucose reading
    public func uploadGlucose(
        time: Date,
        glucoseMgDl: Double,
        trend: String? = nil
    ) async throws {
        let cbg = TidepoolCBG(
            time: time,
            glucoseMgDl: glucoseMgDl,
            deviceId: deviceId,
            trend: trend
        )
        try await uploadData([cbg])
    }
    
    /// Upload bolus
    public func uploadBolus(
        time: Date,
        units: Double,
        extended: Bool = false,
        durationMinutes: Int = 0
    ) async throws {
        let bolus: TidepoolBolus
        if extended && durationMinutes > 0 {
            bolus = .extended(time: time, units: units, durationMinutes: durationMinutes, deviceId: deviceId)
        } else {
            bolus = .normal(time: time, units: units, deviceId: deviceId)
        }
        try await uploadData([bolus])
    }
    
    /// Upload temp basal
    public func uploadTempBasal(
        time: Date,
        rate: Double,
        durationMinutes: Int,
        scheduledRate: Double? = nil
    ) async throws {
        let basal = TidepoolBasal.temp(
            time: time,
            rate: rate,
            durationMinutes: durationMinutes,
            scheduledRate: scheduledRate,
            deviceId: deviceId
        )
        try await uploadData([basal])
    }
    
    /// Upload carb entry
    public func uploadCarbs(
        time: Date,
        grams: Double
    ) async throws {
        let food = TidepoolFood(time: time, carbsGrams: grams, deviceId: deviceId)
        try await uploadData([food])
    }
    
    /// Upload batch of data
    public func uploadData<T: Encodable>(_ data: [T]) async throws {
        guard Self.isUploadEnabled else { return }
        guard !data.isEmpty else { return }
        
        let dataset = try await getOrCreateDataset()
        guard let session = await auth.getCurrentSession() else {
            throw TidepoolError.sessionExpired
        }
        
        let url = await auth.apiUrl
            .appendingPathComponent("v1")
            .appendingPathComponent("data_sets")
            .appendingPathComponent(dataset.id)
            .appendingPathComponent("data")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(data)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TidepoolError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...201:
            Self.lastUploadTime = Date()
        case 401:
            throw TidepoolError.sessionExpired
        case 403:
            throw TidepoolError.accessDenied
        case 429:
            throw TidepoolError.rateLimited
        default:
            throw TidepoolError.serverError(httpResponse.statusCode)
        }
    }
    
    // MARK: - Batch Upload
    
    /// Queue data for batch upload
    public func queueForUpload(_ datum: [String: Any]) {
        pendingUploads.append(datum)
    }
    
    /// Flush pending uploads
    public func flushPendingUploads() async throws {
        guard !pendingUploads.isEmpty else { return }
        
        // Upload in batches
        let batches = stride(from: 0, to: pendingUploads.count, by: batchSize).map {
            Array(pendingUploads[$0..<min($0 + batchSize, pendingUploads.count)])
        }
        
        for batch in batches {
            try await uploadRawData(batch)
        }
        
        pendingUploads.removeAll()
    }
    
    private func uploadRawData(_ data: [[String: Any]]) async throws {
        guard Self.isUploadEnabled else { return }
        guard !data.isEmpty else { return }
        
        let dataset = try await getOrCreateDataset()
        guard let session = await auth.getCurrentSession() else {
            throw TidepoolError.sessionExpired
        }
        
        let url = await auth.apiUrl
            .appendingPathComponent("v1")
            .appendingPathComponent("data_sets")
            .appendingPathComponent(dataset.id)
            .appendingPathComponent("data")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: data)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TidepoolError.invalidResponse
        }
        
        if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
            throw TidepoolError.serverError(httpResponse.statusCode)
        }
        
        Self.lastUploadTime = Date()
    }
}

// MARK: - Convenience Extensions

extension TidepoolUploadService {
    
    /// Create service with default T1Pal configuration
    public static func defaultService() -> TidepoolUploadService {
        let config = TidepoolConfig(
            environment: .production,
            clientId: "t1pal-mobile",
            redirectUri: URL(string: "t1pal://tidepool/callback")!
        )
        return TidepoolUploadService(config: config)
    }
}
