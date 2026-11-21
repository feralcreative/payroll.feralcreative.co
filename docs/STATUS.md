# Status

Updated: 2026-11-21

## Live

<https://payroll.feralcreative.co> runs from Docker on the NAS (container `payroll`) behind the `feral-nas` Cloudflare Tunnel and a Cloudflare Access application (Google sign-in, `ziad@feralcreative.co` and `rebecca@feralcreative.co`). Deployed 2026-11-21 from `b4521ce`, with the Feral look, the Feral/Tame switch, and the sync fixes from 2026-11-19. Details in [deployment.md](deployment.md).

Checked the same day without signing in: every path, a forged token, and a POST all redirect to the Access login, a request straight to the container on the NAS gets 403, and the Access audit shows exactly those two addresses. Nobody has signed in on the new host yet.

The tool was called Harvest Sync and served at <https://harvest.feralcreative.co> until then. That host's DNS record, tunnel rule, and Access application still exist, and it now answers 403 after sign-in; its container is stopped. Removing them is in the open list.

## Open

1. Sign in at the new host in an incognito window, and have Rebecca do the same. Then, with a yes for each: remove the `harvest` DNS record, its tunnel rule, and its Access application, and delete `/volume1/web/harvest.feralcreative.co` and the `harvest-sync:latest` image.
2. The 2026-11-19 sync of 2026-11-01 to 2026-11-15 stopped on a 422 at the −16 h correction on 2026-11-08 (CB0027b, Technology), after creating 22 entries for 11-09 to 11-13. Fixed in `2d09c36` (positives before negatives); deployed 2026-11-21; re-run that range; duplicates are skipped.
3. Rebecca has not signed in yet.
4. The old Angular build is still public and unauthenticated at <https://harvest-feralcreative-co.web.app> (Firebase). Decide whether to disable it.
5. `/volume1/web/harvest.feralcreative.co.2025-11-pm2` on the NAS is the stopped November 2025 copy, holding old Harvest tokens in its `.env`. Delete it when no longer wanted.
6. A sync longer than Cloudflare's proxy timeout (about 100 seconds) shows a 524 in the browser while the container keeps writing. Re-running is safe because duplicates are skipped, but the UI does not explain it yet.
7. `syncAgencyToDestination.js` still crashes on start (see AGENTS.md gotchas).
8. The README has no screenshot: the old one showed the Harvest Sync look and was removed. Take a new one after the new host is live.
9. `npm install` reports 4 vulnerabilities (1 moderate, 2 high, 1 critical) in the dependency tree. Not looked into yet.
10. `assets/images/icon-harvest.svg` and `logo-harvest.svg` (Harvest's own marks) and `assets/fonts/monarch.*` are referenced by nothing.
