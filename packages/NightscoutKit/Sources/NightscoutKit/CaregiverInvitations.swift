// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CaregiverInvitations.swift
// NightscoutKit
//
// Caregiver invitation and permission management
// Extracted from NightscoutClient.swift (NS-REFACTOR-014)
// Requirements: REQ-ID-008

import Foundation

// MARK: - Caregiver Invitations (ID-008)

/// Permission level for caregivers
/// Requirements: REQ-ID-008
public enum CaregiverPermission: String, Codable, Sendable, CaseIterable {
    case readOnly = "read_only"         // View glucose, treatments
    case readWrite = "read_write"       // View and add treatments
    case fullAccess = "full_access"     // All permissions including settings
    case admin = "admin"                // Full access + invite others
    
    public var canRead: Bool { true }
    
    public var canWrite: Bool {
        switch self {
        case .readOnly: return false
        case .readWrite, .fullAccess, .admin: return true
        }
    }
    
    public var canModifySettings: Bool {
        switch self {
        case .readOnly, .readWrite: return false
        case .fullAccess, .admin: return true
        }
    }
    
    public var canInvite: Bool {
        self == .admin
    }
    
    public var displayName: String {
        switch self {
        case .readOnly: return "View Only"
        case .readWrite: return "View & Add Treatments"
        case .fullAccess: return "Full Access"
        case .admin: return "Administrator"
        }
    }
}

/// Invite status
/// Requirements: REQ-ID-008
public enum InviteStatus: String, Codable, Sendable {
    case pending = "pending"
    case accepted = "accepted"
    case expired = "expired"
    case revoked = "revoked"
}

/// Caregiver invite structure
/// Requirements: REQ-ID-008
public struct CaregiverInvite: Codable, Sendable, Identifiable {
    public let id: UUID
    public let code: String
    public let profileId: UUID
    public let permission: CaregiverPermission
    public let createdAt: Date
    public let expiresAt: Date
    public let maxUses: Int
    public var useCount: Int
    public var status: InviteStatus
    public let createdBy: String?
    public let note: String?
    
    public init(
        id: UUID = UUID(),
        code: String,
        profileId: UUID,
        permission: CaregiverPermission,
        createdAt: Date = Date(),
        expiresAt: Date,
        maxUses: Int = 1,
        useCount: Int = 0,
        status: InviteStatus = .pending,
        createdBy: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.code = code
        self.profileId = profileId
        self.permission = permission
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.maxUses = maxUses
        self.useCount = useCount
        self.status = status
        self.createdBy = createdBy
        self.note = note
    }
    
    /// Check if invite is valid for use
    public var isValid: Bool {
        status == .pending && !isExpired && useCount < maxUses
    }
    
    /// Check if invite has expired
    public var isExpired: Bool {
        Date() >= expiresAt
    }
    
    /// Time remaining until expiration
    public var timeRemaining: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }
    
    /// Generate shareable link
    public func shareableLink(baseUrl: URL = URL(string: "https://t1pal.app")!) -> URL {
        var components = URLComponents(url: baseUrl.appendingPathComponent("invite"), resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url!
    }
    
    /// Create used copy
    public func withUse() -> CaregiverInvite {
        var copy = self
        copy.useCount += 1
        if copy.useCount >= copy.maxUses {
            copy.status = .accepted
        }
        return copy
    }
    
    /// Create revoked copy
    public func revoked() -> CaregiverInvite {
        var copy = self
        copy.status = .revoked
        return copy
    }
}

/// Accepted caregiver relationship
/// Requirements: REQ-ID-008
public struct CaregiverRelationship: Codable, Sendable, Identifiable {
    public let id: UUID
    public let caregiverId: String
    public let caregiverName: String?
    public let profileId: UUID
    public let permission: CaregiverPermission
    public let acceptedAt: Date
    public let inviteId: UUID
    
