// SPDX-License-Identifier: MPL-2.0
import Foundation
import Darwin
import KeyhatchCore

@main
struct Fixture {
    /// Use the same pinned executable as ordinary clients so invalid requests reach
    /// framing/decoding after peer authentication. All payloads are synthetic.
    private static func rejectedFrame(path: String, serverHash: String, scenario: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.transport }
        defer { close(fd) }
        try LocalIPC.configure(fd)
        var address = try LocalIPC.address(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw IPCError.transport }
        try LocalIPC.authenticate(fd, expectedHash: serverHash)

        func header(_ length: UInt32) -> Data {
            var value = length.bigEndian
            return withUnsafeBytes(of: &value) { Data($0) }
        }
        let data: Data
        switch scenario {
        case "malformed-json": data = header(1) + Data("{".utf8)
        case "zero-length": data = header(0)
        case "oversized": data = header(UInt32(LocalIPC.maximumFrame + 1))
        case "maximum-length": data = header(UInt32.max)
        case "truncated-header", "stalled-header": data = Data([0, 0])
        case "truncated-body", "stalled-body": data = header(32) + Data("{".utf8)
        default: throw IPCError.framing
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw IPCError.transport }
                offset += count
            }
        }
        if scenario.hasPrefix("truncated-") {
            guard shutdown(fd, SHUT_WR) == 0 else { throw IPCError.transport }
        }
        // Wait for actual peer closure, not our own receive timeout. Otherwise a
        // hung broker would accidentally make a rejection test pass.
        var event = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&event, 1, 6000) > 0 else { throw IPCError.transport }
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, 0)
        guard count == 0 || (count < 0 && errno == ECONNRESET) else { throw IPCError.framing }
        print("rejected \(scenario)")
    }

    static func main() async {
        do {
            try disableCoreDumps()
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["bundle-pin"] {
                print(try BundledDeployment.brokerClientHash())
                return
            }
            guard args.count >= 3 else { exit(2) }
            if args[0] == "server" {
                let server = try BrokerServer(clientHash: args[2], root: URL(fileURLWithPath: args[1]))
                server.start { request in
                    BrokerResponse(ok: request.version == 1 && request.operation == "probe",
                                   status: "synthetic IPC fixture only")
                }
                while true { try await Task.sleep(nanoseconds: 250_000_000) }
            } else if args[0] == "invalid-frame", args.count == 4 {
                try rejectedFrame(path: args[1], serverHash: args[2], scenario: args[3])
            } else {
                let reply = try LocalIPC.call(BrokerRequest(operation: "probe"), serverHash: args[2], path: args[1])
                guard reply.ok, reply.status == "synthetic IPC fixture only", reply.secret == nil else { exit(3) }
                print("authenticated")
            }
        } catch { print("denied"); exit(1) }
    }
}
