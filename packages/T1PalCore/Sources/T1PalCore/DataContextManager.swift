// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// DataContextManager.swift - Observable singleton for data context management
// Part of T1PalCore
//
// Central state manager for DataContext with persistence.
// See PRD-021 REQ-DCA-001.2 for requirements.

import Foundation

// @Observable requires Darwin platforms (iOS 17+, macOS 14+)
#if canImport(Observation)
import Observation

// MARK: - DataContextManager

/// Observable singleton that manages the current data context
///
/// This is the central state manager for data configuration.
/// All data-consuming views should observe this manager for context changes.
///
/// Example usage:
/// ```swift
/// struct MyView: View {
///     @State private var manager = DataContextManager.shared
///     
///     var body: some View {
///         Text(manager.current.indicator)
///     }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@Observable
public final class DataContextManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    /// Shared instance for app-wide data context management
    public static let shared = DataContextManager()
    
    /// Preview instance with demo context (does not persist)
    public static let preview = DataContextManager(
        initialContext: .preview,
        persistenceEnabled: false
    )
    
    // MARK: - Observable State
    
    /// The current active data context
    public private(set) var current: DataContext
    
    /// History of recent contexts (for quick switching)
    public private(set) var recentContexts: [DataContext] = []
    
    /// Whether a context switch is in progress
    public private(set) var isSwitching: Bool = false
    
    /// Error from last context switch attempt
    public private(set) var lastError: DataContextError?
    
    // MARK: - Configuration
    
    /// Maximum number of recent contexts to retain
    public var maxRecentContexts: Int = 5
    
    /// Whether persistence is enabled
    private let persistenceEnabled: Bool
    
    /// UserDefaults for persistence
    private let defaults: UserDefaults
    
    // MARK: - Initialization
    
    /// Initialize with optional custom configuration
    public init(
        initialContext: DataContext = .default,
        persistenceEnabled: Bool = true,
        userDefaults: UserDefaults = .standard
    ) {
        self.persistenceEnabled = persistenceEnabled
        self.defaults = userDefaults
        
        // Load persisted context or use initial
        if persistenceEnabled, let loaded = Self.loadContext(from: userDefaults) {
            self.current = loaded
        } else {
            self.current = initialContext
        }
        
        // Load recent contexts
        if persistenceEnabled {
            self.recentContexts = Self.loadRecentContexts(from: userDefaults)
        }
    }
    
    // MARK: - Context Management
    
    /// Set the current data context
    /// - Parameter context: The new context to activate
    public func setContext(_ context: DataContext) {
        let previous = current
        current = context
        lastError = nil
        
        // Add previous to recents if different
        if previous.sourceType != context.sourceType || 
           previous.nightscoutURL != context.nightscoutURL {
            addToRecents(previous)
        }
        
        // Persist if enabled
        if persistenceEnabled {
            persist()
        }
    }
    
    /// Set context with async validation
    /// - Parameter context: The context to validate and activate
    /// - Returns: Whether the context was successfully activated
    @discardableResult
    public func setContextAsync(_ context: DataContext) async -> Bool {
        isSwitching = true
        defer { isSwitching = false }
        
        // Validate context if it requires network
        if context.sourceType == .liveNS, let url = context.nightscoutURL {
            do {
                try await validateNightscoutURL(url)
            } catch {
                lastError = .validationFailed(error.localizedDescription)
                return false
            }
        }
        
        setContext(context)
        return true
    }
    
    /// Switch to demo mode with a specific pattern
    public func switchToDemo(pattern: String = "flat") {
        setContext(.demo(pattern: pattern))
    }
    
    /// Switch to live Nightscout
    public func switchToNightscout(url: URL, token: String? = nil, label: String? = nil) {
        setContext(.liveNS(url: url, token: token, label: label))
    }
    
    /// Switch to a fixture for testing
    public func switchToFixture(name: String) {
        setContext(.fixture(name: name))
    }
    
    /// BLE-CTX-030: Switch to a specific source type, preserving other settings
    public func setSourceType(_ sourceType: DataSourceType) {
        let c = current
        #if DEBUG
        let updated = DataContext(
            sourceType: sourceType,
            nightscoutURL: c.nightscoutURL,
            nightscoutToken: c.nightscoutToken,
            simulationPattern: c.simulationPattern,
            fixtureName: c.fixtureName,
            isPreview: c.isPreview,
            label: c.label,
            configuredAt: Date(),
            faultConfig: c.faultConfig,
            bleConfig: c.bleConfig,
            pumpConfig: c.pumpConfig
        )
        #else
        let updated = DataContext(
            sourceType: sourceType,
            nightscoutURL: c.nightscoutURL,
            nightscoutToken: c.nightscoutToken,
            simulationPattern: c.simulationPattern,
            fixtureName: c.fixtureName,
            isPreview: c.isPreview,
            label: c.label,
            configuredAt: Date(),
            bleConfig: c.bleConfig,
            pumpConfig: c.pumpConfig
        )
        #endif
        setContext(updated)
    }
    
    /// DATA-PIPE-007: Set BLE configuration for CGM connection
    /// - Parameter bleConfig: The BLE device configuration including connection mode
    public func setBLEConfig(_ bleConfig: BLEDeviceConfig?) {
        let c = current
        #if DEBUG
        let updated = DataContext(
            sourceType: c.sourceType,
            nightscoutURL: c.nightscoutURL,
            nightscoutToken: c.nightscoutToken,
            simulationPattern: c.simulationPattern,
            fixtureName: c.fixtureName,
            isPreview: c.isPreview,
            label: c.label,
            configuredAt: Date(),
            faultConfig: c.faultConfig,
            bleConfig: bleConfig,
            pumpConfig: c.pumpConfig
        )
        #else
        let updated = DataContext(
            sourceType: c.sourceType,
            nightscoutURL: c.nightscoutURL,
            nightscoutToken: c.nightscoutToken,
            simulationPattern: c.simulationPattern,
            fixtureName: c.fixtureName,
            isPreview: c.isPreview,
            label: c.label,
            configuredAt: Date(),
            bleConfig: bleConfig,
            pumpConfig: c.pumpConfig
        )
        #endif
        setContext(updated)
    }
    
    /// Clear error state
    public func clearError() {
        lastError = nil
    }
    
    /// Reset to default context
    public func reset() {
        current = .default
        recentContexts = []
        lastError = nil
        
        if persistenceEnabled {
            persist()
        }
    }
    
    // MARK: - Recent Contexts
    
    /// Add a context to the recents list
    private func addToRecents(_ context: DataContext) {
        // Remove if already in recents
        recentContexts.removeAll { $0 == context }
        
        // Add to front
        recentContexts.insert(context, at: 0)
        
        // Trim to max
        if recentContexts.count > maxRecentContexts {
            recentContexts = Array(recentContexts.prefix(maxRecentContexts))
        }
    }
    
    /// Select a context from recents
    public func selectRecent(at index: Int) {
        guard index >= 0 && index < recentContexts.count else { return }
        let context = recentContexts[index]
        setContext(context)
    }
    
    // MARK: - Persistence
    
    private static let contextKey = "com.t1pal.dataContext.current"
    private static let recentsKey = "com.t1pal.dataContext.recents"
    
    /// Persist current state to UserDefaults
    private func persist() {
        let encoder = JSONEncoder()
        
        // Save current context
        if let data = try? encoder.encode(current) {
            defaults.set(data, forKey: Self.contextKey)
        }
        
        // Save recents
        if let data = try? encoder.encode(recentContexts) {
            defaults.set(data, forKey: Self.recentsKey)
        }
    }
    
    /// Load context from UserDefaults
    private static func loadContext(from defaults: UserDefaults) -> DataContext? {
        guard let data = defaults.data(forKey: contextKey) else { return nil }
        return try? JSONDecoder().decode(DataContext.self, from: data)
    }
    
    /// Load recent contexts from UserDefaults
    private static func loadRecentContexts(from defaults: UserDefaults) -> [DataContext] {
        guard let data = defaults.data(forKey: recentsKey) else { return [] }
        return (try? JSONDecoder().decode([DataContext].self, from: data)) ?? []
    }
    
    // MARK: - Validation
    
    /// Validate a Nightscout URL is reachable
    private func validateNightscoutURL(_ url: URL) async throws {
        // Simple status check
        let statusURL = url.appendingPathComponent("api/v1/status.json")
        #if os(Linux)
        // Linux: Skip async validation, will fail at runtime if unreachable
        _ = statusURL
        #else
        let (_, response) = try await URLSession.shared.data(from: statusURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw DataContextError.unreachable
        }
        #endif
    }
}

