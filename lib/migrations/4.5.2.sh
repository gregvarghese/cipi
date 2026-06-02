#!/bin/bash
#############################################
# Cipi Migration 4.5.2 — Panel API server-metrics pruning
#
# 4.5.1 wired up the panel scheduler + daily maintenance and stopped three
# unbounded-growth sources (cipi-job-logs files, cipi_jobs/failed_jobs rows,
# database.sqlite-wal). One source was missed: the cipi-api package's
# `cipi:record-server-metrics` command runs EVERY MINUTE and inserts one row
# into a server-metrics table. Nothing prunes it.
#
# At ~1440 rows/day the table reaches hundreds of thousands of rows within a
# few months. The panel dashboard / `/api` server endpoints query it on every
# load; with the table unbounded (and SQLite scanning it) each query slows
# until it crosses PHP-FPM's request_terminate_timeout (300s). FPM SIGKILLs
# the worker mid-request, so Laravel never writes an error and the browser
# just gets "HTTP ERROR 500" — intermittently at first, then constantly, with
# no obvious cause. This is the residual "API goes 500 after a while" report.
#
# This migration:
#  - rewrites /usr/local/bin/cipi-api-maintain to also prune the metrics table
#    (table + timestamp column auto-discovered from the schema, so it stays
#    correct regardless of cipi-api package version)
#  - runs a one-time prune + WAL checkpoint so the benefit is immediate
#
# Idempotent: full rewrite of the helper; SQL DELETEs filter by age. Safe to
# re-run.
#############################################

set -e

CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"
CIPI_API_ROOT="${CIPI_API_ROOT:-/opt/cipi/api}"
CIPI_API_CONFIG="${CIPI_CONFIG}/api.json"

echo "Migration 4.5.2 — Panel API server-metrics pruning..."

if [[ -f "${CIPI_LIB}/common.sh" ]]; then
    # shellcheck source=/dev/null
    source "${CIPI_LIB}/common.sh"
fi

# Skip cleanly if API was never installed on this server.
if [[ ! -f "$CIPI_API_CONFIG" ]] || [[ ! -f "${CIPI_API_ROOT}/artisan" ]]; then
    echo "  API not installed on this server — nothing to do"
    echo "Migration 4.5.2 complete"
    exit 0
fi

# 1. Rewrite the maintenance helper with metrics pruning. Kept inline (not
#    sourced from lib/api.sh) so this migration is a self-contained snapshot.
cat > /usr/local/bin/cipi-api-maintain <<'MAINTAIN'
#!/bin/bash
# Cipi API daily maintenance — see /etc/cron.d/cipi-api.
set -u
API_ROOT="/opt/cipi/api"
DB_FILE=""
if [[ -f "${API_ROOT}/.env" ]] && grep -q '^DB_CONNECTION=sqlite' "${API_ROOT}/.env" 2>/dev/null; then
    raw=$(grep '^DB_DATABASE=' "${API_ROOT}/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]"\r')
    [[ -z "$raw" || "$raw" == "null" ]] && raw="database/database.sqlite"
    if [[ "$raw" =~ ^/ ]]; then
        DB_FILE="$raw"
    else
        DB_FILE="${API_ROOT}/${raw}"
    fi
fi

echo "[$(date '+%F %T')] cipi-api-maintain start"

if [[ -f "${API_ROOT}/artisan" ]]; then
    (cd "${API_ROOT}" && /usr/bin/php artisan queue:prune-failed --hours=336 2>&1) || true
fi

if [[ -n "$DB_FILE" && -f "$DB_FILE" ]] && command -v sqlite3 >/dev/null 2>&1; then
    deleted=$(/usr/bin/sqlite3 "$DB_FILE" \
        "DELETE FROM cipi_jobs WHERE status IN ('completed','failed') AND created_at < datetime('now','-14 days'); SELECT changes();" 2>/dev/null)
    echo "  cipi_jobs pruned: ${deleted:-0}"

    # Prune the server-metrics table (cipi:record-server-metrics writes one
    # row/minute; unbounded growth slows dashboard queries → FPM timeout 500s).
    # Table/column auto-discovered so this is package-version independent.
    mtable=$(/usr/bin/sqlite3 "$DB_FILE" \
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%metric%' ORDER BY (name='cipi_server_metrics') DESC, length(name) LIMIT 1;" 2>/dev/null)
    if [[ -n "$mtable" ]]; then
        mcol=$(/usr/bin/sqlite3 "$DB_FILE" \
            "SELECT name FROM pragma_table_info('${mtable}') WHERE name IN ('created_at','recorded_at','timestamp','measured_at','created') ORDER BY (name='created_at') DESC LIMIT 1;" 2>/dev/null)
        if [[ -n "$mcol" ]]; then
            mdeleted=$(/usr/bin/sqlite3 "$DB_FILE" \
                "DELETE FROM \"${mtable}\" WHERE \"${mcol}\" < datetime('now','-14 days'); SELECT changes();" 2>/dev/null)
            echo "  ${mtable} pruned: ${mdeleted:-0}"
        else
            echo "  ${mtable}: no known timestamp column — skipped"
        fi
    fi

    /usr/bin/sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
    echo "  WAL checkpoint: ok"
fi

echo "[$(date '+%F %T')] cipi-api-maintain done"
MAINTAIN
chmod 755 /usr/local/bin/cipi-api-maintain
chown root:root /usr/local/bin/cipi-api-maintain
echo "  /usr/local/bin/cipi-api-maintain updated (metrics pruning added)"

# 2. One-time prune + WAL checkpoint so the table shrinks immediately instead
#    of waiting for 04:15.
DB_FILE=""
if [[ -f "${CIPI_API_ROOT}/.env" ]] && grep -q '^DB_CONNECTION=sqlite' "${CIPI_API_ROOT}/.env" 2>/dev/null; then
    raw=$(grep '^DB_DATABASE=' "${CIPI_API_ROOT}/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]"\r')
    [[ -z "$raw" || "$raw" == "null" ]] && raw="database/database.sqlite"
    if [[ "$raw" =~ ^/ ]]; then
        DB_FILE="$raw"
    else
        DB_FILE="${CIPI_API_ROOT}/${raw}"
    fi
fi
if [[ -n "$DB_FILE" && -f "$DB_FILE" ]] && command -v sqlite3 &>/dev/null; then
    mtable=$(sudo -u www-data sqlite3 "$DB_FILE" \
        "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%metric%' ORDER BY (name='cipi_server_metrics') DESC, length(name) LIMIT 1;" 2>/dev/null)
    if [[ -n "$mtable" ]]; then
        mcol=$(sudo -u www-data sqlite3 "$DB_FILE" \
            "SELECT name FROM pragma_table_info('${mtable}') WHERE name IN ('created_at','recorded_at','timestamp','measured_at','created') ORDER BY (name='created_at') DESC LIMIT 1;" 2>/dev/null)
        if [[ -n "$mcol" ]]; then
            mdeleted=$(sudo -u www-data sqlite3 "$DB_FILE" \
                "DELETE FROM \"${mtable}\" WHERE \"${mcol}\" < datetime('now','-14 days'); SELECT changes();" 2>/dev/null)
            echo "  ${mtable}: pruned ${mdeleted:-0} row(s) older than 14 days"
        else
            echo "  ${mtable}: no known timestamp column — skipped one-time prune"
        fi
    else
        echo "  no server-metrics table found — nothing to prune"
    fi
    sudo -u www-data sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
    echo "  ${DB_FILE}: WAL checkpoint(TRUNCATE)"
fi

echo "Migration 4.5.2 complete"