    public init(
        id: UUID = UUID(),
        caregiverId: String,
        caregiverName: String? = nil,
        profileId: UUID,
        permission: CaregiverPermission,
        acceptedAt: Date = Date(),
        inviteId: UUID
    ) {
        self.id = id
        self.caregiverId = caregiverId
        self.caregiverName = caregiverName
        self.profileId = profileId
        self.permission = permission
        self.acceptedAt = acceptedAt
        self.inviteId = inviteId
    }
}

/// Invite code generator
/// Requirements: REQ-ID-008
public struct InviteCodeGenerator: Sendable {
    
    /// Generate a random invite code
    public static func generateCode(length: Int = 8) -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  // Exclude confusing chars
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    /// Generate a numeric PIN
    public static func generatePin(length: Int = 6) -> String {
        let digits = "0123456789"
        return String((0..<length).map { _ in digits.randomElement()! })
    }
    
    /// Generate a short memorable code
    public static func generateMemorable() -> String {
        let adjectives = ["happy", "sunny", "brave", "calm", "swift"]
        let nouns = ["tiger", "eagle", "river", "mountain", "star"]
        let adj = adjectives.randomElement()!
        let noun = nouns.randomElement()!
        let num = Int.random(in: 10...99)
        return "\(adj)-\(noun)-\(num)"
    }
}

