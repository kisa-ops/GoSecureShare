#!/usr/bin/env bash
# =============================================================================
# 05-db-files.sh — Resolve and copy DB bootstrap files (local or remote)
# Sourced by install.sh — do not execute directly.
#
# Fetch resolution order (per file):
#   1. Local  — db/ folder next to install.sh  (or GSS_DB_DIR override)
#   2. Remote — raw.githubusercontent.com (fast path, works for public repo)
#   3. Remote — GitHub Contents API (fallback, works for private repo w/ token)
# Aborts hard if either file cannot be resolved.
# =============================================================================

echo ""
info "Creating installation directory: ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}/db" "${INSTALL_DIR}/nginx"
success "Directory structure ready."

echo ""
info "── DB Files ────────────────────────────────────────────────"

# ---------------------------------------------------------------------------
# Resolve local db/ dir (if any)
# ---------------------------------------------------------------------------
if [[ -n "${GSS_DB_DIR:-}" ]]; then
  LOCAL_DB_DIR="${GSS_DB_DIR}"
  info "Using GSS_DB_DIR override: ${LOCAL_DB_DIR}"
elif [[ -f "${SCRIPT_DIR}/db/init.sql" && -f "${SCRIPT_DIR}/db/docker-migrate.sh" ]]; then
  LOCAL_DB_DIR="${SCRIPT_DIR}/db"
  info "Found local db/ folder next to install.sh: ${LOCAL_DB_DIR}"
else
  LOCAL_DB_DIR=""
fi

# Ref used for remote DB fetching. Inherits GSS_LIB_REF so both lib/ and db/
# files are always pulled from the same ref. Override with GSS_DB_REF.
DB_REF="${GSS_DB_REF:-${GSS_LIB_REF:-main}}"
DB_RAW_BASE="https://raw.githubusercontent.com/kisa-ops/GoSecureShare/${DB_REF}/db"
# NOTE: DB_API_BASE must NOT include ?ref= here — the ref is appended per-file
#       in _fetch_db_api as: contents/db/<file>?ref=<ref>
DB_API_CONTENTS_BASE="https://api.github.com/repos/kisa-ops/GoSecureShare/contents/db"

# ---------------------------------------------------------------------------
# _fetch_db_api  —  GitHub Contents API fallback (private repos)
# Tries Accept: application/vnd.github.v3.raw first (direct raw download).
# Falls back to JSON response + python3 base64 decode if needed.
# ---------------------------------------------------------------------------
_fetch_db_api() {
  local file="$1" dest="$2"
  # Correct URL: /contents/db/<file>?ref=<ref>
  local url="${DB_API_CONTENTS_BASE}/${file}?ref=${DB_REF}"
  local token_header=(-H "Authorization: Bearer ${GHCR_TOKEN}")

  # Attempt 1: raw media type (direct content, no base64)
  if curl -fsSL --connect-timeout 10 \
      "${token_header[@]}" \
      -H "Accept: application/vnd.github.v3.raw" \
      "${url}" -o "${dest}" 2>/dev/null; then
    return 0
  fi

  # Attempt 2: JSON response → base64 decode via python3
  local tmp_json
  tmp_json=$(mktemp)
  if curl -fsSL --connect-timeout 10 \
      "${token_header[@]}" \
      -H "Accept: application/vnd.github+json" \
      "${url}" -o "${tmp_json}" 2>/dev/null; then
    python3 - "${tmp_json}" "${dest}" <<'PYEOF' 2>/dev/null
import json, sys, base64
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    obj = json.load(fh)
content = obj.get('content')
if content is None:
    sys.exit(1)
data = base64.b64decode(content) if obj.get('encoding') == 'base64' else content.encode()
with open(sys.argv[2], 'wb') as fh:
    fh.write(data)
PYEOF
    local rc=$?
    rm -f "${tmp_json}"
    return $rc
  fi
  rm -f "${tmp_json}"
  return 1
}

# ---------------------------------------------------------------------------
# _resolve_db_file  —  local → raw → API per file
# ---------------------------------------------------------------------------
_resolve_db_file() {
  local file="$1"
  local dest="${INSTALL_DIR}/db/${file}"

  # 1. Local copy
  if [[ -n "${LOCAL_DB_DIR}" && -f "${LOCAL_DB_DIR}/${file}" ]]; then
    cp "${LOCAL_DB_DIR}/${file}" "${dest}"
    success "  Copied from local: ${file}"
    return 0
  fi

  # 2. Raw URL (public repo fast path; also works with token on private repo)
  local raw_curl_args=()
  [[ -n "${GHCR_TOKEN:-}" ]] && raw_curl_args+=(-H "Authorization: Bearer ${GHCR_TOKEN}")
  if curl -fsSL --connect-timeout 10 \
      "${raw_curl_args[@]}" \
      "${DB_RAW_BASE}/${file}" -o "${dest}" 2>/dev/null; then
    success "  Fetched (raw): ${file}"
    return 0
  fi

  # 3. GitHub Contents API (private repo fallback; requires GHCR_TOKEN)
  if [[ -n "${GHCR_TOKEN:-}" ]]; then
    if _fetch_db_api "${file}" "${dest}"; then
      success "  Fetched (API): ${file}"
      return 0
    fi
  fi

  # All paths failed
  warn "  Could not fetch: ${file}"
  return 1
}

# ---------------------------------------------------------------------------
# Fetch both DB files; collect failures and abort hard if any
# ---------------------------------------------------------------------------
if [[ -z "${LOCAL_DB_DIR}" ]]; then
  info "No local db/ folder found — fetching from GitHub (ref: ${DB_REF})..."
fi

DB_FAILED=()
for _dbf in init.sql docker-migrate.sh; do
  _resolve_db_file "${_dbf}" || DB_FAILED+=("${_dbf}")
done

if [[ ${#DB_FAILED[@]} -gt 0 ]]; then
  echo ""
  echo -e "${RED}[ERROR]${RESET} Failed to fetch DB file(s): ${DB_FAILED[*]}" >&2
  echo "" >&2
  if [[ -z "${GHCR_TOKEN:-}" ]]; then
    echo -e "  ${YELLOW}The repo may be private. Options:${RESET}" >&2
    echo -e "  A) Place db/ folder next to install.sh (no token needed):" >&2
    echo -e "       ${SCRIPT_DIR}/db/init.sql" >&2
    echo -e "       ${SCRIPT_DIR}/db/docker-migrate.sh" >&2
    echo -e "  B) Supply a token with 'repo' scope:" >&2
    echo -e "       export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx" >&2
    echo -e "       sudo -E ./install.sh" >&2
    echo -e "  C) Explicit path override: GSS_DB_DIR=/your/path sudo ./install.sh" >&2
  else
    echo -e "  ${YELLOW}Token was supplied but all fetch paths failed. Check:${RESET}" >&2
    echo -e "    • Token has 'repo' scope (not just 'read:packages')" >&2
    echo -e "    • DNS: nslookup raw.githubusercontent.com && nslookup api.github.com" >&2
    echo -e "    • Proxy: export https_proxy=http://<proxy>:<port>" >&2
    echo -e "    • python3 available (needed for API decode fallback)" >&2
    echo -e "  Or place db/ locally: ${SCRIPT_DIR}/db/ and re-run." >&2
  fi
  echo "" >&2
  # Clean up partial downloads to avoid half-state on next run
  rm -f "${INSTALL_DIR}/db/init.sql" "${INSTALL_DIR}/db/docker-migrate.sh"
  exit 1
fi

chmod +x "${INSTALL_DIR}/db/docker-migrate.sh"
success "Database files ready (ref: ${DB_REF})."
