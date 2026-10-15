// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Darwin
import Foundation

public enum CredentialError: Error { case invalidRecord, unsafeFile, storage, expired, locked }

public struct CredentialRecord: Codable {
    public let host: String
    public let account: String
    public let secret: String
    /// Unix timestamps preserve source expiry rather than restarting retention on import.
    public let fetchedAt: TimeInterval
    public let expiresAt: TimeInterval
    public var history: [CredentialHistory] = []

    public func validate(now: Date = Date()) throws {
        guard !host.isEmpty, host.count <= 253, host == host.lowercased(),
              host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                  !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
              }),
              !account.isEmpty, account.utf8.count <= 1024,
              !account.contains(":"), !account.contains(where: { $0.isNewline }),
              !secret.isEmpty, secret.utf8.count <= 65536,
              !account.utf8.contains(0), !secret.utf8.contains(0),
              fetchedAt.isFinite, expiresAt.isFinite,
              fetchedAt <= now.timeIntervalSince1970, expiresAt > fetchedAt,
              expiresAt - fetchedAt <= AccessPolicy.cacheDuration,
              history.count <= 200 else { throw CredentialError.invalidRecord }
        guard now.timeIntervalSince1970 < expiresAt else { throw CredentialError.expired }
    }

    public mutating func record(_ action: String, now: Date = Date()) {
        history.append(CredentialHistory(date: now, action: action))
        history = Array(history.suffix(200))
    }
}

public struct CredentialHistory: Codable, Identifiable {
    public var id = UUID()
    public let date: Date
    public let action: String
}

/// Owner-only encrypted files. Same-UID malicious processes are not isolated.
/// A directory fd and relative operations avoid following final-component links.
public final class CredentialFiles {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/keyhatch", isDirectory: true)
    }
    public let root: URL
    private let directory: Int32
    public init(root: URL = CredentialFiles.defaultRoot) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        directory = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw CredentialError.unsafeFile }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0 else {
            close(directory); throw CredentialError.unsafeFile
        }
    }
    deinit { close(directory) }

    private func validateName(_ name: String) throws {
        guard name.hasSuffix(".keyhatch"), UUID(uuidString: String(name.dropLast(9))) != nil else {
            throw CredentialError.unsafeFile
        }
    }
    public func list() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".keyhatch") }.sorted()
    }
    public func read(_ name: String) throws -> EnclaveEnvelope {
        try validateName(name)
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw CredentialError.unsafeFile }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_nlink == 1, info.st_size > 0, info.st_size <= 1_048_576 else {
            throw CredentialError.unsafeFile
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        guard let data = try handle.read(upToCount: 1_048_577), data.count <= 1_048_576 else {
            throw CredentialError.unsafeFile
        }
        return try JSONDecoder().decode(EnclaveEnvelope.self, from: data)
    }

    public func create(_ envelope: EnclaveEnvelope) throws -> String {
        let name = UUID().uuidString + ".keyhatch"
        try write(envelope, name: name, replacing: false)
        return name
    }

    public func update(_ envelope: EnclaveEnvelope, name: String) throws {
        _ = try read(name)
        try write(envelope, name: name, replacing: true)
    }

    private func write(_ envelope: EnclaveEnvelope, name: String, replacing: Bool) throws {
        try validateName(name)
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= 1_048_576 else { throw CredentialError.storage }
        let temp = ".pending-" + UUID().uuidString
        let fd = openat(directory, temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CredentialError.storage }
        defer { close(fd); unlinkat(directory, temp, 0) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
        guard fsync(fd) == 0 else { throw CredentialError.storage }
        if replacing {
            guard renameat(directory, temp, directory, name) == 0 else { throw CredentialError.storage }
        } else {
            // linkat is no-clobber: an existing destination is never overwritten.
            guard linkat(directory, temp, directory, name, 0) == 0 else { throw CredentialError.storage }
            guard unlinkat(directory, temp, 0) == 0 else { throw CredentialError.storage }
        }
        guard fsync(directory) == 0 else { throw CredentialError.storage }
    }

    /// Hold across a session to prevent two cooperating app instances losing audit writes.
    public func lockFile(_ name: String) throws -> Int32 {
        try validateName(name)
        let fd = openat(directory, name + ".lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw CredentialError.unsafeFile }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_nlink == 1,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); throw CredentialError.unsafeFile
        }
        return fd
    }
}

public func disableCoreDumps() throws {
    var limit = rlimit(rlim_cur: 0, rlim_max: 0)
    guard setrlimit(RLIMIT_CORE, &limit) == 0 else { throw CredentialError.storage }
}
