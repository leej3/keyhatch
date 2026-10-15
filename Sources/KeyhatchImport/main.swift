// SPDX-License-Identifier: MPL-2.0
import Foundation
import Darwin
import KeyhatchCore

// Generic private-pipe importer; no password-manager installation/configuration.
// The caller must provide exactly one authorized credential, never an entire vault.
do {
    try disableCoreDumps()
    guard CommandLine.arguments.count == 1, isatty(STDIN_FILENO) == 0 else {
        throw CredentialError.invalidRecord
    }
    var input = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
        input.append(chunk)
        guard input.count <= 131072 else { throw CredentialError.invalidRecord }
    }
    guard !input.isEmpty, input.count <= 131072 else { throw CredentialError.invalidRecord }
    var record = try JSONDecoder().decode(CredentialRecord.self, from: input)
    try record.validate()
    record.history = []
    record.brokerApproval = nil
    record.record("Imported one selected credential; no agent access granted")
    let envelope = try EnclaveVault.seal(JSONEncoder().encode(record))
    let files = try CredentialFiles()
    let name = try files.create(envelope)
    print("Encrypted credential created: \(files.root.appendingPathComponent(name).path)")
    print("Open Keyhatch → Real credential test → Refresh files → Unlock selected file.")
} catch {
    // Do not echo input, error descriptions, or credential fields.
    FileHandle.standardError.write(Data("Import failed; no plaintext was written. Existing files were not replaced.\n".utf8))
    exit(1)
}
