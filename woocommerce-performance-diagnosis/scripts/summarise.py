#!/usr/bin/env python3
"""Turn store facts and a Performance Analysis report into one Markdown evidence digest.

    python3 summarise.py store-facts.json sspa-report.json [url-profile.json ...] > digest.md

store-facts.json comes from store_facts.php; sspa-report.json from `wp sspa report`. The digest is
for the agent writing the owner's report: facts, a per-page table, the findings with their
evidence, and the key pages the run did not measure. It reads the two files only and uses the
Python 3 standard library.

Part of the woocommerce-performance-diagnosis skill, https://github.com/superspeedyplugins/skills
Licence: GPL-3.0.
"""
import json
import re
import sys

# Literal ID lists in SQL (post, order and item IDs) are noise in a digest and identify records.
ID_LIST = re.compile(r"IN\s*\(\s*\d+(?:\s*,\s*\d+)*\s*\)")

# Key pages a WooCommerce diagnosis needs, and how to recognise each in Performance Analysis page
# keys. A key matches when it equals one of the names or starts with one of the prefixes.
KEY_PAGES = [
    ("Home", ["home"], []),
    ("Shop", ["shop"], []),
    ("A product category", ["product-cat"], []),
    ("A filtered category (attribute or price filter)", [], ["filter"]),
    ("Search results", [], ["search-"]),
    ("A product page", ["product-single", "customer-product"], []),
    ("Cart", ["wc-cart"], []),
    ("Checkout", ["wc-checkout"], []),
    ("My account", ["wc-myaccount", "customer-account"], []),
    ("Admin products list", ["admin-products"], []),
    ("Admin orders list", ["admin-orders"], []),
    ("Admin order search", ["admin-orders-search"], []),
]


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def fmt_bytes(n):
    if n is None:
        return "-"
    n = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} GB"


def fmt_num(v, digits=0):
    if v is None or v == "":
        return "-"
    try:
        f = float(v)
    except (TypeError, ValueError):
        return str(v)
    return f"{f:,.{digits}f}"


def cell(v):
    return str(v).replace("|", "\\|").replace("\n", " ")


def clip(text, limit):
    text = " ".join((text or "").split())
    if len(text) <= limit:
        return text
    return text[:limit].rsplit(" ", 1)[0] + " ..."


def url_page_label(url):
    """Which key page an extra URL measured, from its query string and path."""
    u = (url or "").lower()
    if "filter_" in u or "min_price=" in u or "max_price=" in u or "rating_filter=" in u:
        return "A filtered category (attribute or price filter)"
    if "?s=" in u or "&s=" in u:
        return "Search results"
    return None


def matches(key, names, prefixes):
    k = key.lower()
    return k in names or any(p in k for p in prefixes)


