// SPDX-License-Identifier: AGPL-3.0-or-later
// VariantRegistryImplementations.swift - Registry implementations
// Extracted from VariantRegistry.swift (BLE-REFACTOR-003)
// Trace: INSTR-002

import Foundation

// MARK: - Standard Variant Registry

/// Thread-safe implementation of VariantRegistry.
public actor StandardVariantRegistry: VariantRegistry {
    private var variants: [String: ProtocolVariant] = [:]
    private var configurations: [String: VariantConfiguration] = [:]
    private var matchers: [VariantMatcher] = []
    
    public init() {}
    
    /// Create registry with default variants.
    public static func withDefaults() -> StandardVariantRegistry {
        let registry = StandardVariantRegistry()
        Task {
            await registry.register(.dexcomG6)
            await registry.register(.dexcomG7)
            await registry.register(.libre2)
            await registry.register(.libre3)
            await registry.registerMatcher(DexcomMatcher())
            await registry.registerMatcher(LibreMatcher())
        }
        return registry
    }
    
    public func register(_ variant: ProtocolVariant) async {
        variants[variant.id] = variant
        if configurations[variant.id] == nil {
            configurations[variant.id] = .default(for: variant.id)
        }
    }
    
    public func register(_ variant: ProtocolVariant, configuration: VariantConfiguration) async {
        variants[variant.id] = variant
        configurations[variant.id] = configuration
    }
    
    public func unregister(variantId: String) async -> Bool {
        let existed = variants.removeValue(forKey: variantId) != nil
        configurations.removeValue(forKey: variantId)
        return existed
    }
    
    public func variant(id: String) async -> ProtocolVariant? {
        variants[id]
    }
    
    public func configuration(for variantId: String) async -> VariantConfiguration? {
        configurations[variantId]
    }
    
    public func updateConfiguration(_ configuration: VariantConfiguration) async {
        configurations[configuration.variantId] = configuration
    }
    
    public func allVariants() async -> [ProtocolVariant] {
        Array(variants.values)
    }
    
    public func variants(family: ProtocolFamily) async -> [ProtocolVariant] {
        variants.values.filter { $0.family == family }
    }
    
    public func variants(withCapability capability: VariantCapability) async -> [ProtocolVariant] {
        variants.values.filter { $0.hasCapability(capability) }
    }
    
    public func enabledVariants() async -> [ProtocolVariant] {
        variants.values.filter { variant in
            configurations[variant.id]?.enabled ?? true
        }
    }
    
    public func isRegistered(variantId: String) async -> Bool {
        variants[variantId] != nil
    }
    
    public func registerMatcher(_ matcher: VariantMatcher) async {
        matchers.append(matcher)
    }
    
    public func match(context: DeviceContext) async -> VariantMatch? {
        let matches = await allMatches(context: context)
        return matches.first
    }
    
    public func allMatches(context: DeviceContext) async -> [VariantMatch] {
        var results: [VariantMatch] = []
        
        for matcher in matchers {
            if let match = matcher.match(context: context) {
                results.append(match)
            }
        }
        
        return results.sorted { $0.confidence > $1.confidence }
    }
    
    public func statistics() async -> RegistryStatistics {
        var byFamily: [ProtocolFamily: Int] = [:]
        var enabled = 0
        var deprecated = 0
        var experimental = 0
        
        for variant in variants.values {
            byFamily[variant.family, default: 0] += 1
            if configurations[variant.id]?.enabled ?? true { enabled += 1 }
            if variant.deprecated { deprecated += 1 }
            if variant.experimental { experimental += 1 }
        }
        
        return RegistryStatistics(
            totalVariants: variants.count,
            enabledVariants: enabled,
            deprecatedVariants: deprecated,
            experimentalVariants: experimental,
            variantsByFamily: byFamily,
            matcherCount: matchers.count
        )
    }
    
    public func clear() async {
        variants.removeAll()
        configurations.removeAll()
        matchers.removeAll()
    }
}

// MARK: - Composite Variant Registry

