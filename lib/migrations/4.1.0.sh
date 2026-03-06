#!/bin/bash
#############################################
# Cipi Migration 4.1.0
# - Vault: AES-256-CBC config encryption at rest
# - SMTP cron notification wrapper
# - GDPR-compliant log rotation
#############################################

set -e

CIPI_CONFIG="${CIPI_CONFIG:-/etc/cipi}"
CIPI_LIB="${CIPI_LIB:-/opt/cipi/lib}"

# ── 1. Vault: encrypt existing config files at rest ──────────

echo "Setting up vault encryption..."

if [[ -f "${CIPI_LIB}/vault.sh" ]]; then
    source "${CIPI_LIB}/vault.sh"
    vault_init

    for f in server.json apps.json databases.json backup.json smtp.json api.json; do
        if [[ -f "${CIPI_CONFIG}/$f" ]]; then
            vault_seal "$f" && echo "  Sealed: $f" || echo "  Already encrypted or skipped: $f"
        fi
    done
    echo "Vault encryption configured"
else
    echo "vault.sh not found — skipping vault setup"
fi

# ── 2. SMTP cron wrapper ─────────────────────────────────────

if crontab -l 2>/dev/null | grep -q "CIPI CRON"; then
    if ! crontab -l 2>/dev/null | grep -q "cipi-cron-notify"; then
        echo "Updating root crontab with notification wrapper..."
        crontab -l 2>/dev/null | sed \
            -e 's|/usr/local/bin/cipi self-update|/usr/local/bin/cipi-cron-notify self-update /usr/local/bin/cipi self-update|' \
            -e 's|certbot renew|/usr/local/bin/cipi-cron-notify ssl-renew certbot renew|' \
        | crontab -
        echo "Root crontab updated"
    else
        echo "Root crontab already uses cipi-cron-notify — skip"
    fi
else
    echo "No Cipi cron jobs found — skip"
fi

# ── 3. GDPR log rotation ─────────────────────────────────────

echo "Setting up GDPR-compliant log rotation..."

# Application logs (Laravel, PHP-FPM, workers, deploy) — 12 months
cat > /etc/logrotate.d/cipi-app-logs <<'EOF'
/home/*/shared/storage/logs/*.log
/home/*/logs/php-fpm-*.log
/home/*/logs/worker-*.log
/home/*/logs/deploy.log
/var/log/cipi/*.log
/var/log/cipi-queue.log {
    daily
    missingok
    rotate 365
    compress
    delaycompress
    notifempty
    create 0640 root root
}
EOF

# HTTP / Navigation logs (nginx access & error) — 90 days
cat > /etc/logrotate.d/cipi-http-logs <<'EOF'
/home/*/logs/nginx-access.log
/home/*/logs/nginx-error.log
/var/log/nginx/*.log {
    daily
    missingok
    rotate 90
    compress
    delaycompress
    notifempty
    create 0640 root adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid) 2>/dev/null || true
    endscript
}
EOF

# Security logs (firewall, fail2ban, auth) — 12 months
cat > /etc/logrotate.d/cipi-security-logs <<'EOF'
/var/log/fail2ban.log {
    daily
    missingok
    rotate 365
    compress
    delaycompress
    notifempty
    create 0640 root adm
    postrotate
        fail2ban-client flushlogs >/dev/null 2>&1 || true
    endscript
}
/var/log/ufw.log {
    daily
    missingok
    rotate 365
    compress
    delaycompress
    notifempty
    create 0640 syslog adm
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate 2>/dev/null || invoke-rc.d rsyslog rotate >/dev/null 2>&1 || true
    endscript
}
/var/log/auth.log {
    daily
    missingok
    rotate 365
    compress
    delaycompress
    notifempty
    create 0640 syslog adm
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate 2>/dev/null || invoke-rc.d rsyslog rotate >/dev/null 2>&1 || true
    endscript
}
EOF

# Remove old/conflicting logrotate configs
rm -f /etc/logrotate.d/cipi-apps
rm -f /etc/logrotate.d/nginx
rm -f /etc/logrotate.d/fail2ban

echo "GDPR log rotation configured"
echo "Migration 4.1.0 complete"
