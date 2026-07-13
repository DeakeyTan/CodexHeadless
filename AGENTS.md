# CodexHeadless Agent Instructions

## Highest-Priority Rule

Before performing ANY task in this repository, read:

```text
ENGINEERING_CONSTITUTION.md
```

It is the highest-priority project-level engineering rule.

If a PRD, report, historical implementation note, previous `DONE` status, or temporary task instruction conflicts with the Constitution, follow the Constitution unless the project owner explicitly overrides it.

---

## Project Goal

Build and maintain a stable, recoverable macOS menu bar utility for a 2018 Intel MacBook Pro and other supported Macs used as remote Codex development machines.

---

## Permanent Priorities

1. Stability and recoverability first.
2. Always preserve a CLI recovery path.
3. Never disconnect or destroy the last safe display path.
4. Never record resource cleanup unless the real resource is independently verified absent.
5. Never weaken ownership, recovery, rollback, or takeover checks to make tests pass.
6. Always log display, Keep Awake, recovery, and cleanup transitions.
7. Virtual display resolution must remain configurable.
8. Default virtual display resolution is 1920x1080 @ 60Hz unless a newer active PRD explicitly changes it.
9. Private APIs must be isolated, authorized, recoverable, and treated as experimental unless explicitly stabilized.
10. All work remains in `v0.9.x` until the project owner explicitly authorizes `v1.0.0`.

---

## Required Startup Workflow

### Step 1: Read the Constitution

Read `ENGINEERING_CONSTITUTION.md` completely.

Do not rely on a remembered summary.

### Step 2: Locate the Active PRD

Locate and read the newest applicable remediation PRD completely.

When multiple PRDs exist:

1. use the newest PRD that applies to the requested work;
2. read any predecessor documents it references;
3. treat historical completion reports as evidence to verify, not as facts.

### Step 3: Reconstruct the Current System Model

Before modifying code, reconstruct at least:

- RuntimeState and Clean Normal invariants;
- Recovery Journal authority and schema behavior;
- workflow locks and cross-process coordination;
- display topology lifecycle;
- managed virtual display ownership and cleanup;
- built-in display handoff and restore;
- brightness handoff and recoverability;
- Keep Awake assertion-holder lifecycle;
- confirmation and rollback;
- cleanup progress and restore re-entry;
- helper authorization;
- failure injection and persistence boundaries.

Do not begin with isolated patching.

### Step 4: Build an Issue Map

For every active issue, record:

```text
Issue ID
→ current code location
→ triggering scenario
→ observed failure
→ root cause
→ violated invariant
→ planned code changes
→ planned tests
→ verification commands
```

### Step 5: Implement in Priority Order

Use this order unless the active PRD explicitly defines a stricter dependency sequence:

```text
P0
→ P1
→ P2
→ full verification
→ independent audit
```

Do not skip unresolved higher-priority items.

---

## Closed-Loop Execution

After implementing the active PRD, continue automatically:

```text
Build
→ Run automated tests
→ Static audit
→ State-machine and lifecycle audit
→ Security and recovery audit
→ Release verification when applicable
→ Independent source-code audit
```

The independent audit must ignore earlier developer claims and inspect current source and actual evidence again.

If the audit finds a new P0, P1, or material P2 issue:

1. classify it;
2. create the next complete remediation PRD;
3. include code location, scenario, symptoms, root cause, remediation design, prohibited pseudo-fixes, tests, and acceptance criteria;
4. implement it automatically;
5. rerun verification;
6. audit again;
7. repeat until the Constitution stop conditions are met or work is externally blocked.

Do not stop merely because the originally requested PRD has been implemented.

---

## Evidence Rules

Only claim `DONE` when all of the following are true:

```text
implementation completed
+
corresponding tests actually executed and passed
+
acceptance criteria satisfied
+
independent audit found no remaining issue for that item
```

Use only these statuses:

- `DONE`
- `PARTIALLY DONE`
- `BLOCKED`
- `NOT STARTED`
- `NOT VERIFIED`

Never use test-source count, parsing, compilation alone, or historical reports as proof that tests passed.

