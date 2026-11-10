# API contract snapshot

The iOS client talks to the existing `mngd` server. There is no new backend and
no server change in this project. This file pins the contract the client is
built against (deployed `0.3.1` plus the vault/write paths already implemented
in the working tree). Update it deliberately when the server changes.

## Transport and session

- Base URL is configured by the user at login (e.g. `https://cloud.example.com`).
  Production traffic must be HTTPS; `NSAllowsLocalNetworking` only covers local
  development.
- Session: server-set `HttpOnly` cookie, handled by `HTTPCookieStorage`.
- CSRF: `X-CSRF-Token` header required on every mutating route. The token comes
  from `POST /api/v1/auth/login` or `GET /api/v1/auth/me` and lives in memory
  only.
- JSON errors use `{ "error": "...", "message": "..." }`. `401` means the
  session is gone; `403 csrf` means the token is missing or stale; `503
  writer_unavailable` / `worker_unavailable` means the server-side subsystem is
  not enabled and the UI must say so honestly.

## Endpoints used by the app

### Auth and bootstrap

| Method | Path |
| --- | --- |
| POST | `/api/v1/auth/login` |
| GET | `/api/v1/auth/me` |
| POST | `/api/v1/auth/logout` |
| GET | `/api/v1/bootstrap` (alias `/api/v1/state`) |
| GET | `/api/v1/stats` |
| GET | `/api/v1/years` |
| GET | `/api/v1/months` |

### Items, media and mutations

| Method | Path |
| --- | --- |
| GET | `/api/v1/items` — `cloud,type,favorite,album,year,month,q,person,province,district,limit,offset` |
| GET | `/api/v1/items/{id}` |
| GET | `/api/v1/items/{id}/thumb?size=` |
| GET | `/api/v1/items/{id}/preview` |
| GET | `/api/v1/items/{id}/media` — Range; `download=1`, `live=1` |
| POST | `/api/v1/items/{id}/edit` (multipart) |
| POST | `/api/v1/items/{id}/favorite` |
| POST | `/api/v1/items/{id}/delete` |
| POST | `/api/v1/items/zip` (form: `csrf`, repeated `ids`) |
| GET | `/api/v1/albums` |
| GET | `/api/v1/duplicates` |
| GET | `/api/v1/people` |
| POST | `/api/v1/people/{id}/rename` |
| GET | `/api/v1/faces/{id}/cover` |
| GET | `/api/v1/places` |
| GET | `/api/v1/ai/status` |

Pagination for the timeline is `limit=120` with `offset`; search is
`limit=300` with no paging; duplicates are returned in groups and rendered 30
per page.

### Clouds and operations

| Method | Path |
| --- | --- |
| GET | `/api/v1/clouds` |
| POST | `/api/v1/clouds/active` |
| POST | `/api/v1/clouds/test` |
| POST | `/api/v1/scans` |
| POST | `/api/v1/thumbs/retry` |
| POST | `/api/v1/cache/tmp/clear` |
| GET | `/api/v1/phash/pending` |
| POST | `/api/v1/phash/ingest` |
| POST | `/api/v1/phash/scan` |

### Native vault (`mng-vault/v1`)

| Method | Path |
| --- | --- |
| GET/POST | `/api/v1/vaults` |
| GET | `/api/v1/vaults/{id}` |
| GET/PUT | `/api/v1/vaults/{id}/manifest` (CAS: `prev_sha256`, `bytes`) |
| GET/PUT | `/api/v1/vaults/{id}/blobs/{block}` |
| POST | `/api/v1/vaults/{id}/files` |
| POST | `/api/v1/vaults/{id}/delete` |
| POST | `/api/v1/vaults/{id}/rename` |

The server only relays ciphertext. The password and derived key never leave the
device. Uploads split plaintext into 4 MiB chunks, encrypt each with AES-256-GCM
and AAD bound to the vault/file/chunk, and upload by SHA-1 block id. Manifest
updates retry once after `409 {"error":"stale"}`.

### Seafile E2EE (read-only)

| Method | Path |
| --- | --- |
| GET | `/api/v1/e2ee/libraries` |
| GET | `/api/v1/e2ee/repos/{id}` |
| GET | `/api/v1/e2ee/repos/{id}/dir` |
| GET | `/api/v1/e2ee/repos/{id}/blocks` |
| GET | `/api/v1/e2ee/repos/{id}/files/{fid}/blocks/{bid}/link` |
| GET | `/api/v1/e2ee/repos/{id}/download-link` |

Every block link is reduced to a same-origin `/seafhttp/...` path; the client
verifies the SHA-1 block id before decrypting.

### Admin and iCloud

| Method | Path |
| --- | --- |
| GET | `/api/v1/admin/users` |
| GET | `/api/v1/admin/users/{id}` |
| POST | `/api/v1/admin/users…` (create, password, activate, admin, delete, scan) |
| GET | `/api/v1/icloud/status` |
| POST | `/api/v1/icloud/login`, `.../2fa`, `.../start`, `.../save`, `.../pause`, `.../resume`, `.../cancel`, `.../logout` |

Admin routes never widen item ownership; encrypted-library metadata stays
private even for administrators.
