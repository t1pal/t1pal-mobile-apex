// SPDX-License-Identifier: MIT
//
// CGMSourceSwitcherTests.swift
// T1Pal Mobile
//
// Tests for CGM source switching
// Requirements: DEBUG-ETU-003

import Testing
import Foundation
@testable import CGMKit
@testable import T1PalCore

@Suite("CGM Source Switcher")
struct CGMSourceSwitcherTests {
    
    @Test("Register sources")
    func registerSources() async throws {
        let switcher = CGMSourceSwitcher()
        
        let sim1 = SimulationCGM()
        let sim2 = SimulationCGM()
        
        await switcher.register(id: "sim1", name: "Simulation 1", source: sim1)
        await switcher.register(id: "sim2", name: "Simulation 2", source: sim2)
        
        let ids = await switcher.registeredSourceIds
        #expect(ids.count == 2)
        #expect(ids.contains("sim1"))
        #expect(ids.contains("sim2"))
    }
    
    @Test("Get source name")
    func getSourceName() async throws {
        let switcher = CGMSourceSwitcher()
        let sim = SimulationCGM()
        
        await switcher.register(id: "test", name: "Test Source", source: sim)
        
        let name = await switcher.sourceName(for: "test")
        #expect(name == "Test Source")
    }
    
    @Test("Switch to source by ID")
    func switchById() async throws {
        let switcher = CGMSourceSwitcher()
        
        let sim1 = SimulationCGM()
        let sim2 = SimulationCGM()
        
        await switcher.register(id: "sim1", name: "Simulation 1", source: sim1)
        await switcher.register(id: "sim2", name: "Simulation 2", source: sim2)
        
        try await switcher.switchTo(id: "sim1")
        
        let currentId = await switcher.currentSourceId
        #expect(currentId == "sim1")
    }
    
    @Test("Switch to source by index")
    func switchByIndex() async throws {
        let switcher = CGMSourceSwitcher()
        
        let sim1 = SimulationCGM()
        let sim2 = SimulationCGM()
        
        await switcher.register(id: "a_first", name: "First", source: sim1)
        await switcher.register(id: "b_second", name: "Second", source: sim2)
        
        try await switcher.switchTo(index: 1)
        
        let currentId = await switcher.currentSourceId
        #expect(currentId == "b_second")
    }
    
    @Test("Cycle through sources")
    func cycleNext() async throws {
        let switcher = CGMSourceSwitcher()
        
        let sim1 = SimulationCGM()
        let sim2 = SimulationCGM()
        let sim3 = SimulationCGM()
        
        await switcher.register(id: "a", name: "A", source: sim1)
        await switcher.register(id: "b", name: "B", source: sim2)
        await switcher.register(id: "c", name: "C", source: sim3)
        
        // First cycle - starts at first source
        try await switcher.cycleNext()
        var currentId = await switcher.currentSourceId
        #expect(currentId == "a")
        
        // Second cycle
        try await switcher.cycleNext()
        currentId = await switcher.currentSourceId
        #expect(currentId == "b")
        
        // Third cycle
        try await switcher.cycleNext()
        currentId = await switcher.currentSourceId
        #expect(currentId == "c")
        
        // Fourth cycle - wraps to first
        try await switcher.cycleNext()
        currentId = await switcher.currentSourceId
        #expect(currentId == "a")
    }
    
    @Test("Switch throws for unknown source")
    func switchUnknownThrows() async throws {
        let switcher = CGMSourceSwitcher()
        
        do {
            try await switcher.switchTo(id: "nonexistent")
            Issue.record("Should have thrown")
        } catch let error as CGMError {
            #expect(error == CGMError.deviceNotFound)
        }
    }
    
    @Test("Unregister source")
    func unregisterSource() async throws {
        let switcher = CGMSourceSwitcher()
        let sim = SimulationCGM()
        
        await switcher.register(id: "test", name: "Test", source: sim)
        var ids = await switcher.registeredSourceIds
        #expect(ids.count == 1)
        
        await switcher.unregister(id: "test")
        ids = await switcher.registeredSourceIds
        #expect(ids.count == 0)
    }
    
    @Test("Sensor state follows active source")
    func sensorStateFollowsSource() async throws {
        let switcher = CGMSourceSwitcher()
        let sim = SimulationCGM()
        
        await switcher.register(id: "sim", name: "Sim", source: sim)
        
        var initialState = await switcher.sensorState
        #expect(initialState == .notStarted)
        
        try await switcher.switchTo(id: "sim")
        
        let activeState = await switcher.sensorState
        #expect(activeState == .active)
    }
    
    @Test("Source switched callback fires")
    func sourceSwitchedCallback() async throws {
        let switcher = CGMSourceSwitcher()
        let sim = SimulationCGM()
        
        await switcher.register(id: "sim", name: "Sim", source: sim)
        
        // Use actor to track callback
        let tracker = CallbackTracker()
        
        await switcher.setOnSourceSwitched { id in
            Task {
                await tracker.record(id)
            }
        }
        
        try await switcher.switchTo(id: "sim")
        
        // Give callback time to fire
        try await Task.sleep(nanoseconds: 50_000_000)
        
        let recorded = await tracker.lastId
        #expect(recorded == "sim")
    }
    
    @Test("Disconnect stops active source")
    func disconnectStopsActive() async throws {
        let switcher = CGMSourceSwitcher()
        let sim = SimulationCGM()
        
        await switcher.register(id: "sim", name: "Sim", source: sim)
        try await switcher.switchTo(id: "sim")
        
        await switcher.disconnect()
        
        let currentId = await switcher.currentSourceId
        let state = await switcher.sensorState
        
        #expect(currentId == nil)
        #expect(state == .stopped)
    }
    
    @Test("Register using RegisteredCGMSource struct")
    func registerWithStruct() async throws {
        let sim = SimulationCGM()
        let registered = RegisteredCGMSource(id: "test", name: "Test CGM", source: sim)
        
        let switcher = CGMSourceSwitcher()
        await switcher.register(registered)
        
        let name = await switcher.sourceName(for: "test")
        #expect(name == "Test CGM")
    }
    
    @Test("Create with sources convenience")
    func createWithSources() async throws {
        let sources = [
            RegisteredCGMSource(id: "a", name: "A", source: SimulationCGM()),
            RegisteredCGMSource(id: "b", name: "B", source: SimulationCGM())
        ]
        
        let switcher = await CGMSourceSwitcher.withSources(sources)
        let ids = await switcher.registeredSourceIds
        
        #expect(ids.count == 2)
    }
    
    @Test("Summary shows source count")
    func summaryOutput() async throws {
        let switcher = CGMSourceSwitcher()
        await switcher.register(id: "sim", name: "Sim", source: SimulationCGM())
        
        let summary = await switcher.summary
        #expect(summary.contains("1 sources"))
        #expect(summary.contains("active=none"))
    }
}

// Helper actor to track callbacks
private actor CallbackTracker {
    var lastId: String?
    
    func record(_ id: String) {
        lastId = id
    }
}

// Extension to allow setting callback
extension CGMSourceSwitcher {
    func setOnSourceSwitched(_ callback: @escaping @Sendable (String) -> Void) {
        self.onSourceSwitched = callback
    }
}
