#!/usr/bin/env bash
# update-core.sh [version] - download the pristine WordPress core that new sites are copied
# from (default: latest). Existing sites are untouched.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
V="${1:-latest}"
pd_info "refreshing $CORE_DIR to WordPress $V"
mkdir -p "$CORE_DIR"
( cd "$CORE_DIR" && wp core download --version="$V" --skip-content --force --quiet )

# --skip-content keeps core small but drops every theme, and a site with no theme renders
# nothing, so every front-end check fails for a reason unrelated to your code.
THEME="${PD_DEFAULT_THEME:-twentytwentyfive}"
if [ ! -d "$CORE_DIR/wp-content/themes/$THEME" ]; then
    mkdir -p "$CORE_DIR/wp-content/themes"
    tmp=$(mktemp -d)
    curl -sSfLo "$tmp/theme.zip" "https://downloads.wordpress.org/theme/$THEME.zip"
    unzip -q -o "$tmp/theme.zip" -d "$CORE_DIR/wp-content/themes/"
    rm -rf "$tmp"
    pd_info "added the default theme $THEME"
fi
pd_info "done"
