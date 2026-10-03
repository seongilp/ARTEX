#!/usr/bin/env bash
# Run all Go tests against a disposable PostgreSQL database, never the configured app database.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null || { echo 'Docker가 필요합니다.' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Docker를 실행한 뒤 다시 시도하세요.' >&2; exit 1; }
container_id=''
cleanup() {
  if [[ -n "$container_id" ]]; then docker rm -f "$container_id" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Credentials apply only to this empty, ephemeral test container.
test_password="$(openssl rand -hex 24)"
container_id="$(docker run --rm -d \
  --mount type=tmpfs,destination=/var/lib/postgresql/data \
  -p 127.0.0.1::5432 \
  -e POSTGRES_USER=artex_test -e POSTGRES_DB=artex_test \
  -e "POSTGRES_PASSWORD=$test_password" \
  postgres:16-alpine)"
ready=0
for ((i=0; i<60; i++)); do
  if docker exec "$container_id" pg_isready -U artex_test -d artex_test >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then echo '테스트 PostgreSQL 시작 실패' >&2; exit 1; fi
test_port="$(docker port "$container_id" 5432/tcp)"
test_port="${test_port##*:}"
# Each Go package owns its database: schema migrations and cleanup cannot race
# with another package or leave runnable task/profile state for the next package.
packages="$(go list ./...)"
result=0
index=0
while IFS= read -r package; do
  index=$((index + 1))
  database="artex_test_${index}"
  docker exec "$container_id" createdb -U artex_test "$database"
  if ! ARTEX_PG_DSN="postgres://artex_test:${test_password}@127.0.0.1:${test_port}/${database}?sslmode=disable" \
    go test -count=1 "$@" "$package"; then result=1; fi
done <<< "$packages"
exit "$result"
