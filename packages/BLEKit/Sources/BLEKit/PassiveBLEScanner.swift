// SPDX-License-Identifier: AGPL-3.0-or-later
//
// PassiveBLEScanner.swift
// BLEKit
//
// Passive BLE scanning for coexistence with vendor apps.
// Observes advertisements without connecting.
// Trace: PRD-004, REQ-CGM-009a, CGM-028

import Foundation

// MARK: - Passive Scan Result

/// Result from passive BLE observation
public struct PassiveScanResult: Sendable {
    /// Transmitter identifier extracted from advertisement
    public let transmitterId: String
    
    /// Transmitter type (G6, G7, Libre, etc.)
    public let transmitterType: CGMDeviceType
    
    /// Signal strength
    public let rssi: Int
    
    /// Raw advertisement data
    public let advertisementData: Data?
    
    /// Timestamp of observation
    public let timestamp: Date
    
    /// Whether a connection is detected (isConnectable = false means vendor connected)
    public let vendorConnected: Bool
    
    public init(
        transmitterId: String,
        transmitterType: CGMDeviceType,
        rssi: Int,
        advertisementData: Data?,
        timestamp: Date = Date(),
        vendorConnected: Bool = false
    ) {
        self.transmitterId = transmitterId
        self.transmitterType = transmitterType
        self.rssi = rssi
        self.advertisementData = advertisementData
        self.timestamp = timestamp
        self.vendorConnected = vendorConnected
    }
}

/// CGM device types we can detect via passive scanning
public enum CGMDeviceType: String, Codable, Sendable {
    case dexcomG6
    case dexcomG6Plus  // Firefly transmitters
    case dexcomG7
    case libre2
    case libre3
    case miaomiao
    case bubble
    case unknown
    
    /// Device manufacturer
    public var manufacturer: String {
        switch self {
        case .dexcomG6, .dexcomG6Plus, .dexcomG7:
            return "Dexcom"
        case .libre2, .libre3:
            return "Abbott"
        case .miaomiao:
            return "Tomato"
        case .bubble:
            return "Bubble"
        case .unknown:
            return "Unknown"
        }
    }
    
    /// CGM-MODE-WIRE-003: Whether this is a Dexcom device (for mode explanation UI)
    public var isDexcom: Bool {
        switch self {
        case .dexcomG6, .dexcomG6Plus, .dexcomG7:
            return true
        case .libre2, .libre3, .miaomiao, .bubble, .unknown:
            return false
        }
    }
}

// MARK: - Passive BLE Scanner

