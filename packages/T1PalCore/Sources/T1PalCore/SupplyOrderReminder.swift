// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2026 T1Pal.org
//
// SupplyOrderReminder.swift
// T1PalCore
//
// Predictive supply ordering reminders based on consumable lifecycle data.
// Aggregates sensor, transmitter, pod, and infusion site data to calculate
// when supplies should be ordered based on configurable lead times.
//
// Trace: LIFE-UI-005

import Foundation

// MARK: - Supply Types

/// Types of diabetes supplies that can be tracked for ordering
public enum SupplyType: String, CaseIterable, Sendable, Codable {
    case sensor = "sensor"
    case transmitter = "transmitter"
    case pod = "pod"
    case reservoir = "reservoir"
    case infusionSet = "infusion_set"
    case cartridge = "cartridge"
    case insulin = "insulin"
    
    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .sensor: return "CGM Sensor"
        case .transmitter: return "Transmitter"
        case .pod: return "Insulin Pods"
        case .reservoir: return "Pump Reservoirs"
        case .infusionSet: return "Infusion Sets"
        case .cartridge: return "Pump Cartridges"
        case .insulin: return "Insulin"
        }
    }
    
    /// Default shipping lead time in days
    public var defaultLeadTimeDays: Int {
        switch self {
        case .sensor: return 7          // Order 1 week ahead
        case .transmitter: return 14    // Order 2 weeks ahead (90-day item)
        case .pod: return 7             // Order 1 week ahead
        case .reservoir: return 7       // Order 1 week ahead
        case .infusionSet: return 7     // Order 1 week ahead
        case .cartridge: return 7       // Order 1 week ahead
        case .insulin: return 14        // Order 2 weeks ahead (critical)
        }
    }
    
    /// SF Symbol icon name
    public var iconName: String {
        switch self {
        case .sensor: return "sensor.fill"
        case .transmitter: return "antenna.radiowaves.left.and.right"
        case .pod: return "cross.vial.fill"
        case .reservoir: return "cylinder.fill"
        case .infusionSet: return "syringe.fill"
        case .cartridge: return "cylinder.fill"
        case .insulin: return "drop.fill"
        }
    }
}

// MARK: - Supply Status

/// Current status of a supply item
public struct SupplyStatus: Sendable, Codable, Equatable {
    public let type: SupplyType
    public let daysRemaining: Double
    public let expirationDate: Date?
    public let unitsRemaining: Double?
    public let lastUpdated: Date
    
    public init(
        type: SupplyType,
        daysRemaining: Double,
        expirationDate: Date? = nil,
        unitsRemaining: Double? = nil,
        lastUpdated: Date = Date()
    ) {
        self.type = type
        self.daysRemaining = daysRemaining
        self.expirationDate = expirationDate
        self.unitsRemaining = unitsRemaining
        self.lastUpdated = lastUpdated
    }
    
    /// Whether this supply is expired
    public var isExpired: Bool {
        daysRemaining <= 0
    }
    
    /// Whether this supply needs attention soon (< 3 days)
    public var needsAttention: Bool {
        daysRemaining <= 3 && daysRemaining > 0
    }
}

// MARK: - Order Reminder Configuration

/// User-configurable settings for supply order reminders
public struct SupplyOrderConfig: Sendable, Codable, Equatable {
    /// Lead time in days for each supply type
    public var leadTimes: [SupplyType: Int]
    
    /// Whether reminders are enabled for each supply type
    public var enabledSupplies: Set<SupplyType>
    
    /// Time of day to send reminders (hour, 0-23)
    public var reminderHour: Int
    
    /// Days of week to send reminders (1=Sun, 7=Sat)
    public var reminderDays: Set<Int>
    
    public init(
        leadTimes: [SupplyType: Int] = [:],
        enabledSupplies: Set<SupplyType> = Set(SupplyType.allCases),
        reminderHour: Int = 9,  // 9 AM default
        reminderDays: Set<Int> = [2, 3, 4, 5, 6]  // Mon-Fri
    ) {
        self.leadTimes = leadTimes
        self.enabledSupplies = enabledSupplies
        self.reminderHour = min(23, max(0, reminderHour))
        self.reminderDays = reminderDays
    }
    
    /// Get lead time for a supply type, using default if not configured
    public func leadTime(for type: SupplyType) -> Int {
        leadTimes[type] ?? type.defaultLeadTimeDays
    }
    
    /// Whether reminders are enabled for a supply type
    public func isEnabled(for type: SupplyType) -> Bool {
        enabledSupplies.contains(type)
    }
    
    public static let `default` = SupplyOrderConfig()
}

// MARK: - Order Recommendation

