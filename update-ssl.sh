#!/usr/bin/env bash
# =============================================================================
# GoSecureShare — SSL Certificate Update Script
# Script version: 1.1.0
#
# Usage:  chmod +x update-ssl.sh && sudo ./update-ssl.sh
#
# What it does:
#   • Lets you replace the TLS certificate, private key, and CA/intermediate
#     bundle for the Platform service, the Recipient service, or both.
#   • Validates that the new cert and key match before replacing anything.
#   • Rebuilds fullchain.pem (cert + CA bundle).
#   • Reloads host Nginx so the new certificates take effect immediately.
#   • No Docker restart needed — Nginx serves the certs directly.
#
# Prerequisites:
#   • GoSecureShare must already be installed via install.sh.
#   • SSL mode must be 'certfiles' (host Nginx TLS terminator).
#     If you use an external reverse proxy, manage certs there instead.
#
# Environment overrides:
#   GSS_INSTALL_DIR=/opt/gosecureshare   Override the install directory.
# =============================================================================
set -euo pipefail

# Script-level version (bumped alongside INSTALLER_VERSION in 00-globals.sh)
SCRIPT_VERSION="1.1.0"

RED=$'\033[0;31m'   GREEN=$'\033[0;32m'  YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'  BOLD=$'\033[1m'      RESET=$'\033[0m'
DIM=$'\033[2m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
[[ $EUID -ne 0 ]] && error "Please run as root: sudo ./update-ssl.sh"

# ---------------------------------------------------------------------------
# Locate install directory early (needed to read installed version from .env)
# ---------------------------------------------------------------------------
INSTALL_DIR="${GSS_INSTALL_DIR:-/opt/gosecureshare}"

# ---------------------------------------------------------------------------
# Read installed version from .env (written by install.sh via 09-write-files.sh)
# ---------------------------------------------------------------------------
_INSTALLED_INSTALLER_VER="unknown"
_INSTALLED_AT="unknown"
_INSTALLED_APP_VER="unknown"
if [[ -f "${INSTALL_DIR}/.env" ]]; then
  _INSTALLED_INSTALLER_VER=$(grep -E '^GSS_INSTALLER_VERSION=' "${INSTALL_DIR}/.env" \
    | head -1 | cut -d'=' -f2 | tr -d '"' || echo "unknown")
  _INSTALLED_AT=$(grep -E '^GSS_INSTALLED_AT=' "${INSTALL_DIR}/.env" \
    | head -1 | cut -d'=' -f2- | tr -d '"' || echo "unknown")
  _INSTALLED_APP_VER=$(grep -E '^GSS_VERSION=' "${INSTALL_DIR}/.env" \
    | head -1 | cut -d'=' -f2 | tr -d '"' || echo "unknown")
fi

# ---------------------------------------------------------------------------
# Banner — shows both the script version and the installed installer version
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}╔$(printf '═%.0s' {1..60})╗${RESET}"
echo -e "${BOLD}${GREEN}║      GoSecureShare — SSL Certificate Update              ║${RESET}"
echo -e "${BOLD}${GREEN}╚$(printf '═%.0s' {1..60})╝${RESET}"
echo ""
echo -e "  ${BOLD}Script version:${RESET}      ${SCRIPT_VERSION}"
echo -e "  ${BOLD}Installed by:${RESET}        installer v${_INSTALLED_INSTALLER_VER}  (app: ${_INSTALLED_APP_VER})"
echo -e "  ${BOLD}Installed at:${RESET}        ${_INSTALLED_AT}"
echo ""

# Version mismatch warning
if [[ "${SCRIPT_VERSION}" != "${_INSTALLED_INSTALLER_VER}" && "${_INSTALLED_INSTALLER_VER}" != "unknown" ]]; then
  warn "Script version (${SCRIPT_VERSION}) differs from installer version used at install time (${_INSTALLED_INSTALLER_VER})."
  warn "This is usually fine, but if you see unexpected behaviour, re-download update-ssl.sh"
  warn "from the same release that was used to install GoSecureShare."
  echo ""
fi

# ---------------------------------------------------------------------------
# Check install dir and .env
# ---------------------------------------------------------------------------
[[ ! -d "${INSTALL_DIR}" ]] && \
  error "Install directory not found: ${INSTALL_DIR}\n        Re-run install.sh first, or set GSS_INSTALL_DIR."

[[ ! -f "${INSTALL_DIR}/.env" ]] && \
  error ".env not found in ${INSTALL_DIR}. Is GoSecureShare installed?"

SSL_CERT_DIR="${INSTALL_DIR}/ssl"

[[ ! -d "${SSL_CERT_DIR}" ]] && \
  error "SSL directory not found: ${SSL_CERT_DIR}\n        This script only applies to certfiles mode (host Nginx TLS).\n        If you use an external reverse proxy, manage certs there."

info "Install directory: ${INSTALL_DIR}"
info "SSL directory:     ${SSL_CERT_DIR}"
echo ""

# ---------------------------------------------------------------------------
# Check Nginx is running
# ---------------------------------------------------------------------------
if ! systemctl is-active --quiet nginx 2>/dev/null; then
  warn "Host Nginx does not appear to be running."
  warn "Certificates will be updated but Nginx reload will be skipped."
  _nginx_running=false
else
  _nginx_running=true
fi

# =============================================================================
# _prompt_cert_file <label> <dest_path> <mode>
# mode 1 = file path, mode 2 = paste PEM content
# =============================================================================
_prompt_cert_file() {
  local label="$1" dest="$2" mode="$3"

  case "${mode}" in
    1)
      while true; do
        read -rp "$(echo -e "    ${CYAN}Path to ${label}: ${RESET}")" _path
        _path=$(echo "${_path}" | xargs)
        if [[ -z "${_path}" ]]; then
          warn "    Path cannot be empty."
        elif [[ ! -f "${_path}" ]]; then
          warn "    File not found: ${_path}"
        elif [[ ! -r "${_path}" ]]; then
          warn "    File is not readable: ${_path}"
        elif ! grep -q 'BEGIN' "${_path}" 2>/dev/null; then
          warn "    File does not appear to be a PEM file (no -----BEGIN line found)."
        else
          cp "${_path}" "${dest}"
          success "    Copied: ${label} → ${dest}"
          return 0
        fi
      done
      ;;
    2)
      while true; do
        echo ""
        echo -e "  ${YELLOW}Paste the ${label} PEM content below.${RESET}"
        echo -e "  ${YELLOW}When finished: press ${BOLD}Enter${RESET}${YELLOW}, type ${BOLD}EOF${RESET}${YELLOW}, then press ${BOLD}Enter${RESET}${YELLOW} again.${RESET}"
        echo ""
        : > "${dest}"
        local _line _trimmed _got_content=false
        while IFS= read -r _line; do
          _trimmed=$(echo "${_line}" | xargs 2>/dev/null || echo "${_line}")
          [[ "${_trimmed}" == "EOF" ]] && break
          printf '%s\n' "${_line}" >> "${dest}"
          _got_content=true
        done
        if [[ "${_got_content}" == "false" ]] || [[ ! -s "${dest}" ]]; then
          warn "    No content received — please try again."
          rm -f "${dest}"
          continue
        fi
        if ! grep -q 'BEGIN' "${dest}" 2>/dev/null; then
          warn "    Pasted content does not look like a PEM file (no -----BEGIN line found)."
          warn "    Make sure you paste the full PEM block including the header/footer lines."
          rm -f "${dest}"
          continue
        fi
        success "    Saved: ${label} → ${dest}"
        return 0
      done
      ;;
  esac
}

