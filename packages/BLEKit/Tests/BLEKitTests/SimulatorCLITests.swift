// SPDX-License-Identifier: MIT
//
// SimulatorCLITests.swift
// BLEKit Tests
//
// Tests for CLI/headless simulator functionality.
// Trace: PRD-007 REQ-SIM-009

import Testing
import Foundation
@testable import BLEKit

// MARK: - CLI Parser Tests

@Suite("CLIParser Tests")
struct CLIParserTests {
    
    @Test("Parses help command")
    func parsesHelpCommand() {
        let result = CLIParser.parse(["help"])
        
        if case .success(let args) = result {
            #expect(args.command == .help)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses run command")
    func parsesRunCommand() {
        let result = CLIParser.parse(["run"])
        
        if case .success(let args) = result {
            #expect(args.command == .run)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses config command")
    func parsesConfigCommand() {
        let result = CLIParser.parse(["config"])
        
        if case .success(let args) = result {
            #expect(args.command == .config)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses version command")
    func parsesVersionCommand() {
        let result = CLIParser.parse(["version"])
        
        if case .success(let args) = result {
            #expect(args.command == .version)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses transmitter option")
    func parsesTransmitterOption() {
        let result = CLIParser.parse(["run", "-t", "80H456"])
        
        if case .success(let args) = result {
            #expect(args.command == .run)
            #expect(args.transmitterId == "80H456")
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses pattern option")
    func parsesPatternOption() {
        let result = CLIParser.parse(["run", "-p", "sine"])
        
        if case .success(let args) = result {
            #expect(args.pattern == "sine")
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses duration option")
    func parsesDurationOption() {
        let result = CLIParser.parse(["run", "-d", "60"])
        
        if case .success(let args) = result {
            #expect(args.duration == 60)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses output mode option")
    func parsesOutputOption() {
        let result = CLIParser.parse(["run", "-o", "json"])
        
        if case .success(let args) = result {
            #expect(args.outputMode == .json)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses verbose flag")
    func parsesVerboseFlag() {
        let result = CLIParser.parse(["run", "-v"])
        
        if case .success(let args) = result {
            #expect(args.verbose == true)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses config path option")
    func parsesConfigPath() {
        let result = CLIParser.parse(["run", "-c", "/path/to/config.json"])
        
        if case .success(let args) = result {
            #expect(args.configPath == "/path/to/config.json")
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses long options")
    func parsesLongOptions() {
        let result = CLIParser.parse(["run", "--transmitter", "ABC123", "--pattern", "meal", "--duration", "120"])
        
        if case .success(let args) = result {
            #expect(args.transmitterId == "ABC123")
            #expect(args.pattern == "meal")
            #expect(args.duration == 120)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Parses multiple options")
    func parsesMultipleOptions() {
        let result = CLIParser.parse(["run", "-t", "80H789", "-p", "random", "-d", "30", "-o", "silent", "-v"])
        
        if case .success(let args) = result {
            #expect(args.command == .run)
            #expect(args.transmitterId == "80H789")
            #expect(args.pattern == "random")
            #expect(args.duration == 30)
            #expect(args.outputMode == .silent)
            #expect(args.verbose == true)
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Returns error for unknown command")
    func errorUnknownCommand() {
        let result = CLIParser.parse(["unknown"])
        
        if case .failure(let error) = result {
            #expect(error.description.contains("Unknown command"))
        } else {
            Issue.record("Expected failure")
        }
    }
    
    @Test("Returns error for unknown option")
    func errorUnknownOption() {
        let result = CLIParser.parse(["run", "--invalid"])
        
        if case .failure(let error) = result {
            #expect(error.description.contains("Unknown option"))
        } else {
            Issue.record("Expected failure")
        }
    }
    
    @Test("Returns error for missing value")
    func errorMissingValue() {
        let result = CLIParser.parse(["run", "-t"])
        
        if case .failure(let error) = result {
            #expect(error.description.contains("Missing value"))
        } else {
            Issue.record("Expected failure")
        }
    }
    
    @Test("Returns error for invalid value")
    func errorInvalidValue() {
        let result = CLIParser.parse(["run", "-d", "notanumber"])
        
        if case .failure(let error) = result {
            #expect(error.description.contains("Invalid value"))
        } else {
            Issue.record("Expected failure")
        }
    }
    
    @Test("Help text is not empty")
    func helpTextNotEmpty() {
        #expect(!CLIParser.helpText.isEmpty)
        #expect(CLIParser.helpText.contains("USAGE"))
        #expect(CLIParser.helpText.contains("COMMANDS"))
        #expect(CLIParser.helpText.contains("OPTIONS"))
    }
    
    @Test("Version text is not empty")
    func versionTextNotEmpty() {
        #expect(!CLIParser.versionText.isEmpty)
        #expect(CLIParser.versionText.contains("v1.0.0"))
    }
}

// MARK: - CLI Configuration Tests

@Suite("CLIConfiguration Tests")
struct CLIConfigurationTests {
    
    @Test("Default configuration has valid values")
    func defaultConfig() {
        let config = CLIConfiguration.default
        
        #expect(config.transmitterId == "80H123")
        #expect(config.transmitterType == "g6")
        #expect(config.pattern == "flat")
    }
    
    @Test("Configuration is codable")
    func configCodable() throws {
        let original = CLIConfiguration(
            transmitterId: "TEST123",
            transmitterType: "g7",
            pattern: "sine"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CLIConfiguration.self, from: data)
        
        #expect(decoded.transmitterId == "TEST123")
        #expect(decoded.transmitterType == "g7")
        #expect(decoded.pattern == "sine")
    }
    
    @Test("Pattern config has defaults")
    func patternConfigDefaults() {
        let config = PatternConfig()
        
        #expect(config.baseGlucose == 120)
        #expect(config.amplitude == 40)
        #expect(config.periodMinutes == 180)
    }
    
    @Test("Session config has defaults")
    func sessionConfigDefaults() {
        let config = SessionConfig()
        
        #expect(config.intervalSeconds == 300)
        #expect(config.skipWarmup == true)
        #expect(config.timeAcceleration == 1.0)
    }
    
    @Test("Output config has defaults")
    func outputConfigDefaults() {
        let config = OutputConfig()
        
        #expect(config.mode == "text")
        #expect(config.timestamps == true)
    }
}

// MARK: - Simulator Runner Tests

@Suite("SimulatorRunner Tests")
struct SimulatorRunnerTests {
    
    @Test("Runner starts with default config")
    func startsWithDefaultConfig() {
        let runner = SimulatorRunner()
        
        #expect(!runner.isRunning)
        #expect(runner.readingCount == 0)
    }
    
    @Test("Runner can start and stop")
    func startAndStop() {
        let runner = SimulatorRunner()
        
        runner.start()
        #expect(runner.isRunning)
        
        runner.stop()
        #expect(!runner.isRunning)
    }
    
    @Test("Runner generates readings")
    func generatesReadings() {
        let runner = SimulatorRunner()
        runner.start()
        
        let reading = runner.generateReading()
        
        #expect(reading != nil)
        #expect(runner.readingCount == 1)
        
        runner.stop()
    }
    
    @Test("Runner logs traffic")
    func logsTraffic() {
        let runner = SimulatorRunner()
        runner.start()
        
        _ = runner.generateReading()
        
        #expect(runner.trafficLogger.count >= 2)  // Request + response
        
        runner.stop()
    }
    
    @Test("Runner applies overrides")
    func appliesOverrides() {
        let runner = SimulatorRunner()
        let args = CLIArguments(
            transmitterId: "OVERRIDE",
            pattern: "sine",
            duration: 999
        )
        
        runner.applyOverrides(args)
        
        #expect(runner.config.transmitterId == "OVERRIDE")
        #expect(runner.config.pattern == "sine")
        #expect(runner.config.session.durationSeconds == 999)
    }
    
    @Test("Runner status reflects state")
    func statusReflectsState() {
        let runner = SimulatorRunner()
        
        var status = runner.status
        #expect(!status.isRunning)
        #expect(status.state == .inactive)
        
        runner.start()
        _ = runner.generateReading()
        status = runner.status
        
        #expect(status.isRunning)
        #expect(status.readingCount == 1)
        
        runner.stop()
    }
    
    @Test("Runner exports traffic")
    func exportsTraffic() {
        let runner = SimulatorRunner()
        runner.start()
        _ = runner.generateReading()
        runner.stop()
        
        let json = runner.exportTraffic(format: .json)
        let hex = runner.exportTraffic(format: .hexDump)
        
        #expect(!json.isEmpty)
        #expect(!hex.isEmpty)
    }
    
    @Test("Sample config is valid JSON")
    func sampleConfigIsValid() {
        let json = SimulatorRunner.generateSampleConfig()
        
        #expect(!json.isEmpty)
        
        let data = json.data(using: .utf8)!
        let config = try? JSONDecoder().decode(CLIConfiguration.self, from: data)
        
        #expect(config != nil)
    }
    
    @Test("Runner uses flat pattern")
    func usesFlatPattern() {
        var config = CLIConfiguration.default
        config.pattern = "flat"
        config.patternConfig.baseGlucose = 100
        
        let runner = SimulatorRunner(config: config)
        runner.start()
        
        let reading = runner.generateReading()
        
        // Flat pattern should be near base glucose
        #expect(reading != nil)
        #expect(reading!.glucose >= 40)
        #expect(reading!.glucose <= 400)
        
        runner.stop()
    }
    
    @Test("Runner uses sine pattern")
    func usesSinePattern() {
        var config = CLIConfiguration.default
        config.pattern = "sine"
        
        let runner = SimulatorRunner(config: config)
        runner.start()
        
        let reading = runner.generateReading()
        
        #expect(reading != nil)
        
        runner.stop()
    }
    
    @Test("Runner uses meal pattern")
    func usesMealPattern() {
        var config = CLIConfiguration.default
        config.pattern = "meal"
        
        let runner = SimulatorRunner(config: config)
        runner.start()
        
        let reading = runner.generateReading()
        
        #expect(reading != nil)
        
        runner.stop()
    }
    
    @Test("Runner uses random pattern")
    func usesRandomPattern() {
        var config = CLIConfiguration.default
        config.pattern = "random"
        
        let runner = SimulatorRunner(config: config)
        runner.start()
        
        let reading = runner.generateReading()
        
        #expect(reading != nil)
        
        runner.stop()
    }
    
    @Test("Runner handles different output modes")
    func handlesOutputModes() {
        for mode in OutputMode.allCases {
            let runner = SimulatorRunner(outputMode: mode)
            runner.start()
            _ = runner.generateReading()
            runner.stop()
            // Should not crash in any mode
        }
    }
}

// MARK: - CLI Executor Tests

@Suite("CLIExecutor Tests")
struct CLIExecutorTests {
    
    @Test("Execute help returns help text")
    func executeHelp() {
        let args = CLIArguments(command: .help)
        let result = CLIExecutor.execute(args)
        
        if case .success(let output) = result {
            #expect(output.contains("USAGE"))
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Execute version returns version")
    func executeVersion() {
        let args = CLIArguments(command: .version)
        let result = CLIExecutor.execute(args)
        
        if case .success(let output) = result {
            #expect(output.contains("v1.0.0"))
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Execute config returns JSON")
    func executeConfig() {
        let args = CLIArguments(command: .config)
        let result = CLIExecutor.execute(args)
        
        if case .success(let output) = result {
            #expect(output.contains("transmitterId"))
            #expect(output.contains("pattern"))
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Execute run with silent mode")
    func executeRunSilent() {
        let args = CLIArguments(command: .run, outputMode: .silent, duration: 0)
        let result = CLIExecutor.execute(args)
        
        if case .success(let output) = result {
            #expect(output.contains("Completed"))
        } else {
            Issue.record("Expected success")
        }
    }
    
    @Test("Execute run with JSON mode")
    func executeRunJSON() {
        let args = CLIArguments(command: .run, outputMode: .json, duration: 0)
        let result = CLIExecutor.execute(args)
        
        if case .success(let output) = result {
            // Should be valid JSON status
            #expect(output.contains("isRunning") || output.contains("Completed"))
        } else {
            Issue.record("Expected success")
        }
    }
}

// MARK: - CLI Error Tests

@Suite("CLIError Tests")
struct CLIErrorTests {
    
    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let errors: [CLIError] = [
            .unknownCommand("test"),
            .unknownOption("--test"),
            .missingValue("-t"),
            .invalidValue("-d", "abc"),
            .configNotFound("/path"),
            .configParseError("invalid json"),
            .simulatorError("failed")
        ]
        
        for error in errors {
            #expect(!error.description.isEmpty)
        }
    }
}

// MARK: - Output Mode Tests

@Suite("OutputMode Tests")
struct OutputModeTests {
    
    @Test("All output modes are available")
    func allModesAvailable() {
        #expect(OutputMode.allCases.count == 3)
        #expect(OutputMode.allCases.contains(.text))
        #expect(OutputMode.allCases.contains(.json))
        #expect(OutputMode.allCases.contains(.silent))
    }
    
    @Test("Output modes have raw values")
    func modesHaveRawValues() {
        #expect(OutputMode.text.rawValue == "text")
        #expect(OutputMode.json.rawValue == "json")
        #expect(OutputMode.silent.rawValue == "silent")
    }
}

// MARK: - Simulator Command Tests

@Suite("SimulatorCommand Tests")
struct SimulatorCommandTests {
    
    @Test("All commands are available")
    func allCommandsAvailable() {
        #expect(SimulatorCommand.allCases.count == 6)
    }
    
    @Test("Commands have raw values")
    func commandsHaveRawValues() {
        #expect(SimulatorCommand.run.rawValue == "run")
        #expect(SimulatorCommand.config.rawValue == "config")
        #expect(SimulatorCommand.help.rawValue == "help")
        #expect(SimulatorCommand.version.rawValue == "version")
    }
}