// MARK: - Convenience Extensions

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DataContextManager {
    
    /// Whether the current context is demo mode
    public var isDemo: Bool {
        current.sourceType == .demo
    }
    
    /// Whether the current context is live data
    public var isLive: Bool {
        current.isLiveData
    }
    
    /// Whether the current context is live Nightscout
    public var isLiveNightscout: Bool {
        current.sourceType == .liveNS
    }
    
    /// The current Nightscout URL (if configured)
    public var nightscoutURL: URL? {
        current.nightscoutURL
    }
    
    /// Whether the current context is a preview
    public var isPreview: Bool {
        current.isPreview
    }
    
    /// Current context indicator string
    public var indicator: String {
        current.indicator
    }
    
    /// Current source type
    public var sourceType: DataSourceType {
        current.sourceType
    }
}

// MARK: - Fault Injection (OBS-010)

#if DEBUG
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DataContextManager {
    
    /// Apply fault configuration to the current context
    /// - Parameter faults: The fault configuration to apply
    public func applyFaults(_ faults: FaultConfiguration) {
        let newContext = current.withFaults(faults)
        setContext(newContext)
    }
    
    /// Apply a fault preset to the current context
    /// - Parameter preset: The preset to apply
    public func applyPreset(_ preset: FaultPreset) {
        applyFaults(preset.configuration)
    }
    
    /// Clear all faults from the current context
    public func clearFaults() {
        let newContext = current.withFaults(FaultConfiguration(
            dataFaults: [],
            networkFaults: [],
            isEnabled: false
        ))
        setContext(newContext)
    }
}
#endif

