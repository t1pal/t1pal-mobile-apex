// RileyLinkConfig.swift
// PumpKit
//
// SPDX-License-Identifier: MIT
// Copyright 2026 T1Pal.org
// Trace: RL-CONFIG-ARCH-001
//
// Observable configuration for RileyLink sessions.
// SwiftUI views bind directly to this; session reads values when executing commands.

import Foundation
import Observation

// MARK: - TimingTraceEntry

/// Entry capturing command latency phases
/// Trace: RL-DIAG-005
public struct TimingTraceEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let commandName: String
    public let phases: [Phase]
    public let totalDuration: TimeInterval
    
    /// A single timing phase within a command
    public struct Phase: Sendable {
        public let name: String
        public let duration: TimeInterval
        
        public init(name: String, duration: TimeInterval) {
            self.name = name
            self.duration = duration
        }
        
        /// Duration formatted as milliseconds
        public var formattedDuration: String {
            String(format: "%.1f ms", duration * 1000)
        }
    }
    
    public init(timestamp: Date = Date(), commandName: String, phases: [Phase], totalDuration: TimeInterval) {
        self.timestamp = timestamp
        self.commandName = commandName
        self.phases = phases
        self.totalDuration = totalDuration
    }
    
    /// Formatted timestamp
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    /// Total duration formatted as milliseconds
    public var formattedTotalDuration: String {
        String(format: "%.1f ms", totalDuration * 1000)
    }
    
    /// Summary line for display
    public var summary: String {
        "\(commandName): \(formattedTotalDuration)"
    }
    
    /// Detailed breakdown
    public var detailedBreakdown: String {
        var lines = ["\(commandName) - Total: \(formattedTotalDuration)"]
        for phase in phases {
            lines.append("  \(phase.name): \(phase.formattedDuration)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - PacketLogEntry

/// Entry in the BLE packet log for debugging
/// Trace: RL-PLAYGROUND-005
public struct PacketLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let direction: PacketDirection
    public let data: Data
    public let label: String
    
    public enum PacketDirection: String, Sendable {
        case tx = "TX"
        case rx = "RX"
    }
    
    public init(timestamp: Date = Date(), direction: PacketDirection, data: Data, label: String = "") {
        self.timestamp = timestamp
        self.direction = direction
        self.data = data
        self.label = label
    }
    
    /// Hex string representation (compact)
    public var hexString: String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
    
    /// Formatted timestamp
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    /// RL-DIAG-003: Detailed hex dump with offset + ASCII
    /// Format: "0000: 48 65 6C 6C 6F 20 57 6F  72 6C 64 21 00 00 00 00  |Hello World!....|"
    public var hexDump: String {
        guard !data.isEmpty else { return "(empty)" }
        
        var lines: [String] = []
        let bytesPerLine = 16
        
        for offset in stride(from: 0, to: data.count, by: bytesPerLine) {
            let end = min(offset + bytesPerLine, data.count)
            let chunk = data[offset..<end]
            
            // Offset
            let offsetStr = String(format: "%04X:", offset)
            
            // Hex bytes (first 8, space, second 8)
            var hexPart = ""
            for (i, byte) in chunk.enumerated() {
                if i == 8 { hexPart += " " }
                hexPart += String(format: "%02X ", byte)
            }
            // Pad if less than 16 bytes
            let missingBytes = bytesPerLine - chunk.count
            for i in 0..<missingBytes {
                if chunk.count + i == 8 { hexPart += " " }
                hexPart += "   "
            }
            
            // ASCII representation
            let ascii = chunk.map { byte -> Character in
                (0x20...0x7E).contains(byte) ? Character(UnicodeScalar(byte)) : "."
            }
            let asciiStr = String(ascii)
            
            lines.append("\(offsetStr) \(hexPart) |\(asciiStr)|")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Byte count for display
    public var byteCount: Int { data.count }
}

// MARK: - RileyLinkConfig

/// Observable configuration for RileyLink communication
/// 
/// SwiftUI views bind directly to this config object. The RileyLinkSession
/// reads these values when executing commands, ensuring single source of truth.
///
/// ## Usage
/// ```swift
/// let config = RileyLinkConfig()
/// let session = try await RileyLinkSession(peripheral: p, config: config)
/// 
/// // SwiftUI binds directly
/// Slider(value: $config.responseTimeout, in: 1...30)
/// Toggle("Skip Wakeup", isOn: $config.skipWakeup)
/// ```
///
/// Trace: RL-CONFIG-ARCH-001
@Observable
@MainActor
public final class RileyLinkConfig: Sendable {
    
    // MARK: - RF Configuration
    
    /// Response timeout in seconds (1-30, default 5)
    /// How long to wait for pump response after sending command
    /// Trace: RL-CONFIG-001
    public var responseTimeout: TimeInterval = 5.0
    
    /// Wakeup duration in minutes (1-10, default 2)
    /// How long the pump stays awake after wakeup command
    /// Trace: RL-CONFIG-002
    public var wakeupDurationMinutes: Int = 2
    
    /// Wakeup repeat count (50-500, default 255)
    /// Number of times to repeat the wakeup packet burst
    /// Trace: RL-CONFIG-003
    public var wakeupRepeatCount: Int = 255
    
    // MARK: - Debug Toggles
    
    /// Skip wakeup sequence for quick iteration
    /// When enabled, pump commands skip the wakeup phase
    /// Trace: RL-CONFIG-004
    public var skipWakeup: Bool = false
    
    /// Strict mode disables simulation fallbacks
    /// When enabled, BLE failures throw errors instead of falling back
    /// Trace: RL-MODE-004
    public var strictMode: Bool = false
    
    /// Debug mode enables verbose logging and diagnostic UI
    /// Trace: RL-DIAG-001
    public var debugMode: Bool = false
    
    /// RF retry count for pump commands (1-10, default 3)
    /// Trace: RL-CONFIG-005
    public var retryCount: Int = 3
    
    // MARK: - Packet Log
    
    /// Raw BLE packet log for debugging
    /// Shows TX/RX hex dumps with timestamps
    /// Trace: RL-PLAYGROUND-005
    public private(set) var packetLog: [PacketLogEntry] = []
    
    /// Maximum number of log entries to keep
    public var maxPacketLogEntries: Int = 50
    
    // MARK: - Timing Trace Log
    
    /// Command latency traces for debugging
    /// Shows per-phase timing breakdown
    /// Trace: RL-DIAG-005
    public private(set) var timingLog: [TimingTraceEntry] = []
    
    /// Maximum number of timing entries to keep
    public var maxTimingLogEntries: Int = 50
    
    // MARK: - Read-only State (set by session)
    
    /// Whether a session is currently connected
    public private(set) var isConnected: Bool = false
    
    /// Current firmware version string (if read)
    public private(set) var firmwareVersion: String?
    
    /// Current RF frequency in MHz
    public private(set) var currentFrequency: Double?
    
    // MARK: - Initialization
    
    public nonisolated init() {}
    
    // MARK: - Packet Log Management
    
    /// Add a packet to the log (called by session)
    public func addPacket(direction: PacketLogEntry.PacketDirection, data: Data, label: String = "") {
        let entry = PacketLogEntry(direction: direction, data: data, label: label)
        packetLog.append(entry)
        
        // Trim to max size
        while packetLog.count > maxPacketLogEntries {
            packetLog.removeFirst()
        }
    }
    
    /// Clear the packet log
    public func clearPacketLog() {
        packetLog.removeAll()
    }
    
    // MARK: - Timing Log Management
    
    /// Add a timing trace entry (called by session)
    /// Trace: RL-DIAG-005
    public func addTimingTrace(commandName: String, phases: [TimingTraceEntry.Phase], totalDuration: TimeInterval) {
        let entry = TimingTraceEntry(commandName: commandName, phases: phases, totalDuration: totalDuration)
        timingLog.append(entry)
        
        // Trim to max size
        while timingLog.count > maxTimingLogEntries {
            timingLog.removeFirst()
        }
    }
    
    /// Clear the timing log
    public func clearTimingLog() {
        timingLog.removeAll()
    }
    
    // MARK: - State Updates (called by session)
    
    /// Update connection state (called by session)
    public func setConnected(_ connected: Bool) {
        isConnected = connected
    }
    
    /// Update firmware version (called by session)
    public func setFirmwareVersion(_ version: String?) {
        firmwareVersion = version
    }
    
    /// Update current frequency (called by session)
    public func setCurrentFrequency(_ frequency: Double?) {
        currentFrequency = frequency
    }
}

// MARK: - Sendable Snapshot

extension RileyLinkConfig {
    /// Snapshot of config values for passing to actor-isolated code
    /// Since RileyLinkConfig is @MainActor, we need this for cross-actor access
    public struct Snapshot: Sendable {
        public let responseTimeout: TimeInterval
        public let wakeupDurationMinutes: Int
        public let wakeupRepeatCount: Int
        public let skipWakeup: Bool
        public let strictMode: Bool
        
        public init(
            responseTimeout: TimeInterval,
            wakeupDurationMinutes: Int,
            wakeupRepeatCount: Int,
            skipWakeup: Bool,
            strictMode: Bool
        ) {
            self.responseTimeout = responseTimeout
            self.wakeupDurationMinutes = wakeupDurationMinutes
            self.wakeupRepeatCount = wakeupRepeatCount
            self.skipWakeup = skipWakeup
            self.strictMode = strictMode
        }
    }
    
    /// Create a sendable snapshot of current config values
    public var snapshot: Snapshot {
        Snapshot(
            responseTimeout: responseTimeout,
            wakeupDurationMinutes: wakeupDurationMinutes,
            wakeupRepeatCount: wakeupRepeatCount,
            skipWakeup: skipWakeup,
            strictMode: strictMode
        )
    }
}
