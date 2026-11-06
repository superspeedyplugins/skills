## Project Layout Rule

Detect the plugin root by locating the PHP file that carries the `Plugin Name:` header. When an outer repository wraps a same-named inner plugin folder (`slug/slug/slug.php`), review the **inner** folder as the plugin root. Exclude build/release directories (`_dist/`, `dist/`, `build/`, `releases/`) from source-review scope - they hold release ZIPs and must not be reported as repository noise. Review a built ZIP only during the dedicated release-package check.

Do not "fix" the project's identity conventions. Whatever `Author`, `Author URI`, `Plugin URI` and readme `Contributors` values the plugin already uses are the project's choice; flag them only when they are internally inconsistent, missing, or wrong for the target distribution channel.

---

## Step 1: Discover Plugin Structure & Base Plugin Versions

1. Identify the plugin root directory (argument or cwd).
2. Find the main plugin file (the PHP file in the root with `Plugin Name:` header). Extract: Plugin Name, Version, Slug, Text Domain, Author.
3. List ALL files in the plugin using Glob. Categorize:
   - PHP files (classes, admin, includes, templates)
   - JS files
   - CSS files
   - readme.txt / README.md
   - Language files (.pot, .po, .mo)
   - Composer/package files
   - vendor/ directories
4. **Detect the versions of the plugins this one integrates with.** Every compatibility claim must reference the versions the target site actually runs - never a generic "latest". Resolve them in this order, and state in the report which source you used:
   - A local base-plugin source library, if the project keeps one (a folder of versioned plugin sources). Extract versions from the folder names (e.g. `woocommerce.10.5.3` → WooCommerce 10.5.3).
   - The WordPress install used for QA: `wp plugin list --fields=name,version,status`, or read each plugin's main-file `Version:` header under `wp-content/plugins/`.
   - As a last resort, the reviewed plugin's own `Requires at least` / `Tested up to` / `WC requires at least` headers - and label the result *declared*, not measured.

   Integration targets worth pinning down: WooCommerce core; every WooCommerce extension the plugin calls into (Composite Products, Product Bundles, Subscriptions, Bookings, Memberships, …); the caching stack (page cache, persistent object cache); and any asset optimizer that can defer, delay or disable scripts. Record every detected version in the Compatibility Matrix (Step 6).

4b. **Detect the effective Action Scheduler version (MANDATORY when the plugin schedules anything).** AS is versioned independently of WooCommerce and ships bundled inside WooCommerce *and* inside other plugins. At runtime **the highest bundled copy across all active plugins wins**, so WooCommerce's version number does NOT tell you which AS is running. Detect it explicitly:
   - Inside the detected WooCommerce: `find {wc-dir} -name 'action-scheduler.php' -path '*action-scheduler*'` → read its `Version:` header.
   - Inside the reviewed plugin itself (`vendor/`, `libraries/`, `includes/`) - a plugin bundling its own copy can silently *raise* the site-wide version for every other plugin.
   - Record the result as its own row in the report's Compatibility Matrix (Step 6).

   **Version-sensitive behavior you must never assume:** before **AS 4.0.0** the uniqueness check matched **hook + group and ignored the arguments**, so one pending action blocked every other action on that hook. From **AS 4.0.0 (bundled with WooCommerce 11.0, released 2026-07-28)** the arguments are part of the check, so each distinct arg set gets its own action. Code that dedupes or coalesces by scheduling with an entity id as an argument flips from "one action total" to "one action per id" on upgrade - a coalescer becomes a fan-out with no error and no deprecation notice. Trace every `as_schedule_*` / `as_enqueue_async_action` / `as_has_scheduled_action` call for this assumption and record it as a concurrency and compatibility candidate.

5. **Check current WooCommerce developer updates (MANDATORY when the plugin touches WooCommerce):** When the plugin touches WooCommerce, Store API, Blocks, Checkout, Orders, HPOS, templates, or extension integrations, you MUST consult the official developer site before finalizing the review:
   - **WebFetch `https://developer.woocommerce.com/archive/`** - this is the canonical index of all dated posts. From it, identify and fetch the posts relevant to this plugin: the release post for the detected WooCommerce version AND the next version, plus any current Developer Advisories, deprecation notices, and "What's coming for developers" posts that could affect this plugin's touchpoints (compatibility, hook behavior, performance expectations, newly disclosed risks). **If the plugin schedules anything, also fetch the Action Scheduler release posts** - AS lives on the same developer site but is versioned separately from WooCommerce (Step 1.4b), so a Woo release post alone will not surface an AS break.
   - **Record every source you actually fetched** as `Title (YYYY-MM-DD) - URL`. You will list these verbatim in the report's "WooCommerce References Checked" section (Step 6).
   - **Do NOT invent URLs.** List only posts you genuinely retrieved. If the archive or a post cannot be retrieved (no network, fetch error), do not fabricate - record "could not be retrieved" and say so in the report.
   - Use this as an official current-state reference to supplement code review, not as a replacement for reading the plugin code.

