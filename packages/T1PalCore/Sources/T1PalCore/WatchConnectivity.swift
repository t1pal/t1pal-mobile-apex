// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// WatchConnectivity.swift - Apple Watch communication
// Part of T1PalCore
// Trace: WATCH-SYNC-001

import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - Watch Message Types

/// Types of messages sent between iPhone and Watch
public enum WatchMessageType: String, Codable, Sendable {
    case glucoseUpdate = "glucose.update"
    case glucoseHistory = "glucose.history"
    case settingsSync = "settings.sync"
    case alertTriggered = "alert.triggered"
    case alertDismissed = "alert.dismissed"
    case snoozeRequest = "snooze.request"
    case refreshRequest = "refresh.request"
    case complicationUpdate = "complication.update"
}

// MARK: - Watch Glucose Data

/// Glucose data optimized for Watch transfer
public struct WatchGlucoseUpdate: Codable, Sendable {
    public let glucose: Double
    public let trend: String
    public let timestamp: Date
    public let delta: Double?
    public let isStale: Bool
    
    public init(
        glucose: Double,
        trend: String,
        timestamp: Date,
        delta: Double? = nil,
        isStale: Bool = false
    ) {
        self.glucose = glucose
        self.trend = trend
        self.timestamp = timestamp
        self.delta = delta
        self.isStale = isStale
    }
    
    /// Create from GlucoseReading
    public init(from reading: GlucoseReading, previousReading: GlucoseReading? = nil) {
        self.glucose = reading.glucose
        self.trend = reading.trend.arrow
        self.timestamp = reading.timestamp
        self.isStale = Date().timeIntervalSince(reading.timestamp) > 900 // 15 min
        
        if let prev = previousReading {
            self.delta = reading.glucose - prev.glucose
        } else {
            self.delta = nil
        }
    }
}

// MARK: - Watch Settings

/// Settings synchronized to Watch
public struct WatchSettings: Codable, Sendable {
    public var glucoseUnit: String
    public var highThreshold: Double
    public var lowThreshold: Double
    public var urgentHighThreshold: Double
    public var urgentLowThreshold: Double
    public var showDelta: Bool
    public var showTrend: Bool
    
    public init(
        glucoseUnit: String = "mg/dL",
        highThreshold: Double = 180,
        lowThreshold: Double = 70,
        urgentHighThreshold: Double = 250,
        urgentLowThreshold: Double = 55,
        showDelta: Bool = true,
        showTrend: Bool = true
    ) {
        self.glucoseUnit = glucoseUnit
        self.highThreshold = highThreshold
        self.lowThreshold = lowThreshold
        self.urgentHighThreshold = urgentHighThreshold
        self.urgentLowThreshold = urgentLowThreshold
        self.showDelta = showDelta
        self.showTrend = showTrend
    }
}

// MARK: - Watch Connectivity Manager

/// Manages communication between iPhone and Apple Watch
/// 
/// - Note: @MainActor ensures WCSession is always accessed on the main thread (ARCH-005)
@MainActor
public final class WatchConnectivityManager: NSObject, @unchecked Sendable {
    
    // MARK: - Singleton
    
    public static let shared = WatchConnectivityManager()
    
    // MARK: - Callbacks
    
    /// Called when glucose update received (Watch side)
    public var onGlucoseUpdate: ((WatchGlucoseUpdate) -> Void)?
    
    /// Called when settings received (Watch side)
    public var onSettingsUpdate: ((WatchSettings) -> Void)?
    
    /// Called when refresh requested (iPhone side)
    public var onRefreshRequest: (() -> Void)?
    
    /// Called when snooze requested (iPhone side)
    public var onSnoozeRequest: ((String) -> Void)?
    
    /// Called when reachability changes
    public var onReachabilityChanged: ((Bool) -> Void)?
    
    // MARK: - Properties
    
    #if canImport(WatchConnectivity)
    private var session: WCSession?
    #endif
    
    /// Whether Watch is paired and app installed
    public var isWatchAppInstalled: Bool {
        #if canImport(WatchConnectivity) && !os(watchOS)
        return session?.isWatchAppInstalled ?? false
        #else
        return false
        #endif
    }
    
    /// Whether Watch is currently reachable
    public var isReachable: Bool {
        #if canImport(WatchConnectivity)
        return session?.isReachable ?? false
        #else
        return false
        #endif
    }
    
