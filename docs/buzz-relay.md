# Buzz Relay for Umbrel

This document is the durable project record for packaging Block's Buzz relay in this
community app store. Read it before changing the Buzz package so decisions and test
results survive across development and LLM sessions.

Last research pass: 2026-08-26

## Objective

Create a `marcano-buzz-relay` Umbrel package that eventually lets any Umbrel owner run
a secure, persistent Buzz community. Development will start with a private prototype
configured for this store owner, prove the upstream relay works on a real Umbrel, and
only then add a general browser-based setup experience.

This repository is not installed by other users yet. Breaking prototype changes are
acceptable until the package is explicitly marked ready for wider use.

## Current status

- Research and architecture mapping: complete for the first prototype.
- Package directory: created as `marcano-buzz-relay`.
- Owner public key: configured in hex form for the prototype.
- Canonical relay URL: `wss://buzz.jerseyplebs.com`.
- Umbrel host: AMD64 with approximately 32 GB RAM; free storage must be checked
  before runtime installation.
- Runtime testing on Umbrel: not started.
- General-purpose setup UI: deliberately deferred.

Next action: install the statically validated package through Umbrel and execute the
Phase 2 core runtime checks, including Cloudflare Host-header and WebSocket behavior.

## Inputs needed for the prototype

Prototype inputs recorded on 2026-08-26:

1. `RELAY_OWNER_PUBKEY`:
   `df478ecdffe91db90469aeced8d5a33efcaaf75231bb4d768e711184495107a7`.
   This is public information.
2. `RELAY_URL`: `wss://buzz.jerseyplebs.com`, served through an existing Cloudflare
   Tunnel that remains outside the Umbrel package.
3. Umbrel architecture and capacity: `amd64`, approximately 32 GB RAM, persistent
   storage capacity still to be measured before installation.

Never request, paste, or commit the owner's Nostr private key. It belongs only in the
owner's Buzz client or secure key backup.

## Decisions already made

### Develop in phases

The first package will prioritize validating the unmodified upstream system. It will
use owner-specific public values and Umbrel-derived secrets. It will not initially
attempt to be a polished one-click package for other people.

After the relay is proven, a later phase will replace owner-specific configuration
with a browser setup flow without changing the underlying persistent data layout.

### Use the stable upstream relay release

Start with Buzz relay `0.2.1`, not `main` or `latest`:

```text
ghcr.io/block/buzz:0.2.1
sha256:4e31b7c7abb7d00b6f513dc559e58d2b980416f1dc400aa01bcf762cf2989cfc
```

The digest is the multi-architecture OCI index and contains native
`linux/amd64` and `linux/arm64` images. Before implementation, re-check that the
digest is still accessible and verify whether a newer stable relay release should be
evaluated. Do not silently advance the package to a moving tag.

### Keep the upstream service boundaries

The first prototype consists of:

| Service | Role | Persistent data |
| --- | --- | --- |
| `app_proxy` | Umbrel entry point | None |
| `relay` | Buzz WebSocket, REST, media, Git, web and huddle server | Git working data |
| `postgres` | Events, membership, search, audit and authoritative metadata | PostgreSQL data |
| `redis` | Pub/sub, presence, typing and coordination | Redis AOF data |
| `minio` | S3-compatible media and Git object storage | MinIO data |
| `minio-init` | One-shot private bucket creation | None |

Do not collapse these dependencies into the relay container. Mobile pairing is a
separate optional service and is deferred until the core stack is working.

### Generate server secrets from Umbrel entropy

`exports.sh` should use `derive_entropy` with a unique label for each value:

- relay signing private key;
- Git hook HMAC secret;
- PostgreSQL password;
- Redis password;
- MinIO access key;
- MinIO secret key.

Use `EXPORTS_APP_ID`, `EXPORTS_APP_DIR`, `EXPORTS_APP_DATA_DIR`, and
`app_entropy_identifier` inside `exports.sh`. It is sourced by Umbrel and must not
call `exit`, change shell options, run Docker commands, or write runtime state.

The relay signing key is not the owner's private key. It is a separate, stable server
identity. Rotating it changes how peers identify the relay.

### Start closed and authenticated

Use these production-oriented upstream settings:

```text
BUZZ_REQUIRE_AUTH_TOKEN=true
BUZZ_REQUIRE_RELAY_MEMBERSHIP=true
BUZZ_ALLOW_NIP_OA_AUTH=true
BUZZ_AUTO_MIGRATE=true
BUZZ_GIT_CONFORMANCE_PROBE=true
```

Closed membership requires both a valid `RELAY_OWNER_PUBKEY` and a stable
`BUZZ_RELAY_PRIVATE_KEY`. The relay should fail closed when either is missing rather
than starting as a public relay.

### Let Buzz perform protocol authentication

Buzz Desktop, mobile, CLI, and agents cannot supply an Umbrel browser session cookie.
The protocol surface must therefore bypass Umbrel authentication with
`PROXY_AUTH_ADD: "false"` and rely on Buzz's Nostr authentication and closed relay
membership.

