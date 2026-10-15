// SPDX-License-Identifier: MPL-2.0
import Foundation
import Security

public enum DeploymentPathError: Error {
    case invalidConfiguration, sandboxRequired, missingApplicationGroup, unavailableContainer
}

/// Distribution settings come from bundle metadata covered by the code signature.
/// Store storage never falls back to the legacy directory or a guessed container.
public enum DeploymentPaths {
    private static func usesAppStoreStorage(_ bundle: Bundle) throws -> Bool {
        guard let value = bundle.object(forInfoDictionaryKey: "KeyhatchDistribution") else {
            return false
        }
        guard let channel = value as? String else { throw DeploymentPathError.invalidConfiguration }
        switch channel {
        case "development", "direct": return false
        case "app-store": return true
        default: throw DeploymentPathError.invalidConfiguration
        }
    }

    private static func entitlement(_ name: String) -> CFTypeRef? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, name as CFString, nil)
    }

    private static func requireSandbox() throws {
        guard let value = entitlement("com.apple.security.app-sandbox"),
              CFGetTypeID(value) == CFBooleanGetTypeID(),
              (value as? Bool) == true else { throw DeploymentPathError.sandboxRequired }
    }

    public static func credentialRoot(bundle: Bundle = .main) throws -> URL {
        guard try usesAppStoreStorage(bundle) else { return CredentialFiles.defaultRoot }
        try requireSandbox()
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else {
            throw DeploymentPathError.unavailableContainer
        }
        return support.appendingPathComponent("Keyhatch", isDirectory: true)
    }

    public static func ipcRoot(bundle: Bundle = .main) throws -> URL {
        guard try usesAppStoreStorage(bundle) else { return CredentialFiles.defaultRoot }
        try requireSandbox()
        guard let group = bundle.object(forInfoDictionaryKey: "KeyhatchAppGroup") as? String,
              !group.isEmpty,
              group.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                                     (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              group.split(separator: ".", omittingEmptySubsequences: false).count >= 2,
              group.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
              let groups = entitlement("com.apple.security.application-groups") as? [String],
              groups.contains(group) else { throw DeploymentPathError.missingApplicationGroup }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group) else {
            throw DeploymentPathError.unavailableContainer
        }
        // Only transport state belongs here. Credential files stay broker-private.
        return container.appendingPathComponent("IPC", isDirectory: true)
    }
}
