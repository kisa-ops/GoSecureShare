#!/usr/bin/env bash
# =============================================================================
# 07-ssl.sh — SSL / HTTPS setup
#
# Mode 1: Own reverse proxy (Cloudflare, HAProxy, Nginx, F5, etc.)
#         → Binds Docker containers to 127.0.0.1 only.
#         → Prints proxy target instructions. No cert files needed.
#
# Mode 2: Provide certificate files (corporate CA or purchased cert)
#         → Input mode (file path or paste) is asked ONCE per service.
#         → Recipient can reuse platform certs (wildcard / SAN)
#         → Validates cert+key pair match BEFORE fullchain build and Nginx start.
#         → Installs host Nginx as TLS terminator.
#         → Recipient  → port 443  (standard HTTPS, clean share links)
#         → Platform   → port 8443 (non-standard, internal use; user-prompted)
#         → Docker nginx containers bind to 127.0.0.1:8181 / 127.0.0.1:8282
#           Host Nginx proxies HTTPS → those internal ports.
#           PLATFORM_HTTP_PORT / RECIPIENT_HTTP_PORT overridden to internal
#           values so .env and docker-compose stay consistent.
#
# Sets globals: ENABLE_SSL, SSL_TYPE, PLATFORM_BIND, RECIPIENT_BIND,
#               PLATFORM_DOMAIN, RECIPIENT_DOMAIN,
#               PLATFORM_HTTP_PORT, RECIPIENT_HTTP_PORT (certfiles mode),
#               PLATFORM_HTTPS_PORT (certfiles mode),
#               PLATFORM_CERT_DIR, RECIPIENT_CERT_DIR
# Sourced by install.sh — do not execute directly.
# =============================================================================

# Detect the server's primary IP — used as the default domain in HTTP-only mode.
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
[[ -z "${SERVER_IP}" ]] && SERVER_IP="127.0.0.1"

echo ""
echo -e "${BOLD}── SSL / HTTPS Setup ──────────────────────────────────────────${RESET}"
echo ""
echo -e "  ${CYAN}GoSecureShare requires HTTPS for browser-side encryption (Web Crypto API).${RESET}"
echo -e "  ${CYAN}You can set up TLS now (recommended) or skip and configure it manually later.${RESET}"
echo ""
read -rp "$(echo -e "  ${BOLD}Set up HTTPS with TLS certificates now? (yes/no) [yes]: ${RESET}")" _ssl_choice
_ssl_choice=${_ssl_choice:-yes}

ENABLE_SSL=false
PLATFORM_DOMAIN="${SERVER_IP}"
RECIPIENT_DOMAIN="${SERVER_IP}"
SSL_TYPE="none"

# Internal Docker ports — host Nginx proxies to these in certfiles mode.
# Must not clash with 80/443/8443 which host Nginx owns.
SSL_INTERNAL_PLATFORM_PORT=8181
SSL_INTERNAL_RECIPIENT_PORT=8282

