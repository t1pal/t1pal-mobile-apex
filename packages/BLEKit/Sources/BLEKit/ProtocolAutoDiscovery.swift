// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ProtocolAutoDiscovery.swift
// BLEKit
//
// Automatic protocol variant discovery through systematic testing.
// Generates combinations, executes attempts, logs results, persists working configs.
// Trace: PROTO-AUTO-001a-d, PROTO-AUTO-002, PROTO-AUTO-003

import Foundation

// MARK: - Attempt Result

/// Result of a single protocol variant attempt
public struct ProtocolAttemptResult: Sendable, Codable, Equatable {
    /// Unique attempt identifier
    public let attemptId: UUID
    
    /// Timestamp of attempt
    public let timestamp: Date
    
    /// Protocol configuration used
    public let configuration: CGMProtocolConfiguration
    
    /// Whether the attempt succeeded
    public let success: Bool
    
    /// Error message if failed
    public let errorMessage: String?
    
    /// Error code if available
    public let errorCode: Int?
    
    /// Duration of attempt in seconds
    public let durationSeconds: Double
    
    /// Stage reached before failure (if any)
    public let stageReached: ProtocolStage
    
    /// Additional diagnostic data
    public let diagnosticData: [String: String]
    
    public init(
        attemptId: UUID = UUID(),
        timestamp: Date = Date(),
        configuration: CGMProtocolConfiguration,
        success: Bool,
        errorMessage: String? = nil,
        errorCode: Int? = nil,
        durationSeconds: Double,
        stageReached: ProtocolStage,
        diagnosticData: [String: String] = [:]
    ) {
        self.attemptId = attemptId
        self.timestamp = timestamp
        self.configuration = configuration
        self.success = success
        self.errorMessage = errorMessage
        self.errorCode = errorCode
        self.durationSeconds = durationSeconds
        self.stageReached = stageReached
        self.diagnosticData = diagnosticData
    }
}

/// Protocol execution stages
public enum ProtocolStage: String, Sendable, Codable, CaseIterable {
    case notStarted = "not_started"
    case connecting = "connecting"
    case connected = "connected"
    case discoveringServices = "discovering_services"
    case discoveringCharacteristics = "discovering_characteristics"
    case authenticating = "authenticating"
    case authenticated = "authenticated"
    case bonding = "bonding"
    case bonded = "bonded"
    case subscribing = "subscribing"
    case subscribed = "subscribed"
    case receivingData = "receiving_data"
    case complete = "complete"
    case failed = "failed"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .notStarted: return "Not started"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .discoveringServices: return "Discovering services"
        case .discoveringCharacteristics: return "Discovering characteristics"
        case .authenticating: return "Authenticating"
        case .authenticated: return "Authenticated"
        case .bonding: return "Bonding"
        case .bonded: return "Bonded"
        case .subscribing: return "Subscribing to notifications"
        case .subscribed: return "Subscribed"
        case .receivingData: return "Receiving data"
        case .complete: return "Complete"
        case .failed: return "Failed"
        }
    }
    
    /// Numeric progress value (0-100)
    public var progressPercent: Int {
        switch self {
        case .notStarted: return 0
        case .connecting: return 10
        case .connected: return 20
        case .discoveringServices: return 30
        case .discoveringCharacteristics: return 40
        case .authenticating: return 50
        case .authenticated: return 60
        case .bonding: return 70
        case .bonded: return 80
        case .subscribing: return 85
        case .subscribed: return 90
        case .receivingData: return 95
        case .complete: return 100
        case .failed: return 0
        }
    }
}

// MARK: - Variant Combination Generator (PROTO-AUTO-001a)

/// Generates all possible combinations of protocol variants for a device type
public struct VariantCombinationGenerator: Sendable {
    
    /// Device type to generate combinations for
    public let deviceType: String
    
    public init(deviceType: String) {
        self.deviceType = deviceType
    }
    
    /// Generate all G6 protocol configurations
    public func generateG6Configurations() -> [CGMProtocolConfiguration] {
        var configurations: [CGMProtocolConfiguration] = []
        
        for keyDerivation in G6KeyDerivationVariant.allCases {
            for tokenHandling in G6TokenHashVariant.allCases {
                for authOpcode in G6AuthOpcodeVariant.allCases {
                    var config = CGMProtocolConfiguration(
                        name: "G6-\(keyDerivation.rawValue)-\(tokenHandling.rawValue)-\(authOpcode.rawValue)",
                        deviceType: "DexcomG6",
                        timing: .g6Default
                    )
                    config.g6KeyDerivation = keyDerivation
                    config.g6TokenHash = tokenHandling
                    config.g6AuthOpcode = authOpcode
                    configurations.append(config)
                }
            }
        }
        
        return configurations
    }
    
