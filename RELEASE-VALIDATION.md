# Phase 5 release-validation record

CI verifies an unsigned fresh checkout: the dependency declarations match the
checked-in SwiftPM lockfile, helper-security tests execute, and both Debug and
Release schemes build without developer-local signing settings. It does not
prove signing, notarization, hardware-specific behavior, or operating-system
privacy prompts.

## Required evidence before public release

Record the date, macOS version, processor architecture, tester, and result for
each row. Attach the CI run URL or the generated `.xcresult` where applicable.

| Gate | Apple silicon | Intel | FDA absent | FDA present | Evidence |
| --- | --- | --- | --- | --- | --- |
| Clean install launches and Finder extension can invoke Silocleaner | pending | pending | pending | pending | pending |
| Sentinel registration, launch, and disable/re-enable behavior | pending | pending | pending | pending | pending |
| Helper install/approval/unavailable states are clear and fail closed | pending | pending | pending | pending | pending |
| Protected and unprotected deletion show the correct preview and result | pending | pending | pending | pending | pending |
| Undo restores a deleted unprotected item and reports unavailable protected undo | pending | pending | pending | pending | pending |
| Install beside Pearcleaner without sharing services, URL handling, or CLI links | pending | pending | pending | pending | pending |
| Upgrade then uninstall leaves no Silocleaner launch agent, helper, or Finder extension registration | pending | pending | pending | pending | pending |

## Signed-release gate

After the matrix is complete, perform the Developer ID archive/notarization
workflow in `ENTITLEMENTS.md`. Preserve the archive, notarization submission
identifier, `spctl` result, and the output of `Scripts/verify-release-bundle.sh`.

## Independent security review

Commission an external review before public release. Its scope must include
helper client authorization, bundle/path race resistance, all root-owned and
protected-file mutations, command argument handling, temporary-file cleanup,
and the Finder/Sentinel installation paths. Record the reviewer, reviewed
commit, findings, remediation commits, and acceptance decision here or in the
release notes.
