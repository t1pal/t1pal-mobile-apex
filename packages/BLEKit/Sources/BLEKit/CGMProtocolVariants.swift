// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CGMProtocolVariants.swift
// BLEKit
//
// Protocol variant enums for CGM authentication and connection.
// Each enum represents uncertainty in protocol implementations across vendors.
// Trace: PROTO-FLEX-002 through PROTO-FLEX-007, UNCERT-G6-001, UNCERT-G7-001

import Foundation

// MARK: - Dexcom G6 Variants

/// G6 key derivation method variants.
/// The key is typically 16 bytes for AES-128 encryption.
/// Trace: UNCERT-G6-001, PROTO-FLEX-002
public enum G6KeyDerivationVariant: String, Sendable, Codable, CaseIterable {
    /// ASCII zeros: "00" + ID + "00" + ID as UTF-8 (confirmed correct)
    /// Produces: 0x30 0x30 + ID bytes + 0x30 0x30 + ID bytes
    case asciiZeros = "asciiZeros"
    
    /// Null bytes: 0x00 0x00 + ID + 0x00 0x00 + ID
    /// Common confusion - "00" interpreted as null bytes
    case nullBytes = "nullBytes"
    
    /// SHA-1 of transmitter ID bytes (incorrect but sometimes tried)
    case sha1 = "sha1"
    
    /// Hex encoded: Use hex string representation
    case hexEncoded = "hexEncoded"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .asciiZeros: return "ASCII '00' + ID (correct)"
        case .nullBytes: return "Null bytes 0x00 + ID"
        case .sha1: return "SHA-1 of ID"
        case .hexEncoded: return "Hex string encoding"
        }
    }
    
    /// Source reference for this variant
    public var sourceReference: String {
        switch self {
        case .asciiZeros: return "CGMBLEKit (Loop)"
        case .nullBytes: return "Common confusion"
        case .sha1: return "Incorrect assumption"
        case .hexEncoded: return "Spike"
        }
    }
}

/// G6 token hash method variants.
/// How the token is padded before AES-ECB encryption.
/// Trace: UNCERT-G6-001
public enum G6TokenHashVariant: String, Sendable, Codable, CaseIterable {
    /// Token doubled: token || token (16 bytes)
    case doubled = "doubled"
    
    /// Zero padded: token || 0x00×8 (16 bytes)
    case zeroPadded = "zeroPadded"
    
    /// PKCS7 padded: token with PKCS7 padding
    case pkcs7 = "pkcs7"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .doubled: return "Token doubled (correct)"
        case .zeroPadded: return "Zero padded"
        case .pkcs7: return "PKCS7 padded"
        }
    }
}

/// G6 authentication opcode variants.
/// Different opcodes used for authentication messages.
/// Trace: UNCERT-G6-001
public enum G6AuthOpcodeVariant: String, Sendable, Codable, CaseIterable {
    /// G6 standard (opcode 0x01 for auth request)
    case g6Standard = "g6Standard"
    
    /// G6+ Firefly (opcode 0x02 for auth request)
    case firefly = "firefly"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .g6Standard: return "G6 standard (0x01)"
        case .firefly: return "G6+ Firefly (0x02)"
        }
    }
}

/// Complete G6 variant selection combining all uncertainty dimensions.
/// Trace: UNCERT-G6-002
public struct G6VariantSelection: Sendable, Codable, Hashable, Identifiable {
    public var keyDerivation: G6KeyDerivationVariant
    public var tokenHash: G6TokenHashVariant
    public var authOpcode: G6AuthOpcodeVariant
    
    public init(
        keyDerivation: G6KeyDerivationVariant = .asciiZeros,
        tokenHash: G6TokenHashVariant = .doubled,
        authOpcode: G6AuthOpcodeVariant = .g6Standard
    ) {
        self.keyDerivation = keyDerivation
        self.tokenHash = tokenHash
        self.authOpcode = authOpcode
    }
    
    /// Loop/CGMBLEKit-style configuration (confirmed working)
    public static let loopDefault = G6VariantSelection(
        keyDerivation: .asciiZeros,
        tokenHash: .doubled,
        authOpcode: .g6Standard
    )
    
    /// G6+ Firefly configuration
    public static let firefly = G6VariantSelection(
        keyDerivation: .asciiZeros,
        tokenHash: .doubled,
        authOpcode: .firefly
    )
    
    /// Unique identifier for this configuration
    public var id: String {
        "\(keyDerivation.rawValue)_\(tokenHash.rawValue)_\(authOpcode.rawValue)"
    }
    
