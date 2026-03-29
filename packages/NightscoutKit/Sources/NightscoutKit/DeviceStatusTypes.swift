// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DeviceStatusTypes.swift
// NightscoutKit
//
// Device status types for Nightscout API
// Extracted from NightscoutClient.swift (NS-REFACTOR-001)
// Requirements: REQ-AID-004

import Foundation

// MARK: - Device Status Query

/// Query parameters for devicestatus API
public struct DeviceStatusQuery: Sendable {
    public var count: Int?
    public var dateFrom: Date?
    public var dateTo: Date?
    public var device: String?
    
    public init(
        count: Int? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        device: String? = nil
    ) {
        self.count = count
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.device = device
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
        
        if let device = device {
            items.append(URLQueryItem(name: "find[device]", value: device))
        }
        
        return items
    }
}

// MARK: - AID System Detection (NS-MS-002)

/// Automated Insulin Delivery systems that upload to Nightscout
public enum AIDSystem: String, Codable, Sendable, CaseIterable {
    case loop = "Loop"              // iOS Loop (DIY or Tidepool)
    case aaps = "AndroidAPS"        // AndroidAPS (AAPS)
    case trio = "Trio"              // Trio (iOS fork of AAPS algorithm)
    case openaps = "OpenAPS"        // OpenAPS (oref0/oref1 on Pi/Edison)
    case freeaps = "FreeAPS"        // FreeAPS X (deprecated, now Trio)
    case unknown = "Unknown"
    
    /// Detect system from device string
    public static func detect(from device: String?) -> AIDSystem {
        guard let device = device?.lowercased() else { return .unknown }
        
        // Order matters: check more specific patterns first
        if device.contains("trio") {
            return .trio
        }
        if device.contains("freeaps") {
            return .freeaps
        }
        if device.contains("androidaps") || device.contains("aaps") {
            return .aaps
        }
        if device.contains("openaps") && !device.contains("loop") {
            return .openaps
        }
        if device.contains("loop") {
            return .loop
        }
        
        return .unknown
    }
    
    /// Human-readable name
    public var displayName: String {
        switch self {
        case .loop: return "Loop"
        case .aaps: return "AndroidAPS"
        case .trio: return "Trio"
        case .openaps: return "OpenAPS"
        case .freeaps: return "FreeAPS X"
        case .unknown: return "Unknown"
        }
    }
    
    /// Whether this system uses OpenAPS-style deviceStatus format
    public var usesOpenAPSFormat: Bool {
        switch self {
        case .aaps, .trio, .openaps, .freeaps:
            return true
        case .loop, .unknown:
            return false
        }
    }
}

// MARK: - CGM Uploader Detection (NS-MS-003)

/// CGM data uploaders that may coexist with AID systems in Nightscout
/// In hybrid setups, xDrip+ or Spike may upload CGM while Loop/AAPS handles AID
public enum CGMUploader: String, Codable, Sendable, CaseIterable {
    case xdrip = "xDrip"            // xDrip+ (Android) or xDrip4iOS
    case spike = "Spike"            // Spike (iOS CGM app)
    case glimp = "Glimp"            // Glimp (Android Libre reader)
    case diabox = "Diabox"          // Diabox (Android CGM app)
    case nightguard = "Nightguard"  // Nightguard (watchOS)
    case unknown = "Unknown"
    
    /// Detect CGM uploader from device string
    public static func detect(from device: String?) -> CGMUploader? {
        guard let device = device?.lowercased() else { return nil }
        
        if device.contains("xdrip") {
            return .xdrip
        }
        if device.contains("spike") {
            return .spike
        }
        if device.contains("glimp") {
            return .glimp
        }
        if device.contains("diabox") {
            return .diabox
        }
        if device.contains("nightguard") {
            return .nightguard
        }
        
        return nil
    }
    
    /// Human-readable name
    public var displayName: String {
        switch self {
        case .xdrip: return "xDrip+"
        case .spike: return "Spike"
        case .glimp: return "Glimp"
        case .diabox: return "Diabox"
        case .nightguard: return "Nightguard"
        case .unknown: return "Unknown"
        }
    }
}

/// Describes the complete device setup uploading to Nightscout
/// Handles hybrid configurations where CGM uploader differs from AID system
public struct DeviceSetup: Sendable {
    /// Primary AID system (Loop, AAPS, Trio, etc.)
    public let aidSystem: AIDSystem
    
