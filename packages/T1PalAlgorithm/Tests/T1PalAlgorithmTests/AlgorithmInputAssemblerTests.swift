// SPDX-License-Identifier: AGPL-3.0-or-later
//
// AlgorithmInputAssemblerTests.swift
// T1Pal Mobile
//
// Tests for AlgorithmInputAssembler
// Requirements: ALG-INPUT-001

import Testing
import Foundation
@testable import T1PalAlgorithm
import T1PalCore

@Suite("Algorithm Input Assembler")
struct AlgorithmInputAssemblerTests {
    
    // MARK: - Basic Assembly Tests
    
    @Suite("Basic Assembly")
    struct BasicAssembly {
        @Test("Assemble inputs with mock data source")
        func assembleInputsWithMockDataSource() async throws {
            let mock = MockDataSource(scenario: .stable120)
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            let inputs = try await assembler.assembleInputs()
            
            #expect(!inputs.glucose.isEmpty)
            #expect(inputs.doseHistory != nil)
            #expect(inputs.carbHistory != nil)
            #expect(inputs.profile.basalRates.count > 0)
        }
        
        @Test("Assemble inputs at specific time")
        func assembleInputsAtSpecificTime() async throws {
            let mock = MockDataSource(scenario: .stable100)
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            let specificTime = Date().addingTimeInterval(-3600)  // 1 hour ago
            let inputs = try await assembler.assembleInputs(at: specificTime)
            
            #expect(inputs.currentTime == specificTime)
        }
    }
    
    // MARK: - Glucose Validation Tests
    
    @Suite("Glucose Validation")
    struct GlucoseValidation {
        @Test("Minimum glucose validation")
        func minimumGlucoseValidation() async throws {
            let mock = MockDataSource(scenario: .stable120, glucoseCount: 2)  // Only 2 readings
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            await #expect(throws: AlgorithmDataSourceError.self) {
                _ = try await assembler.assembleInputs()
            }
        }
        
