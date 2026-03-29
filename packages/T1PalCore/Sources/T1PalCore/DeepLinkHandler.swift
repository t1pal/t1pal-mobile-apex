// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// DeepLinkHandler.swift - URL scheme and deep link handling
// Part of T1PalCore
// Trace: DEEP-LINK-001

import Foundation

// MARK: - Deep Link Types

/// Supported deep link actions
public enum DeepLinkAction: String, CaseIterable, Sendable {
    // Navigation
    case home = "home"
    case history = "history"
    case stats = "stats"
    case settings = "settings"
    case devices = "devices"
    
    // Quick actions
    case refresh = "refresh"
    case snooze = "snooze"
    case logCarbs = "log-carbs"
    case logInsulin = "log-insulin"
    
    // Data source
    case connectNightscout = "connect-nightscout"
    case switchSource = "switch-source"
    
    // Alerts
    case viewAlert = "view-alert"
    case dismissAlert = "dismiss-alert"
    
    // Debug/Research playgrounds
    // Trace: GEN-UX-DEEP-001
    case playground = "playground"
}

/// Parsed deep link with parameters
public struct DeepLink: Sendable {
    public let action: DeepLinkAction
    public let parameters: [String: String]
    public let rawURL: URL
    
    public init(action: DeepLinkAction, parameters: [String: String] = [:], rawURL: URL) {
        self.action = action
        self.parameters = parameters
        self.rawURL = rawURL
    }
    
    /// Get parameter value
    public subscript(key: String) -> String? {
        parameters[key]
    }
    
    /// Get integer parameter
    public func intValue(for key: String) -> Int? {
        parameters[key].flatMap { Int($0) }
    }
    
    /// Get double parameter
    public func doubleValue(for key: String) -> Double? {
        parameters[key].flatMap { Double($0) }
    }
    
    /// Get boolean parameter
    public func boolValue(for key: String) -> Bool {
        guard let value = parameters[key]?.lowercased() else { return false }
        return value == "true" || value == "1" || value == "yes"
    }
}

// MARK: - Deep Link Handler

