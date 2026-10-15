// SPDX-License-Identifier: MPL-2.0
import Foundation
import Darwin
import KeyhatchCore

@main
struct Fixture {
    static func main() async {
        do {
            try disableCoreDumps()
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count >= 3 else { exit(2) }
            if args[0] == "server" {
                let server = try BrokerServer(clientHash: args[2], root: URL(fileURLWithPath: args[1]))
                server.start { request in
                    BrokerResponse(ok: request.version == 1 && request.operation == "probe",
                                   status: "synthetic IPC fixture only")
                }
                while true { try await Task.sleep(nanoseconds: 250_000_000) }
            } else {
                let reply = try LocalIPC.call(BrokerRequest(operation: "probe"), serverHash: args[2], path: args[1])
                guard reply.ok, reply.status == "synthetic IPC fixture only", reply.secret == nil else { exit(3) }
                print("authenticated")
            }
        } catch { print("denied"); exit(1) }
    }
}
