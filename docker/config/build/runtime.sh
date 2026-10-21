#!/usr/bin/env bash
# =============================================================================
# Build hook: runs as root while building the runtime image (local, staging
# and production), before any app code is copied. Use it for what the app
# needs at runtime and PHP_EXTENSIONS / APT_PACKAGES can't express: a Python
# venv, a binary download, fonts, ...
#
# This directory is mounted at /dock-build (read only): ship your files next
# to this script, e.g. pip install -r /dock-build/requirements.txt.
# Simple Debian packages: APT_PACKAGES in .env instead.
# Rebuild after changes: ./dock start --build (or deploy).
# =============================================================================
set -euo pipefail
