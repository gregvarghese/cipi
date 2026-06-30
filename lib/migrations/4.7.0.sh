#!/bin/bash
#############################################
# Cipi Migration 4.7.0 — Cipi GUI CLI integration
#
# Bundles lib/gui.sh (cipi/gui package comes from GitHub VCS at install time).
# Reclaims GUI writable paths if the panel is already installed.
#
# Idempotent — safe to re-run.
#############################################

set -euo pipefail

export CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
export CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
export CIPI_LOG="${CIPI_LOG:-/var/log/cipi}"

echo "Migration 4.7.0 — Cipi GUI CLI integration..."

if [[ -f /opt/cipi/lib/gui.sh ]]; then
    # shellcheck source=/dev/null
    source /opt/cipi/lib/gui.sh
    if type ensure_cipi_gui_permissions &>/dev/null; then
        ensure_cipi_gui_permissions
        echo "  ensure_cipi_gui_permissions applied"
    fi
else
    echo "  lib/gui.sh not found — skip permissions"
fi

echo "Migration 4.7.0 complete."
