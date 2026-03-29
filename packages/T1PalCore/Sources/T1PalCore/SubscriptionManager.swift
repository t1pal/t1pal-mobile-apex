// SPDX-License-Identifier: AGPL-3.0-or-later
// SubscriptionManager.swift
// T1PalCore
//
// StoreKit 2 subscription management for T1Pal tier progression
// Trace: BIZ-002, PRD-015-business-features.md, PRD-028-apple-iap-integration.md

import Foundation

// MARK: - Backend API Types

/// Response from /webhooks/apple/verify
public struct BackendVerifyResponse: Codable, Sendable {
    public let ok: Int
    public let entitlement: BackendEntitlement?
    public let account: BackendAccountInfo?
    public let instance: BackendInstanceInfo?
    public let device: BackendDeviceInfo?
    public let error: String?
    public let message: String?
}

/// Entitlement from backend
public struct BackendEntitlement: Codable, Sendable {
    public let plan: String
    public let expiresAt: Date?
    public let features: [String]
    public let willAutoRenew: Bool
    
    enum CodingKeys: String, CodingKey {
        case plan, expiresAt, features, willAutoRenew
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decode(String.self, forKey: .plan)
        features = try container.decodeIfPresent([String].self, forKey: .features) ?? []
        willAutoRenew = try container.decodeIfPresent(Bool.self, forKey: .willAutoRenew) ?? false
        
        // Handle ISO8601 date
        if let dateString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            expiresAt = formatter.date(from: dateString)
        } else {
            expiresAt = nil
        }
    }
}

/// Account info from backend
public struct BackendAccountInfo: Codable, Sendable {
    public let linked: Bool
    public let email: String?
}

/// Nightscout instance info from backend
public struct BackendInstanceInfo: Codable, Sendable {
    public let url: String
    public let apiSecret: String
}

/// Device binding info from backend
public struct BackendDeviceInfo: Codable, Sendable {
    public let id: String
    public let needsAccountLink: Bool
}

// MARK: - Subscription Types

/// T1Pal subscription product identifiers
/// Simplified to single product: Personal hosting subscription
/// All app features are free (BYONS model). Subscription = managed NS hosting.
public enum T1PalProduct: String, CaseIterable, Sendable {
    case personalMonthly = "com.t1pal.personal.monthly"
    
    // Legacy products (for restore handling)
    case legacyPremiumMonthly = "com.t1pal.premium.monthly"
    case legacyPremiumYearly = "com.t1pal.premium.yearly"
    case legacyFamilyMonthly = "com.t1pal.family.monthly"
    case legacyFamilyYearly = "com.t1pal.family.yearly"
    case legacyFounderLifetime = "com.t1pal.founder.lifetime"
    
    /// Display name for the product
    public var displayName: String {
        switch self {
        case .personalMonthly: return "T1Pal Personal"
        case .legacyPremiumMonthly, .legacyPremiumYearly: return "Premium (Legacy)"
        case .legacyFamilyMonthly, .legacyFamilyYearly: return "Family (Legacy)"
        case .legacyFounderLifetime: return "Founder (Legacy)"
        }
    }
    
    /// Whether this is a subscription (vs one-time purchase)
    public var isSubscription: Bool {
        self != .legacyFounderLifetime
    }
    
    /// Tier level unlocked by this product
    public var tierLevel: SubscriptionTier {
        switch self {
        case .personalMonthly:
            return .personal
        case .legacyPremiumMonthly, .legacyPremiumYearly,
             .legacyFamilyMonthly, .legacyFamilyYearly,
             .legacyFounderLifetime:
            return .personal  // All legacy products map to personal
        }
    }
    
    /// Whether this is a legacy product
    public var isLegacy: Bool {
        switch self {
        case .personalMonthly: return false
        default: return true
        }
    }
    
    /// Active products available for new purchases
    public static var activeProducts: [T1PalProduct] {
        [.personalMonthly]
    }
}

/// Subscription tier levels
/// Simplified model: Free (BYONS, all features) vs Personal (hosted NS)
/// All app features are available at free tier. Personal adds managed hosting.
public enum SubscriptionTier: Int, Comparable, Sendable, Codable {
    case free = 0       // BYONS - all features work with user's own Nightscout
    case personal = 1   // T1Pal Hosted Nightscout ($11.99/mo)
    
