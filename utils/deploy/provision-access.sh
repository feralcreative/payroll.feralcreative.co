#!/usr/bin/env bash
# ============================================================================
# Create, or audit, the Cloudflare Access application for harvest.feralcreative.co.
#
#   CLOUDFLARE_API_TOKEN="$(op read 'op://Private/jjnr7y3j4qzxx4du6j2lk4xyqq/credential' \
#     --account ziadezzat.1password.com)" ./utils/deploy/provision-access.sh [--dry-run]
#
# Uses the Feral Admin token (Access: Apps and Policies : Edit). Idempotent: an
# existing application is audited, never recreated, and any drift fails the run.
# The container also checks ALLOWED_EMAILS, written by prod.sh; keep the two lists
# identical.
# ============================================================================
set -euo pipefail

ACCOUNT_ID="30aa05fc7822ef63635046e5c7771a9a"
GOOGLE_IDP="eb8c3be3-b566-4ba3-9ec9-aebeb6faff50"
API="https://api.cloudflare.com/client/v4"
DOMAIN="harvest.feralcreative.co"
SESSION="24h"
POLICY="Feral — harvest.feralcreative.co"
EMAILS=(
  "rebecca@feralcreative.co"
  "ziad@feralcreative.co"
)

DRY_RUN=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY_RUN=1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
die()  { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

command -v jq >/dev/null || die "jq is required."
[[ -n "${CLOUDFLARE_API_TOKEN:-}" ]] || die "CLOUDFLARE_API_TOKEN not set. See the header."

auth_curl() { curl -sS -H @- "$@" <<< "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"; }
check() { [[ "$(jq -r '.success' <<< "$1")" == "true" ]] || die "$2: $(jq -c '.errors' <<< "$1")"; }

WANT_EMAILS="$(printf '%s\n' "${EMAILS[@]}" | jq -R . | jq -sc 'unique')"

info "Listing existing applications..."
EXISTING="$(auth_curl "${API}/accounts/${ACCOUNT_ID}/access/apps?per_page=100")"
check "$EXISTING" "Listing applications"

APP="$(jq -c --arg d "$DOMAIN" '[.result[] | select(.domain == $d)][0] // empty' <<< "$EXISTING")"

if [[ -n "$APP" ]]; then
  ok "An application already covers ${DOMAIN}. Auditing it."
  ok "AUD tag: $(jq -r '.aud' <<< "$APP") (ACCESS_AUD in utils/deploy/prod.sh)"
  DRIFT=0
  expect() { # <label> <jq filter on app> <wanted value>
    local have; have="$(jq -c "$2" <<< "$APP")"
    if [[ "$have" == "$3" ]]; then ok "$1: $have"; else warn "$1 is $have, wants $3"; DRIFT=1; fi
  }
  expect "type" '.type' '"self_hosted"'
  expect "session" '.session_duration' "\"${SESSION}\""
  expect "identity providers" '.allowed_idps' "[\"${GOOGLE_IDP}\"]"
  expect "auto-redirect" '.auto_redirect_to_identity' 'true'
  expect "HttpOnly cookie" '.http_only_cookie_attribute' 'true'
  expect "binding cookie" '.enable_binding_cookie' 'true'

  POLICIES="$(auth_curl "${API}/accounts/${ACCOUNT_ID}/access/apps/$(jq -r '.id' <<< "$APP")/policies")"
  check "$POLICIES" "Listing policies"
  # Bypass and service-auth policies are evaluated before allow, so any of them
  # would open the app to someone the list below does not name.
  OTHER="$(jq -c '[.result[] | select(.decision != "allow") | .decision]' <<< "$POLICIES")"
  [[ "$OTHER" == "[]" ]] || { warn "Non-allow policies present: $OTHER"; DRIFT=1; }
  HAVE_EMAILS="$(jq -c '[.result[] | select(.decision == "allow") | .include[] | (.email.email // ("NOT-AN-EMAIL-RULE: " + tojson))] | unique' <<< "$POLICIES")"
  if [[ "$HAVE_EMAILS" == "$WANT_EMAILS" ]]; then ok "Allow list: $HAVE_EMAILS"; else warn "Allow list is $HAVE_EMAILS, wants $WANT_EMAILS"; DRIFT=1; fi
  (( DRIFT == 0 )) || die "The application has drifted from this script. Fix it in the Zero Trust dashboard."
  exit 0
fi

info "Will create:"
echo "    application : ${DOMAIN}  (self-hosted)"
echo "    session     : ${SESSION}"
echo "    identity    : Google only, auto-redirect on"
echo "    policy      : allow ${WANT_EMAILS}"
if (( DRY_RUN == 1 )); then warn "--dry-run: nothing created."; exit 0; fi

APP_BODY="$(jq -n --arg d "$DOMAIN" --arg s "$SESSION" --arg idp "$GOOGLE_IDP" \
  '{name:$d, domain:$d, type:"self_hosted", session_duration:$s,
    allowed_idps:[$idp], auto_redirect_to_identity:true,
    http_only_cookie_attribute:true, enable_binding_cookie:true}')"
APP_RESP="$(auth_curl -X POST -H "Content-Type: application/json" --data "$APP_BODY" \
  "${API}/accounts/${ACCOUNT_ID}/access/apps")"
check "$APP_RESP" "Creating application"
APP_ID="$(jq -r '.result.id' <<< "$APP_RESP")"
ok "Application created (id ${APP_ID})"
ok "AUD tag: $(jq -r '.result.aud' <<< "$APP_RESP") (set ACCESS_AUD in utils/deploy/prod.sh to this)"

# An application with no policy denies everyone, so a failure here locks the
# host rather than opening it.
INCLUDE="$(printf '%s\n' "${EMAILS[@]}" | jq -R '{email: {email: .}}' | jq -s '.')"
POL_BODY="$(jq -n --arg n "$POLICY" --argjson inc "$INCLUDE" '{name:$n, decision:"allow", include:$inc}')"
POL_RESP="$(auth_curl -X POST -H "Content-Type: application/json" --data "$POL_BODY" \
  "${API}/accounts/${ACCOUNT_ID}/access/apps/${APP_ID}/policies")"
check "$POL_RESP" "Creating policy"
ok "Policy attached."
