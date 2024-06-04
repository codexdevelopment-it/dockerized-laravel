FROM php:8.3-fpm-alpine

# Install system dependencies
RUN apk update && apk add \
    icu \
    oniguruma-dev \
    zlib-dev \
    libpng-dev \
    icu-dev \
    libzip-dev \
    git \
    curl \
    zip \
    unzip \
    procps \
    acl \
    nodejs \
    libwebp-dev \
    jpeg-dev \
    tzdata \
    npm

# Install bash
RUN apk add --no-cache bash

# Set timezone
RUN cp /usr/share/zoneinfo/Europe/Rome /etc/localtime

# Clear package cache
RUN rm -rf /var/cache/apk/*

# Install PHP extensions
RUN docker-php-ext-configure gd --with-webp  --with-jpeg;
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd intl zip

# Get latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Remove original php.ini (for larger file uploads) and copy our own
RUN rm /usr/local/etc/php/php.ini*
COPY php.ini /usr/local/etc/php/
RUN chmod a+r /usr/local/etc/php/php.ini

# Add user with sail name (to use Laravel Sail)
RUN adduser -S sail -G www-data --uid 1001
USER sail