    /// CGM uploader if different from AID system (hybrid setup)
    public let cgmUploader: CGMUploader?
    
    /// Whether this is a hybrid setup (different CGM uploader than AID)
    public var isHybrid: Bool {
        cgmUploader != nil
    }
    
    /// Uploader device name from deviceStatus
    public let uploaderName: String?
    
    public init(aidSystem: AIDSystem, cgmUploader: CGMUploader? = nil, uploaderName: String? = nil) {
        self.aidSystem = aidSystem
        self.cgmUploader = cgmUploader
        self.uploaderName = uploaderName
    }
    
    /// Human-readable description
    public var description: String {
        if let cgm = cgmUploader {
            return "\(aidSystem.displayName) + \(cgm.displayName)"
        }
        return aidSystem.displayName
    }
}

// MARK: - Unified Algorithm Status (NS-MS-010)

/// Unified representation of algorithm state from any AID system
/// Provides common interface for extracting IOB, COB, predictions, and enacted decisions
public struct UnifiedAlgorithmStatus: Sendable {
    /// Source AID system
    public let system: AIDSystem
    
    /// Timestamp of the status
    public let timestamp: Date?
    
    /// Insulin on board (Units)
    public let iob: Double?
    
    /// Basal IOB component (Units) - available from OpenAPS systems
    public let basalIOB: Double?
    
    /// Carbs on board (grams)
    public let cob: Double?
    
    /// Enacted temp basal rate (U/hr)
    public let enactedRate: Double?
    
    /// Enacted temp basal duration (minutes)
    public let enactedDuration: Int?
    
    /// Enacted SMB/bolus (Units)
    public let enactedBolus: Double?
    
    /// Whether the enacted command was received by pump
    public let enactedReceived: Bool?
    
    /// Predicted BG values (mg/dL at 5-min intervals)
    public let predictions: [Double]?
    
    /// Prediction start time
    public let predictionStartDate: Date?
    
    /// OpenAPS-specific: multiple prediction curves
    public let predBGs: PredictionCurves?
    
    /// Algorithm decision reason/explanation
    public let reason: String?
    
    /// Eventual BG prediction (mg/dL)
    public let eventualBG: Double?
    
    /// Multiple prediction curves from OpenAPS systems
    public struct PredictionCurves: Sendable {
        public let iob: [Int]?    // IOB-only prediction
        public let cob: [Int]?    // COB prediction
        public let uam: [Int]?    // Unannounced meal prediction
        public let zt: [Int]?     // Zero-temp prediction
        
        public init(iob: [Int]? = nil, cob: [Int]? = nil, uam: [Int]? = nil, zt: [Int]? = nil) {
            self.iob = iob
            self.cob = cob
            self.uam = uam
            self.zt = zt
        }
        
        /// Primary prediction curve (IOB > COB > UAM > ZT)
        public var primary: [Int]? {
            iob ?? cob ?? uam ?? zt
        }
    }
    
    public init(
        system: AIDSystem,
        timestamp: Date? = nil,
        iob: Double? = nil,
        basalIOB: Double? = nil,
        cob: Double? = nil,
        enactedRate: Double? = nil,
        enactedDuration: Int? = nil,
        enactedBolus: Double? = nil,
        enactedReceived: Bool? = nil,
        predictions: [Double]? = nil,
        predictionStartDate: Date? = nil,
        predBGs: PredictionCurves? = nil,
        reason: String? = nil,
        eventualBG: Double? = nil
    ) {
        self.system = system
        self.timestamp = timestamp
        self.iob = iob
        self.basalIOB = basalIOB
        self.cob = cob
        self.enactedRate = enactedRate
        self.enactedDuration = enactedDuration
        self.enactedBolus = enactedBolus
        self.enactedReceived = enactedReceived
        self.predictions = predictions
        self.predictionStartDate = predictionStartDate
        self.predBGs = predBGs
        self.reason = reason
        self.eventualBG = eventualBG
    }
}

// MARK: - Nightscout Device Status

/// Device status for control plane reconciliation
public struct NightscoutDeviceStatus: Codable, Sendable, Hashable {
    public let _id: String?
    public let device: String
    public let created_at: String
    public let mills: Int64?
    
