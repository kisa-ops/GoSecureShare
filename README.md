<p align="center">
  <a href="https://gosecureshare.com">
    <img src="./assets/logo/gss-shield-dark.svg" alt="GoSecureShare" width="100" />
  </a>
</p>

<h1 align="center">GoSecureShare</h1>

<p align="center">
  Enterprise-grade, self-hosted <strong>zero-knowledge secret sharing</strong>.<br/>
  Share passwords, API keys, and sensitive files via one-time secure links &mdash;<br/>
  fully self-contained with Docker Compose. No cloud dependency. No data leaves your server.
</p>

<p align="center">
  <a href="https://gosecureshare.com">🌐 gosecureshare.com</a>
</p>

---

## Table of Contents

1. [What You Need](#what-you-need)
2. [Prerequisites](#prerequisites)
3. [Quick Install](#quick-install)
4. [Pin to a Specific Version](#pin-to-a-specific-version)
5. [SSL & Reverse Proxy](#ssl--reverse-proxy)
6. [GHCR Credentials](#ghcr-credentials)
7. [Administration](#administration)
   - [Directory Layout](#administration-directory-layout)
   - [Upgrade](#upgrading----upgradesh)
   - [Stop for Maintenance](#stopping-for-maintenance----stopsh)
   - [Start after Maintenance](#starting-after-maintenance----startsh)
   - [Backup & Restore](#backup--restore----backupsh)
   - [Quick Reference](#quick-reference)
8. [Clean Reinstall](#clean-reinstall)
9. [Container Architecture](#container-architecture)
10. [Environment Variables](#environment-variables-reference)
11. [Security Highlights](#security-highlights)
12. [Troubleshooting](#troubleshooting)

---

## What You Need

Just **one file**. The installer is self-bootstrapping &mdash; it auto-fetches all required
library modules from GitHub before installation begins.

```
kisa-ops/GoSecureShare
└── install.sh    ← The only file you need to download
```

> The installer downloads its own `lib/` modules and `db/` files directly from GitHub
> during setup, using the GitHub PAT you provide at the start of the interactive wizard.

---

## Prerequisites

| Requirement           | Minimum version | How to install                                 |
|-----------------------|-----------------|------------------------------------------------|
| Docker Engine         | 24+             | `curl -fsSL https://get.docker.com \| sh`      |
| Docker Compose plugin | v2              | `apt-get install -y docker-compose-plugin`     |
| `curl`                | any             | `apt-get install -y curl`                      |
| `openssl`             | any             | `apt-get install -y openssl`                   |

> **PostgreSQL is not required on the host.** It runs as a dedicated container inside
> the Docker stack.

> ⚠️ All `docker` commands require `sudo` unless your user has been added to the `docker`
> group (`sudo usermod -aG docker $USER`).

---

## Quick Install

### 1 &mdash; Download the installer

```bash
mkdir gosecureshare && cd gosecureshare
curl -fsSL https://raw.githubusercontent.com/kisa-ops/GoSecureShare/main/install.sh -o install.sh
chmod +x install.sh
```

> If the repository is **private**, add `-H "Authorization: Bearer <your-token>"` to the
> `curl` command above, or transfer the file to the server via SFTP.

### 2 &mdash; Run the installer

```bash
sudo ./install.sh
```

The interactive wizard guides you through every step:

1. ✅ **GHCR credentials** &mdash; prompted first; your GitHub PAT (`read:packages` scope)
   is used to pull images and to bootstrap the `lib/` modules from GitHub
2. ✅ **Prerequisites** &mdash; Docker, Compose, `curl`, and `openssl` are verified
3. 🔍 **Version** &mdash; latest stable release auto-detected from GitHub Releases
   (override: `GSS_VERSION=x.y.z sudo ./install.sh`)
4. 🐳 **Image pull** &mdash; all 6 container images pulled from GHCR and Docker Hub
5. 📁 **Install directory** &mdash; `/opt/gosecureshare/` created with all runtime files
6. 🔗 **DB files** &mdash; `db/init.sql` and `db/docker-migrate.sh` fetched from GitHub
7. ⚙️  **Configuration** &mdash; ports, admin email, and admin password prompted interactively
8. 🔐 **Secrets** &mdash; AES-256 encryption key, JWT secret, and DB passwords auto-generated
9. 🔒 **SSL** &mdash; choose between your own reverse proxy or providing certificate
   files for host-level Nginx TLS termination
10. 📝 **`.env` written** &mdash; secured at `/opt/gosecureshare/.env` (`chmod 600`, root-only)
11. 🚀 **Stack started** &mdash; all 8 containers started via Docker Compose
12. ⏳ **DB migration** &mdash; idempotent schema bootstrap waits to complete
13. ❤️  **Health checks** &mdash; all containers polled until healthy
14. ✔️  **Login verified** &mdash; platform login endpoint confirmed reachable before success

### 3 &mdash; Open in your browser

After installation, the summary screen displays your URLs:

| Interface                    | Default internal port | Purpose                                             |
|------------------------------|-----------------------|-----------------------------------------------------|
| **Platform** (Admin / Staff) | `8181`                | Login &middot; create secrets &middot; admin dashboard |
| **Recipient Portal**         | `80`                  | View a shared one-time secret link                  |

> These internal ports sit **behind your reverse proxy or host Nginx**, which terminates
> TLS and forwards to them. See [SSL & Reverse Proxy](#ssl--reverse-proxy) below.

---

## Pin to a Specific Version

```bash
GSS_VERSION=2.3.1 sudo ./install.sh
```

Version pinning controls which GHCR image tags are pulled:

```
ghcr.io/kisa-ops/gosecureshare-api-platform:2.3.1
ghcr.io/kisa-ops/gosecureshare-api-recipient:2.3.1
ghcr.io/kisa-ops/gosecureshare-frontend-platform:2.3.1
ghcr.io/kisa-ops/gosecureshare-frontend-recipient:2.3.1
```

---

## SSL & Reverse Proxy

The installer presents two SSL options during setup:

### Option A &mdash; Your own reverse proxy *(recommended)*

Choose this if you already have Cloudflare, Nginx, HAProxy, or any other TLS-terminating
proxy in front of the server. Docker binds its ports to `127.0.0.1` only; your proxy
handles HTTPS and forwards traffic:

| Proxy target                 | Internal address         |
|------------------------------|--------------------------|
| Platform (admin / staff UI)  | `http://127.0.0.1:8181`  |
| Recipient (share portal)     | `http://127.0.0.1:80`    |

### Option B &mdash; Provide certificate files

Choose this if GoSecureShare manages TLS directly on the host. The installer configures
a host Nginx instance as a TLS terminator. You will be prompted to provide a certificate,
private key, and (optionally) a CA bundle &mdash; either as a file path or by pasting the
PEM content &mdash; separately for the Platform and Recipient endpoints.

---

## GHCR Credentials

GoSecureShare images are hosted on GitHub Container Registry (GHCR). A GitHub Personal
Access Token (PAT) is **required** and is collected interactively at the start of the
installer. There is no way to skip this step.

### Required PAT scopes

| Scope           | Required for                                                            |
|-----------------|-------------------------------------------------------------------------|
| `read:packages` | Pulling container images from `ghcr.io/kisa-ops`                       |
| `repo`          | Fetching `lib/` and `db/` files when the source repository is private  |

> If images are public but the source repo is private, include both scopes.
> If only images are private, `read:packages` alone is sufficient.

### Generate a PAT

Go to **GitHub &rarr; Settings &rarr; Developer settings &rarr; Personal access tokens
(classic)** and create a token with the scopes above. Paste it when prompted by the
installer.

---

## Administration

All day-to-day administration is performed using the management scripts installed at
`/opt/gosecureshare/`. Always run them as `root` from that directory.

> ⚠️ **Golden rule:** Never use `git pull` on a production server. All changes are
> applied through `install.sh` (fresh install) or `upgrade.sh` (existing install).

### Administration Directory Layout

```
/opt/gosecureshare/
├── .env                        ← All secrets & config  (chmod 600, root-only)
├── docker-compose.yml          ← Generated by install.sh — do not edit manually
├── upgrade.sh                  ← Upgrade to a newer version (auto-rollback on failure)
├── stop.sh                     ← Graceful shutdown for maintenance windows
├── start.sh                    ← Start / resume after maintenance
├── backup.sh                   ← Full backup: database + config + scripts
├── db/
│   ├── docker-migrate.sh       ← Idempotent DB schema bootstrap (runs on every up)
│   └── init.sql                ← Intentional no-op (schema managed by docker-migrate.sh)
├── nginx/
│   ├── platform.conf           ← Nginx reverse proxy config for Platform UI
│   └── recipient.conf          ← Nginx reverse proxy config for Recipient portal
└── backups/                    ← Timestamped backup archives (auto-pruned)
    └── gss-backup-<ver>-<ts>.tar.gz
```

---

### Upgrading &mdash; `upgrade.sh`

`upgrade.sh` upgrades GoSecureShare with full safety guarantees. If health checks fail
after applying new images, it **automatically rolls back** to the previously running version.

#### Safety steps

| Step | What happens                                                                            |
|------|-----------------------------------------------------------------------------------------|
| 1    | Pre-flight: Docker daemon running, ≥2 GB free disk, GHCR reachable, stack running      |
| 2    | Snapshot: `docker-compose.yml` and `.env` copied to `.upgrade-snapshot/`               |
| 3    | DB backup: full `pg_dump` written to `.upgrade-snapshot/db-backup-<version>.sql`       |
| 4    | Pull first: all 4 new images pulled completely before the live stack is touched         |
| 5    | Apply: image tags patched in `docker-compose.yml`, stack restarted                     |
| 6    | Health checks: all 4 app containers polled (120 s timeout per container)               |
| 7    | Auto-rollback: on any failure, snapshot restored and old images re-applied             |
| 8    | Version pin: `GSS_INSTALLED_VERSION` in `.env` updated only after all checks pass      |

#### Usage

```bash
cd /opt/gosecureshare

# Upgrade to the latest stable release
sudo ./upgrade.sh

# Upgrade to a specific version
sudo ./upgrade.sh 2.5.0
```

> The installer prompts for your GitHub PAT during the upgrade if GHCR credentials are
> needed to pull the new images.

#### Preserved files after a successful upgrade

```
/opt/gosecureshare/.upgrade-snapshot/
├── docker-compose.yml.<previous-version>   ← previous compose file
├── .env.<previous-version>                 ← previous .env  (chmod 600)
└── db-backup-<previous-version>.sql        ← full database dump
```

These files are **never automatically deleted** &mdash; keep them until you are confident
the upgrade is stable.

#### Manual rollback

```bash
# 1. Restore configuration files
cp /opt/gosecureshare/.upgrade-snapshot/docker-compose.yml.<version> \
   /opt/gosecureshare/docker-compose.yml
cp /opt/gosecureshare/.upgrade-snapshot/.env.<version> \
   /opt/gosecureshare/.env
chmod 600 /opt/gosecureshare/.env

# 2. Restart on the old version
cd /opt/gosecureshare && sudo docker compose up -d

# 3. Optionally restore the database
docker exec -i gosecureshare-postgres psql -U gss_superuser gosecureshare \
  < /opt/gosecureshare/.upgrade-snapshot/db-backup-<version>.sql
```

---

### Stopping for Maintenance &mdash; `stop.sh`

`stop.sh` gracefully shuts down the entire stack in the correct order, ensuring no data
is lost and in-flight requests are drained before containers stop.

#### Shutdown sequence

| Step | Action                                                                                      |
|------|---------------------------------------------------------------------------------------------|
| 1    | Stops host Nginx (if running in SSL cert mode); leaves a marker for `start.sh`             |
| 2    | Waits a drain period for in-flight requests to complete (default: 10 s)                    |
| 3    | Stops app containers in safe order: nginx &rarr; frontend &rarr; API                       |
| 4    | Stops PostgreSQL last, after all app containers are fully down                             |
| 5    | Prints final `docker compose ps` status table                                               |

```bash
cd /opt/gosecureshare

# Standard graceful stop
sudo ./stop.sh

# Skip drain wait (emergency stop)
GSS_DRAIN_SECONDS=0 sudo ./stop.sh

# Longer drain for busy servers
GSS_DRAIN_SECONDS=30 sudo ./stop.sh
```

> PostgreSQL volumes are **not** removed. All data is fully preserved.

---

### Starting after Maintenance &mdash; `start.sh`

`start.sh` starts the full stack and confirms all services are healthy before returning
control to the terminal.

#### Startup sequence

| Step | Action                                                                                      |
|------|---------------------------------------------------------------------------------------------|
| 1    | Pre-flight: Docker daemon running, `.env` and `docker-compose.yml` present                 |
| 2    | `docker compose up -d` &mdash; starts all containers                                        |
| 3    | Resumes host Nginx if the `stop.sh` marker is present; runs `nginx -t` first              |
| 4    | Polls all 4 app containers until healthy (120 s timeout); exits with error if any fail    |
| 5    | Prints Platform and Recipient access URLs on success                                        |

```bash
cd /opt/gosecureshare && sudo ./start.sh
```

#### Typical maintenance window workflow

```bash
# 1. Back up before starting work
sudo ./backup.sh

# 2. Stop the stack
sudo ./stop.sh

# 3. Perform maintenance (OS patches, disk resize, certificate renewal, etc.)

# 4. Start the stack and verify health
sudo ./start.sh
```

---

### Backup & Restore &mdash; `backup.sh`

`backup.sh` creates a complete, timestamped, self-contained backup archive. The archive
holds everything needed to fully restore a fresh installation from scratch.

#### What is backed up

| Artifact              | File in archive                                           | Notes                             |
|-----------------------|-----------------------------------------------------------|-----------------------------------|
| Database              | `database.sql.gz`                                         | Full `pg_dump`, gzip-compressed   |
| Environment           | `config/.env`                                             | `chmod 600` preserved in archive  |
| Compose file          | `config/docker-compose.yml`                               | Exact image tags and port config  |
| Nginx configs         | `config/nginx/platform.conf`, `recipient.conf`            | Reverse proxy routing rules       |
| DB bootstrap          | `db/docker-migrate.sh`, `db/init.sql`                     | Schema + seed for a fresh DB      |
| Management scripts    | `scripts/upgrade.sh`, `start.sh`, `stop.sh`, `backup.sh` | All admin scripts                 |
| Manifest              | `MANIFEST.txt`                                            | Version, timestamp, file list     |

#### Output location

```
/opt/gosecureshare/backups/
└── gss-backup-<version>-<timestamp>.tar.gz    ← chmod 600 (root-only)
```

#### Retention

Old archives are pruned automatically. Default: keep the **7 most recent**. Override:

```bash
cd /opt/gosecureshare

# Standard backup
sudo ./backup.sh

# Keep last 14 backups
GSS_BACKUP_KEEP=14 sudo ./backup.sh

# Write backups to an external mount
GSS_BACKUP_DIR=/mnt/nas/gss-backups sudo ./backup.sh

# Skip gzip compression (faster, larger files)
sudo ./backup.sh --no-compress
```

#### Automate with cron

Add to `/etc/cron.d/gosecureshare-backup` for a daily backup at 02:00:

```
0 2 * * * root /opt/gosecureshare/backup.sh >> /var/log/gss-backup.log 2>&1
```

#### Restoring the database

```bash
# 1. Extract the dump from the archive
tar -xzf /opt/gosecureshare/backups/gss-backup-2.5.0-20260716T020000Z.tar.gz \
    --strip-components=1 '*/database.sql.gz'

# 2. Decompress
gunzip database.sql.gz

# 3. Restore (stack must be running and PostgreSQL must be healthy)
docker exec -i gosecureshare-postgres psql \
    -U gss_superuser gosecureshare < database.sql
```

---

### Quick Reference

| Task                        | Command                                                  |
|-----------------------------|----------------------------------------------------------|
| **Upgrade to latest**       | `cd /opt/gosecureshare && sudo ./upgrade.sh`             |
| **Upgrade to version**      | `sudo ./upgrade.sh 2.5.0`                                |
| **Stop for maintenance**    | `sudo ./stop.sh`                                         |
| **Start after maintenance** | `sudo ./start.sh`                                        |
| **Take a manual backup**    | `sudo ./backup.sh`                                       |
| **Check container status**  | `sudo docker compose ps`                                 |
| **Tail all logs**           | `sudo docker compose logs -f`                            |
| **Tail one service**        | `sudo docker compose logs -f api_platform`               |
| **View DB migration log**   | `sudo docker logs gosecureshare-db-migrate`              |
| **Health check (recipient)**| `curl http://localhost:80/healthz`                       |
| **Restart single container**| `sudo docker compose restart api_platform`               |
| **Open DB shell**           | `sudo docker exec -it gosecureshare-postgres psql -U gss_superuser gosecureshare` |

---

## Clean Reinstall

### 1 &mdash; Back up first

```bash
cd /opt/gosecureshare && sudo ./backup.sh
```

> Always take a backup before wiping. The archive is self-contained and can restore
> a fresh server to the same state.

### 2 &mdash; Stop and wipe the old installation

```bash
cd /opt/gosecureshare
sudo docker compose down -v
```

> ⚠️ The `-v` flag removes all Docker volumes, including PostgreSQL data. This is required
> so the database migration and admin seed scripts run clean on the next install.

### 3 &mdash; Remove the install directory

```bash
sudo rm -rf /opt/gosecureshare
```

### 4 &mdash; Remove old images *(optional but recommended)*

```bash
sudo docker rmi $(sudo docker images --format '{{.ID}}' \
    --filter 'reference=*gosecureshare*') 2>/dev/null || true
sudo docker rmi postgres:16-alpine nginx:1.27-alpine 2>/dev/null || true
```

### 5 &mdash; Re-run the installer

```bash
cd ~/gosecureshare && sudo ./install.sh
```

### 6 &mdash; Verify after install

```bash
cd /opt/gosecureshare
sudo docker compose ps                       # all containers healthy / running
sudo docker logs gosecureshare-db-migrate    # should end with exit code 0
curl http://localhost:80/healthz             # → {"ok": true}
curl http://localhost:8181/healthz           # → {"ok": true}
```

---

## Container Architecture

```
Host machine
└── Docker Engine
    └── gss_internal  (bridge network — fully self-contained)
        ├── gosecureshare-postgres          :5434 (host) / :5432 (internal)
        ├── gosecureshare-db-migrate        runs once, then exits (exit 0)
        ├── gosecureshare-nginx-platform    :8181 (host) → Platform UI + API
        ├── gosecureshare-nginx-recipient   :80   (host) → Recipient share page
        ├── gosecureshare-ui-platform       Next.js 14 — login + admin dashboard
        ├── gosecureshare-ui-recipient      Next.js 14 — /s/[uuid] share page
        ├── gosecureshare-api-platform      FastAPI — auth, secrets, admin
        └── gosecureshare-api-recipient     FastAPI — public reveal endpoint only
```

**6 unique images, 8 containers:**

| Image                                    | Source             | Container name                                         |
|------------------------------------------|--------------------|--------------------------------------------------------|
| `gosecureshare-api-platform:<ver>`       | `ghcr.io/kisa-ops` | `gosecureshare-api-platform`                           |
| `gosecureshare-api-recipient:<ver>`      | `ghcr.io/kisa-ops` | `gosecureshare-api-recipient`                          |
| `gosecureshare-frontend-platform:<ver>`  | `ghcr.io/kisa-ops` | `gosecureshare-ui-platform`                            |
| `gosecureshare-frontend-recipient:<ver>` | `ghcr.io/kisa-ops` | `gosecureshare-ui-recipient`                           |
| `postgres:16-alpine`                     | Docker Hub         | `gosecureshare-postgres` + `gosecureshare-db-migrate`  |
| `nginx:1.27-alpine`                      | Docker Hub         | `gosecureshare-nginx-platform` + `gosecureshare-nginx-recipient` |

---

## Environment Variables Reference

All configuration is stored in `/opt/gosecureshare/.env`, auto-generated and secured by
`install.sh` (`chmod 600` &mdash; readable by root only).

| Variable                    | Required | Description                                           |
|-----------------------------|----------|-------------------------------------------------------|
| `POSTGRES_DB`               | ✅        | Database name (`gosecureshare`)                       |
| `POSTGRES_USER`             | ✅        | DB superuser username                                 |
| `POSTGRES_PASSWORD`         | ✅        | DB superuser password                                 |
| `GSS_PLATFORM_DB_USER`      | ✅        | Application role for the platform API                 |
| `GSS_PLATFORM_DB_PASSWORD`  | ✅        | Platform DB role password                             |
| `GSS_RECIPIENT_DB_USER`     | ✅        | Application role for the recipient API                |
| `GSS_RECIPIENT_DB_PASSWORD` | ✅        | Recipient DB role password                            |
| `ENCRYPTION_KEY`            | ✅        | AES-256 key &mdash; 64 hex characters, auto-generated |
| `JWT_SECRET`                | ✅        | JWT signing key, auto-generated                       |
| `GSS_ADMIN_EMAIL`           | ✅        | Admin account email address                           |
| `GSS_ADMIN_PASSWORD`        | ✅        | Admin password (minimum 12 characters)                |
| `GSS_INSTALLED_VERSION`     | ✅        | Version tag pinned after successful install/upgrade   |
| `PLATFORM_HTTP_PORT`        | &mdash;  | Platform internal port (default `8181`)               |
| `RECIPIENT_HTTP_PORT`       | &mdash;  | Recipient internal port (default `80`)                |
| `LDAP_ENABLED`              | &mdash;  | Enable LDAP / Active Directory auth (`false`)         |
| `DEBUG`                     | &mdash;  | Enable debug mode &mdash; always `false` in production |

> ⚠️ **Never share or commit `.env`.** It contains all secrets for your installation.

---

## Security Highlights

- 🔒 Every secret is encrypted with **AES-256-GCM** before storage &mdash; encryption keys
  never leave your server
- 🔥 **Burn-after-reading**: secrets are deleted from the database immediately after the
  first successful reveal
- 🧱 Recipient Nginx blocks all `/api/` admin routes &mdash; the admin interface is
  completely unreachable via the recipient portal port
- 🔑 Passwords are hashed with **Argon2id**
- 🧹 Automatic retention sweeper deletes stale secrets (default: 14 days, configurable
  1&ndash;90 days)
- 📋 All access attempts are written to `gss_recipient.audit_logs`
- 🚫 Set `DEBUG=false` and restrict `CORS_ORIGINS_RAW` for production hardening

---

## Troubleshooting

**`permission denied` on Docker socket**

```bash
sudo usermod -aG docker $USER && newgrp docker
```

**Containers not starting**

```bash
sudo docker compose -f /opt/gosecureshare/docker-compose.yml logs
```

**Port conflict**

```bash
sudo lsof -i :8181
sudo lsof -i :80
```

Re-run `install.sh` and choose different ports, or edit `PLATFORM_HTTP_PORT` /
`RECIPIENT_HTTP_PORT` in `.env` and restart:

```bash
sudo docker compose -f /opt/gosecureshare/docker-compose.yml up -d
```

**GHCR pull failed**

Images require a GitHub PAT with `read:packages` scope. The installer collects this
interactively. If a pull fails, verify your PAT has not expired and has the correct scope
at **GitHub &rarr; Settings &rarr; Developer settings &rarr; Personal access tokens**.

**DB file fetch failed**

If `init.sql` or `docker-migrate.sh` could not be fetched during bootstrap, verify your
PAT includes the `repo` scope in addition to `read:packages`, then re-run the installer:

```bash
sudo ./install.sh
```

**API container unhealthy**

```bash
curl http://localhost:80/healthz
# Expected response: {"ok": true}
```

**Login fails after fresh install**

```bash
# 1. Confirm DB migration completed cleanly
sudo docker logs gosecureshare-db-migrate

# 2. Confirm admin seed ran
sudo docker logs gosecureshare-api-platform | grep -i seed

# 3. If in doubt, perform a clean reinstall
cd /opt/gosecureshare && sudo docker compose down -v
sudo rm -rf /opt/gosecureshare
# Then re-run: sudo ./install.sh
```

**Certificate renewal (SSL cert mode)**

```bash
# Test Nginx config before reloading
nginx -t

# Reload Nginx to pick up the new certificate (zero downtime)
nginx -s reload
```

---

<p align="center">
  Built with ❤️ by the <a href="https://gosecureshare.com">GoSecureShare</a> team.
</p>