# =============================================================================
# _ask_input_mode <service_label>
# Sets global _cert_input_mode to 1 (path) or 2 (paste).
# =============================================================================
_ask_input_mode() {
  local svc="$1"
  while true; do
    echo ""
    echo -e "  ${BOLD}How will you provide the ${svc} certificate files?${RESET}"
    echo -e "  ${CYAN}  1) File paths${RESET}   ${DIM}(files must exist on this server)${RESET}"
    echo -e "  ${CYAN}  2) Paste PEM content${RESET}   ${DIM}(paste each block, type EOF to finish)${RESET}"
    read -rp "$(echo -e "  ${BOLD}  Choose 1 or 2 [1]: ${RESET}")" _cert_input_mode
    _cert_input_mode=${_cert_input_mode:-1}
    [[ "${_cert_input_mode}" == "1" || "${_cert_input_mode}" == "2" ]] && return 0
    warn "    Invalid choice — enter 1 or 2."
  done
}

# =============================================================================
# _update_service_certs <service>   (platform | recipient)
# Backs up existing certs, prompts for new ones, validates, rebuilds fullchain.
# =============================================================================
_update_service_certs() {
  local svc="$1"
  local svc_label
  [[ "${svc}" == "platform" ]] && svc_label="Platform" || svc_label="Recipient"

  local cert_dir="${SSL_CERT_DIR}/${svc}"
  mkdir -p "${cert_dir}"

  # Backup existing certs if present
  if [[ -f "${cert_dir}/cert.pem" ]]; then
    local backup_dir="${cert_dir}/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "${backup_dir}"
    cp "${cert_dir}/cert.pem"      "${backup_dir}/cert.pem"      2>/dev/null || true
    cp "${cert_dir}/key.pem"       "${backup_dir}/key.pem"       2>/dev/null || true
    cp "${cert_dir}/ca-bundle.pem" "${backup_dir}/ca-bundle.pem" 2>/dev/null || true
    cp "${cert_dir}/fullchain.pem" "${backup_dir}/fullchain.pem" 2>/dev/null || true
    info "  Existing ${svc_label} certs backed up to: ${backup_dir}"
  fi

  echo ""
  echo -e "  ${BOLD}── ${svc_label} Certificate Files ─────────────────────────────────────${RESET}"
  echo -e "  ${DIM}  Three files needed: certificate, private key, CA/intermediate bundle.${RESET}"

  _ask_input_mode "${svc_label}"
  local mode=${_cert_input_mode}

  _prompt_cert_file "${svc_label} certificate (.crt / .pem)"       "${cert_dir}/cert.pem"      "${mode}"
  _prompt_cert_file "${svc_label} private key (.key / .pem)"       "${cert_dir}/key.pem"       "${mode}"
  _prompt_cert_file "${svc_label} CA / intermediate bundle (.pem)"  "${cert_dir}/ca-bundle.pem" "${mode}"

  # Validate cert + key match
  info "  Validating ${svc_label} certificate / key pair..."
  local cert_md5 key_md5
  cert_md5=$(openssl x509 -noout -modulus -in "${cert_dir}/cert.pem" 2>/dev/null | md5sum)
  key_md5=$(openssl rsa  -noout -modulus -in "${cert_dir}/key.pem"  2>/dev/null | md5sum)
  if [[ "${cert_md5}" != "${key_md5}" ]]; then
    warn "  ${svc_label} certificate and key do NOT match!"
    warn "  Restoring backup..."
    if [[ -d "${backup_dir:-}" ]]; then
      cp "${backup_dir}/cert.pem"      "${cert_dir}/cert.pem"      2>/dev/null || true
      cp "${backup_dir}/key.pem"       "${cert_dir}/key.pem"       2>/dev/null || true
      cp "${backup_dir}/ca-bundle.pem" "${cert_dir}/ca-bundle.pem" 2>/dev/null || true
      cp "${backup_dir}/fullchain.pem" "${cert_dir}/fullchain.pem" 2>/dev/null || true
      warn "  Original certificates restored. No changes applied."
    fi
    error "Aborting ${svc_label} cert update due to mismatch."
  fi
  success "  ${svc_label} cert/key pair validated."

  # Rebuild fullchain
  cat "${cert_dir}/cert.pem" \
      "${cert_dir}/ca-bundle.pem" \
      > "${cert_dir}/fullchain.pem"
  chmod 600 "${cert_dir}/key.pem"
  success "  ${svc_label} fullchain.pem rebuilt."
  success "  ${svc_label} certificates updated."
}

