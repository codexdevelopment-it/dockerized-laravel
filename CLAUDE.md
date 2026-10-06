# Dockerized Laravel — contributor notes for Claude

## What this is

A Docker toolkit dropped into Laravel projects. `configure-app.sh` copies `dock`, `scripts/lib/` and
`docker/` into the target project and merges dock settings into its `.env`. The target project then uses
`./dock` for everything (dev, deploy). `docker/AGENTS.md` is the *user-facing* agent guide shipped to
projects; this file is for working on the toolkit itself.

Repo: `https://github.com/Murkrow02/dockerized-laravel` (mirror: `codexdevelopment-it`). The installer and
`dock update` default to Murkrow02 (`DOCKERIZED_LARAVEL_REPO`, `DOCK_REPO` override).

## Layout

```
dock                     CLI (single bash file): arg parsing, commands, deploy, doctor, update
configure-app.sh         installer (new + existing projects), standalone (no lib sourcing)
.env                     template copied by the installer ({{APP_NAME}}, {{CONTAINER_NAME}}, {{DB_NAME}}, {{DB_PASSWORD}})
scripts/lib/
  colors.sh              colors (NO_COLOR aware), print_* helpers
  utils.sh               confirm, safe_sed, set_env_value/get_env_value, abs_path, random_base64
  env.sh                 load_env, validate_full_env, prepare_compose_env, parse_services, resolve_mount_path
  checks.sh              check_docker, port checks, run_preflight_checks
  ui.sh                  run_step (numbered steps, spinner, log capture), step_note, print_box, fmt_duration
  docker.sh              build_compose_args/compose, app_exec/app_run/app_try, reload_app_server, app_url
scripts/dev/             toolkit-only dev tools (not copied into projects)
docker/
  Dockerfile             targets: local | staging | production (see header)
  AGENTS.md              shipped agent guide
  compose/               base.yml, databases/, environments/, servers/, services/
  config/                php, supervisor, nginx, caddy, fpm, postgres (user-customisable)
```

## Invariants (don't break these)

- **bash 3.2 compatible** (macOS): no associative arrays, `${var,,}`, `mapfile`, `source <(...)`.
- **No `set -e` in `dock`/libs**; explicit `|| return 1`. `configure-app.sh` uses `set -eu`, so never use
  `((x++))` there (exits on bash ≥4 when x is 0) — use `x=$((x + 1))`.
- **No eval / string commands** for compose: `_COMPOSE_ARGS` array only.
- **Compose relative paths resolve from `docker/compose/`**, not the project root. Host paths from `.env`
  (`STORAGE_MOUNT_PATH`, `DB_MOUNT_PATH`) are made absolute by `prepare_compose_env`; compose files use
  them without defaults. Any new host-path variable must go through `resolve_mount_path`.
- Compose files only read variables `dock` exports. Derived ones come from `prepare_compose_env`:
  `DOCK_ENV` (local|staging|production, normalises `development`), `RESTART_POLICY`, `USER_ID`/`GROUP_ID`
  (host IDs, never 0), `DOCK_WITH_FRANKENPHP`, `DOCK_IMAGE_SUFFIX`. Use `DOCK_ENV`, not `APP_ENV`, to pick files.
- Container commands run as `laravel` (`app_exec`/`app_run`); root only for chown/supervisorctl
  (`--root`). Running artisan as root creates root-owned logs/caches the app can't write.
- `app_exec` adds `-t` only when stdin and stdout are TTYs.
- Long operations go through `run_step "<label>" <cmd>` after `steps_begin <total>` (compute the total
  up front, see `start_stack_steps`). The command runs in the current shell (exports survive) with
  stdout/stderr captured and stdin from /dev/null, so nothing inside a step may prompt. Inside a step,
  `step_note`, `print_warning` and `print_error` lines are re-shown under the result; everything else
  only appears on failure or with `-v`.
- Passthrough commands (artisan, composer, npm, php, exec, ...) receive args verbatim: global flags are only
  parsed before the command, or after it for dock's own commands (`PASSTHROUGH_COMMANDS` in `dock`).
- `load_env`: shell environment wins over `.env`. Code that changes `.env` mid-run must also `export`.
- Host ports of auxiliary services bind to `${SERVICES_BIND:-127.0.0.1}`. Only the app/web ports and
  Soketi are public. `FORWARD_*` vars change the host side only.
- Database images stay pinned to a major/LTS line (data dirs are major-locked). Pgvector keeps service
  name `postgres`; `pgvector` must be recognised wherever `postgres` is (`is_postgres_driver`).
- `docker/config/*` belongs to the user after install: `dock update` never overwrites it.

## Dockerfile

`base` (PHP + extensions + composer + supervisor) → `app-base` (laravel user, optional FrankenPHP) →
`local` (+ Node) / `release` (code from `builder`) → `staging`, `production`. `builder` does composer
(no-dev in production), `package:discover` (bootstrap/cache from the host is ignored), npm build, drops
node_modules. Only `view:cache` at build time: config/route/event caches need the real `.env` (APP_KEY
affects Livewire's route prefix) and are built by `dock deploy`, which then reloads the server because
production opcache never revalidates.

## Runtime

Supervisor (`docker/config/supervisor/base.conf`) includes `/etc/supervisor/programs/*.conf`:
`10-workers.conf` (workers-<env>.conf) and `20-server.conf` (server-artisan / server-fpm /
server-octane-<env>). Program names used by dock: `artisan-serve`, `php-fpm`, `octane`. The app
healthcheck is `supervisorctl status`. After provisioning, `dock start` runs `supervisorctl start all`
to revive programs that went FATAL while `vendor/` was missing.

FrankenPHP's static binary embeds its own PHP and only reads `/etc/frankenphp/php.d/*.ini`;
`servers/octane.yml` mounts the PHP inis there too.

## Testing changes

- `make lint`: `bash -n`, shellcheck, `docker compose config` for all 45 env/server/db combinations.
- End to end: `./configure-app.sh -t new -n Test -c dltest --non-interactive -y` in a scratch dir, then
  `./dock start`, switch `SERVER`, and `APP_ENV=production` + `git init && git commit` + `./dock deploy --skip-pull -y`.
- Keep README.md, docker/AGENTS.md, CHANGELOG.md and this file in sync with behaviour changes.
