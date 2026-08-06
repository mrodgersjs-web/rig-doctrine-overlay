# RIG Doctrine Overlay — Make any AI repo 1000x governed

`rig-doctrine-overlay` is a transformation toolkit. Point it at any existing AI/ML
repository — a guardrails library, an eval framework, an agent runtime, anything —
and it drops in a five-layer governance overlay that converts the repo from
"code that an agent can edit" into an **FDE-standard repo**: one where every
change is doctrine-governed, self-hardening, independently verified,
behavior-specified, and cryptographically proof-gated before it ships.

It does not touch your source code, your license, or your CI provider. It adds
files. Your repo, your logic, your stack — just governed.

```
./apply-overlay.sh <target-repo>
```

That's the whole interface. One script, one argument, five layers installed.

---

## The 5-Layer Overlay

```
┌─────────────────────────────────────────────────────────────────────┐
│                         RIG DOCTRINE OVERLAY                          │
│                                                                         │
│  Layer 1  TAC          AGENTS.md — hierarchical context every agent    │
│           (doctrine)   reads first: Core Four, 12 Leverage Points,     │
│                         Builder≠Verifier separation, closed-loop arch. │
│                                                                         │
│  Layer 2  L10           .rig/smoke.sh — self-evolving smoke harness:   │
│           (harden)      syntax → unit → integration → eval → proof.    │
│                         Every real failure becomes a permanent,        │
│                         planted regression check via --learn.          │
│                                                                         │
│  Layer 3  L8            .rig/verify.sh — 8 sequential, independently-   │
│           (verify)      runnable layers, each PASS/FAIL with printed   │
│                         evidence: L1 syntax → L8 signoff.               │
│                                                                         │
│  Layer 4  OpenSpec BDD  spec/features/*.feature — executable Gherkin   │
│           (specify)     behavior contracts. "Looks right" is not a     │
│                         Then clause; every scenario ends on a checked   │
│                         proof gate.                                    │
│                                                                         │
│  Layer 5  ProofGates    .rig/proof-gate.yml — HMAC-signed ProofPacket   │
│           (gate)        config: what gets hashed, who may sign, and    │
│                         what pass-rate threshold blocks a merge.        │
└─────────────────────────────────────────────────────────────────────┘
```

### Layer 1 — TAC doctrine (`AGENTS.md`)

Every AI coding agent that touches the repo (Claude Code, Codex, Cursor,
Aider, Copilot Workspace, Devin, ...) reads `AGENTS.md` first. It declares:

- **Core Four** — Context / Model / Prompt / Tools stated explicitly before
  any task starts. An agent that can't state all four hasn't finished planning.
- **12 Leverage Points** — a Donella-Meadows-derived checklist that pushes
  fixes toward the lowest-leverage intervention that actually solves the root
  cause (change a parameter before you re-architect a system).
- **Builder ≠ Verifier** — the single hardest rule to enforce and the one that
  matters most. The agent that writes a diff is never the sole authority that
  declares it correct.
- **Closed-loop architecture diagram** — observe → plan → build → verify →
  learn → repeat, with an explicit exit condition (`verify.sh` prints `ALL 8
  LAYERS: PASS`), never a bare assertion.

### Layer 2 — L10 self-evolving smoke harness (`.rig/smoke.sh`)

Five gates, run in order: syntax → unit tests → integration smoke → eval gate
(BDD spec presence) → proof verification. Auto-detects the repo's stack
(Node/Python/Go/Rust) and runs its real test/build commands — no invented
tooling. `--learn` appends every real failure to `.rig/failures.json`; the
**next** run replays every recorded failure as a regression check before the
normal gates. A bug fixed once cannot silently regress without smoke.sh
catching it — the harness gets stricter every time it finds a real bug.

### Layer 3 — L8 eight-layer verification (`.rig/verify.sh`)

The independent verifier pass. Eight sequential layers, each printing
`PASS`/`FAIL` plus an `evidence:` line backed by an actual command's output —
never an opinion:

| Layer | Checks |
|---|---|
| L1 syntax | Does the code parse? |
| L2 unit | Do unit tests pass? |
| L3 integration | Does the system build/boot end-to-end? |
| L4 eval | Do `spec/features/*.feature` exist and describe real behavior? |
| L5 proof | Does a ProofPacket-shaped artifact exist? |
| L6 gate | Does the run satisfy `proof-gate.yml`'s pass-rate threshold? |
| L7 audit | Is there a human-readable trail (git history)? |
| L8 signoff | Are all prior layers green — cleared to sign? |

Runnable as a whole (`--continue` to see every layer instead of halting at the
first FAIL) or one layer at a time (`--layer=N`) — `smoke.sh`'s Gate 5 calls
`verify.sh --layer=5` directly, so the two harnesses compose.

### Layer 4 — OpenSpec BDD (`spec/features/*.feature`)

