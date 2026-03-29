// VariantRegistryTests.swift
// BLEKit Tests
//
// Tests for VariantRegistry protocol and implementations.
// INSTR-002: VariantRegistry protocol definition

import Testing
import Foundation
@testable import BLEKit

// MARK: - Capability Set Tests

@Suite("Capability Set")
struct CapabilitySetTests {
    
    @Test("Empty set has no capabilities")
    func emptySet() {
        let set = CapabilitySet.empty
        #expect(set.isEmpty)
        #expect(set.count == 0)
        #expect(!set.contains(.authentication))
    }
    
    @Test("Init with array")
    func initWithArray() {
        let set = CapabilitySet([.authentication, .encryption, .backfill])
        #expect(set.count == 3)
        #expect(set.contains(.authentication))
        #expect(set.contains(.encryption))
        #expect(set.contains(.backfill))
        #expect(!set.contains(.calibration))
    }
    
    @Test("Contains all checks")
    func containsAll() {
        let set = CapabilitySet([.authentication, .encryption, .backfill])
        #expect(set.containsAll([.authentication, .encryption]))
        #expect(set.containsAll([.backfill]))
        #expect(!set.containsAll([.authentication, .calibration]))
    }
    
    @Test("Contains any checks")
    func containsAny() {
        let set = CapabilitySet([.authentication, .encryption])
        #expect(set.containsAny([.authentication, .calibration]))
        #expect(set.containsAny([.encryption]))
        #expect(!set.containsAny([.calibration, .backfill]))
    }
    
    @Test("Insert and remove")
    func insertRemove() {
        var set = CapabilitySet.empty
        set.insert(.authentication)
        #expect(set.contains(.authentication))
        set.remove(.authentication)
        #expect(!set.contains(.authentication))
    }
    
    @Test("Union of sets")
    func union() {
        let set1 = CapabilitySet([.authentication, .encryption])
        let set2 = CapabilitySet([.backfill, .calibration])
        let union = set1.union(set2)
        #expect(union.count == 4)
        #expect(union.containsAll([.authentication, .encryption, .backfill, .calibration]))
    }
    
    @Test("Intersection of sets")
    func intersection() {
        let set1 = CapabilitySet([.authentication, .encryption, .backfill])
        let set2 = CapabilitySet([.encryption, .backfill, .calibration])
        let intersection = set1.intersection(set2)
        #expect(intersection.count == 2)
        #expect(intersection.containsAll([.encryption, .backfill]))
        #expect(!intersection.contains(.authentication))
    }
    
    @Test("Preset basic CGM")
    func presetBasicCGM() {
        let set = CapabilitySet.basicCGM
        #expect(set.contains(.glucoseReading))
        #expect(set.contains(.notifications))
        #expect(set.contains(.bonding))
        #expect(!set.contains(.encryption))
    }
    
    @Test("Preset full CGM")
    func presetFullCGM() {
        let set = CapabilitySet.fullCGM
        #expect(set.contains(.glucoseReading))
        #expect(set.contains(.rawReading))
        #expect(set.contains(.authentication))
        #expect(set.contains(.encryption))
        #expect(set.contains(.backfill))
    }
}

// MARK: - Protocol Variant Tests

@Suite("Protocol Variant")
struct ProtocolVariantTests {
    
    @Test("Create variant with defaults")
    func createWithDefaults() {
        let variant = ProtocolVariant(
            id: "test.variant",
            family: .dexcom,
            name: "Test Variant",
            version: "1.0"
        )
        #expect(variant.id == "test.variant")
        #expect(variant.family == .dexcom)
        #expect(variant.name == "Test Variant")
        #expect(variant.version == "1.0")
        #expect(variant.capabilities.isEmpty)
        #expect(variant.minFirmware == nil)
        #expect(!variant.deprecated)
        #expect(!variant.experimental)
    }
    
    @Test("Create variant with all options")
    func createWithAllOptions() {
        let variant = ProtocolVariant(
            id: "test.full",
            family: .libre,
            name: "Full Variant",
            version: "2.0",
            capabilities: .advancedCGM,
            minFirmware: "1.0.0",
            maxFirmware: "2.0.0",
            deprecated: true,
            experimental: false,
            metadata: ["key": "value"]
        )
        #expect(variant.id == "test.full")
        #expect(variant.family == .libre)
        #expect(variant.minFirmware == "1.0.0")
        #expect(variant.maxFirmware == "2.0.0")
        #expect(variant.deprecated)
        #expect(variant.metadata["key"] == "value")
    }
    
