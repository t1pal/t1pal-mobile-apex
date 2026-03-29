// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmRegistry.swift
// T1Pal Mobile
//
// Plugin system for algorithm registration and selection
// Requirements: REQ-ALGO-001, REQ-ALGO-002
//
// Trace: ALG-012, PRD-009

import Foundation

// MARK: - Registry Errors

/// Errors from algorithm registry operations
public enum AlgorithmRegistryError: Error, Sendable, Equatable {
    case algorithmNotFound(name: String)
    case algorithmAlreadyRegistered(name: String)
    case noActiveAlgorithm
    case validationFailed(errors: [String])
}

// MARK: - Algorithm Registry

/// Central registry for available algorithms
/// Thread-safe singleton for algorithm management
/// Requirements: REQ-ALGO-002
public final class AlgorithmRegistry: @unchecked Sendable {
    
    /// Shared singleton instance
    public static let shared = AlgorithmRegistry()
    
    /// Lock for thread-safe access
    private let lock = NSLock()
    
    /// Registered algorithms by name
    private var algorithms: [String: any AlgorithmEngine] = [:]
    
    /// Currently active algorithm name
    private var _activeAlgorithmName: String?
    
    /// Observers for algorithm changes
    private var observers: [(String?, String?) -> Void] = []
    
    // MARK: - Initialization
    
    /// Private init for singleton
    private init() {
        // Register built-in algorithms
        registerBuiltInAlgorithms()
    }
    
    /// Create a new registry (for testing)
    public static func createForTesting() -> AlgorithmRegistry {
        return AlgorithmRegistry(forTesting: true)
    }
    
    /// Private init for testing (no built-ins)
    private init(forTesting: Bool) {
        // Don't register built-ins for testing
    }
    
    // MARK: - Registration
    
    /// Register an algorithm
    /// - Parameter algorithm: The algorithm to register
    /// - Throws: AlgorithmRegistryError.algorithmAlreadyRegistered if name exists
    public func register(_ algorithm: any AlgorithmEngine) throws {
        lock.lock()
        defer { lock.unlock() }
        
        if algorithms[algorithm.name] != nil {
            throw AlgorithmRegistryError.algorithmAlreadyRegistered(name: algorithm.name)
        }
        
        algorithms[algorithm.name] = algorithm
    }
    
    /// Register an algorithm, replacing if exists
    /// - Parameter algorithm: The algorithm to register
    public func registerOrReplace(_ algorithm: any AlgorithmEngine) {
        lock.lock()
        defer { lock.unlock() }
        
        algorithms[algorithm.name] = algorithm
    }
    
    /// Unregister an algorithm by name
    /// - Parameter name: The algorithm name to remove
    /// - Returns: The removed algorithm, if any
    @discardableResult
    public func unregister(name: String) -> (any AlgorithmEngine)? {
        lock.lock()
        defer { lock.unlock() }
        
        // Clear active if removing active algorithm
        if _activeAlgorithmName == name {
            _activeAlgorithmName = nil
        }
        
        return algorithms.removeValue(forKey: name)
    }
    
