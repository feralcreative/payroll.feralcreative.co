# Status

Updated: 2026-11-19

## Live

<https://harvest.feralcreative.co> runs from Docker on the NAS behind the `feral-nas` Cloudflare Tunnel and a Cloudflare Access application (Google sign-in, `ziad@feralcreative.co` and `rebecca@feralcreative.co`). First deployed 2026-11-19. Details in [deployment.md](deployment.md).

An unauthenticated request redirects to the Access login, and `ziad@feralcreative.co` signed in and ran a sync on 2026-11-19.

## Open

1. The 2026-11-19 sync of 2026-11-01 to 2026-11-15 stopped on a 422 at the −16 h correction on 2026-11-08 (CB0027b, Technology), after creating 22 entries for 11-09 to 11-13. Fixed in `2d09c36` (positives before negatives); deploy it, then re-run that range; duplicates are skipped.
2. Rebecca has not signed in yet.
3. The old Angular build is still public and unauthenticated at <https://harvest-feralcreative-co.web.app> (Firebase). Decide whether to disable it.
4. `/volume1/web/harvest.feralcreative.co.2025-11-pm2` on the NAS is the stopped November 2025 copy, holding old Harvest tokens in its `.env`. Delete it when no longer wanted.
5. A sync longer than Cloudflare's proxy timeout (about 100 seconds) shows a 524 in the browser while the container keeps writing. Re-running is safe because duplicates are skipped, but the UI does not explain it yet.
6. `syncAgencyToDestination.js` still crashes on start (see AGENTS.md gotchas).
