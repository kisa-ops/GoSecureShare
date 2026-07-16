#!/usr/bin/env bash
# =============================================================================
# 01-reinstall.sh — Detect existing installation and prompt for cleanup
# Sourced by install.sh — do not execute directly.
# =============================================================================

_existing_stack_detected() {
  [[ -f "${INSTALL_DIR}/docker-compose.yml" ]] && return 0
  docker ps -a --format '{{.Names}}' 2>/dev/null \
    | grep -q '^gosecureshare-' && return 0
  return 1
}

if _existing_stack_detected; then
  echo ""
  echo -e "${BOLD}${YELLOW}╔$(printf '═%.0s' {1..60})╗${RESET}"
  echo -e "${BOLD}${YELLOW}║  ⚠  EXISTING INSTALLATION DETECTED                        ║${RESET}"
  echo -e "${BOLD}${YELLOW}╚$(printf '═%.0s' {1..60})╝${RESET}"
  echo ""
  echo -e "  ${YELLOW}A previous GoSecureShare installation was found at:${RESET}"
  echo -e "  ${DIM}${INSTALL_DIR}${RESET}"
  echo ""
  echo -e "  ${RED}${BOLD}This installer will:${RESET}"
  echo -e "  ${RED}  • Stop and remove all GoSecureShare containers${RESET}"
  echo -e "  ${RED}  • DELETE the PostgreSQL data volume (gss_pgdata)${RESET}"
  echo -e "  ${RED}  • DELETE the current .env and all generated config files${RESET}"
  echo -e "  ${RED}  • Perform a clean install with a fresh database${RESET}"
  echo ""
  echo -e "  ${YELLOW}All existing secrets, users, and audit logs will be lost.${RESET}"
  echo -e "  ${YELLOW}This cannot be undone.${RESET}"
  echo ""

  if [[ "${GSS_FORCE_REINSTALL:-false}" == "true" ]]; then
    warn "GSS_FORCE_REINSTALL=true — skipping confirmation, proceeding automatically."
    _DO_REINSTALL=true
  else
    echo -e "  ${CYAN}To back up your data before proceeding:${RESET}"
    echo -e "  ${DIM}  pg_dump -h 127.0.0.1 -p 5434 -U gss_superuser gosecureshare > backup.sql${RESET}"
    echo ""
    read -rp "$(echo -e "  ${BOLD}Type 'yes' to wipe all data and reinstall, or anything else to abort: ${RESET}")" _reinstall_confirm
    echo ""
    if [[ "${_reinstall_confirm}" == "yes" ]]; then
      _DO_REINSTALL=true
    else
      echo -e "  ${GREEN}Aborted. Your existing installation is untouched.${RESET}"
      echo -e "  ${DIM}  To upgrade instead, run: sudo ${INSTALL_DIR}/upgrade.sh${RESET}"
      echo ""
      exit 0
    fi
  fi

  if [[ "${_DO_REINSTALL:-false}" == "true" ]]; then
    echo ""
    info "── Cleanup: tearing down existing stack ────────────────────"
    if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
      cd "${INSTALL_DIR}"
      info "  Stopping containers and removing volumes..."
      docker compose down --volumes --remove-orphans 2>/dev/null || true
      success "  Containers and volumes removed."
    fi
    STRAY=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep '^gosecureshare-' || true)
    if [[ -n "${STRAY}" ]]; then
      info "  Removing stray containers..."
      echo "${STRAY}" | xargs docker rm -f 2>/dev/null || true
      success "  Stray containers removed."
    fi
    info "  Removing old config files..."
    rm -f "${INSTALL_DIR}/.env" \
          "${INSTALL_DIR}/docker-compose.yml" \
          "${INSTALL_DIR}/upgrade.sh" \
          "${INSTALL_DIR}/db/init.sql" \
          "${INSTALL_DIR}/db/docker-migrate.sh" \
          "${INSTALL_DIR}/nginx/platform.conf" \
          "${INSTALL_DIR}/nginx/recipient.conf"
    success "  Old config files removed."
    success "Cleanup complete — proceeding with fresh install."
    echo ""
  fi
else
  info "No existing installation detected — proceeding with first-time install."
fi