    /// Human-readable description
    public var description: String {
        """
        Key: \(keyDerivation.description)
        Token: \(tokenHash.description)
        Opcode: \(authOpcode.description)
        """
    }
    
    /// Total number of combinations
    public static var totalCombinations: Int {
        G6KeyDerivationVariant.allCases.count *
        G6TokenHashVariant.allCases.count *
        G6AuthOpcodeVariant.allCases.count
    }
}

// MARK: - Dexcom G7 Variants

/// G7 password derivation method variants.
/// How the J-PAKE password is derived from the pairing code.
/// Trace: PROTO-FLEX-004
public enum G7PasswordDerivationVariant: String, Sendable, Codable, CaseIterable {
    /// Standard: SHA-256 of pairing code + salt
    case standard = "standard"
    
    /// Code only: Just the pairing code bytes
    case codeOnly = "codeOnly"
    
    /// Reversed: Reversed byte order of code
    case reversed = "reversed"
    
    /// PBKDF2: Password-based key derivation
    case pbkdf2 = "pbkdf2"
    
    /// Prefixed code: PREFIX (0x30, 0x30) + UTF-8 code → BigInteger (xDrip libkeks)
    /// Source: UNCERT-G7-006b
    case prefixedCode = "prefixedCode"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .standard: return "SHA-256 with salt"
        case .codeOnly: return "Code bytes only"
        case .reversed: return "Reversed byte order"
        case .pbkdf2: return "PBKDF2 derivation"
        case .prefixedCode: return "Prefixed code (xDrip)"
        }
    }
    
    /// Source reference for this variant
    public var sourceReference: String {
        switch self {
        case .standard: return "CGMBLEKit (Loop)"
        case .codeOnly: return "DiaBLE"
        case .reversed: return "xDrip4iOS"
        case .pbkdf2: return "Theoretical"
        case .prefixedCode: return "xDrip libkeks (Android)"
        }
    }
}

/// G7 EC parameter variants.
/// Elliptic curve parameter sources for J-PAKE.
public enum G7ECParameterVariant: String, Sendable, Codable, CaseIterable {
    /// P-256 with standard NIST parameters
    case p256Standard = "p256Standard"
    
    /// P-256 with custom generator point
    case p256CustomGenerator = "p256CustomGenerator"
    
    /// Curve25519 (alternative curve)
    case curve25519 = "curve25519"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .p256Standard: return "P-256 NIST standard"
        case .p256CustomGenerator: return "P-256 custom generator"
        case .curve25519: return "Curve25519"
        }
    }
}

/// G7 bonding order variants.
/// When bonding occurs relative to authentication.
/// Trace: PROTO-FLEX-005
public enum G7BondingOrderVariant: String, Sendable, Codable, CaseIterable {
    /// Authenticate first, then bond
    case authThenBond = "authThenBond"
    
    /// Bond first, then authenticate
    case bondThenAuth = "bondThenAuth"
    
    /// Simultaneous auth and bond
    case simultaneous = "simultaneous"
    
    /// No bonding required (session-only)
    case noBond = "noBond"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .authThenBond: return "Authenticate, then bond"
        case .bondThenAuth: return "Bond, then authenticate"
        case .simultaneous: return "Simultaneous"
        case .noBond: return "No bonding"
        }
    }
}

/// G7 session key derivation variants.
/// How the session key is derived after J-PAKE.
public enum G7SessionKeyDerivationVariant: String, Sendable, Codable, CaseIterable {
    /// HKDF with transcript hash
    case hkdf = "hkdf"
    
    /// PBKDF2 with shared secret
    case pbkdf2 = "pbkdf2"
    
    /// Transcript binding (TLS-style)
    case transcriptBinding = "transcriptBinding"
    
    /// Direct shared secret (no KDF)
    case direct = "direct"
    
    /// SHA256 of X coordinate, truncated to 16 bytes (xDrip libkeks style)
    /// Source: UNCERT-G7-006b - xDrip implementation
    case sha256Truncate = "sha256Truncate"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .hkdf: return "HKDF with transcript"
        case .pbkdf2: return "PBKDF2"
        case .transcriptBinding: return "Transcript binding"
        case .direct: return "Direct (no KDF)"
        case .sha256Truncate: return "SHA256 truncate (xDrip)"
        }
    }
}

// MARK: - Libre 2 Variants

