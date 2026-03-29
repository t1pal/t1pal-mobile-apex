// SPDX-License-Identifier: AGPL-3.0-or-later
//
// BLEProtocols.swift
// BLEKit
//
// Platform-agnostic BLE protocols for central and peripheral operations.
// Trace: PRD-008 REQ-BLE-001, REQ-BLE-002

import Foundation

// MARK: - Simulation Marker Protocol (PROD-HARDEN-032)

/// Marker protocol for simulated/mock BLE implementations.
/// Used to detect when mock implementations are being used.
/// Production code should validate `allowSimulation` before accepting simulated centrals.
public protocol BLESimulatedProtocol {}

/// Error thrown when simulation is not allowed but a simulated central is used
public struct BLESimulationNotAllowedError: Error, CustomStringConvertible {
    public let message: String
    
    public init(component: String = "BLE") {
        self.message = "\(component): Simulated BLE central detected but allowSimulation=false. " +
            "Pass allowSimulation: true for testing, or use a real BLE central."
    }
    
    public var description: String { message }
}

/// Validates that a BLE central is allowed based on simulation settings.
/// - Parameters:
///   - central: The BLE central to validate
///   - allowSimulation: Whether simulation is permitted
///   - component: Component name for error message
/// - Throws: `BLESimulationNotAllowedError` if central is simulated and not allowed
public func validateBLECentral(
    _ central: any BLECentralProtocol,
    allowSimulation: Bool,
    component: String = "BLE"
) throws {
    if !allowSimulation && (central is BLESimulatedProtocol) {
        throw BLESimulationNotAllowedError(component: component)
    }
}

// MARK: - BLE Central Protocol

/// Platform-agnostic BLE Central role API
///
/// Implementations:
/// - `CoreBluetoothCentral` for iOS/macOS (in BLEKitDarwin)
/// - `LinuxBLECentral` for Linux (in BLEKitLinux)
/// - `MockBLECentral` for testing
public protocol BLECentralProtocol: Sendable {
    /// Current Bluetooth state
    var state: BLECentralState { get async }
    
    /// State change notifications
    var stateUpdates: AsyncStream<BLECentralState> { get }
    
    /// Scan for peripherals advertising specific services
    /// - Parameter services: Service UUIDs to filter by (nil for all)
    /// - Returns: Stream of discovered peripherals
    func scan(for services: [BLEUUID]?) -> AsyncThrowingStream<BLEScanResult, Error>
    
    /// Stop scanning
    func stopScan() async
    
    /// Connect to a discovered peripheral
    /// - Parameter peripheral: Peripheral info from scan result
    /// - Returns: Connected peripheral handle
    func connect(to peripheral: BLEPeripheralInfo) async throws -> any BLEPeripheralProtocol
    
    /// Retrieve a known peripheral by identifier (from CoreBluetooth cache)
    /// Returns nil if peripheral is not known to the system
    func retrievePeripheral(identifier: BLEUUID) async -> BLEPeripheralInfo?
    
    /// Retrieve peripherals already connected by other apps (G6-COEX-013)
    /// This is critical for coexistence - finds peripherals the Dexcom app has connected to
    /// - Parameter serviceUUIDs: Services to filter by
    /// - Returns: List of already-connected peripherals
    func retrieveConnectedPeripherals(withServices serviceUUIDs: [BLEUUID]) async -> [BLEPeripheralInfo]
    
    /// Disconnect a peripheral
    func disconnect(_ peripheral: any BLEPeripheralProtocol) async
    
    // MARK: - Connection Events (G7-PASSIVE-001, G7-PASSIVE-003)
    
    /// Register for connection events matching the specified services.
    /// Enables background wake-up when other apps connect to matching peripherals.
    /// Critical for G7 coexistence - notifies when Dexcom app connects to sensor.
    /// 
    /// Reference: Loop's G7BluetoothManager.managerQueue_scanForPeripheral()
    /// - Parameter services: Service UUIDs to match (e.g., Dexcom advertisement + CGM service)
    /// Trace: G7-PASSIVE-001
    func registerForConnectionEvents(matchingServices services: [BLEUUID]) async
    
    /// Stream of connection events from other apps connecting/disconnecting.
    /// Subscribe to this before calling registerForConnectionEvents.
    /// 
    /// Usage:
    /// ```swift
    /// for await event in central.connectionEvents {
    ///     if event.eventType == .peerConnected {
    ///         // Another app connected - try to join the connection
    ///     }
    /// }
    /// ```
    /// Trace: G7-PASSIVE-003
    var connectionEvents: AsyncStream<BLEConnectionEvent> { get }
    
    /// G7-COEX-TIMING-001: Prepare connection events stream synchronously.
    /// This ensures the continuation is set BEFORE registration, avoiding race conditions
    /// where the Task body hasn't started running before the transmitter's brief window closes.
    /// 
    /// Usage:
    /// ```swift
    /// let stream = central.prepareConnectionEventsStream()  // Continuation set immediately
    /// await central.registerForConnectionEvents(matchingServices: [...])
    /// for await event in stream { ... }  // Ready to receive
    /// ```
    /// Trace: G7-COEX-TIMING-001
    func prepareConnectionEventsStream() -> AsyncStream<BLEConnectionEvent>
}

