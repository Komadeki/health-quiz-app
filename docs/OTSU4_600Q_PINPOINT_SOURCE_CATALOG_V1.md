# Otsu4 600Q Pinpoint Source Catalog v1

Status: **FROZEN FOR PRODUCTION AUTHORING**
Verified: 2026-08-25
Product: 危険物取扱者 乙種第4類

## 1. Source rule

Every production candidate must bind to a registered `source_id`, the exact registered `source_version`, and a locator that a separate reviewer can reproduce without relying on Chat context.

Homepage-only or heading-only locators are insufficient for production acceptance. The author must point to an article/paragraph/table, printed PDF page/section, named web subsection, or SDS section/field.

Published questions from the exam authority remain prohibited as commercial Question Bank source text. All questions, choices, and explanations are independently authored.

## 2. Legal authority — O4-LAW targets

Current legal propositions are sourced only from e-Gov. If a non-legal source disagrees with current law, e-Gov controls.

### `O4-LAW-1` 消防法

Exact law URL: `https://laws.e-gov.go.jp/law/323AC0000000186`

Locator form: `消防法 第X条第Y項第Z号` or `消防法 別表第一 第四類 ...`.

Primary use:
- classification/statutory definitions;
- licensing and statutory duties;
- permission / regulatory responsibility concepts;
- transport / transfer statutory duties where the Act supplies the proposition.

### `O4-LAW-2` 危険物の規制に関する政令

Exact law URL: `https://laws.e-gov.go.jp/law/334CO0000000306`

Locator form: `危険物の規制に関する政令 第X条第Y項` or `別表第三 第四類 ...`.

Primary use:
- specified quantities and multiples;
- facility categories and technical standards;
- common storage/handling technical standards;
- transport/transfer technical standards.

`O4-B1-LAW-C002` remains bound to the already-reviewed `O4-LAW-2 / 2026-08-25 / 別表第三・第4類` snapshot.

### `O4-LAW-3` 危険物の規制に関する規則

Exact law URL: `https://laws.e-gov.go.jp/law/334M50000002055`

Current catalog anchors:
- Chapter 1, Articles 1–3: definitions / names;
- Chapter 2, Articles 4–9-2: permission/completion-inspection applications;
- Chapter 5, Articles 38-4–40-14: storage and handling;
- Chapter 6, Articles 41–47-3: transport and transfer;
- Chapter 7, Articles 48–58-15: hazardous-material safety supervisors / handlers;
- Chapter 9, Articles 60-2–62: preventive regulations;
- Chapter 9-2, Articles 62-2–62-8: safety inspections etc.

Candidate locator must narrow these chapter anchors to the exact article/paragraph/field used.

## 3. Physics / Chemistry — O4-PHY targets

### `O4-PHY-1` MEXT High School Curriculum Commentary, Science / Science and Mathematics

Direct official PDF:
`https://www.mext.go.jp/content/20230626-mxt_kyoikujinzai02-000033064_06.pdf`

Permitted pinpoint ranges:
- `物理基礎`, printed pp.48–60: basic physical concepts including heat/energy where the proposition is explicitly supported;
- `化学基礎`, printed pp.85–95: matter composition/change and quantitative chemistry;
- `化学基礎`, printed p.91 onward, `物質量と化学反応式`: amount of substance, mass, gas volume, molar concentration, quantitative reaction relationships;
- `化学基礎`, following pages on acids/bases and `酸化と還元`: chemical-change and oxidation/reduction propositions.

Locator form: `MEXT 理科編 第2章 第4節 化学基礎 p.<printed page>「<subheading>」` or the corresponding `物理基礎` printed-page locator.

Allowed target families:
- `O4-PHY-KT-MATTER-HEAT`
- `O4-PHY-KT-CONCENTRATION`
- `O4-PHY-KT-CHEMICAL-CHANGE`
- `O4-PHY-KT-CALCULATION-BOUNDARY`

### `O4-FDMA-COMBUSTION-1` Fire and Disaster Management Research Institute — ものはなぜ燃えるのか

Official URL:
`https://nrifd.fdma.go.jp/public_info/faq/combustion/`

Permitted locators:
- `火の三角形`
- `燃焼の3要素`
- `着火源`
- `なぜ燃え続けるのか？ ～連鎖反応と連鎖担体～`

Allowed target:
- `O4-PHY-KT-COMBUSTION`

This source supports the roles of combustible material, supporter/oxygen, heat/ignition energy, and combustion-chain concepts. Candidate wording must stay within the proposition actually stated by the selected subsection.

## 4. Properties / prevention / extinguishing — O4-FIR targets

### Current-law classification rule

Class-4 legal classification, specified quantity, and legal duty always bind to `O4-LAW-*`, not to an SDS. Model SDS legal-information sections can be stale and must not define current Fire Service Act classification.

