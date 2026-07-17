#!/usr/bin/env bash
# =============================================================================
# 00-globals.sh — Colors, logging helpers, registry constants, image names
# Sourced by install.sh — do not execute directly.
# =============================================================================

# ---------------------------------------------------------------------------
# INSTALLER VERSION — bump this on every release of the installer script suite.
# Format: SemVer MAJOR.MINOR.PATCH
#   MAJOR — breaking changes to install flow or .env structure
#   MINOR — new features (new SSL modes, new prompts, new generated scripts)
#   PATCH — bug fixes (logic corrections, heredoc fixes)
#
# This value is:
#   • Shown in the install.sh banner so the operator knows what they ran
#   • Written into /opt/gosecureshare/.env as GSS_INSTALLER_VERSION
#   • Written into /opt/gosecureshare/.env as GSS_INSTALLED_AT (timestamp)
#   • Embedded into upgrade.sh and update-ssl.sh so each server tracks
#     which installer version deployed it
#   • Compared by upgrade.sh against the latest released installer to
#     warn when the installer scripts on disk are outdated
# ---------------------------------------------------------------------------
INSTALLER_VERSION="1.1.0"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

REGISTRY="ghcr.io"
NAMESPACE="kisa-ops"
GITHUB_REPO="kisa-ops/GoSecureShare"

IMAGE_API_PLATFORM="${REGISTRY}/${NAMESPACE}/gosecureshare-api-platform"
IMAGE_API_RECIPIENT="${REGISTRY}/${NAMESPACE}/gosecureshare-api-recipient"
IMAGE_FRONTEND_PLATFORM="${REGISTRY}/${NAMESPACE}/gosecureshare-frontend-platform"
IMAGE_FRONTEND_RECIPIENT="${REGISTRY}/${NAMESPACE}/gosecureshare-frontend-recipient"

INSTALL_DIR="/opt/gosecureshare"
