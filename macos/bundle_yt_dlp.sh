#!/bin/sh
# Run by the Runner's "Bundle yt-dlp" build phase: finds the amped_ytdlp
# package (a path or git dependency, wherever pub put it) and runs its
# install_yt_dlp.sh, which puts yt-dlp into the app being built.
set -eu

CONFIG="$SRCROOT/../.dart_tool/package_config.json"
if [ ! -f "$CONFIG" ]; then
  echo "error: $CONFIG is missing; run 'flutter pub get' first" >&2
  exit 1
fi

ROOT_URI="$(awk '
  /"name": "amped_ytdlp"/ { found = 1 }
  found && /"rootUri"/ {
    gsub(/.*"rootUri": "/, ""); gsub(/".*/, ""); print; exit
  }' "$CONFIG")"
if [ -z "$ROOT_URI" ]; then
  echo "error: amped_ytdlp is not in $CONFIG" >&2
  exit 1
fi

case "$ROOT_URI" in
  file://*) PACKAGE_DIR="${ROOT_URI#file://}" ;;
  /*) PACKAGE_DIR="$ROOT_URI" ;;
  *) PACKAGE_DIR="$SRCROOT/../.dart_tool/$ROOT_URI" ;;
esac
# A URI escapes spaces and the like.
PACKAGE_DIR="$(printf '%b' "$(printf '%s' "$PACKAGE_DIR" | sed 's/%\(..\)/\\x\1/g')")"

exec "$PACKAGE_DIR/macos/install_yt_dlp.sh"
