<div align="center">
  <img src="assets/rig-doctrine-overlay-hero.png" width="100%" />
</div>

<br/>

<div align="center">
  <h3>RIG Doctrine Overlay</h3>
  <p><em>Install doctrine, verification and doctrine checks into any repo, and take them out again cleanly.</em></p>
</div>

<div align="center">

![status](https://img.shields.io/badge/status-installer-C8A96E?style=flat-square&labelColor=0A0806)
![layers](https://img.shields.io/badge/layers-5-C8A96E?style=flat-square&labelColor=0A0806)
![idempotent](https://img.shields.io/badge/idempotent-yes-5B8C5A?style=flat-square&labelColor=0A0806)
![license](https://img.shields.io/badge/license-MIT-C8A96E?style=flat-square&labelColor=0A0806)

</div>

<br/>

Point `apply-overlay.sh` at a repository and it adds a governance overlay: an
`AGENTS.md` doctrine file, a smoke harness, an eight-layer verifier, three
doctrine checks, a BDD example and a README header. Every file it creates or
changes is recorded in a manifest, so `uninstall-overlay.sh` puts the target
back exactly as it was. It never touches your source code, tests, license or CI
config. The only existing file it edits is the README (a header is prepended;
the original is backed up), plus `AGENTS.md`/`CLAUDE.md` if you pass `--force`.

## Install and remove

```bash
./apply-overlay.sh /path/to/target-repo            # install
./apply-overlay.sh /path/to/target-repo --dry-run  # list what would be written, write nothing
./apply-overlay.sh /path/to/target-repo --force    # reinstall over a previous overlay install
./uninstall-overlay.sh /path/to/target-repo        # restore the target to its pre-install state
```

Needs `bash`, `git` and `python3` (standard library only). `smoke.sh --learn`
also needs `jq`.

Safety rules the installer enforces:

- A second install without `--force` exits 2. `--force` first uninstalls the
  previous overlay (restoring the originals), then installs fresh, so repeated
  `--force` runs never stack README headers or lose the original backup.
- If the target already has a `.rig/` directory that the overlay did not create,
  the installer refuses (exit 2) even with `--force`, because uninstall could
  not restore it.
- Uninstall deletes the whole `.rig/` directory, including anything you added to
  it (such as claims in `.rig/claims.jsonl`). Caches made by running the
  target's own tests (`__pycache__`, `.pytest_cache`) are not overlay files and
  are left alone.

## What gets installed

| Layer | File | What it does |
| :-: | :-- | :-- |
| 1 — Doctrine | `AGENTS.md`, `CLAUDE.md` | Rules for agents working in the repo (Core Four, leverage points, Builder ≠ Verifier). `CLAUDE.md` is a pointer to `AGENTS.md`. Existing files are kept unless `--force`. |
| 2 — Smoke | `.rig/smoke.sh` | Five gates: syntax, unit tests, import/build, BDD file structure, doctrine checks. With `--learn`, failed gates are appended to `.rig/failures.json` and listed at the start of every later run. |
| 3 — Verify | `.rig/verify.sh` | Eight layers, each PASS/FAIL with printed evidence (table below). `--continue` runs every layer; `--layer=N` runs one. |
| 3 — Checks | `.rig/rig_checks.py` | The three doctrine checks below. Also run as layer L5 of `verify.sh`. |
| 4 — BDD | `spec/features/example.feature` | Gherkin template; installed only if `spec/features/` has no `.feature` files yet. |
| 5 — Gate config | `.rig/proof-gate.yml` | `threshold.min_pass_rate` is enforced by `verify.sh` L6. The other keys are configuration for planned features (see Roadmap). |

### Doctrine checks (`.rig/rig_checks.py`)

```bash
python3 .rig/rig_checks.py all        # or: claims | tests | secrets ; add --json for machine output
RIG_BASE_REF=origin/main python3 .rig/rig_checks.py tests   # diff against a branch instead of HEAD
```

Exit 0 means no violations, 1 means violations (each printed as a `VIOLATION` line), 2 is a usage error.

| Check | Violation |
| :-- | :-- |
| `claims` | A line in `.rig/claims.jsonl` with status `done`/`complete`/`verified`/`shipped` whose `evidence` is missing, is prose, names a file that does not exist or is empty, has a `sha256` that no longer matches the file, or names a `command` with no recorded `output`. |
| `tests` | A changed source file (`.py`, `.js`/`.jsx`/`.ts`/`.tsx`, `.go`; changed = differs from `HEAD` or `$RIG_BASE_REF`, or untracked) with no matching test file: `test_<name>.py` / `<name>_test.py`, `<name>.test.*` / `<name>.spec.*`, or `<name>_test.go` in the same directory. `__init__.py`, config files, files under `tests/`, `docs/`, `examples/` and `fixtures/`, and globs listed in `.rig/test-exempt.txt` are skipped. |
| `secrets` | A secret-shaped string in any tracked or untracked (not ignored) text file: AWS access key ids, GitHub, Slack and `sk-` style tokens, Google API keys, private key blocks, and high-entropy values assigned to names like `password`, `token`, `api_key`. Values are masked in the output. Add `rig: allow-secret` to a line to skip it. |

A claim that passes looks like this:

```json
{"id": "c1", "status": "done", "claim": "mean() rejects empty input", "evidence": {"command": "pytest -q", "output": "3 passed"}}
{"id": "c2", "status": "done", "evidence": {"path": "reports/load-test.txt", "sha256": "<sha256 of the file>"}}
```

<details>
<summary><strong>The eight verify layers</strong></summary>

<br/>

| Layer | Checks |
| :-: | :-- |
| L1 syntax | Python files compile (in memory, no `.pyc` written), `node --check`, `gofmt -l`, or `cargo check` |
| L2 unit | `pytest -q`, `npm test`, `go test ./...` or `cargo test` |
| L3 integration | Top-level Python package imports, `npm run build`, `go build ./...` or `cargo build` |
| L4 eval | At least one `spec/features/*.feature` file exists |
| L5 doctrine | `rig_checks.py all` reports no violations |
| L6 gate | Pass rate of the layers so far meets `min_pass_rate` in `.rig/proof-gate.yml` |
| L7 audit | The repo has git history |
| L8 signoff | Every executed layer passed |

The stack is detected from `package.json`, `pyproject.toml`/`setup.py`, `go.mod`
or `Cargo.toml`. When a tool for a layer is not installed, that layer prints a
no-op PASS and says so. The tests and the CI smoke run cover the Python path;
the Node, Go and Rust branches are not exercised in CI.

</details>

## Tests and CI

```bash
python -m pip install pytest ruff
python -m pytest -q          # apply, verify (pass + each violation), uninstall, checks unit tests
scripts/smoke-e2e.sh         # overlay a fresh copy of tests/fixtures/sample-repo end to end
```

`scripts/smoke-e2e.sh` copies the sample repo, applies the overlay, requires
`verify.sh` to pass, plants a done-claim without evidence, an untested module
and a fake AWS key, requires all three to be reported and `verify.sh` to fail,
then uninstalls and diffs the result against a pristine copy.

CI (`.github/workflows/ci.yml`) runs shellcheck, ruff, pytest, the end-to-end
smoke, and the doctrine checks on this repo itself (this repo carries its own
copy of the overlay in `.rig/`; a test keeps it identical to `templates/`).

## Roadmap

Not implemented yet. The config keys exist in `proof-gate.yml` but nothing reads them:

- HMAC-signed ProofPacket (`.rig/proof-packet.json`): tree hash over `artifacts.source_paths`, signing with `RIG_PROOF_KEY`, packet age (`max_packet_age_hours`).
- Signer separation: enforcing `allow_builder_self_sign: false` and `verifier_identities`.
- `required_pass_layers` and `min_bdd_scenarios` enforcement in L6.
- Executing the BDD scenarios (today L4 and smoke gate 4 check that `.feature` files exist and contain `Feature:`/`Scenario:` lines).
- CI coverage for the Node, Go and Rust detection paths.
- Re-running each recorded failure as its own regression test (today `smoke.sh` lists past failures and reruns the normal gates).

## Documentation

| Resource | Description |
| :-- | :-- |
| [`templates/AGENTS.md`](templates/AGENTS.md) | Layer 1 — doctrine template |
| [`templates/smoke.sh`](templates/smoke.sh) | Layer 2 — smoke harness |
| [`templates/verify.sh`](templates/verify.sh) | Layer 3 — eight-layer verifier |
| [`templates/rig_checks.py`](templates/rig_checks.py) | Doctrine checks: claims, tests, secrets |
| [`templates/feature.template.feature`](templates/feature.template.feature) | Layer 4 — BDD template |
| [`templates/proof-gate.yml`](templates/proof-gate.yml) | Layer 5 — gate config |
| [`assets/architecture.svg`](assets/architecture.svg) | Design diagram of the five layers (shows the planned signed ProofGate, see Roadmap) |
| [`TOP-10-CANDIDATES.md`](TOP-10-CANDIDATES.md) | Repos this overlay was designed for |
| [LICENSE](LICENSE) | MIT |

---

<div align="center"><sub>Built by Mike Rodgers · <a href="https://rodgersintelligence.com">rodgersintelligence.com</a></sub></div>
