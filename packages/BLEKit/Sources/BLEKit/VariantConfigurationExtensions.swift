// SPDX-License-Identifier: AGPL-3.0-or-later
// VariantConfigurationExtensions.swift - Device-specific variant configurations
// Extracted from VariantRegistry.swift (BLE-REFACTOR-003)
// Trace: UNCERT-G7-002e, UNCERT-G6-002, UNCERT-L2-002

import Foundation

// MARK: - G7 Variant Configuration Extension (UNCERT-G7-002e)

extension VariantConfiguration {
    /// G7 variant selection keys
    private enum G7Keys {
        static let passwordDerivation = "g7.passwordDerivation"
        static let ecParameter = "g7.ecParameter"
        static let bondingOrder = "g7.bondingOrder"
        static let sessionKeyDerivation = "g7.sessionKeyDerivation"
    }
    
    /// Create configuration for G7 with type-safe variant selection
    public static func g7(
        selection: G7VariantSelection,
        enabled: Bool = true,
        priority: Int = 0
    ) -> VariantConfiguration {
        VariantConfiguration(
            variantId: "dexcom.g7",
            enabled: enabled,
            priority: priority,
            settings: [
                G7Keys.passwordDerivation: selection.passwordDerivation.rawValue,
                G7Keys.ecParameter: selection.ecParameter.rawValue,
                G7Keys.bondingOrder: selection.bondingOrder.rawValue,
                G7Keys.sessionKeyDerivation: selection.sessionKeyDerivation.rawValue
            ]
        )
    }
    
    /// Extract G7 variant selection from configuration
    public var g7Selection: G7VariantSelection? {
        guard variantId == "dexcom.g7" else { return nil }
        
        return G7VariantSelection(
            passwordDerivation: setting(G7Keys.passwordDerivation)
                .flatMap { G7PasswordDerivationVariant(rawValue: $0) } ?? .standard,
            ecParameter: setting(G7Keys.ecParameter)
                .flatMap { G7ECParameterVariant(rawValue: $0) } ?? .p256Standard,
            bondingOrder: setting(G7Keys.bondingOrder)
                .flatMap { G7BondingOrderVariant(rawValue: $0) } ?? .authThenBond,
            sessionKeyDerivation: setting(G7Keys.sessionKeyDerivation)
                .flatMap { G7SessionKeyDerivationVariant(rawValue: $0) } ?? .hkdf
        )
    }
    
    /// Update with new G7 selection
    public func withG7Selection(_ selection: G7VariantSelection) -> VariantConfiguration {
        self
            .withOverride(G7Keys.passwordDerivation, value: selection.passwordDerivation.rawValue)
            .withOverride(G7Keys.ecParameter, value: selection.ecParameter.rawValue)
            .withOverride(G7Keys.bondingOrder, value: selection.bondingOrder.rawValue)
            .withOverride(G7Keys.sessionKeyDerivation, value: selection.sessionKeyDerivation.rawValue)
    }
}

// MARK: - G6 Variant Configuration Extension (UNCERT-G6-002)

extension VariantConfiguration {
    /// G6 variant selection keys
    private enum G6Keys {
        static let keyDerivation = "g6.keyDerivation"
        static let tokenHash = "g6.tokenHash"
        static let authOpcode = "g6.authOpcode"
    }
    
    /// Create configuration for G6 with type-safe variant selection
    public static func g6(
        selection: G6VariantSelection,
        enabled: Bool = true,
        priority: Int = 0
    ) -> VariantConfiguration {
        VariantConfiguration(
            variantId: "dexcom.g6",
            enabled: enabled,
            priority: priority,
            settings: [
                G6Keys.keyDerivation: selection.keyDerivation.rawValue,
                G6Keys.tokenHash: selection.tokenHash.rawValue,
                G6Keys.authOpcode: selection.authOpcode.rawValue
            ]
        )
    }
    
