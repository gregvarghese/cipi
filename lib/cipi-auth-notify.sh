#!/bin/bash
#############################################
# Cipi — PAM auth notification
# Sends email on successful sudo elevation
# or root/sudoer SSH login.
# Called by pam_exec.so (session open).
#
# Internal operations (API, queue workers,
# cron) are silently skipped so only real
# interactive security events trigger alerts.
#############################################

[[ "${PAM_TYPE:-}" == "open_session" ]] || exit 0

readonly CIPI_CONFIG="/etc/cipi"
readonly CIPI_LIB="/opt/cipi/lib"
readonly SMTP_CFG="${CIPI_CONFIG}/smtp.json"
readonly SMTP_RC="${CIPI_CONFIG}/.msmtprc"

# Quick exit if SMTP not configured
[[ -f "$SMTP_CFG" ]] || exit 0
[[ -f "$SMTP_RC" ]] || exit 0

source "${CIPI_LIB}/vault.sh" 2>/dev/null || exit 0

_SJ=$(vault_read smtp.json 2>/dev/null) || exit 0
[[ "$(echo "$_SJ" | jq -r '.enabled // false')" == "true" ]] || exit 0

TO=$(echo "$_SJ" | jq -r '.to // empty')
FROM=$(echo "$_SJ" | jq -r '.from // "noreply@localhost"')
[[ -z "$TO" ]] && exit 0

HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SERVICE="${PAM_SERVICE:-unknown}"
USER="${PAM_USER:-unknown}"
RHOST="${PAM_RHOST:-local}"
TTY="${PAM_TTY:-unknown}"

# Resolve SSH key name from the key used for the current session.
# Requires ExposeAuthInfo=yes in sshd_config and SSH_USER_AUTH preserved via sudoers.
_resolve_ssh_key_name() {
    local auth_file="${SSH_USER_AUTH:-}"
    [[ -z "$auth_file" || ! -f "$auth_file" ]] && return

    local fp
    fp=$(awk '/^publickey / {print $3; exit}' "$auth_file" 2>/dev/null)
    [[ -z "$fp" ]] && return

    local ak="/home/cipi/.ssh/authorized_keys"
    [[ -f "$ak" ]] || return

    while IFS= read -r line; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local line_fp
        line_fp=$(echo "$line" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
        if [[ "$line_fp" == "$fp" ]]; then
            local comment
            comment=$(echo "$line" | awk '{$1=$2=""; print}' | xargs)
            [[ -n "$comment" ]] && echo "$comment" || echo "$fp"
            return
        fi
    done < "$ak"
    echo "$fp"
}

SSH_KEY_NAME=$(_resolve_ssh_key_name)
[[ -z "$SSH_KEY_NAME" ]] && SSH_KEY_NAME="unknown"

# Detect operations triggered by system services rather than interactive users.
# loginuid 4294967295 = no login session (PHP-FPM, queue workers, cron, systemd).
# Falls back to process-tree inspection for systems without audit enabled.
_is_internal() {
    local luid
    luid=$(cat /proc/self/loginuid 2>/dev/null) || luid=""
    [[ "$luid" == "4294967295" ]] && return 0

    local pid=$$ i=0
    while [[ $pid -gt 1 && $i -lt 20 ]]; do
        local cmd
        cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "")
        case "$cmd" in
            *php-fpm*|*php*artisan*queue*|*supervisord*|*cipi-queue*) return 0 ;;
        esac
        pid=$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null || echo 0)
        i=$((i + 1))
    done
    return 1
}

# Resolve the real user who ran sudo (SUDO_USER is often empty inside PAM).
_resolve_sudo_user() {
    [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "unknown" ]] && { echo "$SUDO_USER"; return; }
    local luid
    luid=$(cat /proc/self/loginuid 2>/dev/null) || luid=""
    if [[ -n "$luid" && "$luid" != "4294967295" ]]; then
        local name
        name=$(getent passwd "$luid" 2>/dev/null | cut -d: -f1)
        [[ -n "$name" ]] && { echo "$name"; return; }
    fi
    echo "unknown"
}

case "$SERVICE" in
    sudo)
        _is_internal && exit 0
        SUDO_BY=$(_resolve_sudo_user)
        SUBJECT="Cipi security: sudo by ${SUDO_BY} (${HOSTNAME})"
        BODY="Sudo elevation detected on ${HOSTNAME}

User:      ${SUDO_BY}
Target:    ${USER}
SSH Key:   ${SSH_KEY_NAME}
TTY:       ${TTY}
Time:      ${TIMESTAMP}"
        ;;
    sshd)
        # Only notify for root or sudoers
        if [[ "$USER" != "root" ]]; then
            id -nG "$USER" 2>/dev/null | grep -qw sudo || exit 0
        fi
        SUBJECT="Cipi security: SSH login ${USER}@${HOSTNAME}"
        BODY="SSH login detected on ${HOSTNAME}

User:      ${USER}
From:      ${RHOST}
SSH Key:   ${SSH_KEY_NAME}
TTY:       ${TTY}
Time:      ${TIMESTAMP}"
        ;;
    *)
        exit 0
        ;;
esac

printf "From: %s\nTo: %s\nSubject: %s\n\n%s\n" "$FROM" "$TO" "$SUBJECT" "$BODY" | \
    msmtp -C "$SMTP_RC" "$TO" 2>/dev/null &

exit 0
