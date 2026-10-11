# Stable per-install secret derived from Umbrel's device seed; signs session cookies.
export APP_MARCANO_TUDUDI_SESSION_SECRET="$(derive_entropy "${app_entropy_identifier}-session-secret")"
