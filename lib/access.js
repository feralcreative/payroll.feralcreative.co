// Verifies the Cloudflare Access token on each request, so the origin trusts a
// signature instead of a header anyone on the network could type.
//
// Access signs a JWT for every request it lets through and sends it as
// Cf-Access-Jwt-Assertion. It is checked here against the team's public keys,
// the application's AUD tag, and its expiry. The plain
// Cf-Access-Authenticated-User-Email header is ignored; the email comes from the
// verified token. Ported to CommonJS from money.ezzat.com/src/access.js; keep the two in step.

const { createPublicKey, verify } = require("node:crypto");

const TEAM_DOMAIN = "https://feralcreative.cloudflareaccess.com";
const CERTS_URL = `${TEAM_DOMAIN}/cdn-cgi/access/certs`;
const KEYS_MAX_AGE_MS = 60 * 60 * 1000;
// An unknown kid triggers a refetch (Cloudflare rotates keys), but no more than
// one attempt a minute, failed or not, so a flood of forged tokens cannot hammer
// the certs endpoint.
const MIN_REFETCH_MS = 60 * 1000;
// If the certs endpoint is down, keys already fetched keep working this long.
// Past it, requests are refused rather than verified against keys that may have
// been rotated out.
const STALE_LIMIT_MS = 24 * 60 * 60 * 1000;
const CLOCK_SKEW_S = 60;

let keys = new Map();
let fetchedAt = 0;
let attemptedAt = 0;
let inflight = null;

async function loadKeys() {
  inflight ??= (async () => {
    attemptedAt = Date.now();
    try {
      const res = await fetch(CERTS_URL, { signal: AbortSignal.timeout(5000) });
      if (!res.ok) throw new Error(`certs fetch returned HTTP ${res.status}`);
      const { keys: jwks } = await res.json();
      // Build the new set fully before swapping it in, so a bad response leaves
      // the working keys in place instead of replacing them with nothing.
      const next = new Map(jwks.map((jwk) => [jwk.kid, createPublicKey({ key: jwk, format: "jwk" })]));
      if (!next.size || [...next.keys()].some((kid) => typeof kid !== "string")) {
        throw new Error("certs response had no usable keys");
      }
      keys = next;
      fetchedAt = Date.now();
    } finally {
      inflight = null;
    }
  })();
  return inflight;
}

async function keyFor(kid) {
  const cached = keys.get(kid);
  const due = !cached || Date.now() - fetchedAt > KEYS_MAX_AGE_MS;
  if (due && !inflight && Date.now() - attemptedAt > MIN_REFETCH_MS) {
    loadKeys().catch((err) => console.warn("[access] Signing key refresh failed", err));
  }
  // A known key answers now, with any refresh running in the background, so a
  // forged unknown kid during an outage cannot stall requests that have one.
  if (cached && Date.now() - fetchedAt <= STALE_LIMIT_MS) return cached;
  if (inflight) await inflight.catch(() => {});
  if (Date.now() - fetchedAt > STALE_LIMIT_MS) throw new Error("No Access signing keys fetched in the last 24 hours");
  return keys.get(kid);
}

function decodePart(part) {
  return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
}

// Resolves to the signed-in email when the token is valid for this application,
// or null when it is missing, forged, expired, or meant for another application.
// Rejects only when the signing keys cannot be fetched, which callers should
// treat as "cannot verify" and refuse the request.
async function verifyAccess(token, aud) {
  if (typeof token !== "string") return null;
  const parts = token.split(".");
  // Strict base64url, so one token has exactly one spelling.
  if (parts.length !== 3 || !parts.every((p) => /^[A-Za-z0-9_-]+$/.test(p))) return null;

  let header, payload;
  try {
    header = decodePart(parts[0]);
    payload = decodePart(parts[1]);
  } catch {
    return null;
  }
  if (!header || typeof header !== "object" || !payload || typeof payload !== "object") return null;
  if (header.alg !== "RS256" || typeof header.kid !== "string") return null;

  const key = await keyFor(header.kid);
  if (!key) return null;
  const signed = Buffer.from(`${parts[0]}.${parts[1]}`);
  try {
    if (!verify("RSA-SHA256", signed, key, Buffer.from(parts[2], "base64url"))) return null;
  } catch {
    return null;
  }

  const now = Math.floor(Date.now() / 1000);
  const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (payload.iss !== TEAM_DOMAIN) return null;
  if (!audiences.includes(aud)) return null;
  if (typeof payload.exp !== "number" || payload.exp < now - CLOCK_SKEW_S) return null;
  if (typeof payload.nbf === "number" && payload.nbf > now + CLOCK_SKEW_S) return null;
  if (typeof payload.email !== "string" || !payload.email) return null;
  return payload.email;
}

module.exports = { verifyAccess };
