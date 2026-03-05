#!/bin/bash
#############################################
# Cipi Migration 4.0.4 — Install Redis
# For servers that had Cipi before Redis was added to the stack.
#############################################

set -e

# Add redis-server to unattended-upgrades blacklist (all servers)
if [[ -f /etc/apt/apt.conf.d/50cipi-unattended-upgrades ]] && ! grep -q '"redis-server"' /etc/apt/apt.conf.d/50cipi-unattended-upgrades; then
    sed -i '/"mariadb-common";/a\    "redis-server";' /etc/apt/apt.conf.d/50cipi-unattended-upgrades
    echo "Added redis-server to unattended-upgrades blacklist"
fi

# Skip if Redis credentials already in server.json (already configured by Cipi)
if [[ -f /etc/cipi/server.json ]] && jq -e '.redis_password' /etc/cipi/server.json &>/dev/null; then
    echo "Redis already configured — skip"
    exit 0
fi

# Skip if Redis already installed (manual install — do not overwrite)
if dpkg -l redis-server 2>/dev/null | grep -q '^ii'; then
    echo "Redis already installed manually — skip (add redis_user/redis_password to /etc/cipi/server.json if needed)"
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

echo "Installing Redis..."
apt-get update -qq
apt-get install -y -qq redis-server

# Generate password
REDIS_PASS=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32)

# Configure requirepass and bind to localhost
if grep -q "^# *requirepass" /etc/redis/redis.conf; then
    sed -i "s/^# *requirepass.*/requirepass ${REDIS_PASS}/" /etc/redis/redis.conf
elif grep -q "^requirepass" /etc/redis/redis.conf; then
    sed -i "s/^requirepass.*/requirepass ${REDIS_PASS}/" /etc/redis/redis.conf
else
    echo "requirepass ${REDIS_PASS}" >> /etc/redis/redis.conf
fi

if grep -q "^bind " /etc/redis/redis.conf; then
    sed -i "s/^bind .*/bind 127.0.0.1 -::1/" /etc/redis/redis.conf
elif ! grep -q "^bind " /etc/redis/redis.conf; then
    echo "bind 127.0.0.1 -::1" >> /etc/redis/redis.conf
fi

systemctl restart redis-server
systemctl enable redis-server

# Save Redis credentials in server.json
tmp=$(mktemp)
jq --arg u "default" --arg p "$REDIS_PASS" '. + {redis_user: $u, redis_password: $p}' /etc/cipi/server.json > "$tmp"
mv "$tmp" /etc/cipi/server.json
chmod 600 /etc/cipi/server.json

echo "Redis installed. Credentials saved in /etc/cipi/server.json (redis_user, redis_password)"
