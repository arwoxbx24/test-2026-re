#!/bin/bash
# ============================================
# ARWOX Project Setup — v1.2
# Этот скрипт настраивает Git-репозиторий
# для работы с проектом.
# ============================================
# ИСПОЛЬЗОВАНИЕ:
# 1. Создайте папку с именем проекта (только латиница, цифры, дефисы)
# 2. Положите этот файл в папку
# 3. Откройте Git Bash в этой папке
# 4. Запустите: bash setup.sh
# ============================================
# ТРЕБОВАНИЯ:
# - Git    (https://git-scm.com)
# - Python (https://python.org/downloads/) — при установке отметьте "Add to PATH"
# ============================================

# Windows CRLF compatibility
(set -o igncr) 2>/dev/null && set -o igncr

set -e

# --- CONFIG (заполняется перед выдачей фрилансеру) ---
ENDPOINT="https://d5d036nqq8ehjmeh4avp.o2p3jdjj.apigw.yandexcloud.net/create-repo"
API_KEY="e55157be8a9d31ff8a065aa1fe4ce6ef"
# --- END CONFIG ---

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Track whether WE created .git (for cleanup on failure)
GIT_CREATED_BY_US=0

cleanup_on_failure() {
    if [ "$GIT_CREATED_BY_US" = "1" ] && [ -d .git ]; then
        warn "Удаляем незавершённый git-репозиторий..."
        rm -rf .git
    fi
}
trap cleanup_on_failure ERR

# Check prerequisites
command -v git >/dev/null 2>&1 || error "git не найден. Установите Git: https://git-scm.com"
command -v curl >/dev/null 2>&1 || error "curl не найден"
command -v ssh >/dev/null 2>&1 || error "ssh не найден"

# Find Python (python3 or python)
PYTHON=""
command -v python3 >/dev/null 2>&1 && PYTHON="python3"
[ -z "$PYTHON" ] && command -v python >/dev/null 2>&1 && PYTHON="python"
[ -z "$PYTHON" ] && error "Python не найден. Установите Python 3: https://python.org/downloads/ (при установке отметьте 'Add to PATH')"

# Get project name from directory
PROJECT=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# Validate: 2–50 chars, lowercase alphanum + hyphens, no leading/trailing hyphen
if ! echo "$PROJECT" | grep -qE '^[a-z0-9]([a-z0-9-]{0,48}[a-z0-9])?$'; then
    error "Имя папки '$PROJECT' не подходит. Используйте только латиницу, цифры и дефисы (2–50 символов, без дефиса в начале/конце)"
fi

# Handle existing .git
if [ -d .git ]; then
    EXISTING_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    EXPECTED_PATTERN="arwoxbx24/${PROJECT}"
    if echo "$EXISTING_REMOTE" | grep -q "$EXPECTED_PATTERN"; then
        warn ".git уже существует для этого проекта. Продолжаем с существующим репозиторием..."
        GIT_CREATED_BY_US=0
    else
        error "В этой папке уже есть git-репозиторий с другим remote: $EXISTING_REMOTE"
    fi
fi

echo ""
echo "================================"
echo "  Проект: $PROJECT"
echo "================================"
echo ""

# Call API — save body to temp file, capture HTTP code separately
info "Создание репозитория..."
TMP_RESPONSE="/tmp/setup_response_$$.json"
HTTP_CODE=$(curl -s -m 30 -o "$TMP_RESPONSE" -w "%{http_code}" -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "{\"project\": \"$PROJECT\", \"api_key\": \"$API_KEY\"}")

BODY=$(cat "$TMP_RESPONSE" 2>/dev/null || echo "")
rm -f "$TMP_RESPONSE"

# Validate that response looks like JSON
if [ -n "$BODY" ] && ! echo "$BODY" | grep -q '^{'; then
    error "Сервер вернул неожиданный ответ (не JSON). Возможно, проблема с сетью. Код: $HTTP_CODE"
fi

case $HTTP_CODE in
    200) info "Репозиторий создан" ;;
    400) error "Неверное имя проекта: $(echo "$BODY" | grep -o '"message":"[^"]*"')" ;;
    401) error "Ошибка авторизации. Обратитесь к администратору." ;;
    409) error "Репозиторий '$PROJECT' уже существует." ;;
    000) error "Нет соединения с сервером (timeout). Проверьте интернет." ;;
    *)   error "Ошибка сервера ($HTTP_CODE). Обратитесь к администратору." ;;
