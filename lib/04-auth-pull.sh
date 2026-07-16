#!/usr/bin/env bash
# =============================================================================
# 04-auth-pull.sh — GHCR login and image pulling
# Sourced by install.sh — do not execute directly.
# =============================================================================

echo ""
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
SERVER_IP=${SERVER_IP:-127.0.0.1}
success "Server IP detected: ${SERVER_IP}"

echo ""
info "── GHCR Authentication ──────────────────────────────────────"

if [[ "${GHCR_IMAGES_PRIVATE:-false}" == "true" ]]; then
  if [[ -z "${GHCR_USERNAME:-}" || -z "${GHCR_TOKEN:-}" ]]; then
    echo ""
    echo -e "${RED}[ERROR]${RESET} GHCR_IMAGES_PRIVATE=true but credentials are missing." >&2
    echo -e "        Re-run with your GitHub PAT (scope: read:packages):" >&2
    echo "" >&2
    echo -e "  ${CYAN}export GHCR_USERNAME=your-github-username${RESET}" >&2
    echo -e "  ${CYAN}export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx${RESET}" >&2
    echo -e "  ${CYAN}sudo -E ./install.sh${RESET}   # -E passes env vars through sudo" >&2
    echo "" >&2
    exit 1
  fi
fi

if [[ -n "${GHCR_USERNAME:-}" && -n "${GHCR_TOKEN:-}" ]]; then
  info "Logging in to GHCR as ${GHCR_USERNAME}..."
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USERNAME}" --password-stdin \
    && success "GHCR login successful." \
    || error "GHCR login failed. Check GHCR_USERNAME and GHCR_TOKEN."
else
  info "No GHCR credentials supplied — attempting public pull."
  warn "If images are private, abort now (Ctrl+C) and re-run with:"
  echo -e "  ${CYAN}export GHCR_USERNAME=<github-user>${RESET}"
  echo -e "  ${CYAN}export GHCR_TOKEN=<ghcr-pat>${RESET}"
  echo -e "  ${CYAN}export GHCR_IMAGES_PRIVATE=true${RESET}   # causes early abort if creds missing"
  echo -e "  ${CYAN}sudo -E ./install.sh${RESET}"
fi

echo ""
info "Pulling GoSecureShare images (namespace: ghcr.io/${NAMESPACE})..."
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
  echo -e "  1. Images are private — re-run with GHCR_USERNAME and GHCR_TOKEN set."
  echo -e "     Set GHCR_IMAGES_PRIVATE=true to catch this before pulling next time."
  echo -e "  2. Wrong image name — verify at: https://github.com/orgs/kisa-ops/packages"
  echo -e "  3. No internet access to ghcr.io on this host."
  exit 1
fi
success "All 6 images pulled (tag: ${VERSION})."
echo ""
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "(gosecureshare|postgres|nginx)" || true
