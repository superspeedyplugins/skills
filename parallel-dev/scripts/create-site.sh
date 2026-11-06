#!/usr/bin/env bash
# create-site.sh <plugin> [scenario]
#
# Creates an isolated WordPress site at http://<scenario>.<plugin>.localhost:<port>/, or
# http://<plugin>.localhost:<port>/ for the `default` scenario, with the plugin symlinked from
# its repository. Adds no nginx config: nginx derives the docroot from the hostname, so making
# the directory is what creates the site. Never run as root.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

PLUGIN="${1:-}"; SCENARIO="${2:-default}"
[ -n "$PLUGIN" ] || pd_die "usage: create-site.sh <plugin> [scenario]"
pd_check_name "$PLUGIN"; pd_check_name "$SCENARIO"
[ "$(id -u)" -ne 0 ] || pd_die "do not run as root - the files must belong to the user php-fpm runs as"
[ -d "$CORE_DIR" ] || pd_die "no pristine core at $CORE_DIR - run update-core.sh first"
pd_disk_guard "$SITES_ROOT"

DIR=$(pd_site_dir "$PLUGIN" "$SCENARIO"); URL=$(pd_site_url "$PLUGIN" "$SCENARIO")
[ ! -d "$DIR" ] || pd_die "site already exists: $DIR ($URL)"
REPO="$PLUGINS_DIR/$PLUGIN"
[ -d "$REPO" ] || pd_info "note: no repository at $REPO, so the plugin is not symlinked"
PASS=$(pd_admin_pass)

pd_info "site      $URL"
pd_info "dir       $DIR"
pd_info "database  $(pd_db_name "$PLUGIN" "$SCENARIO")"

# A local copy of core rather than a download: about a second instead of ten or twenty.
mkdir -p "$DIR"
cp -R "$CORE_DIR"/. "$DIR"/
mkdir -p "$DIR/wp-content/plugins" "$DIR/wp-content/themes" "$DIR/wp-content/uploads"

pd_write_config "$DIR" "$PLUGIN" "$SCENARIO"

( cd "$DIR" && wp core install --url="$URL" --title="$PLUGIN / $SCENARIO" \
    --admin_user="$ADMIN_USER" --admin_password="$PASS" --admin_email="$ADMIN_EMAIL" \
    --skip-email --quiet )

# The plugin under test, symlinked so edits in the repository ARE the site's code.
if [ -d "$REPO" ]; then ln -s "$REPO" "$DIR/wp-content/plugins/$PLUGIN"; fi

pd_info ""
pd_info "created. Log in at $URL/wp-admin as $ADMIN_USER (password in $PD_ENV_FILE)"