### MHLW model SDS source set

Registered production source IDs include:
- `O4-MHLW-SDS-GASOLINE`
- `O4-MHLW-SDS-KEROSENE`
- `O4-MHLW-SDS-ACETONE`
- `O4-MHLW-SDS-ETHANOL`
- `O4-MHLW-SDS-METHANOL`
- `O4-MHLW-SDS-XYLENE`
- `O4-MHLW-SDS-BENZENE`
- `O4-MHLW-SDS-TOLUENE`
- `O4-MHLW-SDS-ETHYL-ACETATE`
- `O4-MHLW-SDS-CRESOL`
- `O4-MHLW-LABEL-DIETHYL-ETHER`

For model SDS pages, locator form is `MHLW model SDS <chemical>, Section N「<field>」` and must identify the field used.

Permitted section uses:
- Section 2: physical-chemical hazard / prevention statements;
- Section 5: suitable/unsuitable extinguishing media and fire-specific response;
- Section 6: accidental-release response where present;
- Section 7: handling/storage precautions where present;
- Section 9: physical/chemical properties such as flash point, autoignition temperature, explosion range, vapor density and density;
- Section 10: stability/reactivity and incompatible materials where present.

Do not source current legal classification from Section 15. Do not generalize a product-specific or missing value beyond the exact model SDS proposition.

Allowed target families:
- `O4-FIR-KT-PROPERTIES`
- `O4-FIR-KT-FLASH-IGNITION`
- `O4-FIR-KT-HAZARDS-PREVENTION`
- `O4-FIR-KT-EXTINGUISHING`
- `O4-FIR-KT-INCIDENT-DECISION`

### `O4-FDMA-STATIC-1`

Official URL:
`https://www.fdma.go.jp/laws/tutatsu/post1258/`

Permitted locators:
- notice body describing gasoline-vapor ignition and static-electricity risk;
- revised safety-display requirements;
- `別紙1 セルフスタンド用注意書き文案`.

Primary target:
- `O4-FIR-KT-HAZARDS-PREVENTION`

### `O4-FDMA-INCIDENT-1`

Official URL:
`https://www.fdma.go.jp/laws/tutatsu/post1964/`

Permitted locators must identify the named facility/incident subsection, for example:
- chemical-factory/general-handling-place static-electricity ignition scenarios;
- leak/ignition scenarios;
- ventilation, cleaning, grounding, fire-source management and equipment-failure prevention points.

Primary targets:
- `O4-FIR-KT-HAZARDS-PREVENTION`
- `O4-FIR-KT-INCIDENT-DECISION`

### `O4-FDMA-SAFETY-1`

This is an official navigation/source-discovery hub. It may support a candidate only when the cited proposition appears on the page itself; otherwise the candidate must register and cite the downstream official document. It cannot substitute for a pinpoint locator.

### `O4-FIR-1` KHK

Retained for compatibility with the existing Batch-1 draft evidence. The KHK top page is not sufficient by itself for new broad production acceptance. New KHK-derived candidates require a reproducible public downstream page registered as a separate source or another already-registered authoritative source.

## 5. Target-to-source readiness

| Target | Primary source path | Production readiness |
| --- | --- | --- |
| LAW quantity/classification | e-Gov Act/Decree/Rule | READY |
| LAW licensing/duties | e-Gov Act/Rule Ch.7 | READY |
| LAW storage/handling | e-Gov Act/Decree/Rule Ch.5 | READY |
| LAW facilities/inspection | e-Gov Act/Decree/Rule Ch.2/9/9-2 | READY |
| LAW transport/transfer | e-Gov Act/Decree/Rule Ch.6 | READY |
| PHY matter/heat | MEXT Physics Basics/Chemistry Basics pinpoint pages | READY |
| PHY combustion | FDMA Research Institute combustion page + MEXT where applicable | READY |
| PHY concentration | MEXT Chemistry Basics quantitative-chemistry pages | READY |
| PHY chemical change | MEXT Chemistry Basics chemical-change / redox pages | READY |
| PHY calculation boundary | MEXT quantitative-chemistry pages; source-defined calculations only | READY |
| FIR properties | e-Gov for legal class + MHLW SDS Sections 2/9 | READY |
| FIR flash/ignition | MHLW SDS Section 9 | READY |
| FIR hazards/prevention | FDMA + MHLW SDS Sections 2/7/10 | READY |
| FIR extinguishing | MHLW SDS Section 5 | READY |
| FIR incident decision | FDMA incident guidance + MHLW SDS Sections 5/6/7 | READY |

## 6. Fail-closed authoring rule

This catalog establishes source paths, not permission to invent 600 distinct propositions. Each batch must first enumerate source-defined propositions and collision-check them against all canonical questions. When materially distinct source-backed propositions are exhausted, stop that target and record a coverage-limit decision rather than backfilling to the planned count.
