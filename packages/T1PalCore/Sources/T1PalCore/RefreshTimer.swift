// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// RefreshTimer.swift - Auto-refresh timer for glucose data
// Part of T1PalCore
// Trace: REFRESH-001

import Foundation
#if canImport(Combine)
import Combine
#endif

// MARK: - Refresh Timer

#if canImport(Combine)
/// Configurable timer for auto-refreshing glucose data
@MainActor
public final class RefreshTimer: ObservableObject {
    
    // MARK: - Configuration
    
    /// Refresh interval options
    public enum Interval: Int, CaseIterable, Sendable {
        case thirtySeconds = 30
        case oneMinute = 60
        case twoMinutes = 120
        case fiveMinutes = 300
        
        public var seconds: TimeInterval {
            TimeInterval(rawValue)
        }
        
        public var displayName: String {
            switch self {
            case .thirtySeconds: return "30 seconds"
            case .oneMinute: return "1 minute"
            case .twoMinutes: return "2 minutes"
            case .fiveMinutes: return "5 minutes"
            }
        }
    }
    
    // MARK: - Published Properties
    
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastRefresh: Date?
    @Published public private(set) var nextRefresh: Date?
    @Published public var interval: Interval = .oneMinute {
        didSet {
            if isRunning {
                restart()
            }
        }
    }
    
    // MARK: - Private Properties
    
    private var timer: Timer?
    private var refreshAction: (() async -> Void)?
    private var backgroundTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(interval: Interval = .oneMinute) {
        self.interval = interval
    }
    
    deinit {
        timer?.invalidate()
        backgroundTask?.cancel()
    }
    
    // MARK: - Singleton
    
    public static let shared = RefreshTimer()
    
    // MARK: - Timer Control
    
    /// Start the refresh timer with an async action
    public func start(action: @escaping () async -> Void) {
        refreshAction = action
        startTimer()
    }
    
    /// Stop the refresh timer
    public func stop() {
        timer?.invalidate()
        timer = nil
        backgroundTask?.cancel()
        backgroundTask = nil
        isRunning = false
        nextRefresh = nil
    }
    
    /// Restart the timer with current interval
    public func restart() {
        stop()
        if refreshAction != nil {
            startTimer()
        }
    }
    
    /// Trigger an immediate refresh
    public func refreshNow() {
        guard let action = refreshAction else { return }
        
        backgroundTask?.cancel()
        backgroundTask = Task {
            await action()
            lastRefresh = Date()
            updateNextRefresh()
        }
    }
    
    /// Pause the timer (keeps action, stops firing)
    public func pause() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        nextRefresh = nil
    }
    
    /// Resume a paused timer
    public func resume() {
        if refreshAction != nil && !isRunning {
            startTimer()
        }
    }
    
    // MARK: - Time Calculations
    
    /// Time until next refresh
    public var timeUntilNextRefresh: TimeInterval? {
        guard let next = nextRefresh else { return nil }
        return max(0, next.timeIntervalSinceNow)
    }
    
    /// Formatted time until next refresh
    public var timeUntilNextRefreshFormatted: String {
        guard let remaining = timeUntilNextRefresh else { return "--" }
        let seconds = Int(remaining)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            return "\(seconds / 60)m \(seconds % 60)s"
        }
    }
    
    /// Time since last refresh
    public var timeSinceLastRefresh: TimeInterval? {
        guard let last = lastRefresh else { return nil }
        return Date().timeIntervalSince(last)
    }
    
    // MARK: - Private Methods
    
    private func startTimer() {
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(
            withTimeInterval: interval.seconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.timerFired()
            }
        }
        
        isRunning = true
        updateNextRefresh()
        
        // Immediate first refresh
        refreshNow()
    }
    
    private func timerFired() {
        guard let action = refreshAction else { return }
        
        backgroundTask?.cancel()
        backgroundTask = Task {
            await action()
            await MainActor.run {
                lastRefresh = Date()
                updateNextRefresh()
            }
        }
    }
    
    private func updateNextRefresh() {
        nextRefresh = Date().addingTimeInterval(interval.seconds)
    }
}
#endif

// MARK: - Refresh State

/// Observable state for refresh status display
public struct RefreshState: Sendable {
    public let isRefreshing: Bool
    public let lastRefresh: Date?
    public let error: String?
    
    public init(isRefreshing: Bool = false, lastRefresh: Date? = nil, error: String? = nil) {
        self.isRefreshing = isRefreshing
        self.lastRefresh = lastRefresh
        self.error = error
    }
    
    public static let idle = RefreshState()
    
    public var lastRefreshFormatted: String {
        guard let last = lastRefresh else { return "Never" }
        let elapsed = Date().timeIntervalSince(last)
        
        if elapsed < 60 {
            return "Just now"
        } else if elapsed < 3600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes) min ago"
        } else {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: last)
        }
    }
}

// MARK: - Background Refresh Support

/// Protocol for background refresh capability
public protocol BackgroundRefreshable: AnyObject {
    /// Minimum interval between background refreshes
    var minimumBackgroundFetchInterval: TimeInterval { get }
    
    /// Perform background refresh
    func performBackgroundRefresh() async -> Bool
}

extension BackgroundRefreshable {
    public var minimumBackgroundFetchInterval: TimeInterval { 300 } // 5 minutes
}

// MARK: - Refresh Timer Delegate

#if canImport(Combine)
/// Delegate for refresh timer events
public protocol RefreshTimerDelegate: AnyObject {
    func refreshTimerWillRefresh(_ timer: RefreshTimer)
    func refreshTimerDidRefresh(_ timer: RefreshTimer, success: Bool)
    func refreshTimerDidFail(_ timer: RefreshTimer, error: Error)
}
#endif

// MARK: - App Lifecycle Integration

#if canImport(UIKit) && canImport(Combine)
import UIKit

extension RefreshTimer {
    /// Configure timer to pause when app backgrounds
    public func configureForAppLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resume()
                self?.refreshNow()
            }
        }
    }
}
#endif