/// Invite manager for creating and managing invites
/// Requirements: REQ-ID-008
public actor InviteManager {
    private var invites: [UUID: CaregiverInvite] = [:]
    private var relationships: [UUID: CaregiverRelationship] = [:]
    private let defaultExpiration: TimeInterval
    
    public init(defaultExpiration: TimeInterval = 7 * 24 * 3600) {  // 7 days
        self.defaultExpiration = defaultExpiration
    }
    
    /// Create a new invite
    public func createInvite(
        for profileId: UUID,
        permission: CaregiverPermission,
        expiresIn: TimeInterval? = nil,
        maxUses: Int = 1,
        createdBy: String? = nil,
        note: String? = nil
    ) -> CaregiverInvite {
        let code = InviteCodeGenerator.generateCode()
        let expiration = expiresIn ?? defaultExpiration
        
        let invite = CaregiverInvite(
            code: code,
            profileId: profileId,
            permission: permission,
            expiresAt: Date().addingTimeInterval(expiration),
            maxUses: maxUses,
            createdBy: createdBy,
            note: note
        )
        
        invites[invite.id] = invite
        return invite
    }
    
    /// Get invite by code
    public func getInvite(byCode code: String) -> CaregiverInvite? {
        invites.values.first { $0.code.uppercased() == code.uppercased() }
    }
    
    /// Get invite by ID
    public func getInvite(byId id: UUID) -> CaregiverInvite? {
        invites[id]
    }
    
    /// Accept an invite
    public func acceptInvite(
        code: String,
        caregiverId: String,
        caregiverName: String? = nil
    ) throws -> CaregiverRelationship {
        guard var invite = getInvite(byCode: code) else {
            throw InviteError.notFound
        }
        
        guard invite.isValid else {
            if invite.isExpired {
                throw InviteError.expired
            } else if invite.useCount >= invite.maxUses {
                throw InviteError.maxUsesReached
            } else {
                throw InviteError.invalid
            }
        }
        
        // Mark invite as used
        invite = invite.withUse()
        invites[invite.id] = invite
        
        // Create relationship
        let relationship = CaregiverRelationship(
            caregiverId: caregiverId,
            caregiverName: caregiverName,
            profileId: invite.profileId,
            permission: invite.permission,
            inviteId: invite.id
        )
        
        relationships[relationship.id] = relationship
        return relationship
    }
    
    /// Revoke an invite
    public func revokeInvite(_ id: UUID) throws {
        guard var invite = invites[id] else {
            throw InviteError.notFound
        }
        
        invite = invite.revoked()
        invites[id] = invite
    }
    
    /// Get all invites for a profile
    public func getInvites(for profileId: UUID) -> [CaregiverInvite] {
        invites.values.filter { $0.profileId == profileId }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get all active invites
    public func getActiveInvites() -> [CaregiverInvite] {
        invites.values.filter { $0.isValid }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get all relationships for a profile
    public func getRelationships(for profileId: UUID) -> [CaregiverRelationship] {
        relationships.values.filter { $0.profileId == profileId }
            .sorted { $0.acceptedAt > $1.acceptedAt }
    }
    
    /// Get all relationships for a caregiver
    public func getRelationships(forCaregiver caregiverId: String) -> [CaregiverRelationship] {
        relationships.values.filter { $0.caregiverId == caregiverId }
            .sorted { $0.acceptedAt > $1.acceptedAt }
    }
    
    /// Remove a relationship
    public func removeRelationship(_ id: UUID) throws {
        guard relationships.removeValue(forKey: id) != nil else {
            throw InviteError.relationshipNotFound
        }
    }
    
    /// Update permission for relationship
    public func updatePermission(_ id: UUID, permission: CaregiverPermission) throws {
        guard let relationship = relationships[id] else {
            throw InviteError.relationshipNotFound
        }
        
        relationships[id] = CaregiverRelationship(
            id: relationship.id,
            caregiverId: relationship.caregiverId,
            caregiverName: relationship.caregiverName,
            profileId: relationship.profileId,
            permission: permission,
            acceptedAt: relationship.acceptedAt,
            inviteId: relationship.inviteId
        )
    }
    
    /// Clean up expired invites
    public func cleanupExpired() {
        let now = Date()
        for (id, invite) in invites {
            if invite.expiresAt < now && invite.status == .pending {
                var expired = invite
                expired.status = .expired
                invites[id] = expired
            }
        }
    }
    
    /// Export invites for persistence
    public func exportInvites() -> [CaregiverInvite] {
        Array(invites.values)
    }
    
    /// Export relationships for persistence
    public func exportRelationships() -> [CaregiverRelationship] {
        Array(relationships.values)
    }
    
    /// Import invites
    public func importInvites(_ invites: [CaregiverInvite]) {
        for invite in invites {
            self.invites[invite.id] = invite
        }
    }
    
    /// Import relationships
    public func importRelationships(_ relationships: [CaregiverRelationship]) {
        for rel in relationships {
            self.relationships[rel.id] = rel
        }
    }
    
    /// Get invite count
    public var inviteCount: Int {
        invites.count
    }
    
    /// Get relationship count
    public var relationshipCount: Int {
        relationships.count
    }
}

/// Invite errors
/// Requirements: REQ-ID-008
public enum InviteError: Error, Sendable {
    case notFound
    case expired
    case invalid
    case maxUsesReached
    case alreadyAccepted
    case relationshipNotFound
    case permissionDenied
}

/// Caregiver access checker
/// Requirements: REQ-ID-008
public struct CaregiverAccessChecker: Sendable {
    private let relationships: [CaregiverRelationship]
    
    public init(relationships: [CaregiverRelationship]) {
        self.relationships = relationships
    }
    
    /// Check if caregiver can access profile
    public func canAccess(caregiverId: String, profileId: UUID) -> Bool {
        relationships.contains {
            $0.caregiverId == caregiverId && $0.profileId == profileId
        }
    }
    
    /// Get permission level for caregiver on profile
    public func getPermission(caregiverId: String, profileId: UUID) -> CaregiverPermission? {
        relationships.first {
            $0.caregiverId == caregiverId && $0.profileId == profileId
        }?.permission
    }
    
    /// Check if caregiver can write to profile
    public func canWrite(caregiverId: String, profileId: UUID) -> Bool {
        getPermission(caregiverId: caregiverId, profileId: profileId)?.canWrite ?? false
    }
    
    /// Check if caregiver can modify settings
    public func canModifySettings(caregiverId: String, profileId: UUID) -> Bool {
        getPermission(caregiverId: caregiverId, profileId: profileId)?.canModifySettings ?? false
    }
    
    /// Check if caregiver can invite others
    public func canInvite(caregiverId: String, profileId: UUID) -> Bool {
        getPermission(caregiverId: caregiverId, profileId: profileId)?.canInvite ?? false
    }
}
