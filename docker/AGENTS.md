# Docker setup (dockerized-laravel) — guide for AI agents

This project runs entirely in Docker through the `./dock` CLI in the project root.
PHP, Composer, Node and the database live in containers, **not on the host**.

## Rules

- Never run `php`, `composer`, `npm`, `npx` or `artisan` directly on the host. Prefix them:
  `./dock artisan …`, `./dock composer …`, `./dock npm …`, `./dock php …`.
- Commands run as the container user `laravel` (UID = host user), so files they create keep the right owner.
  Use `./dock exec --root …` only for system-level tasks.
- Configuration lives in `.env` (dock reads it; there is no `docker-compose.yml` in the root).
  After changing `.env` docker settings run `./dock restart`; after changing PHP version/extensions or the
  Dockerfile run `./dock start --build`.
- Don't edit `docker/compose/*` for app-specific tweaks unless asked: prefer `.env` variables.
  `docker/config/*` (php.ini, nginx, Caddy, supervisor, fpm) is meant to be customised.
- Destructive commands need explicit user approval: `./dock fresh`, `./dock db:restore`, `./dock deploy`,
  deleting `db-data/`.

## Everyday commands

| Task | Command |
|---|---|
| Start / stop / recreate | `./dock start` · `./dock stop` · `./dock restart` |
| Rebuild image | `./dock start --build` (`--no-cache` for a clean build) |
| Status, logs | `./dock status` · `./dock logs app -f` · `./dock logs db` |
| Artisan | `./dock artisan migrate` · `./dock artisan make:model Post -m` |
| Tests | `./dock test` (`php artisan test`, args pass through, e.g. `--filter=UserTest`) |
| Code style | `./dock pint` (`--test` to only check) |
| Composer / Node | `./dock composer require vendor/pkg` · `./dock npm install` · `./dock npm run build` |
| Tinker | `./dock tinker` |
| Shell | `./dock shell` (app) · `./dock shell db` · `./dock shell --root` |
| Database CLI | `./dock db` (mariadb or psql, already authenticated) |
| Backup / restore | `./dock db:dump [file]` · `./dock db:restore <file.sql.gz>` |
| Diagnose problems | `./dock doctor` |
| Resolved compose config | `./dock config` |

`./dock help` lists everything; `./dock help <command>` shows details.

## How it is wired

- `.env` keys used by dock: `CONTAINER_NAME`, `APP_ENV` (local|staging|production), `SERVER`
  (artisan|octane|nginx|caddy|fpm), `DB_DRIVER` (mariadb|postgres|pgvector), `SERVICES`
  (redis,mailpit,meilisearch,phpmyadmin,soketi,gotenberg), `APP_PORT`, `DOMAIN`, `PHP_VERSION`, `PHP_EXTENSIONS`.
- Containers: `<CONTAINER_NAME>` (app), `<CONTAINER_NAME>-db`, `<CONTAINER_NAME>-redis`, … on one Docker network.
  From the app, services are reached by service name: DB host `mariadb` or `postgres`, `redis`, `mailpit:1025`,
  `meilisearch:7700`, `gotenberg:3000`, `soketi:6001`.
- Host ports: app on `APP_PORT` (default 8000); DB/Redis/Mailpit/… bound to `127.0.0.1` only.
- Local: the whole project is bind-mounted, code changes are live; queue worker uses `queue:listen`.
  Staging/production: code is baked into the image, only `storage/` and `.env` are mounted.
- Background processes (server, queue workers, scheduler) run under supervisor in the app container:
  `./dock exec --root supervisorctl -c /etc/supervisor/conf.d/00-base.conf status`.

## Troubleshooting

1. `./dock doctor` first.
2. `./dock logs app` for PHP/server/worker output; `./dock artisan about` for app config.
3. Permission errors on `storage/`: `./dock restart` (provisioning fixes ownership); if the container UID
   differs from yours, `./dock start --build`.
4. Port already in use: change `APP_PORT` (or `FORWARD_DB_PORT`, `FORWARD_REDIS_PORT`, …) in `.env`.
