#!/usr/bin/env bash
# Pull the latest CreepyGnome/t3code feat/repo-worktrees branch (pingdotgg/t3code PR #35476), rebase our
# main commits onto it, build the macOS arm64 desktop app, and install it over
# /Applications/T3 Code (Beta).app.
# Usage: t3code-update.sh [--force]   (--force rebuilds even if already up to date)
set -euo pipefail

# The checkout this script sits in, or $T3CODE_REPO (cloned there when missing).
REPO=${T3CODE_REPO:-$(git -C "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" rev-parse --show-toplevel 2>/dev/null || true)}
[[ -n "$REPO" ]] || { echo "Set T3CODE_REPO to the t3code checkout to build." >&2; exit 1; }
BRANCH=feat/repo-worktrees
LOCAL_BRANCH=main   # our fixes, rebased onto $BRANCH every run
APP="/Applications/T3 Code (Beta).app"
CACHE="$HOME/.local/share/t3code-fork"
MONITOR_DST="$REPO/native/resource-monitor/target/aarch64-apple-darwin/release/t3-resource-monitor"
FORCE=${1:-}
FORK_REMOTE=mine
FORK_FETCH_URL=https://github.com/pnimish/t3code.git    # public, so any Mac can fetch
FORK_PUSH_URL=git@github_pnimish:pnimish/t3code.git    # needs the github_pnimish ~/.ssh/config alias

# Offer to publish only after this commit has built and installed successfully.
offer_push() {
  if ! git fetch -q "$FORK_REMOTE" "$LOCAL_BRANCH"; then
    echo "Could not refresh $FORK_REMOTE/$LOCAL_BRANCH; skipped push." >&2
    return 0
  fi
  local remote local_tip
  remote=$(git rev-parse "refs/remotes/$FORK_REMOTE/$LOCAL_BRANCH")
  local_tip=$(git rev-parse "refs/heads/$LOCAL_BRANCH")
  [[ "$remote" == "$local_tip" ]] && return 0
  if [[ "$remote" != "$FORK_BASE" ]]; then
    echo "$FORK_REMOTE/$LOCAL_BRANCH changed during the update; rerun to integrate it before pushing." >&2
    return 0
  fi
  [[ -t 0 ]] || { echo "Fork's $LOCAL_BRANCH is out of date; not a terminal, so not pushing." >&2; return 0; }
  local answer
  if read -r -p "Build and installation succeeded. Push $LOCAL_BRANCH to $FORK_REMOTE (--force-with-lease)? [y/N] " answer && [[ "$answer" =~ ^[Yy]$ ]]; then
    git push --force-with-lease="refs/heads/$LOCAL_BRANCH:$remote" "$FORK_REMOTE" "refs/heads/$LOCAL_BRANCH:refs/heads/$LOCAL_BRANCH"
  else
    echo "Skipped push."
  fi
}

[[ -d "$REPO/.git" ]] || git clone -b "$BRANCH" https://github.com/CreepyGnome/t3code.git "$REPO"
cd "$REPO"
mkdir -p "$CACHE"

# 1. Get latest and replay our own commits ($LOCAL_BRANCH) on top of the PR branch.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Local changes in $REPO — commit/stash them first." >&2; exit 1
fi
git fetch origin "$BRANCH"
# A fresh checkout (another Mac) has neither the fork remote nor our branch yet.
if ! git remote get-url "$FORK_REMOTE" >/dev/null 2>&1; then
  git remote add "$FORK_REMOTE" "$FORK_FETCH_URL"
  git remote set-url --push "$FORK_REMOTE" "$FORK_PUSH_URL"
fi
git fetch "$FORK_REMOTE" "$LOCAL_BRANCH"
FORK_BASE=$(git rev-parse "refs/remotes/$FORK_REMOTE/$LOCAL_BRANCH")
if ! git rev-parse -q --verify "refs/heads/$LOCAL_BRANCH" >/dev/null; then
  git branch --track "$LOCAL_BRANCH" "$FORK_REMOTE/$LOCAL_BRANCH"
