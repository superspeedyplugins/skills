#!/usr/bin/env bash
# reset-site.sh <plugin> [scenario] - destroy and recreate a site. Everything in it is
# disposable by design; the plugin under test is a symlink, so no work is lost.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
PLUGIN="${1:-}"; SCENARIO="${2:-default}"
[ -n "$PLUGIN" ] || pd_die "usage: reset-site.sh <plugin> [scenario]"
pd_check_name "$PLUGIN"; pd_check_name "$SCENARIO"
DIR=$(pd_site_dir "$PLUGIN" "$SCENARIO")
if [ -d "$DIR" ]; then
    pd_assert_ours "$DIR" "$PLUGIN" "$SCENARIO"
    pd_info "removing $DIR and its database"
    chmod -R u+w "$DIR"; rm -rf "$DIR"
    pd_drop_db "$PLUGIN" "$SCENARIO"
fi
exec "$(dirname "${BASH_SOURCE[0]}")/create-site.sh" "$PLUGIN" "$SCENARIO"