/// Libre 2 crypto constant variants.
/// Different crypto constants used by different implementations.
/// Trace: PROTO-FLEX-006, UNCERT-L2-001
public enum Libre2CryptoConstantVariant: String, Sendable, Codable, CaseIterable {
    /// LibreTransmitter constants (key array: 0xA0C5, 0x6860, 0x0000, 0x14C6)
    case libreTransmitter = "libreTransmitter"
    
    /// xDrip constants (same as LibreTransmitter)
    case xDrip = "xDrip"
    
    /// DiaBLE constants
    case diaBLE = "diaBLE"
    
    /// Bubble app constants
    case bubble = "bubble"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .libreTransmitter: return "LibreTransmitter"
        case .xDrip: return "xDrip"
        case .diaBLE: return "DiaBLE"
        case .bubble: return "Bubble"
        }
    }
    
    /// Source reference for this variant
    public var sourceReference: String {
        switch self {
        case .libreTransmitter: return "https://github.com/dabear/LibreTransmitter"
        case .xDrip: return "xDrip4iOS"
        case .diaBLE: return "https://github.com/gui-dos/DiaBLE"
        case .bubble: return "Bubble app"
        }
    }
}

/// Libre 2 sensor type detection variants.
/// How the sensor type is determined from patch info.
/// Trace: UNCERT-L2-001
public enum Libre2SensorTypeVariant: String, Sendable, Codable, CaseIterable {
    /// Standard detection via patchInfo[0] and patchInfo[3]
    case standard = "standard"
    
    /// Extended detection with firmware version check
    case extended = "extended"
    
    /// Fallback always assumes Libre 2
    case alwaysLibre2 = "alwaysLibre2"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .standard: return "Standard (patchInfo[0,3])"
        case .extended: return "Extended (with firmware)"
        case .alwaysLibre2: return "Always Libre 2"
        }
    }
}

/// Libre 2 unlock payload derivation variants.
/// How the BLE unlock payload is derived from sensor UID and time.
/// Trace: UNCERT-L2-001
public enum Libre2UnlockVariant: String, Sendable, Codable, CaseIterable {
    /// Standard: enableTime + unlockCount
    case standard = "standard"
    
    /// LibreTransmitter style (same as standard but with specific counter handling)
    case libreTransmitter = "libreTransmitter"
    
    /// xDrip style (different counter persistence)
    case xDrip = "xDrip"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .standard: return "Standard (enableTime + counter)"
        case .libreTransmitter: return "LibreTransmitter"
        case .xDrip: return "xDrip"
        }
    }
}

/// Libre 2 FRAM XOR constant variants.
/// Different XOR constants for FRAM block decryption.
/// Trace: UNCERT-L2-001
public enum Libre2FRAMXORVariant: String, Sendable, Codable, CaseIterable {
    /// Standard Libre 2: XOR 0x44 for all blocks
    case standard = "standard"
    
    /// US 14-day: 0xcadc for blocks <3 or ≥40
    case us14day = "us14day"
    
    /// No XOR (raw decryption)
    case none = "none"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .standard: return "Standard (XOR 0x44)"
        case .us14day: return "US 14-day (0xcadc)"
        case .none: return "No XOR"
        }
    }
}

/// Libre 2 glucose calibration factor variants.
/// Different calibration factors for raw → mg/dL conversion.
/// Trace: UNCERT-L2-001, UNCERT-L2-005
public enum Libre2CalibrationVariant: String, Sendable, Codable, CaseIterable {
    /// Simple approximation: rawValue / 8.5
    /// Note: This is a rough approximation, not production-accurate
    case simple = "simple"
    
    /// Full polynomial calibration with temperature compensation
    /// Uses sensor calibration data (i2, i3, i4) and lookup tables
    /// Reference: LibreTransmitter GlucoseFromRaw.swift
    case polynomial = "polynomial"
    
    /// User calibration: adjustable factor
    case userCalibrated = "userCalibrated"
    
    /// Human-readable description
    public var description: String {
        switch self {
        case .simple: return "Simple (÷8.5 approx)"
        case .polynomial: return "Polynomial (temp-compensated)"
        case .userCalibrated: return "User calibrated"
        }
    }
    
    /// Source reference for this variant
    public var sourceReference: String {
        switch self {
        case .simple: return "Common approximation"
        case .polynomial: return "LibreTransmitter (accurate)"
        case .userCalibrated: return "User adjustment"
        }
    }
}