    /// Generate all G7 protocol configurations
    public func generateG7Configurations() -> [CGMProtocolConfiguration] {
        var configurations: [CGMProtocolConfiguration] = []
        
        for password in G7PasswordDerivationVariant.allCases {
            for ec in G7ECParameterVariant.allCases {
                for bonding in G7BondingOrderVariant.allCases {
                    for sessionKey in G7SessionKeyDerivationVariant.allCases {
                        var config = CGMProtocolConfiguration(
                            name: "G7-\(password.rawValue)-\(bonding.rawValue)",
                            deviceType: "DexcomG7",
                            timing: .g7Default
                        )
                        config.g7PasswordDerivation = password
                        config.g7ECParameter = ec
                        config.g7BondingOrder = bonding
                        config.g7SessionKeyDerivation = sessionKey
                        configurations.append(config)
                    }
                }
            }
        }
        
        return configurations
    }
    
    /// Generate all Libre 2 protocol configurations
    public func generateLibre2Configurations() -> [CGMProtocolConfiguration] {
        var configurations: [CGMProtocolConfiguration] = []
        
        for crypto in Libre2CryptoConstantVariant.allCases {
            var config = CGMProtocolConfiguration(
                name: "Libre2-\(crypto.rawValue)",
                deviceType: "Libre2",
                timing: .libre2Default
            )
            config.libre2CryptoConstant = crypto
            configurations.append(config)
        }
        
        return configurations
    }
    
    /// Generate configurations for the current device type
    public func generateAllConfigurations() -> [CGMProtocolConfiguration] {
        switch deviceType.lowercased() {
        case "dexcomg6", "g6":
            return generateG6Configurations()
        case "dexcomg7", "g7":
            return generateG7Configurations()
        case "libre2":
            return generateLibre2Configurations()
        default:
            return []
        }
    }
    
    /// Get total combination count for device type
    public var totalCombinations: Int {
        switch deviceType.lowercased() {
        case "dexcomg6", "g6":
            return G6KeyDerivationVariant.allCases.count *
                   G6TokenHashVariant.allCases.count *
                   G6AuthOpcodeVariant.allCases.count
        case "dexcomg7", "g7":
            return G7PasswordDerivationVariant.allCases.count *
                   G7ECParameterVariant.allCases.count *
                   G7BondingOrderVariant.allCases.count *
                   G7SessionKeyDerivationVariant.allCases.count
        case "libre2":
            return Libre2CryptoConstantVariant.allCases.count
        default:
            return 0
        }
    }
}

// MARK: - Attempt History Logger (PROTO-AUTO-001d)

/// Logs and persists protocol attempt history
public actor AttemptHistoryLogger {
    
    /// All recorded attempts
    public private(set) var attempts: [ProtocolAttemptResult] = []
    
    /// Maximum attempts to keep in memory
    public let maxAttempts: Int
    
    /// Device identifier for this logger
    public let deviceIdentifier: String
    
    public init(deviceIdentifier: String, maxAttempts: Int = 1000) {
        self.deviceIdentifier = deviceIdentifier
        self.maxAttempts = maxAttempts
    }
    
    /// Log an attempt result
    public func log(_ result: ProtocolAttemptResult) {
        attempts.append(result)
        
        // Trim if over limit
        if attempts.count > maxAttempts {
            attempts.removeFirst(attempts.count - maxAttempts)
        }
    }
    
    /// Get all successful attempts
    public var successfulAttempts: [ProtocolAttemptResult] {
        attempts.filter { $0.success }
    }
    
    /// Get all failed attempts
    public var failedAttempts: [ProtocolAttemptResult] {
        attempts.filter { !$0.success }
    }
    
    /// Get the most recent successful configuration
    public var lastSuccessfulConfiguration: CGMProtocolConfiguration? {
        successfulAttempts.last?.configuration
    }
    
    /// Get attempts grouped by stage reached
    public var attemptsByStage: [ProtocolStage: [ProtocolAttemptResult]] {
        Dictionary(grouping: attempts) { $0.stageReached }
    }
    
    /// Get summary statistics
    public var statistics: AttemptStatistics {
        let total = attempts.count
        let successful = successfulAttempts.count
        let failed = failedAttempts.count
        let avgDuration = attempts.isEmpty ? 0 : attempts.map(\.durationSeconds).reduce(0, +) / Double(total)
        
        return AttemptStatistics(
            totalAttempts: total,
            successfulAttempts: successful,
            failedAttempts: failed,
            successRate: total > 0 ? Double(successful) / Double(total) : 0,
            averageDurationSeconds: avgDuration
        )
    }
    
    /// Clear all attempts
    public func clear() {
        attempts.removeAll()
    }
    
    /// Export attempts as JSON
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(attempts)
    }
}

