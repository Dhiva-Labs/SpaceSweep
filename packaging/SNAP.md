# Packaging SpaceSweep as a Snap

`snap/snapcraft.yaml` builds the Linux desktop edition from source into a
strictly confined `core22` + `gnome` extension snap named `spacesweep`, the
same pattern as DoseDrop.

## Building

Pack from a clean export, never from the working tree: `source: .` copies the
whole directory into the container first, including the host's `build/`
(Android + Linux output, over a gigabyte).

```sh
rm -rf ~/snapbuild/spacesweep && mkdir -p ~/snapbuild/spacesweep
git archive HEAD | tar -x -C ~/snapbuild/spacesweep
cd ~/snapbuild/spacesweep && snapcraft pack --use-lxd   # -> spacesweep_<version>_amd64.snap
```

The export must live under `$HOME`; the LXD snap cannot see the host's
`/tmp`. `version` in `snapcraft.yaml` is set by hand and must match
`pubspec.yaml`.

## Testing confined

Install the snap in the `snaptest` VM (see the house notes on snap testing),
connect the personal-files plugs by hand (they only auto-connect once the
store grants it) and run it under `xvfb-run`:

```sh
sudo snap install --dangerous spacesweep_<version>_amd64.snap
sudo snap connect spacesweep:dot-cache
sudo snap connect spacesweep:trash
sudo snap connect spacesweep:user-dirs
```

## Publishing

```sh
snapcraft register spacesweep          # once
snapcraft upload --release=stable spacesweep_<version>_amd64.snap
```

The `personal-files` plugs send every upload to manual review, and a
revision waiting there blocks later releases of the snap until it is
approved or rejected. After approval: `snapcraft release spacesweep <rev> stable`.

### Store request (forum, store-requests category)

> **Title:** personal-files auto-connection for spacesweep
>
> SpaceSweep (`spacesweep`, https://github.com/Dhiva-Labs/SpaceSweep) is a
> disk-space cleaner: duplicate finder, junk and large-file finder, and a
> cache & trash screen. It requests auto-connection of three personal-files
> plugs:
>
> - `dot-cache`: write `$HOME/.cache`. The app's core feature is measuring
>   each application's cache folder and clearing the ones the user picks
>   (contents only; the folders stay). The XDG spec defines this directory
>   as non-essential data that apps rebuild.
> - `trash`: write `$HOME/.local/share/Trash`. Emptying the freedesktop.org
>   trash, after an explicit confirmation listing the item count and size.
> - `user-dirs`: read `$HOME/.config/user-dirs.dirs`. Only to find the
>   localised names of the Documents, Downloads, Pictures, Music, Videos and
>   Desktop folders, which are the only folders the file scans walk.
>
> Nothing else under hidden folders is read or written, the snap has no
> network plug, and every deletion is user-initiated and confirmed. Without
> auto-connection the app's main screen would show no caches and no trash,
> which is the whole point of installing it.

## Confinement

| Feature | Under strict confinement |
|---|---|
| Duplicate, junk and large-file scans | `home` (auto-connected): Desktop, Documents, Downloads, Music, Pictures, Videos. |
| Localised folder names | `user-dirs` (read). Without it, the English folder names are assumed. |
| Cache & trash screen | `dot-cache` and `trash`. Without them the screen shows nothing to clear. |
| Disk size on the home screen | libc `statvfs` through FFI; no `mount-observe` needed (`df` would read the mount table). |

`HOME` inside the snap is `~/snap/spacesweep/<rev>`; the app reads
`SNAP_REAL_HOME` for the real home folder and ignores the snap-scoped
`XDG_*_HOME` variables when `SNAP` is set.
