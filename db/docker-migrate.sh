#!/bin/sh
# =============================================================================
# docker-migrate.sh — AUTHORITATIVE DB BOOTSTRAP
#
# Single source of truth. Runs on every `docker compose up` via db-migrate
# init container. Every operation is fully idempotent.
#
# Derived directly from Python ORM models (models/*.py) — keep in sync.
#
# Tables created:
#   gss_platform  → schema_migrations, users, role_definitions, secret_controls,
#                    audit_logs, user_audit_logs, platform_settings
#   gss_recipient → secrets, retrieval_logs
# =============================================================================
set -e

# ---------------------------------------------------------------------------
# SCHEMA VERSION — bump this whenever the DB schema changes.
# Format: MAJOR.MINOR.PATCH  (same SemVer conventions as INSTALLER_VERSION)
#   MAJOR — destructive changes (column renames, table drops)
#   MINOR — additive changes (new tables, new columns with defaults)
#   PATCH — grant/ownership fixes, index additions, data-only changes
#
# This value is:
#   • Echoed at start so every docker compose up log shows the schema version
#   • Recorded in gss_platform.schema_migrations as 'schema-version-<VER>'
#     so you can query it at any time:
#       SELECT filename, applied_at FROM gss_platform.schema_migrations
#       WHERE filename LIKE 'schema-version-%' ORDER BY applied_at DESC LIMIT 1;
# ---------------------------------------------------------------------------
SCHEMA_VERSION="1.1.0"

PGHOST="${POSTGRES_HOST:-postgres}"
PGPORT=5432
PGUSER="$POSTGRES_USER"
PGDB="$POSTGRES_DB"
PLAT="$GSS_PLATFORM_DB_USER"
PLAT_PW="$GSS_PLATFORM_DB_PASSWORD"
RECP="$GSS_RECIPIENT_DB_USER"
RECP_PW="$GSS_RECIPIENT_DB_PASSWORD"

run()  { psql -h "$PGHOST" -p $PGPORT -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 "$@"; }
run0() { psql -h "$PGHOST" -p $PGPORT -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=0 "$@"; }

echo "[migrate] ============================================================"
echo "[migrate] GoSecureShare DB Bootstrap  —  schema version: ${SCHEMA_VERSION}"
echo "[migrate] ============================================================"
echo "[migrate] Waiting for PostgreSQL..."
until pg_isready -h "$PGHOST" -p $PGPORT -U "$PGUSER"; do sleep 1; done
echo "[migrate] PostgreSQL is ready."

# ---------------------------------------------------------------------------
# Step 1: Roles
# ---------------------------------------------------------------------------
echo "[migrate] Step 1: Roles"
run <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${PLAT}') THEN
    CREATE ROLE "${PLAT}" LOGIN PASSWORD '${PLAT_PW}';
    RAISE NOTICE 'Created role: ${PLAT}';
  END IF;
END \$\$;
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${RECP}') THEN
    CREATE ROLE "${RECP}" LOGIN PASSWORD '${RECP_PW}';
    RAISE NOTICE 'Created role: ${RECP}';
  END IF;
END \$\$;
SQL

# ---------------------------------------------------------------------------
# Step 2: Password sync (always apply from .env)
# ---------------------------------------------------------------------------
echo "[migrate] Step 2: Password sync"
run -c "ALTER ROLE \"${PLAT}\" PASSWORD '${PLAT_PW}';" \
    -c "ALTER ROLE \"${RECP}\" PASSWORD '${RECP_PW}';"

# ---------------------------------------------------------------------------
# Step 3: Schemas
# ---------------------------------------------------------------------------
echo "[migrate] Step 3: Schemas"
run -c "CREATE SCHEMA IF NOT EXISTS gss_platform;" \
    -c "CREATE SCHEMA IF NOT EXISTS gss_recipient;"

# ---------------------------------------------------------------------------
# Step 4: Tables — exact match to Python ORM models
# ---------------------------------------------------------------------------
echo "[migrate] Step 4: Tables"
run <<'SQL'