def facts_section(f):
    out = ["## Store facts", ""]
    env = f.get("environment", {})
    cat = f.get("catalogue", {})
    orders = f.get("orders", {})
    store = f.get("orders_storage", {})
    caching = f.get("caching", {})
    auto = f.get("autoload", {})
    cron = f.get("cron", {})
    asch = f.get("action_scheduler", {})
    house = f.get("housekeeping", {})
    rows = [
        ("Site", env.get("site_url")),
        ("WordPress / WooCommerce", f"{env.get('wordpress')} / {env.get('woocommerce')}"),
        ("PHP (WP-CLI) / database", f"{env.get('php')} / {env.get('database_server')}"),
        ("Theme", env.get("theme") + (f" (child of {env.get('theme_parent')})" if env.get("theme_parent") else "")),
        ("Active plugins", f.get("plugins", {}).get("active_count")),
        ("HPOS", "on" if store.get("hpos_enabled") else "off"),
        ("HPOS compatibility-mode sync", "on" if store.get("compatibility_mode_sync") else "off"),
        ("Published products", fmt_num(cat.get("products_published"))),
        ("Product types", ", ".join(f"{k} {fmt_num(v)}" for k, v in (cat.get("product_types") or {}).items()) or "-"),
        ("Variations", fmt_num(cat.get("variations"))),
        ("Product categories / tags", f"{fmt_num(cat.get('product_categories'))} / {fmt_num(cat.get('product_tags'))}"),
        ("Global attributes", ", ".join(f"{a['taxonomy']} ({a['terms']} terms)" for a in cat.get("global_attributes", [])) or "none"),
        ("Attribute lookup table used for filtering", "yes" if cat.get("attribute_lookup_table_in_use") else "no"),
        ("Orders (total / last 30 days)", f"{fmt_num(orders.get('total'))} / {fmt_num(orders.get('last_30_days'))}"),
        ("Order rows still in wp_posts", fmt_num(orders.get("legacy_order_posts"))),
        ("Persistent object cache", "yes" if caching.get("persistent_object_cache") else "no"),
        ("Page-cache drop-in (advanced-cache.php)", "yes" if caching.get("advanced_cache_dropin") else "no"),
        ("Autoloaded options", f"{fmt_bytes(auto.get('bytes'))} in {fmt_num(auto.get('rows'))} rows"),
        ("Transients (expired)", f"{fmt_num(auto.get('transient_rows'))} ({fmt_num(auto.get('expired_transients'))} expired)"),
        ("WP-Cron events (overdue over 10 minutes)", f"{fmt_num(cron.get('events'))} ({fmt_num(cron.get('overdue_more_than_10_minutes'))})"),
        ("DISABLE_WP_CRON", "yes" if cron.get("disable_wp_cron") else "no"),
    ]
    if asch:
        rows += [
            ("Action Scheduler pending (past due)", f"{fmt_num(asch.get('pending'))} ({fmt_num(asch.get('pending_past_due_more_than_10_minutes'))})"),
            ("Action Scheduler failed / complete / log rows", f"{fmt_num(asch.get('failed'))} / {fmt_num(asch.get('complete'))} / {fmt_num(asch.get('log_rows'))}"),
        ]
    rows += [
        ("Revisions / trashed / auto-drafts", f"{fmt_num(house.get('revisions'))} / {fmt_num(house.get('trashed_posts'))} / {fmt_num(house.get('auto_drafts'))}"),
        ("WooCommerce sessions (expired)", f"{fmt_num(house.get('woocommerce_sessions'))} ({fmt_num(house.get('expired_woocommerce_sessions'))})"),
    ]
    out += ["| Fact | Value |", "|---|---|"]
    out += [f"| {cell(k)} | {cell(v)} |" for k, v in rows]
    out.append("")

    largest = auto.get("largest") or []
    if largest:
        out += ["Largest autoloaded options:", "", "| Option | Size |", "|---|---|"]
        out += [f"| `{cell(o['option_name'])}` | {fmt_bytes(o['bytes'])} |" for o in largest]
        out.append("")

    tables = f.get("database", {}).get("largest_tables") or []
    if tables:
        out += ["Largest tables (row counts are InnoDB estimates):", "", "| Table | Rows | Size | Of which indexes |", "|---|---|---|---|"]
        out += [f"| `{t['name']}` | {fmt_num(t['rows_estimate'])} | {fmt_num(t['size_mb'], 1)} MB | {fmt_num(t['index_mb'], 1)} MB |" for t in tables[:10]]
        out.append("")
    non_innodb = f.get("database", {}).get("non_innodb_tables") or []
    if non_innodb:
        out += ["Tables not using InnoDB: " + ", ".join(f"`{t}`" for t in non_innodb), ""]

    if cron.get("overdue_hooks"):
        out += ["Overdue cron hooks: " + ", ".join(f"`{h}` ({n})" for h, n in cron["overdue_hooks"].items()), ""]
    for label, key in (("Pending Action Scheduler hooks", "top_pending_hooks"), ("Failed Action Scheduler hooks", "top_failed_hooks")):
        hooks = asch.get(key) or []
        if hooks:
            out += [f"{label}: " + ", ".join(f"`{h['hook']}` ({h['n']})" for h in hooks), ""]

    plugins = f.get("plugins", {}).get("active") or []
    if plugins:
        out += ["Active plugins: " + ", ".join(f"{p['slug']} {p.get('version') or ''}".strip() for p in plugins), ""]
    return out


def pages_section(report, profiles=()):
    pages = report.get("pages") or []
    out = ["## Pages measured", ""]
    if not pages:
        return out + ["The report has no pages. Check `wp sspa status` and run `wp sspa run` again.", ""]
    out += ["Medians per page and visitor type. Times in ms.", "",
            "| Page key | Visitor | HTTP | Generation | SQL | Queries | Rows fetched | HTTP calls ms | Peak memory | Blocked by |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    special = [p for p in pages if p.get("page_key") in ("baseline", "mail-probe")]
    pages = [p for p in pages if p.get("page_key") not in ("baseline", "mail-probe")]
    for p in sorted(pages, key=lambda p: -(p.get("generation_ms") or 0)):
        out.append("| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            cell(p.get("page_key")), cell(p.get("variant") or "-"), cell(p.get("response_code") or "-"),
            fmt_num(p.get("generation_ms")), fmt_num(p.get("sql_ms")), fmt_num(p.get("sql_count")),
            fmt_num(p.get("rows_fetched")), fmt_num(p.get("http_ms")), fmt_bytes(p.get("peak_mem_bytes")),
            cell(p.get("blocked_by") or "")))
    out.append("")
    if special:
        out += ["Not pages: `baseline` is the server's own noise floor and `mail-probe` measures sending one email.", ""]

    keys = [str(p.get("page_key") or "") for p in pages]
    extra = {url_page_label(p.get("url")) for p in profiles}
    missing = [label for label, names, prefixes in KEY_PAGES
               if label not in extra and not any(matches(k, names, prefixes) for k in keys)]
    out += ["## Key pages not measured", ""]
    if missing:
        out += ["Neither the run nor an extra URL covers these. Measure each with scripts/profile_url.php (SKILL.md, step 2):", ""]
        out += [f"- {m}" for m in missing]
    else:
        out.append("Every key page has at least one measurement.")
    out.append("")
    return out


