// SPDX-License-Identifier: MPL-2.0
import Darwin
import Foundation
import Security

public enum IPCError: Error { case unavailable, unsafePath, untrustedPeer, framing, transport }

public struct BrokerRequest: Codable {
    public let version: Int
    public let operation: String
    public let host: String?
    public let account: String?
    public init(operation: String, host: String? = nil, account: String? = nil) {
        version = 1; self.operation = operation; self.host = host; self.account = account
    }
}

public struct BrokerResponse: Codable {
    public var version = 1
    public var ok: Bool
    public var status: String
    public var secret: String?
    public var expiresAt: Double?
    public init(ok: Bool, status: String, secret: String? = nil, expiresAt: Double? = nil) {
        self.ok = ok; self.status = status; self.secret = secret; self.expiresAt = expiresAt
    }
}

public enum LocalIPC {
    public static let maximumFrame = 262144
    public static var socketPath: String { CredentialFiles.defaultRoot.appendingPathComponent("broker.sock").path }

    public static func validHash(_ value: String) -> Bool {
        value.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Both directions authenticate the kernel-supplied peer audit token, not a PID
    /// supplied in JSON. Exact CDHash pins make updates require explicit redeployment.
    public static func authenticate(_ fd: Int32, expectedHash: String) throws {
        guard validHash(expectedHash) else { throw IPCError.untrustedPeer }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw IPCError.untrustedPeer }
        var token = [UInt8](repeating: 0, count: 32)
        var length = socklen_t(token.count)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0,
              length == 32 else { throw IPCError.untrustedPeer }
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: Data(token)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess,
              let code else { throw IPCError.untrustedPeer }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("cdhash H\"\(expectedHash)\"" as CFString,
            SecCSFlags(), &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement) == errSecSuccess
        else { throw IPCError.untrustedPeer }
    }

    public static func configure(_ fd: Int32) throws {
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw IPCError.transport }
        var yes: Int32 = 1
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) == 0,
              setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0
        else { throw IPCError.transport }
    }

    public static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        guard !path.utf8.contains(0), path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw IPCError.unsafePath
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { target in
            path.withCString { source in _ = memcpy(target, source, path.utf8.count + 1) }
        }
        return address
    }

    public static func readFrame(_ fd: Int32) throws -> Data {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        func readExactly(_ count: Int) throws -> Data {
            var result = Data(count: count)
            try result.withUnsafeMutableBytes { buffer in
                var offset = 0
                while offset < count {
                    guard ProcessInfo.processInfo.systemUptime < deadline else { throw IPCError.transport }
                    let n = recv(fd, buffer.baseAddress!.advanced(by: offset), count - offset, 0)
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw IPCError.transport }
                    offset += n
                }
            }
            return result
        }
        let header = try readExactly(4)
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard count > 0, count <= maximumFrame else { throw IPCError.framing }
        return try readExactly(count)
    }

    public static func writeFrame(_ data: Data, to fd: Int32) throws {
        guard !data.isEmpty, data.count <= maximumFrame else { throw IPCError.framing }
        var count = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &count) { Data($0) }
        frame.append(data)
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        try frame.withUnsafeBytes { buffer in
            var offset = 0
            while offset < frame.count {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw IPCError.transport }
                let n = send(fd, buffer.baseAddress!.advanced(by: offset), frame.count - offset, 0)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw IPCError.transport }
                offset += n
            }
        }
    }

    public static func call(_ request: BrokerRequest, serverHash: String,
                            path: String = socketPath) throws -> BrokerResponse {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw IPCError.unavailable }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.unavailable }
        defer { close(fd) }
        try configure(fd)
        var addr = try address(path)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw IPCError.unavailable }
        try authenticate(fd, expectedHash: serverHash)
        try writeFrame(JSONEncoder().encode(request), to: fd)
        let response = try JSONDecoder().decode(BrokerResponse.self, from: readFrame(fd))
        guard response.version == 1 else { throw IPCError.framing }
        return response
    }
}

/// Serial transport, bounded frames, private socket, fail-closed mutual pinning.
/// Policy and final send run together on MainActor: lock/revoke cannot interleave
/// between the final policy check and send. An already sent secret is not revocable.
public final class BrokerServer: @unchecked Sendable {
    private let listener: Int32
    private let ownership: Int32
    private let path: String
    private let clientHash: String
    private let state = NSLock()
    private var stopped = false

    public init(clientHash: String, root: URL = CredentialFiles.defaultRoot) throws {
        guard LocalIPC.validHash(clientHash) else { throw IPCError.untrustedPeer }
        _ = try CredentialFiles(root: root)
        path = root.appendingPathComponent("broker.sock").path
        self.clientHash = clientHash
        ownership = Darwin.open(root.appendingPathComponent("broker.lock").path,
                               O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        var info = stat()
        guard ownership >= 0, fstat(ownership, &info) == 0,
              info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0, info.st_nlink == 1,
              flock(ownership, LOCK_EX | LOCK_NB) == 0 else {
            if ownership >= 0 { close(ownership) }; throw IPCError.unavailable
        }
        if lstat(path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid(), unlink(path) == 0 else {
                close(ownership); throw IPCError.unsafePath
            }
        } else if errno != ENOENT { close(ownership); throw IPCError.unsafePath }
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { close(ownership); throw IPCError.transport }
        do {
            try LocalIPC.configure(listener)
            var addr = try LocalIPC.address(path)
            let result = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0, chmod(path, 0o600) == 0, listen(listener, 8) == 0 else { throw IPCError.transport }
        } catch { close(listener); close(ownership); throw error }
    }
    deinit { close(listener); unlink(path); close(ownership) }
    public func stop() { state.lock(); stopped = true; state.unlock() }
    private var running: Bool { state.lock(); defer { state.unlock() }; return !stopped }

    public func start(handler: @escaping @MainActor (BrokerRequest) -> BrokerResponse) {
        DispatchQueue(label: "keyhatch.ipc").async { [self] in
            while running {
                var event = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                guard poll(&event, 1, 250) > 0 else { continue }
                let fd = accept(listener, nil, nil)
                guard fd >= 0 else { continue }
                do {
                    try LocalIPC.configure(fd)
                    try LocalIPC.authenticate(fd, expectedHash: clientHash)
                    let request = try JSONDecoder().decode(BrokerRequest.self, from: LocalIPC.readFrame(fd))
                    let completed = DispatchSemaphore(value: 0)
                    Task { @MainActor [self] in
                        defer { close(fd); completed.signal() }
                        guard self.running else { return }
                        // Recheck peer identity at release, not just at accept.
                        guard (try? LocalIPC.authenticate(fd, expectedHash: self.clientHash)) != nil else { return }
                        let response = handler(request)
                        try? LocalIPC.writeFrame(JSONEncoder().encode(response), to: fd)
                    }
                    completed.wait()
                } catch { close(fd) } // Never log frames or secret-bearing errors.
            }
        }
    }
}