# =============================================================================
# _prompt_cert_file <label> <dest_path> <mode>
#
# mode 1 = file path, mode 2 = paste
# Mode is resolved once by the caller and passed here — no per-file prompt.
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
# _validate_cert_key_pair <service_label> <cert_dir>
#
# Validates that cert.pem and key.pem moduli match using openssl.
# Cleans up the saved files and errors out if they do not match.
# Must be called BEFORE fullchain.pem is built and BEFORE Nginx is touched.
# =============================================================================
_validate_cert_key_pair() {
  local label="$1" cert_dir="$2"
  info "  Validating ${label} certificate / key pair..."

  local cert_md5 key_md5
  cert_md5=$(openssl x509 -noout -modulus -in "${cert_dir}/cert.pem" 2>/dev/null | md5sum) \
    || { rm -f "${cert_dir}/cert.pem" "${cert_dir}/key.pem" "${cert_dir}/ca-bundle.pem"
         error "${label} certificate is not a valid X.509 PEM file. Removed saved files."; }

  key_md5=$(openssl rsa -noout -modulus -in "${cert_dir}/key.pem" 2>/dev/null | md5sum) \
    || { rm -f "${cert_dir}/cert.pem" "${cert_dir}/key.pem" "${cert_dir}/ca-bundle.pem"
         error "${label} private key is not a valid RSA PEM file. Removed saved files."; }

  if [[ "${cert_md5}" != "${key_md5}" ]]; then
    rm -f "${cert_dir}/cert.pem" "${cert_dir}/key.pem" "${cert_dir}/ca-bundle.pem"
    error "${label} certificate and key do NOT match — they were removed.\n        Re-run install.sh and provide the correct matching cert and key."
  fi

  # Also verify the cert is not expired
  local not_after
  not_after=$(openssl x509 -noout -enddate -in "${cert_dir}/cert.pem" 2>/dev/null | cut -d= -f2 || echo "")
  if [[ -n "${not_after}" ]]; then
    local expiry_epoch now_epoch
    expiry_epoch=$(date -d "${not_after}" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "${not_after}" +%s 2>/dev/null || echo "0")
    now_epoch=$(date +%s)
    if (( expiry_epoch > 0 && expiry_epoch < now_epoch )); then
      warn "  ${label} certificate expired on: ${not_after}"
      warn "  The installation will continue but the browser will show a certificate error."
      warn "  Replace the certificate using: sudo ./update-ssl.sh"
    elif (( expiry_epoch > 0 && (expiry_epoch - now_epoch) < 2592000 )); then
      warn "  ${label} certificate expires soon: ${not_after} (within 30 days)"
      warn "  Plan a renewal using: sudo ./update-ssl.sh"
    else
      [[ -n "${not_after}" ]] && info "  ${label} certificate valid until: ${not_after}"
    fi
  fi

  success "  ${label} cert/key pair validated ✓"
}

