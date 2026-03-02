#!/bin/bash
#############################################
# Cipi — Backup (S3)
#############################################

backup_command() {
    local sub="${1:-}"; shift||true
    case "$sub" in
        configure) _bk_configure ;;
        run)       _bk_run "$@" ;;
        list)      _bk_list "$@" ;;
        *) error "Use: configure run list"; exit 1 ;;
    esac
}

_bk_configure() {
    local cf="${CIPI_CONFIG}/backup.json"
    local ck="" cs="" cb="" cr=""
    [[ -f "$cf" ]] && { ck=$(jq -r '.aws_key//"" ' "$cf"); cs=$(jq -r '.aws_secret//""' "$cf"); cb=$(jq -r '.bucket//""' "$cf"); cr=$(jq -r '.region//""' "$cf"); }
    read_input "AWS Access Key ID" "$ck" ck
    read_input "AWS Secret Access Key" "$cs" cs
    read_input "S3 Bucket" "$cb" cb
    read_input "S3 Region" "${cr:-eu-central-1}" cr
    cat > "$cf" <<EOF
{"aws_key":"${ck}","aws_secret":"${cs}","bucket":"${cb}","region":"${cr}"}
EOF
    chmod 600 "$cf"
    aws configure set aws_access_key_id "$ck"
    aws configure set aws_secret_access_key "$cs"
    aws configure set default.region "$cr"
    success "Backup configured"
}

_bk_run() {
    local target="${1:-}" cf="${CIPI_CONFIG}/backup.json"
    [[ ! -f "$cf" ]] && { error "Run: cipi backup configure"; exit 1; }
    local bucket; bucket=$(jq -r '.bucket' "$cf")
    local dbr; dbr=$(get_db_root_password)
    local ts; ts=$(date +%Y-%m-%d_%H%M%S)
    local tmp="/tmp/cipi-bk-${ts}"; mkdir -p "$tmp"

    _do_backup() {
        local app="$1"; local d="${tmp}/${app}"; mkdir -p "$d"
        step "Backup '${app}'..."
        mysqldump -u root -p"$dbr" --single-transaction "$app" 2>/dev/null | gzip >"${d}/db.sql.gz"
        tar -czf "${d}/shared.tar.gz" -C "/home/${app}" shared/ 2>/dev/null
        aws s3 cp "${d}/" "s3://${bucket}/cipi/${app}/${ts}/" --recursive --quiet 2>/dev/null
        [[ $? -eq 0 ]] && success "  → s3://${bucket}/cipi/${app}/${ts}/" || error "  Upload failed"
    }

    if [[ -n "$target" ]]; then
        app_exists "$target" || { error "Not found"; exit 1; }
        _do_backup "$target"
    else
        jq -r 'keys[]' "${CIPI_CONFIG}/apps.json" 2>/dev/null | while read -r a; do _do_backup "$a"; done
    fi
    rm -rf "$tmp"; success "Backup complete"
}

_bk_list() {
    local target="${1:-}" cf="${CIPI_CONFIG}/backup.json"
    [[ ! -f "$cf" ]] && { error "Run: cipi backup configure"; exit 1; }
    local bucket; bucket=$(jq -r '.bucket' "$cf")
    echo -e "\n${BOLD}Backups${NC}"
    if [[ -n "$target" ]]; then aws s3 ls "s3://${bucket}/cipi/${target}/" 2>/dev/null|sed 's/^/  /'
    else aws s3 ls "s3://${bucket}/cipi/" 2>/dev/null|sed 's/^/  /'; fi
    echo ""
}
