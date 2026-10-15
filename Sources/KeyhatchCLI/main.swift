// SPDX-License-Identifier: MPL-2.0
import Darwin
import Foundation
import KeyhatchCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}

func deployment() throws -> LocalDeployment {
    // Resolve beside this installed binary, not through an agent-controlled request.
    guard let actualExecutable = Bundle.main.executableURL else { throw IPCError.unsafePath }
    let executable = actualExecutable.resolvingSymlinksInPath()
    let path = executable.deletingLastPathComponent().appendingPathComponent("deployment.json")
    let fd = Darwin.open(path.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw IPCError.unsafePath }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
          info.st_mode & 0o077 == 0, info.st_nlink == 1, info.st_size <= 8192 else { throw IPCError.unsafePath }
    let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
    let result = try JSONDecoder().decode(LocalDeployment.self, from: data)
    guard LocalIPC.validHash(result.serverHash), LocalIPC.validHash(result.clientHash) else { throw IPCError.untrustedPeer }
    return result
}

func boundedInput() throws -> String {
    var input = Data()
    while let byte = try FileHandle.standardInput.read(upToCount: 1), !byte.isEmpty {
        input.append(byte)
        guard input.count <= 16384 else { throw IPCError.framing }
        if input.suffix(2) == Data([10, 10]) { break }
    }
    guard let text = String(data: input, encoding: .utf8) else { throw IPCError.framing }
    return text
}

do {
    try disableCoreDumps()
    let args = Array(CommandLine.arguments.dropFirst())
    guard let verb = args.first else {
        fail("Usage: keyhatch status | lock | check HOST ACCOUNT | run HOST ACCOUNT --password-env NAME -- COMMAND | git --host HOST --username ACCOUNT get")
    }
    if ["--help", "help"].contains(verb) {
        print("Keyhatch local pilot: status, lock, check HOST ACCOUNT, run HOST ACCOUNT --password-env NAME [--username-env NAME] -- COMMAND, git --host HOST --username ACCOUNT get|store|erase. Unlock and approvals are in the app. No automatic fallback or Passwords fetch.")
        exit(0)
    }
    if verb == "git" && (args.last == "store" || args.last == "erase") { exit(0) }
    let trust = try deployment()
    func call(_ op: String, _ host: String? = nil, _ account: String? = nil) throws -> BrokerResponse {
        try LocalIPC.call(BrokerRequest(operation: op, host: host, account: account), serverHash: trust.serverHash)
    }
    if verb == "status" || verb == "lock" {
        guard args.count == 1 else { throw IPCError.framing }
        let response = try call(verb)
        guard response.secret == nil else { throw IPCError.framing }
        print(response.status)
        exit(response.ok ? 0 : 1)
    }
    if verb == "git" {
        guard args.count == 6, args[1] == "--host", args[3] == "--username", args[5] == "get",
              isatty(STDOUT_FILENO) == 0 else { throw IPCError.framing }
        let host = args[2], account = args[4]
        guard ClientProtocol.matchesGit(try boundedInput(), host: host, account: account) else { exit(0) }
        let response = try call("get", host, account)
        guard response.ok, let secret = response.secret,
              !secret.contains(where: { $0.isNewline }), !secret.utf8.contains(0),
              !account.contains(where: { $0.isNewline }), !account.utf8.contains(0) else {
            fail("Keyhatch denied Git credential retrieval; unlock/approve in the app. No fallback attempted.")
        }
        FileHandle.standardOutput.write(Data("username=\(account)\npassword=\(secret)\n\n".utf8))
        exit(0)
    }
    guard args.count >= 3 else { throw IPCError.framing }
    let host = args[1], account = args[2]
    if verb == "check" {
        guard args.count == 3 || (args.count == 4 && args[3] == "--cached-only") else { throw IPCError.framing }
        let response = try call("check", host, account)
        guard response.secret == nil else { throw IPCError.framing }
        print(response.status)
        exit(response.ok ? 0 : 1)
    }
    guard verb == "run", let separator = args.firstIndex(of: "--"), separator >= 5,
          separator + 1 < args.count else { throw IPCError.framing }
    var secretName: String?, userName = "WEBSITE_USERNAME"
    var index = 3
    while index < separator {
        if args[index] == "--cached-only" { index += 1; continue }
        guard index + 1 < separator else { throw IPCError.framing }
        if args[index] == "--password-env", secretName == nil { secretName = args[index + 1] }
        else if args[index] == "--username-env" { userName = args[index + 1] }
        else { throw IPCError.framing }
        index += 2
    }
    guard let secretName, secretName != userName,
          ClientProtocol.validEnvironmentName(secretName), ClientProtocol.validEnvironmentName(userName) else {
        throw IPCError.framing
    }
    // Resolve the executable before requesting a credential; no shell interpolation.
    let command = args[separator + 1]
    let candidate: String?
    if command.contains("/") { candidate = URL(fileURLWithPath: command).standardizedFileURL.path }
    else {
        candidate = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":")
            .map { String($0) + "/" + command }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    guard let candidate, FileManager.default.isExecutableFile(atPath: candidate) else { fail("Command not executable.") }
    let response = try call("get", host, account)
    guard response.ok, let secret = response.secret else {
        fail("Keyhatch denied retrieval; unlock/approve the selected credential in the app. No fallback attempted.")
    }
    var environment = ProcessInfo.processInfo.environment
    environment[secretName] = secret; environment[userName] = account
    let child = Process()
    child.executableURL = URL(fileURLWithPath: candidate)
    child.arguments = Array(args.dropFirst(separator + 2))
    child.environment = environment
    try child.run(); child.waitUntilExit()
    exit(child.terminationReason == .exit ? child.terminationStatus : 128 + child.terminationStatus)
} catch {
    fail("Keyhatch unavailable, untrusted, or invalid request. Open the installed app; check deployment/unlock. No credential fallback performed.")
}