    // Legacy tiers for backward compatibility (decode only)
    // These all map to personal internally
    
    public static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    /// Features available at this tier
    /// Key change: FREE tier gets ALL features except managed_hosting
    public var features: Set<String> {
        let allFeatures: Set<String> = [
            "demo_mode", "basic_dashboard", "settings",
            "cgm_connection", "glucose_alerts", "aid_mode",
            "nightscout_sync", "widgets", "watch_app",
            "family_sharing", "multi_user", "caregiver_alerts",
            "agp_reports", "custom_alarms", "watch_complications",
            "analytics", "remote_control", "beta_access"
        ]
        
        switch self {
        case .free:
            // Free tier gets ALL features (BYONS model)
            return allFeatures
        case .personal:
            // Personal tier gets all features + managed hosting
            return allFeatures.union(["managed_hosting"])
        }
    }
    
    /// Check if a feature is available at this tier
    public func hasFeature(_ feature: String) -> Bool {
        features.contains(feature)
    }
    
    /// Display name for the tier
    public var displayName: String {
        switch self {
        case .free: return "Free"
        case .personal: return "Personal"
        }
    }
}

// Legacy tier values for Codable compatibility
extension SubscriptionTier {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        
        // Map legacy tier values to new simplified model
        switch rawValue {
        case 0: self = .free
        case 1, 2, 3: self = .personal  // premium, family, founder → personal
        default: self = .free
        }
    }
}

// MARK: - Subscription State

/// Current subscription status
public struct SubscriptionStatus: Sendable, Codable, Equatable {
    /// Current tier level
    public let tier: SubscriptionTier
    
    /// Active product ID (nil if free)
    public let productId: String?
    
    /// Expiration date (nil for lifetime or free)
    public let expiresAt: Date?
    
    /// Whether subscription auto-renews
    public let willRenew: Bool
    
    /// Whether user is in trial period
    public let isTrialPeriod: Bool
    
    /// Whether user is in grace period
    public let isInGracePeriod: Bool
    
    /// Original purchase date
    public let purchaseDate: Date?
    
    /// Last verification date
    public let verifiedAt: Date
    
    public init(
        tier: SubscriptionTier = .free,
        productId: String? = nil,
        expiresAt: Date? = nil,
        willRenew: Bool = false,
        isTrialPeriod: Bool = false,
        isInGracePeriod: Bool = false,
        purchaseDate: Date? = nil,
        verifiedAt: Date = Date()
    ) {
        self.tier = tier
        self.productId = productId
        self.expiresAt = expiresAt
        self.willRenew = willRenew
        self.isTrialPeriod = isTrialPeriod
        self.isInGracePeriod = isInGracePeriod
        self.purchaseDate = purchaseDate
        self.verifiedAt = verifiedAt
    }
    
    /// Free tier default
    public static var free: SubscriptionStatus {
        SubscriptionStatus(tier: .free)
    }
    
    /// Check if subscription is active
    public var isActive: Bool {
        tier != .free
    }
    
    /// Check if subscription is expiring soon (within 7 days)
    public var isExpiringSoon: Bool {
        guard let expires = expiresAt else { return false }
        let daysUntilExpiry = Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0
        return daysUntilExpiry <= 7 && daysUntilExpiry >= 0
    }
}

// MARK: - Purchase Result

/// Result of a purchase attempt
public enum PurchaseResult: Sendable {
    case success(SubscriptionStatus)
    case pending
    case cancelled
    case failed(PurchaseError)
}

/// Purchase errors
public enum PurchaseError: Error, Sendable, LocalizedError {
    case productNotFound
    case purchaseNotAllowed
    case paymentFailed
    case verificationFailed
    case networkError
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Subscription product not found in App Store."
        case .purchaseNotAllowed:
            return "Purchases are not allowed on this device."
        case .paymentFailed:
            return "Payment failed. Please check your payment method."
        case .verificationFailed:
            return "Purchase verification failed. Please try again."
        case .networkError:
            return "Network error during purchase. Please check your connection."
        case .unknown(let message):
            return "Purchase error: \(message)"
        }
    }
}

// MARK: - Subscription Manager Protocol

/// Protocol for subscription management
/// Allows for mock implementation in tests
public protocol SubscriptionManaging: Sendable {
    /// Current subscription status
    var currentStatus: SubscriptionStatus { get async }
    
