# Security checks

The security category of a plugin review, weighted 1.5x when it is combined with other categories.

Check every PHP file for:
- ABSPATH/WPINC check at the top of every PHP file
- All `$_POST`, `$_GET`, `$_REQUEST` inputs sanitized (`sanitize_text_field`, `absint`, `sanitize_email`, etc.)
- All output escaped (`esc_html`, `esc_attr`, `esc_url`, `wp_kses_post`)
- Nonce verification on all form submissions and AJAX handlers (`wp_verify_nonce`, `check_ajax_referer`)
- Capability and object-ownership checks on every privileged action. A nonce is CSRF protection, never authentication/authorization; test lower-privileged users and IDOR/object-level access.
- `$wpdb->prepare()` used for all custom SQL - no string concatenation
- No `eval()`, `assert()`, `call_user_func($user_input)`, `include($_GET[...])`
- No hardcoded secrets or API keys
- File upload validation with `wp_check_filetype()` if applicable
- `wp_die()` used instead of bare `die()`/`exit()` in admin context
- REST routes use explicit permission callbacks, argument schemas/validation, least privilege, bounded pagination and no private-field exposure.
- Webhooks/payment callbacks verify provider signatures, timestamp/replay windows, amount/currency/order identity and idempotency before changing state. Public callbacks may intentionally lack WordPress nonces but require protocol-level authentication.
- User-controlled outbound URLs use SSRF-safe validation (`wp_safe_remote_*` where applicable), restrict schemes/hosts/redirects, and cannot reach loopback/private/link-local/metadata-service addresses.
- Check open redirects, path traversal, unsafe deserialization, dynamic includes/calls, CSV/formula injection, stored/DOM XSS, header/email injection, unsafe SQL identifiers/`LIKE` patterns and upload MIME/content validation.
- Anonymous/expensive endpoints have impact-appropriate rate limits, bounded payloads and cheap rejection before heavy work.
- Secrets, tokens, payment data and personal data are redacted from HTML, REST, debug output and logs.

Deductions: -20 per missing ABSPATH check where direct execution is possible, -25 per exploitable unescaped output, -30 per missing request-authenticity control, -30 per SQL injection risk, -25 per missing capability/object-ownership check, -30 per unauthenticated/replayable state-changing webhook, -25 per SSRF/path traversal/unsafe deserialization risk, -15 per sensitive-data leakage.

## Appendix A - Security SAST Pass

This pass gives the review systematic security coverage without treating scanner output as proof.

### 1. Establish the Threat Model

Before searching for vulnerability patterns, record:

- externally reachable entry points and the actors that can invoke them;
- roles, capabilities, object owners and tenant/site boundaries;
- trust boundaries crossed by browser, REST, AJAX, webhook, cron, CLI and remote-provider data;
- sensitive assets: credentials, tokens, PII, payment/order data, files and privileged settings;
- high-impact state changes, especially payment, refund, stock, entitlement and account changes.

Reuse the evidence bundle's inventories. Do not create duplicate architecture documents.

### 2. Build the Security Coverage Ledger

Track every class below as `CHECKED`, `FINDING`, `N/A` or `UNVERIFIED`. `N/A` requires evidence that the relevant technology or sink is absent. `UNVERIFIED` names the missing code, runtime or provider evidence.

| Security class | WordPress/WooCommerce focus |
|---|---|
| Authentication, authorization, IDOR and CSRF | Nonces, capabilities, object ownership, multisite/tenant boundaries, REST permissions, webhook authentication |
| SQL injection | Dynamic values, identifiers, table names, `LIKE`, `ORDER BY`, limits and raw queries |
| XSS | PHP output, templates, admin notices, email HTML, localized data and DOM sinks |
| SSRF, open redirect and header injection | Remote URLs, redirects, callback URLs, proxy endpoints and response headers |
| File upload and path traversal | Upload validation, archive extraction, import/export paths, downloads, deletes and dynamic includes |
| RCE and unsafe deserialization | Shell/process calls, `eval`-like behavior, dynamic callbacks/includes and attacker-influenced deserialization |
| XXE/XML parser safety | XML/SOAP/SVG/import parsers and external entity/network behavior |
| Secrets, privacy and data exposure | Tracked/release secrets, logs, REST/AJAX responses, HTML, caches and third-party payloads |
| Business logic, replay and concurrency | Prices, coupons, limits, workflow order, idempotency, races, callbacks, payments and refunds |
| Dependency and supply-chain exposure | Composer/npm advisories, abandoned packages, autoload collisions, dev files and release contents |
| JWT | Only when tokens are created or verified; algorithms, key selection, issuer/audience, expiry and replay |
| GraphQL injection/authorization | Only when GraphQL exists; static documents, bound variables, field/operation authorization and limits |
| SSTI | Only when a server-side template string can be selected or constructed dynamically |

Conditional classes are not automatically `N/A`: first verify the technology is absent from first-party code and dependencies used at plugin boundaries.

### 3. Run Two Separate Passes

#### Pass A: Structural Reconnaissance

Find every security-relevant source, sink and guard before deciding exploitability.

Common sources:

