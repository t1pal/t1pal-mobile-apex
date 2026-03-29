// SPDX-License-Identifier: AGPL-3.0-or-later
//
// OpenSSLECOperationsTests.swift
// CryptoValidationTests
//
// Tests for OpenSSLECOperations (EC-LIB-016/017)
// Validates EC point arithmetic using audited OpenSSL backend.
//
// Trace: EC-LIB-016 (Apple), EC-LIB-017 (Linux)
//
// Test Vectors: NIST P-256 (secp256r1)
// Source: https://csrc.nist.gov/groups/STM/cavp/documents/components/ecccdhvs.pdf

import Foundation
import Testing
@testable import CryptoValidation

@Suite("OpenSSLECOperations")
struct OpenSSLECOperationsTests {
    
    // MARK: - NIST P-256 Test Vectors
    
    /// P-256 Generator point G
    /// NIST FIPS 186-4 D.1.2.3
    static let generatorX = Data(hexString: "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296")!
    static let generatorY = Data(hexString: "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5")!
    
    /// 2G - G + G (known test vector)
    static let twoGX = Data(hexString: "7CF27B188D034F7E8A52380304B51AC3C08969E277F21B35A60B48FC47669978")!
    static let twoGY = Data(hexString: "07775510DB8ED040293D9AC69F7430DBBA7DADE63CE982299E04B79D227873D1")!
    
    /// 3G - 2G + G (derived)
    static let threeGX = Data(hexString: "5ECBE4D1A6330A44C8F7EF951D4BF165E6C6B721EFADA985FB41661BC6E7FD6C")!
    static let threeGY = Data(hexString: "8734640C4998FF7E374B06CE1A64A2ECD82AB036384FB83D9A79B127A27D5032")!
    
    // MARK: - Verify (2G Computation)
    
    @Test("verify() computes 2G correctly")
    func verifyComputes2G() throws {
        let result = try OpenSSLECOperations.verify()
        #expect(result, "OpenSSL should compute 2G correctly and match NIST vector")
    }
    
    // MARK: - Scalar Base Multiply
    
    @Test("1 * G = G")
    func multiplyGeneratorByOne() throws {
        // 1 * G = G
        let scalar = Data(count: 31) + Data([0x01])  // scalar = 1 (32 bytes)
        let result = try OpenSSLECOperations.multiplyGenerator(by: scalar)
        
        #expect(result.x == Self.generatorX, "1*G should equal G (x coordinate)")
        #expect(result.y == Self.generatorY, "1*G should equal G (y coordinate)")
    }
    
    @Test("2 * G = 2G")
    func multiplyGeneratorByTwo() throws {
        // 2 * G = 2G
        let scalar = Data(count: 31) + Data([0x02])  // scalar = 2 (32 bytes)
        let result = try OpenSSLECOperations.multiplyGenerator(by: scalar)
        
        #expect(result.x == Self.twoGX, "2*G should equal 2G (x coordinate)")
        #expect(result.y == Self.twoGY, "2*G should equal 2G (y coordinate)")
    }
    
    @Test("3 * G = 3G")
    func multiplyGeneratorByThree() throws {
        // 3 * G = 3G
        let scalar = Data(count: 31) + Data([0x03])  // scalar = 3 (32 bytes)
        let result = try OpenSSLECOperations.multiplyGenerator(by: scalar)
        
        #expect(result.x == Self.threeGX, "3*G should equal 3G (x coordinate)")
        #expect(result.y == Self.threeGY, "3*G should equal 3G (y coordinate)")
    }
    
    // MARK: - Point Addition
    
    @Test("G + G = 2G")
    func addGPlusGEquals2G() throws {
        // G + G = 2G
        let g = ECPoint(x: Self.generatorX, y: Self.generatorY)
        let result = try OpenSSLECOperations.addPoints(g, g)
        
        #expect(result.x == Self.twoGX, "G+G should equal 2G (x coordinate)")
        #expect(result.y == Self.twoGY, "G+G should equal 2G (y coordinate)")
    }
    
