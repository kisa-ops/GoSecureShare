#!/bin/sh
# =============================================================================
# db-validate.sh — Validate production DB structure matches Python ORM models
#
# Run after every deploy to confirm dev/prod parity.
#
# Usage (on prod server):
#   export $(grep -v '^#' /opt/gosecureshare/app/.env | xargs)
#   PGPASSWORD=$POSTGRES_PASSWORD sh production/db/db-validate.sh
#
# Or directly inside the postgres container:
#   sudo docker exec -i gosecureshare-postgres \
#     env POSTGRES_USER=... POSTGRES_DB=... \
#         GSS_PLATFORM_DB_USER=... GSS_RECIPIENT_DB_USER=... \
#     sh /db-validate.sh
#
# Exit codes: 0 = all passed, 1 = one or more failures
# =============================================================================

PGHOST="${POSTGRES_HOST:-localhost}"
PGPORT=5432
PGUSER="$POSTGRES_USER"
PGDB="$POSTGRES_DB"
PLAT="${GSS_PLATFORM_DB_USER:-gss_platform_user}"
RECP="${GSS_RECIPIENT_DB_USER:-gss_recipient_user}"

PASS=0
FAIL=0

_q() { psql -h "$PGHOST" -p $PGPORT -U "$PGUSER" -d "$PGDB" -tAc "$1" 2>/dev/null; }

check() {
  LABEL="$1"; SQL="$2"; WANT="$3"
  GOT=$(_q "$SQL")
  if [ "$GOT" = "$WANT" ]; then
    printf "  ✅  %s\n" "$LABEL"; PASS=$((PASS+1))
  else
    printf "  ❌  %s  (want='%s' got='%s')\n" "$LABEL" "$WANT" "$GOT"; FAIL=$((FAIL+1))
  fi
}

check_exists() {
  LABEL="$1"; SQL="$2"
  GOT=$(_q "$SQL")
  if [ -n "$GOT" ]; then
    printf "  ✅  %s\n" "$LABEL"; PASS=$((PASS+1))
  else
    printf "  ❌  %s  (not found)\n" "$LABEL"; FAIL=$((FAIL+1))
  fi
}

col() {
  SCH="$1"; TBL="$2"; COL="$3"
  check "$SCH.$TBL.$COL" \
    "SELECT column_name FROM information_schema.columns
     WHERE table_schema='$SCH' AND table_name='$TBL' AND column_name='$COL'" \
    "$COL"
}

echo ""
echo "═══════════════════════════════════════════════════"
echo "  GoSecureShare PRODUCTION DB Validation"
echo "  Host: $PGHOST   DB: $PGDB"
echo "═══════════════════════════════════════════════════"

echo ""
echo "── Connectivity ──"
check_exists "PostgreSQL reachable" "SELECT 1"

echo ""
echo "── Schemas ──"
check "gss_platform" \
  "SELECT schema_name FROM information_schema.schemata WHERE schema_name='gss_platform'" \
  "gss_platform"
check "gss_recipient" \
  "SELECT schema_name FROM information_schema.schemata WHERE schema_name='gss_recipient'" \
  "gss_recipient"

echo ""
echo "── Roles ──"
check "$PLAT role" "SELECT rolname FROM pg_roles WHERE rolname='$PLAT'" "$PLAT"
check "$RECP role" "SELECT rolname FROM pg_roles WHERE rolname='$RECP'" "$RECP"

echo ""
echo "── Tables (gss_platform) ──"
for t in schema_migrations users role_definitions secret_controls audit_logs user_audit_logs platform_settings; do
  check "gss_platform.$t" \
    "SELECT tablename FROM pg_tables WHERE schemaname='gss_platform' AND tablename='$t'" "$t"
done

echo ""
echo "── Tables (gss_recipient) ──"
for t in secrets retrieval_logs; do
  check "gss_recipient.$t" \
    "SELECT tablename FROM pg_tables WHERE schemaname='gss_recipient' AND tablename='$t'" "$t"
done

echo ""
echo "── Columns: users ──"
for c in id email hashed_password name role is_active description last_login \
         created_at updated_at mfa_secret mfa_enabled mfa_backup_codes \
         failed_password_attempts password_locked_until; do
  col gss_platform users "$c"
done

echo ""
echo "── Columns: role_definitions ──"
for c in id name description is_builtin is_default \
         can_create_secret can_manage_secret can_view_audit can_upload_file \
         can_set_passphrase can_set_ip_whitelist can_burn_after_reading \
         can_view_all_secrets can_revoke_any_secret \
         max_views_cap expiry_days_cap default_max_views default_expiry_days \
         created_at updated_at; do
  col gss_platform role_definitions "$c"
done

echo ""
echo "── Columns: secret_controls ──"
for c in id role_id control; do
  col gss_platform secret_controls "$c"
done