// MARK: - Fault Status (Available in all builds)

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DataContextManager {
    /// Whether the current context has active faults
    public var hasFaults: Bool {
        current.hasFaults
    }
    
    /// Active data faults in the current context
    public var activeDataFaults: [DataFaultType] {
        current.activeDataFaults
    }
    
    /// Active network faults in the current context
    public var activeNetworkFaults: [NetworkFaultType] {
        current.activeNetworkFaults
    }
    
    /// Current fault configuration (nil if no faults, always nil in Release)
    public var faultConfig: FaultConfiguration? {
        #if DEBUG
        return current.faultConfig
        #else
        return nil
        #endif
    }
}

#endif // canImport(Observation)

// MARK: - DataContextError

/// Errors that can occur during context management
public enum DataContextError: Error, LocalizedError, Sendable {
    case validationFailed(String)
    case unreachable
    case invalidConfiguration
    
    public var errorDescription: String? {
        switch self {
        case .validationFailed(let reason):
            return "Validation failed: \(reason)"
        case .unreachable:
            return "Unable to reach the server"
        case .invalidConfiguration:
            return "Invalid configuration"
        }
    }
}

// MARK: - DataContextConsumer Protocol

/// Protocol for views and objects that consume the data context
///
/// Conforming types automatically integrate with DataContextManager
/// and respond to context changes (demo/live switching, config updates).
///
/// Example usage:
/// ```swift
/// struct MyPlaygroundView: View, DataContextConsumer {
///     var contextManager: DataContextManager { .shared }
///     
///     var body: some View {
///         Text(dataContext.indicator)
///         if isDemo {
///             Text("Demo Mode")
///         }
///     }
/// }
/// ```
///
/// Trace: PRD-021 REQ-DCA-002.4
@MainActor
public protocol DataContextConsumer {
    /// The data context manager this consumer observes
    #if canImport(Observation)
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
    var contextManager: DataContextManager { get }
    #endif
}

#if canImport(Observation)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@MainActor
extension DataContextConsumer {
    /// The current data context
    public var dataContext: DataContext {
        contextManager.current
    }
    
    /// Whether currently in demo mode
    public var isDemo: Bool {
        contextManager.isDemo
    }
    
    /// Whether currently connected to live Nightscout
    public var isLiveNightscout: Bool {
        contextManager.isLiveNightscout
    }
    
    /// The current Nightscout URL (if configured)
    public var nightscoutURL: URL? {
        contextManager.nightscoutURL
    }
    
    /// The context indicator string for display
    public var contextIndicator: String {
        dataContext.indicator
    }
    
    /// Request a context switch to demo mode
    public func switchToDemo() {
        contextManager.setContext(.demo(pattern: "flat"))
    }
    
    /// Request a context switch with Nightscout URL
    public func switchToNightscout(url: URL, token: String? = nil) {
        contextManager.setContext(.liveNS(url: url, token: token))
    }
}
#endif
