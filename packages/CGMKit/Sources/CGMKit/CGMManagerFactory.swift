// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CGMManagerFactory.swift
// T1Pal Mobile
//
// Factory for creating CGMManager based on DataContext configuration
// Trace: BLE-CTX-023, PRD-021

import Foundation
import T1PalCore
import BLEKit

// MARK: - CGM Manager Callbacks

/// Callbacks for CGM manager events that need to be wired at creation time
/// Closures cannot be stored in BLEDeviceConfig (Codable), so they're passed separately.
/// Trace: CGM-066f
public struct CGMManagerCallbacks: Sendable {
    /// Called when a new App Level Key is generated and accepted by transmitter
    /// App should persist this key to Keychain for future sessions.
    /// Trace: CGM-066f, docs/protocols/APP-LEVEL-KEY-PROTOCOL.md
    public var onAppLevelKeyChanged: (@Sendable (Data) -> Void)?
    
    public init(
        onAppLevelKeyChanged: (@Sendable (Data) -> Void)? = nil
    ) {
        self.onAppLevelKeyChanged = onAppLevelKeyChanged
    }
}

/// Factory for creating CGMManager instances based on DataContext
/// Trace: BLE-CTX-023
public enum CGMManagerFactory {
    
    /// Create a CGMManager based on the current DataContext
    /// Uses async for BLE to ensure MainActor creation (BLE-ARCH-001)
    /// ARCH-007: Throws on configuration errors (no silent fallback)
    /// - Parameter context: The data context configuration
    /// - Returns: Appropriate CGMManager instance
    /// - Throws: CGMError.configurationRequired if required config is missing
    public static func create(for context: DataContext) async throws -> any CGMManagerProtocol {
        try await create(for: context, callbacks: nil)
    }
    
    /// Create a CGMManager with optional callbacks
    /// Trace: CGM-066f - Allows wiring persistence callbacks at creation time
    /// - Parameters:
    ///   - context: The data context configuration
    ///   - callbacks: Optional callbacks for persistence and events
    /// - Returns: Appropriate CGMManager instance
    /// - Throws: CGMError.configurationRequired if required config is missing
    public static func create(for context: DataContext, callbacks: CGMManagerCallbacks?) async throws -> any CGMManagerProtocol {
        switch context.sourceType {
        case .demo:
            return createSimulatedManager(pattern: context.simulationPattern)
            
        case .fixture:
            return createReplayManager()
            
        case .liveNS:
            return try createNightscoutManager(context: context)
            
        case .healthKit:
            return createHealthKitManager()
            
        case .ble:
            // ARCH-007: Fail explicit if BLE requested but not configured
            guard let bleConfig = context.bleConfig else {
                throw CGMError.configurationRequired("BLE mode requires bleConfig")
            }
            return try await createBLEManager(config: bleConfig, callbacks: callbacks)
            
        case .blePassive:
            // Passive BLE mode - observe ads, read glucose from HealthKit
            return createHealthKitManager()
            
        case .appGroup:
            // Read from shared app group (Loop/Trio/xDrip)
            return AppGroupCGMManager()
        }
    }
    
    /// Create a simulated CGM manager for demo mode
    private static func createSimulatedManager(pattern: String?) -> any CGMManagerProtocol {
        // Use a fixture file for simulation
        let config = ReplayCGMConfig(
            filePath: "demo-glucose.json",
            timeCompression: 60.0, // 1 minute = 1 second
            loopPlayback: true
        )
        return ReplayCGM(config: config)
    }
    
    /// Create a replay CGM manager for fixture mode
    private static func createReplayManager() -> any CGMManagerProtocol {
        let config = ReplayCGMConfig(
            filePath: "fixture-glucose.json",
            timeCompression: 1.0,
            loopPlayback: false
        )
        return ReplayCGM(config: config)
    }
    
    /// Create a Nightscout follower manager
    /// ARCH-007: Throws if NS URL not configured (no silent fallback to simulation)
    private static func createNightscoutManager(context: DataContext) throws -> any CGMManagerProtocol {
        guard let url = context.nightscoutURL else {
            throw CGMError.configurationRequired("Nightscout mode requires nightscoutURL")
        }
        
        let config = NightscoutFollowerConfig(
            url: url,
            apiSecret: nil,
            token: context.nightscoutToken,
            fetchIntervalSeconds: 60
        )
        return NightscoutFollowerCGM(config: config)
    }
    
