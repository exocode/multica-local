#!/usr/bin/env bash
# sync-and-build.sh — sync your Multica fork with upstream, then build artifacts.
#
# What this does:
#   1. Sanity checks (clean tree, no rebase in progress)
#   2. git fetch upstream
#   3. git rebase kilo-code-adapter onto upstream/main
#      → STOPS on conflicts (you resolve manually, see below)
#   4. make build  → produces server/bin/multica (CLI binary)
#   5. install CLI to ~/.local/bin/multica
#   6. docker compose build backend frontend  → multica-backend:latest, multica-frontend:latest
#   7. tag those as multica-backend:exocode and multica-frontend:exocode
#      (also commit-pinned: multica-backend:exocode-<sha>)
#
# Configurable via env vars:
#   MULTICA_SRC          (default: ~/Coding/multica-development)
#   MULTICA_BRANCH       (default: kilo-code-adapter)
#   MULTICA_INSTALL_DIR  (default: ~/.local/bin)
#   MULTICA_TAG          (default: exocode) — image tag suffix
#
# When rebase fails (likely on first run since we're 225 commits behind):
#   cd ~/Coding/multica-development
#   git status                                 # see conflicted files
#   # Most likely conflict: server/pkg/agent/models.go
#   # — upstream added Kiro registration, your branch added KiloCode registration
#   # — keep BOTH (Kiro stays from upstream, KiloCode from your branch)
#   <edit conflicted files>
#   git add <files>
#   git rebase --continue
#   bash ~/Coding/multica/sync-and-build.sh   # re-run

set -euo pipefail

# --- Config ---
# Read MULTICA_DEV_REPO from .env in the same directory (~ expanded), allow env var override
_dotenv_path() { grep "^${1}=" "$(dirname "$0")/.env" 2>/dev/null | cut -d= -f2- | sed "s|^~|${HOME}|"; }
SRC="${MULTICA_SRC:-$(_dotenv_path MULTICA_DEV_REPO)}"
SRC="${SRC:-${HOME}/Coding/github/multica-development}"
BRANCH="${MULTICA_BRANCH:-kilo-code-adapter}"
INSTALL_DIR="${MULTICA_INSTALL_DIR:-$HOME/.local/bin}"
TAG="${MULTICA_TAG:-exocode}"
UPSTREAM_REF="upstream/main"

# --- Helpers ---
c_blue()  { printf "\033[1;36m%s\033[0m\n" "$*"; }
c_yel()   { printf "\033[1;33m%s\033[0m\n" "$*"; }
c_red()   { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }
die()     { c_red "ERROR: $*"; exit 1; }

# --- Validations ---
[[ -d "$SRC/.git" ]]      || die "$SRC is not a git repository"
[[ -f "$SRC/Makefile" ]]  || die "no Makefile in $SRC"
command -v go >/dev/null     || die "go not on PATH — install with: brew install go"
command -v docker >/dev/null || die "docker not on PATH"
docker info >/dev/null 2>&1  || die "docker daemon is not running"

cd "$SRC"

# --- 1. Pre-flight ---
if [[ -d .git/rebase-merge ]] || [[ -d .git/rebase-apply ]]; then
  die "Rebase already in progress. Resolve it first ('git status', 'git rebase --continue' or '--abort')."
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
  c_red "Uncommitted changes in $SRC:"
  git status -s
  die "Stash or commit before running this script."
fi

# --- 2. Ensure remotes ---
if ! git remote get-url upstream >/dev/null 2>&1; then
  c_blue ">> Adding 'upstream' remote"
  git remote add upstream https://github.com/multica-ai/multica.git
fi

# --- 3. Fetch ---
c_blue ">> Fetching upstream and origin..."
git fetch upstream main
git fetch origin "$BRANCH" || true

# --- 4. Checkout target branch ---
git checkout "$BRANCH"

AHEAD=$(git rev-list --count "${UPSTREAM_REF}..${BRANCH}")
BEHIND=$(git rev-list --count "${BRANCH}..${UPSTREAM_REF}")
c_blue ">> $BRANCH: $AHEAD ahead, $BEHIND behind $UPSTREAM_REF"

# --- 5. Rebase (if needed) ---
if [[ "$BEHIND" -eq 0 ]]; then
  c_blue ">> Already up to date with $UPSTREAM_REF, skipping rebase"
