#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"

pkgbase="$(source PKGBUILD && printf '%s' "$pkgname")"
aur_url="ssh://aur@aur.archlinux.org/${pkgbase}.git"
tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

if git ls-remote --exit-code "$aur_url" refs/heads/master >/dev/null 2>&1; then
  git clone "$aur_url" "$tmpdir" >/dev/null 2>&1
else
  git init "$tmpdir" >/dev/null
  git -C "$tmpdir" branch -m master >/dev/null
  git -C "$tmpdir" remote add origin "$aur_url"
fi

for path in "$tmpdir"/* "$tmpdir"/.[!.]* "$tmpdir"/..?*; do
  [[ -e "$path" ]] || continue
  [[ "${path##*/}" == '.git' ]] && continue
  rm -rf -- "$path"
done

cp PKGBUILD .SRCINFO LICENSE "$tmpdir"/

if git config --get user.name >/dev/null 2>&1; then
  git -C "$tmpdir" config user.name "$(git config --get user.name)"
fi
if git config --get user.email >/dev/null 2>&1; then
  git -C "$tmpdir" config user.email "$(git config --get user.email)"
fi

git -C "$tmpdir" add PKGBUILD .SRCINFO LICENSE
if ! git -C "$tmpdir" diff --cached --quiet || ! git -C "$tmpdir" diff --quiet; then
  version="$(source PKGBUILD && printf '%s' "$pkgver")"
  git -C "$tmpdir" commit -m "chore: sync AUR package ${version}" >/dev/null
fi

git -C "$tmpdir" push origin HEAD:master
