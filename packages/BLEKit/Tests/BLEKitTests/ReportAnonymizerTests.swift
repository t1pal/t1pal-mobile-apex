// ReportAnonymizerTests.swift - Tests for privacy-safe report anonymization
// Part of BLEKit
// Trace: EVID-001

import Foundation
import Testing
@testable import BLEKit

// MARK: - Anonymization Strategy Tests

@Suite("Anonymization Strategy")
struct AnonymizationStrategyTests {
    
    @Test("All strategies exist")
    func allStrategiesExist() {
        #expect(AnonymizationStrategy.allCases.count == 4)
    }
    
    @Test("Raw values are unique")
    func rawValuesUnique() {
        let rawValues = AnonymizationStrategy.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }
}

// MARK: - PII Type Tests

@Suite("PII Type")
struct PIITypeTests {
    
    @Test("All PII types exist")
    func allTypesExist() {
        #expect(PIIType.allCases.count == 10)
    }
    
    @Test("Email pattern matches emails")
    func emailPattern() throws {
        let pattern = PIIType.email.pattern!
        let regex = try NSRegularExpression(pattern: pattern)
        
        let validEmail = "test@example.com"
        let range = NSRange(validEmail.startIndex..., in: validEmail)
        #expect(regex.firstMatch(in: validEmail, range: range) != nil)
    }
    
    @Test("MAC address pattern matches")
    func macAddressPattern() throws {
        let pattern = PIIType.macAddress.pattern!
        let regex = try NSRegularExpression(pattern: pattern)
        
        let validMac = "AA:BB:CC:DD:EE:FF"
        let range = NSRange(validMac.startIndex..., in: validMac)
        #expect(regex.firstMatch(in: validMac, range: range) != nil)
    }
    
    @Test("IP address pattern matches")
    func ipAddressPattern() throws {
        let pattern = PIIType.ipAddress.pattern!
        let regex = try NSRegularExpression(pattern: pattern)
        
        let validIP = "192.168.1.1"
        let range = NSRange(validIP.startIndex..., in: validIP)
        #expect(regex.firstMatch(in: validIP, range: range) != nil)
    }
    
    @Test("UUID pattern matches")
    func uuidPattern() throws {
        let pattern = PIIType.bluetoothUUID.pattern!
        let regex = try NSRegularExpression(pattern: pattern)
        
        let validUUID = "12345678-1234-1234-1234-123456789ABC"
        let range = NSRange(validUUID.startIndex..., in: validUUID)
        #expect(regex.firstMatch(in: validUUID, range: range) != nil)
    }
}

// MARK: - Report Anonymizer Config Tests

@Suite("Report Anonymizer Config")
struct ReportAnonymizerConfigTests {
    
    @Test("Standard config")
    func standardConfig() {
        let config = ReportAnonymizer.Config.standard()
        
        #expect(config.deviceIdStrategy == .hash)
        #expect(config.uuidStrategy == .hash)
        #expect(config.deviceNameStrategy == .redact)
        #expect(config.timestampStrategy == .relative)
        #expect(config.anonymizePacketData == false)
    }
    
    @Test("Max privacy config")
    func maxPrivacyConfig() {
        let config = ReportAnonymizer.Config.maxPrivacy()
        
        #expect(config.deviceNameStrategy == .remove)
        #expect(config.timestampStrategy == .rounded)
        #expect(config.anonymizePacketData == true)
    }
    
    @Test("Research config")
    func researchConfig() {
        let config = ReportAnonymizer.Config.research(salt: "research-salt")
        
        #expect(config.deviceNameStrategy == .hash)
        #expect(config.hashPrefixLength == 12)
    }
    
    @Test("Hash prefix length clamped")
    func hashPrefixClamped() {
        let tooSmall = ReportAnonymizer.Config(salt: "test", hashPrefixLength: 2)
        let tooLarge = ReportAnonymizer.Config(salt: "test", hashPrefixLength: 100)
        
        #expect(tooSmall.hashPrefixLength >= 4)
        #expect(tooLarge.hashPrefixLength <= 32)
    }
}

// MARK: - Report Anonymizer Tests

@Suite("Report Anonymizer")
struct ReportAnonymizerTests {
    
    @Test("Hash produces consistent results")
    func hashConsistent() {
        let anonymizer = ReportAnonymizer(config: .standard(salt: "test-salt"))
        
        let hash1 = anonymizer.hash("device-123")
        let hash2 = anonymizer.hash("device-123")
        
        #expect(hash1 == hash2)
    }
    