esac

# Extract data from response
SSH_URL=$(echo "$BODY" | $PYTHON -c "import sys,json; print(json.load(sys.stdin)['ssh_url'])")
DEPLOY_KEY=$(echo "$BODY" | $PYTHON -c "import sys,json; print(json.load(sys.stdin)['deploy_key'])")

if [ -z "$SSH_URL" ] || [ -z "$DEPLOY_KEY" ]; then
    error "Не удалось получить данные от сервера"
fi

# Save deploy key
KEY_PATH="$HOME/.ssh/deploy_${PROJECT}"
mkdir -p "$HOME/.ssh"

if [ -f "$KEY_PATH" ]; then
    warn "SSH-ключ $KEY_PATH уже существует, используем существующий"
else
    echo "$DEPLOY_KEY" > "$KEY_PATH"
    chmod 600 "$KEY_PATH"
    info "SSH-ключ сохранён: $KEY_PATH"
fi

# Add SSH config
SSH_CONFIG="$HOME/.ssh/config"
HOST_ALIAS="github-${PROJECT}"

if grep -q "Host $HOST_ALIAS" "$SSH_CONFIG" 2>/dev/null; then
    warn "SSH config для $HOST_ALIAS уже существует"
else
    cat >> "$SSH_CONFIG" <<EOF

# ARWOX Project: $PROJECT
Host $HOST_ALIAS
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    IdentitiesOnly yes
EOF
    chmod 600 "$SSH_CONFIG"
    info "SSH config обновлён"
fi

# Fix SSH URL to use alias
ALIAS_URL="git@${HOST_ALIAS}:arwoxbx24/${PROJECT}.git"

# Init git repo (only if we don't already have one)
if [ ! -d .git ]; then
    git init -q
    GIT_CREATED_BY_US=1
    info "Git инициализирован"
fi

git remote add origin "$ALIAS_URL" 2>/dev/null || git remote set-url origin "$ALIAS_URL"
info "Remote: origin → $ALIAS_URL"

# Fetch remote — Cloud Function creates repo with README, must not push-reject
info "Синхронизация с удалённым репозиторием..."
git fetch origin -q 2>/dev/null || true

if git rev-parse origin/main >/dev/null 2>&1; then
    # Remote has commits (e.g. README from Cloud Function) — base our work on it
    git checkout -b main origin/main -q 2>/dev/null || git checkout main -q 2>/dev/null || true
    git add -A
    if ! git diff --cached --quiet 2>/dev/null; then
        git commit -q -m "Initial local commit"
    fi
else
    # Fresh remote with no commits
    git add -A
    git commit -q -m "Initial commit" --allow-empty
    git branch -M main
fi

git push -u origin main -q
info "Первый коммит отправлен"

# Create dev branch and switch to it
git checkout -b dev -q
git push -u origin dev -q
info "Ветка dev создана"

# Create pre-push hook that blocks direct push to main
mkdir -p .git/hooks
cat > .git/hooks/pre-push << 'HOOKEOF'
#!/bin/bash
# Block direct push to main — use branches and merge
while read local_ref local_sha remote_ref remote_sha; do
    if echo "$remote_ref" | grep -q "refs/heads/main"; then
        echo ""
        echo "  ОШИБКА: Push в main запрещён!"
        echo "  Работайте в ветке dev или создайте свою:"
        echo "    git checkout -b fix/описание"
        echo "    git checkout -b feature/описание"
        echo ""
        echo "  Когда готово — отправьте ветку:"
        echo "    git push origin имя-ветки"
        echo ""
        exit 1
    fi
done
exit 0
HOOKEOF
chmod +x .git/hooks/pre-push
info "Git hook установлен (защита main)"

# Disable the error trap — we succeeded
trap - ERR

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}  Готово! Можете работать.${NC}"
echo -e "${GREEN}  Вы на ветке: dev${NC}"
echo -e "${GREEN}${NC}"
echo -e "${GREEN}  Команды:${NC}"
echo -e "${GREEN}  git add . && git commit -m 'описание' && git push${NC}"
echo -e "${GREEN}${NC}"
echo -e "${GREEN}  Новая ветка: git checkout -b feature/название${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Self-cleanup — only on success
rm -f setup.sh
