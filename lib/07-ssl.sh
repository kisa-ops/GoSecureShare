#!/usr/bin/env bash
# =============================================================================
# 07-ssl.sh — SSL / HTTPS setup
#
# Mode 1: Own reverse proxy (Cloudflare, HAProxy, Nginx, F5, etc.)
#         → Binds Docker containers to 127.0.0.1 only.
#         → Prints proxy target instructions. No cert files needed.
#
# Mode 2: Provide certificate files (corporate CA or purchased cert)
#         → Prompts for cert, key, CA bundle — separately for Platform
#           then Recipient.
#         → Validates cert+key pair match.
#         → Installs host Nginx as TLS terminator.
#         → Writes TLS virtual hosts with HTTP→301 redirect and OCSP stapling.
#
# Sets globals: ENABLE_SSL, SSL_TYPE, PLATFORM_BIND, RECIPIENT_BIND,
#               PLATFORM_DOMAIN, RECIPIENT_DOMAIN
# Sourced by install.sh — do not execute directly.
# =============================================================================

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
  echo -e "  ${DIM}     You will be asked for cert, key, and CA bundle — separately${RESET}"
  echo -e "  ${DIM}     for Platform and then for Recipient.${RESET}"
  echo ""
  read -rp "$(echo -e "  ${BOLD}Enter 1 or 2 [1]: ${RESET}")" _ssl_mode
  _ssl_mode=${_ssl_mode:-1}

  echo ""
  read -rp "$(echo -e "  ${BOLD}Platform domain   (e.g. platform.example.com): ${RESET}")" PLATFORM_DOMAIN
  [[ -z "${PLATFORM_DOMAIN}" ]] && error "Platform domain cannot be empty."
  read -rp "$(echo -e "  ${BOLD}Recipient domain  (e.g. share.example.com):    ${RESET}")" RECIPIENT_DOMAIN
  [[ -z "${RECIPIENT_DOMAIN}" ]] && error "Recipient domain cannot be empty."
  [[ "${PLATFORM_DOMAIN}" == "${RECIPIENT_DOMAIN}" ]] && error "Platform and Recipient domains must be different."

  # Always bind Docker containers to localhost when SSL is enabled
  PLATFORM_BIND="127.0.0.1:${PLATFORM_HTTP_PORT}"
  RECIPIENT_BIND="127.0.0.1:${RECIPIENT_HTTP_PORT}"

  # ---------------------------------------------------------------------------
  # MODE 1 — Own reverse proxy
  # ---------------------------------------------------------------------------
  if [[ "${_ssl_mode}" == "1" ]]; then
    SSL_TYPE="proxy"
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
  # MODE 2 — Provide certificate files
  # ---------------------------------------------------------------------------
  elif [[ "${_ssl_mode}" == "2" ]]; then
    SSL_TYPE="certfiles"

    # Prompt for a readable file path, retry until valid
    _prompt_file() {
      local label="$1" varname="$2"
      local path
      while true; do
        read -rp "$(echo -e "    ${CYAN}${label}: ${RESET}")" path
        path=$(echo "${path}" | xargs)   # trim whitespace
        if [[ -z "${path}" ]]; then
          warn "    Path cannot be empty."
        elif [[ ! -f "${path}" ]]; then
          warn "    File not found: ${path}"
        elif [[ ! -r "${path}" ]]; then
          warn "    File is not readable: ${path}"
        else
          printf -v "${varname}" '%s' "${path}"
          break
        fi
      done
    }

    # -- Platform certificates --
    echo ""
    echo -e "  ${BOLD}── Platform certificates (${PLATFORM_DOMAIN}) ──────────────────────────────${RESET}"
    echo -e "  ${DIM}  Provide absolute paths to the certificate files on this server.${RESET}"
    echo -e "  ${DIM}  The CA/intermediate bundle should contain the full chain excluding${RESET}"
    echo -e "  ${DIM}  the leaf cert (or a combined fullchain file is also accepted here).${RESET}"
    echo ""
    _prompt_file "Platform — Certificate file        (.crt / .pem)" P_CERT_FILE
    _prompt_file "Platform — Private key file         (.key / .pem)" P_KEY_FILE
    _prompt_file "Platform — CA / intermediate bundle (.crt / .pem)" P_CA_FILE

    # -- Recipient certificates --
    echo ""
    echo -e "  ${BOLD}── Recipient certificates (${RECIPIENT_DOMAIN}) ─────────────────────────────${RESET}"
    echo -e "  ${DIM}  You may reuse the same files if you have a wildcard or SAN cert.${RESET}"
    echo ""
    _prompt_file "Recipient — Certificate file        (.crt / .pem)" R_CERT_FILE
    _prompt_file "Recipient — Private key file         (.key / .pem)" R_KEY_FILE
    _prompt_file "Recipient — CA / intermediate bundle (.crt / .pem)" R_CA_FILE

    # Copy cert files into install dir
    SSL_CERT_DIR="${INSTALL_DIR}/ssl"
    mkdir -p "${SSL_CERT_DIR}/platform" "${SSL_CERT_DIR}/recipient"

    cp "${P_CERT_FILE}" "${SSL_CERT_DIR}/platform/cert.pem"
    cp "${P_KEY_FILE}"  "${SSL_CERT_DIR}/platform/key.pem"
    cp "${P_CA_FILE}"   "${SSL_CERT_DIR}/platform/ca-bundle.pem"
    # fullchain = leaf cert + CA bundle (what Nginx ssl_certificate expects)
    cat "${SSL_CERT_DIR}/platform/cert.pem" \
        "${SSL_CERT_DIR}/platform/ca-bundle.pem" \
        > "${SSL_CERT_DIR}/platform/fullchain.pem"
    chmod 600 "${SSL_CERT_DIR}/platform/key.pem"
    success "  Platform certificates copied."

    cp "${R_CERT_FILE}" "${SSL_CERT_DIR}/recipient/cert.pem"
    cp "${R_KEY_FILE}"  "${SSL_CERT_DIR}/recipient/key.pem"
    cp "${R_CA_FILE}"   "${SSL_CERT_DIR}/recipient/ca-bundle.pem"
    cat "${SSL_CERT_DIR}/recipient/cert.pem" \
        "${SSL_CERT_DIR}/recipient/ca-bundle.pem" \
        > "${SSL_CERT_DIR}/recipient/fullchain.pem"
    chmod 600 "${SSL_CERT_DIR}/recipient/key.pem"
    success "  Recipient certificates copied."

    PLATFORM_CERT_DIR="${SSL_CERT_DIR}/platform"
    RECIPIENT_CERT_DIR="${SSL_CERT_DIR}/recipient"

    # Validate cert + key pairs match
    info "Validating certificate / key pairs..."
    P_CERT_MD5=$(openssl x509 -noout -modulus -in "${PLATFORM_CERT_DIR}/cert.pem" 2>/dev/null | md5sum)
    P_KEY_MD5=$( openssl rsa  -noout -modulus -in "${PLATFORM_CERT_DIR}/key.pem"  2>/dev/null | md5sum)
    [[ "${P_CERT_MD5}" != "${P_KEY_MD5}" ]] && \
      error "Platform certificate and key do NOT match. Check your files."
    success "  Platform cert/key pair validated."

    R_CERT_MD5=$(openssl x509 -noout -modulus -in "${RECIPIENT_CERT_DIR}/cert.pem" 2>/dev/null | md5sum)
    R_KEY_MD5=$( openssl rsa  -noout -modulus -in "${RECIPIENT_CERT_DIR}/key.pem"  2>/dev/null | md5sum)
    [[ "${R_CERT_MD5}" != "${R_KEY_MD5}" ]] && \
      error "Recipient certificate and key do NOT match. Check your files."
    success "  Recipient cert/key pair validated."

    # Install host Nginx
    info "Installing host Nginx..."
    if command -v apt-get &>/dev/null; then
      apt-get update -qq
      apt-get install -y -qq nginx
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

    # Write host Nginx TLS virtual hosts
    info "Writing host Nginx TLS configs..."
    cat > /etc/nginx/sites-available/gss-platform <<NGINXEOF
