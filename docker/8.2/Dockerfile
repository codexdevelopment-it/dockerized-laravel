FROM php:8.2-fpm

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    zip \
    unzip \
    procps \
    acl

# Install mysqldump for backup
RUN apt-get update && apt-get install -y default-mysql-client

# Install node and npm
RUN apt-get install -y nodejs
RUN apt-get install -y npm

# Install tesseract for OCR
#RUN apt-get install -y     tesseract-ocr \
#                           tesseract-ocr-ita \
#                           imagemagick

# Image magick for pdf split in pages
#RUN apt-get update && apt-get install -y libmagickwand-dev --no-install-recommends && rm -rf /var/lib/apt/lists/*
#RUN mkdir -p /usr/src/php/ext/imagick; \
#    curl -fsSL https://github.com/Imagick/imagick/archive/06116aa24b76edaf6b1693198f79e6c295eda8a9.tar.gz | tar xvz -C "/usr/src/php/ext/imagick" --strip 1; \
#    docker-php-ext-install imagick;

# Install poppler-utils for pdfinfo
#RUN apt-get update && apt-get install -y poppler-utils

# Install ocrmypdf for OCR
RUN apt install ocrmypdf -y

# Clear cache
RUN apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd intl zip

# Get latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copy modified image magick policy
#RUN rm /etc/ImageMagick-6/policy.xml
#COPY image-magick-policy.xml /etc/ImageMagick-6/policy.xml

# Remove original php.ini (for larger file uploads)
RUN rm /usr/local/etc/php/php.ini*

# Copy modified php.ini
COPY php.ini /usr/local/etc/php/

# Add user with sail name (to use Laravel Sail)
RUN useradd -m -g www-data sail --uid 1001

# Change ownership of /var/www to sail
RUN chown -R sail /var/www

USER sail