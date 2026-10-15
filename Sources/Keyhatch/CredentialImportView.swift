// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import KeyhatchCore

private typealias ImportViewState<Value> = SwiftUI.State<Value>

struct CredentialImportView: View {
    @ObservedObject var model: RealCredentialModel
    @Environment(\.dismiss) private var dismiss
    @ImportViewState private var host = ""
    @ImportViewState private var account = ""
    @ImportViewState private var secret = ""
    @ImportViewState private var fetchedAt: Date
    @ImportViewState private var expiresAt: Date
    @ImportViewState private var confirmedSourceTimes = false
    @ImportViewState private var submitting = false
    @ImportViewState private var attemptedImport = false
    @ImportViewState private var importTask: Task<Void, Never>?
    @ImportViewState private var importID: UUID?

    init(model: RealCredentialModel) {
        self.model = model
        let now = Date()
        _fetchedAt = ImportViewState(initialValue: now)
        _expiresAt = ImportViewState(initialValue: now.addingTimeInterval(AccessPolicy.cacheDuration))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import one credential").font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Enter only the credential you chose to share. Keyhatch encrypts it on this Mac; importing does not approve client access or change the source password store.")
            Form {
                TextField("Host (lowercase, no scheme or path)", text: $host)
                    .autocorrectionDisabled()
                TextField("Account", text: $account).autocorrectionDisabled()
                SecureField("Password or token", text: $secret)
                DatePicker("Originally retrieved", selection: $fetchedAt,
                           displayedComponents: [.date, .hourAndMinute])
                DatePicker("Original cache expiry", selection: $expiresAt,
                           displayedComponents: [.date, .hourAndMinute])
                DisclosureGroup("Exact source timestamps (Unix seconds)") {
                    TextField("Originally retrieved", value: Binding(
                        get: { fetchedAt.timeIntervalSince1970 },
                        set: { fetchedAt = Date(timeIntervalSince1970: $0) }),
                        format: .number.grouping(.never).precision(.fractionLength(0...6)))
                    TextField("Original cache expiry", value: Binding(
                        get: { expiresAt.timeIntervalSince1970 },
                        set: { expiresAt = Date(timeIntervalSince1970: $0) }),
                        format: .number.grouping(.never).precision(.fractionLength(0...6)))
                }
            }.disabled(submitting)
            Text("Defaults are now and three days from now, suitable only for a freshly retrieved credential. For a cached credential, enter its original retrieval and expiry times. Importing must not restart its lifetime. Expiry must be within three days of retrieval and may be earlier.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("I confirm these preserve the credential’s original source times.",
                   isOn: $confirmedSourceTimes)
                .disabled(submitting)
            if attemptedImport || submitting {
                Text(model.status).font(.callout).accessibilityLabel("Import status: \(model.status)")
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    importTask?.cancel()
                    if let importID { model.cancelImport(importID) }
                    secret = ""
                    dismiss()
                }.keyboardShortcut(.cancelAction)
                Spacer()
                if submitting { ProgressView().controlSize(.small) }
                Button("Encrypt and import") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(submitting || model.busy || model.unlocked || !confirmedSourceTimes ||
                              host.isEmpty || account.isEmpty || secret.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onChange(of: fetchedAt) { _, _ in confirmedSourceTimes = false }
        .onChange(of: expiresAt) { _, _ in confirmedSourceTimes = false }
        .onDisappear {
            importTask?.cancel()
            secret = ""
            if let importID { model.cancelImport(importID) }
        }
    }

    private func submit() {
        guard confirmedSourceTimes, !submitting else { return }
        submitting = true
        attemptedImport = true
        let selectedSecret = secret
        let operationID = UUID()
        importID = operationID
        secret = ""
        importTask = Task {
            let success = await model.importCredential(host: host, account: account,
                secret: selectedSecret, fetchedAt: fetchedAt, expiresAt: expiresAt,
                operationID: operationID)
            importID = nil
            submitting = false
            if success { dismiss() }
        }
    }
}
