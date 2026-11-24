#!/bin/sh
# Writes the website's release.json from the latest GitHub release (the
# installers' names, URLs, sizes and SHA-256 digests), or a placeholder when
# there is none yet. Needs gh (GH_TOKEN) and jq.
#
#   tool/release_json.sh owner/repo out-file
set -eu
repo=$1
out=$2

if release=$(gh api "repos/$repo/releases/latest" 2>/dev/null); then
  printf '%s' "$release" | jq '{
    version: (.tag_name | ltrimstr("v")),
    published: .published_at,
    notes: .html_url,
    assets: [.assets[] | select(.name != "SHA256SUMS") | {
      name,
      url: .browser_download_url,
      size,
      sha256: ((.digest // "") | ltrimstr("sha256:"))
    }]
  }' > "$out"
else
  echo '{"version":"0.0.0","assets":[]}' > "$out"
fi
cat "$out"
