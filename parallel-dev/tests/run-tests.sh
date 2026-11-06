#!/usr/bin/env bash
# run-tests.sh - drive every parallel-dev script against a private, unprivileged nginx and
# PHP-FPM built from this skill's config templates, on port 18081 with its own sites root.
# Needs nginx, php-fpm, MariaDB (with your passwordless account, see setup.md), WP-CLI and
# zip. Touches no system config. Sites and databases it creates are cleared at the START of
# the next run and left behind afterwards for inspection; only the two server processes it
# started are stopped when it exits.
set -uo pipefail

SK=$(cd "$(dirname "$0")/.." && pwd)
T="${PD_TEST_DIR:-$HOME/.cache/parallel-dev-tests}"
SOCK="${XDG_RUNTIME_DIR:-/tmp}/pd-test-fpm.sock"   # unix socket paths are capped at 108 bytes
FPM=$(command -v php-fpm || ls /usr/sbin/php-fpm* 2>/dev/null | head -1)
[ -n "$FPM" ] || { echo "php-fpm not found"; exit 1; }

export PD_SITES_ROOT=$T/sites PD_PORT=18081 PD_PLUGINS_DIR=$T/plugins PD_ENV_FILE=$T/env

fails=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }
code() { curl -s -o /dev/null -w '%{http_code}' "$1"; }

# Clear the previous run on the way in, through the scripts' own delete so databases go too.
if [ -d "$T/sites" ]; then
    for d in "$T"/sites/*/*/; do
        [ -f "$d/wp-config.php" ] || continue
        p=$(basename "$(dirname "$d")"); s=$(basename "$d")
        "$SK/scripts/delete-site.sh" "$p" "$s" >/dev/null 2>&1
    done
fi
rm -rf -- "${T:?}"
# Database names come from plugin and scenario alone, so a run from another test folder leaves
# databases that would collide with this one's. Drop this suite's own, wherever they came from.
( source "$SK/scripts/lib.sh"; for s in default second foreign smoke-t1; do pd_drop_db hello-plugin "$s"; done )
mkdir -p "$T/conf" "$T/logs" "$T/tmp" "$T/sites" "$T/plugins/hello-plugin/assets"

# The server, from the real templates. Only the port and the run-as lines differ.
sed -e "s|__FPM_SOCKET__|$SOCK|g" "$SK/config/parallel-dev-common.conf" > "$T/conf/parallel-dev-common.conf"
sed -e "s|__SITES_ROOT__|$T/sites|g" -e "s|__CONF_DIR__|$T/conf|g" -e 's/listen 8081;/listen 18081;/' \
    "$SK/config/nginx-parallel-dev.conf" > "$T/conf/parallel-dev.conf"
NGX_CONF_DIR=$(dirname "$(nginx -V 2>&1 | sed -n 's/.*--conf-path=\([^ ]*\).*/\1/p')")
cp "$NGX_CONF_DIR/fastcgi_params" "$NGX_CONF_DIR/mime.types" "$T/conf/"
cat > "$T/conf/nginx.conf" <<CONF
pid $T/nginx.pid; error_log $T/logs/nginx-error.log;
events {}
http { include mime.types; access_log $T/logs/access.log;
  client_body_temp_path $T/tmp; fastcgi_temp_path $T/tmp; proxy_temp_path $T/tmp;
  uwsgi_temp_path $T/tmp; scgi_temp_path $T/tmp;
  include $T/conf/parallel-dev.conf; }
CONF
sed -e "s|__FPM_SOCKET__|$SOCK|g" -e "s|^slowlog.*|slowlog = $T/logs/slow.log|" \
    "$SK/config/php-fpm-parallel-dev.conf" | sed '/^user\|^group\|^listen.owner\|^listen.group/d' > "$T/pool.conf"
printf '[global]\npid=%s\nerror_log=%s\ninclude=%s\n' "$T/fpm.pid" "$T/logs/fpm.log" "$T/pool.conf" > "$T/fpm.conf"

