// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmInputAssembler.swift
// T1Pal Mobile
//
// Shared service for building high-fidelity algorithm inputs
// Requirements: ALG-INPUT-001

import Foundation
import T1PalCore

// MARK: - AlgorithmInputAssembler

/// Assembles algorithm inputs from various data sources.
///
/// This actor provides a unified way to gather all required data for algorithm
/// execution, regardless of the data source (Nightscout, mock, direct CGM/pump).
///
/// Used by: CLI tool, Playground, Demo app, AID app, Research app
///
/// Usage:
/// ```swift
/// let assembler = AlgorithmInputAssembler(dataSource: nightscoutSource)
/// let inputs = try await assembler.assembleInputs()
/// let result = algorithm.calculate(inputs)
/// ```
public actor AlgorithmInputAssembler {
    
    // MARK: - Configuration
    
    /// The data source for fetching glucose, doses, carbs, and profile
    public let dataSource: any AlgorithmDataSource
    
    /// Configuration for input assembly
    public struct Configuration: Sendable {
        /// Number of glucose readings to fetch
        public var glucoseCount: Int
        
        /// Hours of dose history to fetch
        public var doseHistoryHours: Int
        
        /// Hours of carb history to fetch
        public var carbHistoryHours: Int
        
        /// Minimum glucose readings required
        public var minimumGlucoseCount: Int
        
        /// Whether to calculate IOB from dose history
        public var calculateIOB: Bool
        
        /// Whether to calculate COB from carb history
        public var calculateCOB: Bool
        
        /// Whether to apply loop settings to profile
        public var applyLoopSettings: Bool
        
        public init(
            glucoseCount: Int = AlgorithmDataDefaults.glucoseCount,
            doseHistoryHours: Int = AlgorithmDataDefaults.doseHistoryHours,
            carbHistoryHours: Int = AlgorithmDataDefaults.carbHistoryHours,
            minimumGlucoseCount: Int = AlgorithmDataDefaults.minimumGlucoseCount,
            calculateIOB: Bool = true,
            calculateCOB: Bool = true,
            applyLoopSettings: Bool = true
        ) {
            self.glucoseCount = glucoseCount
            self.doseHistoryHours = doseHistoryHours
            self.carbHistoryHours = carbHistoryHours
            self.minimumGlucoseCount = minimumGlucoseCount
            self.calculateIOB = calculateIOB
            self.calculateCOB = calculateCOB
            self.applyLoopSettings = applyLoopSettings
        }
        
        /// Default configuration
        public static let `default` = Configuration()
        
        /// High-fidelity configuration with full history
        public static let highFidelity = Configuration(
            glucoseCount: 72,  // 6 hours
            doseHistoryHours: 8,
            carbHistoryHours: 8
        )
        
        /// Minimal configuration for quick checks
        public static let minimal = Configuration(
            glucoseCount: 12,  // 1 hour
            doseHistoryHours: 4,
            carbHistoryHours: 4
        )
    }
    
    /// Current configuration
    public var configuration: Configuration
    
    // MARK: - Initialization
    
    public init(
        dataSource: any AlgorithmDataSource,
        configuration: Configuration = .default
    ) {
        self.dataSource = dataSource
        self.configuration = configuration
    }
    
    // MARK: - Input Assembly
    
    /// Assemble all algorithm inputs at the current time.
    /// - Returns: Complete algorithm inputs ready for calculation
    /// - Throws: AlgorithmDataSourceError if data cannot be fetched
    public func assembleInputs() async throws -> AlgorithmInputs {
        try await assembleInputs(at: Date())
    }
    
    /// Assemble all algorithm inputs at a specific time.
    /// - Parameter time: The reference time for input assembly
    /// - Returns: Complete algorithm inputs ready for calculation
    /// - Throws: AlgorithmDataSourceError if data cannot be fetched
    public func assembleInputs(at time: Date) async throws -> AlgorithmInputs {
        // Fetch glucose history
        let glucose = try await dataSource.glucoseHistory(count: configuration.glucoseCount)
        
        // Validate minimum glucose data
        guard glucose.count >= configuration.minimumGlucoseCount else {
            throw AlgorithmDataSourceError.insufficientGlucoseData(
                required: configuration.minimumGlucoseCount,
                available: glucose.count
            )
        }
        
        // Fetch dose and carb history
        let doses = try await dataSource.doseHistory(hours: configuration.doseHistoryHours)
        let carbs = try await dataSource.carbHistory(hours: configuration.carbHistoryHours)
        
        // Fetch and optionally enhance profile
        var profile = try await dataSource.currentProfile()
        
        // Apply loop settings if configured
        if configuration.applyLoopSettings {
            if let loopSettings = try await dataSource.loopSettings() {
                profile = applyLoopSettings(loopSettings, to: profile)
            }
        }
        
        // Calculate IOB and COB if configured
        let iob = configuration.calculateIOB ? calculateIOB(from: doses, at: time, profile: profile) : 0
        let cob = configuration.calculateCOB ? calculateCOB(from: carbs, at: time) : 0
        
        return AlgorithmInputs(
            glucose: glucose,
            insulinOnBoard: iob,
            carbsOnBoard: cob,
            profile: profile,
            currentTime: time,
            activeOverride: nil,
            doseHistory: doses,
            carbHistory: carbs
        )
    }
    
    // MARK: - Profile Enhancement
    
    private func applyLoopSettings(_ settings: LoopSettings, to profile: TherapyProfile) -> TherapyProfile {
        var enhanced = profile
        
        if let maxBasal = settings.maximumBasalRatePerHour {
            enhanced.maxBasalRate = maxBasal
        }
        if let maxBolus = settings.maximumBolus {
            enhanced.maxBolus = maxBolus
        }
        if let suspendThreshold = settings.minimumBGGuard {
            enhanced.suspendThreshold = suspendThreshold
        }
        if let strategy = settings.dosingStrategy {
            enhanced.dosingStrategy = strategy
        }
        
        return enhanced
    }
    
    // MARK: - IOB/COB Calculation
    
    /// Calculate insulin on board from dose history.
    /// Uses exponential decay model with ~4 hour duration.
    private func calculateIOB(from doses: [InsulinDose], at time: Date, profile: TherapyProfile) -> Double {
        // Use insulin model DIA (default 6 hours, peak at 75 min)
        let dia: TimeInterval = 6 * 3600  // 6 hours in seconds
        
        var totalIOB: Double = 0
        
        for dose in doses {
            let elapsed = time.timeIntervalSince(dose.timestamp)
            
            // Skip doses in the future or beyond DIA
            guard elapsed >= 0 && elapsed < dia else { continue }
            
            // Exponential decay model (simplified)
            let fractionRemaining = max(0, 1 - (elapsed / dia))
            // Apply curve (more insulin active in first 2 hours)
            let activityFactor = fractionRemaining * fractionRemaining
            
            totalIOB += dose.units * activityFactor
        }
        
        return totalIOB
    }
    
    /// Calculate carbs on board from carb history.
    /// Uses linear absorption model.
    private func calculateCOB(from carbs: [CarbEntry], at time: Date) -> Double {
        var totalCOB: Double = 0
        
        for entry in carbs {
            let elapsed = time.timeIntervalSince(entry.timestamp)
            
            // Skip entries in the future
            guard elapsed >= 0 else { continue }
            
            // Get absorption time (default based on type or custom)
            let absorptionHours = entry.effectiveAbsorptionTime
            let absorptionSeconds = absorptionHours * 3600
            
            // Skip if fully absorbed
            guard elapsed < absorptionSeconds else { continue }
            
            // Linear absorption model
            let fractionRemaining = 1 - (elapsed / absorptionSeconds)
            totalCOB += entry.grams * fractionRemaining
        }
        
        return totalCOB
    }
}

