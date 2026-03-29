// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// CGMDashboardChart.swift - Chart integration for CGM dashboard
// Part of CGMKit
// Trace: CHART-INT-006

#if canImport(SwiftUI)
import SwiftUI
import Foundation
import T1PalCore

#if canImport(Charts)
import Charts
#endif

// MARK: - CGM Dashboard Chart Section

/// Glucose chart section for CGM dashboard
/// Displays real-time CGM data with BLE connection status
public struct CGMGlucoseChartSection: View {
    @ObservedObject var dataSource: CGMChartDataSource
    let showConnectionStatus: Bool
    
    public init(dataSource: CGMChartDataSource, showConnectionStatus: Bool = true) {
        self.dataSource = dataSource
        self.showConnectionStatus = showConnectionStatus
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with connection status
            HStack {
                Label("CGM Readings", systemImage: "wave.3.forward")
                    .font(.headline)
                Spacer()
                
                if showConnectionStatus {
                    connectionStatusBadge
                }
            }
            
            // Current reading display
            if let current = dataSource.currentReading {
                currentReadingDisplay(current)
            }
            
            // Chart or placeholder
            if dataSource.dataPoints.isEmpty && !dataSource.isLoading {
                emptyStateView
            } else {
                chartView
            }
            
            // Sensor info
            if let sensor = dataSource.sensorInfo {
                sensorInfoRow(sensor)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var connectionStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dataSource.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(dataSource.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func currentReadingDisplay(_ reading: CGMReading) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(reading.glucose))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(glucoseColor(reading.glucose))
                    Text("mg/dL")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                Text(reading.trend ?? "→")
                    .font(.title)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(relativeTime(from: reading.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let delta = dataSource.deltaValue {
                    Text(deltaString(delta))
                        .font(.subheadline)
                        .foregroundColor(delta > 0 ? .orange : delta < 0 ? .blue : .secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var chartView: some View {
        if #available(iOS 16.0, *) {
            CGMHistoryChart(
                dataPoints: dataSource.dataPoints,
                targetLow: dataSource.targetLow,
                targetHigh: dataSource.targetHigh
            )
            .frame(height: 180)
        } else {
            LegacyCGMChart(dataPoints: dataSource.dataPoints)
                .frame(height: 180)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No CGM data")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Connect your CGM to see readings")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
    }
    
    private func sensorInfoRow(_ sensor: CGMSensorInfo) -> some View {
        HStack {
            Label(sensor.transmitterID, systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption)
            Spacer()
            if let remaining = sensor.daysRemaining {
                Text("\(remaining)d remaining")
                    .font(.caption)
                    .foregroundColor(remaining <= 1 ? .orange : .secondary)
            }
        }
        .foregroundColor(.secondary)
    }
    
    private func glucoseColor(_ value: Double) -> Color {
        if value < 55 { return .red }
        if value < 70 { return .orange }
        if value <= 180 { return .green }
        if value <= 250 { return .orange }
        return .red
    }
    
    private func relativeTime(from date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }
    
    private func deltaString(_ delta: Double) -> String {
        if delta > 0 { return "+\(Int(delta))" }
        return "\(Int(delta))"
    }
}

// MARK: - CGM Chart Data Source

/// Data source for CGM chart
@MainActor
public final class CGMChartDataSource: ObservableObject {
    
    @Published public private(set) var dataPoints: [CGMDataPoint] = []
    @Published public private(set) var currentReading: CGMReading? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var error: Error? = nil
    @Published public private(set) var sensorInfo: CGMSensorInfo? = nil
    
    public var targetLow: Double = 70
    public var targetHigh: Double = 180
    public var hoursToDisplay: Int = 3
    
    public init() {}
    
    /// Add new reading from CGM
    public func addReading(glucose: Double, trend: String?, timestamp: Date = Date()) {
        let point = CGMDataPoint(timestamp: timestamp, value: glucose, trend: trend)
        dataPoints.append(point)
        
        // Update current
        currentReading = CGMReading(glucose: glucose, trend: trend, timestamp: timestamp)
        
        // Prune old points
        let cutoff = Date().addingTimeInterval(-TimeInterval(hoursToDisplay * 3600))
        dataPoints.removeAll { $0.timestamp < cutoff }
    }
    
    /// Calculate delta from last two readings
    public var deltaValue: Double? {
        guard dataPoints.count >= 2 else { return nil }
        let sorted = dataPoints.sorted { $0.timestamp > $1.timestamp }
        return sorted[0].value - sorted[1].value
    }
    
    /// Update connection status
    public func setConnected(_ connected: Bool) {
        isConnected = connected
    }
    
    /// Update sensor info
    public func setSensorInfo(_ info: CGMSensorInfo) {
        sensorInfo = info
    }
    
    /// Clear all data
    public func clear() {
        dataPoints = []
        currentReading = nil
        error = nil
    }
}

// MARK: - CGM Data Types

public struct CGMDataPoint: Identifiable {
    public let id = UUID()
    public let timestamp: Date
    public let value: Double
    public let trend: String?
    
    public init(timestamp: Date, value: Double, trend: String? = nil) {
        self.timestamp = timestamp
        self.value = value
        self.trend = trend
    }
}

public struct CGMReading {
    public let glucose: Double
    public let trend: String?
    public let timestamp: Date
    
    public init(glucose: Double, trend: String?, timestamp: Date) {
        self.glucose = glucose
        self.trend = trend
        self.timestamp = timestamp
    }
}

public struct CGMSensorInfo {
    public let transmitterID: String
    public let sensorStart: Date?
    public let daysRemaining: Int?
    
    public init(transmitterID: String, sensorStart: Date? = nil, daysRemaining: Int? = nil) {
        self.transmitterID = transmitterID
        self.sensorStart = sensorStart
        self.daysRemaining = daysRemaining
    }
}

// MARK: - CGM History Chart (iOS 16+)

@available(iOS 16.0, macOS 13.0, *)
private struct CGMHistoryChart: View {
    let dataPoints: [CGMDataPoint]
    let targetLow: Double
    let targetHigh: Double
    
    var body: some View {
        #if canImport(Charts)
        Chart {
            // Target range
            RectangleMark(
                yStart: .value("Low", targetLow),
                yEnd: .value("High", targetHigh)
            )
            .foregroundStyle(.green.opacity(0.1))
            
            // Glucose points
            ForEach(dataPoints) { point in
                PointMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Glucose", point.value)
                )
                .foregroundStyle(colorForValue(point.value))
                .symbolSize(30)
            }
            
            // Connecting line
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Glucose", point.value)
                )
                .foregroundStyle(.blue.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }
        }
        .chartYScale(domain: 40...300)
        #else
        Text("Charts require iOS 16+")
        #endif
    }
    
    private func colorForValue(_ value: Double) -> Color {
        if value < 55 { return .red }
        if value < 70 { return .orange }
        if value <= 180 { return .green }
        if value <= 250 { return .orange }
        return .red
    }
}

// MARK: - Legacy CGM Chart

private struct LegacyCGMChart: View {
    let dataPoints: [CGMDataPoint]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Points
                ForEach(Array(dataPoints.enumerated()), id: \.offset) { index, point in
                    let x = geometry.size.width * CGFloat(index) / CGFloat(max(1, dataPoints.count - 1))
                    let y = yPosition(for: point.value, in: geometry.size.height)
                    
                    Circle()
                        .fill(colorForValue(point.value))
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                }
            }
        }
    }
    
    private func yPosition(for value: Double, in height: CGFloat) -> CGFloat {
        let minVal = 40.0
        let maxVal = 300.0
        let range = maxVal - minVal
        return height * (1 - CGFloat((value - minVal) / range))
    }
    
    private func colorForValue(_ value: Double) -> Color {
        if value < 55 { return .red }
        if value < 70 { return .orange }
        if value <= 180 { return .green }
        if value <= 250 { return .orange }
        return .red
    }
}

#endif
