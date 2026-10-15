// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Caller identity MUST come from verified IPC credentials, never request JSON.
/// The prototype supplies synthetic identities; it does not authenticate clients.
public struct AccessRequest: Equatable {
    public let client: String
    public let credential: UUID
    public let destination: String
    public let operation: String

    public init(client: String, credential: UUID, destination: String, operation: String) {
        self.client = client
        self.credential = credential
        self.destination = destination
        self.operation = operation
    }
}

public struct Grant: Identifiable {
    public let id: UUID
    public let request: AccessRequest
    public let expiresAt: Date
    /// nil permits repeated retrieval until expiry or revocation.
    public let maximumUses: Int?
    public private(set) var uses = 0
    public private(set) var revoked = false

    public init(id: UUID = UUID(), request: AccessRequest, expiresAt: Date, maximumUses: Int? = nil) {
        self.id = id
        self.request = request
        self.expiresAt = expiresAt
        self.maximumUses = maximumUses
    }

    mutating func consume() { uses += 1 }
    mutating func revoke() { revoked = true }
}

public enum Decision: String, Equatable {
    case allowed, locked, expiredCredential, noGrant, expiredGrant, revoked, exhausted
}

public struct AuditEvent: Identifiable {
    public let id = UUID()
    public let date: Date
    public let client: String
    public let credential: UUID
    public let decision: Decision
    // Intentionally no secret, request body, arbitrary error text, or URL query.
}

/// Pure policy state. Serialized invocation and trusted clocks are the host's job.
/// Returning allowed reserves one use; the host must recheck lifetime before release.
public struct AccessPolicy {
    public static let sessionDuration: TimeInterval = 5 * 60 * 60
    public static let cacheDuration: TimeInterval = 3 * 24 * 60 * 60
    private var started: Date?
    private var monotonicStart: TimeInterval?
    public private(set) var grants: [Grant] = []
    public private(set) var events: [AuditEvent] = []

    public init() {}

    /// Call ONLY after successful native authentication, not at an agent's request.
    public mutating func beginAuthenticatedSession(now: Date, monotonic: TimeInterval) {
        started = now
        monotonicStart = monotonic
    }

    public mutating func lock() { started = nil; monotonicStart = nil }
    public mutating func approve(_ grant: Grant) { grants.append(grant) }
    public mutating func revoke(_ id: UUID) {
        guard let i = grants.firstIndex(where: { $0.id == id }) else { return }
        grants[i].revoke()
    }

    public func isUnlocked(now: Date, monotonic: TimeInterval) -> Bool {
        guard let started, let monotonicStart else { return false }
        let wallElapsed = now.timeIntervalSince(started)
        let elapsed = monotonic - monotonicStart
        return wallElapsed >= 0 && wallElapsed < Self.sessionDuration &&
            elapsed >= 0 && elapsed < Self.sessionDuration
    }

    public mutating func evaluate(_ request: AccessRequest, fetchedAt: Date,
                                 now: Date, monotonic: TimeInterval) -> Decision {
        let decision: Decision
        if !isUnlocked(now: now, monotonic: monotonic) {
            decision = .locked
        } else if now < fetchedAt || now.timeIntervalSince(fetchedAt) >= Self.cacheDuration {
            decision = .expiredCredential
        } else if let i = grants.firstIndex(where: {
            $0.request == request && !$0.revoked && now < $0.expiresAt &&
                $0.hasRemainingUses
        }) {
            grants[i].consume()
            decision = .allowed
        } else if let matching = grants.last(where: { $0.request == request }) {
            if matching.revoked { decision = .revoked }
            else if now >= matching.expiresAt { decision = .expiredGrant }
            else { decision = .exhausted }
        } else {
            decision = .noGrant
        }
        events.append(AuditEvent(date: now, client: request.client,
                                 credential: request.credential, decision: decision))
        return decision
    }
}

private extension Grant {
    var hasRemainingUses: Bool { maximumUses.map { uses < $0 } ?? true }
}
