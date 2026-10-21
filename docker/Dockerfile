# syntax=docker/dockerfile:1
# =============================================================================
# Dockerized Laravel - multi-target Dockerfile
#
# Targets (picked by compose via DOCK_ENV, see docker/compose/base.yml):
#   local       base + Node, no app code baked in (the project is bind-mounted).
#               Builds in seconds and never touches the build context.
#   staging     code + vendor + built assets baked in.
#   production  same as staging, composer --no-dev.
#
# Stage graph:
# Project hooks: APT_PACKAGES and docker/config/build/runtime.sh (app-base),
# docker/config/build/release.sh (release). Plain `docker build` needs
# --build-context dock-build=docker/config/build.
#
#   base ──┬── app-base ──┬── local
#          │              └── release ── staging / production
#          └── builder ───────────┘ (vendor + public/build)
#
# Versions are build args, overridable from .env (PHP_VERSION, NODE_VERSION, ...).
# =============================================================================

ARG PHP_VERSION=8.5.12
ARG NODE_VERSION=24
ARG DEBIAN_RELEASE=trixie
# PHP image everything builds on. dock passes php:<PHP_VERSION>-fpm-trixie, or
# for SERVER=octane dunglas/frankenphp:<FRANKENPHP_VERSION>-php<PHP_VERSION>-trixie
# (ZTS PHP + FrankenPHP linked against it): server, CLI and workers then run the
# same PHP version with the same extensions.
ARG PHP_BASE_IMAGE=php:${PHP_VERSION}-fpm-${DEBIAN_RELEASE}

FROM node:${NODE_VERSION}-${DEBIAN_RELEASE}-slim AS node
FROM composer:2 AS composer
FROM mlocati/php-extension-installer:2 AS php-ext

# -----------------------------------------------------------------------------
# base: PHP + extensions + system tools. Shared by every other stage, so
# extensions are compiled once (they used to be built twice).
# -----------------------------------------------------------------------------
FROM ${PHP_BASE_IMAGE} AS base

# Extra extensions on top of the defaults, space separated (e.g. "imagick soap").
ARG PHP_EXTENSIONS=""
ARG PHPREDIS_VERSION=6.3.0
# liblzf submodule commit of that phpredis tag (GitHub tarballs omit submodules)
ARG LIBLZF_COMMIT=fb25820c3c0aeafd127956ae6c115063b47e459a

COPY --from=php-ext /usr/bin/install-php-extensions /usr/local/bin/
COPY --from=composer /usr/bin/composer /usr/bin/composer

