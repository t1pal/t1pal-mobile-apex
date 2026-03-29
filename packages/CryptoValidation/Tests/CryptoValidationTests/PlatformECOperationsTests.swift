// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PlatformECOperationsTests.swift
// CryptoValidationTests
//
// Tests for PlatformECOperations (CryptoKit wrapper).
//
// Trace: EC-LIB-014, PRD-008

import Foundation
import Testing

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

@testable import CryptoValidation

@Suite("PlatformECOperations")
struct PlatformECOperationsTests {
    
    // MARK: - Test Data
    
    /// Known test scalar
    let testScalar = Data([
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
        0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20
    ])
    
    // MARK: - Protocol Conformance
    
    @Test("Conforms to ECOperationsProvider protocol")
    func platformConformsToProtocol() {
        let _: ECOperationsProvider.Type = PlatformECOperations.self
        #expect(Bool(true), "PlatformECOperations conforms to ECOperationsProvider")
    }
    
    // MARK: - Scalar Base Multiply
    
    @Test("scalarBaseMultiply produces valid point")
    func scalarBaseMultiplyProducesValidPoint() throws {
        let point = try #require(PlatformECOperations.scalarBaseMultiply(scalar: testScalar))
        
        #expect(point.count == 64, "Result should be 64 bytes (X || Y)")
        #expect(PlatformECOperations.isValidPoint(point), "Result should be on curve")
    }
    
    @Test("scalarBaseMultiply is deterministic")
    func scalarBaseMultiplyDeterministic() {
        let point1 = PlatformECOperations.scalarBaseMultiply(scalar: testScalar)
        let point2 = PlatformECOperations.scalarBaseMultiply(scalar: testScalar)
        
        #expect(point1 == point2, "Same scalar should produce same point")
    }
    
    // MARK: - Point Validation
    
    @Test("isValidPoint rejects wrong size")
    func isValidPointRejectsWrongSize() {
        let tooShort = Data(repeating: 0x00, count: 32)
        let tooLong = Data(repeating: 0x00, count: 128)
        
        #expect(!PlatformECOperations.isValidPoint(tooShort))
        #expect(!PlatformECOperations.isValidPoint(tooLong))
    }
    
    @Test("isValidPoint rejects zero point")
    func isValidPointRejectsZeroPoint() {
        let zeroPoint = Data(repeating: 0x00, count: 64)
        #expect(!PlatformECOperations.isValidPoint(zeroPoint))
    }
    
    // MARK: - Negate Point
    
    @Test("negatePoint returns nil (not supported)")
    func negatePointReturnsNil() throws {
        let point = try #require(PlatformECOperations.scalarBaseMultiply(scalar: testScalar))
        
        // negatePoint should return nil for PlatformECOperations (not supported)
        #expect(PlatformECOperations.negatePoint(point) == nil,
            "PlatformECOperations.negatePoint should return nil (not supported by CryptoKit)")
    }
    
    // MARK: - Cross-Validator Utility
    
    @Test("ECCrossValidator exists and works")
    func crossValidatorExists() {
        let scalar = testScalar
        let result = ECCrossValidator.validateScalarBaseMultiply(
            reference: PlatformECOperations.self,
            platform: PlatformECOperations.self,
            scalar: scalar
        )
        
        #expect(result.match, "Same implementation should match")
        #expect(result.operation == "scalarBaseMultiply")
    }
    
    // MARK: - Validation Result
    
    @Test("ECValidationResult initialization")
    func ecValidationResultInitialization() {
        let result = ECValidationResult(
            operation: "test",
            reference: Data([0x01]),
            platform: Data([0x01])
        )
        
        #expect(result.match)
        #expect(result.operation == "test")
    }
}
