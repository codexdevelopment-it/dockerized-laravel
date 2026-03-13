# Stage 1: Build stage
FROM dunglas/frankenphp:1.11.2-php8.3 AS builder

# --- FIX: Ensure the extension installer is present ---
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# Install build-time tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip && rm -rf /var/lib/apt/lists/*

# Install extensions (including opentelemetry)
RUN install-php-extensions zip intl bcmath exif opentelemetry

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/html

COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

COPY . .
RUN composer dump-autoload --optimize --no-dev --no-scripts

# Stage 2: Production stage
FROM dunglas/frankenphp:1.11.2-php8.3 AS production

# --- FIX: Ensure the extension installer is present here too ---
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# --- Set the server name to listen on port 8000 ---
ENV SERVER_NAME=":8000"

RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor curl && rm -rf /var/lib/apt/lists/*

# Install all required extensions for production
RUN install-php-extensions \
    pdo_pgsql pdo_mysql gd intl zip opcache redis pcntl bcmath exif opentelemetry

RUN groupadd -g 1000 appgroup && useradd -u 1000 -g appgroup -m appuser

WORKDIR /var/www/html

COPY --from=builder --chown=appuser:appgroup /var/www/html /var/www/html
COPY --chown=appuser:appgroup ./.docker/php.ini /usr/local/etc/php/php.ini
COPY ./.docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN mkdir -p /var/www/html/vendor/laravel/octane/bin \
    && ln -sf /usr/local/bin/frankenphp /var/www/html/vendor/laravel/octane/bin/frankenphp-linux-x86_64 \
    && chown -R appuser:appgroup /var/www/html/storage /var/www/html/bootstrap/cache /var/www/html/vendor/laravel/octane/bin \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

USER appuser

# Disable OTel specifically for these build-time commands to prevent hangs
RUN OTEL_PHP_AUTOLOAD_ENABLED=false php artisan config:cache && \
    OTEL_PHP_AUTOLOAD_ENABLED=false php artisan route:cache && \
    OTEL_PHP_AUTOLOAD_ENABLED=false php artisan view:cache && \
    OTEL_PHP_AUTOLOAD_ENABLED=false php artisan filament:optimize && \
    rm -f bootstrap/cache/*.php

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/up || exit 1

USER root
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]