6. **Bundled shared-library freshness check (only when the plugin vendors an in-house shared library).** Teams that bundle their own admin-UI/helper library into every plugin have a fleet problem, not a local one: on a site running several such plugins **the first-loaded copy wins for the whole request**, so one stale bundle silently downgrades every other plugin. If the library's canonical source is checked out locally (put the path in your project's CLAUDE.md - `{PATH_TO_SHARED_LIBRARY_SOURCE}`):
   a. Compare the version the bundled copy reports against the source copy.
   b. `diff -q` every source file (excluding `.git/`, `.github/`, `README.md`, `tools/`) against its bundled counterpart.
   c. Record: source version, bundled version, and every file that differs or is missing from the bundle.

   If the plugin vendors no such library, or the source path does not exist, skip this step and say so - do not report the comparison as failed.

## Step 2: Read Every Single File

Use parallel tool calls to read ALL plugin files simultaneously. Read every single PHP, JS, CSS, .po, readme.txt file - do not skip any. For large plugins, batch reads across multiple parallel calls.

Also read the `.po` files to cross-reference translations later.

Note what each file does as you read it; the inventories below are built from this reading.

**First-party versus dependency scope:** Read every first-party source file. Do not pretend to manually audit every line of generated or third-party `vendor/` / `node_modules/` code. Inventory dependencies and versions, inspect lockfiles and bootstrap/autoload integration, audit advisories and licenses, and read dependency source only at plugin call boundaries or where a suspected issue requires it. Treat modified vendored files as first-party changes.

## Step 2.5: Static Analysis First-Pass

If the tools exist in the environment, run them and use the output as review INPUT (verify each hit yourself before reporting - linter noise is not a finding; but a clean linter run never replaces manual review):

- `phpcs --standard=WordPress,WordPress-Extra` on the plugin directory (summary first, then per-file detail for hits)
- `phpstan analyse` (project config if present, otherwise `--level=5` on the plugin directory)
- `composer validate` if composer.json exists
- `composer audit` if Composer dependencies exist
- Semgrep/security scan when available
- relevant JavaScript lint/tests and package-manager audit without applying fixes
- source-to-minified CSS/JS parity and production build artefact checks when minified files are distributed

If unavailable, note "static analysis unavailable" in the report and continue.

Additionally, ALWAYS:

- Run `php -l` on EVERY PHP file - parse errors hide in files never loaded during development (uninstall.php, CLI classes, rarely-hit templates).
- If the plugin is a git repo: run `git log --oneline --stat -15`, and `git diff {last-version-tag}..HEAD` when a tag exists. Files changed most recently or most frequently get EXTRA scrutiny - new bugs live in new code. Review the full diff since the last tag line by line.

## Step 2.6: Runtime Verification (when safely available)

Static review cannot prove runtime compatibility, performance, accessibility, or integration behavior. **If a local QA environment exists, use it - do not treat this step as optional or hypothetical.**

**The environment.** Ask the user for a local or staging test site if one is not already known, or create one (the `parallel-dev` skill in the same repository makes an isolated local site in seconds). Record these once in the project's CLAUDE.md or AGENTS.md:
- A **local or staging WordPress site** with the plugin installed - `{QA_SITE_URL}`, WP root `{QA_SITE_PATH}`. A symlinked plugin directory means local edits are already live; no reinstall needed between tests.
- **Always log in through the real `wp-login.php` form**, using a dedicated QA administrator account (`{QA_ADMIN_USER}`; keep the password in your own notes, never in this file). Never test admin behaviour from an unauthenticated session, and never add a URL-parameter or mu-plugin auth bypass to make testing easier.
- **Browser flow (Playwright or equivalent):** navigate `{QA_SITE_URL}/wp-login.php` → fill `#user_login` + `#user_pass` → click `#wp-submit` → wait for `wp-admin`, then drive the screen under test at a desktop *and* a mobile viewport, watching the console for errors.
- **wp-cli** against the QA site (`wp --path={QA_SITE_PATH} …`) for data-level proof: did the row actually change, did the option actually persist, did the scheduled action actually get queued.
- If the project already has a QA/test slash-command, reuse it instead of inventing a procedure.
- Never run any of this against production.

