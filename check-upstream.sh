#!/usr/bin/env bash
# check-upstream.sh — runs weekly via launchd; notifies if upstream/main has
# moved ahead of your kilo-code-adapter branch.
#
# Does NOT build or rebase anything. Just checks + macOS notification.
# Triggered by: ~/Library/LaunchAgents/com.exocode.multica.upstream-check.plist

set -euo pipefail

SRC="${MULTICA_SRC:-$HOME/Coding/multica-development}"
BRANCH="${MULTICA_BRANCH:-kilo-code-adapter}"

# launchd starts with a minimal PATH; make sure git/osascript resolve.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Always log timestamp so the launchd logs are useful.
echo "[$(date '+%Y-%m-%d %H:%M:%S')] checking $BRANCH against upstream/main"

if [[ ! -d "$SRC/.git" ]]; then
  echo "  $SRC is not a git repo, skipping"
  exit 0
fi

cd "$SRC"

# Fetch quietly. Network errors should NOT spam the user — exit silently.
if ! git fetch --quiet upstream main 2>/dev/null; then
  echo "  git fetch failed (offline?), skipping"
  exit 0
fi

BEHIND=$(git rev-list --count "${BRANCH}..upstream/main" 2>/dev/null || echo "0")
echo "  $BRANCH is $BEHIND commits behind upstream/main"

if [[ "$BEHIND" -eq 0 ]]; then
  exit 0
fi

# Subject of latest upstream commit, sanitized for AppleScript single-line use.
LAST=$(git log -1 --pretty='%h %s' upstream/main 2>/dev/null | tr -d '"\\' | cut -c1-80)

# Build the AppleScript with %q-style escaping safe for double-quoted string.
# osascript can be picky; we keep the message ASCII-friendly.
TITLE="Multica upstream update available"
SUBTITLE="$BEHIND new commit(s) on upstream/main"
MESSAGE="cd ~/Coding/multica && ./multica-local rebuild-fork  ($LAST)"

/usr/bin/osascript <<APPLESCRIPT
display notification "${MESSAGE//\"/\\\"}" with title "${TITLE}" subtitle "${SUBTITLE}"
APPLESCRIPT

echo "  notification sent"