# =============================================================================
# MAIN — which service(s) to update?
# =============================================================================
echo -e "${BOLD}── Select Service ─────────────────────────────────────────────${RESET}"
echo ""
echo -e "  ${CYAN}  1) Platform only${RESET}   ${DIM}(internal admin UI)${RESET}"
echo -e "  ${CYAN}  2) Recipient only${RESET}  ${DIM}(external share UI)${RESET}"
echo -e "  ${CYAN}  3) Both${RESET}            ${DIM}(Platform then Recipient)${RESET}"
echo ""
while true; do
  read -rp "$(echo -e "  ${BOLD}Choose 1, 2, or 3 [3]: ${RESET}")" _svc_choice
  _svc_choice=${_svc_choice:-3}
  [[ "${_svc_choice}" =~ ^[123]$ ]] && break
  warn "  Invalid choice — enter 1, 2, or 3."
done

# =============================================================================
# Wildcard / SAN shortcut when updating both
# =============================================================================
_reuse_for_recipient=false
if [[ "${_svc_choice}" == "3" ]]; then
  echo ""
  read -rp "$(echo -e "  ${BOLD}Use the same certificate files for both services? (wildcard / SAN cert) (yes/no) [yes]: ${RESET}")" _reuse_both
  _reuse_both=${_reuse_both:-yes}
  [[ "${_reuse_both}" == "yes" ]] && _reuse_for_recipient=true
