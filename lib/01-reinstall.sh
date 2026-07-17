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
  echo -e "${BOLD}${YELLOW}╔$(printf '═%.0s' {1..62})╗${RESET}"
  echo -e "${BOLD}${YELLOW}║  ⚠  EXISTING INSTALLATION DETECTED                          ║${RESET}"
  echo -e "${BOLD}${YELLOW}╚$(printf '═%.0s' {1..62})╝${RESET}"
  echo ""

  # ---- Show what was detected ------------------------------------------------
  echo -e "  ${BOLD}Detected installation:${RESET}"
  echo -e "  ${DIM}  Directory:  ${INSTALL_DIR}${RESET}"

  # Version from .env
  if [[ -f "${INSTALL_DIR}/.env" ]]; then
    _det_ver=$(grep -E '^GSS_VERSION=' "${INSTALL_DIR}/.env" 2>/dev/null \
                 | cut -d= -f2 | tr -d '"' || echo "unknown")
    echo -e "  ${DIM}  Version:    ${_det_ver}${RESET}"
    _det_created=$(stat -c '%y' "${INSTALL_DIR}/.env" 2>/dev/null \
                   | cut -d' ' -f1 || echo "unknown")
    echo -e "  ${DIM}  Installed:  ${_det_created}${RESET}"
  fi

  # Running containers
  _running_containers=$(docker ps --format '{{.Names}}' 2>/dev/null \
                        | grep '^gosecureshare-' || true)
  if [[ -n "${_running_containers}" ]]; then
    echo -e "  ${DIM}  Running containers:${RESET}"
    while IFS= read -r _c; do
      echo -e "  ${DIM}    • ${_c}${RESET}"
    done <<< "${_running_containers}"
  else
    echo -e "  ${DIM}  Running containers: none (stack is down)${RESET}"
  fi

  # SSL certs
  if [[ -d "${INSTALL_DIR}/ssl" ]]; then
    echo -e "  ${DIM}  SSL certs:  ${INSTALL_DIR}/ssl/ (platform + recipient)${RESET}"
  fi

  echo ""

  # ---- Safer alternatives ----------------------------------------------------
  echo -e "  ${BOLD}Are you sure you need a fresh install?${RESET}"
  echo -e "  ${CYAN}  For most cases, a safer alternative exists:${RESET}"
  echo ""
  echo -e "  ${GREEN}  • Upgrade to a new version:${RESET}"
  echo -e "  ${DIM}      sudo ${INSTALL_DIR}/upgrade.sh${RESET}"
  echo ""
  echo -e "  ${GREEN}  • Renew / replace TLS certificates only:${RESET}"
  SCRIPT_DIR_REF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
  echo -e "  ${DIM}      sudo ${SCRIPT_DIR_REF}/update-ssl.sh${RESET}"
  echo ""
  echo -e "  ${YELLOW}  Only continue below if you intentionally want to wipe${RESET}"
  echo -e "  ${YELLOW}  everything and start from scratch.${RESET}"
  echo ""

  # ---- Destruction warning ---------------------------------------------------
  echo -e "  ${RED}${BOLD}A fresh install will permanently:${RESET}"
  echo -e "  ${RED}  • Stop and remove ALL GoSecureShare containers${RESET}"
  echo -e "  ${RED}  • DELETE the PostgreSQL data volume (gss_pgdata) — all secrets, users, logs${RESET}"
  echo -e "  ${RED}  • DELETE .env and all generated config files${RESET}"
  if [[ -d "${INSTALL_DIR}/ssl" ]]; then
  echo -e "  ${RED}  • DELETE existing TLS certificates in ${INSTALL_DIR}/ssl/${RESET}"
  fi
  echo -e "  ${RED}  • Perform a clean install with a brand-new empty database${RESET}"
  echo ""
  echo -e "  ${YELLOW}  This CANNOT be undone.${RESET}"
  echo ""

  if [[ "${GSS_FORCE_REINSTALL:-false}" == "true" ]]; then
    warn "GSS_FORCE_REINSTALL=true — skipping confirmation, proceeding automatically."
    _DO_REINSTALL=true
  else
    # Back up hint
    echo -e "  ${CYAN}  Back up your data first (optional):${RESET}"
    echo -e "  ${DIM}    pg_dump -h 127.0.0.1 -p 5434 -U gss_superuser gosecureshare > backup.sql${RESET}"
    echo ""
    echo -e "  ${BOLD}  To confirm, type ${RED}REINSTALL${RESET}${BOLD} (uppercase) and press Enter.${RESET}"
    echo -e "  ${DIM}  Anything else will safely abort.${RESET}"
    echo ""
    read -rp "$(echo -e "  ${BOLD}  Confirmation: ${RESET}")" _reinstall_confirm
    echo ""
    if [[ "${_reinstall_confirm}" == "REINSTALL" ]]; then
      _DO_REINSTALL=true
    else
      echo -e "  ${GREEN}Aborted. Your existing installation is untouched.${RESET}"
      echo ""
      echo -e "  ${DIM}  • To upgrade:      sudo ${INSTALL_DIR}/upgrade.sh${RESET}"
      echo -e "  ${DIM}  • To update certs:  sudo ${SCRIPT_DIR_REF}/update-ssl.sh${RESET}"
      echo ""
      exit 0
    fi
  fi

  if [[ "${_DO_REINSTALL:-false}" == "true" ]]; then
    echo ""
    info "── Cleanup: tearing down existing stack ─────────────────────"
    if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
      cd "${INSTALL_DIR}"
      info "  Stopping containers and removing volumes..."
      docker compose down --volumes --remove-orphans 2>/dev/null || true
      success "  Containers and volumes removed."
    fi
    _STRAY=$(docker ps -a --format '{{.Names}}' 2>/dev/null \
             | grep '^gosecureshare-' || true)
    if [[ -n "${_STRAY}" ]]; then
      info "  Removing stray containers..."
      echo "${_STRAY}" | xargs docker rm -f 2>/dev/null || true
      success "  Stray containers removed."
    fi
    info "  Removing old config and SSL files..."
    rm -f  "${INSTALL_DIR}/.env" \
           "${INSTALL_DIR}/docker-compose.yml" \
           "${INSTALL_DIR}/upgrade.sh" \
           "${INSTALL_DIR}/db/init.sql" \
           "${INSTALL_DIR}/db/docker-migrate.sh" \
           "${INSTALL_DIR}/nginx/platform.conf" \
           "${INSTALL_DIR}/nginx/recipient.conf"
    rm -rf "${INSTALL_DIR}/ssl"
    success "  Old config and SSL files removed."
    success "Cleanup complete — proceeding with fresh install."
    echo ""
  fi
else
  info "No existing installation detected — proceeding with first-time install."
fi