This exposure must be clearly documented in the final app listing. PostgreSQL,
Redis, MinIO, health, metrics, and administrative ports must remain internal.

### Treat the canonical relay URL as durable identity

Buzz derives the deployment community from the authority in `RELAY_URL` and resolves
requests using the HTTP `Host` header. A different hostname or port can be treated as
a different or unknown community.

Choose the real long-term URL before creating meaningful data. Examples:

```text
ws://umbrel.local:<app-port>       # LAN-only
wss://buzz.example.com            # stable remote access
```

TLS should terminate at the user's existing remote-access layer, such as a reverse
proxy, tunnel, or private network gateway. Do not bind Caddy directly to host ports
80/443 in the initial Umbrel package.

## Planned persistent layout

Convert all upstream named volumes to bind mounts under Umbrel app data:

```text
${APP_DATA_DIR}/data/
├── config/
├── postgres/
├── redis/
├── minio/
└── git/
```

Expected container mappings:

```text
data/postgres -> /var/lib/postgresql/data
data/redis    -> /data
data/minio    -> /data
data/git      -> /data/git
```

Commit `.gitkeep` files for empty source directories required on first install. Verify
the runtime users can write every mount; do not assume that forcing UID/GID 1000 is
valid for PostgreSQL, Redis, or MinIO without testing their entrypoints.

## Internal ports

The planned network map is:

| Port | Service | Exposure |
| --- | --- | --- |
| `3000` | Buzz relay HTTP/WebSocket | Through `app_proxy` only |
| `8080` | Relay liveness/readiness | Internal only |
| `9102` | Relay Prometheus metrics | Internal only |
| `5432` | PostgreSQL | Internal only |
| `6379` | Redis | Internal only |
| `9000` | MinIO S3 API | Internal only |
| `9001` | MinIO console | Internal only; likely unnecessary to expose |
| `5000` | Optional pairing relay | Deferred; later route through `/pair` |

Choose an unused Umbrel manifest port during implementation. The manifest port is not
the relay's internal port 3000.

## Image policy

All runtime and one-shot images must be public, pinned as
`tag@sha256:multi-arch-index-digest`, and support both AMD64 and ARM64. This includes:

- Buzz relay;
- PostgreSQL 17;
- Redis 7;
- MinIO;
- MinIO client.

The 2026-08-26 research pass confirmed both required architectures for all five
upstream image families. Phase 1 pins:

```text
ghcr.io/block/buzz:0.2.1@sha256:4e31b7c7abb7d00b6f513dc559e58d2b980416f1dc400aa01bcf762cf2989cfc
postgres:17.11-alpine3.24@sha256:18cfe3ef5e6815560c98237d6216d1e5119702fb0f3894c8785dd58b8bbe5d73
redis:7.4.11-alpine@sha256:ff02b58f971e7d7d156a1267e283fcbbeee91773b6aa36c49dac28ecfe28eadf
minio/minio:RELEASE.2025-09-07T16-13-09Z@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e
minio/mc:RELEASE.2025-08-13T08-35-41Z@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727
```

## Prototype implementation phases

### Phase 1: Static package

- [x] Create `marcano-buzz-relay/umbrel-app.yml`.
- [x] Create `marcano-buzz-relay/docker-compose.yml` from the upstream production bundle.
- [x] Create `exports.sh` with independently derived secrets.
- [x] Hardcode only the owner public key and canonical public URL values supplied for
  the prototype.
- [x] Add persistent directory scaffolding.
- [x] Pin every image by a multi-architecture digest.
- [x] Complete YAML, Compose, shell, image and Umbrel package lint checks.

### Phase 2: Core runtime validation

- Install through the Umbrel community app store, not raw Compose alone.
- Confirm every dependency becomes healthy.
- Confirm automatic PostgreSQL migrations complete.
- Confirm MinIO bucket initialization and the Git conformance probe succeed.
- Verify `/_liveness`, `/_readiness`, and NIP-11 responses.
- Verify a real WebSocket upgrade through Umbrel's proxy.
- Confirm logs report that the deployment community was ensured and the owner was
  bootstrapped.

### Phase 3: User workflow validation

- Connect Buzz Desktop using the canonical relay URL.
- Authenticate as the configured owner.
- Create a channel and send messages.
- Restart the app from Umbrel and verify channels and messages persist.
- Upload and retrieve media, then restart and verify it persists.
- Exercise Git repository creation/push/clone if supported by the selected client.
- Inspect settled logs for authorization, host routing, database, Redis and S3 errors.

### Phase 4: Operations validation

- Back up all persistent paths and stable identity configuration.
- Restore into a disposable test installation and verify identity and data.
- Test an upgrade from the first packaged release to the next selected stable release.
- Record actual CPU, memory and disk use on the target Umbrel.
- Obtain AMD64 and ARM64 runtime coverage where possible.

### Phase 5: Generalize for other users

