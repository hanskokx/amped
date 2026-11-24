#!/bin/sh
# Packs the Linux release bundle into a .deb and an .rpm (needs fpm and rpm).
#
#   tool/package_linux.sh 0.1.0 1 build/linux/x64/release/bundle out-dir
set -eu
version=$1
iteration=$2
bundle=$3
out=$4

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
here=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$root/opt/amped" "$root/usr/bin" \
  "$root/usr/share/applications" "$root/usr/share/icons/hicolor/512x512/apps"
cp -R "$bundle"/. "$root/opt/amped/"
ln -s /opt/amped/amped "$root/usr/bin/amped"
cp "$here/linux/org.hadak.amped.desktop" "$root/usr/share/applications/"
cp "$here/linux/org.hadak.amped.png" \
  "$root/usr/share/icons/hicolor/512x512/apps/org.hadak.amped.png"
mkdir -p "$out"

fpm_package() {
  type=$1
  package=$2
  shift 2
  fpm -s dir -t "$type" --name amped --version "$version" \
    --iteration "$iteration" --architecture native \
    --maintainer "Hans Kokx" --description "Amped: crank it up." \
    --url https://github.com/hanskokx/amped --chdir "$root" \
    --package "$package" "$@" opt usr
}

fpm_package deb "$out/amped_${version}-${iteration}_amd64.deb" \
  -d libgtk-3-0 -d libsecret-1-0 -d "libmpv2 | libmpv1" \
  -d libayatana-appindicator3-1
fpm_package rpm "$out/amped-${version}-${iteration}.x86_64.rpm" \
  -d gtk3 -d libsecret -d mpv-libs -d libayatana-appindicator-gtk3
