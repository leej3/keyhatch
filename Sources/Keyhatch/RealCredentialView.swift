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
    @Published var brokerStatus = "Broker not started"
    @Published var cliApproved = false
    private var key: SymmetricKey?
    private var envelope: EnclaveEnvelope?
    private var storage: CredentialFiles?
    private var heldLock: Int32 = -1
    private var activeName = ""
    private var lifetime: SessionLifetime?
    private var generation = UUID()
    private var importGeneration: UUID?
    private var network: URLSession?
    private var broker: BrokerServer?
    private var clientHash = ""

    /// Plaintext exists only in memory; cancellation invalidates the result before saving.
    func importCredential(host: String, account: String, secret: String,
                          fetchedAt: Date, expiresAt: Date, operationID: UUID) async -> Bool {
        guard !Task.isCancelled else { return false }
        guard !unlocked, !busy, let storage else {
            status = "Lock the session and make private storage available before importing."
            return false
        }
        generation = operationID
        let token = generation
        importGeneration = token
        busy = true
        status = "Encrypting one selected credential. No client access will be granted."
        do {
            let fields: [String: Any] = ["host": host, "account": account, "secret": secret,
                "fetchedAt": fetchedAt.timeIntervalSince1970,
                "expiresAt": expiresAt.timeIntervalSince1970, "history": []]
            var record = try JSONDecoder().decode(CredentialRecord.self,
                from: JSONSerialization.data(withJSONObject: fields))
            try record.validate()
            record.record("User imported one selected credential; no client access granted")
            let payload = try JSONEncoder().encode(record)
            let sealed = try await Task.detached { try EnclaveVault.seal(payload) }.value
            guard generation == token, importGeneration == token else { return false }
            guard !Task.isCancelled else { cancelImport(operationID); return false }
            // Sealing or scheduling must not extend an already elapsed source lifetime.
            try record.validate()
            let name = try storage.create(sealed)
            importGeneration = nil
            busy = false
            files = (try? storage.list()) ?? (files + [name]).sorted()
            selected = name
            status = "Imported one encrypted credential. Unlock and approve separately to allow retrieval."
            return true
        } catch {
            guard generation == token, importGeneration == token else { return false }
            importGeneration = nil
            busy = false
            status = "Import failed: check the host, account, secret, and original source times. No existing credential was replaced."
            return false
        }
    }

    func cancelImport(_ operationID: UUID) {
        guard importGeneration == operationID, generation == operationID else { return }
        importGeneration = nil
        lock()
        status = "Import canceled. No pending import will be saved."
    }

    func deleteCredential(_ name: String) {
        guard !unlocked, !busy, name == selected, !name.isEmpty else { return }
        do {
            guard let storage else { throw CredentialError.storage }
            try storage.remove(name)
            files = (try? storage.list()) ?? files.filter { $0 != name }
            selected = files.first ?? ""
            status = "Deleted the selected local encrypted credential and its history. Source credentials, remote sessions, backups, and recipient copies are unchanged."
        } catch {
            status = "Deletion failed or another app instance holds the file. No remote credential was revoked."
        }
    }

    func refresh() {
        do {
            try disableCoreDumps()
            let store = try CredentialFiles(root: DeploymentPaths.credentialRoot())
            files = try store.list()
            storage = store
            if !files.contains(selected) { selected = files.last ?? "" }
            if broker == nil {
                if Bundle.main.object(forInfoDictionaryKey: "KeyhatchDistribution") != nil {
                    clientHash = try BundledDeployment.brokerClientHash()
                } else {
                    clientHash = Bundle.main.object(forInfoDictionaryKey: "KeyhatchClientCDHash") as? String ?? ""
                }
                let service = try BrokerServer(clientHash: clientHash, root: DeploymentPaths.ipcRoot())
                service.start { [weak self] request in
                    self?.handle(request) ?? BrokerResponse(ok: false, status: "locked")
                }
                broker = service
                brokerStatus = "Broker ready · pinned CLI only · shared by agents under your account"
            }
        } catch { status = "Cannot access private credential storage; access denied." }
    }

    func lock() {
        generation = UUID()
        network?.invalidateAndCancel(); network = nil
        key = nil; envelope = nil; lifetime = nil; unlocked = false; busy = false; cliApproved = false
        host = ""; account = ""; expires = nil; history = []
        if heldLock >= 0 { close(heldLock); heldLock = -1 }
        status = "Locked. Future access denied; existing remote sessions are not revoked."
    }

    func tick() {
        if unlocked && !active { lock(); status = "Session or credential expired; locked." }
    }
    private var active: Bool {
        authorizationTime != nil
    }
    private var authorizationTime: Date? {
        guard unlocked, let lifetime else { return nil }
        return lifetime.authorizationTime(now: Date(), continuous: SessionLifetime.continuousTime())
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
                    // Read continuous time first so scheduling between the clock
                    // samples can only shorten the remaining lifetime.
                    let continuous = SessionLifetime.continuousTime()
                    let now = Date()
                    try record.validate(now: now)
                    guard let lifetime = SessionLifetime(now: now,
                        continuous: continuous, credentialExpiry: record.expiresAt)
                    else { throw CredentialError.expired }
                    key = sessionKey; envelope = sealed; activeName = name
                    host = record.host; account = record.account
                    expires = Date(timeIntervalSince1970: record.expiresAt)
                    self.lifetime = lifetime
                    unlocked = true
                    cliApproved = record.brokerApproval?.permits(clientHash: clientHash,
                        credentialExpiry: record.expiresAt, now: now) ?? false
                    try recordEvent("Unlocked for at most five hours; existing CLI approval re-evaluated")
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
        try persist(record)
    }

    private func persist(_ record: CredentialRecord) throws {
        guard active else { throw CredentialError.locked }
        guard let key, let envelope, let storage else { throw CredentialError.locked }
        let updated = try EnclaveVault.replacingPayload(envelope,
            plaintext: JSONEncoder().encode(record), using: key)
        try storage.update(updated, name: activeName)
        self.envelope = updated
        history = record.history
    }

    func approveCLI() {
        do {
            guard broker != nil, LocalIPC.validHash(clientHash) else { throw IPCError.unavailable }
            var record = try readRecord()
            record.brokerApproval = BrokerApproval(clientHash: clientHash, expiresAt: record.expiresAt)
            record.record("User approved pinned CLI for repeated retrieval until source expiry; recipient may retain copies")
            try persist(record)
            cliApproved = true
            status = "CLI approved for this credential until its original cache expiry."
        } catch { lock(); status = "Approval could not be persisted; locked." }
    }

    func revokeCLI() {
        do {
            var record = try readRecord()
            record.brokerApproval = nil
            record.record("User revoked CLI retrieval; previously disclosed copies are not revoked")
            try persist(record)
            cliApproved = false
            status = "CLI revoked. Further retrieval is denied."
        } catch { lock(); status = "Revocation could not be persisted; locked. Do not assume persistent revocation succeeded." }
    }

    private func handle(_ request: BrokerRequest) -> BrokerResponse {
        guard request.version == 1 else { return BrokerResponse(ok: false, status: "unsupported request") }
        if request.operation == "status" {
            tick()
            return BrokerResponse(ok: true, status: active ? (cliApproved ? "unlocked; CLI approved" : "unlocked; approval required") : "locked")
        }
        if request.operation == "lock" { lock(); return BrokerResponse(ok: true, status: "locked") }
        guard ["get", "check"].contains(request.operation) else { return BrokerResponse(ok: false, status: "unsupported request") }
        guard active else { tick(); return BrokerResponse(ok: false, status: "locked or expired") }
        do {
            guard request.host == host, request.account == account else {
                try recordEvent("Denied CLI request for a different credential")
                return BrokerResponse(ok: false, status: "credential not selected")
            }
            let record = try readRecord()
            guard let authorizationTime,
                  record.brokerApproval?.permits(clientHash: clientHash,
                    credentialExpiry: record.expiresAt, now: authorizationTime) == true else {
                cliApproved = false
                try recordEvent("Denied CLI request: approval required or revoked")
                return BrokerResponse(ok: false, status: "approval required or revoked")
            }
            try recordEvent(request.operation == "get" ? "Authorized pinned CLI credential release (recipient may retain a copy)" : "Pinned CLI availability check; no secret released")
            // The encrypted audit write may take time: recheck immediately before sending.
            guard let releaseTime = self.authorizationTime,
                  record.brokerApproval?.permits(clientHash: clientHash,
                    credentialExpiry: record.expiresAt, now: releaseTime) == true else {
                lock(); return BrokerResponse(ok: false, status: "expired during request")
            }
            return BrokerResponse(ok: true, status: "available", secret: request.operation == "get" ? record.secret : nil,
                                  expiresAt: record.expiresAt)
        } catch {
            lock()
            return BrokerResponse(ok: false, status: "validation or audit failure; locked")
        }
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
                // Scheduling may outlast the session. A stale task must not send
                // credentials or lock a replacement session.
                guard generation == token else { return }
                guard active else { tick(); return }
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
    @ObservedObject var model: RealCredentialModel
    @LocalViewState private var confirmRequest = false
    @LocalViewState private var confirmCLI = false
    @LocalViewState private var showImporter = false
    @LocalViewState private var confirmDelete = false
    @LocalViewState private var pendingDeletion = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyhatch · Real credential test").font(.title.bold())
            Text("Local pilot · Pinned CLI identity · No bulk Passwords access")
                .foregroundStyle(.orange)
            Text(model.brokerStatus).font(.caption)
            Text("Import one selected credential. Encrypted files remain on this Mac; the source password store is unchanged.")
            HStack {
                Picker("Encrypted file", selection: $model.selected) {
                    Text("Select a file").tag("")
                    ForEach(model.files, id: \.self) { Text($0).tag($0) }
                }.disabled(model.unlocked || model.busy)
                Button("Refresh files") { model.refresh() }.disabled(model.busy || model.unlocked)
            }
            HStack {
                Button("Import one credential…") { showImporter = true }
                    .disabled(model.busy || model.unlocked)
                Button("Delete selected file…", role: .destructive) {
                    pendingDeletion = model.selected
                    confirmDelete = true
                }.disabled(model.selected.isEmpty || model.busy || model.unlocked)
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
                HStack {
                    Button("Approve local CLI…") { confirmCLI = true }.disabled(model.cliApproved || model.busy)
                    Button("Revoke CLI") { model.revokeCLI() }.disabled(!model.cliApproved)
                    Text(model.cliApproved ? "Repeated retrieval approved" : "CLI retrieval denied")
                }
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
        .sheet(isPresented: $showImporter) { CredentialImportView(model: model) }
        .confirmationDialog("Delete the selected encrypted credential and its local history? This cannot be undone here. It does not delete the source credential, revoke remote access, or remove backups or recipient copies.",
                            isPresented: $confirmDelete) {
            Button("Delete local credential", role: .destructive) { model.deleteCredential(pendingDeletion) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Send the selected credential to \(model.host) for a read-only identity check?",
                            isPresented: $confirmRequest) {
            Button("Send to selected host") { model.checkForgeIdentity() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Allow the installed Keyhatch CLI to retrieve \(model.host) / \(model.account) while unlocked until source expiry? All agents under your account can use this CLI and retain credentials after lock or revocation.",
                            isPresented: $confirmCLI) {
            Button("Approve this credential for local CLI") { model.approveCLI() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
