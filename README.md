# SpaceSweep

**Free up space on your Android phone.** Find duplicate files, clear app caches,
sweep away junk and spot the files eating your storage — all on-device, no ads,
no tracking, no network access.

<p>
  <img src="docs/screenshots/home.png" width="180" alt="Home, dark">
  <img src="docs/screenshots/home-light.png" width="180" alt="Home, light">
  <img src="docs/screenshots/duplicates.png" width="180" alt="Duplicate files">
</p>
<p>
  <img src="docs/screenshots/app-cache.png" width="180" alt="App cache">
  <img src="docs/screenshots/junk.png" width="180" alt="Junk files">
  <img src="docs/screenshots/large-files.png" width="180" alt="Large files">
</p>

The home screen's storage ring splits used space into photos, videos, apps
and everything else (with usage access). The look is "Lilac night": ink-black
and lavender surfaces with lilac, pink, lime and peach accents, set in
[Space Grotesk](https://github.com/floriankarsten/space-grotesk) (SIL OFL 1.1,
bundled in `assets/fonts`, so the app still needs no internet access).

## Features

### Duplicate files
- Compares **file content**, not names: files are grouped by size, then by a
  SHA-256 of three 16 KB samples (start, middle, end), and only the remaining
  candidates are hashed in full. Most files are never read completely.
- Groups are sorted by how much space they'd free, with image thumbnails and
  filters for images, videos, audio, documents and archives.
- One copy is pre-marked **Keep** — the oldest by default, or the newest, or
  the shortest path.
- Ignores files below a size you choose (1 KB – 1 MB) and, unless you opt in,
  hidden folders.

### App cache
- Lists every app by cache size (system apps optional), with icons.
- **Trim caches** — asks Android to delete cached files across *all* apps in
  one tap (`StorageManager.allocateBytes`). Android clears the largest caches
  first and may leave small ones alone.
- **Clear app cache folders** (Android 11+) — Android's own confirmation dialog
  that empties every app's cache folder in shared storage
  (`ACTION_CLEAR_APP_CACHE`).
- **Per-app Clear** — opens the app's settings page; when you come back,
  SpaceSweep shows how much you freed.

### Junk files
| Category | What | Pre-selected |
|---|---|---|
| Thumbnail caches | `.thumbnails` folders galleries rebuild on demand | yes |
| Installer files | `.apk/.apks/.xapk/.apkm`, with app name and version | only if that version (or newer) is installed |
| Temporary & log files | `.tmp`, `.part`, `.crdownload`, `~$` lock files, `.log` — **older than a day** | yes |
| Media in the trash | `.trashed-*` files waiting in the system trash | no |
| Empty folders | folders with nothing inside | yes |

### Large files
The biggest files over 10 / 50 / 100 / 500 MB, filterable by type.

## About clearing other apps' caches

Since Android 6, only system apps may wipe another app's internal cache
directly (`CLEAR_APP_CACHE` is a signature permission). "Cleaner" apps that
claim one-tap total cache clearing either drive Settings through accessibility
automation or don't actually clear anything. SpaceSweep uses only the supported
routes above. Verified on an Android 17 emulator: Trim removed a 400 MB cache
planted in another app, and the per-app flow measured 163 MB freed from Gboard.

## Safety

Deletes are re-checked at the moment they happen:

- A duplicate group always keeps at least one copy, and nothing in the group
  is deleted unless that kept copy is still on disk unchanged.
- Any file whose size or modification time changed since the scan — or that
  became a symlink — is skipped, not deleted.
- Nothing outside shared storage, or inside `Android/data` / `Android/obb`, is
  ever touched. Symlinks are never followed.
- "Empty" folders are re-checked for content right before removal; standard
  folders (`DCIM`, `Download`, `Music`, …), hidden folders and the `Android`
  tree are never reported as empty.
- With a filter active, Delete only acts on what's on screen.
- Deleted media is removed from the media store so galleries don't show ghosts.

## Permissions

| Permission | Why |
|---|---|
| `MANAGE_EXTERNAL_STORAGE` (Android 11+) / storage (Android 8–10) | Scan and delete files in shared storage |
| `PACKAGE_USAGE_STATS` (usage access) | Read other apps' cache sizes |
| `QUERY_ALL_PACKAGES` | List installed apps on the cache screen and match APKs to installed apps |

No internet permission. Google Play restricts all-files access and
`QUERY_ALL_PACKAGES` to approved use cases, so a Play release would need a
permissions declaration.

## Building

Requires Flutter 3.44+ and the Android SDK. Runs on Android 8.0 (API 26) or newer.

```bash
flutter test                 # unit + widget tests
flutter build apk --release  # signed with debug keys until a keystore is set up
```

Code layout:

```
lib/src/scan/      walker, duplicate finder, junk & large-file scanners, isolate runner
lib/src/clean/     Cleaner: re-checked, guarded deletion
lib/src/platform/  StorageBridge (method channel "space_sweep/storage")
lib/src/ui/        screens
android/.../StorageChannel.kt   StorageStatsManager, allocateBytes, ACTION_CLEAR_APP_CACHE, APK info
```

Scans run on a background isolate and can be cancelled.