// MARK: - BLE Peripheral Protocol

/// Platform-agnostic connected peripheral operations
public protocol BLEPeripheralProtocol: Sendable {
    /// Unique identifier
    var identifier: BLEUUID { get }
    
    /// Peripheral name (may be nil)
    var name: String? { get }
    
    /// Current connection state
    var state: BLEPeripheralState { get async }
    
    /// State change notifications
    var stateUpdates: AsyncStream<BLEPeripheralState> { get }
    
    /// G6-COEX-016: Get cached services from CoreBluetooth (if available)
    /// Returns services that CoreBluetooth has cached from prior connections.
    /// Use this to avoid rediscovery and enable single-cycle initialization.
    var cachedServices: [BLEService]? { get }
    
    /// G6-COEX-016: Get cached characteristics for a service (if available)
    /// Returns characteristics that CoreBluetooth has cached from prior connections.
    func cachedCharacteristics(for service: BLEService) -> [BLECharacteristic]?
    
    /// Discover services
    /// - Parameter uuids: Specific services to discover (nil for all)
    func discoverServices(_ uuids: [BLEUUID]?) async throws -> [BLEService]
    
    /// Discover characteristics for a service
    /// - Parameters:
    ///   - uuids: Specific characteristics to discover (nil for all)
    ///   - service: Service to search in
    func discoverCharacteristics(_ uuids: [BLEUUID]?, for service: BLEService) async throws -> [BLECharacteristic]
    
    /// Read characteristic value
    /// - Parameter characteristic: Characteristic to read
    /// - Returns: Read data
    func readValue(for characteristic: BLECharacteristic) async throws -> Data
    
    /// Write characteristic value
    /// - Parameters:
    ///   - data: Data to write
    ///   - characteristic: Target characteristic
    ///   - type: Write type (with/without response)
    func writeValue(_ data: Data, for characteristic: BLECharacteristic, type: BLEWriteType) async throws
    
    /// Subscribe to characteristic notifications
    /// - Parameter characteristic: Characteristic to subscribe to
    /// - Returns: Stream of notification values
    func subscribe(to characteristic: BLECharacteristic) -> AsyncThrowingStream<Data, Error>
    
    /// Prepare notification stream synchronously (G6-COEX-023)
    /// Registers continuation immediately to avoid race with first notification.
    /// Use with enableNotifications() for time-critical passive observation.
    /// - Parameter characteristic: Characteristic to receive notifications from
    /// - Returns: Stream that will receive notifications once enabled
    func prepareNotificationStream(for characteristic: BLECharacteristic) async -> AsyncThrowingStream<Data, Error>
    
    /// Enable notifications for a characteristic and wait for confirmation
    /// Use in passive/coexistence mode where timing is critical
    /// - Parameter characteristic: Characteristic to enable notifications for
    func enableNotifications(for characteristic: BLECharacteristic) async throws
    
    /// Unsubscribe from characteristic notifications
    func unsubscribe(from characteristic: BLECharacteristic) async throws
    
    /// Disconnect from peripheral
    func disconnect() async
}

// MARK: - BLE Peripheral Extensions

public extension BLEPeripheralProtocol {
    /// Convenience: Discover a single characteristic by UUID
    /// - Parameters:
    ///   - uuid: Characteristic UUID to find
    ///   - serviceUUID: Service UUID containing the characteristic
    /// - Returns: The characteristic if found, nil otherwise
    func discoverCharacteristic(uuid: String, serviceUUID: String) async throws -> BLECharacteristic? {
        guard let serviceUUID = BLEUUID(string: serviceUUID) else {
            return nil
        }
        let services = try await discoverServices([serviceUUID])
        guard let service = services.first else {
            return nil
        }
        
        guard let charUUID = BLEUUID(string: uuid) else {
            return nil
        }
        let characteristics = try await discoverCharacteristics(
            [charUUID],
            for: service
        )
        return characteristics.first
    }
    
    // MARK: - Timeout-Aware Discovery (PROD-HARDEN-020)
    
    /// Discover services with timeout
    /// - Parameters:
    ///   - uuids: Specific services to discover (nil for all)
    ///   - timeout: Maximum time to wait in seconds (default: 5s)
    /// - Returns: Discovered services
    /// - Throws: `BLETimeoutError` if discovery takes too long
    func discoverServices(
        _ uuids: [BLEUUID]?,
        timeout: TimeInterval = BLETimingConstants.defaultConnectionTimeout
    ) async throws -> [BLEService] {
        try await withTimeout(seconds: timeout, operation: "service discovery") {
            try await self.discoverServices(uuids)
        }
    }
    
