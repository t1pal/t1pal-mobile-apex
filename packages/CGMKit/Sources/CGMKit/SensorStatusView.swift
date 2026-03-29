// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SensorStatusView.swift - CGM sensor status display
// Part of CGMKit
// Trace: CGM-UI-006, LIFE-UI-001, LIFE-UI-002

#if canImport(SwiftUI)
import SwiftUI

// MARK: - Transmitter Warning Level (LIFE-UI-001)

/// Warning level for transmitter lifecycle display
public enum TransmitterWarningLevel: String, Sendable {
    case unknown = "unknown"
    case healthy = "healthy"
    case attention = "attention"   // 14 days remaining
    case caution = "caution"       // 7 days remaining
    case warning = "warning"       // 3 days remaining
    case critical = "critical"     // 1 day remaining
    case expired = "expired"
    
    /// Color for this warning level
    public var color: Color {
        switch self {
        case .unknown: return .gray
        case .healthy: return .green
        case .attention: return .blue
        case .caution: return .yellow
        case .warning: return .orange
        case .critical, .expired: return .red
        }
    }
    
    /// Icon for this warning level
    public var iconName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .healthy: return "checkmark.circle.fill"
        case .attention: return "info.circle.fill"
        case .caution: return "exclamationmark.triangle"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .expired: return "xmark.octagon.fill"
        }
    }
}

/// Sensor lifecycle state (CGM-GRACE-001)
public enum SensorLifecycleState: String, Sendable {
    case warmingUp = "Warming Up"
    case active = "Active"
    case gracePeriod = "Grace Period"
    case expired = "Expired"
    
    /// Color for UI display
    public var color: String {
        switch self {
        case .warmingUp: return "blue"
        case .active: return "green"
        case .gracePeriod: return "purple"
        case .expired: return "red"
        }
    }
    
    /// SF Symbol for state
    public var systemImage: String {
        switch self {
        case .warmingUp: return "hourglass"
        case .active: return "checkmark.circle.fill"
        case .gracePeriod: return "clock.badge.exclamationmark"
        case .expired: return "xmark.circle.fill"
        }
    }
}

/// Sensor status information
public struct SensorStatus: Sendable, Equatable {
    public let sensorType: String           // "Dexcom G6", "Libre 2", etc.
    public let transmitterID: String?
    public let sensorStartDate: Date?
    public let sensorEndDate: Date?
    public let lastCalibrationDate: Date?
    public let calibrationCount: Int
    public let signalStrength: Int?         // RSSI or quality indicator
    public let batteryLevel: Int?           // Transmitter battery %
    public let warmupRemaining: TimeInterval?
    public let isWarmingUp: Bool
    public let isExpired: Bool
    public let errorCode: String?
    
    // MARK: - Grace Period (CGM-GRACE-001)
    
    /// Whether sensor is in grace period (expired but still providing data)
    public let isInGracePeriod: Bool
    /// End of grace period (typically 12h after sensorEndDate)
    public let graceEndDate: Date?
    
    // MARK: - Transmitter Lifecycle (LIFE-UI-001, LIFE-UI-002)
    
    /// Transmitter activation date (for 90-day tracking)
    public let transmitterActivationDate: Date?
    /// Transmitter lifetime in days (default 90 for G6)
    public let transmitterLifetimeDays: Int?
    
    public init(
        sensorType: String,
        transmitterID: String? = nil,
        sensorStartDate: Date? = nil,
        sensorEndDate: Date? = nil,
        lastCalibrationDate: Date? = nil,
        calibrationCount: Int = 0,
        signalStrength: Int? = nil,
        batteryLevel: Int? = nil,
        warmupRemaining: TimeInterval? = nil,
        isWarmingUp: Bool = false,
        isExpired: Bool = false,
        errorCode: String? = nil,
        isInGracePeriod: Bool = false,
        graceEndDate: Date? = nil,
        transmitterActivationDate: Date? = nil,
        transmitterLifetimeDays: Int? = nil
    ) {
        self.sensorType = sensorType
        self.transmitterID = transmitterID
        self.sensorStartDate = sensorStartDate
        self.sensorEndDate = sensorEndDate
        self.lastCalibrationDate = lastCalibrationDate
        self.calibrationCount = calibrationCount
        self.signalStrength = signalStrength
        self.batteryLevel = batteryLevel
        self.warmupRemaining = warmupRemaining
        self.isWarmingUp = isWarmingUp
        self.isExpired = isExpired
        self.errorCode = errorCode
        self.isInGracePeriod = isInGracePeriod
        self.graceEndDate = graceEndDate
        self.transmitterActivationDate = transmitterActivationDate
        self.transmitterLifetimeDays = transmitterLifetimeDays
    }
    
