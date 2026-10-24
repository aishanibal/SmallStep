#!/usr/bin/env bash
# Applies the migrations + seed to a throwaway Postgres container (with a stub of Supabase's auth
# schema) and runs the RLS check. Needs Docker. This is a sanity check of the SQL, not a replacement
# for running supabase/tests/rls_check.sql once against the hosted project.
set -euo pipefail
cd "$(dirname "$0")/.."
name=smallstep-sqlcheck
docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" -e POSTGRES_PASSWORD=pw postgres:17 >/dev/null
trap 'docker rm -f "$name" >/dev/null 2>&1' EXIT
until docker exec "$name" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
sleep 2
psql() { docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql < supabase/tests/local/stub.sql
for f in supabase/migrations/*.sql; do echo "applying $f"; psql < "$f"; done
[ -n "${EXTRA_SQL:-}" ] && { echo "applying EXTRA_SQL (mutation test)"; echo "$EXTRA_SQL" | psql; }
echo "seeding"; psql < supabase/seed.sql
echo "rows: $(psql -tA -c 'select count(*) from public.export_suggestions')"
psql -f - < supabase/tests/rls_check.sql | tail -3
echo "export queries:"; psql -o /dev/null < docs/export.sql && echo "docs/export.sql runs"
[ -n "${SHOW_EXPORT:-}" ] && psql < docs/export.sql | sed -n "/source /,/^(/p" | head -12
