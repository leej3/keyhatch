// SPDX-License-Identifier: MPL-2.0
import Darwin
import Foundation
import KeyhatchCore

func runBundledDeploymentChecks() {
    do {
        let app = URL(fileURLWithPath: "/tmp/Keyhatch.app", isDirectory: true)
        let direct = try BundledDeployment.enclosingApplication(app.appendingPathComponent("Contents/MacOS/keyhatch"))
        let nested = try BundledDeployment.enclosingApplication(
            app.appendingPathComponent("Contents/Helpers/KeyhatchClient.app/Contents/MacOS/keyhatch"))
        let standalone = try BundledDeployment.enclosingApplication(URL(fileURLWithPath: "/tmp/keyhatch"))
        precondition(direct == app && nested == app && standalone == nil)
        func rejected(_ operation: () throws -> Void) {
            do { try operation(); preconditionFailure("Untrusted deployment accepted") } catch {}
        }
        rejected { _ = try BundledDeployment.enclosingApplication(
            app.appendingPathComponent("Contents/Resources/keyhatch")) }
        rejected { _ = try BundledDeployment.enclosingApplication(
            app.appendingPathComponent("Contents/Helpers/Other.app/Contents/MacOS/keyhatch")) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("keyhatch")
        let path = root.appendingPathComponent("deployment.json")
        let pin = String(repeating: "a", count: 40)
        let data = try JSONEncoder().encode(LocalDeployment(serverHash: pin, clientHash: pin, appPath: "/tmp/Test.app"))
        try data.write(to: path)
        precondition(chmod(path.path, 0o600) == 0)
        let deployment = try BundledDeployment.legacy(executable: executable)
        precondition(deployment.serverHash == pin && deployment.clientHash == pin)
        precondition(chmod(path.path, 0o644) == 0)
        rejected { _ = try BundledDeployment.legacy(executable: executable) }
        precondition(chmod(path.path, 0o600) == 0)
        let hardLink = root.appendingPathComponent("second-link")
        try FileManager.default.linkItem(at: path, to: hardLink)
        rejected { _ = try BundledDeployment.legacy(executable: executable) }
        try FileManager.default.removeItem(at: hardLink)
        try Data(repeating: 32, count: 8193).write(to: path)
        rejected { _ = try BundledDeployment.legacy(executable: executable) }
        try FileManager.default.removeItem(at: path)
        let target = root.appendingPathComponent("target.json")
        try data.write(to: target)
        precondition(chmod(target.path, 0o600) == 0)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
        rejected { _ = try BundledDeployment.legacy(executable: executable) }
        try FileManager.default.removeItem(at: path)
        precondition(mkfifo(path.path, 0o600) == 0)
        rejected { _ = try BundledDeployment.legacy(executable: executable) }
        print("PASS: enclosing app boundaries; legacy trust file permissions, links, size and FIFO rejection")
    } catch { preconditionFailure("Deployment checks failed: \(error)") }
}
