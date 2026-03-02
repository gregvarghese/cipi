#!/bin/bash
#############################################
# Cipi — SSL (Let's Encrypt)
#############################################

ssl_command() {
    local sub="${1:-}"; shift||true
    case "$sub" in
        install) _ssl_install "$@" ;;
        renew)   _ssl_renew ;;
        status)  _ssl_status ;;
        *) error "Use: install renew status"; exit 1 ;;
    esac
}

_ssl_install() {
    local app="${1:-}"; [[ -z "$app" ]] && { error "Usage: cipi ssl install <app>"; exit 1; }
    app_exists "$app" || { error "Not found"; exit 1; }
    local d; d=$(app_get "$app" domain)
    local domains="-d ${d}"
    jq -r --arg a "$app" '.[$a].aliases[]?//empty' "${CIPI_CONFIG}/apps.json" 2>/dev/null | while read -r a; do
        [[ -n "$a" ]] && domains+=" -d ${a}"
    done
    step "Installing SSL for ${d}..."
    certbot --nginx $domains --non-interactive --agree-tos --register-unsafely-without-email --redirect 2>&1
    if [[ $? -eq 0 ]]; then
        sed -i "s|^APP_URL=http://|APP_URL=https://|" "/home/${app}/shared/.env" 2>/dev/null
        log_action "SSL INSTALLED: $app"; success "SSL installed"
    else
        error "Failed. Ensure DNS points to this server."
    fi
}

_ssl_renew() {
    step "Renewing certificates..."
    certbot renew --nginx --non-interactive 2>&1
    systemctl reload nginx 2>/dev/null
    success "Renewal complete"
}

_ssl_status() {
    echo -e "\n${BOLD}SSL Certificates${NC}"
    certbot certificates 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *"Certificate Name:"*) echo -e "\n  ${BOLD}${line##*: }${NC}" ;;
            *"Domains:"*)          echo -e "    Domains: ${CYAN}${line##*: }${NC}" ;;
            *"Expiry Date:"*)
                local exp; exp=$(echo "${line##*: }"|awk '{print $1}')
                local days; days=$(( ($(date -d "$exp" +%s) - $(date +%s)) / 86400 ))
                local c="${GREEN}"; [[ $days -lt 14 ]] && c="${RED}"; [[ $days -lt 30 && $days -ge 14 ]] && c="${YELLOW}"
                echo -e "    Expiry:  ${c}${exp} (${days}d)${NC}" ;;
        esac
    done; echo ""
}
