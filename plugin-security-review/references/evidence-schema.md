# Evidence bundle schema

## Manifest

`manifest.json` contains:

```json
{
  "schema_version": 2,
  "evidence_id": "2026-08-25T113000Z-a1b2c3d",
  "created_at": "2026-08-25T11:30:00Z",
  "repository_path": "/absolute/canonical/path",
  "repository_slug": "plugin-slug",
  "plugin_root": "/absolute/plugin/root",
  "plugin_version": "1.2.3",
  "head_commit": "full commit hash",
  "head_tree": "full tree hash of head_commit: the reviewed source regardless of uncommitted files",
  "git_status": "clean",
  "working_tree_changes": [],
  "source_fingerprint": "sha256",
  "runtime": {
    "site_url": null,
    "php": null,
    "wordpress": null,
    "woocommerce": null,
    "action_scheduler": null
  },
  "inventories": {
    "files": "COMPLETE",
    "feature_surfaces": "COMPLETE",
    "entry_points": "COMPLETE",
    "inputs_and_sinks": "COMPLETE",
    "hooks": "COMPLETE",
    "state_changes": "COMPLETE",
    "outputs": "COMPLETE",
    "bootstrap_contexts": "COMPLETE",
    "dependencies_and_network": "COMPLETE",
    "money_and_authority": "NOT_APPLICABLE"
  }
}
```

Use `COMPLETE`, `UNVERIFIED` or `NOT_APPLICABLE`. `UNVERIFIED` requires a line beginning
`Limitation:` in the corresponding inventory saying what is unverified and how to reproduce the
check. `NOT_APPLICABLE` requires a line beginning `Not applicable:` giving the evidence.
`scripts/validate-evidence.sh` enforces both, along with the fingerprint and commit checks.

`git_status` is `clean` or `dirty`; `working_tree_changes` carries the `git status --porcelain`
lines present when the bundle was built and `head_tree` identifies the reviewed commit's source
independently of them. Schema 1 bundles predate those two fields; one carrying porcelain text in
`git_status` is read as `dirty`.

## Evidence document

`evidence.md` is the human-readable index:

- plugin identity and declared requirements;
- source and runtime versions;
- links to every inventory;
- the canonical feature and surface vocabulary;
- static-analysis and test tools run;
- official compatibility references fetched;
- unresolved evidence;
- source fingerprint command and result.

## Inventory rows

Each row includes:

- stable symbol or hook/route identifier;
- exact current file:line;
- callers and downstream sink where relevant;
- request/runtime contexts;
- guards or transformations observed;
- evidence status;
- notes that remain factual rather than category verdicts.

## Feature and surface rows

`inventories/feature-surfaces.md` owns the canonical grouping vocabulary used by every specialist and the final remediation plan. Each surface contains:

```yaml
surface_id: order-export
name: Order export
type: backend-process
parent_surface: orders
purpose: Export selected orders to CSV in bounded batches.
points_of_contact:
  - type: scheduled-action
    identifier: example_export_batch
entry_points:
  - example_export_batch
symbols:
  - Example_Export::run_batch
data_stores:
  - wp_example_exports
jobs:
  - example_export_batch
integrations:
  - action-scheduler
```

Use stable kebab-case IDs derived from product terminology. Surfaces may be hierarchical, but every finding must have one primary surface. Technical files and review categories are evidence about a surface, not surfaces themselves.