**If the plugin's settings screen is built on a custom tabbed/AJAX admin framework, check its integration at runtime first** - those defects are invisible in PHP review and exist only in the rendered DOM. At minimum: press a bulk **Apply** and confirm the row actually changed in the database, then switch to a second tab and confirm that tab's JS/CSS is present and that its settings survive a save.

With `WP_DEBUG`/logging enabled, test:

- activation, deactivation, existing-install upgrade/migration, and uninstall dry-run behavior
- plugin active versus inactive on homepage, product, category, cart, classic checkout, Checkout Blocks/Store API, relevant admin screens, AJAX, REST, cron/Action Scheduler, CLI, email and webhook paths as applicable
- response time, query count, memory, scripts/styles, registered autoloaders, remote calls and PHP warnings/fatals
- critical feature success/failure paths, duplicate submissions/callbacks, and missing/disabled dependency behavior

Never activate, deactivate, uninstall, mutate production data, send real payments/messages, or run destructive tests on production. If no safe runtime is available, mark affected claims `NOT RUNTIME VERIFIED`; static plausibility is not a compatibility pass.

## Step 2.75: Build Inventories (MANDATORY - this is where hidden bugs surface)

Build the feature/surface map and all eight technical inventories BEFORE category analysis. Every row cites file:line. These are the raw material for specialist reviews, remediation grouping and the report's matrices.

**0. Feature & Surface Map.** Identify the stable functional areas through which a developer, administrator, visitor or external system encounters the plugin. This is the canonical grouping vocabulary for every specialist report and the final remediation plan. Use stable kebab-case IDs based on product language, not implementation class names.

Allowed surface types:

- `customer-feature`
- `admin-interface`
- `frontend-interface`
- `backend-process`
- `scheduled-process`
- `integration`
- `storage`
- `bootstrap`
- `installation-upgrade`
- `release-package`
- `cross-cutting`

For each surface record: ID | user-facing name | type | parent surface if any | purpose | points of contact | entry points | principal symbols | data stores | jobs | integrations. A point of contact is the concrete place work enters or appears, such as an admin screen, settings tab, REST route, AJAX action, product tab, import phase, payment callback, scheduled hook, database table, bootstrap loader or build pipeline.

Prefer the narrowest stable product area that owns the behaviour. Do not use review categories such as `security`, files such as `class-loader.php`, or vague buckets such as `backend` as surface IDs. Use `cross-cutting` only when no single functional owner is honest. Record relationships when one surface calls, renders or schedules another.

**1. Entry-Point Inventory.** Every way execution can be triggered from outside:
- AJAX: `wp_ajax_*`, `wp_ajax_nopriv_*`
- REST: `register_rest_route` (record the `permission_callback`)
- Forms: `admin_post_*`, direct `$_POST` handlers on `init`/`admin_init`
- Shortcodes, blocks, widgets
- Cron: `wp_schedule_event`, Action Scheduler jobs
- Lifecycle: activation / deactivation / uninstall / upgrade routines
- WP-CLI commands, webhook listeners

For EACH entry point record: file:line | nonce verified? | capability checked? | inputs sanitized? | abuse potential. Every `nopriv` endpoint and every `permission_callback => __return_true` gets hostile-input analysis: what is the WORST thing an anonymous visitor can do here?

**2. Input Data-Flow Map.** Every read of `$_POST` / `$_GET` / `$_REQUEST` / `$_SERVER` / `$_COOKIE` / `$_FILES` / `php://input`. Trace each value to its sinks: DB write, SQL, echo/HTML, `header()`, redirect, file operation, option/meta write. Any path reaching a sink without BOTH sanitization at entry AND escaping/preparing at the sink is a candidate finding. Do not trust wrapper functions blindly - open them and verify they actually sanitize.

**3. Hook Registration Inventory.** Every `add_action`/`add_filter`: does the callback exist? Does the accepted-args count match the call site? Is the priority sane relative to WooCommerce defaults? Flag any FILTER callback with a code path that fails to return a value - a missing `return` on one branch silently nulls the filtered value (classic silent breakage).

**4. Write/State-Change Inventory.** Every `update_option`/`add_option` (autoload appropriate?), post/order/user meta write, custom-table INSERT/UPDATE/DELETE, transient set/delete, file write. For each: what triggers it, is it guarded (capability + nonce), is it idempotent, and can two simultaneous requests corrupt it (read-modify-write without atomicity)?

**5. Output Inventory.** Every `echo`/`print`/`printf`/heredoc/template interpolating a variable: is the escaping function present AND correct for the context - `esc_attr` in attributes, `esc_url` in href/src, `esc_js` inside scripts, `wp_kses_post` for rich HTML? `esc_html` used inside an attribute context is a finding, not a pass.

