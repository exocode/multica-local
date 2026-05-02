# multica-local

Self-hosted [Multica](https://github.com/multica-ai/multica) setup for local development and personal use.

## Why this repo exists

The official Multica repo ships Docker images via GHCR that point to `api.multica.ai`. This setup lets you run the full stack locally — backend, frontend, and PostgreSQL — with all data bind-mounted to `./data/` so nothing is lost when containers are rebuilt or removed.

It also supports running a **custom fork** (e.g. with a `kilo-code-adapter` branch that registers additional AI runtimes like KiloCode) alongside the standard upstream images, and building a **local Desktop app** that connects to this instance instead of the cloud.

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- `multica` CLI: `brew install multica-ai/tap/multica`
- Go (only for fork builds): `brew install go`
- pnpm (only for desktop app builds): `npm i -g pnpm`

---

## Setup

```bash
# 1. Clone this repo
git clone <this-repo> ~/Multica
cd ~/Multica

# 2. Create your .env from the example
cp .env.example .env

# 3. Edit .env — at minimum set:
#    - JWT_SECRET   (openssl rand -hex 32)
#    - MULTICA_DEV_REPO      path to your fork (for rebuild-fork)
#    - MULTICA_UPSTREAM_REPO path to the upstream checkout (for build-app)

# 4. Start the stack and configure the daemon
./multica-local up
./multica-local setup   # first time only — registers this machine against localhost:8080
```

The `up` command starts all containers, then restarts the Multica daemon and prompts for login if not yet authenticated. Use any email address; the verification code is printed to stdout (no mail server needed locally).

---

## Commands

| Command | What it does |
|---|---|
| `./multica-local up` | Start backend + frontend + postgres, restart daemon |
| `./multica-local stop` | Stop containers and daemon (data preserved) |
| `./multica-local restart` | stop + up |
| `./multica-local status` | Container status + daemon status |
| `./multica-local logs` | Tail backend + frontend logs |
| `./multica-local backup` | pg_dump to `./backups/` |
| `./multica-local update` | Backup → pull latest GHCR images → up *(upstream mode only)* |
| `./multica-local rebuild-fork` | Backup → rebase fork → build images → up + daemon *(fork mode)* |
| `./multica-local setup` | First-time CLI / daemon configuration |
| `./multica-local doctor` | Sanity checks (ports, volumes, JWT_SECRET, images) |
| `./multica-local build-app` | Build the Electron desktop app pointing to this local instance |

---

## Modes

Mode is **auto-detected** by the presence of `compose.fork.yml`:

| File present | Mode | Images used |
|---|---|---|
| `compose.fork.yml` absent | **UPSTREAM** | `ghcr.io/multica-ai/*:latest` |
| `compose.fork.yml` present | **FORK** | `multica-backend:exocode` / `multica-frontend:exocode` (built locally) |

To switch to fork mode, create `compose.fork.yml` (see `compose.fork.yml` in this repo for the template) and run `./multica-local rebuild-fork` once.

---

## Fork / custom branch workflow

If you maintain a fork of Multica with custom changes (e.g. registering additional agent runtimes):

1. Set `MULTICA_DEV_REPO` in `.env` to point to your fork checkout.
2. Make sure your custom branch is checked out there.
3. Run:
   ```bash
   ./multica-local rebuild-fork
   ```
   This will:
   - Back up the database
   - Fetch upstream, rebase your branch, build Go binaries and Docker images
   - Restart the stack with the new images
   - Restart the daemon and handle authentication automatically

If the rebase hits conflicts, the script stops and explains what to resolve. Re-run after resolving.

---

## Desktop app (local build)

The released Multica desktop app connects to `api.multica.ai`. To build a version that connects to your local instance:

```bash
./multica-local build-app
```

Set `MULTICA_UPSTREAM_REPO` in `.env` to the path of the Multica source checkout. The built `.dmg` ends up in `<upstream-repo>/apps/desktop/dist/`.

---

## Data persistence

All persistent data lives in `./data/` (bind-mounted, not Docker-managed volumes):

| Path | Contents |
|---|---|
| `./data/postgres/` | PostgreSQL data directory |
| `./data/uploads/` | User-uploaded files |

Both are in `.gitignore`. Backups (pg_dump) are written to `./backups/`, also ignored.

---

## Upstream update notifications

`check-upstream.sh` can be triggered by a launchd agent to notify you when the upstream Multica repo has new commits. See the comments inside the script for setup instructions.
