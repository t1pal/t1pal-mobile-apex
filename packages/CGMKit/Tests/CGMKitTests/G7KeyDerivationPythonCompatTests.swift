// SPDX-License-Identifier: AGPL-3.0-or-later
//
// G7KeyDerivationPythonCompatTests.swift
// CGMKitTests
//
// G7-FIX-009: PYTHON-COMPAT conformance tests for password → scalar derivation.
// Verifies Swift key derivation matches Python g7-jpake.py output byte-for-byte.
//
// Pattern: Each test validates Swift PasswordDerivation matches Python output.
// Reference: tools/g7-cli/g7-jpake.py, conformance/protocol/dexcom/fixture_g7_key_derivation.json
//
// Trace: G7-FIX-009, PRD-008 REQ-BLE-008

import Testing
import Foundation
@testable import CGMKit

// MARK: - PasswordDerivation PYTHON-COMPAT Tests (G7-FIX-009)

@Suite("G7 Key Derivation PYTHON-COMPAT")
struct G7KeyDerivationPythonCompatTests {
    
    // MARK: - Raw Variant Tests
    
    /// PYTHON-COMPAT: Raw derivation for 4-digit code
    /// Python: password_bytes + zero padding to 32 bytes
    @Test("Raw variant - 4-digit code 1234")
    func rawDerivation4Digit() {
        let password = "1234"
        let scalar = PasswordDerivation.raw.derive(password: password)
        
        // From fixture_g7_key_derivation.json DERIVE-001
        let expected = Data(hexString: "3132333400000000000000000000000000000000000000000000000000000000")!
        
        #expect(scalar.count == 32, "Scalar should be 32 bytes")
        #expect(scalar == expected, "Raw derivation should match Python")
    }
    
    /// PYTHON-COMPAT: Raw derivation for 6-digit code with "00" prefix
    @Test("Raw variant - 6-digit code 123456 with 00 prefix")
    func rawDerivation6Digit() {
        let password = "123456"
        let scalar = PasswordDerivation.raw.derive(password: password)
        
        // From fixture_g7_key_derivation.json DERIVE-004
        // "00" prefix (0x30, 0x30) + "123456" + zero padding
        let expected = Data(hexString: "3030313233343536000000000000000000000000000000000000000000000000")!
        
        #expect(scalar.count == 32, "Scalar should be 32 bytes")
        #expect(scalar == expected, "Raw derivation with 00 prefix should match Python")
    }
    
    // MARK: - SHA-256 Variant Tests
    
    /// PYTHON-COMPAT: SHA-256 without salt
    @Test("SHA256 no salt - 4-digit code 1234")
    func sha256NoSaltDerivation() {
        let password = "1234"
        let scalar = PasswordDerivation.sha256NoSalt.derive(password: password)
        
        // From fixture_g7_key_derivation.json DERIVE-001
        let expected = Data(hexString: "03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4")!
        
        #expect(scalar.count == 32, "Scalar should be 32 bytes")
        #expect(scalar == expected, "SHA256 no salt should match Python")
    }
    
    /// PYTHON-COMPAT: SHA-256 with salt
    @Test("SHA256 with salt - 4-digit code 1234")
    func sha256SaltDerivation() {
        let password = "1234"
        let scalar = PasswordDerivation.sha256Salt.derive(password: password)
        
        // From fixture_g7_key_derivation.json DERIVE-001
        let expected = Data(hexString: "a4e7fdfc85846476a81c629d035020f76a9cfb1dea4471c8cba3b9b795e7a765")!
        
        #expect(scalar.count == 32, "Scalar should be 32 bytes")
        #expect(scalar == expected, "SHA256 with salt should match Python")
    }
    
    // MARK: - With Serial Variant Tests
    
