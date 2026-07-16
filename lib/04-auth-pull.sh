#!/usr/bin/env bash
# =============================================================================
# 04-auth-pull.sh — GHCR login and image pulling
# Sourced by install.sh — do not execute directly.
#
# GHCR_USERNAME, GHCR_TOKEN, and GHCR_IMAGES_PRIVATE=true are always set
# by install.sh before this module is sourced.
# =============================================================================

echo ""
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
SERVER_IP=${SERVER_IP:-127.0.0.1}
success "Server IP detected: ${SERVER_IP}"

echo ""
info "── GHCR Authentication ──────────────────────────────────────"

# Credentials are always collected at startup; this is a safety guard only.
if [[ -z "${GHCR_USERNAME:-}" || -z "${GHCR_TOKEN:-}" ]]; then
  error "GHCR credentials are missing. This should not happen — please re-run install.sh from the beginning."
fi

info "Logging in to GHCR as ${GHCR_USERNAME}..."
echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USERNAME}" --password-stdin \
  && success "GHCR login successful." \
  || error "GHCR login failed. Check that your token has 'read:packages' scope."

echo ""
info "── Pulling GoSecureShare images (ghcr.io/${NAMESPACE}) ──────"
echo ""
PULL_FAILED=()
for IMAGE in "${ALL_IMAGES[@]}"; do
  info "  ▶ Pulling ${IMAGE}..."
  if docker pull "${IMAGE}"; then
    success "  ✓ ${IMAGE}"
  else
    warn "  ✗ Failed to pull: ${IMAGE}"
    PULL_FAILED+=("${IMAGE}")
  fi
done
echo ""
if [[ ${#PULL_FAILED[@]} -gt 0 ]]; then
  echo -e "${RED}[ERROR]${RESET} Failed to pull the following images:"
  printf '         - %s\n' "${PULL_FAILED[@]}"
  echo ""
  echo -e "  ${YELLOW}Possible causes:${RESET}"
  echo -e "  1. Token lacks 'read:packages' scope — generate a new PAT and re-run."
  echo -e "  2. Wrong image name — verify at: https://github.com/orgs/kisa-ops/packages"
  echo -e "  3. No internet access to ghcr.io on this host."
  exit 1
fi
success "All images pulled successfully (tag: ${VERSION})."
echo ""
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "(gosecureshare|postgres|nginx)" || true
