// SPDX-License-Identifier: MPL-2.0
import Foundation
import Darwin
import KeyhatchCore

func runDeploymentStorageChecks() {
    func rejects(_ operation: () throws -> Void) {
        do { try operation(); preconditionFailure("Unsafe deployment/storage operation accepted") }
        catch { }
    }
    do {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyhatch-deployment-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(channel: Any? = nil) throws -> Bundle {
            let path = root.appendingPathComponent(UUID().uuidString + ".bundle")
            let contents = path.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = ["CFBundleIdentifier": "local.keyhatch.synthetic." + UUID().uuidString]
            info["KeyhatchDistribution"] = channel
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            guard let result = Bundle(url: path) else { throw CredentialError.storage }
            return result
        }
        for channel in [nil, "development", "direct"] as [String?] {
            let fixture = try bundle(channel: channel)
            let credentials = try DeploymentPaths.credentialRoot(bundle: fixture)
            let ipc = try DeploymentPaths.ipcRoot(bundle: fixture)
            precondition(credentials == CredentialFiles.defaultRoot && ipc == credentials)
        }
        for channel: Any in ["typo", "", NSNumber(value: 1)] {
            let fixture = try bundle(channel: channel)
            rejects { _ = try DeploymentPaths.credentialRoot(bundle: fixture) }
            rejects { _ = try DeploymentPaths.ipcRoot(bundle: fixture) }
        }
        // The dependency-free runner is deliberately not sandboxed. A claimed
        // Store channel must fail before consulting or creating any real container.
        let store = try bundle(channel: "app-store")
        rejects { _ = try DeploymentPaths.credentialRoot(bundle: store) }
        rejects { _ = try DeploymentPaths.ipcRoot(bundle: store) }
        print("PASS: deployment configuration rejects invalid channels and unsandboxed Store fallback")

        let filesRoot = root.appendingPathComponent("records")
        let files = try CredentialFiles(root: filesRoot)
        let synthetic = try JSONDecoder().decode(EnclaveEnvelope.self, from: Data(
            "{\"version\":1,\"keyReference\":\"\",\"ephemeralPublicKey\":\"\",\"salt\":\"\",\"wrappedKey\":\"\",\"ciphertext\":\"\"}".utf8))
        let name = try files.create(synthetic)
        let held = try files.lockFile(name)
        rejects { try files.remove(name) }
        _ = try files.read(name)
        close(held)
        let lockPath = filesRoot.appendingPathComponent(name + ".lock").path
        var before = stat()
        precondition(lstat(lockPath, &before) == 0)
        try files.remove(name)
        var after = stat()
        precondition(lstat(lockPath, &after) == 0 && before.st_ino == after.st_ino)
        rejects { _ = try files.read(name) }
        rejects { try files.remove("../outside.keyhatch") }
        let target = try files.create(synthetic)
        let linkName = UUID().uuidString + ".keyhatch"
        let linkPath = filesRoot.appendingPathComponent(linkName)
        try FileManager.default.createSymbolicLink(at: linkPath,
            withDestinationURL: filesRoot.appendingPathComponent(target))
        rejects { try files.remove(linkName) }
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: linkPath.path)
        precondition(destination == filesRoot.appendingPathComponent(target).path)
        _ = try files.read(target)
        let malformed = UUID().uuidString + ".keyhatch"
        let malformedPath = filesRoot.appendingPathComponent(malformed)
        try Data("not an envelope".utf8).write(to: malformedPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: malformedPath.path)
        rejects { try files.remove(malformed) }
        precondition(FileManager.default.fileExists(atPath: malformedPath.path))
        print("PASS: deletion rejects active, malformed and linked records; retains lock inode")
    } catch { preconditionFailure("Deployment/storage checks failed: \(error)") }
}
