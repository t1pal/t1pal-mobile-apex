// SPDX-License-Identifier: AGPL-3.0-or-later
// DeliveryReporter.swift
// NightscoutKit
//
// Converts delivery events to Nightscout treatments (CONTROL-003)
// Trace: agent-control-plane-integration.md

import Foundation

// MARK: - Delivery Reporter (CONTROL-003)

/// Configuration for delivery reporter
public struct DeliveryReporterConfig: Sendable, Codable {
    /// App identifier for enteredBy field
    public let appIdentifier: String
    
    /// Whether to include reason/notes in treatments
    public let includeNotes: Bool
    
    /// Minimum bolus size to report (units)
    public let minimumBolusSize: Double
    
    /// Whether to report scheduled basal changes
    public let reportScheduledBasal: Bool
    
    /// Whether to batch uploads for efficiency
    public let batchUploads: Bool
    
    /// Maximum batch size
    public let maxBatchSize: Int
    
    public init(
        appIdentifier: String = "T1Pal",
        includeNotes: Bool = true,
        minimumBolusSize: Double = 0.01,
        reportScheduledBasal: Bool = false,
        batchUploads: Bool = true,
        maxBatchSize: Int = 50
    ) {
        self.appIdentifier = appIdentifier
        self.includeNotes = includeNotes
        self.minimumBolusSize = minimumBolusSize
        self.reportScheduledBasal = reportScheduledBasal
        self.batchUploads = batchUploads
        self.maxBatchSize = maxBatchSize
    }
    
    /// Default configuration
    public static let `default` = DeliveryReporterConfig()
}

/// Result of a delivery report
public struct DeliveryReportResult: Sendable, Equatable {
    public let eventsProcessed: Int
    public let treatmentsUploaded: Int
    public let eventsSkipped: Int
    public let errors: [String]
    
    public init(
        eventsProcessed: Int = 0,
        treatmentsUploaded: Int = 0,
        eventsSkipped: Int = 0,
        errors: [String] = []
    ) {
        self.eventsProcessed = eventsProcessed
        self.treatmentsUploaded = treatmentsUploaded
        self.eventsSkipped = eventsSkipped
        self.errors = errors
    }
    
    /// Whether all events were successfully processed
    public var isSuccess: Bool {
        errors.isEmpty
    }
    
    /// Combine two results
    public func merged(with other: DeliveryReportResult) -> DeliveryReportResult {
        DeliveryReportResult(
            eventsProcessed: eventsProcessed + other.eventsProcessed,
            treatmentsUploaded: treatmentsUploaded + other.treatmentsUploaded,
            eventsSkipped: eventsSkipped + other.eventsSkipped,
            errors: errors + other.errors
        )
    }
}

/// Pending delivery event for batching
public struct PendingDeliveryEvent: Sendable, Codable, Identifiable {
    public let id: UUID
    public let event: DeliveryEvent
    public let queuedAt: Date
    public var retryCount: Int
    
    public init(
        id: UUID = UUID(),
        event: DeliveryEvent,
        queuedAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.event = event
        self.queuedAt = queuedAt
        self.retryCount = retryCount
    }
    
    /// Age of pending event
    public var age: TimeInterval {
        Date().timeIntervalSince(queuedAt)
    }
}

/// Logic for converting delivery events to Nightscout treatments
public struct DeliveryReporterLogic: @unchecked Sendable {
    private let config: DeliveryReporterConfig
    private let dateFormatter: ISO8601DateFormatter
    
