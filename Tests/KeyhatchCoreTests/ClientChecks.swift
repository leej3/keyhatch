// SPDX-License-Identifier: MPL-2.0
import Foundation
import KeyhatchCore

func runClientChecks() {
    let good = "protocol=https\nhost=example.org\nusername=test\n\n"
    precondition(ClientProtocol.matchesGit(good, host: "example.org", account: "test"))
    for bad in [good.replacingOccurrences(of: "https", with: "http"),
                good.replacingOccurrences(of: "example.org", with: "example.org.evil"),
                good.replacingOccurrences(of: "username=test", with: "username=other"),
                "protocol=https\nhost=example.org\nhost=evil.org\n\n",
                good.replacingOccurrences(of: "example.org", with: "example.org:444"),
                "protocol=https\nhost=example.org\nusername=test\0\n\n"] {
        precondition(!ClientProtocol.matchesGit(bad, host: "example.org", account: "test"))
    }
    precondition(!ClientProtocol.matchesGit(String(repeating: "a", count: 16385), host: "example.org", account: "test"))
    for name in ["PATH", "HOME", "DYLD_INSERT_LIBRARIES", "BASH_ENV", "BAD-NAME", "1TOKEN"] {
        precondition(!ClientProtocol.validEnvironmentName(name))
    }
    precondition(ClientProtocol.validEnvironmentName("SERVICE_TOKEN"))
    let now = Date(timeIntervalSince1970: 1000)
    let hash = String(repeating: "a", count: 40)
    let grant = BrokerApproval(clientHash: hash, expiresAt: 2000)
    precondition(grant.permits(clientHash: hash, credentialExpiry: 2000, now: now))
    precondition(!grant.permits(clientHash: String(repeating: "b", count: 40), credentialExpiry: 2000, now: now))
    precondition(!grant.permits(clientHash: hash, credentialExpiry: 1999, now: now))
    precondition(!grant.permits(clientHash: hash, credentialExpiry: 2000, now: Date(timeIntervalSince1970: 2000)))
    print("PASS: Git scope/duplicates/input limits, environment names, pinned grant expiry/build identity")
}
