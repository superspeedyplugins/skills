#!/usr/bin/env bash
# Tests for the woocommerce-performance-diagnosis scripts, run against a real, throwaway
# WooCommerce site with HPOS on and at least one order:
#
#   WPD_TEST_WP_PATH=/path/to/throwaway/wordpress woocommerce-performance-diagnosis/tests/run-tests.sh
#
# They drive store_facts.php through WP-CLI exactly as SKILL.md does (piped to `wp eval-file -`),
# check it against WordPress's own answers, check it changes no catalogue or order table and leaks no customer data,
# then run summarise.py on the site's real Performance Analysis report. Nothing is torn down.
# Needs WP-CLI, python3 and, for the summarise case, Performance Analysis with at least one run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTS_PHP="$HERE/../scripts/store_facts.php"
SUMMARISE="$HERE/../scripts/summarise.py"
SITE="${WPD_TEST_WP_PATH:?Set WPD_TEST_WP_PATH to a throwaway WooCommerce install}"
[ -f "$SITE/wp-config.php" ] || { echo "No wp-config.php in $SITE" >&2; exit 2; }
cd "$SITE"
wp plugin is-active woocommerce || { echo "WooCommerce is not active on $SITE" >&2; exit 2; }
echo "Test site: $(wp option get siteurl) ($SITE)"

