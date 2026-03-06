#!/bin/bash
#############################################
# Cipi — Vault (AES-256-CBC config encryption at rest)
#############################################

readonly VAULT_KEY="${CIPI_CONFIG}/.vault_key"
readonly VAULT_CIPHER="aes-256-cbc"

vault_init() {
    [[ -f "$VAULT_KEY" ]] && return 0
    openssl rand -base64 32 > "$VAULT_KEY"
    chmod 400 "$VAULT_KEY"
}

# Decrypt a config file and write JSON to stdout.
# Transparently handles both plaintext (legacy) and encrypted files.
vault_read() {
    local file="${CIPI_CONFIG}/$1"
    [[ ! -f "$file" ]] && { echo "{}"; return 0; }

    if jq empty "$file" 2>/dev/null; then
        cat "$file"
    else
        openssl enc -d -"${VAULT_CIPHER}" -pbkdf2 -pass "file:${VAULT_KEY}" -in "$file" 2>/dev/null \
            || { echo "vault: failed to decrypt $1" >&2; return 1; }
    fi
}

# Read JSON from stdin, encrypt, and write to a config file.
# Optional second arg overrides chmod (default 600).
vault_write() {
    local file="${CIPI_CONFIG}/$1"
    local perms="${2:-600}"
    local tmp; tmp=$(mktemp)
    openssl enc -"${VAULT_CIPHER}" -salt -pbkdf2 -pass "file:${VAULT_KEY}" -out "$tmp"
    mv "$tmp" "$file"
    chmod "$perms" "$file"
}

# Encrypt an existing plaintext config file in-place.
# No-op if the file is already encrypted or missing.
vault_seal() {
    local file="${CIPI_CONFIG}/$1"
    [[ ! -f "$file" ]] && return 0
    jq empty "$file" 2>/dev/null || return 0

    local tmp; tmp=$(mktemp)
    openssl enc -"${VAULT_CIPHER}" -salt -pbkdf2 -pass "file:${VAULT_KEY}" -in "$file" -out "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file"
}