stop_servers() {
    [ -f "$T/nginx.pid" ] && kill "$(cat "$T/nginx.pid")" 2>/dev/null
    [ -f "$T/fpm.pid" ] && kill "$(cat "$T/fpm.pid")" 2>/dev/null
}
trap stop_servers EXIT
"$FPM" -y "$T/fpm.conf" || { echo "php-fpm did not start, see $T/logs/fpm.log"; exit 1; }
nginx -p "$T" -c "$T/conf/nginx.conf" || { echo "nginx did not start, see $T/logs/nginx-error.log"; exit 1; }

printf '<?php\n/* Plugin Name: Hello Plugin */\n' > "$T/plugins/hello-plugin/hello-plugin.php"
echo 'body{}' > "$T/plugins/hello-plugin/assets/a.css"

echo "test dir $T"
"$SK/scripts/update-core.sh" >/dev/null
check "core has a default theme" test -d "$T/sites/.core/wp-content/themes/twentytwentyfive"

"$SK/scripts/create-site.sh" hello-plugin >/dev/null
"$SK/scripts/create-site.sh" hello-plugin second >/dev/null
. "$PD_ENV_FILE"
check "env file is private"          test "$(stat -c %a "$PD_ENV_FILE" 2>/dev/null || stat -f %Lp "$PD_ENV_FILE")" = 600
check "default site serves"          test "$(code http://hello-plugin.localhost:18081/)" = 200
check "scenario site serves"         test "$(code http://second.hello-plugin.localhost:18081/)" = 200
check "plugin asset via symlink"     test "$(code http://second.hello-plugin.localhost:18081/wp-content/plugins/hello-plugin/assets/a.css)" = 200
check "list shows both sites"        test "$("$SK/scripts/list-sites.sh" hello-plugin | wc -l)" -eq 2
check "admin password logs in"       wp --path="$T/sites/hello-plugin/second" user check-password admin "$PD_ADMIN_PASS"
check "databases are separate"       test "$(wp --path="$T/sites/hello-plugin/default" config get DB_NAME)" != "$(wp --path="$T/sites/hello-plugin/second" config get DB_NAME)"

D=$T/sites/hello-plugin/default
mkdir -p "$D/wp-content/mu-plugins"; echo '<?php this is a half saved file' > "$D/wp-content/mu-plugins/broken.php"
check "a fatal 500s its own site"    test "$(code http://hello-plugin.localhost:18081/)" = 500
check "...and not its sibling"       test "$(code http://second.hello-plugin.localhost:18081/)" = 200
unlink "$D/wp-content/mu-plugins/broken.php"

wp --path="$T/sites/hello-plugin/second" post create --post_title=marker --post_status=publish --quiet
"$SK/scripts/reset-site.sh" hello-plugin second >/dev/null
check "reset clears data"            test "$(wp --path="$T/sites/hello-plugin/second" post list --title=marker --format=count)" = 0

mkdir -p "$T/sites/hello-plugin/foreign"; echo "<?php // not ours" > "$T/sites/hello-plugin/foreign/wp-config.php"
"$SK/scripts/delete-site.sh" hello-plugin foreign >/dev/null 2>&1
check "delete refuses a foreign site" test -f "$T/sites/hello-plugin/foreign/wp-config.php"
DB=$(wp --path="$D" config get DB_NAME)
"$SK/scripts/delete-site.sh" hello-plugin >/dev/null
check "delete removes the files"     test ! -d "$D"
check "delete drops the database"    test -z "$(mysql -N -e "SHOW DATABASES LIKE '$DB'")"

(cd "$T/plugins" && zip -qr "$T/hello-plugin.zip" hello-plugin)
source "$SK/scripts/smoke.sh"
pd_smoke_start t1 hello-plugin "$T/hello-plugin.zip" 2>/dev/null
check "smoke installs the zip"       test "$(wpc plugin list --status=active --field=name)" = hello-plugin
check "smoke site serves"            test "$(code "$PD_SMOKE_URL/")" = 200
wpc post create --post_title=leftover --post_status=publish --quiet
pd_smoke_start t1 hello-plugin "$T/hello-plugin.zip" 2>/dev/null
check "smoke clears on the way in"   test "$(wpc post list --title=leftover --format=count)" = 0

echo
[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
exit "$fails"