/// Complete Libre 2 variant selection combining all uncertainty dimensions.
/// Trace: UNCERT-L2-002
public struct Libre2VariantSelection: Sendable, Codable, Hashable, Identifiable {
    public var cryptoConstant: Libre2CryptoConstantVariant
    public var sensorType: Libre2SensorTypeVariant
    public var unlock: Libre2UnlockVariant
    public var framXOR: Libre2FRAMXORVariant
    public var calibration: Libre2CalibrationVariant
    
    public init(
        cryptoConstant: Libre2CryptoConstantVariant = .libreTransmitter,
        sensorType: Libre2SensorTypeVariant = .standard,
        unlock: Libre2UnlockVariant = .standard,
        framXOR: Libre2FRAMXORVariant = .standard,
        calibration: Libre2CalibrationVariant = .polynomial
    ) {
        self.cryptoConstant = cryptoConstant
        self.sensorType = sensorType
        self.unlock = unlock
        self.framXOR = framXOR
        self.calibration = calibration
    }
    
    /// LibreTransmitter-compatible configuration (accurate)
    public static let libreTransmitterDefault = Libre2VariantSelection(
        cryptoConstant: .libreTransmitter,
        sensorType: .standard,
        unlock: .libreTransmitter,
        framXOR: .standard,
        calibration: .polynomial
    )
    
    /// xDrip-compatible configuration
    public static let xDripDefault = Libre2VariantSelection(
        cryptoConstant: .xDrip,
        sensorType: .standard,
        unlock: .xDrip,
        framXOR: .standard,
        calibration: .polynomial
    )
    
    /// US 14-day configuration
    public static let us14day = Libre2VariantSelection(
        cryptoConstant: .libreTransmitter,
        sensorType: .extended,
        unlock: .standard,
        framXOR: .us14day,
        calibration: .polynomial
    )
    
    /// Unique identifier for this configuration
    public var id: String {
        "\(cryptoConstant.rawValue)_\(sensorType.rawValue)_\(unlock.rawValue)_\(framXOR.rawValue)_\(calibration.rawValue)"
    }
    
    /// Human-readable description
    public var description: String {
        """
        Crypto: \(cryptoConstant.description)
        Sensor: \(sensorType.description)
        Unlock: \(unlock.description)
        FRAM: \(framXOR.description)
        Cal: \(calibration.description)
        """
    }
    
    /// Total number of combinations
    public static var totalCombinations: Int {
        Libre2CryptoConstantVariant.allCases.count *
        Libre2SensorTypeVariant.allCases.count *
        Libre2UnlockVariant.allCases.count *
        Libre2FRAMXORVariant.allCases.count *
        Libre2CalibrationVariant.allCases.count
    }
}

/// Selector for trying Libre 2 variants in order of likelihood.
/// Trace: UNCERT-L2-002
public struct Libre2VariantSelector: Sendable {
    /// Ordered list of selections to try (most likely first)
    public let selections: [Libre2VariantSelection]
    
    /// Create selector with default order (known working configs first)
    public init() {
        self.selections = [
            .libreTransmitterDefault,
            .xDripDefault,
            .us14day,
        ]
    }
    
    /// Create selector with custom priority order
    public init(selections: [Libre2VariantSelection]) {
        self.selections = selections
    }
    
    /// Get next selection to try after current one
    public func next(after current: Libre2VariantSelection) -> Libre2VariantSelection? {
        guard let index = selections.firstIndex(of: current) else {
            return selections.first
        }
        let nextIndex = index + 1
        return nextIndex < selections.count ? selections[nextIndex] : nil
    }
}

// MARK: - Timing Variants

/// Connection timing configuration.
/// Trace: PROTO-FLEX-007
public struct CGMTimingConfiguration: Sendable, Codable, Equatable {
    /// Connection timeout in seconds
    public var connectionTimeout: TimeInterval
    
    /// Keep-alive interval in seconds
    public var keepAliveInterval: TimeInterval
    
    /// Message delay between writes in milliseconds
    public var messageDelayMs: Int
    
    /// Retry delay after failure in seconds
    public var retryDelay: TimeInterval
    
    /// Maximum retry attempts
    public var maxRetries: Int
    
    public init(
        connectionTimeout: TimeInterval = 10.0,
        keepAliveInterval: TimeInterval = 60.0,
        messageDelayMs: Int = 100,
        retryDelay: TimeInterval = 2.0,
        maxRetries: Int = 3
    ) {
        self.connectionTimeout = connectionTimeout
        self.keepAliveInterval = keepAliveInterval
        self.messageDelayMs = messageDelayMs
        self.retryDelay = retryDelay
        self.maxRetries = maxRetries
    }
    
