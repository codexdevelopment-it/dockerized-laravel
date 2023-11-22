FROM php:8.2-fpm

# Arguments defined in docker-compose.yml
ARG user
ARG uid

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libjpeg-dev \
    libfreetype6-dev \
    zip \
    unzip

# Install mysql client
RUN apt-get install -y default-mysql-client

# Install node and npm
RUN apt-get install -y nodejs
RUN apt-get install -y npm

# Install xdebug
RUN pecl install xdebug && docker-php-ext-enable xdebug

# Clear cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-configure gd --enable-gd --with-freetype --with-jpeg
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd intl zip

# Get latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copy modified php.ini
COPY php.ini /usr/local/etc/php/

# Add user with sail name (to use Laravel Sail)
RUN useradd -m -g www-data sail -u 1001

USER sail