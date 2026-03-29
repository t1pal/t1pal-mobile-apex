// ProposalBenchmarkTests.swift - Agent proposal storage size and performance benchmarks
// Part of NightscoutKitTests
// Trace: BENCH-PROP-001, BENCH-PROP-002, BENCH-PROP-003

import Foundation
import Testing
@testable import NightscoutKit
import T1PalCore
#if canImport(CoreFoundation)
import CoreFoundation
#endif

// MARK: - Synthetic Proposal Generator

enum ProposalGenerator {
    
    /// Create a synthetic override proposal
    static func createOverrideProposal(
        agentId: String = "exercise-agent",
        agentName: String = "Exercise Mode Agent"
    ) -> AgentProposal {
        AgentProposal(
            id: UUID(),
            timestamp: Date(),
            agentId: agentId,
            agentName: agentName,
            proposalType: .override,
            description: "Suggest exercise mode override for 2 hours",
            rationale: "Detected elevated heart rate (145 bpm) and scheduled workout in calendar. Pre-emptive target raise to prevent hypoglycemia during activity.",
            expiresAt: Date().addingTimeInterval(3600), // 1 hour expiry
            status: .pending,
            proposedOverride: ProposedOverride(
                name: "Exercise Mode",
                duration: 7200, // 2 hours
                targetRange: 140...160,
                insulinSensitivityMultiplier: 1.5,
                carbRatioMultiplier: nil,
                basalMultiplier: 0.5
            ),
            proposedTempTarget: nil
        )
    }
    
    /// Create a synthetic temp target proposal
    static func createTempTargetProposal(
        agentId: String = "meal-agent",
        agentName: String = "Meal Anticipation Agent"
    ) -> AgentProposal {
        AgentProposal(
            id: UUID(),
            timestamp: Date(),
            agentId: agentId,
            agentName: agentName,
            proposalType: .tempTarget,
            description: "Suggest pre-meal target for upcoming carbs",
            rationale: "Based on typical meal timing patterns, a pre-meal target helps build insulin on board before eating.",
            expiresAt: Date().addingTimeInterval(1800), // 30 min expiry
            status: .pending,
            proposedOverride: nil,
            proposedTempTarget: ProposedTempTarget(
                targetRange: 80...100,
                duration: 3600, // 1 hour
                reason: "Pre-meal"
            )
        )
    }
    
    /// Create a synthetic suspend proposal
    static func createSuspendProposal() -> AgentProposal {
        AgentProposal(
            id: UUID(),
            timestamp: Date(),
            agentId: "hypo-prevention-agent",
            agentName: "Hypoglycemia Prevention Agent",
            proposalType: .suspendDelivery,
            description: "Suggest temporary insulin suspension",
            rationale: "Rapidly falling glucose trend (-3 mg/dL/min) with low IOB. Suspend recommended to prevent hypoglycemia.",
            expiresAt: Date().addingTimeInterval(600), // 10 min expiry
            status: .pending,
            proposedOverride: nil,
            proposedTempTarget: nil
        )
    }
    
    /// Create reviewed/executed proposal with audit trail
    static func createReviewedProposal() -> AgentProposal {
        var proposal = createOverrideProposal()
        proposal.approve(by: "user@example.com", note: "Approved for afternoon workout")
        return proposal
    }
}

// MARK: - Size Benchmarks (BENCH-PROP-001)

@Suite("Proposal Size Benchmarks")
struct ProposalSizeBenchmarkTests {
    
    @Test("Measure override proposal size")
    func measureOverrideProposalSize() throws {
        let proposal = ProposalGenerator.createOverrideProposal()
        let encoder = JSONEncoder()
        let data = try encoder.encode(proposal)
        
        let sizeBytes = data.count
        print("[BENCH] Override proposal: \(sizeBytes) bytes")
        
        // Expected: 500-1000 bytes based on LIVE-BACKLOG notes
        #expect(sizeBytes > 300, "Override proposal should be > 300 bytes")
        #expect(sizeBytes < 2000, "Override proposal should be < 2KB")
    }
    
    @Test("Measure temp target proposal size")
    func measureTempTargetProposalSize() throws {
        let proposal = ProposalGenerator.createTempTargetProposal()
        let encoder = JSONEncoder()
        let data = try encoder.encode(proposal)
        
        let sizeBytes = data.count
        print("[BENCH] Temp target proposal: \(sizeBytes) bytes")
        
        #expect(sizeBytes > 300, "Temp target proposal should be > 300 bytes")
        #expect(sizeBytes < 1500, "Temp target proposal should be < 1.5KB")
    }
    
