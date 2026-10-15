// SPDX-License-Identifier: MPL-2.0
import Foundation
import KeyhatchCore

// Dependency-free runner for machines with Command Line Tools but no XCTest.
// Preconditions remain enabled in release builds (never use -Ounchecked).
private func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T) {
    precondition(actual == expected, "Expected \(expected), received \(actual)")
}
private func XCTAssertFalse(_ actual: Bool) { precondition(!actual) }

final class PolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let id = UUID()
    var request: AccessRequest {
        AccessRequest(client: "test-client", credential: id, destination: "example.org", operation: "read")
    }
    func ready(uses: Int = 2) -> AccessPolicy {
        var policy = AccessPolicy()
        policy.beginAuthenticatedSession(now: now, monotonic: 100)
        policy.approve(Grant(request: request, expiresAt: now.addingTimeInterval(3600), maximumUses: uses))
        return policy
    }
    func evaluate(_ policy: inout AccessPolicy, offset: TimeInterval = 0,
                  fetched: Date? = nil, request override: AccessRequest? = nil) -> Decision {
        policy.evaluate(override ?? request, fetchedAt: fetched ?? now,
                        now: now.addingTimeInterval(offset), monotonic: 100 + offset)
    }
    func testLockedByDefault() {
        var p = AccessPolicy()
        XCTAssertEqual(evaluate(&p), .locked)
    }
    func testDenyWithoutGrant() {
        var p = AccessPolicy()
        p.beginAuthenticatedSession(now: now, monotonic: 100)
        XCTAssertEqual(evaluate(&p), .noGrant)
    }
    func testLimitedUses() {
        var p = ready()
        XCTAssertEqual(evaluate(&p), .allowed)
        XCTAssertEqual(evaluate(&p), .allowed)
        XCTAssertEqual(evaluate(&p), .exhausted)
        XCTAssertEqual(p.events.count, 3)
    }
    func testZeroUsesCannotRelease() {
        var p = ready(uses: 0)
        XCTAssertEqual(evaluate(&p), .exhausted)
    }
    func testExactScope() {
        let variants = [
            AccessRequest(client: "impostor", credential: id, destination: "example.org", operation: "read"),
            AccessRequest(client: "test-client", credential: UUID(), destination: "example.org", operation: "read"),
            AccessRequest(client: "test-client", credential: id, destination: "example.org.evil", operation: "read"),
            AccessRequest(client: "test-client", credential: id, destination: "example.org", operation: "write")
        ]
        for variant in variants {
            var p = ready()
            XCTAssertEqual(evaluate(&p, request: variant), .noGrant)
            XCTAssertEqual(p.grants[0].uses, 0)
        }
    }
    func testRevoke() {
        var p = ready()
        p.revoke(p.grants[0].id)
        XCTAssertEqual(evaluate(&p), .revoked)
    }
    func testLock() {
        var p = ready()
        p.lock()
        XCTAssertEqual(evaluate(&p), .locked)
    }
    func testSessionBoundary() {
        var p = ready()
        XCTAssertEqual(evaluate(&p, offset: AccessPolicy.sessionDuration), .locked)
    }
    func testGrantBoundary() {
        var p = ready()
        XCTAssertEqual(evaluate(&p, offset: 3600), .expiredGrant)
    }
    func testCacheBoundary() {
        var p = ready()
        XCTAssertEqual(evaluate(&p, fetched: now.addingTimeInterval(-AccessPolicy.cacheDuration)), .expiredCredential)
    }
    func testFutureFetchRejected() {
        var p = ready()
        XCTAssertEqual(evaluate(&p, fetched: now.addingTimeInterval(1)), .expiredCredential)
    }
    func testClockRollback() {
        let p = ready()
        XCTAssertFalse(p.isUnlocked(now: now.addingTimeInterval(-1), monotonic: 101))
        XCTAssertFalse(p.isUnlocked(now: now, monotonic: 99))
    }
    func testMonotonicDeadlineDespiteWallClock() {
        let p = ready()
        XCTAssertFalse(p.isUnlocked(now: now.addingTimeInterval(1),
                                   monotonic: 100 + AccessPolicy.sessionDuration))
    }
    func testRenewDoesNotRenewCredential() {
        var p = ready()
        let future = now.addingTimeInterval(AccessPolicy.cacheDuration)
        p.beginAuthenticatedSession(now: future, monotonic: 100)
        XCTAssertEqual(p.evaluate(request, fetchedAt: now, now: future, monotonic: 100), .expiredCredential)
    }
    func testNewGrantCanFollowRevocation() {
        var p = ready()
        p.revoke(p.grants[0].id)
        p.approve(Grant(request: request, expiresAt: now.addingTimeInterval(30), maximumUses: 1))
        XCTAssertEqual(evaluate(&p), .allowed)
        XCTAssertEqual(p.grants[0].uses, 0)
        XCTAssertEqual(p.grants[1].uses, 1)
    }
    func testUnsupportedEnvelopeRejectedWithoutAuthentication() {
        let json = Data("{\"version\":999,\"keyReference\":\"\",\"ephemeralPublicKey\":\"\",\"salt\":\"\",\"wrappedKey\":\"\",\"ciphertext\":\"\"}".utf8)
        do {
            let envelope = try JSONDecoder().decode(EnclaveEnvelope.self, from: json)
            _ = try EnclaveVault.open(envelope)
            preconditionFailure("Unsupported envelope was accepted")
        } catch EnvelopeError.unsupportedVersion { }
        catch { preconditionFailure("Unexpected error: \(error)") }
    }

    func testReusableApprovalSurvivesSessionRenewal() {
        var p = AccessPolicy()
        p.beginAuthenticatedSession(now: now, monotonic: 100)
        p.approve(Grant(request: request, expiresAt: now.addingTimeInterval(AccessPolicy.cacheDuration)))
        for _ in 0..<100 { XCTAssertEqual(evaluate(&p), .allowed) }
        p.lock()
        XCTAssertEqual(evaluate(&p), .locked)
        p.beginAuthenticatedSession(now: now.addingTimeInterval(10), monotonic: 110)
        XCTAssertEqual(evaluate(&p, offset: 10), .allowed)
        XCTAssertEqual(p.grants.count, 1)
        p.revoke(p.grants[0].id)
        XCTAssertEqual(evaluate(&p, offset: 10), .revoked)
    }

    func testReusableApprovalStillExpires() {
        var p = AccessPolicy()
        p.beginAuthenticatedSession(now: now, monotonic: 100)
        p.approve(Grant(request: request, expiresAt: now.addingTimeInterval(30)))
        XCTAssertEqual(evaluate(&p, offset: 29), .allowed)
        XCTAssertEqual(evaluate(&p, offset: 30), .expiredGrant)
    }
}