    @Test("Has capability")
    func hasCapability() {
        let variant = ProtocolVariant(
            id: "test",
            family: .dexcom,
            name: "Test",
            version: "1.0",
            capabilities: .advancedCGM
        )
        #expect(variant.hasCapability(.authentication))
        #expect(variant.hasCapability(.encryption))
        #expect(!variant.hasCapability(.firmwareUpdate))
    }
    
    @Test("Meets requirements")
    func meetsRequirements() {
        let variant = ProtocolVariant(
            id: "test",
            family: .dexcom,
            name: "Test",
            version: "1.0",
            capabilities: .advancedCGM
        )
        #expect(variant.meetsRequirements([.authentication, .encryption]))
        #expect(!variant.meetsRequirements([.authentication, .firmwareUpdate]))
    }
    
    @Test("Supports firmware range")
    func supportsFirmware() {
        let variant = ProtocolVariant(
            id: "test",
            family: .dexcom,
            name: "Test",
            version: "1.0",
            minFirmware: "1.0.0",
            maxFirmware: "2.0.0"
        )
        #expect(variant.supportsFirmware("1.5.0"))
        #expect(variant.supportsFirmware("1.0.0"))
        #expect(variant.supportsFirmware("2.0.0"))
        #expect(!variant.supportsFirmware("0.9.0"))
        #expect(!variant.supportsFirmware("2.1.0"))
    }
    
    @Test("Well-known Dexcom G6")
    func wellKnownG6() {
        let variant = ProtocolVariant.dexcomG6
        #expect(variant.id == "dexcom.g6")
        #expect(variant.family == .dexcom)
        #expect(variant.name == "Dexcom G6")
        #expect(variant.hasCapability(.authentication))
    }
    
    @Test("Well-known Dexcom G7")
    func wellKnownG7() {
        let variant = ProtocolVariant.dexcomG7
        #expect(variant.id == "dexcom.g7")
        #expect(variant.family == .dexcom)
        #expect(variant.name == "Dexcom G7")
        #expect(variant.hasCapability(.rawReading))
    }
    
    @Test("Well-known Libre 2")
    func wellKnownLibre2() {
        let variant = ProtocolVariant.libre2
        #expect(variant.id == "libre.2")
        #expect(variant.family == .libre)
        #expect(variant.name == "Libre 2")
    }
    
    @Test("Well-known Libre 3")
    func wellKnownLibre3() {
        let variant = ProtocolVariant.libre3
        #expect(variant.id == "libre.3")
        #expect(variant.family == .libre)
        #expect(variant.name == "Libre 3")
    }
}

// MARK: - Variant Match Tests

@Suite("Variant Match")
struct VariantMatchTests {
    
    @Test("Exact match")
    func exactMatch() {
        let match = VariantMatch.exact(.dexcomG6, reason: "Service UUID match")
        #expect(match.confidence == 1.0)
        #expect(match.isHighConfidence)
        #expect(!match.isMediumConfidence)
        #expect(!match.isLowConfidence)
        #expect(match.matchReason == "Service UUID match")
    }
    
    @Test("Probable match")
    func probableMatch() {
        let match = VariantMatch.probable(.dexcomG6, confidence: 0.8, reason: "Name match")
        #expect(match.confidence == 0.8)
        #expect(!match.isHighConfidence)
        #expect(match.isMediumConfidence)
        #expect(!match.isLowConfidence)
    }
    
    @Test("Uncertain match")
    func uncertainMatch() {
        let match = VariantMatch.uncertain(.libre2, reason: "Unknown version", 
                                           warnings: ["Version detection failed"])
        #expect(match.confidence == 0.5)
        #expect(!match.isHighConfidence)
        #expect(!match.isMediumConfidence)
        #expect(match.isLowConfidence)
        #expect(match.warnings.count == 1)
    }
    
    @Test("Confidence clamped to range")
    func confidenceClamped() {
        let high = VariantMatch(variant: .dexcomG6, confidence: 1.5, matchReason: "")
        #expect(high.confidence == 1.0)
        
        let low = VariantMatch(variant: .dexcomG6, confidence: -0.5, matchReason: "")
        #expect(low.confidence == 0.0)
    }
}

