// SPDX-License-Identifier: MPL-2.0
// Disposable signed test client. Never installed as the production client.
import Darwin
import Foundation
import Security

enum ProbeFailure: Error { case check(String) }

@main
struct StoreSandboxProbe {
    static func require(_ condition: Bool, _ name: String) throws {
        guard condition else { throw ProbeFailure.check(name) }
    }

    static func authenticateBroker(_ fd: Int32, hash: String) throws {
        var uid: uid_t = 0, gid: gid_t = 0
        try require(getpeereid(fd, &uid, &gid) == 0 && uid == getuid(), "broker owner")
        var token = [UInt8](repeating: 0, count: 32)
        var count = socklen_t(token.count)
        try require(getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &count) == 0 && count == 32,
                    "broker audit token")
        var code: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: Data(token)] as CFDictionary
        try require(SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess,
                    "broker code")
        var requirement: SecRequirement?
        try require(SecRequirementCreateWithString("cdhash H\"\(hash)\"" as CFString,
                    SecCSFlags(), &requirement) == errSecSuccess, "broker requirement")
        guard let code, let requirement else { throw ProbeFailure.check("broker identity") }
        try require(SecCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement)
                    == errSecSuccess, "broker signature")
    }

    static func testBroker(_ path: String, hash: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        try require(fd >= 0, "IPC socket")
        defer { close(fd) }
        var noSignal: Int32 = 1
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        try require(setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, 4) == 0 &&
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                               socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
                    "IPC socket options")
        var address = sockaddr_un()
        try require(path.utf8.count < MemoryLayout.size(ofValue: address.sun_path), "IPC path length")
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { destination in
            path.withCString { source in _ = memcpy(destination, source, path.utf8.count + 1) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try require(result == 0, "IPC connect (unavailable broker is not a rejection)")
        try authenticateBroker(fd, hash: hash)
        let request = Data("{\"version\":1,\"operation\":\"status\"}".utf8)
        var count = UInt32(request.count).bigEndian
        var frame = withUnsafeBytes(of: &count) { Data($0) }
        frame.append(request)
        let sent = frame.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        if sent < 0 {
            try require(errno == EPIPE || errno == ECONNRESET, "IPC send")
        } else {
            try require(sent == frame.count, "IPC partial send")
            var byte: UInt8 = 0
            let received = recv(fd, &byte, 1, 0)
            // A timeout is inconclusive and fails. Any response byte also fails;
            // never print or parse data received from the broker.
            try require(received == 0 || (received < 0 && errno == ECONNRESET),
                        "wrong-build client must receive immediate rejection")
        }
        print("PASS: authenticated broker rejected changed client build")
    }

    static func main() {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            try require(args.count == 3 || args.count == 4, "arguments")
            let group = args[0], hash = args[2]
            guard let port = UInt16(args[1]) else { throw ProbeFailure.check("port") }
            try require(hash.count == 40 && hash.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            }, "hash")
            guard let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: group) else {
                throw ProbeFailure.check("App Group container")
            }
            let scratch = container.appendingPathComponent("keyhatch-sandbox-probe-" + UUID().uuidString)
            let scratchFD = open(scratch.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            try require(scratchFD >= 0, "App Group create")
            let marker: [UInt8] = [75, 72]
            let written = marker.withUnsafeBytes { write(scratchFD, $0.baseAddress, $0.count) }
            close(scratchFD)
            let removed = unlink(scratch.path)
            try require(written == marker.count && removed == 0, "App Group write/remove")
            print("PASS: App Group scratch write and removal")
            if args.count == 4 {
                // The caller attests this is a known existing synthetic file.
                // Only open; never read, map, log, or mutate its contents.
                let fd = open(args[3], O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                let error = errno
                if fd >= 0 { close(fd) }
                try require(fd < 0 && (error == EPERM || error == EACCES), "broker private file denied")
                print("PASS: synthetic broker-private file open denied")
            } else {
                print("SKIP: no synthetic broker-private file supplied")
            }
            let network = socket(AF_INET, SOCK_STREAM, 0)
            try require(network >= 0, "network socket")
            var destination = sockaddr_in()
            destination.sin_family = sa_family_t(AF_INET)
            destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            destination.sin_port = port.bigEndian
            destination.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &destination) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(network, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            let networkError = errno
            close(network)
            try require(connected < 0 && (networkError == EPERM || networkError == EACCES),
                        "outbound loopback denied")
            print("PASS: outbound loopback connection denied")
            try testBroker(container.appendingPathComponent("IPC/broker.sock").path, hash: hash)
        } catch ProbeFailure.check(let name) {
            FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("FAIL: unexpected probe error\n".utf8))
            exit(1)
        }
    }
}
