#!/usr/bin/env bash
# =============================================================================
# GoSecureShare — Automated Installation Script
# Supports: Ubuntu 20.04+, Debian 11+, Rocky/RHEL 8+
# Usage:  chmod +x install.sh && sudo ./install.sh
#
# SELF-BOOTSTRAPPING
#   This script only needs itself to start. If the lib/ directory is not
#   present alongside install.sh, all required lib files are automatically
#   fetched from GitHub before installation proceeds.
#
# PORT DEFAULTS
#   Platform  (internal admin UI):  HTTP 8181  →  HTTPS 443 (behind host Nginx)
#   Recipient (external share UI):  HTTP 80    →  HTTPS 443 (behind host Nginx)
#
# VERSION PINNING
#   By default this script auto-detects the latest stable SemVer release.
#   To install a specific version:
#     GSS_VERSION=2.3.1 sudo ./install.sh
#
# DB FILES (init.sql + docker-migrate.sh)
#   Resolution order (first match wins):
#     1. Local  — db/ folder next to install.sh
#     2. Remote — fetched from raw.githubusercontent.com / GitHub API
#   Override path: GSS_DB_DIR=/path/to/db sudo ./install.sh
#
# AUTHENTICATION
#   Prompted interactively during install (GHCR_USERNAME + GHCR_TOKEN).
#   To skip prompts (e.g. CI), pre-export before running:
#     export GHCR_USERNAME=your-github-username
#     export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
#     sudo -E ./install.sh          # -E passes env vars through sudo
#
# SSL OPTIONS (prompted during install):
#   1) Own reverse proxy (Cloudflare, Nginx, HAProxy, F5, etc.)
#      → Docker binds to 127.0.0.1. Your proxy handles TLS.
#   2) Provide certificate files
#      → Host Nginx installed as TLS terminator.
#      → Cert, key, CA bundle asked separately for Platform then Recipient.
#      → Each file can be provided as a path or by pasting the PEM content.
#
# REINSTALL / CI FLAGS
#   GSS_FORCE_REINSTALL=true   Skip reinstall confirmation.
# =============================================================================
set -euo pipefail

# Colours used in bootstrap messages (before 00-globals.sh is sourced)
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${RESET} Please run as root: sudo ./install.sh" >&2
  exit 1
fi

echo ""
echo -e "${BOLD}${GREEN}╔$(printf '═%.0s' {1..60})╗${RESET}"
echo -e "${BOLD}${GREEN}║      GoSecureShare — Automated Installer                   ║${RESET}"
echo -e "${BOLD}${GREEN}║      Self-Hosted Zero-Knowledge Secret Sharing             ║${RESET}"
echo -e "${BOLD}${GREEN}╚$(printf '═%.0s' {1..60})╝${RESET}"
echo ""

# =============================================================================
# GHCR CREDENTIALS
# Prompted here — before lib bootstrap — so the token is available for
# private-repo lib fetching AND for docker pull in 04-auth-pull.sh.
# Skipped if already exported in the environment (sudo -E ./install.sh).
# =============================================================================
echo -e "${BOLD}── GHCR Credentials ────────────────────────────────────────────${RESET}"
echo -e "  ${CYAN}GoSecureShare images are hosted on GitHub Container Registry (GHCR).${RESET}"
echo -e "  ${CYAN}A GitHub username and a Personal Access Token (PAT) with at least${RESET}"
echo -e "  ${CYAN}'read:packages' scope are required to pull the images.${RESET}"
echo ""

if [[ -z "${GHCR_USERNAME:-}" ]]; then
  while true; do
    read -rp "$(echo -e "  ${BOLD}GitHub username (GHCR_USERNAME): ${RESET}")" GHCR_USERNAME
    GHCR_USERNAME=$(echo "${GHCR_USERNAME}" | xargs)
    [[ -n "${GHCR_USERNAME}" ]] && break
    echo -e "  ${YELLOW}[WARN]${RESET}  Username cannot be empty."
  done
else
  echo -e "  ${GREEN}[OK]${RESET}    GHCR_USERNAME already set: ${GHCR_USERNAME}"
fi

if [[ -z "${GHCR_TOKEN:-}" ]]; then
  while true; do
    read -rsp "$(echo -e "  ${BOLD}GitHub PAT    (GHCR_TOKEN):    ${RESET}")" GHCR_TOKEN
    echo ""   # newline after silent input
    GHCR_TOKEN=$(echo "${GHCR_TOKEN}" | xargs)
    [[ -n "${GHCR_TOKEN}" ]] && break
    echo -e "  ${YELLOW}[WARN]${RESET}  Token cannot be empty."
  done
else
  echo -e "  ${GREEN}[OK]${RESET}    GHCR_TOKEN already set (length: ${#GHCR_TOKEN})."
