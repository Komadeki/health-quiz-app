# KOMADEKI UI/UX Autopilot Contract v1.0

This contract defines a durable autonomous UI/UX workstream for the KOMADEKI Qualification App Factory. It is separate from the Drone Question Bank Autopilot and must not use chat history, browser state, model memory, or local-only commits as completion evidence.

## 1. Goal

Move the reusable Qualification Factory UX and the Drone reference-product UX from the current production baseline to product-ready UX with minimal routine owner labor.

The ordered state machine is:

1. `BASELINE_AUDIT`
2. `STANDARD_UX_CONTRACT`
3. `CORE_UX_IMPROVEMENT`
4. `DRONE_SPECIFIC_UX`
5. `ACCESSIBILITY_RESPONSIVE`
6. `PRODUCT_UX_CLOSURE`
7. `PHYSICAL_UX`
8. `DONE`

A phase may be revisited only when new evidence invalidates a previously passed UX gate.

## 2. Durable authority

Authoritative evidence is limited to:

- GitHub `main`;
- open and merged pull requests;
- required CI and tests;
- `tooling/komadeki_ui_ux_autopilot/ui_ux_state.json`;
- the control issue referenced by that state;
- repository architecture contracts, especially `docs/QUALIFICATION_APP_FACTORY.md`, `docs/ADDING_QUALIFICATION_APP.md`, and `docs/MONOREPO.md`;
- current production implementation under `packages/qualification_app` and `apps/drone_second_class`;
- physical-device evidence only when the phase explicitly requires it.

Chat history and ephemeral work are never completion evidence.

## 3. Scope boundary

### Shared Factory UX

Reusable learning/navigation/product behavior belongs primarily in `packages/qualification_app` and, when UI-independent, `packages/quiz_engine`.

Examples include home hierarchy, quiz interaction, feedback presentation, progress, history, weakness, recommendation, practice modes, mock-exam presentation, purchase/restore presentation, empty/loading/error states, accessibility, and responsive behavior.

### Qualification-specific UX

Drone-specific presentation belongs in `apps/drone_second_class` or manifest/configuration seams when it reflects a defensible qualification difference such as official terminology, exam structure, source presentation, learning path, or domain-specific explanatory context.

Do not fork shared controllers, persistence, selection algorithms, purchase handling, or standard screens merely to make Drone look different.

### Prohibited cross-workstream mutation

This UI/UX workstream must not mutate Question Bank authoring, acceptance, permanent IDs, released/runtime bank content, or `tooling/komadeki_autopilot/drone_state.json` unless the current atomic objective explicitly requires a compatibility update after the Question Bank workstream has already changed an interface on `main`.

## 4. Product UX principles

Until a more specific durable Standard UX Contract is adopted, autonomous decisions must follow these defaults:

1. make the primary next learning action obvious;
2. prioritize resume/review/weakness-driven action over a flat feature menu;
3. minimize unnecessary taps for frequent learning actions;
4. keep correctness, explanation, progress, purchase state, and errors unambiguous;
5. never invent unsupported pass probability, official endorsement, or exam-performance claims;
6. preserve source traceability when the Question Bank exposes source metadata;
7. avoid metrics that do not lead to a useful learner action;
8. support Dynamic Type/text scaling, semantics, sufficient touch targets, and long Japanese question text;
9. preserve Factory reuse: improve shared UX once when the requirement is reusable;
10. preserve qualification differentiation where the qualification genuinely differs.

## 5. Atomic transition rule

One autonomous run performs at most one meaningful UX transition, for example:

- persist a baseline UX audit and prioritized backlog;
- adopt or revise one Standard UX acceptance contract;
- implement one bounded P0/P1 UX improvement;
- add one reusable source-aware feedback component;
- close one accessibility/responsive defect class;
- close one Drone-specific UX gap;
- advance one phase after its exit criteria are proven.

A transition is complete only after durable GitHub evidence exists.

## 6. Resource routing

Use the lightest mechanism that meets the quality requirement.

- Read-only repository inspection, issue/state updates, PR/CI audit, and deterministic metadata persistence: ChatGPT GitHub tools.
- Production code mutation, widget/test implementation, multi-file UI behavior changes, or refactors: Codex using the lightest capable implementation model.
- Escalate only for architecture changes, unclear state/lifecycle defects, or cross-package reasoning that a standard implementation model cannot resolve.
- Pro-level reasoning is reserved for final release/product gate or a high-risk independent audit when ordinary reasoning is insufficient.

Implementation-worker output is not completion evidence until pushed to GitHub and independently audited.

## 7. PR and CI gate

Production changes normally use a branch and PR. Before merge, independently verify:

- latest `main` and expected base/head;
- intended changed files only;
- no collision with open Question Bank or other UI/UX PRs;
- architecture boundaries remain valid;
- relevant unit/widget tests pass;
- repository required CI passes;
- no unresolved P0/P1 audit finding introduced by the transition.

Never merge stale work merely because its original CI passed. Reconcile against current `main` first when concurrent autonomous work has landed.

## 8. Baseline audit requirements

The initial audit must inspect at minimum:

- Home information hierarchy and primary action;
- resume behavior;
- unit/practice-mode discovery;
- quiz selection and answer-commit interaction;
- correct/incorrect feedback and explanation presentation;
- mock-exam timing and result presentation;
- progress, weakness, recommendation, and history;
- Full Unlock and Restore presentation;
- loading, empty, fatal-error, and inaccessible-content states;
- long-text behavior, semantics, text scaling, and responsive constraints;
- current widget/controller test coverage;
- shared-vs-Drone ownership of every proposed improvement.

The audit produces a durable backlog with P0/P1/P2 priority, evidence, expected user impact, proposed ownership (`FACTORY_SHARED` or `DRONE_SPECIFIC`), and acceptance criteria. The audit itself must not alter production behavior.

## 9. Human-only gate

Normal UX design and implementation must not be returned to the owner.

Enter `HUMAN_BLOCKED` only when evidence genuinely cannot be produced by available tools, such as:

- a final visual/brand choice explicitly reserved to the owner;
- a physical-device observation that cannot be established remotely;
- Apple authentication/signing or store actions outside available authenticated tooling.

Do not create a human blocker merely because a decision is subjective. Prefer a reversible, contract-consistent default and continue unless the decision is explicitly owner-reserved or materially irreversible.

## 10. Completion

`DONE` requires durable evidence that:

- the Standard UX Contract is adopted;
- all accepted P0 and P1 shared UX findings are closed or explicitly rejected with rationale;
- all accepted P0 and P1 Drone-specific UX findings are closed or explicitly rejected with rationale;
- accessibility/responsive checks are complete;
- Product UX Closure passes;
- required physical-device UX evidence is complete or incorporated into the parent product release gate;
- machine state and control issue are synchronized.

When `DONE` is reached, autonomous UI/UX mutation stops.