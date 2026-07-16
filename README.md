<p align="center">
  <a href="https://gosecureshare.com">
    <img src="logo.svg" alt="GoSecureShare" width="200" />
  </a>
</p>

<h1 align="center">
  <a href="https://gosecureshare.com">GoSecureShare</a>
</h1>

<p align="center">
  Enterprise-grade, self-hosted <strong>zero-knowledge secret sharing</strong>.<br/>
  Share passwords, API keys, and files via one-time secure links — fully air-gapped with Docker Compose.
</p>

<p align="center">
  <a href="https://gosecureshare.com">🌐 gosecureshare.com</a>
</p>

---

## What you need

Just **1 file**. The installer auto-fetches the DB files and writes all configuration.

```
gosecureshare/
└── install.sh    ← Run this (canonical location: production/install.sh)
```

The installer downloads `db/init.sql` and `db/docker-migrate.sh` directly from GitHub during setup. If the repo is private, supply a token with `repo` scope (see [Private Registry](#private-ghcr-registry--private-repo) below).

---

## Prerequisites

| Requirement | Minimum version | Install |
|---|---|---|
| Docker Engine | 24+ | `curl -fsSL https://get.docker.com \| sh` |
| Docker Compose plugin | v2 | `apt-get install -y docker-compose-plugin` |
| `curl` | any | `apt-get install -y curl` |
| `openssl` | any | `apt-get install -y openssl` |

> No local PostgreSQL installation needed — it runs as a dedicated container.

> ⚠️ All `docker` commands must be run with `sudo` unless your user has been added to the `docker` group.

---

## Quick Install

### 1. Download the installer

```bash
mkdir gosecureshare && cd gosecureshare
curl -fsSL https://raw.githubusercontent.com/kisa-ops/GoSecureShare/main/production/install.sh -o install.sh
chmod +x install.sh
```

> If the repository is **private**, add `-H "Authorization: Bearer <your-token>"` to the curl command,
> or download the file via `gh repo clone` / SFTP and copy it to the server.

### 2. Run the installer

```bash
sudo ./install.sh
```

The installer will:

1. ✅ Verify prerequisites (Docker, Compose, curl, openssl)
2. 🔍 Auto-detect the latest stable release from GitHub Releases
3. 🐳 Pull all 6 container images (`ghcr.io/kisa-ops/*`, `postgres:16-alpine`, `nginx:1.27-alpine`)
4. 📁 Create the installation directory at `/opt/gosecureshare/`
5. 🔗 Fetch `db/init.sql` and `db/docker-migrate.sh` directly from GitHub
6. ⚙️  Prompt for ports and admin credentials
7. 🔐 Auto-generate all cryptographic secrets (AES-256 key, JWT secret, DB passwords)
8. 📝 Write `/opt/gosecureshare/.env` (secured with `chmod 600`)
9. 🚀 Start all 8 containers via Docker Compose
10. ⏳ Wait for database migration to complete successfully
11. ❤️  Wait for platform API to become healthy
12. ✔️  Verify login endpoint is reachable before declaring success

### 3. Open in browser

After install, the summary screen shows your URLs:

| Interface | Default URL | Purpose |
|---|---|---|
| **Platform (Admin / Staff)** | `http://<server-ip>:80` | Login · create secrets · admin dashboard |
| **Recipient Portal** | `http://<server-ip>:8181` | View a shared one-time secret |
| **Health check** | `http://<server-ip>:80/healthz` | Liveness probe |

---

## Install Options

### Pin to a specific version

```bash
GSS_VERSION=2.3.1 sudo ./install.sh
```

### Custom ports

The installer prompts for platform and recipient ports interactively. You can also edit `/opt/gosecureshare/.env` after install and restart:

```bash
sudo docker compose -f /opt/gosecureshare/docker-compose.yml up -d
```

### Private GHCR registry / private repo

When the **GHCR images are private**, a GitHub PAT is required for `docker login`. When the **source repository is also private**, the same token (with an additional scope) is used to fetch the DB files.

#### Step 1 — Create a GitHub PAT

Go to **GitHub → Settings → Developer settings → Personal access tokens (classic)** and create a token with:

| Scope | Required for |
|---|---|
| `read:packages` | Pulling private GHCR images |
| `repo` | Fetching `init.sql` / `docker-migrate.sh` from a private repo |

> If your images are public but the source repo is private, you only need `repo`.
> If only images are private, `read:packages` is sufficient.

#### Step 2 — Export credentials and run

```bash
export GHCR_USERNAME=your-github-username
export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
export GHCR_IMAGES_PRIVATE=true       # causes early abort if creds are missing
sudo -E ./install.sh                  # -E passes env vars through sudo
```

> ⚠️ The `-E` flag is **required**. Without it, `sudo` strips the environment and the script
> never receives the credentials, leading to a silent pull failure.

#### How the token is used internally

| Step | What happens |
|---|---|
| **STEP 4** | `docker login ghcr.io` with `GHCR_USERNAME` + `GHCR_TOKEN` |
| **STEP 7** | `curl -H "Authorization: Bearer $GHCR_TOKEN"` to fetch DB files from `raw.githubusercontent.com` |
| **STEP 2** | GitHub Releases API call also uses the token (needed for private repos) |

#### Early-abort mode (`GHCR_IMAGES_PRIVATE=true`)

Setting this flag makes the installer **abort immediately** at STEP 4 with a clear error if either `GHCR_USERNAME` or `GHCR_TOKEN` is missing — rather than proceeding and failing silently during the `docker pull` later.

Without the flag the script still warns and attempts a public pull, which is useful when only some images are private or during local testing.

#### Combined example (private images + private repo + pinned version)

```bash
export GHCR_USERNAME=your-github-username
export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
export GHCR_IMAGES_PRIVATE=true
export GSS_VERSION=1.2.3
sudo -E ./install.sh
```

---

## Upgrading

The installer writes an `upgrade.sh` helper to `/opt/gosecureshare/`:

```bash
# Upgrade to latest release (auto-detected)
cd /opt/gosecureshare && sudo ./upgrade.sh

# Upgrade to a specific version
sudo ./upgrade.sh 2.5.0

# Upgrade with private registry credentials
export GHCR_USERNAME=your-github-username
export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
cd /opt/gosecureshare && sudo -E ./upgrade.sh
```

`upgrade.sh` re-authenticates to GHCR, pulls the new images, patches `docker-compose.yml` in-place, restarts the stack, and records the new version in `.env`.

---

## Clean Reinstall

### 1. Stop and wipe the old installation

```bash
cd /opt/gosecureshare
sudo docker compose down -v
```

> ⚠️ The `-v` flag removes all volumes including PostgreSQL data. Required so the DB migration and admin seed run clean on the next start.

### 2. Remove the install directory

```bash
sudo rm -rf /opt/gosecureshare
```

### 3. Remove old images (optional but recommended)

```bash
sudo docker rmi $(sudo docker images --format '{{.ID}}' --filter 'reference=*gosecureshare*') 2>/dev/null || true
sudo docker rmi postgres:16-alpine nginx:1.27-alpine 2>/dev/null || true
```

### 4. Re-run the installer

```bash
cd ~/gosecureshare && sudo ./install.sh
```

### 5. Verify after install

```bash
cd /opt/gosecureshare
sudo docker compose ps                         # all containers healthy/running
sudo docker logs gosecureshare-db-migrate      # should end with exit 0
curl http://localhost/healthz                  # → {"ok": true}
```

---

## Container Architecture

```
Host machine
└── Docker Engine
    └── gss_internal (bridge network — fully self-contained)
        ├── gosecureshare-postgres        :5434 (host) / :5432 (internal)
        ├── gosecureshare-db-migrate      runs once, then exits
        ├── gosecureshare-nginx-platform  :80   → Platform UI + API
        ├── gosecureshare-nginx-recipient :8181 → Recipient share page
        ├── gosecureshare-ui-platform            Next.js 14 — login + dashboard
        ├── gosecureshare-ui-recipient           Next.js 14 — /s/[uuid] share page
        ├── gosecureshare-api-platform           FastAPI — auth, secrets, admin
        └── gosecureshare-api-recipient          FastAPI — public reveal endpoint only
```

**Images pulled (6 unique, 8 containers):**

| Image | Source | Container name |
|---|---|---|
| `gosecureshare-api-platform:<ver>` | `ghcr.io/kisa-ops` | `gosecureshare-api-platform` |
| `gosecureshare-api-recipient:<ver>` | `ghcr.io/kisa-ops` | `gosecureshare-api-recipient` |
| `gosecureshare-frontend-platform:<ver>` | `ghcr.io/kisa-ops` | `gosecureshare-ui-platform` |
| `gosecureshare-frontend-recipient:<ver>` | `ghcr.io/kisa-ops` | `gosecureshare-ui-recipient` |
| `postgres:16-alpine` | Docker Hub | `gosecureshare-postgres` + `gosecureshare-db-migrate` |
| `nginx:1.27-alpine` | Docker Hub | `gosecureshare-nginx-platform` + `gosecureshare-nginx-recipient` |

---

## Post-Install Management

All commands run from `/opt/gosecureshare/`:

```bash
cd /opt/gosecureshare

# Upgrade to latest release
sudo ./upgrade.sh

# Upgrade to a specific version
sudo ./upgrade.sh 2.5.0

# Check container status
sudo docker compose ps

# Tail live logs
sudo docker compose logs -f

# Tail logs for a single service
sudo docker compose logs -f api_platform

# Stop the stack (data preserved)
sudo docker compose down

# Stop and DELETE all data ⚠️
sudo docker compose down -v
```

---

## Environment Variables Reference

All configuration is stored in `/opt/gosecureshare/.env` (auto-generated by `install.sh`).

| Variable | Required | Description |
|---|---|---|
| `POSTGRES_DB` | ✅ | Database name (`gosecureshare`) |
| `POSTGRES_USER` | ✅ | DB superuser |
| `POSTGRES_PASSWORD` | ✅ | DB superuser password |
| `GSS_PLATFORM_DB_USER` | ✅ | App role for platform API |
| `GSS_PLATFORM_DB_PASSWORD` | ✅ | Platform DB role password |
| `GSS_RECIPIENT_DB_USER` | ✅ | App role for recipient API |
| `GSS_RECIPIENT_DB_PASSWORD` | ✅ | Recipient DB role password |
| `ENCRYPTION_KEY` | ✅ | AES-256 key — 64 hex chars |
| `JWT_SECRET` | ✅ | JWT signing key |
| `GSS_ADMIN_EMAIL` | ✅ | Admin account email |
| `GSS_ADMIN_PASSWORD` | ✅ | Admin password (min 12 chars) |
| `PLATFORM_HTTP_PORT` | — | Platform port (default `80`) |
| `RECIPIENT_HTTP_PORT` | — | Recipient port (default `8181`) |
| `LDAP_ENABLED` | — | Enable LDAP/AD auth (`false`) |
| `DEBUG` | — | Enable debug mode — `false` in production |

> ⚠️ **Never share or commit `.env`.** It is `chmod 600` — readable only by root.

---

## Security Highlights

- 🔒 Every secret is encrypted with **AES-256-GCM** before storage — keys never leave the server
- 🔥 Burn-after-reading: secrets are deleted from the database immediately after first reveal
- 🧱 Recipient Nginx blocks all `/api/` admin routes — the admin interface is unreachable on port 8181
- 🔑 Passwords are hashed with **Argon2id**
- 🧹 Automatic retention sweeper deletes stale secrets (default: 14 days, configurable 1–90 days)
- 📋 All access attempts are logged to `gss_recipient.audit_logs`
- 🚫 Set `DEBUG=false` and restrict `CORS_ORIGINS_RAW` for production hardening

---

## Troubleshooting

**`permission denied` on Docker socket?**

```bash
# Always prefix with sudo, or add your user to the docker group:
sudo usermod -aG docker $USER && newgrp docker
```

**Containers not starting?**
```bash
sudo docker compose -f /opt/gosecureshare/docker-compose.yml logs
```

**Port conflict?**
```bash
lsof -i :80
lsof -i :8181
```
Re-run `install.sh` and choose different ports, or edit `PLATFORM_HTTP_PORT` / `RECIPIENT_HTTP_PORT` in `.env`.

**GHCR pull failed?**

Images may be private. Re-run with credentials and the early-abort flag:
```bash
export GHCR_USERNAME=your-github-username
export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
export GHCR_IMAGES_PRIVATE=true
sudo -E ./install.sh
```
Verify your PAT has the correct scopes: `read:packages` for images, `repo` if the source repo is also private.

**DB file fetch failed (private repo)?**

If `init.sql` or `docker-migrate.sh` could not be fetched, check that your token has `repo` scope (not just `read:packages`):
```bash
export GHCR_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx   # must have: read:packages + repo
sudo -E ./install.sh
```

**API container unhealthy?**
```bash
curl http://localhost/healthz
# → {"ok": true}
```

**Login fails after fresh install?**
```bash
# 1. Check migration completed cleanly
sudo docker logs gosecureshare-db-migrate

# 2. Check API started correctly
sudo docker logs gosecureshare-api-platform | grep -i seed

# 3. Full clean reinstall
cd /opt/gosecureshare && sudo docker compose down -v
sudo rm -rf /opt/gosecureshare
# Then re-run: sudo ./install.sh
```

---

<p align="center">
  Built with ❤️ by the <a href="https://gosecureshare.com">GoSecureShare</a> team.
</p>
