# 🐳 Dockerized Laravel

Dockerize any Laravel application in seconds. One command to set up a complete development environment with production-ready optimizations.

## Quick Start

```bash
# Install in your Laravel project
bash <(curl -s https://raw.githubusercontent.com/codexdevelopment-it/dockerized-laravel/main/configure-app.sh)

# Start the application
./dock start
```

Your app is now running at `http://localhost:8000`

## Commands

```bash
./dock start              # Start containers
./dock stop               # Stop containers
./dock restart            # Restart containers
./dock status             # Show status
./dock logs [-f]          # View logs
./dock shell              # Shell into app container
./dock shell mariadb      # Shell into database

./dock artisan <cmd>      # Run artisan commands
./dock composer <cmd>     # Run composer
./dock npm <cmd>          # Run npm
./dock tinker             # Laravel Tinker
./dock migrate            # Run migrations
./dock fresh              # Fresh migrate + seed
./dock seed               # Run seeders
```

Add `-v` or `--verbose` for detailed output.

## Configuration

Edit `.env` to configure:

```env
CONTAINER_NAME=myapp      # Container prefix
APP_ENV=local             # local | staging | production
SERVER=octane             # artisan | octane | fpm | nginx | caddy
SERVICES=redis,mailpit    # Additional services (comma-separated)
APP_PORT=8000             # Application port
```

### Server Types

| Server | Use Case |
|--------|----------|
| `artisan` | Quick development with `php artisan serve` |
| `octane` | High performance with FrankenPHP (recommended) |
| `fpm` | Traditional PHP-FPM |
| `nginx` | Nginx + PHP-FPM |
| `caddy` | Caddy + PHP-FPM with automatic HTTPS |

### Available Services

| Service | Ports | Description |
|---------|-------|-------------|
| `redis` | 6379 | Cache and queues |
| `mailpit` | 1025, 8025 | Email testing (UI at :8025) |
| `meilisearch` | 7700 | Full-text search |
| `phpmyadmin` | 8080 | Database management |
| `soketi` | 6001 | WebSocket server |

## Installation Options

```bash
# Interactive (asks questions)
bash <(curl -s .../configure-app.sh)

# Non-interactive for new project
bash <(curl -s .../configure-app.sh) -t new -n "My App" -c myapp --non-interactive

# Non-interactive for existing project
bash <(curl -s .../configure-app.sh) -t existing -n "My App" --non-interactive
```

| Flag | Description |
|------|-------------|
| `-t, --type` | `new` or `existing` |
| `-n, --name` | Application name |
| `-c, --container` | Container base name |
| `-d, --database` | Database name |
| `-r, --repo` | Repository URL (for deployment) |
| `--non-interactive` | Skip all prompts |

## Production Deployment

End-to-end guide for a fresh Linux server (Ubuntu/Debian assumed; Fedora/Arch similar).

### 1. Server prerequisites (one-time)

```bash
# Docker + Compose V2
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker            # or log out/in

# Git (for the deploy clone)
sudo apt-get install -y git rsync openssl

# Verify
docker compose version
```

If you use a **private repo**, set up SSH access on the server:

```bash
ssh-keygen -t ed25519 -C "deploy@$(hostname)"
cat ~/.ssh/id_ed25519.pub        # add as a deploy key in GitHub/GitLab
ssh -T git@github.com            # accept fingerprint
```

### 2. Pick paths

| Variable | Purpose | Example |
|---|---|---|
| `DEPLOY_DIR` | Where the app lives | `/var/www/myapp` |
| `STORAGE_MOUNT_PATH` | Persistent `storage/` (uploads, logs) | `/var/data/myapp/storage` |
| `DB_MOUNT_PATH` | MariaDB data dir | `/var/data/myapp/db` |

The deploy script will create them if missing and `chown` them to the container user. **Avoid putting them inside `DEPLOY_DIR`** if you want rsync to be safe — keep data in `/var/data/...`.