    @Test("2G + G = 3G")
    func add2GPlusGEquals3G() throws {
        // 2G + G = 3G
        let g = ECPoint(x: Self.generatorX, y: Self.generatorY)
        let twoG = ECPoint(x: Self.twoGX, y: Self.twoGY)
        let result = try OpenSSLECOperations.addPoints(twoG, g)
        
        #expect(result.x == Self.threeGX, "2G+G should equal 3G (x coordinate)")
        #expect(result.y == Self.threeGY, "2G+G should equal 3G (y coordinate)")
    }
    
    @Test("Point addition is commutative")
    func additionCommutative() throws {
        // G + 2G = 2G + G
        let g = ECPoint(x: Self.generatorX, y: Self.generatorY)
        let twoG = ECPoint(x: Self.twoGX, y: Self.twoGY)
        
        let result1 = try OpenSSLECOperations.addPoints(g, twoG)
        let result2 = try OpenSSLECOperations.addPoints(twoG, g)
        
        #expect(result1.x == result2.x, "Point addition should be commutative (x)")
        #expect(result1.y == result2.y, "Point addition should be commutative (y)")
    }
    
    // MARK: - Scalar Point Multiply
    
    @Test("G * 2 = 2G")
    func multiplyPointGByTwo() throws {
        // G * 2 = 2G
        let g = ECPoint(x: Self.generatorX, y: Self.generatorY)
        let scalar = Data(count: 31) + Data([0x02])
        let result = try OpenSSLECOperations.multiplyPoint(g, by: scalar)
        
        #expect(result.x == Self.twoGX, "G*2 should equal 2G (x coordinate)")
        #expect(result.y == Self.twoGY, "G*2 should equal 2G (y coordinate)")
    }
    
    @Test("2G * 1 = 2G")
    func multiply2GByOneEquals2G() throws {
        // 2G * 1 = 2G
        let twoG = ECPoint(x: Self.twoGX, y: Self.twoGY)
        let scalar = Data(count: 31) + Data([0x01])
        let result = try OpenSSLECOperations.multiplyPoint(twoG, by: scalar)
        
        #expect(result.x == Self.twoGX, "2G*1 should equal 2G (x coordinate)")
        #expect(result.y == Self.twoGY, "2G*1 should equal 2G (y coordinate)")
    }
    
    // MARK: - Cross-Platform Consistency
    
    @Test("multiplyGenerator matches multiplyPoint(G)")
    func randomScalarProducesSameResultAsMultiplyByG() throws {
        // For any scalar k: multiplyGenerator(k) == multiplyPoint(G, k)
        let scalar = Data([
            0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
            0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
            0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00,
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08
        ])
        
        let g = ECPoint(x: Self.generatorX, y: Self.generatorY)
        
        let result1 = try OpenSSLECOperations.multiplyGenerator(by: scalar)
        let result2 = try OpenSSLECOperations.multiplyPoint(g, by: scalar)
        
        #expect(result1.x == result2.x, "multiplyGenerator and multiplyPoint(G) should match (x)")
        #expect(result1.y == result2.y, "multiplyGenerator and multiplyPoint(G) should match (y)")
    }
}

// MARK: - AuditedECOperations Tests (EC-LIB-018)

@Suite("AuditedECOperations")
struct AuditedECOperationsTests {
    
    // MARK: - Test Data (same NIST vectors)
    
    static let generatorRaw = Data(hexString: "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C2964FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5")!
    static let twoGRaw = Data(hexString: "7CF27B188D034F7E8A52380304B51AC3C08969E277F21B35A60B48FC4766997807775510DB8ED040293D9AC69F7430DBBA7DADE63CE982299E04B79D227873D1")!
    static let threeGRaw = Data(hexString: "5ECBE4D1A6330A44C8F7EF951D4BF165E6C6B721EFADA985FB41661BC6E7FD6C8734640C4998FF7E374B06CE1A64A2ECD82AB036384FB83D9A79B127A27D5032")!
    
    // MARK: - ECOperationsProvider Conformance
    
    @Test("Conforms to ECOperationsProvider protocol")
    func conformsToProtocol() {
        let _: ECOperationsProvider.Type = AuditedECOperations.self
        #expect(Bool(true), "AuditedECOperations conforms to ECOperationsProvider")
    }
    
    // MARK: - addPoints
    
    @Test("G + G = 2G")
    func addPointsGPlusGEquals2G() {
        let result = AuditedECOperations.addPoints(Self.generatorRaw, Self.generatorRaw)
        #expect(result == Self.twoGRaw, "G + G should equal 2G")
    }
    
