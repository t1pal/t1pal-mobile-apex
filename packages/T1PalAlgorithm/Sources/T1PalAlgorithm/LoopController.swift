// SPDX-License-Identifier: AGPL-3.0-or-later
//
// LoopController.swift
// T1Pal Mobile
//
// Orchestrates the complete loop iteration: CGM → Algorithm → Dose
// Requirements: REQ-AID-002, REQ-SAFETY-001
//
// Trace: AID-LOOP-001, AID-SAFETY-001

import Foundation
import T1PalCore

// MARK: - Loop Controller Protocols

/// Protocol for CGM data source
public protocol CGMDataSource: Sendable {
    /// Fetch recent glucose readings
    func fetchGlucose() async throws -> [GlucoseReading]
}

/// Protocol for pump control
public protocol PumpController: Sendable {
    /// Enact a temp basal
    func setTempBasal(rate: Double, duration: TimeInterval) async throws
    
    /// Deliver a bolus
    func deliverBolus(units: Double) async throws
    
    /// Cancel current temp basal
    func cancelTempBasal() async throws
    
    /// Get current delivery status
    func getDeliveryStatus() async throws -> PumpDeliveryStatus
}

/// Pump delivery status
public struct PumpDeliveryStatus: Sendable {
    public let isDelivering: Bool
    public let currentTempBasal: TempBasal?
    public let lastBolus: BolusRecord?
    public let reservoirUnits: Double?
    
    public init(
        isDelivering: Bool = false,
        currentTempBasal: TempBasal? = nil,
        lastBolus: BolusRecord? = nil,
        reservoirUnits: Double? = nil
    ) {
        self.isDelivering = isDelivering
        self.currentTempBasal = currentTempBasal
        self.lastBolus = lastBolus
        self.reservoirUnits = reservoirUnits
    }
}

/// Bolus record
public struct BolusRecord: Sendable {
    public let units: Double
    public let timestamp: Date
    public let type: BolusType
    
    public enum BolusType: String, Sendable {
        case normal
        case smb
        case correction
    }
    
    public init(units: Double, timestamp: Date = Date(), type: BolusType = .normal) {
        self.units = units
        self.timestamp = timestamp
        self.type = type
    }
}

// MARK: - Loop Iteration Result

/// Complete result of a loop iteration
public struct LoopIterationResult: Sendable {
    /// Timestamp of iteration
    public let timestamp: Date
    
    /// Current glucose reading
    public let glucose: GlucoseReading?
    
    /// Algorithm decision (before safety)
    public let algorithmDecision: AlgorithmDecision?
    
    /// Safe decision (after safety limits)
    public let safeDecision: LoopDecision?
    
    /// Whether dose was enacted
    public let enacted: Bool
    
    /// Enactment result (success/failure message)
    public let enactmentResult: String?
    
    /// Any errors that occurred
    public let error: LoopIterationError?
    
    /// Execution time in seconds
    public let executionTime: TimeInterval
    
    public init(
        timestamp: Date = Date(),
        glucose: GlucoseReading? = nil,
        algorithmDecision: AlgorithmDecision? = nil,
        safeDecision: LoopDecision? = nil,
        enacted: Bool = false,
        enactmentResult: String? = nil,
        error: LoopIterationError? = nil,
        executionTime: TimeInterval = 0
    ) {
        self.timestamp = timestamp
        self.glucose = glucose
        self.algorithmDecision = algorithmDecision
        self.safeDecision = safeDecision
        self.enacted = enacted
        self.enactmentResult = enactmentResult
        self.error = error
        self.executionTime = executionTime
    }
    
    /// Whether the iteration was successful
    public var isSuccess: Bool {
        error == nil && algorithmDecision != nil
    }
}

/// Loop iteration errors
public enum LoopIterationError: Error, Sendable, Equatable {
    case noCGMData
    case staleGlucose(age: TimeInterval)
    case algorithmError(String)
    case pumpError(String)
    case safetyLimitExceeded(String)
    case loopSuspended
    case notConfigured
}

// MARK: - Loop Controller

