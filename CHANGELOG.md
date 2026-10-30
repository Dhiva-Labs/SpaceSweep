# Changelog

All notable changes to SpaceSweep are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] — 2026-10-16

First release of the Linux desktop edition. The version in `pubspec.yaml` and
`snap/snapcraft.yaml` was already 1.1.0, so this release needs no version bump.

### Added

- Linux desktop edition: duplicate files, junk files and large files over your
  Desktop, Documents, Downloads, Music, Pictures and Videos folders, and a
  **Cache & trash** screen that clears `~/.cache` folders and empties the
  desktop trash.
- Linux x86-64 and arm64 (aarch64) builds. CI builds, tests and smoke-runs the
  app on a native runner of each architecture and attaches
  `SpaceSweep-<version>-linux-x64.tar.gz` and
  `SpaceSweep-<version>-linux-arm64.tar.gz` to a published release.
- Snap packaging (`spacesweep`, strictly confined, core22) for amd64 and arm64.
- `packaging/build_tarball.sh`, which packs the Linux bundle for the
  architecture of the machine it runs on.

### Changed

- The file tools take a scan scope (a base folder plus the folders to walk).
  Android still scans all shared storage; Linux scans the user folders only.
- Folders that tools fill on their own (such as `Screenshots` and
  `Screencasts`) and hidden folders are no longer offered as empty-folder junk,
  and a parent that holds only those is not reported as empty either.

## [1.0.0] — 2026-10-13

First release: Android app with duplicate finder, app cache tools, junk
cleaner and large-file finder.

[1.1.0]: https://github.com/Dhiva-Labs/SpaceSweep/releases/tag/v1.1.0
[1.0.0]: https://github.com/Dhiva-Labs/SpaceSweep/releases/tag/v1.0.0
