#!/bin/bash
#############################################
# Cipi Migration 4.6.4 — self-update path recovery
#
# Servers stuck at 4.6.2 with libs already copied from 4.6.3 may have partial
# migration state (token-abilities.txt written, cron/notifications step failed).
# 4.6.3 re-runs idempotently on the way here; this migration verifies the fix
# and completes any remaining 4.6.3 steps. Safe no-op when already complete.
#############################################

set -euo pipefail

export CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
export CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
export CIPI_LOG="${CIPI_LOG:-/var/log/cipi}"

readonly COMMON="${CIPI_LIB}/common.sh"
readonly API_SH="${CIPI_LIB}/api.sh"

echo "Migration 4.6.4 — self-update path recovery..."

if [[ ! -f "$COMMON" ]]; then
    echo "  ERROR: ${COMMON} not found" >&2
    exit 1
fi

if ! grep -q 'BASH_SOURCE\[0\]' "$COMMON" 2>/dev/null; then
    echo "  ERROR: common.sh missing CIPI_LIB self-resolution (expected BASH_SOURCE derive)" >&2
    exit 1
fi
echo "  common.sh CIPI_LIB self-resolution OK"

if [[ -f "${CIPI_API_ROOT:-/opt/cipi/api}/token-abilities.txt" ]]; then
    echo "  token-abilities.txt present"
else
    echo "  WARN: token-abilities.txt missing — 4.6.3 should have created it"
fi

if [[ -f "$API_SH" ]] && grep -q 'token-abilities.txt' "$API_SH" 2>/dev/null; then
    echo "  api.sh reads token-abilities.txt"
else
    echo "  WARN: api.sh may still need the 4.6.3 patch"
fi

# Complete partial 4.6.3 steps (idempotent)
if [[ -f "$COMMON" && -f "$API_SH" ]]; then
    # shellcheck source=/dev/null
    source "$COMMON"
    # shellcheck source=/dev/null
    source "$API_SH"
    if [[ -f "${CIPI_CONFIG}/api.json" ]]; then
        _api_setup_cron
        echo "  /etc/cron.d/cipi-api verified/refreshed"
    else
        echo "  Panel API not configured — skip cron refresh"
    fi
fi

if [[ -f "${CIPI_LIB}/notifications.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/vault.sh"
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/notifications.sh"
    if [[ -f "${CIPI_CONFIG}/notifications.json" ]]; then
        echo "  notifications.json present"
    else
        _notify_ensure_config
        echo "  notifications.json created (all triggers enabled)"
    fi
fi

echo "Migration 4.6.4 complete"