/// Orchestrates the complete closed-loop iteration
/// Fetches CGM data, runs algorithm, applies safety, commands pump
public actor LoopController {
    
    // MARK: - Dependencies
    
    private let loopFacade: LoopFacade
    private var cgmSource: (any CGMDataSource)?
    private var pumpController: (any PumpController)?
    private var profileProvider: (@Sendable () -> T1PalCore.TherapyProfile)?
    
    // MARK: - Configuration
    
    /// Maximum age of glucose reading in seconds (default: 10 minutes)
    public var maxGlucoseAge: TimeInterval = 600
    
    /// Whether to enact doses (false = open loop)
    public var enactEnabled: Bool = false
    
    /// Whether the controller is running
    public private(set) var isRunning: Bool = false
    
    /// Last iteration result
    public private(set) var lastResult: LoopIterationResult?
    
    // MARK: - Callbacks
    
    public var onIterationComplete: (@Sendable (LoopIterationResult) -> Void)?
    public var onError: (@Sendable (LoopIterationError) -> Void)?
    
    // MARK: - Initialization
    
    public init(loopFacade: LoopFacade = .shared) {
        self.loopFacade = loopFacade
    }
    
    /// Configure the loop controller with data sources
    public func configure(
        cgmSource: any CGMDataSource,
        pumpController: any PumpController,
        profileProvider: @Sendable @escaping () -> T1PalCore.TherapyProfile
    ) {
        self.cgmSource = cgmSource
        self.pumpController = pumpController
        self.profileProvider = profileProvider
    }
    
    // MARK: - Loop Control
    
    /// Start the loop (enables running)
    public func start() {
        isRunning = true
    }
    
    /// Stop the loop (disables running)
    public func stop() {
        isRunning = false
    }
    
    /// Enable closed-loop dosing
    public func enableEnact() {
        enactEnabled = true
    }
    
    /// Disable closed-loop dosing (open loop)
    public func disableEnact() {
        enactEnabled = false
    }
    
    // MARK: - Loop Iteration
    
    /// Run a single loop iteration: CGM → Algorithm → Dose
    /// - Returns: Complete result of the iteration
    public func runIteration() async -> LoopIterationResult {
        let startTime = Date()
        
        // Check if running
        guard isRunning else {
            let result = LoopIterationResult(
                timestamp: startTime,
                error: .loopSuspended,
                executionTime: Date().timeIntervalSince(startTime)
            )
            lastResult = result
            onError?(.loopSuspended)
            return result
        }
        
        // Check configuration
        guard let cgmSource = cgmSource,
              let profileProvider = profileProvider else {
            let result = LoopIterationResult(
                timestamp: startTime,
                error: .notConfigured,
                executionTime: Date().timeIntervalSince(startTime)
            )
            lastResult = result
            onError?(.notConfigured)
            return result
        }
        
        // Step 1: Fetch CGM data
        let glucose: [GlucoseReading]
        do {
            glucose = try await cgmSource.fetchGlucose()
        } catch {
            let iterError = LoopIterationError.noCGMData
            let result = LoopIterationResult(
                timestamp: startTime,
                error: iterError,
                executionTime: Date().timeIntervalSince(startTime)
            )
            lastResult = result
            onError?(iterError)
            return result
        }
        
        // Check for valid glucose
        guard let latestGlucose = glucose.first else {
            let iterError = LoopIterationError.noCGMData
            let result = LoopIterationResult(
                timestamp: startTime,
                error: iterError,
                executionTime: Date().timeIntervalSince(startTime)
            )
            lastResult = result
            onError?(iterError)
            return result
        }
        
        // Check glucose age
        let glucoseAge = Date().timeIntervalSince(latestGlucose.timestamp)
        if glucoseAge > maxGlucoseAge {
            let iterError = LoopIterationError.staleGlucose(age: glucoseAge)
            let result = LoopIterationResult(
                timestamp: startTime,
                glucose: latestGlucose,
                error: iterError,
                executionTime: Date().timeIntervalSince(startTime)
            )
            lastResult = result
            onError?(iterError)
            return result
        }
        
        // Step 2: Get current profile
        let profile = profileProvider()
        
        // Step 3: Build algorithm inputs with parity schedules (ALG-DOSE-002/APP-WIRE-006)
        // Build schedule timeline covering algorithm prediction window (~6 hours)
        let now = Date()
        let scheduleStart = now.addingTimeInterval(-24 * 3600)  // 24 hours ago
        let scheduleEnd = now.addingTimeInterval(6 * 3600)      // 6 hours ahead
        
        // Build parity schedules from profile
        let basalSchedule = profile.basalRates.toAbsoluteSchedule(from: scheduleStart, to: scheduleEnd)
        let insulinSensitivitySchedule = profile.sensitivityFactors.toAbsoluteSchedule(from: scheduleStart, to: scheduleEnd)
        let correctionRangeSchedule = profile.targetGlucose.toAbsoluteSchedule(from: scheduleStart, to: scheduleEnd)
        
        let inputs = AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: 0,  // Will be calculated by algorithm
            carbsOnBoard: 0,    // Will be calculated by algorithm
            profile: profile,
            currentTime: Date(),
            basalSchedule: basalSchedule,
            insulinSensitivitySchedule: insulinSensitivitySchedule,
            correctionRangeSchedule: correctionRangeSchedule
        )
        
        // Step 4: Execute algorithm via LoopFacade
        let loopDecision: LoopDecision
        do {
            loopDecision = try loopFacade.execute(inputs)
        } catch let error as LoopError {
            let iterError = LoopIterationError.algorithmError(error.localizedDescription)
            let result = LoopIterationResult(
                timestamp: startTime,
                glucose: latestGlucose,
                error: iterError,
                executionTime: Date().timeIntervalSince(startTime)
            )
            lastResult = result
            onError?(iterError)
            return result
        } catch {
            let iterError = LoopIterationError.algorithmError(error.localizedDescription)
            let result = LoopIterationResult(
                timestamp: startTime,
                glucose: latestGlucose,
                error: iterError,
                executionTime: Date().timeIntervalSince(startTime)
            )
            lastResult = result
            onError?(iterError)
            return result
        }
        
        // Step 5: Enact dose (if enabled and in closed loop)
        var enacted = false
        var enactmentResult: String? = nil
        
        if enactEnabled, let pumpController = pumpController {
            enacted = await enactDose(loopDecision.safeDecision, pumpController: pumpController)
            enactmentResult = enacted ? "Dose enacted successfully" : "Enactment skipped or failed"
        } else {
            enactmentResult = enactEnabled ? "Pump not configured" : "Open loop - no enactment"
        }
        
        // Build final result
        let result = LoopIterationResult(
            timestamp: startTime,
            glucose: latestGlucose,
            algorithmDecision: loopDecision.rawDecision,
            safeDecision: loopDecision,
            enacted: enacted,
            enactmentResult: enactmentResult,
            executionTime: Date().timeIntervalSince(startTime)
        )
        
        lastResult = result
        onIterationComplete?(result)
        return result
    }
    
    // MARK: - Dose Enactment
    
    /// Enact the recommended dose on the pump
    private func enactDose(_ decision: SafeDecision, pumpController: any PumpController) async -> Bool {
        // Enact temp basal if recommended
        if let tempBasal = decision.tempBasal {
            do {
                try await pumpController.setTempBasal(rate: tempBasal.rate, duration: tempBasal.duration)
            } catch {
                return false
            }
        }
        
        // Enact bolus if recommended (SMB)
        if let bolus = decision.bolus, bolus > 0 {
            do {
                try await pumpController.deliverBolus(units: bolus)
            } catch {
                return false
            }
        }
        
        return true
    }
}

