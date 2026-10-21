# Changelog

## Unreleased

### Added

- `./dock autodeploy`: continuous deployment from the host's cron. Every `AUTODEPLOY_INTERVAL` minutes
  (default 2) it fetches `origin/BRANCH` and runs `./dock deploy -y` when there are new commits.
  `enable [--every N]` checks that git can fetch without a terminal (no ssh-agent, as under cron) and
  installs the cron job; `disable`, `status`, `logs`, `run`. Failed deploys are not retried for the same
  commit; repeated problems are logged once. State and log live in `.git/dock/`. `./dock deploy` shows
  the command to enable it while it is off (`AUTODEPLOY=false` hides the hint); `doctor` reports it.
- `APT_PACKAGES` (extra Debian packages) and build hooks in `docker/config/build/`: `runtime.sh` runs as
  root in every app image (Python venvs, downloads, ...), `release.sh` in staging/production images with
  the code in place. They reach the build as the named context `dock-build` (compose
  `additional_contexts`, Compose ≥ 2.17), so `.dockerignore` can't hide them. `dock update` adds the
  default no-op scripts.
- `docker/compose/project.yml`: optional project-owned overrides, always merged last (a custom DB image,
  Redis persistence, extra volumes). The toolkit never ships it, so `dock update` keeps it.
- `docker/config/deploy-artisan.txt`: artisan commands `./dock deploy` runs after migrations and caches
  (e.g. `scout:sync-index-settings`), one per line; failures are warnings.
- `APP_BIND` (e.g. `127.0.0.1`): publish the app port of `artisan`/`octane`/`nginx` on one interface
  only, for servers with a reverse proxy on the host. Unset keeps publishing on every interface.
- Deploys take a lock (`.git/dock/deploy.lock`): a manual deploy and an auto-deploy never overlap.
- Risky-setting warnings on `start`/`deploy`/`config` and in `doctor` (failures for the insecure
  ones): FastCGI, DB, Redis or phpMyAdmin published on a non-loopback `SERVICES_BIND`, `APP_DEBUG`,
  default/short `DB_PASSWORD`, `DB_USERNAME=root`, default `MEILISEARCH_KEY`, `MEILI_ENV`, default
  Soketi secret, Caddy without `DOMAIN`, localhost `APP_URL`, `MAIL_HOST=mailpit`, `LOG_LEVEL=debug`,
  `DB_PASSWORD` containing `${`. Printed once per deploy (not again after the re-exec).
- `STORAGE_MOUNT_PATH` / `DB_MOUNT_PATH` pointing at `/`, a system directory, `$HOME`, the project root
  or at each other are refused (deploy runs `chown -R` on the storage path).

- `./dock backups`: encrypted off-site DB backups on S3-compatible storage (AWS, DigitalOcean Spaces, R2,
  MinIO). `enable` asks for the missing `BACKUP_*` settings, saves them to `.env`, checks bucket access and
  installs a host cron job (`BACKUP_SCHEDULE`, default `0 3 * * *`); `disable`, `status`, `run`, `list`,
  `download`, `restore`, `prune` (`BACKUP_KEEP_DAYS`, default 30) and `logs`. Dumps are gzipped and
  encrypted with openssl (AES-256-CBC, PBKDF2-SHA256, 200k iterations); failed uploads wait in
  `backups/pending/` and are retried; runs are locked against overlap. The AWS CLI runs from
  `amazon/aws-cli` (no host install). `doctor` checks settings, the cron job and the last run.

- `PUBLISH_DB_PORT` / `PUBLISH_REDIS_PORT` (`true`/`false`). Default: published in local, **not** in
  staging/production (docker network only). Staging used to publish the DB and Redis was published
  everywhere; set `true` to keep that. Host ports now live in `docker/compose/ports/*.yml`, added by `build_compose_args` when enabled;
  `databases/*-local.yml` and `*-staging.yml` are gone (`dock update` removes them).

### Fixed

- `SERVER=octane` ignored `PHP_VERSION` for web requests: FrankenPHP's static binary embeds its own PHP
  (8.5 in 1.13.0) and extension set, while artisan, queues and the scheduler used `PHP_VERSION`. Octane
  images are now built on `dunglas/frankenphp:<FRANKENPHP_VERSION>-php<PHP_VERSION>-trixie`, so server
  and CLI share one PHP and the toolkit's extensions; the `/etc/frankenphp/php.d` ini mounts are gone.
- Staging/production builds failed with "Please provide a valid cache path" when a project's
  `.dockerignore` excluded `storage/framework/views` itself: the builder creates the framework dirs.
- Staging/production builds failed for apps with composer `path` repositories (e.g. Nova's
  `./nova-components/*`): the dependency layer ran before the code was copied. That layer is now best
  effort; the install after `COPY . .` completes it.
- The terminal cursor stayed hidden when a step of `start`, `restart` or `deploy` failed.
- `db:dump` printed its result twice; the migration count of `deploy` included "Creating migration table".
- `./dock db`, `db:dump`, `db:restore`: the DB password was passed as `docker exec -e VAR=value`, visible
  in the host's process list. It now reaches docker through the environment.
- nginx passed every `*.php` under `public/` to php-fpm, so an uploaded `.php` reachable through
  `public/storage` could be executed. Only `/index.php` runs now (like the Caddyfile). `docker/config`
  is yours: existing projects should copy the change from `docker/config/nginx/default.conf`.
- nginx static asset responses lost the security headers (`add_header` in a location drops the
  server-level ones).
- The installer's `.env.backup-*` (secrets) was world-readable when `.env` was and not git-ignored: now
  `chmod 600` and added to `.gitignore`.
- `.dockerignore` excludes all of `storage/app/*` (it only excluded `storage/app/public`), so private
  uploads on the host are no longer copied into staging/production images. Existing projects: replace
  `storage/app/public/*` with `storage/app/*` in `.dockerignore`.
- `BACKUP_SCHEDULE` fields are restricted to cron characters, and paths written into crontab lines
  (project root, `-e` env file) are checked for `'` and `%`.

- **Staging builds failed** at `composer install` with exit code 1 and no output:
  `NO_DEV=$([ "$BUILD_ENV" = "production" ] && echo --no-dev)` takes the exit status of the failed test
  when `BUILD_ENV` is not `production`, so `&&` skipped composer. Now `|| true`. CI builds the `staging`
  target too.

### Changed

- The app image ships the `pgsql` extension next to `pdo_pgsql` (ext-pgsql, `pg_*` functions).
- `deploy` preview: risky settings are listed in a "Warnings" section next to the confirmation (not above
  the header); the URL is `APP_URL` in staging/production; `--skip-pull` shows the deployed commit and
  says the working tree is deployed as-is (uncommitted tracked changes included) instead of "no new
  commits"; the new-migrations hint doesn't suggest `--backup` when it was passed.
- `deploy` final box shows the release (`abc1234 → def5678 (3 commits)`) and turns yellow ("Deployed
  with warnings") when a cache step failed.
- `restart` runs the pre-flight checks and rejects unknown options.

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
