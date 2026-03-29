// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ExerciseModeTests.swift
// T1Pal Mobile
//
// Tests for exercise mode provider
// Trace: GLUCOS-IMPL-004

import Testing
import Foundation
@testable import T1PalAlgorithm

@Suite("Exercise Mode Provider")
struct ExerciseModeProviderTests {
    
    // MARK: - Basic State
    
    @Suite("Basic State")
    struct BasicState {
        @Test("Initial state is inactive")
        func initialStateInactive() async {
            let provider = ExerciseModeProvider(
                storage: InMemoryExerciseStorage()
            )
            
            let state = await provider.state
            #expect(state == .inactive)
        }
        
        @Test("Start exercise")
        func startExercise() async {
            let provider = ExerciseModeProvider(
                storage: InMemoryExerciseStorage()
            )
            
            await provider.startExercise()
            
            let state = await provider.state
            #expect(state == .active)
            
            let isExercising = await provider.isExercising(at: Date())
            #expect(isExercising)
        }
        
        @Test("End exercise")
        func endExercise() async {
            let provider = ExerciseModeProvider(
                storage: InMemoryExerciseStorage()
            )
            
            await provider.startExercise()
            await provider.endExercise()
            
            let state = await provider.state
            #expect(state == .inactive)
            
            let isExercising = await provider.isExercising(at: Date())
            #expect(!isExercising)
        }
    }
    
    // MARK: - Expiration
    
    @Suite("Expiration")
    struct Expiration {
        @Test("Exercise expires")
        func exerciseExpires() async {
            let settings = ExerciseModeSettings(
                expirationInterval: 60  // 1 minute for testing
            )
            let provider = ExerciseModeProvider(
                settings: settings,
                storage: InMemoryExerciseStorage()
            )
            
            await provider.startExercise()
            
            // Check immediately - should be exercising
            let isExercisingNow = await provider.isExercising(at: Date())
            #expect(isExercisingNow)
            
            // Check after expiration - should not be exercising
            let futureDate = Date().addingTimeInterval(120)  // 2 minutes later
            let isExercisingLater = await provider.isExercising(at: futureDate)
            #expect(!isExercisingLater)
        }
    }
    
    // MARK: - Target Adjustment
    
    @Suite("Target Adjustment")
    struct TargetAdjustment {
        @Test("Effective target during exercise")
        func effectiveTargetDuringExercise() async {
            let settings = ExerciseModeSettings(
                adjustTargetDuringExercise: true,
                exerciseTargetGlucose: 140
            )
            let provider = ExerciseModeProvider(
                settings: settings,
                storage: InMemoryExerciseStorage()
            )
            
            await provider.startExercise()
            
            let effectiveTarget = await provider.effectiveTarget(baseTarget: 100, at: Date())
            #expect(effectiveTarget == 140)
        }
        
        @Test("Effective target not lowered")
        func effectiveTargetNotLowered() async {
            let settings = ExerciseModeSettings(
                adjustTargetDuringExercise: true,
                exerciseTargetGlucose: 140
            )
            let provider = ExerciseModeProvider(
                settings: settings,
                storage: InMemoryExerciseStorage()
            )
            
            await provider.startExercise()
            
            // If base target is higher than exercise target, use base
            let effectiveTarget = await provider.effectiveTarget(baseTarget: 160, at: Date())
            #expect(effectiveTarget == 160)
        }
        
        @Test("Effective target when not exercising")
        func effectiveTargetWhenNotExercising() async {
            let settings = ExerciseModeSettings(
                adjustTargetDuringExercise: true,
                exerciseTargetGlucose: 140
            )
            let provider = ExerciseModeProvider(
                settings: settings,
                storage: InMemoryExerciseStorage()
            )
            
            // Not exercising
            let effectiveTarget = await provider.effectiveTarget(baseTarget: 100, at: Date())
            #expect(effectiveTarget == 100)
        }
        
        @Test("Effective target when disabled")
        func effectiveTargetWhenDisabled() async {
            let settings = ExerciseModeSettings(
                adjustTargetDuringExercise: false,
                exerciseTargetGlucose: 140
            )
            let provider = ExerciseModeProvider(
                settings: settings,
                storage: InMemoryExerciseStorage()
            )
            
            await provider.startExercise()
            
            // Should not adjust even when exercising
            let effectiveTarget = await provider.effectiveTarget(baseTarget: 100, at: Date())
            #expect(effectiveTarget == 100)
        }
    }
    
    // MARK: - Watch Message
    
    @Suite("Watch Message")
    struct WatchMessage {
        @Test("Handle watch message started")
        func handleWatchMessageStarted() async {
            let provider = ExerciseModeProvider(
                storage: InMemoryExerciseStorage()
            )
            
            let message = ExerciseWatchMessage(type: .started)
            await provider.handleWatchMessage(message)
            
            let state = await provider.state
            #expect(state == .active)
        }
        
        @Test("Handle watch message ended")
        func handleWatchMessageEnded() async {
            let provider = ExerciseModeProvider(
                storage: InMemoryExerciseStorage()
            )
            
            await provider.startExercise()
            
            let message = ExerciseWatchMessage(type: .ended)
            await provider.handleWatchMessage(message)
            
            let state = await provider.state
            #expect(state == .inactive)
        }
    }
}

// MARK: - In-Memory Storage

final class InMemoryExerciseStorage: ExerciseModeStorage, @unchecked Sendable {
    private var state: ExercisePersistentState?
    
    func saveState(_ state: ExercisePersistentState) {
        self.state = state
    }
    
    func loadState() -> ExercisePersistentState? {
        return state
    }
}