    // Loop/iOS status
    public let loop: LoopStatus?
    
    // OpenAPS/AAPS status
    public let openaps: OpenAPSStatus?
    
    // Pump status
    public let pump: PumpStatus?
    
    // Uploader status (phone battery, etc.)
    public let uploader: UploaderStatus?
    
    // MARK: - Loop Status (iOS Loop app)
    
    public struct LoopStatus: Codable, Sendable, Hashable {
        public let iob: IOBStatus?
        public let cob: COBStatus?
        public let predicted: PredictedStatus?
        public let enacted: EnactedStatus?
        public let recommendedBolus: Double?
        public let ripileyLink: RileyLinkStatus?
        public let failureReason: String?
        public let version: String?
        public let timestamp: String?
        /// Loop app name (e.g., "T1Pal Loop", "Loop")
        public let name: String?
        /// Automatic dose recommendation with temp basal adjustment
        public let automaticDoseRecommendation: AutomaticDoseRecommendation?
        
        public init(
            iob: IOBStatus? = nil,
            cob: COBStatus? = nil,
            predicted: PredictedStatus? = nil,
            enacted: EnactedStatus? = nil,
            recommendedBolus: Double? = nil,
            ripileyLink: RileyLinkStatus? = nil,
            failureReason: String? = nil,
            version: String? = nil,
            timestamp: String? = nil,
            name: String? = nil,
            automaticDoseRecommendation: AutomaticDoseRecommendation? = nil
        ) {
            self.iob = iob
            self.cob = cob
            self.predicted = predicted
            self.enacted = enacted
            self.recommendedBolus = recommendedBolus
            self.ripileyLink = ripileyLink
            self.failureReason = failureReason
            self.version = version
            self.timestamp = timestamp
            self.name = name
            self.automaticDoseRecommendation = automaticDoseRecommendation
        }
        
        /// Automatic dose recommendation from Loop
        public struct AutomaticDoseRecommendation: Codable, Sendable, Hashable {
            public let tempBasalAdjustment: TempBasalAdjustment?
            public let bolusVolume: Double?
            public let timestamp: String?
            
            public init(tempBasalAdjustment: TempBasalAdjustment? = nil, bolusVolume: Double? = nil, timestamp: String? = nil) {
                self.tempBasalAdjustment = tempBasalAdjustment
                self.bolusVolume = bolusVolume
                self.timestamp = timestamp
            }
            
            public struct TempBasalAdjustment: Codable, Sendable, Hashable {
                public let rate: Double?
                public let duration: Double?
                
                public init(rate: Double? = nil, duration: Double? = nil) {
                    self.rate = rate
                    self.duration = duration
                }
            }
        }
        
        public struct IOBStatus: Codable, Sendable, Hashable {
            public let iob: Double?
            public let basaliob: Double?
            public let timestamp: String?
            
            public init(iob: Double? = nil, basaliob: Double? = nil, timestamp: String? = nil) {
                self.iob = iob
                self.basaliob = basaliob
                self.timestamp = timestamp
            }
        }
        
        public struct COBStatus: Codable, Sendable, Hashable {
            public let cob: Double?
            public let carbs_hr: Double?
            public let timestamp: String?
            
            public init(cob: Double? = nil, carbs_hr: Double? = nil, timestamp: String? = nil) {
                self.cob = cob
                self.carbs_hr = carbs_hr
                self.timestamp = timestamp
            }
        }
        
        public struct PredictedStatus: Codable, Sendable, Hashable {
            public let startDate: String?
            /// Predicted glucose values (mg/dL). May be decimal from Loop.
            public let values: [Double]?
            
            public init(startDate: String? = nil, values: [Double]? = nil) {
                self.startDate = startDate
                self.values = values
            }
        }
        
        public struct EnactedStatus: Codable, Sendable, Hashable {
            public let rate: Double?
            public let duration: Double?
            public let timestamp: String?
            public let received: Bool?
            public let bolusVolume: Double?
            
            public init(rate: Double? = nil, duration: Double? = nil, timestamp: String? = nil, received: Bool? = nil, bolusVolume: Double? = nil) {
                self.rate = rate
                self.duration = duration
                self.timestamp = timestamp
                self.received = received
                self.bolusVolume = bolusVolume
            }
        }
        
