// SPDX-License-Identifier: MIT
//
// SupplyOrderReminderTests.swift
// T1PalCoreTests
//
// Tests for predictive supply order reminders (LIFE-UI-005)

import Testing
import Foundation
@testable import T1PalCore

@Suite("Supply Order Reminder Tests")
struct SupplyOrderReminderTests {
    
    // MARK: - SupplyType Tests
    
    @Test("All supply types have display names")
    func allTypesHaveDisplayNames() {
        for type in SupplyType.allCases {
            #expect(!type.displayName.isEmpty, "\(type) should have display name")
        }
    }
    
    @Test("All supply types have default lead times")
    func allTypesHaveLeadTimes() {
        for type in SupplyType.allCases {
            #expect(type.defaultLeadTimeDays > 0, "\(type) should have lead time > 0")
        }
    }
    
    @Test("Transmitter has longer lead time than sensor")
    func transmitterHasLongerLeadTime() {
        #expect(SupplyType.transmitter.defaultLeadTimeDays > SupplyType.sensor.defaultLeadTimeDays)
    }
    
    @Test("All supply types have icons")
    func allTypesHaveIcons() {
        for type in SupplyType.allCases {
            #expect(!type.iconName.isEmpty, "\(type) should have icon")
        }
    }
    
    // MARK: - SupplyStatus Tests
    
    @Test("Supply status tracks days remaining")
    func supplyStatusDaysRemaining() {
        let status = SupplyStatus(
            type: .sensor,
            daysRemaining: 5.5,
            expirationDate: Date().addingTimeInterval(5.5 * 86400)
        )
        #expect(status.daysRemaining == 5.5)
        #expect(!status.isExpired)
    }
    
    @Test("Expired supply has negative or zero days")
    func expiredSupplyStatus() {
        let status = SupplyStatus(type: .sensor, daysRemaining: 0)
        #expect(status.isExpired)
        
        let negativeStatus = SupplyStatus(type: .sensor, daysRemaining: -1)
        #expect(negativeStatus.isExpired)
    }
    
    @Test("Supply needs attention when < 3 days")
    func supplyNeedsAttention() {
        let status2 = SupplyStatus(type: .sensor, daysRemaining: 2)
        #expect(status2.needsAttention)
        
        let status5 = SupplyStatus(type: .sensor, daysRemaining: 5)
        #expect(!status5.needsAttention)
    }
    
    // MARK: - SupplyOrderConfig Tests
    
    @Test("Default config has all supplies enabled")
    func defaultConfigAllEnabled() {
        let config = SupplyOrderConfig.default
        for type in SupplyType.allCases {
            #expect(config.isEnabled(for: type), "\(type) should be enabled by default")
        }
    }
    
    @Test("Config uses type default when no custom lead time")
    func configUsesDefaultLeadTime() {
        let config = SupplyOrderConfig()
        #expect(config.leadTime(for: .sensor) == SupplyType.sensor.defaultLeadTimeDays)
    }
    
    @Test("Config uses custom lead time when set")
    func configUsesCustomLeadTime() {
        let config = SupplyOrderConfig(leadTimes: [.sensor: 10])
        #expect(config.leadTime(for: .sensor) == 10)
        #expect(config.leadTime(for: .pod) == SupplyType.pod.defaultLeadTimeDays)
    }
    
    @Test("Config reminder hour is clamped")
    func configReminderHourClamped() {
        let config = SupplyOrderConfig(reminderHour: 25)
        #expect(config.reminderHour == 23)
        
        let negConfig = SupplyOrderConfig(reminderHour: -5)
        #expect(negConfig.reminderHour == 0)
    }
    
    // MARK: - OrderUrgency Tests
    
    @Test("Order urgency from days until order")
    func orderUrgencyFromDays() {
        #expect(OrderUrgency.from(daysUntilOrder: -1) == .orderNow)
        #expect(OrderUrgency.from(daysUntilOrder: 0) == .orderNow)
        #expect(OrderUrgency.from(daysUntilOrder: 2) == .orderSoon)
        #expect(OrderUrgency.from(daysUntilOrder: 5) == .planAhead)
        #expect(OrderUrgency.from(daysUntilOrder: 10) == .adequate)
    }
    
    @Test("Order urgency is comparable")
    func orderUrgencyComparable() {
        #expect(OrderUrgency.orderNow < OrderUrgency.orderSoon)
        #expect(OrderUrgency.orderSoon < OrderUrgency.planAhead)
        #expect(OrderUrgency.planAhead < OrderUrgency.adequate)
    }
    
    @Test("Only non-adequate urgencies should notify")
    func urgencyShouldNotify() {
        #expect(OrderUrgency.orderNow.shouldNotify)
        #expect(OrderUrgency.orderSoon.shouldNotify)
        #expect(OrderUrgency.planAhead.shouldNotify)
        #expect(!OrderUrgency.adequate.shouldNotify)
    }
    
    // MARK: - SupplyOrderCalculator Tests
    
    @Test("Calculator returns nil for disabled supply")
    func calculatorDisabledSupply() {
        var config = SupplyOrderConfig()
        config.enabledSupplies.remove(.sensor)
        let calculator = SupplyOrderCalculator(config: config)
        
        let status = SupplyStatus(type: .sensor, daysRemaining: 5)
        let recommendation = calculator.calculateRecommendation(for: status)
        
        #expect(recommendation == nil)
    }
    
    @Test("Calculator calculates order date correctly")
    func calculatorOrderDate() {
        let config = SupplyOrderConfig(leadTimes: [.sensor: 7])
        let calculator = SupplyOrderCalculator(config: config)
        
        // 14 days remaining, 7 day lead time = order in 7 days
        let status = SupplyStatus(type: .sensor, daysRemaining: 14)
        let now = Date()
        let recommendation = calculator.calculateRecommendation(for: status, at: now)
        
        #expect(recommendation != nil)
        #expect(recommendation?.daysUntilOrder == 7)
        #expect(recommendation?.urgency == .planAhead)
    }
    
