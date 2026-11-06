#!/usr/bin/env bash
# Shared settings and helpers for parallel-dev. Sourced by the other scripts, not run.
#
# Configuration comes from environment variables, optionally set in ~/.config/parallel-dev/env
# (or the file named by PD_ENV_FILE). Every setting has a default:
#
#   PD_SITES_ROOT   where sites live; nginx serves <scenario>.<plugin>.localhost from
#                   $PD_SITES_ROOT/<plugin>/<scenario>        (default /var/www/sites)
#   PD_PORT         the port nginx listens on                  (default 8081)
#   PD_PLUGINS_DIR  where your plugin repositories are checked out; the plugin under test is
#                   symlinked from $PD_PLUGINS_DIR/<plugin>    (default ~/dev)
#   PD_ADMIN_USER   admin user created on every site           (default admin)
#   PD_ADMIN_PASS   its password; generated once and saved to the env file if unset
#   PD_ADMIN_EMAIL  its email                                  (default admin@example.com)
#   PD_MIN_FREE_GB  refuse to create a site below this much free disk (default 5)

set -euo pipefail

PD_ENV_FILE="${PD_ENV_FILE:-$HOME/.config/parallel-dev/env}"
[ -f "$PD_ENV_FILE" ] && . "$PD_ENV_FILE"

SITES_ROOT="${PD_SITES_ROOT:-/var/www/sites}"
CORE_DIR="$SITES_ROOT/.core"
PORT="${PD_PORT:-8081}"
PLUGINS_DIR="${PD_PLUGINS_DIR:-$HOME/dev}"
ADMIN_USER="${PD_ADMIN_USER:-admin}"
ADMIN_EMAIL="${PD_ADMIN_EMAIL:-admin@example.com}"

# Xdebug slows every PHP process it is loaded into. Set XDEBUG_MODE yourself to profile.
export XDEBUG_MODE="${XDEBUG_MODE:-off}"

pd_die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
pd_info() { printf '  %s\n' "$*"; }

pd_random_password() { ( set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32 ); }

# One admin password for every site, so you never register a user. Generated on first use and
# kept in the env file (mode 600), never in a script and never printed.
pd_admin_pass() {
    if [ -z "${PD_ADMIN_PASS:-}" ]; then
        PD_ADMIN_PASS=$(pd_random_password)
        mkdir -p "$(dirname "$PD_ENV_FILE")"
        printf 'PD_ADMIN_PASS=%s\n' "$PD_ADMIN_PASS" >> "$PD_ENV_FILE"
        chmod 600 "$PD_ENV_FILE"
        pd_info "generated the admin password for every site; it is in $PD_ENV_FILE" >&2
    fi
    printf '%s' "$PD_ADMIN_PASS"
}

# Refuse to fill the disk. Checks the filesystem the site will be written to.
pd_disk_guard() {
    local dest="${1:-$SITES_ROOT}" min="${PD_MIN_FREE_GB:-5}" free
    while [ ! -e "$dest" ] && [ "$dest" != / ]; do dest=$(dirname "$dest"); done
    free=$(df -P -BG "$dest" 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}')
    [ -n "$free" ] && [ "$free" -lt "$min" ] && pd_die "only ${free} GB free on the filesystem holding $dest (need ${min})"
    return 0
}

# Names become hostname labels, and nginx matches [a-z0-9-]+ per label.
pd_check_name() {
    case "$1" in
        *[!a-z0-9-]*|"") pd_die "'$1' must be lowercase letters, digits and hyphens only" ;;
    esac
}

pd_site_dir() { printf '%s/%s/%s' "$SITES_ROOT" "$1" "$2"; }
pd_site_url() {
    if [ "$2" = default ]; then printf 'http://%s.localhost:%s' "$1" "$PORT"
    else printf 'http://%s.%s.localhost:%s' "$2" "$1" "$PORT"; fi
}