fi
git switch -q "$LOCAL_BRANCH"
# Include commits pushed from another checkout before replaying our changes.
if ! git merge --ff-only --quiet "$FORK_REMOTE/$LOCAL_BRANCH"; then
  echo "$LOCAL_BRANCH and $FORK_REMOTE/$LOCAL_BRANCH have diverged; reconcile them by hand, then rerun." >&2
  exit 1
fi
git branch --set-upstream-to="$FORK_REMOTE/$LOCAL_BRANCH" "$LOCAL_BRANCH" >/dev/null
OLD=$(git rev-parse HEAD)
if ! git rebase -q "origin/$BRANCH"; then
  git rebase --abort
  echo "Rebasing $LOCAL_BRANCH onto origin/$BRANCH conflicted; resolve it by hand, then rerun." >&2
  exit 1
fi
NEW=$(git rev-parse HEAD)
LAST_BUILT=$(cat "$CACHE/last-built" 2>/dev/null || true)
if [[ "$NEW" == "$LAST_BUILT" && "$FORCE" != "--force" ]]; then
  echo "Already built and installed $(git log -1 --format='%h %s' "$NEW")."; offer_push; exit 0
fi
echo "Updated $(git rev-parse --short "$OLD") -> $(git log -1 --format='%h %ci %s')"
echo "Local commits on top of origin/$BRANCH:"
git log --oneline "origin/$BRANCH..HEAD"

# 2. Resource monitor: reuse a prebuilt binary instead of compiling Rust.
if [[ ! -x "$CACHE/t3-resource-monitor" ]]; then
  [[ -x "$APP/Contents/Resources/resource-monitor/t3-resource-monitor" ]] || {
    echo "Install the official T3 Code app first (it provides the prebuilt resource monitor)." >&2; exit 1; }
  cp "$APP/Contents/Resources/resource-monitor/t3-resource-monitor" "$CACHE/"
fi
mkdir -p "$(dirname "$MONITOR_DST")"
cp "$CACHE/t3-resource-monitor" "$MONITOR_DST"
TREE=$(git rev-parse HEAD:native/resource-monitor)
if [[ -f "$CACHE/monitor-tree" && "$(cat "$CACHE/monitor-tree")" != "$TREE" ]]; then
  echo "WARNING: native/resource-monitor source changed; the cached binary may be stale." >&2
  echo "         If the app's resource stats break, build it once with cargo." >&2
fi
echo "$TREE" > "$CACHE/monitor-tree"

# 3. Toolchain: use the Node and pnpm versions pinned in package.json (via fnm).
NODE_VERSION=$(sed -n 's/.*"node": *"\([0-9.]*\)".*/\1/p' package.json | head -1)
PNPM_VERSION=$(sed -n 's/.*"packageManager": *"pnpm@\([^"]*\)".*/\1/p' package.json)
eval "$(fnm env --shell bash)"
fnm use --install-if-missing "$NODE_VERSION"
if [[ "$(pnpm --version 2>/dev/null)" != "$PNPM_VERSION" ]]; then
  npm install -g "pnpm@$PNPM_VERSION"
fi
echo "Using node $(node -v), pnpm $(pnpm --version)"

# 4. Build.
pnpm install --frozen-lockfile
rm -rf release
T3CODE_DESKTOP_REUSE_RESOURCE_MONITOR=true pnpm dist:desktop:dmg:arm64
DMG=$(ls -t release/*.dmg | head -1)

# 5. Install over the existing app.
osascript -e 'quit app "T3 Code (Beta)"' 2>/dev/null || true
sleep 2
MNT=$(mktemp -d)
hdiutil attach -nobrowse -quiet -mountpoint "$MNT" "$DMG"
trap 'hdiutil detach -quiet "$MNT" || true' EXIT
rm -rf "$APP"
ditto "$MNT/T3 Code (Beta).app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "$NEW" > "$CACHE/last-built"
echo "Installed $(git log -1 --format='%h' "$NEW") to $APP"
offer_push
