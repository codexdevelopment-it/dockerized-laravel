# Dockerized Laravel — Context for Claude

## What this is

A self-contained Docker toolkit you drop into any Laravel project. After running `configure-app.sh` (or `./dock install`), the target project gets a `dock` CLI, a `docker/` config tree, and a `scripts/` lib — everything needed to start, develop, and deploy without touching the host machine.

Repo: `https://github.com/Murkrow02/dockerized-laravel` (also mirrored at `codexdevelopment-it`)

## Project layout

```
dock                     Main CLI entry point (single bash file, ~880 lines)
configure-app.sh         One-shot installer: clones this repo into a target project
scripts/
  lib/
    colors.sh            ANSI color vars + icon constants
    utils.sh             Spinner, confirm(), prompt(), safe_sed(), string helpers
    env.sh               load_env(), validate_full_env(), parse_services(), get_env_compose_file()
    checks.sh            run_preflight_checks(), port checks, compose file checks, octane check
    docker.sh            build_compose_command(), docker_up/down/restart/logs/exec/status
docker/
  Dockerfile             Multi-stage: builder (composer install + copy) → runtime (php:8.3-fpm-bookworm)
  compose/
    base.yml             app + mariadb services, app-network
    environments/        local.yml  staging.yml  production.yml
    servers/             artisan.yml  fpm.yml  nginx.yml  caddy.yml  octane.yml
    services/            redis.yml  mailpit.yml  meilisearch.yml  phpmyadmin.yml  soketi.yml  gotenberg.yml
  config/
    php/                 base.ini  local.ini  staging.ini  production.ini
    supervisor/          base.conf (include glob)  server-*.conf  workers-*.conf
    nginx/               default.conf
    caddy/               Caddyfile
    fpm/                 pool.conf
```

## How the modular compose system works

`build_compose_args()` in `docker.sh` assembles a `_COMPOSE_ARGS` array (no `eval`):
1. `docker/compose/base.yml`
2. `docker/compose/databases/<DB_DRIVER>.yml`          (mariadb | postgres)
3. `docker/compose/databases/<DB_DRIVER>-<env>.yml`    (e.g. mariadb-local.yml — optional)
4. `docker/compose/environments/<APP_ENV>.yml`          (local | staging | production)
5. `docker/compose/servers/<SERVER>.yml`                (artisan | fpm | nginx | caddy | octane)
6. One file per entry in `SERVICES=redis,mailpit,...`

Everything is driven by `.env`. No separate `docker-compose.yml` lives in the project root.

### Database architecture

MariaDB and PostgreSQL each have a base file (`databases/<driver>.yml`) plus optional env-specific overrides (`databases/<driver>-local.yml` etc.). The env files (`environments/`) contain only app-service overrides — no DB config. This means adding a new DB or new env variant only requires a new file in `databases/`, not touching the env files.

## Key .env variables

| Variable | Purpose |
|---|---|
| `CONTAINER_NAME` | Prefix for all containers (`myapp`, `myapp-mariadb`, ...) |
| `APP_ENV` | `local` / `staging` / `production` — picks env compose + PHP ini |
| `DB_DRIVER` | `mariadb` (default) or `postgres` — picks database compose file |
| `SERVER` | Which server compose to load |
| `SERVICES` | Comma-separated optional services |
| `APP_PORT` | Host port mapped to container :8000 |
| `DOMAIN` | Used by Caddy for automatic HTTPS |
| `STORAGE_MOUNT_PATH` | Host path mounted as `/var/www/html/storage` in prod/staging |
| `DB_MOUNT_PATH` | Host path for MariaDB data in prod/staging |
| `USER_ID` / `GROUP_ID` | Build args for container user, auto-detected by `dock deploy` |

## Dockerfile design

- **Builder stage**: `php:8.3-fpm-bookworm`, installs Composer deps (no-dev in prod), runs `COPY . .`
- **Runtime stage**: same base, adds supervisor, PHP extensions (pdo_mysql, pdo_pgsql, gd, redis, opcache, pcntl, ...), FrankenPHP binary (always installed, ~30 MB), creates `laravel` user matching host UID/GID
- Build arg `BUILD_ENV` controls `--no-dev` and whether caches are baked in at build time
- `.dockerignore` is critical — without it, `COPY . .` clobbers the freshly-installed vendor/

## Server types

| SERVER | How it works |
|---|---|
| `artisan` | `docker exec ... php artisan serve` (started in `cmd_start`, interactive) |
| `octane` | FrankenPHP via supervisor, `server-octane-<env>.conf` |
| `fpm` | php-fpm only, no reverse proxy |
| `nginx` | nginx:alpine + php-fpm on app:9000 |
| `caddy` | caddy:alpine + php-fpm, auto HTTPS via DOMAIN |

## Environment differences

- **local**: entire project volume-mounted (`../../:/var/www/html`), DB port exposed, `optimize:clear` on start
- **staging / production**: only `storage/` and `.env` mounted, code baked in image, opcache with `validate_timestamps=0`

## Supervisor

- `base.conf` uses `[include] files = /etc/supervisor/programs/*.conf` — compose files mount specific confs into that dir
- Workers: `workers-<env>.conf` (queue:work + scheduler loop)
- Server: `server-<type>-<env>.conf` or `server-<type>.conf`

## Deploy flow (`dock deploy`)

1. git fetch + show diff summary
2. Confirm (unless `-y`)
3. git pull --rebase --autostash
4. Ensure USER_ID/GROUP_ID in .env, generate APP_KEY if missing
5. `dock start --build` (rebuilds image)
6. Wait for MariaDB healthcheck (60s timeout, 1s poll)
7. `artisan migrate --force`, storage:link, config/route/view/event cache
8. `artisan octane:reload` if SERVER=octane

## Template placeholders

`configure-app.sh` replaces `{{APP_NAME}}`, `{{CONTAINER_NAME}}`, `{{DB_NAME}}`, `{{REPO_URL}}` in `.env` and nginx/caddy configs via `sed`.

## Notable design choices

- No `set -e` in `dock` — explicit `|| return 1` used instead; avoids false failures in AND-OR chains
- `provision_app()` always returns 0 (best-effort); failures only shown in `--verbose`
- `check_required_ports()` treats port conflicts as warnings (not errors) — you still get a URL even if the port is taken
- `docker_up` in non-verbose mode suppresses all output (`>/dev/null 2>&1`) — this conflicts with the comment "Always stream docker output" in `cmd_start`; currently a known inconsistency
- `eval` is used to run compose commands built as strings in `docker.sh`
