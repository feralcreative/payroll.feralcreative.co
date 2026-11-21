#!/usr/bin/env bash
# payroll.feralcreative.co — post-deploy management.
#   ./utils/deploy/deploy-utils.sh logs|status|restart|stop|start|health|gate-check
set -euo pipefail

NAS="ziad@nas.feralcreative.co"
SSH=(ssh -p 33725 "$NAS")
DIR="/volume1/web/payroll.feralcreative.co"
NAME="payroll"
URL="https://payroll.feralcreative.co"
DOCKER="/usr/local/bin/docker"
COMPOSE="/usr/local/bin/docker-compose"

case "${1:-help}" in
  logs)    "${SSH[@]}" "${DOCKER} logs -f --tail 100 ${NAME}" ;;
  status)  "${SSH[@]}" "${DOCKER} ps --filter name=^${NAME}$" ;;
  restart) "${SSH[@]}" "cd ${DIR} && ${COMPOSE} restart" ;;
  stop)    "${SSH[@]}" "cd ${DIR} && ${COMPOSE} down" ;;
  start)   "${SSH[@]}" "cd ${DIR} && ${COMPOSE} up -d" ;;
  health)  "${SSH[@]}" "${DOCKER} exec ${NAME} curl -fsS http://127.0.0.1:8118/healthz" && echo ;;
  gate-check)
    r="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 20 "${URL}/" || true)"
    case "$r" in
      30[12378]\ https://feralcreative.cloudflareaccess.com/*) echo "Gated: ${r%% *} to the Access login." ;;
      *) echo "NOT GATED as expected: ${r}" >&2; exit 1 ;;
    esac ;;
  *) sed -n '2,3p' "$0"; exit 1 ;;
esac