Only after the prototype passes should the package gain a browser-based setup/gateway
component. It should:

- accept and validate an `npub` or 64-character hex owner public key;
- ask for LAN-only or stable public operation;
- validate and persist the canonical relay URL;
- never request the owner's private key;
- show relay health and client connection instructions;
- route HTTP and WebSocket traffic to the relay;
- optionally route `/pair` to the stateless pairing relay;
- preserve the Phase 1 data and secret layout during migration.

That helper must be open source, small, auditable, unprivileged, multi-architecture,
and must not mount the Docker socket.

## Validation record

Update this table as tests are completed. Include dates and the tested architecture,
but never paste keys, credentials, private hostnames, cookies, or sensitive logs.

| Check | Status | Evidence/notes |
| --- | --- | --- |
| Static package lint | Passed 2026-08-26 | Official Umbrel linter: 0 errors; expected `minio-init` one-shot restart warning |
| AMD64 image manifests | Passed 2026-08-26 | All five pinned image indexes include AMD64 |
| ARM64 image manifests | Passed 2026-08-26 | All five pinned image indexes include ARM64 |
| Fresh Umbrel install | Not started | |
| PostgreSQL migrations | Not started | |
| MinIO initialization | Not started | |
| Relay readiness | Not started | |
| NIP-11 response | Not started | |
| WebSocket upgrade | Not started | |
| Owner bootstrap | Not started | |
| Desktop connection | Not started | |
| Message persistence | Not started | |
| Media persistence | Not started | |
| Git workflow | Not started | |
| Umbrel restart | Not started | |
| Backup and restore | Not started | |
| Version upgrade | Not started | |
| Mobile pairing | Deferred | After the core stack works |

## Backup contract

Until runtime tests prove otherwise, preserve together:

- PostgreSQL data;
- Redis data;
- MinIO data;
- Git data;
- derived relay identity and service-secret inputs;
- owner public configuration.

The operator must separately back up the owner's Nostr private key. Aim for PostgreSQL,
MinIO, and Git snapshots from the same maintenance window. Test restoration rather
than treating the existence of backup files as proof.

## Known risks and open questions

- Package `0.2.1-2` fixes the first deployment's `role "buzz" does not exist`
  failure. Generic Docker aliases (`postgres`, `redis`, and `minio`) can collide
  with other apps on Umbrel's shared network, so internal URLs now use qualified
  unique, URL-safe `marcano-buzz-relay-*` network aliases. Package `0.2.1-1`
  briefly used underscore-containing container names, which MinIO's `mc`
  rejected as an endpoint URL. The Postgres health check also runs a real
  query as the Buzz user because `pg_isready` can succeed against the temporary
  initialization server before the configured role and database exist. The
  accompanying app-proxy DNS errors were downstream symptoms of the relay
  repeatedly exiting.
- Buzz is early and changes quickly; stable relay releases currently trail `main`.
- The canonical host is part of community routing and is awkward to change later.
- A public `wss://` endpoint needs a stable domain and TLS outside the initial package.
- A local Umbrel URL and a public URL may send different Host headers. Test the exact
  intended ingress path before storing real data.
- Umbrel proxy authentication must be disabled for protocol clients, increasing the
  importance of Buzz's own closed-membership defaults.
- The upstream Compose bundle does not start the pairing relay even though the binary
  is included in the image.
- The release documentation treats Git disk state as backup-worthy, while newer
  upstream architecture increasingly treats it as object-store-backed working state.
  Preserve it until the packaged release is tested and its recovery behavior is clear.
- Database migrations run at startup. Every update needs backup and upgrade-path tests.
- Actual resource requirements on common Umbrel hardware remain unmeasured.
- The official Umbrel linter warns about `minio-init` using `restart: "no"`.
  This is intentional: it is a one-shot, idempotent bucket initializer that the
  relay waits for with `service_completed_successfully`.

## Upstream references

- [Run your own Buzz relay](https://engineering.block.xyz/blog/run-your-own-buzz-relay)
- [Block Buzz repository](https://github.com/block/buzz)
- [Production Compose bundle](https://github.com/block/buzz/tree/main/deploy/compose)
- [Buzz Helm deployment guide](https://github.com/block/buzz/blob/main/deploy/charts/buzz/README.md)
- [Buzz deployment identity](https://github.com/block/buzz/blob/main/docs/deployment-identity.md)
- [Umbrel community app store template](https://github.com/getumbrel/umbrel-community-app-store)
- [Official Umbrel app packages](https://github.com/getumbrel/umbrel-apps)

## Session handoff checklist

At the end of each development session:

1. Update **Current status** and **Next action** near the top of this document.
2. Record completed runtime checks in **Validation record**.
3. Add newly discovered constraints to **Known risks and open questions**.
4. Record image tags and multi-architecture digests when they change.
5. Note any deviation from upstream Compose and why it is needed on Umbrel.
6. Run static validation and record anything that could not be tested.
7. Never write secret values into this document, Git history, screenshots, or logs.
