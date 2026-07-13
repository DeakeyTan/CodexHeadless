# CodexHeadless Engineering Constitution

Version: 1.0
Status: Active
Priority: Highest project-level engineering rule

This document defines the permanent engineering rules for the CodexHeadless project.

Every implementation task, remediation task, audit, refactor, test effort, release preparation, and generated PRD MUST follow this Constitution.

If a PRD, report, task prompt, implementation comment, or historical decision conflicts with this Constitution, this Constitution takes precedence unless the project owner explicitly overrides it.

---

## 1. Source Code and Observable Behavior Are the Source of Truth

Never assume that any of the following proves an issue is resolved:

- a previous audit report;
- a previous PRD;
- a TODO marked complete;
- a commit message;
- an implementation comment;
- a generated remediation report;
- a previous `DONE` status;
- a test file that has not actually run.

These are hypotheses and records, not proof.

The authoritative evidence is:

1. current source code;
2. actual build output;
3. actually executed tests;
4. observable runtime behavior;
5. independently observable system state;
6. verified release artifacts.

Every audit starts from the current source and reconstructs the relevant system model again.

---

## 2. Reconstruct the Mental Model Before Modifying Code

Every implementation or audit must begin by reconstructing the current architecture relevant to the task.

At minimum, understand:

- RuntimeState and its invariants;
- Recovery Journal and its authority boundaries;
- workflow locking and cross-process coordination;
- display topology lifecycle;
- managed virtual display lifecycle;
- built-in display handoff and restore lifecycle;
- Keep Awake ownership and assertion lifecycle;
- confirmation and rollback lifecycle;
- cleanup progress and restore re-entry;
- process ownership and PID-reuse protection;
- config and persistence schema compatibility;
- failure injection and recovery behavior.

Do not patch isolated lines before understanding how the change affects the full lifecycle.

---

## 3. Independent Engineering Roles

During each closed-loop iteration, act as separate roles:

```text
Developer
→ Reviewer
→ Security Auditor
→ QA Engineer
→ Release Engineer
→ Independent Reviewer
```

Each role must challenge the assumptions made by the previous role.

The Reviewer must inspect current code instead of trusting the Developer's explanation.

The Security Auditor must verify invariants, ownership, race boundaries, corruption handling, and recovery rather than trusting unit-test intent.

The QA Engineer must verify observable behavior and failure paths rather than trusting implementation structure.

The Release Engineer must verify actual artifacts rather than trusting build scripts.

The final Independent Reviewer must start from source and evidence again.

A developer conclusion cannot approve itself.

---

## 4. Closed-Loop Engineering Workflow

Every substantive task follows this lifecycle:

```text
Understand architecture
→ Implement
→ Build
→ Run automated tests
→ Perform static audit
→ Perform state-machine and lifecycle audit
→ Perform security and recovery audit
→ Verify release assets when applicable
→ Independently review current source
→ Classify newly discovered issues
→ Generate a remediation PRD when required
→ Continue implementation
```

The loop continues automatically until the Candidate Gate is satisfied or work is genuinely blocked by an external limitation.

Do not stop merely because the original PRD items were implemented.

---

## 5. Safety Before Features and Convenience

Never weaken safety to make a build, test, or demo pass.

Do not reduce:

- ownership verification;
- physical display takeover verification;
- recovery guarantees;
- cleanup guarantees;
- state consistency;
- future-schema protection;
- rollback guarantees;
- corruption handling;
- cross-process locking.

Prefer refusing an unsafe operation over recording a false success.

---

## 6. Recorded State Must Match Independently Observable Reality

A recorded flag is not proof that a resource exists or has stopped.

Never write `Keep Awake = Off` unless the real assertion holder has been identified, stopped, and independently verified absent.

Never write `Virtual Display = Off` unless both the owned host and the managed virtual display have been independently verified absent.

Never write `Normal` unless the Clean Normal invariant is satisfied.

Never return Restore success while a required recovery stage is unknown, failed, or unverified.

RuntimeState alone is never sufficient evidence for managed-resource truth.

---

## 7. Observable Facts and Trust Boundaries

Relevant observable facts include:

- active and online displays;
- which display is main;
- physical versus managed virtual display identity;
- real managed process facts;
- executable canonical path and file identity;
- process start time;
- PID-reuse evidence;
- assertion holder identity;
- Recovery Journal contents and schema;
- independent ownership sidecars or capabilities;
- actual process tree;
- actual release binary architecture and version.

A resource may not prove its own ownership solely through the same untrusted RuntimeState record or its own command line.

Ownership must be supported by an independent, persisted trust record and current observable facts.

---

## 8. Clean Normal Is an Invariant, Not a Mode Name

`RuntimeState.mode == Normal` does not by itself mean the system is clean.

Clean Normal requires all relevant conditions to be true, including:

- no active CodexHeadless Keep Awake resource;
- no active CodexHeadless virtual display host;
- no managed virtual display still enumerated;
- no pending Recovery Journal;
- no soft-disconnected built-in display;
- no unresolved brightness handoff;
- no unresolved Touch Bar handoff;
- no incomplete cleanup stage;
- a usable physical display has safely taken over;
- RuntimeState reflects these facts.

Enable must require Clean Normal, not merely `mode == Normal`.

---

## 9. Restore Success Is Strict

A Restore operation may return success only after all required recovery work is complete and verified.

Depending on the active handoff, this includes:

- restoring and verifying a usable physical display;
- restoring brightness when brightness was changed;
- restoring Touch Bar state when changed;
- stopping the owned virtual display host;
- verifying the managed virtual display disappeared;
- stopping the real Keep Awake assertion holder;
- verifying the assertion holder disappeared;
- persisting Clean Normal RuntimeState;
- finalizing or safely deleting the Recovery Journal.

If any required stage fails or remains unknown, return a non-success result and preserve enough recovery evidence to resume.

---

## 10. Every Side Effect Requires Durable Recovery Evidence

Before or immediately when a system resource is created or changed, persist enough independent information to recover it after:

- process crash;
- App restart;
- CLI takeover;
- RuntimeState corruption;
- config corruption;
- partial persistence failure;
- partial cleanup failure.

A resource-start workflow must follow a durable protocol such as:

```text
Reserve intent
→ Start resource
→ Observe ownership and effect
→ Persist observed record to Recovery Journal
→ Commit RuntimeState
```

If any persistence or cleanup stage fails, do not delete the last trustworthy recovery record.

---

## 11. Every Failure Path Must Preserve Recoverability

Every failure path must answer:

- Can the user recover now?
- Can the App recover after restart?
- Can the CLI continue recovery?
- Can recovery continue if RuntimeState is damaged?
- Is the last replacement display preserved when needed?
- Is Keep Awake preserved when sleep would make recovery harder?
- Is ownership evidence retained?

If these answers are unclear, the implementation is incomplete.

---

## 12. Future Schemas Are Never Damage

A persisted file with a schema version newer than the current application supports must never be:

- deleted;
- overwritten;
- downgraded;
- migrated as a legacy schema;
- backed up and replaced as ordinary corruption.

Future schema handling must preserve the original file and report an explicit unsupported-version condition.

The application may refuse Enable and require an upgrade, but it must not destroy newer recovery evidence.

---

## 13. Internal Helpers Require Authorization

An internal command name such as `__helper-name` is not a security boundary.

Any helper that can change display state, Touch Bar state, Keep Awake state, or create a managed resource must require an authenticated one-time capability or equivalent workflow-bound authorization.

The authorization should bind the helper invocation to relevant facts such as:

- operation ID;
- helper kind;
- nonce or token;
- expiration;
- expected parent or launcher;
- valid Recovery Journal stage;
- single-use semantics.

Manual invocation without valid authorization must produce no side effect.

---

## 14. Testing Rules

The existence of test source does not mean the behavior is verified.

A test is verified only when it actually runs and passes in a supported environment.

If execution is impossible, record:

```text
NOT VERIFIED
```

Never replace XCTest execution with parsing, compilation alone, or source-code counting.

Fakes must not silently provide capabilities unavailable in production. Production limitations must be represented explicitly in tests.

Tests must cover lifecycle boundaries, not only happy-path return values.

---

## 15. Required Audit Categories

Each independent audit must consider at least:

- state drift;
- resource leaks;
- ownership mismatch;
- PID reuse;
- TOCTOU races;
- cross-process conflicts;
- partial persistence;
- partial cleanup;
- restart and re-entry;
- corrupted state/config/journal;
- future schema compatibility;
- helper authorization;
- release artifact correctness;
- unsafe test doubles;
- false success reporting.

---

## 16. New Findings Generate a New Remediation PRD

When an audit discovers a new P0, P1, or material P2 issue, do not merely append an informal TODO.

Automatically:

1. classify the issue;
2. identify the current code location;
3. describe the triggering scenario and observed failure;
4. explain the root cause;
5. define the safety invariant;
6. describe the remediation approach;
7. list prohibited pseudo-fixes;
8. define tests and acceptance criteria;
9. create the next remediation PRD;
10. continue implementation and verification.

The PRD becomes durable project memory, but it remains subject to later source-based audit.

---

## 17. Status Vocabulary

Use only clear evidence-based statuses:

- `DONE`
- `PARTIALLY DONE`
- `BLOCKED`
- `NOT STARTED`
- `NOT VERIFIED`

`DONE` requires implementation, actual verification, and satisfaction of acceptance criteria.

Do not use vague conclusions such as:

- mostly complete;
- appears fixed;
- tests added;
- static checks look good;
- primary path works.

---

## 18. Candidate Gate

The project may be declared a v0.9.x Candidate only when all of the following are true:

- no unresolved P0;
- no unresolved P1;
- P2 issues are closed or explicitly accepted as external limitations, manual hardware validation, or approved deferrals;
- automated tests actually executed with nonzero test count and passed;
- supported architecture builds passed;
- release assets passed verification when applicable;
- architecture and security audits found no new blocking issue;
- resource lifecycle and recovery tests passed;
- required reports accurately reflect evidence;
- version remains within the approved v0.9.x line.

If the Candidate Gate is not satisfied, continue the closed-loop workflow.

---

## 19. Version Policy

All P0, P1, P2, release preparation, and candidate validation work remains in the `v0.9.x` version line.

Codex must never automatically change the project to `v1.0.0`.

Only the project owner may authorize `v1.0.0`, after:

- Candidate Gate passes;
- Intel hardware validation passes;
- Apple Silicon hardware validation passes;
- long-duration and repeated-cycle testing passes;
- release evidence is reviewed;
- the project owner explicitly approves the version change.

---

## 20. Automation Boundary

Codex may automatically:

- audit source code;
- reconstruct architecture;
- write remediation PRDs;
- implement fixes;
- refactor relevant code;
- add and run tests;
- run build and release verification;
- update documentation and reports;
- repeat remediation loops.

Codex must not automatically:

- commit unless explicitly instructed;
- push;
- merge;
- create tags;
- publish releases;
- upgrade to `v1.0.0`;
- delete historical PRDs or audit reports;
- weaken safety gates;
- modify `pet-runs/`.

---

## 21. Scope Discipline

Do not make unrelated improvements merely because they are convenient.

Changes outside the active remediation scope are allowed only when necessary to satisfy an invariant, remove a blocking architectural defect, or keep the project compiling and testable.

Record such changes in the remediation report.

---

## 22. Evidence and Reporting

Every completed remediation cycle must produce evidence appropriate to the task, including:

- audit report;
- test verification report;
- release verification report when applicable;
- manual hardware test checklist;
- exact commands and exit codes;
- actual test counts;
- build architectures;
- release artifact hashes;
- remaining blocked or manual items.

Reports must distinguish current independently verified evidence from historical or agent-reported claims.

---

## 23. Stop Conditions

The automatic remediation loop may stop only when:

1. the Candidate Gate is satisfied; or
2. all remaining work is genuinely blocked by an external dependency or physical hardware validation that cannot be performed in the current environment.

When blocked:

- finish all unblocked engineering work;
- preserve a clear manual checklist;
- mark the relevant items `BLOCKED` or `NOT VERIFIED`;
- do not claim Candidate status.

---

## 24. Permanent Engineering Preferences

Prefer:

```text
correctness over convenience
observable facts over recorded assumptions
explicit recovery over implicit cleanup
fail-safe refusal over false success
architecture over local patches
deterministic behavior over timing assumptions
long-term maintainability over short-term completion claims
```

---

End of Constitution.
