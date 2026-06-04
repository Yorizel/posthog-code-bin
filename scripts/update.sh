#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"

release_json="$(mktemp)"
trap 'rm -f "$release_json"' EXIT

python3 <<'PY' > "$release_json"
import json
import re
import sys
import urllib.request

API = 'https://api.github.com/repos/PostHog/code/releases?per_page=30'
PATTERN = re.compile(r'^PostHog\.Code-(?P<version>[0-9][^/]*)-x64\.AppImage$')

headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'posthog-code-bin-updater',
}

for page in range(1, 6):
    url = f'{API}&page={page}'
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as resp:
        releases = json.load(resp)
    if not releases:
        break

    for release in releases:
        if release.get('draft') or release.get('prerelease'):
            continue
        for asset in release.get('assets', []):
            match = PATTERN.match(asset.get('name', ''))
            if not match:
                continue
            digest = asset.get('digest', '')
            if not digest.startswith('sha256:'):
                raise SystemExit(f"Asset digest missing sha256 for {asset['name']}")
            version = match.group('version')
            tag = release.get('tag_name', '')
            if tag.startswith('v') and tag[1:] != version:
                raise SystemExit(f"Version mismatch: release tag {tag} asset {asset['name']}")
            json.dump({
                'version': version,
                'url': asset['browser_download_url'],
                'sha256': digest.split(':', 1)[1],
                'tag': tag,
                'published_at': release.get('published_at'),
            }, sys.stdout)
            raise SystemExit(0)

raise SystemExit('No compatible x64 AppImage release found in recent GitHub releases')
PY

new_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$release_json")"
new_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$release_json")"
new_sha256="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$release_json")"
current_version="$(source PKGBUILD && printf '%s' "$pkgver")"

echo "current version: $current_version"
echo "latest x64 appimage version: $new_version"

if [[ "$current_version" == "$new_version" ]]; then
  echo 'PKGBUILD already targets the newest compatible release.'
  exit 0
fi

python3 - "$new_version" "$new_url" "$new_sha256" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path('PKGBUILD')
text = path.read_text()
version, url, sha256 = sys.argv[1:4]
text, count = re.subn(r'^pkgver=.*$', f'pkgver={version}', text, flags=re.M)
if count != 1:
    raise SystemExit('Failed to update pkgver')
text, count = re.subn(r'^source_x86_64=\(.+\)$', f'source_x86_64=("{url}")', text, flags=re.M)
if count != 1:
    raise SystemExit('Failed to update source_x86_64')
text, count = re.subn(r'^noextract=\(.+\)$', f'noextract=("PostHog.Code-{version}-x64.AppImage")', text, flags=re.M)
if count != 1:
    raise SystemExit('Failed to update noextract')
text, count = re.subn(r"^sha256sums_x86_64=\('.+'\)$", f"sha256sums_x86_64=('{sha256}')", text, flags=re.M)
if count != 1:
    raise SystemExit('Failed to update sha256sums_x86_64')
path.write_text(text)
PY

makepkg --printsrcinfo > .SRCINFO

echo "updated PKGBUILD to $new_version"