if [[ "${_ssl_choice}" == "yes" ]]; then
  ENABLE_SSL=true

  echo ""
  echo -e "  ${BOLD}How will TLS be handled?${RESET}"
  echo ""
  echo -e "  ${CYAN}  1) I have my own reverse proxy (Cloudflare, Nginx, HAProxy, F5, etc.)${RESET}"
  echo -e "  ${DIM}     GoSecureShare binds to 127.0.0.1 only.${RESET}"
  echo -e "  ${DIM}     Your proxy handles TLS — no cert files needed here.${RESET}"
  echo ""
  echo -e "  ${CYAN}  2) I will provide certificate files (corporate CA or purchased cert)${RESET}"
  echo -e "  ${DIM}     Host Nginx will be installed as TLS terminator.${RESET}"
  echo -e "  ${DIM}     Recipient → port 443 (standard HTTPS, clean share links).${RESET}"
  echo -e "  ${DIM}     Platform  → port 8443 (non-standard, internal use).${RESET}"
  echo ""
  read -rp "$(echo -e "  ${BOLD}Enter 1 or 2 [1]: ${RESET}")" _ssl_mode
  _ssl_mode=${_ssl_mode:-1}

  echo ""
  read -rp "$(echo -e "  ${BOLD}Platform domain   (e.g. platform.example.com): ${RESET}")" PLATFORM_DOMAIN
  [[ -z "${PLATFORM_DOMAIN}" ]] && error "Platform domain cannot be empty."
  read -rp "$(echo -e "  ${BOLD}Recipient domain  (e.g. share.example.com):    ${RESET}")" RECIPIENT_DOMAIN
  [[ -z "${RECIPIENT_DOMAIN}" ]] && error "Recipient domain cannot be empty."
  [[ "${PLATFORM_DOMAIN}" == "${RECIPIENT_DOMAIN}" ]] && error "Platform and Recipient domains must be different."

  # ---------------------------------------------------------------------------
  # MODE 1 — Own reverse proxy
  # ---------------------------------------------------------------------------
  if [[ "${_ssl_mode}" == "1" ]]; then
    SSL_TYPE="proxy"
    PLATFORM_BIND="127.0.0.1:${PLATFORM_HTTP_PORT}"
    RECIPIENT_BIND="127.0.0.1:${RECIPIENT_HTTP_PORT}"
    echo ""
    success "Docker containers will bind to 127.0.0.1 only."
    info "Configure your reverse proxy to forward traffic to:"
    echo -e "  ${BOLD}    https://${PLATFORM_DOMAIN}  →  http://127.0.0.1:${PLATFORM_HTTP_PORT}${RESET}"
    echo -e "  ${BOLD}    https://${RECIPIENT_DOMAIN}  →  http://127.0.0.1:${RECIPIENT_HTTP_PORT}${RESET}"
    echo ""
    info "Ensure your proxy sets these headers:"
    echo -e "  ${DIM}    X-Forwarded-Proto: https${RESET}"
    echo -e "  ${DIM}    X-Forwarded-For:   <client-ip>${RESET}"
    echo -e "  ${DIM}    Host:              <domain>${RESET}"
    echo ""

  # ---------------------------------------------------------------------------
  # MODE 2 — Provide certificate files (path or paste)
  # ---------------------------------------------------------------------------
  elif [[ "${_ssl_mode}" == "2" ]]; then
    SSL_TYPE="certfiles"

    # Prompt for platform HTTPS port (non-standard, internal use).
    # Recipient always gets 443 for clean external share links.
    echo ""
    echo -e "  ${DIM}Recipient will be served on port 443 (standard HTTPS).${RESET}"
    echo -e "  ${DIM}Platform is for internal use and runs on a non-standard HTTPS port.${RESET}"
    while true; do
      read -rp "$(echo -e "  ${BOLD}Platform HTTPS port [8443]: ${RESET}")" PLATFORM_HTTPS_PORT
      PLATFORM_HTTPS_PORT=${PLATFORM_HTTPS_PORT:-8443}
      [[ "${PLATFORM_HTTPS_PORT}" =~ ^[0-9]+$ ]] && \
        (( PLATFORM_HTTPS_PORT >= 1024 && PLATFORM_HTTPS_PORT <= 65535 )) && \
        (( PLATFORM_HTTPS_PORT != 443 )) && break
      warn "  Must be 1024–65535 and not 443."
    done

    # Override internal port vars — host Nginx owns 80/443/PLATFORM_HTTPS_PORT.
    PLATFORM_HTTP_PORT=${SSL_INTERNAL_PLATFORM_PORT}
    RECIPIENT_HTTP_PORT=${SSL_INTERNAL_RECIPIENT_PORT}
    PLATFORM_BIND="127.0.0.1:${PLATFORM_HTTP_PORT}"
    RECIPIENT_BIND="127.0.0.1:${RECIPIENT_HTTP_PORT}"

    info "Port layout:"
    echo -e "  ${DIM}    Recipient  → https://${RECIPIENT_DOMAIN}           (port 443, Docker internal :${RECIPIENT_HTTP_PORT})${RESET}"
    echo -e "  ${DIM}    Platform   → https://${PLATFORM_DOMAIN}:${PLATFORM_HTTPS_PORT}  (Docker internal :${PLATFORM_HTTP_PORT})${RESET}"

    SSL_CERT_DIR="${INSTALL_DIR}/ssl"
    mkdir -p "${SSL_CERT_DIR}/platform" "${SSL_CERT_DIR}/recipient"

    # -------------------------------------------------------------------------
    # Platform certificates
    # Collect all 3 files → validate cert+key match → THEN build fullchain.
    # Nginx is not touched until both services pass validation.
    # -------------------------------------------------------------------------
    echo ""
    echo -e "  ${BOLD}── Platform certificates (${PLATFORM_DOMAIN}) ──────────────────────────────${RESET}"
    echo -e "  ${DIM}  Three files needed: certificate, private key, CA/intermediate bundle.${RESET}"

    _ask_input_mode "Platform"
    _p_mode=${_cert_input_mode}

    _prompt_cert_file "Platform certificate (.crt / .pem)"       "${SSL_CERT_DIR}/platform/cert.pem"      "${_p_mode}"
    _prompt_cert_file "Platform private key (.key / .pem)"       "${SSL_CERT_DIR}/platform/key.pem"       "${_p_mode}"
    _prompt_cert_file "Platform CA / intermediate bundle (.pem)"  "${SSL_CERT_DIR}/platform/ca-bundle.pem" "${_p_mode}"

    _validate_cert_key_pair "Platform" "${SSL_CERT_DIR}/platform"

    cat "${SSL_CERT_DIR}/platform/cert.pem" \
        "${SSL_CERT_DIR}/platform/ca-bundle.pem" \
        > "${SSL_CERT_DIR}/platform/fullchain.pem"
    chmod 600 "${SSL_CERT_DIR}/platform/key.pem"
    success "  Platform certificates saved and fullchain built."

    # -------------------------------------------------------------------------
    # Recipient certificates
    # Same pattern: collect → validate → build fullchain.
    # -------------------------------------------------------------------------
    echo ""
    echo -e "  ${BOLD}── Recipient certificates (${RECIPIENT_DOMAIN}) ─────────────────────────────${RESET}"
    echo ""
    read -rp "$(echo -e "  ${BOLD}Use the same certificate files as Platform? (wildcard / SAN cert) (yes/no) [yes]: ${RESET}")" _reuse_certs
    _reuse_certs=${_reuse_certs:-yes}
    # Normalize to lowercase so y/Y/Yes/YES all resolve correctly.
    _reuse_certs=$(echo "${_reuse_certs}" | tr '[:upper:]' '[:lower:]')
    # Treat any "y"-prefixed answer as "yes", anything else as "no".
    [[ "${_reuse_certs}" == y* ]] && _reuse_certs="yes" || _reuse_certs="no"

    if [[ "${_reuse_certs}" == "yes" ]]; then
      cp "${SSL_CERT_DIR}/platform/cert.pem"      "${SSL_CERT_DIR}/recipient/cert.pem"
      cp "${SSL_CERT_DIR}/platform/key.pem"       "${SSL_CERT_DIR}/recipient/key.pem"
      cp "${SSL_CERT_DIR}/platform/ca-bundle.pem" "${SSL_CERT_DIR}/recipient/ca-bundle.pem"
      cp "${SSL_CERT_DIR}/platform/fullchain.pem" "${SSL_CERT_DIR}/recipient/fullchain.pem"
      chmod 600 "${SSL_CERT_DIR}/recipient/key.pem"
      success "  Reusing Platform certificate files for Recipient."
      # No need to re-validate — same files, already validated above.
    else
      echo -e "  ${DIM}  Provide separate certificate files for ${RECIPIENT_DOMAIN}.${RESET}"
      _ask_input_mode "Recipient"
      _r_mode=${_cert_input_mode}

      _prompt_cert_file "Recipient certificate (.crt / .pem)"       "${SSL_CERT_DIR}/recipient/cert.pem"      "${_r_mode}"
      _prompt_cert_file "Recipient private key (.key / .pem)"       "${SSL_CERT_DIR}/recipient/key.pem"       "${_r_mode}"
      _prompt_cert_file "Recipient CA / intermediate bundle (.pem)"  "${SSL_CERT_DIR}/recipient/ca-bundle.pem" "${_r_mode}"

      _validate_cert_key_pair "Recipient" "${SSL_CERT_DIR}/recipient"

      cat "${SSL_CERT_DIR}/recipient/cert.pem" \
          "${SSL_CERT_DIR}/recipient/ca-bundle.pem" \
          > "${SSL_CERT_DIR}/recipient/fullchain.pem"
      chmod 600 "${SSL_CERT_DIR}/recipient/key.pem"
      success "  Recipient certificates saved and fullchain built."
    fi

    PLATFORM_CERT_DIR="${SSL_CERT_DIR}/platform"
    RECIPIENT_CERT_DIR="${SSL_CERT_DIR}/recipient"

    # -------------------------------------------------------------------------
    # All certs validated. Now safe to install and configure Nginx.
    # -------------------------------------------------------------------------

    # Install host Nginx
    info "Installing host Nginx..."
    if command -v apt-get &>/dev/null; then
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx
    elif command -v dnf &>/dev/null; then
      dnf install -y nginx
    elif command -v yum &>/dev/null; then
      yum install -y nginx
    else
      error "Cannot install nginx — unsupported package manager. Install it manually and re-run."
    fi
    success "Host Nginx installed."

    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
    rm -f /etc/nginx/sites-enabled/default

    # NOTE: 'listen 443 ssl http2' / 'listen PORT ssl http2' is used instead
    # of standalone 'http2 on;' for nginx 1.24 compatibility (Ubuntu LTS).
    info "Writing host Nginx TLS configs..."

    # Platform — non-standard HTTPS port, internal use
    cat > /etc/nginx/sites-available/gss-platform <<NGINXEOF
