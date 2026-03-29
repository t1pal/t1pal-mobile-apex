// ProtocolReportTests.swift
// BLEKit Tests
//
// Tests for ProtocolReport JSON schema and related types.
// INSTR-004: ProtocolReport JSON schema

import Testing
import Foundation
@testable import BLEKit

// MARK: - Protocol Phase Tests

@Suite("Protocol Phase")
struct ProtocolPhaseTests {
    
    @Test("All phases available")
    func allPhases() {
        let phases = ProtocolPhase.allCases
        #expect(phases.contains(.discovery))
        #expect(phases.contains(.connection))
        #expect(phases.contains(.authentication))
        #expect(phases.contains(.dataExchange))
        #expect(phases.contains(.disconnection))
        #expect(phases.count >= 10)
    }
    
    @Test("Raw value encoding")
    func rawValue() {
        #expect(ProtocolPhase.discovery.rawValue == "discovery")
        #expect(ProtocolPhase.authentication.rawValue == "authentication")
    }
}

// MARK: - Phase Status Tests

@Suite("Phase Status")
struct PhaseStatusTests {
    
    @Test("All statuses available")
    func allStatuses() {
        #expect(PhaseStatus.pending.rawValue == "pending")
        #expect(PhaseStatus.inProgress.rawValue == "inProgress")
        #expect(PhaseStatus.succeeded.rawValue == "succeeded")
        #expect(PhaseStatus.failed.rawValue == "failed")
        #expect(PhaseStatus.timedOut.rawValue == "timedOut")
    }
}

// MARK: - Phase Result Tests

@Suite("Phase Result")
struct PhaseResultTests {
    
    @Test("Create phase result")
    func createResult() {
        let start = Date()
        let end = start.addingTimeInterval(1.5)
        
        let result = PhaseResult(
            phase: .connection,
            status: .succeeded,
            startTime: start,
            endTime: end
        )
        
        #expect(result.phase == .connection)
        #expect(result.status == .succeeded)
        #expect(result.isSuccess)
        #expect(!result.isFailure)
        #expect(result.durationMs == 1500)
    }
    
    @Test("Success factory")
    func successFactory() {
        let start = Date()
        let end = start.addingTimeInterval(0.5)
        
        let result = PhaseResult.success(
            phase: .authentication,
            startTime: start,
            endTime: end,
            metadata: ["key": "value"]
        )
        
        #expect(result.isSuccess)
        #expect(result.metadata["key"] == "value")
    }
    
    @Test("Failure factory")
    func failureFactory() {
        let start = Date()
        let end = start.addingTimeInterval(2.0)
        
        let result = PhaseResult.failure(
            phase: .authentication,
            startTime: start,
            endTime: end,
            errorCode: "AUTH_FAILED",
            errorMessage: "Authentication failed",
            retryCount: 2
        )
        
        #expect(result.isFailure)
        #expect(result.errorCode == "AUTH_FAILED")
        #expect(result.retryCount == 2)
    }
    
    @Test("Timeout factory")
    func timeoutFactory() {
        let start = Date()
        let end = start.addingTimeInterval(30.0)
        
        let result = PhaseResult.timeout(
            phase: .connection,
            startTime: start,
            endTime: end,
            retryCount: 3
        )
        
        #expect(result.status == .timedOut)
        #expect(result.isFailure)
        #expect(result.errorCode == "TIMEOUT")
    }
}

// MARK: - Attempt Record Tests

@Suite("Attempt Record")
struct AttemptRecordTests {
    
    @Test("Create attempt record")
    func createRecord() {
        let start = Date()
        let end = start.addingTimeInterval(5.0)
        
        let attempt = AttemptRecord(
            attemptNumber: 1,
            startTime: start,
            endTime: end,
            success: true,
            deviceId: "ABC123",
            rssi: -65
        )
        
        #expect(attempt.attemptNumber == 1)
        #expect(attempt.success)
        #expect(attempt.durationMs == 5000)
        #expect(attempt.deviceId == "ABC123")
        #expect(attempt.rssi == -65)
    }
    
