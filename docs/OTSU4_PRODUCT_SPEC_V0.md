# Otsu4 Product Spec v0

## Frozen exam profile

- Product: 危険物取扱者 乙種第4類 (Otsu4); no eligibility prerequisite; five-choice written examination; 2 hours.
- Blueprint: 法令 15, 基礎的な物理学及び基礎的な化学 10, 危険物の性質並びにその火災予防及び消火の方法 10.
- Pass rule: at least 60% in each of the three subjects. The product must present readiness by subject; it must not claim an official pass prediction.

## Authoritative source set

| ID | Authority | Use | Rights classification |
| --- | --- | --- | --- |
| O4-EXAM-1 | [消防試験研究センター・危険物取扱者試験](https://www.shoubo-shiken.or.jp/) | eligibility, format, duration, blueprint, pass rule | factual/exam-profile reference; do not copy published questions |
| O4-COPYRIGHT-1 | [消防試験研究センター](https://www.shoubo-shiken.or.jp/) | published-question copyright restriction | prohibited for commercial question reproduction, adaptation, or "past-question collection" claims |
| O4-LAW-1 | [消防法 (e-Gov)](https://laws.e-gov.go.jp/law/323AC0000000186) | statutory concepts and definitions | public-law reference; author original wording and explanations |
| O4-LAW-2 | [危険物の規制に関する政令 (e-Gov)](https://laws.e-gov.go.jp/) | classifications, specified quantities, regulatory detail | public-law reference; verify current version before each batch |
| O4-LAW-3 | [危険物の規制に関する規則 (e-Gov)](https://laws.e-gov.go.jp/) | operational/regulatory detail | public-law reference; verify current version before each batch |
| O4-FDMA-1 | [消防庁](https://www.fdma.go.jp/) | official technical and safety context | supplemental only; source locator required per question |

The inventory was endpoint-checked on 2026-08-25. O4-EXAM-1 is authoritative for the exam profile; laws prevail for substantive legal claims. Source changes require a new source version, not silent question edits.

## Product promise and boundaries

Help learners diagnose and close subject-specific Otsu4 gaps through original, source-traceable practice. The product does not promise a pass, official endorsement, or a collection of past questions.

Factory reuse remains `explicit_v1`, `qualification_runtime_v2`, and `singleFullUnlock`. No shared-architecture change is authorized by this spec.

## Initial bank and coverage decision

The first production target is 300 original accepted questions: 法令 130, 物化 80, 性消 90. Each question has one primary subject, a knowledge target, an authoritative source locator, and collision evidence.

Required early coverage includes: classification/specifed quantities and legal duties; states of matter, combustion, concentration and calculation boundaries; Class 4 properties, flash/ignition points, fire prevention, and suitable extinguishing methods. At least 20 questions in each subject must be calculation or decision-boundary questions before a mock-exam gate may pass.

## Next gate

Adopt an Otsu4 Question Bank contract and coverage taxonomy compatible with `KOMADEKI_AUTONOMOUS_QUESTION_ACCEPTANCE.md`. No production questions may be authored before that gate passes.
