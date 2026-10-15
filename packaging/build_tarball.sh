#!/usr/bin/env bash
# Packs the Linux release bundle as SpaceSweep-<version>-linux-<arch>.tar.gz,
# for the architecture of the machine it runs on (x64 or arm64).
#
# Run from anywhere after `flutter build linux --release`:
#
#     packaging/build_tarball.sh [output-dir]        # default output-dir: dist/
#
# The archive holds one top-level folder with the bundle in it: extract it
# anywhere and run ./space_sweep. It needs the GTK 3 runtime (libgtk-3-0).
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="${1:-dist}"

case "$(uname -m)" in
  x86_64) ARCH=x64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *)
    echo "error: unsupported machine '$(uname -m)' (x86_64 or aarch64)" >&2
    exit 1
    ;;
esac

RELEASE_DIR="build/linux/$ARCH/release"
VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
NAME="SpaceSweep-${VERSION}-linux-${ARCH}"

[ -x "$RELEASE_DIR/bundle/space_sweep" ] || {
  echo "error: $RELEASE_DIR/bundle/space_sweep not found; run 'flutter build linux --release' first" >&2
  exit 1
}

mkdir -p "$OUT_DIR"
tar -czf "$OUT_DIR/$NAME.tar.gz" --owner=0 --group=0 --sort=name \
  --transform "s,^bundle,$NAME," -C "$RELEASE_DIR" bundle
echo "built $OUT_DIR/$NAME.tar.gz"