    @Test("Failed phase detection")
    func failedPhase() {
        let start = Date()
        let phases = [
            PhaseResult.success(phase: .discovery, startTime: start, endTime: start.addingTimeInterval(0.5)),
            PhaseResult.failure(phase: .connection, startTime: start, endTime: start.addingTimeInterval(1.0),
                               errorCode: "CONN_FAIL", errorMessage: "Connection failed")
        ]
        
        let attempt = AttemptRecord(
            attemptNumber: 1,
            startTime: start,
            endTime: start.addingTimeInterval(1.5),
            success: false,
            phases: phases
        )
        
        #expect(attempt.failedPhase?.phase == .connection)
        #expect(attempt.completedPhases.count == 1)
    }
    
    @Test("Total retries calculation")
    func totalRetries() {
        let start = Date()
        let phases = [
            PhaseResult(phase: .discovery, status: .succeeded, startTime: start, retryCount: 1),
            PhaseResult(phase: .connection, status: .succeeded, startTime: start, retryCount: 2),
            PhaseResult(phase: .authentication, status: .succeeded, startTime: start, retryCount: 1)
        ]
        
        let attempt = AttemptRecord(
            attemptNumber: 1,
            startTime: start,
            success: true,
            phases: phases
        )
        
        #expect(attempt.totalRetries == 4)
    }
}

// MARK: - Protocol Metrics Tests

@Suite("Protocol Metrics")
struct ProtocolMetricsTests {
    
    @Test("Create metrics")
    func createMetrics() {
        let metrics = ProtocolMetrics(
            totalDurationMs: 5000,
            discoveryDurationMs: 500,
            connectionDurationMs: 1000,
            authenticationDurationMs: 2000,
            averageRssi: -70,
            retryCount: 2,
            timeoutCount: 1
        )
        
        #expect(metrics.totalDurationMs == 5000)
        #expect(metrics.discoveryDurationMs == 500)
        #expect(metrics.averageRssi == -70)
        #expect(metrics.retryCount == 2)
    }
    
    @Test("Calculate from attempts")
    func calculateFromAttempts() {
        let start = Date()
        
        let phases1 = [
            PhaseResult.success(phase: .discovery, startTime: start, endTime: start.addingTimeInterval(0.5)),
            PhaseResult.success(phase: .connection, startTime: start, endTime: start.addingTimeInterval(1.0))
        ]
        
        let phases2 = [
            PhaseResult.success(phase: .discovery, startTime: start, endTime: start.addingTimeInterval(0.3)),
            PhaseResult.success(phase: .connection, startTime: start, endTime: start.addingTimeInterval(0.8))
        ]
        
        let attempts = [
            AttemptRecord(attemptNumber: 1, startTime: start, endTime: start.addingTimeInterval(2.0),
                         success: true, phases: phases1, rssi: -60),
            AttemptRecord(attemptNumber: 2, startTime: start, endTime: start.addingTimeInterval(1.5),
                         success: true, phases: phases2, rssi: -70)
        ]
        
        let metrics = ProtocolMetrics.calculate(from: attempts)
        
        #expect(metrics.totalDurationMs == 3500)
        // Allow for floating point rounding (799-800, 1799-1800)
        #expect(metrics.discoveryDurationMs! >= 799 && metrics.discoveryDurationMs! <= 800)
        #expect(metrics.connectionDurationMs! >= 1799 && metrics.connectionDurationMs! <= 1800)
        #expect(metrics.averageRssi == -65)
        #expect(metrics.minRssi == -70)
        #expect(metrics.maxRssi == -60)
    }
    
    @Test("Empty attempts")
    func emptyAttempts() {
        let metrics = ProtocolMetrics.calculate(from: [])
        #expect(metrics.totalDurationMs == 0)
        #expect(metrics.averageRssi == nil)
    }
}

// MARK: - Device Info Tests

@Suite("Report Device Info")
struct ReportDeviceInfoTests {
    
    @Test("Create device info")
    func createDeviceInfo() {
        let info = ReportDeviceInfo(
            deviceId: "ABC123",
            name: "Dexcom G6",
            manufacturer: "Dexcom",
            model: "G6",
            firmware: "1.2.3"
        )
        
        #expect(info.deviceId == "ABC123")
        #expect(info.name == "Dexcom G6")
        #expect(info.firmware == "1.2.3")
    }
    