/// Passive BLE scanner for vendor app coexistence
/// Scans for CGM transmitter advertisements without connecting
public actor PassiveBLEScanner {
    
    // MARK: - Properties
    
    /// BLE central for scanning
    private let central: any BLECentralProtocol
    
    /// Current scanning state
    public private(set) var isScanning: Bool = false
    
    /// Most recent scan result per transmitter
    public private(set) var knownTransmitters: [String: PassiveScanResult] = [:]
    
    /// Callbacks
    public var onTransmitterDiscovered: (@Sendable (PassiveScanResult) -> Void)?
    public var onVendorConnectionDetected: (@Sendable (String, Bool) -> Void)?
    
    // MARK: - Configuration
    
    /// Service UUIDs to scan for
    private let scanServices: [BLEUUID]
    
    /// Stale threshold - remove transmitters not seen in this time
    private let staleThresholdSeconds: TimeInterval
    
    // MARK: - Initialization
    
    /// Create PassiveBLEScanner asynchronously (required for MainActor BLE init)
    /// - Parameter staleThresholdSeconds: Time before transmitter considered stale
    /// - Returns: Configured PassiveBLEScanner
    public static func create(staleThresholdSeconds: TimeInterval = 300) async -> PassiveBLEScanner {
        let central = await BLECentralFactory.createAsync()
        return PassiveBLEScanner(central: central, staleThresholdSeconds: staleThresholdSeconds)
    }
    
    /// Initialize with an injected BLE central (for testing or custom configuration)
    /// - Parameters:
    ///   - central: BLE central instance
    ///   - staleThresholdSeconds: Time before transmitter considered stale
    public init(
        central: any BLECentralProtocol,
        staleThresholdSeconds: TimeInterval = 300
    ) {
        self.central = central
        self.staleThresholdSeconds = staleThresholdSeconds
        
        // Scan for Dexcom and Libre advertisements
        self.scanServices = [
            .dexcomAdvertisement,  // G6
            .dexcomG7Advertisement, // G7
            .libre2Service          // Libre 2/3
        ]
    }
    
    /// Factory method with mock central for testing
    public static func createMock(staleThresholdSeconds: TimeInterval = 300) -> PassiveBLEScanner {
        let central = BLECentralFactory.createMock()
        return PassiveBLEScanner(central: central, staleThresholdSeconds: staleThresholdSeconds)
    }
    
    // MARK: - Callbacks
    
    /// Set callbacks for discovered transmitters and vendor connection status
    /// - Parameters:
    ///   - onDiscovered: Called when a transmitter is discovered
    ///   - onVendorConnection: Called when vendor connection status changes
    public func setCallbacks(
        onDiscovered: (@Sendable (PassiveScanResult) -> Void)?,
        onVendorConnection: (@Sendable (String, Bool) -> Void)?
    ) {
        self.onTransmitterDiscovered = onDiscovered
        self.onVendorConnectionDetected = onVendorConnection
    }
    
    // MARK: - Scanning
    
    /// Start passive scanning for transmitters
    public func startScanning() async throws {
        guard !isScanning else { return }
        
        let state = await central.state
        guard state == .poweredOn else {
            throw BLEError.notPoweredOn
        }
        
        isScanning = true
        
        // Start scan and process results
        let scanStream = central.scan(for: scanServices)
        
        Task {
            do {
                for try await result in scanStream {
                    await processScanResult(result)
                }
            } catch {
                isScanning = false
            }
        }
    }
    
    /// Stop passive scanning
    public func stopScanning() async {
        guard isScanning else { return }
        isScanning = false
        await central.stopScan()
    }
    
    // MARK: - Scan Processing
    
    private func processScanResult(_ result: BLEScanResult) async {
        guard let passiveResult = extractTransmitterInfo(from: result) else {
            return
        }
        
        let transmitterId = passiveResult.transmitterId
        let wasKnown = knownTransmitters[transmitterId] != nil
        let wasVendorConnected = knownTransmitters[transmitterId]?.vendorConnected ?? false
        
        // Update known transmitters
        knownTransmitters[transmitterId] = passiveResult
        
        // Notify discovery
        if !wasKnown {
            onTransmitterDiscovered?(passiveResult)
        }
        
        // Notify vendor connection status change
        if wasVendorConnected != passiveResult.vendorConnected {
            onVendorConnectionDetected?(transmitterId, passiveResult.vendorConnected)
        }
    }
    
    /// Extract transmitter info from BLE scan result
    private func extractTransmitterInfo(from result: BLEScanResult) -> PassiveScanResult? {
        let services = result.advertisement.serviceUUIDs
        
        // Determine transmitter type
        let transmitterType: CGMDeviceType
        if services.contains(.dexcomG7Advertisement) {
            transmitterType = .dexcomG7
        } else if services.contains(.dexcomAdvertisement) {
            transmitterType = .dexcomG6
        } else if services.contains(.libre2Service) {
            transmitterType = .libre2
        } else if services.contains(.nordicUARTService) {
            // Could be Miaomiao or Bubble - check name
            if let name = result.peripheral.name?.lowercased() {
                if name.contains("miaomiao") {
                    transmitterType = .miaomiao
                } else if name.contains("bubble") {
                    transmitterType = .bubble
                } else {
                    transmitterType = .unknown
                }
            } else {
                transmitterType = .unknown
            }
        } else {
            return nil
        }
        
        // Extract transmitter ID from name or advertisement
        let transmitterId = extractTransmitterId(
            from: result.peripheral.name,
            manufacturerData: result.advertisement.manufacturerData,
            type: transmitterType
        )
        
        // Check if vendor app is connected (isConnectable = false means someone else connected)
        let vendorConnected = !result.advertisement.isConnectable
        
        return PassiveScanResult(
            transmitterId: transmitterId,
            transmitterType: transmitterType,
            rssi: result.rssi,
            advertisementData: result.advertisement.manufacturerData,
            vendorConnected: vendorConnected
        )
    }
    
    /// Extract transmitter ID from advertisement data
    private func extractTransmitterId(
        from name: String?,
        manufacturerData: Data?,
        type: CGMDeviceType
    ) -> String {
        // Dexcom transmitter names are like "DexcomXX" where XX is 2 chars
        // or the full transmitter ID in manufacturer data
        if let name = name {
            switch type {
            case .dexcomG6, .dexcomG6Plus, .dexcomG7:
                // Dexcom name format: "DexcomXX" or "DEXCOM XX"
                let cleaned = name.replacingOccurrences(of: "Dexcom", with: "")
                    .replacingOccurrences(of: "DEXCOM", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    return cleaned
                }
            case .libre2, .libre3:
                // Libre sensors may include serial in name
                return name
            case .miaomiao, .bubble:
                return name
            case .unknown:
                break
            }
        }
        
        // Fall back to manufacturer data if available
        if let data = manufacturerData, data.count >= 6 {
            // Extract ID from manufacturer specific data
            // Format varies by manufacturer
            return data.prefix(6).map { String(format: "%02X", $0) }.joined()
        }
        
        // Last resort: use a hash of available data
        return "Unknown-\(UUID().uuidString.prefix(8))"
    }
    
    // MARK: - Transmitter Management
    
    /// Get transmitter by ID
    public func getTransmitter(_ id: String) -> PassiveScanResult? {
        return knownTransmitters[id]
    }
    
    /// Get all known transmitters
    public func getAllTransmitters() -> [PassiveScanResult] {
        return Array(knownTransmitters.values)
    }
    
    /// Check if a transmitter has vendor app connected
    public func isVendorConnected(_ transmitterId: String) -> Bool {
        return knownTransmitters[transmitterId]?.vendorConnected ?? false
    }
    
    /// Remove stale transmitters not seen recently
    public func pruneStaleTransmitters() {
        let now = Date()
        let staleIds = knownTransmitters.filter { (_, result) in
            now.timeIntervalSince(result.timestamp) > staleThresholdSeconds
        }.map { $0.key }
        
        for id in staleIds {
            knownTransmitters.removeValue(forKey: id)
        }
    }
    
    /// Clear all known transmitters
    public func clearTransmitters() {
        knownTransmitters.removeAll()
    }
}