    @Test("Measure suspend proposal size")
    func measureSuspendProposalSize() throws {
        let proposal = ProposalGenerator.createSuspendProposal()
        let encoder = JSONEncoder()
        let data = try encoder.encode(proposal)
        
        let sizeBytes = data.count
        print("[BENCH] Suspend proposal: \(sizeBytes) bytes")
        
        // Minimal proposal (no override/tempTarget)
        #expect(sizeBytes > 200, "Suspend proposal should be > 200 bytes")
        #expect(sizeBytes < 1000, "Suspend proposal should be < 1KB")
    }
    
    @Test("Measure reviewed proposal with audit trail")
    func measureReviewedProposalSize() throws {
        let proposal = ProposalGenerator.createReviewedProposal()
        let encoder = JSONEncoder()
        let data = try encoder.encode(proposal)
        
        let sizeBytes = data.count
        print("[BENCH] Reviewed proposal: \(sizeBytes) bytes")
        
        // Reviewed adds ~50-100 bytes for reviewer/timestamp/note
        #expect(sizeBytes > 400, "Reviewed proposal should be > 400 bytes")
        #expect(sizeBytes < 2500, "Reviewed proposal should be < 2.5KB")
    }
    
    @Test("Measure average proposal size")
    func measureAverageProposalSize() throws {
        let proposals: [AgentProposal] = [
            ProposalGenerator.createOverrideProposal(),
            ProposalGenerator.createTempTargetProposal(),
            ProposalGenerator.createSuspendProposal(),
            ProposalGenerator.createReviewedProposal()
        ]
        
        let encoder = JSONEncoder()
        let totalSize = try proposals.reduce(0) { acc, p in
            acc + (try encoder.encode(p)).count
        }
        let avgSize = totalSize / proposals.count
        
        print("[BENCH] Average proposal size: \(avgSize) bytes")
        print("[BENCH] Total for \(proposals.count) proposals: \(totalSize) bytes")
        
        // Document finding for PERSISTENCE-DATA-PATTERNS.md
        #expect(avgSize > 300, "Average should be > 300 bytes")
        #expect(avgSize < 1500, "Average should be < 1.5KB")
    }
}

// MARK: - Volume Estimates (BENCH-PROP-002)

@Suite("Proposal Volume Estimates")
struct ProposalVolumeEstimateTests {
    
    @Test("Estimate daily proposal storage")
    func estimateDailyProposalStorage() throws {
        // Scenario: Active agent producing 10-50 proposals/day
        let lowProposalsPerDay = 10
        let highProposalsPerDay = 50
        
        let avgProposalSize = 700 // bytes, from size benchmarks
        
        let lowDailyKB = (lowProposalsPerDay * avgProposalSize) / 1024
        let highDailyKB = (highProposalsPerDay * avgProposalSize) / 1024
        
        print("[BENCH] Daily proposals (low): \(lowProposalsPerDay) = \(lowDailyKB) KB")
        print("[BENCH] Daily proposals (high): \(highProposalsPerDay) = \(highDailyKB) KB")
        
        // Low: 10 * 700 = 7 KB/day
        // High: 50 * 700 = 35 KB/day
        #expect(lowDailyKB < 50, "Low activity should be < 50 KB/day")
        #expect(highDailyKB < 100, "High activity should be < 100 KB/day")
    }
    
    @Test("Estimate 90-day proposal storage")
    func estimate90DayProposalStorage() throws {
        // 90-day retention per BENCH-PROP-004
        let proposalsPerDay = 30 // moderate activity
        let avgProposalSize = 700 // bytes
        
        let totalProposals = proposalsPerDay * 90
        let totalSizeMB = Double(totalProposals * avgProposalSize) / (1024 * 1024)
        
        print("[BENCH] 90-day proposals: \(totalProposals) records")
        print("[BENCH] 90-day storage: \(String(format: "%.2f", totalSizeMB)) MB")
        
        // 30 * 90 * 700 = 1.9 MB
        #expect(totalSizeMB < 10, "90 days should be < 10 MB")
        #expect(totalSizeMB > 0.5, "90 days should be > 0.5 MB with moderate activity")
    }
    
