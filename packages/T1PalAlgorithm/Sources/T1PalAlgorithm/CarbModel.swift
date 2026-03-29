// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CarbModel.swift
// T1Pal Mobile
//
// Carbohydrate absorption model and COB calculation
// Requirements: REQ-AID-003
//
// Based on oref0 carb absorption model:
// https://github.com/openaps/oref0/blob/master/lib/determine-basal/cob.js

import Foundation

// MARK: - Carb Absorption Types

/// Carb absorption speed categories
public enum CarbAbsorptionType: String, Codable, Sendable, CaseIterable {
    case fast = "fast"       // Simple sugars, juice, candy
    case medium = "medium"   // Bread, pasta, most meals
    case slow = "slow"       // High fat/protein meals, pizza
    
    /// Default absorption time in hours
    public var defaultAbsorptionTime: Double {
        switch self {
        case .fast: return 1.5    // 90 minutes
        case .medium: return 3.0  // 3 hours
        case .slow: return 5.0    // 5 hours
        }
    }
    
    public var displayName: String {
        switch self {
        case .fast: return "Fast (juice, candy)"
        case .medium: return "Medium (bread, pasta)"
        case .slow: return "Slow (pizza, high-fat)"
        }
    }
}

// MARK: - Carb Entry

/// A record of carbohydrates consumed
public struct CarbEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let grams: Double
    public let timestamp: Date
    public let absorptionType: CarbAbsorptionType
    public let absorptionTime: Double?  // Custom override in hours
    public let source: String           // "manual", "food-database", etc.
    public let foodType: String?        // Optional description
    
    public init(
        id: UUID = UUID(),
        grams: Double,
        timestamp: Date,
        absorptionType: CarbAbsorptionType = .medium,
        absorptionTime: Double? = nil,
        source: String = "manual",
        foodType: String? = nil
    ) {
        self.id = id
        self.grams = grams
        self.timestamp = timestamp
        self.absorptionType = absorptionType
        self.absorptionTime = absorptionTime
        self.source = source
        self.foodType = foodType
    }
    
    /// Effective absorption time (custom or default)
    public var effectiveAbsorptionTime: Double {
        absorptionTime ?? absorptionType.defaultAbsorptionTime
    }
}

// MARK: - Carb Absorption Model

/// Carb absorption curve model
/// Uses trapezoidal model similar to oref0
public struct CarbModel: Sendable {
    
    public init() {}
    
    /// Calculate fraction of carbs absorbed at time t (hours after eating)
    /// Uses a linear absorption model (trapezoidal approximation)
    public func absorbed(at t: Double, absorptionTime: Double) -> Double {
        guard t >= 0 else { return 0 }
        guard t <= absorptionTime else { return 1.0 }
        
        // Simple linear absorption
        // More sophisticated models use parabolic or exponential curves
        return t / absorptionTime
    }
    
    /// Calculate fraction of carbs remaining (COB ratio)
    public func remaining(at t: Double, absorptionTime: Double) -> Double {
        return 1.0 - absorbed(at: t, absorptionTime: absorptionTime)
    }
    
    /// Calculate carb absorption rate at time t (grams per hour)
    /// For linear model, this is constant during absorption
    public func absorptionRate(grams: Double, absorptionTime: Double, at t: Double) -> Double {
        guard t >= 0 && t <= absorptionTime else { return 0 }
        return grams / absorptionTime
    }
    
    /// Get COB curve as array of values at 5-minute intervals
    public func cobCurve(grams: Double, absorptionTime: Double, intervalMinutes: Int = 5) -> [Double] {
        let intervals = Int(absorptionTime * 60 / Double(intervalMinutes))
        return (0...intervals).map { i in
            let hours = Double(i * intervalMinutes) / 60.0
            return grams * remaining(at: hours, absorptionTime: absorptionTime)
        }
    }
}

// MARK: - COB Calculator

/// Calculates total COB from multiple carb entries
public struct COBCalculator: Sendable {
    public let model: CarbModel
    
    public init(model: CarbModel = CarbModel()) {
        self.model = model
    }
    
    /// Calculate COB from a single carb entry at a given time
    public func cobFromEntry(_ entry: CarbEntry, at time: Date) -> Double {
        let hoursAgo = time.timeIntervalSince(entry.timestamp) / 3600
        guard hoursAgo >= 0 else { return entry.grams }  // Future entry
        
        let remaining = model.remaining(at: hoursAgo, absorptionTime: entry.effectiveAbsorptionTime)
        return entry.grams * remaining
    }
    
    /// Calculate total COB from multiple entries
    public func totalCOB(from entries: [CarbEntry], at time: Date = Date()) -> Double {
        entries.reduce(0) { total, entry in
            total + cobFromEntry(entry, at: time)
        }
    }
    
    /// Calculate current carb absorption rate (grams/hour)
    public func absorptionRate(from entries: [CarbEntry], at time: Date = Date()) -> Double {
        entries.reduce(0) { total, entry in
            let hoursAgo = time.timeIntervalSince(entry.timestamp) / 3600
            guard hoursAgo >= 0 else { return total }
            return total + model.absorptionRate(
                grams: entry.grams,
                absorptionTime: entry.effectiveAbsorptionTime,
                at: hoursAgo
            )
        }
    }
    
    /// Project COB over time (for predictions)
    public func projectCOB(from entries: [CarbEntry],
                           startTime: Date = Date(),
                           durationMinutes: Int = 180,
                           intervalMinutes: Int = 5) -> [Double] {
        let intervals = durationMinutes / intervalMinutes
        return (0...intervals).map { i in
            let futureTime = startTime.addingTimeInterval(Double(i * intervalMinutes * 60))
            return totalCOB(from: entries, at: futureTime)
        }
    }
    
    /// Estimate time until carbs fully absorbed
    public func timeUntilAbsorbed(from entries: [CarbEntry], at time: Date = Date()) -> TimeInterval? {
        let activeEntries = entries.filter { entry in
            let hoursAgo = time.timeIntervalSince(entry.timestamp) / 3600
            return hoursAgo < entry.effectiveAbsorptionTime
        }
        
        guard !activeEntries.isEmpty else { return nil }
        
        // Find the entry that will finish absorbing last
        let maxRemainingTime = activeEntries.map { entry -> TimeInterval in
            let hoursAgo = time.timeIntervalSince(entry.timestamp) / 3600
            let hoursRemaining = entry.effectiveAbsorptionTime - hoursAgo
            return max(0, hoursRemaining * 3600)
        }.max()
        
        return maxRemainingTime
    }
}

// MARK: - Carb Ratio Helper

/// Helper for insulin-to-carb ratio calculations
public struct CarbRatioHelper: Sendable {
    
    /// Calculate bolus for carbs given ICR (insulin-to-carb ratio)
    /// - Parameters:
    ///   - grams: Carbs in grams
    ///   - icr: Insulin-to-carb ratio (grams per unit of insulin)
    /// - Returns: Insulin units needed
    public static func bolusForCarbs(grams: Double, icr: Double) -> Double {
        guard icr > 0 else { return 0 }
        return grams / icr
    }
    
    /// Calculate carbs covered by insulin
    /// - Parameters:
    ///   - units: Insulin units
    ///   - icr: Insulin-to-carb ratio
    /// - Returns: Grams of carbs covered
    public static func carbsCoveredByInsulin(units: Double, icr: Double) -> Double {
        return units * icr
    }
}
