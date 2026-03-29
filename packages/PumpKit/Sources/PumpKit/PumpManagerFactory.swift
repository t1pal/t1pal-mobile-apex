// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PumpManagerFactory.swift
// T1Pal Mobile
//
// Factory for creating PumpManager based on DataContext configuration
// Trace: BLE-CTX-024, PRD-021

import Foundation
import T1PalCore

/// Factory for creating PumpManager instances based on DataContext
/// Trace: BLE-CTX-024
public enum PumpManagerFactory {
    
    /// Create a PumpManager based on the current DataContext
    /// - Parameter context: The data context configuration
    /// - Returns: Appropriate PumpManager instance, or nil if no pump configured
    public static func create(for context: DataContext) -> (any PumpManagerProtocol)? {
        // Only create pump manager for demo or BLE contexts with pump config
        switch context.sourceType {
        case .demo:
            // Demo mode always has simulation pump available
            return createSimulationPump()
            
        case .ble, .blePassive, .appGroup:
            // BLE mode requires pump config
            if let pumpConfig = context.pumpConfig {
                return createBLEPump(config: pumpConfig)
            }
            return nil
            
        case .fixture, .liveNS, .healthKit:
            // These modes don't typically have pump control
            // Could add pump config later if needed
            if let pumpConfig = context.pumpConfig {
                return createBLEPump(config: pumpConfig)
            }
            return nil
        }
    }
    
    /// Create a simulation pump for demo mode
    private static func createSimulationPump() -> any PumpManagerProtocol {
        return SimulationPump()
    }
    
    /// Create a BLE pump manager based on device configuration
    private static func createBLEPump(config: PumpDeviceConfig) -> any PumpManagerProtocol {
        switch config.pumpType {
        case .medtronic:
            return createMinimedManager(config: config)
            
        case .omnipodDash:
            return createOmnipodDashManager(config: config)
            
        case .omnipodEros:
            return createOmnipodErosManager(config: config)
            
        case .dana:
            return createDanaManager(config: config)
            
        case .tandemX2:
            return createTandemX2Manager(config: config)
        }
    }
    
    // MARK: - Pump Manager Creators
    
    private static func createMinimedManager(config: PumpDeviceConfig) -> any PumpManagerProtocol {
        // Create manager with default settings
        // Actual pump pairing happens separately with pairPump()
        return MinimedManager(
            basalRate: 1.0,
            maxBolus: 25.0,
            maxBasalRate: 10.0
        )
    }
    
    private static func createOmnipodDashManager(config: PumpDeviceConfig) -> any PumpManagerProtocol {
        return OmnipodDashManager(
            basalRate: 1.0,
            maxBolus: 10.0,
            maxBasalRate: 5.0
        )
    }
    
    private static func createDanaManager(config: PumpDeviceConfig) -> any PumpManagerProtocol {
        return DanaManager(
            basalRate: 1.0,
            maxBolus: 25.0,
            maxBasalRate: 5.0
        )
    }
    
    private static func createOmnipodErosManager(config: PumpDeviceConfig) -> any PumpManagerProtocol {
        return OmnipodErosManager(
            basalRate: 1.0,
            maxBolus: 10.0,
            maxBasalRate: 5.0
        )
    }
    
    private static func createTandemX2Manager(config: PumpDeviceConfig) -> any PumpManagerProtocol {
        return TandemX2Manager(
            maxBolus: 25.0,
            maxBasalRate: 5.0
        )
    }
}

// MARK: - Convenience Extension

public extension DataContextManager {
    /// Create a PumpManager for the current context
    /// Returns nil if no pump is configured
    /// Trace: BLE-CTX-024
    func createPumpManager() -> (any PumpManagerProtocol)? {
        return PumpManagerFactory.create(for: current)
    }
    
    /// Whether a pump is configured in the current context
    var hasPumpConfigured: Bool {
        switch current.sourceType {
        case .demo:
            return true // Demo always has simulation pump
        case .ble, .blePassive, .appGroup:
            return current.pumpConfig != nil
        case .fixture, .liveNS, .healthKit:
            return current.pumpConfig != nil
        }
    }
}
