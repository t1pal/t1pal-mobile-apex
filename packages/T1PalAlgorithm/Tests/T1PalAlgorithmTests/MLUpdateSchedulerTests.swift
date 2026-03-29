// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MLUpdateSchedulerTests.swift
// T1PalAlgorithm
//
// Tests for ML model update scheduling.
//
// Trace: ALG-SHADOW-031

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("ML Update Scheduler")
struct MLUpdateSchedulerTests {
    
    // MARK: - Configuration Tests
    
    @Suite("Configuration")
    struct Configuration {
        @Test("Default config")
        func defaultConfig() {
            let config = MLUpdateSchedulerConfig.default
            
            #expect(config.minTrainingInterval == 86400)  // 1 day
            #expect(config.defaultTrainingInterval == 604800)  // 7 days
            #expect(config.minNewDataRows == 288)  // 1 day of data
            #expect(config.maxModelAgeDays == 90)
            #expect(config.autoScheduleEnabled)
        }
        
        @Test("Weekly config")
        func weeklyConfig() {
            let config = MLUpdateSchedulerConfig.weekly
            
            #expect(config.defaultTrainingInterval == 604800)
        }
        
        @Test("Daily config")
        func dailyConfig() {
            let config = MLUpdateSchedulerConfig.daily
            
            #expect(config.defaultTrainingInterval == 86400)
            #expect(config.minTrainingInterval == 3600)
        }
    }
    
    // MARK: - Scheduler State Tests
    
    @Suite("Scheduler State")
    struct SchedulerState {
        @Test("Initial state")
        func initialState() async {
            let scheduler = MLUpdateScheduler()
            
            let result = await scheduler.lastResult
            #expect(result == nil)
            
            let isTraining = await scheduler.isTraining
            #expect(!isTraining)
        }
        
        @Test("Reset")
        func reset() async {
            let scheduler = MLUpdateScheduler()
            
            // Import some state
            let state = MLUpdateScheduler.PersistedState(
                lastTrainingDate: Date().addingTimeInterval(-86400),
                rowCountAtLastTraining: 1000
            )
            await scheduler.importState(state)
            
            // Reset
            await scheduler.reset()
            
            let exported = await scheduler.exportState()
            #expect(exported.lastTrainingDate == nil)
            #expect(exported.rowCountAtLastTraining == 0)
        }
    }
    
    // MARK: - Status Tests
    
    @Suite("Status")
    struct Status {
        func makeTempDirectory() throws -> URL {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MLUpdateSchedulerTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            return tempDirectory
        }
        
        @Test("Status with no model")
        func statusWithNoModel() async throws {
            let tempDirectory = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: tempDirectory) }
            
            let scheduler = MLUpdateScheduler()
            let collector = MLDataCollector()
            let storageConfig = MLModelStorageConfig(baseDirectory: tempDirectory)
            let storage = MLModelStorage(config: storageConfig)
            try await storage.initialize()
            
            let status = await scheduler.status(collector: collector, storage: storage)
            