    /// PYTHON-COMPAT: Derivation with serial (no serial = same as sha256_salt)
    @Test("With serial - empty serial matches sha256_salt")
    func withSerialEmptySerial() {
        let password = "1234"
        let scalarWithSerial = PasswordDerivation.withSerial.derive(password: password, serial: "")
        let scalarSha256Salt = PasswordDerivation.sha256Salt.derive(password: password)
        
        // With empty serial, should match sha256_salt
        // From fixture_g7_key_derivation.json DERIVE-001
        let expected = Data(hexString: "a4e7fdfc85846476a81c629d035020f76a9cfb1dea4471c8cba3b9b795e7a765")!
        
        #expect(scalarWithSerial == expected, "With empty serial should match sha256_salt")
        #expect(scalarWithSerial == scalarSha256Salt, "With empty serial should equal sha256_salt variant")
    }
    
    /// PYTHON-COMPAT: Derivation with actual serial
    @Test("With serial - actual serial 3M1234ABCD")
    func withSerialActualSerial() {
        let password = "1234"
        let serial = "3M1234ABCD"
        let scalar = PasswordDerivation.withSerial.derive(password: password, serial: serial)
        
        // From fixture_g7_key_derivation.json DERIVE-005
        let expected = Data(hexString: "2d90c4ebac4a4c5f67f84137859f1b7e6b46eab0f26fc5fd3685ab3936e21759")!
        
        #expect(scalar.count == 32, "Scalar should be 32 bytes")
        #expect(scalar == expected, "With serial should match Python")
    }
    
    // MARK: - PBKDF2 Variant Tests
    
    /// PYTHON-COMPAT: PBKDF2-HMAC-SHA256 derivation
    @Test("PBKDF2 variant - 4-digit code 1234")
    func pbkdf2Derivation() {
        let password = "1234"
        let scalar = PasswordDerivation.pbkdf2.derive(password: password)
        
        // From fixture_g7_key_derivation.json DERIVE-001
        let expected = Data(hexString: "78aa81e2093fdb11a5879a054e53a8ea0c779603178dd79adcd7161308c97550")!
        
        #expect(scalar.count == 32, "Scalar should be 32 bytes")
        #expect(scalar == expected, "PBKDF2 should match Python")
    }
    
    // MARK: - HKDF Variant Tests
    
    /// PYTHON-COMPAT: HKDF-SHA256 derivation
    @Test("HKDF variant - 4-digit code 1234")
    func hkdfDerivation() {
        let password = "1234"
        let scalar = PasswordDerivation.hkdf.derive(password: password)
        
        // From fixture_g7_key_derivation.json DERIVE-001
        let expected = Data(hexString: "78516196cb804bce4c4d936c6621be650696d0e0e02e8c6c1fcd314f3355c656")!
        
        #expect(scalar.count == 32, "Scalar should be 32 bytes")
        #expect(scalar == expected, "HKDF should match Python")
    }
    
    // MARK: - ScalarOperations.passwordToScalar Tests
    
    /// PYTHON-COMPAT: password_to_scalar raw bytes (without padding)
    @Test("passwordToScalar - 4-digit raw bytes")
    func passwordToScalar4Digit() {
        let password = "1234"
        let scalar = ScalarOperations.passwordToScalar(password)
        
        // From fixture_g7_key_derivation.json PTS-001
        // Note: passwordToScalar returns raw bytes WITHOUT padding
        let expected = Data(hexString: "31323334")!
        
        #expect(scalar == expected, "passwordToScalar should return raw UTF-8 bytes")
    }
    
    /// PYTHON-COMPAT: password_to_scalar with 6-digit "00" prefix
    @Test("passwordToScalar - 6-digit with 00 prefix")
    func passwordToScalar6Digit() {
        let password = "123456"
        let scalar = ScalarOperations.passwordToScalar(password)
        
        // From fixture_g7_key_derivation.json PTS-002
        // 6-digit gets "00" prefix (ASCII 0x30, 0x30)
        let expected = Data(hexString: "3030313233343536")!
        
        #expect(scalar == expected, "passwordToScalar should prefix 6-digit with '00'")
    }
}

// MARK: - Fixture Cross-Validation Tests

@Suite("G7 Key Derivation Fixture Validation")
struct G7KeyDerivationFixtureValidationTests {
    
