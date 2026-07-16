#!/usr/bin/env bash
# =============================================================================
# 03-version.sh — Resolve image version and build tagged image names
# Sourced by install.sh — do not execute directly.
# =============================================================================

info "Resolving image version..."

_resolve_version() {
  if [[ -n "${GSS_VERSION:-}" ]]; then
    echo "${GSS_VERSION#v}"
    return
  fi
  local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"
  local curl_auth=()
  [[ -n "${GHCR_TOKEN:-}" ]] && curl_auth=(-H "Authorization: Bearer ${GHCR_TOKEN}")
  local tag
  tag=$(curl -fsSL --connect-timeout 8 \
    -H "Accept: application/vnd.github+json" \
    "${curl_auth[@]}" \
    "${api_url}" 2>/dev/null \
    | grep '"tag_name"' \
    | sed 's/.*"tag_name": "\(.*\)".*/\1/' \
    | tr -d '[:space:]' \
    | sed 's/^v//' || echo "")
  if [[ -n "${tag}" && "${tag}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${tag}"
  else
    echo "latest"
  fi
}

VERSION="$(_resolve_version)"
if [[ "${VERSION}" == "latest" ]]; then
  warn "No stable SemVer release found — using :latest tag."
  warn "For production, pin to a specific version: GSS_VERSION=x.y.z sudo ./install.sh"
else
  success "Installing version: ${VERSION}"
  info  "To install a different version: GSS_VERSION=x.y.z sudo ./install.sh"
fi

if [[ "${VERSION}" == "latest" ]]; then
  GIT_REF="main"
else
  GIT_REF="v${VERSION}"
fi

TAGGED_API_PLATFORM="${IMAGE_API_PLATFORM}:${VERSION}"
TAGGED_API_RECIPIENT="${IMAGE_API_RECIPIENT}:${VERSION}"
TAGGED_FRONTEND_PLATFORM="${IMAGE_FRONTEND_PLATFORM}:${VERSION}"
TAGGED_FRONTEND_RECIPIENT="${IMAGE_FRONTEND_RECIPIENT}:${VERSION}"
ALL_IMAGES=(
  "${TAGGED_API_PLATFORM}"
  "${TAGGED_API_RECIPIENT}"
  "${TAGGED_FRONTEND_PLATFORM}"
  "${TAGGED_FRONTEND_RECIPIENT}"
  "postgres:16-alpine"
  "nginx:1.27-alpine"
)
