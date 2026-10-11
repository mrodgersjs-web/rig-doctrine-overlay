<!-- ============================================================= -->
<!-- FDE STANDARD HEADER — installed by rig-doctrine-overlay        -->
<!-- Paste this block at the very top of the target repo's README.  -->
<!-- Replace every <REPLACE: ...> marker before committing.         -->
<!-- ============================================================= -->

# <REPLACE: repo display name>

[![RIG Doctrine](https://img.shields.io/badge/RIG-doctrine--governed-6a0dad)](./AGENTS.md)
[![L10 Smoke](https://img.shields.io/badge/L10-self--evolving-2ea44f)](./.rig/smoke.sh)
[![L8 Verify](https://img.shields.io/badge/L8-8%2F8%20layers-2ea44f)](./.rig/verify.sh)
[![Proof Gate](https://img.shields.io/badge/proof--gate-configured-blue)](./.rig/proof-gate.yml)
[![BDD Spec](https://img.shields.io/badge/spec-OpenSpec%20BDD-orange)](./spec/features)
[![License: MIT](https://img.shields.io/badge/license-MIT-lightgrey)](./LICENSE)

> **FDE Standard.** This repository has the [RIG Doctrine Overlay](https://github.com/mrodgersjs-web/rig-doctrine-overlay)
> applied: every change is governed by [`AGENTS.md`](./AGENTS.md) (TAC doctrine),
> hardened by [`.rig/smoke.sh`](./.rig/smoke.sh) (L10 self-evolving smoke tests),
> independently verified by [`.rig/verify.sh`](./.rig/verify.sh) (L8 eight-layer
> verification, including [`.rig/rig_checks.py`](./.rig/rig_checks.py): done-claims
> need evidence, changed modules need tests, no secret-shaped strings), and
> specified in [`spec/features/`](./spec/features) (BDD). Pass-rate threshold:
> [`.rig/proof-gate.yml`](./.rig/proof-gate.yml). Builder and Verifier are separate passes — see `AGENTS.md`.

<details>
<summary><strong>RIG Governance Status</strong> (click to expand)</summary>

| Layer | Mechanism | Status | Evidence |
|---|---|---|---|
| Doctrine | `AGENTS.md` (TAC: Core Four, 12 leverage points, Builder≠Verifier) | ✅ installed | this file |
| L10 | `.rig/smoke.sh` — self-evolving smoke harness | <REPLACE: run `.rig/smoke.sh` and paste PASS/FAIL> | `.rig/failures.json` |
| L8 | `.rig/verify.sh` — 8-layer independent verification | <REPLACE: run `.rig/verify.sh` and paste PASS/FAIL> | last CI run |
| BDD | `spec/features/*.feature` — OpenSpec Gherkin specs | <REPLACE: N feature files, M scenarios> | `spec/features/` |
| Doctrine checks | `.rig/rig_checks.py all` — claims / tests / secrets | <REPLACE: run it and paste PASS/FAIL> | `.rig/claims.jsonl` |

Regenerate this table with `.rig/verify.sh` — do not hand-edit the status column
without a fresh run backing it.

</details>

<!-- ============================================================= -->
<!-- END FDE STANDARD HEADER — original README content follows      -->
<!-- ============================================================= -->
