# Changelog

## Unreleased

### Changed

- The `.env` template lists every image pin on its own line with its default (`PHP_VERSION`,
  `NODE_VERSION`, `FRANKENPHP_VERSION`, `MARIADB_VERSION`, `POSTGRES_VERSION`, `PGVECTOR_VERSION`,
  `NGINX_VERSION`, `CADDY_VERSION`, `REDIS_VERSION`, `MAILPIT_VERSION`, `MEILISEARCH_VERSION`,
  `PHPMYADMIN_VERSION`, `SOKETI_VERSION`, `GOTENBERG_VERSION`), so a project pins one by uncommenting
  it. The compose defaults are unchanged.

## 3.0.0 — 2026-10-05

### Upgrade notes

- Run `./dock update` (or reinstall), then `./dock start --build`. Images are retagged
  (`<name>:<env>`, `<name>:<env>-octane`), so the first start rebuilds.
- **Default PHP is 8.5.** Pin `PHP_VERSION=8.4` (or 8.3) in `.env` if the app isn't ready.
- Relative `STORAGE_MOUNT_PATH` / `DB_MOUNT_PATH` now resolve from the project root, as documented.
  Before, compose resolved them from `docker/compose/`: a production `./storage` actually mounted an empty
  `docker/compose/storage`. Data already in `docker/compose/db-data` keeps being used (dock prints a
  warning); move it to `./db-data` when convenient and add `/db-data` to `.dockerignore`/`.gitignore`.
- DB / Redis / Mailpit / Meilisearch / phpMyAdmin / Gotenberg / FastCGI ports bind to `127.0.0.1`
  (`SERVICES_BIND`). Host-side ports moved to `FORWARD_DB_PORT` / `FORWARD_REDIS_PORT`, so `DB_PORT` and
  `REDIS_PORT` are again only what the app connects to.
- `SERVER=artisan` runs under supervisor on container port 8000: `./dock start` returns, logs are in
  `./dock logs app`.
- Meilisearch default is v1.54 (was v1.5): an existing index needs a dump/import or `scout:import`, or pin
  `MEILISEARCH_VERSION=v1.5.0`.
- Production app memory limit default 1G (`APP_MEMORY_LIMIT`), was 512M.
- Restart policy outside local is `unless-stopped` (was `always`).

### Fixed

- Installer died at the first step on Linux (`((step++))` under `set -e`, bash ≥ 4).
- Production images shipped the host's `bootstrap/cache/packages.php`: dev-only providers (e.g. Pail)
  broke artisan with `--no-dev`. The manifest is rebuilt in the image.
- `dock artisan/composer/migrate/deploy` ran as root, leaving root-owned `storage/logs` and caches the app
  couldn't write. Everything runs as `laravel` now.
- Global flags were parsed anywhere: `./dock artisan test -v`, `./dock npm version`, `./dock composer -V`
  were swallowed by dock. Wrapped tools now get their arguments verbatim.
- `docker exec -it` failed without a TTY (CI, pipes): `-t` is only added for terminals.
- `./dock npm` failed: Node wasn't in the runtime image. Local image ships Node 24 (also enables
  `octane --watch`).
- `git fetch`/`git pull` failures in deploy were not detected (grep in the pipeline masked exit codes);
  pull is now `--ff-only` and stops on divergence. Deploy checks the checked-out branch matches `BRANCH`.
- Deploy continued and reported success after failed migrations; it now exits non-zero.
- Deploy as root made `.env` unreadable for the container user (600 root-owned); ownership is fixed.
- `start --no-cache` was parsed but ignored.
- `APP_ENV=development` mounted non-existent ini/supervisor files.
- phpMyAdmin with PostgreSQL broke compose (`depends_on: mariadb`); now a clear validation error.
- Typos in `SERVICES` were silently ignored; now an error.
- `dock shell` fell back to `sh` whenever the bash session exited non-zero.
- Ctrl+C during waits didn't stop dock (INT trap without exit).
- `APP_PORT=8080 ./dock start` was overridden by `.env`; shell variables now win.
- Port checks warned about ports held by the project's own running containers.
- Queue workers that crashed while `vendor/` was missing stayed FATAL after `composer install`.
- `E_STRICT` (deprecated in PHP 8.4) removed from ini files.

### Security

- Auxiliary service ports and php-fpm's FastCGI port no longer published on all interfaces (Docker
  bypasses `ufw`; exposed FastCGI allows code execution).
- nginx/Caddy only mount `public/` and `storage/` instead of the whole project (`.env` included).
- Random `DB_PASSWORD` generated at install; `doctor`/`deploy` warn about defaults, `APP_DEBUG=true`
  outside local and readable `.env`.
- DB CLI/dump pass passwords via environment, not argv.
- `nginx`: `server_tokens off`, `Referrer-Policy`; Caddy: `Referrer-Policy`.
- Container log rotation (json-file, 3 × 10 MB).
- FrankenPHP 1.13.0 (fixes 5 upstream CVEs) downloaded from its current `php/frankenphp` repo; the PHP
  extension installer comes from its versioned image instead of an unpinned `releases/latest` download.

### Changed

- Dockerfile rewritten: shared `base` stage (extensions compiled once instead of twice), `local` target
  without app code (builds in seconds, no build context), `node_modules` and Node no longer shipped in
  production images, FrankenPHP only in octane images, BuildKit caches for composer/npm.
- Versions: PHP 8.5 (`PHP_VERSION`), Debian trixie, Node 24 LTS, FrankenPHP 1.13.0, Redis 8, pgvector
  0.8.7, Mailpit v1.31, Meilisearch v1.54, phpMyAdmin 5.2 (official image), nginx stable, Caddy 2.
  All image tags overridable from `.env`.
- Scheduler uses `schedule:work` (no drift); local queue uses `queue:listen` (picks up code changes).
- App healthcheck checks supervisor programs instead of `php -v`.
- MariaDB uses `MARIADB_*` variables and `MARIADB_AUTO_UPGRADE`; root password `DB_ROOT_PASSWORD`.
- Installer keeps an existing `.env` and merges the dock settings; `.dockerignore`/`.gitignore` are merged
  instead of replaced; new projects use `composer create-project` in the image.
- Scripts slimmed down: dead code (spinner, legacy compose paths, unused helpers) removed.

### Terminal UI

- `start`, `restart`, `stop`, `build` and `deploy` run as numbered steps (`✓ [3/9] Building image 33s`)
  with a spinner that shows the live last log line. Full output only with `-v` or on failure, where the
  relevant tail is printed (BuildKit stack traces stripped) plus the path of the full log.
- Notes under steps: migrations that ran, backup file, warnings raised inside a step.
- `status` and the end of `start`/`deploy` show one table (service, state, health, published ports)
  and a summary box with total time and the app/service URLs.
- One-line environment summary under the header; deploy preview shows paths relative to the project.
- Plain output (no colors, no spinner) without a TTY or with `NO_COLOR`; `-q` prints only errors;
  Ctrl+C stops cleanly and restores the cursor.

### Added

- Commands: `build`, `config`, `php`, `npx`, `node`, `test`, `pint`/`format`, `db`, `db:dump`,
  `db:restore`, `doctor`, `update`, `help <command>`; `deploy --backup`; `shell --root`; `exec --root`;
  global `-y`.
- `PHP_EXTENSIONS` for extra extensions, `NO_COLOR` support.
- `docker/AGENTS.md` agent guide, linked from the project's `AGENTS.md`/`CLAUDE.md`.
- `make lint` (bash -n, shellcheck, compose matrix), GitHub Actions CI, `.editorconfig`, `.shellcheckrc`.
