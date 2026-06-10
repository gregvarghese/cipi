#!/bin/bash
# Emergency one-shot when /opt/cipi/lib/common.sh breaks cipi or migrations:
#   - CIPI_CONFIG: readonly variable  (pre-4.4.9)
#   - CIPI_LIB unset when common.sh is sourced outside the main binary (pre-4.6.4)
#
# Run as root on the server, then: cipi self-update
#
#   curl -fsSL https://raw.githubusercontent.com/cipi-sh/cipi/latest/lib/fix-common-readonly.sh | sudo bash
#
# On 4.6.4+ this is built into common.sh; keep this script for servers that cannot
# self-update yet.

set -euo pipefail

COMMON="${1:-/opt/cipi/lib/common.sh}"

[[ -f "$COMMON" ]] || { echo "Missing: $COMMON" >&2; exit 1; }

cp -a "$COMMON" "${COMMON}.bak.$(date +%s)"

START=$(grep -nF 'source "${CIPI_LIB}/vault.sh"' "$COMMON" | head -1 | cut -d: -f1) || {
    echo "Could not find: source \"\${CIPI_LIB}/vault.sh\" in $COMMON" >&2
    exit 1
}

{
    head -n 5 "$COMMON"
    cat <<'HDR'
# When sourced outside the main cipi binary (e.g. migrations), CIPI_* may be unset.
# The main cipi script sets them readonly — only assign when unset (never touch readonly).
if [[ -z "${CIPI_LIB:-}" ]]; then
    CIPI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -z "${CIPI_CONFIG:-}" ]]; then
    CIPI_CONFIG="/etc/cipi"
fi
if [[ -z "${CIPI_LOG:-}" ]]; then
    CIPI_LOG="/var/log/cipi"
fi

source "${CIPI_LIB}/vault.sh"
HDR
    tail -n +$((START + 1)) "$COMMON"
} > "${COMMON}.new"

mv "${COMMON}.new" "$COMMON"
chmod 700 "$COMMON"

echo "OK — backup: ${COMMON}.bak.*"
echo "Run: cipi self-update"