// MARK: - Mock Implementations for Testing

/// Mock CGM data source for testing
public actor MockCGMSource: CGMDataSource {
    private var readings: [GlucoseReading]
    
    public init(readings: [GlucoseReading] = []) {
        self.readings = readings
    }
    
    public func setReadings(_ readings: [GlucoseReading]) {
        self.readings = readings
    }
    
    public func fetchGlucose() async throws -> [GlucoseReading] {
        guard !readings.isEmpty else {
            throw LoopIterationError.noCGMData
        }
        return readings
    }
}

/// Mock pump controller for testing
public actor MockPumpController: PumpController {
    public private(set) var lastTempBasal: TempBasal?
    public private(set) var lastBolus: Double?
    public private(set) var tempBasalCancelled: Bool = false
    public private(set) var commandCount: Int = 0
    
    public var shouldFail: Bool = false
    
    public init() {}
    
    public func setTempBasal(rate: Double, duration: TimeInterval) async throws {
        commandCount += 1
        if shouldFail {
            throw LoopIterationError.pumpError("Mock pump failure")
        }
        lastTempBasal = TempBasal(rate: rate, duration: duration)
    }
    
    public func deliverBolus(units: Double) async throws {
        commandCount += 1
        if shouldFail {
            throw LoopIterationError.pumpError("Mock pump failure")
        }
        lastBolus = units
    }
    
    public func cancelTempBasal() async throws {
        commandCount += 1
        if shouldFail {
            throw LoopIterationError.pumpError("Mock pump failure")
        }
        tempBasalCancelled = true
        lastTempBasal = nil
    }
    
    public func getDeliveryStatus() async throws -> PumpDeliveryStatus {
        PumpDeliveryStatus(
            isDelivering: lastTempBasal != nil,
            currentTempBasal: lastTempBasal,
            lastBolus: lastBolus.map { BolusRecord(units: $0) }
        )
    }
    
    public func reset() {
        lastTempBasal = nil
        lastBolus = nil
        tempBasalCancelled = false
        commandCount = 0
        shouldFail = false
    }
}
