---
name: plugin-security-review
description: Adversarial security review of a WordPress or WooCommerce plugin, tracing every input from source to sink with a complete coverage ledger. Use when asked to security-review a plugin.
license: GPL-3.0. Full text at https://www.gnu.org/licenses/gpl-3.0.html
compatibility: Claude Code or another agent that can read files and run shell commands. Needs git, Node.js 18 or later, and sha256sum or shasum. PHP, WP-CLI and a local test site make runtime checks possible.
metadata:
  author: Super Speedy Plugins
  version: "1.0.0"
---

# Plugin security review

Review the WordPress or WooCommerce plugin in the current directory, or at the path the user gives.
This is a focused security review. It scores security only and gives no overall deployment verdict.

The review has two halves. First build an **evidence bundle**: inventories of every entry point,
input, sink, output, state change, dependency and money path, tied to the exact source revision.
Then run the **security pass** over that evidence, tracing each candidate from where the value
comes in to where it ends up. The evidence is an index into the code, never a substitute for
reading it.

Paths below are relative to this skill's folder.

## Fresh eyes

If this conversation wrote or edited any of the code under review, do not review it here. Hand the
whole review to a fresh agent with only the plugin path and an instruction to run this skill. Do
not pass on the implementation rationale or the findings you expect.

## 1. Storage

```bash
scripts/prepare-storage.sh <plugin-repository>
```

Evidence and reports go in `<plugin-repository>/.code-reviews/`, which the script excludes from
Git locally. A security report lists weaknesses, so never commit it to a public repository. If the
user wants evidence kept outside the repository, set `PLUGIN_REVIEW_STORE` to a folder first.

The script stops if `.code-reviews` exists and is not what it expects. Never move or replace
existing evidence without the user's approval.

## 2. Evidence bundle

```bash
scripts/source-fingerprint.sh <plugin-repository>
```

Reuse an existing bundle under `.code-reviews/evidence/` only when its `manifest.json` matches all
of: repository path, source fingerprint, HEAD commit, clean or dirty status, and schema version.
Never update an old bundle. If anything differs, build a new one:

1. Read [references/discovery-checks.md](references/discovery-checks.md) and
   [references/evidence-schema.md](references/evidence-schema.md) completely.
2. Name the bundle `<UTC timestamp>-<short HEAD>`, for example `2026-11-06T143000Z-a1b2c3d`, and
   create `.code-reviews/evidence/<id>/` and `.code-reviews/reviews/<id>/`.
3. Build the feature and surface map first, then every inventory, from current code and any
   runtime evidence. Cite symbols plus file:line. Record facts, not verdicts.
4. Write `manifest.json` and `evidence.md` as the schema describes.

Then validate it, and stop if it fails:

```bash
scripts/validate-evidence.sh <plugin-repository> .code-reviews/evidence/<id>
```

It recomputes the fingerprint, checks the commit and tree, and checks that every inventory exists
and that each declared status is backed by its content. Quote its output in the report.

## 3. Security pass

Read [references/common-rules.md](references/common-rules.md),
[references/finding-contract.md](references/finding-contract.md) and
[references/checks.md](references/checks.md) completely before judging anything.

Use the entry-point, input/sink, output, state-change, dependency/network and money/authority
inventories. Do structural reconnaissance first, finding every source, sink and guard. Only then
judge exploitability: trace every candidate from its source to its final sink and the state
change that results, reading every helper and wrapper on the way. A function called
`sanitize_something` proves nothing until you have read what it does.

Fill in the security coverage ledger from `checks.md`. An `N/A` row needs evidence that the
technology or sink is absent. Missing runtime or provider evidence is `UNVERIFIED`, with no
deduction.

Runtime confirmation is only ever done on a local or staging copy the user controls, with
harmless proof markers. Never test against a live site, send real payments or messages, or weaken
authentication to make a test easier.

## 4. Report

Write a new, timestamped report:

```text
.code-reviews/reviews/<evidence-id>/security-<YYYY-MM-DDTHHMMSS>.md
```

Use the format in `finding-contract.md`. Never overwrite an earlier report. Score Security only.

Before finishing, play devil's advocate: re-read the files and inventory rows with the weakest
coverage, re-check every line you cite, and ask which role, request context, cache, migration or
failing dependency could still overturn a conclusion. Verify it, or mark it unverified.

Tell the user where the report is, how many findings were confirmed at each severity, and which
areas stayed unverified and why.