    public init(config: DeliveryReporterConfig = .default) {
        self.config = config
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    
    /// Convert delivery event to Nightscout treatment
    public func toTreatment(_ event: DeliveryEvent) -> NightscoutTreatment? {
        // Skip events below threshold
        if event.deliveryType == .bolus || event.deliveryType == .correctionBolus || event.deliveryType == .smb {
            if event.units < config.minimumBolusSize {
                return nil
            }
        }
        
        // Skip scheduled basal if not configured to report
        if event.deliveryType == .scheduledBasal && !config.reportScheduledBasal {
            return nil
        }
        
        let eventType = nightscoutEventType(for: event.deliveryType)
        let created_at = dateFormatter.string(from: event.timestamp)
        let notes = config.includeNotes ? event.reason : nil
        
        switch event.deliveryType {
        case .bolus, .correctionBolus:
            return NightscoutTreatment(
                _id: nil,
                eventType: eventType,
                created_at: created_at,
                insulin: event.units,
                carbs: nil,
                duration: nil,
                absolute: nil,
                rate: nil,
                percent: nil,
                profileIndex: nil,
                profile: nil,
                targetTop: nil,
                targetBottom: nil,
                glucose: nil,
                glucoseType: nil,
                units: nil,
                enteredBy: config.appIdentifier,
                notes: notes,
                reason: nil,
                preBolus: nil
            )
            
        case .smb:
            return NightscoutTreatment(
                _id: nil,
                eventType: eventType,
                created_at: created_at,
                insulin: event.units,
                carbs: nil,
                duration: nil,
                absolute: nil,
                rate: nil,
                percent: nil,
                profileIndex: nil,
                profile: nil,
                targetTop: nil,
                targetBottom: nil,
                glucose: nil,
                glucoseType: nil,
                units: nil,
                enteredBy: config.appIdentifier,
                notes: notes ?? "SMB",
                reason: nil,
                preBolus: nil
            )
            
        case .tempBasal:
            return NightscoutTreatment(
                _id: nil,
                eventType: eventType,
                created_at: created_at,
                insulin: nil,
                carbs: nil,
                duration: event.duration.map { $0 / 60.0 }, // Convert to minutes
                absolute: event.rate,
                rate: event.rate,
                percent: nil,
                profileIndex: nil,
                profile: nil,
                targetTop: nil,
                targetBottom: nil,
                glucose: nil,
                glucoseType: nil,
                units: nil,
                enteredBy: config.appIdentifier,
                notes: notes,
                reason: nil,
                preBolus: nil
            )
            
        case .scheduledBasal:
            return NightscoutTreatment(
                _id: nil,
                eventType: eventType,
                created_at: created_at,
                insulin: nil,
                carbs: nil,
                duration: event.duration.map { $0 / 60.0 },
                absolute: event.rate,
                rate: event.rate,
                percent: nil,
                profileIndex: nil,
                profile: nil,
                targetTop: nil,
                targetBottom: nil,
                glucose: nil,
                glucoseType: nil,
                units: nil,
                enteredBy: config.appIdentifier,
                notes: notes,
                reason: nil,
                preBolus: nil
            )
            
        case .suspend:
            return NightscoutTreatment(
                _id: nil,
                eventType: eventType,
                created_at: created_at,
                insulin: nil,
                carbs: nil,
                duration: event.duration.map { $0 / 60.0 },
                absolute: 0,
                rate: 0,
                percent: nil,
                profileIndex: nil,
                profile: nil,
                targetTop: nil,
                targetBottom: nil,
                glucose: nil,
                glucoseType: nil,
                units: nil,
                enteredBy: config.appIdentifier,
                notes: notes ?? "Pump suspended",
                reason: nil,
                preBolus: nil
            )
            
        case .resume:
            return NightscoutTreatment(
                _id: nil,
                eventType: eventType,
                created_at: created_at,
                insulin: nil,
                carbs: nil,
                duration: nil,
                absolute: nil,
                rate: nil,
                percent: nil,
                profileIndex: nil,
                profile: nil,
                targetTop: nil,
                targetBottom: nil,
                glucose: nil,
                glucoseType: nil,
                units: nil,
                enteredBy: config.appIdentifier,
                notes: notes ?? "Pump resumed",
                reason: nil,
                preBolus: nil
            )
        }
    }
    
    /// Convert batch of delivery events to treatments
    public func toTreatments(_ events: [DeliveryEvent]) -> [NightscoutTreatment] {
        events.compactMap { toTreatment($0) }
    }
    
    /// Get Nightscout event type for delivery type
    public func nightscoutEventType(for deliveryType: DeliveryType) -> String {
        switch deliveryType {
        case .bolus: return "Bolus"
        case .correctionBolus: return "Correction Bolus"
        case .smb: return "SMB"
        case .tempBasal: return "Temp Basal"
        case .scheduledBasal: return "Basal"
        case .suspend: return "Suspend Pump"
        case .resume: return "Resume Pump"
        }
    }
    
    /// Check if event should be reported
    public func shouldReport(_ event: DeliveryEvent) -> Bool {
        // Skip below minimum bolus threshold
        if event.deliveryType == .bolus || event.deliveryType == .correctionBolus || event.deliveryType == .smb {
            if event.units < config.minimumBolusSize {
                return false
            }
        }
        
        // Skip scheduled basal if not configured
        if event.deliveryType == .scheduledBasal && !config.reportScheduledBasal {
            return false
        }
        
        return true
    }
}

/// Actor for managing delivery reporting queue
public actor DeliveryReporter {
    private let config: DeliveryReporterConfig
    private let logic: DeliveryReporterLogic
    private var pendingEvents: [PendingDeliveryEvent] = []
    private var lastUploadTime: Date?
    private var totalReported: Int = 0
    private var totalSkipped: Int = 0
    private var totalErrors: Int = 0
    
    public init(config: DeliveryReporterConfig = .default) {
        self.config = config
        self.logic = DeliveryReporterLogic(config: config)
    }
    
    /// Queue a delivery event for reporting
    public func queue(_ event: DeliveryEvent) {
        if logic.shouldReport(event) {
            let pending = PendingDeliveryEvent(event: event)
            pendingEvents.append(pending)
        } else {
            totalSkipped += 1
        }
    }
    
    /// Queue multiple delivery events
    public func queue(_ events: [DeliveryEvent]) {
        for event in events {
            queue(event)
        }
    }
    
    /// Get pending event count
    public func pendingCount() -> Int {
        pendingEvents.count
    }
    
    /// Get pending events
    public func getPendingEvents() -> [PendingDeliveryEvent] {
        pendingEvents
    }
    
    /// Clear pending events
    public func clearPending() {
        pendingEvents.removeAll()
    }
    
    /// Process and return treatments ready for upload
    public func processPendingBatch() -> [NightscoutTreatment] {
        let batch = Array(pendingEvents.prefix(config.maxBatchSize))
        let treatments = logic.toTreatments(batch.map { $0.event })
        
        // Remove processed events
        let processedIds = Set(batch.map { $0.id })
        pendingEvents.removeAll { processedIds.contains($0.id) }
        
        totalReported += treatments.count
        lastUploadTime = Date()
        
        return treatments
    }
    
    /// Process and return a limited batch of treatments
    public func processPendingBatch(limit: Int) -> [NightscoutTreatment] {
        let effectiveLimit = min(limit, config.maxBatchSize)
        let batch = Array(pendingEvents.prefix(effectiveLimit))
        let treatments = logic.toTreatments(batch.map { $0.event })
        
        // Remove processed events
        let processedIds = Set(batch.map { $0.id })
        pendingEvents.removeAll { processedIds.contains($0.id) }
        
        totalReported += treatments.count
        lastUploadTime = Date()
        
        return treatments
    }
    
    /// Get reporter statistics
    public func getStatistics() -> DeliveryReporterStatistics {
        DeliveryReporterStatistics(
            pendingCount: pendingEvents.count,
            totalReported: totalReported,
            totalSkipped: totalSkipped,
            totalErrors: totalErrors,
            lastUploadTime: lastUploadTime
        )
    }
    
    /// Increment error count
    public func recordError() {
        totalErrors += 1
    }
    
    /// Record a partial success (some items succeeded, some failed)
    public func recordPartialSuccess(succeeded: Int, failed: Int) {
        totalReported += succeeded
        totalErrors += failed
        lastUploadTime = Date()
    }
    
    /// Reset statistics
    public func resetStatistics() {
        totalReported = 0
        totalSkipped = 0
        totalErrors = 0
        lastUploadTime = nil
    }
    
    // MARK: - Flush Result
    
    /// Result of a flush operation
    public struct FlushResult: Sendable {
        public let treatmentsUploaded: Int
        public let treatmentsFailed: Int
        
        public init(treatmentsUploaded: Int, treatmentsFailed: Int = 0) {
            self.treatmentsUploaded = treatmentsUploaded
            self.treatmentsFailed = treatmentsFailed
        }
    }
    
    /// Flush all pending events to Nightscout
    /// - Parameter client: The NightscoutClient to use for uploading
    /// - Returns: FlushResult with count of uploaded treatments
    /// - Throws: If upload fails
    public func flush(client: NightscoutClient) async throws -> FlushResult {
        let treatments = processPendingBatch()
        guard !treatments.isEmpty else {
            return FlushResult(treatmentsUploaded: 0)
        }
        
        try await client.uploadTreatments(treatments)
        return FlushResult(treatmentsUploaded: treatments.count)
    }
}

/// Statistics for delivery reporter
public struct DeliveryReporterStatistics: Sendable, Equatable {
    public let pendingCount: Int
    public let totalReported: Int
    public let totalSkipped: Int
    public let totalErrors: Int
    public let lastUploadTime: Date?
    
