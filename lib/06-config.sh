#!/usr/bin/env bash
# =============================================================================
# 06-config.sh — Prompt for ports and admin credentials
# Platform default: 8181 (internal)  |  Recipient default: 80 (external)
# Sourced by install.sh — do not execute directly.
# =============================================================================

echo ""
echo -e "${BOLD}── Configuration ──────────────────────────────────────────────${RESET}"
echo ""
echo -e "  ${DIM}Platform  = internal admin UI  (default port 8181)${RESET}"
echo -e "  ${DIM}Recipient = external share UI   (default port 80)${RESET}"
echo ""

while true; do
  read -rp "${CYAN}Platform  HTTP port [8181]: ${RESET}" PLATFORM_HTTP_PORT
  PLATFORM_HTTP_PORT=${PLATFORM_HTTP_PORT:-8181}
  [[ "${PLATFORM_HTTP_PORT}" =~ ^[0-9]+$ ]] && (( PLATFORM_HTTP_PORT >= 1 && PLATFORM_HTTP_PORT <= 65535 )) && break
  warn "Invalid port. Must be 1–65535."
done

while true; do
  read -rp "${CYAN}Recipient HTTP port [80]:   ${RESET}" RECIPIENT_HTTP_PORT
  RECIPIENT_HTTP_PORT=${RECIPIENT_HTTP_PORT:-80}
  [[ "${RECIPIENT_HTTP_PORT}" =~ ^[0-9]+$ ]] && (( RECIPIENT_HTTP_PORT >= 1 && RECIPIENT_HTTP_PORT <= 65535 )) && break
  warn "Invalid port. Must be 1–65535."
done

(( PLATFORM_HTTP_PORT == RECIPIENT_HTTP_PORT )) && \
  error "Platform and Recipient ports must be different (both set to ${PLATFORM_HTTP_PORT})."

read -rp "${CYAN}Admin email [admin@gosecureshare.local]: ${RESET}" GSS_ADMIN_EMAIL
GSS_ADMIN_EMAIL=${GSS_ADMIN_EMAIL:-admin@gosecureshare.local}

while true; do
  read -rsp "${CYAN}Admin password (min 12 chars): ${RESET}" GSS_ADMIN_PASSWORD
  echo ""
  [[ ${#GSS_ADMIN_PASSWORD} -ge 12 ]] && break
  warn "Password too short — must be at least 12 characters."
done