        @Test("Custom minimum glucose")
        func customMinimumGlucose() async throws {
            let mock = MockDataSource(scenario: .stable120, glucoseCount: 5)
            var config = AlgorithmInputAssembler.Configuration.default
            config.minimumGlucoseCount = 10  // Require more than available
            
            let assembler = AlgorithmInputAssembler(dataSource: mock, configuration: config)
            
            await #expect(throws: AlgorithmDataSourceError.self) {
                _ = try await assembler.assembleInputs()
            }
        }
    }
    
    // MARK: - Configuration Tests
    
    @Suite("Configuration")
    struct Configuration {
        @Test("Default configuration")
        func defaultConfiguration() async throws {
            let mock = MockDataSource(scenario: .stable120)
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            let inputs = try await assembler.assembleInputs()
            
            // Default fetches 36 glucose readings
            #expect(inputs.glucose.count == 36)
        }
        
        @Test("High fidelity configuration")
        func highFidelityConfiguration() async throws {
            let mock = MockDataSource(scenario: .stable120, glucoseCount: 100)
            let assembler = AlgorithmInputAssembler(
                dataSource: mock,
                configuration: .highFidelity
            )
            
            let inputs = try await assembler.assembleInputs()
            
            // High fidelity fetches 72 readings (6 hours)
            #expect(inputs.glucose.count == 72)
        }
        
        @Test("Minimal configuration")
        func minimalConfiguration() async throws {
            let mock = MockDataSource(scenario: .stable120)
            let assembler = AlgorithmInputAssembler(
                dataSource: mock,
                configuration: .minimal
            )
            
            let inputs = try await assembler.assembleInputs()
            
            // Minimal fetches 12 readings (1 hour)
            #expect(inputs.glucose.count == 12)
        }
    }
    
    // MARK: - Loop Settings Tests
    
    @Suite("Loop Settings")
    struct LoopSettingsTests {
        @Test("Loop settings applied")
        func loopSettingsApplied() async throws {
            let settings = LoopSettings(
                maximumBasalRatePerHour: 5.0,
                maximumBolus: 12.0,
                minimumBGGuard: 75,
                dosingStrategy: "automaticBolus"
            )
            let mock = MockDataSource(customLoopSettings: settings)
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            let inputs = try await assembler.assembleInputs()
            
            #expect(inputs.profile.maxBasalRate == 5.0)
            #expect(inputs.profile.maxBolus == 12.0)
            #expect(inputs.profile.suspendThreshold == 75)
            #expect(inputs.profile.dosingStrategy == "automaticBolus")
        }
        
        @Test("Loop settings disabled")
        func loopSettingsDisabled() async throws {
            let settings = LoopSettings(maximumBasalRatePerHour: 99.0)
            let mock = MockDataSource(customLoopSettings: settings)
            
            var config = AlgorithmInputAssembler.Configuration.default
            config.applyLoopSettings = false
            
            let assembler = AlgorithmInputAssembler(dataSource: mock, configuration: config)
            let inputs = try await assembler.assembleInputs()
            
            // Should NOT apply the 99.0 setting
            #expect(inputs.profile.maxBasalRate != 99.0)
        }
    }
    
    // MARK: - IOB/COB Calculation Tests
    
    @Suite("IOB/COB Calculation")
    struct IOBCOBCalculation {
        @Test("IOB calculation")
        func iobCalculation() async throws {
            let mock = MockDataSource(scenario: .rising)  // Has recent doses
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            let inputs = try await assembler.assembleInputs()
            
            // Rising scenario has meal bolus, should have some IOB
            #expect(inputs.insulinOnBoard > 0)
        }
        
        @Test("COB calculation")
        func cobCalculation() async throws {
            let mock = MockDataSource(scenario: .rising)  // Has recent carbs
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            let inputs = try await assembler.assembleInputs()
            
            // Rising scenario has meal carbs, should have some COB
            #expect(inputs.carbsOnBoard > 0)
        }
        
        @Test("IOB COB disabled")
        func iobCobDisabled() async throws {
            let mock = MockDataSource(scenario: .rising)
            
            var config = AlgorithmInputAssembler.Configuration.default
            config.calculateIOB = false
            config.calculateCOB = false
            
            let assembler = AlgorithmInputAssembler(dataSource: mock, configuration: config)
            let inputs = try await assembler.assembleInputs()
            
            #expect(inputs.insulinOnBoard == 0)
            #expect(inputs.carbsOnBoard == 0)
        }
    }
    
    // MARK: - Metadata Tests
    
    @Suite("Metadata")
    struct Metadata {
        @Test("Assemble with metadata")
        func assembleWithMetadata() async throws {
            let mock = MockDataSource(scenario: .stable120)
            let assembler = AlgorithmInputAssembler(dataSource: mock)
            
            let result = try await assembler.assembleWithMetadata()
            
            #expect(!result.inputs.glucose.isEmpty)
            #expect(result.assemblyDuration >= 0)
            #expect(result.glucoseCount == 36)
            #expect(result.loopSettingsApplied)
        }
    }
    
    // MARK: - Scenario Integration Tests
    
    @Test("All scenarios produce valid inputs", arguments: MockDataSource.GlucoseScenario.allCases)
    func allScenariosProduceValidInputs(scenario: MockDataSource.GlucoseScenario) async throws {
        let mock = MockDataSource(scenario: scenario)
        let assembler = AlgorithmInputAssembler(dataSource: mock)
        
        let inputs = try await assembler.assembleInputs()
        
        #expect(!inputs.glucose.isEmpty, "Scenario \(scenario) should have glucose")
        #expect(inputs.doseHistory != nil, "Scenario \(scenario) should have dose history")
        #expect(inputs.insulinOnBoard >= 0, "Scenario \(scenario) IOB should be non-negative")
        #expect(inputs.carbsOnBoard >= 0, "Scenario \(scenario) COB should be non-negative")
    }
}
