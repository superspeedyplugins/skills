# Specialist report contract

Every specialist report starts with:

```yaml
review: plugin-security-review
evidence_id: 2026-08-25T143000-a1b2c3d
source_fingerprint: <sha256>
started_at: 2026-08-25T15:00:00+03:00
completed_at: 2026-08-25T15:42:00+03:00
status: REVIEWED
runtime_verified: false
```

Use `NOT APPLICABLE` only with evidence that the feature or technology is absent. Use `INCOMPLETE` when required evidence or coverage is missing.

## Coverage

List the inventory sections consumed, code paths checked, runtime checks performed, unavailable tools and all unverified areas.

## Findings

Use one block per candidate:

```yaml
id: SECURITY-001
title: Anonymous export route exposes private order data
classification: CONFIRMED BUG
severity: Critical
category: security
primary_surface:
  id: order-export
  name: Order export
  type: admin-interface
secondary_surface_ids:
  - order-data
point_of_contact:
  type: rest-route
  identifier: example/v1/export/(?P<id>\d+)
locations:
  - includes/class-export.php:84
symbols:
  - Example_Export::register_routes
affected_context:
  - unauthenticated REST
evidence: <complete trace>
impact: <concrete result>
pattern_search: <all equivalent locations checked>
required_fix: <narrow correction or verification>
fix_scope:
  - Example_Export::register_routes
  - Example_Export::export_order
fix_dependencies: []
related_categories:
  - woocommerce
deduction: 30
```

Use surface IDs from the evidence bundle's `feature-surfaces.md`. `primary_surface` is the functional area a developer would open first to make the fix. `secondary_surface_ids` names genuinely affected adjacent areas. `point_of_contact` identifies the concrete screen, route, hook, job, table, callback, loader or build step where the defect is reached or observed.

Do not use a category, severity, filename or generic layer such as `backend` as the primary surface. If the evidence map has no honest surface, mark `primary_surface: UNRESOLVED` and explain what the parent review must resolve rather than inventing a private synonym.

`fix_scope` names the symbols or configuration areas likely to change. `fix_dependencies` lists finding IDs or prerequisite work that must happen first. Specialists propose these fields; the top-level review verifies and normalises them before producing remediations.

## Rejected and unverified candidates

Preserve meaningful rejected hypotheses with the evidence that disproved them. For each `UNVERIFIED` candidate, name the missing measurement or access needed to settle it. Do not deduct.

## Output path

Write to:

```text
.code-reviews/reviews/<evidence-id>/<specialist>-<YYYY-MM-DDTHHMMSS>.md
```

Never overwrite an existing report.
