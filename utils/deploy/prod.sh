#!/usr/bin/env bash
# ============================================================================
# payroll.feralcreative.co — production deploy to the Synology NAS.
#
#   ./utils/deploy/prod.sh [--dry-run] [--force]
#
# Builds the image here, streams it to the NAS over SSH, writes the runtime .env
# there, restarts the container, and fails unless an unauthenticated request is
# redirected to the Cloudflare Access login. One-time setup: utils/deploy/SETUP.md.
# ============================================================================
set -euo pipefail

NAS_USER="ziad"
NAS_HOST="nas.feralcreative.co"
NAS_SSH_PORT="33725"
NAS_DEPLOY_PATH="/volume1/web/payroll.feralcreative.co"
CONTAINER_NAME="payroll"
# The pre-rename deployment. It publishes the same port, so it is stopped just
# before the new container starts, and started again if the new one fails.
LEGACY_DEPLOY_PATH="/volume1/web/harvest.feralcreative.co"
IMAGE_NAME="payroll:latest"
PRIMARY_URL="https://payroll.feralcreative.co"
DOCKER="/usr/local/bin/docker"
COMPOSE="/usr/local/bin/docker-compose"

# The Access application's AUD tag (not a secret; provision-access.sh prints it).
# Empty until the payroll.feralcreative.co application exists: the AUD tag of the
# old harvest.feralcreative.co application does not carry over.
ACCESS_AUD="fe8717a33af3207710864e3cbcd3a3aef09655af2b108f2bdee768950aeab200"
# Must match the allow policy in provision-access.sh.
ALLOWED_EMAILS="ziad@feralcreative.co,rebecca@feralcreative.co"

# Settings copied from the local .env into the NAS runtime .env. Nothing else is.
RUNTIME_KEYS=(
  AGENCY_HARVEST_TOKEN AGENCY_HARVEST_ACCOUNT_ID AGENCY_NAME AGENCY_BRAND_COLOR
  CONTRACTOR_HARVEST_TOKEN CONTRACTOR_HARVEST_ACCOUNT_ID CONTRACTOR_NAME CONTRACTOR_BRAND_COLOR
  EMPLOYEE_1_NAME EMPLOYEE_2_NAME
)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
die()  { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

DRY_RUN=""; FORCE=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --force|-f)   FORCE=1 ;;
    --help|-h)    sed -n '2,10p' "$0"; exit 0 ;;
    *)            die "Unknown flag: $arg" ;;
  esac
done

for c in docker ssh git curl; do command -v "$c" >/dev/null || die "$c is required."; done
[[ -n "$ACCESS_AUD" ]] || die "ACCESS_AUD is empty. Run provision-access.sh and paste the AUD tag into this script."
[[ -f .env ]] || die "No local .env."
# Parsed, not sourced: values like "Feral Creative" are unquoted, as dotenv allows.
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
  key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
  if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then val="${BASH_REMATCH[1]}"; fi
  printf -v "$key" '%s' "$val"
done < .env
for k in AGENCY_HARVEST_TOKEN AGENCY_HARVEST_ACCOUNT_ID CONTRACTOR_HARVEST_TOKEN CONTRACTOR_HARVEST_ACCOUNT_ID EMPLOYEE_1_NAME; do
  [[ -n "${!k:-}" ]] || die "$k is not set in .env."
done
for k in "${RUNTIME_KEYS[@]}"; do
  [[ "${!k:-}" != *$'\n'* ]] || die "$k contains a newline."
done

GIT_SHA="$(git rev-parse --short HEAD)"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ -z "$FORCE" ]]; then
  [[ -z "$(git status --porcelain)" ]] || die "Working tree is dirty. Commit, or pass --force."
  [[ "$GIT_BRANCH" == "main" ]] || die "Not on main (on $GIT_BRANCH). Switch, or pass --force."
fi

SSH=(ssh -p "$NAS_SSH_PORT" "${NAS_USER}@${NAS_HOST}")

if [[ -n "$DRY_RUN" ]]; then
  warn "DRY RUN: nothing is built, sent, or restarted."
  echo "  1. docker build --platform linux/amd64 -t ${IMAGE_NAME} ."
  echo "  2. stream the image to ${NAS_HOST}:${NAS_DEPLOY_PATH} and docker load it"
  echo "  3. send docker-compose.yml; write .env (mode 600) with: ${RUNTIME_KEYS[*]} REQUIRE_ACCESS_HEADER ACCESS_AUD ALLOWED_EMAILS"
  echo "  4. stop the old container in ${LEGACY_DEPLOY_PATH} if it is running; docker-compose down, up -d; check /healthz inside the container (the old one is restarted if this fails)"
  echo "  5. require an unauthenticated ${PRIMARY_URL}/ to 302 to the Access login"
  exit 0