/// A recommendation to order supplies
public struct SupplyOrderRecommendation: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let supplyType: SupplyType
    public let orderByDate: Date
    public let daysUntilOrder: Int
    public let currentStatus: SupplyStatus
    public let urgency: OrderUrgency
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        supplyType: SupplyType,
        orderByDate: Date,
        daysUntilOrder: Int,
        currentStatus: SupplyStatus,
        urgency: OrderUrgency,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.supplyType = supplyType
        self.orderByDate = orderByDate
        self.daysUntilOrder = daysUntilOrder
        self.currentStatus = currentStatus
        self.urgency = urgency
        self.createdAt = createdAt
    }
    
    /// Formatted message for the order reminder
    public var message: String {
        switch urgency {
        case .orderNow:
            return "Order \(supplyType.displayName) now — supplies running low"
        case .orderSoon:
            return "Order \(supplyType.displayName) within \(daysUntilOrder) days"
        case .planAhead:
            return "Plan to order \(supplyType.displayName) by \(formattedOrderDate)"
        case .adequate:
            return "\(supplyType.displayName) supplies adequate"
        }
    }
    
    /// Formatted order-by date
    public var formattedOrderDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: orderByDate)
    }
}

/// Urgency level for ordering supplies
public enum OrderUrgency: String, Sendable, Codable, Comparable {
    case orderNow = "order_now"       // <= 0 days until order date
    case orderSoon = "order_soon"     // 1-3 days until order date
    case planAhead = "plan_ahead"     // 4-7 days until order date
    case adequate = "adequate"        // > 7 days until order date
    
    public static func from(daysUntilOrder: Int) -> OrderUrgency {
        switch daysUntilOrder {
        case ...0: return .orderNow
        case 1...3: return .orderSoon
        case 4...7: return .planAhead
        default: return .adequate
        }
    }
    
    public static func < (lhs: OrderUrgency, rhs: OrderUrgency) -> Bool {
        lhs.priority < rhs.priority
    }
    
    private var priority: Int {
        switch self {
        case .orderNow: return 0
        case .orderSoon: return 1
        case .planAhead: return 2
        case .adequate: return 3
        }
    }
    
    /// Whether this urgency level should trigger a notification
    public var shouldNotify: Bool {
        self != .adequate
    }
}

// MARK: - Supply Order Calculator

/// Calculates supply order recommendations based on current status and lead times
public struct SupplyOrderCalculator: Sendable {
    private let config: SupplyOrderConfig
    
    public init(config: SupplyOrderConfig = .default) {
        self.config = config
    }
    
    /// Calculate order recommendation for a supply status
    public func calculateRecommendation(
        for status: SupplyStatus,
        at date: Date = Date()
    ) -> SupplyOrderRecommendation? {
        guard config.isEnabled(for: status.type) else { return nil }
        
        let leadTime = config.leadTime(for: status.type)
        let daysUntilOrder = Int(status.daysRemaining) - leadTime
        
        // Calculate order-by date
        let orderByDate = date.addingTimeInterval(TimeInterval(daysUntilOrder) * 86400)
        
        let urgency = OrderUrgency.from(daysUntilOrder: daysUntilOrder)
        
        return SupplyOrderRecommendation(
            supplyType: status.type,
            orderByDate: orderByDate,
            daysUntilOrder: max(0, daysUntilOrder),
            currentStatus: status,
            urgency: urgency
        )
    }
    
    /// Calculate recommendations for multiple supplies, sorted by urgency
    public func calculateRecommendations(
        for statuses: [SupplyStatus],
        at date: Date = Date()
    ) -> [SupplyOrderRecommendation] {
        statuses
            .compactMap { calculateRecommendation(for: $0, at: date) }
            .sorted { $0.urgency < $1.urgency }
    }
    
    /// Get the most urgent recommendation
    public func mostUrgent(
        from statuses: [SupplyStatus],
        at date: Date = Date()
    ) -> SupplyOrderRecommendation? {
        calculateRecommendations(for: statuses, at: date).first
    }
}

// MARK: - Supply Order Reminder Persistence

/// Protocol for persisting supply order reminder state
public protocol SupplyOrderReminderPersistence: Sendable {
    func saveConfig(_ config: SupplyOrderConfig) async
    func loadConfig() async -> SupplyOrderConfig?
    func saveLastReminder(for type: SupplyType, date: Date) async
    func loadLastReminder(for type: SupplyType) async -> Date?
}

/// In-memory persistence for testing
public actor InMemorySupplyOrderPersistence: SupplyOrderReminderPersistence {
    private var config: SupplyOrderConfig?
    private var lastReminders: [SupplyType: Date] = [:]
    
    public init() {}
    
    public func saveConfig(_ config: SupplyOrderConfig) async {
        self.config = config
    }
    
    public func loadConfig() async -> SupplyOrderConfig? {
        config
    }
    
    public func saveLastReminder(for type: SupplyType, date: Date) async {
        lastReminders[type] = date
    }
    
    public func loadLastReminder(for type: SupplyType) async -> Date? {
        lastReminders[type]
    }
}