fi

# =============================================================================
# Run updates
# =============================================================================
case "${_svc_choice}" in
  1)
    _update_service_certs "platform"
    ;;
  2)
    _update_service_certs "recipient"
    ;;
  3)
    _update_service_certs "platform"
    if [[ "${_reuse_for_recipient}" == "true" ]]; then
      echo ""
      info "Copying Platform certificates to Recipient..."
      local_cert_dir_p="${SSL_CERT_DIR}/platform"
      local_cert_dir_r="${SSL_CERT_DIR}/recipient"
      mkdir -p "${local_cert_dir_r}"
      # Backup recipient first
      if [[ -f "${local_cert_dir_r}/cert.pem" ]]; then
        local _rbak="${local_cert_dir_r}/backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "${_rbak}"
        cp "${local_cert_dir_r}/cert.pem"      "${_rbak}/" 2>/dev/null || true
        cp "${local_cert_dir_r}/key.pem"       "${_rbak}/" 2>/dev/null || true
        cp "${local_cert_dir_r}/ca-bundle.pem" "${_rbak}/" 2>/dev/null || true
        cp "${local_cert_dir_r}/fullchain.pem" "${_rbak}/" 2>/dev/null || true
        info "  Existing Recipient certs backed up to: ${_rbak}"
      fi
      cp "${local_cert_dir_p}/cert.pem"      "${local_cert_dir_r}/cert.pem"
      cp "${local_cert_dir_p}/key.pem"       "${local_cert_dir_r}/key.pem"
      cp "${local_cert_dir_p}/ca-bundle.pem" "${local_cert_dir_r}/ca-bundle.pem"
      cp "${local_cert_dir_p}/fullchain.pem" "${local_cert_dir_r}/fullchain.pem"
      chmod 600 "${local_cert_dir_r}/key.pem"
      success "  Recipient certificates updated (copied from Platform)."
    else
      _update_service_certs "recipient"
    fi
    ;;
esac

# =============================================================================
# Reload Nginx
# =============================================================================
echo ""
if [[ "${_nginx_running}" == "true" ]]; then
  info "Testing Nginx configuration..."
  nginx -t || error "Nginx config test failed. Check /etc/nginx/sites-available/gss-{platform,recipient}."
  info "Reloading Nginx..."
  systemctl reload nginx
  success "Nginx reloaded. New certificates are now active."
else
  warn "Nginx is not running — skipping reload."
  warn "Start Nginx manually: systemctl start nginx"
fi

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}╔$(printf '═%.0s' {1..60})╗${RESET}"
echo -e "${BOLD}${GREEN}║  ✓  SSL certificate update complete!                       ║${RESET}"
echo -e "${BOLD}${GREEN}╚$(printf '═%.0s' {1..60})╝${RESET}"
echo ""

case "${_svc_choice}" in
  1) echo -e "  ${CYAN}Updated:${RESET}  Platform certificates" ;;
  2) echo -e "  ${CYAN}Updated:${RESET}  Recipient certificates" ;;
  3) echo -e "  ${CYAN}Updated:${RESET}  Platform and Recipient certificates" ;;
esac

echo ""
echo -e "  ${DIM}Certificate locations:${RESET}"
if [[ "${_svc_choice}" == "1" || "${_svc_choice}" == "3" ]]; then
  echo -e "  ${DIM}    ${SSL_CERT_DIR}/platform/{cert.pem, key.pem, ca-bundle.pem, fullchain.pem}${RESET}"
fi
if [[ "${_svc_choice}" == "2" || "${_svc_choice}" == "3" ]]; then
  echo -e "  ${DIM}    ${SSL_CERT_DIR}/recipient/{cert.pem, key.pem, ca-bundle.pem, fullchain.pem}${RESET}"
fi
echo ""
echo -e "  ${DIM}Nginx vhosts:${RESET}"
echo -e "  ${DIM}    /etc/nginx/sites-available/gss-platform${RESET}"
echo -e "  ${DIM}    /etc/nginx/sites-available/gss-recipient${RESET}"
echo ""
echo -e "  ${DIM}To verify the active certificate:${RESET}"
echo -e "  ${CYAN}    openssl x509 -noout -dates -subject -in ${SSL_CERT_DIR}/platform/cert.pem${RESET}"
echo -e "  ${CYAN}    openssl x509 -noout -dates -subject -in ${SSL_CERT_DIR}/recipient/cert.pem${RESET}"
echo ""
