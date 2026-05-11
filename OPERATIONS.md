# Multica — Operations Runbook (Local Self-Host)

This runbook is the **authoritative guide** for starting, stopping, updating,
and backing up this Multica install. It supersedes generic instructions in the
upstream `SELF_HOSTING.md`, because **this folder runs a customized self-host
setup with bind-mounted data** instead of Docker named volumes.

> If a command in upstream docs conflicts with what's written here — follow
> this file. The upstream docs assume the default Docker volumes; we don't.

---

## Why this is different from upstream

| Upstream default (`docker-compose.selfhost.yml`) | This folder (`compose.local.yml`) |
|---|---|
| Postgres data in Docker named volume `pgdata` | Postgres data in `./data/postgres/` (bind mount) |
| Uploads in named volume `backend_uploads` | Uploads in `./data/uploads/` (bind mount) |
| Backend/frontend built from source on the fly | Official GHCR images: `ghcr.io/multica-ai/multica-backend:latest`, `ghcr.io/multica-ai/multica-web:latest` |
| `docker compose down -v` deletes data | `down -v` does **not** touch our bind mounts (Docker doesn't manage them) |

**Consequence:** the data is sitting in plain folders that Time Machine, rsync,
and your backup tool can see directly. But you must always remember to use
`-f compose.local.yml` — the default `docker compose up` would start a
different setup (the bare `docker-compose.yml` Postgres-only stub) and
**ignore your data**.

---

## Quick reference

```bash
cd ~/Coding/multica

# Start everything via the wrapper
./multica-local up

# Status
./multica-local status

# Stop (safe)
./multica-local stop

# Logs (tail)
./multica-local logs
```

CLI / daemon (only needed once after install or when re-authenticating):

```bash
./multica-local setup
./multica-local daemon restart
./multica-local daemon status
```

Open: http://localhost:9000 — login email + master code `888888`.

---

## Start procedure

### A) Cold start (after reboot / fresh shell)

```bash
cd ~/Coding/multica
./multica-local up
./multica-local daemon status   # sanity check
```

That's it. Containers start, Postgres mounts `./data/postgres`, backend
auto-runs migrations, frontend connects.

### B) First-ever start on a new machine

1. Make sure Docker Desktop is running.
2. Confirm the local images exist:
   ```bash
   docker image ls | grep -E "multica-backend|multica-frontend|pgvector"
   ```
   If any are missing, see **Rebuilding images** below.
3. Confirm `.env` exists and has a real `JWT_SECRET` (not `change-me-in-production`):
   ```bash
   grep JWT_SECRET .env
   # If it shows the default, regenerate:
   #   sed -i '' "s/^JWT_SECRET=.*/JWT_SECRET=$(openssl rand -hex 32)/" .env
   ```
4. Start everything and configure the daemon:
   ```bash
   ./multica-local up
   ./multica-local setup
   ```
5. Verify daemon status:
   ```bash
   ./multica-local daemon status
   ```

> **Important:** `multica setup self-host` does **not** start Docker. It only
> configures the CLI to point at `localhost:8080/3000` and starts the daemon.
> Docker must already be up.

---

## Stop procedure

```bash
cd ~/Coding/multica
./multica-local stop
./multica-local daemon stop
```

`stop` keeps containers around so the next `up` is fast. Use `down`
(without `-v`!) only if you want to fully remove containers.

---

## Update procedure

This setup uses the **official GHCR images**, so updates are just pull +
recreate. Bind-mounted data (`./data/postgres`, `./data/uploads`) is never
touched by Docker during this process.

```bash
cd ~/Coding/multica

# Easiest — wrapper does backup + pull + up + log-tail in one shot
./multica-local update

# Or, if you just want to control the daemon through the wrapper
./multica-local daemon restart
./multica-local daemon status
```

Manually, if you prefer:

```bash
cd ~/Coding/multica

# 1. Backup
./multica-local backup

# 2. Pull latest images
docker compose -f compose.local.yml pull

# 3. Recreate containers — data folders are untouched
docker compose -f compose.local.yml up -d

# 4. Watch migrations apply
docker compose -f compose.local.yml logs -f --tail=100 backend
# Look for "migrations applied" / "listening on :8080"
```

### Pinning a specific version (recommended for production-ish use)

`:latest` is convenient but means "whatever GHCR happens to serve today".
For predictable updates, pin a tag in `compose.local.yml`:

```yaml
backend:
  image: ghcr.io/multica-ai/multica-backend:v1.2.3
frontend:
  image: ghcr.io/multica-ai/multica-web:v1.2.3
```

Available tags: https://github.com/multica-ai/multica/pkgs/container/multica-backend
Update by bumping the tag and re-running `./multica-local update`.

### Rolling back

If an update breaks something:

```bash
cd ~/Coding/multica
docker compose -f compose.local.yml stop
# Edit compose.local.yml, set the image tag back to the previous version
docker compose -f compose.local.yml up -d
# If the DB schema also changed and won't accept the old binary,
# restore from the pre-update pg_dump (see Backup & restore section).
```

---

## Backup & restore

### Backup

Two complementary backups, do both:

```bash
cd ~/Coding/multica

# 1. Logical pg_dump (portable, restore-anywhere)
mkdir -p backups
docker exec multica-local-postgres-1 pg_dump -U multica -d multica -Fc \
  > backups/multica-$(date +%Y%m%d-%H%M%S).dump

# 2. Filesystem snapshot (fast, captures uploads too)
cp -R ./data ./data-snapshot-$(date +%Y%m%d-%H%M%S)
# or with rsync to external disk:
# rsync -aH --delete ./data/ /Volumes/Backup/multica-data/
```

Automate with a `launchd` job (recommended for daily backups). Skeleton:
`~/Library/LaunchAgents/com.multica.backup.plist` running the pg_dump command
once a day.

### Restore

```bash
cd ~/Coding/multica

# Stop the writers
docker compose -f compose.local.yml stop backend frontend

# Restore a pg_dump
cat backups/YOUR_BACKUP.dump | \
  docker exec -i multica-local-postgres-1 \
  pg_restore -U multica -d multica --clean --if-exists

# Bring writers back
docker compose -f compose.local.yml up -d backend frontend
```

### Restore from filesystem snapshot

```bash
cd ~/Coding/multica
docker compose -f compose.local.yml down       # NO -v
rm -rf ./data
mv ./data-snapshot-YYYYMMDD-HHMMSS ./data
docker compose -f compose.local.yml up -d
```

---

## Anti-patterns — never run these against this folder

| Command | What it does | Why it's bad here |
|---|---|---|
| `docker compose up -d` (no `-f`) | Uses `docker-compose.yml` (Postgres-only stub) | Won't start backend/frontend, may confuse things |
| `docker compose -f compose.local.yml down -v` | `down` + remove volumes | The `-v` flag wouldn't touch our bind mounts but **would** delete any leftover named volumes from older setups — only relevant if you have old data to migrate, but generally avoid the habit |
| `docker volume prune` / `docker system prune --volumes` | Removes "dangling" volumes | Same risk as above; build the muscle memory of *not* running these on this machine |
| `make selfhost` | Upstream's "easy" startup | Uses `docker-compose.selfhost.yml` with **named volumes** — would start a parallel install with empty data |
| `multica setup self-host` (without `--profile local`) | Configures the **default** profile | Fragments your config; stick to `--profile local` for this install |
| `rm -rf ./data` | — | Self-explanatory. Never. |

---

## Troubleshooting

**Containers up but website blank / 502:**
- Tail backend logs: `docker compose -f compose.local.yml logs -f backend`
- Check `JWT_SECRET` is set in `.env` (the local compose marks it required: `${JWT_SECRET:?...}`).

**Postgres won't start ("incompatible data directory"):**
- The `./data/postgres` folder was created by a different Postgres major version.
  Restore from a `pg_dump` backup against a fresh data dir.

**`multica` CLI talks to the wrong server:**
- Check active profile: `multica --profile local config show`
- Re-run: `multica --profile local setup self-host --port 8080 --frontend-port 3000`

**"Where is my data, exactly?"**
- Database: `~/Coding/multica/data/postgres/`
- Uploaded files: `~/Coding/multica/data/uploads/`
- pg_dumps: `~/Coding/multica/backups/`
- Daemon workspace cache: `~/multica_workspaces_local/` (regeneratable, not data)

---

## Sanity-check before any update or risky operation

```bash
cd ~/Coding/multica

# 1. Which compose file would `docker compose` use by default? (should warn you about ambiguity)
docker compose config --services 2>&1 | head -5

# 2. Confirm the file you intend to use
docker compose -f compose.local.yml config --services
# Expected: postgres, backend, frontend

# 3. Confirm your data is bind-mounted, not in a volume
docker compose -f compose.local.yml config | grep -A2 "volumes:" | head -20
# Expected: ./data/postgres, ./data/uploads

# 4. Make a backup
mkdir -p backups
docker exec multica-local-postgres-1 pg_dump -U multica -d multica -Fc \
  > backups/multica-$(date +%Y%m%d-%H%M%S).dump
```

If any of (2) or (3) doesn't match — **stop and figure out why** before running
anything else. That's the moment data gets lost.
