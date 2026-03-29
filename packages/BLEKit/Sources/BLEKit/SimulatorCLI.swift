// SPDX-License-Identifier: AGPL-3.0-or-later
//
// SimulatorCLI.swift
// BLEKit
//
// Command-line interface for running the CGM transmitter simulator.
// Enables headless testing and automation without GUI dependencies.
// Trace: PRD-007 REQ-SIM-009

import Foundation

// MARK: - CLI Command

/// Available CLI commands
public enum SimulatorCommand: String, Sendable, CaseIterable {
    /// Run the simulator
    case run
    
    /// Generate sample configuration
    case config
    
    /// Show simulator status
    case status
    
    /// Export traffic log
    case export
    
    /// Show help
    case help
    
    /// Show version
    case version
}

// MARK: - Output Mode

/// Output format for CLI
public enum OutputMode: String, Sendable, CaseIterable {
    /// Human-readable text output
    case text
    
    /// JSON output for machine parsing
    case json
    
    /// Minimal output (errors only)
    case silent
}

// MARK: - CLI Configuration

/// Configuration for CLI simulator
public struct CLIConfiguration: Sendable, Codable {
    /// Transmitter ID
    public var transmitterId: String
    
    /// Transmitter type (g5, g6, g7)
    public var transmitterType: String
    
    /// Glucose pattern (flat, sine, meal, random)
    public var pattern: String
    
    /// Pattern parameters
    public var patternConfig: PatternConfig
    
    /// Session configuration
    public var session: SessionConfig
    
    /// Output configuration
    public var output: OutputConfig
    
    /// Default configuration
    public static let `default` = CLIConfiguration(
        transmitterId: "80H123",
        transmitterType: "g6",
        pattern: "flat",
        patternConfig: PatternConfig(),
        session: SessionConfig(),
        output: OutputConfig()
    )
    
    public init(
        transmitterId: String = "80H123",
        transmitterType: String = "g6",
        pattern: String = "flat",
        patternConfig: PatternConfig = PatternConfig(),
        session: SessionConfig = SessionConfig(),
        output: OutputConfig = OutputConfig()
    ) {
        self.transmitterId = transmitterId
        self.transmitterType = transmitterType
        self.pattern = pattern
        self.patternConfig = patternConfig
        self.session = session
        self.output = output
    }
}

/// Pattern-specific configuration
public struct PatternConfig: Sendable, Codable {
    /// Base glucose for flat pattern
    public var baseGlucose: Int
    
    /// Amplitude for sine pattern
    public var amplitude: Int
    
    /// Period in minutes for sine pattern
    public var periodMinutes: Int
    
    /// Random walk step size
    public var stepSize: Int
    
    public init(
        baseGlucose: Int = 120,
        amplitude: Int = 40,
        periodMinutes: Int = 180,
        stepSize: Int = 5
    ) {
        self.baseGlucose = baseGlucose
        self.amplitude = amplitude
        self.periodMinutes = periodMinutes
        self.stepSize = stepSize
    }
}

/// Session configuration
public struct SessionConfig: Sendable, Codable {
    /// Duration in seconds (0 = run until stopped)
    public var durationSeconds: Int
    
    /// Reading interval in seconds
    public var intervalSeconds: Int
    
    /// Skip warmup period
    public var skipWarmup: Bool
    
    /// Time acceleration factor
    public var timeAcceleration: Double
    
    public init(
        durationSeconds: Int = 0,
        intervalSeconds: Int = 300,
        skipWarmup: Bool = true,
        timeAcceleration: Double = 1.0
    ) {
        self.durationSeconds = durationSeconds
        self.intervalSeconds = intervalSeconds
        self.skipWarmup = skipWarmup
        self.timeAcceleration = timeAcceleration
    }
}

/// Output configuration
public struct OutputConfig: Sendable, Codable {
    /// Output mode
    public var mode: String
    
    /// Log file path (optional)
    public var logFile: String?
    
    /// Traffic log file (optional)
    public var trafficLog: String?
    
    /// Include timestamps in output
    public var timestamps: Bool
    
    public init(
        mode: String = "text",
        logFile: String? = nil,
        trafficLog: String? = nil,
        timestamps: Bool = true
    ) {
        self.mode = mode
        self.logFile = logFile
        self.trafficLog = trafficLog
        self.timestamps = timestamps
    }
}

// MARK: - CLI Arguments

/// Parsed CLI arguments
public struct CLIArguments: Sendable {
    /// Command to execute
    public var command: SimulatorCommand
    
    /// Configuration file path
    public var configPath: String?
    
