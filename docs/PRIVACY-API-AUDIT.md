# Privacy API and collection audit

Reviewed October 15, 2026.
This is a source and package inspection, not an Apple submission result or a
legal determination.
No credentials were read, no network identity check was made, and no biometric
operation was performed.

## Scope and result

Reviewed every Swift file under `Sources`, the Swift package manifest, generated
Xcode
target/resource configuration, direct packaging, the in-app privacy text, and `Resources/Privacy.md`.
The app has no third-party package dependencies or embedded third-party SDKs.
Apple's system frameworks and Swift runtime supply the remaining functionality.

The current Store manifest accurately covers the two observed required-reason
API categories.
No additional category or reason was identified, so
`Resources/PrivacyInfo.xcprivacy` is unchanged.
Its tracking flag is false, and its tracking-domain and collected-data arrays
are empty.
Both the Store broker and independently sandboxed client receive their own copy.

## API evidence

| Category | Source and purpose | Declaration |
| --- | --- | --- |
| File timestamp | `CredentialFile.swift` uses `fstat` and `fstatat` to reject unsafe ownership, permissions, file types, hard links and excessive file sizes. `LocalIPC.swift` uses `fstat` and `lstat` to validate its socket and lock. Store paths are inside the broker's app container or the entitled App Group. No file timestamps are read from the returned structures. | `NSPrivacyAccessedAPICategoryFileTimestamp`, `C617.1` |
| System boot time | `LocalIPC.swift` reads `ProcessInfo.systemUptime` to bound frame transfers. The synthetic dashboard in `KeyhatchApp.swift` also uses uptime for elapsed session checks. Real credential expiry uses process-relative `ContinuousClock` durations in `SessionLifetime.swift`. Neither clock value is included in network requests or credential responses. | `NSPrivacyAccessedAPICategorySystemBootTime`, `35F9.1` |
| Disk space | No `statfs`, `statvfs`, available-capacity, total-capacity or filesystem-size query found. A regular file's `st_size` belongs to the file metadata category above. | None |
| Active keyboards | No keyboard-enumeration API found. SwiftUI keyboard shortcuts do not enumerate active input modes. | None |
| User defaults | No `UserDefaults`, `CFPreferences`, `AppStorage` or `SceneStorage` access found in application code. | None |

Apple's current reason list includes the entire `stat` family above even when
the caller needs non-time metadata.
`C617.1` covers
app/container metadata; `35F9.1` covers elapsed-event measurements and timers. `ContinuousClock` itself is not named in the current list; the existing uptime calls independently require the latter declaration. No raw boot time is persisted or transmitted. See Apple's [API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

`BundledDeployment.legacy` also contains a bounded `fstat` check on a legacy
deployment manifest.
A correctly packaged Store executable resolves its sealed containing app and
does not enter this standalone ad-hoc compatibility path.
The Store client never falls back to a guessed container or legacy credential
directory.

The Developer ID variant intentionally uses `~/.local/state/keyhatch`, which is
not an App Sandbox container.
The shared `C617.1` declaration must not be used to claim that the direct
variant's entire legacy filesystem path is covered by that reason.
Apple's current required-reason overview names iOS, iPadOS, tvOS, visionOS and
watchOS; the plist key is also available on macOS.
Keep the manifest in macOS packages, but distinguish the Store container
rationale from the direct path.
Do not invent document-picker consent or add an unrelated reason to hide this
distinction.
Reassess if Apple expands the enforcement scope or the storage design changes.
See Apple's
[required-reason API guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

## Target and package coverage

| Shipped code | Privacy resource location | Inspection |
| --- | --- | --- |
| Direct broker, CLI and importer | Outer app `Contents/Resources/PrivacyInfo.xcprivacy`; all three executables belong to that bundle | Present and parseable |
| Store broker | Outer app `Contents/Resources/PrivacyInfo.xcprivacy` | Present and parseable |
| Store client | Nested `KeyhatchClient.app/Contents/Resources/PrivacyInfo.xcprivacy` | Present and parseable |
| Core library | Statically linked into the executable targets; not shipped as a separate SDK bundle | Covered by each containing bundle |

Inspected both architectures with `nm -u -arch arm64` and `nm -u -arch x86_64`
in the icon-era Developer ID package `direct-jcwy5gjn` and manually provisioned
Store archive `build.j9EPAi`.
All ten executable/architecture inspections succeeded.
Their imported file metadata symbols matched the source inventory.
The real-session clock symbols were present in the broker.
Direct Swift package builds also retain shared-core symbols in the helpers; the
common manifest covers these.

The parent also repeated all ten inspections and manifest parsing on the final
0.1.0 build 2 direct/Store packages after adding support contact text and the
nonblocking file-open fix.
All passed.

This symbol check corroborates source inspection; it does not enumerate every
Objective-C selector or every internal system-framework operation.
It is not a substitute for Apple upload validation.
Regenerate and inspect the final signed artifacts after changing sources or
dependencies.

## App Store privacy answers

The source supports
**no data collected by the developer or integrated third-party partners**, and
**no tracking**.
This conclusion is narrower than "no data ever leaves the device."

- Credentials, host/account identifiers, original expiry, client approvals and
  the latest 200 history entries are stored in local encrypted records.
  No developer backend, analytics endpoint, advertising SDK, crash-upload client
  or remote configuration service is present.
- Unlock uses LocalAuthentication and the Secure Enclave.
  Keyhatch does not receive biometric templates or fingerprint data.
- The user's explicit Forgejo identity check sends HTTP Basic authentication to
  the selected HTTPS host at `/api/v1/user`.
  The host sees the account, credential and ordinary network information,
  including the IP address.
  The ephemeral session disables persistent credentials, cookies and response
  caching, and refuses redirects.
  The destination's retention is outside Keyhatch's control.
  Source review does not prove that every destination avoids logging requests.
- The approved local client can disclose the credential to Git or, in the direct
  variant, a selected child process.
  Recipient retention and subsequent transmission remain possible.
  The policy describes this explicitly.
- macOS diagnostics, backups and management are controlled separately.
  No source claim here establishes their absence or deletes their copies.

Apple's label definition concerns data transmitted off-device for retention by
the developer or its integrated partners.
The user-selected services and external credential recipients are not developer
analytics partners in the current architecture.
This interpretation supports the empty collection array; it must be revisited if
Keyhatch adds a hosted service, integrated service partner, analytics or support
upload.
The empty array does not waive the obligation to disclose credential sharing
clearly.
See Apple's
[App Store privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

The hostable policy and accessible in-app policy already describe local storage,
optional HTTPS requests, recipient copies, deletion limits and retention.
App Store Connect answers still require the publisher to confirm the final
service arrangements and provide a public privacy-policy URL before submission.
This audit does not publish those answers or assert Store acceptance.

## Recheck triggers

Revisit this inventory when adding a dependency, persistent preferences,
filesystem APIs, a new executable or extension, telemetry, network functionality
or a different storage location.
Check every shipped bundle's manifest after packaging.
Keep the hostable and in-app policies aligned with actual behavior.
