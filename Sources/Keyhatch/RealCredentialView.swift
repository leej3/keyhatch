// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import Combine
import CryptoKit
import Darwin
import KeyhatchCore

private typealias LocalViewState<Value> = SwiftUI.State<Value>

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class RealCredentialModel: ObservableObject {
    @Published var files: [String] = []
    @Published var selected = ""
    @Published var status = "No real credential unlocked. Existing Agent Vault is unchanged."
    @Published var host = ""
    @Published var account = ""
    @Published var expires: Date?
    @Published var history: [CredentialHistory] = []
    @Published var unlocked = false
    @Published var busy = false
    private var key: SymmetricKey?
    private var envelope: EnclaveEnvelope?
    private var storage: CredentialFiles?
    private var heldLock: Int32 = -1
    private var activeName = ""
    private var start: Date?
    private var monotonicStart: TimeInterval = 0
    private var generation = UUID()
    private var network: URLSession?

    func refresh() {
        do {
            try disableCoreDumps()
            let store = try CredentialFiles()
            files = try store.list()
            storage = store
            if !files.contains(selected) { selected = files.last ?? "" }
        } catch { status = "Cannot access private credential storage; access denied." }
    }

    func lock() {
        generation = UUID()
        network?.invalidateAndCancel(); network = nil
        key = nil; envelope = nil; start = nil; unlocked = false; busy = false
        host = ""; account = ""; expires = nil; history = []
        if heldLock >= 0 { close(heldLock); heldLock = -1 }
        status = "Locked. Future access denied; existing remote sessions are not revoked."
    }

    func tick() {
        if unlocked && !active { lock(); status = "Session or credential expired; locked." }
    }
    private var active: Bool {
        guard unlocked, let start, let expires else { return false }
        let elapsed = Date().timeIntervalSince(start)
        let monotonic = ProcessInfo.processInfo.systemUptime - monotonicStart
        return elapsed >= 0 && elapsed < AccessPolicy.sessionDuration &&
            monotonic >= 0 && monotonic < AccessPolicy.sessionDuration && Date() < expires
    }

    func unlock() {
        guard !busy, !selected.isEmpty else { return }
        lock()
        busy = true
        let token = generation
        let name = selected
        do {
            guard let storage else { throw CredentialError.storage }
            heldLock = try storage.lockFile(name)
            let sealed = try storage.read(name)
            status = "Authorize Touch ID once to open the selected credential."
            Task {
                do {
                    let sessionKey = try await Task.detached { try EnclaveVault.unlockKey(sealed) }.value
                    guard generation == token else { return }
                    let record = try JSONDecoder().decode(CredentialRecord.self,
                        from: EnclaveVault.decrypt(sealed, using: sessionKey))
                    try record.validate()
                    key = sessionKey; envelope = sealed; activeName = name
                    host = record.host; account = record.account
                    expires = Date(timeIntervalSince1970: record.expiresAt)
                    start = Date(); monotonicStart = ProcessInfo.processInfo.systemUptime
                    unlocked = true
                    try recordEvent("Unlocked for at most five hours; no agent access granted")
                    status = "Loaded \(host) / \(account). No password value is displayed."
                    busy = false
                } catch {
                    guard generation == token else { return }
                    lock()
                    status = "Unlock failed, canceled, or credential expired. Existing encrypted data preserved."
                }
            }
        } catch {
            lock(); status = "Cannot open credential safely, or another app instance holds it."
        }
    }

    private func readRecord() throws -> CredentialRecord {
        guard active, let key, let envelope else { throw CredentialError.locked }
        let record = try JSONDecoder().decode(CredentialRecord.self,
            from: EnclaveVault.decrypt(envelope, using: key))
        try record.validate()
        guard record.host == host, record.account == account else { throw CredentialError.invalidRecord }
        return record
    }

    private func recordEvent(_ text: String) throws {
        var record = try readRecord()
        record.record(text)
        guard let key, let envelope, let storage else { throw CredentialError.locked }
        let updated = try EnclaveVault.replacingPayload(envelope,
            plaintext: JSONEncoder().encode(record), using: key)
        try storage.update(updated, name: activeName)
        self.envelope = updated
        history = record.history
    }

    /// Explicit user action: exact-host HTTPS GET only, no redirects or shared cookies.
    func checkForgeIdentity() {
        guard active, !busy else { tick(); return }
        do {
            // Fail closed if the pre-request audit write cannot be persisted.
            try recordEvent("User requested read-only HTTPS GET /api/v1/user; redirects disabled")
            let record = try readRecord()
            guard let url = URL(string: "https://\(record.host)/api/v1/user"),
                  url.host == record.host, url.scheme == "https" else { throw CredentialError.invalidRecord }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 20
            request.setValue("Basic " + Data("\(record.account):\(record.secret)".utf8).base64EncodedString(),
                             forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForResource = 25
            let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
            network = session
            let token = generation
            let expectedAccount = record.account
            busy = true
            status = "Checking the selected host; response body will not be displayed."
            Task {
                defer { session.invalidateAndCancel() }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard generation == token, active else { return }
                    guard let http = response as? HTTPURLResponse else { throw CredentialError.invalidRecord }
                    var result = "HTTPS identity check: HTTP \(http.statusCode)"
                    if http.statusCode == 200 {
                        var body = Data()
                        for try await byte in bytes {
                            guard body.count < 65536 else { throw CredentialError.invalidRecord }
                            body.append(byte)
                        }
                        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                        result += payload?["login"] as? String == expectedAccount
                            ? "; account matched" : "; account did NOT match (not verified)"
                    }
                    guard generation == token, active else { return }
                    try recordEvent(result)
                    status = result; busy = false; network = nil
                } catch {
                    guard generation == token else { return }
                    do { try recordEvent("Identity check failed; response details withheld") }
                    catch { lock(); status = "Audit/storage failure: locked. A request may already have reached the host."; return }
                    status = "Identity check failed; response details withheld. No retry performed."
                    busy = false; network = nil
                }
            }
        } catch {
            lock(); status = "Validation or audit failure: locked before network access."
        }
    }
}

