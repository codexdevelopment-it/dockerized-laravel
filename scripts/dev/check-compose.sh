#!/usr/bin/env bash
# Validate `docker compose config` for every APP_ENV x SERVER x DB_DRIVER
# combination, with every optional service enabled. Used by `make lint` and CI.
set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -R "${root}/dock" "${root}/scripts" "${root}/docker" "$work/"
cd "$work" || exit 1

fails=0 total=0
for env in local staging production; do
    for server in artisan octane fpm nginx caddy; do
        for db in mariadb postgres pgvector; do
            services="redis,mailpit,meilisearch,soketi,gotenberg"
            [[ "$db" == "mariadb" ]] && services="${services},phpmyadmin"
            printf 'CONTAINER_NAME=ci\nAPP_ENV=%s\nSERVER=%s\nDB_DRIVER=%s\nSERVICES=%s\nDB_DATABASE=d\nDB_USERNAME=u\nDB_PASSWORD=p\n' \
                "$env" "$server" "$db" "$services" > .env
            total=$((total + 1))
            if ! out="$(./dock config -q 2>&1)"; then
                echo "FAIL ${env}/${server}/${db}: ${out}"
                fails=$((fails + 1))
            fi
        done
    done
done

echo "compose config: $((total - fails))/${total} ok"
[[ $fails -eq 0 ]]
