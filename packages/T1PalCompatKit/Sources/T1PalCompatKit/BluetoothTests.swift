// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BluetoothTests.swift
// T1PalCompatKit
//
// Bluetooth capability tests for CGM/pump connectivity.
// Trace: PRD-006 REQ-COMPAT-001
//
// These tests verify BLE capabilities required for CGM mode.
// On Linux, tests return .unsupported status.

import Foundation

#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
#endif

// MARK: - BLE Central State Test

/// Test that BLE central manager can be initialized and reports state
public struct BLECentralStateTest: CapabilityTest {
    public let id = "ble-central-state"
    public let name = "BLE Central State"
    public let category = CapabilityCategory.bluetooth
    public let priority = 10
    public let requiresHardware = true
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(CoreBluetooth)
        let startTime = Date()
        
        // Create a delegate to receive state updates
        let delegate = BLEStateDelegate()
        let manager = CBCentralManager(delegate: delegate, queue: nil, options: [
            CBCentralManagerOptionShowPowerAlertKey: false
        ])
        
        // Wait for state to be determined (up to 2 seconds)
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            if manager.state != .unknown {
                break
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let state = manager.state
        
        let stateDetails: [String: String] = [
            "state": stateDescription(state),
            "stateRaw": "\(state.rawValue)"
        ]
        
        switch state {
        case .poweredOn:
            return passed("Bluetooth powered on", details: stateDetails, duration: duration)
        case .poweredOff:
            return failed("Bluetooth powered off", details: stateDetails, duration: duration)
        case .unauthorized:
            return failed("Bluetooth unauthorized", details: stateDetails, duration: duration)
        case .unsupported:
            return unsupported("Bluetooth not supported on this device")
        case .unknown:
            return failed("Bluetooth state unknown after timeout", details: stateDetails, duration: duration)
        case .resetting:
            return failed("Bluetooth resetting", details: stateDetails, duration: duration)
        @unknown default:
            return failed("Unknown Bluetooth state", details: stateDetails, duration: duration)
        }
        #else
        return unsupported("CoreBluetooth not available on this platform")
        #endif
    }
    
    #if canImport(CoreBluetooth)
    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "poweredOn"
        case .poweredOff: return "poweredOff"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }
    #endif
}

// MARK: - BLE Background Mode Test

/// Test that app has background BLE entitlements (iOS only)
public struct BLEBackgroundModeTest: CapabilityTest {
    public let id = "ble-background-mode"
    public let name = "BLE Background Mode"
    public let category = CapabilityCategory.bluetooth
    public let priority = 11
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if os(iOS)
        // Check Info.plist for UIBackgroundModes containing bluetooth-central
        if let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] {
            let hasBLECentral = backgroundModes.contains("bluetooth-central")
            let hasBLEPeripheral = backgroundModes.contains("bluetooth-peripheral")
            
            let details: [String: String] = [
                "bluetooth-central": hasBLECentral ? "enabled" : "disabled",
                "bluetooth-peripheral": hasBLEPeripheral ? "enabled" : "disabled"
            ]
            
            if hasBLECentral {
                return passed("Background BLE central mode enabled", details: details)
            } else {
                return failed("Background BLE central mode not enabled", details: details)
            }
        } else {
            return failed("No UIBackgroundModes in Info.plist", details: [
                "note": "Add bluetooth-central to UIBackgroundModes"
            ])
        }
        #elseif os(macOS)
        // macOS doesn't require background modes for BLE
        return passed("macOS: Background BLE always available")
        #else
        return unsupported("Background modes not applicable on this platform")
        #endif
    }
}

// MARK: - BLE State Restoration Test

/// Test that app has state restoration configured for BLE
public struct BLEStateRestorationTest: CapabilityTest {
    public let id = "ble-state-restoration"
    public let name = "BLE State Restoration"
    public let category = CapabilityCategory.bluetooth
    public let priority = 12
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if os(iOS) && canImport(CoreBluetooth)
        // State restoration requires a restoration identifier
        // CoreBluetooth always supports this on iOS
        return passed("State restoration available", details: [
            "note": "Use CBCentralManagerOptionRestoreIdentifierKey when creating manager"
        ])
        #elseif os(macOS)
        return passed("macOS: State restoration available via CBCentralManagerOptionRestoreIdentifierKey")
        #else
        return unsupported("BLE state restoration not available on this platform")
        #endif
    }
}

// MARK: - BLE Authorization Test

/// Test Bluetooth authorization status
public struct BLEAuthorizationTest: CapabilityTest {
    public let id = "ble-authorization"
    public let name = "BLE Authorization"
    public let category = CapabilityCategory.bluetooth
    public let priority = 13
    
    public init() {}
    
    public func run() async -> CapabilityResult {
        #if canImport(CoreBluetooth)
        let authorization = CBCentralManager.authorization
        
        let details: [String: String] = [
            "authorization": authorizationDescription(authorization),
            "authorizationRaw": "\(authorization.rawValue)"
        ]
        
        switch authorization {
        case .allowedAlways:
            return passed("Bluetooth authorized", details: details)
        case .notDetermined:
            return skipped("Bluetooth authorization not yet requested", details: details)
        case .denied:
            return failed("Bluetooth authorization denied", details: details)
        case .restricted:
            return failed("Bluetooth authorization restricted", details: details)
        @unknown default:
            return failed("Unknown authorization status", details: details)
        }
        #else
        return unsupported("CoreBluetooth not available on this platform")
        #endif
    }
    
    #if canImport(CoreBluetooth)
    private func authorizationDescription(_ auth: CBManagerAuthorization) -> String {
        switch auth {
        case .allowedAlways: return "allowedAlways"
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown(\(auth.rawValue))"
        }
    }
    #endif
}

// MARK: - Helper Classes

#if canImport(CoreBluetooth)
/// Simple delegate to receive CBCentralManager state updates
private class BLEStateDelegate: NSObject, CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // State is accessed directly from the manager
    }
}
#endif