    @Test("Estimate proposals per agent type")
    func estimateProposalsPerAgentType() throws {
        // Different agents have different activity levels
        let agentProposalsPerDay: [(String, Int)] = [
            ("exercise-agent", 2),      // 1-2 workouts/day
            ("meal-agent", 3),          // 3 meals
            ("hypo-prevention", 5),     // Multiple IOB/COB cycles
            ("schedule-agent", 4),      // Work, sleep, custom
            ("activity-agent", 2),      // Step count triggers
        ]
        
        let totalPerDay = agentProposalsPerDay.reduce(0) { $0 + $1.1 }
        let avgProposalSize = 700
        let dailyKB = (totalPerDay * avgProposalSize) / 1024
        
        print("[BENCH] Agent breakdown:")
        for (agent, count) in agentProposalsPerDay {
            print("  - \(agent): \(count)/day")
        }
        print("[BENCH] Total proposals/day: \(totalPerDay)")
        print("[BENCH] Daily storage: \(dailyKB) KB")
        
        #expect(totalPerDay >= 10, "Expect 10+ proposals/day with active agents")
        #expect(totalPerDay <= 50, "Expect <50 proposals/day typical")
    }
}

// MARK: - Audit Trail Storage (BENCH-PROP-003)

@Suite("Audit Trail Storage Benchmarks")
struct AuditTrailStorageBenchmarkTests {
    
    @Test("Measure audit entry size")
    func measureAuditEntrySize() throws {
        let entry = AgentAuditEntry(
            id: UUID(),
            timestamp: Date(),
            agentId: "exercise-agent",
            action: .proposalSubmitted,
            details: [
                "proposalId": UUID().uuidString,
                "type": "override",
                "target": "140-160"
            ],
            outcome: .success,
            userId: "user@example.com"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)
        let sizeBytes = data.count
        
        print("[BENCH] Audit entry: \(sizeBytes) bytes")
        
        // Audit entries are smaller than proposals
        #expect(sizeBytes > 150, "Audit entry should be > 150 bytes")
        #expect(sizeBytes < 500, "Audit entry should be < 500 bytes")
    }
    
    @Test("Estimate audit trail storage per proposal")
    func estimateAuditTrailPerProposal() throws {
        // Each proposal lifecycle generates multiple audit entries:
        // 1. proposalCreated
        // 2. proposalReviewed (or autoApproved)
        // 3. proposalExecuted (or expired/rejected)
        
        let entriesPerProposal = 3
        let avgEntrySize = 300 // bytes
        let auditOverheadPerProposal = entriesPerProposal * avgEntrySize
        
        print("[BENCH] Audit entries per proposal: \(entriesPerProposal)")
        print("[BENCH] Audit overhead per proposal: \(auditOverheadPerProposal) bytes")
        
        // 90-day estimate with 30 proposals/day
        let proposalsPerDay = 30
        let totalProposals = proposalsPerDay * 90
        let totalAuditMB = Double(totalProposals * auditOverheadPerProposal) / (1024 * 1024)
        
        print("[BENCH] 90-day audit trail: \(String(format: "%.2f", totalAuditMB)) MB")
        
        #expect(totalAuditMB < 5, "90-day audit trail should be < 5 MB")
    }
    
    @Test("Total storage: proposals + audit")
    func estimateTotalProposalStorage() throws {
        let proposalsPerDay = 30
        let avgProposalSize = 700 // bytes
        let entriesPerProposal = 3
        let avgEntrySize = 300 // bytes
        
        let dailyProposalBytes = proposalsPerDay * avgProposalSize
        let dailyAuditBytes = proposalsPerDay * entriesPerProposal * avgEntrySize
        let dailyTotalBytes = dailyProposalBytes + dailyAuditBytes
        
        let day90MB = Double(dailyTotalBytes * 90) / (1024 * 1024)
        let day365MB = Double(dailyTotalBytes * 365) / (1024 * 1024)
        
        print("[BENCH] Daily total (proposals + audit): \(dailyTotalBytes / 1024) KB")
        print("[BENCH] 90-day total: \(String(format: "%.2f", day90MB)) MB")
        print("[BENCH] 365-day total: \(String(format: "%.2f", day365MB)) MB")
        
        // Reasonable for local storage
        #expect(day90MB < 10, "90-day total should be < 10 MB")
        #expect(day365MB < 50, "365-day total should be < 50 MB")
    }
}
