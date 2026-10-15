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
}
