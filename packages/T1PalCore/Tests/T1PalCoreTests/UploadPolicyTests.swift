/// Tests for UploadPolicy
/// AID-PARTIAL-006 verification: CGM always uploads regardless of pump state

import XCTest
@testable import T1PalCore

final class UploadPolicyTests: XCTestCase {
    
    // MARK: - CGM Always Uploads Tests (Critical)
    
    func testCGMUploadsInCGMOnlyMode() {
        let policy = UploadPolicy.for(mode: .cgmOnly)
        
        XCTAssertTrue(policy.shouldUploadCGM, "CGM must upload in cgmOnly mode")
    }
    
    func testCGMUploadsInOpenLoopMode() {
        let policy = UploadPolicy.for(mode: .openLoop)
        
        XCTAssertTrue(policy.shouldUploadCGM, "CGM must upload in openLoop mode")
    }
    
    func testCGMUploadsInTempBasalOnlyMode() {
        let policy = UploadPolicy.for(mode: .tempBasalOnly)
        
        XCTAssertTrue(policy.shouldUploadCGM, "CGM must upload in tempBasalOnly mode")
    }
    
    func testCGMUploadsInClosedLoopMode() {
        let policy = UploadPolicy.for(mode: .closedLoop)
        
        XCTAssertTrue(policy.shouldUploadCGM, "CGM must upload in closedLoop mode")
    }
    
    func testCGMUploadsWhenPumpDisconnected() {
        let policy = UploadPolicy.pumpDisconnected
        
        XCTAssertTrue(policy.shouldUploadCGM, "CGM must upload even when pump disconnected")
    }
    
    func testAllModesCGMUploads() {
        // Critical test: verify CGM uploads in ALL modes
        for mode in LoopMode.allCases {
            let policy = UploadPolicy.for(mode: mode)
            XCTAssertTrue(policy.shouldUploadCGM, "CGM must upload in \(mode) mode")
        }
    }
    
    // MARK: - Mode-Specific Policy Tests
    
    func testCGMOnlyModeNoTreatments() {
        let policy = UploadPolicy.cgmOnly
        
        XCTAssertFalse(policy.shouldUploadTreatments, "CGM-only has no treatments")
        XCTAssertFalse(policy.shouldUploadPredictions, "CGM-only has no predictions")
        XCTAssertFalse(policy.shouldUploadPumpData, "CGM-only has no pump")
        XCTAssertTrue(policy.shouldUploadDeviceStatus, "Device status should upload")
    }
    
    func testOpenLoopModeFull() {
        let policy = UploadPolicy.openLoop
        
        XCTAssertTrue(policy.shouldUploadCGM)
        XCTAssertTrue(policy.shouldUploadTreatments)
        XCTAssertTrue(policy.shouldUploadPredictions)
        XCTAssertTrue(policy.shouldUploadPumpData)
    }
    
    func testClosedLoopModeFull() {
        let policy = UploadPolicy.closedLoop
        
        XCTAssertTrue(policy.shouldUploadCGM)
        XCTAssertTrue(policy.shouldUploadTreatments)
        XCTAssertTrue(policy.shouldUploadPredictions)
        XCTAssertTrue(policy.shouldUploadPumpData)
    }
    
    func testDisabledPolicyNoUploads() {
        let policy = UploadPolicy.disabled
        
        XCTAssertFalse(policy.shouldUploadCGM)
        XCTAssertFalse(policy.shouldUploadTreatments)
        XCTAssertFalse(policy.shouldUploadDeviceStatus)
        XCTAssertFalse(policy.shouldUploadPredictions)
        XCTAssertFalse(policy.shouldUploadPumpData)
    }
    
    func testPumpDisconnectedDegradation() {
        let policy = UploadPolicy.pumpDisconnected
        
        XCTAssertTrue(policy.shouldUploadCGM, "CGM always uploads")
        XCTAssertTrue(policy.shouldUploadDeviceStatus, "Report disconnected status")
        XCTAssertFalse(policy.shouldUploadTreatments, "Can't enact without pump")
        XCTAssertFalse(policy.shouldUploadPredictions, "Predictions stale")
        XCTAssertFalse(policy.shouldUploadPumpData, "No pump data")
    }
    
    // MARK: - Policy Evaluator Tests
    
    func testEvaluatorCGMOnlyMode() {
        let evaluator = UploadPolicyEvaluator(
            loopMode: .cgmOnly,
            isPumpConnected: false,
            isCGMConnected: true
        )
        
        XCTAssertTrue(evaluator.shouldUploadCGM)
        XCTAssertEqual(evaluator.effectivePolicy.policyName, "cgmOnly")
    }
    
    func testEvaluatorClosedLoopWithPump() {
        let evaluator = UploadPolicyEvaluator(
            loopMode: .closedLoop,
            isPumpConnected: true,
            isCGMConnected: true
        )
        
        XCTAssertEqual(evaluator.effectivePolicy.policyName, "closedLoop")
        XCTAssertTrue(evaluator.shouldUploadTreatments)
    }
    