/// UserDefaults persistence for production
public actor UserDefaultsSupplyOrderPersistence: SupplyOrderReminderPersistence {
    private let configKey = "com.t1pal.supplyorder.config"
    private let reminderKeyPrefix = "com.t1pal.supplyorder.lastreminder."
    
    public init() {}
    
    public func saveConfig(_ config: SupplyOrderConfig) async {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }
    
    public func loadConfig() async -> SupplyOrderConfig? {
        guard let data = UserDefaults.standard.data(forKey: configKey) else { return nil }
        return try? JSONDecoder().decode(SupplyOrderConfig.self, from: data)
    }
    
    public func saveLastReminder(for type: SupplyType, date: Date) async {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: reminderKeyPrefix + type.rawValue)
    }
    
    public func loadLastReminder(for type: SupplyType) async -> Date? {
        let interval = UserDefaults.standard.double(forKey: reminderKeyPrefix + type.rawValue)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}

// MARK: - Supply Order Reminder Service

/// Service that manages supply order reminders
public actor SupplyOrderReminderService {
    private let persistence: SupplyOrderReminderPersistence
    private var config: SupplyOrderConfig
    private var supplyStatuses: [SupplyType: SupplyStatus] = [:]
    
    /// Callback when a reminder should be sent
    public var onReminderDue: (@Sendable (SupplyOrderRecommendation) async -> Void)?
    
    public init(persistence: SupplyOrderReminderPersistence? = nil) {
        self.persistence = persistence ?? UserDefaultsSupplyOrderPersistence()
        self.config = .default
    }
    
    /// Load configuration from persistence
    public func loadConfig() async {
        if let saved = await persistence.loadConfig() {
            config = saved
        }
    }
    
    /// Update configuration
    public func updateConfig(_ newConfig: SupplyOrderConfig) async {
        config = newConfig
        await persistence.saveConfig(newConfig)
    }
    
    /// Get current configuration
    public func getConfig() -> SupplyOrderConfig {
        config
    }
    
    /// Update supply status from lifecycle monitors
    public func updateSupplyStatus(_ status: SupplyStatus) {
        supplyStatuses[status.type] = status
    }
    
    /// Get all current supply statuses
    public func getAllStatuses() -> [SupplyStatus] {
        Array(supplyStatuses.values)
    }
    
    /// Calculate current recommendations
    public func calculateRecommendations(at date: Date = Date()) -> [SupplyOrderRecommendation] {
        let calculator = SupplyOrderCalculator(config: config)
        return calculator.calculateRecommendations(for: getAllStatuses(), at: date)
    }
    
    /// Check if any reminders should be sent
    public func checkAndSendReminders(at date: Date = Date()) async {
        let recommendations = calculateRecommendations(at: date)
        
        for recommendation in recommendations {
            guard recommendation.urgency.shouldNotify else { continue }
            
            // Check if we already sent a reminder today for this type
            if let lastReminder = await persistence.loadLastReminder(for: recommendation.supplyType) {
                if Calendar.current.isDate(lastReminder, inSameDayAs: date) {
                    continue  // Already reminded today
                }
            }
            
            // Send reminder
            await onReminderDue?(recommendation)
            await persistence.saveLastReminder(for: recommendation.supplyType, date: date)
        }
    }
    
    /// Get the most urgent recommendation
    public func mostUrgentRecommendation(at date: Date = Date()) -> SupplyOrderRecommendation? {
        calculateRecommendations(at: date).first
    }
    
    /// Summary of supply status for UI display
    public func summary(at date: Date = Date()) -> SupplyOrderSummary {
        let recommendations = calculateRecommendations(at: date)
        let urgent = recommendations.filter { $0.urgency == .orderNow || $0.urgency == .orderSoon }
        let planning = recommendations.filter { $0.urgency == .planAhead }
        let adequate = recommendations.filter { $0.urgency == .adequate }
        
        return SupplyOrderSummary(
            urgentCount: urgent.count,
            planningCount: planning.count,
            adequateCount: adequate.count,
            mostUrgent: recommendations.first,
            allRecommendations: recommendations
        )
    }
}

/// Summary of supply order status for UI
public struct SupplyOrderSummary: Sendable {
    public let urgentCount: Int
    public let planningCount: Int
    public let adequateCount: Int
    public let mostUrgent: SupplyOrderRecommendation?
    public let allRecommendations: [SupplyOrderRecommendation]
    
    /// Overall status color hint
    public var statusColor: String {
        if urgentCount > 0 { return "red" }
        if planningCount > 0 { return "orange" }
        return "green"
    }
    
    /// Short status message
    public var shortMessage: String {
        if urgentCount > 0 {
            return "\(urgentCount) supply order\(urgentCount == 1 ? "" : "s") needed"
        } else if planningCount > 0 {
            return "\(planningCount) supply order\(planningCount == 1 ? "" : "s") to plan"
        } else {
            return "All supplies adequate"
        }
    }
}