// MARK: - Device Context Tests

@Suite("Device Context")
struct DeviceContextTests {
    
    @Test("Create context")
    func createContext() {
        let context = DeviceContext(
            deviceId: "ABC123",
            name: "Dexcom G6",
            manufacturer: "Dexcom",
            model: "G6",
            firmware: "1.2.3"
        )
        #expect(context.deviceId == "ABC123")
        #expect(context.name == "Dexcom G6")
        #expect(context.manufacturer == "Dexcom")
    }
    
    @Test("Has service UUID")
    func hasService() {
        let context = DeviceContext(
            deviceId: "ABC123",
            serviceUUIDs: ["F8083532-849E-531C-C594-30F1F86A4EA5", "180A"]
        )
        #expect(context.hasService("F8083532-849E-531C-C594-30F1F86A4EA5"))
        #expect(context.hasService("f8083532-849e-531c-c594-30f1f86a4ea5"))
        #expect(context.hasService("180A"))
        #expect(!context.hasService("180B"))
    }
    
    @Test("Name contains check")
    func nameContains() {
        let context = DeviceContext(deviceId: "ABC", name: "Dexcom G6 Transmitter")
        #expect(context.nameContains("Dexcom"))
        #expect(context.nameContains("dexcom"))
        #expect(context.nameContains("G6"))
        #expect(!context.nameContains("Libre"))
    }
    
    @Test("Manufacturer is check")
    func manufacturerIs() {
        let context = DeviceContext(deviceId: "ABC", manufacturer: "Dexcom")
        #expect(context.manufacturerIs("Dexcom"))
        #expect(context.manufacturerIs("dexcom"))
        #expect(!context.manufacturerIs("Abbott"))
    }
}

// MARK: - Dexcom Matcher Tests

@Suite("Dexcom Matcher")
struct DexcomMatcherTests {
    let matcher = DexcomMatcher()
    
    @Test("Matcher properties")
    func matcherProperties() {
        #expect(matcher.matcherId == "dexcom")
        #expect(matcher.family == .dexcom)
    }
    
    @Test("Can handle Dexcom by name")
    func canHandleByName() {
        let context = DeviceContext(deviceId: "ABC", name: "Dexcom G6")
        #expect(matcher.canHandle(context: context))
    }
    
    @Test("Can handle Dexcom by manufacturer")
    func canHandleByManufacturer() {
        let context = DeviceContext(deviceId: "ABC", manufacturer: "Dexcom")
        #expect(matcher.canHandle(context: context))
    }
    
    @Test("Match G6 by name")
    func matchG6ByName() {
        let context = DeviceContext(deviceId: "ABC", name: "Dexcom G6")
        let match = matcher.match(context: context)
        #expect(match != nil)
        #expect(match?.variant.id == "dexcom.g6")
        #expect(match?.confidence == 1.0)
    }
    
    @Test("Match G7 by name")
    func matchG7ByName() {
        let context = DeviceContext(deviceId: "ABC", name: "Dexcom G7")
        let match = matcher.match(context: context)
        #expect(match != nil)
        #expect(match?.variant.id == "dexcom.g7")
        #expect(match?.confidence == 1.0)
    }
    
    @Test("Match G6 by service UUID")
    func matchG6ByService() {
        let context = DeviceContext(
            deviceId: "ABC",
            serviceUUIDs: ["F8083532-849E-531C-C594-30F1F86A4EA5"]
        )
        let match = matcher.match(context: context)
        #expect(match != nil)
        #expect(match?.variant.id == "dexcom.g6")
    }
    
    @Test("No match for non-Dexcom")
    func noMatchNonDexcom() {
        let context = DeviceContext(deviceId: "ABC", name: "Libre 2")
        let match = matcher.match(context: context)
        #expect(match == nil)
    }
}

// MARK: - Libre Matcher Tests

@Suite("Libre Matcher")
struct LibreMatcherTests {
    let matcher = LibreMatcher()
    
    @Test("Matcher properties")
    func matcherProperties() {
        #expect(matcher.matcherId == "libre")
        #expect(matcher.family == .libre)
    }
    