**6. Bootstrap & Request-Context Inventory.** Start at the main plugin file's top-level statements and trace the load graph **transitively** - every `require`/`include`, every unconditional `new`, each of those constructors, service containers / DI registries that eagerly resolve, and every Composer autoloader. Do not stop one level deep. Then, for each substantial feature, one row:

| Feature | Bootstrap Path (file:line chain) | What Runs at Load | Contexts Loaded | Contexts It Can Fire | Verdict |
|---|---|---|---|---|---|

- *What runs at load* distinguishes **cheap** (constructor only calls `add_action`/`add_filter`, assigns properties - acceptable) from **heavy** (DB query, `get_option()` scan, remote call, filesystem work, SDK init, autoloader registration, large include tree, object graph).
- *Contexts* are drawn from this fixed list: homepage · product · category · cart · checkout · wp-admin screens · authenticated `admin-ajax.php` · unauthenticated `admin-ajax.php` · REST · Store API · cron / Action Scheduler · WP-CLI · emails · webhooks / payment callbacks · subscription renewals.
- **Verdict = VIOLATION when heavy code is loaded in contexts where the feature can never fire.** Remember `is_admin()` is true on `admin-ajax.php` (including `nopriv`), so an `is_admin()`-gated row still loads on every AJAX request - mark those contexts as loaded.

This inventory is the raw material for performance and cache-safety findings and for the report's Bootstrap & Request-Context Matrix.

**7. External Dependency & Network Inventory.** List Composer/npm/bundled packages and every remote host/API. Record: version/source/license | where loaded | authentication/secrets | personal/payment data sent | timeout/retry/backoff | response validation | SSRF exposure | log redaction | failure behavior. Check namespace/SPL autoloader collisions and whether development packages or source maps enter the release ZIP.

**8. Money & Authority Inventory - MANDATORY when the plugin can move, hold, or decide that money moved.** Payment gateways, refund/cancel paths, subscription renewals, wallet/credit balances, capture reconciliation, saved-card vaults. If your project keeps a payment-security rules file, read it before building this inventory. The recurring defect shapes to hunt for, drawn from real gateway assessments: non-atomic state transitions; controls that exist in the code but do not hold under concurrency; client-originated values trusted because they were later signed or encrypted (sealing authenticates transit, not origin); order state machines that can be re-entered; scheduled jobs that silently retry a capture; secrets reachable through logs, order meta or REST; and REST routes treated as internal because only the plugin's own JS calls them.

Build two tables:

*8a. Money primitives.* One row per function that actually moves money or marks an order paid (`process_payment`, `process_refund`, any `reverse`/`capture`/`void` executor, any `payment_complete()` / status→`processing` write). For each: **every caller**, file:line, and which gate each caller passes. A kill-switch or capability check read at one call site while three paths reach the primitive is not a control.

*8b. Authority per settle path.* One row per path that can settle or mutate a paid order - callbacks (`wc-api`, webhooks), REST/Store API checkout, scheduled retries, admin actions. Columns: caller identity · replay guard · state allowlist · amount re-derived from where · uniqueness claim (atomic? before or after the remote call?) · lock key (**who chooses it**).

Then apply these specific checks, each of which passed an ordinary review before:

- **Who chose the value?** For every identifier that gates money - lock key, reference number, `cardId`, `eulaId`, phone - trace whether the *browser* minted it. A value sealed/signed after you accepted it is still client-chosen; the seal proves transit, not origin.
- **Ownership binding.** Every route taking an entity id must separately prove the caller owns it. `WC()->customer->get_billing_phone()` proves nothing - Store API `cart/update-customer` is `__return_true`, so an anonymous caller sets it.
- **Atomicity.** `add_option()` is not an atomic mutex (core uses `ON DUPLICATE KEY UPDATE` after a cached read). A uniqueness `SELECT` before a slow remote call is not uniqueness. A check excluding the current row does not stop re-entry. A ledger keyed to deletable rows goes blind when orders are purged.
- **Hook ordering.** Read the emitting core file. A guard on `woocommerce_order_status_changed` fires *after* the `..._status_cancelled` money hook - it can restore a status, not un-send a reverse.
- **Guard order within a handler:** identity → replay → state allowlist → amount. A branch that demotes an order before the replay guard is an unauthenticated downgrade primitive.
- **Fail-open routing.** Any branch chosen by the *absence* of a provider field must land on the safe side.
- **Reconciliation that cannot fail.** If the enumerator finds orders by a meta key the provider's own response wrote, the "marked paid, no capture" bucket is arithmetically always empty. Enumerate independently via `wc_get_orders()`.
- **Order meta is public.** WC's orders REST API does not apply `is_protected_meta()`. Flag any token/credential/PII parked there, and any money decision that reads it.

---
