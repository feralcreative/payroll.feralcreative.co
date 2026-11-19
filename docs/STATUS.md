# Status

Updated: 2026-11-19

## Live

<https://harvest.feralcreative.co> runs from Docker on the NAS behind the `feral-nas` Cloudflare Tunnel and a Cloudflare Access application (Google sign-in, `ziad@feralcreative.co` and `rebecca@feralcreative.co`). First deployed 2026-11-19. Details in [deployment.md](deployment.md).

An unauthenticated request redirects to the Access login (checked by `prod.sh` and `deploy-utils.sh gate-check`). A real signed-in session has not yet been confirmed end to end.

## Open

1. Sign in once as each allowlisted address and confirm the dashboard loads and both status cards read connected.
2. The old Angular build is still public and unauthenticated at <https://harvest-feralcreative-co.web.app> (Firebase). Decide whether to disable it.
3. `/volume1/web/harvest.feralcreative.co.2025-11-pm2` on the NAS is the stopped November 2025 copy, holding old Harvest tokens in its `.env`. Delete it when no longer wanted.
4. A sync longer than Cloudflare's proxy timeout (about 100 seconds) shows a 524 in the browser while the container keeps writing. Re-running is safe because duplicates are skipped, but the UI does not explain it yet.
5. `syncAgencyToDestination.js` still crashes on start (see AGENTS.md gotchas).
