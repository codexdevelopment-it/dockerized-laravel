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

```bash
./dock deploy /path/to/production.env
```

Production `.env` requirements:
```env
APP_ENV=production
REPO_URL=https://github.com/user/repo
BRANCH=main
DEPLOY_DIR=/var/www/myapp
STORAGE_MOUNT_PATH=/data/storage
DB_MOUNT_PATH=/data/mysql
```

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