    public init(
        pendingCount: Int = 0,
        totalReported: Int = 0,
        totalSkipped: Int = 0,
        totalErrors: Int = 0,
        lastUploadTime: Date? = nil
    ) {
        self.pendingCount = pendingCount
        self.totalReported = totalReported
        self.totalSkipped = totalSkipped
        self.totalErrors = totalErrors
        self.lastUploadTime = lastUploadTime
    }
    
    /// Time since last upload
    public var timeSinceLastUpload: TimeInterval? {
        guard let lastUploadTime = lastUploadTime else { return nil }
        return Date().timeIntervalSince(lastUploadTime)
    }
}

// MARK: - Extensions

extension NightscoutClient {
    /// Report delivery events to Nightscout
    public func reportDeliveries(_ events: [DeliveryEvent], config: DeliveryReporterConfig = .default) async throws -> DeliveryReportResult {
        let logic = DeliveryReporterLogic(config: config)
        let treatments = logic.toTreatments(events)
        
        if treatments.isEmpty {
            return DeliveryReportResult(
                eventsProcessed: events.count,
                treatmentsUploaded: 0,
                eventsSkipped: events.count
            )
        }
        
        try await uploadTreatments(treatments)
        
        return DeliveryReportResult(
            eventsProcessed: events.count,
            treatmentsUploaded: treatments.count,
            eventsSkipped: events.count - treatments.count
        )
    }
    
    /// Report a single delivery event
    public func reportDelivery(_ event: DeliveryEvent, config: DeliveryReporterConfig = .default) async throws -> DeliveryReportResult {
        try await reportDeliveries([event], config: config)
    }
}