    func testEvaluatorClosedLoopPumpDisconnected() {
        let evaluator = UploadPolicyEvaluator(
            loopMode: .closedLoop,
            isPumpConnected: false,
            isCGMConnected: true
        )
        
        // Degrades to pumpDisconnected policy
        XCTAssertEqual(evaluator.effectivePolicy.policyName, "pumpDisconnected")
        XCTAssertTrue(evaluator.shouldUploadCGM, "CGM still uploads")
        XCTAssertFalse(evaluator.shouldUploadTreatments, "Treatments disabled")
    }
    
    func testEvaluatorUploadsDisabled() {
        let evaluator = UploadPolicyEvaluator(
            loopMode: .closedLoop,
            isPumpConnected: true,
            isCGMConnected: true,
            uploadsEnabled: false
        )
        
        XCTAssertEqual(evaluator.effectivePolicy.policyName, "disabled")
        XCTAssertFalse(evaluator.shouldUploadCGM)
    }
    
    func testEvaluatorCGMDisconnected() {
        let evaluator = UploadPolicyEvaluator(
            loopMode: .closedLoop,
            isPumpConnected: true,
            isCGMConnected: false
        )
        
        // No CGM = nothing to upload
        XCTAssertEqual(evaluator.effectivePolicy.policyName, "disabled")
    }
    
    func testEvaluatorOpenLoopPumpDisconnectedStillUploads() {
        // Open loop doesn't require pump, so pump disconnect doesn't degrade
        let evaluator = UploadPolicyEvaluator(
            loopMode: .openLoop,
            isPumpConnected: false,
            isCGMConnected: true
        )
        
        // openLoop requires pump, so it degrades
        XCTAssertEqual(evaluator.effectivePolicy.policyName, "pumpDisconnected")
        XCTAssertTrue(evaluator.shouldUploadCGM)
    }
    
    func testEvaluatorCGMOnlyNoPumpNoDegradation() {
        // CGM-only mode doesn't require pump
        let evaluator = UploadPolicyEvaluator(
            loopMode: .cgmOnly,
            isPumpConnected: false,
            isCGMConnected: true
        )
        
        // Should remain cgmOnly, not degrade
        XCTAssertEqual(evaluator.effectivePolicy.policyName, "cgmOnly")
    }
    
    // MARK: - Upload Decision Tests
    
    func testUploadDecisionsFromClosedLoop() {
        let policy = UploadPolicy.closedLoop
        let decisions = UploadDecision.from(policy: policy, policySource: "closedLoop")
        
        XCTAssertEqual(decisions.count, 5)
        
        let cgmDecision = decisions.first { $0.dataType == .cgmGlucose }
        XCTAssertNotNil(cgmDecision)
        XCTAssertTrue(cgmDecision!.allowed)
    }
    
    func testUploadDecisionsFromCGMOnly() {
        let policy = UploadPolicy.cgmOnly
        let decisions = UploadDecision.from(policy: policy, policySource: "cgmOnly")
        
        let cgmDecision = decisions.first { $0.dataType == .cgmGlucose }
        XCTAssertTrue(cgmDecision!.allowed, "CGM should be allowed")
        
        let treatmentDecision = decisions.first { $0.dataType == .treatments }
        XCTAssertFalse(treatmentDecision!.allowed, "Treatments should not be allowed")
    }
    
    // MARK: - Policy Name Tests
    
    func testPolicyNames() {
        XCTAssertEqual(UploadPolicy.cgmOnly.policyName, "cgmOnly")
        XCTAssertEqual(UploadPolicy.openLoop.policyName, "openLoop")
        XCTAssertEqual(UploadPolicy.closedLoop.policyName, "closedLoop")
        XCTAssertEqual(UploadPolicy.disabled.policyName, "disabled")
        XCTAssertEqual(UploadPolicy.pumpDisconnected.policyName, "pumpDisconnected")
    }
    
    // MARK: - Description Tests
    
    func testPolicyDescription() {
        let policy = UploadPolicy.closedLoop
        let description = policy.description
        
        XCTAssertTrue(description.contains("closedLoop"))
        XCTAssertTrue(description.contains("CGM=true"))
    }
    
    func testEvaluatorDescription() {
        let evaluator = UploadPolicyEvaluator(
            loopMode: .closedLoop,
            isPumpConnected: true,
            isCGMConnected: true
        )
        
        let description = evaluator.description
        XCTAssertTrue(description.contains("closedLoop"))
    }
    
    // MARK: - Equatable Tests
    
    func testPolicyEquatable() {
        let policy1 = UploadPolicy.closedLoop
        let policy2 = UploadPolicy.for(mode: .closedLoop)
        
        XCTAssertEqual(policy1, policy2)
    }
    
    func testDecisionEquatable() {
        let decision1 = UploadDecision(dataType: .cgmGlucose, allowed: true, reason: "test")
        let decision2 = UploadDecision(dataType: .cgmGlucose, allowed: true, reason: "test")
        
        XCTAssertEqual(decision1, decision2)
    }
}
