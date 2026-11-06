# Common plugin-review rules

## Reviewer posture

Act as an independent external auditor. Zero confirmed findings is valid after complete coverage. Demonstrate depth through inventories, runtime evidence, rejected hypotheses and named unverified areas, not by inventing findings.

- Grep locates candidates; reading decides.
- Never mark a check as passed without evidence.
- A design document, README or previous review states claims, not controls. Re-derive controls from code.
- Ask who chooses every identifier that gates a decision. Signing or encryption authenticates transit, not origin.
- Treat comments asserting guarantees such as `atomic`, `protected`, `validated upstream` or `cannot happen` as claims requiring measurement.
- Scanner and linter output supplies leads, not findings.
- Static plausibility is never runtime verification.

## Scope

Read every first-party PHP, JavaScript, CSS, template, translation and release-metadata file relevant to the specialist pass. Audit generated and third-party trees through dependency inventories, locks, advisories, licences and plugin call boundaries unless a suspected issue requires source inspection.

Exclude release/build directories from source scope. Inspect the actual customer ZIP only during release-package checks.

## Triage classifications

- `CONFIRMED BUG`: the exact failing input, state or sequence is demonstrated.
- `CONFIRMED RISK`: the code path is demonstrated and failure requires a named realistic condition.
- `UNVERIFIED`: plausible, but material runtime or external evidence is unavailable. Apply no deduction.
- `NITPICK`: style or consistency only. Do not inflate severity.
- `REJECTED`: the complete path proves the candidate false.

## Severity

- `Critical`: unauthenticated or lower-privileged exploitation; wrong, lost or duplicated money; data loss or corruption; fatal on activation or a core flow; private data entering a shared cache.
- `High`: breaks a core flow for a normal user, or causes serious harm under an unusual but reachable condition or production-scale load.
- `Medium`: wrong behaviour in a genuine edge case or a standards/compatibility defect without a current core-flow failure.
- `Low`: cosmetic, stylistic or hardening-only issue with no reachable material failure.

Silent failure ranks one level higher than the equivalent visible error. Severity and score deduction are separate decisions.

## Evidence minimum

Every accepted finding names:

1. exact source locations and symbols;
2. actor, input, request context or state;
3. complete failing or risky code path;
4. concrete impact;
5. pattern-propagation results;
6. narrow fix or verification method;
7. classification, severity and deduction.
