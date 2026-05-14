# =============================================================================
# Dockerized Laravel - Multi-Environment Dockerfile
# Supports: local, staging, production
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder
# -----------------------------------------------------------------------------
FROM dunglas/frankenphp:1.11.2-php8.3 AS builder

ARG BUILD_ENV=local

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip curl nodejs npm \
    && rm -rf /var/lib/apt/lists/*

RUN install-php-extensions zip intl bcmath exif calendar

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy dependency files AND auth.json (if it exists) BEFORE running composer
COPY composer.json composer.lock package.json* package-lock.json* auth.json* ./

# Install PHP dependencies (Now has access to Nova credentials)
RUN if [ "$BUILD_ENV" = "production" ]; then \
        composer install --no-scripts --no-autoloader --prefer-dist --no-dev; \
    else \
        composer install --no-scripts --no-autoloader --prefer-dist; \
    fi

# Copy remaining application files
COPY . .

# Dump autoloader
RUN composer dump-autoload --optimize --no-scripts

# Remove auth.json so it doesn't get copied to the runtime stage
RUN rm -f auth.json

# -----------------------------------------------------------------------------
# Stage 2: Runtime
# -----------------------------------------------------------------------------
FROM dunglas/frankenphp:1.11.2-php8.3 AS runtime

ARG BUILD_ENV=local
ARG USER_ID=1000
ARG GROUP_ID=1000

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

ENV SERVER_NAME=":8000"

RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor curl acl nano procps git unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN install-php-extensions \
    pdo_pgsql pdo_mysql gd intl zip opcache redis pcntl bcmath exif calendar mbstring

# Create laravel user matching host UID/GID to avoid storage permission issues.
# UID 0 is rejected on purpose - we never run app as root inside the container.
RUN if [ "${USER_ID}" = "0" ] || [ "${GROUP_ID}" = "0" ]; then \
        echo "ERROR: USER_ID/GROUP_ID must not be 0 (refusing to run as root)" >&2; \
        exit 1; \
    fi && \
    # If GID already exists, reuse its group name; otherwise create one.
    if getent group ${GROUP_ID} >/dev/null; then \
        EXISTING_GROUP=$(getent group ${GROUP_ID} | cut -d: -f1); \
    else \
        groupadd -g ${GROUP_ID} laravel; \
        EXISTING_GROUP=laravel; \
    fi && \
    # If UID already exists, rename that user to laravel; otherwise create one.
    if getent passwd ${USER_ID} >/dev/null; then \
        EXISTING_USER=$(getent passwd ${USER_ID} | cut -d: -f1); \
        if [ "$EXISTING_USER" != "laravel" ]; then \
            usermod -l laravel -d /home/laravel -m "$EXISTING_USER" || true; \
            groupmod -n laravel "$EXISTING_USER" 2>/dev/null || true; \
        fi; \
    else \
        useradd -u ${USER_ID} -g ${EXISTING_GROUP} -m laravel; \
    fi && \
    usermod -aG www-data laravel

WORKDIR /var/www/html

# Copy application from builder stage
COPY --from=builder --chown=laravel:www-data /var/www/html /var/www/html

RUN mkdir -p /var/www/html/vendor/laravel/octane/bin \
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

EXPOSE 8000

USER root

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/00-base.conf"]