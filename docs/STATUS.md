# Status

Updated: 2026-11-21

## Rebrand in progress

The tool is now **Payroll**, to be served at <https://payroll.feralcreative.co>. Done on branch `chore/rebrand-payroll` (2026-11-21): Feral Creative colors and logo on the dashboard and the preview report, the name in the UI and docs, and the deploy scripts, container, and NAS path pointed at the new host. The GitHub repo and the local folder are `payroll.feralcreative.co`. The dashboard also has the Feral/Tame switch: a light look, chosen in the header and remembered per browser.

Not done: the new host itself. It needs an Access application, a tunnel rule, a DNS record, and a deploy, in the order given in [deployment.md](deployment.md#moving-from-harvestferalcreativeco). Until then production is the old host below, running the old look, and `prod.sh` on this branch refuses to run because `ACCESS_AUD` is empty.

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
7. The README has no screenshot: the old one showed the Harvest Sync look and was removed. Take a new one after the new host is live.
8. `npm install` reports 4 vulnerabilities (1 moderate, 2 high, 1 critical) in the dependency tree. Not looked into yet.
9. `assets/images/icon-harvest.svg` and `logo-harvest.svg` (Harvest's own marks) and `assets/fonts/monarch.*` are referenced by nothing.