    @Test("Redact device info")
    func redactDeviceInfo() {
        let info = ReportDeviceInfo(
            deviceId: "ABC123",
            name: "Dexcom G6",
            manufacturer: "Dexcom",
            serialNumber: "SN12345"
        )
        
        let redacted = info.redacted()
        
        #expect(redacted.deviceId == "[REDACTED]")
        #expect(redacted.name == "[REDACTED]")
        #expect(redacted.manufacturer == "Dexcom")
        #expect(redacted.serialNumber == "[REDACTED]")
    }
}

// MARK: - Platform Info Tests

@Suite("Report Platform Info")
struct ReportPlatformInfoTests {
    
    @Test("Create platform info")
    func createPlatformInfo() {
        let info = ReportPlatformInfo(
            os: "iOS",
            osVersion: "17.0",
            appVersion: "1.0.0",
            appBuild: "42"
        )
        
        #expect(info.os == "iOS")
        #expect(info.osVersion == "17.0")
        #expect(info.appVersion == "1.0.0")
    }
    
    @Test("Current platform info")
    func currentPlatformInfo() {
        let info = ReportPlatformInfo.current(appVersion: "1.0.0")
        
        #expect(!info.os.isEmpty)
        #expect(!info.osVersion.isEmpty)
        #expect(info.appVersion == "1.0.0")
    }
}

// MARK: - Protocol Report Tests

@Suite("Protocol Report")
struct ProtocolReportTests {
    
    func makeAttempt(success: Bool) -> AttemptRecord {
        let start = Date()
        return AttemptRecord(
            attemptNumber: 1,
            startTime: start,
            endTime: start.addingTimeInterval(2.0),
            success: success,
            phases: [
                PhaseResult.success(phase: .discovery, startTime: start, endTime: start.addingTimeInterval(0.5)),
                PhaseResult.success(phase: .connection, startTime: start, endTime: start.addingTimeInterval(1.0))
            ]
        )
    }
    
    @Test("Create report")
    func createReport() {
        let report = ProtocolReport(
            protocolName: "DexcomG6",
            protocolVersion: "1.0",
            attempts: [makeAttempt(success: true)],
            success: true
        )
        
        #expect(report.protocolName == "DexcomG6")
        #expect(report.protocolVersion == "1.0")
        #expect(report.success)
        #expect(report.attemptCount == 1)
        #expect(report.schemaVersion == "1.0.0")
    }
    
    @Test("Success rate calculation")
    func successRate() {
        let report = ProtocolReport(
            protocolName: "Test",
            protocolVersion: "1.0",
            attempts: [
                makeAttempt(success: true),
                makeAttempt(success: false),
                makeAttempt(success: true)
            ],
            success: true
        )
        
        #expect(report.attemptCount == 3)
        #expect(report.successfulAttempts == 2)
        #expect(report.failedAttempts == 1)
        #expect(report.successRate > 0.66 && report.successRate < 0.67)
    }
    
    @Test("Redact report")
    func redactReport() {
        let report = ProtocolReport(
            protocolName: "Test",
            protocolVersion: "1.0",
            deviceInfo: ReportDeviceInfo(deviceId: "ABC123", name: "Device"),
            attempts: [],
            success: true
        )
        
        let redacted = report.redacted()
        
        #expect(redacted.deviceInfo?.deviceId == "[REDACTED]")
        #expect(redacted.protocolName == "Test")
    }
    
    @Test("JSON round trip")
    func jsonRoundTrip() throws {
        let report = ProtocolReport(
            protocolName: "DexcomG6",
            protocolVersion: "1.0",
            deviceInfo: ReportDeviceInfo(deviceId: "ABC", name: "Device"),
            platformInfo: ReportPlatformInfo.current(appVersion: "1.0.0"),
            attempts: [makeAttempt(success: true)],
            success: true,
            notes: "Test report",
            tags: ["test", "debug"]
        )
        
        let json = try report.toJSON()
        let decoded = try ProtocolReport.fromJSON(json)
        
        #expect(decoded.protocolName == report.protocolName)
        #expect(decoded.attemptCount == report.attemptCount)
        #expect(decoded.success == report.success)
        #expect(decoded.tags == report.tags)
    }
    
    @Test("Empty attempts success rate")
    func emptySuccessRate() {
        let report = ProtocolReport(
            protocolName: "Test",
            protocolVersion: "1.0",
            attempts: [],
            success: false
        )
        
        #expect(report.successRate == 0)
    }
}