/// Attempt statistics summary
public struct AttemptStatistics: Sendable, Codable {
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let failedAttempts: Int
    public let successRate: Double
    public let averageDurationSeconds: Double
}

// MARK: - Sequential Attempt Executor (PROTO-AUTO-001b, 001c)

/// Executes protocol variants sequentially with success detection
public actor SequentialAttemptExecutor {
    
    /// Configurations to attempt
    private var configurations: [CGMProtocolConfiguration]
    
    /// Current attempt index
    public private(set) var currentIndex: Int = 0
    
    /// Attempt history logger
    public let logger: AttemptHistoryLogger
    
    /// Whether a successful configuration was found
    public private(set) var foundWorkingConfig: Bool = false
    
    /// The working configuration (if found)
    public private(set) var workingConfiguration: CGMProtocolConfiguration?
    
    /// Callback for attempt progress
    public var onAttemptStarted: (@Sendable (Int, CGMProtocolConfiguration) -> Void)?
    public var onAttemptCompleted: (@Sendable (ProtocolAttemptResult) -> Void)?
    public var onDiscoveryComplete: (@Sendable (CGMProtocolConfiguration?) -> Void)?
    
    /// Whether to stop on first success
    public let stopOnSuccess: Bool
    
    public init(
        configurations: [CGMProtocolConfiguration],
        logger: AttemptHistoryLogger,
        stopOnSuccess: Bool = true
    ) {
        self.configurations = configurations
        self.logger = logger
        self.stopOnSuccess = stopOnSuccess
    }
    
    /// Create from a generator
    public init(
        generator: VariantCombinationGenerator,
        deviceIdentifier: String,
        stopOnSuccess: Bool = true
    ) {
        self.configurations = generator.generateAllConfigurations()
        self.logger = AttemptHistoryLogger(deviceIdentifier: deviceIdentifier)
        self.stopOnSuccess = stopOnSuccess
    }
    
    /// Get total configurations to attempt
    public var totalConfigurations: Int {
        configurations.count
    }
    
    /// Get remaining configurations
    public var remainingConfigurations: Int {
        max(0, configurations.count - currentIndex)
    }
    
    /// Get progress percentage
    public var progressPercent: Double {
        guard !configurations.isEmpty else { return 0 }
        return Double(currentIndex) / Double(configurations.count) * 100
    }
    
    /// Record an attempt result
    public func recordAttempt(
        success: Bool,
        errorMessage: String? = nil,
        errorCode: Int? = nil,
        durationSeconds: Double,
        stageReached: ProtocolStage,
        diagnosticData: [String: String] = [:]
    ) async {
        guard currentIndex < configurations.count else { return }
        
        let config = configurations[currentIndex]
        let result = ProtocolAttemptResult(
            configuration: config,
            success: success,
            errorMessage: errorMessage,
            errorCode: errorCode,
            durationSeconds: durationSeconds,
            stageReached: stageReached,
            diagnosticData: diagnosticData
        )
        
        await logger.log(result)
        onAttemptCompleted?(result)
        
        // Success detection and early exit (PROTO-AUTO-001c)
        if success && stopOnSuccess {
            foundWorkingConfig = true
            workingConfiguration = config
            onDiscoveryComplete?(config)
        }
        
        currentIndex += 1
        
        // Check if we've exhausted all options
        if currentIndex >= configurations.count && !foundWorkingConfig {
            onDiscoveryComplete?(nil)
        }
    }
    
    /// Get the next configuration to attempt
    public func nextConfiguration() -> CGMProtocolConfiguration? {
        guard !foundWorkingConfig || !stopOnSuccess else { return nil }
        guard currentIndex < configurations.count else { return nil }
        
        let config = configurations[currentIndex]
        onAttemptStarted?(currentIndex, config)
        return config
    }
    
    /// Skip to a specific configuration index
    public func skipTo(index: Int) {
        guard index >= 0 && index < configurations.count else { return }
        currentIndex = index
    }
    
    /// Reset the executor
    public func reset() {
        currentIndex = 0
        foundWorkingConfig = false
        workingConfiguration = nil
    }
    
    /// Prioritize configurations based on source reference
    /// (Puts configurations matching known-working sources first)
    public func prioritize(preferredSources: [String]) {
        configurations.sort { config1, config2 in
            let source1Priority = preferredSources.firstIndex { source in
                config1.name.lowercased().contains(source.lowercased())
            } ?? Int.max
            let source2Priority = preferredSources.firstIndex { source in
                config2.name.lowercased().contains(source.lowercased())
            } ?? Int.max
            return source1Priority < source2Priority
        }
    }
}

