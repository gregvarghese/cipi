#!/bin/bash
#############################################
# Cipi Migration 4.4.16 — Panel API SQLite/logs/cache + .env + PsySH (www-data)
#
# Composer and other root operations under /opt/cipi/api could leave
# database.sqlite or storage/logs owned by root, breaking artisan (sudo -u www-data)
# and PHP-FPM. ensure_cipi_api_permissions fixes storage, database, bootstrap/cache,
# and .env. PsySH (tinker) cache dir under www-data's home avoids flaky api status.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

echo "Migration 4.4.16 — Panel API permissions + PsySH home (www-data)..."

if [[ -f "${CIPI_LIB}/common.sh" ]]; then
    source "${CIPI_LIB}/common.sh"
fi

if type ensure_cipi_api_permissions &>/dev/null; then
    ensure_cipi_api_permissions
fi

h=$(getent passwd www-data 2>/dev/null | cut -d: -f6)
if [[ -n "$h" && -d "$h" ]]; then
    mkdir -p "${h}/.config/psysh" 2>/dev/null || true
    chown -R www-data:www-data "${h}/.config" 2>/dev/null || true
fi

echo "Migration 4.4.16 complete"
