#!/usr/bin/env bash
# A fresh WordPress for a smoke test of a BUILT plugin zip. Sourced by a test script:
#
#   source /path/to/parallel-dev/scripts/smoke.sh
#   pd_smoke_start <tag> <plugin> /path/to/plugin.zip
#   wpc plugin list               # wp, pointed at the smoke site
#   curl -s "$PD_SMOKE_URL/"      # served by nginx
#
# The site is http://smoke-<tag>.<plugin>.localhost:<port>/. It is cleared when the NEXT run
# starts, never when this one ends, so a failed run leaves its evidence behind to inspect.

_pd_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_pd_here/lib.sh"
# lib.sh sets -e; smoke tests are usually written as `check || fail` and need it off.
set +e

PD_SMOKE_DIR=""; PD_SMOKE_URL=""

pd_smoke_start() {
    local tag="$1" plugin="$2" zip="${3:-}" scenario pass
    scenario="smoke-$tag"
    pd_check_name "$plugin"; pd_check_name "$scenario"
    [ -d "$CORE_DIR" ] || { echo "no pristine core at $CORE_DIR - run update-core.sh" >&2; return 1; }
    PD_SMOKE_DIR=$(pd_site_dir "$plugin" "$scenario")
    PD_SMOKE_URL=$(pd_site_url "$plugin" "$scenario")
    pass=$(pd_admin_pass)

    # Clear the PREVIOUS run on the way in.
    if [ -d "$PD_SMOKE_DIR" ]; then ( pd_assert_ours "$PD_SMOKE_DIR" "$plugin" "$scenario" ) || return 1; chmod -R u+w "$PD_SMOKE_DIR"; rm -rf "$PD_SMOKE_DIR"; fi
    pd_drop_db "$plugin" "$scenario" 2>/dev/null

    mkdir -p "$PD_SMOKE_DIR" && cp -R "$CORE_DIR"/. "$PD_SMOKE_DIR"/ || return 1
    mkdir -p "$PD_SMOKE_DIR/wp-content/plugins"
    ( set -e; pd_write_config "$PD_SMOKE_DIR" "$plugin" "$scenario" ) || return 1
    wp --path="$PD_SMOKE_DIR" core install --url="$PD_SMOKE_URL" --title="smoke-$tag" \
        --admin_user="$ADMIN_USER" --admin_password="$pass" --admin_email="$ADMIN_EMAIL" \
        --skip-email --quiet || return 1
    [ -z "$zip" ] || wp --path="$PD_SMOKE_DIR" plugin install "$zip" --activate --quiet || return 1
    echo "    [smoke] $PD_SMOKE_URL  (left in place for inspection)" >&2
}

wpc() { wp --path="$PD_SMOKE_DIR" "$@"; }
