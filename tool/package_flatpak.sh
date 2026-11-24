#!/bin/sh
# Builds a Flatpak bundle from the AppDir tool/package_appimage.sh made.
#
#   tool/package_flatpak.sh 0.1.0 out-dir      (out-dir holds AppDir)
set -eu
version=$1
out=$2
here=$(cd "$(dirname "$0")/.." && pwd)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R "$out/AppDir" "$work/AppDir"
cp "$here/linux/flatpak/org.hadak.amped.yml" "$work/"
cp "$here/linux/org.hadak.amped.desktop" "$here/linux/org.hadak.amped.png" "$work/"

flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
(cd "$work" && flatpak-builder --user --force-clean \
  --install-deps-from=flathub --repo=repo build org.hadak.amped.yml)
flatpak build-bundle "$work/repo" "$out/Amped-$version-x86_64.flatpak" org.hadak.amped
