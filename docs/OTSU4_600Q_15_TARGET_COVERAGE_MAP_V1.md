# Otsu4 600Q / 15-Target Coverage Map v1

Status: **ADOPTED FOR COVERAGE PLANNING**
Date: 2026-08-25
Product: 危険物取扱者 乙種第4類
Production target: 600 original accepted questions

## 1. Planning principles

The user-facing learning hierarchy remains three exam subjects, with five focused subtargets under each subject. The target count is a commercial depth plan, not a quota. Question Factory quality gates, source traceability, semantic distinctness, and copyright constraints take precedence over count.

No wording-only duplicate, unsupported variant, or low-value filler may be accepted to satisfy a target allocation. If a target reaches a source-backed semantic ceiling, record a coverage-limit decision and reallocate only after Director review.

## 2. 600-question allocation

### 法令 — 260

| Knowledge target | Target | Primary learning value |
| --- | ---: | --- |
| `O4-LAW-KT-QUANTITY` 指定数量・分類 | 60 | 指定数量、倍数、類別、数量境界の計算・判断 |
| `O4-LAW-KT-LICENSING-DUTIES` 免状・義務 | 50 | 免状、取扱者・立会い、届出・義務、責任主体 |
| `O4-LAW-KT-STORAGE-HANDLING` 貯蔵・取扱い | 60 | 貯蔵・取扱い基準、禁止・許容条件、運用判断 |
| `O4-LAW-KT-FACILITIES-INSPECTION` 施設・検査 | 50 | 製造所等、許可・完成検査・予防規程・点検 |
| `O4-LAW-KT-TRANSPORT` 運搬・移送 | 40 | 運搬、移送、容器・積載・標識等の判断 |

### 基礎的な物理学・化学 — 160

| Knowledge target | Target | Primary learning value |
| --- | ---: | --- |
| `O4-PHY-KT-MATTER-HEAT` 物質・熱 | 30 | 状態変化、密度、熱、温度、蒸気等の基礎 |
| `O4-PHY-KT-COMBUSTION` 燃焼 | 40 | 燃焼条件、燃焼範囲、消火原理、支燃物・熱 |
| `O4-PHY-KT-CONCENTRATION` 濃度 | 30 | 濃度、混合、気体・蒸気、比率判断 |
| `O4-PHY-KT-CHEMICAL-CHANGE` 化学変化 | 30 | 酸化、反応、化学変化と物理変化の区別 |
| `O4-PHY-KT-CALCULATION-BOUNDARY` 計算・判断境界 | 30 | 単位、割合、密度・体積等の計算と誤概念境界 |

### 危険物の性質・火災予防・消火 — 180

| Knowledge target | Target | Primary learning value |
| --- | ---: | --- |
| `O4-FIR-KT-PROPERTIES` 第4類の分類・性質 | 50 | 第4類各品名の性質、分類、共通性・差異 |
| `O4-FIR-KT-FLASH-IGNITION` 引火・発火 | 30 | 引火点、発火点、蒸気、燃焼範囲等の判断 |
| `O4-FIR-KT-HAZARDS-PREVENTION` 危険性・火災予防 | 40 | 静電気、換気、漏えい、混触、火源管理等 |
| `O4-FIR-KT-EXTINGUISHING` 消火適応 | 30 | 消火剤・消火原理・適否・禁忌 |
| `O4-FIR-KT-INCIDENT-DECISION` 事故・状況判断 | 30 | 漏えい・火災・拡散時の優先判断と誤行動回避 |

Total: **600** = Law 260 + Physics/Chemistry 160 + Properties/Fire 180.

## 3. Variation mix

The bank should not be dominated by pure recall. Subject-level planning floor:

- 法令: at least 60 `calculation_decision` questions; remaining mix favors application over recall.
- 物化: at least 50 calculation/decision-boundary questions.
- 性消: at least 50 incident/application/decision-boundary questions.

Every target must ultimately contain materially distinct `recall`, `application`, and/or `calculation_decision` variants where the source proposition supports them. Counts are planning targets, not permission to manufacture variants.

## 4. Source-readiness classification

### Currently structurally sourceable

The five Law targets can be sourced from the registered current e-Gov law/regulation set (`O4-LAW-1`, `O4-LAW-2`, `O4-LAW-3`), but broad authoring still requires precise article/table/paragraph locators per candidate.

### Pinpoint-source catalog required before broad authoring

The five Physics/Chemistry targets and five Properties/Fire targets currently have source registry endpoints but not a sufficiently deep pinned locator catalog for 340 source-traceable questions. `O4-PHY-1` is registered at the MEXT curriculum-explanation level and `O4-FIR-1` at the KHK safety-information level. Broad production authoring must not proceed from homepage/heading-only evidence.

The next gate is therefore to freeze a target-by-target pinpoint source catalog with current authoritative URLs, versions/effective dates, and reproducible locators for all fifteen targets. Existing accepted candidate `O4-B1-LAW-C002` remains valid and may be integrated later; this planning transition does not alter its evidence.

## 5. Batch strategy after source freeze

Author in source-coherent batches of approximately 20–30 candidates. Each batch goes through independent AI review, Director adjudication, content-bound acceptance packets, deterministic Permanent ID allocation, canonical integration, and source verification. Batch size improves throughput; no quality gate is skipped.
