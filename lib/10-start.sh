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
echo -e "${BOLD}${GREEN}╔$(printf '═%.0s' {1..62})╗${RESET}"
echo -e "${BOLD}${GREEN}║  ✓  GoSecureShare ${VERSION} — Installation complete!              ║${RESET}"
echo -e "${BOLD}${GREEN}╚$(printf '═%.0s' {1..62})╝${RESET}"
echo ""

# =============================================================================
# ACCESS URLs
# =============================================================================
echo -e "${BOLD}── Access URLs ───────────────────────────────────────────────────${RESET}"
echo ""

if [[ "${ENABLE_SSL}" == "true" ]]; then
  if [[ "${SSL_TYPE}" == "certfiles" ]]; then
    # Platform runs on non-standard HTTPS port; recipient on 443
    echo -e "  ${CYAN}Platform  (internal):${RESET}  https://${PLATFORM_DOMAIN}:${PLATFORM_HTTPS_PORT}"
    echo -e "  ${CYAN}Recipient (external):${RESET}  https://${RECIPIENT_DOMAIN}"
    echo ""
    echo -e "  ${DIM}TLS terminator: host Nginx${RESET}"
    echo -e "  ${DIM}Platform  → Nginx :${PLATFORM_HTTPS_PORT} → Docker :${PLATFORM_HTTP_PORT} (internal)${RESET}"
    echo -e "  ${DIM}Recipient → Nginx :443        → Docker :${RECIPIENT_HTTP_PORT} (internal)${RESET}"
  elif [[ "${SSL_TYPE}" == "proxy" ]]; then
    echo -e "  ${CYAN}Platform  (internal):${RESET}  https://${PLATFORM_DOMAIN}"
    echo -e "  ${CYAN}Recipient (external):${RESET}  https://${RECIPIENT_DOMAIN}"
    echo ""
    echo -e "  ${YELLOW}TLS mode: external reverse proxy.${RESET}"
    echo -e "  ${DIM}Point your proxy to:${RESET}"
    echo -e "  ${DIM}    https://${PLATFORM_DOMAIN}  →  http://127.0.0.1:${PLATFORM_HTTP_PORT}${RESET}"
    echo -e "  ${DIM}    https://${RECIPIENT_DOMAIN}  →  http://127.0.0.1:${RECIPIENT_HTTP_PORT}${RESET}"
    echo -e "  ${DIM}Required headers: X-Forwarded-Proto, X-Forwarded-For, Host${RESET}"
  fi
else
  echo -e "  ${CYAN}Platform  (internal):${RESET}  http://${SERVER_IP}:${PLATFORM_HTTP_PORT}"
  echo -e "  ${CYAN}Recipient (external):${RESET}  http://${SERVER_IP}:${RECIPIENT_HTTP_PORT}"
  echo ""
  echo -e "  ${YELLOW}⚠  Running without HTTPS.${RESET}"
  echo -e "  ${YELLOW}   Browser encryption (Web Crypto API) requires HTTPS.${RESET}"
  echo -e "  ${YELLOW}   Add a TLS reverse proxy or re-run install to enable SSL.${RESET}"
fi

# =============================================================================
# DOCKER CONTAINERS
# =============================================================================
echo ""
echo -e "${BOLD}── Docker Containers ────────────────────────────────────────────${RESET}"
echo ""
printf "  ${BOLD}%-38s %-14s %s${RESET}\n" "Container" "Internal Port" "Role"
printf "  ${DIM}%-38s %-14s %s${RESET}\n" "─────────────────────────────────────" "─────────────" "────────────────────────────"
printf "  %-38s %-14s %s\n" "gosecureshare-nginx-platform"  ":${PLATFORM_HTTP_PORT}"  "Nginx → Platform frontend+API"
printf "  %-38s %-14s %s\n" "gosecureshare-nginx-recipient" ":${RECIPIENT_HTTP_PORT}" "Nginx → Recipient frontend+API"
printf "  %-38s %-14s %s\n" "gosecureshare-api-platform"    ":8000"          "Platform FastAPI backend"
printf "  %-38s %-14s %s\n" "gosecureshare-api-recipient"   ":8000"          "Recipient FastAPI backend"
printf "  %-38s %-14s %s\n" "gosecureshare-ui-platform"     ":3000"          "Platform Next.js frontend"
printf "  %-38s %-14s %s\n" "gosecureshare-ui-recipient"    ":3000"          "Recipient Next.js frontend"
printf "  %-38s %-14s %s\n" "gosecureshare-postgres"        ":5432"          "PostgreSQL 16 database"
printf "  %-38s %-14s %s\n" "gosecureshare-db-migrate"      "(init)"         "DB schema bootstrap (exits)"
echo ""