    @Test("2G + G = 3G")
    func addPoints2GPlusGEquals3G() {
        let result = AuditedECOperations.addPoints(Self.twoGRaw, Self.generatorRaw)
        #expect(result == Self.threeGRaw, "2G + G should equal 3G")
    }
    
    @Test("Point addition is commutative")
    func addPointsCommutative() {
        let result1 = AuditedECOperations.addPoints(Self.generatorRaw, Self.twoGRaw)
        let result2 = AuditedECOperations.addPoints(Self.twoGRaw, Self.generatorRaw)
        #expect(result1 == result2, "Point addition should be commutative")
    }
    
    // MARK: - scalarMultiply
    
    @Test("G * 2 = 2G")
    func scalarMultiplyGByTwo() {
        let scalar = Data(count: 31) + Data([0x02])
        let result = AuditedECOperations.scalarMultiply(point: Self.generatorRaw, scalar: scalar)
        #expect(result == Self.twoGRaw, "G * 2 should equal 2G")
    }
    
    // MARK: - scalarBaseMultiply
    
    @Test("1 * G = G")
    func scalarBaseMultiplyByOne() {
        let scalar = Data(count: 31) + Data([0x01])
        let result = AuditedECOperations.scalarBaseMultiply(scalar: scalar)
        #expect(result == Self.generatorRaw, "1 * G should equal G")
    }
    
    @Test("2 * G = 2G")
    func scalarBaseMultiplyByTwo() {
        let scalar = Data(count: 31) + Data([0x02])
        let result = AuditedECOperations.scalarBaseMultiply(scalar: scalar)
        #expect(result == Self.twoGRaw, "2 * G should equal 2G")
    }
    
    // MARK: - negatePoint
    
    @Test("Negated point is 64 bytes")
    func negatePointProduces64Bytes() {
        let negated = AuditedECOperations.negatePoint(Self.generatorRaw)
        #expect(negated != nil)
        #expect(negated?.count == 64, "Negated point should be 64 bytes")
    }
    
    @Test("Negation preserves X coordinate")
    func negatePointPreservesX() {
        let negated = AuditedECOperations.negatePoint(Self.generatorRaw)
        #expect(negated != nil)
        #expect(negated?.prefix(32) == Self.generatorRaw.prefix(32), "X coordinate should be preserved")
    }
    
    @Test("Negation changes Y coordinate")
    func negatePointChangesY() {
        let negated = AuditedECOperations.negatePoint(Self.generatorRaw)
        #expect(negated != nil)
        #expect(negated?.suffix(32) != Self.generatorRaw.suffix(32), "Y coordinate should change")
    }
    
    // MARK: - isValidPoint
    
    @Test("isValidPoint accepts generator")
    func isValidPointAcceptsGenerator() {
        #expect(AuditedECOperations.isValidPoint(Self.generatorRaw))
    }
    
    @Test("isValidPoint accepts 2G")
    func isValidPointAccepts2G() {
        #expect(AuditedECOperations.isValidPoint(Self.twoGRaw))
    }
    
    @Test("isValidPoint rejects wrong size")
    func isValidPointRejectsWrongSize() {
        #expect(!AuditedECOperations.isValidPoint(Data(count: 32)))
        #expect(!AuditedECOperations.isValidPoint(Data(count: 128)))
    }
    
    @Test("isValidPoint rejects zero")
    func isValidPointRejectsZero() {
        #expect(!AuditedECOperations.isValidPoint(Data(count: 64)))
    }
    
    // MARK: - subtractPoints (default implementation)
    
    @Test("2G - G = G")
    func subtractPoints2GMinusGEqualsG() {
        let result = AuditedECOperations.subtractPoints(Self.twoGRaw, Self.generatorRaw)
        #expect(result == Self.generatorRaw, "2G - G should equal G")
    }
    
    @Test("3G - 2G = G")
    func subtract3GMinus2GEqualsG() {
        let result = AuditedECOperations.subtractPoints(Self.threeGRaw, Self.twoGRaw)
        #expect(result == Self.generatorRaw, "3G - 2G should equal G")
    }
}

// MARK: - Hex String Helper

private extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
