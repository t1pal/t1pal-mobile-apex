// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CapabilityRegistry.swift
// T1PalCompatKit
//
// Registry for discovering and running capability tests.
// Trace: PRD-006 REQ-COMPAT-001
//
// Usage:
//   CapabilityRegistry.shared.register(MyTest())
//   let results = await CapabilityRegistry.shared.runAll()

import Foundation

/// Registry for capability tests
public actor CapabilityRegistry {
    /// Shared singleton instance
    public static let shared = CapabilityRegistry()
    
    /// Registered tests
    private var tests: [any CapabilityTest] = []
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register a capability test
    public func register(_ test: any CapabilityTest) {
        tests.append(test)
    }
    
    /// Register multiple tests
    public func register(_ tests: [any CapabilityTest]) {
        self.tests.append(contentsOf: tests)
    }
    
    /// Get all registered tests
    public func allTests() -> [any CapabilityTest] {
        tests
    }
    
    /// Get tests by category
    public func tests(in category: CapabilityCategory) -> [any CapabilityTest] {
        tests.filter { $0.category == category }
    }
    
    /// Get count of registered tests
    public var count: Int {
        tests.count
    }
    
    // MARK: - Running Tests
    
    /// Run all registered tests
    public func runAll(skipHardware: Bool = false) async -> CapabilityReport {
        let startTime = Date()
        var results: [CapabilityResult] = []
        
        let sortedTests = tests.sorted { $0.priority < $1.priority }
        
        for test in sortedTests {
            if skipHardware && test.requiresHardware {
                results.append(CapabilityResult(
                    testId: test.id,
                    testName: test.name,
                    category: test.category,
                    status: .skipped,
                    message: "Hardware test skipped"
                ))
                continue
            }
            
            let result = await test.run()
            results.append(result)
        }
        
        return CapabilityReport(
            results: results,
            startTime: startTime,
            endTime: Date()
        )
    }
    
    /// Run tests in a specific category
    public func run(category: CapabilityCategory, skipHardware: Bool = false) async -> CapabilityReport {
        let startTime = Date()
        var results: [CapabilityResult] = []
        
        let categoryTests = tests(in: category).sorted { $0.priority < $1.priority }
        
        for test in categoryTests {
            if skipHardware && test.requiresHardware {
                results.append(test.skipped("Hardware test skipped"))
                continue
            }
            
            let result = await test.run()
            results.append(result)
        }
        
        return CapabilityReport(
            results: results,
            startTime: startTime,
            endTime: Date()
        )
    }
    
    /// Clear all registered tests (for testing)
    public func clear() {
        tests = []
    }
    
    /// Create a fresh isolated registry for testing (avoids shared state issues)
    public static func createIsolated() -> CapabilityRegistry {
        CapabilityRegistry()
    }
}

// MARK: - Capability Report

/// Summary report of capability test results
public struct CapabilityReport: Codable, Sendable {
    /// All test results
    public let results: [CapabilityResult]
    
    /// When testing started
    public let startTime: Date
    
    /// When testing completed
    public let endTime: Date
    
    /// Total duration
    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    /// Count of passed tests
    public var passedCount: Int {
        results.filter { $0.status == .passed }.count
    }
    
    /// Count of failed tests
    public var failedCount: Int {
        results.filter { $0.status == .failed }.count
    }
    
    /// Count of skipped tests
    public var skippedCount: Int {
        results.filter { $0.status == .skipped }.count
    }
    
    /// Count of unsupported tests
    public var unsupportedCount: Int {
        results.filter { $0.status == .unsupported }.count
    }
    
    /// Whether all tests passed (ignoring skipped/unsupported)
    public var allPassed: Bool {
        failedCount == 0
    }
    
    /// Results grouped by category
    public var byCategory: [CapabilityCategory: [CapabilityResult]] {
        Dictionary(grouping: results, by: { $0.category })
    }
    
