#!/bin/bash
#############################################
# Cipi Migration 4.7.17 — Panel API fixes for Ubuntu 25.10+ / 26.04
#
# Consolidates fixes for servers upgrading in one step:
#   - sudo-rs compatible /etc/sudoers.d/cipi-api (4.7.15)
#   - API PHP-FPM open_basedir: allow is_executable() on /usr/local/bin/cipi*
#   - Verify read-only-safe common.sh (code fix in lib/common.sh + lib/vault.sh)
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
CIPI_API_ROOT="${CIPI_API_ROOT:-/opt/cipi/api}"

echo "Migration 4.7.17 — Panel API: sudoers + open_basedir..."

# ── 1. sudo-rs compatible sudoers ─────────────────────────────
if [[ -f "${CIPI_LIB}/cipi-api-sudoers.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/cipi-api-sudoers.sh"
    write_cipi_api_sudoers
    echo "  /etc/sudoers.d/cipi-api refreshed (sudo-rs)"
else
    echo "  WARN: cipi-api-sudoers.sh missing — skip sudoers"
fi

# ── 2. API FPM open_basedir: /usr/local/bin/ ──────────────────
PHP_VER=""
for pv in 8.5 8.4 8.3 8.2 8.1 8.0 7.4; do
    if [[ -f "/etc/php/${pv}/fpm/pool.d/cipi-api.conf" ]]; then
        PHP_VER="$pv"
        break
    fi
done

if [[ -n "$PHP_VER" ]]; then
    pool="/etc/php/${PHP_VER}/fpm/pool.d/cipi-api.conf"
    basedir="${CIPI_API_ROOT}/:/tmp/:/etc/cipi/:/proc/:/usr/local/bin/"
    if grep -q '/usr/local/bin/' "$pool" 2>/dev/null; then
        echo "  open_basedir already includes /usr/local/bin/ (php${PHP_VER})"
    else
        sed -i "s|^php_admin_value\\[open_basedir\\] = .*|php_admin_value[open_basedir] = ${basedir}|" "$pool"
        echo "  open_basedir updated on php${PHP_VER} FPM pool"
    fi
    if command -v systemctl &>/dev/null; then
        systemctl reload "php${PHP_VER}-fpm" 2>/dev/null \
            || systemctl restart "php${PHP_VER}-fpm" 2>/dev/null \
            || true
        echo "  php${PHP_VER}-fpm reloaded"
    fi
else
    echo "  No cipi-api FPM pool found — skip open_basedir"
fi

# ── 3. Verify read-only-safe common.sh ──────────────────────────
if [[ -f "${CIPI_LIB}/common.sh" ]] && grep -q '_cipi_config_writable' "${CIPI_LIB}/common.sh"; then
    echo "  common.sh includes read-only /etc/cipi guards"
else
    echo "  WARN: common.sh missing _cipi_config_writable — re-run cipi self-update"
fi

echo "Migration 4.7.17 complete"
