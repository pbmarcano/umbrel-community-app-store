# Bugsink for Umbrel

This document records the research, packaging decisions, and remaining runtime checks
for `marcano-bugsink`.

Last research pass: 2026-09-08

## Objective

Run a small, private Bugsink installation on Umbrel as a Sentry-compatible error
collector for Rails applications, replacing a lightly used hosted error-tracking
subscription without giving up grouped exceptions, releases, alerts, or the existing
Sentry Ruby SDK integration.

## Upstream findings

- Bugsink focuses on error events. It intentionally does not provide Sentry-style
  tracing or metrics.
- The server accepts Sentry SDK traffic, including the Ruby SDK used by Rails apps.
- The current stable release is `2.5.1` (2026-08-31). Its Docker image supports both
  `linux/amd64` and `linux/arm64`.
- The image normally runs as its own non-root `bugsink` user (UID/GID 14237), runs
  database migrations before Gunicorn starts, and runs the Snappea background worker
  in the same container. The Umbrel mapping runs it as the equally non-root UID/GID
  1000 so its bind-mounted app-data directory is writable.
- The built-in readiness endpoint is `/health/ready` on internal port `8000`.
- `CREATE_SUPERUSER=email:password` creates the initial account only when no user
  exists. Leaving the value in the environment is therefore safe across restarts.
- `BASE_URL` is operationally important: Bugsink uses it to generate project DSNs,
  alert links, invitation links, and password-reset links.
- Bugsink defaults to phoning home with basic installation information. This package
  opts out with `PHONEHOME=false`.

Source links:

- <https://github.com/bugsink/bugsink>
- <https://www.bugsink.com/docs/docker-install/>
- <https://www.bugsink.com/docs/docker-compose-install/>
- <https://www.bugsink.com/docs/settings/>
- <https://www.bugsink.com/docs/proxy-headers/>
- <https://www.bugsink.com/docs/sdk-recommendations/>

## License note

Most of Bugsink is licensed under PolyForm Shield 1.0.0, with separately licensed
components called out in its `LICENSE`. That is a source-available license with a
noncompete restriction, not an OSI-approved open-source license. This package only
describes and pulls Bugsink's official image; it does not rebuild or redistribute a
modified Bugsink image. Review the upstream license before any commercial or
competitive use.

## Architecture decision

Use the smallest topology Bugsink supports:

| Service | Role | Persistent data |
| --- | --- | --- |
| `app_proxy` | Umbrel HTTP entry point | None |
| `web` | Bugsink UI, ingestion API, SQLite database, migrations, and Snappea worker | `data/db.sqlite3` |

This deliberately differs from the current upstream Compose sample, which adds
PostgreSQL. Bugsink is designed around SQLite and calls it the recommended database
outside containers. For this low-volume, single-node installation, PostgreSQL's
extra process, credentials, memory, backup procedure, and upgrade surface are not
justified.

Upstream does warn against SQLite on Docker volumes because its WAL mode requires
reliable filesystem locking and durability semantics. Umbrel maps `/data` directly to
a directory on the host's local filesystem rather than to network storage. That makes
SQLite a reasonable pragmatic choice here, but the warning still matters: keep app
data on Umbrel's local disk, do not relocate it to NFS/SMB, and validate backup and
restore before relying on the service. PostgreSQL remains the upgrade path if event
volume or write concurrency becomes substantial.

The Snappea queue database intentionally remains temporary inside the web container.
Upstream describes it as a local coordination queue, not application data, and warns
against putting it on shared or persistent storage.

## Image pins

```text
bugsink/bugsink:2.5.1
sha256:ecdd845877464d70d61244b8adba20d623e1860e88d8338f2808d9cc2925745c
```

The Bugsink digest is the multi-platform OCI index and contains native AMD64 and
ARM64 manifests.

## Authentication and exposure

`PROXY_AUTH_ADD=false` is required. A Rails server reporting an exception cannot
present an Umbrel browser session cookie, so enabling Umbrel proxy authentication
would reject every SDK envelope. Bugsink supplies the correct security boundaries:

- its UI requires a Bugsink user session;
- event ingestion requires the public key embedded in a project's DSN;
- no database or secondary service is exposed.

The initial login is:

```text
Username: admin@umbrel.local
Password: the deterministic app password shown by Umbrel
```

The Django secret key is derived from the Umbrel app entropy. It is stable across
restarts and is never committed.

## URL and reverse-proxy decision

The package initially uses:

```text
BASE_URL=http://${DEVICE_DOMAIN_NAME}:3781
BEHIND_PLAIN_HTTP_PROXY=true
BEHIND_HTTPS_PROXY=false
```

This makes the first install work over Umbrel's normal LAN URL. It is only suitable
for Rails applications that can resolve and reach the Umbrel host.

For an Internet-hosted Rails app, choose a stable HTTPS hostname before creating the
real Bugsink projects. Route that hostname through a TLS-enabled reverse proxy or
tunnel to Umbrel port `3781`, then change the package to:

```yaml
BASE_URL: https://errors.example.com
BEHIND_PLAIN_HTTP_PROXY: "false"
BEHIND_HTTPS_PROXY: "true"
```

The outer proxy must preserve the original `Host` header and send
`X-Forwarded-Proto: https` and `X-Real-IP`. Restart Bugsink after changing these
values. Existing project keys remain valid, but copy the regenerated DSNs into the
Rails applications because the hostname is part of every DSN.

Do not expose container port `8000` directly. The only public route should terminate
at the Umbrel app port.

## Rails migration from Honeybadger

Bugsink is a replacement for error collection, not every Honeybadger feature. Confirm
whether the Rails apps rely on uptime checks, cron/heartbeat monitoring, performance
tracing, or deployment tracking before canceling Honeybadger; Bugsink deliberately
concentrates on errors.

For each Rails app:

1. Create a Bugsink project and copy the DSN shown by its setup page.
2. Add `sentry-ruby` and `sentry-rails` if they are not already installed.
3. Put the project DSN in the Rails app's secret environment, such as `SENTRY_DSN`.
4. Configure the SDK with tracing disabled. Bugsink recommends enabling default PII
   only if that matches the application's privacy policy.
5. Deploy, deliberately capture one test exception, and confirm its stacktrace,
   environment, release, and request context in Bugsink.
6. Run Honeybadger and Bugsink in parallel briefly, then remove Honeybadger only after
   the real production delivery path is proven.

A minimal initializer shape is:

```ruby
Sentry.init do |config|
  config.dsn = ENV.fetch("SENTRY_DSN")
  config.traces_sample_rate = 0
  config.send_default_pii = true
end
```

Use a release identifier from the deployment process if release-aware resolution is
important. Do not commit the DSN even though it is an ingestion key rather than an
administrator password.

## Email and alerts

Email is intentionally unconfigured in the initial package. Bugsink will still run,
and current releases can display invitation/setup links for manual sharing. To use
email alerts and password resets, add the documented `EMAIL_HOST`, credentials, port,
TLS/SSL, and `DEFAULT_FROM_EMAIL` variables. Chat alerts can instead be configured per
project in Bugsink.

## Retention and backups

Upstream retention limits are left unset so the initial package does not silently
delete error history. After observing real event volume, configure either an age or
event-count limit. The relevant settings include `MAX_EVENT_AGE_DAYS`,
`MAX_RETENTION_EVENT_COUNT`, and `MAX_RETENTION_PER_PROJECT_EVENT_COUNT`.

Back up all of `${APP_DATA_DIR}/data`, including the SQLite database and its `-wal`
and `-shm` companions if they exist. A live file-level copy can be inconsistent, so
prefer an Umbrel backup mechanism that stops/quiesces the app, or use SQLite's online
backup API. Bugsink runs migrations automatically on container start, so take a
backup before changing the pinned Bugsink version.

## Validation status

Completed statically:

- [x] Mapped the current upstream Compose services and settings.
- [x] Chose single-container SQLite for the low-volume Umbrel use case and recorded
  the upstream WAL/filesystem caveat.
- [x] Pinned the Bugsink multi-architecture image index.
- [x] Kept all durable state under `${APP_DATA_DIR}`.
- [x] Added deterministic per-install secrets and initial credentials.
- [x] Routed only port 8000 through `app_proxy` and disabled proxy auth for SDKs.

Required on a real Umbrel before considering the package production-ready:

- [ ] Install through the community app store and confirm the service becomes healthy.
- [ ] Log in with the credentials shown by Umbrel.
- [ ] Create a project and send a test event from a Rails app on the same network.
- [ ] Restart and recreate the container; confirm users, projects, and issues persist.
- [ ] Configure the final HTTPS hostname and validate UI login plus SDK ingestion.
- [ ] Confirm the reverse proxy preserves `Host`, `X-Forwarded-Proto`, and `X-Real-IP`.
- [ ] Test a consistent SQLite backup and restore on a disposable install.
- [ ] Record actual memory, CPU, database growth, and event throughput.
