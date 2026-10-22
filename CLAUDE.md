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
  cron.sh                crontab entries owned by dock (marker comment), cron_dock_command
  backups.sh             ./dock backups: S3 upload via aws-cli container, cron entry, retention.
                         Uses dock's db_dump_sql / db_require / cmd_db_restore / env_path.
  autodeploy.sh          ./dock autodeploy: cron fetches origin/BRANCH, runs `dock deploy -y` when ahead.
                         Uses dock's dock_state_dir / deploy_lock / DOCK_BIN.
scripts/dev/             toolkit-only dev tools (not copied into projects)
docker/
  Dockerfile             targets: local | staging | production (see header)
  AGENTS.md              shipped agent guide
  compose/               base.yml, databases/, environments/, servers/, services/
  config/                php, supervisor, nginx, caddy, fpm, postgres, build hooks (user-customisable)
```

## Invariants (don't break these)

- **bash 3.2 compatible** (macOS): no associative arrays, `${var,,}`, `mapfile`, `source <(...)`.
- **No `set -e` in `dock`/libs**; explicit `|| return 1`. `configure-app.sh` uses `set -eu`, so never use
  `((x++))` there (exits on bash ≥4 when x is 0) — use `x=$((x + 1))`.
- **No eval / string commands** for compose: `_COMPOSE_ARGS` array only.
- **Compose relative paths resolve from `docker/compose/`**, not the project root. Host paths from `.env`
  (`STORAGE_MOUNT_PATH`, `DB_MOUNT_PATH`) are made absolute by `prepare_compose_env`; compose files use
  them without defaults. Any new host-path variable must go through `resolve_mount_path`.
- `docker/compose/project.yml` (optional, project-owned, never shipped) is merged last by
  `build_compose_args`; project services are extra `services/<name>.yml` files. Never ship either name.
- Compose files only read variables `dock` exports. Derived ones come from `prepare_compose_env`:
  `DOCK_ENV` (local|staging|production, normalises `development`), `RESTART_POLICY`, `USER_ID`/`GROUP_ID`
  (host IDs, never 0), `DOCK_WITH_FRANKENPHP`, `DOCK_IMAGE_SUFFIX`, `DOCK_APP_BIND` (`APP_BIND:` or empty). Use `DOCK_ENV`, not `APP_ENV`, to pick files.
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
- DB/Redis host ports come from `docker/compose/ports/*.yml`, added only when `publish_db_port` /
  `publish_redis_port` allow (`PUBLISH_DB_PORT`, `PUBLISH_REDIS_PORT`). Keep `published_ports` in
  `checks.sh` in sync.
- Host ports of auxiliary services bind to `${SERVICES_BIND:-127.0.0.1}`. Only the app/web ports and
  Soketi are public. `FORWARD_*` vars change the host side only.
- Database images stay pinned to a major/LTS line (data dirs are major-locked). Pgvector keeps service
  name `postgres`; `pgvector` must be recognised wherever `postgres` is (`is_postgres_driver`).
- `docker/config/*` belongs to the user after install: `dock update` never overwrites it.
- Backups: remote names are UTC stamps (`BACKUP_STAMP_FORMAT`) so they sort chronologically and
  retention compares names; listing and pruning only touch names matching `BACKUP_NAME_RE`. Changing
  `BACKUP_CIPHER` makes existing backups undecryptable with the new code: don't, or support both.
  S3 credentials reach the aws-cli container via `-e VAR` (environment), never argv. The cron line is
  found by its `# dock-backups:<PROJECT_ROOT>:` marker; read the crontab fully before `crontab -`.
  `BACKUP_*` values are written single-quoted (literal for phpdotenv too).
- Cron entries (backups, autodeploy) go through `cron.sh`: marker `# dock-<kind>:<PROJECT_ROOT>:`,
  paths checked by `cron_require_safe_paths`. Changing a cron line's format makes `status` report
  installed entries as out of date.
- `docker/config/post-deploy.sh` (project-owned, host-side, run with `bash`) is the last deploy step; failure is a
  warning. Its use must stay visible: preview, run_step, summary box, `doctor`, `autodeploy status`.
- Deploy/autodeploy state lives in `.git/dock/` (never committed or in the image). `cmd_deploy` holds
  `deploy.lock` across its re-exec (same pid). `autodeploy run` must stay silent when nothing changes
  and log repeated problems once (it runs every couple of minutes).
- Risky-config checks live in `config_risks` (env.sh): `high|msg` / `warn|msg` lines, printed by
  `validate_full_env` once per run (`DOCK_CONFIG_WARNED`) and by `doctor`. Add new checks there.
- Never pass secrets as `docker exec -e VAR=value` (shows in `ps`): set the variable on the docker
  command and pass `-e VAR`.

## Dockerfile

Project hooks: `APT_PACKAGES` + `docker/config/build/runtime.sh` (app-base) and `release.sh` (release),
mounted from the named build context `dock-build` (compose `additional_contexts`; plain `docker build`
needs `--build-context dock-build=docker/config/build`), because `.dockerignore` excludes `/docker`.

`base` (PHP + extensions + composer + supervisor) → `app-base` (laravel user, project hooks) →
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

Octane images build `FROM dunglas/frankenphp:<FRANKENPHP_VERSION>-php<PHP_VERSION>-trixie`
(`DOCK_PHP_BASE_IMAGE`, set by `prepare_compose_env`), others `FROM php:<PHP_VERSION>-fpm-trixie`:
never go back to FrankenPHP's static binary, it embeds its own PHP version and extension set, so
`PHP_VERSION` would only apply to the CLI. Caddy state lives in `/data` and `/config` (owned by laravel).

## Testing changes

- `make lint`: `bash -n`, shellcheck, `docker compose config` for all 45 env/server/db combinations.
- End to end: `./configure-app.sh -t new -n Test -c dltest --non-interactive -y` in a scratch dir, then
  `./dock start`, switch `SERVER`, and `APP_ENV=production` + `git init && git commit` + `./dock deploy --skip-pull -y`.
- Keep README.md, docker/AGENTS.md, CHANGELOG.md and this file in sync with behaviour changes.