    /// Create a HealthKit CGM manager
    private static func createHealthKitManager() -> any CGMManagerProtocol {
        return HealthKitCGMManager()
    }
    
    /// Create a BLE CGM manager based on device configuration
    /// Uses async for MainActor BLE central creation (BLE-ARCH-001)
    /// G7-COEX-FIX-001: Throws for configuration errors (no silent fallback)
    /// G7-PASSIVE-010: Waits for BLE to be powered on before returning
    /// CGM-066f: Accepts callbacks for persistence wiring
    private static func createBLEManager(config: BLEDeviceConfig, callbacks: CGMManagerCallbacks?) async throws -> any CGMManagerProtocol {
        let central = await BLECentralFactory.createAsync()
        
        // G7-PASSIVE-010: Wait for BLE to be ready before returning manager
        // This ensures startScanning() won't fail immediately
        let bleReady = await waitForBLEReady(central: central)
        if !bleReady {
            _ = await central.state
            throw CGMError.bluetoothUnavailable
        }
        
        switch config.cgmType {
        case .dexcomG6:
            return await createDexcomG6Manager(config: config, central: central, callbacks: callbacks)
            
        case .dexcomG7, .dexcomONEPlus:
            // G7-COEX-FIX-001: Coexistence mode doesn't need sensorCode
            // (Dexcom app handles auth; we just subscribe to characteristic)
            switch config.connectionMode {
            case .coexistence:
                // Use placeholder - manager handles "COEXISTENCE" specially
                return createDexcomG7ManagerForCoexistence(config: config, central: central)
            case .direct:
                // Direct mode requires both sensorCode (for J-PAKE) and serial
                guard config.sensorCode != nil, config.transmitterId != nil else {
                    // ARCH-007: Explicit error, no silent HealthKit fallback
                    throw CGMError.configurationRequired(
                        "G7 direct mode requires sensorCode and transmitterId"
                    )
                }
                guard let manager = createDexcomG7Manager(config: config, central: central) else {
                    throw CGMError.configurationRequired(
                        "G7 direct mode: failed to create manager"
                    )
                }
                return manager
            default:
                // Other modes (passiveBLE, healthKitObserver) - route to HealthKit
                return createHealthKitManager()
            }
            
        case .libre2, .libre3:
            // LIBRE-IMPL-003: Wire Libre3Manager with BLECentral
            if config.cgmType == .libre3 {
                return createLibre3Manager(config: config, central: central)
            }
            // Libre 2 requires NFC-scanned sensor info - use HealthKit for now
            return createHealthKitManager()
            
        case .miaomiao, .bubble:
            // Bridge devices - use HealthKit for now
            return createHealthKitManager()
        }
    }
    
    // MARK: - BLE Manager Creators
    
    /// CGM-066f: Wire callbacks including onAppLevelKeyChanged for ALK persistence
    private static func createDexcomG6Manager(config: BLEDeviceConfig, central: any BLECentralProtocol, callbacks: CGMManagerCallbacks?) async -> any CGMManagerProtocol {
        guard let transmitterIdString = config.transmitterId,
              let transmitterId = TransmitterID(transmitterIdString) else {
            // Return HealthKit if invalid transmitter ID
            return createHealthKitManager()
        }
        
        // Map BLEConnectionMode to CGMConnectionMode (G6-APP-002)
        let connectionMode = mapConnectionMode(config.connectionMode)
        
        let managerConfig = DexcomG6ManagerConfig(
            transmitterId: transmitterId,
            connectionMode: connectionMode,
            // CGM-066e: Pass ALK config from BLEDeviceConfig
            appLevelKey: config.appLevelKey,
            generateNewAppLevelKey: config.generateNewAppLevelKey,
            // G6-COEX-012: Disable HealthKit fallback - requires entitlement
            passiveFallbackToHealthKit: false
        )
        let manager = DexcomG6Manager(config: managerConfig, central: central)
        
        // CGM-066f: Wire ALK persistence callback if provided
        if let onALKChanged = callbacks?.onAppLevelKeyChanged {
            await manager.setOnAppLevelKeyChanged(onALKChanged)
        }
        
        return manager
    }
    
