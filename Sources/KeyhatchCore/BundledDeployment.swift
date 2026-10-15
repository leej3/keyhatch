// SPDX-License-Identifier: MPL-2.0
import Darwin
import Foundation
import Security

public struct BundledConfiguration {
    public let deployment: LocalDeployment
    public let distribution: String
    public let applicationURL: URL?
}

/// Resolves trust from the sealed containing application. Standalone ad hoc
/// pilot builds retain their legacy deployment file, never as a bundle fallback.
public enum BundledDeployment {
    private static let validationFlags = SecCSFlags(rawValue:
        kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)

    private struct Identity {
        let running: SecCode
        let executable: URL
        let info: [String: Any]
    }

    public static func current() throws -> LocalDeployment { try resolve().deployment }

    public static func resolve() throws -> BundledConfiguration {
        let own = try identity()
        guard let app = try enclosingApplication(own.executable) else {
            // A production client copied out of its app must not accept mutable
            // deployment data instead of its publisher's sealed configuration.
            guard isAdHoc(own.info) else {
                throw IPCError.untrustedPeer
            }
            let deployment = try legacy(executable: own.executable)
            guard deployment.clientHash == (try hash(own.info)) else { throw IPCError.untrustedPeer }
            return BundledConfiguration(deployment: deployment,
                                        distribution: "legacy", applicationURL: nil)
        }
        return try validate(app: app, own: own, isBroker: false)
    }

    /// Called by the broker before starting its listener. Approval remains bound
    /// to the actual client build, including Apple's App Store re-signing.
    public static func brokerClientHash() throws -> String {
        let own = try identity()
        guard let app = try enclosingApplication(own.executable) else { throw IPCError.unsafePath }
        return try validate(app: app, own: own, isBroker: true).deployment.clientHash
    }

    private static func identity() throws -> Identity {
        var running: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &running) == errSecSuccess, let running,
              SecCodeCheckValidity(running, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess
        else { throw IPCError.untrustedPeer }
        var ownStatic: SecStaticCode?
        guard SecCodeCopyStaticCode(running, SecCSFlags(), &ownStatic) == errSecSuccess,
              let ownStatic else { throw IPCError.untrustedPeer }
        let info = try signingInformation(ownStatic)
        guard let url = info[kSecCodeInfoMainExecutable as String] as? URL else { throw IPCError.unsafePath }
        return Identity(running: running, executable: url.resolvingSymlinksInPath(), info: info)
    }

