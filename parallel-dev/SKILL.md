---
name: parallel-dev
description: Gives each AI agent, branch or test suite its own isolated local WordPress site at scenario.plugin.localhost, created in seconds on native nginx, PHP-FPM and MariaDB. Use for WordPress test sites.
license: GPL-3.0. Full text at https://www.gnu.org/licenses/gpl-3.0.html
compatibility: Linux, WSL2 or macOS with nginx, PHP-FPM, MariaDB or MySQL, and WP-CLI installed. Claude Code or another agent that can run shell commands. One-time server setup needs sudo.
metadata:
  author: Super Speedy Plugins
  version: "1.0.0"
---

# Parallel WordPress development sites

When several agents (or one agent and a human) work on WordPress plugins in a single install,
a half-saved file in one plugin is a fatal error for everyone: the whole site returns 500, and
every other agent sees the breakage as if it were their own. Tests run on that install also
leave products, options and users behind for the next run to trip over.

The fix is one WordPress per agent, branch or scenario. A site here costs a directory and a
database, takes a few seconds to create, and needs no new nginx config: nginx works out the
document root from the hostname.

```
http://<scenario>.<plugin>.localhost:8081/  ->  $PD_SITES_ROOT/<plugin>/<scenario>/
http://<plugin>.localhost:8081/             ->  $PD_SITES_ROOT/<plugin>/default/
```

`*.localhost` resolves to 127.0.0.1 on Linux, macOS and recent browsers without touching
`/etc/hosts`. Every site has its own database, its own database user with access to that
database only, its own keys and salts, and its own object-cache key prefix and Redis database.
Sites share only the nginx, PHP-FPM and MariaDB processes.

All scripts are in this skill's `scripts/` folder. Paths below are relative to the skill folder.

## First-time setup

If `scripts/list-sites.sh` reports `no sites root`, or a site URL does not load, the machine
needs the one-time setup. **Ask the user before running anything with sudo**, and show them the
commands. Read `setup.md` for the steps; it covers Ubuntu/Debian/WSL2 and macOS with Homebrew.

Settings are environment variables, optionally kept in `~/.config/parallel-dev/env`:

| Variable | Default | Meaning |
|---|---|---|
| `PD_SITES_ROOT` | `/var/www/sites` | Where sites live. Must match the nginx config |
| `PD_PORT` | `8081` | The port nginx listens on. Must match the nginx config |
| `PD_PLUGINS_DIR` | `~/dev` | Where the user's plugin repositories are checked out |
| `PD_ADMIN_USER` | `admin` | The admin account on every site |
| `PD_ADMIN_PASS` | generated | Generated on first use and saved in the env file |

Never print `PD_ADMIN_PASS` or write it into a repository. Tell the user where it is kept.

## Procedure

**1. See what exists.** The filesystem is the registry.

```bash
scripts/list-sites.sh [plugin]
```

**2. Reuse a suitable site, or create one.** Names are lowercase letters, digits and hyphens,
because they become hostname labels. Use the plugin's full folder name as `<plugin>`; the
plugin is symlinked from `$PD_PLUGINS_DIR/<plugin>`, so edits in the repository are live on
the site with nothing to copy back.

```bash
scripts/create-site.sh <plugin> [scenario]
```

**3. Install what the work needs, from inside the site directory.**

```bash
cd "$PD_SITES_ROOT/<plugin>/<scenario>"
wp plugin install woocommerce --activate
wp plugin activate <plugin>
```

For WooCommerce, also turn off coming-soon mode, or logged-out requests (curl, Playwright)
see an empty shop while wp-admin looks fine:

```bash
wp option update woocommerce_coming_soon no
wp option update woocommerce_store_pages_only no
```

**4. Give the user the full URL** (`http://<scenario>.<plugin>.localhost:8081/`), so they can
click through and check the result themselves.

**5. Reset a site that has drifted**, rather than creating another one:

```bash
scripts/reset-site.sh <plugin> [scenario]
```

Reset and delete refuse any directory whose `wp-config.php` was not written by these scripts.

## Test data: never one WP-CLI call per item

Do not populate a site by calling WP-CLI once per product, post or user, for example a shell
loop around `wp wc product create`. Every call starts PHP and boots WordPress and every active
plugin again, so the boot costs more than the product. For anything beyond a handful of items:

1. **Best:** put the data in a CSV and import it with a bulk importer. Super Speedy Imports
   Lite is free on wordpress.org and maps columns automatically:

   ```bash
   wp plugin install super-speedy-imports-lite --activate
   wp ssi create "Test data" product products.csv   # prints the new import's ID
   wp ssi <id>
   ```

   Columns named `SKU`, `Name`, `Description`, `Regular_Price`, `Stock` and `Categories`
   (with `>` between parent and child, for example `Clothing>Shirts`) map on their own.
   Re-running the import updates the same products by SKU instead of duplicating them.

2. **Otherwise:** one `wp eval-file` process that loops over the data and calls the
   WordPress or WooCommerce API (`wp_insert_post`, `new WC_Product_Simple()` then `save()`).
   WordPress boots once instead of once per item.

Write the CSV with a fixed random seed, so every run and every site gets the same data.

## Rules

1. **One site per agent or per scenario.** The agent is what makes half-finished edits, so the
   agent is the unit of isolation. One agent working across related plugins can share a site.
2. **Never run the scripts as root.** Files must belong to the user PHP-FPM runs as.
3. **Do not add nginx config per site.** The wildcard server block already covers every site.
4. **Sites are disposable.** Keep nothing in one that cannot be rebuilt. The plugin code lives
   in its repository, which is version controlled.
5. **Clear on the way in, never on the way out.** A test suite gets its own site
   (`tests-<purpose>`), resets it or clears its own fixtures when it starts, and leaves the
   result behind, so the user can log in and see what the tests actually produced. A suite
   that tidies up after itself destroys the evidence of a failure.
6. **Refuse to run a suite against anything outside `$PD_SITES_ROOT`**, so a test can never
   reset the user's own working site.

## Smoke-testing a built zip

For a test that needs an empty WordPress with a plugin installed from its built zip:

```bash
source scripts/smoke.sh
pd_smoke_start <tag> <plugin> /path/to/plugin.zip
wpc plugin list          # wp, pointed at the smoke site
curl -s "$PD_SMOKE_URL/"
```

The site is `http://smoke-<tag>.<plugin>.localhost:8081/`. The previous run of the same tag is
cleared when the next one starts, never at exit, so a failed smoke leaves its site to inspect.
Two runs of the same tag at once collide; use a different tag for each concurrent smoke.

## Keeping core current

New sites are copied from a pristine core at `$PD_SITES_ROOT/.core`, which is why creating one
needs no network. Refresh it after a WordPress release; existing sites are not touched.

```bash
scripts/update-core.sh [version]
```
