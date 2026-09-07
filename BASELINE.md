# Phase 0 baseline — 7 September 2026

## Release decision

Silocleaner will target **macOS 13.0 and later** and use **Developer ID,
notarized direct distribution**. This is the only selected channel: the app's
Sparkle updater and its intended optional privileged service do not fit an
App-Store-only release model.

The first public release is an unprivileged cleaner. It includes application
and related-file discovery, user-approved moves to Trash and restore, Finder
invocation, Sentinel monitoring, package-receipt lookup, update discovery,
Homebrew management, and app thinning where the current user can write the
bundle. It must not install or encourage use of the privileged helper until
Phases 1--3 have passed their gates. Protected-file mutation and root-owned
bundle thinning are therefore explicitly withheld.

## Source and toolchain

| Item | Recorded value |
| --- | --- |
| Repository revision | `2527435` (`main`, clean before this baseline record) |
| Distribution repository | `origin` → `https://github.com/lindemannm/Silocleaner.git` |
| Upstream | `upstream` → `https://github.com/alienator88/Pearcleaner.git` |
| Upstream policy | Track upstream `main`; review upstream changes as security-sensitive patches. Merge only after Silocleaner identity, privilege, private-API, and regression review. Do not fast-forward release branches. |
| Host | macOS 26.6.2 (25G83), arm64 |
| Xcode | 26.6 (17F113) |
| Project deployment target | macOS 13.0 |
| Dependencies | Sparkle 2.8.0; swift-argument-parser 1.6.1; AlinFoundation `f61241c2ea1856ef41cbfc965afe9d756121456f` |

## Reproducible build check

Both checks began with isolated derived-data paths and disabled signing. They
resolved the package graph from `Package.resolved` and built the app, Finder
extension, Sentinel, and helper in dependency order.

| Configuration | Command | Result |
| --- | --- | --- |
| Debug | `xcodebuild -project Silocleaner.xcodeproj -scheme 'Silocleaner Debug' -configuration Debug -derivedDataPath /private/tmp/silocleaner-phase0-derived CODE_SIGNING_ALLOWED=NO build` | Passed (`BUILD SUCCEEDED`) |
| Release | `xcodebuild -project Silocleaner.xcodeproj -scheme 'Silocleaner Release' -configuration Release -derivedDataPath /private/tmp/silocleaner-phase0-release-derived CODE_SIGNING_ALLOWED=NO build` | Passed (`BUILD SUCCEEDED`) |

The first attempt inside Codex's filesystem sandbox could not write Xcode and
SwiftPM caches. Repeating the same isolated build with normal local macOS cache
access succeeded; this was an execution-sandbox limitation, not a project
build failure. No tests ran: the project currently has no test target.

## Destructive-operation inventory

| Operation | Owner and input source | Expected scope | Privilege/release treatment |
| --- | --- | --- | --- |
| Application-related-file removal | `FileManagerUndo.deleteFiles`; user selection from app/leftover search or CLI | Individual selected files, moved into a timestamped bundle in the current user's Trash | Unprivileged first-release capability; confirmation and path validation required |
| Restore | `FileManagerUndo.restoreFiles`, undo history | Recorded Trash bundle back to each recorded original location | Unprivileged when writable; failed protected restores must be reported |
| Self-uninstall | `uninstallSilocleaner`; explicit app-menu command | Silocleaner bundle and its selected related files | Unprivileged only; unregister Sentinel before removal |
| CLI link install/removal | `manageSymlink`; Settings or CLI request | `/usr/local/bin/pear` or legacy `/usr/local/bin/silocleaner` | Requires elevation when `/usr/local/bin` is protected; retain for Phase 2 command-path review |
| Finder extension and Sentinel registration | `manageFinderPlugin`, `launchctl`; explicit settings/app lifecycle action | Registered Silocleaner extension and `com.lindemannm.SilocleanerSentinel` agent | Service-management operation; verify on a clean account before release |
| Helper registration | `HelperToolManager`; explicit settings/CLI action | `com.lindemannm.Silocleaner.SilocleanerHelper` daemon | Excluded from public release until Phases 1--3; it is the principal privileged boundary |
| Root-owned app thinning | Helper `runThinning` / `runBundleThinning`; user-selected app bundle | A selected Mach-O binary or app bundle | Excluded until Phase 1 validates canonical paths, symlinks, allowlists, races, limits, and tests |
| User-writable app thinning | `thinAppBundle` / Mach-O APIs; user-selected app bundle | Executable binaries inside the selected app bundle | First-release capability only after preview/confirmation validation |
| Homebrew install, uninstall, tap management, update and cleanup | `HomebrewController` / `HomebrewUninstaller`; named package/tap and Homebrew metadata | Homebrew prefix, Cellar/Caskroom, taps, caches/logs, and launch-agent schedules | Included only with explicit package selection/confirmation; Phase 2 reviews every command and path boundary |
| Package receipt lookup | `PKGManager`; application/package metadata | Read-only `pkgutil` receipt queries | First-release capability |
| Third-party application updates | `UpdateManager`, Sparkle/Homebrew/App Store handoff; selected update | The selected third-party app or its package manager | First-release capability subject to each updater's own confirmation/authorization |
| iOS wrapper replacement | `IOSAppInstaller`; selected App Store metadata and temporary IPA extraction | A temporary extraction directory and target wrapper | Phase 2 command and temporary-directory review required before public exposure |
| Temporary cleanup | `cleanupSilocleanerTempDirs` and iOS installer | `/tmp` entries currently matched by the `silocleaner` prefix | Must be redesigned in Phase 2 to use unique, owner-controlled directories; do not treat as release-safe |
| BTM reset | `HelperToolManager.resetBTM`; explicit recovery action | System Background Task Management database | Excluded from public release pending typed-helper and authorization review |

## Phase 0 outcome

The baseline is reproducible for unsigned Debug and Release builds on the
recorded host. It does **not** establish signing, notarization, a fresh-machine
install, test execution, or privileged-operation safety; those remain the
release gates in later phases.