    /// Map T1PalCore.BLEConnectionMode to CGMKit.CGMConnectionMode
    /// Trace: G6-APP-002
    private static func mapConnectionMode(_ mode: BLEConnectionMode) -> CGMConnectionMode {
        switch mode {
        case .direct:
            return .direct
        case .coexistence:
            return .coexistence
        case .passiveBLE:
            return .passiveBLE
        case .healthKitObserver:
            return .healthKitObserver
        case .cloudFollower:
            return .cloudFollower
        case .nightscoutFollower:
            return .nightscoutFollower
        }
    }
    
    /// Create G7 manager for direct mode (requires sensorCode for J-PAKE)
    /// ARCH-007: Returns nil on failure (caller throws explicit error)
    private static func createDexcomG7Manager(config: BLEDeviceConfig, central: any BLECentralProtocol) -> (any CGMManagerProtocol)? {
        guard let sensorCode = config.sensorCode,
              let transmitterId = config.transmitterId else {
            return nil
        }
        
        let managerConfig = DexcomG7ManagerConfig(
            sensorSerial: transmitterId,
            sensorCode: sensorCode,
            connectionMode: .direct
        )
        
        do {
            return try DexcomG7Manager(config: managerConfig, central: central)
        } catch {
            return nil
        }
    }
    
    /// Create G7 manager for coexistence mode (no auth needed)
    /// G7-COEX-FIX-001: Coexistence uses placeholder sensorCode
    /// The manager handles "COEXISTENCE" serial specially (G7-COEX-005)
    private static func createDexcomG7ManagerForCoexistence(
        config: BLEDeviceConfig,
        central: any BLECentralProtocol
    ) -> any CGMManagerProtocol {
        // Coexistence mode: use provided serial or "COEXISTENCE" placeholder
        // Manager will connect to any G7 if serial is "COEXISTENCE"
        let sensorSerial = config.transmitterId ?? "COEXISTENCE"
        
        // Coexistence doesn't use sensorCode (Dexcom app authenticates)
        // Use placeholder to satisfy config requirement
        let placeholderCode = "0000"
        
        let managerConfig = DexcomG7ManagerConfig(
            sensorSerial: sensorSerial,
            sensorCode: placeholderCode,
            connectionMode: .coexistence
        )
        
        do {
            return try DexcomG7Manager(config: managerConfig, central: central)
        } catch {
            // Shouldn't fail with placeholder, but return HealthKit if it does
            CGMLogger.general.error("G7 coexistence init failed: \(error.localizedDescription)")
            return createHealthKitManager()
        }
    }
    
    /// Create Libre 3 manager with BLE central
    /// Trace: LIBRE-IMPL-003
    private static func createLibre3Manager(config: BLEDeviceConfig, central: any BLECentralProtocol) -> any CGMManagerProtocol {
        let managerConfig = Libre3ManagerConfig(
            sensorSerial: config.transmitterId,
            autoReconnect: true,
            allowSimulation: false
        )
        
        return Libre3Manager(config: managerConfig, central: central)
    }
    
    // MARK: - BLE State Helpers
    
    /// Wait for BLE central to reach powered on state (max 5 seconds)
    /// G7-PASSIVE-010: Ensures BLE is ready before returning manager
    private static func waitForBLEReady(central: any BLECentralProtocol) async -> Bool {
        let initialState = await central.state
        if initialState == .poweredOn {
            return true
        }
        
        // Wait up to 5 seconds for BLE to be ready
        return await withTaskGroup(of: Bool.self) { group in
            // Task 1: Wait for state change
            group.addTask {
                for await state in central.stateUpdates {
                    if state == .poweredOn {
                        return true
                    }
                    if state == .unauthorized || state == .unsupported || state == .poweredOff {
                        return false
                    }
                }
                return false
            }
            
            // Task 2: Timeout after 5 seconds
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            
            // Return the first result
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return false
        }
    }
}

// MARK: - Convenience Extension

public extension DataContextManager {
    /// Create a CGMManager for the current context
    /// Uses async for BLE central creation (BLE-ARCH-001)
    /// ARCH-007: Throws on configuration errors
    /// Trace: BLE-CTX-023
    func createCGMManager() async throws -> any CGMManagerProtocol {
        return try await CGMManagerFactory.create(for: current)
    }
}
