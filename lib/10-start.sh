#!/usr/bin/env bash
# =============================================================================
# 10-start.sh — Start the Docker stack and print the success banner
# Sourced by install.sh — do not execute directly.
# =============================================================================

echo ""
info "Starting GoSecureShare ${VERSION} (8 services)..."
cd "${INSTALL_DIR}"
docker compose up -d
success "GoSecureShare ${VERSION} is up."

# =============================================================================
# SUCCESS BANNER
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔$(printf '═%.0s' {1..60})╗${RESET}"
echo -e "${BOLD}${GREEN}║  ✓  Installation complete!                                 ║${RESET}"
echo -e "${BOLD}${GREEN}╚$(printf '═%.0s' {1..60})╝${RESET}"
echo ""

if [[ "${ENABLE_SSL}" == "true" ]]; then
  echo -e "  ${CYAN}Platform UI:   ${RESET}https://${PLATFORM_DOMAIN}"
  echo -e "  ${CYAN}Recipient UI:  ${RESET}https://${RECIPIENT_DOMAIN}"
  echo ""
  if [[ "${SSL_TYPE}" == "proxy" ]]; then
    echo -e "  ${YELLOW}TLS mode: external reverse proxy.${RESET}"
    echo -e "  ${YELLOW}Point your proxy to:${RESET}"
    echo -e "  ${DIM}    https://${PLATFORM_DOMAIN}  →  http://127.0.0.1:${PLATFORM_HTTP_PORT}${RESET}"
    echo -e "  ${DIM}    https://${RECIPIENT_DOMAIN}  →  http://127.0.0.1:${RECIPIENT_HTTP_PORT}${RESET}"
  elif [[ "${SSL_TYPE}" == "certfiles" ]]; then
    echo -e "  ${GREEN}TLS mode: host Nginx with your provided certificates.${RESET}"
    echo -e "  ${DIM}  Platform cert:  ${INSTALL_DIR}/ssl/platform/${RESET}"
    echo -e "  ${DIM}  Recipient cert: ${INSTALL_DIR}/ssl/recipient/${RESET}"
    echo -e "  ${DIM}  Nginx configs:  /etc/nginx/sites-available/gss-{platform,recipient}${RESET}"
    echo ""
    warn "  Certificate renewal is your responsibility."
    warn "  After renewing, copy new files to ${INSTALL_DIR}/ssl/<service>/"
    warn "  then run: systemctl reload nginx"
  fi
else
  echo -e "  ${CYAN}Platform UI:   ${RESET}http://${SERVER_IP}:${PLATFORM_HTTP_PORT}"
  echo -e "  ${CYAN}Recipient UI:  ${RESET}http://${SERVER_IP}:${RECIPIENT_HTTP_PORT}"
  echo ""
  echo -e "  ${YELLOW}⚠ Running without HTTPS.${RESET}"
  echo -e "  ${YELLOW}  Browser encryption is unavailable on plain HTTP.${RESET}"
  echo -e "  ${YELLOW}  Add a TLS reverse proxy to enable secret creation.${RESET}"
fi

echo ""
echo -e "  ${CYAN}Admin email:   ${RESET}${GSS_ADMIN_EMAIL}"
echo ""
echo -e "  ${DIM}Logs:    cd ${INSTALL_DIR} && docker compose logs -f${RESET}"
echo -e "  ${DIM}Stop:    cd ${INSTALL_DIR} && docker compose down${RESET}"
echo -e "  ${DIM}Upgrade: sudo ${INSTALL_DIR}/upgrade.sh${RESET}"
echo ""
