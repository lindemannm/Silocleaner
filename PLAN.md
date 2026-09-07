# Silocleaner plan

## Purpose and current baseline

Silocleaner is a new fork of Pearcleaner: a native macOS application cleaner
with a Finder extension, login-item Sentinel, command-line interface, updater,
and a privileged helper. The checked-out baseline is `7724df7` on `main`.

The SEC-01 generic-command endpoint has been removed. The remaining phases are
not implemented yet.

## Release rule

**Silocleaner must not be distributed, notarized, or encouraged to install its
privileged helper until Phases 1--3 are complete and their release gates pass.**

The first objective is a safe privilege boundary, not a cosmetic rename.

## Tracked risks

| ID | Priority | Finding | Primary location |
| --- | --- | --- | --- |
| SEC-01 | Critical | Root helper accepts arbitrary Bash strings over XPC. | `PearcleanerHelper/main.swift` |
| SEC-02 | Critical | Helper caller check compares certificate chains rather than enforcing Silocleaner's designated requirement. | `PearcleanerHelper/CodesignCheck.swift` |
| SEC-03 | High | Privileged shell commands interpolate untrusted/path-derived values. | `Pearcleaner/Logic/Utilities.swift`, uninstaller and updater code |
| ID-01 | Resolved | Targets, app group, service labels, URL scheme, updater origin, and user-facing branding have been migrated to Silocleaner. Final Apple signing credentials remain a release gate. | project, plists, entitlements, Swift sources |
| SEC-04 | Resolved | Finder extension now observes only standard application folders and has no filesystem temporary exception. | `FinderOpen/FinderOpen.entitlements`, `FinderOpen/FinderOpen.swift` |
| SEC-05 | Medium | The app caches a sudo password in Keychain without explicit access controls. | `Pearcleaner/Logic/KeychainPasswordManager.swift` |
| SUP-01 | Resolved | `AlinFoundation` is pinned to immutable revision `f61241c2ea1856ef41cbfc965afe9d756121456f`. | `Silocleaner.xcodeproj/project.pbxproj`, `Silocleaner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |
| REL-01 | Resolved | Private PackageKit/CommerceKit/StoreFoundation build integration was removed. Package receipts use public `pkgutil`; App Store discovery uses the public lookup API and installation is handed to App Store. | `Silocleaner.xcodeproj/project.pbxproj`, `Silocleaner/Logic/PKG/PKGManager.swift` |
| QLT-01 | Medium | No unit/UI test targets currently exist. | Xcode project |

## Phase 0 -- establish a reproducible baseline

Status: **complete**

- [x] Record supported macOS versions and target release channel (Developer ID
  notarized distribution, App Store, or both). The current project targets
  macOS 13.0; the distribution decision governs entitlements and private API
  removal. See `BASELINE.md`.
- [x] Add an `upstream` Git remote for `alienator88/Pearcleaner`; document the
  intended update/merge policy for the fork. See `BASELINE.md`.
- [x] Build all current targets without signing in a clean, isolated derived
  data directory, then record the exact Xcode/macOS versions and failures. See
  `BASELINE.md`.
- [x] Inventory every destructive operation and classify it as: unprivileged
  user file, protected user file, system file, package receipt, launch item,
  Homebrew item, app thinning, or application update. See `BASELINE.md`.
- [x] Decide which existing capabilities are in the first Silocleaner release.
  Features relying on private frameworks should be disabled or removed unless a
  supported public-API design is agreed. See `BASELINE.md`.

Exit criteria:

- [x] A clean checkout can resolve dependencies and build the selected supported
  targets.
- [x] Every privilege-requiring operation has an owner, input source, and expected
  filesystem scope documented.

## Phase 1 -- redesign the privileged helper

Status: **complete**

- [x] Remove `runCommand(command:)` from `HelperToolProtocol`; a root XPC
  service must never expose a generic shell execution endpoint.
- [x] Define the sole approved helper operation: a secure, typed request to
  thin a root-owned application bundle that is a direct child of `/Applications`.
  Each request contains structured data, not command text.
- [x] Canonicalize the accepted bundle path; reject traversal and symlink
  components; require root ownership and the `/Applications` allowlist; and
  re-check the bundle identity immediately before every privileged mutation.
- [x] Use Foundation and low-level file-descriptor APIs only. The helper has
  no shell or subprocess invocation.
- [x] Replace certificate-array equality with `SecCodeCheckValidity` against a
  designated requirement anchored to the helper's Developer ID team and exact
  main-app identifier. Unsigned/ad-hoc helpers and clients fail closed. The
  requirement derives the main-app identifier from the helper identity, so the
  Phase 3 Silocleaner identity rename remains a signing configuration change.
- [x] Add serialized request handling, connection invalidation, a bounded path
  request, and path-free audit logging.
- [x] Add helper-focused tests for caller validation, rejected operation names,
  path traversal, symlink handling, quote/metacharacter paths, allowlist
  boundaries, and concurrent requests.

Exit criteria:

- No helper method accepts arbitrary commands or shell source.
- A process signed with another identity, an unsigned process, and a process
  with a mismatched bundle identifier are all rejected.
- Tests show that malformed paths and shell metacharacters cannot cause an
  operation outside the declared scope.

## Phase 2 -- eliminate unsafe command construction and password caching

Status: **not started**

- [ ] Find every `Process(... "-c" ...)`, `runSUCommand`,
  `performPrivilegedCommands`, and string-built shell command.
- [ ] Replace path/name interpolation with typed APIs or correctly delimited
  `Process` arguments. This includes CLI symlink management, undo/restore,
  launch-item management, package cleanup, Homebrew cleanup, and iOS wrapper
  replacement.
- [ ] Remove the sudo-password cache where the privileged helper replaces it.
  If a separate authentication path remains essential, require a documented
  security design and explicit Keychain access control before retaining it.
- [ ] Make temporary data use uniquely created directories with restrictive
  permissions; remove broad startup deletion of every `/tmp/pearcleaner*`
  entry.
- [ ] Ensure every destructive action has a clear preview/confirmation and an
  accurate post-operation result.

Exit criteria:

- Static review finds no generic root-shell pathway and no unescaped
  path-derived shell construction.
- Password material is not retained beyond an approved, documented design.
- Temporary-file cleanup cannot delete unrelated same-user files by prefix.

## Phase 3 -- establish Silocleaner identity and signing

Status: **in progress**

Identity selected for this fork: `com.lindemannm.Silocleaner`, with
`group.com.lindemannm.Silocleaner`, the `silocleaner://` URL scheme,
`com.lindemannm.Silocleaner.SilocleanerHelper`, and
`com.lindemannm.SilocleanerSentinel`. Upstream team IDs and provisioning
profiles have been removed; a Silocleaner-controlled Apple Developer team must
be configured before a signed release.