    /// Generate CLI summary
    public func summary(useColor: Bool = true) -> String {
        var lines: [String] = []
        
        lines.append("═══════════════════════════════════════════")
        lines.append("        Capability Test Report")
        lines.append("═══════════════════════════════════════════")
        lines.append("")
        
        // Group by category
        for category in CapabilityCategory.allCases {
            guard let categoryResults = byCategory[category], !categoryResults.isEmpty else {
                continue
            }
            
            lines.append("[\(category.displayName)]")
            for result in categoryResults {
                lines.append("  \(result.formatted(useColor: useColor))")
            }
            lines.append("")
        }
        
        // Summary line
        let durationStr = String(format: "%.2f", duration)
        lines.append("───────────────────────────────────────────")
        lines.append("Total: \(results.count) tests in \(durationStr)s")
        
        let summaryParts = [
            passedCount > 0 ? "\(passedCount) passed" : nil,
            failedCount > 0 ? "\(failedCount) failed" : nil,
            skippedCount > 0 ? "\(skippedCount) skipped" : nil,
            unsupportedCount > 0 ? "\(unsupportedCount) unsupported" : nil,
        ].compactMap { $0 }
        
        lines.append(summaryParts.joined(separator: ", "))
        
        if allPassed {
            let check = useColor ? "\u{001B}[32m✓\u{001B}[0m" : "✓"
            lines.append("\(check) All capability tests passed")
        } else {
            let x = useColor ? "\u{001B}[31m✗\u{001B}[0m" : "✗"
            lines.append("\(x) Some capability tests failed")
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Export as JSON
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    
    /// Export as JSON string
    public func toJSONString() throws -> String {
        let data = try toJSON()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Playground Test Report (AUDIT-PLAY-005)

/// Comprehensive test report for playground and CI export
/// Includes device info, environment, and traceability metadata
public struct PlaygroundTestReport: Codable, Sendable {
    /// Report format version
    public let version: String
    
    /// Report generation timestamp (ISO 8601)
    public let generatedAt: Date
    
    /// Device and environment info
    public let environment: TestEnvironment
    
    /// Core capability results
    public let capabilityReport: CapabilityReport
    
    /// Trace information for regulatory/QA
    public let traceability: TraceabilityInfo
    
    /// Summary statistics
    public let summary: PlaygroundTestSummary
    
    public init(
        capabilityReport: CapabilityReport,
        environment: TestEnvironment = .current(),
        traceability: TraceabilityInfo = .default
    ) {
        self.version = "1.0"
        self.generatedAt = Date()
        self.environment = environment
        self.capabilityReport = capabilityReport
        self.traceability = traceability
        self.summary = PlaygroundTestSummary(from: capabilityReport)
    }
    
    /// Export to JSON data
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    
    /// Export to JSON string
    public func toJSONString() throws -> String {
        let data = try toJSON()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    /// Export to file
    public func write(to url: URL) throws {
        let data = try toJSON()
        try data.write(to: url)
    }
}

/// Device and runtime environment information
public struct TestEnvironment: Codable, Sendable {
    public let platform: String
    public let osVersion: String
    public let deviceModel: String
    public let appVersion: String
    public let buildNumber: String
    public let isSimulator: Bool
    public let locale: String
    public let timezone: String
    
    public init(
        platform: String,
        osVersion: String,
        deviceModel: String,
        appVersion: String = "1.0.0",
        buildNumber: String = "1",
        isSimulator: Bool = false,
        locale: String = "en_US",
        timezone: String = "UTC"
    ) {
        self.platform = platform
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.isSimulator = isSimulator
        self.locale = locale
        self.timezone = timezone
    }
    
    /// Get current environment (platform-aware)
    public static func current() -> TestEnvironment {
        #if os(iOS)
        return TestEnvironment(
            platform: "iOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: deviceModelIdentifier(),
            isSimulator: isRunningOnSimulator(),
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
        #elseif os(macOS)
        return TestEnvironment(
            platform: "macOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: "Mac",
            isSimulator: false,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
        #elseif os(Linux)
        return TestEnvironment(
            platform: "Linux",
            osVersion: "Linux",
            deviceModel: "Server",
            isSimulator: false,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
        #else
        return TestEnvironment(
            platform: "Unknown",
            osVersion: "Unknown",
            deviceModel: "Unknown"
        )
        #endif
    }
    
    private static func deviceModelIdentifier() -> String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        return machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        #else
        return "Unknown"
        #endif
    }
    
    private static func isRunningOnSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

/// Traceability information for regulatory and QA purposes
public struct TraceabilityInfo: Codable, Sendable {
    public let testSuiteId: String
    public let runId: String
    public let prdReferences: [String]
    public let requirementIds: [String]
    public let gitCommit: String?
    public let ciJobId: String?
    
    public init(
        testSuiteId: String = "T1Pal-CapabilityTests",
        runId: String = UUID().uuidString,
        prdReferences: [String] = ["PRD-006", "PRD-010"],
        requirementIds: [String] = ["REQ-COMPAT-001", "REQ-DEBUG-004"],
        gitCommit: String? = nil,
        ciJobId: String? = nil
    ) {
        self.testSuiteId = testSuiteId
        self.runId = runId
        self.prdReferences = prdReferences
        self.requirementIds = requirementIds
        self.gitCommit = gitCommit
        self.ciJobId = ciJobId
    }
    
    public static let `default` = TraceabilityInfo()
}

/// Aggregated test statistics
/// Aggregated test statistics for playground reports
public struct PlaygroundTestSummary: Codable, Sendable {
    public let totalTests: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    public let unsupported: Int
    public let passRate: Double
    public let duration: TimeInterval
    public let byCategory: [String: PlaygroundCategorySummary]
    
    public init(
        totalTests: Int,
        passed: Int,
        failed: Int,
        skipped: Int,
        unsupported: Int,
        passRate: Double,
        duration: TimeInterval,
        byCategory: [String: PlaygroundCategorySummary]
    ) {
        self.totalTests = totalTests
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
        self.unsupported = unsupported
        self.passRate = passRate
        self.duration = duration
        self.byCategory = byCategory
    }
    
    public init(from report: CapabilityReport) {
        let totalTests = report.results.count
        let passed = report.passedCount
        let failed = report.failedCount
        let skipped = report.skippedCount
        let unsupported = report.unsupportedCount
        
        let denominator = max(1, totalTests - skipped - unsupported)
        let passRate = Double(passed) / Double(denominator)
        
        var categories: [String: PlaygroundCategorySummary] = [:]
        for (category, results) in report.byCategory {
            categories[category.rawValue] = PlaygroundCategorySummary(from: results)
        }
        
        self.init(
            totalTests: totalTests,
            passed: passed,
            failed: failed,
            skipped: skipped,
            unsupported: unsupported,
            passRate: passRate,
            duration: report.duration,
            byCategory: categories
        )
    }
}

/// Per-category statistics for playground reports
public struct PlaygroundCategorySummary: Codable, Sendable {
    public let total: Int
    public let passed: Int
    public let failed: Int
    public let skipped: Int
    
    public init(total: Int, passed: Int, failed: Int, skipped: Int) {
        self.total = total
        self.passed = passed
        self.failed = failed
        self.skipped = skipped
    }
    
    public init(from results: [CapabilityResult]) {
        self.init(
            total: results.count,
            passed: results.filter { $0.status == .passed }.count,
            failed: results.filter { $0.status == .failed }.count,
            skipped: results.filter { $0.status == .skipped }.count
        )
    }
}

// MARK: - CapabilityRegistry Extensions

extension CapabilityRegistry {
    /// Run all tests and generate a full playground test report
    public func runAllWithReport(
        skipHardware: Bool = false,
        traceability: TraceabilityInfo = .default
    ) async -> PlaygroundTestReport {
        let report = await runAll(skipHardware: skipHardware)
        return PlaygroundTestReport(
            capabilityReport: report,
            traceability: traceability
        )
    }
    
    /// Run tests and write report to file
    public func runAllAndExport(
        to url: URL,
        skipHardware: Bool = false,
        traceability: TraceabilityInfo = .default
    ) async throws {
        let report = await runAllWithReport(
            skipHardware: skipHardware,
            traceability: traceability
        )
        try report.write(to: url)
    }
}