        public struct RileyLinkStatus: Codable, Sendable, Hashable {
            public let connected: Bool?
            public let frequency: Double?
            public let name: String?
            
            public init(connected: Bool? = nil, frequency: Double? = nil, name: String? = nil) {
                self.connected = connected
                self.frequency = frequency
                self.name = name
            }
        }
    }
    
    // MARK: - OpenAPS Status (OpenAPS/AAPS)
    // Trace: ALG-AB-002 (algorithm field for A/B testing)
    
    public struct OpenAPSStatus: Codable, Sendable, Hashable {
        public let iob: IOBData?
        public let suggested: SuggestedStatus?
        public let enacted: EnactedStatus?
        public let reason: String?
        public let timestamp: String?
        
        /// Algorithm identifier for A/B testing (e.g., "oref0", "oref1", "loop", "trio")
        public let algorithm: String?
        
        public init(
            iob: IOBData? = nil,
            suggested: SuggestedStatus? = nil,
            enacted: EnactedStatus? = nil,
            reason: String? = nil,
            timestamp: String? = nil,
            algorithm: String? = nil
        ) {
            self.iob = iob
            self.suggested = suggested
            self.enacted = enacted
            self.reason = reason
            self.timestamp = timestamp
            self.algorithm = algorithm
        }
        
        public struct IOBData: Codable, Sendable, Hashable {
            public let iob: Double?
            public let basaliob: Double?
            public let bolussnooze: Double?
            public let activity: Double?
            public let lastBolusTime: Int64?
            public let lastTemp: LastTemp?
            public let timestamp: String?
            
            public init(
                iob: Double? = nil,
                basaliob: Double? = nil,
                bolussnooze: Double? = nil,
                activity: Double? = nil,
                lastBolusTime: Int64? = nil,
                lastTemp: LastTemp? = nil,
                timestamp: String? = nil
            ) {
                self.iob = iob
                self.basaliob = basaliob
                self.bolussnooze = bolussnooze
                self.activity = activity
                self.lastBolusTime = lastBolusTime
                self.lastTemp = lastTemp
                self.timestamp = timestamp
            }
            
            public struct LastTemp: Codable, Sendable, Hashable {
                public let rate: Double?
                public let timestamp: String?
                public let started_at: String?
                public let duration: Int?
                
                public init(rate: Double? = nil, timestamp: String? = nil, started_at: String? = nil, duration: Int? = nil) {
                    self.rate = rate
                    self.timestamp = timestamp
                    self.started_at = started_at
                    self.duration = duration
                }
            }
        }
        
        public struct SuggestedStatus: Codable, Sendable, Hashable {
            public let bg: Double?
            public let temp: String?
            public let rate: Double?
            public let duration: Int?
            public let reason: String?
            public let eventualBG: Double?
            public let snoozeBG: Double?
            public let minPredBG: Double?
            public let predBGs: PredBGs?
            public let COB: Double?
            public let IOB: Double?
            public let sensitivityRatio: Double?
            public let timestamp: String?
            
            public init(
                bg: Double? = nil,
                temp: String? = nil,
                rate: Double? = nil,
                duration: Int? = nil,
                reason: String? = nil,
                eventualBG: Double? = nil,
                snoozeBG: Double? = nil,
                minPredBG: Double? = nil,
                predBGs: PredBGs? = nil,
                COB: Double? = nil,
                IOB: Double? = nil,
                sensitivityRatio: Double? = nil,
                timestamp: String? = nil
            ) {
                self.bg = bg
                self.temp = temp
                self.rate = rate
                self.duration = duration
                self.reason = reason
                self.eventualBG = eventualBG
                self.snoozeBG = snoozeBG
                self.minPredBG = minPredBG
                self.predBGs = predBGs
                self.COB = COB
                self.IOB = IOB
                self.sensitivityRatio = sensitivityRatio
                self.timestamp = timestamp
            }
            
            public struct PredBGs: Codable, Sendable, Hashable {
                public let IOB: [Int]?
                public let COB: [Int]?
                public let UAM: [Int]?
                public let ZT: [Int]?
                
                public init(IOB: [Int]? = nil, COB: [Int]? = nil, UAM: [Int]? = nil, ZT: [Int]? = nil) {
                    self.IOB = IOB
                    self.COB = COB
                    self.UAM = UAM
                    self.ZT = ZT
                }
            }
        }
        