- [x] Choose final bundle-ID namespace, app group, XPC/helper labels, Finder
  extension identifier, Sentinel identifier, URL scheme, CLI name, and
  support/update URLs.
- [x] Rename targets, product names, directories, schemes, resources, source
  symbols, deep-link notification names, and user-visible text coherently.
- [ ] Replace all upstream Apple team/profile/signing settings with the
  Silocleaner signing identity. Do not reuse Pearcleaner identifiers or
  provisioning profiles.
- [ ] Create new app-group and service entitlements under the final identity;
  add migration only where retaining a user's old settings is intentional and
  safe.
- [ ] Update helper and Sentinel launch plist associations and Mach-service
  labels together with their client code.
- [x] Replace updater ownership and release links with Silocleaner-controlled
  infrastructure; do not ship an updater pointed at Pearcleaner.
- [x] Rewrite README, preserve license attribution/obligations, update funding details, issue
  templates, privacy/support links, release notes, and all remaining branding.

Exit criteria:

- `rg -i 'pearcleaner|alienator88|pear://'` produces only intentional
  attribution/migration references, each documented.
- A fresh signed install registers only Silocleaner services and does not
  collide with a Pearcleaner installation.
- Helper caller validation uses the final released identity.

## Phase 4 -- entitlement and distribution hardening

Status: **in progress**

- [x] Re-evaluate the Finder extension's `/` read exception. The extension
  observes only `/Applications`, `/System/Applications`, and
  `~/Applications`, where Finder Sync can supply selected-item URLs. It does
  not inspect or mutate selected apps, so no filesystem temporary exception or
  security-scoped bookmark is required. Apps elsewhere intentionally use the
  main app or its Services entry point instead.
- [ ] Audit all targets' entitlements against their actual requirements;
  remove unused app groups and temporary exceptions.
- [x] Replace private `PackageKit`, `CommerceKit`, and `StoreFoundation`
  dependencies with public APIs, or omit the affected features from a
  notarized release.
- [x] Remove absolute paths from `OTHER_SWIFT_FLAGS` and make all module maps
  project-relative and source-controlled where genuinely required.
- [ ] Set a supported signing/notarization workflow with verification of the
  app, Finder extension, Sentinel, and privileged helper as a single bundle.

Exit criteria:

- Release configuration has no upstream machine paths, stale identifiers, or
  unreviewed broad entitlements.
- The selected distribution path completes codesign verification, notarization,
  and a fresh-machine install test.

## Phase 5 -- dependencies, tests, and release confidence

Status: **not started**

- [ ] Pin every dependency to an immutable tag or revision. Fork/vend the
  required AlinFoundation revision if its maintenance or trust model is not
  suitable for Silocleaner.
- [ ] Add CI that resolves dependencies from the lockfile, builds Debug and
  Release without developer-local paths, runs tests, and reports failures.
- [ ] Add unit tests for file-scope classification, deep-link parsing, command
  argument construction, temporary file lifecycle, and destructive-operation
  previews.
- [ ] Add integration/UI tests for Finder invocation, Sentinel behaviour,
  helper installation/approval states, protected/unprotected deletion, undo,
  and a conflicting Pearcleaner install.
- [ ] Test on a clean macOS 13+ user account with Full Disk Access absent and
  present, both Apple silicon and Intel where supported.
- [ ] Perform an external security review before the first public release,
  concentrating on helper authorization, filesystem races, and every feature
  that mutates system-owned state.

Exit criteria:

- CI is green from a fresh checkout.
- Tests execute, rather than merely build, and cover the new helper contract.
- Fresh-install, upgrade, uninstall, and Pearcleaner-coexistence checks have
  recorded evidence.

## Suggested first implementation slice

1. Complete Phase 0's operation inventory and release-channel decision.
2. Implement and test the Phase 1 typed helper boundary.
3. Carry out the Phase 3 identity/signing change in the same coherent slice,
   because the helper's designated requirement depends on the final identity.
4. Only then rename the wider UI and begin feature work.

## Verification record

| Check | Result | Notes |
| --- | --- | --- |
| Clone and Git status | Passed | Clean `main` at `2527435` before the Phase 0 documentation change. |
| Dependency resolution | Passed | Sparkle 2.8.0, ArgumentParser 1.6.1, AlinFoundation `f61241c`. |
| Full build | Passed | Unsigned, isolated Debug and Release builds completed with Xcode 26.6 on macOS 26.6.2; see `BASELINE.md`. |
| Automated tests | Pending | No test target or test source files were found in the baseline project. |