    private static func validate(app: URL, own: Identity, isBroker: Bool) throws -> BundledConfiguration {
        let appCode = try staticCode(app)
        let appInfo = try signingInformation(appCode)
        guard let plist = appInfo[kSecCodeInfoPList as String] as? [String: Any],
              let distribution = plist["KeyhatchDistribution"] as? String,
              ["development", "direct", "app-store"].contains(distribution),
              let serverURL = appInfo[kSecCodeInfoMainExecutable as String] as? URL else {
            throw IPCError.untrustedPeer
        }
        let relativeClient = distribution == "app-store"
            ? "Contents/Helpers/KeyhatchClient.app/Contents/MacOS/keyhatch" : "Contents/MacOS/KeyhatchCLI"
        let clientURL = app.appendingPathComponent(relativeClient)
        // Reject links that escape the sealed application layout.
        guard clientURL.resolvingSymlinksInPath() == clientURL,
              own.executable == (isBroker ? serverURL.resolvingSymlinksInPath() : clientURL) else {
            throw IPCError.unsafePath
        }
        let clientCode = try staticCode(clientURL)
        let clientInfo = try signingInformation(clientCode)
        let serverHash = try hash(appInfo), clientHash = try hash(clientInfo)
        let expectedHash = isBroker ? serverHash : clientHash
        guard try hash(own.info) == expectedHash else { throw IPCError.untrustedPeer }
        let ownPin = try requirement("cdhash H\"\(expectedHash)\"")
        guard SecCodeCheckValidity(own.running, SecCSFlags(rawValue: kSecCSStrictValidate), ownPin) == errSecSuccess
        else { throw IPCError.untrustedPeer }
        if distribution != "development" {
            guard let team = own.info[kSecCodeInfoTeamIdentifier as String] as? String,
                  team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil,
                  appInfo[kSecCodeInfoTeamIdentifier as String] as? String == team,
                  clientInfo[kSecCodeInfoTeamIdentifier as String] as? String == team,
                  plist["KeyhatchTeamIdentifier"] as? String == team,
                  let bundleID = plist["CFBundleIdentifier"] as? String,
                  appInfo[kSecCodeInfoIdentifier as String] as? String == bundleID,
                  clientInfo[kSecCodeInfoIdentifier as String] as? String == bundleID + ".client"
            else { throw IPCError.untrustedPeer }
            // TeamIdentifier alone does not prove an Apple-issued certificate.
            // The Store may re-sign app/helper code, so do not pin a pre-upload
            // CDHash or require a Developer ID identity for the Store variant.
            var publisherSource = "anchor apple generic"
            if distribution == "direct" {
                publisherSource += " and certificate leaf[subject.OU] = \"\(team)\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            }
            let publisher = try requirement(publisherSource)
            guard SecStaticCodeCheckValidity(appCode, validationFlags, publisher) == errSecSuccess,
                  SecStaticCodeCheckValidity(clientCode, validationFlags, publisher) == errSecSuccess,
                  SecCodeCheckValidity(own.running, SecCSFlags(rawValue: kSecCSStrictValidate), publisher) == errSecSuccess
            else { throw IPCError.untrustedPeer }
        } else {
            // Explicit development mode cannot downgrade a production client.
            guard isAdHoc(own.info), isAdHoc(appInfo), isAdHoc(clientInfo) else { throw IPCError.untrustedPeer }
        }
        return BundledConfiguration(deployment: LocalDeployment(serverHash: serverHash,
            clientHash: clientHash, appPath: app.path), distribution: distribution, applicationURL: app)
    }

    /// The outermost application owns the configuration, including a nested
    /// Store helper app. Any malformed application ancestry fails closed.
    public static func enclosingApplication(_ executable: URL) throws -> URL? {
        var ancestor = executable.deletingLastPathComponent()
        var result: URL?
        while ancestor.path != "/" {
            if ancestor.pathExtension.lowercased() == "app" { result = ancestor }
            ancestor.deleteLastPathComponent()
        }
        if let result {
            let direct = result.appendingPathComponent("Contents/MacOS", isDirectory: true)
            let helper = result.appendingPathComponent("Contents/Helpers/KeyhatchClient.app/Contents/MacOS",
                                                      isDirectory: true)
            guard [direct, helper].contains(executable.deletingLastPathComponent()) else { throw IPCError.unsafePath }
        }
        return result
    }

    public static func legacy(executable: URL) throws -> LocalDeployment {
        let path = executable.deletingLastPathComponent().appendingPathComponent("deployment.json")
        let fd = Darwin.open(path.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw IPCError.unsafePath }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= 8192 else { throw IPCError.unsafePath }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var data = Data()
        while let part = try handle.read(upToCount: 8193 - data.count), !part.isEmpty {
            data.append(part)
            guard data.count <= 8192 else { throw IPCError.unsafePath }
        }
        let result = try JSONDecoder().decode(LocalDeployment.self, from: data)
        guard LocalIPC.validHash(result.serverHash), LocalIPC.validHash(result.clientHash) else {
            throw IPCError.untrustedPeer
        }
        return result
    }

    private static func staticCode(_ path: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(path as CFURL, SecCSFlags(), &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, validationFlags, nil) == errSecSuccess else {
            throw IPCError.untrustedPeer
        }
        return code
    }

    private static func signingInformation(_ code: SecStaticCode) throws -> [String: Any] {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let result = info as? [String: Any] else { throw IPCError.untrustedPeer }
        return result
    }

    private static func hash(_ info: [String: Any]) throws -> String {
        guard let bytes = info[kSecCodeInfoUnique as String] as? Data else { throw IPCError.untrustedPeer }
        let result = bytes.map { String(format: "%02x", $0) }.joined()
        guard LocalIPC.validHash(result) else { throw IPCError.untrustedPeer }
        return result
    }

    private static func isAdHoc(_ info: [String: Any]) -> Bool {
        guard let flags = info[kSecCodeInfoFlags as String] as? NSNumber else { return false }
        return flags.uint32Value & SecCodeSignatureFlags.adhoc.rawValue != 0 &&
            info[kSecCodeInfoTeamIdentifier as String] == nil
    }

    private static func requirement(_ source: String) throws -> SecRequirement {
        var result: SecRequirement?
        guard SecRequirementCreateWithString(source as CFString, SecCSFlags(), &result) == errSecSuccess,
              let result else { throw IPCError.untrustedPeer }
        return result
    }
}