@main
enum Checks {
    static func main() {
        let t = PolicyTests()
        let checks: [(String, () -> Void)] = [
            ("locked by default", t.testLockedByDefault),
            ("deny without grant", t.testDenyWithoutGrant),
            ("limited uses", t.testLimitedUses),
            ("zero-use grant", t.testZeroUsesCannotRelease),
            ("exact scope", t.testExactScope),
            ("revoke", t.testRevoke),
            ("lock", t.testLock),
            ("session boundary", t.testSessionBoundary),
            ("grant boundary", t.testGrantBoundary),
            ("cache boundary", t.testCacheBoundary),
            ("future fetch", t.testFutureFetchRejected),
            ("clock rollback", t.testClockRollback),
            ("monotonic deadline", t.testMonotonicDeadlineDespiteWallClock),
            ("renewal preserves retention", t.testRenewDoesNotRenewCredential),
            ("new grant after revocation", t.testNewGrantCanFollowRevocation),
            ("unsupported envelope", t.testUnsupportedEnvelopeRejectedWithoutAuthentication),
            ("reusable approval across sessions", t.testReusableApprovalSurvivesSessionRenewal),
            ("reusable approval expires", t.testReusableApprovalStillExpires)
        ]
        for (name, check) in checks { check(); print("PASS: \(name)") }
        print("\(checks.count) checks passed; no credentials or biometric prompts used.")
        runCredentialChecks()
    }
}
