# Public prototype identity. Buzz binds a community to the authority in this URL,
# so changing it after real use requires deliberate migration and validation.
export APP_MARCANO_BUZZ_RELAY_URL="wss://buzz.jerseyplebs.com"
export APP_MARCANO_BUZZ_MEDIA_BASE_URL="https://buzz.jerseyplebs.com/media"
export APP_MARCANO_BUZZ_CORS_ORIGINS="https://buzz.jerseyplebs.com"
export APP_MARCANO_BUZZ_RELAY_OWNER_PUBKEY="9c83fc9cc0d76e2c11dc6cec8152bc72318f3f6110aea1d4da065140dab9f8b5"

# Stable, independent per-install secrets derived from Umbrel's device seed. The
# owner's Nostr private key is intentionally not stored or derived here.
export APP_MARCANO_BUZZ_RELAY_PRIVATE_KEY="$(derive_entropy "${app_entropy_identifier}-relay-private-key")"
export APP_MARCANO_BUZZ_GIT_HMAC_SECRET="$(derive_entropy "${app_entropy_identifier}-git-hook-hmac-secret")"
export APP_MARCANO_BUZZ_POSTGRES_PASSWORD="$(derive_entropy "${app_entropy_identifier}-postgres-password")"
export APP_MARCANO_BUZZ_REDIS_PASSWORD="$(derive_entropy "${app_entropy_identifier}-redis-password")"
export APP_MARCANO_BUZZ_S3_ACCESS_KEY="$(derive_entropy "${app_entropy_identifier}-s3-access-key")"
export APP_MARCANO_BUZZ_S3_SECRET_KEY="$(derive_entropy "${app_entropy_identifier}-s3-secret-key")"
