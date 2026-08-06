# AGENTS.md — TAC Doctrine (Tactical Agentic Coding)

> This file is read by every AI coding agent (Claude Code, Codex, Cursor, Aider, Copilot Workspace,
> Devin, etc.) that touches this repository. It is the hierarchical context root — sub-directories
> MAY carry their own `AGENTS.md` that narrows, but never contradicts, this one.
>
> Installed by `rig-doctrine-overlay`. Edit the `## Project Conventions` section for your repo;
> the doctrine sections below (`Core Four`, `12 Leverage Points`, `Builder≠Verifier`, `Closed-Loop
> Architecture`) are load-bearing — do not delete them, only extend them.

---

## Project Conventions

<!-- FILL IN: replace this block with the target repo's actual conventions -->

- **Language / runtime:** `<detect: package.json / pyproject.toml / go.mod / Cargo.toml>`
- **Package manager:** `<npm|pnpm|yarn|pip|poetry|uv|cargo|go mod>`
- **Test command:** `<e.g. npm test / pytest / go test ./... / cargo test>`
- **Lint command:** `<e.g. eslint . / ruff check . / golangci-lint run>`
- **Build command:** `<e.g. npm run build / python -m build>`
- **Branch convention:** `<main is protected; feature branches → PR → squash-merge>`
- **Commit convention:** Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`)
- **Directory layout:**
  - `src/` or equivalent — implementation
  - `test/` or `tests/` — unit + integration tests
  - `.rig/` — RIG doctrine overlay (smoke.sh, verify.sh, proof-gate.yml, failures.json)
  - `spec/features/` — OpenSpec BDD Gherkin specs (executable behavior contracts)

Agents MUST run the project's own test/lint/build commands before claiming a change works.
Agents MUST NOT invent a new test runner, formatter, or package manager not already in use.

---

## Core Four Declaration

Every agentic task in this repo MUST make these four dimensions explicit before execution.
An agent that cannot state all four for its current task has not finished planning.

| Dimension   | Question it answers                                              | This repo's default |
|-------------|--------------------------------------------------------------------|----------------------|
| **Context** | What information does the agent need loaded to do this correctly? | This `AGENTS.md`, the file(s) under edit, `spec/features/*.feature` for the touched behavior, `.rig/proof-gate.yml` for gate thresholds. |
| **Model**   | Which model/capability tier is this task worth?                   | Default to the session's configured model; escalate to a stronger model only for architecture-level decisions or when two prior attempts failed verification. |
| **Prompt**  | What is the precise, falsifiable instruction?                     | State the acceptance criterion as a test or command that will be run, not as prose intent. |
| **Tools**   | What tools does the agent need, and which are forbidden?          | Read/Edit/Bash/Grep/Glob for implementation. Destructive git (`push --force`, `reset --hard`, `clean -fdx`) is FORBIDDEN without explicit human approval. |

**Rule:** if a task cannot state Context, Model, Prompt, and Tools in one paragraph each, it is
under-specified — stop and ask, or decompose further, before writing code.

---

## 12 Leverage Points Checklist

Adapted from Donella Meadows' leverage-points hierarchy, applied to where an agent should intervene
in this codebase. Weakest leverage (parameters) is listed first; strongest (paradigm) last. When two
fixes are equally correct, prefer the one with LOWER leverage-point number that still solves the
actual problem — smaller interventions are safer and easier to verify.

- [ ] **1. Constants/parameters** — Can this be fixed by changing a config value, env var, or magic number?
- [ ] **2. Buffer sizes/stocks** — Is this a capacity, cache, or queue-size problem?
- [ ] **3. Structure of material stocks/flows** — Does data need to move through a different pipeline shape?
- [ ] **4. Delays** — Is a timing/ordering issue (race condition, stale cache, async gap) the real cause?
- [ ] **5. Balancing feedback loops** — Is a corrective mechanism (retry, backoff, circuit breaker) missing or miscalibrated?
- [ ] **6. Reinforcing feedback loops** — Is something compounding (unbounded growth, runaway retries) that needs a brake?
- [ ] **7. Information flows** — Does the right actor lack visibility into the right signal (logging, telemetry, error surfacing)?
- [ ] **8. Rules of the system** — Is this an incentive/constraint problem (API contract, validation rule, permission)?
- [ ] **9. Self-organization** — Can the system be given the ability to add new structure itself (plugin points, extension APIs)?
- [ ] **10. Goals of the system** — Is the stated objective itself wrong (optimizing the wrong metric)?
- [ ] **11. Mindset/paradigm the system arises from** — Does the underlying architecture encode a wrong assumption?
- [ ] **12. Power to transcend paradigms** — Is a full re-architecture actually warranted (rare — requires explicit human sign-off)?

**Usage:** before implementing a fix, check off the lowest-numbered item that actually resolves the
root cause. Jumping straight to #11/#12 for a #1/#2 problem is over-engineering; patching #1/#2 for
an #8+ problem is a band-aid that will recur (see `.rig/failures.json` for recurrence tracking).

---

## Builder ≠ Verifier Separation

**This is the single most important rule in this file.**

An agent (or agent session) that WRITES a change MUST NOT be the sole authority that declares the
change correct. Verification MUST be an independent pass with different tooling, different eyes, or
a different model — never the builder re-reading its own diff and self-certifying.

```
┌─────────────┐        writes         ┌──────────────┐
│   BUILDER    │ ───────────────────▶ │  CANDIDATE   │
│ (agent pass) │                       │    DIFF      │
└─────────────┘                       └──────┬───────┘
                                              │
                                              ▼
                                    ┌──────────────────┐
                                    │  L10 smoke.sh     │  ← adaptive, self-evolving
                                    │  L8  verify.sh     │  ← 8 sequential gates
                                    └──────┬────────────┘
                                              │
                              PASS ◀─────────┴─────────▶ FAIL
                                │                            │
                                ▼                            ▼
                      ┌──────────────────┐        ┌──────────────────────┐
                      │  VERIFIER          │        │  back to BUILDER      │
                      │  (independent      │        │  with .rig/failures.  │
                      │  pass: read-only,  │        │  json evidence — NOT  │
                      │  re-runs L8+L10,   │        │  a silent retry       │
                      │  checks proof-gate)│        └──────────────────────┘
                      └────────┬───────────┘
                                │
                          signed ProofPacket
                          (.rig/proof-gate.yml
                           + HMAC signature)
                                │
                                ▼
                          MERGE / SHIP
```

Rules that enforce this in practice:
1. The agent that authored a diff MUST run `.rig/smoke.sh` and `.rig/verify.sh` and paste the actual
   output — never assert "tests pass" without the command output attached.
2. A PASS claim without command output is treated as a FAIL.
3. Human (or a separate verifier agent/session) re-runs `.rig/verify.sh` independently before merge.
   The builder's own run is evidence, not proof.
4. `.rig/proof-gate.yml` defines the machine-checkable threshold (all 8 layers PASS + HMAC-signed
   artifact hash). No merge without a green ProofPacket.

## Closed-Loop Architecture

```
        ┌────────────────────────────────────────────────────────┐
        │                     CLOSED LOOP                          │
        │                                                            │
        │   observe → plan → build → verify → learn → repeat        │
        │      ▲                                        │            │
        │      └────────────────────────────────────────┘            │
        │                                                            │
        │  Each iteration:                                          │
        │   1. observe   — read AGENTS.md, spec/features/, prior     │
        │                  .rig/failures.json entries                │
        │   2. plan      — state Core Four for the task              │
        │   3. build     — implement against the lowest-leverage     │
        │                  fix that solves the root cause            │
        │   4. verify    — run .rig/smoke.sh --learn && .rig/verify.sh│
        │   5. learn     — on FAIL, failure is appended to            │
        │                  .rig/failures.json with root-cause tag;    │
        │                  next iteration's smoke.sh grows a new      │
        │                  regression check for that exact failure    │
        │      (this is what makes L10 "self-evolving": every real    │
        │       bug becomes a permanent, planted regression test)     │
        └────────────────────────────────────────────────────────┘
```

The loop never exits on a bare assertion. It exits only when `.rig/verify.sh` prints
`ALL 8 LAYERS: PASS` and `.rig/proof-gate.yml`'s threshold is satisfied.
