// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MirroredPumpSource.swift
// PumpKit
//
// Pump source that mirrors data from Nightscout devicestatus.
// Reads pump state from devicestatus.pump field for remote monitoring.
// Trace: PUMP-CTX-004, PRD-005
//
// Usage:
//   let config = MirroredPumpConfig(nightscoutURL: url, token: "...")
//   let source = MirroredPumpSource(config: config)
//   try await source.start()

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Mirrored Pump Source

/// Pump source that mirrors data from Nightscout
public actor MirroredPumpSource: PumpSource {
    
    public nonisolated let sourceType: PumpDataSourceType = .mirrored
    
    // MARK: - State
    
    private var config: MirroredPumpConfig
    private var isRunning: Bool = false
    private var pollTask: Task<Void, Never>?
    private var currentStatus: PumpStatus
    private var lastFetch: Date?
    private var consecutiveErrors: Int = 0
    
    // MARK: - Initialization
    
    public init(config: MirroredPumpConfig) {
        self.config = config
        self.currentStatus = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: nil,
            batteryLevel: nil,
            insulinOnBoard: 0
        )
    }
    
    // MARK: - PumpSource Protocol
    
    public var status: PumpStatus {
        currentStatus
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        
        isRunning = true
        consecutiveErrors = 0
        
        // Initial fetch
        await fetchDeviceStatus()
        
        // Start polling
        startPolling()
    }
    
    public func stop() async {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        
        currentStatus = PumpStatus(
            connectionState: .disconnected,
            reservoirLevel: currentStatus.reservoirLevel,
            batteryLevel: currentStatus.batteryLevel,
            insulinOnBoard: currentStatus.insulinOnBoard,
            lastDelivery: currentStatus.lastDelivery
        )
    }
    
    public func execute(_ command: PumpSourceCommand) async throws -> PumpSourceResult {
        // Mirrored source is read-only
        switch command {
        case .readStatus:
            await fetchDeviceStatus()
            return PumpSourceResult(success: true, command: command, updatedStatus: currentStatus)
            
        default:
            return PumpSourceResult(
                success: false,
                command: command,
                message: "Mirrored source is read-only"
            )
        }
    }
    
    // MARK: - Polling
    
    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, await self.isRunning else { break }
                
                let interval = await self.config.pollIntervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                
                await self.fetchDeviceStatus()
            }
        }
    }
    
    // MARK: - Fetching
    
    private func fetchDeviceStatus() async {
        var urlComponents = URLComponents(url: config.nightscoutURL, resolvingAgainstBaseURL: true)!
        urlComponents.path = (urlComponents.path.isEmpty ? "" : urlComponents.path) + "/api/v1/devicestatus"
        urlComponents.queryItems = [
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "find[pump][$exists]", value: "true")
        ]
        
        guard let url = urlComponents.url else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        // Add auth if provided
        if let token = config.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                handleError()
                return
            }
            
            let statuses = try JSONDecoder().decode([DeviceStatusResponse].self, from: data)
            
            if let latest = statuses.first {
                updateFromDeviceStatus(latest)
                consecutiveErrors = 0
            }
            
            lastFetch = Date()
            
        } catch {
            handleError()
        }
    }
    
    private func updateFromDeviceStatus(_ response: DeviceStatusResponse) {
        guard let pump = response.pump else { return }
        
        // Parse reservoir
        let reservoir: Double?
        if let res = pump.reservoir {
            reservoir = res
        } else if let res = pump.status?.reservoir {
            reservoir = res
        } else {
            reservoir = currentStatus.reservoirLevel
        }
        
        // Parse battery
        let battery: Double?
        if let bat = pump.battery?.percent {
            battery = bat / 100.0  // Convert percentage to 0-1
        } else if let bat = pump.status?.batteryPct {
            battery = bat / 100.0
        } else {
            battery = currentStatus.batteryLevel
        }
        
        // Parse IOB
        let iob: Double
        if let iobVal = pump.iob?.iob {
            iob = iobVal
        } else if let iobVal = response.openaps?.iob?.iob {
            iob = iobVal
        } else {
            iob = currentStatus.insulinOnBoard
        }
        
        // Parse suspended state
        let connectionState: PumpConnectionState
        if pump.status?.suspended == true || pump.status?.status == "suspended" {
            connectionState = .suspended
        } else if pump.status?.bolusing == true {
            connectionState = .connected
        } else {
            connectionState = .connected
        }
        
        // Parse last bolus time
        let lastDelivery: Date?
        if let bolusTime = pump.status?.timestamp {
            lastDelivery = ISO8601DateFormatter().date(from: bolusTime)
        } else {
            lastDelivery = currentStatus.lastDelivery
        }
        
        currentStatus = PumpStatus(
            connectionState: connectionState,
            reservoirLevel: reservoir,
            batteryLevel: battery,
            insulinOnBoard: iob,
            lastDelivery: lastDelivery
        )
    }
    
    private func handleError() {
        consecutiveErrors += 1
        
        if consecutiveErrors >= 3 {
            currentStatus = PumpStatus(
                connectionState: .error,
                reservoirLevel: currentStatus.reservoirLevel,
                batteryLevel: currentStatus.batteryLevel,
                insulinOnBoard: currentStatus.insulinOnBoard,
                lastDelivery: currentStatus.lastDelivery
            )
        }
    }
}

// MARK: - Nightscout Response Types

/// devicestatus API response
struct DeviceStatusResponse: Codable {
    let _id: String?
    let created_at: String?
    let pump: PumpDeviceStatus?
    let openaps: OpenAPSStatus?
    let device: String?
}

/// pump field in devicestatus
struct PumpDeviceStatus: Codable {
    let reservoir: Double?
    let clock: String?
    let battery: BatteryStatus?
    let iob: IOBStatus?
    let status: PumpStatusField?
    let extended: ExtendedPumpStatus?
}

/// battery status
struct BatteryStatus: Codable {
    let percent: Double?
    let voltage: Double?
    let status: String?
}

/// IOB status
struct IOBStatus: Codable {
    let iob: Double?
    let timestamp: String?
    let activity: Double?
    let basaliob: Double?
    let bolusiob: Double?
}

/// pump.status field
struct PumpStatusField: Codable {
    let status: String?
    let bolusing: Bool?
    let suspended: Bool?
    let timestamp: String?
    let reservoir: Double?
    let batteryPct: Double?
}

/// Extended pump status
struct ExtendedPumpStatus: Codable {
    let TempBasalAbsoluteRate: Double?
    let TempBasalRemaining: Double?
    let BaseBasalRate: Double?
    let ActiveProfile: String?
}

/// OpenAPS status
struct OpenAPSStatus: Codable {
    let iob: OpenAPSIOB?
    let suggested: OpenAPSSuggested?
    let enacted: OpenAPSEnacted?
}

struct OpenAPSIOB: Codable {
    let iob: Double?
    let activity: Double?
    let basaliob: Double?
    let bolusiob: Double?
    let time: String?
}

struct OpenAPSSuggested: Codable {
    let rate: Double?
    let duration: Int?
    let units: Double?
    let reason: String?
}

struct OpenAPSEnacted: Codable {
    let rate: Double?
    let duration: Int?
    let received: Bool?
}