    /// Default timing for Dexcom G6
    public static let g6Default = CGMTimingConfiguration(
        connectionTimeout: 10.0,
        keepAliveInterval: 295.0,  // ~5 min readings
        messageDelayMs: 100,
        retryDelay: 2.0,
        maxRetries: 3
    )
    
    /// Default timing for Dexcom G7
    public static let g7Default = CGMTimingConfiguration(
        connectionTimeout: 15.0,
        keepAliveInterval: 295.0,
        messageDelayMs: 50,
        retryDelay: 3.0,
        maxRetries: 5
    )
    
    /// Default timing for Libre 2
    public static let libre2Default = CGMTimingConfiguration(
        connectionTimeout: 20.0,
        keepAliveInterval: 60.0,
        messageDelayMs: 200,
        retryDelay: 5.0,
        maxRetries: 3
    )
}

// MARK: - Combined Configuration

/// Complete CGM protocol variant configuration.
/// Combines all variant selections for a specific CGM type.
public struct CGMProtocolConfiguration: Sendable, Codable, Equatable {
    /// Configuration name
    public var name: String
    
    /// CGM device type
    public var deviceType: String
    
    /// G6 key derivation (if applicable)
    public var g6KeyDerivation: G6KeyDerivationVariant?
    
    /// G6 token hash (if applicable)
    public var g6TokenHash: G6TokenHashVariant?
    
    /// G6 auth opcodes (if applicable)
    public var g6AuthOpcode: G6AuthOpcodeVariant?
    
    /// G7 password derivation (if applicable)
    public var g7PasswordDerivation: G7PasswordDerivationVariant?
    
    /// G7 EC parameters (if applicable)
    public var g7ECParameter: G7ECParameterVariant?
    
    /// G7 bonding order (if applicable)
    public var g7BondingOrder: G7BondingOrderVariant?
    
    /// G7 session key derivation (if applicable)
    public var g7SessionKeyDerivation: G7SessionKeyDerivationVariant?
    
    /// Libre 2 crypto constants (if applicable)
    public var libre2CryptoConstant: Libre2CryptoConstantVariant?
    
    /// Timing configuration
    public var timing: CGMTimingConfiguration
    
    public init(
        name: String,
        deviceType: String,
        timing: CGMTimingConfiguration = CGMTimingConfiguration()
    ) {
        self.name = name
        self.deviceType = deviceType
        self.timing = timing
    }
    
    // MARK: - Presets
    
    /// Default G6 configuration (Loop-compatible)
    public static let g6Default: CGMProtocolConfiguration = {
        var config = CGMProtocolConfiguration(name: "G6 Default", deviceType: "DexcomG6", timing: .g6Default)
        config.g6KeyDerivation = .asciiZeros
        config.g6TokenHash = .doubled
        config.g6AuthOpcode = .g6Standard
        return config
    }()
    
    /// Default G7 configuration (Loop-compatible)
    public static let g7Default: CGMProtocolConfiguration = {
        var config = CGMProtocolConfiguration(name: "G7 Default", deviceType: "DexcomG7", timing: .g7Default)
        config.g7PasswordDerivation = .standard
        config.g7ECParameter = .p256Standard
        config.g7BondingOrder = .authThenBond
        config.g7SessionKeyDerivation = .hkdf
        return config
    }()
    
    /// Default Libre 2 configuration
    public static let libre2Default: CGMProtocolConfiguration = {
        var config = CGMProtocolConfiguration(name: "Libre 2 Default", deviceType: "Libre2", timing: .libre2Default)
        config.libre2CryptoConstant = .xDrip
        return config
    }()
}

// MARK: - G7 Variant Selection (UNCERT-G7-002e)

/// G7-specific variant configuration for protocol uncertainty handling.
/// Trace: UNCERT-G7-002e - Wire enums to registry, add selection logic
public struct G7VariantSelection: Sendable, Codable, Equatable {
    public var passwordDerivation: G7PasswordDerivationVariant
    public var ecParameter: G7ECParameterVariant
    public var bondingOrder: G7BondingOrderVariant
    public var sessionKeyDerivation: G7SessionKeyDerivationVariant
    
    public init(
        passwordDerivation: G7PasswordDerivationVariant = .standard,
        ecParameter: G7ECParameterVariant = .p256Standard,
        bondingOrder: G7BondingOrderVariant = .authThenBond,
        sessionKeyDerivation: G7SessionKeyDerivationVariant = .hkdf
    ) {
        self.passwordDerivation = passwordDerivation
        self.ecParameter = ecParameter
        self.bondingOrder = bondingOrder
        self.sessionKeyDerivation = sessionKeyDerivation
    }
    
