#!/bin/bash
#############################################
# Cipi Migration 4.2.5
# - Migrate Composer package names from
#   andreapollastri/* to cipi/* org
#############################################

set -e

echo "Migrating package names to cipi org..."

# ── Migrate cipi-api Composer package ──────────────────────────
CIPI_API_ROOT="${CIPI_API_ROOT:-/opt/cipi/api}"

if [[ -f "${CIPI_API_ROOT}/artisan" ]]; then
    echo "  Updating cipi-api package name in Laravel app..."

    # Replace old package with new one
    if (cd "$CIPI_API_ROOT" && composer show andreapollastri/cipi-api 2>/dev/null) >/dev/null 2>&1; then
        (cd "$CIPI_API_ROOT" && composer remove andreapollastri/cipi-api --no-interaction 2>/dev/null) || true

        local_pkg="/opt/cipi/cipi-api"
        if [[ -d "$local_pkg" ]]; then
            (cd "$CIPI_API_ROOT" && composer config repositories.cipi-api path "$local_pkg" 2>/dev/null) || true
            (cd "$CIPI_API_ROOT" && composer require cipi/api:@dev --no-interaction 2>/dev/null) || true
        else
            (cd "$CIPI_API_ROOT" && composer require cipi/api --no-interaction 2>/dev/null) || true
        fi
        echo "  Package migrated: andreapollastri/cipi-api → cipi/api"
    else
        echo "  Old package not found — skip"
    fi

    # Re-publish assets and run migrations
    chown -R www-data:www-data "$CIPI_API_ROOT" 2>/dev/null || true
    (cd "$CIPI_API_ROOT" && sudo -u www-data php artisan vendor:publish --tag=cipi-assets --force 2>/dev/null) || true
    (cd "$CIPI_API_ROOT" && sudo -u www-data php artisan migrate --force 2>/dev/null) || true
    systemctl restart cipi-queue 2>/dev/null || true
else
    echo "  API app not installed — skip"
fi

# ── Update crontab comments for app users ──────────────────────
for home in /home/*/; do
    user=$(basename "$home")
    [[ "$user" == "cipi" || "$user" == "lost+found" ]] && continue
    if crontab -u "$user" -l 2>/dev/null | grep -q 'andreapollastri/cipi-agent'; then
        crontab -u "$user" -l 2>/dev/null | sed 's|andreapollastri/cipi-agent|cipi/agent|g' | crontab -u "$user" -
        echo "  Updated crontab comment for $user"
    fi
done

echo "Migration 4.2.5 complete"
