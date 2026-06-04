#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_root"

main_branch="${MAIN_BRANCH:-main}"
aur_branch="${AUR_BRANCH:-aur}"
aur_remote="${AUR_REMOTE:-aur}"
pkgbase="$(source PKGBUILD && printf '%s' "$pkgname")"
aur_url="ssh://aur@aur.archlinux.org/${pkgbase}.git"

if ! git remote get-url "$aur_remote" >/dev/null 2>&1; then
  git remote add "$aur_remote" "$aur_url"
fi

tmpdir="$(mktemp -d)"
cleanup() {
  git worktree remove -f "$tmpdir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if git ls-remote --exit-code "$aur_remote" refs/heads/master >/dev/null 2>&1; then
  git fetch "$aur_remote" master
  if git show-ref --verify --quiet "refs/heads/${aur_branch}"; then
    git branch -f "$aur_branch" FETCH_HEAD
  else
    git branch "$aur_branch" FETCH_HEAD
  fi
elif ! git show-ref --verify --quiet "refs/heads/${aur_branch}"; then
  git branch "$aur_branch" "$main_branch"
fi

git worktree add "$tmpdir" "$aur_branch" >/dev/null

(
  cd "$tmpdir"
  git rm -r --ignore-unmatch . >/dev/null
  git checkout "$main_branch" -- PKGBUILD .SRCINFO LICENSE

  if ! git diff --cached --quiet || ! git diff --quiet; then
    version="$(source PKGBUILD && printf '%s' "$pkgver")"
    git commit -m "chore: sync AUR package ${version}" >/dev/null
  fi

  git push "$aur_remote" HEAD:master
)
