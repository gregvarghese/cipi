#!/bin/bash
#############################################
# Cipi Migration 4.6.1 — Composer >= 2.10.1
#
# Ensures the system Composer (/usr/local/bin/composer) is on the 2.x
# channel and at least 2.10.1. Servers provisioned with older builds keep
# whatever Composer the getcomposer.org installer shipped at the time, so
# this brings them up to the current stable 2.x release.
# Idempotent — safe to re-run.
#############################################

set -e

COMPOSER_MIN="2.10.1"

echo "Migration 4.6.1 — Composer >= ${COMPOSER_MIN}..."

# Resolve the composer binary (prefer the Cipi-managed path).
composer_bin="/usr/local/bin/composer"
if [[ ! -x "$composer_bin" ]]; then
    composer_bin="$(command -v composer 2>/dev/null || true)"
fi
if [[ -z "$composer_bin" ]]; then
    echo "  Composer not installed — skipping"
    echo "Migration 4.6.1 complete"
    exit 0
fi

_composer_version() {
    "$composer_bin" --version --no-ansi 2>/dev/null \
        | sed -n 's/.*Composer version \([0-9][0-9.]*\).*/\1/p' | head -1
}

current="$(_composer_version)"
echo "  Current Composer: ${current:-unknown}"

# Already at/above the floor → nothing to do.
if [[ -n "$current" ]] \
   && [[ "$(printf '%s\n' "$COMPOSER_MIN" "$current" | sort -V | head -1)" == "$COMPOSER_MIN" ]]; then
    echo "  Composer ${current} already >= ${COMPOSER_MIN} — nothing to do"
    echo "Migration 4.6.1 complete"
    exit 0
fi

echo "  Updating Composer to the latest stable 2.x..."
if "$composer_bin" self-update --2 --no-interaction 2>/dev/null; then
    new="$(_composer_version)"
    echo "  Composer now: ${new:-unknown}"
    # Latest 2.x still below the floor (shouldn't happen) → pin explicitly.
    if [[ -n "$new" ]] \
       && [[ "$(printf '%s\n' "$COMPOSER_MIN" "$new" | sort -V | head -1)" != "$COMPOSER_MIN" ]]; then
        echo "  Still below ${COMPOSER_MIN} — pinning ${COMPOSER_MIN}..."
        "$composer_bin" self-update "$COMPOSER_MIN" --no-interaction 2>/dev/null \
            && echo "  Composer now: $(_composer_version)" \
            || echo "  WARN: could not pin Composer ${COMPOSER_MIN}"
    fi
else
    echo "  WARN: 'composer self-update --2' failed (network?) — trying pinned ${COMPOSER_MIN}..."
    if "$composer_bin" self-update "$COMPOSER_MIN" --no-interaction 2>/dev/null; then
        echo "  Composer now: $(_composer_version)"
    else
        echo "  WARN: could not update Composer — leaving ${current:-current} as-is"
    fi
fi

echo "Migration 4.6.1 complete"
