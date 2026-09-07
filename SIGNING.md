# Silocleaner signing setup

Silocleaner is distributed directly, signed by a Silocleaner-controlled Apple
Developer team, and notarized. No Pearcleaner certificate, team ID, bundle ID,
or provisioning profile may be used.

## Identity inventory

| Component | Identifier |
| --- | --- |
| Main app | `com.lindemannm.Silocleaner` |
| App group | `group.com.lindemannm.Silocleaner` |
| Finder extension | `com.lindemannm.Silocleaner.FinderOpen` |
| Privileged helper | `com.lindemannm.Silocleaner.SilocleanerHelper` |
| Sentinel agent | `com.lindemannm.SilocleanerSentinel` |
| URL scheme | `silocleaner` |

Register these identifiers and the app group with the Silocleaner Apple
Developer team before producing a signed build. Enable the App Groups
capability for the main app and Finder extension. The helper and Sentinel use
their launchd association plists and do not receive the application-group
entitlement.

## Local configuration

Install a **Developer ID Application** certificate belonging to the
Silocleaner team. Then copy
`Silocleaner/Config/Signing.local.xcconfig.example` to
`Silocleaner/Config/Signing.local.xcconfig` and replace both placeholders. The
local file is ignored by Git. The project deliberately has no default team or
certificate: a normal signed archive cannot silently fall back to an upstream
or developer-machine identity.

Confirm the identity before archiving:

```sh
security find-identity -v -p codesigning
xcodebuild -project Silocleaner.xcodeproj -scheme 'Silocleaner Release' \
  -configuration Release -showBuildSettings | \
  rg 'CODE_SIGN_IDENTITY|CODE_SIGN_STYLE|DEVELOPMENT_TEAM'
```

For an unsigned development build, use `CODE_SIGNING_ALLOWED=NO`; do not
change the tracked signing configuration to make that build work.

## Release hand-off

Phase 4 owns notarization and fresh-machine installation evidence. Before
that phase can close, archive with the configured Developer ID identity and
verify the main app, Finder extension, Sentinel, and helper signatures and
entitlements as one bundle. In particular, verify that the helper's
designated-requirement check sees the final main-app bundle ID and the same
Silocleaner team ID; it rejects unsigned and mismatched clients by design.