struct RealCredentialView: View {
    @StateObject private var model = RealCredentialModel()
    @LocalViewState private var confirmRequest = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyhatch · Real credential test").font(.title.bold())
            Text("Experimental local build · No agent IPC · No bulk Passwords access")
                .foregroundStyle(.orange)
            Text("Import one selected credential through the private-pipe importer. Encrypted files remain on this Mac; the source password store is unchanged.")
            HStack {
                Picker("Encrypted file", selection: $model.selected) {
                    Text("Select a file").tag("")
                    ForEach(model.files, id: \.self) { Text($0).tag($0) }
                }.disabled(model.unlocked || model.busy)
                Button("Refresh files") { model.refresh() }.disabled(model.busy || model.unlocked)
            }
            HStack {
                Button("Unlock selected file with Touch ID") { model.unlock() }
                    .disabled(model.selected.isEmpty || model.busy || model.unlocked)
                Button("Lock now") { model.lock() }
                Spacer()
                Text(model.unlocked ? "Unlocked · up to 5 hours" : "Locked")
            }
            Label(model.status, systemImage: "info.circle")
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            if model.unlocked {
                Text("\(model.host) / \(model.account)").font(.headline)
                if let expires = model.expires { Text("Source cache expiry: \(expires.formatted())") }
                Button("Check read-only Forgejo identity…") { confirmRequest = true }.disabled(model.busy)
                Text("Sends this credential only to https://\(model.host)/api/v1/user. No redirects, no shared cookie store, no response body displayed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Encrypted review history · latest 200 events").font(.headline)
            List(model.history.reversed()) { event in
                VStack(alignment: .leading) {
                    Text(event.action)
                    Text(event.date.formatted()).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Lock/expiry cannot revoke credentials already disclosed. This build does not isolate other unrestricted processes under your macOS account.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 860, minHeight: 620)
        .onAppear { model.refresh() }
        .onDisappear { model.lock() }
        .onReceive(timer) { _ in model.tick() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.lock() }
        .confirmationDialog("Send the selected credential to \(model.host) for a read-only identity check?",
                            isPresented: $confirmRequest) {
            Button("Send to selected host") { model.checkForgeIdentity() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