# phpredis is built from its GitHub tag instead of PECL: pecl.php.net is
# unreliable (HTTP 500/504 for hours) and broke image builds.
RUN apt-get update \
    && apt-get install -y --no-install-recommends supervisor acl procps curl git unzip \
    && mkdir -p /tmp/phpredis \
    && curl -fsSL --retry 5 --retry-all-errors \
        "https://codeload.github.com/phpredis/phpredis/tar.gz/refs/tags/${PHPREDIS_VERSION}" \
        | tar -xz -C /tmp/phpredis --strip-components=1 \
    && curl -fsSL --retry 5 --retry-all-errors \
        "https://codeload.github.com/nemequ/liblzf/tar.gz/${LIBLZF_COMMIT}" \
        | tar -xz -C /tmp/phpredis/liblzf --strip-components=1 \
    && install-php-extensions \
        bcmath calendar exif gd intl opcache pcntl pdo_mysql pdo_pgsql pgsql zip \
        /tmp/phpredis \
        ${PHP_EXTENSIONS} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /usr/src/*

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1

WORKDIR /var/www/html

# -----------------------------------------------------------------------------
# app-base: runtime user + supervisor + project hooks.
# -----------------------------------------------------------------------------
FROM base AS app-base

ARG USER_ID=1000
ARG GROUP_ID=1000
# 1 only when SERVER=octane (dock sets it, with the FrankenPHP base image).
ARG WITH_FRANKENPHP=0

# Runtime user matching the host UID/GID so bind-mounted files keep sane owners.
# UID/GID 0 is refused: the app never runs as root.
RUN if [ "${USER_ID}" = "0" ] || [ "${GROUP_ID}" = "0" ]; then \
        echo "ERROR: USER_ID/GROUP_ID must not be 0 (refusing to run as root)" >&2; exit 1; \
    fi \
    && if getent group "${GROUP_ID}" >/dev/null; then \
        GROUP_NAME=$(getent group "${GROUP_ID}" | cut -d: -f1); \
    else \
        groupadd -g "${GROUP_ID}" laravel; GROUP_NAME=laravel; \
    fi \
    && if getent passwd "${USER_ID}" >/dev/null; then \
        EXISTING_USER=$(getent passwd "${USER_ID}" | cut -d: -f1); \
        [ "$EXISTING_USER" = "laravel" ] || usermod -l laravel -d /home/laravel -m "$EXISTING_USER"; \
    else \
        useradd -u "${USER_ID}" -g "${GROUP_NAME}" -m -s /bin/bash laravel; \
    fi \
    && usermod -aG www-data laravel \
    && mkdir -p /etc/supervisor/programs

# Project additions (APT_PACKAGES in .env, docker/config/build/runtime.sh).
# docker/config/build is the separate build context "dock-build" (compose
# additional_contexts), so the project's .dockerignore can't hide it.
ARG APT_PACKAGES=""
RUN --mount=type=bind,from=dock-build,target=/dock-build \
    if [ -n "${APT_PACKAGES}" ]; then \
        apt-get update \
        && apt-get install -y --no-install-recommends ${APT_PACKAGES} \
        && rm -rf /var/lib/apt/lists/*; \
    fi \
    && if [ -f /dock-build/runtime.sh ]; then bash /dock-build/runtime.sh; fi

# SERVER=octane: FrankenPHP comes with the base image. Caddy (inside it) keeps
# certificates/state in XDG_DATA_HOME=/data and XDG_CONFIG_HOME=/config, which
# the laravel user must be able to write.
RUN if [ "${WITH_FRANKENPHP}" = "1" ]; then \
        frankenphp version \
        && mkdir -p /data/caddy /config/caddy \
        && chown -R laravel /data /config; \
    fi

EXPOSE 8000 9000
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/00-base.conf"]

# -----------------------------------------------------------------------------
# local: dev image. Code comes from the bind mount; Node is here for
# `./dock npm`, Vite and `octane --watch`.
# -----------------------------------------------------------------------------
FROM app-base AS local

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && ln -s ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack

# -----------------------------------------------------------------------------
# builder: composer + npm build. Never shipped.
# -----------------------------------------------------------------------------
FROM base AS builder

ARG BUILD_ENV=production

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm

# NO_DEV: `|| true` matters. An assignment takes the exit status of its command
# substitution, so without it a non-production build (staging) "fails" the
# assignment and `&&` silently skips composer: exit 1 with no output.

# Dependency manifests first for layer caching. composer.json anchors the COPY
# (a glob-only COPY with zero matches fails); the rest are optional.
COPY composer.json composer.lock* auth.json* ./

# Best effort: composer `path` repositories (e.g. ./nova-components/*,
# ./packages/*) only exist after `COPY . .`, so this layer may stop early.
# The install after the full copy completes it and reports real errors.
RUN --mount=type=cache,target=/root/.composer/cache \
    NO_DEV=$([ "$BUILD_ENV" = "production" ] && echo --no-dev || true) \
    && { composer install --no-scripts --no-autoloader --prefer-dist $NO_DEV \
        || echo "composer: dependency layer incomplete (path repositories?), completed below"; }

COPY package.json* package-lock.json* ./
RUN --mount=type=cache,target=/root/.npm \
    if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; \
    elif [ -f package.json ]; then npm install --no-audit --no-fund; fi

COPY . .

# Re-running composer install is idempotent when vendor/ matches the lock and
# self-heals if a missing .dockerignore let the host's vendor/ overwrite it.
# --no-scripts skips package:discover, and the host's bootstrap/cache was built
# with dev packages (e.g. Pail): rebuild the manifest for what is installed.
RUN --mount=type=cache,target=/root/.composer/cache \
    NO_DEV=$([ "$BUILD_ENV" = "production" ] && echo --no-dev || true) \
    && composer install --no-scripts --prefer-dist --optimize-autoloader $NO_DEV \
    && mkdir -p bootstrap/cache storage/framework/cache storage/framework/sessions \
        storage/framework/views storage/logs && rm -f bootstrap/cache/*.php \
    && php artisan package:discover --ansi \
    && if [ -f package.json ]; then npm run --if-present build; fi \
    && rm -rf node_modules auth.json

# -----------------------------------------------------------------------------
# release: staging / production image with code baked in.
# -----------------------------------------------------------------------------
FROM app-base AS release

COPY --from=builder --chown=laravel:www-data /var/www/html /var/www/html

RUN mkdir -p storage/app/public storage/framework/cache storage/framework/sessions \
             storage/framework/views storage/logs bootstrap/cache \
    && chown -R laravel:www-data storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

# Only env-independent caches here: .env is not in the build context, so
# config/route/event caches built now would bake a NULL APP_KEY (e.g. Livewire's
# /livewire-<hash>/ route prefix). `dock deploy` builds them at runtime with the
# real .env mounted. view:cache only compiles Blade, safe at build time.
RUN su laravel -s /bin/sh -c "php artisan view:cache" || true

# Project hook that needs the code (docker/config/build/release.sh).
RUN --mount=type=bind,from=dock-build,target=/dock-build \
    if [ -f /dock-build/release.sh ]; then bash /dock-build/release.sh; fi

FROM release AS staging
FROM release AS production