    // MARK: - Transmitter Lifecycle Computed Properties
    
    /// Transmitter expiration date
    public var transmitterExpirationDate: Date? {
        guard let activation = transmitterActivationDate,
              let lifetime = transmitterLifetimeDays else { return nil }
        return activation.addingTimeInterval(TimeInterval(lifetime) * 86400)
    }
    
    /// Days remaining on transmitter
    public var transmitterDaysRemaining: Double? {
        guard let expiration = transmitterExpirationDate else { return nil }
        let remaining = expiration.timeIntervalSinceNow / 86400.0
        return max(remaining, 0)
    }
    
    /// Transmitter usage percentage (0.0 to 1.0+)
    public var transmitterUsedPercentage: Double? {
        guard let activation = transmitterActivationDate,
              let lifetime = transmitterLifetimeDays else { return nil }
        let elapsed = Date().timeIntervalSince(activation) / 86400.0
        return elapsed / Double(lifetime)
    }
    
    /// Whether transmitter has expired
    public var transmitterIsExpired: Bool {
        guard let days = transmitterDaysRemaining else { return false }
        return days <= 0
    }
    
    /// Transmitter warning level based on days remaining
    public var transmitterWarningLevel: TransmitterWarningLevel {
        guard let days = transmitterDaysRemaining else { return .unknown }
        if days <= 0 { return .expired }
        if days <= 1 { return .critical }
        if days <= 3 { return .warning }
        if days <= 7 { return .caution }
        if days <= 14 { return .attention }
        return .healthy
    }
    
    /// Time remaining until sensor expires
    public var timeRemaining: TimeInterval? {
        guard let endDate = sensorEndDate else { return nil }
        let remaining = endDate.timeIntervalSinceNow
        return remaining > 0 ? remaining : 0
    }
    
    /// Percentage of sensor life used
    public var usedPercentage: Double? {
        guard let startDate = sensorStartDate,
              let endDate = sensorEndDate else { return nil }
        
        let totalLife = endDate.timeIntervalSince(startDate)
        let elapsed = Date().timeIntervalSince(startDate)
        
        return min(max(elapsed / totalLife, 0), 1)
    }
    
    // MARK: - Grace Period Computed Properties (CGM-GRACE-001)
    
    /// Time remaining in grace period (nil if not in grace period)
    public var graceTimeRemaining: TimeInterval? {
        guard isInGracePeriod, let graceEnd = graceEndDate else { return nil }
        let remaining = graceEnd.timeIntervalSinceNow
        return remaining > 0 ? remaining : 0
    }
    
    /// Hours remaining in grace period
    public var graceHoursRemaining: Double? {
        guard let remaining = graceTimeRemaining else { return nil }
        return remaining / 3600.0
    }
    
    /// Lifecycle state for UI display
    public var lifecycleState: SensorLifecycleState {
        if isWarmingUp { return .warmingUp }
        if isInGracePeriod { return .gracePeriod }
        if isExpired { return .expired }
        return .active
    }
    
    /// Sample status for previews
    public static let sample = SensorStatus(
        sensorType: "Dexcom G6",
        transmitterID: "8G1234",
        sensorStartDate: Date().addingTimeInterval(-7 * 24 * 3600),
        sensorEndDate: Date().addingTimeInterval(3 * 24 * 3600),
        lastCalibrationDate: Date().addingTimeInterval(-6 * 3600),
        calibrationCount: 2,
        signalStrength: -65,
        batteryLevel: 85,
        transmitterActivationDate: Date().addingTimeInterval(-75 * 24 * 3600), // 75 days ago
        transmitterLifetimeDays: 90  // 15 days remaining
    )
}