### 3. Bootstrap a `production.env`

On your **local machine** (or anywhere with this repo), copy `.env` to e.g. `~/myapp.prod.env` and edit:

```env
APP_NAME="My App"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
APP_KEY=                                # leave empty — deploy generates one

CONTAINER_NAME=myapp
SERVER=octane                           # recommended: octane (FrankenPHP)
SERVICES=redis

# Deploy
REPO_URL=git@github.com:you/myapp.git
BRANCH=main
DEPLOY_DIR=/var/www/myapp
DOMAIN=app.example.com                  # used by Caddy for auto-HTTPS

STORAGE_MOUNT_PATH=/var/data/myapp/storage
DB_MOUNT_PATH=/var/data/myapp/db

# DB
DB_DATABASE=myapp
DB_USERNAME=app
DB_PASSWORD=<strong-password>           # change this!

# Optional: pin to host UID/GID (auto-detected if omitted)
# USER_ID=1000
# GROUP_ID=1000
```

Copy it to the server:

```bash
scp ~/myapp.prod.env user@server:~/myapp.prod.env
chmod 600 ~/myapp.prod.env              # on the server
```

### 4. Get the dock CLI on the server

You only need the `dock` script + `scripts/` dir + `docker/` dir for the **first** deploy (subsequent deploys overwrite them from your app repo):

```bash
ssh user@server
bash <(curl -s https://raw.githubusercontent.com/codexdevelopment-it/dockerized-laravel/main/configure-app.sh) \
    -t existing -n "My App" -c myapp --non-interactive
cd myapp
```

Or just `git clone` your app repo (which already has `dock` baked in after the install step) to a scratch dir.

### 5. Deploy

```bash
./dock deploy ~/myapp.prod.env
```

What it does, in order:

1. Validates the env file (refuses unsafe `DEPLOY_DIR` like `/`, `/root`, `/etc`).
2. Creates `DEPLOY_DIR`, `STORAGE_MOUNT_PATH`, `DB_MOUNT_PATH` if missing.
3. `git clone` the repo to a temp dir.
4. `rsync` into `DEPLOY_DIR`, **excluding** `.env`, `storage/`, `db-data/`.
5. Copies your `production.env` to `${DEPLOY_DIR}/.env` (mode `600`).
6. Generates `APP_KEY` if empty (preserves existing key across re-deploys).
7. Auto-detects host `USER_ID`/`GROUP_ID` and persists them in `.env`.
8. Sets exec bits on `dock` + `scripts/*.sh`.
9. `chown` storage + db dirs to the container user.
10. `docker compose build --build` and `up -d`.
11. Waits for MariaDB healthcheck.
12. Runs `php artisan migrate --force`, `storage:link`, `config/route/view:cache`.
13. `octane:reload` if `SERVER=octane`.

### 6. Re-deploy (after a code push)

Same command — it's idempotent:

```bash
./dock deploy ~/myapp.prod.env
```

A backup of the previous `.env` is saved as `.env.bak.<timestamp>` automatically.

### 7. HTTPS (recommended)

Use `SERVER=caddy` + `DOMAIN=app.example.com`. Caddy will request a Let's Encrypt cert automatically on first request to that domain. Make sure port 80 and 443 are open on the server firewall and DNS for `DOMAIN` points to the server's IP.

### Troubleshooting deploy

| Symptom | Fix |
|---|---|
| `Cannot connect to the Docker daemon` | `sudo usermod -aG docker $USER && newgrp docker` |
| `Permission denied` on `storage/` | Re-run deploy as a user that can `chown`, or `sudo` it |
| `git clone` fails on private repo | Add server's SSH key as deploy key (step 1) |
| Port 80/443 in use | Stop host webserver (`sudo systemctl stop nginx`) or set `HTTP_PORT`/`HTTPS_PORT` in env |
| App reachable but DB connection refused | Wait — first start migrates DB; check `./dock logs mariadb` |
| Changed `.env` not taking effect | `.env` is mounted read-only into the container. Run `./dock restart` (no rebuild needed for env-only changes) |

