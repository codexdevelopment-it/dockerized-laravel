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

The deploy is dead simple: **clone the repo to the server once, edit `.env`, then `./dock deploy` forever after.** Every subsequent deploy is the same single command.

### 1. Prepare the server (one-time)

```bash
# Docker + Compose V2
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker                   # or log out / back in

sudo apt-get install -y git openssl
docker compose version          # verify
```

If your app repo is **private**, give the server an SSH key:

```bash
ssh-keygen -t ed25519 -C "deploy@$(hostname)"
cat ~/.ssh/id_ed25519.pub       # add this as a deploy key in GitHub/GitLab
ssh -T git@github.com           # accept fingerprint
```

### 2. Clone your app once

```bash
sudo mkdir -p /var/www && sudo chown $USER /var/www
cd /var/www
git clone git@github.com:you/myapp.git
cd myapp
```

(Your app repo should already have `dock` + `scripts/` + `docker/` committed — those are produced by the installer when the project was first set up.)

### 3. Create the production `.env`

In the same dir:

```bash
cp .env.example .env            # or scp it up from your laptop
nano .env
```

Minimum required values:

```env
APP_NAME="My App"
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
APP_KEY=                        # leave blank, deploy will generate one

CONTAINER_NAME=myapp            # used as container prefix
SERVER=octane                   # octane | caddy | nginx | fpm | artisan
SERVICES=redis                  # comma-separated optional services

DOMAIN=app.example.com          # used by Caddy for auto-HTTPS
BRANCH=main                     # branch to pull on each deploy

DB_DATABASE=myapp
DB_USERNAME=app
DB_PASSWORD=<strong-password>

# Optional - absolute paths recommended on a real server.
# Defaults to ./storage and ./db-data inside this directory.
# STORAGE_MOUNT_PATH=/var/data/myapp/storage
# DB_MOUNT_PATH=/var/data/myapp/db
```

```bash
chmod 600 .env
```

### 4. Deploy

```bash
./dock deploy
```

That's it. The command will:

1. `git fetch origin <BRANCH>` and show you a **summary** of the new commits, files changed, and config to deploy.
2. Ask for confirmation.
3. `git pull --rebase --autostash`.
4. Generate `APP_KEY` if missing, persist host `USER_ID`/`GROUP_ID` into `.env`.
5. `chmod`/`chown` storage + db data dirs.
6. `docker compose build && up -d` the containers.
7. Wait for MariaDB to be healthy.
8. Run `artisan migrate --force`, `storage:link`, `config/route/view/event:cache`.
9. `octane:reload` if `SERVER=octane`.

Output preview:

```
🐳 Deployment
⚙️ Configuration
  App           My App
  Environment   production
  Server        octane
  Branch        main
  Domain        app.example.com
  ...

📦 Changes
  From    a1b2c3d
  To      e4f5g6h
  Commits 4

  e4f5g6h  Fix billing edge case (Alice)
  9876543  Add admin dashboard (Bob)
  ...

Proceed with deployment? [y/N]
```

### 5. Re-deploy (after every code push)

Identical command:

```bash
./dock deploy
```

It's fully idempotent. If there are no new commits, it'll tell you and you can choose to abort or continue (useful to force a rebuild + re-migrate without a code change).

### Flags

| Flag | Effect |
|---|---|
| `-y`, `--yes` | Skip the confirmation prompt (for CI/cron) |
| `--skip-pull` | Don't run `git fetch`/`pull` — deploy whatever is in the working tree |
| `-v`, `--verbose` | Stream `docker compose` output instead of hiding it |

### HTTPS

Use `SERVER=caddy` + `DOMAIN=app.example.com`. Caddy fetches a Let's Encrypt cert automatically on first request. Make sure:
- DNS for `DOMAIN` resolves to the server's IP.
- Ports 80 + 443 are open on the firewall.
- No other webserver is bound to those ports.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `Cannot connect to the Docker daemon` | `sudo usermod -aG docker $USER && newgrp docker` |
| `Permission denied` on `storage/` | Re-run with `sudo` or set storage dir owner to your UID |
| `git fetch` fails on private repo | Add the server's SSH key as a deploy key (step 1) |
| Port 80/443 already in use | Stop host webserver (`sudo systemctl stop nginx`) or set `HTTP_PORT`/`HTTPS_PORT` in `.env` |
| `.env` change not taking effect | `.env` is mounted read-only into the container. Run `./dock restart` (no rebuild needed for env-only changes) |
| Want to abort after seeing the diff | Just answer `N` to the prompt — nothing has been pulled yet |

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
- **`./dock backup` / `./dock restore`**: one-shot DB + storage tarball. Should ideally be runnable as a `--backup` flag of `deploy` to auto-snapshot before each deploy.
- **`./dock deploy --tag <tag>`**: deploy a specific git tag/sha (currently always pulls the configured `BRANCH`).
- **systemd integration**: auto-start on boot via a generated `dock-${CONTAINER_NAME}.service`.
- **Webhook notifications** on deploy success/failure (Slack/Telegram/Discord).
- **`--dry-run`** flag for `deploy` (show the plan without pulling/building).
- **Optional pre/post hooks**: `scripts/deploy/before.sh`, `scripts/deploy/after.sh` so apps can plug in extra steps (e.g. flush CDN, warm cache).

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