Executable Gherkin specs. `templates/feature.template.feature` is a real,
non-placeholder example with a Background, three concrete Scenarios (happy
path, regression caught by the failure ledger, builder-cannot-self-certify),
and a Scenario Outline that walks all 8 verification layers. Every Scenario's
`Then` ends on a checked proof gate, an exit code, or a written artifact —
never a vibe.

### Layer 5 — ProofGates (`.rig/proof-gate.yml`)

The machine-checkable contract behind "done." Defines: the HMAC-SHA256
signing key source, exactly which paths get hashed into the ProofPacket
(with excludes for `node_modules`, `.venv`, build output), the deterministic
tree-hash algorithm, the pass-rate threshold `.rig/verify.sh`'s L6 layer
enforces, which layers are non-negotiable even under `--continue`, and who is
allowed to sign (`allow_builder_self_sign: false` by default — enforcing
Builder≠Verifier at the config level, not just the doctrine level).

---

## Before / After

**Before** — a typical AI repo:

```
my-repo/
├── README.md              (marketing copy, no governance signal)
├── src/
├── test/                  (tests exist, but nothing enforces they're run
│                            before a change is called "done")
└── package.json

An agent (or a human) can:
  - claim "tests pass" without running them
  - merge a change that silently reintroduces a fixed bug
  - self-certify its own diff as correct
  - ship with no record of WHY a change is believed to be safe
```

**After** — `./apply-overlay.sh my-repo` applied:

```
my-repo/
├── README.md              (FDE standard header: badges, governance status
│                            table, links to every gate)
├── AGENTS.md               (TAC doctrine — every agent reads this first)
├── CLAUDE.md                (pointer to AGENTS.md for Claude-specific tooling)
├── .rig/
│   ├── smoke.sh              (L10 — 5 gates, self-evolving via --learn)
│   ├── verify.sh              (L8 — 8 independently-runnable layers)
│   ├── proof-gate.yml          (signing key source, hash config, thresholds)
│   └── failures.json            (regression ledger — starts empty, grows
│                                  with every real bug found)
├── spec/features/
│   └── example.feature           (executable BDD — replace with real specs)
├── src/
├── test/
└── package.json

An agent (or a human) now:
  - MUST run .rig/smoke.sh --learn and paste real output before claiming done
  - CANNOT self-certify — .rig/verify.sh is the independent pass, and
    proof-gate.yml's allow_builder_self_sign: false blocks the builder
    from being the signer
  - gets a bug that regresses caught automatically — smoke.sh replays every
    entry in failures.json on every subsequent run
  - has an auditable, hash-verifiable trail of exactly what was checked
    before a change was declared complete
```

---

## Usage

```bash
# apply the overlay to a target repo
./apply-overlay.sh /path/to/target-repo

# preview what would change without writing anything
./apply-overlay.sh /path/to/target-repo --dry-run

# re-apply / overwrite an existing .rig/ install (idempotent — safe to re-run)
./apply-overlay.sh /path/to/target-repo --force
```

`apply-overlay.sh` runs seven steps: check for an existing `.rig/`, install
`AGENTS.md` (+ a `CLAUDE.md` pointer), install `.rig/smoke.sh`, install
`.rig/verify.sh`, install `spec/features/`, install `.rig/proof-gate.yml`
(templated with the target repo's slug) plus a seeded `failures.json`,
prepend the FDE standard header to the target's README (idempotently — safe
under repeated `--force`), and sanity-check that every file landed.

After applying, inside the target repo:

```bash
cd /path/to/target-repo

# edit AGENTS.md's "Project Conventions" section for this repo's actual stack
$EDITOR AGENTS.md

# replace the example BDD scenario with real ones for this repo's behavior
$EDITOR spec/features/example.feature

# run the self-evolving smoke harness
.rig/smoke.sh --learn

# run the independent 8-layer verifier
.rig/verify.sh

# wire signing into CI
export RIG_PROOF_KEY=...
```

Both `.rig/smoke.sh` and `.rig/verify.sh` auto-detect the target's stack
(Node via `package.json`, Python via `pyproject.toml`/`setup.py`, Go via
`go.mod`, Rust via `Cargo.toml`) and run that stack's real test/build
commands — they never invent a tool the repo doesn't already use, and every
gate that can't apply prints `SKIP` with a stated reason rather than silently
passing.

---

## Repo layout

```
rig-doctrine-overlay/
├── README.md                        this file
├── LICENSE                          MIT
├── apply-overlay.sh                  the installer (run this)
├── TOP-10-CANDIDATES.md               target repos this overlay is built for
├── templates/
│   ├── AGENTS.md                       Layer 1 — TAC doctrine
│   ├── smoke.sh                          Layer 2 — L10 harness
│   ├── verify.sh                          Layer 3 — L8 verification
│   ├── proof-gate.yml                      Layer 5 — ProofPacket config
│   ├── feature.template.feature             Layer 4 — BDD template
│   └── README-header.md                      FDE standard README header
└── .rig/                             this repo's own overlay (dogfooded —
                                        rig-doctrine-overlay is itself
                                        RIG-governed)
```

## License

MIT — see [`LICENSE`](./LICENSE).
