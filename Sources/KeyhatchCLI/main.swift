// SPDX-License-Identifier: MPL-2.0
import Darwin
import Foundation
import KeyhatchCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
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
        fail("Usage: keyhatch verify-installation | status | lock | check HOST ACCOUNT | run HOST ACCOUNT --password-env NAME -- COMMAND | git --host HOST --username ACCOUNT get")
    }
    if ["--help", "help"].contains(verb) {
        print("Keyhatch: verify-installation, status, lock, check HOST ACCOUNT, run HOST ACCOUNT --password-env NAME [--username-env NAME] -- COMMAND, git --host HOST --username ACCOUNT get|store|erase. Unlock and approvals are in the app. The App Store variant does not support run. No automatic fallback or Passwords fetch.")
        exit(0)
    }
    if verb == "git" && (args.last == "store" || args.last == "erase") { exit(0) }
    let configuration = try BundledDeployment.resolve()
    let trust = configuration.deployment
    if verb == "verify-installation" {
        guard args.count == 1 else { throw IPCError.framing }
        print("Keyhatch installation verified (\(configuration.distribution)).")
        exit(0)
    }
    if verb == "run" && configuration.distribution == "app-store" {
        fail("The App Store variant does not support running arbitrary commands. Use the direct-distribution app for this workflow.")
    }
    let root: URL
    if let applicationURL = configuration.applicationURL {
        guard let bundle = Bundle(url: applicationURL) else { throw IPCError.unsafePath }
        root = try DeploymentPaths.ipcRoot(bundle: bundle)
    } else { root = CredentialFiles.defaultRoot }
    func call(_ op: String, _ host: String? = nil, _ account: String? = nil) throws -> BrokerResponse {
        try LocalIPC.call(BrokerRequest(operation: op, host: host, account: account),
                          serverHash: trust.serverHash, path: root.appendingPathComponent("broker.sock").path)
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
    if CommandLine.arguments.dropFirst().first == "verify-installation" {
        fail("Keyhatch installation verification failed. For a sandboxed Store client, use a validated installation under /Applications; build and archive directories may be inaccessible. No credential fallback performed.")
    }
    fail("Keyhatch unavailable, untrusted, or invalid request. Open the installed app; check deployment/unlock. No credential fallback performed.")
}
