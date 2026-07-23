#!/usr/bin/env bash
#
# Umbrel sources this file at app start, AFTER it has exported ${APP_DATA_DIR}.
# Its job: read the Rails master key from a file that lives ONLY on this Umbrel box
# — never in git, never in the Docker image — and hand it to the container as an
# env var. This is the same "secret lives in the app data dir" pattern Umbrel's own
# bitcoin app uses (see getumbrel/umbrel-apps/bitcoin/exports.sh).
#
# You create this file once, over SSH, before first launch (see README.md):
#   ~/umbrel/app-data/laurenandpete-wedding/data/master.key

MASTER_KEY_FILE="${APP_DATA_DIR}/data/master.key"

if [[ -f "${MASTER_KEY_FILE}" ]]; then
  # tr strips any trailing newline so RAILS_MASTER_KEY is exactly the 32-char hex.
  export RAILS_MASTER_KEY="$(tr -d '[:space:]' < "${MASTER_KEY_FILE}")"
else
  >&2 echo "laurenandpete-wedding: ${MASTER_KEY_FILE} not found."
  >&2 echo "  Create it (your config/master.key contents) before starting the app — see README.md."
fi