    /// Extract G6 variant selection from configuration
    public var g6Selection: G6VariantSelection? {
        guard variantId == "dexcom.g6" else { return nil }
        
        return G6VariantSelection(
            keyDerivation: setting(G6Keys.keyDerivation)
                .flatMap { G6KeyDerivationVariant(rawValue: $0) } ?? .asciiZeros,
            tokenHash: setting(G6Keys.tokenHash)
                .flatMap { G6TokenHashVariant(rawValue: $0) } ?? .doubled,
            authOpcode: setting(G6Keys.authOpcode)
                .flatMap { G6AuthOpcodeVariant(rawValue: $0) } ?? .g6Standard
        )
    }
    
    /// Update with new G6 selection
    public func withG6Selection(_ selection: G6VariantSelection) -> VariantConfiguration {
        self
            .withOverride(G6Keys.keyDerivation, value: selection.keyDerivation.rawValue)
            .withOverride(G6Keys.tokenHash, value: selection.tokenHash.rawValue)
            .withOverride(G6Keys.authOpcode, value: selection.authOpcode.rawValue)
    }
}

// MARK: - Libre 2 Variant Configuration Extension (UNCERT-L2-002)

extension VariantConfiguration {
    /// Libre 2 variant selection keys
    private enum Libre2Keys {
        static let cryptoConstant = "libre2.cryptoConstant"
        static let sensorType = "libre2.sensorType"
        static let unlock = "libre2.unlock"
        static let framXOR = "libre2.framXOR"
        static let calibration = "libre2.calibration"
    }
    
    /// Create configuration for Libre 2 with type-safe variant selection
    public static func libre2(
        selection: Libre2VariantSelection,
        enabled: Bool = true,
        priority: Int = 0
    ) -> VariantConfiguration {
        VariantConfiguration(
            variantId: "libre.2",
            enabled: enabled,
            priority: priority,
            settings: [
                Libre2Keys.cryptoConstant: selection.cryptoConstant.rawValue,
                Libre2Keys.sensorType: selection.sensorType.rawValue,
                Libre2Keys.unlock: selection.unlock.rawValue,
                Libre2Keys.framXOR: selection.framXOR.rawValue,
                Libre2Keys.calibration: selection.calibration.rawValue
            ]
        )
    }
    
    /// Extract Libre 2 variant selection from configuration
    public var libre2Selection: Libre2VariantSelection? {
        guard variantId == "libre.2" else { return nil }
        
        return Libre2VariantSelection(
            cryptoConstant: setting(Libre2Keys.cryptoConstant)
                .flatMap { Libre2CryptoConstantVariant(rawValue: $0) } ?? .libreTransmitter,
            sensorType: setting(Libre2Keys.sensorType)
                .flatMap { Libre2SensorTypeVariant(rawValue: $0) } ?? .standard,
            unlock: setting(Libre2Keys.unlock)
                .flatMap { Libre2UnlockVariant(rawValue: $0) } ?? .standard,
            framXOR: setting(Libre2Keys.framXOR)
                .flatMap { Libre2FRAMXORVariant(rawValue: $0) } ?? .standard,
            calibration: setting(Libre2Keys.calibration)
                .flatMap { Libre2CalibrationVariant(rawValue: $0) } ?? .polynomial
        )
    }
    
    /// Update with new Libre 2 selection
    public func withLibre2Selection(_ selection: Libre2VariantSelection) -> VariantConfiguration {
        self
            .withOverride(Libre2Keys.cryptoConstant, value: selection.cryptoConstant.rawValue)
            .withOverride(Libre2Keys.sensorType, value: selection.sensorType.rawValue)
            .withOverride(Libre2Keys.unlock, value: selection.unlock.rawValue)
            .withOverride(Libre2Keys.framXOR, value: selection.framXOR.rawValue)
            .withOverride(Libre2Keys.calibration, value: selection.calibration.rawValue)
    }
}

