# =============================================================================
# Dockerized Laravel - Multi-Environment Dockerfile
# Base: php:8.3-fpm (provides both php-fpm and php-cli SAPIs)
# Octane (FrankenPHP) is optional - the static binary is added for users who
# pick SERVER=octane. Users on SERVER=nginx/caddy/fpm don't need it.
# =============================================================================

ARG FRANKENPHP_VERSION=1.11.2

# -----------------------------------------------------------------------------
# Stage 1: Builder
# -----------------------------------------------------------------------------
FROM php:8.3-fpm-bookworm AS builder

ARG BUILD_ENV=local

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip curl ca-certificates gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN install-php-extensions zip intl bcmath exif calendar

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy dependency files AND auth.json (if it exists) BEFORE running composer.
# composer.json is the only required file: it anchors the COPY (a glob-only
# COPY with zero matches fails the build). composer.lock is optional so the
# installer's bootstrap stub and lock-less repos can still build — composer
# falls back to resolving from composer.json.
COPY composer.json composer.lock* package.json* package-lock.json* auth.json* ./

RUN if [ "$BUILD_ENV" = "production" ]; then \
        composer install --no-scripts --no-autoloader --prefer-dist --no-dev; \
    else \
        composer install --no-scripts --no-autoloader --prefer-dist; \
    fi

# Pre-install npm deps before copying source for better layer caching.
# Skipped for local: the volume mount overlays public/build anyway.
RUN if [ "$BUILD_ENV" != "local" ] && [ -f "package.json" ] && [ -f "package-lock.json" ]; then \
        npm ci --no-audit --no-fund; \
    fi

COPY . .

# Build frontend assets (production/staging only).
# --if-present skips gracefully when no "build" script is defined in package.json.
RUN if [ "$BUILD_ENV" != "local" ] && [ -f "package.json" ]; then \
        npm run --if-present build; \
    fi

# Defensive heal: if .dockerignore is missing on the host, `COPY . .` will
# overlay the host's vendor/ on top of the freshly-installed one above and
# ship whatever stale package versions happen to be on the developer's laptop.
# Re-running composer install is idempotent when vendor matches composer.lock
# (fast lockfile validate + autoload dump) and self-heals when vendor was
# clobbered. --optimize-autoloader subsumes the previous dump-autoload step.
RUN if [ "$BUILD_ENV" = "production" ]; then \
        composer install --no-scripts --prefer-dist --no-dev --optimize-autoloader; \
    else \
        composer install --no-scripts --prefer-dist --optimize-autoloader; \
    fi

RUN rm -f auth.json

# -----------------------------------------------------------------------------
# Stage 2: Runtime
# -----------------------------------------------------------------------------
FROM php:8.3-fpm-bookworm AS runtime

ARG BUILD_ENV=local
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG FRANKENPHP_VERSION=1.11.2
ARG TARGETARCH

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

ENV SERVER_NAME=":8000"

RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor curl acl nano procps git unzip ca-certificates netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN install-php-extensions \
    pdo_pgsql pdo_mysql gd intl zip opcache redis pcntl bcmath exif calendar mbstring

# Install FrankenPHP static binary - only needed when SERVER=octane.
# Harmless dead weight (~30MB) otherwise. Detected arch fallback to amd64.
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
        amd64) FP_ARCH=x86_64 ;; \
        arm64) FP_ARCH=aarch64 ;; \
        *)     FP_ARCH=x86_64 ;; \
    esac && \
    curl -fsSL -o /usr/local/bin/frankenphp \
        "https://github.com/dunglas/frankenphp/releases/download/v${FRANKENPHP_VERSION}/frankenphp-linux-${FP_ARCH}" && \
    chmod +x /usr/local/bin/frankenphp

# Create laravel user matching host UID/GID. UID 0 forbidden (no app-as-root).
RUN if [ "${USER_ID}" = "0" ] || [ "${GROUP_ID}" = "0" ]; then \
        echo "ERROR: USER_ID/GROUP_ID must not be 0 (refusing to run as root)" >&2; \
        exit 1; \
    fi && \
    if getent group ${GROUP_ID} >/dev/null; then \
        EXISTING_GROUP=$(getent group ${GROUP_ID} | cut -d: -f1); \
    else \
        groupadd -g ${GROUP_ID} laravel; \
        EXISTING_GROUP=laravel; \
    fi && \
    if getent passwd ${USER_ID} >/dev/null; then \
        EXISTING_USER=$(getent passwd ${USER_ID} | cut -d: -f1); \
        if [ "$EXISTING_USER" != "laravel" ]; then \
            usermod -l laravel -d /home/laravel -m "$EXISTING_USER" 2>/dev/null || true; \
            groupmod -n laravel "$EXISTING_USER" 2>/dev/null || true; \
        fi; \
    else \
        useradd -u ${USER_ID} -g ${EXISTING_GROUP} -m laravel; \
    fi && \
    usermod -aG www-data laravel

WORKDIR /var/www/html

# Supervisor program drop-in dir (env compose + server compose mount here)
RUN mkdir -p /etc/supervisor/programs

# Copy application from builder stage
COPY --from=builder --chown=laravel:www-data /var/www/html /var/www/html

# Create runtime dirs (storage/bootstrap may not exist in slim apps or be
# .dockerignored) and prelink frankenphp binary for octane:frankenphp.
RUN mkdir -p /var/www/html/vendor/laravel/octane/bin \
             /var/www/html/storage/framework/cache \
             /var/www/html/storage/framework/sessions \
             /var/www/html/storage/framework/views \
             /var/www/html/storage/logs \
             /var/www/html/bootstrap/cache \
    && ln -sf /usr/local/bin/frankenphp /var/www/html/vendor/laravel/octane/bin/frankenphp-linux-x86_64 \
    && ln -sf /usr/local/bin/frankenphp /var/www/html/vendor/laravel/octane/bin/frankenphp-linux-aarch64 \
    && chown -R laravel:www-data /var/www/html/storage /var/www/html/bootstrap/cache /var/www/html/vendor/laravel/octane/bin \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

USER laravel

RUN if [ "$BUILD_ENV" = "production" ] || [ "$BUILD_ENV" = "staging" ]; then \
        php artisan config:cache && \
        php artisan route:cache && \
        php artisan view:cache && \
        if php artisan list | grep -q "filament:optimize"; then \
            echo "Filament detected, optimizing..." && \
            php artisan filament:optimize; \
        fi; \
    else \
        echo "Skipping optimizations for ${BUILD_ENV} environment"; \
    fi

# php-fpm pool default port (overridden by mounted pool.conf)
EXPOSE 8000 9000

USER root

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/00-base.conf"]
