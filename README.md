# Deploy and Host WooCommerce on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/woo-commerce?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=woo-commerce)

[WooCommerce](https://woocommerce.com/) is the open-source online store that runs on WordPress: products, cart, checkout, orders, taxes and shipping, with thousands of extensions and themes. This template installs WordPress and WooCommerce on the first boot, so the deploy ends at a working store with an admin login, not at a setup page anyone can claim.

## About Hosting WooCommerce

Two services: the store (WordPress 7.1, PHP 8.3 and Apache, with WooCommerce 11.3) and a private MariaDB. Each has its own volume.

- **Installed before it goes public.** A fresh WordPress shows its installer to whoever opens the URL first. Here WordPress is installed on the first boot, before the site answers, with a generated admin password. WooCommerce is activated, its tables are created, and the Shop, Cart, Checkout and My account pages exist when you first sign in. MariaDB has generated passwords and no public proxy.
- **Sized to the plan.** Apache's worker count is set from the service's memory limit, so a small service queues requests instead of running out of memory. Tested on 0.5 GB services: after bulk product imports, reports and a guest order, the store read about 250 MB on Railway's meter and MariaDB about 135 MB.
- **Limits for a real shop.** 128 MB uploads (the stock image stops at 2 MB), 256 MB of PHP memory, 5-minute requests for imports, pretty permalinks on, and WP-CLI built in.
- **Real visitor addresses.** Orders and rate limits see the customer's IP, not Railway's edge.

## Common Use Cases

- A store of your own for physical or digital products, without a monthly platform fee
- A client shop for freelancers and agencies, handed over with the admin login
- A staging copy of an existing WooCommerce shop to test themes, plugins and updates
- A headless store: the WooCommerce REST and Store APIs behind your own frontend

## Dependencies for WooCommerce Hosting

- MariaDB 11.8 LTS (included, private network only)

### Deployment Dependencies

- [WooCommerce documentation](https://woocommerce.com/documentation/woocommerce/)
- [WordPress documentation](https://wordpress.org/documentation/)
- [WP-CLI commands](https://developer.wordpress.org/cli/commands/) and [WooCommerce CLI](https://developer.woocommerce.com/docs/wc-cli/wc-cli-overview/)
- [Template source on GitHub](https://github.com/two-workspaces/woocommerce)

### Implementation Details

**Sign in** at `https://<your domain>/wp-admin` with the username `admin` and the `WP_ADMIN_PASSWORD` value from the WooCommerce service's Variables tab. WooCommerce then walks you through its setup: store location, currency, payments, shipping. Change the admin email under Settings → General, because order notifications go there.

**Launching.** Until you launch the store, visitors see WooCommerce's "Coming soon" page instead of your shop. That is WooCommerce's own default for a new store. Switch it off under WooCommerce → Settings → Site visibility when you are ready.

**Variables**, all read on the first boot only:

| Variable | What it does |
| --- | --- |
| `WP_ADMIN_USER`, `WP_ADMIN_PASSWORD` | The first administrator. Change the password later under Users → Profile. |
| `WP_ADMIN_EMAIL` | The administrator's email address. |
| `WP_SITE_TITLE` | The store's name. |

**Email.** WooCommerce sends order confirmations and password resets by email, and the container has no mail server. Railway allows outbound SMTP only on the Pro plan. On any plan, install a mail plugin that sends through an email provider's HTTPS API, such as FluentSMTP or WP Mail SMTP with Brevo, Mailgun, Postmark or SendGrid. Until you set one up, the store can't send mail.

Notes and limits:

- **Updates.** WordPress, WooCommerce, themes and plugins update from the dashboard as usual, and they live on the volume. Redeploying a newer image of this template changes PHP and Apache, not your store's files.
- **Custom domain.** Add it in the service's Settings, then set both addresses under Settings → General in WordPress to the new domain.
- **WP-CLI.** In a `railway ssh` session on the WooCommerce service, `wp` runs as the web server's user: `wp wc product list --user=1`, `wp plugin update --all`, `wp db export backup.sql`.
- **Backups.** Nothing is backed up for you. Use a backup plugin that stores copies off the server, or run `wp db export` and copy `wp-content` on your own schedule.
- **More traffic.** A 0.5 GB service serves up to 5 requests at once and a 1 GB service 12. Give the store more memory for more, or set `WP_APACHE_WORKERS` yourself.
- **Deactivating WooCommerce** is respected: the template sets the store up once and does not switch it back on.

## Why Deploy WooCommerce on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying WooCommerce on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
