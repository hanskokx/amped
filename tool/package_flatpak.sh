#!/bin/sh
# Packs the AppDir that package_appimage.sh leaves behind into a Flatpak
# bundle, for people who install it with `flatpak install Amped-*.flatpak`.
# Needs flatpak and flatpak-builder, and the GNOME runtime and SDK.
#
#   tool/package_flatpak.sh 0.1.0 out-dir     (out-dir holds AppDir)
set -eu
version=$1
out=$2
runtime=49

here=$(cd "$(dirname "$0")/.." && pwd)
work="$out/flatpak"
rm -rf "$work"
mkdir -p "$work"

cat > "$work/org.hadak.amped.yml" <<YML
app-id: org.hadak.amped
runtime: org.gnome.Platform
runtime-version: '$runtime'
sdk: org.gnome.Sdk
command: amped-flatpak
finish-args:
  - --share=ipc
  - --share=network
  - --socket=x11
  - --socket=wayland
  - --socket=pulseaudio
  - --device=dri
  - --filesystem=xdg-music
  - --filesystem=xdg-videos
  - --talk-name=org.freedesktop.secrets
  - --talk-name=org.kde.StatusNotifierWatcher
modules:
  - name: amped
    buildsystem: simple
    build-commands:
      - cp -R opt/amped /app/amped
      - mkdir -p /app/lib /app/bin /app/share
      - cp -an usr/lib/. /app/lib/
      - cp -R usr/share/. /app/share/
      - install -Dm755 amped-flatpak /app/bin/amped-flatpak
      - install -Dm644 org.hadak.amped.metainfo.xml /app/share/metainfo/org.hadak.amped.metainfo.xml
    sources:
      - type: dir
        path: ../AppDir
      - type: file
        path: amped-flatpak
      - type: file
        path: org.hadak.amped.metainfo.xml
YML

cat > "$work/amped-flatpak" <<'RUN'
#!/bin/sh
export LD_LIBRARY_PATH="/app/lib:/app/amped/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec /app/amped/amped "$@"
RUN

cat > "$work/org.hadak.amped.metainfo.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>org.hadak.amped</id>
  <name>Amped</name>
  <summary>Crank it up.</summary>
  <metadata_license>CC0-1.0</metadata_license>
  <url type="homepage">https://www.amped-player.com</url>
  <description><p>A desktop music player with skins.</p></description>
  <launchable type="desktop-id">org.hadak.amped.desktop</launchable>
  <releases><release version="$version"/></releases>
</component>
XML

cd "$work"
flatpak-builder --force-clean --disable-rofiles-fuse --repo=repo build org.hadak.amped.yml
flatpak build-bundle repo "../Amped-$version-linux-x86_64.flatpak" org.hadak.amped
