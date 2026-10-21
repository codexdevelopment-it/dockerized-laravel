# 🐳 Dockerized Laravel

Drop-in Docker toolkit for Laravel. One installer adds a `./dock` CLI, a modular Docker Compose setup and
production-ready images to any Laravel project — new or existing. Nothing but Docker is needed on the host,
and the same `./dock deploy` command ships it to a server.

- **PHP 8.5** (configurable), Composer 2, Node 24 LTS, supervisor-managed workers and scheduler
- Servers: `artisan`, `octane` (FrankenPHP 1.13), `nginx`, `caddy` (automatic HTTPS), `fpm`
- Databases: MariaDB 11.4 LTS, PostgreSQL 16, PostgreSQL + pgvector — pinned versions
- Optional services: Redis 8, Mailpit, Meilisearch, phpMyAdmin, Soketi, Gotenberg
- One-command, idempotent deploys with preview, confirmation, optional DB backup
- Secure defaults: non-root app user, auxiliary ports bound to `127.0.0.1`, log rotation

## Contents

- [Quick start](#quick-start) · [Commands](#commands) · [Configuration](#configuration)
- [Servers](#servers) · [Databases](#databases) · [Services](#services)
- [Production deployment](#production-deployment) · [Backups](#backups) · [Updating](#updating-the-toolkit)
- [How it works](#how-it-works) · [AI agents](#ai-coding-agents) · [Troubleshooting](#troubleshooting)

## Quick start

```bash
# Existing project: run in the Laravel root
bash <(curl -fsSL https://raw.githubusercontent.com/Murkrow02/dockerized-laravel/main/configure-app.sh)

# Then
./dock start
```

The app is at `http://localhost:8000`. Choosing *new* creates `./<name>/` with a fresh Laravel app
(`composer create-project` runs inside the image).

The installer:

- copies `dock`, `scripts/lib/` and `docker/` into the project;
- **keeps your `.env`** (backup in `.env.backup-<date>`), adds the dock settings, points `DB_HOST` at the
  container and generates a random `DB_PASSWORD`;
- appends what it needs to `.dockerignore` and `.gitignore` (`/db-data`, `/backups`);
- links `docker/AGENTS.md` from `AGENTS.md` / `CLAUDE.md` for AI coding agents.

Non-interactive:

```bash
./configure-app.sh -t existing -n "My App" -c myapp --db-driver postgres --server nginx -y --non-interactive
./configure-app.sh -t new      -n "My App" -c myapp --non-interactive
```

| Flag | Description |
|---|---|
| `-t, --type` | `new` or `existing` |
| `-n, --name` | Application name |
| `-c, --container` | Container prefix (`myapp` → `myapp`, `myapp-db`, …) |
| `-d, --database` | Database name (default: container name) |
| `--db-driver` | `mariadb` (default), `postgres`, `pgvector` |
| `--server` | `artisan` (default), `octane`, `nginx`, `caddy`, `fpm` |
| `-y`, `--non-interactive` | Skip confirmation / all prompts |

## Commands

```text
Lifecycle   start [--build] [--no-cache] · stop · restart [--build] · build [--no-cache] [--pull]
            status · logs [service] [-f] [-n N] · shell [service] [--root] · config
Laravel     artisan|a · composer · npm · npx · node · php · exec [--root] · tinker · test
            pint|format · migrate · fresh · seed
Database    db · db:dump [file] · db:restore <file>
Backups     backups enable · disable · status · run · list · download [sel] · restore [sel] · prune · logs
Operations  deploy [-y] [--skip-pull] [--backup] · autodeploy enable [--every N] · disable · status · logs
            doctor · update [--check] · help [command]
Global      -v/--verbose · -q/--quiet · -y/--yes · -e/--env <file> · --debug
```

Examples:

```bash
./dock artisan make:model Post -m      # arguments pass through untouched (even -v, -h)
./dock composer require laravel/horizon
./dock npm run dev
./dock test --filter=UserTest
./dock pint --test
./dock logs app -f
./dock shell db
echo "select count(*) from users;" | ./dock db
./dock db:dump && ./dock db:restore backups/myapp-myapp-20260101-120000.sql.gz
```

`start`, `restart` and `deploy` show numbered steps with a live spinner and finish with a status table:

```text
✓ [1/4] Building image myapp:local 41s
✓ [2/4] Starting containers 3s
✓ [3/4] Installing Composer dependencies 28s
✓ [4/4] Preparing app 2s

  SERVICE        STATE        HEALTH      PORTS
  app            ● running    healthy     8000
  mariadb        ● running    healthy     127.0.0.1:3306
  redis          ● running    healthy     127.0.0.1:6379

╭───────────────────────────────────────╮
│  ✓ Ready in 1m 14s                    │
│                                       │
│  App          http://localhost:8000   │
│  Mailpit      http://localhost:8025   │
╰───────────────────────────────────────╯
```

Command output is shown only when a step fails (the relevant tail + full log path) or with `-v`.

Tool commands run as the container user `laravel`, whose UID/GID match yours, so generated files and
`storage/` logs keep the right owner. `./dock exec --root …` and `./dock shell --root` are there when you
need root. They work without a TTY too (CI, pipes).

## Configuration

Everything lives in `.env`. Docker-related keys:

| Variable | Default | Purpose |
|---|---|---|
| `CONTAINER_NAME` | — | Prefix for containers, compose project, image |
| `APP_ENV` | `local` | `local` / `staging` / `production`: compose overrides, PHP ini, workers, image target |
| `SERVER` | `artisan` | `artisan` · `octane` · `nginx` · `caddy` · `fpm` |
| `DB_DRIVER` | `mariadb` | `mariadb` · `postgres` · `pgvector` |
| `SERVICES` | — | Comma separated: `redis,mailpit,meilisearch,phpmyadmin,soketi,gotenberg` |
| `APP_PORT` | `8000` | Host port of the app (`caddy` uses `HTTP_PORT`/`HTTPS_PORT`) |
| `DOMAIN` | — | Caddy automatic HTTPS domain |
| `BRANCH` | current | Branch pulled by `./dock deploy` |
| `STORAGE_MOUNT_PATH` | `./storage` | Host dir for `storage/` (staging/production) |
| `DB_MOUNT_PATH` | `./db-data` | Host dir for database files |
| `SERVICES_BIND` | `127.0.0.1` | Interface for DB / Redis / Mailpit / … host ports |
| `FORWARD_DB_PORT`, `FORWARD_REDIS_PORT` | `3306`/`5432`, `6379` | Host-side ports (the app keeps the container ports) |
| `PUBLISH_DB_PORT` | `true` (local), `false` (staging/production) | Publish the DB port on the host. `false` keeps it docker-network only |
| `PUBLISH_REDIS_PORT` | `true` (local), `false` (staging/production) | Same for Redis |
| `MAILPIT_UI_PORT`, `MEILISEARCH_PORT`, `PHPMYADMIN_PORT`, `SOKETI_PORT`, `GOTENBERG_PORT` | defaults | Host-side ports |
| `PHP_VERSION` | `8.5` | PHP minor version of the image |
| `NODE_VERSION` | `24` | Node major (local image + asset build) |
| `PHP_EXTENSIONS` | — | Extra extensions, e.g. `"imagick soap"` ([list](https://github.com/mlocati/docker-php-extension-installer#supported-php-extensions)) |
| `FRANKENPHP_VERSION` | `1.13.0` | FrankenPHP binary for `SERVER=octane` |
| `MARIADB_VERSION`, `POSTGRES_VERSION`, `PGVECTOR_VERSION` | `11.4`, `16.15`, `0.8.7-pg17` | Database image tags (see [Databases](#databases)) |
| `NGINX_VERSION`, `CADDY_VERSION` | `stable-alpine`, `2-alpine` | Web server image tags |
| `REDIS_VERSION`, `MAILPIT_VERSION`, `MEILISEARCH_VERSION`, `PHPMYADMIN_VERSION`, `SOKETI_VERSION`, `GOTENBERG_VERSION` | see [Services](#services) | Service image tags |
| `APP_MEMORY_LIMIT`, `DB_MEMORY_LIMIT` | `1G` | Container memory limits in production |
| `USER_ID`, `GROUP_ID` | your UID/GID | Container user (written by `deploy`) |

Relative mount paths are relative to the project root. Variables already exported in your shell override
`.env` (`APP_PORT=8080 ./dock start`). After changing image settings (`PHP_*`, `NODE_VERSION`) run
`./dock start --build`; for everything else `./dock restart` is enough.

PHP tuning is in `docker/config/php/` (`base.ini` + `<env>.ini`), workers in `docker/config/supervisor/`,
web servers in `docker/config/{nginx,caddy,fpm}/`. Those files are yours to customise.

## Servers

| `SERVER` | App container | In front | Notes |
|---|---|---|---|
| `artisan` | `php artisan serve` (supervised) | — | Development only |
| `octane` | FrankenPHP worker on `:8000` | — | `laravel/octane` required (auto-installed locally). `--watch` locally: `./dock npm i -D chokidar` |
| `nginx` | php-fpm `:9000` | `nginx` | Static files served by nginx |
| `caddy` | php-fpm `:9000` | `caddy` | Automatic HTTPS for `DOMAIN` (ports 80/443) |
| `fpm` | php-fpm `:9000` | your own | FastCGI published on `127.0.0.1:APP_PORT` only |

FrankenPHP is baked only into `octane` images (tagged `<name>:<env>-octane`), so other images stay
~100 MB smaller and switching `SERVER` rebuilds automatically.

## Databases

| `DB_DRIVER` | Image | `.env` |
|---|---|---|
| `mariadb` | `mariadb:11.4` | `DB_CONNECTION=mysql`, `DB_HOST=mariadb`, `DB_PORT=3306` |
| `postgres` | `postgres:16.15-alpine` | `DB_CONNECTION=pgsql`, `DB_HOST=postgres`, `DB_PORT=5432` |
| `pgvector` | `pgvector/pgvector:0.8.7-pg17` | as `postgres`; `vector` extension created on a fresh data dir |

The DB runs as `<CONTAINER_NAME>-db`; data is bind-mounted from `DB_MOUNT_PATH`. Local publishes
the port on `127.0.0.1:FORWARD_DB_PORT` for desktop clients; staging and production publish nothing. Set
`PUBLISH_DB_PORT=true` to publish it there too (still on `SERVICES_BIND`).

Versions are pinned (override with `MARIADB_VERSION` / `POSTGRES_VERSION` / `PGVECTOR_VERSION`) so a
rebuild never silently changes the major that owns the data dir. Same-major bumps are safe in place
(MariaDB runs `mariadb-upgrade` automatically); a PostgreSQL major bump needs `./dock db:dump`, a fresh
`DB_MOUNT_PATH`, then `./dock db:restore`.

## Services

| Service | Image | Host port (on `SERVICES_BIND`) | From the app |
|---|---|---|---|
| `redis` | `redis:8-alpine` | `FORWARD_REDIS_PORT` 6379 (local only, or `PUBLISH_REDIS_PORT=true`) | `redis:6379` |
| `mailpit` | `axllent/mailpit:v1.31` | UI 8025, SMTP 1025 | `mailpit:1025` |
| `meilisearch` | `getmeili/meilisearch:v1.54` | 7700 | `http://meilisearch:7700` |
| `phpmyadmin` | `phpmyadmin:5.2` | 8080 | MariaDB only |
| `soketi` | `quay.io/soketi/soketi` | 6001 (public, `SOKETI_BIND`) | `soketi:6001` |
| `gotenberg` | `gotenberg/gotenberg:8` | 3000 | `http://gotenberg:3000` |

Each image tag is pinned and overridable from `.env` (`REDIS_VERSION`, `MAILPIT_VERSION`,
`MEILISEARCH_VERSION`, `PHPMYADMIN_VERSION`, `SOKETI_VERSION`, `GOTENBERG_VERSION`); the template lists
every pin with its default, one per line, ready to uncomment.
Outside local set `MEILISEARCH_KEY` (16+ chars) and `MEILI_ENV=production`.

## Production deployment

Clone the app once on the server, write the `.env`, then `./dock deploy` forever after.

### 1. Server (one-time)

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo adduser deploy && sudo usermod -aG docker deploy   # deploy as a non-root user
sudo -iu deploy
ssh-keygen -t ed25519 -C "deploy@$(hostname)"            # add ~/.ssh/id_ed25519.pub as a read-only deploy key
```

### 2. Clone and configure

```bash
git clone git@github.com:you/myapp.git /srv/myapp && cd /srv/myapp
cp .env.example .env && nano .env
```

```env
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
APP_KEY=                       # generated by the first deploy
CONTAINER_NAME=myapp
SERVER=caddy                   # or octane / nginx
DOMAIN=app.example.com
DB_DRIVER=mariadb
DB_HOST=mariadb
DB_DATABASE=myapp
DB_USERNAME=app
DB_PASSWORD=<long random password>
SERVICES=redis
BRANCH=main
STORAGE_MOUNT_PATH=/srv/data/myapp/storage   # absolute paths recommended
DB_MOUNT_PATH=/srv/data/myapp/db
```

### 3. Deploy

```bash
./dock deploy            # interactive: shows incoming commits, asks to confirm
./dock deploy -y --backup  # CI / cron: no prompt, dump the DB first
```

What it does:

1. `git fetch` the `BRANCH`, show commits/files to deploy (and flag new migrations) and risky settings, confirm.
2. `git pull --ff-only --autostash`, then continue with the freshly pulled `dock`.
3. Write `USER_ID`/`GROUP_ID` and a missing `APP_KEY` to `.env`, `chmod 600 .env`, fix storage ownership.
4. Optional `db:dump` (`--backup`), build the image, recreate containers.
5. Copy built assets to the host (`nginx`/`caddy` serve `public/` from it).
6. Wait for the DB healthcheck, `migrate --force`, `storage:link`, config/route/view/event caches,
   `filament:optimize` when present.
7. Reload the server (opcache never revalidates in production) and `queue:restart`.

It is idempotent: with no new commits it rebuilds and re-runs migrations. It exits non-zero if migrations fail.
Only one deploy runs at a time (lock in `.git/dock/`).

### Auto-deploy (optional)

Let the server deploy every push to `BRANCH` by itself, from the host's cron:

```bash
./dock autodeploy enable            # every 2 minutes (AUTODEPLOY_INTERVAL)
./dock autodeploy enable --every 5  # saves AUTODEPLOY_INTERVAL=5 to .env
./dock autodeploy                   # status: cron, last check, last deploy, problems
./dock autodeploy logs -f           # deploy output (.git/dock/autodeploy.log)
./dock autodeploy disable
```

Each run does `git fetch origin BRANCH`; when origin is ahead it runs `./dock deploy -y` for the `APP_ENV`
in `.env` (runs with nothing new write nothing). `enable` first checks that git can fetch the way cron
will (no ssh-agent, no passphrase prompt): use a deploy key without passphrase. A deploy never overlaps
another one, a failed deploy is not retried for the same commit (push a fix or run `./dock deploy`), and
repeated problems (fetch failing, diverged checkout) are logged once. Until it is enabled, `./dock deploy`
shows the command to enable it; `AUTODEPLOY=false` in `.env` hides that hint.

> Anyone who can push to `BRANCH` deploys to the server, migrations included: protect the branch.

### HTTPS

`SERVER=caddy` + `DOMAIN`: certificates are issued on the first request. DNS must point at the server and
ports 80/443 must be open. Behind another proxy, use `nginx`/`octane` and terminate TLS there.

### Security notes

- The app runs as an unprivileged user; supervisor is the only root process.
- DB, Redis, Mailpit, Meilisearch, phpMyAdmin, Gotenberg and FastCGI are published on `127.0.0.1` only —
  Docker port publishing bypasses `ufw`, so never set `SERVICES_BIND=0.0.0.0` on a public host. Use an SSH
  tunnel (`ssh -L 8080:127.0.0.1:8080 server`) for phpMyAdmin.
- nginx and Caddy only hand `/index.php` to PHP: an uploaded `.php` in `public/storage` is never executed.
- Container logs rotate (3 × 10 MB per container).
- `start`, `deploy` and `doctor` warn about risky settings: `APP_DEBUG=true`, default or short
  `DB_PASSWORD`, `DB_USERNAME=root`, DB/Redis/phpMyAdmin/FastCGI published on a non-loopback
  `SERVICES_BIND`, default `MEILISEARCH_KEY` / Soketi secret, `MEILI_ENV`, Caddy without `DOMAIN`,
  localhost `APP_URL`, `MAIL_HOST=mailpit`, `LOG_LEVEL=debug`, a `DB_PASSWORD` with `${`
  (Laravel expands it, the database doesn't). Mount paths pointing at system directories, the project
  root or each other are refused (deploy chowns `STORAGE_MOUNT_PATH` recursively).

## Backups

Encrypted, off-site database backups on any S3-compatible storage (AWS S3, DigitalOcean Spaces,
Cloudflare R2, MinIO, …), scheduled with the host's cron. Run it on the server, in the project:

```bash
./dock backups enable         # asks for what .env is missing, checks the bucket, installs the cron job
./dock backups enable --reconfigure   # change settings later (keeps the encryption password)
./dock backups                # status: schedule, last run, how many backups, newest / oldest
./dock backups list           # remote backups, numbered (1 = newest)
./dock backups restore latest # download, decrypt, db:restore (asks first)
```

Each run dumps `DB_DATABASE` (MariaDB or PostgreSQL), gzips it, encrypts it with `openssl`
(AES-256-CBC, PBKDF2-SHA256, 200k iterations) and uploads `<BACKUP_S3_PATH>/2026-01-31T03-00-00Z.sql.gz.enc`
(UTC), then deletes backups older than `BACKUP_KEEP_DAYS` in one batch call (never the newest one, never
other files in the folder). If the upload fails the file stays in `backups/pending/` and the next run
retries it. Runs never overlap (lock in `backups/`). The result of the last run is in `backups/last-run`
(shown by `status` and `doctor`); cron output goes to `backups/backup.log` (`./dock backups logs -f`,
trimmed automatically).

| Variable | Default | Purpose |
|---|---|---|
| `BACKUP_S3_ENDPOINT` | — (AWS) | e.g. `https://fra1.digitaloceanspaces.com`, `https://<id>.r2.cloudflarestorage.com` |
| `BACKUP_S3_REGION` | `us-east-1` | Signing region (`fra1`, `auto`, …) |
| `BACKUP_S3_BUCKET` | — | Bucket |
| `BACKUP_S3_PATH` | `CONTAINER_NAME` | Folder in the bucket |
| `BACKUP_S3_ACCESS_KEY`, `BACKUP_S3_SECRET_KEY` | — | Credentials (read/write/delete on the bucket) |
| `BACKUP_PASSWORD` | generated by `enable` if left empty | Encryption password |
| `BACKUP_KEEP_DAYS` | `30` | Retention, `0` keeps everything |
| `BACKUP_SCHEDULE` | `0 3 * * *` | Cron expression in server time (`@daily` works too) |
| `BACKUP_AWS_CLI_IMAGE` | `amazon/aws-cli:2.27.50` | Image used for S3 calls |

> **Keep a copy of `BACKUP_PASSWORD` outside the server** (password manager). Without it the backups
> can't be decrypted, and losing the server loses the `.env`.

Other commands: `run` (back up now), `download [sel]` (decrypted `.sql.gz` in `backups/downloads/`),
`prune`, `disable` (removes the cron job, keeps settings and backups). `sel` is `latest`, a number from
`list` or a file name; omitted, dock asks. The host needs docker, openssl and cron: the AWS CLI runs in a
container, credentials are passed through the environment. After editing `BACKUP_SCHEDULE` in `.env`, run
`enable` again (`status` flags an out-of-date cron entry). Decrypting by hand:
`openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -in FILE.sql.gz.enc -out FILE.sql.gz`.

## Updating the toolkit

```bash
./dock update --check    # list what changed upstream
./dock update            # replace dock, scripts/lib, docker/compose, Dockerfile, docker/AGENTS.md
./dock start --build
```

`docker/config/*` is never overwritten: new files are added and changed ones are listed for manual merging.
`DOCK_REPO` / `DOCK_BRANCH` select a fork or branch.

## How it works

`dock` assembles the compose file list from `.env` (no `docker-compose.yml` in your project):

```text
docker/compose/base.yml                          app service, network, PHP ini, supervisor
docker/compose/databases/<DB_DRIVER>.yml         + <DB_DRIVER>-<env>.yml
docker/compose/environments/<env>.yml            local: whole project mounted; else storage + .env
docker/compose/servers/<SERVER>.yml              server program + front container
docker/compose/services/<service>.yml            one per SERVICES entry
```

The Dockerfile has three targets: `local` (PHP + Node, no code: builds in seconds and never reads the build
context), `staging` and `production` (vendor and built assets baked in; dev dependencies dropped in
production; node_modules never shipped). PHP extensions are compiled once in a shared `base` stage.

```text
├── dock                     CLI
├── scripts/lib/             colors, utils, env, checks, docker, ui, backups
└── docker/
    ├── Dockerfile
    ├── AGENTS.md            usage guide for AI coding agents
    ├── compose/             base, databases, environments, servers, services
    └── config/              php, supervisor, nginx, caddy, fpm, postgres
```

| | Local | Staging | Production |
|---|---|---|---|
| Code | bind-mounted | in image | in image |
| Composer dev deps | yes | yes | no |
| OPcache timestamps | validated | every 60 s | never (server reloaded on deploy) |
| JIT | off | function | tracing |
| Queue | `queue:listen` | `queue:work` ×1 + `schedule:work` | `queue:work` ×2 + `schedule:work` |

## AI coding agents

Projects get `docker/AGENTS.md`, a compact guide that tells agents (Claude Code, Codex, Cursor, …) to run
everything through `./dock`, which commands exist and what needs confirmation. The installer links it at
the top of `AGENTS.md` / `CLAUDE.md`. This repo's own contributor notes are in [`CLAUDE.md`](CLAUDE.md).

## Troubleshooting

Start with `./dock doctor`.

| Symptom | Fix |
|---|---|
| Port already in use | Change `APP_PORT` (or `FORWARD_DB_PORT`, …) in `.env`, `./dock restart` |
| `Permission denied` in `storage/` | `./dock restart` re-applies ownership; UID mismatch: `./dock start --build` |
| Container UID ≠ `USER_ID` warning | `./dock start --build` |
| `.env` change ignored | `./dock restart` (staging/production mount `.env` read-only) |
| `Cannot connect to the Docker daemon` | `sudo usermod -aG docker $USER && newgrp docker` |
| `git fetch` fails on deploy | Add the server key as a deploy key |
| Diverged checkout on deploy | Resolve by hand: deploy only fast-forwards |
| Production page shows stale code | `./dock deploy --skip-pull -y` |
| Auto-deploy does nothing | `./dock autodeploy status` (problem, last check); `./dock autodeploy logs` |
| Backup upload failed | `./dock backups logs`; the file waits in `backups/pending/` and the next run retries it |
| Cron backups never run | `./dock backups status`; check the cron service is running (`systemctl status cron`) |
| Old setup: DB data in `docker/compose/db-data` | Still used automatically (dock warns); move it to `./db-data` when convenient |

## Contributing

```bash
make lint      # shellcheck + bash -n + compose config for every env/server/db combination
```

CI runs the same checks on every push (`.github/workflows/ci.yml`). See [CHANGELOG.md](CHANGELOG.md).

## License

MIT
