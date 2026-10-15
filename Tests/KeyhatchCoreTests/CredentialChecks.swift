// SPDX-License-Identifier: MPL-2.0
import Foundation
import CryptoKit
import Darwin
import KeyhatchCore

func runCredentialChecks() {
    func rejects(_ operation: () throws -> Void) {
        do { try operation(); preconditionFailure("Unsafe input accepted") }
        catch { }
    }
    func envelope() throws -> EnclaveEnvelope {
        try JSONDecoder().decode(EnclaveEnvelope.self, from:
            Data("{\"version\":1,\"keyReference\":\"\",\"ephemeralPublicKey\":\"\",\"salt\":\"\",\"wrappedKey\":\"\",\"ciphertext\":\"\"}".utf8))
    }
    func record(host: String = "example.org", account: String = "test",
                fetched: Double = Date().timeIntervalSince1970 - 60,
                expires: Double = Date().timeIntervalSince1970 + 60) throws -> CredentialRecord {
        let bytes = try JSONSerialization.data(withJSONObject: [
            "host": host, "account": account, "secret": "SYNTHETIC-ONLY",
            "fetchedAt": fetched, "expiresAt": expires, "history": []
        ])
        return try JSONDecoder().decode(CredentialRecord.self, from: bytes)
    }
    do {
        try record().validate()
        for host in ["evil.org/path", "example.org@evil.org", "EXAMPLE.org", "a..b", "-bad.org", "a.org:443"] {
            rejects { try record(host: host).validate() }
        }
        rejects { try record(account: "test:injected").validate() }
        rejects { try record(fetched: Date().timeIntervalSince1970 + 100).validate() }
        rejects { try record(expires: Date().timeIntervalSince1970 - 1).validate() }
        rejects { try record(expires: Date().timeIntervalSince1970 + AccessPolicy.cacheDuration + 100).validate() }
        print("PASS: real-record identity and non-sliding expiry validation")

        let key = SymmetricKey(size: .bits256)
        let plain = Data("SYNTHETIC-ONLY".utf8)
        let sealed = try EnclaveVault.replacingPayload(envelope(), plaintext: plain, using: key)
        let decrypted = try EnclaveVault.decrypt(sealed, using: key)
        precondition(decrypted == plain)
        precondition(sealed.ciphertext.range(of: plain) == nil)
        rejects { _ = try EnclaveVault.decrypt(sealed, using: SymmetricKey(size: .bits256)) }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sealed)) as! [String: Any]
        var altered = sealed.ciphertext
        altered[altered.startIndex] ^= 1
        object["ciphertext"] = altered.base64EncodedString()
        let tampered = try JSONDecoder().decode(EnclaveEnvelope.self, from: JSONSerialization.data(withJSONObject: object))
        rejects { _ = try EnclaveVault.decrypt(tampered, using: key) }
        print("PASS: payload round trip, wrong-key and tamper rejection (software AES test only)")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("keyhatch-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try CredentialFiles(root: root)
        let name = try files.create(sealed)
        let loaded = try files.read(name)
        precondition(loaded.ciphertext == sealed.ciphertext)
        let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(name).path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        let lock = try files.lockFile(name)
        rejects { _ = try files.lockFile(name) }
        close(lock)
        let next = try EnclaveVault.replacingPayload(sealed, plaintext: Data("NEXT".utf8), using: key)
        try files.update(next, name: name)
        let updated = try files.read(name)
        precondition(updated.ciphertext == next.ciphertext)
        rejects { _ = try files.read("../outside.keyhatch") }
        let linkName = UUID().uuidString + ".keyhatch"
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(linkName),
                                                  withDestinationURL: root.appendingPathComponent(name))
        rejects { _ = try files.read(linkName) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent(name).path)
        rejects { _ = try files.read(name) }
        print("PASS: owner-only persistence, atomic update, locks, traversal/symlink/permission rejection")
    } catch { preconditionFailure("Credential checks failed: \(error)") }
}
