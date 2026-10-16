# Keyhatch App Review draft

These notes describe the Store candidate.
Complete the owner contact fields in App Store Connect and finish the deferred
device tests before submission.
No developer account or remote service login is needed to use the app.

## Purpose and boundaries

Keyhatch selectively shares user-imported credentials with its bundled local
client.
It does not read Apple Passwords automatically, bulk-import a password store,
install a daemon, or download executable code.
The Store client cannot launch arbitrary child commands.
Source is available under MPL-2.0.

The broker and nested client have separate App Sandbox entitlements and
provisioning profiles.
Encrypted credentials stay in the broker's private container.
The App Group holds only socket and locking state.
Both endpoints validate the running peer against the current signed bundle.
Approval authorizes that exact client build, not an individual agent or
conversation.

All agents under the same user may invoke the approved client.
Disclosed secrets can be retained.
Lock and revocation stop future retrieval; they cannot revoke recipient copies
or remote sessions.
These limits appear in the UI and policy.

## Hardware requirements

Credential operations require a Secure Enclave-capable Mac and enrolled Touch
ID.
There is no software-key or password fallback.
Use a supported physical Mac for the full test.
An Apple silicon Mac with working Touch ID is the tested hardware family.
Intel runtime and the minimum supported macOS version still need validation;
universal binary compilation alone is not runtime evidence.

## Synthetic review walkthrough

Install through Apple's distribution workflow into `/Applications/Keyhatch.app`.
Do not move the nested client out of the app or run it from an archive
directory.

1. Open Keyhatch.
   Help → Keyhatch Privacy is available without authentication.
2. Choose **Import one credential**.
   Use host `example.org`, account `reviewer`, and a newly invented synthetic
   token that is not valid on any service.
   For this fresh synthetic value, keep the initial retrieval and expiry times,
   confirm them, then choose **Encrypt and import**.
3. Unlock the selected record with Touch ID.
   Before CLI approval, retrieval must fail.
   Choose **Approve local CLI** and review the disclosure.
4. In Terminal, invoke the nested client using the commands below.
   The matching Git request now returns only the synthetic token.
   A different host is denied.
5. Revoke CLI access and verify denial.
   Lock, then cancel a subsequent Touch ID request and verify denial again.
   While locked, delete the synthetic record.
6. The optional Forgejo identity check needs a real compatible server and an
   explicitly selected credential; it is unnecessary for this local walkthrough.
   Do not send the synthetic example.org token to a remote endpoint.

```sh
client='/Applications/Keyhatch.app/Contents/Helpers/KeyhatchClient.app/Contents/MacOS/keyhatch'
"$client" verify-installation
"$client" status
printf 'protocol=https\nhost=example.org\nusername=reviewer\n\n' |
  "$client" git --host example.org --username reviewer get
"$client" lock
```

The token in this procedure is synthetic.
Never use a real password in captured terminal output or review attachments.
A reproducible biometric walkthrough is provided here; running it is deferred at
the owner's request.

## Submission decisions still required

- Review contact name, email and telephone number (enter privately in App Store
  Connect) and final URLs.
  Public support and private security reports use support@pythonaisolutions.com;
  confirm that the inbox is monitored.
- Price, territories, ownership/copyright declaration, age-rating questionnaire,
  and applicable trader, banking, tax and agreement steps.
- Owner confirmation of the privacy answers and encryption export declaration.
  CryptoKit/Security provide AES-GCM, HKDF-SHA256 and P-256; no custom cipher or
  bundled third-party cryptographic library is shipped.
  No export exemption is asserted by this draft.
- Manual release after approval, rather than automatic publication.

Apple references:
[complete review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review),
[version metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/),
[encryption declarations](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).
