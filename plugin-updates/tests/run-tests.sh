#!/usr/bin/env bash
# End-to-end tests for build_live_script.py: generate real live scripts and run them against a
# real, throwaway WordPress site with real wordpress.org plugins.
#
#   PU_TEST_WP_PATH=/path/to/throwaway/wordpress plugin-updates/tests/run-tests.sh
#
# The site's plugins classic-editor and hello-dolly are reinstalled at old versions at the start
# of every case (cleared on the way in; nothing is torn down at the end, so the site shows what
# the last case left). Never point this at a site you care about. Needs WP-CLI, curl, python3.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$HERE/../scripts/build_live_script.py"
SITE="${PU_TEST_WP_PATH:?Set PU_TEST_WP_PATH to a throwaway WordPress install}"
[ -f "$SITE/wp-config.php" ] || { echo "No wp-config.php in $SITE" >&2; exit 2; }
cd "$SITE"
URL="$(wp option get siteurl)"; URL="${URL%/}"
echo "Test site: $URL ($SITE)"

WORK="$(mktemp -d)"
ZIPS="$HERE/.cache"; mkdir -p "$ZIPS"
for z in classic-editor.1.6.6 classic-editor.1.6.7 hello-dolly.1.6 hello-dolly.1.7.2; do
  [ -s "$ZIPS/$z.zip" ] || curl -fsSL -o "$ZIPS/$z.zip" "https://downloads.wordpress.org/plugin/$z.zip" || { echo "Download of $z failed" >&2; exit 2; }
done
NEW_DOLLY_SHA="$(sha256sum "$ZIPS/hello-dolly.1.7.2.zip" | cut -d' ' -f1)"

PASS=0; FAILS=0
ok()  { echo "PASS  $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }
ver() { wp plugin get "$1" --field=version 2>/dev/null; }

reset_site() {
  wp plugin install "$ZIPS/classic-editor.1.6.6.zip" --force --activate >/dev/null 2>&1
  wp plugin install "$ZIPS/hello-dolly.1.6.zip" --force >/dev/null 2>&1
  [ "$(ver classic-editor)" = 1.6.6 ] && [ "$(ver hello-dolly)" = 1.6 ] || { echo "Could not reset the site" >&2; exit 2; }
}

manifest() { # $1 live url, $2 classic-editor from, $3 dolly sha
  cat > "$WORK/manifest.json" <<EOF
{"live_url": "$1", "tested_on": "https://staging.invalid",
 "plugins": [
  {"slug": "classic-editor", "from": "$2", "to": "1.6.7", "source": "wordpress.org"},
  {"slug": "hello-dolly", "from": "1.6", "to": "1.7.2", "source": "zip",
   "zip": "hello-dolly.1.7.2.zip", "sha256": "$3"}]}
EOF
}

generate() {
  rm -f "$WORK/update-live.sh"
  python3 "$GEN" "$WORK/manifest.json" > "$WORK/update-live.sh" && cp "$ZIPS/hello-dolly.1.7.2.zip" "$WORK/"
}

unchanged() { [ "$(ver classic-editor)" = 1.6.6 ] && [ "$(ver hello-dolly)" = 1.6 ]; }

# 1. Wrong site: refuses and changes nothing.
reset_site; manifest "https://live.invalid" 1.6.6 "$NEW_DOLLY_SHA"; generate
out="$(bash "$WORK/update-live.sh" 2>&1)"; rc=$?
[ $rc -ne 0 ] && grep -q "not https://live.invalid" <<<"$out" && unchanged && ok "refuses a site that isn't live_url" || bad "wrong site: rc=$rc $out"

# 2. Live is not at the tested version: refuses and changes nothing.
reset_site; manifest "$URL" 1.6.5 "$NEW_DOLLY_SHA"; generate
out="$(bash "$WORK/update-live.sh" 2>&1)"; rc=$?
[ $rc -ne 0 ] && grep -q "staging was tested from 1.6.5" <<<"$out" && unchanged && ok "refuses when installed version differs from tested" || bad "version mismatch: rc=$rc $out"

# 3. Zip differs from the one tested: refuses and changes nothing.
reset_site; manifest "$URL" 1.6.6 "$(printf '0%.0s' {1..64})"; generate
out="$(bash "$WORK/update-live.sh" 2>&1)"; rc=$?
[ $rc -ne 0 ] && grep -q "does not match the zip tested" <<<"$out" && unchanged && ok "refuses a zip whose checksum differs" || bad "checksum: rc=$rc $out"

# 4. --check passes and changes nothing, and takes no backup.
reset_site; manifest "$URL" 1.6.6 "$NEW_DOLLY_SHA"; generate
export BACKUP_DIR="$WORK/backups"; mkdir -p "$BACKUP_DIR"
out="$(bash "$WORK/update-live.sh" --check 2>&1)"; rc=$?
[ $rc -eq 0 ] && grep -q "All checks passed" <<<"$out" && unchanged && [ -z "$(ls -A "$BACKUP_DIR")" ] && ok "--check passes without changing anything" || bad "--check: rc=$rc $out"

# 5. A real run: backs up, updates both to exactly the tested versions.
out="$(bash "$WORK/update-live.sh" 2>&1)"; rc=$?
[ $rc -eq 0 ] && [ "$(ver classic-editor)" = 1.6.7 ] && [ "$(ver hello-dolly)" = 1.7.2 ] && ls "$BACKUP_DIR"/before-plugin-updates-*.sql >/dev/null 2>&1 && grep -q "plugin install classic-editor --version=1.6.6 --force" <<<"$out" \
  && ok "updates to the tested versions, backs up and prints rollback" || bad "real run: rc=$rc $out"

# 6. Running it again refuses: live is no longer at the tested 'from' versions.
out="$(bash "$WORK/update-live.sh" 2>&1)"; rc=$?
[ $rc -ne 0 ] && grep -q "classic-editor: 1.6.7, but staging was tested from 1.6.6" <<<"$out" && ok "a second run refuses" || bad "second run: rc=$rc $out"

# 7. The generator rejects bad manifests.
for case in \
  '{"live_url":"https://a.test","tested_on":"https://a.test/","plugins":[{"slug":"x","from":"1","to":"2","source":"wordpress.org"}]}|same URL' \
  '{"live_url":"https://a.test","plugins":[{"slug":"x; rm -rf /","from":"1","to":"2","source":"wordpress.org"}]}|slug must be' \
  '{"live_url":"https://a.test","plugins":[{"slug":"x","from":"1","to":"2","source":"zip","zip":"../x.zip","sha256":"'"$NEW_DOLLY_SHA"'"}]}|zip must be' \
  '{"live_url":"https://a.test","plugins":[{"slug":"x","from":"1","to":"2","source":"zip","zip":"x.zip"}]}|sha256 must be' \
  '{"live_url":"https://a.test","plugins":[]}|non-empty'; do
  json="${case%|*}"; want="${case##*|}"
  printf '%s' "$json" > "$WORK/bad.json"
  err="$(python3 "$GEN" "$WORK/bad.json" 2>&1 >/dev/null)"; rc=$?
  [ $rc -ne 0 ] && grep -q "$want" <<<"$err" && ok "generator rejects: $want" || bad "generator accepted ($want): $err"
done

echo "$PASS passed, $FAILS failed. Scratch files: $WORK"
[ "$FAILS" -eq 0 ]