// MARK: - Protocol Report Builder Tests

@Suite("Protocol Report Builder")
struct ProtocolReportBuilderTests {
    
    @Test("Build basic report")
    func buildBasicReport() {
        let report = ProtocolReportBuilder()
            .protocolName("DexcomG6")
            .protocolVersion("1.0")
            .build()
        
        #expect(report.protocolName == "DexcomG6")
        #expect(report.protocolVersion == "1.0")
    }
    
    @Test("Build with device info")
    func buildWithDeviceInfo() {
        let deviceInfo = ReportDeviceInfo(deviceId: "ABC", name: "Device")
        
        let report = ProtocolReportBuilder()
            .protocolName("Test")
            .protocolVersion("1.0")
            .deviceInfo(deviceInfo)
            .build()
        
        #expect(report.deviceInfo?.deviceId == "ABC")
    }
    
    @Test("Build with attempts")
    func buildWithAttempts() {
        let start = Date()
        
        let report = ProtocolReportBuilder()
            .protocolName("Test")
            .protocolVersion("1.0")
            .startAttempt()
            .recordPhase(PhaseResult.success(phase: .discovery, startTime: start, endTime: start.addingTimeInterval(0.5)))
            .recordPhase(PhaseResult.success(phase: .connection, startTime: start, endTime: start.addingTimeInterval(1.0)))
            .setDeviceId("ABC123")
            .setRssi(-65)
            .endAttempt(success: true)
            .build()
        
        #expect(report.attemptCount == 1)
        #expect(report.success)
        #expect(report.attempts.first?.deviceId == "ABC123")
        #expect(report.attempts.first?.rssi == -65)
    }
    
    @Test("Build with tags and metadata")
    func buildWithTagsAndMetadata() {
        let report = ProtocolReportBuilder()
            .protocolName("Test")
            .protocolVersion("1.0")
            .tag("debug")
            .tag("test")
            .metadata("key", "value")
            .notes("Test notes")
            .build()
        
        #expect(report.tags.contains("debug"))
        #expect(report.tags.contains("test"))
        #expect(report.metadata["key"] == "value")
        #expect(report.notes == "Test notes")
    }
    
    @Test("Multiple attempts")
    func multipleAttempts() {
        let start = Date()
        
        let report = ProtocolReportBuilder()
            .protocolName("Test")
            .protocolVersion("1.0")
            .startAttempt()
            .recordPhase(PhaseResult.failure(phase: .connection, startTime: start, endTime: start.addingTimeInterval(1.0),
                                             errorCode: "FAIL", errorMessage: "Failed"))
            .endAttempt(success: false, errorCode: "FAIL", errorMessage: "First attempt failed")
            .startAttempt()
            .recordPhase(PhaseResult.success(phase: .connection, startTime: start, endTime: start.addingTimeInterval(0.5)))
            .endAttempt(success: true)
            .build()
        
        #expect(report.attemptCount == 2)
        #expect(report.failedAttempts == 1)
        #expect(report.successfulAttempts == 1)
        #expect(report.success)
    }
}

// MARK: - Report Validation Tests

@Suite("Protocol Report Validation")
struct ProtocolReportValidationTests {
    let validator = ProtocolReportValidator()
    
    @Test("Valid report passes")
    func validReport() {
        let report = ProtocolReport(
            protocolName: "DexcomG6",
            protocolVersion: "1.0",
            attempts: [],
            success: false
        )
        
        let result = validator.validate(report)
        
        #expect(result.isValid)
        #expect(result.errors.isEmpty)
    }
    
    @Test("Empty protocol name fails")
    func emptyProtocolName() {
        let report = ProtocolReport(
            protocolName: "",
            protocolVersion: "1.0",
            attempts: [],
            success: false
        )
        
        let result = validator.validate(report)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("Protocol name") })
    }
    
    @Test("Empty protocol version fails")
    func emptyProtocolVersion() {
        let report = ProtocolReport(
            protocolName: "Test",
            protocolVersion: "",
            attempts: [],
            success: false
        )
        
        let result = validator.validate(report)
        
        #expect(!result.isValid)
        #expect(result.errors.contains { $0.contains("Protocol version") })
    }
    
    @Test("Success with no attempts warning")
    func successNoAttempts() {
        let report = ProtocolReport(
            protocolName: "Test",
            protocolVersion: "1.0",
            attempts: [],
            success: true
        )
        
        let result = validator.validate(report)
        
        #expect(result.isValid)
        #expect(result.warnings.contains { $0.contains("no attempts") })
    }
}

