# HTTP API

Every route lives in `server.js`. Read before touching a route handler or a `fetch` call in `public/js/dashboard.js`. Root rules: [../AGENTS.md](../AGENTS.md).

All responses are JSON. Every handler catches and answers `500` with `{ "error": "<message>" }`; validation failures answer `400` with the same shape.

In production every route except `/healthz` sits behind the Cloudflare Access gate (403 without a valid token for an allowlisted email; see [deployment.md](deployment.md)). Any non-GET request from another origin (`Sec-Fetch-Site` other than `same-origin`, or a foreign `Origin`) is a `403`. API responses are `Cache-Control: no-store`.

## Live routes

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/status` | Connectivity and branding for both accounts |
| GET | `/api/sync/users` | The configured employee pair, resolved to ids in both accounts |
| GET | `/api/users/:account` | All users in one account; `:account` is `agency` or `contractor` |
| POST | `/api/preview` | Dry run with duplicate detection; writes nothing |
| POST | `/api/sync` | Executes the sync; writes to the contractor account |
| GET | `/healthz` | `ok`, answered before the Access gate; for the Docker healthcheck |
| GET | anything else | `public/index.html`, for client-side routing |

## GET /api/status

Issues a one-row `/users` request against each account to prove the credentials work. Never fails as a whole—a broken account comes back as `connected: false` with an `error` string.

```json
{
  "agency": { "connected": true, "name": "Agency Name", "brandColor": "#RRGGBB" },
  "contractor": { "connected": true, "name": "Your Company", "brandColor": "#RRGGBB" }
}
```

`name` comes from `AGENCY_NAME` / `CONTRACTOR_NAME`; `brandColor` from `AGENCY_BRAND_COLOR` / `CONTRACTOR_BRAND_COLOR`, each falling back to a hardcoded hex in the handler when unset.

## GET /api/sync/users

Answers `400` when neither `EMPLOYEE_1_NAME` nor `EMPLOYEE_2_NAME` is set. `found: false` means the exact `first last` string was not present in that account—the commonest cause of a user silently not syncing.

```json
{
  "users": [
    {
      "name": "Employee One",
      "agency": { "userId": 1234567, "found": true },
      "contractor": { "found": false }
    }
  ]
}
```

## GET /api/users/:account

```json
{
  "users": [
    { "id": 1234567, "name": "Employee One", "firstName": "Employee", "lastName": "One" }
  ]
}
```

`:account` must be `agency` or `contractor`; anything else is a `400`.

## POST /api/preview

Request:

```json
{ "fromDate": "2026-09-01", "toDate": "2026-09-15", "userIds": [1234567] }
```

`fromDate` and `toDate` are required, must be real `YYYY-MM-DD` days, and `fromDate` must not be after `toDate`; otherwise `400`. `userIds` is optional and holds **agency** user ids as integers. Only agency users matching `config.targetUsers` by name are ever synced: `userIds` narrows that set and cannot widen it. No user left is a `400`. `/api/sync` validates the same way, and answers `409` while another sync is running.

Response:

```json
{
  "summary": {
    "totalEntries": 6,
    "totalHours": 9.25,
    "totalProjects": 5,
    "newProjects": 1,
    "newTasks": 0,
    "hoursByUser": { "Employee One": 9.25 }
  },
  "lineItems": [
    {
      "date": "2026-09-01",
      "user": "Employee One",
      "project": "Client Project",
      "projectCode": "CP",
      "task": "Development",
      "hours": 2.5,
      "notes": "",
      "projectStatus": "exists",
      "taskStatus": "new",
      "entryStatus": "pending"
    }
  ]
}
```

`projectStatus` and `taskStatus` are `exists` or `new`. `entryStatus` is `pending` or `duplicate`.

## POST /api/sync

Same request body and same validation as preview.

The response differs from preview in `summary`: `entriesCreated` and `entriesSkipped` replace `newProjects` and `newTasks`. `lineItems` carries the same fields, with `entryStatus` now `created` or `duplicate`, and `projectStatus` / `taskStatus` reflecting the state **before** this run created anything.

An unexpected error mid-loop aborts with a `500` and leaves the sync partial. Entries already written stay written; re-running skips them.

## Disabled routes

`/api/timer/user`, `/api/timer/projects/:account/:userId`, `/api/timer/tasks/:account/:projectId`, `/api/timer/running/:account/:userId`, `/api/timer/today/:account/:userId`, `POST /api/timer/start`, and `POST /api/timer/stop` are all commented out in `server.js` between the `TIMER ENDPOINTS DISABLED` and `END TIMER ENDPOINTS DISABLED` markers. The client code that calls them is still live in `public/js/dashboard.js` and would receive `public/index.html` from the catch-all if it were reachable.

## Upstream

All outbound calls go to `https://api.harvestapp.com/v2` with `Authorization: Bearer <token>`, `Harvest-Account-Id: <id>`, and a fixed `User-Agent`. Harvest allows 100 requests per 15 seconds per account. Endpoint reference is vendored in [harvest-api-v2.md](harvest-api-v2.md).