If XCTest cannot run, report `NOT VERIFIED` or `BLOCKED`; do not claim PASS.

---

## Safety Rules

- Before changing display topology, persist durable recovery evidence and log the current display state.
- Never destroy a managed virtual display before a usable physical display has safely taken over and every required pre-cleanup recovery step has succeeded.
- Never use brightness dimming when the original brightness cannot be restored reliably.
- Never treat `mode == Normal` as sufficient proof of Clean Normal.
- Never terminate a process whose ownership cannot be independently verified.
- Never write Keep Awake Off until the real assertion holder is verified absent.
- Never write Virtual Display Off until the owned host and managed display are verified absent.
- Never delete the last trustworthy Recovery Journal or ownership record while a managed resource may still exist.
- Never overwrite, downgrade, or rebuild a future-schema persistence file.
- Internal helper commands must require workflow-bound authorization; a hidden command name is not authorization.
- Validate custom resolutions before creating a virtual display.
- Preserve a CLI recovery path throughout every workflow.

---

## Configuration Mutation Rules

Configuration changes that affect display, recovery, Keep Awake, confirmation, timing, or managed resources must be allowed only when the Core confirms Clean Normal, unless an active PRD explicitly defines a safe exception.

UI availability is not a sufficient safety boundary. Core must re-read state after acquiring the workflow lock.

---

## Standard Commands

- Build: `swift build --build-system native`
- Test: `swift test --build-system native`
- Build arm64: `swift build --build-system native --arch arm64`
- Build x86_64: `swift build --build-system native --arch x86_64`
- Run menu bar app: `swift run CodexHeadless`
- CLI Status: `swift run codex-headless status`
- CLI On: `swift run codex-headless on`
- CLI Off: `swift run codex-headless off`
- Set Resolution: `swift run codex-headless config set resolution 2560x1440`
- Shell validation: `bash -n scripts/*.sh`
- Diff whitespace validation: `git diff --check`

Also run all additional verification commands required by the active PRD.

If the current environment cannot execute a required command, finish all unblocked work and report the command as `BLOCKED` or `NOT VERIFIED` with the exact reason.

---

## Required Reports

For a remediation cycle, generate the reports required by the active PRD. At minimum, include:

- Audit Remediation Report;
- Test Verification Report;
- Release Verification Report when applicable;
- Manual Hardware Test Checklist.

Reports must include:

- issue-by-issue status;
- modified files;
- tests added;
- exact commands and exit codes;
- actual test count;
- supported build architectures;
- release artifact paths and checksums when applicable;
- manual and hardware items not performed;
- Candidate Gate conclusion.

---

## Stop Conditions

Only stop the automatic remediation loop when:

1. the Candidate Gate in `ENGINEERING_CONSTITUTION.md` is satisfied; or
2. every remaining item is genuinely blocked by an external dependency or physical hardware validation unavailable in the current environment.

When blocked:

- complete all unblocked work;
- preserve a precise manual checklist;
- keep unresolved items marked `BLOCKED` or `NOT VERIFIED`;
- do not claim Candidate status.

---

## Automation Boundaries

Codex MAY automatically:

- inspect and audit code;
- create remediation PRDs;
- implement and refactor relevant code;
- add tests;
- run verification;
- update documentation and reports;
- continue remediation iterations.

Codex MUST NOT automatically:

- modify `pet-runs/`;
- delete historical PRDs or reports;
- commit unless explicitly instructed;
- push;
- merge;
- create tags;
- publish a release;
- upgrade to `v1.0.0`;
- weaken safety requirements.

---

## Final Response Requirements

At the end of a remediation cycle, report:

1. active PRD;
2. current v0.9.x version;
3. P0/P1/P2 item statuses;
4. architecture decisions;
5. modified files;
6. tests added;
7. commands executed and exit codes;
8. actual XCTest count;
9. release artifact and architecture results;
10. remaining manual or blocked items;
11. whether any commit, push, tag, or release occurred;
12. whether the v0.9.x Candidate Gate is satisfied;
13. whether the v1.0.0 gate is satisfied.

Do not replace this with vague claims such as “mostly complete,” “looks fixed,” or “tests were added.”
