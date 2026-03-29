//
//  RileyLinkSessionTests.swift
//  PumpKitTests
//
//  Tests for RileyLinkSession static properties and types
//  Trace: PG-TEST-001

import Foundation
import Testing
@testable import PumpKit
@testable import BLEKit

@Suite("RileyLink Session")
struct RileyLinkSessionTests {
    
    // MARK: - Static UUID Tests
    
    @Test("Service UUID matches RileyLink spec")
    func serviceUUIDMatchesSpec() {
        #expect(RileyLinkSession.serviceUUID == "0235733B-99C5-4197-B856-69219C2A3845")
    }
    
    @Test("Data characteristic UUID matches spec")
    func dataCharUUIDMatchesSpec() {
        #expect(RileyLinkSession.dataCharUUID == "C842E849-5028-42E2-867C-016ADADA9155")
    }
    
    @Test("Response count UUID matches spec")
    func responseCountUUIDMatchesSpec() {
        #expect(RileyLinkSession.responseCountUUID == "6E6C7910-B89E-43A5-A0FE-50C5E2B81F4A")
    }
    
    @Test("Firmware version UUID matches spec")
    func firmwareVersionUUIDMatchesSpec() {
        #expect(RileyLinkSession.firmwareCharUUID == "30D99DC9-7C91-4295-A051-0A104D238CF2")
    }
    
    // MARK: - BLEUUID Extension Tests
    
    @Test("BLEUUID.rileyLinkService matches session UUID")
    func bleUUIDServiceMatches() {
        #expect(BLEUUID.rileyLinkService.description.uppercased() == RileyLinkSession.serviceUUID.uppercased())
    }
    
    @Test("BLEUUID.rileyLinkData matches session UUID")
    func bleUUIDDataMatches() {
        #expect(BLEUUID.rileyLinkData.description.uppercased() == RileyLinkSession.dataCharUUID.uppercased())
    }
    
    @Test("BLEUUID.rileyLinkResponseCount matches session UUID")
    func bleUUIDResponseCountMatches() {
        #expect(BLEUUID.rileyLinkResponseCount.description.uppercased() == RileyLinkSession.responseCountUUID.uppercased())
    }
    
    @Test("BLEUUID.rileyLinkFirmwareVersion matches session UUID")
    func bleUUIDFirmwareMatches() {
        #expect(BLEUUID.rileyLinkFirmwareVersion.description.uppercased() == RileyLinkSession.firmwareCharUUID.uppercased())
    }
}

// MARK: - RileyLink Session Error Tests

@Suite("RileyLink Session Errors")
struct RileyLinkSessionErrorTests {
    
    @Test("missingCharacteristic error has description")
    func missingCharacteristicError() {
        let error = RileyLinkSessionError.missingCharacteristic("data")
        #expect(error.errorDescription?.contains("data") == true)
    }
    
    @Test("timeout error has description")
    func timeoutError() {
        let error = RileyLinkSessionError.timeout("test timeout")
        #expect(error.errorDescription?.isEmpty == false)
    }
    
    @Test("rfTimeout error has description")
    func rfTimeoutError() {
        let error = RileyLinkSessionError.rfTimeout
        #expect(error.errorDescription?.contains("RF") == true || error.errorDescription?.contains("pump") == true)
    }
    
    @Test("unknownResponse error includes code")
    func unknownResponseError() {
        let error = RileyLinkSessionError.unknownResponse(0xAA)
        #expect(error.errorDescription?.contains("AA") == true)
    }
}

// MARK: - Radio Firmware Version Tests

@Suite("Radio Firmware Version")
struct RadioFirmwareVersionTests {
    
    @Test("Parses subg_rfspy 1.0 format")
    func parsesSubg10() {
        let version = RadioFirmwareVersion(versionString: "subg_rfspy 1.0")
        #expect(version != nil)
        #expect(version?.components == [1, 0])
    }
    
    @Test("Parses subg_rfspy 2.2 format")
    func parsesSubg22() {
        let version = RadioFirmwareVersion(versionString: "subg_rfspy 2.2")
        #expect(version != nil)
        #expect(version?.components == [2, 2])
    }
    
    @Test("Parses ble_rfspy format")
    func parsesBleRfspy() {
        let version = RadioFirmwareVersion(versionString: "ble_rfspy 1.5")
        #expect(version != nil)
        #expect(version?.components == [1, 5])
    }
    
    @Test("Returns nil for invalid string")
    func returnsNilForInvalid() {
        let version = RadioFirmwareVersion(versionString: "invalid")
        #expect(version == nil)
    }
    
    @Test("unknown has single zero component")
    func unknownVersion() {
        let version = RadioFirmwareVersion.unknown
        #expect(version.components == [0])
        #expect(version.isUnknown == true)
    }
    
    @Test("assumeV2 has 2.2 components")
    func assumeV2Version() {
        let version = RadioFirmwareVersion.assumeV2
        #expect(version.components == [2, 2])
        #expect(version.isUnknown == false)
    }
    
    @Test("Firmware version is Equatable")
    func firmwareEquatable() {
        let v1 = RadioFirmwareVersion(versionString: "subg_rfspy 2.2")
        let v2 = RadioFirmwareVersion(versionString: "subg_rfspy 2.2")
        #expect(v1 == v2)
    }
    
    @Test("Different versions are not equal")
    func differentVersionsNotEqual() {
        let v1 = RadioFirmwareVersion(versionString: "subg_rfspy 1.0")
        let v2 = RadioFirmwareVersion(versionString: "subg_rfspy 2.2")
        #expect(v1 != v2)
    }
}
