#!/bin/bash
#############################################
# Cipi — Firewall (UFW)
#############################################

firewall_command() {
    local sub="${1:-}"; shift||true
    case "$sub" in
        allow) local p="${1:-}"; shift||true; [[ -z "$p" ]] && { error "Usage: cipi firewall allow <port> [--from=IP]"; exit 1; }
               parse_args "$@"
               if [[ -n "${ARG_from:-}" ]]; then ufw allow from "${ARG_from}" to any port "$p" proto tcp
               else ufw allow "$p/tcp"; fi
               success "Allowed ${p}/tcp" ;;
        deny)  local p="${1:-}"; [[ -z "$p" ]] && { error "Usage: cipi firewall deny <port>"; exit 1; }
               ufw deny "$p/tcp"; success "Denied ${p}/tcp" ;;
        list)  echo ""; ufw status numbered 2>/dev/null; echo "" ;;
        *) error "Use: allow deny list"; exit 1 ;;
    esac
}
