# Keyhatch Privacy

Last updated October 15, 2026.

## Your selected credentials stay on this Mac

Keyhatch stores only the credentials you choose to import, including their host,
account, secret, original expiry, approval, and recent access history.
It encrypts those records locally.
The App Store build stores them in its macOS app container, separately from the
direct-distribution build’s private storage.
Unlocking uses macOS authentication and a Secure Enclave key.
Keyhatch does not receive or store your fingerprint or other biometric data.

## No analytics or developer-operated cloud

Keyhatch has no analytics, advertising, tracking, or developer-operated account
or cloud service.
It does not upload your vault or access history to the developer. macOS backup,
diagnostics, and device-management features are controlled separately by your
system settings.

## Sharing is an explicit product feature

When you approve credential retrieval, the approved local client can receive the
selected secret while the session and approval remain valid.
Other tools running under your account may invoke that client.
A recipient can retain, use, or transmit a disclosed credential under its own
policies.
Locking, expiry, revocation, or deletion in Keyhatch cannot retract those copies
or revoke existing remote sessions.

## Optional network request

If you confirm the read-only Forgejo identity check, Keyhatch sends the selected
account and credential over HTTPS to the selected host at `/api/v1/user`.
The host also receives ordinary connection information such as your IP address.
Redirects are refused, and the request uses no persistent cookie or response
cache.
The host controls its own processing and retention.
Keyhatch does not perform this check automatically.

## Retention and your controls

Credential access is limited to the source expiry, at most three days from
retrieval.
An unlocked session lasts at most five hours.
Each encrypted record keeps its latest 200 local history events; older events
are dropped when new events are recorded.
Expiry stops access but does not automatically erase the encrypted record.
Local records remain until deleted.

Lock or revoke access in the credential window.
While locked, select an encrypted file and choose **Delete selected file** to
remove that local record and its history.
Deletion does not remove the original credential from its source.
Backups and recipient copies require separate removal.
Revoke or rotate a credential at its issuing service if you need to invalidate
it.

## About this policy

This policy describes Keyhatch itself.
Tools receiving credentials, credential sources, and remote services have their
own privacy practices.
This policy is available in the app under **Help → Keyhatch Privacy** without
importing or unlocking a credential.
