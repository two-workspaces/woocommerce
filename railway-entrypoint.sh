#!/bin/bash
# Railway entrypoint for WooCommerce: WordPress and the store are installed on first
# boot with a generated admin password (no public installer, not even for a moment),
# and Apache is sized from the plan's memory.
set -uo pipefail
log() { echo "railway: $*"; }

# Railway flattens the image layers, which brings back the mpm_event links the PHP
# image deleted, and Apache then refuses to start: "AH00534: More than one MPM
# loaded". mod_php needs prefork only.
rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.*

case "${PORT:-}" in
  ''|*[!0-9]*) log "PORT='${PORT:-}' is not a number, using 8080"; PORT=8080 ;;
esac
export PORT

# Prefork runs one process per concurrent request, and a WooCommerce admin page holds
# far more PHP memory than a plain WordPress page. WORKER_MB is the budget per worker
# after BASE_MB for Apache's parent and OPcache, sized from the plan's memory limit
# (Railway sets the cgroup limit to it), never from the host's 48 CPUs. Workers are
# replaced after 200 requests, so one heavy request doesn't keep its memory for good.
BASE_MB=150
WORKER_MB=64
mem=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo max)
case "$mem" in ''|*[!0-9]*) mem=$((8 << 30)) ;; esac
workers=$(( (mem / 1048576 - BASE_MB) / WORKER_MB ))
workers=$(( workers < 3 ? 3 : workers > 64 ? 64 : workers ))
case "${WP_APACHE_WORKERS:-}" in
  '') ;;
  *[!0-9]*|0) log "WP_APACHE_WORKERS='${WP_APACHE_WORKERS}' is not a number, using $workers" ;;
  *) workers=$WP_APACHE_WORKERS ;;
esac
spare=$(( workers < 5 ? workers : 5 ))
cat > /etc/apache2/conf-enabled/zz-workers.conf <<CFG
<IfModule mpm_prefork_module>
	StartServers 2
	MinSpareServers 1
	MaxSpareServers $spare
	MaxRequestWorkers $workers
	MaxConnectionsPerChild 200
</IfModule>
CFG
log "memory limit $((mem / 1048576)) MB: Apache serves up to $workers requests at once"

# Copy WordPress and WooCommerce onto the volume and write wp-config.php, with its
# salts randomized once and kept on the volume, the way the official image does
# before Apache starts.
docker-ensure-installed.sh true 2>&1 || { log "error: can't copy WordPress onto the volume (is it full?)"; exit 1; }

# On a fresh deploy MariaDB may still be initializing.
for i in $(seq 150); do
  php -r 'mysqli_report(MYSQLI_REPORT_OFF);
          exit(@mysqli_connect(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"),
                               getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME")) ? 0 : 1);' && break
  [ "$i" = 150 ] && { log "error: database not reachable after 5 minutes"; exit 1; }
  sleep 2
done

if ! wp core is-installed 2>/dev/null; then
  if [ -z "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    log "error: no public domain. Generate one in the service's Settings, then redeploy"; exit 1
  fi
  admin_pass=${WP_ADMIN_PASSWORD:-}
  if [ -z "$admin_pass" ]; then
    admin_pass=$(head -c 18 /dev/urandom | base64 | tr -d '/+=')
    log "WP_ADMIN_PASSWORD is empty. The admin password for this install: $admin_pass"
  fi
  log "first boot, installing WordPress"
  wp core install --url="https://${RAILWAY_PUBLIC_DOMAIN}" \
    --title="${WP_SITE_TITLE:-My Store}" --admin_user="${WP_ADMIN_USER:-admin}" \
    --admin_password="$admin_pass" --admin_email="${WP_ADMIN_EMAIL:-admin@example.com}" --skip-email \
    || { log "error: WordPress install failed"; exit 1; }
  wp rewrite structure '/%postname%/'  # WooCommerce needs pretty URLs; the image's .htaccess routes them
fi

# The store, once: activate WooCommerce (it creates its tables) and its Shop, Cart,
# Checkout and My account pages. Recorded in the database, so deactivating WooCommerce
# later is respected. A failure here is logged and tried again on the next start; the
# site still comes up.
if [ "$(wp option get railway_store_setup 2>/dev/null)" != done ]; then
  log "setting up WooCommerce"
  if wp plugin activate woocommerce && wp wc tool run install_pages --user=1 >/dev/null; then
    wp option update railway_store_setup done >/dev/null
    log "WooCommerce $(wp plugin get woocommerce --field=version 2>/dev/null) is ready"
  else
    log "warning: WooCommerce setup did not finish; it will be tried again on the next start"
  fi
fi

trap 'kill $(jobs -p) 2>/dev/null; wait; exit 0' TERM INT
apache2-foreground &
apache_pid=$!

# Apache exiting means the site is down: exit so Railway restarts the service.
wait -n "$apache_pid"
exit 1
