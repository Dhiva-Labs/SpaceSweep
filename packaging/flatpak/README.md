# Flatpak

The `flatpak` job in `.github/workflows/ci.yml` builds
`spacesweep-<version>-<x86_64|aarch64>.flatpak` on the GNOME 51 runtime, then
installs that bundle in the Flatpak builder container and runs it: every ELF
file must find its libraries inside the sandbox, and the "SpaceSweep" window
must come up under Xvfb (`test-bundle.sh`).

The manifest does not compile anything: it takes the installed tree CI builds
from the release tarball (`packaging/linux-distros/make-tree.sh`, unpacked
into `tree/`), so the Flatpak runs the same binary as every other package.

Install a bundle from a release (the GNOME runtime comes from Flathub):

```sh
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user ./spacesweep-1.1.0-x86_64.flatpak
flatpak run com.dhivalabs.space_sweep
```

Permissions: Wayland/X11, the GPU and the home folder (`--filesystem=home`):
SpaceSweep scans the user folders and deletes what you pick, clears folders in
`~/.cache` and empties the trash, all by path. Flatpak would point
`XDG_CACHE_HOME`, `XDG_DATA_HOME` and `XDG_CONFIG_HOME` into the app's own
`~/.var/app` folder, where the app would find only its own cache and trash and
no `user-dirs.dirs`; the manifest unsets them, so the app works on the real
`~/.cache`, trash and user folders, and keeps its own settings in
`~/.local/share`, as the other Linux packages do.

## A Flathub submission would differ

- Flathub does not build from CI artifacts. The `tree` source becomes the
  release tarball (`type: archive`, `url:` + `sha256:`) plus the desktop file
  and icon from this repository.
- Flathub asks for a free-software or redistributable licence in the
  metainfo; SpaceSweep is declared proprietary (as in the snap).
- `--filesystem=home` and the unset XDG variables need a justification in the
  submission; `flatpak-builder-lint` must pass on the manifest and the
  metainfo (screenshots, release notes, a brand colour).