server {
    listen 80;
    server_name ${PLATFORM_DOMAIN};
    return 301 https://\$host:${PLATFORM_HTTPS_PORT}\$request_uri;
}
server {
    listen ${PLATFORM_HTTPS_PORT} ssl http2;
    server_name ${PLATFORM_DOMAIN};

    ssl_certificate         ${PLATFORM_CERT_DIR}/fullchain.pem;
    ssl_certificate_key     ${PLATFORM_CERT_DIR}/key.pem;
    ssl_trusted_certificate ${PLATFORM_CERT_DIR}/ca-bundle.pem;
    ssl_protocols           TLSv1.2 TLSv1.3;
    ssl_ciphers             HIGH:!aNULL:!MD5;
    ssl_session_cache       shared:SSL_P:10m;
    ssl_session_timeout     1d;
    # ssl_stapling on/off depends on whether your CA provides an OCSP responder.
    # Enabled here for public CAs; harmlessly ignored if OCSP is unavailable.
    # ssl_stapling_verify is intentionally omitted — it causes Nginx reload
    # errors when the OCSP responder is unreachable (corporate / offline CAs).
    ssl_stapling            on;

    client_max_body_size 50M;

    location / {
        proxy_pass         http://127.0.0.1:${PLATFORM_HTTP_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        'upgrade';
    }
}
NGINXEOF

    # Recipient — standard port 443, clean external share links
    cat > /etc/nginx/sites-available/gss-recipient <<NGINXEOF
