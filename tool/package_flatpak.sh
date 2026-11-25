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
# The metadata the software centers show: name, author, version, icon.
sed -e "s/@VERSION@/$version/" -e "s/@DATE@/$(date -u +%Y-%m-%d)/" \
  "$here/linux/flatpak/org.hadak.amped.metainfo.xml" > "$work/org.hadak.amped.metainfo.xml"
cp "$here/linux/org.hadak.amped.desktop" "$here/linux/org.hadak.amped.png" "$work/"

flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
(cd "$work" && flatpak-builder --user --force-clean \
  --install-deps-from=flathub --repo=repo build org.hadak.amped.yml)
# --runtime-repo lets an install of the bundle fetch the GNOME runtime itself.
flatpak build-bundle \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$work/repo" "$out/Amped-$version-$(uname -m).flatpak" org.hadak.amped stable
