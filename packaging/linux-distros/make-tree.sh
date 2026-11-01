#!/usr/bin/env bash
# Builds the installed file tree the .rpm, Arch package, AppImage and
# Flatpak are made from, out of the Linux release tarball (SpaceSweep ships
# no .deb):
#
#   /usr/lib/spacesweep/                  the Flutter bundle (space_sweep, lib/, data/)
#   /usr/bin/spacesweep                   -> ../lib/spacesweep/space_sweep
#   /usr/share/applications/spacesweep.desktop
#   /usr/share/icons/hicolor/512x512/apps/spacesweep.png
#
# usage: make-tree.sh <SpaceSweep-<version>-linux-<arch>.tar.gz> <root>
#
# packaging/arch/PKGBUILD.in lays the AUR package out the same way.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[ $# -eq 2 ] || { echo "usage: $0 <tarball> <root>" >&2; exit 2; }
tarball="$1" root="$2"

install -d "$root/usr/lib/spacesweep" "$root/usr/bin"
tar -xzf "$tarball" --strip-components=1 -C "$root/usr/lib/spacesweep"
[ -x "$root/usr/lib/spacesweep/space_sweep" ] ||
  { echo "$tarball has no space_sweep at its top level" >&2; exit 1; }
ln -s ../lib/spacesweep/space_sweep "$root/usr/bin/spacesweep"
install -Dm644 "$repo/packaging/linux/spacesweep.desktop" \
  "$root/usr/share/applications/spacesweep.desktop"
install -Dm644 "$repo/snap/gui/spacesweep.png" \
  "$root/usr/share/icons/hicolor/512x512/apps/spacesweep.png"
(cd "$root" && find . -not -path '*/flutter_assets/*' | sort)