            #expect(status.isEnabled)
            #expect(status.lastTrainingDate == nil)
            #expect(status.currentModelAge == nil)
            #expect(status.newDataRowsSinceLastTraining == 0)
        }
        
        @Test("Status with disabled scheduling")
        func statusWithDisabledScheduling() async throws {
            let tempDirectory = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: tempDirectory) }
            
            let config = MLUpdateSchedulerConfig(autoScheduleEnabled: false)
            let scheduler = MLUpdateScheduler(config: config)
            let collector = MLDataCollector()
            let storageConfig = MLModelStorageConfig(baseDirectory: tempDirectory)
            let storage = MLModelStorage(config: storageConfig)
            try await storage.initialize()
            
            let status = await scheduler.status(collector: collector, storage: storage)
            
            #expect(!status.isEnabled)
            #expect(!status.isEligibleNow)
            #expect(status.eligibilityReason == .disabled)
        }
    }
    
    // MARK: - Eligibility Tests
    
    @Suite("Eligibility")
    struct Eligibility {
        func makeTempDirectory() throws -> URL {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MLUpdateSchedulerTests_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            return tempDirectory
        }
        
        @Test("Ineligible insufficient data")
        func ineligibleInsufficientData() async throws {
            let tempDirectory = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: tempDirectory) }
            
            let config = MLUpdateSchedulerConfig(minNewDataRows: 1000)
            let scheduler = MLUpdateScheduler(config: config)
            let collector = MLDataCollector()
            let storageConfig = MLModelStorageConfig(baseDirectory: tempDirectory)
            let storage = MLModelStorage(config: storageConfig)
            try await storage.initialize()
            
            let status = await scheduler.status(collector: collector, storage: storage)
            
            // No data collected, should be insufficient
            #expect(!status.isEligibleNow)
            #expect(status.eligibilityReason == .insufficientData)
        }
    }
    
    // MARK: - Persistence Tests
    
    @Suite("Persistence")
    struct Persistence {
        @Test("State persistence")
        func statePersistence() async {
            let scheduler = MLUpdateScheduler()
            
            let lastDate = Date().addingTimeInterval(-86400)
            let state = MLUpdateScheduler.PersistedState(
                lastTrainingDate: lastDate,
                rowCountAtLastTraining: 5000
            )
            
            await scheduler.importState(state)
            
            let exported = await scheduler.exportState()
            #expect(abs((exported.lastTrainingDate?.timeIntervalSince1970 ?? 0) - lastDate.timeIntervalSince1970) < 1)
            #expect(exported.rowCountAtLastTraining == 5000)
        }
    }
    
    // MARK: - Schedule Calculation Tests
    
    @Suite("Schedule Calculation")
    struct ScheduleCalculation {
        @Test("Next scheduled date with no history")
        func nextScheduledDateWithNoHistory() async {
            let scheduler = MLUpdateScheduler()
            
            let nextDate = await scheduler.nextScheduledDate()
            
            // Should schedule for now if never trained
            #expect(nextDate != nil)
            #expect(abs(nextDate!.timeIntervalSinceNow) < 5)
        }
        
        @Test("Next scheduled date with history")
        func nextScheduledDateWithHistory() async {
            let config = MLUpdateSchedulerConfig(defaultTrainingInterval: 604800)  // Weekly
            let scheduler = MLUpdateScheduler(config: config)
            
            let lastDate = Date().addingTimeInterval(-86400)  // 1 day ago
            await scheduler.importState(MLUpdateScheduler.PersistedState(
                lastTrainingDate: lastDate,
                rowCountAtLastTraining: 1000
            ))
            
            let nextDate = await scheduler.nextScheduledDate()
            
            // Should be 6 days from now (7 days - 1 day elapsed)
            #expect(nextDate != nil)
            let expectedInterval: TimeInterval = 604800 - 86400  // 6 days in seconds
            #expect(abs(nextDate!.timeIntervalSinceNow - expectedInterval) < 60)
        }
        
        @Test("Days until next training")
        func daysUntilNextTraining() async {
            let config = MLUpdateSchedulerConfig(defaultTrainingInterval: 604800)
            let scheduler = MLUpdateScheduler(config: config)
            
            let lastDate = Date().addingTimeInterval(-86400 * 3)  // 3 days ago
            await scheduler.importState(MLUpdateScheduler.PersistedState(
                lastTrainingDate: lastDate,
                rowCountAtLastTraining: 1000
            ))
            
            let days = await scheduler.daysUntilNextTraining()
            
            // 7 days total - 3 elapsed ≈ 3-4 days remaining (depends on time of day)
            #expect(days != nil)
            #expect(days! >= 3 && days! <= 4, "Expected 3-4 days, got \(days!)")
        }
    }
    
    // MARK: - Training Trigger Tests
    
    @Test("Training trigger types")
    func trainingTriggerTypes() {
        #expect(TrainingTrigger.scheduled.rawValue == "Scheduled")
        #expect(TrainingTrigger.manual.rawValue == "Manual")
        #expect(TrainingTrigger.modelExpired.rawValue == "Model expired")
        #expect(TrainingTrigger.dataThreshold.rawValue == "Data threshold reached")
    }
    
    // MARK: - Background Scheduling Tests
    
    @Test("Start and stop scheduling")
    func startAndStopScheduling() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLUpdateSchedulerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        
        let scheduler = MLUpdateScheduler()
        let collector = MLDataCollector()
        let pipelineConfig = MLTrainingPipelineConfig(minTrainingRows: 100)
        let pipeline = MLTrainingPipeline(config: pipelineConfig)
        let storageConfig = MLModelStorageConfig(baseDirectory: tempDirectory)
        let storage = MLModelStorage(config: storageConfig)
        try await storage.initialize()
        
        // Start scheduling with short interval
        await scheduler.startScheduling(
            collector: collector,
            pipeline: pipeline,
            storage: storage,
            checkInterval: 0.1  // Very short for testing
        )
        
        // Let it run briefly
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        
        // Stop
        await scheduler.stopScheduling()
        
        // Should not be training after stop
        let isTraining = await scheduler.isTraining
        #expect(!isTraining)
    }
}