// MARK: - Report Summary Tests

@Suite("Protocol Report Summary")
struct ProtocolReportSummaryTests {
    
    @Test("Generate summary text")
    func generateSummary() {
        let start = Date()
        let attempt = AttemptRecord(
            attemptNumber: 1,
            startTime: start,
            endTime: start.addingTimeInterval(2.0),
            success: true,
            phases: [
                PhaseResult.success(phase: .discovery, startTime: start, endTime: start.addingTimeInterval(0.5)),
                PhaseResult.success(phase: .connection, startTime: start, endTime: start.addingTimeInterval(1.0))
            ]
        )
        
        let report = ProtocolReport(
            protocolName: "DexcomG6",
            protocolVersion: "1.0",
            deviceInfo: ReportDeviceInfo(deviceId: "ABC", name: "Device", firmware: "1.2.3"),
            attempts: [attempt],
            success: true,
            notes: "Test notes"
        )
        
        let summary = ProtocolReportSummary(report)
        let text = summary.text
        
        #expect(text.contains("DexcomG6"))
        #expect(text.contains("SUCCESS"))
        #expect(text.contains("Attempts: 1"))
        #expect(text.contains("Device"))
        #expect(text.contains("Test notes"))
    }
    
    @Test("Failed report summary")
    func failedSummary() {
        let report = ProtocolReport(
            protocolName: "Test",
            protocolVersion: "1.0",
            attempts: [],
            success: false,
            errorSummary: "Connection failed"
        )
        
        let summary = ProtocolReportSummary(report)
        let text = summary.text
        
        #expect(text.contains("FAILED"))
        #expect(text.contains("Connection failed"))
    }
}

// MARK: - Report Aggregator Tests

@Suite("Protocol Report Aggregator")
struct ProtocolReportAggregatorTests {
    let aggregator = ProtocolReportAggregator()
    
    func makeReport(protocolName: String, success: Bool, attempts: Int, successfulAttempts: Int) -> ProtocolReport {
        let start = Date()
        var attemptRecords: [AttemptRecord] = []
        
        for i in 0..<attempts {
            let isSuccess = i < successfulAttempts
            attemptRecords.append(AttemptRecord(
                attemptNumber: i + 1,
                startTime: start,
                endTime: start.addingTimeInterval(Double(i + 1)),
                success: isSuccess
            ))
        }
        
        return ProtocolReport(
            protocolName: protocolName,
            protocolVersion: "1.0",
            attempts: attemptRecords,
            success: success
        )
    }
    
    @Test("Aggregate multiple reports")
    func aggregateReports() {
        let reports = [
            makeReport(protocolName: "DexcomG6", success: true, attempts: 3, successfulAttempts: 2),
            makeReport(protocolName: "DexcomG6", success: true, attempts: 2, successfulAttempts: 2),
            makeReport(protocolName: "Libre2", success: false, attempts: 1, successfulAttempts: 0)
        ]
        
        let stats = aggregator.aggregate(reports)
        
        #expect(stats.reportCount == 3)
        #expect(stats.totalAttempts == 6)
        #expect(stats.successfulAttempts == 4)
        #expect(stats.protocolBreakdown["DexcomG6"] == 2)
        #expect(stats.protocolBreakdown["Libre2"] == 1)
    }
    
    @Test("Empty reports")
    func emptyReports() {
        let stats = aggregator.aggregate([])
        
        #expect(stats.reportCount == 0)
        #expect(stats.totalAttempts == 0)
        #expect(stats.averageSuccessRate == 0)
    }
    
    @Test("Success rate calculation")
    func successRateCalculation() {
        let reports = [
            makeReport(protocolName: "Test", success: true, attempts: 4, successfulAttempts: 3)
        ]
        
        let stats = aggregator.aggregate(reports)
        
        #expect(stats.averageSuccessRate == 0.75)
    }
}
