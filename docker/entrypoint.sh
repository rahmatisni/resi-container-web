#!/usr/bin/env bash
set -e

# Jalankan sebagai www-data untuk operasi file Laravel
run_as_www() {
  su-exec www-data:www-data "$@"
}

# Pastikan permission benar
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache || true

# Buat APP_KEY jika belum ada
if [ ! -f /var/www/html/.env ] && [ -f /var/www/html/.env.example ]; then
  cp /var/www/html/.env.example /var/www/html/.env
fi

if ! grep -q "^APP_KEY=base64:" /var/www/html/.env 2>/dev/null; then
  echo ">> Generating APP_KEY"
  run_as_www php artisan key:generate --force || true
fi

# Storage link (aman jika sudah ada)
run_as_www php artisan storage:link >/dev/null 2>&1 || true

# Cache config/route/views kalau APP_ENV=production
if [ "$APP_ENV" = "production" ]; then
  echo ">> Caching Laravel config/routes/views"
  run_as_www php artisan config:cache || true
  run_as_www php artisan route:cache || true
  run_as_www php artisan view:cache || true
fi

# Opsional: tunggu DB & migrasi (set RUN_MIGRATIONS=1)
if [ "${RUN_MIGRATIONS}" = "1" ] && [ -n "$DB_HOST" ]; then
  echo ">> Waiting for DB ${DB_HOST}:${DB_PORT:-3306} ..."
  for i in {1..60}; do
    mariadb --host="${DB_HOST}" --port="${DB_PORT:-3306}" --user="${DB_USERNAME:-root}" --password="${DB_PASSWORD:-}" -e "SELECT 1" >/dev/null 2>&1 && break
    sleep 2
  done
  echo ">> Running migrations"
  run_as_www php artisan migrate --force || true
fi

exec "$@"
