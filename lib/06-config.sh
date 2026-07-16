#!/usr/bin/env bash
# =============================================================================
# 06-config.sh — Prompt for ports and admin credentials
#
# Port usage depends on the SSL mode chosen in 07-ssl.sh:
#   • No SSL (HTTP only)     → ports used as-is, bound on 0.0.0.0
#   • SSL mode 1 (own proxy) → ports bound on 127.0.0.1, proxy forwards here
#   • SSL mode 2 (cert files)→ these ports are IGNORED; Docker nginx binds
#                               to internal ports 8181 (platform) and 8282
#                               (recipient) automatically. Host Nginx proxies
#                               443 → those internal ports.
#
# Platform default: 8181  |  Recipient default: 80
# Sourced by install.sh — do not execute directly.
# =============================================================================

echo ""
echo -e "${BOLD}── Configuration ───────────────────────────────────────────────${RESET}"
echo ""
echo -e "  ${DIM}Platform  = internal admin UI  (default port 8181)${RESET}"
echo -e "  ${DIM}Recipient = external share UI   (default port 80)${RESET}"
echo ""
echo -e "  ${YELLOW}Note: if you choose SSL mode 2 (provide certificate files) in the next${RESET}"
echo -e "  ${YELLOW}step, these ports are not used externally — Docker will bind to internal${RESET}"
echo -e "  ${YELLOW}ports 8181 / 8282 automatically and host Nginx will proxy to them.${RESET}"
echo ""

while true; do
  read -rp "$(echo -e "  ${CYAN}Platform  HTTP port [8181]: ${RESET}")" PLATFORM_HTTP_PORT
  PLATFORM_HTTP_PORT=${PLATFORM_HTTP_PORT:-8181}
  [[ "${PLATFORM_HTTP_PORT}" =~ ^[0-9]+$ ]] && (( PLATFORM_HTTP_PORT >= 1 && PLATFORM_HTTP_PORT <= 65535 )) && break
  warn "Invalid port. Must be 1–65535."
done

while true; do
  read -rp "$(echo -e "  ${CYAN}Recipient HTTP port [80]:   ${RESET}")" RECIPIENT_HTTP_PORT
  RECIPIENT_HTTP_PORT=${RECIPIENT_HTTP_PORT:-80}
  [[ "${RECIPIENT_HTTP_PORT}" =~ ^[0-9]+$ ]] && (( RECIPIENT_HTTP_PORT >= 1 && RECIPIENT_HTTP_PORT <= 65535 )) && break
  warn "Invalid port. Must be 1–65535."
done

(( PLATFORM_HTTP_PORT == RECIPIENT_HTTP_PORT )) && \
  error "Platform and Recipient ports must be different (both set to ${PLATFORM_HTTP_PORT})."

read -rp "$(echo -e "  ${CYAN}Admin email [admin@gosecureshare.local]: ${RESET}")" GSS_ADMIN_EMAIL
GSS_ADMIN_EMAIL=${GSS_ADMIN_EMAIL:-admin@gosecureshare.local}

while true; do
  read -rsp "$(echo -e "  ${CYAN}Admin password (min 12 chars): ${RESET}")" GSS_ADMIN_PASSWORD
  echo ""
  [[ ${#GSS_ADMIN_PASSWORD} -ge 12 ]] && break
  warn "Password too short — must be at least 12 characters."
done