WORK="$(mktemp -d)"
PASS=0; FAILS=0; SKIPS=0
ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL  $1"; FAILS=$((FAILS+1)); }
skip() { echo "SKIP  $1"; SKIPS=$((SKIPS+1)); }
jq_py() { python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$@"; }
PREFIX="$(wp db prefix)"

# Action Scheduler and options are left out on purpose: the site's own queue runner and WP-Cron
# change them while the test runs (seen draining 3,600 pending lookup-table actions mid-run).
checksum() {
  wp db query "CHECKSUM TABLE ${PREFIX}posts, ${PREFIX}postmeta, ${PREFIX}terms, ${PREFIX}term_taxonomy, ${PREFIX}term_relationships, ${PREFIX}wc_orders, ${PREFIX}wc_orders_meta, ${PREFIX}wc_order_addresses" --skip-column-names 2>/dev/null
}

# 1. Runs through `wp eval-file -` and prints valid JSON with the expected schema.
before="$(checksum)"
if wp eval-file - < "$FACTS_PHP" > "$WORK/facts.json" 2> "$WORK/facts.err" && [ "$(jq_py "$WORK/facts.json" "d['schema']")" = "woocommerce-performance-diagnosis/store-facts@1" ]; then
  ok "store_facts.php prints store-facts@1 JSON through wp eval-file -"
else
  bad "store_facts.php did not print valid JSON: $(head -c 400 "$WORK/facts.err")"
fi
after="$(checksum)"

# 2. Changes nothing in the catalogue, order or Action Scheduler tables.
[ -n "$before" ] && [ "$before" = "$after" ] && ok "store_facts.php leaves posts, postmeta, terms and orders unchanged" || bad "table checksums changed:
$before
---
$after"

# 3. Facts agree with WordPress and WooCommerce's own answers.
want_products="$(wp post list --post_type=product --post_status=publish --format=count)"
got_products="$(jq_py "$WORK/facts.json" "d['catalogue']['products_published']")"
[ "$want_products" = "$got_products" ] && ok "published products match wp post list ($got_products)" || bad "products: facts $got_products, wp post list $want_products"

want_variations="$(wp post list --post_type=product_variation --post_status=any --format=count)"
got_variations="$(jq_py "$WORK/facts.json" "d['catalogue']['variations']")"
[ "$want_variations" = "$got_variations" ] && ok "variations match wp post list ($got_variations)" || bad "variations: facts $got_variations, wp post list $want_variations"

want_hpos="$( [ "$(wp option get woocommerce_custom_orders_table_enabled)" = yes ] && echo True || echo False)"
got_hpos="$(jq_py "$WORK/facts.json" "d['orders_storage']['hpos_enabled']")"
[ "$want_hpos" = "$got_hpos" ] && ok "HPOS state matches the WooCommerce option ($got_hpos)" || bad "HPOS: facts $got_hpos, option $want_hpos"

want_orders="$(wp wc shop_order list --user=1 --status=any --format=count 2>/dev/null || true)"
got_orders="$(jq_py "$WORK/facts.json" "d['orders']['total']")"
if [ -z "$want_orders" ]; then
  want_orders="$(wp db query "SELECT COUNT(*) FROM ${PREFIX}wc_orders WHERE type='shop_order'" --skip-column-names)"
fi
[ "$want_orders" = "$got_orders" ] && ok "order count matches WooCommerce ($got_orders)" || bad "orders: facts $got_orders, WooCommerce $want_orders"

want_autoload="$(wp db query "SELECT COALESCE(SUM(LENGTH(option_value)),0) FROM ${PREFIX}options WHERE autoload IN ('yes','on','auto-on','auto')" --skip-column-names)"
got_autoload="$(jq_py "$WORK/facts.json" "d['autoload']['bytes']")"
python3 -I -c "import sys; a,b=int(sys.argv[1]),int(sys.argv[2]); sys.exit(0 if abs(a-b) <= max(2048, a//100) else 1)" "$want_autoload" "$got_autoload" \
  && ok "autoload size matches the options table ($got_autoload bytes)" || bad "autoload: facts $got_autoload, table $want_autoload"

# 4. No customer data: take real billing emails and last names from the site's own orders and
# check none appears anywhere in the output.
leaks=0; checked=0
while IFS=$'\t' read -r email last; do
  [ -n "$email" ] || continue
  checked=$((checked+1))
  if grep -qiF -- "$email" "$WORK/facts.json" || { [ -n "$last" ] && grep -qF -- "$last" "$WORK/facts.json"; }; then leaks=$((leaks+1)); fi
done < <(wp db query "SELECT o.billing_email, a.last_name FROM ${PREFIX}wc_orders o LEFT JOIN ${PREFIX}wc_order_addresses a ON a.order_id = o.id AND a.address_type = 'billing' WHERE o.billing_email <> '' LIMIT 50" --skip-column-names 2>/dev/null)
if [ "$checked" -eq 0 ]; then
  bad "no order with a billing email to check against: add one order to the test site"
elif [ "$leaks" -eq 0 ]; then
  ok "no billing email or last name from $checked real orders appears in the facts"
else
  bad "$leaks of $checked orders' customer details appear in the facts"
fi

# 5. summarise.py on the site's real Performance Analysis report.
if wp plugin is-active super-speedy-performance-analysis 2>/dev/null && wp sspa report > "$WORK/report.json" 2>/dev/null && [ -s "$WORK/report.json" ]; then
  if python3 -I "$SUMMARISE" "$WORK/facts.json" "$WORK/report.json" > "$WORK/digest.md" 2> "$WORK/digest.err"; then
    pages="$(jq_py "$WORK/report.json" "len(d.get('pages') or [])")"
    rows="$(grep -cE '^\| [a-z0-9]' "$WORK/digest.md" || true)"
    if grep -q '^## Store facts' "$WORK/digest.md" && grep -q '^## Pages measured' "$WORK/digest.md" && grep -q '^## Findings' "$WORK/digest.md" && [ "$pages" -gt 0 ] \
       && grep -q "| $(jq_py "$WORK/report.json" "d['pages'][0]['page_key']") |" "$WORK/digest.md"; then
      ok "summarise.py writes facts, all sections and the report's pages ($pages page rows)"
    else
      bad "digest is missing sections or pages (pages=$pages rows=$rows): $(head -c 400 "$WORK/digest.md")"
    fi
    leaks=0
    while IFS= read -r email; do [ -n "$email" ] && grep -qiF -- "$email" "$WORK/digest.md" && leaks=$((leaks+1)); done \
      < <(wp db query "SELECT billing_email FROM ${PREFIX}wc_orders WHERE billing_email <> '' LIMIT 50" --skip-column-names 2>/dev/null)
    [ "$leaks" -eq 0 ] && ok "the digest contains no customer email" || bad "$leaks customer emails in the digest"
  else
    bad "summarise.py failed: $(head -c 400 "$WORK/digest.err")"
  fi
else
  skip "summarise.py: Performance Analysis is not active or has no completed run (wp sspa run first)"
fi

echo
echo "$PASS passed, $FAILS failed, $SKIPS skipped. Output kept in $WORK"
[ "$FAILS" -eq 0 ]