---

## Future improvements

These are known gaps tracked for future work (not blocking the current deploy):

### Reliability / safety
- **Release-based deploy layout** (`releases/`, `shared/`, `current` symlink) for instant rollback.
- **DB backup before each re-deploy** (`mysqldump` → `${DB_MOUNT_PATH}/../backups/`).
- **Real healthcheck**: replace `php -v` with `curl -f http://localhost:8000/up`.
- **`./dock doctor`** subcommand: scan for common misconfig (missing extensions, perms, port conflicts, stale containers).

### Operational
- **`./dock bootstrap`** subcommand: install Docker + create system user + open firewall ports + systemd unit so the app survives reboots.
- **`./dock backup` / `./dock restore`**: one-shot DB + storage tarball.
- **systemd integration**: auto-start on boot via a generated `dock-${CONTAINER_NAME}.service`.
- **Webhook notifications** on deploy success/failure (Slack/Telegram/Discord).
- **`--dry-run`** flag for `deploy`.

### Build / runtime
- **Pin `mariadb:latest`** to a major version (e.g. `mariadb:11.4`).
- **Xdebug** install gated by `XDEBUG_MODE` (currently env var is wired but extension not installed).
- **Multi-arch image builds** (amd64 + arm64) via buildx, with arch-detected octane symlinks (currently both are linked unconditionally).
- **Scheduler via cron** container instead of `while sleep 60` (drift-free).
- **Octane installation moved to Dockerfile** so prod doesn't `composer require` at runtime.

### Server compose hygiene
- **Port-conflict awareness**: extend `check_required_ports` to cover soketi (6001), gotenberg, mailpit SMTP (1025), and 80/443 for caddy.
- **`docker_exec` argument quoting**: current `$cmd` unquoted, breaks on args with spaces.
- **phpMyAdmin behind auth** or bind to `127.0.0.1` only when used in non-local environments.

### Developer experience
- **`./dock update`** to pull + redeploy in one shot with minimal downtime.
- **`./dock ssl <domain>`** to generate a Caddyfile snippet for a new domain.
- **VS Code devcontainer config** generated by the installer for one-click attach.

---

## How It Works

The CLI dynamically assembles Docker Compose configurations:

```
base.yml + environment/{local,staging,production}.yml + server/{artisan,octane,...}.yml + services/{redis,mailpit,...}.yml
```

### Project Structure

```
├── dock                    # CLI entrypoint
├── .env                    # Configuration
├── docker/
│   ├── Dockerfile          # Multi-stage build
│   ├── compose/
│   │   ├── base.yml        # Core services (app + mariadb)
│   │   ├── environments/   # Environment overrides
│   │   ├── servers/        # Server-specific configs
│   │   └── services/       # Optional services
│   └── config/
│       ├── php/            # PHP configs per environment
│       └── supervisor/     # Supervisor configs per environment
└── scripts/lib/            # Shell libraries
```

### Environment Optimizations

| Setting | Local | Production |
|---------|-------|------------|
| OPcache timestamps | Validated (instant reload) | Disabled (max speed) |
| JIT | Off | Tracing mode |
| Octane | `--watch` flag | Persistent workers |
| Caches | Cleared on start | Baked into image |
| Code mount | Full project | Storage only |

## Requirements

- Docker with Compose V2
- Bash 3.2+ (macOS default works)

## Troubleshooting

**Port in use:**
```bash
lsof -i :8000              # Find what's using it
APP_PORT=8080 ./dock start # Use different port
```

**Permission issues:**
```bash
./dock shell
chmod -R 775 storage bootstrap/cache
```

**Code changes not reflecting (production):**
```bash
./dock restart
# Or: ./dock artisan octane:reload
```

## License

MIT