pd_sha1() {
    if command -v sha1sum >/dev/null 2>&1; then sha1sum
    elif command -v shasum >/dev/null 2>&1; then shasum
    else pd_die "neither sha1sum nor shasum is installed"; fi
}

# Database names allow 64 characters and no hyphens. A short hash of the pair stops two long
# names colliding after truncation.
pd_db_name() {
    local raw="${1}_${2}" h
    raw="${raw//-/_}"
    h=$(printf '%s' "$1/$2" | pd_sha1 | cut -c1-6)
    printf 'pd_%.40s_%s' "$raw" "$h"
}
# MySQL caps user names at 32 characters (MariaDB allows 80), so the user is a hash.
pd_db_user() { printf 'pd_%s' "$(printf '%s' "$1/$2" | pd_sha1 | cut -c1-24)"; }

pd_drop_db() {
    mysql -e "DROP DATABASE IF EXISTS \`$(pd_db_name "$1" "$2")\`; DROP USER IF EXISTS '$(pd_db_user "$1" "$2")'@'localhost';"
}

# A distinct Redis database per site, so an object cache cannot serve one site's data to
# another. Redis has 16 by default; 0 is left for anything else on the machine.
pd_redis_db() { printf '%s' $(( 0x$(printf '%s' "$1/$2" | pd_sha1 | cut -c1-4) % 15 + 1 )); }

# Fresh keys and salts, generated locally with no network request.
pd_auth_salts() {
    php -r '
        foreach (["AUTH_KEY", "SECURE_AUTH_KEY", "LOGGED_IN_KEY", "NONCE_KEY",
                  "AUTH_SALT", "SECURE_AUTH_SALT", "LOGGED_IN_SALT", "NONCE_SALT"] as $name) {
            printf("define(%s, %s);\n", var_export($name, true), var_export(bin2hex(random_bytes(32)), true));
        }
    '
}

# Create the database, its own user, and wp-config.php for a site directory.
pd_write_config() {
    local dir="$1" plugin="$2" scenario="$3" db user pass
    db=$(pd_db_name "$plugin" "$scenario"); user=$(pd_db_user "$plugin" "$scenario")
    pass=$(pd_random_password)
    mysql -e "
CREATE DATABASE \`$db\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$user'@'localhost' IDENTIFIED BY '$pass';
GRANT ALL ON \`$db\`.* TO '$user'@'localhost';
FLUSH PRIVILEGES;"
    cat > "$dir/wp-config.php" <<CONF
<?php
define('DB_NAME', '$db');
define('DB_USER', '$user');
define('DB_PASSWORD', '$pass');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

$(pd_auth_salts)

// Per-site isolation. Do not copy these between sites.
define('WP_CACHE_KEY_SALT', '$plugin-$scenario');
define('WP_REDIS_DATABASE', $(pd_redis_db "$plugin" "$scenario"));
define('WP_REDIS_PREFIX', '$plugin-$scenario:');

define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
define('WP_ENVIRONMENT_TYPE', 'local');
define('AUTOMATIC_UPDATER_DISABLED', true);

\$table_prefix = 'wp_';
if ( ! defined('ABSPATH') ) define('ABSPATH', __DIR__ . '/');
require_once ABSPATH . 'wp-settings.php';
CONF
}

# Refuse to delete anything that is not recognisably one of our sites.
pd_assert_ours() {
    local dir="$1" plugin="$2" scenario="$3"
    [ -f "$dir/wp-config.php" ] || pd_die "$dir has no wp-config.php - refusing to delete"
    grep -q "WP_CACHE_KEY_SALT', '$plugin-$scenario'" "$dir/wp-config.php" \
        || pd_die "$dir/wp-config.php was not written by parallel-dev - refusing to delete"
    grep -q "define('DB_NAME', '$(pd_db_name "$plugin" "$scenario")')" "$dir/wp-config.php" \
        || pd_die "$dir/wp-config.php names a different database - refusing to delete"
}