    @Test("Hash produces different results for different inputs")
    func hashDifferent() {
        let anonymizer = ReportAnonymizer(config: .standard(salt: "test-salt"))
        
        let hash1 = anonymizer.hash("device-123")
        let hash2 = anonymizer.hash("device-456")
        
        #expect(hash1 != hash2)
    }
    
    @Test("Different salts produce different hashes")
    func differentSalts() {
        // Use very different salts to ensure djb2 fallback also works
        let anonymizer1 = ReportAnonymizer(config: .standard(salt: "AAAA-FIRST-SALT-XXXX"))
        let anonymizer2 = ReportAnonymizer(config: .standard(salt: "ZZZZ-SECOND-SALT-9999"))
        
        let hash1 = anonymizer1.hash("device-123")
        let hash2 = anonymizer2.hash("device-123")
        
        #expect(hash1 != hash2)
    }
    
    @Test("Anonymize device ID with hash strategy")
    func anonymizeDeviceIdHash() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        
        let anonymized = anonymizer.anonymizeDeviceId("DEXCOM-ABC123")
        
        #expect(anonymized.hasPrefix("DEV-"))
        #expect(!anonymized.contains("DEXCOM"))
        #expect(!anonymized.contains("ABC123"))
    }
    
    @Test("Anonymize device ID with redact strategy")
    func anonymizeDeviceIdRedact() {
        let config = ReportAnonymizer.Config(
            salt: "test",
            deviceIdStrategy: .redact
        )
        var anonymizer = ReportAnonymizer(config: config)
        
        let anonymized = anonymizer.anonymizeDeviceId("DEXCOM-ABC123")
        
        #expect(anonymized == "[REDACTED-DEVICE]")
    }
    
    @Test("Anonymize device ID with sequential strategy")
    func anonymizeDeviceIdSequential() {
        let config = ReportAnonymizer.Config(
            salt: "test",
            deviceIdStrategy: .sequential
        )
        var anonymizer = ReportAnonymizer(config: config)
        
        let id1 = anonymizer.anonymizeDeviceId("device-1")
        let id2 = anonymizer.anonymizeDeviceId("device-2")
        
        #expect(id1 == "DEV-0001")
        #expect(id2 == "DEV-0002")
    }
    
    @Test("Anonymize UUID")
    func anonymizeUUID() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        
        let original = "12345678-1234-1234-1234-123456789ABC"
        let anonymized = anonymizer.anonymizeUUID(original)
        
        #expect(anonymized != original)
        #expect(anonymized.contains("-0000-0000-0000-"))
    }
    
    @Test("Anonymize device name")
    func anonymizeDeviceName() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        
        let anonymized = anonymizer.anonymizeDeviceName("John's iPhone")
        
        #expect(anonymized == "[REDACTED-NAME]")
    }
    
    @Test("Anonymize timestamp - relative")
    func anonymizeTimestampRelative() {
        let config = ReportAnonymizer.Config(
            salt: "test",
            timestampStrategy: .relative
        )
        let anonymizer = ReportAnonymizer(config: config)
        
        let reference = Date(timeIntervalSince1970: 1000)
        let timestamp = Date(timeIntervalSince1970: 1060)  // 60 seconds later
        
        let anonymized = anonymizer.anonymizeTimestamp(timestamp, referenceDate: reference)
        
        #expect(anonymized != nil)
        #expect(anonymized!.timeIntervalSince1970 == 60)
    }
    
    @Test("Anonymize timestamp - rounded")
    func anonymizeTimestampRounded() {
        let config = ReportAnonymizer.Config(
            salt: "test",
            timestampStrategy: .rounded
        )
        let anonymizer = ReportAnonymizer(config: config)
        
        let reference = Date()
        let timestamp = Date(timeIntervalSince1970: 1000.5)  // Not on minute boundary
        
        let anonymized = anonymizer.anonymizeTimestamp(timestamp, referenceDate: reference)
        
        #expect(anonymized != nil)
        // Should be rounded to nearest minute (1020 or 960)
        #expect(anonymized!.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0)
    }
    
    @Test("Anonymize timestamp - remove")
    func anonymizeTimestampRemove() {
        let config = ReportAnonymizer.Config(
            salt: "test",
            timestampStrategy: .remove
        )
        let anonymizer = ReportAnonymizer(config: config)
        
        let result = anonymizer.anonymizeTimestamp(Date(), referenceDate: Date())
        
        #expect(result == nil)
    }
    
    @Test("Anonymize MAC address")
    func anonymizeMacAddress() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        
        let original = "AA:BB:CC:DD:EE:FF"
        let anonymized = anonymizer.anonymizeMacAddress(original)
        
        #expect(anonymized != original)
        #expect(anonymized.contains(":"))
    }
    
    @Test("Cache consistency")
    func cacheConsistency() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        
        let id1 = anonymizer.anonymizeDeviceId("device-123")
        let id2 = anonymizer.anonymizeDeviceId("device-123")
        
        #expect(id1 == id2)
        #expect(anonymizer.cacheSize == 1)
    }
    
    @Test("Reset clears state")
    func resetClearsState() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        
        _ = anonymizer.anonymizeDeviceId("device-123")
        #expect(anonymizer.cacheSize == 1)
        
        anonymizer.reset()
        #expect(anonymizer.cacheSize == 0)
    }
}

