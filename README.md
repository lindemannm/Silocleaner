# Silocleaner

Silocleaner is a native macOS application cleaner: it finds related files,
supports a Finder extension, a login-item Sentinel, a command-line interface,
and optional privileged operations.

## Release status

This fork is undergoing a security and identity migration. Do not distribute,
notarize, or install its privileged helper until the release gates in
[PLAN.md](PLAN.md) are complete.

## Requirements

- macOS 13 or later
- Full Disk Access for comprehensive searches
- A separately approved privileged helper only for operations that require it

## Development

Open [Silocleaner.xcodeproj](Silocleaner.xcodeproj) in Xcode. The app bundle
identifier is `com.lindemannm.Silocleaner`; release signing requires a
Silocleaner-controlled Apple Developer team and provisioning configuration.

## Issues and discussion

Use the repository's [issue templates](https://github.com/lindemannm/Silocleaner/issues/new/choose)
or [discussions](https://github.com/lindemannm/Silocleaner/discussions).

## Attribution and license

Silocleaner is a fork of [Pearcleaner](https://github.com/alienator88/Pearcleaner).
It remains subject to the repository's [license](LICENSE.md), including its
attribution and Commons Clause obligations.
