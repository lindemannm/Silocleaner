# Silocleaner plan

## Purpose and current baseline

Silocleaner is a new fork of Pearcleaner: a native macOS application cleaner
with a Finder extension, login-item Sentinel, command-line interface, updater,
and a privileged helper. The checked-out baseline is `7724df7` on `main`.

The privilege-boundary, command-construction, identity, entitlement, and
release-automation implementation work is complete. The remaining work is
targeted hardening plus evidence from a signed distribution, real installations,
and an independent review; it must not be inferred from unsigned builds or the
package-level tests.

## Release rule

**Silocleaner must not be distributed, notarized, or encouraged to install its
privileged helper until Phases 1--3 are complete and their release gates pass.**

The first objective is a safe privilege boundary, not a cosmetic rename.

## Tracked risks

| ID | Priority | Finding | Primary location |
| --- | --- | --- | --- |
| SEC-01 | Resolved | The root helper exposes only a typed bundle-thinning request; it has no generic shell endpoint. | `SilocleanerHelper/HelperToolProtocol.swift`, `SilocleanerHelper/PrivilegedBundleThinner.swift` |
| SEC-02 | Resolved in code; signed-release evidence pending | Helper authorization uses a designated requirement. A Developer ID-signed client/helper pair must still prove it in the release matrix. | `SilocleanerHelper/CodesignCheck.swift`, `RELEASE-VALIDATION.md` |
| SEC-03 | Resolved | Destructive and privileged operations pass discrete `Process` arguments, and subprocesses use a direct allowlisted environment without launching a user shell. | `Silocleaner/Logic/Utilities.swift`, `Silocleaner/Logic/ProcessEnv.swift`, `Shared/UserProcessEnvironment.swift` |
| ID-01 | Resolved | Targets, app group, service labels, URL scheme, updater origin, and user-facing branding have been migrated to Silocleaner. Final Apple signing credentials remain a release gate. | project, plists, entitlements, Swift sources |
| SEC-04 | Resolved | Finder extension observes only standard application folders, validates exactly one selected `.app`, and emits a safely encoded deep link that the app revalidates. | `FinderOpen/FinderOpen.entitlements`, `FinderOpen/FinderOpen.swift`, `Shared/FinderInvocation.swift` |
| SEC-05 | Resolved | The Keychain password cache was removed. `SUDO_ASKPASS` requests a password for the immediate operation and does not persist it. | `Silocleaner/Logic/CLI.swift`, `Silocleaner/Resources/askpass.sh` |
| SUP-01 | Resolved | `AlinFoundation` is pinned to immutable revision `f61241c2ea1856ef41cbfc965afe9d756121456f`. | `Silocleaner.xcodeproj/project.pbxproj`, `Silocleaner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |
| REL-01 | Resolved | Private PackageKit/CommerceKit/StoreFoundation build integration was removed. Package receipts use public `pkgutil`; App Store discovery uses the public lookup API and installation is handed to App Store. | `Silocleaner.xcodeproj/project.pbxproj`, `Silocleaner/Logic/PKG/PKGManager.swift` |
| QLT-01 | Partially resolved | A SwiftPM suite exercises helper-security and core safety contracts; Xcode integration/UI tests and physical-install evidence remain absent. | `Package.swift`, `HelperSecurityTests`, `CoreTests`, `RELEASE-VALIDATION.md` |

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

Status: **complete**

- [x] Find every shell `Process(... "-c" ...)`, `runSUCommand`,
  `performPrivilegedCommands`, and string-built command. The one remaining
  `-c` is a constant Python program (not shell source) used to query the
  selected Python interpreter.
- [x] Replace path/name interpolation with typed APIs or correctly delimited
  `Process` arguments. This includes CLI symlink management, undo/restore,
  launch-item management, package cleanup, Homebrew cleanup, and iOS wrapper
  replacement.
- [x] Remove the sudo-password cache where the privileged helper replaces it.
  If a separate authentication path remains essential, require a documented
  security design and explicit Keychain access control before retaining it.
  Homebrew's `SUDO_ASKPASS` path obtains a fresh password for each request and
  does not persist it.
- [x] Make temporary data use uniquely created directories with restrictive
  permissions; remove broad startup deletion of every `/tmp/pearcleaner*`
  entry.
- [x] Ensure every destructive action has a clear preview/confirmation and an
  accurate post-operation result. Destructive GUI actions require confirmation
  regardless of the general prompt preference; CLI deletion commands print a
  resolved-path preview and require `--yes`; completion states distinguish
  success, failure, and partial deletion.

Exit criteria:

- [x] Static review finds no generic root-shell pathway and no unescaped
  path-derived shell construction in the destructive and privileged flows.
- [x] Password material is not retained beyond an approved, documented design.
- [x] Temporary-file cleanup cannot delete unrelated same-user files by prefix.

`ProcessEnv.userShellInvocation()` has been removed. User-owned subprocesses
receive only a direct, allowlisted `HOME`, `TMPDIR`, and supported
system/Homebrew `PATH`; they do not launch a login shell or source startup
files. Package tests verify hostile `SHELL`, `BASH_ENV`, `ENV`, and `PATH`
values cannot influence that environment.

## Phase 3 -- establish Silocleaner identity and signing

Status: **complete in source/configuration; signed-install evidence pending**

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
- [x] Replace all upstream Apple team/profile/signing settings with a
  Silocleaner-only local signing configuration. The project has no checked-in
  team or certificate and fails closed until the Silocleaner Developer ID
  identity is configured; see `SIGNING.md`.
- [x] Create app-group entitlements under the final identity for the app and
  Finder extension. No legacy settings migration is shipped because this fork
  has no prior Silocleaner identifier.
- [x] Update helper and Sentinel launch plist associations and Mach-service
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

Status: **complete in source/configuration; signed distribution evidence pending**

- [x] Re-evaluate the Finder extension's `/` read exception. The extension
  observes only `/Applications`, `/System/Applications`, and
  `~/Applications`, where Finder Sync can supply selected-item URLs. It does
  not inspect or mutate selected apps, so no filesystem temporary exception or
  security-scoped bookmark is required. Apps elsewhere intentionally use the
  main app or its Services entry point instead.
- [x] Audit all targets' entitlements against their actual requirements;
  remove unused app groups and temporary exceptions. `ENTITLEMENTS.md` records
  the intentionally minimal policy: the main app and Finder extension share
  the one preference-bearing app group; FinderOpen remains sandboxed; helper
  and Sentinel have no entitlements.
- [x] Replace private `PackageKit`, `CommerceKit`, and `StoreFoundation`
  dependencies with public APIs, or omit the affected features from a
  notarized release.
- [x] Remove absolute paths from `OTHER_SWIFT_FLAGS` and make all module maps
  project-relative and source-controlled where genuinely required.
- [x] Set a supported signing/notarization workflow with verification of the
  app, Finder extension, Sentinel, and privileged helper as a single bundle.
  `Scripts/notarize-release.sh` archives, verifies, notarizes, staples, runs
  Gatekeeper assessment, and re-verifies the individual signed components;
  `ENTITLEMENTS.md` supplies the required fresh-machine acceptance record.

Exit criteria:

- Release configuration has no upstream machine paths, stale identifiers, or
  unreviewed broad entitlements.
- The selected distribution path completes codesign verification, notarization,
  and a fresh-machine install test.

## Phase 5 -- dependencies, tests, and release confidence

Status: **foundation complete; integration, hardware, and independent-review gates pending**

- [x] Pin every dependency to an immutable revision in both the project and
  `Package.resolved`. AlinFoundation remains an upstream-owned, immutable
  commit; fork or vend it before release if its maintenance or trust model is
  not accepted.
- [x] Add CI that verifies the lockfile, resolves dependencies, builds Debug
  and Release without developer-local paths, runs tests, and reports failures.
- [x] Add unit tests for file-scope classification, deep-link parsing,
  temporary-file lifecycle, and destructive-operation previews.
- [x] Add command-argument construction and direct-environment tests for
  literal metacharacter handling and hostile shell/startup-file values.
- [ ] Add integration/UI tests for Finder invocation, Sentinel behaviour,
  helper installation/approval states, protected/unprotected deletion, undo,
  and a conflicting Pearcleaner install.
  - [x] Add fixture-backed deletion-safety coverage for confirmation-before-
    authorization, protected-path refusal without approved elevation, literal
    move planning (including duplicate filenames), and inverse undo planning.
    The app uses these tested plans; the tests do not touch a real Trash or
    privileged helper.
  - [x] Add a fixture-tested helper lifecycle model for unavailable,
    installable/installing, approval-required, enabled, denied, invalid-
    signature, and unknown/failure outcomes. Settings and Lipo now present the
    state and only the enabled state authorizes helper use. This does not prove
    the signed `SMAppService` registration or XPC connection on a real Mac.
  - [x] Add a shared, fixture-tested Finder invocation policy: exactly one
    selected `.app` beneath `/Applications`, `/System/Applications`, or
    `~/Applications` may create a safely encoded Finder deep link; the app
    rejects malformed or unknown Silocleaner deep links. Services retain an
    explicit `.app`-only route for apps outside those folders. This verifies
    policy, not an installed/signed Finder extension or Services registration.
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

`RELEASE-VALIDATION.md` is the required evidence record for the remaining
hardware, privacy-permission, signed-release, and independent-review gates.

## Next implementation slice

Build the Sentinel lifecycle integration seam and tests: registration,
enablement, current-user Trash monitoring, graceful failure/recovery, and a
visible lifecycle state. Then validate it on a signed machine alongside the
real helper install, approval, unavailable, and XPC-failure states.

After that, complete the remaining Phase 5 integration/UI suite around Finder
and Services invocation, protected/unprotected deletion and undo, and
Pearcleaner coexistence.

## Verification record

| Check | Result | Notes |
| --- | --- | --- |
| Clone and Git status | Passed | Clean `main` at `2527435` before the Phase 0 documentation change. |
| Dependency resolution | Passed | Sparkle 2.8.0, ArgumentParser 1.6.1, AlinFoundation `f61241c`. |
| Full build | Passed | Unsigned, isolated Debug and Release builds completed with Xcode 26.6 on macOS 26.6.2; see `BASELINE.md`. |
| Automated tests | Passed | `swift test --disable-sandbox` executed 23/23 package tests on 2026-09-08: 8 helper-security and 15 core-safety tests, including the Finder invocation policy. This is not Xcode UI or signed-release evidence. |
| Unsigned Debug build after Finder invocation slice | Passed | `Silocleaner Debug` built with `CODE_SIGNING_ALLOWED=NO` on 2026-09-08 after the Finder invocation changes. This does not prove signed, physical-install, Finder, Sentinel, Services, or privacy-permission behavior. |
