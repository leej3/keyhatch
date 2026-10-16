# Keyhatch screenshot preparation

The signed Store candidate was inspected in a disposable app under
`/Applications`, using its empty sandbox and no real credentials.
The main window, selective import form and privacy window are reachable without
Touch ID.
Incomplete import stays disabled, and cancel returns to the empty locked state.
The privacy window includes the support address without requiring unlock.

Screenshot files are pending: native capture to disk was blocked by macOS Screen
Recording permission during preparation.
No mock screenshot is supplied as evidence of the running app.
Enable capture permission and use the final candidate to finish the assets
below.

## Capture list

1. **Select what to share**: empty locked Credentials window with import
   control.
2. **Import one credential**: import form with `example.org` and `reviewer`;
   keep the secret empty, do not submit, and avoid personal accounts or record
   IDs.
3. **Privacy and control**: Help → Keyhatch Privacy, showing sharing and
   retention disclosures.
   Include the contact section in an additional capture if useful.
4. **Approval and history**, later: use only a newly created synthetic record
   after the owner resumes biometric testing.
   Do not substitute the synthetic policy demo for the Store credential UI,
   because that tab is not shipped in the Store app.

Apple accepts Mac screenshots at 1280×800, 1440×900, 2560×1600 or 2880×1800, all
16:10.
Use at least one genuine app screenshot, retain a consistent size, and visually
check every export for clipped controls, readable text and unintended personal
information.
Keep raw captures alongside any presentation assets until review is complete.
Final files should be PNG or JPEG.

Source:
[Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
