// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import KeyhatchCore

// Select the stable property wrapper instead of the SDK's same-named macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct KeyhatchApp: App {
    @StateObject private var model = RealCredentialModel()
    var body: some Scene {
        WindowGroup("Keyhatch · Development Preview") {
            TabView {
                RealCredentialView(model: model).tabItem { Text("Real credential test") }
                Dashboard().tabItem { Text("Synthetic policy demo") }
            }.frame(minWidth: 860, minHeight: 680)
        }
    }
}

struct PreviewCredential: Identifiable {
    let id = UUID()
    let host: String
    let account: String
    let fetchedAt = Date()
}

struct Dashboard: View {
    @ViewState private var policy = AccessPolicy()
    @ViewState private var credentials: [PreviewCredential] = []
    @ViewState private var notice = "No credentials loaded. This preview never reads Apple Passwords."
    @ViewState private var hardwareNotice = "Hardware verification has not been run."
    @ViewState private var confirmHardware = false
    @ViewState private var testingHardware = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "hand.raised.fingers.spread.fill").font(.largeTitle)
                VStack(alignment: .leading) {
                    Text("Keyhatch").font(.largeTitle.bold())
                    Text("Prioritizing practicality over perfection.").foregroundStyle(.secondary)
                }
                Spacer()
                Text("SYNTHETIC PREVIEW").font(.caption.bold()).padding(8)
                    .background(.orange.opacity(0.15), in: Capsule())
            }
            Text("This is not an active credential broker. No real agent access is enabled.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Start demo session") {
                    policy.beginAuthenticatedSession(now: Date(), monotonic: ProcessInfo.processInfo.systemUptime)
                    notice = "Simulated five-hour session started. Production unlock must require Touch ID."
                }
                Button("Load example credential") { loadExample() }
                Button("Lock now") { policy.lock(); notice = "Demo locked. New requests will be denied." }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { clock in
                    Text(policy.isUnlocked(now: clock.date, monotonic: ProcessInfo.processInfo.systemUptime)
                         ? "Demo unlocked · maximum 5 hours" : "Locked")
                }
            }
            Label(notice, systemImage: "info.circle").padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Credential activity: \(notice)")
            Text("Loaded credentials").font(.headline)
            if credentials.isEmpty { Text("Nothing loaded").foregroundStyle(.secondary) }
            ForEach(credentials) { credential in
                HStack {
                    VStack(alignment: .leading) {
                        Text(credential.host).bold()
                        Text("\(credential.account) · synthetic · expires \(credential.fetchedAt.addingTimeInterval(AccessPolicy.cacheDuration).formatted())")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Approve for 3 days") {
                        policy.approve(Grant(request: request(credential),
                            expiresAt: credential.fetchedAt.addingTimeInterval(AccessPolicy.cacheDuration)))
                        notice = "Approved example-agent for repeated retrieval of \(credential.host), while unlocked, until cache expiry or revocation."
                    }.disabled(policy.grants.contains { $0.request == request(credential) && !$0.revoked && $0.expiresAt > Date() })
                    Button("Simulate request") {
                        let result = policy.evaluate(request(credential), fetchedAt: credential.fetchedAt,
                            now: Date(), monotonic: ProcessInfo.processInfo.systemUptime)
                        notice = "example-agent → \(credential.host): \(result.rawValue). No secret was released."
                    }
                }
            }
            if !policy.grants.isEmpty {
                Text("Grants").font(.headline)
                ForEach(policy.grants) { grant in
                    HStack {
                        Text("\(grant.request.client) · \(grant.uses) retrievals · \(grant.revoked ? "revoked" : "expires " + grant.expiresAt.formatted())")
                        Spacer()
                        Button("Revoke") { policy.revoke(grant.id) }.disabled(grant.revoked)
                    }.font(.caption)
                }
            }
            Text("Review history · current preview session only").font(.headline)
            List(policy.events.reversed()) { event in
                HStack {
                    Text(event.date.formatted(date: .omitted, time: .standard))
                    Text(event.client)
                    Text(event.credential.uuidString.prefix(8)).font(.system(.caption, design: .monospaced))
                    Spacer()
                    Text(event.decision.rawValue).foregroundStyle(event.decision == .allowed ? .green : .orange)
                }
            }.frame(minHeight: 100)
            Divider()
            HStack {
                Button("Verify Secure Enclave…") { confirmHardware = true }.disabled(testingHardware)
                Text(hardwareNotice).font(.caption).foregroundStyle(.secondary)
            }
            Text("Hardware verification uses a random synthetic payload, may prompt for Touch ID, and saves nothing. It does not unlock the demo or your existing vault.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .confirmationDialog("Run a hardware-only round trip? Touch ID may be requested.",
                            isPresented: $confirmHardware) {
            Button("Verify with synthetic data") { verifyHardware() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func request(_ credential: PreviewCredential) -> AccessRequest {
        AccessRequest(client: "example-agent", credential: credential.id,
                      destination: credential.host, operation: "read")
    }

    private func loadExample() {
        guard credentials.isEmpty else { notice = "Example already loaded; retention was not extended."; return }
        credentials.append(PreviewCredential(host: "example.org", account: "demo-account"))
        notice = "Loaded example.org / demo-account (synthetic). Cache lifetime: three days. No access granted."
    }

    private func verifyHardware() {
        testingHardware = true
        hardwareNotice = "Verifying… authorize the native prompt if shown."
        Task {
            let success = await Task.detached {
                do {
                    let payload = Data(UUID().uuidString.utf8)
                    return try EnclaveVault.open(EnclaveVault.seal(payload)) == payload
                } catch { return false }
            }.value
            hardwareNotice = success ? "Hardware round trip succeeded on this Mac."
                : "Verification failed or was canceled. No fallback used. Check provisioning and hardware."
            testingHardware = false
        }
    }
}