/// View displaying CGM sensor status
@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
public struct SensorStatusView: View {
    public let status: SensorStatus
    public var onCalibrate: (() -> Void)?
    public var onStartNewSensor: (() -> Void)?
    
    public init(
        status: SensorStatus,
        onCalibrate: (() -> Void)? = nil,
        onStartNewSensor: (() -> Void)? = nil
    ) {
        self.status = status
        self.onCalibrate = onCalibrate
        self.onStartNewSensor = onStartNewSensor
    }
    
    public var body: some View {
        List {
            // Status Header
            Section {
                statusHeaderCard
            }
            
            // Sensor Life
            if status.sensorStartDate != nil {
                Section("Sensor Life") {
                    sensorLifeSection
                }
            }
            
            // Transmitter
            if status.transmitterID != nil || status.batteryLevel != nil {
                Section("Transmitter") {
                    transmitterSection
                }
            }
            
            // Calibration
            Section("Calibration") {
                calibrationSection
            }
            
            // Connection
            if status.signalStrength != nil {
                Section("Connection") {
                    connectionSection
                }
            }
            
            // Errors
            if let error = status.errorCode {
                Section {
                    errorRow(error)
                }
            }
            
            // Actions
            Section {
                actionsSection
            }
        }
        .navigationTitle("Sensor Status")
    }
    
    // MARK: - Status Header
    
