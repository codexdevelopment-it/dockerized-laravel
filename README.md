# 🐳 Dockerized Laravel

A powerful utility to easily dockerize Laravel applications for both local development and production environments. Features automatic Octane setup, environment-specific optimizations, and a beautiful CLI interface.

## Features

- **🚀 Multiple Server Modes**: artisan serve, Laravel Octane (FrankenPHP), PHP-FPM, Nginx, Caddy
- **🔧 Environment-Specific Configs**: Different PHP/OPcache settings for local vs production
- **📦 Modular Services**: Add Redis, Mailpit, Meilisearch, phpMyAdmin as needed
- **🔄 Hot Reload**: Automatic code reloading in local development
- **🎨 Beautiful CLI**: Color-coded output, progress indicators, helpful commands

## Quick Start

### Installation

```bash
# One-liner installation
bash <(curl -s https://raw.githubusercontent.com/Murkrow02/dockerized-laravel/main/configure-app.sh)

# Or with options
bash <(curl -s https://raw.githubusercontent.com/Murkrow02/dockerized-laravel/main/configure-app.sh) \
  -t existing -n "My App" -c myapp --non-interactive
```

### Starting Your Application

```bash
# Start with default settings (artisan serve)
./dock start

# Start with verbose output
./dock start --verbose

# Force rebuild containers
./dock start --build
```

## CLI Commands

```
./dock <command> [options]
```

### Container Management

| Command | Description |
|---------|-------------|
| `start` | Start all containers |
| `stop` | Stop all containers |
| `restart` | Restart all containers |
| `status` | Show container status |
| `logs [service]` | View logs (`-f` to follow) |
| `shell [container]` | Open shell in container |

### Laravel Shortcuts

| Command | Description |
|---------|-------------|
| `artisan <cmd>` | Run artisan command |
| `composer <cmd>` | Run composer command |
| `npm <cmd>` | Run npm command |
| `tinker` | Start Tinker REPL |
| `migrate` | Run migrations |
| `fresh` | Migrate fresh with seed |

### Options

| Option | Description |
|--------|-------------|
| `-v, --verbose` | Detailed output |
| `-q, --quiet` | Minimal output |
| `-e, --env <file>` | Use specific env file |
| `-h, --help` | Show help |

## Configuration

### Server Types

Configure via `SERVER=` in `.env`:

| Server | Description | Best For |
|--------|-------------|----------|
| `artisan` | `php artisan serve` | Quick development |
| `octane` | Laravel Octane + FrankenPHP | Performance |
| `fpm` | PHP-FPM (requires nginx/caddy) | Traditional setup |
| `nginx` | Nginx + PHP-FPM | Full control |
| `caddy` | Caddy + PHP-FPM + Auto HTTPS | Production |

### Additional Services

Configure via `SERVICES=` in `.env` (comma-separated):

```env
SERVICES=redis,mailpit,meilisearch
```

| Service | Ports | Description |
|---------|-------|-------------|
| `redis` | 6379 | Redis cache/queue |
| `mailpit` | 1025, 8025 | Mail testing |
| `meilisearch` | 7700 | Full-text search |
| `phpmyadmin` | 8080 | Database GUI |
| `soketi` | 6001 | WebSocket server |

### Environment Variables

```env
# Required
CONTAINER_NAME=myapp          # Base name for containers
APP_ENV=local                 # local, staging, production

# Server
SERVER=octane                 # Server type
APP_PORT=8000                 # Application port

# Database
DB_DATABASE=myapp
DB_USERNAME=app
DB_PASSWORD=password

# Deployment (production only)
REPO_URL=https://github.com/user/repo
BRANCH=main
DEPLOY_DIR=/var/www/myapp
```

## Architecture

```
project/
├── dock                      # CLI entrypoint
├── .env                      # Configuration
├── docker/
│   ├── Dockerfile            # Multi-environment build
│   ├── compose/
│   │   ├── base.yml          # Core services
│   │   ├── environments/     # Per-env overrides
│   │   │   ├── local.yml
│   │   │   ├── staging.yml
│   │   │   └── production.yml
│   │   ├── servers/          # Server configs
│   │   │   ├── artisan.yml
│   │   │   ├── octane.yml
│   │   │   └── ...
│   │   └── services/         # Optional services
│   │       ├── redis.yml
│   │       └── ...
│   └── config/
│       ├── php/              # Per-env PHP configs
│       │   ├── base.ini
│       │   ├── local.ini
│       │   └── production.ini
│       └── supervisor/       # Per-env supervisor
│           ├── base.conf
│           ├── local.conf
│           └── production.conf
└── scripts/
    └── lib/                  # Shell libraries
```

## Environment-Specific Optimizations

### Local Development

- OPcache validates file timestamps (instant code changes)
- JIT disabled (faster reload)
- Octane runs with `--watch` flag
- All ports exposed for tooling
- Dev dependencies included

### Production

- OPcache never validates timestamps (max performance)
- JIT enabled (tracing mode)
- Route, config, view caches baked in
- Only storage volumes mounted
- Scheduler daemon included

## Deployment

### Production Deploy

```bash
# Deploy using production env file
./dock deploy /path/to/production.env
```

The production `.env` should include:

```env
APP_ENV=production
REPO_URL=https://github.com/user/repo
BRANCH=main
DEPLOY_DIR=/var/www/myapp
STORAGE_MOUNT_PATH=/data/storage
DB_MOUNT_PATH=/data/mysql
```

## Requirements

- Docker & Docker Compose V2
- For deployment: `apt install rsync acl`

## Troubleshooting

### Ports Already In Use

```bash
# Check what's using a port
lsof -i :8000

# Use a different port
APP_PORT=8080 ./dock start
```

### Permission Issues

```bash
# Inside container
./dock shell
chmod -R 775 storage bootstrap/cache
```

### OPcache Changes Not Reflecting

In production, OPcache is permanent. To update code:

```bash
./dock restart
# Or inside container:
php artisan octane:reload
```

## Contributing

Contributions welcome! Please ensure your changes work across all environments (local, staging, production).

## License

MIT
