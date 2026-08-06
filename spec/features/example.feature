@rig-doctrine @proof-gated
Feature: <REPLACE: name of the behavior this feature file governs>
  As a <REPLACE: role — e.g. "developer using this library">
  I want <REPLACE: capability — e.g. "invalid input to be rejected before it reaches the model">
  So that <REPLACE: outcome — e.g. "the system never silently produces an unverified result">

  # This file lives under spec/features/ and is checked for presence and
  # structural validity by .rig/smoke.sh (Gate 4/5, "eval gate") and
  # .rig/verify.sh (L4-eval). Delete the REPLACE markers and the example
  # scenarios below once you've written real ones for this repo.
  #
  # Convention: every Scenario in this repo MUST end its Then clause with an
  # assertion that a proof gate was checked — either an explicit exit code,
  # a written artifact, or a signed packet. "It looks right" is not a Then.

  Background:
    Given the repository has the RIG doctrine overlay installed
    And ".rig/proof-gate.yml" exists and is readable

  Scenario: Happy path — a correct change clears every layer
    Given a candidate change that satisfies all acceptance criteria
    When ".rig/smoke.sh --learn" is run
    Then all 5 smoke gates report PASS
    And ".rig/verify.sh" is run independently
    And all 8 verification layers report PASS
    And exit code is 0

  Scenario: A regression is caught and remembered
    Given a change that reintroduces a previously-fixed bug
    And that bug's signature already exists in ".rig/failures.json"
    When ".rig/smoke.sh --learn" is run
    Then the regression replay section lists the matching prior failure
    And the relevant gate reports FAIL
    And exit code is 1
    And no new entry silently overwrites the existing failure record

  Scenario: Builder cannot self-certify
    Given a builder agent has produced a candidate diff
    When the builder claims the change is "done" without command output
    Then the claim is treated as unverified
    And an independent verifier pass re-runs ".rig/verify.sh"
    And only a verifier identity listed in "proof-gate.yml#signers" may set signed: true

  Scenario Outline: Each verification layer produces evidence, not opinion
    Given layer "<layer>" is executed via ".rig/verify.sh --layer=<layer_number>"
    When the layer completes
    Then the output includes a PASS or FAIL line
    And the output includes an "evidence:" line with a concrete artifact, command, or file
    And a bare assertion with no evidence is treated as FAIL

    Examples:
      | layer          | layer_number |
      | L1-syntax      | 1            |
      | L2-unit        | 2            |
      | L3-integration | 3            |
      | L4-eval        | 4            |
      | L5-proof       | 5            |
      | L6-gate        | 6            |
      | L7-audit       | 7            |
      | L8-signoff     | 8            |