// MARK: - Assembly Result

/// Extended result from input assembly with metadata
public struct AssemblyResult: Sendable {
    /// The assembled algorithm inputs
    public let inputs: AlgorithmInputs
    
    /// Time taken to assemble inputs
    public let assemblyDuration: TimeInterval
    
    /// Data freshness (age of most recent glucose)
    public let dataAge: TimeInterval
    
    /// Number of glucose readings fetched
    public let glucoseCount: Int
    
    /// Number of doses in history
    public let doseCount: Int
    
    /// Number of carb entries in history
    public let carbCount: Int
    
    /// Whether loop settings were applied
    public let loopSettingsApplied: Bool
}

// MARK: - Extended Assembly

public extension AlgorithmInputAssembler {
    
    /// Assemble inputs with metadata about the assembly process.
    func assembleWithMetadata(at time: Date = Date()) async throws -> AssemblyResult {
        let startTime = Date()
        
        let inputs = try await assembleInputs(at: time)
        
        let assemblyDuration = Date().timeIntervalSince(startTime)
        let dataAge = inputs.glucose.first.map { time.timeIntervalSince($0.timestamp) } ?? .infinity
        
        // Check if loop settings were applied
        let loopSettings = try? await dataSource.loopSettings()
        
        return AssemblyResult(
            inputs: inputs,
            assemblyDuration: assemblyDuration,
            dataAge: dataAge,
            glucoseCount: inputs.glucose.count,
            doseCount: inputs.doseHistory?.count ?? 0,
            carbCount: inputs.carbHistory?.count ?? 0,
            loopSettingsApplied: loopSettings != nil && configuration.applyLoopSettings
        )
    }
}