fi

echo -e "\n${BOLD}Deploying ${GIT_SHA} (${GIT_BRANCH}) to ${PRIMARY_URL}${NC}"
read -r -p "Type 'yes' to continue: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || die "Aborted."

info "Building image..."
docker build --platform linux/amd64 -t "$IMAGE_NAME" .

info "Sending image to the NAS..."
"${SSH[@]}" "mkdir -p ${NAS_DEPLOY_PATH} && chmod 700 ${NAS_DEPLOY_PATH}"
docker save "$IMAGE_NAME" | gzip | "${SSH[@]}" "gunzip | ${DOCKER} load"

info "Sending docker-compose.yml..."
"${SSH[@]}" "cat > ${NAS_DEPLOY_PATH}/docker-compose.yml" < docker-compose.yml

# /volume1/web carries an inherited ACL that makes new files world-readable
# whatever the umask; an explicit chmod drops it.
info "Writing runtime .env (mode 600)..."
{
  for k in "${RUNTIME_KEYS[@]}"; do printf '%s=%s\n' "$k" "${!k:-}"; done
  printf 'REQUIRE_ACCESS_HEADER=1\nACCESS_AUD=%s\nALLOWED_EMAILS=%s\n' "$ACCESS_AUD" "$ALLOWED_EMAILS"
} | "${SSH[@]}" "umask 077 && cat > ${NAS_DEPLOY_PATH}/.env.tmp && chmod 600 ${NAS_DEPLOY_PATH}/.env.tmp && mv ${NAS_DEPLOY_PATH}/.env.tmp ${NAS_DEPLOY_PATH}/.env"

LEGACY=""
if "${SSH[@]}" "test -f ${LEGACY_DEPLOY_PATH}/docker-compose.yml && cd ${LEGACY_DEPLOY_PATH} && [ -n \"\$(${COMPOSE} ps -q)\" ]"; then
  LEGACY=1
  info "Stopping the old harvest-sync container (same port)..."
  "${SSH[@]}" "cd ${LEGACY_DEPLOY_PATH} && ${COMPOSE} down"
fi
restore_legacy() {
  [[ -n "$LEGACY" ]] || return 0
  warn "Starting the old harvest-sync container again..."
  "${SSH[@]}" "cd ${NAS_DEPLOY_PATH} && ${COMPOSE} down; cd ${LEGACY_DEPLOY_PATH} && ${COMPOSE} up -d" || warn "Could not restart it. Run docker-compose up -d in ${LEGACY_DEPLOY_PATH}."
}

info "Restarting container..."
"${SSH[@]}" "cd ${NAS_DEPLOY_PATH} && ${COMPOSE} down && ${COMPOSE} up -d" || { restore_legacy; die "The container did not start."; }

info "Waiting for /healthz inside the container..."
for i in $(seq 1 15); do
  if "${SSH[@]}" "${DOCKER} exec ${CONTAINER_NAME} curl -fsS http://127.0.0.1:8118/healthz" >/dev/null 2>&1; then
    ok "App is up."; break
  fi
  [[ $i -eq 15 ]] && { "${SSH[@]}" "${DOCKER} logs --tail 30 ${CONTAINER_NAME}" || true; restore_legacy; die "App never answered /healthz."; }
  sleep 2
done

info "Checking that ${PRIMARY_URL} is gated..."
RESULT="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "${PRIMARY_URL}/" || true)"
case "$RESULT" in
  30[12378]\ https://feralcreative.cloudflareaccess.com/*)
    ok "Unauthenticated request redirects to the Access login." ;;
  200\ *|403\ *)
    "${SSH[@]}" "cd ${NAS_DEPLOY_PATH} && ${COMPOSE} down" || true
    restore_legacy
    die "HTTP ${RESULT%% *} without signing in: Access is not in front. Container stopped." ;;
  *)
    die "Unexpected response '${RESULT}'. The container is running; check the tunnel and Access, then run deploy-utils.sh gate-check." ;;
esac

ok "Deployed ${GIT_SHA}. Sign in at ${PRIMARY_URL} in an incognito window to confirm."