    /// Output mode override
    public var outputMode: OutputMode
    
    /// Transmitter ID override
    public var transmitterId: String?
    
    /// Pattern override
    public var pattern: String?
    
    /// Duration override
    public var duration: Int?
    
    /// Verbose output
    public var verbose: Bool
    
    public init(
        command: SimulatorCommand = .help,
        configPath: String? = nil,
        outputMode: OutputMode = .text,
        transmitterId: String? = nil,
        pattern: String? = nil,
        duration: Int? = nil,
        verbose: Bool = false
    ) {
        self.command = command
        self.configPath = configPath
        self.outputMode = outputMode
        self.transmitterId = transmitterId
        self.pattern = pattern
        self.duration = duration
        self.verbose = verbose
    }
}

// MARK: - CLI Parser

/// Parses command-line arguments
public struct CLIParser: Sendable {
    
    /// Parse command-line arguments
    /// - Parameter args: Array of argument strings (excluding program name)
    /// - Returns: Parsed arguments
    public static func parse(_ args: [String]) -> Result<CLIArguments, CLIError> {
        var result = CLIArguments()
        var index = 0
        
        // Parse command
        if index < args.count {
            if let cmd = SimulatorCommand(rawValue: args[index].lowercased()) {
                result.command = cmd
                index += 1
            } else if args[index].hasPrefix("-") {
                // No command specified, default to help if just flags
                result.command = .help
            } else {
                return .failure(.unknownCommand(args[index]))
            }
        }
        
        // Parse flags and options
        while index < args.count {
            let arg = args[index]
            
            switch arg {
            case "-c", "--config":
                guard index + 1 < args.count else {
                    return .failure(.missingValue(arg))
                }
                index += 1
                result.configPath = args[index]
                
            case "-o", "--output":
                guard index + 1 < args.count else {
                    return .failure(.missingValue(arg))
                }
                index += 1
                guard let mode = OutputMode(rawValue: args[index].lowercased()) else {
                    return .failure(.invalidValue(arg, args[index]))
                }
                result.outputMode = mode
                
            case "-t", "--transmitter":
                guard index + 1 < args.count else {
                    return .failure(.missingValue(arg))
                }
                index += 1
                result.transmitterId = args[index]
                
            case "-p", "--pattern":
                guard index + 1 < args.count else {
                    return .failure(.missingValue(arg))
                }
                index += 1
                result.pattern = args[index]
                
            case "-d", "--duration":
                guard index + 1 < args.count else {
                    return .failure(.missingValue(arg))
                }
                index += 1
                guard let dur = Int(args[index]) else {
                    return .failure(.invalidValue(arg, args[index]))
                }
                result.duration = dur
                
            case "-v", "--verbose":
                result.verbose = true
                
            case "-h", "--help":
                result.command = .help
                
            case "--version":
                result.command = .version
                
            default:
                if arg.hasPrefix("-") {
                    return .failure(.unknownOption(arg))
                }
            }
            
            index += 1
        }
        
        return .success(result)
    }
    
    /// Generate help text
    public static var helpText: String {
        """
        CGM Transmitter Simulator CLI
        
        USAGE:
            cgm-sim <command> [options]
        
        COMMANDS:
            run         Run the simulator
            config      Generate sample configuration file
            status      Show simulator status
            export      Export traffic log
            help        Show this help message
            version     Show version information
        
        OPTIONS:
            -c, --config <path>     Configuration file path
            -o, --output <mode>     Output mode: text, json, silent
            -t, --transmitter <id>  Transmitter ID (e.g., 80H123)
            -p, --pattern <name>    Glucose pattern: flat, sine, meal, random
            -d, --duration <sec>    Run duration in seconds (0 = indefinite)
            -v, --verbose           Verbose output
            -h, --help              Show help
            --version               Show version
        
        EXAMPLES:
            cgm-sim run -t 80H123 -p flat
            cgm-sim run -c config.json
            cgm-sim config > config.json
            cgm-sim export -o json > traffic.json
        """
    }
    
    /// Version string
    public static var versionText: String {
        "CGM Transmitter Simulator v1.0.0 (BLEKit)"
    }
}

// MARK: - CLI Error

/// CLI parsing and execution errors
public enum CLIError: Error, Sendable, CustomStringConvertible {
    case unknownCommand(String)
    case unknownOption(String)
    case missingValue(String)
    case invalidValue(String, String)
    case configNotFound(String)
    case configParseError(String)
    case simulatorError(String)
    