else
  # Heads-up about Kiro
  if git ls-tree -r --name-only "$UPSTREAM_REF" | grep -qE 'pkg/agent/kiro\.go$'; then
    c_yel ">> Note: upstream contains Kiro adapter (server/pkg/agent/kiro.go)."
    c_yel "   Likely rebase conflict: server/pkg/agent/models.go (Kiro vs KiloCode registration)."
    c_yel "   Resolution rule: KEEP BOTH entries."
  fi

  c_blue ">> Rebasing $BRANCH onto $UPSTREAM_REF..."
  if ! git rebase "$UPSTREAM_REF"; then
    cat >&2 <<EOF

$(c_red "✗ Rebase produced conflicts.")

What just happened:
  Your fork was $BEHIND commits behind upstream. While replaying your
  KiloCode commits on top of upstream, git hit a conflict.

Most likely conflicted file:
  server/pkg/agent/models.go     (Kiro and KiloCode register here)
  server/pkg/agent/agent.go      (agent dispatch)
  server/pkg/agent/agent_test.go (tests for agent registry)

To resolve:
  cd $SRC
  git status                                  # show conflicts
  git diff --name-only --diff-filter=U
  # Edit each conflicted file. For models.go and agent.go: keep BOTH
  # Kiro (from upstream) and KiloCode (from your branch).
  git add <resolved files>
  git rebase --continue

Then re-run:
  bash $0

Or to abort and try again later:
  cd $SRC && git rebase --abort

EOF
    exit 2
  fi
  c_blue ">> Rebase clean."
fi

COMMIT=$(git rev-parse --short HEAD)
COMMIT_FULL=$(git rev-parse HEAD)

# --- 6. Build CLI ---
c_blue ">> make build"
make build
BIN="$SRC/server/bin/multica"
[[ -x "$BIN" ]] || die "expected $BIN to be produced by 'make build'"

# --- 7. Install CLI ---
mkdir -p "$INSTALL_DIR"
install -m 0755 "$BIN" "$INSTALL_DIR/multica"
c_blue ">> Installed CLI: $INSTALL_DIR/multica"
"$INSTALL_DIR/multica" --version 2>/dev/null || true

# Warn if PATH order would shadow our install
ACTIVE=$(command -v multica || true)
if [[ -n "$ACTIVE" && "$ACTIVE" != "$INSTALL_DIR/multica" ]]; then
  c_yel "!! 'multica' on PATH resolves to: $ACTIVE"
  c_yel "   That's a different binary than what we just built."
  c_yel "   If you installed via Homebrew: 'brew unlink multica'"
  c_yel "   Or prepend $INSTALL_DIR to your PATH in ~/.zshrc."
fi

# --- 8. Build Docker images ---
# The selfhost compose file only has `image:` references (it pulls from GHCR by
# default). The .build.yml override adds the `build:` directives we need to
# compile from the current checkout. Without the override, `compose build` says
# "No services to build" and produces nothing.
c_blue ">> docker compose build backend frontend"
docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml build backend frontend

# --- 9. Re-tag with our explicit suffix ---
# The build override tags as multica-backend:dev and multica-web:dev (note: web,
# not frontend). compose.fork.yml expects multica-backend:exocode and
# multica-frontend:exocode, so we rename here.
c_blue ">> Tagging images: multica-backend:${TAG} and multica-frontend:${TAG}"
docker tag multica-backend:dev "multica-backend:${TAG}"
docker tag multica-backend:dev "multica-backend:${TAG}-${COMMIT}"
docker tag multica-web:dev     "multica-frontend:${TAG}"
docker tag multica-web:dev     "multica-frontend:${TAG}-${COMMIT}"

# --- 10. Summary ---
cat <<EOF

$(c_blue "✓ Done.")

Branch HEAD:  $COMMIT  ($(git log -1 --pretty=%s))

Built artifacts:
  CLI:      $INSTALL_DIR/multica
  Backend:  multica-backend:${TAG}    (also: multica-backend:${TAG}-${COMMIT})
  Frontend: multica-frontend:${TAG}   (also: multica-frontend:${TAG}-${COMMIT})

Recent commits:
$(git log --oneline -5 | sed 's/^/  /')

Next:
  cd ~/Coding/multica
  ./multica-local restart      # apply new images to running stack
EOF
