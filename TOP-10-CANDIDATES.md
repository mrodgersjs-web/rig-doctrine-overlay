# Top 10 Candidates for the RIG Doctrine Overlay

Ten target repos evaluated for `rig-doctrine-overlay` application. All star counts
and metadata below were pulled live from the GitHub REST API
(`api.github.com/repos/<owner>/<repo>`) — not estimated.

**Two corrections to the source list, found while pulling data:**

- `meta-llama/llama-guard` does not exist as a standalone repository (404).
  Llama Guard ships inside **`meta-llama/PurpleLlama`**, Meta's LLM-security
  toolkit monorepo. Table entry below uses the correct location.
- `outerbounds/metaflow` does not exist (404) — Metaflow's canonical home is
  **`Netflix/metaflow`** (Outerbounds is the commercial entity that grew out
  of the Metaflow team, but the OSS repo itself is under Netflix's org).
  Table entry below uses the correct location.

---

| # | Repo | Stars | What RIG Adds | Transformation Difficulty | Priority |
|---|---|---:|---|---|---|
| 1 | [`langchain-ai/langgraph`](https://github.com/langchain-ai/langgraph) | 38,995 | LangGraph agents run arbitrary tool loops with no built-in notion of "this agent's output was independently verified before it acted." The overlay adds Builder≠Verifier separation at the graph level (a verifier node re-checks state transitions), L8 gate coverage for graph-compile + graph-invoke smoke tests, and BDD specs for the resilience guarantees LangGraph already claims ("build resilient agents") but doesn't formally test. | **Medium** — large, fast-moving codebase (Python, `uv`-based monorepo with multiple sub-packages); CI already exists so `.rig/verify.sh`'s stack auto-detection and command reuse apply directly; the risk is scale (525K+ repo size) making BDD coverage of "resilience" claims non-trivial to scope narrowly. | **P0** — highest reach: 39K stars, the reference agent-orchestration framework; a governed langgraph sets the template every downstream agent framework copies. |
| 2 | [`promptfoo/promptfoo`](https://github.com/promptfoo/promptfoo) | 23,977 | promptfoo is itself an eval/red-team tool — ironic that its own merges aren't proof-gated. The overlay adds an L8 layer that treats promptfoo's own red-team scan results as an L4/L5 input (dogfooding: use promptfoo to eval promptfoo), and BDD specs that pin down "used by OpenAI and Anthropic" claims as checkable scenarios instead of marketing copy. | **Medium** — TypeScript/Node stack, `npm test` already present, overlay's Node-path auto-detection (Gate 1-3) applies cleanly out of the box; large surface area (2,163 forks) means spec/features/ needs real scoping work, not just the template. | **P0** — an eval/red-team tool that isn't itself proof-gated is the single most credibility-relevant target on this list. |
| 3 | [`confident-ai/deepeval`](https://github.com/confident-ai/deepeval) | 17,435 | DeepEval defines "LLM evaluation" as a product category but has no doctrine file governing its *own* development process. The overlay adds AGENTS.md's Builder≠Verifier rule directly on top of deepeval's own metric-scoring code (the thing that scores others should itself be scored by something else), plus L4 BDD specs turning deepeval's metric definitions into executable Gherkin instead of docstrings. | **Low-Medium** — clean Python package, `pytest` already the test runner, `.rig/smoke.sh`'s Python-path auto-detection needs zero configuration; straightforward apply. | **P1** — second-largest eval framework on the list; governing an eval framework with the overlay is a strong "physician heal thyself" proof point. |
| 4 | [`Arize-ai/phoenix`](https://github.com/Arize-ai/phoenix) | 10,910 | Phoenix is an observability platform — it watches *other* systems for drift and hallucination but has no equivalent self-monitoring for its own release process. The overlay adds .rig/failures.json as literally the same pattern Phoenix sells (a growing ledger of detected regressions) applied reflexively to Phoenix's own codebase. | **Medium-High** — very large repo (499K size on disk), custom license ("Other", not a standard OSS license — worth flagging before any PR), multi-language (Python core + TS UI) so the overlay's single-stack auto-detection will only cover the Python half cleanly; UI half needs a second smoke.sh pass or a manual stack override. | **P1** — high reach, but the multi-stack + license situation raises transformation difficulty above the other P1s. |
| 5 | [`Netflix/metaflow`](https://github.com/Netflix/metaflow) *(corrected from `outerbounds/metaflow`)* | 10,207 | Metaflow orchestrates ML pipelines end-to-end but the pipeline *definitions themselves* aren't governed by anything beyond code review. The overlay's L8 gate is a natural fit for a "flow" — L3 integration maps directly onto "does this flow's DAG actually execute," and proof-gate.yml's tree-hash becomes a natural complement to Metaflow's own artifact versioning. | **Medium** — Python package with mature CI, `go test`/`pytest`-style conventions already present; large org (Netflix) means any actual PR would need to go through a heavier external contribution process than a smaller project. | **P2** — strong conceptual fit (proof-gating pipelines is Metaflow's whole domain) but lower urgency since Metaflow already has strong internal engineering discipline. |
| 6 | [`NVIDIA-NeMo/Guardrails`](https://github.com/NVIDIA-NeMo/Guardrails) *(NVIDIA/NeMo-Guardrails redirects here)* | 6,879 | NeMo Guardrails defines Colang rules to constrain conversational LLM behavior but has no doctrine constraining how *contributors* modify the guardrail engine itself. The overlay's AGENTS.md 12-Leverage-Points checklist is directly applicable to Colang rule design (a rule change is almost always a leverage-point-8 "rules of the system" change) — a natural teaching fit, not just a mechanical bolt-on. | **Medium** — Python, `develop` as default branch (non-standard, `.rig/verify.sh` handles this fine since it doesn't assume `main`), NVIDIA org review process adds external friction similar to Metaflow. | **P2** — good conceptual alignment (guardrails-on-guardrails) but mid-size reach relative to the P0/P1 tier. |
| 7 | [`guardrails-ai/guardrails`](https://github.com/guardrails-ai/guardrails) | 7,257 | Same "guardrails needs guardrails" argument as NeMo, at smaller scale but with a friendlier, single-org contribution path. The overlay's ProofPacket signing model (`allow_builder_self_sign: false`) maps almost 1:1 onto what Guardrails' own validators do at runtime (a validator that approved its own output would be exactly the anti-pattern Guardrails exists to prevent). | **Low** — clean Apache-2.0 Python package, `pytest`, standard `main` branch, smallest/cleanest of the three "guardrails" candidates — best low-friction entry point for a first real-world PR. | **P1** — smallest transformation cost among the guardrails-category repos and the clearest "eat your own dog food" narrative; good first external contribution. |
| 8 | [`AgentOps-AI/agentops`](https://github.com/AgentOps-AI/agentops) | 5,752 | AgentOps monitors agent cost/behavior across many frameworks (CrewAI, Autogen, LangChain, ...) but the SDK itself ships without any behavior spec proving its own instrumentation doesn't silently drop events. The overlay's spec/features/ is the natural place to pin "every monitored agent call produces exactly one tracked event" as an executable contract instead of an implicit assumption. | **Low-Medium** — Python SDK, MIT license, standard `main`, but last push was over a month prior to the other candidates (repo is less actively maintained right now) — worth confirming current maintainer bandwidth before proposing a PR. | **P2** — solid conceptual fit, smaller star count and slower cadence than the P0/P1 tier lowers near-term priority. |
| 9 | [`meta-llama/PurpleLlama`](https://github.com/meta-llama/PurpleLlama) *(corrected from the non-existent `meta-llama/llama-guard`)* | 4,331 | PurpleLlama (home of Llama Guard) is Meta's LLM-security toolkit — high-stakes surface where an unverified change to a safety classifier is a real risk, not a hypothetical one. The overlay's mandatory L7 audit trail + non-negotiable L1/L2/L4/L8 layers in proof-gate.yml are the highest-value fit on this entire list for exactly that reason. | **High** — Meta-owned monorepo with multiple sub-projects (Llama Guard, CyberSecEval, Code Shield) under one roof; a single AGENTS.md/overlay would need per-subproject scoping, and Meta's external contribution bar (CLA, internal review) is the steepest of any repo here. | **P1 (impact) / P3 (near-term feasibility)** — the correctness/safety stakes are the highest of any candidate, but the practical bar to landing a real PR is also the highest; treat as a stretch target, not a first move. |
| 10 | [`huytieu/COG-second-brain`](https://github.com/huytieu/COG-second-brain) | 797 | This is the outlier on the list: COG-second-brain already implements a closed-loop, V-model, "worker never grades its own homework" verification harness — independently converging on almost the same Builder≠Verifier principle this overlay formalizes. Applying the overlay here isn't introducing a new idea, it's the fastest possible **validation case**: does `rig-doctrine-overlay`'s AGENTS.md/L10/L8 stack cleanly compose with a repo that already built an equivalent pattern from scratch, or does it collide with it? | **Low** — small repo (584 KB), single maintainer, MIT license, and — critically — a codebase already conceptually aligned with the overlay, so no doctrine friction is expected; the main work is reconciling naming (its own "closed-loop"/"V-model" terms vs. the overlay's "Builder≠Verifier"/"L8") rather than introducing new constraints. | **P0 (as a test case)** — not for reach (797 stars is the smallest here) but as the fastest, lowest-risk repo to prove the overlay composes correctly with a pre-existing, independently-designed verification harness before pushing into the higher-stakes P0 targets above. |

---

## Priority summary

- **P0 — apply first:** `langchain-ai/langgraph` (reach), `promptfoo/promptfoo`
  (credibility), `huytieu/COG-second-brain` (fast composability test case).
- **P1 — apply next:** `confident-ai/deepeval`, `Arize-ai/phoenix`,
  `guardrails-ai/guardrails`, `meta-llama/PurpleLlama` (impact, but treat the
  timeline as P3 given Meta's contribution bar).
- **P2 — apply after P0/P1 proves the pattern:** `Netflix/metaflow`,
  `NVIDIA-NeMo/Guardrails`, `AgentOps-AI/agentops`.

## Methodology

Stars, forks, license, default branch, and last-push timestamps were pulled
directly from `https://api.github.com/repos/<owner>/<repo>` on the date this
file was written. "Transformation Difficulty" is derived from three concrete,
checkable signals per repo (not a subjective guess):

1. **Stack homogeneity** — does `apply-overlay.sh`'s single-stack
   auto-detection (Node/Python/Go/Rust) cover the whole repo, or is it a
   polyglot monorepo needing a manual override?
2. **Contribution friction** — is this a single-org, standard-license, `main`
   -branch repo (low friction), or a large corporate monorepo with a CLA and
   heavier review process (high friction)?
3. **Existing test/CI maturity** — does the repo already have a real
   `test`/`build` command `.rig/smoke.sh` and `.rig/verify.sh` can shell out
   to, or would the overlay be verifying against a thin/absent test suite?

"What RIG Adds" is scoped to what is *actually missing* in each repo today —
not a generic pitch. Every row names the specific governance gap the overlay
closes for that repo's actual domain.
