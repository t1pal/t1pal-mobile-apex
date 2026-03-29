// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SensorState.swift
// CGMKitShare
//
// Sensor state enum shared between local and cloud CGM sources

import Foundation

/// CGM sensor state
/// Used by both local BLE managers and cloud clients to track sensor lifecycle
public enum SensorState: String, Sendable {
    /// Sensor not started
    case notStarted
    /// Sensor warming up (initial calibration period)
    case warmingUp
    /// Sensor active and reading
    case active
    /// Sensor expired
    case expired
    /// Sensor failed
    case failed
    /// Sensor stopped (disconnected or ended)
    case stopped
    /// No sensor attached (transmitter reports invalid session)
    /// Trace: GAP-API-021 (future-dated entries fix)
    case noSensor
}