// MARK: - Working Config Persistence (PROTO-AUTO-002)

/// Persists working protocol configurations per device
public actor WorkingConfigStore {
    
    /// Storage key prefix
    private let keyPrefix = "protocol.working_config."
    
    /// In-memory cache of working configs
    private var cache: [String: CGMProtocolConfiguration] = [:]
    
    /// UserDefaults for persistence (could be replaced with file storage)
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    /// Save a working configuration for a device
    public func save(configuration: CGMProtocolConfiguration, forDevice deviceId: String) throws {
        let key = keyPrefix + deviceId
        let encoder = JSONEncoder()
        let data = try encoder.encode(configuration)
        defaults.set(data, forKey: key)
        cache[deviceId] = configuration
    }
    
    /// Load a working configuration for a device
    public func load(forDevice deviceId: String) throws -> CGMProtocolConfiguration? {
        // Check cache first
        if let cached = cache[deviceId] {
            return cached
        }
        
        // Load from storage
        let key = keyPrefix + deviceId
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        let config = try decoder.decode(CGMProtocolConfiguration.self, from: data)
        cache[deviceId] = config
        return config
    }
    
    /// Clear saved configuration for a device
    public func clear(forDevice deviceId: String) {
        let key = keyPrefix + deviceId
        defaults.removeObject(forKey: key)
        cache.removeValue(forKey: deviceId)
    }
    
    /// Get all saved device IDs
    public var savedDeviceIds: [String] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(keyPrefix) }
            .map { String($0.dropFirst(keyPrefix.count)) }
    }
}

// MARK: - Diagnostic Report Generator (PROTO-AUTO-003)

/// Generates diagnostic reports from attempt history
public struct DiagnosticReportGenerator: Sendable {
    
    /// Generate a text report from attempt history
    public static func generateTextReport(from attempts: [ProtocolAttemptResult]) -> String {
        var lines: [String] = []
        
        lines.append("=== Protocol Discovery Diagnostic Report ===")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")
        
        // Summary
        let successful = attempts.filter { $0.success }.count
        let failed = attempts.filter { !$0.success }.count
        lines.append("## Summary")
        lines.append("Total attempts: \(attempts.count)")
        lines.append("Successful: \(successful)")
        lines.append("Failed: \(failed)")
        lines.append("Success rate: \(String(format: "%.1f%%", Double(successful) / Double(max(1, attempts.count)) * 100))")
        lines.append("")
        
        // Stage breakdown
        lines.append("## Stage Reached Breakdown")
        let byStage = Dictionary(grouping: attempts) { $0.stageReached }
        for stage in ProtocolStage.allCases {
            if let stageAttempts = byStage[stage], !stageAttempts.isEmpty {
                lines.append("- \(stage.description): \(stageAttempts.count)")
            }
        }
        lines.append("")
        
        // Error breakdown
        let errors = attempts.compactMap { $0.errorMessage }
        if !errors.isEmpty {
            lines.append("## Common Errors")
            let errorCounts = Dictionary(grouping: errors) { $0 }.mapValues { $0.count }
            for (error, count) in errorCounts.sorted(by: { $0.value > $1.value }).prefix(10) {
                lines.append("- [\(count)x] \(error)")
            }
            lines.append("")
        }
        
        // Successful configurations
        let successfulConfigs = attempts.filter { $0.success }
        if !successfulConfigs.isEmpty {
            lines.append("## Successful Configurations")
            for attempt in successfulConfigs {
                lines.append("- \(attempt.configuration.name) (stage: \(attempt.stageReached.description))")
            }
            lines.append("")
        }
        
        // Timing analysis
        lines.append("## Timing Analysis")
        let durations = attempts.map(\.durationSeconds)
        if !durations.isEmpty {
            lines.append("Average duration: \(String(format: "%.2fs", durations.reduce(0, +) / Double(durations.count)))")
            lines.append("Min duration: \(String(format: "%.2fs", durations.min() ?? 0))")
            lines.append("Max duration: \(String(format: "%.2fs", durations.max() ?? 0))")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Generate a JSON report from attempt history
    public static func generateJSONReport(from attempts: [ProtocolAttemptResult]) throws -> Data {
        let report = DiagnosticReport(
            generatedAt: Date(),
            totalAttempts: attempts.count,
            successfulAttempts: attempts.filter { $0.success }.count,
            failedAttempts: attempts.filter { !$0.success }.count,
            attempts: attempts
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }
}

/// Full diagnostic report structure
public struct DiagnosticReport: Sendable, Codable {
    public let generatedAt: Date
    public let totalAttempts: Int
    public let successfulAttempts: Int
    public let failedAttempts: Int
    public let attempts: [ProtocolAttemptResult]
}
