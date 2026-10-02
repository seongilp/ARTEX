#!/usr/bin/env bash
# ARTEX 업데이트 스크립트: ① Docker 업데이트(새 이미지 가져와 재생성) ② 로컬 컴파일 업데이트(바이너리 재생성)
# 与 install.sh 对应：install 负责首次落地，update 负责升级到新版本。
# DB 迁移无需手动执行——artex 每次启动都会幂等重跑 schema.sql（含 ADD COLUMN/CREATE
# INDEX IF NOT EXISTS），所以“重启即迁移”。数据（pgdata 卷、./data、./skills）不受影响。
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

info(){ printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok(){   printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[!]\033[0m %s\n' "$*"; }
die(){  printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
ask(){  local p="$1" d="${2:-}" a; read -rp "$p${d:+ [$d]}: " a; echo "${a:-$d}"; }

# ── 可选：同步仓库到最新代码（compose/脚本/本地编译源码都靠它更新）───────
sync_repo(){
  [ -d .git ] && command -v git >/dev/null 2>&1 || { warn "Git 작업 사본이 아니므로 git pull을 건너뜁니다"; return; }
  [ "$(ask '최신 코드를 가져올까요 (git pull --ff-only)? (y/n)' y)" = y ] || return
  if ! git pull --ff-only; then
    warn "git pull이 fast-forward되지 않았습니다(로컬 변경 또는 브랜치 분기). 직접 해결한 뒤 다시 시도하세요. 이번에는 현재 코드를 사용합니다"
  fi
}

# ── ① Docker 업데이트 ───────────────────────────────
update_docker(){
  command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 \
    || die "docker 또는 docker compose를 찾을 수 없습니다. 먼저 ./install.sh로 설치하세요"
  [ -f .env ] || die ".env 파일이 없습니다. 먼저 ./install.sh를 실행해 최초 배포를 완료하세요"

  # 可选：升级到指定版本 tag（不填则沿用 .env 中的 ARTEX_TAG，缺省为 latest）
  local tag; tag="$(ask '대상 이미지 태그(Enter를 누르면 .env 값 또는 latest 사용)' '')"
  if [ -n "$tag" ]; then
    if grep -q '^ARTEX_TAG=' .env; then
      sed -i.bak "s|^ARTEX_TAG=.*|ARTEX_TAG=${tag}|" .env && rm -f .env.bak
    else
      printf '\nARTEX_TAG=%s\n' "$tag" >> .env
    fi
    ok "ARTEX_TAG를 다음으로 설정했습니다: ${tag}"
  fi

  # 只动 artex：postgres 是固定的 16-alpine，不需要跟着升级（拉它纯属浪费带宽，
  # 且大版本变动还会有兼容风险）。artex 声明了 depends_on postgres，所以带服务名
  # up 时若 pg 没起会自动拉起，已在跑的则原样保留、不重建。
  info "새 이미지 가져오는 중(artex만)…"
  docker compose pull artex
  info "재생성 및 시작 중(artex 재시작 시 스키마 자동 마이그레이션)…"
  docker compose up -d artex
  ok "업데이트 완료 → http://localhost:8787"
  info "로그 보기: docker compose logs -f artex"
  info "이전 이미지 정리(선택 사항): docker image prune -f"
}

# ── ② 로컬 컴파일 업데이트 ──────────────────────────────
update_local(){
  command -v go >/dev/null 2>&1 || die "Go(>=1.26)를 찾을 수 없습니다: https://go.dev/dl/"
  [ -f config.json ] || warn "config.json 파일이 없습니다. 최초 배포라면 ./install.sh를 사용하세요"
  ok "Go: $(go version)"

  if command -v npm >/dev/null 2>&1; then
    info "프런트엔드 정적 파일 다시 빌드 중…"
    ( cd web && npm ci && npm run build:static )
    rm -rf server/webui/dist && cp -r web/out server/webui/dist
    info "프런트엔드를 포함한 단일 바이너리 다시 컴파일 중…"
    CGO_ENABLED=0 go build -tags embedui -trimpath -o artex ./cmd/artex
  else
    warn "npm을 찾을 수 없습니다. 프런트엔드를 포함하지 않은 백엔드를 컴파일합니다(프런트엔드는 별도로 npm run dev 실행 필요)"
    CGO_ENABLED=0 go build -o artex ./cmd/artex
  fi
  ok "컴파일 완료 → ./artex"
  warn "변경 사항을 적용하려면 실행 중인 artex 프로세스를 재시작하세요(재시작 시 스키마 자동 마이그레이션)"
}

echo "=============================="
echo "  ARTEX 업데이트"
echo "  1) Docker 업데이트(새 이미지 가져와 재생성)"
echo "  2) 로컬 업데이트(Go로 다시 컴파일)"
echo "=============================="
case "$(ask '선택' 1)" in
  1) sync_repo; update_docker ;;
  2) sync_repo; update_local ;;
  *) die "잘못된 선택" ;;
esac