/// Registry that delegates to multiple registries.
public actor CompositeVariantRegistry: VariantRegistry {
    private var registries: [VariantRegistry]
    private var primaryRegistry: VariantRegistry
    
    public init(primary: VariantRegistry, secondaries: [VariantRegistry] = []) {
        self.primaryRegistry = primary
        self.registries = [primary] + secondaries
    }
    
    public func register(_ variant: ProtocolVariant) async {
        await primaryRegistry.register(variant)
    }
    
    public func register(_ variant: ProtocolVariant, configuration: VariantConfiguration) async {
        await primaryRegistry.register(variant, configuration: configuration)
    }
    
    public func unregister(variantId: String) async -> Bool {
        await primaryRegistry.unregister(variantId: variantId)
    }
    
    public func variant(id: String) async -> ProtocolVariant? {
        for registry in registries {
            if let variant = await registry.variant(id: id) {
                return variant
            }
        }
        return nil
    }
    
    public func configuration(for variantId: String) async -> VariantConfiguration? {
        for registry in registries {
            if let config = await registry.configuration(for: variantId) {
                return config
            }
        }
        return nil
    }
    
    public func updateConfiguration(_ configuration: VariantConfiguration) async {
        await primaryRegistry.updateConfiguration(configuration)
    }
    
    public func allVariants() async -> [ProtocolVariant] {
        var seen = Set<String>()
        var result: [ProtocolVariant] = []
        
        for registry in registries {
            for variant in await registry.allVariants() {
                if !seen.contains(variant.id) {
                    seen.insert(variant.id)
                    result.append(variant)
                }
            }
        }
        
        return result
    }
    
    public func variants(family: ProtocolFamily) async -> [ProtocolVariant] {
        var seen = Set<String>()
        var result: [ProtocolVariant] = []
        
        for registry in registries {
            for variant in await registry.variants(family: family) {
                if !seen.contains(variant.id) {
                    seen.insert(variant.id)
                    result.append(variant)
                }
            }
        }
        
        return result
    }
    
    public func variants(withCapability capability: VariantCapability) async -> [ProtocolVariant] {
        var seen = Set<String>()
        var result: [ProtocolVariant] = []
        
        for registry in registries {
            for variant in await registry.variants(withCapability: capability) {
                if !seen.contains(variant.id) {
                    seen.insert(variant.id)
                    result.append(variant)
                }
            }
        }
        
        return result
    }
    
    public func enabledVariants() async -> [ProtocolVariant] {
        var seen = Set<String>()
        var result: [ProtocolVariant] = []
        
        for registry in registries {
            for variant in await registry.enabledVariants() {
                if !seen.contains(variant.id) {
                    seen.insert(variant.id)
                    result.append(variant)
                }
            }
        }
        
        return result
    }
    
    public func isRegistered(variantId: String) async -> Bool {
        for registry in registries {
            if await registry.isRegistered(variantId: variantId) {
                return true
            }
        }
        return false
    }
    
    public func registerMatcher(_ matcher: VariantMatcher) async {
        await primaryRegistry.registerMatcher(matcher)
    }
    
    public func match(context: DeviceContext) async -> VariantMatch? {
        var bestMatch: VariantMatch?
        
        for registry in registries {
            if let match = await registry.match(context: context) {
                if bestMatch == nil || match.confidence > bestMatch!.confidence {
                    bestMatch = match
                }
            }
        }
        
        return bestMatch
    }
    
    public func allMatches(context: DeviceContext) async -> [VariantMatch] {
        var allMatches: [VariantMatch] = []
        
        for registry in registries {
            allMatches.append(contentsOf: await registry.allMatches(context: context))
        }
        
        return allMatches.sorted { $0.confidence > $1.confidence }
    }
    
    public func statistics() async -> RegistryStatistics {
        await primaryRegistry.statistics()
    }
    
    public func clear() async {
        for registry in registries {
            await registry.clear()
        }
    }
}

// MARK: - Read-Only Variant Registry

/// Registry that wraps another registry as read-only.
public actor ReadOnlyVariantRegistry: VariantRegistry {
    private let wrapped: VariantRegistry
    
    public init(wrapping registry: VariantRegistry) {
        self.wrapped = registry
    }
    
    public func register(_ variant: ProtocolVariant) async {
        // No-op for read-only
    }
    
    public func register(_ variant: ProtocolVariant, configuration: VariantConfiguration) async {
        // No-op for read-only
    }
    
    public func unregister(variantId: String) async -> Bool {
        false // Always returns false for read-only
    }
    
    public func variant(id: String) async -> ProtocolVariant? {
        await wrapped.variant(id: id)
    }
    
    public func configuration(for variantId: String) async -> VariantConfiguration? {
        await wrapped.configuration(for: variantId)
    }
    
    public func updateConfiguration(_ configuration: VariantConfiguration) async {
        // No-op for read-only
    }
    
    public func allVariants() async -> [ProtocolVariant] {
        await wrapped.allVariants()
    }
    
    public func variants(family: ProtocolFamily) async -> [ProtocolVariant] {
        await wrapped.variants(family: family)
    }
    
    public func variants(withCapability capability: VariantCapability) async -> [ProtocolVariant] {
        await wrapped.variants(withCapability: capability)
    }
    
    public func enabledVariants() async -> [ProtocolVariant] {
        await wrapped.enabledVariants()
    }
    
    public func isRegistered(variantId: String) async -> Bool {
        await wrapped.isRegistered(variantId: variantId)
    }
    
    public func registerMatcher(_ matcher: VariantMatcher) async {
        // No-op for read-only
    }
    
    public func match(context: DeviceContext) async -> VariantMatch? {
        await wrapped.match(context: context)
    }
    
    public func allMatches(context: DeviceContext) async -> [VariantMatch] {
        await wrapped.allMatches(context: context)
    }
    
    public func statistics() async -> RegistryStatistics {
        await wrapped.statistics()
    }
    
    public func clear() async {
        // No-op for read-only
    }
}

