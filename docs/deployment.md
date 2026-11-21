# Deployment

Read before any deploy conversation. Deploying requires explicit human approval every time; see [../AGENTS.md](../AGENTS.md).

## Target

The app was renamed from Harvest Sync to Payroll on 2026-11-21, and everything below describes the new host. **Until the cutover in [Moving from harvest.feralcreative.co](#moving-from-harvestferalcreativeco) is done, production is still the old host**: <https://harvest.feralcreative.co>, deploy path `/volume1/web/harvest.feralcreative.co`, container and image `harvest-sync`, deployed from commit `6029a64` or earlier.

| Fact | Value |
| --- | --- |
| Public URL | <https://payroll.feralcreative.co> |
| Host | Synology DS1525+, `ssh -p 33725 ziad@nas.feralcreative.co` (1Password SSH agent) |
| Deploy path | `/volume1/web/payroll.feralcreative.co` (holds only `docker-compose.yml` and the runtime `.env`) |
| Runtime | Docker container `payroll`, image `payroll:latest`, published on `127.0.0.1:8118` only |
| Ingress | Cloudflare Tunnel `feral-nas` (remotely managed), hostname `payroll.feralcreative.co` → `http://127.0.0.1:8118` |
| Auth | Cloudflare Access application `payroll.feralcreative.co`, Google only, 24 h session |
| Who | `ziad@feralcreative.co` and `rebecca@feralcreative.co` |

There is no stage environment, by decision (User, 2026-11-19).

## How the gate works

Browser → Cloudflare Access (Google sign-in, allow policy) → tunnel → container. The container checks every request's `Cf-Access-Jwt-Assertion` against the `feralcreative` team's signing keys and this application's AUD tag ([../lib/access.js](../lib/access.js)), then checks the email against `ALLOWED_EMAILS`. Missing, forged, or wrong-application tokens get 403; unreachable signing keys get 503. Only `/healthz` is answered before the gate, for the Docker healthcheck.

To add or remove a person, change **both** lists: `EMAILS` in [../utils/deploy/provision-access.sh](../utils/deploy/provision-access.sh) (and the policy in the Zero Trust dashboard, which the script audits but does not edit) and `ALLOWED_EMAILS` in [../utils/deploy/prod.sh](../utils/deploy/prod.sh), then redeploy.

## Release

```bash
cd ~/www/feralcreative/payroll.feralcreative.co
./utils/deploy/prod.sh --dry-run
./utils/deploy/prod.sh
```

The script refuses a dirty tree or a branch other than `main` (`--force` overrides both), asks for a typed `yes`, builds a `linux/amd64` image, streams it to the NAS, sends `docker-compose.yml`, writes the runtime `.env`, restarts the container, waits for `/healthz`, and then requires an unauthenticated request to the public URL to 302 to `feralcreative.cloudflareaccess.com`. A 200 or 403 there means Access is not in front: the script stops the container and fails.

The runtime `.env` on the NAS is generated from the local `.env`: only the Harvest tokens, account IDs, names, colors, and employee names, plus `REQUIRE_ACCESS_HEADER=1`, `ACCESS_AUD`, and `ALLOWED_EMAILS`. It is written at mode 600 with an explicit `chmod`, because `/volume1/web` carries an inherited ACL that makes new files world-readable whatever the umask. Changing a credential means editing the local `.env` and redeploying.

## Day-to-day

```bash
cd ~/www/feralcreative/payroll.feralcreative.co
./utils/deploy/deploy-utils.sh status
```

Other commands: `logs`, `restart`, `stop`, `start`, `health` (inside the container, bypassing Access), and `gate-check` (fails unless the public URL redirects to the Access login).

## Access application

`provision-access.sh` created the `payroll.feralcreative.co` application with the Feral Admin token on 2026-11-21 (id `d8893bf7-914b-4bbb-86ce-07d5644ff9ce`); its AUD tag is `ACCESS_AUD` in `prod.sh`. The `harvest.feralcreative.co` application was created the same way on 2026-11-19. Re-running the script audits the existing application (type, session, IdP, cookie flags, no non-allow policies, exact allow list) and fails on any drift:

```bash
cd ~/www/feralcreative/payroll.feralcreative.co
CLOUDFLARE_API_TOKEN="$(op read 'op://Private/jjnr7y3j4qzxx4du6j2lk4xyqq/credential' --account ziadezzat.1password.com)" ./utils/deploy/provision-access.sh
```

The AUD tag is hard-coded in `prod.sh` as `ACCESS_AUD`; it is not a secret. It is empty until the new application exists, and `prod.sh` refuses to run while it is.

## DNS and tunnel

`payroll.feralcreative.co` needs a proxied CNAME to `9b28cb3b-667f-4eba-b443-8e8e9b841913.cfargotunnel.com` and a tunnel ingress rule ahead of the `http_status:404` catch-all. Neither exists yet (2026-11-21). `harvest.feralcreative.co` has both, changed 2026-11-19 with User's written permission; until then it was a DNS-only CNAME to the old Firebase site `harvest-feralcreative-co.web.app`. Any DNS or tunnel change needs User's written yes.

Never publish port 8118 any other way (Web Station vhost, router forward, `0.0.0.0` in compose): that would bypass Access, leaving only the container's own token check.

## Moving from harvest.feralcreative.co

Steps 1 and 2 touch Cloudflare, and each needs User's written yes.

1. **Access application.** Run `provision-access.sh` (`--dry-run` first). It creates the `payroll.feralcreative.co` application and its allow policy and prints the AUD tag. Paste the tag into `ACCESS_AUD` in `prod.sh` and commit.
2. **Tunnel and DNS.** Add the public hostname `payroll.feralcreative.co` → `http://127.0.0.1:8118` to the `feral-nas` tunnel, ahead of the catch-all, and the proxied CNAME `payroll` → `9b28cb3b-667f-4eba-b443-8e8e9b841913.cfargotunnel.com`. Adding the hostname in the Zero Trust dashboard creates the CNAME as well, so there it is one action and one yes covering both; through the API they are two calls. Do this only after step 1: a hostname with no Access application in front is open to anyone until the container refuses it.
3. **Deploy** with `prod.sh`, then sign in at <https://payroll.feralcreative.co> in an incognito window. Both containers publish `127.0.0.1:8118`, so `prod.sh` stops the old one (`LEGACY_DEPLOY_PATH`) only after the new image is on the NAS, and starts it again if the new container does not come up.

From step 3 on, <https://harvest.feralcreative.co> still reaches the new container through its own tunnel rule, but the container only accepts tokens for the payroll application, so the old host answers 403. To go back, stop the `payroll` container and run `docker-compose up -d` in the old path.

Each browser keeps its activity history and display settings per host, so both start empty on the new one.

Once the new host is confirmed, and with User's yes for each: remove the `harvest` DNS record, its tunnel rule, and its Access application, then delete `/volume1/web/harvest.feralcreative.co` (its `.env` holds Harvest tokens) and the `harvest-sync:latest` image.

## Rollback

There is no release history on the NAS. Check out the last good commit locally and run `prod.sh --force` from it, then switch back to `main`.

## Leftovers

- `/volume1/web/harvest.feralcreative.co.2025-11-pm2` is the old SFTP/PM2 copy from November 2025, moved aside on 2026-11-19, not running. Its `.env` holds Harvest tokens (chmod 600 on the move). Delete it when User agrees.
- The old Angular build is still served, unauthenticated, at <https://harvest-feralcreative-co.web.app>. Disable it when User decides.
