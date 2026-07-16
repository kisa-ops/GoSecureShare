#!/usr/bin/env bash
# =============================================================================
# 00-globals.sh — Colors, logging helpers, registry constants, image names
# Sourced by install.sh — do not execute directly.
# =============================================================================

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
