#!/usr/bin/env bash
# =============================================================================
# Build hook: runs as root in the staging/production image after the app code
# is in /var/www/html (the working directory), before the image is finished.
# Use it for build steps that need the code, e.g. downloading model weights the
# app would otherwise fetch on first use. storage/ is replaced by the runtime
# mount, so don't write there. Files of this directory are in /dock-build.
# =============================================================================
set -euo pipefail
