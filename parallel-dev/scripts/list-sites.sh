#!/usr/bin/env bash
# list-sites.sh [plugin] - every site that exists. The filesystem is the registry, so this
# cannot drift out of step with reality the way a tracked list would.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
FILTER="${1:-}"
[ -d "$SITES_ROOT" ] || pd_die "no sites root at $SITES_ROOT"
found=0
for plugin_dir in "$SITES_ROOT"/*/; do
    plugin=$(basename "$plugin_dir")
    case "$plugin" in .*) continue ;; esac
    [ -z "$FILTER" ] || [ "$plugin" = "$FILTER" ] || continue
    for scenario_dir in "$plugin_dir"*/; do
        [ -f "$scenario_dir/wp-config.php" ] || continue
        found=1
        printf '  %-60s %s\n' "$(pd_site_url "$plugin" "$(basename "$scenario_dir")")" "$scenario_dir"
    done
done
[ "$found" = 1 ] || printf '  no sites yet%s\n' "${FILTER:+ for $FILTER}"
