---
name: woocommerce-performance-diagnosis
description: Diagnoses a slow WooCommerce store's back end with WP-CLI and the free Performance Analysis plugin, then writes an evidence-based report with free fixes first.
license: GPL-3.0. Full text at https://www.gnu.org/licenses/gpl-3.0.html
compatibility: Claude Code or another agent that runs shell commands. Needs WP-CLI on the store (ideally a staging copy), Python 3 and curl on this computer, and WordPress 6.9 or later for the Performance Analysis plugin.
metadata:
  author: Super Speedy Plugins
  version: "1.0.0"
---

# WooCommerce performance diagnosis

The user has a WooCommerce store that is slow, or wants to know why it will be once the catalogue
grows. You gather the store's facts, measure its key pages with the free
[Super Speedy Performance Analysis](https://www.superspeedyplugins.com/product/super-speedy-performance-analysis/)
plugin, match what you found to causes and fixes, and write a Markdown report the owner can read
and act on, with the evidence for every claim in it.

This skill is about the server side: how long WordPress, WooCommerce, plugins and the database
take to build a page. It does not cover images, JavaScript or Core Web Vitals. For generic
WordPress profiling without WooCommerce, the WordPress project's `wp-performance` skill
(https://github.com/WordPress/agent-skills) complements this one.

## Rules that never bend

1. **Read-only unless the owner says yes to that change.** Installing a plugin, enabling its
   profiler, deleting transients, changing a setting, adding an index: each is a change. Say what
   it does, wait for a yes, then do it. A yes to one change is not a yes to the next.
2. **Prefer staging.** Ask whether the site you can reach is staging or live. Run
   `wp option get siteurl` and tell the user what it says. On live, measuring is allowed once the
   owner agrees, but **never change a setting, a table or a plugin's configuration on live**:
   write the fix into the report for the owner to apply on staging first.
3. **No purchases, no write tests, no traffic collection** without the owner's explicit,
   separate agreement. The Performance Analysis checkout flow creates a real order and sends real
   emails; write profiles create temporary objects. A normal `wp sspa run` sends GET requests only.
4. **Never print or store customer data.** No names, emails, addresses, order details or IP
   addresses in your messages or the report. The scripts here never output them; if a log or query
   result you read contains them, summarise without them.
5. **Every number in the report was measured on this store in this session.** Never quote a
   speed-up for any plugin, product or fix, ours included. Say "measure again after the change"
   instead of predicting the result.
6. **Do not enable community sharing** in Performance Analysis. Only the owner may opt in.

## Before you start

Find out how to run WP-CLI on the store: on this computer (`cd` to the WordPress folder), over
SSH (`ssh host "cd /path && wp ..."`), or with `wp --ssh=user@host/path`. Below, `wp` means
whichever of those works. Check `wp core version` and `wp plugin is-active woocommerce` work
before anything else.

Ask the owner, in one message:

- whether this is staging or live, and the live URL;
- what feels slow to them and to their customers (a page, the admin, imports, checkout);
- whether you may install and activate the free Performance Analysis plugin and turn its
  profiler on, and whether it should stay installed afterwards;
- roughly how much traffic the store gets, if they know.

Make a folder on this computer for the evidence, for example `diagnosis-YYYY-MM-DD/`. Every file
below goes there.

## Step 1: the store's facts (read-only)

`scripts/store_facts.php` (relative to this skill's folder) runs SELECT queries and reads
options only. It changes nothing and prints no customer data. Pipe it to WP-CLI so it works the
same on a remote server:

```text
wp eval-file - < scripts/store_facts.php > diagnosis-YYYY-MM-DD/store-facts.json
```

It records: WordPress, WooCommerce, PHP and database versions; HPOS and compatibility-mode
sync; products by type, variations, categories, tags and attribute terms; whether WooCommerce's
attribute lookup table is used for filtering; order and customer counts; active plugins,
must-use plugins and drop-ins; persistent object cache and page-cache drop-ins; autoloaded
options (total size and the ten largest); transients; WP-Cron and Action Scheduler backlog and
failures; the largest tables, non-InnoDB tables, and the indexes on the tables WooCommerce
queries hit hardest; and leftovers such as revisions and expired sessions.

Then look at the page cache from outside, twice each, for the home page and the shop page:

```text
curl -s -o /dev/null -D - https://example.com/ | grep -iE '^(age|x-cache|cf-cache-status|x-litespeed-cache|x-proxy-cache|x-varnish|x-fastcgi-cache|x-sg-cache|x-kinsta-cache|cache-control|set-cookie):'
```

A HIT, an `age` above zero or a cache header that changes from MISS to HIT on the second request
means a page cache serves anonymous visitors. No such header is not proof there is none; say
"not detected" rather than "none".

## Step 2: install Performance Analysis and measure (owner's OK first)

Performance Analysis is free and GPL 3. It profiles each key page with signed requests to the
site itself, and attributes SQL time, rows, memory, HTTP calls and mail to the plugin or theme
that caused them. Its Plugin Impact Analysis can then prove a plugin's cost by switching it off
for its own test requests only; real visitors always get the full site.

Check whether it is already there, in either edition (the folder is
`super-speedy-performance-analysis` or `super-speedy-performance-analysis-pro`):

```text
wp plugin list --status=active --field=name | grep super-speedy-performance-analysis
```

If that prints nothing, install it from its GitHub release:

```text
wp plugin install https://github.com/superspeedyplugins/super-speedy-performance-analysis/releases/latest/download/super-speedy-performance-analysis.zip --activate
wp sspa profiler enable
```

`wp sspa profiler enable` installs a small profiling loader in `wp-content/mu-plugins`. It only
profiles requests that carry the plugin's signed token.

Measure the key pages. This is read-only (GET requests only) and takes from about a minute to
several minutes, depending on the store. It waits until it finishes:

```text
wp sspa run --porcelain                        # prints the run id: note it
wp sspa report > diagnosis-YYYY-MM-DD/sspa-report.json
wp sspa cache-optimisation-report --format=json > diagnosis-YYYY-MM-DD/sspa-cache.json
wp sspa http-calls --format=json > diagnosis-YYYY-MM-DD/sspa-http-calls.json
```

A normal run measures home, shop, a product category, a product, two searches, cart, checkout
and my account (logged out and as a test customer), the admin products and orders lists, order
search, and other admin screens. It does not measure a **filtered category**, and its searches are
generic site searches. Measure those, and any page the owner named, one URL at a time with
`scripts/profile_url.php`. It calls the plugin's own "Analyse this page" (the `sspa/profile-url`
ability) and prints a short summary without SQL text. Use an administrator's login for `--user`
(`wp user list --role=administrator --field=user_login`):

```text
wp eval-file - "https://example.com/product-category/clothing/" --user=<admin> < scripts/profile_url.php > diagnosis-YYYY-MM-DD/url-category.json
wp eval-file - "https://example.com/product-category/clothing/?filter_colour=blue" --user=<admin> < scripts/profile_url.php > diagnosis-YYYY-MM-DD/url-filtered.json
wp eval-file - "https://example.com/?s=<a real search term>&post_type=product" --user=<admin> < scripts/profile_url.php > diagnosis-YYYY-MM-DD/url-search.json
```

Measure the filtered category **and the same category without the filter**, so the cost of the
filter itself is visible. Pages are measured as a logged-out visitor; add `admin` after the URL
for a wp-admin URL (that is the default for wp-admin URLs anyway). There is no logged-in
customer option for a single URL; the normal run already covers customer pages.

Ask the owner for a filter their shoppers use and a common search term. Without them, take an
attribute from the store facts (`global_attributes`) and a term from one of its products:
`filter_<attribute without pa_>=<term slug>` on a category that has products with that term.
Check the summary's `response_code` is 200 and its `rows_fetched` is above zero before relying on
it; a filter that matches nothing measures an empty page.

Then make the evidence digest. It puts the facts, the per-page table, the extra URLs and the
findings in one Markdown file you can read without loading the full JSON, and lists any key page
that is still unmeasured:

```text
python3 scripts/summarise.py diagnosis-YYYY-MM-DD/store-facts.json diagnosis-YYYY-MM-DD/sspa-report.json diagnosis-YYYY-MM-DD/url-*.json > diagnosis-YYYY-MM-DD/digest.md
```

Read `digest.md` all the way through before you interpret anything.

If Performance Analysis was installed before you started, it keeps its earlier runs. Use only the
run ids from this session, and say in the report that older measurements exist.

If `sspa-http-calls.json` says `"complete": false`, list its `incomplete_reasons` under "Not
measured" in the report rather than reporting "no outbound HTTP calls".

**If the report shows `blocked_by` on pages**, a security plugin or firewall blocked the
profiling requests. Relay the finding's whitelisting advice to the owner and run again once they
have changed it. Do not change the firewall yourself.

## Step 3: prove the suspects (optional, owner's OK)

When findings name a plugin as the cause of a slow page, Plugin Impact Analysis measures its real
cost on that page:

```text
wp sspa run --type=deep --suspects=<plugin-slug>,<plugin-slug> --pages=<page-key> --porcelain
wp sspa impacts > diagnosis-YYYY-MM-DD/sspa-impacts.json
```

Page keys are in the digest's Pages table. Suspects are plugins other than WooCommerce: WooCommerce,
WordPress core and the active theme cannot be switched off for a test, so when the findings name
only those, skip this step and say why. Only call a plugin the cause of a slowdown when an
impact says so; a finding's `confidence: inferred` is attribution, not proof. Each impact carries its own noise
floor (`noise_floor_ms`); deltas under it are "no measurable impact".

If the store has Redis or Memcached, `wp sspa run --type=cache_impact` shows which plugins ignore
the object cache.

## Step 4: interpret

Work through `references/fixes.md`. For each finding or fact that matches a row's evidence:

1. say what you measured (page, time, query count, rows, the component responsible);
2. say what usually causes it;
3. give the free fix first;
4. then, only where it applies, the plugin that fixes it, with its product page link.

Order the findings by what costs the store most: slow cart, checkout and my-account pages first
(they are never page-cached), then catalogue pages that a page cache misses, then admin screens,
then housekeeping. A store with fewer than a few hundred products and fast pages may have
nothing worth fixing: say so plainly.

Some evidence is real but small today: a sort that cannot use an index, a `LIKE` scan, a lookup
table WooCommerce is not using. Put those under "Watch as the catalogue grows" with the measured
numbers and the row count involved, without predicting how slow they will get.

Do not recommend a fix whose evidence you did not find. Do not recommend anything already in
place (check the active plugins list).

## Step 5: the report

Write `diagnosis-YYYY-MM-DD/report.md` for the owner, in plain English, in this order:

1. **Summary.** Three to six lines: the store's size, the slowest pages and the two or three
   things that matter most.
2. **What was measured.** Site URL, staging or live, date and time, WordPress, WooCommerce, PHP
   and database versions, HPOS, object cache, page cache (detected or not), and the Performance
   Analysis version and run ids.
3. **Store size.** Products by type, variations, categories, attributes, orders, the largest
   tables.
4. **Pages.** A table from the digest: page, generation time, SQL time, queries, rows fetched,
   peak memory.
5. **Findings.** One section each, most important first: the evidence (numbers, the component
   and, where it helps, the query shape), the cause, the free fix, and the plugin that fixes it
   if one applies.
6. **Watch as the catalogue grows.** Evidence that costs little now and grows with products or
   orders, as described in step 4.
7. **Housekeeping.** Autoload, transients, cron and Action Scheduler, leftovers, only where they
   are worth acting on.
8. **Not measured.** Pages or areas you could not measure, and why.
9. **What this diagnosis changed on the site.** Every change you made (for example: installed
   and activated Performance Analysis, enabled its profiler), and how to undo each one.
10. **Next step.** Apply the free fixes on staging, then run `wp sspa run` again and compare with
   `wp sspa history-compare <before-run-id> <after-run-id>`.

Attach or link the evidence files. Keep customer data out of every file. In the report, describe
a query by its shape (the table, the `WHERE` and `ORDER BY` columns, or the fingerprint
Performance Analysis gives) rather than pasting it with its literal IDs and values.

## Step 6: leave the site as the owner wants it

Ask whether to keep Performance Analysis for later before-and-after checks. If not:

```text
wp sspa profiler disable
wp plugin deactivate <the folder name the check in step 2 printed>
```

Its saved measurements stay in its own tables until the plugin is deleted. Deleting it
(`wp plugin delete <folder name>`) only removes those tables if the owner has
turned on its data-removal setting on the Compare tab.
