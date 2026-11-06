#!/usr/bin/env bash
# delete-site.sh <plugin> [scenario] - remove a site and its database for good.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
PLUGIN="${1:-}"; SCENARIO="${2:-default}"
[ -n "$PLUGIN" ] || pd_die "usage: delete-site.sh <plugin> [scenario]"
pd_check_name "$PLUGIN"; pd_check_name "$SCENARIO"
DIR=$(pd_site_dir "$PLUGIN" "$SCENARIO")
[ -d "$DIR" ] || pd_die "no such site: $DIR"
pd_assert_ours "$DIR" "$PLUGIN" "$SCENARIO"
pd_info "deleting $DIR and its database"
chmod -R u+w "$DIR"; rm -rf "$DIR"
pd_drop_db "$PLUGIN" "$SCENARIO"