# =============================================================================
# ADMINISTRATION
# =============================================================================
echo -e "${BOLD}── Administration ──────────────────────────────────────────────${RESET}"
echo ""
echo -e "  ${BOLD}Admin account:${RESET}  ${GSS_ADMIN_EMAIL}"
echo -e "  ${BOLD}Install dir:${RESET}    ${INSTALL_DIR}"
echo ""
echo -e "  ${DIM}Key files:${RESET}"
echo -e "  ${DIM}    ${INSTALL_DIR}/.env                  → secrets & config (chmod 600)${RESET}"
echo -e "  ${DIM}    ${INSTALL_DIR}/docker-compose.yml    → stack definition${RESET}"
echo -e "  ${DIM}    ${INSTALL_DIR}/db/docker-migrate.sh  → DB schema bootstrap${RESET}"
if [[ "${SSL_TYPE}" == "certfiles" ]]; then
echo -e "  ${DIM}    ${INSTALL_DIR}/ssl/platform/          → Platform TLS certificates${RESET}"
echo -e "  ${DIM}    ${INSTALL_DIR}/ssl/recipient/         → Recipient TLS certificates${RESET}"
echo -e "  ${DIM}    /etc/nginx/sites-available/gss-platform   → Host Nginx platform vhost${RESET}"
echo -e "  ${DIM}    /etc/nginx/sites-available/gss-recipient  → Host Nginx recipient vhost${RESET}"
fi
echo ""
echo -e "  ${BOLD}Common commands:${RESET}"
echo -e "  ${DIM}    # View all container logs (follow)${RESET}"
echo -e "  ${CYAN}    cd ${INSTALL_DIR} && docker compose logs -f${RESET}"
echo ""
echo -e "  ${DIM}    # View logs for a single service${RESET}"
echo -e "  ${CYAN}    docker logs gosecureshare-api-platform -f${RESET}"
echo -e "  ${CYAN}    docker logs gosecureshare-api-recipient -f${RESET}"
echo -e "  ${CYAN}    docker logs gosecureshare-nginx-platform -f${RESET}"
echo -e "  ${CYAN}    docker logs gosecureshare-nginx-recipient -f${RESET}"
echo -e "  ${CYAN}    docker logs gosecureshare-postgres -f${RESET}"
echo ""
echo -e "  ${DIM}    # Container status${RESET}"
echo -e "  ${CYAN}    cd ${INSTALL_DIR} && docker compose ps${RESET}"
echo ""
echo -e "  ${DIM}    # Stop the stack${RESET}"
echo -e "  ${CYAN}    cd ${INSTALL_DIR} && docker compose down${RESET}"
echo ""
echo -e "  ${DIM}    # Restart the stack${RESET}"
echo -e "  ${CYAN}    cd ${INSTALL_DIR} && docker compose restart${RESET}"
echo ""
echo -e "  ${DIM}    # Upgrade to a new version${RESET}"
echo -e "  ${CYAN}    sudo ${INSTALL_DIR}/upgrade.sh${RESET}"
echo ""

if [[ "${SSL_TYPE}" == "certfiles" ]]; then
  echo -e "${BOLD}── Certificate Renewal ─────────────────────────────────────────${RESET}"
  echo ""
  echo -e "  ${YELLOW}Certificate renewal is your responsibility.${RESET}"
  echo -e "  ${DIM}  1. Replace files in ${INSTALL_DIR}/ssl/{platform,recipient}/${RESET}"
  echo -e "  ${DIM}     cert.pem, key.pem, ca-bundle.pem, fullchain.pem${RESET}"
  echo -e "  ${DIM}  2. Reload Nginx:${RESET}"
  echo -e "  ${CYAN}     systemctl reload nginx${RESET}"
  echo ""
fi