// MARK: - Traffic Entry Anonymization Tests

@Suite("Traffic Entry Anonymization")
struct TrafficEntryAnonymizationTests {
    
    @Test("Anonymize single entry")
    func anonymizeSingleEntry() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        let entry = TrafficEntry(
            direction: .outgoing,
            data: Data([0x01, 0x02, 0x03]),
            characteristic: "12345678-1234-1234-1234-123456789ABC",
            service: "ABCD1234-1234-1234-1234-123456789ABC",
            note: "Test note"
        )
        
        let anonymized = anonymizer.anonymize(entry, referenceDate: Date())
        
        #expect(anonymized.characteristic != entry.characteristic)
        #expect(anonymized.service != entry.service)
        #expect(anonymized.id != entry.id)  // New ID
    }
    
    @Test("Anonymize entries collection")
    func anonymizeCollection() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        let entries = [
            TrafficEntry(
                direction: .outgoing,
                data: Data([0x01]),
                characteristic: "12345678-1234-1234-1234-123456789ABC"
            ),
            TrafficEntry(
                direction: .incoming,
                data: Data([0x02]),
                characteristic: "12345678-1234-1234-1234-123456789ABC"
            )
        ]
        
        let (anonymized, result) = anonymizer.anonymize(entries)
        
        #expect(anonymized.count == 2)
        #expect(result.fieldsAnonymized > 0)
        #expect(result.piiTypesFound.contains(.bluetoothUUID))
    }
    
    @Test("Consistent UUID anonymization across entries")
    func consistentUUIDAnonymization() {
        var anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        let uuid = "12345678-1234-1234-1234-123456789ABC"
        let entries = [
            TrafficEntry(direction: .outgoing, data: Data([0x01]), characteristic: uuid),
            TrafficEntry(direction: .incoming, data: Data([0x02]), characteristic: uuid)
        ]
        
        let (anonymized, _) = anonymizer.anonymize(entries)
        
        // Same original UUID should produce same anonymized UUID
        #expect(anonymized[0].characteristic == anonymized[1].characteristic)
    }
    
    @Test("Packet data anonymization when enabled")
    func packetDataAnonymization() {
        let config = ReportAnonymizer.Config.maxPrivacy(salt: "test")
        var anonymizer = ReportAnonymizer(config: config)
        let entry = TrafficEntry(
            direction: .outgoing,
            data: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        )
        
        let anonymized = anonymizer.anonymize(entry, referenceDate: Date())
        
        // Bytes 2-5 should be masked
        #expect(anonymized.data[2] == 0x00)
        #expect(anonymized.data[3] == 0x00)
    }
}

// MARK: - PII Scanning Tests

@Suite("PII Scanning")
struct PIIScanningTests {
    
    @Test("Scan detects email")
    func scanDetectsEmail() {
        let anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        let text = "Contact: john@example.com for help"
        
        let found = anonymizer.scanForPII(text)
        
        #expect(found.contains(.email))
    }
    
    @Test("Scan detects MAC address")
    func scanDetectsMac() {
        let anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        let text = "Device MAC: AA:BB:CC:DD:EE:FF"
        
        let found = anonymizer.scanForPII(text)
        
        #expect(found.contains(.macAddress))
    }
    
    @Test("Scan detects IP address")
    func scanDetectsIP() {
        let anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        let text = "Server: 192.168.1.1"
        
        let found = anonymizer.scanForPII(text)
        
        #expect(found.contains(.ipAddress))
    }
    
