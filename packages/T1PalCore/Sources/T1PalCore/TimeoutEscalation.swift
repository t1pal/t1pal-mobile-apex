/// Communication timeout escalation for pump/CGM operations
/// Pattern: Loop DeviceDataManager retry logic
///
/// Implements retry-before-alert pattern:
/// 1. First failures: Silent retry (up to maxRetries)
/// 2. Retries exhausted: Escalate to warning
/// 3. Persistent failures: Escalate to critical alert
///
/// ## Usage
/// ```swift
/// let policy = RetryPolicy.standard
/// var tracker = CommunicationRetryTracker(policy: policy)
///
/// for attempt in 1...policy.maxRetries {
///     do {
///         try await sendCommand()
///         tracker.recordSuccess()
///         break
///     } catch {
///         let action = tracker.recordFailure(error: error)
///         if action == .abort { throw error }
///         await Task.sleep(for: policy.delayBetweenRetries)
///     }
/// }
/// ```

import Foundation

// MARK: - RetryPolicy

/// Configuration for retry behavior
public struct RetryPolicy: Sendable, Equatable, Codable {
    
    /// Maximum number of retry attempts
    public let maxRetries: Int
    
    /// Delay between retry attempts
    public let delayBetweenRetries: Duration
    
    /// Total timeout for all retries combined
    public let totalTimeout: Duration
    
    /// Whether to use exponential backoff
    public let useExponentialBackoff: Bool
    
    /// Backoff multiplier (if using exponential backoff)
    public let backoffMultiplier: Double
    
    /// Maximum delay when using exponential backoff
    public let maxBackoffDelay: Duration
    
    /// Initialize with custom values
    public init(
        maxRetries: Int = 3,
        delayBetweenRetries: Duration = .milliseconds(500),
        totalTimeout: Duration = .seconds(30),
        useExponentialBackoff: Bool = false,
        backoffMultiplier: Double = 2.0,
        maxBackoffDelay: Duration = .seconds(10)
    ) {
        self.maxRetries = maxRetries
        self.delayBetweenRetries = delayBetweenRetries
        self.totalTimeout = totalTimeout
        self.useExponentialBackoff = useExponentialBackoff
        self.backoffMultiplier = backoffMultiplier
        self.maxBackoffDelay = maxBackoffDelay
    }
    
    // MARK: - Presets
    
    /// Standard retry policy (3 retries, 500ms delay)
    public static let standard = RetryPolicy(
        maxRetries: 3,
        delayBetweenRetries: .milliseconds(500),
        totalTimeout: .seconds(30)
    )
    
    /// Quick retry for time-sensitive operations (2 retries, 200ms delay)
    public static let quick = RetryPolicy(
        maxRetries: 2,
        delayBetweenRetries: .milliseconds(200),
        totalTimeout: .seconds(10)
    )
    
    /// Patient retry for flaky connections (5 retries, exponential backoff)
    public static let patient = RetryPolicy(
        maxRetries: 5,
        delayBetweenRetries: .milliseconds(500),
        totalTimeout: .seconds(60),
        useExponentialBackoff: true,
        backoffMultiplier: 2.0,
        maxBackoffDelay: .seconds(10)
    )
    
    /// No retry (immediate failure)
    public static let noRetry = RetryPolicy(
        maxRetries: 0,
        delayBetweenRetries: .zero,
        totalTimeout: .seconds(30)
    )
    
    /// Calculate delay for a given attempt number
    public func delayFor(attempt: Int) -> Duration {
        guard useExponentialBackoff else {
            return delayBetweenRetries
        }
        
        let multiplier = pow(backoffMultiplier, Double(attempt - 1))
        let delayNanos = Double(delayBetweenRetries.components.attoseconds) / 1_000_000_000 * multiplier
        let maxNanos = Double(maxBackoffDelay.components.attoseconds) / 1_000_000_000
        let actualDelay = min(delayNanos, maxNanos)
        
        return .nanoseconds(Int64(actualDelay * 1_000_000_000))
    }
}

// MARK: - CommunicationRetryTracker

/// Tracks retry attempts and determines escalation
public struct CommunicationRetryTracker: Sendable {
    
    /// Retry policy
    public let policy: RetryPolicy
    
    /// Current attempt number (0 = not started)
    public private(set) var currentAttempt: Int
    
    /// Last error encountered
    public private(set) var lastError: String?
    
    /// When first failure occurred
    public private(set) var firstFailureTime: Date?
    
    /// Total failures recorded
    public private(set) var totalFailures: Int
    
    /// Current escalation level
    public private(set) var escalationLevel: EscalationLevel
    
    /// Initialize with policy
    public init(policy: RetryPolicy = .standard) {
        self.policy = policy
        self.currentAttempt = 0
        self.lastError = nil
        self.firstFailureTime = nil
        self.totalFailures = 0
        self.escalationLevel = .none
    }
    
    /// Record a successful operation (resets tracker)
    public mutating func recordSuccess() {
        currentAttempt = 0
        lastError = nil
        firstFailureTime = nil
        escalationLevel = .none
        // Don't reset totalFailures - useful for metrics
    }
    
