# Marcano Ventures Umbrel App Store

A private Umbrel community app store for Marcano projects and selected self-hosted
software packaged to run locally on umbrelOS.

## Apps

| App | ID | Status |
| --- | --- | --- |
| Buzz Relay | `marcano-buzz-relay` | Experimental prototype |

## Work in progress

- [Buzz relay packaging strategy](docs/buzz-relay.md) — research, architecture,
  decisions, phased implementation plan, and session handoff notes for the first app.

## Add this store to Umbrel

Push this repository to GitHub, then add its repository URL from the Umbrel App
Store's community app store interface. Umbrel reads `umbrel-app-store.yml` and every
valid top-level app directory from the selected branch.

The store ID is `marcano`. Every app directory and its manifest `id` must therefore
start with `marcano-`.

## Port an open-source app

Create one top-level directory per app:

```text
marcano-example/
├── docker-compose.yml
├── umbrel-app.yml
└── exports.sh          # optional; only for computed or file-backed environment values
```

Use the examples below as a structural starting point, but derive the container
configuration from the upstream project's documentation.

### 1. Check the upstream project

Before packaging it, confirm:

- its license permits redistribution;
- it publishes a Docker image for every architecture you need (typically `amd64`
  and `arm64` for Umbrel devices);
- its internal web port and required environment variables are documented;
- all databases, uploads, configuration, and other durable state can be mounted
  beneath `${APP_DATA_DIR}`;
- upgrades and database migrations are non-interactive.

Prefer a versioned, multi-architecture image pinned by digest. Avoid `latest` for a
release you want to reproduce reliably.

### 2. Write `umbrel-app.yml`

The directory name and manifest `id` must match. Choose an unused host `port`, write
real listing metadata, and link `repo` and `support` to the upstream project. Increment
`version` and update `releaseNotes` whenever the package changes.

Minimal shape:

```yaml
manifestVersion: 1
id: marcano-example
name: Example
tagline: A short description
icon: https://example.com/icon.svg
category: utilities
version: "1.0.0"
port: 12345
description: >-
  A useful description of the app and any setup it requires.
developer: Upstream Developer
website: https://example.com
submitter: Pete Marcano
submission: https://github.com/pbmarcano/umbrel-community-app-store
repo: https://github.com/example/example
support: https://github.com/example/example/issues
gallery: []
releaseNotes: "Initial Umbrel package."
dependencies: []
path: ""
defaultUsername: ""
defaultPassword: ""
```

### 3. Write `docker-compose.yml`

Umbrel supplies `app_proxy`; point it at `<app-id>_<service-name>_1` and the port
inside the application container. Do not publish the web UI's port directly unless
the application has a specific non-HTTP networking requirement.

```yaml
version: "3.7"

services:
  app_proxy:
    environment:
      APP_HOST: marcano-example_web_1
      APP_PORT: 8080

  web:
    image: ghcr.io/example/example:1.0.0@sha256:REPLACE_WITH_MULTI_ARCH_DIGEST
    user: "1000:1000"
    restart: on-failure
    init: true
    volumes:
      - ${APP_DATA_DIR}/data:/data
```

Keep credentials out of Git. Prefer an application's browser-based setup flow. If a
secret must be created before startup, store it under `${APP_DATA_DIR}/data` and use
an optional `exports.sh` to expose it to Compose.

### 4. Test before publishing

At minimum, verify:

- the Compose and manifest YAML parse successfully;
- the image exists for the Umbrel machine's CPU architecture;
- install, first-run setup, restart, and upgrade all work;
- app data survives container recreation;
- uninstall/reinstall behavior is understood;
- the UI works through Umbrel's proxy and does not require shell access;
- backups contain every path needed to restore the app.

Commit and push the new directory, refresh this community store in Umbrel, then
install the app from the App Store UI.

## Maintenance notes

- Treat each app directory as an independently versioned package.
- Review upstream release notes before changing an image.
- Pin the tested image digest and bump the manifest version together.
- Back up app data before testing migrations on your primary Umbrel.
- Never commit passwords, API keys, private keys, or `.env` files.

Umbrel's upstream references are the
[community store template](https://github.com/getumbrel/umbrel-community-app-store)
and [official app packages](https://github.com/getumbrel/umbrel-apps).
