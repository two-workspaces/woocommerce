# Pinned: a moving tag (wordpress:latest, :apache) would rebase every deploy of this
# template at once. Bump deliberately. This fixes PHP, Apache and the versions of the
# first install; after that WordPress and WooCommerce update themselves from the
# dashboard as usual.
FROM wordpress:7.1.5-php8.3-apache

# The MariaDB client that `wp db export` and `wp db import` run.
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends mariadb-client; \
	rm -rf /var/lib/apt/lists/*

# WP-CLI, checksum-verified.
RUN set -eux; \
	curl -fsSL -o /usr/local/lib/wp-cli.phar https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar; \
	echo 'be928f6b8ca1e8dfb9d2f4b75a13aa4aee0896f8a9a0a1c45cd5d2c98605e6172e6d014dda2e27f88c98befc16c040cbb2bd1bfa121510ea5cdf5f6a30fe8832  /usr/local/lib/wp-cli.phar' | sha512sum -c -; \
	printf 'path: /var/www/html\n' > /etc/wp-cli.yml
ENV WP_CLI_CONFIG_PATH=/etc/wp-cli.yml WP_CLI_CACHE_DIR=/tmp/wp-cli-cache

# WooCommerce from wordpress.org, checksum-verified. It goes into the image's WordPress
# source, so the first boot copies it onto the volume with the rest. When you bump the
# version, replace the checksum with the new zip's sha256.
# upgrade: github woocommerce/woocommerce
ARG WOOCOMMERCE_VERSION=11.3.1
ARG WOOCOMMERCE_SHA256=1502600c738840f7f9ebfa2f11e1aaff087221a5fc5a2006c51be2d874ae2a09
RUN set -eux; \
	curl -fsSL -o /tmp/woocommerce.zip "https://downloads.wordpress.org/plugin/woocommerce.${WOOCOMMERCE_VERSION}.zip"; \
	echo "${WOOCOMMERCE_SHA256}  /tmp/woocommerce.zip" | sha256sum -c -; \
	php -r '$z = new ZipArchive; exit($z->open("/tmp/woocommerce.zip") === true && $z->extractTo("/usr/src/wordpress/wp-content/plugins") ? 0 : 1);'; \
	rm /tmp/woocommerce.zip; \
	test -f /usr/src/wordpress/wp-content/plugins/woocommerce/woocommerce.php; \
	chown -R www-data:www-data /usr/src/wordpress/wp-content/plugins/woocommerce

# The stock limits reject most themes, plugins and product images (2 MB uploads), and
# the image's OPcache holds 4000 files where WordPress with WooCommerce has over 6000.
RUN printf '%s\n' 'upload_max_filesize = 128M' 'post_max_size = 128M' 'memory_limit = 256M' 'max_execution_time = 300' 'expose_php = Off' \
		'opcache.max_accelerated_files = 12000' \
	> /usr/local/etc/php/conf.d/railway.ini

# Apache on Railway's $PORT, IPv6 and IPv4 (the [::] socket takes both where it can,
# and Apache falls back to IPv4 alone on hosts without IPv6). Errors go to stdout:
# Railway paints all of stderr red, including Apache's startup notices.
ENV PORT=8080
RUN set -eux; \
	printf 'Listen [::]:${PORT}\nListen 0.0.0.0:${PORT}\n' > /etc/apache2/ports.conf; \
	sed -i 's/<VirtualHost \*:80>/<VirtualHost *:${PORT}>/' /etc/apache2/sites-available/000-default.conf; \
	grep -q 'VirtualHost \*:${PORT}' /etc/apache2/sites-available/000-default.conf; \
	ln -sfT /dev/stdout /var/log/apache2/error.log; \
	sed -i 's/^ServerTokens OS/ServerTokens Prod/; s/^ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf; \
	mkdir -p /usr/local/share/railway; \
	echo ok > /usr/local/share/railway/healthz
COPY railway.conf /etc/apache2/conf-enabled/railway.conf

# The visitor's address: Railway's edge connects from 100.64.0.0/10 and sets X-Real-IP
# to the client (overwriting what the client sent). The image reads X-Forwarded-For
# from private ranges only; on Railway that logged the edge, and X-Forwarded-For also
# ends in an edge hop, so WooCommerce (orders, rate limits, geolocation) saw the proxy
# for everyone.
RUN printf '%s\n' 'RemoteIPHeader X-Real-IP' 'RemoteIPInternalProxy 100.64.0.0/10' > /etc/apache2/conf-available/remoteip.conf

COPY --chmod=0755 wp /usr/local/bin/
COPY --chmod=0755 railway-entrypoint.sh /railway-entrypoint.sh
ENTRYPOINT ["/railway-entrypoint.sh"]
# The PHP image stops Apache with SIGWINCH; the entrypoint handles SIGTERM, which is
# also what Railway sends.
STOPSIGNAL SIGTERM