    @Test("Can handle Libre by name")
    func canHandleByName() {
        let context = DeviceContext(deviceId: "ABC", name: "Libre 2")
        #expect(matcher.canHandle(context: context))
    }
    
    @Test("Can handle by manufacturer")
    func canHandleByManufacturer() {
        let context = DeviceContext(deviceId: "ABC", manufacturer: "Abbott")
        #expect(matcher.canHandle(context: context))
    }
    
    @Test("Match Libre 2 by name")
    func matchLibre2() {
        let context = DeviceContext(deviceId: "ABC", name: "Libre 2")
        let match = matcher.match(context: context)
        #expect(match != nil)
        #expect(match?.variant.id == "libre.2")
        #expect(match?.confidence == 1.0)
    }
    
    @Test("Match Libre 3 by name")
    func matchLibre3() {
        let context = DeviceContext(deviceId: "ABC", name: "Libre 3")
        let match = matcher.match(context: context)
        #expect(match != nil)
        #expect(match?.variant.id == "libre.3")
        #expect(match?.confidence == 1.0)
    }
    
    @Test("Generic Libre uncertain match")
    func genericLibreUncertain() {
        let context = DeviceContext(deviceId: "ABC", name: "Libre Sensor")
        let match = matcher.match(context: context)
        #expect(match != nil)
        #expect(match?.confidence == 0.5)
        #expect(match?.warnings.count == 1)
    }
}

// MARK: - Variant Configuration Tests

@Suite("Variant Configuration")
struct VariantConfigurationTests {
    
    @Test("Default configuration")
    func defaultConfig() {
        let config = VariantConfiguration.default(for: "test")
        #expect(config.variantId == "test")
        #expect(config.enabled)
        #expect(config.priority == 0)
        #expect(config.settings.isEmpty)
    }
    
    @Test("Get setting with override")
    func settingWithOverride() {
        let config = VariantConfiguration(
            variantId: "test",
            settings: ["key": "original"],
            overrides: ["key": "overridden"]
        )
        #expect(config.setting("key") == "overridden")
    }
    
    @Test("Get setting without override")
    func settingWithoutOverride() {
        let config = VariantConfiguration(
            variantId: "test",
            settings: ["key": "original"]
        )
        #expect(config.setting("key") == "original")
    }
    
    @Test("With override")
    func withOverride() {
        let config = VariantConfiguration.default(for: "test")
        let updated = config.withOverride("key", value: "value")
        #expect(updated.setting("key") == "value")
    }
    
    @Test("With enabled")
    func withEnabled() {
        let config = VariantConfiguration.default(for: "test")
        let disabled = config.withEnabled(false)
        #expect(!disabled.enabled)
    }
    
    @Test("With priority")
    func withPriority() {
        let config = VariantConfiguration.default(for: "test")
        let prioritized = config.withPriority(10)
        #expect(prioritized.priority == 10)
    }
}

// MARK: - Standard Variant Registry Tests

@Suite("Standard Variant Registry")
struct StandardVariantRegistryTests {
    
