// SPDX-License-Identifier: MPL-2.0
import Foundation
import KeyhatchCore

func runSessionLifetimeChecks() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let continuous: TimeInterval = 100
    func lifetime(_ remaining: TimeInterval) -> SessionLifetime {
        SessionLifetime(now: start, continuous: continuous,
                        credentialExpiry: start.timeIntervalSince1970 + remaining)!
    }
    func time(_ session: SessionLifetime, wall: TimeInterval,
              elapsed: TimeInterval) -> Date? {
        session.authorizationTime(now: start.addingTimeInterval(wall),
                                  continuous: continuous + elapsed)
    }

    let short = lifetime(60)
    precondition(time(short, wall: 0, elapsed: 0) == start)
    precondition(time(short, wall: 59, elapsed: 59) == start.addingTimeInterval(59))
    precondition(time(short, wall: 60, elapsed: 59) == nil)
    precondition(time(short, wall: 59, elapsed: 60) == nil)
    // After 61 real seconds, a wall adjustment leaves the displayed clock only
    // 10 seconds beyond unlock. The source's original 60-second TTL is still over.
    precondition(time(short, wall: 10, elapsed: 61) == nil)
    precondition(time(short, wall: -1, elapsed: 1) == nil)
    precondition(time(short, wall: 1, elapsed: -1) == nil)
    print("PASS: source TTL cannot extend under partial wall rollback; exact expiry fails closed")

    let long = lifetime(AccessPolicy.cacheDuration)
    let cap = AccessPolicy.sessionDuration
    precondition(time(long, wall: cap - 1, elapsed: cap - 1) != nil)
    precondition(time(long, wall: cap, elapsed: 1) == nil)
    precondition(time(long, wall: 1, elapsed: cap) == nil)
    // ContinuousClock includes sleep; injected elapsed represents waking after
    // the session limit even if the wall clock has also moved backward.
    precondition(time(long, wall: 1, elapsed: cap + 3600) == nil)
    print("PASS: five-hour session cap applies independently to wall and continuous clocks")

    let hash = String(repeating: "a", count: 40)
    let approval = BrokerApproval(clientHash: hash,
                                  expiresAt: start.timeIntervalSince1970 + 30)
    func permits(wall: TimeInterval, elapsed: TimeInterval) -> Bool {
        guard let now = time(short, wall: wall, elapsed: elapsed) else { return false }
        return approval.permits(clientHash: hash,
                                credentialExpiry: start.timeIntervalSince1970 + 60, now: now)
    }
    precondition(permits(wall: 29, elapsed: 29))
    precondition(!permits(wall: 10, elapsed: 30))
    precondition(!permits(wall: 30, elapsed: 10))
    precondition(!permits(wall: 10, elapsed: 31))
    print("PASS: shorter broker approval cannot extend under partial wall rollback")

    for invalid in [TimeInterval.nan, .infinity, -.infinity] {
        precondition(SessionLifetime(now: Date(timeIntervalSince1970: invalid),
            continuous: continuous, credentialExpiry: start.timeIntervalSince1970 + 60) == nil)
        precondition(SessionLifetime(now: start, continuous: invalid,
            credentialExpiry: start.timeIntervalSince1970 + 60) == nil)
        precondition(SessionLifetime(now: start, continuous: continuous,
            credentialExpiry: invalid) == nil)
        precondition(short.authorizationTime(now: Date(timeIntervalSince1970: invalid),
            continuous: continuous) == nil)
        precondition(short.authorizationTime(now: start, continuous: invalid) == nil)
    }
    precondition(SessionLifetime(now: start, continuous: -1,
        credentialExpiry: start.timeIntervalSince1970 + 60) == nil)
    precondition(SessionLifetime(now: start, continuous: continuous,
        credentialExpiry: start.timeIntervalSince1970) == nil)
    precondition(SessionLifetime(now: start, continuous: continuous,
        credentialExpiry: start.timeIntervalSince1970 - 1) == nil)
    let first = SessionLifetime.continuousTime()
    let second = SessionLifetime.continuousTime()
    precondition(first.isFinite && first >= 0 && second >= first)
    print("PASS: invalid lifetime inputs fail closed; continuous clock readings are ordered")

    // Simulated sleep and clock corrections must use the later of the two
    // elapsed readings, including when evaluating a shorter persisted approval.
    for wall in [TimeInterval(0), 10, 29, 30, 59, 60, 61] {
        for elapsed in [TimeInterval(0), 10, 29, 30, 59, 60, 61] {
            let observed = time(short, wall: wall, elapsed: elapsed)
            let later = max(wall, elapsed)
            precondition(observed == (later < 60 ? start.addingTimeInterval(later) : nil))
            precondition(permits(wall: wall, elapsed: elapsed) == (later < 30))
        }
    }
    // A request permitted before an encrypted audit write must be denied if
    // either the grant or source/session expires before the release check.
    precondition(permits(wall: 10, elapsed: 29))
    precondition(!permits(wall: 10, elapsed: 30))
    precondition(time(short, wall: 10, elapsed: 59) != nil)
    precondition(time(short, wall: 10, elapsed: 60) == nil)
    print("PASS: simulated sleep/clock matrix and delayed-release expiry checks")

    // A renewed session starts from the source's original absolute expiry,
    // not a fresh cache TTL. Zero represents a new process's clock origin.
    let originalExpiry = start.timeIntervalSince1970 + 60
    let renewedAt = start.addingTimeInterval(59)
    let renewed = SessionLifetime(now: renewedAt, continuous: 0,
                                  credentialExpiry: originalExpiry)!
    precondition(renewed.authorizationTime(now: renewedAt, continuous: 0) == renewedAt)
    precondition(renewed.authorizationTime(now: renewedAt, continuous: 1) == nil)
    precondition(renewed.authorizationTime(now: start.addingTimeInterval(60), continuous: 0) == nil)
    precondition(SessionLifetime(now: start.addingTimeInterval(60), continuous: 0,
                                 credentialExpiry: originalExpiry) == nil)
    // Old process-relative state cannot authorize against a reset clock.
    precondition(short.authorizationTime(now: renewedAt, continuous: 0) == nil)
    print("PASS: session renewal preserves original expiry; old state rejects a reset clock")

    // Persisted approvals are reusable only for the exact approved build. A
    // restart does not imply unlock, and a build change requires new approval.
    let restored = try! JSONDecoder().decode(BrokerApproval.self,
                                            from: JSONEncoder().encode(approval))
    let newHash = String(repeating: "b", count: 40)
    precondition(restored.permits(clientHash: hash,
        credentialExpiry: originalExpiry, now: start))
    precondition(!restored.permits(clientHash: newHash,
        credentialExpiry: originalExpiry, now: start))
    let replacement = BrokerApproval(clientHash: newHash, expiresAt: originalExpiry)
    precondition(replacement.permits(clientHash: newHash,
        credentialExpiry: originalExpiry, now: renewedAt))
    precondition(!replacement.permits(clientHash: hash,
        credentialExpiry: originalExpiry, now: renewedAt))
    precondition(!replacement.permits(clientHash: newHash,
        credentialExpiry: originalExpiry, now: start.addingTimeInterval(60)))

    let request = AccessRequest(client: hash, credential: UUID(),
                                destination: "example.org", operation: "read")
    var restartedPolicy = AccessPolicy()
    restartedPolicy.approve(Grant(request: request,
        expiresAt: Date(timeIntervalSince1970: restored.expiresAt)))
    precondition(restartedPolicy.evaluate(request, fetchedAt: start,
        now: start, monotonic: 0) == .locked)
    restartedPolicy.beginAuthenticatedSession(now: start, monotonic: 0)
    precondition(restartedPolicy.evaluate(request, fetchedAt: start,
        now: start, monotonic: 0) == .allowed)
    restartedPolicy.lock()
    precondition(restartedPolicy.evaluate(request, fetchedAt: start,
        now: start, monotonic: 0) == .locked)
    print("PASS: serialized approval rejects changed builds; restored grants do not unlock a new policy")
}