server {
    listen 80;
    server_name ${RECIPIENT_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    server_name ${RECIPIENT_DOMAIN};

    ssl_certificate         ${RECIPIENT_CERT_DIR}/fullchain.pem;
    ssl_certificate_key     ${RECIPIENT_CERT_DIR}/key.pem;
    ssl_trusted_certificate ${RECIPIENT_CERT_DIR}/ca-bundle.pem;
    ssl_protocols           TLSv1.2 TLSv1.3;
    ssl_ciphers             HIGH:!aNULL:!MD5;
    ssl_session_cache       shared:SSL_R:10m;
    ssl_session_timeout     1d;
    # ssl_stapling on/off depends on whether your CA provides an OCSP responder.
    # Enabled here for public CAs; harmlessly ignored if OCSP is unavailable.
    # ssl_stapling_verify is intentionally omitted — it causes Nginx reload
    # errors when the OCSP responder is unreachable (corporate / offline CAs).
    ssl_stapling            on;

    client_max_body_size 50M;

    location / {
        proxy_pass         http://127.0.0.1:${RECIPIENT_HTTP_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Upgrade           \$http_upgrade;
        proxy_set_header   Connection        'upgrade';
    }
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/gss-platform  /etc/nginx/sites-enabled/gss-platform
    ln -sf /etc/nginx/sites-available/gss-recipient /etc/nginx/sites-enabled/gss-recipient

    nginx -t || error "Host Nginx config test failed. Check /etc/nginx/sites-available/gss-{platform,recipient}."
    systemctl enable nginx --quiet
    systemctl restart nginx
    success "Host Nginx restarted with TLS configs."

  else
    error "Invalid SSL mode '${_ssl_mode}'. Please enter 1 or 2."
  fi

else
  # ---------------------------------------------------------------------------
  # HTTP-only — ask for domains (defaulting to detected server IP) and bind
  # Docker containers on all interfaces.
  # ---------------------------------------------------------------------------
  echo ""
  echo -e "  ${DIM}HTTP-only mode. Domains default to the server IP (${SERVER_IP}).${RESET}"
  echo -e "  ${DIM}You can enter hostnames if DNS is already configured.${RESET}"
  echo ""
  read -rp "$(echo -e "  ${BOLD}Platform  domain/IP [${SERVER_IP}]: ${RESET}")" PLATFORM_DOMAIN
  PLATFORM_DOMAIN=${PLATFORM_DOMAIN:-${SERVER_IP}}
  read -rp "$(echo -e "  ${BOLD}Recipient domain/IP [${SERVER_IP}]: ${RESET}")" RECIPIENT_DOMAIN
  RECIPIENT_DOMAIN=${RECIPIENT_DOMAIN:-${SERVER_IP}}

  PLATFORM_BIND="0.0.0.0:${PLATFORM_HTTP_PORT}"
  RECIPIENT_BIND="0.0.0.0:${RECIPIENT_HTTP_PORT}"
  warn "Skipping SSL setup. GoSecureShare will run on plain HTTP."
  warn "Browser encryption (crypto.subtle) will NOT work until HTTPS is configured."
fi
