#!/bin/bash
#############################################
# Cipi Migration 4.7.6 — API sudoers: allow basicauth + app suspend/unsuspend
#
# The panel/API runs `sudo cipi basicauth enable|disable|status` (ability
# apps-basicauth) and `sudo cipi app suspend|unsuspend` (ability apps-suspend)
# as www-data. The cipi-api sudoers whitelist did not include these, so sudo
# asked for a password and failed without a TTY ("a terminal is required to
# read the password"). Extend the whitelist to cover them.
#############################################

set -e

echo "Migration 4.7.6 — Extend /etc/sudoers.d/cipi-api with basicauth + app suspend/unsuspend..."

cat > /etc/sudoers.d/cipi-api <<'SUDOEOF'
www-data ALL=(root) NOPASSWD: /usr/local/bin/cipi app create *, \
                               /usr/local/bin/cipi app edit *, \
                               /usr/local/bin/cipi app delete *, \
                               /usr/local/bin/cipi app suspend *, \
                               /usr/local/bin/cipi app unsuspend *, \
                               /usr/local/bin/cipi basicauth enable *, \
                               /usr/local/bin/cipi basicauth disable *, \
                               /usr/local/bin/cipi basicauth status *, \
                               /usr/local/bin/cipi deploy *, \
                               /usr/local/bin/cipi alias add *, \
                               /usr/local/bin/cipi alias remove *, \
                               /usr/local/bin/cipi ssl install *, \
                               /usr/local/bin/cipi db list, \
                               /usr/local/bin/cipi db create *, \
                               /usr/local/bin/cipi db delete *, \
                               /usr/local/bin/cipi db backup *, \
                               /usr/local/bin/cipi db restore * *, \
                               /usr/local/bin/cipi db password *, \
                               /bin/cat /etc/cipi/apps.json
SUDOEOF
chmod 440 /etc/sudoers.d/cipi-api

echo "Migration 4.7.6 complete"
