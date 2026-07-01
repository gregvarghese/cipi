#!/bin/bash
#############################################
# Cipi Migration 4.7.7 — apps-public.json: expose suspended + basic_auth
#
# apps-public.json is the API read model. Suspend/unsuspend and basic auth
# state live in apps.json but were omitted from the projection, so GET /apps
# never reported suspended=true and the GUI kept showing "Suspend".
#############################################

set -e

CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.7.7 — Regenerate apps-public.json with suspended/basic_auth flags..."

if [[ -f "${CIPI_LIB}/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/common.sh"
fi

if type _update_apps_public &>/dev/null; then
    _update_apps_public
    echo "  apps-public.json regenerated"
else
    echo "  _update_apps_public not found — skipped"
fi

echo "Migration 4.7.7 complete"