    /// Record a failure and determine next action
    public mutating func recordFailure(error: Error, at time: Date = Date()) -> RetryAction {
        currentAttempt += 1
        totalFailures += 1
        lastError = error.localizedDescription
        
        if firstFailureTime == nil {
            firstFailureTime = time
        }
        
        // Check if retries exhausted
        if currentAttempt > policy.maxRetries {
            escalationLevel = .alert
            return .abort
        }
        
        // Check total timeout
        if let firstTime = firstFailureTime {
            let elapsed = time.timeIntervalSince(firstTime)
            let totalTimeoutSeconds = Double(policy.totalTimeout.components.seconds)
            if elapsed > totalTimeoutSeconds {
                escalationLevel = .alert
                return .abort
            }
        }
        
        // Determine escalation level based on attempt
        updateEscalationLevel()
        
        return .retry(delay: policy.delayFor(attempt: currentAttempt))
    }
    
    /// Check if we should escalate to user notification
    public var shouldNotifyUser: Bool {
        escalationLevel >= .warning
    }
    
    /// Get current status for logging/display
    public var status: Status {
        Status(
            currentAttempt: currentAttempt,
            maxRetries: policy.maxRetries,
            escalationLevel: escalationLevel,
            lastError: lastError,
            totalFailures: totalFailures
        )
    }
    
    // MARK: - Private
    
    private mutating func updateEscalationLevel() {
        // Alert only when retries are exhausted (after maxRetries attempts)
        // Warning when >= 50% of retries used but not yet exhausted
        if currentAttempt > policy.maxRetries {
            escalationLevel = .alert
        } else if currentAttempt >= (policy.maxRetries + 1) / 2 {
            // At or past halfway point (e.g., attempt 2+ for 3 retries)
            escalationLevel = .warning
        } else {
            escalationLevel = .none
        }
    }
    
    // MARK: - Nested Types
    
    /// Next action after failure
    public enum RetryAction: Sendable, Equatable {
        /// Retry after delay
        case retry(delay: Duration)
        
        /// Stop retrying, escalate
        case abort
    }
    
    /// Escalation level
    public enum EscalationLevel: Int, Sendable, Comparable, Codable {
        /// No escalation - silent retry
        case none = 0
        
        /// Warning level - may show subtle indicator
        case warning = 1
        
        /// Alert level - notify user
        case alert = 2
        
        public static func < (lhs: EscalationLevel, rhs: EscalationLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
        
        /// Convert to DeviceStatusElementState
        public var elementState: DeviceStatusElementState {
            switch self {
            case .none: return .normalPump
            case .warning: return .warning
            case .alert: return .critical
            }
        }
    }
    
    /// Status snapshot
    public struct Status: Sendable, Equatable {
        public let currentAttempt: Int
        public let maxRetries: Int
        public let escalationLevel: EscalationLevel
        public let lastError: String?
        public let totalFailures: Int
        
        public var retriesRemaining: Int {
            max(0, maxRetries - currentAttempt)
        }
        
        public var progressDescription: String {
            if currentAttempt == 0 {
                return "Ready"
            } else if currentAttempt > maxRetries {
                return "Retries exhausted"
            } else {
                return "Attempt \(currentAttempt)/\(maxRetries)"
            }
        }
    }
}

// MARK: - TimeoutEscalationManager

/// Manages timeout escalation for device communication
public struct TimeoutEscalationManager: Sendable {
    
    /// Trackers by operation type
    private var trackers: [OperationType: CommunicationRetryTracker]
    
    /// Default policy
    public let defaultPolicy: RetryPolicy
    
    /// Callback for escalation events
    public var onEscalation: (@Sendable (EscalationEvent) -> Void)?
    
    /// Initialize with default policy
    public init(defaultPolicy: RetryPolicy = .standard) {
        self.defaultPolicy = defaultPolicy
        self.trackers = [:]
    }
    
    /// Get or create tracker for operation type
    public mutating func tracker(for operation: OperationType) -> CommunicationRetryTracker {
        if let existing = trackers[operation] {
            return existing
        }
        let policy = policyFor(operation: operation)
        let tracker = CommunicationRetryTracker(policy: policy)
        trackers[operation] = tracker
        return tracker
    }
    
    /// Record success for operation
    public mutating func recordSuccess(for operation: OperationType) {
        var tracker = self.tracker(for: operation)
        tracker.recordSuccess()
        trackers[operation] = tracker
    }
    
    /// Record failure for operation
    public mutating func recordFailure(
        for operation: OperationType,
        error: Error,
        at time: Date = Date()
    ) -> CommunicationRetryTracker.RetryAction {
        var tracker = self.tracker(for: operation)
        let previousLevel = tracker.escalationLevel
        let action = tracker.recordFailure(error: error, at: time)
        trackers[operation] = tracker
        
        // Fire escalation callback if level changed
        if tracker.escalationLevel > previousLevel {
            onEscalation?(EscalationEvent(
                operation: operation,
                level: tracker.escalationLevel,
                error: error.localizedDescription,
                attempt: tracker.currentAttempt,
                maxRetries: tracker.policy.maxRetries
            ))
        }
        
        return action
    }
    