        public struct EnactedStatus: Codable, Sendable, Hashable {
            public let bg: Double?
            public let temp: String?
            public let rate: Double?
            public let duration: Int?
            public let reason: String?
            public let received: Bool?
            public let timestamp: String?
            
            public init(
                bg: Double? = nil,
                temp: String? = nil,
                rate: Double? = nil,
                duration: Int? = nil,
                reason: String? = nil,
                received: Bool? = nil,
                timestamp: String? = nil
            ) {
                self.bg = bg
                self.temp = temp
                self.rate = rate
                self.duration = duration
                self.reason = reason
                self.received = received
                self.timestamp = timestamp
            }
        }
    }
    
    // MARK: - Pump Status
    
    public struct PumpStatus: Codable, Sendable, Hashable {
        public let clock: String?
        public let reservoir: Double?
        public let battery: BatteryStatus?
        public let status: StatusInfo?
        public let suspended: Bool?
        
        public init(
            clock: String? = nil,
            reservoir: Double? = nil,
            battery: BatteryStatus? = nil,
            status: StatusInfo? = nil,
            suspended: Bool? = nil
        ) {
            self.clock = clock
            self.reservoir = reservoir
            self.battery = battery
            self.status = status
            self.suspended = suspended
        }
        
        public struct BatteryStatus: Codable, Sendable, Hashable {
            public let percent: Int?
            public let voltage: Double?
            public let status: String?
            
            public init(percent: Int? = nil, voltage: Double? = nil, status: String? = nil) {
                self.percent = percent
                self.voltage = voltage
                self.status = status
            }
        }
        
        public struct StatusInfo: Codable, Sendable, Hashable {
            public let status: String?
            public let bolusing: Bool?
            public let suspended: Bool?
            public let timestamp: String?
            
            public init(status: String? = nil, bolusing: Bool? = nil, suspended: Bool? = nil, timestamp: String? = nil) {
                self.status = status
                self.bolusing = bolusing
                self.suspended = suspended
                self.timestamp = timestamp
            }
        }
    }
    
    // MARK: - Uploader Status
    
    public struct UploaderStatus: Codable, Sendable, Hashable {
        public let battery: Int?
        public let batteryVoltage: Double?
        public let isCharging: Bool?
        public let name: String?
        
        public init(battery: Int? = nil, batteryVoltage: Double? = nil, isCharging: Bool? = nil, name: String? = nil) {
            self.battery = battery
            self.batteryVoltage = batteryVoltage
            self.isCharging = isCharging
            self.name = name
        }
    }
    
    // MARK: - Initialization
    
    public init(
        _id: String? = nil,
        device: String,
        created_at: String,
        mills: Int64? = nil,
        loop: LoopStatus? = nil,
        openaps: OpenAPSStatus? = nil,
        pump: PumpStatus? = nil,
        uploader: UploaderStatus? = nil
    ) {
        self._id = _id
        self.device = device
        self.created_at = created_at
        self.mills = mills
        self.loop = loop
        self.openaps = openaps
        self.pump = pump
        self.uploader = uploader
    }
    
