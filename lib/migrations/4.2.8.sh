#!/bin/bash
#############################################
# Cipi Migration 4.2.8
# - Add cipi deploy + ssl permissions to app
#   sudoers (scoped to own app name only)
# - cipi-auth-notify: only notify on cipi→root
#   (handled by updated script via self-update)
# - Fix cipi binary permissions (755) so app
#   users can execute it (auto-sudo handles root)
#############################################

set -e

echo "Adding deploy and ssl permissions to app sudoers..."

for sf in /etc/sudoers.d/cipi-*; do
    [[ ! -f "$sf" ]] && continue
    [[ "$(basename "$sf")" == "cipi-sudo" ]] && continue
    [[ "$(basename "$sf")" == "cipi-api" ]] && continue

    app=$(grep -oP '(?<=cipi-worker restart )\S+' "$sf" | head -1)
    [[ -z "$app" ]] && continue

    if ! grep -q 'cipi deploy' "$sf"; then
        echo "${app} ALL=(root) NOPASSWD: /usr/local/bin/cipi deploy ${app}" >> "$sf"
        echo "${app} ALL=(root) NOPASSWD: /usr/local/bin/cipi deploy ${app} *" >> "$sf"
        echo "  Patched: $(basename "$sf") (added deploy for ${app})"
    fi

    if ! grep -q 'cipi ssl' "$sf"; then
        echo "${app} ALL=(root) NOPASSWD: /usr/local/bin/cipi ssl install ${app}" >> "$sf"
        echo "  Patched: $(basename "$sf") (added ssl install for ${app})"
    fi
done

echo "Fixing cipi binary permissions..."
chmod 755 /usr/local/bin/cipi

echo "Migration 4.2.8 complete"
