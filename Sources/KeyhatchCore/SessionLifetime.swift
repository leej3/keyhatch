// SPDX-License-Identifier: MPL-2.0
import Foundation

/// An authenticated session cannot outlive its original remaining source lifetime.
/// Inject both clocks for deterministic checks; do not persist continuous timestamps.
public struct SessionLifetime {
    private let started: Date
    private let continuousStart: TimeInterval
    private let duration: TimeInterval
    private static let clockOrigin = ContinuousClock.now

    public init?(now: Date, continuous: TimeInterval, credentialExpiry: TimeInterval) {
        let wall = now.timeIntervalSince1970
        let remaining = credentialExpiry - wall
        guard wall.isFinite, continuous.isFinite, continuous >= 0,
              credentialExpiry.isFinite, remaining.isFinite, remaining > 0 else { return nil }
        started = now
        continuousStart = continuous
        duration = min(remaining, AccessPolicy.sessionDuration)
    }

    /// Swift ContinuousClock advances during system sleep, unlike an uptime clock.
    /// https://developer.apple.com/documentation/swift/continuousclock
    public static func continuousTime() -> TimeInterval {
        let origin = clockOrigin
        let elapsed = origin.duration(to: .now).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }

    /// Use this time for approval expiry too, including approvals shorter than the
    /// source lifetime. A backward wall adjustment cannot add time to either TTL.
    /// Invalid clocks, rollback before unlock, and exact expiry all fail closed.
    public func authorizationTime(now: Date, continuous: TimeInterval) -> Date? {
        let wallElapsed = now.timeIntervalSince(started)
        let continuousElapsed = continuous - continuousStart
        guard now.timeIntervalSince1970.isFinite, continuous.isFinite,
              wallElapsed.isFinite, continuousElapsed.isFinite,
              wallElapsed >= 0, continuousElapsed >= 0,
              wallElapsed < duration, continuousElapsed < duration else { return nil }
        return started.addingTimeInterval(max(wallElapsed, continuousElapsed))
    }
}