echo ""
echo "── Columns: audit_logs ──"
for c in id secret_uuid actor_uuid actor_type ip_address action success detail created_at; do
  col gss_platform audit_logs "$c"
done

echo ""
echo "── Columns: user_audit_logs ──"
for c in id actor_id target_user_id action ip_address user_agent source success detail created_at; do
  col gss_platform user_audit_logs "$c"
done

echo ""
echo "── Columns: platform_settings ──"
for c in key value updated_at; do
  col gss_platform platform_settings "$c"
done

echo ""
echo "── Columns: secrets ──"
for c in id uuid creator_id content_type \
         encrypted_payload encryption_iv kms_key_id \
         encrypted_text_payload encryption_text_iv \
         encrypted_file_payload encryption_file_iv \
         vault_file_path original_file_name file_mime_type \
         is_client_encrypted secret_label has_passphrase passphrase_hash \
         expires_at max_views burn_after_reading allowed_ips \
         is_active views_count created_at deleted_at deletion_reason; do
  col gss_recipient secrets "$c"
done

echo ""
echo "── Columns: retrieval_logs ──"
for c in id secret_uuid ip_address user_agent success failure_reason detail created_at; do
  col gss_recipient retrieval_logs "$c"
done

echo ""
echo "── Column types (ORM-critical) ──"
check "users.id is bigint" \
  "SELECT data_type FROM information_schema.columns
   WHERE table_schema='gss_platform' AND table_name='users' AND column_name='id'" \
  "bigint"
check "secrets.id is bigint" \
  "SELECT data_type FROM information_schema.columns
   WHERE table_schema='gss_recipient' AND table_name='secrets' AND column_name='id'" \
  "bigint"
check "secrets.creator_id is bigint" \
  "SELECT data_type FROM information_schema.columns
   WHERE table_schema='gss_recipient' AND table_name='secrets' AND column_name='creator_id'" \
  "bigint"
check "secrets.uuid is uuid type" \
  "SELECT data_type FROM information_schema.columns
   WHERE table_schema='gss_recipient' AND table_name='secrets' AND column_name='uuid'" \
  "uuid"

echo ""
echo "── Indexes ──"
for idx in ix_users_id ix_users_email \
           ix_role_definitions_id ix_secret_controls_id \
           ix_user_audit_logs_action ix_user_audit_logs_created_at \
           ix_secrets_id ix_secrets_uuid ix_secrets_creator_id ix_secrets_expires_at \
           ix_retrieval_logs_secret_uuid ix_retrieval_logs_created_at; do
  check_exists "index $idx" \
    "SELECT indexname FROM pg_indexes WHERE indexname='$idx'"
done

echo ""
echo "── Constraints ──"
for c in uq_users_email uq_role_definitions_name uq_secret_controls_role_control; do
  check_exists "constraint $c" \
    "SELECT conname FROM pg_constraint WHERE conname='$c'"
done
check_exists "FK secrets.creator_id → users.id" \
  "SELECT conname FROM pg_constraint
   WHERE contype='f' AND conrelid='gss_recipient.secrets'::regclass
     AND confrelid='gss_platform.users'::regclass"
check_exists "FK secret_controls.role_id → role_definitions.id" \
  "SELECT conname FROM pg_constraint
   WHERE contype='f' AND conrelid='gss_platform.secret_controls'::regclass"

echo ""
echo "── Seed data ──"
for role in admin user viewer; do
  check "role_definitions.$role" \
    "SELECT name FROM gss_platform.role_definitions WHERE name='$role'" "$role"
done
check "platform_settings.mfa_required" \
  "SELECT key FROM gss_platform.platform_settings WHERE key='mfa_required'" "mfa_required"
check "schema_migrations recorded" \
  "SELECT filename FROM gss_platform.schema_migrations WHERE filename='docker-migrate.sh'" "docker-migrate.sh"

echo ""
echo "── Grants ──"
check_exists "$PLAT USAGE on gss_platform" \
  "SELECT 1 FROM information_schema.role_usage_grants
   WHERE grantee='$PLAT' AND object_schema='gss_platform'"
check_exists "$PLAT USAGE on gss_recipient" \
  "SELECT 1 FROM information_schema.role_usage_grants
   WHERE grantee='$PLAT' AND object_schema='gss_recipient'"
check_exists "$RECP USAGE on gss_recipient" \
  "SELECT 1 FROM information_schema.role_usage_grants
   WHERE grantee='$RECP' AND object_schema='gss_recipient'"

echo ""
echo "═══════════════════════════════════════════════════"
printf "  Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "═══════════════════════════════════════════════════"
echo ""

if [ $FAIL -gt 0 ]; then
  echo "❌  Validation FAILED — $FAIL check(s) did not pass."
  exit 1
else
  echo "✅  Validation PASSED — DB structure matches ORM expectations."
  exit 0
fi
