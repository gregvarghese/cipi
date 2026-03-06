#!/bin/bash
#############################################
# Cipi Migration 4.0.8 — apps.json security
# Fix: app users could read other apps'
# webhook tokens via www-data group.
# Solution: dedicated cipi-api group for
# API file access.
#############################################

set -e

CIPI_CONFIG="/etc/cipi"

# 1. Create dedicated group for API config access
if ! getent group cipi-api &>/dev/null; then
    groupadd cipi-api 2>/dev/null || true
    echo "Created cipi-api group"
else
    echo "cipi-api group already exists — skip"
fi

# 2. Add www-data to cipi-api group
if ! id -nG www-data 2>/dev/null | grep -qw cipi-api; then
    usermod -aG cipi-api www-data 2>/dev/null || true
    echo "Added www-data to cipi-api group"
else
    echo "www-data already in cipi-api — skip"
fi

# 3. Fix permissions on /etc/cipi and apps.json
if [[ -f "${CIPI_CONFIG}/api.json" ]] && [[ -f "${CIPI_CONFIG}/apps.json" ]]; then
    chgrp cipi-api "${CIPI_CONFIG}" 2>/dev/null || true
    chmod 750 "${CIPI_CONFIG}" 2>/dev/null || true
    chgrp cipi-api "${CIPI_CONFIG}/apps.json" 2>/dev/null || true
    chmod 640 "${CIPI_CONFIG}/apps.json" 2>/dev/null || true
    echo "Fixed apps.json permissions (group: cipi-api)"
else
    echo "API not configured or apps.json missing — skip permissions fix"
fi

# 4. Restart PHP-FPM so www-data picks up new group membership
if systemctl is-active --quiet php8.4-fpm 2>/dev/null; then
    systemctl restart php8.4-fpm 2>/dev/null || true
    echo "Restarted php8.4-fpm (www-data group refresh)"
fi