    @Test("Scan detects UUID")
    func scanDetectsUUID() {
        let anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        let text = "Characteristic: 12345678-1234-1234-1234-123456789ABC"
        
        let found = anonymizer.scanForPII(text)
        
        #expect(found.contains(.bluetoothUUID))
    }
    
    @Test("Redact PII from text")
    func redactPII() {
        let anonymizer = ReportAnonymizer(config: .standard(salt: "test"))
        let text = "Contact john@example.com at 192.168.1.1"
        
        let redacted = anonymizer.redactPII(text)
        
        #expect(!redacted.contains("john@example.com"))
        #expect(!redacted.contains("192.168.1.1"))
        #expect(redacted.contains("[EMAIL]"))
        #expect(redacted.contains("[IPADDRESS]"))
    }
}

// MARK: - Anonymized Report Tests

@Suite("Anonymized Report")
struct AnonymizedReportTests {
    
    @Test("Create anonymized report")
    func createReport() {
        let report = AnonymizedReport(
            deviceId: "DEV-abc123",
            entries: [],
            sessionDuration: 300,
            entryCount: 10,
            errorCount: 2,
            anonymizationInfo: AnonymizationInfo(
                deviceIdStrategy: "hash",
                uuidStrategy: "hash",
                timestampStrategy: "relative",
                packetDataAnonymized: false,
                uniqueDeviceCount: 1,
                redactedPIITypes: ["bluetoothUUID"]
            )
        )
        
        #expect(report.deviceId == "DEV-abc123")
        #expect(report.sessionDuration == 300)
        #expect(report.entryCount == 10)
        #expect(report.errorCount == 2)
    }
    
    @Test("Report is Codable")
    func reportCodable() throws {
        let report = AnonymizedReport(
            deviceId: "DEV-abc123",
            entries: [],
            sessionDuration: 300,
            entryCount: 10,
            errorCount: 0,
            anonymizationInfo: AnonymizationInfo(
                deviceIdStrategy: "hash",
                uuidStrategy: "hash",
                timestampStrategy: "relative",
                packetDataAnonymized: false,
                uniqueDeviceCount: 1,
                redactedPIITypes: []
            )
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(report)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnonymizedReport.self, from: data)
        
        #expect(decoded.deviceId == report.deviceId)
        #expect(decoded.sessionDuration == report.sessionDuration)
    }
}

// MARK: - Report Builder Tests

@Suite("Anonymized Report Builder")
struct AnonymizedReportBuilderTests {
    
    @Test("Build report from entries")
    func buildReport() {
        var builder = AnonymizedReportBuilder(
            deviceId: "DEXCOM-ABC123",
            config: .standard(salt: "test")
        )
        
        let entries = [
            TrafficEntry(
                direction: .outgoing,
                data: Data([0x01]),
                characteristic: "12345678-1234-1234-1234-123456789ABC"
            ),
            TrafficEntry(
                direction: .incoming,
                data: Data([0x02])
            )
        ]
        
        let report = builder.build(from: entries, errorCount: 1)
        
        #expect(report.deviceId.hasPrefix("DEV-"))
        #expect(!report.deviceId.contains("DEXCOM"))
        #expect(report.entryCount == 2)
        #expect(report.errorCount == 1)
        #expect(report.entries.count == 2)
    }
    
    @Test("Session duration calculated correctly")
    func sessionDuration() {
        var builder = AnonymizedReportBuilder(
            deviceId: "device-1",
            config: .standard(salt: "test")
        )
        
        let start = Date()
        let end = start.addingTimeInterval(120)  // 2 minutes
        
        let entries = [
            TrafficEntry(timestamp: start, direction: .outgoing, data: Data([0x01])),
            TrafficEntry(timestamp: end, direction: .incoming, data: Data([0x02]))
        ]
        
        let report = builder.build(from: entries)
        
        #expect(report.sessionDuration == 120)
    }
    
    @Test("Anonymization info populated")
    func anonymizationInfo() {
        var builder = AnonymizedReportBuilder(
            deviceId: "device-1",
            config: .maxPrivacy(salt: "test")
        )
        
        let entries = [
            TrafficEntry(
                direction: .outgoing,
                data: Data([0x01]),
                characteristic: "12345678-1234-1234-1234-123456789ABC"
            )
        ]
        
        let report = builder.build(from: entries)
        
        #expect(report.anonymizationInfo.deviceIdStrategy == "hash")
        #expect(report.anonymizationInfo.timestampStrategy == "rounded")
        #expect(report.anonymizationInfo.packetDataAnonymized == true)
    }
}
