#!/bin/bash
#############################################
# Cipi Migration 4.2.2
# - Fix default nginx host to always serve index.html
# - Install PAM auth notifications (sudo & SSH)
#############################################

set -e

# ── Fix default nginx host ──────────────────────────────────

echo "Fixing default nginx host..."

cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html;
    server_name _;
    server_tokens off;

    # All requests serve the Server Up page (no 404 leaks)
    location / {
        rewrite ^ /index.html break;
    }
}
EOF

nginx -t && systemctl reload nginx
echo "Default nginx host fixed"

# ── PAM auth notifications ──────────────────────────────────

echo "Setting up PAM auth notifications..."

cp /opt/cipi/lib/cipi-auth-notify.sh /usr/local/bin/cipi-auth-notify
chmod 700 /usr/local/bin/cipi-auth-notify
chown root:root /usr/local/bin/cipi-auth-notify

if [[ -x /usr/local/bin/cipi-auth-notify ]]; then
    if ! grep -q 'cipi-auth-notify' /etc/pam.d/sudo 2>/dev/null; then
        echo 'session optional pam_exec.so seteuid /usr/local/bin/cipi-auth-notify' >> /etc/pam.d/sudo
    fi
    if ! grep -q 'cipi-auth-notify' /etc/pam.d/sshd 2>/dev/null; then
        echo 'session optional pam_exec.so seteuid /usr/local/bin/cipi-auth-notify' >> /etc/pam.d/sshd
    fi
    echo "PAM auth notifications installed"
fi

echo "Migration 4.2.2 complete"


set -e

echo "Migration 4.2.3 complete (reset commands added via lib update)"