    /// Discover characteristics with timeout
    /// - Parameters:
    ///   - uuids: Specific characteristics to discover (nil for all)
    ///   - service: Service to search in
    ///   - timeout: Maximum time to wait in seconds (default: 5s)
    /// - Returns: Discovered characteristics
    /// - Throws: `BLETimeoutError` if discovery takes too long
    func discoverCharacteristics(
        _ uuids: [BLEUUID]?,
        for service: BLEService,
        timeout: TimeInterval = BLETimingConstants.defaultConnectionTimeout
    ) async throws -> [BLECharacteristic] {
        try await withTimeout(seconds: timeout, operation: "characteristic discovery") {
            try await self.discoverCharacteristics(uuids, for: service)
        }
    }
}

// MARK: - BLE Central Factory

/// Factory for creating platform-appropriate BLE central
public enum BLECentralFactory {
    /// Create a BLE central for the current platform.
    /// 
    /// ⚠️ IMPORTANT: Must be called from SYNCHRONOUS main thread context!
    /// iOS 26 CBCentralManager crashes if created from async context (even MainActor.run).
    /// 
    /// ✅ Safe contexts: App.init(), @main, viewDidLoad(), AppDelegate
    /// ❌ Unsafe contexts: Task { }, async func, actor methods, MainActor.run
    /// 
    /// For lazy initialization from async code, create the central at app startup
    /// and inject it where needed.
    /// 
    /// Trace: BLE-ARCH-001, RL-WIRE-008
    public static func create(options: BLECentralOptions = .default) -> any BLECentralProtocol {
        #if canImport(CoreBluetooth)
        // iOS/macOS: Use real CoreBluetooth implementation
        return DarwinBLECentral(options: options)
        #elseif os(Linux) && canImport(Bluetooth)
        // Linux: Use BlueZ implementation (if available)
        return LinuxBLECentral(options: options)
        #else
        // Fallback: Mock for testing/simulation
        return MockBLECentral(options: options)
        #endif
    }
    
    /// Create a mock BLE central for testing
    /// Use this when you want to simulate BLE without real hardware
    public static func createMock(options: BLECentralOptions = .default) -> any BLECentralProtocol {
        MockBLECentral(options: options)
    }
    
    /// Create a BLE central asynchronously from any context
    /// Hops to MainActor since DarwinBLECentral requires main thread initialization
    /// Trace: BLE-ARCH-001
    @MainActor
    public static func createAsync(options: BLECentralOptions = .default) async -> any BLECentralProtocol {
        create(options: options)
    }
}

/// Options for BLE central creation
public struct BLECentralOptions: Sendable {
    /// Whether to show power alert on iOS
    public let showPowerAlert: Bool
    
    /// Restoration identifier for iOS background
    public let restorationIdentifier: String?
    
    /// Default options
    public static let `default` = BLECentralOptions(showPowerAlert: false, restorationIdentifier: nil)
    
    public init(showPowerAlert: Bool = false, restorationIdentifier: String? = nil) {
        self.showPowerAlert = showPowerAlert
        self.restorationIdentifier = restorationIdentifier
    }
}

// MARK: - Shared BLE Central (BLE-ARCH-003)

/// Shared BLE central instance for the app.
/// Must be set at app startup from synchronous main thread context.
/// 
/// Usage in App.init():
/// ```swift
/// @main
/// struct MyApp: App {
///     init() {
///         BLECentralFactory.setShared(BLECentralFactory.create())
///     }
/// }
/// ```
/// 
/// Usage in views:
/// ```swift
/// let viewModel = BLEScannerViewModel(central: BLECentralFactory.shared)
/// ```
/// 
/// Trace: BLE-ARCH-003
public extension BLECentralFactory {
    /// The shared BLE central instance, if set
    /// Note: nonisolated(unsafe) because this is set once at app startup from main thread
    nonisolated(unsafe) private(set) static var shared: (any BLECentralProtocol)?
    
    /// Set the shared BLE central. Must be called from synchronous main thread at app startup.
    /// - Parameter central: The BLE central to share across the app
    static func setShared(_ central: any BLECentralProtocol) {
        shared = central
    }
}

// MARK: - SwiftUI Environment Support (BLE-ARCH-003)

#if canImport(SwiftUI)
import SwiftUI

/// Environment key for injecting BLE central into SwiftUI views
/// Trace: BLE-ARCH-003, RL-WIRE-019
private struct BLECentralEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any BLECentralProtocol)? = nil
}

public extension EnvironmentValues {
    /// The shared BLE central for the app
    /// 
    /// Must be set at app startup using `.environment(\.bleCentral, central)`
    /// Views should read this and inject into BLEScannerViewModel.
    var bleCentral: (any BLECentralProtocol)? {
        get { self[BLECentralEnvironmentKey.self] }
        set { self[BLECentralEnvironmentKey.self] = newValue }
    }
}

public extension View {
    /// Inject BLE central into the environment for child views
    /// 
    /// Usage in App.init():
    /// ```swift
    /// let bleCentral = BLECentralFactory.create()
    /// WindowGroup {
    ///     ContentView()
    ///         .bleCentralEnvironment(bleCentral)
    /// }
    /// ```
    func bleCentralEnvironment(_ central: any BLECentralProtocol) -> some View {
        environment(\.bleCentral, central)
    }
}
#endif
