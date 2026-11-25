#!/bin/sh
# Writes the website's release.json from the latest GitHub release (the
# installers' names, URLs, sizes and SHA-256 digests), or a placeholder when
# there is none yet. Needs gh (GH_TOKEN) and jq.
#
#   tool/release_json.sh owner/repo out-file
set -eu
repo=$1
out=$2

# No release yet (404) gives a placeholder. Any other failure (rate limit,
# network) stops the deploy, so a good release.json is never replaced by it.
if release=$(gh api "repos/$repo/releases/latest" 2>"$out.err"); then
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
elif grep -q "HTTP 404" "$out.err"; then
  echo '{"version":"0.0.0","assets":[]}' > "$out"
else
  cat "$out.err" >&2
  rm -f "$out.err"
  exit 1
fi
rm -f "$out.err"
cat "$out"
