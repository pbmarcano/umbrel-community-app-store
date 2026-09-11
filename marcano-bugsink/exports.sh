export APP_MARCANO_BUGSINK_SECRET_KEY="$(derive_entropy "env-${app_entropy_identifier}-secret-key")"