server {
    listen 80;
    server_name ${PLATFORM_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    http2 on;
    server_name ${PLATFORM_DOMAIN};

    ssl_certificate         ${PLATFORM_CERT_DIR}/fullchain.pem;
    ssl_certificate_key     ${PLATFORM_CERT_DIR}/key.pem;
    ssl_trusted_certificate ${PLATFORM_CERT_DIR}/ca-bundle.pem;
    ssl_protocols           TLSv1.2 TLSv1.3;
    ssl_ciphers             HIGH:!aNULL:!MD5;
    ssl_session_cache       shared:SSL_P:10m;
    ssl_session_timeout     1d;
    ssl_stapling            on;
    ssl_stapling_verify     on;

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

    cat > /etc/nginx/sites-available/gss-recipient <<NGINXEOF
server {
    listen 80;
    server_name ${RECIPIENT_DOMAIN};
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    http2 on;
    server_name ${RECIPIENT_DOMAIN};

    ssl_certificate         ${RECIPIENT_CERT_DIR}/fullchain.pem;
    ssl_certificate_key     ${RECIPIENT_CERT_DIR}/key.pem;
    ssl_trusted_certificate ${RECIPIENT_CERT_DIR}/ca-bundle.pem;
    ssl_protocols           TLSv1.2 TLSv1.3;
    ssl_ciphers             HIGH:!aNULL:!MD5;
    ssl_session_cache       shared:SSL_R:10m;
    ssl_session_timeout     1d;
    ssl_stapling            on;
    ssl_stapling_verify     on;

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
  # HTTP-only — Docker containers bind on all interfaces
  PLATFORM_BIND="0.0.0.0:${PLATFORM_HTTP_PORT}"
  RECIPIENT_BIND="0.0.0.0:${RECIPIENT_HTTP_PORT}"
  warn "Skipping SSL setup. GoSecureShare will run on plain HTTP."
  warn "Browser encryption (crypto.subtle) will NOT work until HTTPS is configured."
fi