    /// Remove all registered algorithms
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        algorithms.removeAll()
        _activeAlgorithmName = nil
    }
    
    // MARK: - Query
    
    /// Get all registered algorithm names
    public var registeredNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(algorithms.keys).sorted()
    }
    
    /// Get all registered algorithms
    public var allAlgorithms: [any AlgorithmEngine] {
        lock.lock()
        defer { lock.unlock() }
        return Array(algorithms.values)
    }
    
    /// Get count of registered algorithms
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return algorithms.count
    }
    
    /// Check if an algorithm is registered
    /// - Parameter name: The algorithm name
    /// - Returns: True if registered
    public func isRegistered(name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return algorithms[name] != nil
    }
    
    /// Get an algorithm by name
    /// - Parameter name: The algorithm name
    /// - Returns: The algorithm if found
    public func algorithm(named name: String) -> (any AlgorithmEngine)? {
        lock.lock()
        defer { lock.unlock() }
        return algorithms[name]
    }
    
    /// Get algorithm by name, throwing if not found
    /// - Parameter name: The algorithm name
    /// - Returns: The algorithm
    /// - Throws: AlgorithmRegistryError.algorithmNotFound
    public func requireAlgorithm(named name: String) throws -> any AlgorithmEngine {
        guard let alg = algorithm(named: name) else {
            throw AlgorithmRegistryError.algorithmNotFound(name: name)
        }
        return alg
    }
    
    /// Find algorithms matching a capability filter
    /// - Parameter filter: Closure that returns true for matching capabilities
    /// - Returns: Array of matching algorithms
    public func algorithms(matching filter: (AlgorithmCapabilities) -> Bool) -> [any AlgorithmEngine] {
        lock.lock()
        defer { lock.unlock() }
        
        return algorithms.values.filter { filter($0.capabilities) }
    }
    
    /// Find algorithms supporting SMB
    public var algorithmsSupportingSMB: [any AlgorithmEngine] {
        algorithms(matching: { $0.supportsSMB })
    }
    
    /// Find algorithms providing predictions
    public var algorithmsProvidingPredictions: [any AlgorithmEngine] {
        algorithms(matching: { $0.providesPredictions })
    }
    
    /// Find algorithms by origin
    /// - Parameter origin: The algorithm origin to match
    /// - Returns: Array of matching algorithms
    public func algorithms(origin: AlgorithmOrigin) -> [any AlgorithmEngine] {
        algorithms(matching: { $0.origin == origin })
    }
    
    // MARK: - Active Algorithm
    
    /// The currently active algorithm name
    public var activeAlgorithmName: String? {
        lock.lock()
        defer { lock.unlock() }
        return _activeAlgorithmName
    }
    
    /// The currently active algorithm
    public var activeAlgorithm: (any AlgorithmEngine)? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let name = _activeAlgorithmName else { return nil }
        return algorithms[name]
    }
    
    /// Set the active algorithm by name
    /// - Parameter name: The algorithm name to activate
    /// - Throws: AlgorithmRegistryError.algorithmNotFound if not registered
    public func setActive(name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        guard algorithms[name] != nil else {
            throw AlgorithmRegistryError.algorithmNotFound(name: name)
        }
        
        let oldName = _activeAlgorithmName
        _activeAlgorithmName = name
        
        // Notify observers (outside lock would be better, but keeping simple)
        notifyObservers(oldName: oldName, newName: name)
    }
    
    /// Clear the active algorithm
    public func clearActive() {
        lock.lock()
        defer { lock.unlock() }
        
        let oldName = _activeAlgorithmName
        _activeAlgorithmName = nil
        notifyObservers(oldName: oldName, newName: nil)
    }
    
    /// Get the active algorithm, throwing if none set
    /// - Returns: The active algorithm
    /// - Throws: AlgorithmRegistryError.noActiveAlgorithm
    public func requireActiveAlgorithm() throws -> any AlgorithmEngine {
        guard let alg = activeAlgorithm else {
            throw AlgorithmRegistryError.noActiveAlgorithm
        }
        return alg
    }
    
    // MARK: - Validation
    
    /// Validate inputs against the active algorithm
    /// - Parameter inputs: The algorithm inputs to validate
    /// - Returns: Array of validation errors (empty if valid)
    public func validateInputs(_ inputs: AlgorithmInputs) -> [AlgorithmError] {
        guard let alg = activeAlgorithm else {
            return [.configurationError(reason: "No active algorithm")]
        }
        return alg.validate(inputs)
    }
    
    /// Execute the active algorithm
    /// - Parameter inputs: The algorithm inputs
    /// - Returns: The algorithm decision
    /// - Throws: AlgorithmRegistryError or AlgorithmError
    public func calculate(_ inputs: AlgorithmInputs) throws -> AlgorithmDecision {
        let alg = try requireActiveAlgorithm()
        
        // Validate first
        let errors = alg.validate(inputs)
        if !errors.isEmpty {
            let messages = errors.map { "\($0)" }
            throw AlgorithmRegistryError.validationFailed(errors: messages)
        }
        
        return try alg.calculate(inputs)
    }
    
    // MARK: - Observers
    
    /// Add an observer for algorithm changes
    /// - Parameter observer: Closure called with (oldName, newName)
    public func addObserver(_ observer: @escaping (String?, String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        observers.append(observer)
    }
    
    /// Remove all observers
    public func removeAllObservers() {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll()
    }
    
    private func notifyObservers(oldName: String?, newName: String?) {
        // Note: Called while lock is held - observers should be quick
        for observer in observers {
            observer(oldName, newName)
        }
    }
    
    // MARK: - Built-in Registration
    
    private func registerBuiltInAlgorithms() {
        // Register oref0 as the default
        let oref0 = Oref0Algorithm()
        algorithms[oref0.name] = oref0
        
        // Register Loop Community variant (LoopKit/LoopWorkspace)
        // This is what most users run - primary Loop implementation
        let loopCommunity = LoopAlgorithm(configuration: .community)
        algorithms[loopCommunity.name] = loopCommunity
        
        // Register Loop Tidepool variant (tidepool-org/LoopAlgorithm)
        // FDA-cleared standalone package - may differ from community
        let loopTidepool = LoopAlgorithm(configuration: .tidepool)
        algorithms[loopTidepool.name] = loopTidepool
        
        // Register simple proportional for testing
        let simple = SimpleProportionalAlgorithm()
        algorithms[simple.name] = simple
        
        // Register GlucOS algorithm (GLUCOS-INT-001)
        let glucos = GlucOSAlgorithm()
        algorithms[glucos.name] = glucos
        
        // Set oref0 as default active
        _activeAlgorithmName = oref0.name
    }
}

// MARK: - Convenience Extensions

public extension AlgorithmRegistry {
    
    /// Get a summary of all registered algorithms
    var summary: String {
        let names = registeredNames
        let active = activeAlgorithmName ?? "(none)"
        return "AlgorithmRegistry: \(names.count) algorithms, active: \(active)"
    }
    
    /// Get detailed info for all algorithms
    var detailedInfo: [(name: String, version: String, origin: AlgorithmOrigin, capabilities: AlgorithmCapabilities)] {
        lock.lock()
        defer { lock.unlock() }
        
        return algorithms.values.map { alg in
            (name: alg.name, version: alg.version, origin: alg.capabilities.origin, capabilities: alg.capabilities)
        }.sorted { $0.name < $1.name }
    }
    
    /// Get the Loop algorithm instance for state manipulation (e.g., seeding predictions)
    /// - Parameter variant: Which variant to get (default: community)
    /// - Returns: The LoopAlgorithm instance, or nil if not registered
    func loopAlgorithm(variant: LoopAlgorithmVariant = .community) -> LoopAlgorithm? {
        let name = variant == .community ? "Loop" : "Loop-Tidepool"
        lock.lock()
        defer { lock.unlock() }
        return algorithms[name] as? LoopAlgorithm
    }
}
