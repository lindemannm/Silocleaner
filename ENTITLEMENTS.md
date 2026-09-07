# Entitlement and release-bundle policy

Silocleaner is a Developer ID, direct-distribution app. It uses hardened
runtime on every shipped executable and requests only the entitlements below.
No target has a temporary filesystem exception, Apple-event exception, disabled
library validation, debugger entitlement, or network/server entitlement.

| Component | Required entitlement(s) | Reason |
| --- | --- | --- |
| Silocleaner app | `com.apple.security.application-groups = group.com.lindemannm.Silocleaner` | Shares the Finder-menu preference with the Finder extension. The app is deliberately not sandboxed because its selected functionality manages user files and invokes approved system services. |
| FinderOpen extension | `com.apple.security.app-sandbox`, `com.apple.security.application-groups = group.com.lindemannm.Silocleaner` | Finder Sync extensions must be sandboxed; the group carries only the shared preference. Finder supplies selected application URLs. |
| SilocleanerHelper | none | The root helper receives only its typed XPC request and must not gain app-container or app-group access. |
| SilocleanerSentinel | none | The login-item agent watches the current user's Trash and has no shared-container requirement. |

`Shared/AppGroupDefaults.swift` is compiled into the app and Finder extension
only; its `showAppIconInMenu` preference is the sole app-group consumer.

## Release workflow

1. Register the main app, Finder extension, and app group with the
   Silocleaner Apple Developer team; enable App Groups for the app and Finder
   extension. Install that team's **Developer ID Application** certificate.
2. Create the ignored `Silocleaner/Config/Signing.local.xcconfig` from its
   checked-in example. Confirm the resolved identity with the command in
   `SIGNING.md`. Do not use automatic signing or an Apple Development
   certificate for the release archive.
3. Store notarization credentials in a local keychain profile, for example:

   ```sh
   xcrun notarytool store-credentials silocleaner-notary
   ```

4. Run the release gate, passing that profile and an empty, absolute export
   directory:

   ```sh
   ./Scripts/notarize-release.sh silocleaner-notary /absolute/path/to/export
   ```

   It archives the `Silocleaner Release` scheme, verifies the main app,
   Finder extension, Sentinel and helper independently, requires their signing
   team to match, submits a ZIP to notarization, staples the ticket, runs
   Gatekeeper assessment, and verifies the exact component set again. The
   verification script intentionally does not use `codesign --deep`.

5. On a clean macOS 13+ user account, copy the stapled app to `/Applications`,
   open it via Finder, confirm Gatekeeper accepts it, enable the Finder
   extension, enable Sentinel and (only after the Phase 1--3 gates) the helper
   in Login Items, then exercise the Finder command, a Sentinel notification,
   and helper thinning of a root-owned app in `/Applications`. Record the
   archive hash, notarization submission ID, macOS version, and results.

The automated checks require a configured Developer ID identity and therefore
cannot be substituted by unsigned development builds.