    /// Whether session is activated
    public var isActivated: Bool {
        #if canImport(WatchConnectivity)
        return session?.activationState == .activated
        #else
        return false
        #endif
    }
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
    }
    
    // MARK: - Activation
    
    /// Activate the Watch connectivity session.
    /// Should be called on main thread.
    /// Trace: ARCH-IMPL-006
    public func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        
        // WCSession should be accessed on main thread (ARCH-IMPL-006)
        if Thread.isMainThread {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.session = WCSession.default
                self?.session?.delegate = self
                self?.session?.activate()
            }
        }
        #endif
    }
    
    // MARK: - Send Messages
    
    /// Send glucose update to Watch
    public func sendGlucoseUpdate(_ update: WatchGlucoseUpdate) {
        let message: [String: Any] = [
            "type": WatchMessageType.glucoseUpdate.rawValue,
            "data": (try? JSONEncoder().encode(update)) as Any
        ].compactMapValues { $0 }
        
        sendMessage(message)
    }
    
    /// Send glucose history to Watch
    public func sendGlucoseHistory(_ readings: [WatchGlucoseUpdate]) {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.glucoseHistory.rawValue,
            "data": data
        ]
        
        sendMessage(message)
    }
    
    /// Send settings to Watch
    public func sendSettings(_ settings: WatchSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        
        let message: [String: Any] = [
            "type": WatchMessageType.settingsSync.rawValue,
            "data": data
        ]
        
        sendMessage(message)
    }
    
    /// Request refresh from iPhone (Watch side)
    public func requestRefresh() {
        let message: [String: Any] = [
            "type": WatchMessageType.refreshRequest.rawValue
        ]
        
        sendMessage(message)
    }
    
    /// Request snooze from iPhone (Watch side)
    public func requestSnooze(alertType: String) {
        let message: [String: Any] = [
            "type": WatchMessageType.snoozeRequest.rawValue,
            "alertType": alertType
        ]
        
        sendMessage(message)
    }
    
    // MARK: - Application Context
    
    /// Update application context (survives across sessions)
    public func updateApplicationContext(_ context: [String: Any]) {
        #if canImport(WatchConnectivity)
        do {
            try session?.updateApplicationContext(context)
        } catch {
            // Silently fail
        }
        #endif
    }
    
    /// Get current application context
    public func getApplicationContext() -> [String: Any] {
        #if canImport(WatchConnectivity)
        return session?.applicationContext ?? [:]
        #else
        return [:]
        #endif
    }
    
    // MARK: - User Info Transfer
    
    /// Transfer user info (queued, guaranteed delivery)
    public func transferUserInfo(_ userInfo: [String: Any]) {
        #if canImport(WatchConnectivity)
        session?.transferUserInfo(userInfo)
        #endif
    }
    
    /// Transfer complication data (high priority)
    public func transferComplicationUserInfo(_ userInfo: [String: Any]) {
        #if canImport(WatchConnectivity) && !os(watchOS)
        session?.transferCurrentComplicationUserInfo(userInfo)
        #endif
    }
    
    // MARK: - Private
    
    private func sendMessage(_ message: [String: Any]) {
        #if canImport(WatchConnectivity)
        guard let session = session, session.activationState == .activated else { return }
        
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            // Fall back to user info transfer
            transferUserInfo(message)
        }
        #endif
    }
}

// MARK: - WCSessionDelegate

#if canImport(WatchConnectivity)
extension WatchConnectivityManager: WCSessionDelegate {
    
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Activation complete
    }
    
    #if !os(watchOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        // Session inactive
    }
    
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for new Watch
        session.activate()
    }
    #endif
    
    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        Task { @MainActor in
            self.onReachabilityChanged?(isReachable)
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            self.handleMessage(message)
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handleMessage(message)
        }
        replyHandler(["status": "received"])
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            self.handleMessage(userInfo)
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handleMessage(applicationContext)
        }
    }
    
    private func handleMessage(_ message: [String: Any]) {
        guard let typeString = message["type"] as? String,
              let type = WatchMessageType(rawValue: typeString) else {
            return
        }
        
        switch type {
        case .glucoseUpdate:
            if let data = message["data"] as? Data,
               let update = try? JSONDecoder().decode(WatchGlucoseUpdate.self, from: data) {
                DispatchQueue.main.async {
                    self.onGlucoseUpdate?(update)
                }
            }
            
        case .settingsSync:
            if let data = message["data"] as? Data,
               let settings = try? JSONDecoder().decode(WatchSettings.self, from: data) {
                DispatchQueue.main.async {
                    self.onSettingsUpdate?(settings)
                }
            }
            
        case .refreshRequest:
            DispatchQueue.main.async {
                self.onRefreshRequest?()
            }
            
        case .snoozeRequest:
            if let alertType = message["alertType"] as? String {
                DispatchQueue.main.async {
                    self.onSnoozeRequest?(alertType)
                }
            }
            
        default:
            break
        }
    }
}
#endif
