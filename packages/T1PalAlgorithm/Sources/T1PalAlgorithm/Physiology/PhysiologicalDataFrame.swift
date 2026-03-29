// PhysiologicalDataFrame.swift
// T1PalAlgorithm
//
// Physiological snapshot and data frame types
// Source: GlucOS AddedGlucoseDataFrame pattern
// Trace: GLUCOS-IMPL-003, ADR-010

import Foundation

/// 5-minute physiological snapshot
/// Source: GlucOS AddedGlucoseDataFrame
/// Trace: GLUCOS-DES-004
public struct PhysiologicalSnapshot: Sendable, Codable, Equatable {
    /// Timestamp of snapshot
    public let timestamp: Date
    
    /// Glucose value (mg/dL)
    public let glucose: Double
    
    /// Insulin delivered in prior 5 minutes (units)
    public let insulinDelivered: Double
    
    /// Insulin on board at this time (units)
    public let insulinOnBoard: Double
    
    /// Carbs on board at this time (grams)
    public let carbsOnBoard: Double
    
    public init(
        timestamp: Date,
        glucose: Double,
        insulinDelivered: Double,
        insulinOnBoard: Double,
        carbsOnBoard: Double = 0
    ) {
        self.timestamp = timestamp
        self.glucose = glucose
        self.insulinDelivered = insulinDelivered
        self.insulinOnBoard = insulinOnBoard
        self.carbsOnBoard = carbsOnBoard
    }
    
    /// Delta to previous snapshot
    public func delta(from previous: PhysiologicalSnapshot) -> SnapshotDelta {
        let timeDelta = timestamp.timeIntervalSince(previous.timestamp)
        let glucoseDelta = glucose - previous.glucose
        
        return SnapshotDelta(
            timeDelta: timeDelta,
            glucoseDelta: glucoseDelta,
            glucoseRatePerHour: timeDelta > 0 ? (glucoseDelta / timeDelta) * 3600 : 0,
            insulinDelta: insulinOnBoard - previous.insulinOnBoard,
            carbsDelta: carbsOnBoard - previous.carbsOnBoard
        )
    }
}

/// Change between two snapshots
public struct SnapshotDelta: Sendable, Equatable {
    public let timeDelta: TimeInterval
    public let glucoseDelta: Double
    public let glucoseRatePerHour: Double
    public let insulinDelta: Double
    public let carbsDelta: Double
}

/// Collection of physiological snapshots for analysis
public struct PhysiologicalDataFrame: Sendable {
    /// Ordered snapshots (oldest first)
    public let snapshots: [PhysiologicalSnapshot]
    
    /// Standard frame size (24 snapshots = 2 hours)
    public static let standardSize = 24
    
    /// Minimum required snapshots
    public static let minimumSize = 20
    
    public init(snapshots: [PhysiologicalSnapshot]) {
        self.snapshots = snapshots.sorted { $0.timestamp < $1.timestamp }
    }
    
    public var isEmpty: Bool {
        snapshots.isEmpty
    }
    
    public var count: Int {
        snapshots.count
    }
    
    public var isValid: Bool {
        snapshots.count >= Self.minimumSize
    }
    
    public var duration: TimeInterval {
        guard let first = snapshots.first, let last = snapshots.last else {
            return 0
        }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }
    
    public var latestGlucose: Double? {
        snapshots.last?.glucose
    }
    
    public var latestIOB: Double? {
        snapshots.last?.insulinOnBoard
    }
    
    public var averageGlucose: Double? {
        guard !snapshots.isEmpty else { return nil }
        return snapshots.reduce(0) { $0 + $1.glucose } / Double(snapshots.count)
    }
    
    public var glucoseRange: (min: Double, max: Double)? {
        guard !snapshots.isEmpty else { return nil }
        let values = snapshots.map { $0.glucose }
        return (min: values.min()!, max: values.max()!)
    }
    
    /// Get all deltas between consecutive snapshots
    public var deltas: [SnapshotDelta] {
        guard snapshots.count >= 2 else { return [] }
        
        return (1..<snapshots.count).map { i in
            snapshots[i].delta(from: snapshots[i - 1])
        }
    }
    
    /// Get recent snapshots (last N)
    public func recent(_ count: Int) -> PhysiologicalDataFrame {
        let startIndex = max(0, snapshots.count - count)
        return PhysiologicalDataFrame(snapshots: Array(snapshots[startIndex...]))
    }
    
    /// Filter snapshots by time range
    public func filtered(from start: Date, to end: Date) -> PhysiologicalDataFrame {
        let filtered = snapshots.filter { $0.timestamp >= start && $0.timestamp <= end }
        return PhysiologicalDataFrame(snapshots: filtered)
    }
}

/// Result from PID controller calculation
/// Source: GlucOS PIDTempBasalResult
public struct PIDTempBasalResult: Sendable, Equatable {
    /// Recommended temp basal rate (U/hr)
    public let tempBasal: Double
    
    /// Proportional component contribution
    public let proportional: Double
    
    /// Integral component contribution
    public let integral: Double
    
    /// Derivative component contribution
    public let derivative: Double
    
    /// Delta glucose error (mg/dL/hr)
    public let deltaGlucoseError: Double?
    
    /// Whether digestion is detected
    public let isDigesting: Bool
    
    /// Human-readable reason
    public let reason: String
    
    public init(
        tempBasal: Double,
        proportional: Double = 0,
        integral: Double = 0,
        derivative: Double = 0,
        deltaGlucoseError: Double? = nil,
        isDigesting: Bool = false,
        reason: String = ""
    ) {
        self.tempBasal = tempBasal
        self.proportional = proportional
        self.integral = integral
        self.derivative = derivative
        self.deltaGlucoseError = deltaGlucoseError
        self.isDigesting = isDigesting
        self.reason = reason
    }
    
    /// Total PID contribution (P + I + D)
    public var totalPID: Double {
        proportional + integral + derivative
    }
}

/// IOB calculation result with breakdown
/// Source: GlucOS IOBManager pattern
public struct IOBResult: Sendable, Equatable {
    /// Total IOB (units)
    public let total: Double
    
    /// Basal IOB (from temp basals)
    public let basal: Double
    
    /// Bolus IOB (from manual boluses)
    public let bolus: Double
    
    /// Time until IOB reaches zero (seconds)
    public let timeToZero: TimeInterval
    
    /// Activity curve (insulin effect per 5-min interval)
    public let activityCurve: [Double]
    
    public init(
        total: Double,
        basal: Double,
        bolus: Double,
        timeToZero: TimeInterval,
        activityCurve: [Double] = []
    ) {
        self.total = total
        self.basal = basal
        self.bolus = bolus
        self.timeToZero = timeToZero
        self.activityCurve = activityCurve
    }
    
    /// Hours until IOB reaches zero
    public var hoursToZero: Double {
        timeToZero / 3600
    }
    
    /// Create a zero IOB result
    public static var zero: IOBResult {
        IOBResult(total: 0, basal: 0, bolus: 0, timeToZero: 0)
    }
}