-- ── gss_platform.schema_migrations ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gss_platform.schema_migrations (
    filename   TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── gss_platform.users  (models/user.py) ──────────────────────────────────
-- users.id is BIGSERIAL to match secrets.creator_id BIGINT FK (FIX-7/FIX-10)
CREATE TABLE IF NOT EXISTS gss_platform.users (
    id                       BIGSERIAL    PRIMARY KEY,
    email                    VARCHAR      NOT NULL,
    hashed_password          VARCHAR      NOT NULL,
    name                     VARCHAR(120),
    role                     VARCHAR      NOT NULL DEFAULT 'viewer',
    is_active                BOOLEAN      NOT NULL DEFAULT TRUE,
    description              VARCHAR(500),
    last_login               TIMESTAMPTZ,
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
    mfa_secret               TEXT,
    mfa_enabled              BOOLEAN      NOT NULL DEFAULT FALSE,
    mfa_backup_codes         TEXT,
    failed_password_attempts INTEGER      NOT NULL DEFAULT 0,
    password_locked_until    TIMESTAMPTZ,
    CONSTRAINT uq_users_email UNIQUE (email)
);
CREATE INDEX IF NOT EXISTS ix_users_id    ON gss_platform.users (id);
CREATE INDEX IF NOT EXISTS ix_users_email ON gss_platform.users (email);

-- ── gss_platform.role_definitions  (models/role_definition.py) ────────────
CREATE TABLE IF NOT EXISTS gss_platform.role_definitions (
    id                     SERIAL      PRIMARY KEY,
    name                   VARCHAR(80) NOT NULL,
    description            TEXT,
    is_builtin             BOOLEAN     NOT NULL DEFAULT FALSE,
    is_default             BOOLEAN     NOT NULL DEFAULT FALSE,
    can_create_secret      BOOLEAN     NOT NULL DEFAULT TRUE,
    can_manage_secret      BOOLEAN     NOT NULL DEFAULT TRUE,
    can_view_audit         BOOLEAN     NOT NULL DEFAULT FALSE,
    can_upload_file        BOOLEAN     NOT NULL DEFAULT FALSE,
    can_set_passphrase     BOOLEAN     NOT NULL DEFAULT TRUE,
    can_set_ip_whitelist   BOOLEAN     NOT NULL DEFAULT TRUE,
    can_burn_after_reading BOOLEAN     NOT NULL DEFAULT TRUE,
    can_view_all_secrets   BOOLEAN     NOT NULL DEFAULT FALSE,
    can_revoke_any_secret  BOOLEAN     NOT NULL DEFAULT FALSE,
    max_views_cap          INTEGER,
    expiry_days_cap        INTEGER,
    default_max_views      INTEGER,
    default_expiry_days    INTEGER,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_role_definitions_name UNIQUE (name)
);
CREATE INDEX IF NOT EXISTS ix_role_definitions_id ON gss_platform.role_definitions (id);

-- ── gss_platform.secret_controls  (models/role_definition.py: SecretControl)
CREATE TABLE IF NOT EXISTS gss_platform.secret_controls (
    id      SERIAL      PRIMARY KEY,
    role_id INTEGER     NOT NULL
                REFERENCES gss_platform.role_definitions (id) ON DELETE CASCADE,
    control VARCHAR(60) NOT NULL,
    CONSTRAINT uq_secret_controls_role_control UNIQUE (role_id, control)
);
CREATE INDEX IF NOT EXISTS ix_secret_controls_id ON gss_platform.secret_controls (id);

-- ── gss_platform.audit_logs  (models/audit.py) ────────────────────────────
CREATE TABLE IF NOT EXISTS gss_platform.audit_logs (
    id          BIGSERIAL   PRIMARY KEY,
    secret_uuid UUID,
    actor_uuid  UUID,
    actor_type  VARCHAR     NOT NULL DEFAULT 'user',
    ip_address  INET,
    action      VARCHAR     NOT NULL,
    success     BOOLEAN     NOT NULL DEFAULT TRUE,
    detail      JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── gss_platform.user_audit_logs  (models/user_audit.py) ─────────────────
-- FIX: actor_id and target_user_id are BIGINT to match users.id (BIGSERIAL).
--      INTEGER FK referencing a BIGINT PK causes implicit cast overhead and
--      FK violations on large IDs (> 2^31).
CREATE TABLE IF NOT EXISTS gss_platform.user_audit_logs (
    id             BIGSERIAL    PRIMARY KEY,
    actor_id       BIGINT       REFERENCES gss_platform.users (id) ON DELETE SET NULL,
    target_user_id BIGINT       REFERENCES gss_platform.users (id) ON DELETE SET NULL,
    action         VARCHAR(64)  NOT NULL,
    ip_address     INET,
    user_agent     VARCHAR(512),
    source         VARCHAR(64),
    success        BOOLEAN      NOT NULL DEFAULT TRUE,
    detail         JSONB,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_user_audit_logs_action     ON gss_platform.user_audit_logs (action);
CREATE INDEX IF NOT EXISTS ix_user_audit_logs_created_at ON gss_platform.user_audit_logs (created_at);

-- ── gss_platform.platform_settings  (models/platform_settings.py) ─────────
-- Key/value store for runtime feature flags (e.g. mfa_required)
CREATE TABLE IF NOT EXISTS gss_platform.platform_settings (
    key        VARCHAR(120) PRIMARY KEY,
    value      VARCHAR      NOT NULL,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ── gss_recipient.secrets  (models/secret.py) ────────────────────────────
-- original_file_name: DB column name is original_file_name (underscore)
--   ORM maps: original_filename = Column(..., name='original_file_name')
--   Using wrong name (original_filename) caused UndefinedColumnError (FIX-5)
CREATE TABLE IF NOT EXISTS gss_recipient.secrets (
    id                      BIGSERIAL    PRIMARY KEY,
    uuid                    UUID         NOT NULL UNIQUE,
    creator_id              BIGINT       REFERENCES gss_platform.users (id),
    content_type            VARCHAR(10)  NOT NULL,
    encrypted_payload       TEXT,
    encryption_iv           VARCHAR(64),
    kms_key_id              VARCHAR(255),
    encrypted_text_payload  TEXT,
    encryption_text_iv      VARCHAR(64),
    encrypted_file_payload  TEXT,
    encryption_file_iv      VARCHAR(64),
    vault_file_path         VARCHAR(512),
    original_file_name      VARCHAR(255),
    file_mime_type          VARCHAR(128),
    is_client_encrypted     BOOLEAN      NOT NULL DEFAULT FALSE,
    secret_label            VARCHAR(255),
    has_passphrase          BOOLEAN      NOT NULL DEFAULT FALSE,
    passphrase_hash         VARCHAR(255),
    expires_at              TIMESTAMPTZ,
    max_views               BIGINT,
    burn_after_reading      BOOLEAN      NOT NULL DEFAULT FALSE,
    allowed_ips             JSONB,
    is_active               BOOLEAN      NOT NULL DEFAULT TRUE,
    views_count             BIGINT       NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ,
    deletion_reason         VARCHAR(64)
);
CREATE INDEX IF NOT EXISTS ix_secrets_id         ON gss_recipient.secrets (id);
CREATE INDEX IF NOT EXISTS ix_secrets_uuid       ON gss_recipient.secrets (uuid);
CREATE INDEX IF NOT EXISTS ix_secrets_creator_id ON gss_recipient.secrets (creator_id);
CREATE INDEX IF NOT EXISTS ix_secrets_expires_at ON gss_recipient.secrets (expires_at);

-- ── gss_recipient.retrieval_logs  (models/retrieval_log.py) ──────────────
CREATE TABLE IF NOT EXISTS gss_recipient.retrieval_logs (
    id             BIGSERIAL   PRIMARY KEY,
    secret_uuid    UUID        NOT NULL,
    ip_address     INET,
    user_agent     VARCHAR,
    success        BOOLEAN     NOT NULL DEFAULT TRUE,
    failure_reason VARCHAR,
    detail         JSONB,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_retrieval_logs_secret_uuid ON gss_recipient.retrieval_logs (secret_uuid);
CREATE INDEX IF NOT EXISTS ix_retrieval_logs_created_at  ON gss_recipient.retrieval_logs (created_at);

SQL

# ---------------------------------------------------------------------------
# Step 5: Ownership + grants + default privileges
# ---------------------------------------------------------------------------
echo "[migrate] Step 5: Ownership + grants"
run0 <<SQL

ALTER SCHEMA gss_platform  OWNER TO "${PLAT}";
ALTER SCHEMA gss_recipient OWNER TO "${RECP}";

DO \$\$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables
           WHERE schemaname = 'gss_platform' AND tableowner <> '${PLAT}'
  LOOP
    EXECUTE format('ALTER TABLE gss_platform.%I OWNER TO "${PLAT}"', r.tablename);
  END LOOP;
  FOR r IN SELECT tablename FROM pg_tables
           WHERE schemaname = 'gss_recipient' AND tableowner <> '${RECP}'
  LOOP
    EXECUTE format('ALTER TABLE gss_recipient.%I OWNER TO "${RECP}"', r.tablename);
  END LOOP;
END;
\$\$;

GRANT USAGE ON SCHEMA gss_platform  TO "${PLAT}";
GRANT USAGE ON SCHEMA gss_recipient TO "${PLAT}";
GRANT USAGE ON SCHEMA gss_recipient TO "${RECP}";

GRANT ALL ON ALL TABLES    IN SCHEMA gss_platform  TO "${PLAT}";
GRANT ALL ON ALL SEQUENCES IN SCHEMA gss_platform  TO "${PLAT}";
GRANT ALL ON ALL TABLES    IN SCHEMA gss_recipient TO "${PLAT}";
GRANT ALL ON ALL SEQUENCES IN SCHEMA gss_recipient TO "${PLAT}";
GRANT ALL ON ALL TABLES    IN SCHEMA gss_recipient TO "${RECP}";
GRANT ALL ON ALL SEQUENCES IN SCHEMA gss_recipient TO "${RECP}";

GRANT ALL ON TABLE gss_platform.schema_migrations TO "${PLAT}";
GRANT ALL ON TABLE gss_platform.schema_migrations TO "${RECP}";

ALTER DEFAULT PRIVILEGES FOR ROLE "${PLAT}" IN SCHEMA gss_platform
  GRANT ALL ON TABLES TO "${PLAT}";
ALTER DEFAULT PRIVILEGES FOR ROLE "${PLAT}" IN SCHEMA gss_platform
  GRANT ALL ON SEQUENCES TO "${PLAT}";

ALTER DEFAULT PRIVILEGES FOR ROLE "${RECP}" IN SCHEMA gss_recipient
  GRANT ALL ON TABLES    TO "${PLAT}";
ALTER DEFAULT PRIVILEGES FOR ROLE "${RECP}" IN SCHEMA gss_recipient
  GRANT ALL ON SEQUENCES TO "${PLAT}";
ALTER DEFAULT PRIVILEGES FOR ROLE "${RECP}" IN SCHEMA gss_recipient
  GRANT ALL ON TABLES    TO "${RECP}";
ALTER DEFAULT PRIVILEGES FOR ROLE "${RECP}" IN SCHEMA gss_recipient
  GRANT ALL ON SEQUENCES TO "${RECP}";

SQL

# ---------------------------------------------------------------------------
# Step 6: Seed built-in roles
# ---------------------------------------------------------------------------
echo "[migrate] Step 6: Seed built-in roles"
run <<'SQL'
INSERT INTO gss_platform.role_definitions
  (name, description, is_builtin, is_default,
   can_create_secret, can_manage_secret, can_view_audit,
   can_upload_file,   can_set_passphrase, can_set_ip_whitelist,
   can_burn_after_reading, can_view_all_secrets, can_revoke_any_secret)
VALUES
  ('admin',  'Full platform access', TRUE, TRUE,
   TRUE, TRUE, TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  TRUE),
  ('user',   'Standard user',        TRUE, TRUE,
   TRUE, TRUE, FALSE, FALSE, TRUE,  TRUE,  TRUE,  FALSE, FALSE),
  ('viewer', 'Read-only observer',   TRUE, TRUE,
   FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE)
ON CONFLICT (name) DO NOTHING;
SQL

# ---------------------------------------------------------------------------
# Step 7: Seed platform_settings defaults
# ---------------------------------------------------------------------------
echo "[migrate] Step 7: Seed platform settings"
run <<'SQL'
INSERT INTO gss_platform.platform_settings (key, value)
VALUES
  ('mfa_required',            'false'),
  ('allow_anonymous_secrets', 'true'),
  ('max_secret_size_kb',      '10240')
ON CONFLICT (key) DO NOTHING;
SQL

# ---------------------------------------------------------------------------
# Step 8: Seed admin user (optional — requires ADMIN_EMAIL + ADMIN_HASHED_PASSWORD)
# NOTE: ADMIN_HASHED_PASSWORD MUST be an Argon2 hash.
#       install.sh produces this via: passlib CryptContext(schemes=['argon2'])
# ---------------------------------------------------------------------------
if [ -n "${ADMIN_EMAIL}" ] && [ -n "${ADMIN_HASHED_PASSWORD}" ]; then
  echo "[migrate] Step 8: Upsert admin user (${ADMIN_EMAIL})"
  run <<SQL
INSERT INTO gss_platform.users
  (email, hashed_password, name, role, is_active)
VALUES
  ('${ADMIN_EMAIL}', '${ADMIN_HASHED_PASSWORD}', 'Administrator', 'admin', TRUE)
ON CONFLICT (email) DO UPDATE
  SET hashed_password = EXCLUDED.hashed_password,
      role            = 'admin',
      is_active       = TRUE;
SQL
else
  echo "[migrate] Step 8: ADMIN_EMAIL or ADMIN_HASHED_PASSWORD not set — skipping."
fi

# ---------------------------------------------------------------------------
# Step 9: Record in migration tracking table
# Records both the script name (idempotent marker) and the current schema
# version so you can always query which version is running:
#   SELECT filename, applied_at
#   FROM gss_platform.schema_migrations
#   WHERE filename LIKE 'schema-version-%'
#   ORDER BY applied_at DESC LIMIT 1;
# ---------------------------------------------------------------------------
echo "[migrate] Step 9: Recording migration markers"
run <<SQL
INSERT INTO gss_platform.schema_migrations (filename)
  VALUES ('docker-migrate.sh')
  ON CONFLICT DO NOTHING;
INSERT INTO gss_platform.schema_migrations (filename, applied_at)
  VALUES ('schema-version-${SCHEMA_VERSION}', now())
  ON CONFLICT (filename) DO UPDATE SET applied_at = now();
SQL

echo "[migrate] ============================================================"
echo "[migrate] Bootstrap complete.  Schema version: ${SCHEMA_VERSION}"
echo "[migrate] ============================================================"