/// Handler for parsing and routing deep links
public final class DeepLinkHandler: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// URL schemes supported by the app
    public static let supportedSchemes = ["t1pal", "t1palmobile"]
    
    /// Universal link domains
    public static let universalLinkDomains = ["t1pal.org", "www.t1pal.org"]
    
    // MARK: - Singleton
    
    public static let shared = DeepLinkHandler()
    
    // MARK: - Callbacks
    
    /// Called when a deep link is received
    public var onDeepLink: ((DeepLink) -> Void)?
    
    /// Called when navigation is requested
    public var onNavigate: ((DeepLinkAction) -> Void)?
    
    /// Called for quick actions
    public var onQuickAction: ((DeepLinkAction, [String: String]) -> Void)?
    
    // MARK: - State
    
    /// Pending deep link (received before handler was ready)
    public private(set) var pendingDeepLink: DeepLink?
    
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - URL Handling
    
    /// Handle an incoming URL
    /// - Returns: true if URL was handled
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard let deepLink = parse(url) else { return false }
        
        // Notify handlers
        onDeepLink?(deepLink)
        
        // Route based on action type
        switch deepLink.action {
        case .home, .history, .stats, .settings, .devices, .playground:
            onNavigate?(deepLink.action)
            
        case .refresh, .snooze, .logCarbs, .logInsulin,
             .connectNightscout, .switchSource,
             .viewAlert, .dismissAlert:
            onQuickAction?(deepLink.action, deepLink.parameters)
        }
        
        return true
    }
    
    /// Handle URL and store as pending if not ready
    @discardableResult
    public func handleOrQueue(_ url: URL) -> Bool {
        guard let deepLink = parse(url) else { return false }
        
        if onDeepLink != nil || onNavigate != nil || onQuickAction != nil {
            return handle(url)
        } else {
            lock.withLock {
                pendingDeepLink = deepLink
            }
            return true
        }
    }
    
    /// Process any pending deep link
    public func processPending() {
        var pending: DeepLink?
        lock.withLock {
            pending = pendingDeepLink
            pendingDeepLink = nil
        }
        
        if let link = pending {
            _ = handle(link.rawURL)
        }
    }
    
    /// Clear pending deep link
    public func clearPending() {
        lock.withLock {
            pendingDeepLink = nil
        }
    }
    
    // MARK: - URL Parsing
    
    /// Parse URL into DeepLink
    public func parse(_ url: URL) -> DeepLink? {
        // Check scheme
        if let scheme = url.scheme?.lowercased(),
           Self.supportedSchemes.contains(scheme) {
            return parseCustomScheme(url)
        }
        
        // Check universal link
        if let host = url.host?.lowercased(),
           Self.universalLinkDomains.contains(host) {
            return parseUniversalLink(url)
        }
        
        return nil
    }
    
    private func parseCustomScheme(_ url: URL) -> DeepLink? {
        // Format: t1pal://action?param1=value1&param2=value2
        guard let host = url.host,
              let action = DeepLinkAction(rawValue: host.lowercased()) else {
            return nil
        }
        
        let parameters = parseQueryParameters(url)
        return DeepLink(action: action, parameters: parameters, rawURL: url)
    }
    
    private func parseUniversalLink(_ url: URL) -> DeepLink? {
        // Format: https://t1pal.org/app/action?params
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard pathComponents.count >= 2,
              pathComponents[0] == "app",
              let action = DeepLinkAction(rawValue: pathComponents[1].lowercased()) else {
            return nil
        }
        
        let parameters = parseQueryParameters(url)
        return DeepLink(action: action, parameters: parameters, rawURL: url)
    }
    
    private func parseQueryParameters(_ url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return [:]
        }
        
        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }
        return params
    }
    
    // MARK: - URL Generation
    
    /// Create deep link URL for action
    public func url(for action: DeepLinkAction, parameters: [String: String] = [:]) -> URL? {
        var components = URLComponents()
        components.scheme = Self.supportedSchemes.first
        components.host = action.rawValue
        
        if !parameters.isEmpty {
            components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        return components.url
    }
    
    /// Create universal link URL for action
    public func universalURL(for action: DeepLinkAction, parameters: [String: String] = [:]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.universalLinkDomains.first
        components.path = "/app/\(action.rawValue)"
        
        if !parameters.isEmpty {
            components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        
        return components.url
    }
}

// MARK: - Quick Actions (3D Touch / Home Screen)

/// Quick action identifiers
public enum QuickActionType: String, Sendable {
    case refresh = "com.t1pal.quickaction.refresh"
    case logCarbs = "com.t1pal.quickaction.logcarbs"
    case viewHistory = "com.t1pal.quickaction.history"
    case snoozeAlerts = "com.t1pal.quickaction.snooze"
    
    /// Convert to DeepLinkAction
    public var deepLinkAction: DeepLinkAction {
        switch self {
        case .refresh: return .refresh
        case .logCarbs: return .logCarbs
        case .viewHistory: return .history
        case .snoozeAlerts: return .snooze
        }
    }
}

// MARK: - Spotlight Integration

/// Spotlight searchable item types
public enum SpotlightItemType: String, Sendable {
    case glucoseReading = "com.t1pal.spotlight.glucose"
    case carbEntry = "com.t1pal.spotlight.carb"
    case insulinDose = "com.t1pal.spotlight.insulin"
    case report = "com.t1pal.spotlight.report"
    
    /// Domain identifier for Spotlight
    public static let domainIdentifier = "com.t1pal.spotlight"
}

// MARK: - URL Examples

/*
 Custom Scheme Examples:
 - t1pal://home
 - t1pal://history
 - t1pal://settings
 - t1pal://refresh
 - t1pal://snooze?duration=30
 - t1pal://log-carbs?amount=45
 - t1pal://connect-nightscout?url=https://example.com
 
 Universal Link Examples:
 - https://t1pal.org/app/home
 - https://t1pal.org/app/history?days=7
 - https://t1pal.org/app/settings
 */