- `$_GET`, `$_POST`, `$_REQUEST`, `$_COOKIE`, `$_FILES`, `php://input` and request headers;
- REST/AJAX arguments, shortcode/block attributes, query vars and uploaded/imported content;
- unauthenticated webhook/provider responses;
- options, post/order/user meta, transients and database rows previously written from user-controlled input;
- URL fragments/query strings, `postMessage`, storage and API responses consumed by JavaScript.

Common sinks:

- `$wpdb` queries and dynamically selected identifiers;
- `echo`, templates, HTML attributes, JavaScript strings, `innerHTML`, `insertAdjacentHTML`, `document.write`, jQuery `.html()` and code-evaluation APIs;
- `wp_remote_*`, cURL, sockets, redirects and response headers;
- filesystem reads/writes/deletes, archive extraction, uploads and dynamic `include`/`require`;
- `unserialize`, dynamic function/class invocation, process execution and XML/template parsers;
- option/meta/order/user/file mutations and payment/refund/stock transitions.

Record all candidate sites even when a guard appears nearby. Reconnaissance finds coverage targets; it does not produce findings.

#### Pass B: Source-to-Sink Verification

For every candidate sink, trace backwards to its origin and then forwards through the resulting state change:

```text
actor + entry point
  -> raw value or object identifier
  -> transformations and storage
  -> authentication / capability / ownership / protocol checks
  -> validation or allowlist
  -> context-specific preparation or escaping
  -> sink
  -> security impact
```

Include second-order flows: attacker-controlled data may be stored safely, then later become dangerous when rendered, queried, fetched as a URL, parsed, included or used in a payment/state decision.

Read every helper and wrapper in the trace. A function name such as `sanitize_*`, `safe_*` or `verify_*` is not evidence of what it enforces.

### 4. Verify Guards in the Correct Context

- A nonce proves request intent, not identity, privilege or object ownership.
- A capability check on a collection does not prove access to the specific order, user, file or site.
- Sanitization normalizes input; it does not replace validation, authorization, prepared SQL or output escaping.
- Escaping must match the final sink: HTML text, attribute, URL, JavaScript, CSS and rich HTML are different contexts.
- `$wpdb->prepare()` protects bound values, not arbitrary SQL fragments. Allowlist dynamic directions/clauses and use `%i` only where supported for identifiers. Escape `LIKE` data with `esc_like()` before binding.
- `wp_safe_remote_*` and `wp_safe_redirect()` are useful primitives, but still verify the intended host/scheme policy, redirects and any private/link-local/metadata destination exposure required by the flow.
- Upload checks require an explicit allowlist, server-side type/content validation, safe naming and a storage/execution policy; client MIME or filename alone is insufficient.
- Webhooks and payment callbacks require provider-level authentication, replay protection, order/merchant/amount/currency binding and idempotent state transitions; WordPress nonces are normally inapplicable.
- Validation performed only in JavaScript is never a server-side security control.
- The score measures whether the plugin can make a customer's site insecure. A secret is a finding when it ships in a release artefact, reaches browser/mobile code, is logged or returned by the plugin, or is used by the plugin at runtime on customer sites.
- Repository-only material is not scored: developer tokens, webhooks, test credentials, internal notes or data exports that sit only in the repository or its git history and never ship in any release artefact cannot affect a customer's site. List each under "Not scored" as repository hygiene, with the remedy (revoke, rotate, history rewrite). Still deduct anything that is in a release ZIP, and still deduct customer personal data (customers, orders, emails, licences) committed anywhere.

### 5. Triage Precisely

Use the classifications from `common-rules.md`:

- `CONFIRMED BUG`: the complete source-to-sink path and failing scenario are demonstrated.
- `CONFIRMED RISK`: the path is demonstrated and exploitation depends on a named realistic condition.
- `UNVERIFIED`: a material link depends on unavailable runtime, provider, infrastructure or opaque dependency evidence. Do not deduct.
- `REJECTED`: the full trace proves an effective guard or no attacker influence.

Do not use `LIKELY VULNERABLE` as a substitute for finishing the trace. Do not claim a class is clean from grep or tool output alone.

Every accepted security finding must include:

1. entry point, actor and required privilege;
2. source-to-sink trace with exact file:line evidence;
3. missing or ineffective guard;
4. concrete confidentiality, integrity, availability or financial impact;
5. pattern-propagation results across first-party code;
6. narrow remediation and a safe verification method.

Map to CWE/CVSS only when useful; correctness of the attack path matters more than taxonomy.

### 6. Use Tools as Leads, Not Verdicts

Run Semgrep, dependency audits, secret scanners and linters when available. Verify every hit manually and record tool availability. A clean scan does not close a coverage row; unavailable tools do not block the manual pass.

For dynamic confirmation, use only an authorized local/dev environment and benign proof markers. Never exploit production, send real payments/messages, retrieve unrelated private data or weaken authentication to make a test easier. Preserve `NOT RUNTIME VERIFIED` where safe confirmation is unavailable.

### 7. Report Coverage

Add the coverage ledger to the security report. For each row, cite the number and location of candidate sites checked or the evidence for `N/A`. A zero-finding security result is valid only when all applicable rows are `CHECKED` and material unknowns are explicitly `UNVERIFIED`.