    @Test("Register and retrieve variant")
    func registerAndRetrieve() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        
        let variant = await registry.variant(id: "dexcom.g6")
        #expect(variant != nil)
        #expect(variant?.id == "dexcom.g6")
    }
    
    @Test("Unregister variant")
    func unregister() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        
        let removed = await registry.unregister(variantId: "dexcom.g6")
        #expect(removed)
        
        let variant = await registry.variant(id: "dexcom.g6")
        #expect(variant == nil)
    }
    
    @Test("Unregister non-existent returns false")
    func unregisterNonExistent() async {
        let registry = StandardVariantRegistry()
        let removed = await registry.unregister(variantId: "nonexistent")
        #expect(!removed)
    }
    
    @Test("Register with configuration")
    func registerWithConfig() async {
        let registry = StandardVariantRegistry()
        let config = VariantConfiguration(variantId: "dexcom.g6", enabled: false, priority: 5)
        await registry.register(.dexcomG6, configuration: config)
        
        let retrieved = await registry.configuration(for: "dexcom.g6")
        #expect(retrieved?.enabled == false)
        #expect(retrieved?.priority == 5)
    }
    
    @Test("Update configuration")
    func updateConfig() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        
        let newConfig = VariantConfiguration(variantId: "dexcom.g6", enabled: false)
        await registry.updateConfiguration(newConfig)
        
        let config = await registry.configuration(for: "dexcom.g6")
        #expect(config?.enabled == false)
    }
    
    @Test("All variants")
    func allVariants() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        await registry.register(.dexcomG7)
        await registry.register(.libre2)
        
        let all = await registry.allVariants()
        #expect(all.count == 3)
    }
    
    @Test("Variants by family")
    func variantsByFamily() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        await registry.register(.dexcomG7)
        await registry.register(.libre2)
        
        let dexcom = await registry.variants(family: .dexcom)
        #expect(dexcom.count == 2)
        
        let libre = await registry.variants(family: .libre)
        #expect(libre.count == 1)
    }
    
    @Test("Variants with capability")
    func variantsWithCapability() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        await registry.register(.dexcomG7)
        
        let withRaw = await registry.variants(withCapability: .rawReading)
        #expect(withRaw.count == 1)
        #expect(withRaw.first?.id == "dexcom.g7")
    }
    
    @Test("Enabled variants only")
    func enabledVariants() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        let disabledConfig = VariantConfiguration(variantId: "dexcom.g7", enabled: false)
        await registry.register(.dexcomG7, configuration: disabledConfig)
        
        let enabled = await registry.enabledVariants()
        #expect(enabled.count == 1)
        #expect(enabled.first?.id == "dexcom.g6")
    }
    
    @Test("Is registered check")
    func isRegistered() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        
        #expect(await registry.isRegistered(variantId: "dexcom.g6"))
        #expect(!(await registry.isRegistered(variantId: "nonexistent")))
    }
    
    @Test("Register and use matcher")
    func registerMatcher() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        await registry.register(.dexcomG7)
        await registry.registerMatcher(DexcomMatcher())
        
        let context = DeviceContext(deviceId: "ABC", name: "Dexcom G7")
        let match = await registry.match(context: context)
        #expect(match != nil)
        #expect(match?.variant.id == "dexcom.g7")
    }
    
    @Test("All matches sorted by confidence")
    func allMatchesSorted() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        await registry.register(.libre2)
        await registry.registerMatcher(DexcomMatcher())
        await registry.registerMatcher(LibreMatcher())
        
        let context = DeviceContext(deviceId: "ABC", name: "Dexcom G6")
        let matches = await registry.allMatches(context: context)
        #expect(matches.count == 1)
        #expect(matches.first?.confidence == 1.0)
    }
    
    @Test("Statistics")
    func statistics() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        await registry.register(.dexcomG7)
        await registry.register(.libre2)
        await registry.registerMatcher(DexcomMatcher())
        
        let stats = await registry.statistics()
        #expect(stats.totalVariants == 3)
        #expect(stats.enabledVariants == 3)
        #expect(stats.matcherCount == 1)
        #expect(stats.variantsByFamily[.dexcom] == 2)
        #expect(stats.variantsByFamily[.libre] == 1)
    }
    
    @Test("Clear registry")
    func clear() async {
        let registry = StandardVariantRegistry()
        await registry.register(.dexcomG6)
        await registry.register(.dexcomG7)
        await registry.registerMatcher(DexcomMatcher())
        
        await registry.clear()
        
        let all = await registry.allVariants()
        #expect(all.isEmpty)
        
        let stats = await registry.statistics()
        #expect(stats.matcherCount == 0)
    }
}

// MARK: - Composite Variant Registry Tests

@Suite("Composite Variant Registry")
struct CompositeVariantRegistryTests {
    
    @Test("Lookup from primary")
    func lookupFromPrimary() async {
        let primary = StandardVariantRegistry()
        await primary.register(.dexcomG6)
        
        let composite = CompositeVariantRegistry(primary: primary)
        let variant = await composite.variant(id: "dexcom.g6")
        #expect(variant != nil)
    }
    
    @Test("Lookup from secondary")
    func lookupFromSecondary() async {
        let primary = StandardVariantRegistry()
        let secondary = StandardVariantRegistry()
        await secondary.register(.libre2)
        
        let composite = CompositeVariantRegistry(primary: primary, secondaries: [secondary])
        let variant = await composite.variant(id: "libre.2")
        #expect(variant != nil)
    }
    