    /// Get current status for all operations
    public var allStatus: [OperationType: CommunicationRetryTracker.Status] {
        trackers.mapValues { $0.status }
    }
    
    /// Reset all trackers
    public mutating func resetAll() {
        for (operation, var tracker) in trackers {
            tracker.recordSuccess()
            trackers[operation] = tracker
        }
    }
    
    // MARK: - Private
    
    private func policyFor(operation: OperationType) -> RetryPolicy {
        switch operation {
        case .pumpStatus, .cgmReading:
            return .standard
        case .bolus, .tempBasal:
            return .quick  // Time-sensitive, fewer retries
        case .pumpHistory, .settings:
            return .patient  // Can wait longer
        case .custom:
            return defaultPolicy
        }
    }
    
    // MARK: - Operation Types
    
    /// Types of operations that can be tracked
    public enum OperationType: String, Sendable, Hashable, Codable {
        case pumpStatus
        case cgmReading
        case bolus
        case tempBasal
        case pumpHistory
        case settings
        case custom
    }
    
    /// Escalation event
    public struct EscalationEvent: Sendable {
        public let operation: OperationType
        public let level: CommunicationRetryTracker.EscalationLevel
        public let error: String
        public let attempt: Int
        public let maxRetries: Int
        
        /// User-facing message
        public var message: String {
            switch level {
            case .none:
                return "Connecting..."
            case .warning:
                return "Connection attempt \(attempt) of \(maxRetries) - \(operation.rawValue)"
            case .alert:
                return "Unable to communicate with \(deviceName) after \(maxRetries) attempts"
            }
        }
        
        private var deviceName: String {
            switch operation {
            case .pumpStatus, .bolus, .tempBasal, .pumpHistory:
                return "pump"
            case .cgmReading:
                return "CGM"
            case .settings, .custom:
                return "device"
            }
        }
    }
}

// MARK: - TimeoutAlert

/// Alert for communication timeout
public struct TimeoutAlert: Sendable, Equatable {
    
    /// Alert title
    public let title: String
    
    /// Alert message
    public let message: String
    
    /// Recovery suggestions
    public let recoverySuggestions: [String]
    
    /// Severity level
    public let level: CommunicationRetryTracker.EscalationLevel
    
    /// Create from escalation event
    public init(event: TimeoutEscalationManager.EscalationEvent) {
        self.level = event.level
        
        switch event.level {
        case .none:
            self.title = "Connecting"
            self.message = "Attempting to connect to \(event.operation.rawValue)..."
            self.recoverySuggestions = []
            
        case .warning:
            self.title = "Connection Delayed"
            self.message = "Having trouble connecting. Attempt \(event.attempt) of \(event.maxRetries)."
            self.recoverySuggestions = [
                "Move closer to your device",
                "Make sure Bluetooth is enabled"
            ]
            
        case .alert:
            self.title = "Connection Failed"
            self.message = "Unable to communicate after \(event.maxRetries) attempts: \(event.error)"
            self.recoverySuggestions = [
                "Check that your device is powered on",
                "Toggle Bluetooth off and on",
                "Move closer to your device",
                "Check for interference from other devices",
                "Restart the app if problem persists"
            ]
        }
    }
    
    /// Create custom alert
    public init(
        title: String,
        message: String,
        recoverySuggestions: [String] = [],
        level: CommunicationRetryTracker.EscalationLevel = .alert
    ) {
        self.title = title
        self.message = message
        self.recoverySuggestions = recoverySuggestions
        self.level = level
    }
}

// MARK: - Async Retry Helper

/// Execute an operation with retry policy
public func withRetry<T: Sendable>(
    policy: RetryPolicy = .standard,
    operation: OperationType = .custom,
    action: @Sendable () async throws -> T
) async throws -> T {
    var tracker = CommunicationRetryTracker(policy: policy)
    var lastError: Error?
    
    for _ in 0...policy.maxRetries {
        do {
            let result = try await action()
            tracker.recordSuccess()
            return result
        } catch {
            lastError = error
            let retryAction = tracker.recordFailure(error: error)
            
            switch retryAction {
            case .retry(let delay):
                try await Task.sleep(for: delay)
            case .abort:
                throw error
            }
        }
    }
    
    throw lastError ?? CommunicationError.retriesExhausted
}

/// Communication error for retry exhaustion
public enum CommunicationError: Error, LocalizedError, Sendable {
    case retriesExhausted
    case timeout
    case connectionLost
    
    public var errorDescription: String? {
        switch self {
        case .retriesExhausted:
            return "Communication failed after maximum retries"
        case .timeout:
            return "Communication timed out"
        case .connectionLost:
            return "Connection was lost"
        }
    }
}

// MARK: - Convenience Type Alias

public typealias OperationType = TimeoutEscalationManager.OperationType