    /// Available products for purchase
    func availableProducts() async throws -> [ProductInfo]
    
    /// Purchase a product
    func purchase(_ productId: String) async -> PurchaseResult
    
    /// Restore previous purchases
    func restorePurchases() async -> PurchaseResult
    
    /// Check entitlement for a feature
    func hasEntitlement(for feature: String) async -> Bool
}

/// Product information for display
public struct ProductInfo: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    public let price: String
    public let pricePerMonth: String?
    public let isBestValue: Bool
    public let isPopular: Bool
    
    public init(
        id: String,
        displayName: String,
        description: String,
        price: String,
        pricePerMonth: String? = nil,
        isBestValue: Bool = false,
        isPopular: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.price = price
        self.pricePerMonth = pricePerMonth
        self.isBestValue = isBestValue
        self.isPopular = isPopular
    }
}

// MARK: - Mock Implementation

/// Mock subscription manager for testing and demo mode
public actor MockSubscriptionManager: SubscriptionManaging {
    private var status: SubscriptionStatus
    private let products: [ProductInfo]
    
    public init(initialTier: SubscriptionTier = .free) {
        self.status = SubscriptionStatus(tier: initialTier)
        self.products = [
            ProductInfo(
                id: T1PalProduct.personalMonthly.rawValue,
                displayName: "T1Pal Personal",
                description: "Managed Nightscout hosting with unlimited followers",
                price: "$11.99/month",
                isPopular: true
            ),
        ]
    }
    
    public var currentStatus: SubscriptionStatus {
        status
    }
    
    public func availableProducts() async throws -> [ProductInfo] {
        products
    }
    
    public func purchase(_ productId: String) async -> PurchaseResult {
        // Simulate purchase delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        guard let product = T1PalProduct(rawValue: productId) else {
            return .failed(.productNotFound)
        }
        
        let newStatus = SubscriptionStatus(
            tier: product.tierLevel,
            productId: productId,
            expiresAt: product.isSubscription ? Calendar.current.date(byAdding: .month, value: 1, to: Date()) : nil,
            willRenew: product.isSubscription,
            isTrialPeriod: false,
            isInGracePeriod: false,
            purchaseDate: Date(),
            verifiedAt: Date()
        )
        
        status = newStatus
        return .success(newStatus)
    }
    
    public func restorePurchases() async -> PurchaseResult {
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        // In mock, just return current status
        if status.tier == .free {
            return .cancelled
        }
        return .success(status)
    }
    
    public func hasEntitlement(for feature: String) async -> Bool {
        status.tier.hasFeature(feature)
    }
    
    /// Set tier directly (for testing)
    public func setTier(_ tier: SubscriptionTier) {
        status = SubscriptionStatus(tier: tier, verifiedAt: Date())
    }
}

// MARK: - StoreKit 2 Implementation

#if canImport(StoreKit)
import StoreKit

// MARK: - Backend IAP Client

/// Client for T1Pal backend IAP verification
@available(iOS 15.0, macOS 12.0, *)
public actor BackendIAPClient {
    private let baseURL: URL
    private let session: URLSession
    
    /// Shared instance using production URL
    public static let shared = BackendIAPClient(
        baseURL: URL(string: "https://t1pal.com")!
    )
    
    /// Sandbox instance for testing
    public static let sandbox = BackendIAPClient(
        baseURL: URL(string: "https://staging.t1pal.com")!
    )
    
    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    /// Verify a transaction with the backend
    /// - Parameters:
    ///   - signedTransaction: JWS-encoded transaction from StoreKit 2
    ///   - deviceId: iOS identifierForVendor for device binding
    ///   - authToken: Optional bearer token if user is signed in
    /// - Returns: Backend verification response
    public func verifyTransaction(
        signedTransaction: String,
        deviceId: String?,
        authToken: String? = nil
    ) async throws -> BackendVerifyResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/webhooks/apple/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        var body: [String: Any] = ["signedTransaction": signedTransaction]
        if let deviceId = deviceId {
            body["deviceId"] = deviceId
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PurchaseError.networkError
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let verifyResponse = try decoder.decode(BackendVerifyResponse.self, from: data)
        
        if httpResponse.statusCode != 200 {
            throw PurchaseError.verificationFailed
        }
        
        return verifyResponse
    }
    
    /// Link a device to an authenticated account
    /// - Parameters:
    ///   - deviceId: iOS identifierForVendor
    ///   - authToken: Bearer token from Sign in with Apple
    /// - Returns: Backend response with entitlement and optional instance
    public func linkDevice(
        deviceId: String,
        authToken: String
    ) async throws -> BackendVerifyResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/iap/link-device"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        let body = ["deviceId": deviceId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PurchaseError.networkError
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let linkResponse = try decoder.decode(BackendVerifyResponse.self, from: data)
        
        if httpResponse.statusCode != 200 {
            if let errorMsg = linkResponse.error {
                throw PurchaseError.unknown(errorMsg)
            }
            throw PurchaseError.verificationFailed
        }
        
        return linkResponse
    }
}