    @Test("Registration goes to primary")
    func registrationToPrimary() async {
        let primary = StandardVariantRegistry()
        let composite = CompositeVariantRegistry(primary: primary)
        
        await composite.register(.dexcomG6)
        
        let variant = await primary.variant(id: "dexcom.g6")
        #expect(variant != nil)
    }
    
    @Test("All variants deduplicates")
    func allVariantsDeduplicates() async {
        let primary = StandardVariantRegistry()
        await primary.register(.dexcomG6)
        
        let secondary = StandardVariantRegistry()
        await secondary.register(.dexcomG6)
        await secondary.register(.libre2)
        
        let composite = CompositeVariantRegistry(primary: primary, secondaries: [secondary])
        let all = await composite.allVariants()
        #expect(all.count == 2)
    }
    
    @Test("Best match from all registries")
    func bestMatchFromAll() async {
        let primary = StandardVariantRegistry()
        await primary.registerMatcher(DexcomMatcher())
        
        let secondary = StandardVariantRegistry()
        await secondary.registerMatcher(LibreMatcher())
        
        let composite = CompositeVariantRegistry(primary: primary, secondaries: [secondary])
        
        let context = DeviceContext(deviceId: "ABC", name: "Libre 3")
        let match = await composite.match(context: context)
        #expect(match != nil)
        #expect(match?.variant.id == "libre.3")
    }
}

// MARK: - Read-Only Variant Registry Tests

@Suite("Read-Only Variant Registry")
struct ReadOnlyVariantRegistryTests {
    
    @Test("Can read variants")
    func canRead() async {
        let inner = StandardVariantRegistry()
        await inner.register(.dexcomG6)
        
        let readOnly = ReadOnlyVariantRegistry(wrapping: inner)
        let variant = await readOnly.variant(id: "dexcom.g6")
        #expect(variant != nil)
    }
    
    @Test("Register is no-op")
    func registerNoOp() async {
        let inner = StandardVariantRegistry()
        let readOnly = ReadOnlyVariantRegistry(wrapping: inner)
        
        await readOnly.register(.dexcomG7)
        
        let variant = await inner.variant(id: "dexcom.g7")
        #expect(variant == nil)
    }
    
    @Test("Unregister returns false")
    func unregisterFalse() async {
        let inner = StandardVariantRegistry()
        await inner.register(.dexcomG6)
        
        let readOnly = ReadOnlyVariantRegistry(wrapping: inner)
        let removed = await readOnly.unregister(variantId: "dexcom.g6")
        #expect(!removed)
        
        let variant = await inner.variant(id: "dexcom.g6")
        #expect(variant != nil)
    }
    
    @Test("Clear is no-op")
    func clearNoOp() async {
        let inner = StandardVariantRegistry()
        await inner.register(.dexcomG6)
        
        let readOnly = ReadOnlyVariantRegistry(wrapping: inner)
        await readOnly.clear()
        
        let all = await inner.allVariants()
        #expect(all.count == 1)
    }
}

// MARK: - Variant Selection Strategy Tests

@Suite("Variant Selection Strategy")
struct VariantSelectionStrategyTests {
    
    @Test("Highest confidence selects best match")
    func highestConfidence() {
        let matches = [
            VariantMatch(variant: .dexcomG6, confidence: 0.7, matchReason: ""),
            VariantMatch(variant: .dexcomG7, confidence: 0.9, matchReason: ""),
            VariantMatch(variant: .libre2, confidence: 0.5, matchReason: "")
        ]
        
        let selected = VariantSelectionStrategy.highestConfidence.select(from: matches)
        #expect(selected?.variant.id == "dexcom.g7")
    }
    
    @Test("Prefer stable excludes experimental")
    func preferStable() {
        let experimental = ProtocolVariant(
            id: "test.exp",
            family: .dexcom,
            name: "Experimental",
            version: "1.0",
            experimental: true
        )
        
        let matches = [
            VariantMatch(variant: experimental, confidence: 0.9, matchReason: ""),
            VariantMatch(variant: .dexcomG6, confidence: 0.8, matchReason: "")
        ]
        
        let selected = VariantSelectionStrategy.preferStable.select(from: matches)
        #expect(selected?.variant.id == "dexcom.g6")
    }
    
