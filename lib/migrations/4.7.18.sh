#!/bin/bash
#############################################
# Cipi Migration 4.7.18 — Fix `cipi db list` (completes 4.7.16 / 4.7.17)
#
# Servers that already ran 4.7.16 only got chmod || true on common.sh — not enough:
# ensure_apps_json_api_access still wrote apps-public.json on read-only /etc/cipi.
# 4.7.17 fixed sudo-rs sudoers + API open_basedir but only WARNed if lib/*.sh
# lacked read-only guards.
#
# 4.7.18 is the migration that closes the gap for every upgrade path:
#   • read-only /etc/cipi (lib/common.sh + lib/vault.sh, no init chmod)
#   • db list lists empty databases (lib/db.sh schemata query)
#   • remount / rw when /etc/cipi is read-only
#   • re-applies sudoers + open_basedir (idempotent)
#   • refreshes apps-public.json when writable
#   • smoke-tests `sudo cipi db list` as www-data
#
# Do not retro-edit migrations 4.7.16 or 4.7.17 — they are historical steps.
#############################################

set -e

CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
CIPI_API_ROOT="${CIPI_API_ROOT:-/opt/cipi/api}"
CIPI_REPO="${CIPI_REPO:-cipi-sh/cipi}"
CIPI_BRANCH="${CIPI_BRANCH:-latest}"
CIPI_UPDATE_TMP="${CIPI_UPDATE_TMP:-}"
COMMON="${CIPI_LIB}/common.sh"
VAULT="${CIPI_LIB}/vault.sh"
DB_SH="${CIPI_LIB}/db.sh"

echo "Migration 4.7.18 — Fix cipi db list (read-only /etc/cipi + panel API)..."

# ── 1. Remount / rw when /etc/cipi cannot accept writes ─────────
_cipi_probe_writable() {
    local probe="${CIPI_CONFIG}/.cipi-migrate-writable-$$"
    touch "$probe" 2>/dev/null || return 1
    rm -f "$probe" 2>/dev/null || true
    return 0
}

if ! _cipi_probe_writable; then
    echo "  /etc/cipi is read-only — attempting mount -o remount,rw / ..."
    mount -o remount,rw / 2>/dev/null || true
    if _cipi_probe_writable; then
        echo "  remount,rw / succeeded"
    else
        echo "  WARN: / still read-only — need 4.7.18 lib/*.sh on disk"
        echo "        Check: mount | grep ' on / '; dmesg | tail -20"
    fi
fi

# ── 2. Ensure lib/common.sh + lib/vault.sh + lib/db.sh from 4.7.18 ──
_418_lib_ok() {
    [[ -f "$COMMON" ]] && grep -q '_cipi_config_writable || return 0' "$COMMON" \
        && ! grep -qE '^chmod 700 "\$\{CIPI_CONFIG\}"' "$COMMON" \
        && [[ -f "$VAULT" ]] && grep -q '_cipi_safe_chmod' "$VAULT"
}

_418_db_ok() {
    [[ -f "$DB_SH" ]] && grep -q 'information_schema.schemata' "$DB_SH"
}

_418_install_lib_from_bundle() {
    local src="$1"
    [[ -d "$src" ]] || return 1
    [[ -f "${src}/common.sh" && -f "${src}/vault.sh" ]] || return 1
    cp -a "$COMMON" "${COMMON}.bak.418-$(date +%s)" 2>/dev/null || true
    cp -a "$VAULT" "${VAULT}.bak.418-$(date +%s)" 2>/dev/null || true
    cp "${src}/common.sh" "$COMMON"
    cp "${src}/vault.sh" "$VAULT"
    [[ -f "${src}/db.sh" ]] && cp -a "$DB_SH" "${DB_SH}.bak.418-$(date +%s)" 2>/dev/null || true
    [[ -f "${src}/db.sh" ]] && cp "${src}/db.sh" "$DB_SH"
    chmod 700 "$COMMON" "$VAULT" "$DB_SH" 2>/dev/null || true
    return 0
}

if ! _418_lib_ok || ! _418_db_ok; then
    echo "  lib/*.sh outdated — installing 4.7.18 lib..."
    if [[ -n "$CIPI_UPDATE_TMP" && -d "${CIPI_UPDATE_TMP}/lib" ]] \
        && _418_install_lib_from_bundle "${CIPI_UPDATE_TMP}/lib"; then
        echo "  Installed from self-update bundle (${CIPI_UPDATE_TMP}/lib)"
    elif command -v curl &>/dev/null; then
        tmp_lib="/tmp/cipi-418-lib.$$"
        mkdir -p "$tmp_lib"
        if curl -fsSL "https://raw.githubusercontent.com/${CIPI_REPO}/refs/heads/${CIPI_BRANCH}/lib/common.sh" -o "${tmp_lib}/common.sh" \
            && curl -fsSL "https://raw.githubusercontent.com/${CIPI_REPO}/refs/heads/${CIPI_BRANCH}/lib/vault.sh" -o "${tmp_lib}/vault.sh" \
            && curl -fsSL "https://raw.githubusercontent.com/${CIPI_REPO}/refs/heads/${CIPI_BRANCH}/lib/db.sh" -o "${tmp_lib}/db.sh" \
            && _418_install_lib_from_bundle "$tmp_lib"; then
            echo "  Installed from GitHub (${CIPI_BRANCH})"
        fi
        rm -rf "$tmp_lib"
    fi
fi

if ! _418_lib_ok; then
    echo "  ERROR: could not install 4.7.18 lib/common.sh + lib/vault.sh"
    echo "        Run: sudo mount -o remount,rw / && sudo cipi self-update"
    exit 1
fi
echo "  lib/common.sh + lib/vault.sh: read-only-safe (no init chmod)"

if ! _418_db_ok; then
    echo "  ERROR: lib/db.sh missing schemata query — re-run cipi self-update"
    exit 1
fi
echo "  lib/db.sh: lists empty databases (schemata query)"

# ── 3. sudo-rs compatible sudoers (4.7.15 / 4.7.17 — redo for safety) ──
if [[ -f "${CIPI_LIB}/cipi-api-sudoers.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/cipi-api-sudoers.sh"
    write_cipi_api_sudoers
    echo "  /etc/sudoers.d/cipi-api refreshed (sudo-rs)"
else
    echo "  WARN: cipi-api-sudoers.sh missing — skip sudoers"
fi

# ── 4. API FPM open_basedir: /usr/local/bin/ (4.7.17 — redo for safety) ──
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

# ── 5. Regenerate apps-public.json when /etc/cipi is writable ───
if _cipi_probe_writable && [[ -f "$COMMON" ]]; then
    # shellcheck source=/dev/null
    ( set +e; source "$COMMON"; type ensure_apps_json_api_access &>/dev/null && ensure_apps_json_api_access ) || true
    echo "  apps-public.json refresh attempted"
fi

# ── 6. Smoke test: panel API path for db list ───────────────────
if command -v sudo &>/dev/null && [[ -x /usr/local/bin/cipi ]]; then
    if out=$(sudo -u www-data sudo -n /usr/local/bin/cipi db list 2>&1); then
        echo "  smoke test: sudo cipi db list OK"
    else
        echo "  WARN: smoke test failed (sudo -u www-data sudo -n cipi db list):"
        echo "$out" | sed 's/^/    /'
    fi
else
    echo "  smoke test skipped (sudo or /usr/local/bin/cipi unavailable)"
fi

echo "Migration 4.7.18 complete"
