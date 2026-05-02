# DEV_README

Lokales Multica-Setup auf diesem Mac. Zwei parallele Stacks — original (anfassen verboten) und dev.

## Ports

| Stack | Frontend | Backend | DB | Quelle |
|---|---|---|---|---|
| **original** (prod) | 3000 | 8080 | 54332 | `~/Coding/multica/compose.local.yml` |
| **dev** | 3033 | 8088 | 5433 | dev-checkout (`.env` in der jeweiligen working-copy) |

## Profile

- CLI-Profil: `multica-dev` (`~/.multica/profiles/multica-dev/`) — zeigt auf den dev-Backend `http://localhost:8088`.

## Shell-Helpers

In `~/.dotfiles/.aliases`:

```bash
multicadev() { ... }   # ruft <repo>/server/bin/multica auf
```

`multicadev` löst den Repo-Pfad aus `git rev-parse --show-toplevel` auf und prüft, dass `server/cmd/multica/` existiert. Außerhalb eines Multica-Checkouts → Fehler. Vor dem ersten Aufruf: `cd` in den Repo.

## Erste Inbetriebnahme

```bash
cd <multica-repo>
make build                                    # Go-Binaries → server/bin/{multica,server,migrate}
multicadev login   --profile multica-dev      # einmalig, falls noch nicht eingeloggt
multicadev daemon start --profile multica-dev
pnpm install                                  # einmalig
```

Frontend dev-server (Port 3033, gegen dev-Backend :8088):

```bash
NEXT_PUBLIC_API_URL=http://localhost:8088 \
NEXT_PUBLIC_WS_URL=ws://localhost:8088/ws \
PORT=3033 \
  pnpm dev:web
```

→ Browser: http://localhost:3033

Alternativ ein `.env` mit den `NEXT_PUBLIC_*` Werten und `make dev` nutzen.

## Was bei welcher Änderung tun

| Änderung | Action |
|---|---|
| `apps/`, `packages/` (`.tsx`/`.ts`) | nichts — HMR im Browser |
| `server/cmd/server/` (Backend) | `make dev` neu starten (`go run` kompiliert beim Start) |
| `server/cmd/multica/`, `server/pkg/agent/` (Daemon/CLI) | `make build` + `multicadev daemon stop && multicadev daemon start --profile multica-dev` |
| `server/pkg/db/queries/*.sql` | `make sqlc` → `make build` |
| DB-Schema | `make migrate-up` |
| Shared deps in `package.json` | `pnpm install` |

## Verifikation

```bash
make check        # typecheck + tests + Go-Tests + E2E
# oder gezielt:
pnpm typecheck
pnpm test
make test
```

## Logs

- Daemon: `~/.multica/profiles/multica-dev/daemon.log` — `tail -f` für live.
- Backend (Container): `docker logs -f multica-backend-1`
- Frontend dev: stdout des `pnpm dev:web` Prozesses

## Häufige Fallen

- **Port 3000 belegt** → ist der Original-Stack. Dev läuft auf 3033, NICHT auf 3000.
- **Logo/UI-Änderung wird nicht sichtbar** → Frontend läuft im Docker-Container mit altem Build. Statt rebuild: `pnpm dev:web` lokal starten (Port 3033), Container vorher stoppen: `docker stop multica-frontend-1`.
- **Daemon zeigt alte Agenten-Liste** → läuft aus altem `server/bin/multica`. `make build` + Daemon-Restart.
- **Cookie-/CORS-Probleme nach Port-Wechsel** → Browser-Session leeren, neu einloggen.

## Repo-Struktur (Kurz)

- `apps/web/` — Next.js Frontend
- `apps/desktop/` — Electron
- `packages/` — shared `core`, `ui`, `views`
- `server/` — Go Backend, CLI, Daemon
- `e2e/` — Playwright

Mehr in `CLAUDE.md` (Architektur, Coding Rules, Tests).
