// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ClientProtocol {
    /// Refuse duplicate fields and cross-host/cross-account requests before IPC.
    public static func matchesGit(_ input: String, host: String, account: String) -> Bool {
        guard input.utf8.count <= 16384, !input.utf8.contains(0) else { return false }
        var values: [String: String] = [:]
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { break }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, values[String(parts[0])] == nil else { return false }
            values[String(parts[0])] = String(parts[1])
        }
        return values["protocol"] == "https" && values["host"] == host &&
            (values["username"] == nil || values["username"] == account)
    }

    public static func validEnvironmentName(_ name: String) -> Bool {
        guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { return false }
        guard !name.hasPrefix("DYLD_"), !name.hasPrefix("LD_") else { return false }
        return !["PATH", "HOME", "SHELL", "TMPDIR", "PYTHONPATH", "PYTHONHOME", "BASH_ENV", "ENV",
                 "LD_PRELOAD", "LD_LIBRARY_PATH", "DYLD_INSERT_LIBRARIES", "DYLD_LIBRARY_PATH"].contains(name)
    }
}

public struct LocalDeployment: Codable {
    public let serverHash: String
    public let clientHash: String
    public let appPath: String
    public init(serverHash: String, clientHash: String, appPath: String) {
        self.serverHash = serverHash; self.clientHash = clientHash; self.appPath = appPath
    }
}
