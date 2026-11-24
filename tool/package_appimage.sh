#!/bin/sh
# Builds an AppImage, and leaves the AppDir it was made from in <out>/AppDir
# (the Flatpak is built from that too). libmpv, which the player loads at run
# time, is bundled with what it needs.
#
#   tool/package_appimage.sh 0.1.0 build/linux/x64/release/bundle out-dir
set -eu
version=$1
bundle=$2
out=$3
here=$(cd "$(dirname "$0")/.." && pwd)
tools=$(mktemp -d)
trap 'rm -rf "$tools"' EXIT

base=https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous
curl -fsSL -o "$tools/linuxdeploy" "$base/linuxdeploy-x86_64.AppImage"
curl -fsSL -o "$tools/linuxdeploy-plugin-appimage" \
  https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage
chmod +x "$tools/linuxdeploy" "$tools/linuxdeploy-plugin-appimage"

mkdir -p "$out"
appdir="$out/AppDir"
rm -rf "$appdir"
mkdir -p "$appdir/usr/bin"
cp -R "$bundle"/. "$appdir/usr/bin/"

mpv=$(ldconfig -p | awk '/libmpv\.so\.[0-9]+ /{print $NF; exit}')
[ -n "$mpv" ] || { echo "libmpv is not installed" >&2; exit 1; }

# AppImages cannot be run directly on a runner without FUSE.
export APPIMAGE_EXTRACT_AND_RUN=1
export PATH="$tools:$PATH"
export LINUXDEPLOY_OUTPUT_VERSION="$version"
export ARCH=x86_64
(cd "$out" && "$tools/linuxdeploy" --appdir AppDir \
  --executable AppDir/usr/bin/amped \
  --library "$mpv" \
  --desktop-file "$here/linux/org.hadak.amped.desktop" \
  --icon-file "$here/linux/org.hadak.amped.png" \
  --output appimage)
ls "$out"