    public var description: String {
        switch self {
        case .unknownCommand(let cmd):
            return "Unknown command: \(cmd)"
        case .unknownOption(let opt):
            return "Unknown option: \(opt)"
        case .missingValue(let opt):
            return "Missing value for option: \(opt)"
        case .invalidValue(let opt, let val):
            return "Invalid value '\(val)' for option: \(opt)"
        case .configNotFound(let path):
            return "Configuration file not found: \(path)"
        case .configParseError(let msg):
            return "Configuration parse error: \(msg)"
        case .simulatorError(let msg):
            return "Simulator error: \(msg)"
        }
    }
}

// MARK: - Simulator Runner

/// Runs the simulator in headless mode
public final class SimulatorRunner: @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Current configuration
    public private(set) var config: CLIConfiguration
    
    /// Output mode
    public var outputMode: OutputMode
    
    /// Traffic logger
    public let trafficLogger: BLETrafficLogger
    
    /// State simulator
    public private(set) var stateSimulator: TransmitterStateSimulator?
    
    /// Glucose simulator
    public private(set) var glucoseSimulator: G6GlucoseSimulator?
    
    /// Is running
    public private(set) var isRunning: Bool = false
    
    /// Reading count
    public private(set) var readingCount: Int = 0
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    /// Create a simulator runner
    public init(config: CLIConfiguration = .default, outputMode: OutputMode = .text) {
        self.config = config
        self.outputMode = outputMode
        self.trafficLogger = BLETrafficLogger()
    }
    
    // MARK: - Configuration
    
    /// Load configuration from file
    public func loadConfig(from path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        config = try decoder.decode(CLIConfiguration.self, from: data)
    }
    
    /// Apply CLI argument overrides
    public func applyOverrides(_ args: CLIArguments) {
        if let id = args.transmitterId {
            config.transmitterId = id
        }
        if let pattern = args.pattern {
            config.pattern = pattern
        }
        if let duration = args.duration {
            config.session.durationSeconds = duration
        }
        outputMode = args.outputMode
    }
    
    // MARK: - Running
    
    /// Start the simulator
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isRunning else { return }
        
        // Create state simulator
        let stateConfig: StateSimulatorConfig
        if config.session.skipWarmup {
            stateConfig = .instant
        } else {
            stateConfig = config.transmitterType == "g7" ? .g7 : .g6
        }
        stateSimulator = TransmitterStateSimulator(config: stateConfig)
        
        // Create glucose provider based on pattern
        let provider = createGlucoseProvider()
        
        // Create sensor session (start in active state if skipping warmup)
        let transmitterType: TransmitterType = config.transmitterType == "g7" ? .g7 : .g6
        let initialState: TransmitterState = config.session.skipWarmup ? .active : .warmup
        let session = SensorSession(
            startTime: config.session.skipWarmup ? Date().addingTimeInterval(-3 * 60 * 60) : Date(),
            state: initialState,
            transmitterType: transmitterType
        )
        
        // Create glucose simulator
        glucoseSimulator = G6GlucoseSimulator(
            session: session,
            glucoseProvider: provider
        )
        
        // Start session
        stateSimulator?.startSensor()
        isRunning = true
        readingCount = 0
        
        output("Simulator started")
        output("Transmitter: \(config.transmitterId)")
        output("Pattern: \(config.pattern)")
    }
    
    /// Stop the simulator
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRunning else { return }
        
        stateSimulator?.stopSensor()
        isRunning = false
        
        output("Simulator stopped after \(readingCount) readings")
    }
    
    /// Generate a single glucose reading
    public func generateReading() -> SimulatedGlucoseReading? {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRunning, let simulator = glucoseSimulator else {
            return nil
        }
        
        // Build a glucose request
        let request = Data([0x30])  // GlucoseTx opcode
        
        // Process and get response
        let result = simulator.processMessage(request)
        
        if case .sendResponse(let data) = result {
            trafficLogger.logOutgoing(request)
            trafficLogger.logIncoming(data)
            readingCount += 1
            
            // Parse response to get reading info
            // Response format: opcode(1) + status(1) + sequence(4) + timestamp(4) + glucose(2) + predicted(2) + trend(1)
            // Glucose is at bytes 10-11 (zero-indexed)
            if data.count >= 15 {
                let glucose = UInt16(data[10]) | (UInt16(data[11]) << 8)
                let reading = SimulatedGlucoseReading(
                    glucose: glucose,
                    sequence: UInt32(readingCount),
                    timestamp: UInt32(Date().timeIntervalSince1970)
                )
                
                outputReading(reading)
                return reading
            }
        }
        
        return nil
    }
    
    /// Run for specified duration
    /// - Parameter duration: Duration in seconds (0 = single reading)
    public func run(duration: Int = 0) {
        start()
        
        if duration == 0 {
            // Single reading
            _ = generateReading()
        } else {
            // Run for duration
            let interval = TimeInterval(config.session.intervalSeconds)
            let endTime = Date().addingTimeInterval(TimeInterval(duration))
            
            while Date() < endTime && isRunning {
                _ = generateReading()
                if Date() < endTime {
                    Thread.sleep(forTimeInterval: Swift.min(interval, endTime.timeIntervalSinceNow))
                }
            }
        }
        
        stop()
    }
    
    // MARK: - Export
    
    /// Export traffic log
    public func exportTraffic(format: TrafficExportFormat = .json) -> String {
        trafficLogger.export(format: format)
    }
    
    /// Generate sample configuration JSON
    public static func generateSampleConfig() -> String {
        let config = CLIConfiguration.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(config),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
    
    // MARK: - Status
    
    /// Get current status
    public var status: SimulatorStatus {
        lock.lock()
        defer { lock.unlock() }
        
        return SimulatorStatus(
            isRunning: isRunning,
            state: stateSimulator?.state ?? .inactive,
            readingCount: readingCount,
            transmitterId: config.transmitterId,
            pattern: config.pattern,
            trafficEntries: trafficLogger.count
        )
    }
    
    // MARK: - Private
    
    private func createGlucoseProvider() -> GlucoseProvider {
        let base = UInt16(config.patternConfig.baseGlucose)
        
        switch config.pattern.lowercased() {
        case "sine":
            return SineWavePattern(
                baseGlucose: base,
                amplitude: UInt16(config.patternConfig.amplitude),
                periodMinutes: Double(config.patternConfig.periodMinutes)
            )
        case "meal":
            return MealResponsePattern(baseGlucose: base)
        case "random":
            return RandomWalkPattern(
                baseGlucose: base,
                volatility: Double(config.patternConfig.stepSize)
            )
        default:
            return FlatGlucosePattern(baseGlucose: base)
        }
    }
    
    private func output(_ message: String) {
        guard outputMode != .silent else { return }
        
        if outputMode == .json {
            let json = ["message": message, "timestamp": ISO8601DateFormatter().string(from: Date())]
            if let data = try? JSONEncoder().encode(json),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            if config.output.timestamps {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                print("[\(formatter.string(from: Date()))] \(message)")
            } else {
                print(message)
            }
        }
    }
    
    private func outputReading(_ reading: SimulatedGlucoseReading) {
        guard outputMode != .silent else { return }
        
        if outputMode == .json {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(reading),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            output("Glucose: \(reading.glucose) mg/dL (seq: \(reading.sequence))")
        }
    }
}

