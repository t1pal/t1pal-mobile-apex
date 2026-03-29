// GlucoseColor.swift
// T1PalCore
//
// Unified glucose color categorization for consistent UI display.
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
// Trace: COMPL-DUP-002

import Foundation

// MARK: - Glucose Color Category

/// Standard glucose range categories for color coding.
/// Used consistently across all T1Pal apps for visual glucose indication.
///
/// Standard thresholds (mg/dL):
/// - urgentLow: < 55
/// - low: 55-70
/// - inRange: 70-180
/// - high: 180-250
/// - urgentHigh: > 250
public enum GlucoseColorCategory: String, Sendable, Codable, CaseIterable, Hashable {
    case urgentLow = "urgentLow"
    case low = "low"
    case inRange = "inRange"
    case high = "high"
    case urgentHigh = "urgentHigh"
    case veryHigh = "veryHigh"  // Alias for urgentHigh (backwards compatibility)
    case stale = "stale"
    
    /// Initialize from a glucose value in mg/dL
    public init(glucose: Double, thresholds: GlucoseThresholds = .default) {
        switch glucose {
        case ..<thresholds.urgentLow:
            self = .urgentLow
        case thresholds.urgentLow..<thresholds.low:
            self = .low
        case thresholds.low..<thresholds.high:
            self = .inRange
        case thresholds.high..<thresholds.urgentHigh:
            self = .high
        default:
            self = .urgentHigh
        }
    }
    
    /// Initialize from a glucose value with unit conversion
    public init(glucose: Double, unit: GlucoseUnit, thresholds: GlucoseThresholds = .default) {
        let mgdL = unit == .mmolL ? glucose * 18.0182 : glucose
        self.init(glucose: mgdL, thresholds: thresholds)
    }
}

// MARK: - Glucose Thresholds

/// Configurable thresholds for glucose color categories
public struct GlucoseThresholds: Sendable, Codable, Equatable {
    public let urgentLow: Double
    public let low: Double
    public let high: Double
    public let urgentHigh: Double
    
    public init(
        urgentLow: Double = 55,
        low: Double = 70,
        high: Double = 180,
        urgentHigh: Double = 250
    ) {
        self.urgentLow = urgentLow
        self.low = low
        self.high = high
        self.urgentHigh = urgentHigh
    }
    
    /// Standard clinical thresholds
    public static let `default` = GlucoseThresholds()
    
    /// Tighter control thresholds (e.g., pregnancy)
    public static let tight = GlucoseThresholds(
        urgentLow: 60,
        low: 63,
        high: 140,
        urgentHigh: 200
    )
}

