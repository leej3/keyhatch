# Keyhatch support

Keyhatch is an experimental macOS app for selectively sharing credentials with
local tools.
Public distribution is pending validation and review.

## Get help

Email [support@pythonaisolutions.com](mailto:support@pythonaisolutions.com) for
app support, privacy questions, or private security reports.
For general questions or reproducible non-security bugs, you can also use the
[Keyhatch issue tracker](https://github.com/leej3/keyhatch/issues).
Include the app version, macOS version, distribution route, and steps using
synthetic data.
Never attach passwords, tokens, encrypted credential files, private keys,
provisioning profiles, or personal access history.

Do not report security vulnerabilities publicly; see
[security reporting](../SECURITY.md).

## Start using the app

1. Import only a credential you intend to share.
   Preserve its original retrieval and expiry times; importing does not renew a
   cached credential.
2. Select the encrypted record and unlock it with Touch ID.
3. Approve the local CLI when ready to allow retrieval.
   Other tools under your login can invoke that approved client.
4. Lock or revoke approval to stop future retrieval.
   Rotate the credential at its issuing service if a recipient's copy must be
   invalidated.

App Store installations use a separate private container.
They do not implicitly migrate records from a direct installation.

## Command line setup

Keep the helper inside the signed app.
For a Store installation in `/Applications/Keyhatch.app`, run:

```sh
"/Applications/Keyhatch.app/Contents/Helpers/KeyhatchClient.app/Contents/MacOS/keyhatch" verify-installation
"/Applications/Keyhatch.app/Contents/Helpers/KeyhatchClient.app/Contents/MacOS/keyhatch" status
```

For a direct build, replace the helper path with
`/Applications/Keyhatch.app/Contents/MacOS/KeyhatchCLI`.
The Store client does not support `run`; it supports status, lock, scoped checks
and Git credential handoff.
Neither variant automatically changes Git settings.

After an update, unlock and approve the new client build if prompted.
A stored approval for an older executable does not authorize its replacement.

## Recovery and deletion

Keyhatch is a cache, not your only copy of a credential.
Biometric enrollment changes or loss of device-bound key material can make
cached data inaccessible.
Retrieve a replacement from your original source; do not overwrite an existing
encrypted record to repair an unlock failure.

While locked, select a record and choose **Delete selected file** to remove its
local encrypted data and history.
Deletion does not erase backups, the original source, recipient copies, or
remote sessions.

Read the [privacy policy](../Resources/Privacy.md) and
[security limits](../SECURITY.md) before sharing a real credential.
