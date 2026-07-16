#!/usr/bin/env bash
# =============================================================================
# 02-prerequisites.sh — Check Docker, Docker Compose, curl, openssl, python3
# Sourced by install.sh — do not execute directly.
# =============================================================================

info "Checking prerequisites..."
echo ""
PREREQ_OK=true

if command -v docker &>/dev/null; then
  DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
  success "Docker found: v${DOCKER_VER}"
  if docker compose version &>/dev/null 2>&1; then
    COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "unknown")
    success "Docker Compose found: v${COMPOSE_VER}"
  else
    warn "Docker Compose plugin is NOT installed."
    echo -e "  ${YELLOW}Install:${RESET}  apt-get install -y docker-compose-plugin"
    PREREQ_OK=false
  fi
else
  warn "Docker is NOT installed."
  echo -e "  ${YELLOW}Install:${RESET}  curl -fsSL https://get.docker.com | sh"
  PREREQ_OK=false
fi

for tool in curl openssl python3; do
  if command -v "${tool}" &>/dev/null; then
    success "${tool} found"
  else
    warn "${tool} is NOT installed."
    echo -e "  ${YELLOW}Install:${RESET}  apt-get install -y ${tool}   # or dnf install -y ${tool}"
    PREREQ_OK=false
  fi
done

echo ""
[[ "${PREREQ_OK}" == "false" ]] && error "Prerequisites missing. Install them (see above) and re-run."
success "All prerequisites satisfied."