def findings_section(report):
    findings = report.get("findings") or []
    out = ["## Findings", ""]
    if not findings:
        return out + ["No findings.", ""]
    order = {"critical": 0, "warn": 1, "info": 2}
    findings = sorted(findings, key=lambda f: (order.get(f.get("severity"), 3), str(f.get("type"))))
    counts = {}
    for f in findings:
        counts[f.get("severity")] = counts.get(f.get("severity"), 0) + 1
    out += ["Counts: " + ", ".join(f"{k} {v}" for k, v in counts.items()), ""]
    for i, f in enumerate(findings, 1):
        rec = f.get("recommendation") or {}
        ev = f.get("evidence") or {}
        out.append(f"### {i}. [{f.get('severity')}] {f.get('type')}: {cell(f.get('headline') or '')}")
        out.append("")
        out.append(f"- Component: {f.get('component') or 'site-level'}; page: {f.get('page_key') or '-'}; confidence: {f.get('confidence') or '-'}")
        brief = {k: v for k, v in ev.items() if k != "sql" and isinstance(v, (int, float, str)) and len(str(v)) <= 200}
        if brief:
            out.append("- Evidence: " + "; ".join(f"{k} {v}" for k, v in list(brief.items())[:12]))
        detail = ID_LIST.sub("IN (...)", " ".join((f.get("detail") or "").split()))
        if detail:
            out.append("- Detail: " + cell(clip(detail, 600)))
        if rec.get("title") or rec.get("body"):
            out.append(f"- Performance Analysis recommends: {cell(rec.get('title') or '')}. {cell(clip(rec.get('body'), 900))}")
        out.append("")
    return out


def extra_urls_section(profiles):
    if not profiles:
        return []
    out = ["## Extra URLs measured", "", "From scripts/profile_url.php. Generation is the median of the samples. Times in ms.", "",
           "| URL | Visitor | HTTP | Generation | SQL | Queries | Rows fetched | Peak memory | Top component by SQL |",
           "|---|---|---|---|---|---|---|---|---|"]
    for p in profiles:
        comps = p.get("components") or []
        top = f"{comps[0]['component']} ({fmt_num(comps[0].get('sql_ms'), 1)} ms)" if comps else "-"
        out.append("| {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            cell(p.get("url")), cell(p.get("as") or "-"), cell(p.get("response_code") or "-"), fmt_num(p.get("generation_ms")),
            fmt_num(p.get("sql_ms")), fmt_num(p.get("sql_count")), fmt_num(p.get("rows_fetched")), fmt_bytes(p.get("peak_mem_bytes")), cell(top)))
    out.append("")
    for p in profiles:
        fs = p.get("findings") or []
        if fs:
            out += [f"Findings on {p.get('url')}:", ""]
            out += [f"- [{f.get('severity')}] {f.get('type')}: {cell(f.get('headline') or '')}" + (f" ({fmt_num(f.get('ms'), 1)} ms)" if f.get("ms") else "") for f in fs]
            out.append("")
    return out


def impacts_section(report):
    impacts = report.get("impacts") or []
    if not impacts:
        return []
    out = ["## Plugin Impact Analysis", "",
           "Positive delta means the plugin adds time. `measured` is proven; `none` is below the noise floor.", "",
           "| Plugin | Page | Object cache | Generation delta ms | SQL delta ms | Queries delta | Noise floor ms | Confidence |",
           "|---|---|---|---|---|---|---|---|"]
    for i in impacts[:60]:
        out.append("| {} | {} | {} | {} | {} | {} | {} | {} |".format(
            cell(i.get("plugin") or "-"), cell(i.get("page_key") or "-"), cell(i.get("object_cache_mode") or "-"),
            fmt_num(i.get("delta_generation_ms"), 1), fmt_num(i.get("delta_sql_ms"), 1), fmt_num(i.get("delta_queries")),
            fmt_num(i.get("noise_floor_ms"), 1), cell(i.get("confidence") or "-")))
    if len(impacts) > 60:
        out.append(f"\n{len(impacts) - 60} more rows in the report JSON.")
    out.append("")
    return out


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: summarise.py store-facts.json sspa-report.json [url-profile.json ...]\n")
        return 2
    facts = load(argv[1])
    report = load(argv[2])
    profiles = [load(a) for a in argv[3:]]
    run = report.get("run") or {}
    out = ["# Evidence digest", "",
           f"Performance Analysis run {run.get('id')} ({run.get('type')}, {run.get('status')}), finished {run.get('finished')}. "
           f"Score {report.get('score')}/100. Facts gathered {facts.get('generated_at_utc')}.", ""]
    out += facts_section(facts)
    out += pages_section(report, profiles)
    out += extra_urls_section(profiles)
    out += findings_section(report)
    out += impacts_section(report)
    sys.stdout.write("\n".join(out).rstrip() + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
