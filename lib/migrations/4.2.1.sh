#!/bin/bash
#############################################
# Cipi Migration 4.2.1
# - Restrict su to sudo group (blocks app users)
#############################################

set -e

echo "Restricting su to sudo group members..."

if ! grep -q '^auth\s\+required\s\+pam_wheel\.so' /etc/pam.d/su 2>/dev/null; then
    sed -i '/^#.*pam_wheel\.so/c\auth       required   pam_wheel.so group=sudo' /etc/pam.d/su \
        || echo 'auth       required   pam_wheel.so group=sudo' >> /etc/pam.d/su
fi

echo "su restricted to sudo group"
echo "Migration 4.2.1 complete"
