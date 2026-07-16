#!/usr/bin/env bash
# =============================================================================
# 08-secrets.sh — Generate cryptographic secrets and hash admin password
# Sourced by install.sh — do not execute directly.
# =============================================================================

info "Generating cryptographic secrets..."
ENCRYPTION_KEY=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)
GSS_PLATFORM_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)
GSS_RECIPIENT_DB_PASSWORD=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)
success "Secrets generated."

# ---------------------------------------------------------------------------
# Hash admin password with Argon2.
# ---------------------------------------------------------------------------
info "Hashing admin password (argon2)..."

ADMIN_HASHED_PASSWORD=$(python3 -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['argon2'], deprecated='auto')
print(ctx.hash('${GSS_ADMIN_PASSWORD}')); " 2>/dev/null || echo "HASH_UNAVAILABLE")

if [[ "${ADMIN_HASHED_PASSWORD}" == "HASH_UNAVAILABLE" ]]; then
  info "passlib[argon2] not found on host — installing into a temporary virtualenv..."

  if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null 2>&1; then
    error "pip3 is not available and passlib[argon2] is not installed.\n" \
          "       Install pip first: apt-get install -y python3-pip  # or dnf install -y python3-pip\n" \
          "       Then re-run this installer."
  fi

  GSS_VENV_DIR="$(mktemp -d /tmp/gss_venv_XXXXXX)"
  python3 -m venv "${GSS_VENV_DIR}" --without-pip 2>/dev/null \
    || python3 -m venv "${GSS_VENV_DIR}"

  if [[ ! -f "${GSS_VENV_DIR}/bin/pip" ]]; then
    curl -fsSL https://bootstrap.pypa.io/get-pip.py | "${GSS_VENV_DIR}/bin/python3" - \
      || error "Failed to bootstrap pip into temporary venv. Cannot hash admin password."
  fi

  "${GSS_VENV_DIR}/bin/pip" install --quiet --disable-pip-version-check 'passlib[argon2]' \
    || error "Failed to install passlib[argon2] into temporary venv. Cannot hash admin password."

  ADMIN_HASHED_PASSWORD=$("${GSS_VENV_DIR}/bin/python3" -c "
from passlib.context import CryptContext
ctx = CryptContext(schemes=['argon2'], deprecated='auto')
print(ctx.hash('${GSS_ADMIN_PASSWORD}')); " 2>/dev/null || echo "HASH_UNAVAILABLE")

  rm -rf "${GSS_VENV_DIR}"

  if [[ "${ADMIN_HASHED_PASSWORD}" == "HASH_UNAVAILABLE" ]]; then
    error "Argon2 hashing failed even after installing passlib[argon2].\n" \
          "       Please report this at https://github.com/kisa-ops/GoSecureShare/issues"
  fi

  success "passlib[argon2] installed and admin password hashed successfully."
else
  success "Admin password hashed (argon2)."
fi

ADMIN_HASHED_PASSWORD_ESC="${ADMIN_HASHED_PASSWORD//$/\$\$}"