/// StoreKit 2 subscription manager
@available(iOS 15.0, macOS 12.0, *)
public actor StoreKitSubscriptionManager: SubscriptionManaging {
    private var status: SubscriptionStatus = .free
    private var products: [Product] = []
    private var updateTask: Task<Void, Never>?
    
    /// Backend client for server verification
    private let backendClient: BackendIAPClient
    
    /// Device ID for device binding (identifierForVendor)
    private var deviceId: String?
    
    /// Auth token for authenticated requests
    private var authToken: String?
    
    /// Last backend response (for Nightscout instance info)
    public private(set) var lastBackendResponse: BackendVerifyResponse?
    
    /// Callback when Nightscout instance is provisioned
    /// App layer can wire this to FollowedUserStore.add()
    /// Parameters: (url: String, apiSecret: String)
    public var onInstanceProvisioned: (@Sendable (String, String) async -> Void)?
    
    /// Whether device needs account linking
    public var needsAccountLink: Bool {
        lastBackendResponse?.device?.needsAccountLink ?? false
    }
    
    /// Nightscout instance info from backend
    public var nightscoutInstance: BackendInstanceInfo? {
        lastBackendResponse?.instance
    }
    
    public init(backendClient: BackendIAPClient = .shared) {
        self.backendClient = backendClient
    }
    
    /// Configure device and auth credentials
    public func configure(deviceId: String?, authToken: String? = nil) {
        self.deviceId = deviceId
        self.authToken = authToken
    }
    
    /// Set auth token (e.g., after Sign in with Apple)
    public func setAuthToken(_ token: String?) {
        self.authToken = token
    }
    
    /// Start listening for transaction updates
    public func startListening() {
        guard updateTask == nil else { return }
        updateTask = Task {
            await listenForTransactionUpdates()
        }
    }
    
    deinit {
        updateTask?.cancel()
    }
    
    public var currentStatus: SubscriptionStatus {
        status
    }
    
    public func availableProducts() async throws -> [ProductInfo] {
        let productIds = T1PalProduct.allCases.map { $0.rawValue }
        products = try await Product.products(for: productIds)
        
        return products.map { product in
            let t1palProduct = T1PalProduct(rawValue: product.id)
            
            var pricePerMonth: String? = nil
            if case .autoRenewable = product.type {
                if let subscription = product.subscription {
                    let months = subscription.subscriptionPeriod.value *
                        (subscription.subscriptionPeriod.unit == .year ? 12 : 1)
                    if months > 1 {
                        let monthly = product.price / Decimal(months)
                        pricePerMonth = "\(product.priceFormatStyle.format(monthly))/month"
                    }
                }
            }
            
            return ProductInfo(
                id: product.id,
                displayName: product.displayName,
                description: product.description,
                price: product.displayPrice,
                pricePerMonth: pricePerMonth,
                isBestValue: false,  // Single product, no comparison needed
                isPopular: t1palProduct == .personalMonthly
            )
        }
    }
    
    public func purchase(_ productId: String) async -> PurchaseResult {
        guard let product = products.first(where: { $0.id == productId }) else {
            return .failed(.productNotFound)
        }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerification(verification)
                
                // Get JWS for backend verification from the verification result
                let jwsRepresentation: String
                switch verification {
                case .verified(let signedTransaction):
                    jwsRepresentation = signedTransaction.jsonRepresentation.base64EncodedString()
                case .unverified:
                    jwsRepresentation = ""
                }
                
                // Verify with backend if we have JWS
                if !jwsRepresentation.isEmpty {
                    do {
                        let backendResponse = try await backendClient.verifyTransaction(
                            signedTransaction: jwsRepresentation,
                            deviceId: deviceId,
                            authToken: authToken
                        )
                        lastBackendResponse = backendResponse
                        
                        // Update status from backend entitlement
                        if let entitlement = backendResponse.entitlement {
                            updateStatusFromBackend(entitlement)
                        }
                        
                        // IAP-011: Auto-add provisioned Nightscout instance
                        if let instance = backendResponse.instance {
                            await onInstanceProvisioned?(instance.url, instance.apiSecret)
                        }
                    } catch {
                        // Backend verification failed - log but don't fail the purchase
                        // Local verification already succeeded
                        print("Backend verification failed: \(error)")
                    }
                }
                
                await transaction.finish()
                await updateSubscriptionStatus()
                return .success(status)
                
            case .pending:
                return .pending
                
            case .userCancelled:
                return .cancelled
                
            @unknown default:
                return .failed(.unknown("Unknown purchase result"))
            }
        } catch {
            return .failed(.paymentFailed)
        }
    }
    
    /// Link device to account after Sign in with Apple
    /// Call this after user authenticates to bind their device purchase to their account
    public func linkDeviceToAccount() async throws -> BackendVerifyResponse {
        guard let deviceId = deviceId else {
            throw PurchaseError.unknown("Device ID not configured")
        }
        guard let authToken = authToken else {
            throw PurchaseError.unknown("Auth token not set - sign in first")
        }
        
        let response = try await backendClient.linkDevice(deviceId: deviceId, authToken: authToken)
        lastBackendResponse = response
        
        if let entitlement = response.entitlement {
            updateStatusFromBackend(entitlement)
        }
        
        // IAP-011: Auto-add provisioned Nightscout instance
        if let instance = response.instance {
            await onInstanceProvisioned?(instance.url, instance.apiSecret)
        }
        
        return response
    }
    
    /// Update local status from backend entitlement
    private func updateStatusFromBackend(_ entitlement: BackendEntitlement) {
        let tier: SubscriptionTier
        switch entitlement.plan.lowercased() {
        // All paid plans map to personal tier (hosted NS)
        case "personal", "gold", "founder", "silver", "family", "bronze", "premium":
            tier = .personal
        default: tier = .free
        }
        
        status = SubscriptionStatus(
            tier: tier,
            productId: nil,
            expiresAt: entitlement.expiresAt,
            willRenew: entitlement.willAutoRenew,
            isTrialPeriod: false,
            isInGracePeriod: false,
            purchaseDate: nil,
            verifiedAt: Date()
        )
    }
    
    public func restorePurchases() async -> PurchaseResult {
        await updateSubscriptionStatus()
        
        if status.tier == .free {
            return .cancelled
        }
        return .success(status)
    }
    
    public func hasEntitlement(for feature: String) async -> Bool {
        await updateSubscriptionStatus()
        return status.tier.hasFeature(feature)
    }
    
    // MARK: Private
    
    private func checkVerification<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw PurchaseError.verificationFailed
        }
    }
    
    private func updateSubscriptionStatus() async {
        var highestTier: SubscriptionTier = .free
        var activeProductId: String?
        var expiresAt: Date?
        var willRenew = false
        var purchaseDate: Date?
        
        // Check for active subscriptions
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            if let product = T1PalProduct(rawValue: transaction.productID) {
                if product.tierLevel > highestTier {
                    highestTier = product.tierLevel
                    activeProductId = transaction.productID
                    purchaseDate = transaction.purchaseDate
                    expiresAt = transaction.expirationDate
                    
                    // Check renewal status via subscription info
                    if product.isSubscription {
                        // Active transaction means active subscription
                        willRenew = transaction.revocationDate == nil
                    }
                }
            }
        }
        
        status = SubscriptionStatus(
            tier: highestTier,
            productId: activeProductId,
            expiresAt: expiresAt,
            willRenew: willRenew,
            isTrialPeriod: false,
            isInGracePeriod: false,
            purchaseDate: purchaseDate,
            verifiedAt: Date()
        )
    }
    
    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
            await updateSubscriptionStatus()
        }
    }
}
#endif