    /// Timestamp as Date
    public var timestamp: Date? {
        if let mills = mills {
            return Date(timeIntervalSince1970: Double(mills) / 1000)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: created_at) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: created_at)
    }
    
    /// Check if this is a Loop status
    public var isLoopStatus: Bool {
        loop != nil
    }
    
    /// Check if this is an OpenAPS/AAPS status
    public var isOpenAPSStatus: Bool {
        openaps != nil
    }
    
    /// Detected AID system from device field (NS-MS-002)
    public var detectedSystem: AIDSystem {
        // First try device string
        let fromDevice = AIDSystem.detect(from: device)
        if fromDevice != .unknown {
            return fromDevice
        }
        
        // Fallback: infer from status format
        if loop != nil {
            return .loop
        }
        if openaps != nil {
            // Could be AAPS, Trio, or OpenAPS - can't distinguish without device string
            return .unknown
        }
        
        return .unknown
    }
    
    /// Detected device setup including hybrid configurations (NS-MS-003)
    /// Handles cases where CGM uploader (xDrip+, Spike) differs from AID system
    public var deviceSetup: DeviceSetup {
        let aidSystem = detectedSystem
        
        // Check if device string indicates a CGM uploader rather than AID system
        let cgmUploader = CGMUploader.detect(from: device)
        
        // Get uploader name from uploader object
        let uploaderName = uploader?.name
        
        return DeviceSetup(
            aidSystem: aidSystem,
            cgmUploader: cgmUploader,
            uploaderName: uploaderName
        )
    }
    
    /// Get IOB value from either Loop or OpenAPS
    public var iob: Double? {
        loop?.iob?.iob ?? openaps?.iob?.iob
    }
    
    /// Get COB value from either Loop or OpenAPS
    public var cob: Double? {
        loop?.cob?.cob ?? openaps?.suggested?.COB
    }
    
    /// Extract unified algorithm status (NS-MS-010)
    /// Normalizes Loop and OpenAPS formats into common representation
    public var unifiedStatus: UnifiedAlgorithmStatus {
        let system = detectedSystem
        
        // Parse timestamp
        let statusTimestamp = self.timestamp
        
        // Extract based on format
        if let loopStatus = loop {
            return extractLoopStatus(loopStatus, system: system, timestamp: statusTimestamp)
        } else if let openapsStatus = openaps {
            return extractOpenAPSStatus(openapsStatus, system: system, timestamp: statusTimestamp)
        }
        
        // Empty status
        return UnifiedAlgorithmStatus(system: system, timestamp: statusTimestamp)
    }
    
    /// Extract from Loop format (NS-MS-011)
    private func extractLoopStatus(_ loop: LoopStatus, system: AIDSystem, timestamp: Date?) -> UnifiedAlgorithmStatus {
        // Parse prediction start date
        var predStartDate: Date?
        if let startDateStr = loop.predicted?.startDate {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            predStartDate = formatter.date(from: startDateStr)
            if predStartDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                predStartDate = formatter.date(from: startDateStr)
            }
        }
        
        return UnifiedAlgorithmStatus(
            system: system,
            timestamp: timestamp,
            iob: loop.iob?.iob,
            basalIOB: nil,  // Loop doesn't separate basalIOB in standard format
            cob: loop.cob?.cob,
            enactedRate: loop.enacted?.rate,
            enactedDuration: loop.enacted?.duration.map { Int($0) },
            enactedBolus: loop.enacted?.bolusVolume,
            enactedReceived: loop.enacted?.received,
            predictions: loop.predicted?.values?.map { Double($0) },
            predictionStartDate: predStartDate,
            predBGs: nil,  // Loop uses single prediction array
            reason: nil,
            eventualBG: nil
        )
    }
    
    /// Extract from OpenAPS format (NS-MS-012)
    private func extractOpenAPSStatus(_ openaps: OpenAPSStatus, system: AIDSystem, timestamp: Date?) -> UnifiedAlgorithmStatus {
        let suggested = openaps.suggested
        let enacted = openaps.enacted
        let iobData = openaps.iob
        
        // Build predBGs if available
        var predBGs: UnifiedAlgorithmStatus.PredictionCurves?
        if let preds = suggested?.predBGs {
            predBGs = UnifiedAlgorithmStatus.PredictionCurves(
                iob: preds.IOB,
                cob: preds.COB,
                uam: preds.UAM,
                zt: preds.ZT
            )
        }
        
        // Convert primary prediction to Double array
        let predictions: [Double]? = predBGs?.primary?.map { Double($0) }
        
        return UnifiedAlgorithmStatus(
            system: system,
            timestamp: timestamp,
            iob: iobData?.iob,
            basalIOB: iobData?.basaliob,
            cob: suggested?.COB,
            enactedRate: enacted?.rate,
            enactedDuration: enacted?.duration,
            enactedBolus: nil,  // OpenAPS enacted doesn't have bolus field
            enactedReceived: enacted?.received,
            predictions: predictions,
            predictionStartDate: nil,  // OpenAPS doesn't provide explicit start
            predBGs: predBGs,
            reason: enacted?.reason ?? suggested?.reason,
            eventualBG: suggested?.eventualBG
        )
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(created_at)
        hasher.combine(device)
    }
    
    public static func == (lhs: NightscoutDeviceStatus, rhs: NightscoutDeviceStatus) -> Bool {
        lhs.created_at == rhs.created_at && lhs.device == rhs.device
    }
}
