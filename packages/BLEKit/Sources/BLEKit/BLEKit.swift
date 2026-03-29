// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLEKit.swift
// BLEKit
//
// Module entry point - re-exports all public types.
// Trace: PRD-008

// Re-export all public types

// Core types
@_exported import struct Foundation.Data

// BLETypes.swift exports
// - BLEUUID
// - BLECentralState
// - BLEPeripheralState
// - BLEScanResult
// - BLEPeripheralInfo
// - BLEAdvertisement
// - BLEService
// - BLECharacteristic
// - BLECharacteristicProperties
// - BLEWriteType
// - BLEError

// BLEProtocols.swift exports
// - BLECentralProtocol
// - BLEPeripheralProtocol
// - BLECentralFactory
// - BLECentralOptions

// BLEPeripheralManager.swift exports (PRD-007 REQ-SIM-001)
// - BLEPeripheralManagerProtocol
// - BLEPeripheralManagerState
// - BLEMutableService
// - BLEMutableCharacteristic
// - BLEAttributePermissions
// - BLEAdvertisementData
// - BLECentralInfo
// - BLEATTReadRequest
// - BLEATTWriteRequest
// - BLESubscriptionChange
// - BLEATTError
// - BLEPeripheralManagerFactory
// - BLEPeripheralManagerOptions

// MockBLE.swift exports
// - MockBLECentral
// - MockBLEPeripheral

// MockBLEPeripheralManager.swift exports
// - MockBLEPeripheralManager

// TransmitterIdentity.swift exports (PRD-007 REQ-SIM-002)
// - TransmitterType
// - SimulatorTransmitterID
// - FirmwareVersion
// - SimulatorTransmitterConfig
// - TransmitterState
// - SensorSession

// G6AuthSimulator.swift exports (PRD-007 REQ-SIM-003)
// - G6AuthState
// - G6AuthResult
// - G6AuthSimulator
// - G6SimOpcode

// G6GlucoseSimulator.swift exports (PRD-007 REQ-SIM-004)
// - G6GlucoseStatus
// - SimulatedGlucoseReading
// - G6GlucoseResult
// - GlucoseProvider
// - StaticGlucoseProvider
// - G6GlucoseSimulator

// GlucosePatterns.swift exports (PRD-007 REQ-SIM-005)
// - GlucosePattern
// - FlatGlucosePattern
// - SineWavePattern
// - MealResponsePattern
// - RandomWalkPattern
// - ReplayPattern
// - CompositePattern
