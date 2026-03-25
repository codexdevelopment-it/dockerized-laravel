# =============================================================================
# Dockerized Laravel - Multi-Environment Dockerfile
# Supports: local, staging, production
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder
# Installs dependencies and prepares the application
# -----------------------------------------------------------------------------
FROM dunglas/frankenphp:1.11.2-php8.3 AS builder

# Build argument for environment
ARG BUILD_ENV=local

# Install the PHP extension installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# Install build-time tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip curl nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN install-php-extensions zip intl bcmath exif calendar

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Copy dependency files first (for better caching)
COPY composer.json composer.lock package.json* package-lock.json* ./

# Install PHP dependencies
# In local, we include dev dependencies for tools like Pail, Pint, etc.
RUN if [ "$BUILD_ENV" = "production" ]; then \
        composer install --no-scripts --no-autoloader --prefer-dist --no-dev; \
    else \
        composer install --no-scripts --no-autoloader --prefer-dist; \
    fi

# Copy application files
COPY . .

# Dump autoloader
RUN composer dump-autoload --optimize --no-scripts

# -----------------------------------------------------------------------------
# Stage 2: Runtime
# Final production-ready image
# -----------------------------------------------------------------------------
FROM dunglas/frankenphp:1.11.2-php8.3 AS runtime

# Build argument for environment
ARG BUILD_ENV=local

# Install the PHP extension installer
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# FrankenPHP server configuration
ENV SERVER_NAME=":8000"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor curl acl nano procps git unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Composer (needed for local dev where vendor is mounted)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Install production PHP extensions
RUN install-php-extensions \
    pdo_pgsql pdo_mysql gd intl zip opcache redis pcntl bcmath exif calendar mbstring

# Create laravel user with www-data group
RUN useradd -u 1000 -g www-data -m laravel

WORKDIR /var/www/html

# Copy application from builder stage
COPY --from=builder --chown=laravel:www-data /var/www/html /var/www/html

# Create Octane binary links
RUN mkdir -p /var/www/html/vendor/laravel/octane/bin \
    && ln -sf /usr/local/bin/frankenphp /var/www/html/vendor/laravel/octane/bin/frankenphp-linux-x86_64 \
    && ln -sf /usr/local/bin/frankenphp /var/www/html/vendor/laravel/octane/bin/frankenphp-linux-aarch64 \
    && chown -R laravel:www-data /var/www/html/storage /var/www/html/bootstrap/cache /var/www/html/vendor/laravel/octane/bin \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

# Switch to laravel user for optimization commands
USER laravel

# Run Laravel optimizations only in production/staging
# In local dev, these caches are overwritten by mounted files anyway
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

# Switch back to root for supervisord
USER root

# Default command: run supervisord
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/00-base.conf"]
