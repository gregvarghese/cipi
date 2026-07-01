#!/bin/bash
#############################################
# Cipi Migration 4.7.10 — app logs read for panel API
#
# cipi-api PHP runs with open_basedir excluding /home/*, so log files must be
# read via sudo. Adds `cipi app logs read` to sudoers (works even when
# cipi-read-app-logs is missing).
#############################################

set -e

echo "Migration 4.7.10 — Allow www-data to run cipi app logs read via sudo..."

cat > /etc/sudoers.d/cipi-api <<'SUDOEOF'
www-data ALL=(root) NOPASSWD: /usr/local/bin/cipi app create *, \
                               /usr/local/bin/cipi app edit *, \
                               /usr/local/bin/cipi app delete *, \
                               /usr/local/bin/cipi app logs read *, \
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
                               /usr/local/bin/cipi-read-app-logs *, \
                               /bin/cat /etc/cipi/apps.json
SUDOEOF
chmod 440 /etc/sudoers.d/cipi-api

echo "Migration 4.7.10 complete"