    @Test("Calculator returns order now for overdue")
    func calculatorOrderNow() {
        let config = SupplyOrderConfig(leadTimes: [.sensor: 7])
        let calculator = SupplyOrderCalculator(config: config)
        
        // 3 days remaining, 7 day lead time = should have ordered 4 days ago
        let status = SupplyStatus(type: .sensor, daysRemaining: 3)
        let recommendation = calculator.calculateRecommendation(for: status)
        
        #expect(recommendation != nil)
        #expect(recommendation?.urgency == .orderNow)
    }
    
    @Test("Calculator sorts recommendations by urgency")
    func calculatorSortsByUrgency() {
        let calculator = SupplyOrderCalculator()
        
        let statuses = [
            SupplyStatus(type: .transmitter, daysRemaining: 30),  // adequate
            SupplyStatus(type: .sensor, daysRemaining: 5),        // orderSoon (5-7=~-2 -> orderNow)
            SupplyStatus(type: .pod, daysRemaining: 10),          // planAhead
        ]
        
        let recommendations = calculator.calculateRecommendations(for: statuses)
        
        #expect(recommendations.count == 3)
        // First should be most urgent
        #expect(recommendations[0].supplyType == .sensor)
    }
    
    // MARK: - SupplyOrderRecommendation Tests
    
    @Test("Recommendation has formatted message")
    func recommendationMessage() {
        let status = SupplyStatus(type: .sensor, daysRemaining: 5)
        let recommendation = SupplyOrderRecommendation(
            supplyType: .sensor,
            orderByDate: Date().addingTimeInterval(3 * 86400),
            daysUntilOrder: 3,
            currentStatus: status,
            urgency: .orderSoon
        )
        
        #expect(recommendation.message.contains("CGM Sensor"))
        #expect(recommendation.message.contains("3 days"))
    }
    
    // MARK: - Persistence Tests
    
    @Test("InMemory persistence saves and loads config")
    func inMemoryPersistenceConfig() async {
        let persistence = InMemorySupplyOrderPersistence()
        
        let config = SupplyOrderConfig(leadTimes: [.insulin: 21])
        await persistence.saveConfig(config)
        
        let loaded = await persistence.loadConfig()
        #expect(loaded?.leadTime(for: .insulin) == 21)
    }
    
    @Test("InMemory persistence saves and loads last reminder")
    func inMemoryPersistenceReminder() async {
        let persistence = InMemorySupplyOrderPersistence()
        let date = Date()
        
        await persistence.saveLastReminder(for: .sensor, date: date)
        let loaded = await persistence.loadLastReminder(for: .sensor)
        
        #expect(loaded != nil)
        #expect(abs(loaded!.timeIntervalSince(date)) < 1)
    }
    
    // MARK: - SupplyOrderReminderService Tests
    
    @Test("Service calculates recommendations from statuses")
    func serviceCalculatesRecommendations() async {
        let service = SupplyOrderReminderService(persistence: InMemorySupplyOrderPersistence())
        
        await service.updateSupplyStatus(SupplyStatus(type: .sensor, daysRemaining: 10))
        await service.updateSupplyStatus(SupplyStatus(type: .pod, daysRemaining: 5))
        
        let recommendations = await service.calculateRecommendations()
        #expect(recommendations.count == 2)
    }
    
    @Test("Service summary provides urgency counts")
    func serviceSummary() async {
        let service = SupplyOrderReminderService(persistence: InMemorySupplyOrderPersistence())
        
        // Sensor: 3 days remaining, 7 day lead = orderNow
        await service.updateSupplyStatus(SupplyStatus(type: .sensor, daysRemaining: 3))
        // Pod: 20 days remaining, 7 day lead = adequate
        await service.updateSupplyStatus(SupplyStatus(type: .pod, daysRemaining: 20))
        
        let summary = await service.summary()
        #expect(summary.urgentCount == 1)
        #expect(summary.adequateCount == 1)
        #expect(summary.statusColor == "red")
    }
    
    @Test("Service updates config")
    func serviceUpdatesConfig() async {
        let service = SupplyOrderReminderService(persistence: InMemorySupplyOrderPersistence())
        
        let newConfig = SupplyOrderConfig(leadTimes: [.insulin: 30])
        await service.updateConfig(newConfig)
        
        let retrieved = await service.getConfig()
        #expect(retrieved.leadTime(for: .insulin) == 30)
    }
    
    // MARK: - SupplyOrderSummary Tests
    
    @Test("Summary short message for urgent")
    func summaryMessageUrgent() {
        let summary = SupplyOrderSummary(
            urgentCount: 2,
            planningCount: 1,
            adequateCount: 3,
            mostUrgent: nil,
            allRecommendations: []
        )
        #expect(summary.shortMessage.contains("2 supply orders needed"))
    }
    
    @Test("Summary short message for planning")
    func summaryMessagePlanning() {
        let summary = SupplyOrderSummary(
            urgentCount: 0,
            planningCount: 1,
            adequateCount: 3,
            mostUrgent: nil,
            allRecommendations: []
        )
        #expect(summary.shortMessage.contains("1 supply order to plan"))
    }
    
    @Test("Summary short message for adequate")
    func summaryMessageAdequate() {
        let summary = SupplyOrderSummary(
            urgentCount: 0,
            planningCount: 0,
            adequateCount: 3,
            mostUrgent: nil,
            allRecommendations: []
        )
        #expect(summary.shortMessage == "All supplies adequate")
    }
}