    /// Default configuration (Loop-compatible)
    public static let loopDefault = G7VariantSelection()
    
    /// DiaBLE-style configuration
    public static let diaBLEStyle = G7VariantSelection(
        passwordDerivation: .codeOnly,
        ecParameter: .p256Standard,
        bondingOrder: .authThenBond,
        sessionKeyDerivation: .hkdf
    )
    
    /// xDrip-style configuration (based on libkeks analysis - UNCERT-G7-006b)
    public static let xDripStyle = G7VariantSelection(
        passwordDerivation: .prefixedCode,  // PREFIX (0x30, 0x30) + UTF-8 code
        ecParameter: .p256Standard,          // secp256r1 confirmed
        bondingOrder: .bondThenAuth,
        sessionKeyDerivation: .sha256Truncate  // SHA256(X-coord)[0:16]
    )
    
    /// Unique identifier for this configuration
    public var id: String {
        "\(passwordDerivation.rawValue)_\(ecParameter.rawValue)_\(bondingOrder.rawValue)_\(sessionKeyDerivation.rawValue)"
    }
    
    /// Human-readable description
    public var description: String {
        """
        Password: \(passwordDerivation.description)
        EC: \(ecParameter.description)
        Bonding: \(bondingOrder.description)
        Session Key: \(sessionKeyDerivation.description)
        """
    }
}

/// Generator for all G7 variant combinations.
/// Trace: UNCERT-G7-002e
public struct G7VariantCombinationGenerator: Sequence {
    public typealias Iterator = G7VariantIterator
    
    public init() {}
    
    public func makeIterator() -> G7VariantIterator {
        G7VariantIterator()
    }
    
    /// Total number of combinations
    public static var totalCombinations: Int {
        G7PasswordDerivationVariant.allCases.count *
        G7ECParameterVariant.allCases.count *
        G7BondingOrderVariant.allCases.count *
        G7SessionKeyDerivationVariant.allCases.count
    }
}

/// Iterator for G7 variant combinations
public struct G7VariantIterator: IteratorProtocol {
    private var passwordIndex = 0
    private var ecIndex = 0
    private var bondingIndex = 0
    private var sessionKeyIndex = 0
    private var exhausted = false
    
    public init() {}
    
    public mutating func next() -> G7VariantSelection? {
        guard !exhausted else { return nil }
        
        let passwords = G7PasswordDerivationVariant.allCases
        let ecs = G7ECParameterVariant.allCases
        let bondings = G7BondingOrderVariant.allCases
        let sessionKeys = G7SessionKeyDerivationVariant.allCases
        
        let selection = G7VariantSelection(
            passwordDerivation: passwords[passwordIndex],
            ecParameter: ecs[ecIndex],
            bondingOrder: bondings[bondingIndex],
            sessionKeyDerivation: sessionKeys[sessionKeyIndex]
        )
        
        // Advance indices
        sessionKeyIndex += 1
        if sessionKeyIndex >= sessionKeys.count {
            sessionKeyIndex = 0
            bondingIndex += 1
        }
        if bondingIndex >= bondings.count {
            bondingIndex = 0
            ecIndex += 1
        }
        if ecIndex >= ecs.count {
            ecIndex = 0
            passwordIndex += 1
        }
        if passwordIndex >= passwords.count {
            exhausted = true
        }
        
        return selection
    }
}

/// Selector for trying G7 variants in order of likelihood.
/// Trace: UNCERT-G7-002e
public struct G7VariantSelector: Sendable {
    /// Ordered list of selections to try (most likely first)
    public let selections: [G7VariantSelection]
    
    /// Create selector with default order (known working configs first)
    public init() {
        self.selections = [
            .loopDefault,
            .diaBLEStyle,
            .xDripStyle,
            // Add more as discovered...
        ]
    }
    
    /// Create selector with custom priority order
    public init(selections: [G7VariantSelection]) {
        self.selections = selections
    }
    
    /// Create selector that tries all combinations
    public static func exhaustive() -> G7VariantSelector {
        G7VariantSelector(selections: Array(G7VariantCombinationGenerator()))
    }
    
    /// Get next selection to try after current one
    public func next(after current: G7VariantSelection) -> G7VariantSelection? {
        guard let index = selections.firstIndex(of: current) else {
            return selections.first
        }
        let nextIndex = index + 1
        return nextIndex < selections.count ? selections[nextIndex] : nil
    }
}
