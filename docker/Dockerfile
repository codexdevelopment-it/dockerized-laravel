# Stage 1: Build stage
FROM dunglas/frankenphp:1.11.2-php8.3 AS builder

# Ensure the extension installer is present
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# Install build-time tools (Included Node.js/npm for frontend assets)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git unzip curl nodejs npm && rm -rf /var/lib/apt/lists/*

# Install extensions
RUN install-php-extensions zip intl bcmath exif calendar

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /var/www/html

# Copy app files from the root context
COPY composer.json composer.lock package.json* package-lock.json* ./

# Install dependencies WITHOUT --no-dev so dev packages (like Pail, Pint, etc.) stay for local dev
RUN composer install --no-scripts --no-autoloader --prefer-dist

COPY . .
RUN composer dump-autoload --optimize --no-scripts

# Stage 2: Production & Local stage
FROM dunglas/frankenphp:1.11.2-php8.3 AS production

# Ensure the extension installer is present
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions

# Set the server name for FrankenPHP
ENV SERVER_NAME=":8000"

# --- FIXED: Added git and unzip so Composer can actually download/extract packages inside the container ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor curl acl nano procps git unzip && rm -rf /var/lib/apt/lists/*

# --- FIXED: Copy Composer into the final running container ---
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Install production extensions
RUN install-php-extensions \
    pdo_pgsql pdo_mysql gd intl zip opcache redis pcntl bcmath exif calendar mbstring

# Use laravel user and Debian's native www-data group
# Debian's www-data group already exists (usually GID 33). We create the 'laravel' user and add it to this group.
RUN useradd -u 1000 -g www-data -m laravel

WORKDIR /var/www/html

# 1. Copy the application from the builder stage with new ownership
COPY --from=builder --chown=laravel:www-data /var/www/html /var/www/html

# 2. Config files from the docker context
COPY --chown=laravel:www-data ./docker/php.ini /usr/local/etc/php/php.ini
COPY ./docker/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Permissions and Octane binary setup
RUN mkdir -p /var/www/html/vendor/laravel/octane/bin \
    && ln -sf /usr/local/bin/frankenphp /var/www/html/vendor/laravel/octane/bin/frankenphp-linux-x86_64 \
    && ln -sf /usr/local/bin/frankenphp /var/www/html/vendor/laravel/octane/bin/frankenphp-linux-aarch64 \
    && chown -R laravel:www-data /var/www/html/storage /var/www/html/bootstrap/cache /var/www/html/vendor/laravel/octane/bin \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

USER laravel

# --- FLEXIBLE OPTIMIZATION SECTION ---
RUN php artisan config:cache && \
    php artisan route:cache && \
    php artisan view:cache && \
    if php artisan list | grep -q "filament:optimize"; then \
        echo "Filament detected, optimizing..." && \
        php artisan filament:optimize; \
    else \
        echo "Filament not found, skipping filament:optimize."; \
    fi
# -------------------------------------

EXPOSE 8000

# Run as root so Supervisord can manage processes, but workers run as 'laravel'
USER root
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