// MARK: - Simulator Status

/// Current simulator status
public struct SimulatorStatus: Sendable, Codable {
    public let isRunning: Bool
    public let state: TransmitterState
    public let readingCount: Int
    public let transmitterId: String
    public let pattern: String
    public let trafficEntries: Int
}

// MARK: - CLI Executor

/// Executes CLI commands
public struct CLIExecutor: Sendable {
    
    /// Execute parsed arguments
    public static func execute(_ args: CLIArguments) -> Result<String, CLIError> {
        switch args.command {
        case .help:
            return .success(CLIParser.helpText)
            
        case .version:
            return .success(CLIParser.versionText)
            
        case .config:
            return .success(SimulatorRunner.generateSampleConfig())
            
        case .run:
            return executeRun(args)
            
        case .status:
            return .success("Simulator not running (use 'run' command)")
            
        case .export:
            return .success("No traffic to export (run simulator first)")
        }
    }
    
    private static func executeRun(_ args: CLIArguments) -> Result<String, CLIError> {
        var config = CLIConfiguration.default
        
        // Load config file if specified
        if let path = args.configPath {
            do {
                let url = URL(fileURLWithPath: path)
                let data = try Data(contentsOf: url)
                config = try JSONDecoder().decode(CLIConfiguration.self, from: data)
            } catch {
                return .failure(.configParseError(error.localizedDescription))
            }
        }
        
        let runner = SimulatorRunner(config: config, outputMode: args.outputMode)
        runner.applyOverrides(args)
        
        let duration = args.duration ?? config.session.durationSeconds
        runner.run(duration: duration)
        
        let status = runner.status
        
        if args.outputMode == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(status),
               let str = String(data: data, encoding: .utf8) {
                return .success(str)
            }
        }
        
        return .success("Completed: \(status.readingCount) readings generated")
    }
}
