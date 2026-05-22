#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# ── 색상 ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERR ]${NC} $1"; exit 1; }

# ── 커밋 메시지 인자 처리 ─────────────────────────────
COMMIT_MSG="${1:-"chore: sync local changes"}"

info "원격 저장소 확인 중..."
git fetch origin

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
  ok "원격 저장소와 동일 — pull 불필요"
else
  BEHIND=$(git rev-list HEAD..origin/main --count)
  info "원격에 ${BEHIND}개 커밋 있음 — merge 진행"
  git merge --no-edit origin/main || error "merge 충돌 발생. 수동으로 해결 후 다시 실행하세요."
  ok "merge 완료"
fi

# ── 로컬 변경사항 확인 ────────────────────────────────
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  warn "커밋할 변경사항이 없습니다."
  exit 0
fi

# ── 스테이징 & 커밋 ───────────────────────────────────
info "변경 파일 스테이징..."
git add -A
git status --short

echo ""
read -rp "커밋 메시지 [${COMMIT_MSG}]: " INPUT
[ -n "$INPUT" ] && COMMIT_MSG="$INPUT"

git commit -m "$COMMIT_MSG"
ok "커밋 완료"

# ── 푸시 ─────────────────────────────────────────────
info "origin/main 으로 push 중..."
git push origin main
ok "push 완료 — $(git rev-parse --short HEAD)"
