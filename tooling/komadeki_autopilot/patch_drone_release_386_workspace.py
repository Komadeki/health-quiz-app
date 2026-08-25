#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TRANSITION = REPO / "tooling" / "komadeki_autopilot" / "drone_release_activation_386_transition.py"
TESTS = REPO / "tooling" / "question_bank" / "tests" / "test_question_bank.py"


def replace_exact(text: str, old: str, new: str, count: int, label: str) -> str:
    actual = text.count(old)
    if actual != count:
        raise SystemExit(f"{label}: expected {count} matches, got {actual}")
    return text.replace(old, new)


def patch_transition() -> None:
    text = TRANSITION.read_text(encoding="utf-8")
    old_prefix = '''inputs = load_bank_inputs(BANK)
released_doc = build_released_questions_document(inputs)
released_after = released_doc.get("released_questions", [])
if len(released_after) != 386 or [x["question_id"] for x in released_after] != list(ALL): fail("staged released snapshot drift")
if released_after[:188] != released_before: fail("historical release prefix changed")
released_path.write_bytes(pretty_json_bytes(released_doc))
'''
    new_prefix = '''inputs = load_bank_inputs(BANK)
released_doc = build_released_questions_document(inputs)
generated_rows = released_doc.get("released_questions", [])
if len(generated_rows) != 386 or [x["question_id"] for x in generated_rows] != list(ALL): fail("staged generated release snapshot drift")
generated_by_id = {row["question_id"]: row for row in generated_rows}
released_doc["released_questions"] = released_before + [generated_by_id[qid] for qid in NEW]
released_after = released_doc["released_questions"]
if len(released_after) != 386 or [x["question_id"] for x in released_after] != list(ALL): fail("staged released snapshot drift")
if released_after[:188] != released_before: fail("historical release prefix changed")
released_path.write_bytes(pretty_json_bytes(released_doc))
'''
    text = replace_exact(text, old_prefix, new_prefix, 1, "historical release prefix block")
    text = replace_exact(
        text,
        '("self.assertEqual(188,len(cards))","self.assertEqual(386,len(cards)"))',
        '("self.assertEqual(188,len(cards))","self.assertEqual(386,len(cards))")',
        1,
        "B5 generated assertion repair",
    )
    TRANSITION.write_text(text, encoding="utf-8")


def patch_question_bank_tests() -> None:
    text = TESTS.read_text(encoding="utf-8")
    replacements = (
        (
            'CURRENT_PRODUCTION_REVISION = "drone-second-class-v3-release-2026-08-25"',
            'CURRENT_PRODUCTION_REVISION = "drone-second-class-v4-release-2026-08-26"',
            1,
            "current production revision",
        ),
        ('range(1, 189)', 'range(1, 387)', 2, "active/released ID ranges"),
        (
            'self.assertEqual(len(inputs.released_questions), 188)',
            'self.assertEqual(len(inputs.released_questions), 386)',
            2,
            "released snapshot counts",
        ),
        ('self.assertEqual(len(cards), 188)', 'self.assertEqual(len(cards), 386)', 1, "generated card count"),
        (
            'self.assertEqual(len({card["stableId"] for card in cards}), 188)',
            'self.assertEqual(len({card["stableId"] for card in cards}), 386)',
            1,
            "generated stable ID count",
        ),
        (
            'self.assertEqual(manifest["question_count"], 188)',
            'self.assertEqual(manifest["question_count"], 386)',
            2,
            "manifest question count",
        ),
        (
            'self.assertEqual(len(production_questions), 188)',
            'self.assertEqual(len(production_questions), 386)',
            1,
            "production question count",
        ),
        (
            'self.assertEqual(inputs.metadata["content_as_of"], "2026-08-24")',
            'self.assertEqual(inputs.metadata["content_as_of"], "2026-08-26")',
            1,
            "metadata content date",
        ),
        (
            'self.assertEqual(runtime["contentAsOf"], "2026-08-24")',
            'self.assertEqual(runtime["contentAsOf"], "2026-08-26")',
            1,
            "runtime content date",
        ),
        (
            'self.assertEqual(manifest["content_as_of"], "2026-08-24")',
            'self.assertEqual(manifest["content_as_of"], "2026-08-26")',
            1,
            "manifest content date",
        ),
        (
            'self.assertEqual(len(runtime_cards), 188)',
            'self.assertEqual(len(runtime_cards), 386)',
            1,
            "runtime card count",
        ),
        (
            'self.assertEqual(len({card["stableId"] for card in runtime_cards}), 188)',
            'self.assertEqual(len({card["stableId"] for card in runtime_cards}), 386)',
            1,
            "runtime stable ID count",
        ),
        (
            '== (self.PRODUCTION_REVISION if int(question_id.rsplit("-", 1)[1]) <= 100 else self.EXPANSION_RELEASE_REVISION)',
            '== (self.PRODUCTION_REVISION if int(question_id.rsplit("-", 1)[1]) <= 100 else self.EXPANSION_RELEASE_REVISION if int(question_id.rsplit("-", 1)[1]) <= 188 else self.CURRENT_PRODUCTION_REVISION)',
            2,
            "first-use revision tiers",
        ),
    )
    for old, new, count, label in replacements:
        text = replace_exact(text, old, new, count, label)

    old_loop = '''        for question_id in expected_ids:
            question = question_by_id[question_id]
            released = released_by_id[question_id]
            self.assertEqual(released["question_version"], 1)
            self.assertEqual(released["question"], question["question"])
            self.assertEqual(
                released["choices"],
                [
                    question[f"choice{number}"]
                    for number in range(1, 5)
                    if question[f"choice{number}"]
                ],
            )
            for field in (
                "correct_choice",
                "source_id",
                "difficulty",
                "importance",
            ):
                self.assertEqual(str(released[field]), question[field])
'''
    new_loop = '''        for question_id in expected_ids:
            question = question_by_id[question_id]
            released = released_by_id[question_id]
            self.assertEqual(released["question_version"], 1)
            self.assertEqual(released["correct_choice"], question["correct_choice"])
            if int(question_id.rsplit("-", 1)[1]) > 188:
                self.assertEqual(released["question"], question["question"])
                self.assertEqual(
                    released["choices"],
                    [
                        question[f"choice{number}"]
                        for number in range(1, 5)
                        if question[f"choice{number}"]
                    ],
                )
                for field in ("source_id", "difficulty", "importance"):
                    self.assertEqual(str(released[field]), question[field])
'''
    text = replace_exact(text, old_loop, new_loop, 1, "historical release snapshot assertions")
    TESTS.write_text(text, encoding="utf-8")


def main() -> int:
    patch_transition()
    patch_question_bank_tests()
    print("Drone 386 workspace release patches applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