    /// Load fixture and validate all test vectors
    @Test("All DERIVE vectors match Python output")
    func allDeriveVectorsMatch() throws {
        let bundle = Bundle.module
        guard let fixtureURL = bundle.url(forResource: "fixture_g7_key_derivation", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("fixture_g7_key_derivation.json not found in test bundle")
            return
        }
        
        let data = try Data(contentsOf: fixtureURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let vectors = json["test_vectors"] as! [[String: Any]]
        
        for vector in vectors {
            let id = vector["id"] as! String
            let password = vector["password"] as! String
            let serial = vector["serial"] as? String ?? ""
            let expected = vector["expected"] as! [String: String]
            
            // Test each variant in the expected results
            for (variantName, expectedHex) in expected {
                guard let variant = variantFromString(variantName) else {
                    continue
                }
                
                let scalar = variant.derive(password: password, serial: serial)
                let expectedData = Data(hexString: expectedHex)!
                
                #expect(
                    scalar == expectedData,
                    "\(id) \(variantName): mismatch"
                )
            }
        }
    }
    
    /// Validate fixture constants match Swift constants
    @Test("Fixture constants match Swift constants")
    func fixtureConstantsMatch() throws {
        let bundle = Bundle.module
        guard let fixtureURL = bundle.url(forResource: "fixture_g7_key_derivation", withExtension: "json", subdirectory: "Fixtures") else {
            Issue.record("fixture_g7_key_derivation.json not found in test bundle")
            return
        }
        
        let data = try Data(contentsOf: fixtureURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let constants = json["constants"] as! [String: Any]
        
        // Verify salt
        let fixtureSalt = constants["default_salt"] as! String
        let swiftSalt = String(data: PasswordDerivation.defaultSalt, encoding: .utf8)!
        #expect(fixtureSalt == swiftSalt, "Salt should match")
        
        // Verify PBKDF2 iterations
        let fixtureIterations = constants["pbkdf2_iterations"] as! Int
        #expect(fixtureIterations == PasswordDerivation.pbkdf2Iterations, "PBKDF2 iterations should match")
    }
    
    // Helper to convert string to variant enum
    private func variantFromString(_ name: String) -> PasswordDerivation? {
        switch name {
        case "raw": return .raw
        case "sha256_no_salt": return .sha256NoSalt
        case "sha256_salt": return .sha256Salt
        case "with_serial": return .withSerial
        case "pbkdf2": return .pbkdf2
        case "hkdf": return .hkdf
        default: return nil
        }
    }
}

// MARK: - All Variants Coverage

@Suite("G7 Key Derivation All Variants")
struct G7KeyDerivationAllVariantsTests {
    
    /// Verify all variants produce 32-byte output
    @Test("All variants produce 32-byte scalars")
    func allVariants32Bytes() {
        let password = "1234"
        
        for variant in PasswordDerivation.allCases {
            let scalar = variant.derive(password: password)
            #expect(scalar.count == 32, "\(variant.rawValue) should produce 32 bytes, got \(scalar.count)")
        }
    }
    
    /// Verify all variants produce deterministic output
    @Test("All variants are deterministic")
    func allVariantsDeterministic() {
        let password = "9012"
        
        for variant in PasswordDerivation.allCases {
            let scalar1 = variant.derive(password: password)
            let scalar2 = variant.derive(password: password)
            #expect(scalar1 == scalar2, "\(variant.rawValue) should be deterministic")
        }
    }
    
    /// Verify different passwords produce different scalars
    @Test("Different passwords produce different scalars")
    func differentPasswordsDifferentScalars() {
        let passwords = ["1234", "5678", "0000", "9999"]
        
        for variant in PasswordDerivation.allCases {
            var scalars: [Data] = []
            for password in passwords {
                let scalar = variant.derive(password: password)
                #expect(!scalars.contains(scalar), "\(variant.rawValue) should produce unique scalars")
                scalars.append(scalar)
            }
        }
    }
}
