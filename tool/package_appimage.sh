#!/bin/sh
# Packs the Linux release bundle into an AppImage, and leaves the AppDir
# (with libmpv and the libraries it needs copied in) for package_flatpak.sh.
# GTK and libsecret come from the host, as with the .deb. Needs
# linuxdeploy and appimagetool on the PATH (the release workflow fetches them).
#
#   tool/package_appimage.sh 0.1.0 build/linux/x64/release/bundle out-dir
set -eu
version=$1
bundle=$2
out=$3

here=$(cd "$(dirname "$0")/.." && pwd)
appdir="$out/AppDir"
rm -rf "$appdir"
mkdir -p "$appdir/opt/amped" "$appdir/usr/bin" "$appdir/usr/lib" \
  "$appdir/usr/share/applications" \
  "$appdir/usr/share/icons/hicolor/512x512/apps"
cp -R "$bundle"/. "$appdir/opt/amped/"
ln -s ../../opt/amped/amped "$appdir/usr/bin/amped"
cp "$here/linux/org.hadak.amped.desktop" "$appdir/usr/share/applications/"
cp "$here/linux/org.hadak.amped.png" \
  "$appdir/usr/share/icons/hicolor/512x512/apps/org.hadak.amped.png"

# libmpv and its dependencies are not on every system, so they travel along.
mpv=$(ldconfig -p | awk '/libmpv\.so\.[0-9]+ / {print $NF; exit}')
[ -n "$mpv" ] || { echo "libmpv not found" >&2; exit 1; }

export APPIMAGE_EXTRACT_AND_RUN=1
(cd "$out" && linuxdeploy --appdir AppDir \
  --executable "$appdir/opt/amped/amped" \
  --library "$mpv" \
  --desktop-file "$appdir/usr/share/applications/org.hadak.amped.desktop" \
  --icon-file "$here/linux/org.hadak.amped.png")

cat > "$appdir/AppRun" <<'RUN'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
export LD_LIBRARY_PATH="$here/usr/lib:$here/opt/amped/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$here/opt/amped/amped" "$@"
RUN
chmod +x "$appdir/AppRun"

ARCH=x86_64 appimagetool "$appdir" "$out/Amped-$version-linux-x86_64.AppImage"