fi

export GHCR_USERNAME
export GHCR_TOKEN
export GHCR_IMAGES_PRIVATE=true

echo ""
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
success "GHCR credentials captured. GHCR_IMAGES_PRIVATE=true."
echo ""

# =============================================================================
# BOOTSTRAP — fetch lib/ files from GitHub if not present alongside install.sh
# =============================================================================
LIB_FILES=(
  "00-globals.sh"
  "01-reinstall.sh"
  "02-prerequisites.sh"
  "03-version.sh"
  "04-auth-pull.sh"
  "05-db-files.sh"
  "06-config.sh"
  "07-ssl.sh"
  "08-secrets.sh"
  "09-write-files.sh"
  "10-start.sh"
)

# Ref to fetch lib files from. Defaults to 'main'.
# Override: GSS_LIB_REF=v2.3.1 sudo -E ./install.sh
LIB_REF="${GSS_LIB_REF:-main}"
LIB_BASE_URL="https://raw.githubusercontent.com/kisa-ops/GoSecureShare/${LIB_REF}/lib"

_needs_bootstrap=false
for _f in "${LIB_FILES[@]}"; do
  [[ ! -f "${LIB_DIR}/${_f}" ]] && { _needs_bootstrap=true; break; }
done

if [[ "${_needs_bootstrap}" == "true" ]]; then
  echo -e "${CYAN}[INFO]${RESET}  lib/ not found — fetching from GitHub (ref: ${LIB_REF})..."
  echo ""
  mkdir -p "${LIB_DIR}"
  _curl_auth=(-H "Authorization: Bearer ${GHCR_TOKEN}")
  _bootstrap_failed=false
  for _f in "${LIB_FILES[@]}"; do
    if curl -fsSL --connect-timeout 10 \
        "${_curl_auth[@]}" \
        "${LIB_BASE_URL}/${_f}" \
        -o "${LIB_DIR}/${_f}" 2>/dev/null; then
      echo -e "${GREEN}[OK]${RESET}    Fetched: lib/${_f}"
    else
      echo -e "${RED}[ERROR]${RESET} Failed to fetch: lib/${_f}" >&2
      _bootstrap_failed=true
    fi
  done
  echo ""
  if [[ "${_bootstrap_failed}" == "true" ]]; then
    echo -e "${RED}[ERROR]${RESET} One or more lib files could not be fetched." >&2
    echo -e "        Possible causes:" >&2
    echo -e "          1. No internet access to raw.githubusercontent.com" >&2
    echo -e "          2. Token lacks sufficient scope — ensure 'repo' or 'read:packages'" >&2
    echo -e "          3. Wrong ref — try: GSS_LIB_REF=main sudo -E ./install.sh" >&2
    echo -e "        Or download the full release package and place lib/ next to install.sh." >&2
    rm -rf "${LIB_DIR}"
    exit 1
  fi
  chmod +x "${LIB_DIR}"/*.sh
  echo -e "${GREEN}[OK]${RESET}    All lib files ready."
  echo ""
fi

# Verify lib dir is complete before sourcing
for _f in "${LIB_FILES[@]}"; do
  if [[ ! -f "${LIB_DIR}/${_f}" ]]; then
    echo -e "${RED}[ERROR]${RESET} Missing lib file: lib/${_f}" >&2
    echo -e "        Delete the lib/ directory and re-run to trigger auto-fetch." >&2
    exit 1
  fi
done

# =============================================================================
# SOURCE MODULES IN ORDER
# =============================================================================
# shellcheck source=lib/00-globals.sh
. "${LIB_DIR}/00-globals.sh"
# shellcheck source=lib/01-reinstall.sh
. "${LIB_DIR}/01-reinstall.sh"
# shellcheck source=lib/02-prerequisites.sh
. "${LIB_DIR}/02-prerequisites.sh"
# shellcheck source=lib/03-version.sh
. "${LIB_DIR}/03-version.sh"
# shellcheck source=lib/04-auth-pull.sh
. "${LIB_DIR}/04-auth-pull.sh"
# shellcheck source=lib/05-db-files.sh
. "${LIB_DIR}/05-db-files.sh"
# shellcheck source=lib/06-config.sh
. "${LIB_DIR}/06-config.sh"
# shellcheck source=lib/07-ssl.sh
. "${LIB_DIR}/07-ssl.sh"
# shellcheck source=lib/08-secrets.sh
. "${LIB_DIR}/08-secrets.sh"
# shellcheck source=lib/09-write-files.sh
. "${LIB_DIR}/09-write-files.sh"
# shellcheck source=lib/10-start.sh
. "${LIB_DIR}/10-start.sh"