    @Test("Prefer experimental prioritizes it")
    func preferExperimental() {
        let experimental = ProtocolVariant(
            id: "test.exp",
            family: .dexcom,
            name: "Experimental",
            version: "1.0",
            experimental: true
        )
        
        let matches = [
            VariantMatch(variant: .dexcomG6, confidence: 0.9, matchReason: ""),
            VariantMatch(variant: experimental, confidence: 0.8, matchReason: "")
        ]
        
        let selected = VariantSelectionStrategy.preferExperimental.select(from: matches)
        #expect(selected?.variant.id == "test.exp")
    }
    
    @Test("By family filters")
    func byFamily() {
        let matches = [
            VariantMatch(variant: .dexcomG6, confidence: 0.9, matchReason: ""),
            VariantMatch(variant: .libre2, confidence: 0.8, matchReason: "")
        ]
        
        let selected = VariantSelectionStrategy.byFamily(.libre).select(from: matches)
        #expect(selected?.variant.id == "libre.2")
    }
    
    @Test("Empty matches returns nil")
    func emptyReturnsNil() {
        let selected = VariantSelectionStrategy.highestConfidence.select(from: [])
        #expect(selected == nil)
    }
}

// MARK: - Variant Builder Tests

@Suite("Variant Builder")
struct VariantBuilderTests {
    
    @Test("Build with defaults")
    func buildDefaults() {
        let variant = VariantBuilder(id: "test")
            .build()
        
        #expect(variant.id == "test")
        #expect(variant.name == "test")
        #expect(variant.family == .unknown)
        #expect(variant.version == "1.0")
    }
    
    @Test("Build with all options")
    func buildAllOptions() {
        let variant = VariantBuilder(id: "custom.variant")
            .family(.dexcom)
            .name("Custom Variant")
            .version("2.0")
            .capabilities(.advancedCGM)
            .capability(.firmwareUpdate)
            .minFirmware("1.0.0")
            .maxFirmware("3.0.0")
            .deprecated(true)
            .experimental(false)
            .metadata("key", "value")
            .build()
        
        #expect(variant.id == "custom.variant")
        #expect(variant.family == .dexcom)
        #expect(variant.name == "Custom Variant")
        #expect(variant.version == "2.0")
        #expect(variant.hasCapability(.authentication))
        #expect(variant.hasCapability(.firmwareUpdate))
        #expect(variant.minFirmware == "1.0.0")
        #expect(variant.maxFirmware == "3.0.0")
        #expect(variant.deprecated)
        #expect(!variant.experimental)
        #expect(variant.metadata["key"] == "value")
    }
    
    @Test("Fluent API is immutable")
    func fluentImmutable() {
        let builder1 = VariantBuilder(id: "test")
        let builder2 = builder1.name("Updated")
        
        let variant1 = builder1.build()
        let variant2 = builder2.build()
        
        #expect(variant1.name == "test")
        #expect(variant2.name == "Updated")
    }
}

// MARK: - Protocol Family Tests

@Suite("Protocol Family")
struct ProtocolFamilyTests {
    
    @Test("All cases available")
    func allCases() {
        let cases = ProtocolFamily.allCases
        #expect(cases.contains(.dexcom))
        #expect(cases.contains(.libre))
        #expect(cases.contains(.medtronic))
        #expect(cases.contains(.omnipod))
        #expect(cases.contains(.tandem))
        #expect(cases.contains(.dana))
        #expect(cases.contains(.unknown))
    }
    
    @Test("Raw value encoding")
    func rawValue() {
        #expect(ProtocolFamily.dexcom.rawValue == "dexcom")
        #expect(ProtocolFamily.libre.rawValue == "libre")
    }
}

// MARK: - Variant Capability Tests

@Suite("Variant Capability")
struct VariantCapabilityTests {
    
    @Test("All cases available")
    func allCases() {
        let cases = VariantCapability.allCases
        #expect(cases.contains(.authentication))
        #expect(cases.contains(.encryption))
        #expect(cases.contains(.glucoseReading))
        #expect(cases.count >= 20)
    }
    
    @Test("Raw value encoding")
    func rawValue() {
        #expect(VariantCapability.authentication.rawValue == "authentication")
        #expect(VariantCapability.glucoseReading.rawValue == "glucoseReading")
    }
}