    private var statusHeaderCard: some View {
        HStack(spacing: 16) {
            statusIcon
                .font(.system(size: 50))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(status.sensorType)
                    .font(.headline)
                
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 60, height: 60)
            
            Image(systemName: statusIconName)
                .foregroundColor(statusColor)
        }
    }
    
    private var statusIconName: String {
        if status.isWarmingUp {
            return "hourglass"
        } else if status.isExpired {
            return "exclamationmark.triangle.fill"
        } else if status.errorCode != nil {
            return "xmark.circle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }
    
    private var statusText: String {
        if status.isWarmingUp {
            if let remaining = status.warmupRemaining {
                let minutes = Int(remaining / 60)
                return "Warming up (\(minutes) min remaining)"
            }
            return "Warming up..."
        } else if status.isExpired {
            return "Sensor expired"
        } else if status.errorCode != nil {
            return "Error"
        } else {
            return "Active"
        }
    }
    
    private var statusColor: Color {
        if status.isWarmingUp {
            return .orange
        } else if status.isExpired || status.errorCode != nil {
            return .red
        } else {
            return .green
        }
    }
    
    // MARK: - Sensor Life Section
    
    private var sensorLifeSection: some View {
        VStack(spacing: 12) {
            // Progress bar
            if let percentage = status.usedPercentage {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor(percentage))
                                .frame(width: geometry.size.width * CGFloat(percentage))
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("Used: \(Int(percentage * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let remaining = status.timeRemaining {
                            Text(formatTimeRemaining(remaining))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Start/End dates
            if let start = status.sensorStartDate {
                detailRow(label: "Started", value: formatDate(start))
            }
            if let end = status.sensorEndDate {
                detailRow(label: "Expires", value: formatDate(end))
            }
        }
    }
    
    private func progressColor(_ percentage: Double) -> Color {
        if percentage > 0.9 {
            return .red
        } else if percentage > 0.75 {
            return .orange
        } else {
            return .green
        }
    }
    
    // MARK: - Transmitter Section
    
    private var transmitterSection: some View {
        VStack(spacing: 8) {
            if let id = status.transmitterID {
                detailRow(label: "ID", value: id)
            }
            
            // LIFE-UI-001: Transmitter days remaining
            if let daysRemaining = status.transmitterDaysRemaining {
                transmitterLifecycleRow(daysRemaining: daysRemaining)
            }
            
            // LIFE-UI-002: Transmitter lifecycle progress bar
            if let percentage = status.transmitterUsedPercentage {
                transmitterProgressBar(percentage: percentage)
            }
            
            if let battery = status.batteryLevel {
                HStack {
                    Text("Battery")
                        .foregroundColor(.secondary)
                    Spacer()
                    batteryIndicator(level: battery)
                }
            }
        }
    }
    
    // LIFE-UI-001: Transmitter days remaining row
    private func transmitterLifecycleRow(daysRemaining: Double) -> some View {
        HStack {
            Text("Transmitter Life")
                .foregroundColor(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: status.transmitterWarningLevel.iconName)
                    .foregroundColor(status.transmitterWarningLevel.color)
                Text(formatTransmitterDaysRemaining(daysRemaining))
                    .font(.body.monospacedDigit())
                    .foregroundColor(status.transmitterWarningLevel.color)
            }
        }
    }
    
    // LIFE-UI-002: Transmitter lifecycle progress bar
    private func transmitterProgressBar(percentage: Double) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(transmitterProgressColor(percentage))
                        .frame(width: geometry.size.width * CGFloat(min(percentage, 1.0)))
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("Age: \(Int(percentage * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let expiration = status.transmitterExpirationDate {
                    Text("Expires: \(formatDate(expiration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func transmitterProgressColor(_ percentage: Double) -> Color {
        if percentage >= 1.0 {
            return .red
        } else if percentage > 0.9 {
            return .orange
        } else if percentage > 0.75 {
            return .yellow
        } else {
            return .green
        }
    }
    
    private func formatTransmitterDaysRemaining(_ days: Double) -> String {
        if days <= 0 {
            return "Expired"
        } else if days < 1 {
            let hours = Int(days * 24)
            return "\(hours) hours"
        } else if days < 7 {
            return String(format: "%.0f days", days)
        } else {
            let weeks = days / 7
            return String(format: "%.1f weeks", weeks)
        }
    }
    
    private func batteryIndicator(level: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon(level: level))
                .foregroundColor(batteryColor(level: level))
            Text("\(level)%")
                .font(.body.monospacedDigit())
        }
    }
    
    private func batteryIcon(level: Int) -> String {
        switch level {
        case 0..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func batteryColor(level: Int) -> Color {
        switch level {
        case 0..<20: return .red
        case 20..<40: return .orange
        default: return .green
        }
    }
    
    // MARK: - Calibration Section
    
    private var calibrationSection: some View {
        VStack(spacing: 8) {
            detailRow(
                label: "Calibrations",
                value: "\(status.calibrationCount)"
            )
            
            if let lastCal = status.lastCalibrationDate {
                detailRow(
                    label: "Last Calibration",
                    value: formatRelativeDate(lastCal)
                )
            }
        }
    }
    
    // MARK: - Connection Section
    
    private var connectionSection: some View {
        VStack(spacing: 8) {
            if let rssi = status.signalStrength {
                HStack {
                    Text("Signal Strength")
                        .foregroundColor(.secondary)
                    Spacer()
                    signalIndicator(rssi: rssi)
                }
            }
        }
    }
    
    private func signalIndicator(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { bar in
                Rectangle()
                    .fill(bar < signalBars(rssi: rssi) ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(8 + bar * 4))
            }
            Text("\(rssi) dBm")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
    }
    
    private func signalBars(rssi: Int) -> Int {
        switch rssi {
        case -50...0: return 4
        case -60..<(-50): return 3
        case -70..<(-60): return 2
        default: return 1
        }
    }
    
    // MARK: - Error Row
    
    private func errorRow(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(error)
                .foregroundColor(.red)
        }
    }
    
    // MARK: - Actions Section
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            if let onCalibrate = onCalibrate, !status.isExpired {
                Button(action: onCalibrate) {
                    Label("Enter Calibration", systemImage: "drop.fill")
                }
            }
            
            if let onStartNew = onStartNewSensor {
                Button(action: onStartNew) {
                    Label("Start New Sensor", systemImage: "sensor.tag.radiowaves.forward")
                }
                .foregroundColor(status.isExpired ? .accentColor : .secondary)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func formatTimeRemaining(_ interval: TimeInterval) -> String {
        let days = Int(interval / 86400)
        let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
        
        if days > 0 {
            return "\(days)d \(hours)h remaining"
        } else {
            return "\(hours)h remaining"
        }
    }
}

// MARK: - Preview

@available(iOS 15.0, macOS 12.0, watchOS 8.0, *)
struct SensorStatusView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SensorStatusView(
                status: .sample,
                onCalibrate: {},
                onStartNewSensor: {}
            )
        }
    }
}

#endif
