from __future__ import annotations

import csv
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


TOOL_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(TOOL_DIR))

from question_bank import (  # noqa: E402
    build_generated_files,
    load_bank_inputs,
    validate_bank,
    write_generated_files,
)
from contract import QUESTION_ID_PATTERN  # noqa: E402


class QuestionBankContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        source = REPOSITORY_ROOT / "question_banks" / "qualification_fixture"
        self.bank = Path(self.temporary_directory.name) / "qualification_fixture"
        shutil.copytree(source, self.bank)

    @property
    def questions_path(self) -> Path:
        return self.bank / "authoring" / "questions.csv"

    def _mutate_question(self, index: int, **changes: str) -> None:
        with self.questions_path.open(newline="", encoding="utf-8") as file:
            reader = csv.DictReader(file)
            fieldnames = list(reader.fieldnames or [])
            rows = list(reader)
        rows[index].update(changes)
        with self.questions_path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def _error_codes(self) -> set[str]:
        return {issue.code for issue in validate_bank(self.bank).errors}

    def test_valid_fixture_generates_and_decodes_expected_contract(self) -> None:
        result = validate_bank(self.bank)
        self.assertTrue(result.is_valid, [str(issue) for issue in result.issues])

        written = list(write_generated_files(self.bank))
        self.assertEqual(len(written), 2)
        checked = validate_bank(self.bank, check_generated=True)
        self.assertTrue(checked.is_valid, [str(issue) for issue in checked.issues])

        runtime = json.loads(
            (self.bank / "generated" / "qualification_fixture_bank.json")
            .read_text(encoding="utf-8")
        )
        all_cards = [
            card
            for deck in runtime["decks"]
            for unit in deck["units"]
            for card in unit["cards"]
        ]
        three_choice = next(
            card for card in all_cards if card["stableId"] == "FIXTURE-Q-000001"
        )
        self.assertEqual(three_choice["questionVersion"], 1)
        self.assertEqual(three_choice["answerIndex"], 0)
        self.assertEqual(len(three_choice["choices"]), 3)
        self.assertEqual(len(all_cards), 2)
        self.assertEqual({card["isPremium"] for card in all_cards}, {True, False})

    def test_generation_is_deterministic(self) -> None:
        inputs = load_bank_inputs(self.bank)
        first = build_generated_files(inputs)
        second = build_generated_files(load_bank_inputs(self.bank))
        self.assertEqual(first, second)

    def test_duplicate_question_id_fails(self) -> None:
        self._mutate_question(1, question_id="FIXTURE-Q-000001")
        self.assertIn("duplicate_question_id", self._error_codes())

    def test_retired_question_id_reuse_fails(self) -> None:
        self._mutate_question(
            2,
            status="active",
            last_reviewed_at="2026-08-01",
            valid_until="2027-01-01",
        )
        self.assertIn("retired_id_reuse", self._error_codes())

    def test_invalid_correct_choice_fails(self) -> None:
        self._mutate_question(0, correct_choice="D")
        self.assertIn("invalid_correct_choice", self._error_codes())

    def test_missing_source_fails(self) -> None:
        self._mutate_question(0, source_id="MISSING-SOURCE")
        self.assertIn("unresolved_source_id", self._error_codes())

    def test_missing_explicit_id_fails_without_hash_fallback(self) -> None:
        self._mutate_question(0, question_id="")
        codes = self._error_codes()
        self.assertIn("missing_question_id", codes)
        self.assertIn("explicit_identity_missing_id", codes)

    def test_active_question_requires_last_reviewed_at(self) -> None:
        self._mutate_question(0, last_reviewed_at="")
        self.assertIn("active_missing_last_reviewed_at", self._error_codes())

    def test_expired_active_question_fails_against_content_as_of(self) -> None:
        self._mutate_question(0, valid_until="2026-08-16")
        self.assertIn("expired_active_question", self._error_codes())

    def test_future_valid_from_active_question_fails(self) -> None:
        self._mutate_question(0, valid_from="2026-10-01")
        self.assertIn("active_question_not_yet_valid", self._error_codes())

    def test_generated_drift_fails(self) -> None:
        write_generated_files(self.bank)
        generated = self.bank / "generated" / "qualification_fixture_bank.json"
        generated.write_text("{}\n", encoding="utf-8")
        codes = {
            issue.code
            for issue in validate_bank(self.bank, check_generated=True).errors
        }
        self.assertIn("generated_json_drift", codes)

    def test_manifest_count_mismatch_fails(self) -> None:
        write_generated_files(self.bank)
        manifest_path = self.bank / "generated" / "bank_manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["question_count"] = 99
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        codes = {
            issue.code
            for issue in validate_bank(self.bank, check_generated=True).errors
        }
        self.assertIn("bank_manifest_count_mismatch", codes)

    def test_released_correct_choice_change_fails(self) -> None:
        self._mutate_question(1, correct_choice="A", question_version="3")
        self.assertIn("released_correct_choice_changed", self._error_codes())

    def test_released_choice_text_change_warns_without_version_increment(self) -> None:
        self._mutate_question(1, choice2="所定の電子様式に残す")
        result = validate_bank(self.bank)
        warning_codes = {issue.code for issue in result.warnings}
        error_codes = {issue.code for issue in result.errors}

        self.assertIn("released_choices_changed", warning_codes)
        self.assertIn("question_version_not_incremented", warning_codes)
        self.assertNotIn("released_correct_choice_changed", error_codes)

    def test_released_metadata_change_warns(self) -> None:
        self._mutate_question(0, difficulty="2")
        warnings = {issue.code for issue in validate_bank(self.bank).warnings}
        self.assertIn("difficulty_changed", warnings)
        self.assertIn("question_version_not_incremented", warnings)


class DroneQuestionBankTest(unittest.TestCase):
    PERMANENT_SLOT_TO_ID = {
        "VS-001": "DRONE-Q-000001",
        "VS-004": "DRONE-Q-000002",
        "VS-027": "DRONE-Q-000003",
        "VS-039": "DRONE-Q-000004",
        "VS-069": "DRONE-Q-000005",
        "VS-002": "DRONE-Q-000006",
        "VS-003": "DRONE-Q-000007",
        "VS-015": "DRONE-Q-000008",
        "VS-021": "DRONE-Q-000009",
        "VS-022": "DRONE-Q-000010",
        "VS-005": "DRONE-Q-000011",
        "VS-006": "DRONE-Q-000012",
        "VS-016": "DRONE-Q-000013",
        "VS-007": "DRONE-Q-000014",
        "VS-008": "DRONE-Q-000015",
        "VS-009": "DRONE-Q-000016",
        "VS-017": "DRONE-Q-000017",
        "VS-010": "DRONE-Q-000018",
        "VS-011": "DRONE-Q-000019",
        "VS-018": "DRONE-Q-000020",
        "VS-019": "DRONE-Q-000021",
        "VS-012": "DRONE-Q-000022",
        "VS-013": "DRONE-Q-000023",
        "VS-014": "DRONE-Q-000024",
        "VS-020": "DRONE-Q-000025",
        "VS-023": "DRONE-Q-000026",
        "VS-030": "DRONE-Q-000027",
        "VS-024": "DRONE-Q-000028",
        "VS-031": "DRONE-Q-000029",
        "VS-025": "DRONE-Q-000030",
        "VS-032": "DRONE-Q-000031",
        "VS-026": "DRONE-Q-000032",
        "VS-033": "DRONE-Q-000033",
        "VS-034": "DRONE-Q-000034",
        "VS-028": "DRONE-Q-000035",
        "VS-035": "DRONE-Q-000036",
        "VS-029": "DRONE-Q-000037",
        "VS-036": "DRONE-Q-000038",
        "VS-041": "DRONE-Q-000039",
        "VS-042": "DRONE-Q-000040",
        "VS-037": "DRONE-Q-000041",
        "VS-038": "DRONE-Q-000042",
        "VS-040": "DRONE-Q-000043",
        "VS-043": "DRONE-Q-000044",
        "VS-044": "DRONE-Q-000045",
        "VS-045": "DRONE-Q-000046",
        "VS-046": "DRONE-Q-000047",
        "VS-047": "DRONE-Q-000048",
        "VS-048": "DRONE-Q-000049",
        "VS-049": "DRONE-Q-000050",
        "VS-050": "DRONE-Q-000051",
        "VS-051": "DRONE-Q-000052",
        "VS-052": "DRONE-Q-000053",
        "VS-053": "DRONE-Q-000054",
        "VS-054": "DRONE-Q-000055",
        "VS-055": "DRONE-Q-000056",
        "VS-056": "DRONE-Q-000057",
        "VS-057": "DRONE-Q-000058",
        "VS-058": "DRONE-Q-000059",
        "VS-059": "DRONE-Q-000060",
        "VS-060": "DRONE-Q-000061",
        "VS-061": "DRONE-Q-000062",
        "VS-062": "DRONE-Q-000063",
        "VS-063": "DRONE-Q-000064",
        "VS-064": "DRONE-Q-000065",
        "VS-065": "DRONE-Q-000066",
        "VS-066": "DRONE-Q-000067",
        "VS-067": "DRONE-Q-000068",
        "VS-068": "DRONE-Q-000069",
        "VS-070": "DRONE-Q-000070",
        "VS-071": "DRONE-Q-000071",
        "VS-072": "DRONE-Q-000072",
        "VS-073": "DRONE-Q-000073",
        "VS-074": "DRONE-Q-000074",
        "VS-075": "DRONE-Q-000075",
        "VS-076": "DRONE-Q-000076",
        "VS-077": "DRONE-Q-000077",
        "VS-078": "DRONE-Q-000078",
        "VS-079": "DRONE-Q-000079",
        "VS-080": "DRONE-Q-000080",
        "VS-081": "DRONE-Q-000081",
        "VS-082": "DRONE-Q-000082",
        "VS-083": "DRONE-Q-000083",
        "VS-084": "DRONE-Q-000084",
        "VS-085": "DRONE-Q-000085",
        "VS-086": "DRONE-Q-000086",
        "VS-087": "DRONE-Q-000087",
        "VS-088": "DRONE-Q-000088",
        "VS-089": "DRONE-Q-000089",
    }
    B3A_EXPECTATIONS = {
        "DRONE-Q-000039": {
            "unit_id": "drone_operations",
            "slot_id": "VS-041",
            "primary_role": "UNKNOWN_SENTINEL",
            "kt_id": "D3-T01-KT004",
            "family": "US-E",
            "notes_internal": (
                "slot_id=VS-041; verification_state=author_source_verified; "
                "primary_role=UNKNOWN_SENTINEL; kt_id=D3-T01-KT004; "
                "family=US-E; independent_reviewed=false; "
                "subject_matter_expert_reviewed=false; release_approved=false"
            ),
            "content": {
                "question": (
                    "当日の運航が終了したあとに行う「運航終了後の点検」の項目として、"
                    "教則に例示されているものはどれか。"
                ),
                "choice1": "機体・バッテリー等の安全な保管状態の確認",
                "choice2": "機体へのゴミ等の付着の確認",
                "choice3": "各機器の異常な発熱の確認",
                "correct_choice": "A",
                "explanation": (
                    "教則では、運航終了後の点検として、機体やバッテリー等を安全な"
                    "状態で適切な場所に保管したかを確認する例を示している。\n"
                    "BとCは、各飛行後に行う「飛行後の点検」の項目である。教則の表"
                    "でも、ゴミ等の付着と異常な発熱は「飛行後の点検」、安全な保管は"
                    "「運航終了後の点検」と明確に分けられている。"
                ),
                "source_locator": (
                    "教則 第5章 5.1「運航時の点検及び確認事項」(1)4)・5) / (2)"
                    "（教則表示ページ53–54 / PDF viewer 59–60）"
                ),
            },
        },
        "DRONE-Q-000040": {
            "unit_id": "drone_operations",
            "slot_id": "VS-042",
            "primary_role": "UNKNOWN_SENTINEL",
            "kt_id": "D3-T03-KT002",
            "family": "US-F",
            "notes_internal": (
                "slot_id=VS-042; verification_state=author_source_verified; "
                "primary_role=UNKNOWN_SENTINEL; kt_id=D3-T03-KT002; "
                "family=US-F; independent_reviewed=false; "
                "subject_matter_expert_reviewed=false; release_approved=false"
            ),
            "content": {
                "question": (
                    "前夜に飲酒した操縦者が、翌日に無人航空機を操縦する予定である。\n"
                    "教則の注意として最も適切なものはどれか。"
                ),
                "choice1": (
                    "前夜の飲酒から翌日の操縦時までに十分な時間が経過しているかを、"
                    "影響判断の主な基準とする"
                ),
                "choice2": (
                    "前夜の飲酒でも翌日の操縦時まで影響が残る可能性があることに"
                    "注意する"
                ),
                "choice3": (
                    "前夜の飲酒量と翌日の本人の体調を、影響判断の主な基準とする"
                ),
                "correct_choice": "B",
                "explanation": (
                    "教則は、前夜に飲酒した場合でも、翌日の操縦時までアルコールの"
                    "影響を受けている可能性があることへの注意を求めている。\n"
                    "また、アルコール検知器を活用することも有用としている。"
                ),
                "source_locator": (
                    "教則 第5章 5.3.2（教則表示ページ61 / PDF viewer 67）"
                ),
            },
        },
    }
    B3A_REGISTRY_NOTES = {
        "DRONE-Q-000039": (
            "VS-041; B3A US-E clean sentinel; UNKNOWN_SENTINEL; permanent ID; "
            "pre-release"
        ),
        "DRONE-Q-000040": (
            "VS-042; B3A US-F clean sentinel; UNKNOWN_SENTINEL; permanent ID; "
            "pre-release"
        ),
    }
    B3B_EXPECTATIONS = {
        "DRONE-Q-000041": {
            "unit_id": "drone_rules",
            "slot_id": "VS-037",
            "primary_role": "UNKNOWN_SENTINEL",
            "kt_id": "D1-T01-KT020",
            "family": "US-A",
            "notes_internal": (
                "slot_id=VS-037; verification_state=author_source_verified; "
                "primary_role=UNKNOWN_SENTINEL; kt_id=D1-T01-KT020; "
                "family=US-A; independent_reviewed=false; "
                "subject_matter_expert_reviewed=false; release_approved=false"
            ),
            "content": {
                "question": (
                    "重量90gの遠隔操作可能な機体は、航空法上「模型航空機」に"
                    "分類されるものとする。\nある空域が緊急用務空域に指定されて"
                    "いる場合、この模型航空機の扱いとして、教則に最も合うものは"
                    "どれか。"
                ),
                "choice1": (
                    "100g未満の模型航空機なので、緊急用務空域の飛行禁止対象には"
                    "ならない"
                ),
                "choice2": (
                    "100g未満の模型航空機も、緊急用務空域の飛行禁止対象となる"
                ),
                "choice3": (
                    "100g未満では、無人航空機として登録されている場合に限り"
                    "飛行禁止対象となる"
                ),
                "correct_choice": "B",
                "explanation": (
                    "教則では、100g未満で航空法上「模型航空機」に分類される機体"
                    "であっても、緊急用務空域の飛行禁止の対象となるとしている。"
                ),
                "source_locator": (
                    "教則 第3章 3.1.2(2)1)b"
                    "（教則表示ページ15 / PDF viewer 21）"
                ),
            },
        },
        "DRONE-Q-000042": {
            "unit_id": "drone_rules",
            "slot_id": "VS-038",
            "primary_role": "UNKNOWN_SENTINEL",
            "kt_id": "D1-T01-KT029",
            "family": "US-B",
            "notes_internal": (
                "slot_id=VS-038; verification_state=author_source_verified; "
                "primary_role=UNKNOWN_SENTINEL; kt_id=D1-T01-KT029; "
                "family=US-B; independent_reviewed=false; "
                "subject_matter_expert_reviewed=false; release_approved=false"
            ),
            "content": {
                "question": (
                    "特定飛行を行った場合、教則が「遅滞なく飛行日誌に記載する」"
                    "としている記録の組合せはどれか。"
                ),
                "choice1": "飛行記録・日常点検記録・点検整備記録",
                "choice2": "飛行記録・飛行計画記録・事故報告記録",
                "choice3": "日常点検記録・飛行計画記録・事故報告記録",
                "correct_choice": "A",
                "explanation": (
                    "教則では、特定飛行を行った場合、飛行記録、日常点検記録"
                    "および点検整備記録を遅滞なく飛行日誌へ記載することとして"
                    "いる。"
                ),
                "source_locator": (
                    "教則 第2章 2.2.10(3)"
                    "（教則表示ページ6 / PDF viewer 12）"
                ),
            },
        },
        "DRONE-Q-000043": {
            "unit_id": "drone_systems",
            "slot_id": "VS-040",
            "primary_role": "UNKNOWN_SENTINEL",
            "kt_id": "D2-T05-KT008",
            "family": "US-D",
            "notes_internal": (
                "slot_id=VS-040; verification_state=author_source_verified; "
                "primary_role=UNKNOWN_SENTINEL; kt_id=D2-T05-KT008; "
                "family=US-D; independent_reviewed=false; "
                "subject_matter_expert_reviewed=false; release_approved=false"
            ),
            "content": {
                "question": (
                    "無人航空機の磁気キャリブレーションについて、教則の説明に"
                    "最も合うものはどれか。"
                ),
                "choice1": (
                    "飛行場所の地磁気を検出して方位を取得し、その情報をGNSS機能"
                    "やメインコントローラーに認識させる"
                ),
                "choice2": (
                    "周囲の鉄材や電流による磁気干渉の強さを測定し、その強さを"
                    "GNSS機能やメインコントローラーに認識させる"
                ),
                "choice3": (
                    "磁北と地図上の北との差である偏角そのものを測定し、その値を"
                    "GNSS機能やメインコントローラーに認識させる"
                ),
                "correct_choice": "A",
                "explanation": (
                    "教則では、無人航空機の磁気キャリブレーションとは、飛行前に"
                    "その場所の地磁気を検出して方位を取得し、GNSS機能やメイン"
                    "コントローラーに認識させることとしている。"
                ),
                "source_locator": (
                    "教則 第4章 4.5.2(3)「無人航空機の磁気キャリブレーション」"
                    "（教則表示ページ49 / PDF viewer 55）"
                ),
            },
        },
        "DRONE-Q-000044": {
            "unit_id": "drone_risk_management",
            "slot_id": "VS-043",
            "primary_role": "UNKNOWN_SENTINEL",
            "kt_id": "D4-T01-KT004",
            "family": "US-G",
            "notes_internal": (
                "slot_id=VS-043; verification_state=author_source_verified; "
                "primary_role=UNKNOWN_SENTINEL; kt_id=D4-T01-KT004; "
                "family=US-G; independent_reviewed=false; "
                "subject_matter_expert_reviewed=false; release_approved=false"
            ),
            "content": {
                "question": (
                    "飛行計画を立てている。着陸予定地点に着陸できなくなった場合、"
                    "離陸地点まで戻るだけの飛行可能距離も確保できないリスクが"
                    "ある。\nこのリスクへの事前の備えとして、教則に最も合うものは"
                    "どれか。"
                ),
                "choice1": (
                    "飛行領域に安全上の範囲を加え、第三者の立入管理を行う"
                ),
                "choice2": "別途、事前に緊急着陸地点を確保しておく",
                "choice3": (
                    "ジオフェンス機能を利用し、飛行禁止空域への逸脱を防止する"
                ),
                "correct_choice": "B",
                "explanation": (
                    "教則では、予定していた着陸地点に着陸できず、離陸地点まで"
                    "戻る飛行可能距離も確保できない場合に備え、事前に緊急着陸"
                    "地点を確保しておくことを示している。"
                ),
                "source_locator": (
                    "教則 第6章 6.1.2(1)"
                    "（教則表示ページ64 / PDF viewer 70）"
                ),
            },
        },
        "DRONE-Q-000045": {
            "unit_id": "drone_risk_management",
            "slot_id": "VS-044",
            "primary_role": "UNKNOWN_SENTINEL",
            "kt_id": "D4-T02-KT006",
            "family": "US-H",
            "notes_internal": (
                "slot_id=VS-044; verification_state=author_source_verified; "
                "primary_role=UNKNOWN_SENTINEL; kt_id=D4-T02-KT006; "
                "family=US-H; independent_reviewed=false; "
                "subject_matter_expert_reviewed=false; release_approved=false"
            ),
            "content": {
                "question": (
                    "低温環境で無人航空機を飛行させる場合、教則が特に注意を"
                    "求めている影響として最も適切なものはどれか。"
                ),
                "choice1": (
                    "バッテリーの持続時間、すなわち飛行可能時間が普段より短く"
                    "なる可能性がある"
                ),
                "choice2": (
                    "地表面が暖められることで上昇気流が発生する可能性がある"
                ),
                "choice3": (
                    "高層建物群の配置によって周囲より速いビル風が継続する可能性"
                    "がある"
                ),
                "correct_choice": "A",
                "explanation": (
                    "教則では、低温環境ではバッテリーの持続時間が短くなり、"
                    "飛行可能時間が普段より短くなる可能性があることに注意を"
                    "求めている。"
                ),
                "source_locator": (
                    "教則 第6章 6.2.2(2)"
                    "（教則表示ページ73 / PDF viewer 79）"
                ),
            },
        },
    }
    B3B_REGISTRY_NOTES = {
        "DRONE-Q-000041": (
            "VS-037; B3B US-A routed sentinel; UNKNOWN_SENTINEL; permanent ID; "
            "pre-release"
        ),
        "DRONE-Q-000042": (
            "VS-038; B3B US-B routed sentinel; UNKNOWN_SENTINEL; permanent ID; "
            "pre-release"
        ),
        "DRONE-Q-000043": (
            "VS-040; B3B US-D routed sentinel; UNKNOWN_SENTINEL; permanent ID; "
            "pre-release"
        ),
        "DRONE-Q-000044": (
            "VS-043; B3B US-G routed sentinel; UNKNOWN_SENTINEL; permanent ID; "
            "pre-release"
        ),
        "DRONE-Q-000045": (
            "VS-044; B3B US-H routed sentinel; UNKNOWN_SENTINEL; permanent ID; "
            "pre-release"
        ),
    }
    B4_D1_EXPECTATIONS = {
        "DRONE-Q-000046": {
            "slot_id": "VS-045",
            "kt_id": "D1-T01-KT001",
            "coverage": "COV-01",
            "question": (
                "遠隔操作が可能で、構造上人が乗ることができない機体がある。\n\n"
                "重量は次のとおりである。\n\n"
                "* 機体本体：75g\n"
                "* バッテリー：30g\n"
                "* 取り外し可能なカメラ：20g\n\n"
                "航空法上の無人航空機の重量判定と分類として、教則に最も合うものは"
                "どれか。"
            ),
            "choice1": "105gとして判定し、無人航空機に該当する",
            "choice2": "125gとして判定し、無人航空機に該当する",
            "choice3": "75gとして判定し、模型航空機に分類する",
            "correct_choice": "A",
            "explanation": (
                "航空法上の重量は、機体本体とバッテリーの重量の合計で判定し、"
                "バッテリー以外の取り外し可能な付属品は含めない。この機体は"
                "75g＋30g＝105gとなるため、他の定義条件も満たしている本scenario"
                "では無人航空機に該当する。100g未満は模型航空機として区別される。"
            ),
            "source_locator": (
                "教則 第3章 3.1.1(1)（教則表示ページ7 / PDF viewer 13）"
            ),
        },
        "DRONE-Q-000047": {
            "slot_id": "VS-046",
            "kt_id": "D1-T01-KT005",
            "coverage": "COV-02",
            "question": (
                "登録済みの無人航空機について、リモートID機能を搭載せずに飛行"
                "することを検討している。\n\nリモートID機能の搭載免除に該当する"
                "飛行として、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "あらかじめ国に届け出たリモートID特定区域で、補助者の配置や区域"
                "範囲の明示など必要な措置を講じて飛行する"
            ),
            "choice2": (
                "リモートID特定区域を国に届け出ているが、区域の監視や範囲の明示"
                "などの必要な措置を講じずに飛行する"
            ),
            "choice3": (
                "私有地で所有者の同意を得て、区域の監視や範囲の明示を行うが、"
                "リモートID特定区域として国には届け出ずに飛行する"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則では、Remote IDは原則として搭載が必要だが、あらかじめ国に"
                "届け出たリモートID特定区域で、補助者配置や区域範囲の明示など必要な"
                "措置を講じる飛行は搭載免除の対象としている。単に特定区域を届け出る"
                "だけ、あるいは私有地で安全措置を講じるだけでは、この免除routeの"
                "条件を満たさない。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(1)5)（教則表示ページ14 / PDF viewer 20）"
            ),
        },
        "DRONE-Q-000048": {
            "slot_id": "VS-047",
            "kt_id": "D1-T01-KT008",
            "coverage": "COV-03",
            "question": (
                "操縦者は飛行中、無人航空機を自分の目では直接監視せず、機体から"
                "送られるモニター映像だけを見て操縦している。補助者は機体を直接"
                "目視している。\n\n航空法上の飛行方法の扱いとして、教則に最も合う"
                "ものはどれか。"
            ),
            "choice1": "補助者が直接目視しているため、目視内飛行として扱う",
            "choice2": (
                "操縦者自身が目視により常時監視していないため、目視外飛行に該当する"
            ),
            "choice3": (
                "モニター映像で機体を継続監視しているため、目視内飛行として扱う"
            ),
            "correct_choice": "B",
            "explanation": (
                "教則の「目視により常時監視」は、飛行させる者自身が自分の目で見る"
                "ことを指す。モニターや双眼鏡による監視、補助者による監視はこれに"
                "含まれないため、このscenarioは目視外飛行に該当する。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)2)b（教則表示ページ15 / PDF viewer 21）"
            ),
        },
        "DRONE-Q-000049": {
            "slot_id": "VS-048",
            "kt_id": "D1-T01-KT012",
            "coverage": "COV-04",
            "question": (
                "ある飛行はカテゴリーII-B飛行であることが確認済みで、必要な立入管理"
                "措置も講じるものとする。\n\n個別の飛行許可・承認を不要にできるため"
                "の条件の組合せとして、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "飛行に必要な技能証明を有する操縦者が、機体認証を受けた無人航空機"
                "を使用し、飛行マニュアルの作成・遵守など必要な安全確保措置を講じる"
            ),
            "choice2": (
                "飛行に必要な技能証明を有する操縦者であれば、機体認証を受けていない"
                "無人航空機でも、安全確保措置を講じれば個別手続は不要となる"
            ),
            "choice3": (
                "機体認証を受けた無人航空機であれば、操縦者が技能証明を有していなく"
                "ても、安全確保措置を講じれば個別手続は不要となる"
            ),
            "correct_choice": "A",
            "explanation": (
                "Category II-Bでは、技能証明を受けた操縦者が機体認証を受けた"
                "無人航空機を使用し、飛行マニュアルの作成・遵守など必要な安全確保"
                "措置を講じる場合、個別の許可・承認を不要にできる。技能証明または"
                "機体認証の一方を欠く場合は、この手続省略routeには該当しない。"
            ),
            "source_locator": (
                "教則 第3章 3.1.1(2)5)a（教則表示ページ10 / PDF viewer 16）"
            ),
        },
        "DRONE-Q-000050": {
            "slot_id": "VS-049",
            "kt_id": "D1-T01-KT016",
            "coverage": "COV-05",
            "question": (
                "航空法施行規則第236条の82第1項第2号および関係通達で定める必要な"
                "要件をすべて満たして、無人航空機による農薬等の空中散布を行うもの"
                "とする。\n\n飛行の承認手続が不要となる飛行方法だけで構成された組合せ"
                "はどれか。"
            ),
            "choice1": "夜間飛行・目視外飛行・物件投下",
            "choice2": "夜間飛行・催し場所上空の飛行・物件投下",
            "choice3": "空港等の周辺の空域での飛行・目視外飛行・物件投下",
            "correct_choice": "A",
            "explanation": (
                "所定の要件を満たす農薬等の空中散布では、夜間飛行、目視外飛行、"
                "30m未満の飛行、危険物輸送、物件投下に係る承認手続が不要となる。"
                "催し場所上空はこの特例の対象ではなく、空港等周辺は飛行方法の承認"
                "ではなく空域に係る許可の論点である。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)3)d（教則表示ページ18 / PDF viewer 24）"
            ),
            "supporting_authority": (
                "航空法施行規則 第236条の82第1項第2号 / 国空無機第338898号 / "
                "令和8年3月23日 制定"
            ),
        },
        "DRONE-Q-000051": {
            "slot_id": "VS-050",
            "kt_id": "D1-T01-KT023",
            "coverage": "COV-06",
            "question": (
                "無人航空機を飛行させている最中に、航行中の航空機が近くを飛行して"
                "いることを確認した。\n\n操縦者の対応として、教則に最も合うものは"
                "どれか。"
            ),
            "choice1": (
                "無人航空機を地上に降下させるなど、航空機との接近・衝突を避ける"
                "ための適切な措置をとる"
            ),
            "choice2": (
                "航空機側が無人航空機を確認して回避できるまで、現在の高度と飛行"
                "経路を維持する"
            ),
            "choice3": (
                "航空機との距離が30m以上確保できていれば、現在の飛行経路を維持する"
            ),
            "correct_choice": "A",
            "explanation": (
                "飛行中に航行中の航空機を確認した場合、教則は無人航空機を地上へ"
                "降下させるなど、接近・衝突を回避する適切な措置を求めている。"
                "航空機との関係では無人航空機側が回避する考え方であり、第三者等との"
                "30m距離ruleを航空機との優先関係へ転用するものではない。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(3)1)c（教則表示ページ22 / PDF viewer 28）"
            ),
        },
        "DRONE-Q-000052": {
            "slot_id": "VS-051",
            "kt_id": "D1-T01-KT026",
            "coverage": "COV-07",
            "question": (
                "無人航空機の飛行により、航空法上の「事故」に該当する事態が発生し、"
                "負傷者もいることが確認された。\n\n操縦者に求められる措置として、"
                "最も適切なものはどれか。"
            ),
            "choice1": (
                "直ちに飛行を中止し、負傷者の救護や状況に応じた危険防止措置を"
                "行ったうえで、必要事項を国土交通大臣に報告する"
            ),
            "choice2": (
                "直ちに飛行を中止し、負傷者の救護や危険防止措置を行うが、国土交通"
                "大臣への報告は損害額が一定以上の場合に限る"
            ),
            "choice3": (
                "直ちに飛行を中止して国土交通大臣へ報告し、負傷者の救護や危険防止"
                "措置は関係機関の到着後に行う"
            ),
            "correct_choice": "A",
            "explanation": (
                "航空法上の事故が発生した場合は、直ちに飛行を中止し、負傷者がいれば"
                "救護・通報を行うなど必要な危険防止措置を講じ、事故の必要事項を"
                "国土交通大臣へ報告する必要がある。事故後の原因究明を先行させて"
                "これらの措置を遅らせるruleではない。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(3)1)f ア)（教則表示ページ22 / PDF viewer 28）"
            ),
        },
        "DRONE-Q-000053": {
            "slot_id": "VS-052",
            "kt_id": "D1-T01-KT028",
            "coverage": "COV-08",
            "question": (
                "特定飛行について、あらかじめ飛行計画を通報して飛行を開始した。\n\n"
                "飛行中、撮影対象を変更したくなったため、安全確保上やむを得ない事情"
                "はないが、通報した経路とは別の経路へ変更したい。\n\n教則の扱いと"
                "して最も適切なものはどれか。"
            ),
            "choice1": (
                "飛行目的が変わらなければ、通報した経路から変更してもよい"
            ),
            "choice2": (
                "原則として通報した飛行計画に従って飛行し、安全確保のためやむを"
                "得ない場合でなければ任意に変更しない"
            ),
            "choice3": (
                "経路は自由に変更でき、飛行終了後に変更内容だけを通報すればよい"
            ),
            "correct_choice": "B",
            "explanation": (
                "特定飛行では、原則としてあらかじめ飛行計画を通報し、通報した計画に"
                "従って飛行する必要がある。安全確保のためやむを得ない場合には例外が"
                "あるが、このscenarioではその条件を満たしていない。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(3)2)a（教則表示ページ23 / PDF viewer 29）"
            ),
        },
        "DRONE-Q-000054": {
            "slot_id": "VS-053",
            "kt_id": "D1-T02-KT001",
            "coverage": "COV-09",
            "question": (
                "小型無人機等飛行禁止法における「特定航空用機器」に該当するものと"
                "して、教則に最も合うものはどれか。"
            ),
            "choice1": "遠隔操作で飛行させる無人回転翼航空機",
            "choice2": "人が使用して飛行するパラグライダー",
            "choice3": "人が搭乗して飛行する通常の有人ヘリコプター",
            "correct_choice": "B",
            "explanation": (
                "同法では、規制対象を「小型無人機」と「特定航空用機器」に分けて"
                "いる。人が使用して飛行できる気球、ハンググライダー、パラグライダー"
                "等は特定航空用機器に該当する。Aは同法上の「小型無人機」側の例で"
                "あり、Bとはcategoryが異なる。"
            ),
            "source_locator": (
                "教則 第3章 3.2.1(2)2)（教則表示ページ30 / PDF viewer 36）"
            ),
        },
        "DRONE-Q-000055": {
            "slot_id": "VS-054",
            "kt_id": "D1-T02-KT002",
            "coverage": "COV-10",
            "question": (
                "ある施設が、小型無人機等飛行禁止法上の対象施設であることは確認済み"
                "とする。\n\nレッド・ゾーンとイエロー・ゾーンの関係として、教則に"
                "最も合うものはどれか。"
            ),
            "choice1": (
                "対象施設の敷地・区域の上空がレッド・ゾーン、その周囲おおむね"
                "1,000mの上空がイエロー・ゾーン"
            ),
            "choice2": (
                "対象施設の敷地・区域の上空がイエロー・ゾーン、その周囲おおむね"
                "1,000mの上空がレッド・ゾーン"
            ),
            "choice3": (
                "対象施設の敷地・区域とその周囲おおむね1,000mの上空がすべて"
                "レッド・ゾーンで、イエロー・ゾーンは設けない"
            ),
            "correct_choice": "A",
            "explanation": (
                "小型無人機等飛行禁止法では、対象施設の敷地・区域上空をRed Zone、"
                "その周囲おおむね1,000mの上空をYellow Zoneとして規制する。具体的"
                "にどの施設が現在対象施設に指定されているかは変動し得るため、本問"
                "では対象施設であることをinputとして固定している。"
            ),
            "source_locator": (
                "教則 第3章 3.2.1(3)（教則表示ページ30 / PDF viewer 36）"
            ),
        },
        "DRONE-Q-000056": {
            "slot_id": "VS-055",
            "kt_id": "D1-T02-KT003",
            "coverage": "COV-11",
            "question": (
                "小型無人機等飛行禁止法の対象施設周辺地域で、対象施設の管理者から"
                "同意を得ており、飛行禁止の法定例外に該当するものとする。\n\n"
                "この場合の通報について、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "管理者の同意により例外が成立しているため、同法に基づく通報は"
                "不要である"
            ),
            "choice2": (
                "例外に該当する場合でも、対象施設周辺地域を飛行するには所定の通報"
                "が必要である"
            ),
            "choice3": "例外に該当する場合、通報は飛行終了後に行えばよい",
            "correct_choice": "B",
            "explanation": (
                "小型無人機等飛行禁止法では、管理者の同意等によって飛行禁止の例外に"
                "該当しても、対象施設周辺地域で飛行する場合には都道府県公安委員会等"
                "への所定の通報が必要である。「例外に該当すること」と「通報が不要"
                "であること」は同義ではない。"
            ),
            "source_locator": (
                "教則 第3章 3.2.1(4)（教則表示ページ31 / PDF viewer 37）"
            ),
            "supporting_authority": "警察庁 小型無人機等飛行禁止法 通報手続",
        },
        "DRONE-Q-000057": {
            "slot_id": "VS-056",
            "kt_id": "D1-T02-KT005",
            "coverage": "COV-12",
            "question": (
                "無人航空機で使用する次の2つの無線systemについて考える。\n\n"
                "System P: 技術基準適合証明等を受けた、2.4GHz帯・10mW/MHzの"
                "小電力データ通信system\n\n"
                "System Q: 2.4GHz帯・1Wの無人移動体画像伝送system\n\n"
                "教則に示された無線局免許等・無線従事者資格の組合せとして最も"
                "適切なものはどれか。"
            ),
            "choice1": (
                "Pは無線局免許等・無線従事者資格とも不要、Qは無線局免許を要し"
                "第三級陸上特殊無線技士以上の資格を要する"
            ),
            "choice2": (
                "Pは無線局免許を要するが資格は不要、Qは無線局免許は不要だが"
                "第三級陸上特殊無線技士以上の資格を要する"
            ),
            "choice3": (
                "Pは無線局免許等は不要だが第三級陸上特殊無線技士以上の資格を要し、"
                "Qは無線局免許だけを要して資格は不要"
            ),
            "correct_choice": "A",
            "explanation": (
                "必要な無線局免許・無線従事者資格は、単に「2.4GHzを使うか」では"
                "なく使用する無線systemとその条件によって異なる。教則表では、条件を"
                "満たす小電力systemは無線局免許等・資格とも不要。一方、2.4GHz帯1W"
                "の無人移動体画像伝送systemは無線局免許を要し、第三級陸上特殊無線"
                "技士以上の資格を要する。"
            ),
            "source_locator": (
                "教則 第3章 3.2.2(1)〜(2)（教則表示ページ31–32 / PDF viewer 37–38）"
            ),
        },
        "DRONE-Q-000058": {
            "slot_id": "VS-057",
            "kt_id": "D1-T02-KT009",
            "coverage": "COV-13",
            "question": (
                "ある場所で無人航空機を飛行する計画があり、航空法上必要となる許可・"
                "承認等については確認済みである。\n\n飛行場所は地方公共団体が管理"
                "する施設内である。\n\n飛行可否を判断するために次に確認すべきもの"
                "として、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "航空法上の確認が完了していれば、それ以外の規制確認は不要である"
            ),
            "choice2": (
                "土地・施設の管理者から使用の了承が得られれば、地方公共団体の条例等"
                "は確認しなくてよい"
            ),
            "choice3": (
                "その場所に適用される地方公共団体の条例や施設の規則など、航空法以外"
                "の規制も確認する"
            ),
            "correct_choice": "C",
            "explanation": (
                "飛行可否は航空法だけで完結するとは限らない。教則は、その他の法令や"
                "地方公共団体の条例により、特定の場所で無人航空機の利用・飛行が制限"
                "される場合があるとしており、最新の条例情報などを関係する地方公共"
                "団体等へ確認する必要がある。"
            ),
            "source_locator": (
                "教則 第3章 3.2.3（教則表示ページ33 / PDF viewer 39）"
            ),
        },
        "DRONE-Q-000059": {
            "slot_id": "VS-058",
            "kt_id": "D1-T02-KT010",
            "coverage": "COV-14",
            "question": (
                "無人航空機の飛行自粛要請空域について、教則の説明に最も合うものは"
                "どれか。"
            ),
            "choice1": (
                "航空法に基づく飛行禁止空域であり、航空法上の飛行許可を取得している"
                "かを確認する"
            ),
            "choice2": (
                "法令等に基づく規制ではなく、飛行前に国土交通省の公示等で設定の有無"
                "を確認し、要請内容に応じて対応する"
            ),
            "choice3": (
                "地方公共団体の条例に基づいて設定される区域であり、その地方公共団体"
                "の条例だけを確認する"
            ),
            "correct_choice": "B",
            "explanation": (
                "飛行自粛要請空域は、法令等に基づく飛行禁止規制そのものではない。"
                "警備上の観点等から関係機関の要請を受け、国土交通省が飛行自粛を要請"
                "するもので、設定時には国土交通省の公式情報で公示される。そのため"
                "操縦者は飛行前に設定の有無を確認し、要請内容に応じて対応する。"
            ),
            "source_locator": (
                "教則 第3章 3.2.4（教則表示ページ33 / PDF viewer 39）"
            ),
        },
    }
    B5_D2A_EXPECTATIONS = {
        "DRONE-Q-000060": {
            "slot_id": "VS-059",
            "kt_id": "D2-T01-KT001",
            "coverage": "COV-15",
            "question": (
                "垂直離着陸やホバリングは必要なく、比較的高速で、エネルギー効率を"
                "高くして長距離・長時間の前進飛行を行うことを重視する。\n\n"
                "教則に示された機体種類の特徴に最も合う選択はどれか。"
            ),
            "choice1": (
                "飛行機を選ぶ。回転翼航空機より飛行速度が速く、エネルギー効率が"
                "高いため、長距離・長時間の飛行に適する"
            ),
            "choice2": (
                "マルチローターを選ぶ。飛行機より飛行速度が速く、エネルギー効率が"
                "高いため、長距離・長時間の飛行に適する"
            ),
            "choice3": (
                "ヘリコプターを選ぶ。飛行機より飛行速度が速く、エネルギー効率が"
                "高いため、長距離・長時間の飛行に適する"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則では、回転翼航空機は垂直離着陸やホバリングが可能である一方、"
                "飛行機は回転翼航空機より飛行速度が速く、エネルギー効率が高いため、"
                "長距離・長時間飛行が可能という特徴を示している。今回の任務条件は"
                "飛行機側の特徴に合う。"
            ),
            "source_locator": (
                "教則 第4章 4.1.1「無人航空機の種類と特徴」（教則表示ページ34 / "
                "PDF viewer 40）"
            ),
        },
        "DRONE-Q-000061": {
            "slot_id": "VS-060",
            "kt_id": "D2-T01-KT003",
            "coverage": "COV-16",
            "question": (
                "回転翼航空機（ヘリコプター）で、前後左右への移動のためにローターの"
                "回転面を傾けたり、上昇・降下のためにローターピッチ角を変えたりする。"
                "\n\n教則が、このために必要な機構として挙げているものはどれか。"
            ),
            "choice1": (
                "スワッシュプレート等を用いて、ローター回転面の傾きやローターピッチ角"
                "を変える"
            ),
            "choice2": (
                "テールローターを用いて、ローター回転面の傾きやローターピッチ角を"
                "変える"
            ),
            "choice3": (
                "メインローターの反トルクを用いて、ローター回転面の傾きやローター"
                "ピッチ角を変える"
            ),
            "correct_choice": "A",
            "explanation": (
                "ヘリコプターでは、前後左右への移動のためのローター回転面の傾きや、"
                "上昇・降下のためのローターピッチ角の変更に必要な機構として、教則は"
                "スワッシュプレート等を挙げている。"
            ),
            "source_locator": (
                "教則 第4章 4.1.3(1)（教則表示ページ35 / PDF viewer 41）"
            ),
        },
        "DRONE-Q-000062": {
            "slot_id": "VS-061",
            "kt_id": "D2-T01-KT004",
            "coverage": "COV-17",
            "question": (
                "ホバリング中のマルチローターを右方向へ移動させる。\n\n教則に示された"
                "基本的な機体の動きとして、最も適切なものはどれか。"
            ),
            "choice1": (
                "右側のローターの回転数を下げ、左側のローターの回転数を上げて、"
                "機体を右へ傾ける"
            ),
            "choice2": (
                "右側のローターの回転数を上げ、左側のローターの回転数を下げて、"
                "機体を右へ傾ける"
            ),
            "choice3": (
                "左右のローターの回転数を同じだけ上げ、機体を右へ傾ける"
            ),
            "correct_choice": "A",
            "explanation": (
                "マルチローターの前後左右移動では、移動を指示した側のローター回転数を"
                "下げ、反対側を上げる。これによって機体が指示方向へ傾き、ローター推力"
                "の合力もその方向へ傾くため、機体が移動する。右移動なら右側を下げ、"
                "左側を上げる。"
            ),
            "source_locator": (
                "教則 第4章 4.1.4(1)2)（教則表示ページ36 / PDF viewer 42）"
            ),
        },
        "DRONE-Q-000063": {
            "slot_id": "VS-062",
            "kt_id": "D2-T02-KT001",
            "coverage": "COV-18",
            "question": (
                "夜間飛行を予定している機体について確認したところ、衝突回避などに"
                "利用するビジョンセンサーが夜間に対応していないことが分かった。\n\n"
                "この場合に考慮すべき技術上の影響として、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "ビジョンセンサーに依存する衝突回避や姿勢安定などの安全機能が使用"
                "できない可能性がある"
            ),
            "choice2": (
                "地上照明を設置すれば、ビジョンセンサーの夜間対応の有無は安全機能の"
                "評価から外せる"
            ),
            "choice3": (
                "送信機で位置や高度を確認できれば、ビジョンセンサーの夜間対応の有無"
                "は安全機能の評価から外せる"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則は、機体に搭載されたビジョンセンサーが夜間に対応していない場合、"
                "衝突回避・姿勢安定などの安全機能が使用できない可能性があることに注意"
                "を求めている。地上照明や別の情報表示があることだけから、このsensor "
                "limitationを除外するとはしていない。"
            ),
            "source_locator": (
                "教則 第4章 4.2「夜間飛行」(1)（教則表示ページ37 / PDF viewer 43）"
            ),
        },
        "DRONE-Q-000064": {
            "slot_id": "VS-063",
            "kt_id": "D2-T02-KT003",
            "coverage": "COV-19",
            "question": (
                "目視外飛行を行う機体で、搭載カメラから機外の映像は地上で確認できる。"
                "一方、操縦装置には飛行中の機体速度が表示されない。\n\n教則の目視外"
                "飛行に関する技術的な観点から、この状態の評価として最も適切なものは"
                "どれか。"
            ),
            "choice1": (
                "機外の映像を確認できるため、飛行中の速度を地上で把握できなくても"
                "必要な情報は補えている"
            ),
            "choice2": (
                "機外の映像とは別に、機体状態の情報として飛行中の速度も地上で把握"
                "できるようにする必要がある"
            ),
            "choice3": (
                "飛行前に予定速度を設定していれば、飛行中の実際の速度を地上で把握"
                "できなくてもよい"
            ),
            "correct_choice": "B",
            "explanation": (
                "目視外飛行では機体や周囲の状況を直接肉眼で確認できないため、教則は"
                "機体カメラによる外部情報に加え、速度などの機体状態を把握することを"
                "求めている。また、目視外飛行に必要な装備として、高度・速度・位置・"
                "不具合状況等を地上で監視できる操縦装置が挙げられている。このため、"
                "機外の映像を確認できても、飛行中の機体速度を地上で把握できない状態"
                "では十分ではない。"
            ),
            "source_locator": (
                "教則 第4章 4.2「目視外飛行」(1)（教則表示ページ37 / PDF viewer 43）; "
                "supporting 4.2「目視外飛行」(2)①（教則表示ページ37 / PDF viewer 43）"
            ),
        },
        "DRONE-Q-000065": {
            "slot_id": "VS-064",
            "kt_id": "D2-T02-KT004",
            "coverage": "COV-20",
            "question": (
                "目視外飛行中に、操縦者と機体との無線通信が断絶した。\n\n教則が"
                "フェールセーフ機能の例として示している、この事象への対応として最も"
                "適切なものはどれか。"
            ),
            "choice1": (
                "離陸地点まで自動的に戻る、または通信が復帰するまで空中で位置を"
                "維持する"
            ),
            "choice2": "GNSS以外の手段へ切り替えて、新たな位置情報を取得する",
            "choice3": "電池の発煙・発火を防止し、安全な自動着陸を行う",
            "correct_choice": "A",
            "explanation": (
                "教則は、目視外飛行のfailsafe例として、電波断絶時には離陸地点への"
                "自動帰還、または電波が復帰するまで空中で位置を維持する機能を挙げて"
                "いる。BはGNSS異常、Cは電池異常に対応する別のfailsafe exampleで"
                "あり、radio-link lossへの対応とは異なる。"
            ),
            "source_locator": (
                "教則 第4章 4.2「目視外飛行」(2)①（教則表示ページ37–38 / "
                "PDF viewer 43–44）"
            ),
        },
        "DRONE-Q-000066": {
            "slot_id": "VS-065",
            "kt_id": "D2-T03-KT001",
            "coverage": "COV-21",
            "question": (
                "飛行機が速度と姿勢を一定に保って定常飛行している。\n\n飛行機に働く"
                "主な力の関係として、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "主翼の揚力が重力に対抗し、プロペラ等の推力が抗力に対抗する"
            ),
            "choice2": (
                "主翼の揚力が抗力に対抗し、プロペラ等の推力が重力に対抗する"
            ),
            "choice3": (
                "抗力が重力に対抗し、プロペラ等の推力が主翼の揚力に対抗する"
            ),
            "correct_choice": "A",
            "explanation": (
                "飛行機では主翼に生じる揚力が重力に対抗し、飛行方向と逆向きに働く"
                "抗力に対してプロペラ等の推力が対抗する。これら機体に働く力が釣り"
                "合うと、速度と姿勢を一定とする定常飛行になる。"
            ),
            "source_locator": (
                "教則 第4章 4.3.1「無人航空機の飛行原理」（教則表示ページ38 / "
                "PDF viewer 44）"
            ),
        },
        "DRONE-Q-000067": {
            "slot_id": "VS-066",
            "kt_id": "D2-T03-KT004",
            "coverage": "COV-22",
            "question": (
                "飛行機の翼について、迎角を徐々に大きくし、過度に大きな迎角となった。"
                "\n\n教則が示す変化として最も適切なものはどれか。"
            ),
            "choice1": (
                "翼面から流れが剥離し、揚力が減少して抗力が増大し、失速につながる"
            ),
            "choice2": (
                "翼面から流れが剥離し、揚力が増加して抗力が減少し、失速につながる"
            ),
            "choice3": (
                "翼面から流れが剥離せず、揚力と抗力がともに減少し、失速につながる"
            ),
            "correct_choice": "A",
            "explanation": (
                "一般には迎角を増すと揚力と抗力は増加するが、迎角を大きくしすぎると"
                "翼表面から流れが剥離し、揚力は減少、抗力は増大して失速を招く。単に"
                "迎角を増しただけで直ちにstallになるという意味ではない。"
            ),
            "source_locator": (
                "教則 第4章 4.3.2「揚力発生の特徴」（教則表示ページ38 / "
                "PDF viewer 44）"
            ),
        },
        "DRONE-Q-000068": {
            "slot_id": "VS-067",
            "kt_id": "D2-T03-KT005",
            "coverage": "COV-23",
            "question": (
                "一般的な回転翼航空機（ヘリコプター）について、メインローターの反"
                "トルクへの対応とヨー方向の姿勢制御の説明として、教則に最も合うもの"
                "はどれか。"
            ),
            "choice1": (
                "テールローターの推力でメインローターの反トルクを相殺し、その推力を"
                "変化させてヨーを制御する"
            ),
            "choice2": (
                "テールローターの推力でメインローターの揚力を相殺し、その推力を変化"
                "させてピッチを制御する"
            ),
            "choice3": (
                "テールローターの推力でメインローターの抗力を相殺し、その推力を変化"
                "させてロールを制御する"
            ),
            "correct_choice": "A",
            "explanation": (
                "一般的なヘリコプターでは、メインローターの反トルクをテールローター"
                "で相殺する。また、tail rotorの推力を変化させることでヨー方向の"
                "姿勢制御を行う。"
            ),
            "source_locator": (
                "教則 第4章 4.3.2「揚力発生の特徴」（教則表示ページ38–39 / "
                "PDF viewer 44–45）"
            ),
        },
        "DRONE-Q-000069": {
            "slot_id": "VS-068",
            "kt_id": "D2-T03-KT006",
            "coverage": "COV-24",
            "question": (
                "同じ重量のペイロードを、機体の元の重心に近い位置から、機体前方の"
                "離れた位置へ付け替える。\n\n総重量は変わらないものとすると、飛行"
                "特性への影響について教則に最も合うものはどれか。"
            ),
            "choice1": (
                "総重量が同じなら、搭載位置が変わっても飛行特性は基本的に同じと"
                "考える"
            ),
            "choice2": (
                "搭載位置によって重心位置が変わると、安定性・飛行性能・運動性能に"
                "影響する可能性がある"
            ),
            "choice3": (
                "搭載位置は空気抵抗には影響し得るが、重心位置による飛行特性への影響"
                "は考えなくてよい"
            ),
            "correct_choice": "B",
            "explanation": (
                "教則は、機体重量の変化によって安定性・飛行性能・運動性能などの飛行"
                "特性が変化するとし、特に重心位置の変化は飛行特性へ大きな影響を及ぼす"
                "としている。そのため、同じ重量のpayloadでも搭載位置によってCGが"
                "変わる点を無視できない。"
            ),
            "source_locator": (
                "教則 第4章 4.3.4「無人航空機へのペイロード搭載」（教則表示ページ39 "
                "/ PDF viewer 45）"
            ),
        },
    }
    B6_D2B_EXPECTATIONS = {
        "DRONE-Q-000070": {
            "slot_id": "VS-070",
            "kt_id": "D2-T04-KT002",
            "coverage": "COV-26",
            "question": (
                "無人航空機に搭載されるIMU（慣性計測装置）の構成と、検出する情報の"
                "組合せとして、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "3軸のジャイロセンサと3方向の加速度センサ等を用い、3次元の角速度と"
                "加速度を検出する"
            ),
            "choice2": (
                "3軸のジャイロセンサとGNSS受信機を用い、3次元の角速度と地球上の"
                "位置を一体として検出する"
            ),
            "choice3": (
                "3方向の加速度センサと地磁気センサを用い、3次元の加速度と機体方位を"
                "一体として検出する"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則では、IMUを3軸のジャイロセンサと3方向の加速度センサ等によって、"
                "3次元の角速度と加速度を検出する装置としている。GNSSによる位置取得や"
                "地磁気センサによる方位取得とは役割が異なる。"
            ),
            "source_locator": (
                "教則 第4章 4.4.1(1)〜(2)（教則表示ページ42 / PDF viewer 48）"
            ),
        },
        "DRONE-Q-000071": {
            "slot_id": "VS-071",
            "kt_id": "D2-T04-KT005",
            "coverage": "COV-27",
            "question": (
                "電動の無人航空機で、ローターの回転数を変化させて揚力や推力を調整"
                "する。\n\nこのとき、モーターの回転数を制御するcomponentとして教則に"
                "示されているものはどれか。"
            ),
            "choice1": "バッテリー",
            "choice2": "ESC（エレクトロニック・スピード・コントローラー）",
            "choice3": "ローター（プロペラ）",
            "correct_choice": "B",
            "explanation": (
                "教則では、モーターの回転数はESCによって制御され、モーターで駆動"
                "されるローターの回転数を増減させることで揚力や推力を変化させると"
                "している。"
            ),
            "source_locator": (
                "教則 第4章 4.4.2(2)〜(3)（教則表示ページ43 / PDF viewer 49）"
            ),
        },
        "DRONE-Q-000072": {
            "slot_id": "VS-072",
            "kt_id": "D2-T04-KT010",
            "coverage": "COV-28",
            "question": (
                "LiPoバッテリーの端子が誤って接触し、短絡した。\n\n教則がこの状態に"
                "ついて直接示している危険として、最も適切なものはどれか。"
            ),
            "choice1": "急速な劣化が進み、寿命が短くなることが主な危険となる",
            "choice2": (
                "内部に通常より多くのガスが発生し、膨張することが主な危険となる"
            ),
            "choice3": "発火する可能性がある",
            "correct_choice": "C",
            "explanation": (
                "教則は、LiPoバッテリーが短絡した場合には発火する可能性があるとして"
                "いる。したがって、端子の短絡は火災につながり得る電気的な危険として"
                "扱う必要がある。"
            ),
            "source_locator": (
                "教則 第4章 4.4.4(2)（教則表示ページ45 / PDF viewer 51）"
            ),
        },
        "DRONE-Q-000073": {
            "slot_id": "VS-073",
            "kt_id": "D2-T04-KT012",
            "coverage": "COV-29",
            "question": (
                "無人航空機に物件投下装置を取り付けて使用する。\n\n物件投下装置の"
                "technical characteristicと取扱いとして、教則に最も合うものは"
                "どれか。"
            ),
            "choice1": (
                "意図せず物件が落下しない構造とし、装置ごとに定められた搭載方法や"
                "投下手順を理解して使用する"
            ),
            "choice2": (
                "投下のタイミングを操縦者が監視できれば、装置側で意図しない落下を"
                "防止する構造は必要としない"
            ),
            "choice3": (
                "物件を確実に保持できれば、装置ごとに定められた搭載方法や投下手順を"
                "確認せず使用できる"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則では、物件投下装置は意図せず物件が落下しない構造となっており、"
                "さらに搭載方法や投下手順が定められているため、装置の特性と機能を"
                "理解して使用する必要があるとしている。"
            ),
            "source_locator": (
                "教則 第4章 4.4.5（教則表示ページ46 / PDF viewer 52）"
            ),
        },
        "DRONE-Q-000074": {
            "slot_id": "VS-074",
            "kt_id": "D2-T05-KT001",
            "coverage": "COV-30",
            "question": (
                "無人航空機の通信に用いる電波について、周波数と障害物への回り込み"
                "やすさの関係として、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "周波数が高く波長が短いほど回折しやすくなり、障害物の背後へ回り込み"
                "やすくなる"
            ),
            "choice2": (
                "周波数が低く波長が長いほど回折しやすくなり、障害物の背後へ回り込み"
                "やすくなる"
            ),
            "choice3": (
                "回折のしやすさは周波数や波長とは関係せず、送信出力だけで決まる"
            ),
            "correct_choice": "B",
            "explanation": (
                "教則では、電波は周波数が低く、波長が長いほど障害物の後ろへ回り込み"
                "やすいとしている。一方、2.4GHz帯の電波は比較的回折しにくく直進性が"
                "高いため、障害物の影響を受けやすい。"
            ),
            "source_locator": (
                "教則 第4章 4.5.1(1)1)（教則表示ページ47 / PDF viewer 53）"
            ),
        },
        "DRONE-Q-000075": {
            "slot_id": "VS-075",
            "kt_id": "D2-T05-KT002",
            "coverage": "COV-31",
            "question": (
                "無人航空機の制御用電波が、周囲の建物などで反射・屈折し、複数の経路"
                "を通って受信側へ届いている。経路によってわずかな到達時間の差も生じて"
                "いる。\n\nこの状態が無線通信へ及ぼす影響として、教則に最も合うものは"
                "どれか。"
            ),
            "choice1": "電波が弱くなり、一時的に操縦不能となる要因になり得る",
            "choice2": (
                "複数経路から届くことで受信電波が安定して強くなり、通信距離が伸びる"
                "方向に働く"
            ),
            "choice3": (
                "送信機の出力が自動的に増加し、経路差による通信への影響が打ち消される"
            ),
            "correct_choice": "A",
            "explanation": (
                "建物などによる反射・屈折で電波が複数の経路を通る現象をmultipathと"
                "いう。教則では、反射・屈折した電波にはわずかな到達遅れが生じ、電波が"
                "弱くなって一時的に操縦不能となる要因の一つになり得るとしている。"
            ),
            "source_locator": (
                "教則 第4章 4.5.1(1)2)（教則表示ページ47 / PDF viewer 53）"
            ),
        },
        "DRONE-Q-000076": {
            "slot_id": "VS-076",
            "kt_id": "D2-T05-KT007",
            "coverage": "COV-32",
            "question": (
                "高圧線や変電所、鉄材を多く使用した建物などの近くで無人航空機を飛行"
                "させる。\n\nこのような環境が機体へ及ぼし得る影響について、教則に最も"
                "合うものはどれか。"
            ),
            "choice1": (
                "鉄や電流が主に気圧センサの検出へ影響し、高度の測定だけに影響する"
                "可能性がある"
            ),
            "choice2": (
                "鉄や電流が地磁気の検出へ影響し、機体の姿勢や進行方向へ影響する"
                "可能性がある"
            ),
            "choice3": (
                "鉄や電流が主に加速度センサの検出へ影響し、速度変化の測定だけに影響"
                "する可能性がある"
            ),
            "correct_choice": "B",
            "explanation": (
                "教則では、鉄や電流が地磁気の検出へ影響を与えるとしており、高圧線、"
                "変電所、鉄材を多く使用した建物などを例示している。この影響によって、"
                "機体の姿勢や進行方向へ影響が生じる場合がある。"
            ),
            "source_locator": (
                "教則 第4章 4.5.2(2)（教則表示ページ49 / PDF viewer 55）"
            ),
        },
        "DRONE-Q-000077": {
            "slot_id": "VS-077",
            "kt_id": "D2-T05-KT009",
            "coverage": "COV-33",
            "question": (
                "GNSSによって無人航空機の位置を求める基本原理として、教則に最も合う"
                "ものはどれか。"
            ),
            "choice1": (
                "最低4個以上の人工衛星から信号を同時に受信し、それぞれの人工衛星まで"
                "の距離を用いて位置を求める"
            ),
            "choice2": (
                "最低3個の人工衛星から信号を同時に受信し、それぞれの人工衛星までの"
                "距離を用いて位置を求める"
            ),
            "choice3": (
                "最低4個以上の人工衛星から信号を受信し、各衛星からの電波強度だけを"
                "比較して位置を求める"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則では、GNSSは最低4個以上の人工衛星からの信号を同時に受信し、機体"
                "のreceiverがそれぞれの人工衛星までの距離を求めることで機体位置を"
                "特定するとしている。"
            ),
            "source_locator": (
                "教則 第4章 4.5.3(1)（教則表示ページ50 / PDF viewer 56）"
            ),
        },
        "DRONE-Q-000078": {
            "slot_id": "VS-078",
            "kt_id": "D2-T06-KT001",
            "coverage": "COV-34",
            "question": (
                "電動機を用いる無人航空機について、飛行前後の点検では異常が確認されて"
                "いない。\n\n一方、その機体で定められている定期整備の総飛行時間に達した。"
                "\n\n整備・点検の扱いとして、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "飛行前後に異常がなければ、一定期間や総飛行時間による定期整備点検は"
                "行わない"
            ),
            "choice2": (
                "機体ごとに定められた一定期間や総飛行時間に従い、メーカーが設定する"
                "内容で整備点検を行う"
            ),
            "choice3": (
                "一定期間だけを基準に整備点検を行い、総飛行時間による整備時期は考慮"
                "しない"
            ),
            "correct_choice": "B",
            "explanation": (
                "電動機を用いる無人航空機では、飛行前後の点検だけでなく、機体ごとに"
                "定められた一定期間や一定の総飛行時間ごとにも整備点検を行う必要が"
                "ある。その際は、機体メーカーが設定する整備内容を踏まえ、必要な時期"
                "に修理等の整備を行う。"
            ),
            "source_locator": (
                "教則 第4章 4.6.1(1)（教則表示ページ50 / PDF viewer 56）"
            ),
        },
        "DRONE-Q-000079": {
            "slot_id": "VS-079",
            "kt_id": "D2-T06-KT004",
            "coverage": "COV-35",
            "question": (
                "エンジン機について、機体メーカーが定めた整備を行う必要がある。\n\n"
                "しかし運航者には、エンジン整備に関する十分な知識と技能がない。\n\n"
                "教則に沿った対応として最も適切なものはどれか。"
            ),
            "choice1": (
                "メーカーの整備手順書があれば、知識や技能が不足していても運航者自身"
                "で整備を行う"
            ),
            "choice2": (
                "整備を次の定期時期まで延期し、その間は飛行前後の点検だけで運航を"
                "継続する"
            ),
            "choice3": "専門の整備業者に依頼する",
            "correct_choice": "C",
            "explanation": (
                "教則は、エンジン機の整備について、運航者のエンジン整備に関する知識"
                "や技能が不足している場合には、専門の整備業者へ依頼するとしている。"
                "整備手順が存在することだけで、知識・技能不足を補えるという扱いでは"
                "ない。"
            ),
            "source_locator": (
                "教則 第4章 4.6.2（教則表示ページ51 / PDF viewer 57）"
            ),
        },
    }
    B7_D3_EXPECTATIONS = {
        "DRONE-Q-000080": {
            "slot_id": "VS-080",
            "kt_id": "D3-T01-KT001",
            "coverage": "COV-36",
            "question": (
                "飛行に必要な許可・承認や機体登録はすでに取得済みであり、飛行計画や"
                "気象等の確認も終えている。\n\n飛行開始前の最終的な準備として、"
                "教則に最も合うものはどれか。"
            ),
            "choice1": (
                "必要な装置・設備が設置され、許可・承認や機体登録等の有効期間が"
                "切れていないことを最終確認する"
            ),
            "choice2": (
                "この飛行に許可・承認が必要かどうかを、航空法上の飛行形態から"
                "もう一度判定し直す"
            ),
            "choice3": (
                "飛行経路のリスクを改めて分析し、発生頻度と結果の重大性から飛行計画"
                "を作り直す"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則では「飛行前の準備」として、必要な装置や設備を設置するとともに、"
                "飛行に必要な許可・承認や機体登録等の有効期間が切れていないかを最終"
                "確認するとしている。本問では法的要否やrisk評価そのものは既に済んで"
                "おり、飛行開始条件の最終確認が対象である。"
            ),
            "source_locator": (
                "教則 第5章 5.1.2(1)1)「飛行前の準備」"
                "（教則表示ページ52 / PDF viewer 58）"
            ),
        },
        "DRONE-Q-000081": {
            "slot_id": "VS-081",
            "kt_id": "D3-T01-KT002",
            "coverage": "COV-37",
            "question": (
                "飛行開始直前である。飛行前の準備や必要な手続は既に完了している。\n\n"
                "機体が正常に飛行できる状態かを確認する飛行前点検として、教則に"
                "最も合うものはどれか。"
            ),
            "choice1": "許可・承認の有効期間と飛行計画の通報状況を確認する",
            "choice2": (
                "機体の損傷やバッテリーの状態に加え、通信・推進・電源・自動制御系が"
                "正常に作動するか確認する"
            ),
            "choice3": (
                "一定期間や総飛行時間に基づく定期整備の実施時期だけを確認する"
            ),
            "correct_choice": "B",
            "explanation": (
                "飛行前の点検は、機体を飛行させる前にその都度行う最終点検である。"
                "教則では、機体の損傷やバッテリー等に加え、通信系、推進系、電源系、"
                "自動制御系が正常に作動するかなどを確認し、正常に飛行できることを"
                "確かめる。"
            ),
            "source_locator": (
                "教則 第5章 5.1.2(1)2)「飛行前の点検」"
                "（教則表示ページ52 / PDF viewer 58）"
            ),
        },
        "DRONE-Q-000082": {
            "slot_id": "VS-082",
            "kt_id": "D3-T01-KT006",
            "coverage": "COV-38",
            "question": (
                "あるカテゴリーII飛行について、個別の飛行許可・承認が必要であることは"
                "既に確認済みである。\n\n実際に飛行へ進むまでの手続として、最も"
                "適切なものはどれか。"
            ),
            "choice1": (
                "必要な機体・操縦者等の情報を整えて許可・承認申請を行い、審査後に"
                "許可・承認を得てから対象飛行を行う"
            ),
            "choice2": (
                "必要な情報を整えて申請を提出すれば、審査結果を待たず申請受付時点から"
                "対象飛行を行う"
            ),
            "choice3": (
                "飛行計画の通報を行えば、別途の許可・承認申請を行わず対象飛行を行う"
            ),
            "correct_choice": "A",
            "explanation": (
                "個別の許可・承認が必要な飛行では、必要な情報を整えて飛行許可・承認"
                "申請を行い、審査を経て許可・承認を取得してから飛行する。国土交通省"
                "の現行公式案内でも、機体情報・操縦者情報の整備、申請、審査、許可・"
                "承認発行というworkflowが示されている。"
            ),
            "source_locator": (
                "教則 第5章 5.1.3(1)「国土交通省への飛行申請」"
                "（教則表示ページ54 / PDF viewer 60）"
            ),
        },
        "DRONE-Q-000083": {
            "slot_id": "VS-083",
            "kt_id": "D3-T01-KT007",
            "coverage": "COV-39",
            "question": (
                "特定飛行について飛行計画を既に通報しているが、飛行開始前に予定経路"
                "を変更することになった。\n\n飛行計画の通報に関する実際の対応として、"
                "最も適切なものはどれか。"
            ),
            "choice1": (
                "元の飛行計画はそのまま残し、変更した経路で飛行した後に通報内容を"
                "更新する"
            ),
            "choice2": (
                "通報済みの飛行計画を更新し、通報している飛行開始日時までに変更を"
                "完了する"
            ),
            "choice3": (
                "飛行計画の通報は変更せず、飛行許可・承認申請を改めて行うことで"
                "経路変更に対応する"
            ),
            "correct_choice": "B",
            "explanation": (
                "通報済みの飛行計画について、飛行開始前に内容を変更する場合は、通報"
                "済みの計画を変更し、通報した飛行開始日時までに変更を行う。DIPS2.0"
                "の公式案内でも、通報した飛行計画の変更・削除は通報済み飛行開始日時"
                "までに行うとしている。"
            ),
            "source_locator": (
                "教則 第5章 5.1.2(2)⑦「飛行計画の策定及び通報」"
                "（教則表示ページ53 / PDF viewer 59）"
            ),
        },
        "DRONE-Q-000084": {
            "slot_id": "VS-084",
            "kt_id": "D3-T01-KT009",
            "coverage": "COV-40",
            "question": (
                "無人航空機を使用しない時間帯に、盗難や不正利用を防ぐための機器管理"
                "を行う。\n\n教則に示されたsecurity actionとして、最も適切なものは"
                "どれか。"
            ),
            "choice1": (
                "無人航空機本体と遠隔操縦に使用する機器の双方を適切に管理する"
            ),
            "choice2": (
                "無人航空機本体を適切に管理すれば、遠隔操縦に使用する機器は通常の"
                "場所に置いてよい"
            ),
            "choice3": (
                "遠隔操縦に使用する機器を適切に管理すれば、無人航空機本体の管理は"
                "特に行わなくてよい"
            ),
            "correct_choice": "A",
            "explanation": (
                "無人航空機には、機体そのものの盗難だけでなく、犯罪等への悪用を目的"
                "とした運航妨害やcontrol奪取のriskがある。教則はsecurity対策の例と"
                "して、無人航空機本体と遠隔操縦のための機器を適切に管理し、盗難等を"
                "防止することを挙げている。"
            ),
            "source_locator": (
                "教則 第5章 5.1「保険及びセキュリティ」(2) "
                "無人航空機に係るセキュリティ確保"
                "（教則表示ページ55 / PDF viewer 61）"
            ),
        },
        "DRONE-Q-000085": {
            "slot_id": "VS-085",
            "kt_id": "D3-T02-KT001",
            "coverage": "COV-41",
            "question": (
                "マルチローターを降下させている。\n\nボルテックス・リング・ステート"
                "による急激な揚力低下への対策として、教則に最も合う操作はどれか。"
            ),
            "choice1": (
                "機体を垂直方向に保ち、水平移動を加えずに降下を続ける"
            ),
            "choice2": (
                "降下中は機体を一定位置に保ち、垂直方向の操作だけで降下速度を"
                "調整する"
            ),
            "choice3": (
                "揚力を徐々に減少させながら、水平方向の移動も合わせて操作する"
            ),
            "correct_choice": "C",
            "explanation": (
                "マルチローターを垂直降下させると、吹き下ろした空気を再び吸い込んで"
                "気流が再循環し、急激に揚力を失うボルテックス・リング・ステートが"
                "発生することがある。教則では、降下時に水平方向の移動を合わせて操作"
                "することを墜落防止対策としている。"
            ),
            "source_locator": (
                "教則 第5章 5.2.1(1)3)「降下」"
                "（教則表示ページ56 / PDF viewer 62）"
            ),
        },
        "DRONE-Q-000086": {
            "slot_id": "VS-086",
            "kt_id": "D3-T02-KT005",
            "coverage": "COV-42",
            "question": (
                "次の2つの作業を行う。\n\n"
                "- 作業P: あらかじめ定めた同じ飛行経路を、繰り返し高い再現性で"
                "飛行したい\n"
                "- 作業Q: 複雑な構造物の近くで、状況に応じた細かな機体操作を"
                "行いたい\n\n"
                "教則に示されたmanual / automatic controlの特徴に最も合う組合せは"
                "どれか。"
            ),
            "choice1": "Pは自動操縦、Qは熟練した操縦者による手動操縦",
            "choice2": "Pは手動操縦、Qは自動操縦",
            "choice3": "PもQも、再現性と細かな操作の双方に優れるため自動操縦",
            "correct_choice": "A",
            "explanation": (
                "教則では、自動操縦は事前設定したwaypoint等を用いることで高い再現性"
                "を求める飛行に適する。一方、熟練した操縦者によるmanual controlは、"
                "複雑な構造物の点検など、状況の変化に応じた細かな操作に向く。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(1)「手動操縦・自動操縦の特徴とメリット」"
                "（教則表示ページ59 / PDF viewer 65）"
            ),
        },
        "DRONE-Q-000087": {
            "slot_id": "VS-087",
            "kt_id": "D3-T02-KT010",
            "coverage": "COV-43",
            "question": (
                "無人航空機が墜落した。機体はまだ通電している可能性があり、プロペラ"
                "も回転している可能性がある。\n\n事故直後の現場での対応順序として、"
                "教則に最も合うものはどれか。"
            ),
            "choice1": (
                "まず機体へ近づいて電源やプロペラの状態を確認し、その後に周囲の人の"
                "安全を確認する"
            ),
            "choice2": (
                "まず人の安全を確認し、その後、必要に応じて機体の電源を切るなど周囲"
                "への危険を抑え、回転中のプロペラには不用意に近づかない"
            ),
            "choice3": (
                "まず機体の飛行logや損傷状態を確認して事故原因を整理し、その後に人と"
                "機体の安全を確認する"
            ),
            "correct_choice": "B",
            "explanation": (
                "事故を起こした場合、教則は人の安全確認を第一としている。その後、"
                "墜落した機体が通電している場合は電源を切るなど周囲への危険を防止し、"
                "プロペラがまだ回っている場合は不用意に機体へ接近しないよう求めて"
                "いる。"
            ),
            "source_locator": (
                "教則 第2章 2.3.1「事故を起こしたら」"
                "（教則表示ページ6 / PDF viewer 12）"
            ),
        },
        "DRONE-Q-000088": {
            "slot_id": "VS-088",
            "kt_id": "D3-T04-KT001",
            "coverage": "COV-44",
            "question": (
                "操縦者のtechnical skillを高めていても、人間の特性や能力の限界から"
                "human errorを完全になくすことはできない。\n\nCRMの考え方に最も合う"
                "運航体制はどれか。"
            ),
            "choice1": (
                "操縦者のtechnical skillを中心に運航し、他のresourceは問題が起きた"
                "場合にだけ利用する"
            ),
            "choice2": (
                "最新のinformationを中心に判断し、人的resourceやhardwareは判断材料"
                "を増やしすぎないよう限定する"
            ),
            "choice3": (
                "利用可能な人的resource、hardware、informationを総合的に活用する"
            ),
            "correct_choice": "C",
            "explanation": (
                "CRMでは、technical skillの向上だけではhuman errorを完全に排除でき"
                "ないことを前提に、利用可能な人的resource、hardware、informationを"
                "総合的に活用する。一つのresourceだけへ依存する考え方ではない。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1 CRM（教則表示ページ62 / PDF viewer 68）"
            ),
        },
        "DRONE-Q-000089": {
            "slot_id": "VS-089",
            "kt_id": "D3-T04-KT004",
            "coverage": "COV-45",
            "question": (
                "複数の補助者を配置して運航を行うことになった。\n\n操縦者と補助者の"
                "coordinationとして、教則に最も合うものはどれか。"
            ),
            "choice1": (
                "飛行前に補助者の人数・配置・担当範囲・役割・異常運航時の対応方法を"
                "決め、操縦者との連絡方法もあらかじめ定める"
            ),
            "choice2": (
                "飛行前は補助者の人数と配置だけを決め、担当範囲や連絡方法は飛行中の"
                "状況に合わせてその都度決める"
            ),
            "choice3": (
                "連絡方法だけを飛行前に決め、各補助者の担当範囲や役割は必要になった"
                "段階で決める"
            ),
            "correct_choice": "A",
            "explanation": (
                "補助者を使用する場合、教則は飛行経路や範囲に応じて補助者の人数、"
                "配置、担当範囲、役割、異常運航時の対応方法をあらかじめ決めるととも"
                "に、操縦者とのcommunicationも事前に定めた手段で行うとしている。"
            ),
            "source_locator": (
                "教則 第5章 5.4.2"
                "「安全な運航のための補助者の必要性、役割及び配置」"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
        },
    }
    B1A_EXPECTATIONS = {
        "DRONE-Q-000006": {
            "correct_choice": "B",
            "source_locator": "教則 第6章 6.1.4（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-002",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D4-T01-KT001",
                "family=H2",
                "variant=primary",
            ),
        },
        "DRONE-Q-000007": {
            "correct_choice": "C",
            "source_locator": "教則 第6章 6.1.4（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-003",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D4-T01-KT001",
                "family=H2",
                "alternate_of=VS-002",
            ),
        },
        "DRONE-Q-000008": {
            "correct_choice": "A",
            "source_locator": "教則 第6章 6.1.5（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-015",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D4-T01-KT001",
                "family=H5",
            ),
        },
        "DRONE-Q-000009": {
            "correct_choice": "C",
            "source_locator": "教則 第6章 6.1.5（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-021",
                "primary_role=DEEP_REPLICATION_A",
                "kt_id=D4-T01-KT001",
                "family=H3",
                "form=A",
            ),
        },
        "DRONE-Q-000010": {
            "correct_choice": "B",
            "source_locator": "教則 第6章 6.1.5（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-022",
                "primary_role=DEEP_REPLICATION_B",
                "kt_id=D4-T01-KT001",
                "family=H4",
                "form=B",
            ),
        },
    }
    B1B_EXPECTATIONS = {
        "DRONE-Q-000011": {
            "unit_id": "drone_rules",
            "correct_choice": "B",
            "source_locator": (
                "教則 第3章 3.1.2(2)4)a(2)"
                "（教則表示ページ19 / PDF viewer 25）"
            ),
            "notes": (
                "slot_id=VS-005",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D1-T01-KT010",
                "family=T2",
                "variant=primary",
            ),
        },
        "DRONE-Q-000012": {
            "unit_id": "drone_rules",
            "correct_choice": "C",
            "source_locator": (
                "教則 第3章 3.1.2(2)4)a(2)"
                "（教則表示ページ19 / PDF viewer 25）"
            ),
            "notes": (
                "slot_id=VS-006",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D1-T01-KT010",
                "family=T2",
                "alternate_of=VS-005",
            ),
        },
        "DRONE-Q-000013": {
            "unit_id": "drone_rules",
            "correct_choice": "A",
            "source_locator": (
                "教則 第3章 3.1.2(2)4)a(2)①"
                "（教則表示ページ19 / PDF viewer 25）"
            ),
            "notes": (
                "slot_id=VS-016",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D1-T01-KT010",
                "family=T3",
                "ordinary_shielding_exception=true",
                "level_3_5=false",
            ),
        },
        "DRONE-Q-000014": {
            "unit_id": "drone_systems",
            "correct_choice": "C",
            "source_locator": (
                "教則 第4章 4.5.3(3)（教則表示ページ50 / PDF viewer 56）; "
                "supporting 4.5.1(1)2)"
                "（教則表示ページ47 / PDF viewer 53）"
            ),
            "notes": (
                "slot_id=VS-007",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D2-T05-KT011",
                "family=G1",
                "variant=primary",
            ),
        },
        "DRONE-Q-000015": {
            "unit_id": "drone_systems",
            "correct_choice": "A",
            "source_locator": (
                "教則 第4章 4.5.3(3)"
                "（教則表示ページ50 / PDF viewer 56）"
            ),
            "notes": (
                "slot_id=VS-008",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D2-T05-KT011",
                "family=G2",
            ),
        },
        "DRONE-Q-000016": {
            "unit_id": "drone_systems",
            "correct_choice": "B",
            "source_locator": (
                "教則 第4章 4.5.3(3)（教則表示ページ50 / PDF viewer 56）; "
                "supporting 4.5.1(1)2)"
                "（教則表示ページ47 / PDF viewer 53）"
            ),
            "notes": (
                "slot_id=VS-009",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D2-T05-KT011",
                "family=G1",
                "alternate_of=VS-007",
            ),
        },
        "DRONE-Q-000017": {
            "unit_id": "drone_systems",
            "correct_choice": "C",
            "source_locator": (
                "教則 第4章 4.5.3(3)"
                "（教則表示ページ50 / PDF viewer 56）"
            ),
            "notes": (
                "slot_id=VS-017",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D2-T05-KT011",
                "family=G3",
            ),
        },
    }
    B1C_EXPECTATIONS = {
        "DRONE-Q-000018": {
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
            "notes": (
                "slot_id=VS-010",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T02-KT008",
                "family=A1",
                "construct=transition_trigger",
            ),
        },
        "DRONE-Q-000019": {
            "correct_choice": "A",
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
            "notes": (
                "slot_id=VS-011",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T02-KT008",
                "family=A4",
                "construct=takeover_preparedness",
            ),
        },
        "DRONE-Q-000020": {
            "correct_choice": "C",
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
            "notes": (
                "slot_id=VS-018",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D3-T02-KT008",
                "family=A2",
                "construct=immediate_flight_control_concern",
            ),
        },
        "DRONE-Q-000021": {
            "correct_choice": "A",
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）; "
                "supporting 4.1.4(1)"
                "（教則表示ページ35 / PDF viewer 41）"
            ),
            "notes": (
                "slot_id=VS-019",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D3-T02-KT008",
                "family=A3",
                "construct=situational_verification",
                "aircraft_scope=multirotor",
            ),
        },
        "DRONE-Q-000022": {
            "correct_choice": "A",
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
            "notes": (
                "slot_id=VS-012",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T04-KT002",
                "family=E1",
                "variant=primary",
                "construct=stage_classification",
            ),
        },
        "DRONE-Q-000023": {
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
            "notes": (
                "slot_id=VS-013",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T04-KT002",
                "family=E2",
                "construct=early_threat_management",
            ),
        },
        "DRONE-Q-000024": {
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
            "notes": (
                "slot_id=VS-014",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T04-KT002",
                "family=E1",
                "alternate_of=VS-012",
                "construct=stage_classification",
            ),
        },
        "DRONE-Q-000025": {
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
            "notes": (
                "slot_id=VS-020",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D3-T04-KT002",
                "family=E3",
                "construct=recovery_judgment",
            ),
        },
    }
    B2A_EXPECTATIONS = {
        "DRONE-Q-000026": {
            "unit_id": "drone_rules",
            "correct_choice": "A",
            "source_locator": (
                "教則 第3章 3.1.2(2)1)c"
                "（教則表示ページ15 / PDF viewer 21）"
            ),
            "notes": (
                "slot_id=VS-023",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D1-T01-KT006",
                "family=HB1-150",
                "construct=terrain_reference_airspace_classification",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000027": {
            "unit_id": "drone_rules",
            "correct_choice": "B",
            "source_locator": (
                "教則 第3章 3.1.2(2)1)d"
                "（教則表示ページ15 / PDF viewer 21）"
            ),
            "notes": (
                "slot_id=VS-030",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D1-T01-KT006",
                "family=HB1-DID",
                "construct=did_industrial_only_zone_exception",
                "counterbalance=YES",
                "additional_authority=MLIT_NOTICE_435",
                "notice_promulgated=2026-03-31",
                "mlit_web_announcement=2026-06-30",
            ),
        },
        "DRONE-Q-000028": {
            "unit_id": "drone_rules",
            "correct_choice": "B",
            "source_locator": (
                "教則 第3章 3.1 飛行形態の分類"
                "（教則表示ページ8–9 / PDF viewer 14–15）"
            ),
            "notes": (
                "slot_id=VS-024",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D1-T01-KT009",
                "family=HB2-II-III",
                "construct=category_ii_vs_iii_classification",
                "counterbalance=PARTIAL_ONLY",
            ),
        },
        "DRONE-Q-000029": {
            "unit_id": "drone_rules",
            "correct_choice": "A",
            "source_locator": (
                "教則 第3章 3.1 飛行形態の分類"
                "（教則表示ページ9 / PDF viewer 15）"
            ),
            "notes": (
                "slot_id=VS-031",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D1-T01-KT009",
                "family=HB2-IIA-IIB",
                "construct=category_iia_vs_iib_classification",
                "counterbalance=PARTIAL_ONLY",
            ),
        },
        "DRONE-Q-000030": {
            "unit_id": "drone_rules",
            "correct_choice": "A",
            "source_locator": (
                "教則 第3章 3.1.2(2)3)c"
                "（教則表示ページ18 / PDF viewer 24）"
            ),
            "notes": (
                "slot_id=VS-025",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D1-T01-KT015",
                "family=HB3-CONDITIONS",
                "construct=tether_exception_qualification",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000031": {
            "unit_id": "drone_rules",
            "correct_choice": "C",
            "source_locator": (
                "教則 第3章 3.1.2(2)3)c"
                "（教則表示ページ18 / PDF viewer 24）"
            ),
            "notes": (
                "slot_id=VS-032",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D1-T01-KT015",
                "family=HB3-TOWING",
                "construct=towing_nonexample_boundary",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000032": {
            "unit_id": "drone_systems",
            "correct_choice": "B",
            "source_locator": (
                "教則 第4章 4.6.1(2)"
                "（教則表示ページ50 / PDF viewer 56）"
            ),
            "notes": (
                "slot_id=VS-026",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D2-T06-KT002",
                "family=HB4-STORAGE",
                "construct=long_term_storage_charge",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000033": {
            "unit_id": "drone_systems",
            "correct_choice": "C",
            "source_locator": (
                "教則 第4章 4.6.1(3)"
                "（教則表示ページ51 / PDF viewer 57）"
            ),
            "notes": (
                "slot_id=VS-033",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D2-T06-KT002",
                "family=HB4-REPLACEMENT",
                "construct=swelling_replacement_decision",
                "counterbalance=YES",
            ),
        },
    }
    B2B_EXPECTATIONS = {
        "DRONE-Q-000034": {
            "unit_id": "drone_operations",
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.3.1（教則表示ページ61 / PDF viewer 67）"
            ),
            "notes": (
                "slot_id=VS-034",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D3-T03-KT001",
                "family=Stress-management",
                "construct=stress_management_plan",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000035": {
            "unit_id": "drone_risk_management",
            "correct_choice": "B",
            "source_locator": (
                "教則 第6章 6.2.2(1)2)h"
                "（教則表示ページ73 / PDF viewer 79）"
            ),
            "notes": (
                "slot_id=VS-028",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D4-T02-KT005",
                "family=Building-terrain-local-wind",
                "construct=spatial_local_wind_interpretation",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000036": {
            "unit_id": "drone_risk_management",
            "correct_choice": "B",
            "source_locator": (
                "教則 第6章 6.2.2(1)2)c–d"
                "（教則表示ページ72 / PDF viewer 78）"
            ),
            "notes": (
                "slot_id=VS-035",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D4-T02-KT005",
                "family=Gust-rapid-change",
                "construct=temporal_wind_variability_interpretation",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000037": {
            "unit_id": "drone_risk_management",
            "correct_choice": "C",
            "source_locator": (
                "教則 第6章 6.4.2(1)1)"
                "（教則表示ページ79 / PDF viewer 85）"
            ),
            "notes": (
                "slot_id=VS-029",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D4-T04-KT002",
                "family=Observer-external-monitoring",
                "construct=external_monitoring_control",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000038": {
            "unit_id": "drone_risk_management",
            "correct_choice": "C",
            "source_locator": (
                "教則 第6章 6.4.2(1)1)"
                "（教則表示ページ79 / PDF viewer 85）"
            ),
            "notes": (
                "slot_id=VS-036",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D4-T04-KT002",
                "family=Aircraft-state-monitoring",
                "construct=aircraft_state_monitoring",
                "counterbalance=YES",
            ),
        },
    }
    B2B_REGISTRY_NOTES = {
        "DRONE-Q-000034": (
            "VS-034; B2B HB5 stress; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000035": (
            "VS-028; B2B HB6 building-terrain; BREADTH_OBSERVED; permanent ID; "
            "pre-release"
        ),
        "DRONE-Q-000036": (
            "VS-035; B2B HB6 gust; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000037": (
            "VS-029; B2B HB7 observer; BREADTH_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000038": (
            "VS-036; B2B HB7 state; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
    }
    B2B_PAIR_EXPECTATIONS = (
        (
            "DRONE-Q-000003",
            "DRONE-Q-000034",
            "D3-T03-KT001",
            "Fatigue-management",
            "Stress-management",
        ),
        (
            "DRONE-Q-000035",
            "DRONE-Q-000036",
            "D4-T02-KT005",
            "Building-terrain-local-wind",
            "Gust-rapid-change",
        ),
        (
            "DRONE-Q-000037",
            "DRONE-Q-000038",
            "D4-T04-KT002",
            "Observer-external-monitoring",
            "Aircraft-state-monitoring",
        ),
    )
    B2B_CONTENT_FREEZE_EXPECTATIONS = {
        "DRONE-Q-000034": {
            "question": (
                "操縦者が高いストレスを抱えている状態で運航を行うことになった。"
                "\nストレス軽減を運航へ取り入れる方法として、教則の内容に"
                "最も合うものはどれか。"
            ),
            "choice1": (
                "操縦者との適切なコミュニケーションは飛行前の準備時に行い、"
                "飛行中・飛行後は当初の運航計画を基準に対応する"
            ),
            "choice2": (
                "操縦者との適切なコミュニケーションを一連の運航の計画に"
                "組み込み、ストレス軽減を図る"
            ),
            "choice3": (
                "操縦者との適切なコミュニケーションは飛行後の振り返りに重点を"
                "置き、次回の運航計画でストレス軽減を図る"
            ),
            "correct_choice": "B",
            "explanation": (
                "高いstressは安全な飛行を妨げる要因となるため、教則は操縦者との"
                "適切なcommunicationを、飛行計画・運航体制・飛行前・飛行中・"
                "飛行後などを含む一連の運航の計画に組み込む等によりstress軽減を"
                "図るとしている。"
            ),
            "source_locator": (
                "教則 第5章 5.3.1（教則表示ページ61 / PDF viewer 67）"
            ),
        },
        "DRONE-Q-000035": {
            "question": (
                "飛行予定地点から少し離れた開けた場所では風が穏やかである。"
                "一方、実際の飛行予定地点は高層建物が複数近接している場所で"
                "ある。\n飛行予定地点の風の捉え方として、教則の内容に最も合う"
                "ものはどれか。"
            ),
            "choice1": (
                "開けた場所の風向・風速を、建物周辺にもそのまま適用して評価する"
            ),
            "choice2": (
                "建物群の配置によって周囲とは異なるビル風が生じ得るため、"
                "建物周辺の風を別に考慮する"
            ),
            "choice3": (
                "建物周辺の風は建物配置より広域の平均風速で決まるため、"
                "局地的な差は考慮しない"
            ),
            "correct_choice": "B",
            "explanation": (
                "教則は、高層ビル等が近接する場所・周辺ではビル風が発生し、"
                "周囲より風速が速く継続して吹くことや、建物群の配置・構成により"
                "風の特徴が異なるとしている。"
            ),
            "source_locator": (
                "教則 第6章 6.2.2(1)2)h"
                "（教則表示ページ73 / PDF viewer 79）"
            ),
        },
        "DRONE-Q-000036": {
            "question": (
                "ある地点の風について、観測時の前10分間の平均風速は4m/sだった"
                "一方、最大瞬間風速は9m/sだった。\nこの観測結果の捉え方として、"
                "教則の内容に最も合うものはどれか。"
            ),
            "choice1": (
                "平均風速が4m/sであれば、その観測時間中の風は概ね4m/sだった"
                "ものとして瞬間値は分けて考えなくてよい"
            ),
            "choice2": (
                "平均風速と瞬間風速は異なるため、平均値だけでは一時的に強くなる"
                "風の変動を十分に表せない"
            ),
            "choice3": (
                "最大瞬間風速9m/sを観測時間全体の風速として扱い、平均風速は"
                "判断材料から外す"
            ),
            "correct_choice": "B",
            "explanation": (
                "風は一定の強さで吹き続けるとは限らず、教則は10分間の平均風速と"
                "最大瞬間風速を区別している。そのため、平均値だけでは時間内の"
                "一時的な強い風まで表せない。"
            ),
            "source_locator": (
                "教則 第6章 6.2.2(1)2)c–d"
                "（教則表示ページ72 / PDF viewer 78）"
            ),
        },
        "DRONE-Q-000037": {
            "question": (
                "補助者を配置して目視外飛行を行う。操縦者からは飛行経路やその"
                "周囲の障害物等を直接肉眼で確認できない。\nこの情報不足を補う"
                "ための補助者の配置として、教則の内容に最も合うものはどれか。"
            ),
            "choice1": (
                "離着陸地点を重点的に確認できる位置に配置し、飛行中の経路は"
                "事前確認の情報を用いる"
            ),
            "choice2": (
                "操縦者付近から見える範囲を確認できる位置に配置し、それ以外の"
                "経路は機体カメラを中心に確認する"
            ),
            "choice3": "飛行経路全体を把握し、安全を確認できる補助者を配置する",
            "correct_choice": "C",
            "explanation": (
                "目視外飛行では、機体の状況や障害物等の周囲状況を直接肉眼で"
                "確認できないため、教則は飛行経路全体を把握し、安全を確認できる"
                "補助者の配置を推奨している。"
            ),
            "source_locator": (
                "教則 第6章 6.4.2(1)1)"
                "（教則表示ページ79 / PDF viewer 85）"
            ),
        },
        "DRONE-Q-000038": {
            "question": (
                "補助者を配置して目視外飛行を行う場合、機体について地上側で把握"
                "できるようにする情報として、教則の内容に最も合うものはどれか。"
            ),
            "choice1": (
                "機体の位置を把握できればよく、異常の有無は飛行後に確認する"
            ),
            "choice2": (
                "異常の有無を把握できればよく、機体の位置は飛行後の記録で確認する"
            ),
            "choice3": (
                "機体の位置と異常の有無の双方を地上で把握できるようにする"
            ),
            "correct_choice": "C",
            "explanation": (
                "補助者を配置して行う目視外飛行について、教則は地上で無人航空機"
                "の位置および異常の有無を把握できることを求めている。"
            ),
            "source_locator": (
                "教則 第6章 6.4.2(1)1)"
                "（教則表示ページ79 / PDF viewer 85）"
            ),
        },
    }
    HB5_EXISTING_FREEZE_EXPECTATION = {
        "question": (
            "操縦者は同じ日に複数回の飛行を行い、疲労を感じ始めている。"
            "これまで操作ミスはなく、機体・気象・飛行経路にも問題は確認されて"
            "いない。教則に沿った対応として、最も適切なものはどれか。"
        ),
        "choice1": (
            "本人がまだ安全に操縦できると判断しているため、当初の運航予定を"
            "維持し、疲労は運航終了後に評価する"
        ),
        "choice2": (
            "機体・気象・飛行経路に問題がないため、当初の飛行時間計画を維持し、"
            "各飛行終了後に疲労を評価する"
        ),
        "choice3": (
            "疲労時は飛行を続ける判断に偏りやすいことを踏まえ、当初計画に"
            "固定せず飛行時間を管理する"
        ),
        "correct_choice": "C",
        "explanation": (
            "現行教則第5版は、操縦者には疲労を感じても飛行を継続してしまう傾向"
            "があるため、適切な飛行時間管理が必要としている。Aは本人の主観的な"
            "継続判断を、Bは当初計画をそれぞれ疲労管理より優先している。"
        ),
        "source_locator": (
            "教則 第5章 5.3.1（教則表示ページ61 / PDF viewer 67）"
        ),
        "notes_internal": (
            "slot_id=VS-027; verification_state=author_source_verified; "
            "primary_role=BREADTH_OBSERVED; kt_id=D3-T03-KT001; "
            "family=Fatigue-management; independent_reviewed=false; "
            "subject_matter_expert_reviewed=false; release_approved=false"
        ),
    }
    B2A_REGISTRY_NOTES = {
        "DRONE-Q-000026": (
            "VS-023; B2A HB1 150m; BREADTH_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000027": (
            "VS-030; B2A HB1 DID; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000028": (
            "VS-024; B2A HB2 II-III; BREADTH_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000029": (
            "VS-031; B2A HB2 IIA-IIB; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000030": (
            "VS-025; B2A HB3 conditions; BREADTH_OBSERVED; permanent ID; "
            "pre-release"
        ),
        "DRONE-Q-000031": (
            "VS-032; B2A HB3 towing; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000032": (
            "VS-026; B2A HB4 storage; BREADTH_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000033": (
            "VS-033; B2A HB4 replacement; BREADTH_HELDOUT; permanent ID; "
            "pre-release"
        ),
    }
    B2A_PAIR_EXPECTATIONS = (
        ("DRONE-Q-000026", "DRONE-Q-000027", "D1-T01-KT006", "YES"),
        (
            "DRONE-Q-000028",
            "DRONE-Q-000029",
            "D1-T01-KT009",
            "PARTIAL_ONLY",
        ),
        ("DRONE-Q-000030", "DRONE-Q-000031", "D1-T01-KT015", "YES"),
        ("DRONE-Q-000032", "DRONE-Q-000033", "D2-T06-KT002", "YES"),
    )
    B1C_REGISTRY_NOTES = {
        "DRONE-Q-000018": (
            "VS-010; B1C A1; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000019": (
            "VS-011; B1C A4; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000020": (
            "VS-018; B1C A2; DEEP_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000021": (
            "VS-019; B1C A3; DEEP_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000022": (
            "VS-012; B1C E1 primary; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000023": (
            "VS-013; B1C E2; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000024": (
            "VS-014; B1C E1 alternate; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000025": (
            "VS-020; B1C E3; DEEP_HELDOUT; permanent ID; pre-release"
        ),
    }
    B2A_CONTENT_FREEZE_EXPECTATIONS = {
        "DRONE-Q-000026": {
            "question": (
                "離陸地点から130m上方を飛行している無人航空機がある。現在の"
                "機体直下の地表は、離陸地点の地表より40m低い。\n\n"
                "このとき「高度150m以上の空域」の判定として最も適切なものは"
                "どれか。"
            ),
            "choice1": "高度150m以上の空域に該当する",
            "choice2": "離陸地点からの高度差が130mなので該当しない",
            "choice3": "海抜高度が示されていないため判定できない",
            "correct_choice": "A",
            "explanation": (
                "150mの基準は離陸地点や海抜高度ではなく、飛行中の機体直下の"
                "地表・水面との高度差である。この場合、その高度差は170mになる。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)1)c"
                "（教則表示ページ15 / PDF viewer 21）"
            ),
        },
        "DRONE-Q-000027": {
            "question": (
                "地図上では人口集中地区（DID）として表示されている区域で飛行を"
                "計画している。確認したところ、その場所は都市計画法第8条第1項"
                "第1号の工業専用地域内である。\n\n他の規制対象空域や飛行方法"
                "には該当しないものとすると、DIDに係る扱いとして最も適切な"
                "ものはどれか。"
            ),
            "choice1": (
                "地図上でDIDと表示されているため、DIDに係る許可手続き等が"
                "必要である"
            ),
            "choice2": (
                "工業専用地域内の除外区域に該当するため、DIDに係る許可手続き等"
                "は不要である"
            ),
            "choice3": (
                "DIDに係る許可手続き等の要否は、操縦者が技能証明を保有して"
                "いるかだけで決まる"
            ),
            "correct_choice": "B",
            "explanation": (
                "現行制度では、都市計画法上の工業専用地域内の区域は「人又は"
                "家屋の密集している地域」から除外され、DIDに係る飛行許可は"
                "不要となる。その他の空域・飛行方法の規制は別途判定する。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)1)d"
                "（教則表示ページ15 / PDF viewer 21）"
            ),
        },
        "DRONE-Q-000028": {
            "question": (
                "ある特定飛行について、飛行経路下に第三者が立ち入らないよう"
                "立入管理措置を講じたうえで飛行する。\n\nこの飛行形態の分類"
                "として最も適切なものはどれか。"
            ),
            "choice1": "カテゴリーI",
            "choice2": "カテゴリーII",
            "choice3": "カテゴリーIII",
            "correct_choice": "B",
            "explanation": (
                "特定飛行のうち、飛行経路下への第三者の立入りを管理する措置を"
                "講じて行うものがCategory IIである。Category IIIは、そのような"
                "立入管理措置を講じず第三者上空で行う特定飛行である。"
            ),
            "source_locator": (
                "教則 第3章 3.1 飛行形態の分類"
                "（教則表示ページ8–9 / PDF viewer 14–15）"
            ),
        },
        "DRONE-Q-000029": {
            "question": (
                "いずれも立入管理措置を講じ、最大離陸重量25kg未満の無人航空機"
                "で行う特定飛行とする。また、記載した条件以外にカテゴリーII-A"
                "に該当する条件はないものとする。\n\n- 飛行X：危険物を輸送する"
                "\n- 飛行Y：夜間に飛行する\n\nカテゴリーII-A / II-Bの分類"
                "として最も適切なものはどれか。"
            ),
            "choice1": "X = II-A、Y = II-B",
            "choice2": "X = II-B、Y = II-A",
            "choice3": "X = II-A、Y = II-A",
            "correct_choice": "A",
            "explanation": (
                "Category IIのうち危険物輸送はII-Aに含まれる。一方、25kg未満で、"
                "他のII-A条件に該当しない夜間飛行は「その他のCategory II」"
                "としてII-Bに分類される。"
            ),
            "source_locator": (
                "教則 第3章 3.1 飛行形態の分類"
                "（教則表示ページ9 / PDF viewer 15）"
            ),
        },
        "DRONE-Q-000030": {
            "question": (
                "係留飛行の例外に必要な条件の組合せとして、教則に最も合うものは"
                "どれか。"
            ),
            "choice1": (
                "十分な強度の25mの紐で係留し、飛行可能範囲への第三者の"
                "立入管理措置を講じる"
            ),
            "choice2": (
                "十分な強度の35mの紐で係留し、飛行可能範囲への第三者の"
                "立入管理措置を講じる"
            ),
            "choice3": (
                "十分な強度の25mの紐で係留するが、飛行可能範囲への第三者の"
                "立入管理措置は講じない"
            ),
            "correct_choice": "A",
            "explanation": (
                "係留飛行の例外では、十分な強度を持つ30m以下の紐等による係留と、"
                "飛行可能範囲への第三者立入管理等が条件となる。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)3)c"
                "（教則表示ページ18 / PDF viewer 24）"
            ),
        },
        "DRONE-Q-000031": {
            "question": (
                "無人航空機を紐につなぎ、その紐を操縦者が手に持って歩いて移動"
                "しながら飛行させている。\n\nこの飛行の扱いとして、教則に"
                "最も合うものはどれか。"
            ),
            "choice1": (
                "無人航空機が紐につながっているため、係留飛行として扱う"
            ),
            "choice2": "操縦者が紐を直接管理しているため、係留飛行として扱う",
            "choice3": (
                "人が紐を持って移動しながら行う飛行はえい航であり、係留には"
                "該当しない"
            ),
            "correct_choice": "C",
            "explanation": (
                "人が紐等を持って移動しながら無人航空機を飛行させる行為は"
                "えい航であり、係留には該当しない。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)3)c"
                "（教則表示ページ18 / PDF viewer 24）"
            ),
        },
        "DRONE-Q-000032": {
            "question": (
                "LiPoバッテリーを長期間使用しない場合の保管方法として、教則に"
                "最も合うものはどれか。"
            ),
            "choice1": "満充電にして保管する",
            "choice2": "充電60%程度を目安にして保管する",
            "choice3": "飛行終了後の放電状態のまま保管する",
            "correct_choice": "B",
            "explanation": (
                "長期間使用しない場合は、劣化を遅らせるため充電60%程度を目安に"
                "保管する。満充電状態や飛行後の放電状態での長期保管は避ける。"
            ),
            "source_locator": (
                "教則 第4章 4.6.1(2)"
                "（教則表示ページ50 / PDF viewer 56）"
            ),
        },
        "DRONE-Q-000033": {
            "question": (
                "飛行前点検でLiPoバッテリーが膨らんでいることに気付いた。充電"
                "自体は可能で、直前の飛行でも大きな容量低下は感じていない。"
                "\n\n教則に沿った対応として最も適切なものはどれか。"
            ),
            "choice1": (
                "充放電できる間は使用を続け、飛行時間を短くして経過を見る"
            ),
            "choice2": (
                "膨張の程度を記録し、容量低下が明確になった時点で交換する"
            ),
            "choice3": (
                "内部に可燃性ガスが発生している可能性を考慮し、早めに交換する"
            ),
            "correct_choice": "C",
            "explanation": (
                "教則では、LiPoが膨らんでいる場合は内部に可燃性ガスが発生して"
                "いる可能性があるため、早めに交換するとしている。"
            ),
            "source_locator": (
                "教則 第4章 4.6.1(3)"
                "（教則表示ページ51 / PDF viewer 57）"
            ),
        },
    }
    B1C_CONTENT_FREEZE_EXPECTATIONS = {
        "DRONE-Q-000018": {
            "question": (
                "自動操縦で飛行している無人航空機について、飛行状態が次第に"
                "不安定になり、操縦者も「安定した自動飛行を維持できていない」"
                "と判断した。\n\n教則の考え方に最も合う判断はどれか。"
            ),
            "choice1": "自動操縦の設定を変更しながら、まず現在のmodeを維持する",
            "choice2": (
                "不安定な飛行と判断した状況として、手動操作への切り替えを"
                "検討する"
            ),
            "choice3": (
                "不安定となった原因を特定してから、操縦modeを変更するか決める"
            ),
            "correct_choice": "B",
            "explanation": (
                "教則は、自動操縦中に何らかの原因で不安定な飛行と判断した"
                "場合を、手動操作へ切り替える場合の一つとして示している。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
        },
        "DRONE-Q-000019": {
            "question": (
                "自動操縦を中心とする飛行を計画している。飛行中には状況変化に"
                "よって手動操縦への切り替えが必要になる可能性もある。\n\n"
                "事前の運航体制として教則の考え方に最も合うものはどれか。"
            ),
            "choice1": (
                "必要となった場合に速やかに手動操縦へ切り替えられる体制を"
                "事前に整えておく"
            ),
            "choice2": (
                "状況変化が起きた時点で、その場の状況に合わせて手動切替の"
                "対応方法を組み立てる"
            ),
            "choice3": (
                "自動操縦を継続できるかの判断方法を事前に決め、手動切替の体制は"
                "必要になった後に整える"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則は、必要に応じて手動操縦への切り替えを速やかに行える"
                "体制をあらかじめ整えておくとしている。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
        },
        "DRONE-Q-000020": {
            "question": (
                "自動操縦から手動操縦へ切り替えた直後である。切り替え自体は"
                "正常に完了した。\n\nこの直後の操縦上の備えとして、教則が示す"
                "内容に最も合うものはどれか。"
            ),
            "choice1": (
                "自動操縦中の設定値を確認し、手動操作の入力値をそれに合わせる"
                "ことを優先する"
            ),
            "choice2": (
                "現在位置と飛行計画上の予定位置との差を確認し、経路修正を"
                "優先する"
            ),
            "choice3": "急な飛行速度の低下や失速に備えた操作準備を行う",
            "correct_choice": "C",
            "explanation": (
                "教則は、手動操縦へ切り替えた後、急な飛行速度の低下や失速に"
                "備えた操作準備が必要としている。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
        },
        "DRONE-Q-000021": {
            "question": (
                "ホバリングが可能な回転翼航空機（マルチローター）を、自動操縦"
                "から手動操縦へ切り替えた。切り替えを終え、飛行速度についても"
                "安定した状態を確認している。\n\nこの後の確認として、教則の内容に"
                "最も合うものはどれか。"
            ),
            "choice1": (
                "機体の向きと障害物への接近を確認し、ホバリングで機体の安定性と"
                "周囲の安全を確認する"
            ),
            "choice2": (
                "自動操縦時のroute設定と予定速度を確認し、自動操縦へ戻す条件を"
                "整理する"
            ),
            "choice3": (
                "送信機のflight logと作業進捗を確認し、予定経路との差を記録する"
            ),
            "correct_choice": "A",
            "explanation": (
                "手動操縦への切り替え後は、障害物への接近を避けるための機体方向"
                "確認に加え、ホバリングして機体の安定性や周囲の安全を確認する"
                "必要がある。今回の機体はホバリング可能なマルチローターとして"
                "stemで固定している。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）; "
                "supporting 4.1.4(1)"
                "（教則表示ページ35 / PDF viewer 41）"
            ),
        },
        "DRONE-Q-000022": {
            "question": (
                "飛行中、次の二つの状態が生じた。\n\n"
                "① 周囲の気象状況が変化し、運航へ影響を及ぼし得る状況となった。"
                "\n\n② その後、運航上の問題を経て、機体の安全マージンが低下した"
                "状態に至った。\n\nTEMにおける①と②の分類として、最も適切な"
                "ものはどれか。"
            ),
            "choice1": "① Threat ／ ② UAS",
            "choice2": "① Threat ／ ② Error",
            "choice3": "① Error ／ ② UAS",
            "correct_choice": "A",
            "explanation": (
                "教則は気象の変化をErrorにつながり得るThreatの例として挙げて"
                "いる。また、安全マージンが低下した航空機の状態をUASとしている。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
        },
        "DRONE-Q-000023": {
            "question": (
                "飛行中、飛行空域周辺の最新情報から天候が変化しつつあることを"
                "把握した。まだ操縦上のErrorやUASは生じていない。\n\n"
                "TEMの考え方に最も合う対応はどれか。"
            ),
            "choice1": (
                "実際の操縦Errorが確認されるまでは初期計画を基準とし、天候情報は"
                "継続監視にとどめる"
            ),
            "choice2": (
                "利用可能な最新情報等を使い、Errorにつながり得るThreatとして"
                "早期に把握・管理する"
            ),
            "choice3": (
                "機体がUASに入ったかどうかを確認してから、天候変化への対応を"
                "開始する"
            ),
            "correct_choice": "B",
            "explanation": (
                "TEMでは、利用可能なresourceを活用して、Errorにつながりかねない"
                "Threatの発生状況を早期に把握・管理する。教則は周辺状況の最新情報"
                "などをresourceの例としている。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
        },
        "DRONE-Q-000024": {
            "question": (
                "ある飛行の運航記録に、次の二つの状態が記録されていた。\n\n"
                "記録P：飛行中に機材不具合が発生した。\n\n"
                "記録Q：その後、機体は安全マージンが低下した状態に至った。\n\n"
                "TEMにおけるPとQの分類として、最も適切なものはどれか。"
            ),
            "choice1": "P = Error ／ Q = UAS",
            "choice2": "P = Threat ／ Q = UAS",
            "choice3": "P = Threat ／ Q = Error",
            "correct_choice": "B",
            "explanation": (
                "教則は機材不具合をErrorにつながり得るThreatの例として挙げて"
                "いる。また、安全マージンが低下した航空機の状態はUASに"
                "位置付けられる。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
        },
        "DRONE-Q-000025": {
            "question": (
                "運航中に操縦Errorが発生し、機体は安全マージンの低下したUASに"
                "至った。ただし、まだ事故等は発生していない。\n\n"
                "TEMの考え方に最も合うものはどれか。"
            ),
            "choice1": (
                "まず最初のThreatの原因分析を完了し、その後に機体状態への対応を"
                "決める"
            ),
            "choice2": (
                "ErrorやUASに至った後でも、事故等へ進ませないための適切な対応を"
                "行う"
            ),
            "choice3": (
                "UASに至った段階でTEMによるmanagementは終了し、その後は運航"
                "終了後の分析を中心とする"
            ),
            "correct_choice": "B",
            "explanation": (
                "TEMはThreatの早期管理だけでなく、万一ErrorやUASに至った場合でも"
                "事故等へ至らないよう適切に対処する考え方を含む。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
        },
    }
    B1B_CONTENT_FREEZE_EXPECTATIONS = {
        "DRONE-Q-000012": {
            "question": (
                "飛行範囲の外周からの保証された落下距離が6mである。\n\n"
                "飛行に関与しない第三者Xは、飛行範囲の外周の最も近い点から"
                "外側へ4m、第三者Yは、外側へ9m離れた位置にいる。どちらも"
                "飛行経路の直下ではなく、遮蔽物については考慮しないものとする。"
                "\n\n第三者上空の判定として適切なものはどれか。"
            ),
            "choice1": "XとYの両方について、第三者上空に該当する",
            "choice2": "Yについてのみ、第三者上空に該当する",
            "choice3": "Xについてのみ、第三者上空に該当する",
        },
        "DRONE-Q-000014": {
            "question": (
                "飛行中、GNSSの測位精度が不安定になった。捕捉している衛星数は"
                "十分で、受信環境のノイズも大きくない。一方、周囲の建物で反射"
                "した衛星信号が、複数の経路から受信機へ届いている。\n\n"
                "この状況から直接読み取れる、測位精度へ影響している要因として"
                "最も適切なものはどれか。"
            ),
        },
        "DRONE-Q-000016": {
            "question": (
                "同じ無人航空機のGNSS受信状態を、同じ時間帯に2か所で確認した。"
                "\n\n地点Pは上空が開け、周囲に大きな建物が少ない。地点Qは周囲"
                "に建物が多く、建物で反射した衛星信号が複数の経路から受信機へ"
                "届き得る環境である。捕捉している衛星数と受信環境のノイズには、"
                "2地点で大きな差は確認されていない。\n\n地点QでGNSS測位精度が"
                "悪化した場合、この状況から直接考えられる要因として最も適切な"
                "ものはどれか。"
            ),
        },
    }

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        source = REPOSITORY_ROOT / "question_banks" / "drone_second_class"
        self.bank = Path(self.temporary_directory.name) / "drone_second_class"
        shutil.copytree(source, self.bank)

    @property
    def questions_path(self) -> Path:
        return self.bank / "authoring" / "questions.csv"

    @property
    def registry_path(self) -> Path:
        return self.bank / "authoring" / "question_id_registry.csv"

    def _read_csv(self, path: Path) -> tuple[list[str], list[dict[str, str]]]:
        with path.open(newline="", encoding="utf-8") as file:
            reader = csv.DictReader(file)
            return list(reader.fieldnames or []), list(reader)

    def _write_csv(
        self,
        path: Path,
        fieldnames: list[str],
        rows: list[dict[str, str]],
    ) -> None:
        with path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def _error_codes(self) -> set[str]:
        return {issue.code for issue in validate_bank(self.bank).errors}

    def test_drone_namespace_preserves_permanent_mappings_and_invariants(self) -> None:
        result = validate_bank(self.bank)
        self.assertTrue(result.is_valid, [str(issue) for issue in result.issues])

        inputs = load_bank_inputs(self.bank)
        question_ids = [row["question_id"] for row in inputs.questions]
        registry_ids = [row["question_id"] for row in inputs.id_registry]
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        self.assertEqual(len(question_ids), len(set(question_ids)))
        self.assertEqual(len(registry_ids), len(set(registry_ids)))
        self.assertEqual(
            set(question_ids),
            set(self.PERMANENT_SLOT_TO_ID.values()),
        )
        self.assertTrue(set(question_ids).issubset(registry_ids))
        self.assertTrue(
            all(
                QUESTION_ID_PATTERN.fullmatch(question_id)
                for question_id in question_ids
            )
        )
        self.assertTrue(all(row["status"] == "used" for row in inputs.id_registry))
        self.assertTrue(
            all(not row["first_used_bank_revision"] for row in inputs.id_registry)
        )
        self.assertEqual(inputs.metadata["app_key"], "drone_second_class")
        self.assertEqual(inputs.metadata["question_identity_policy"], "explicit_v1")
        self.assertEqual(inputs.released_questions, [])

        for slot_id, question_id in self.PERMANENT_SLOT_TO_ID.items():
            self.assertIn(question_id, question_by_id)
            self.assertIn(question_id, registry_by_id)
            self.assertIn(
                f"slot_id={slot_id}", question_by_id[question_id]["notes_internal"]
            )
            self.assertIn(slot_id, registry_by_id[question_id]["notes"])

        for question_id, expected in self.B1A_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(
                question["correct_choice"], expected["correct_choice"]
            )
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(
                question["source_locator"], expected["source_locator"]
            )
            self.assertIn(
                "verification_state=author_source_verified",
                question["notes_internal"],
            )
            self.assertIn(
                "independent_reviewed=false", question["notes_internal"]
            )
            self.assertIn(
                "subject_matter_expert_reviewed=false",
                question["notes_internal"],
            )
            self.assertIn("release_approved=false", question["notes_internal"])
            for note in expected["notes"]:
                self.assertIn(note, question["notes_internal"])

        for question_id, expected in self.B1B_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], expected["unit_id"])
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-18")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["correct_choice"], expected["correct_choice"])
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(question["source_locator"], expected["source_locator"])
            self.assertIn(
                "verification_state=author_source_verified",
                question["notes_internal"],
            )
            self.assertIn("independent_reviewed=false", question["notes_internal"])
            self.assertIn(
                "subject_matter_expert_reviewed=false",
                question["notes_internal"],
            )
            self.assertIn("release_approved=false", question["notes_internal"])
            for note in expected["notes"]:
                self.assertIn(note, question["notes_internal"])

        held_out_t3 = question_by_id["DRONE-Q-000013"]
        self.assertNotIn("level_3_5=true", held_out_t3["notes_internal"])
        self.assertNotIn("moving_vehicle=", held_out_t3["notes_internal"])

        for question_id, fields in self.B1B_CONTENT_FREEZE_EXPECTATIONS.items():
            question = question_by_id[question_id]
            for field, expected_text in fields.items():
                self.assertEqual(question[field], expected_text)

        sentinel = question_by_id["DRONE-Q-000004"]
        sentinel_neighbor = question_by_id["DRONE-Q-000005"]
        self.assertIn("slot_id=VS-039", sentinel["notes_internal"])
        self.assertIn("family=US-C", sentinel["notes_internal"])
        self.assertIn("slot_id=VS-069", sentinel_neighbor["notes_internal"])
        self.assertIn("coverage=COV-25", sentinel_neighbor["notes_internal"])
        neighbor_content = " ".join(
            sentinel_neighbor[field]
            for field in (
                "question",
                "choice1",
                "choice2",
                "choice3",
                "choice4",
                "explanation",
            )
        ).casefold()
        forbidden_terms = (
            "送信機",
            "受信機",
            "transmitter",
            "receiver",
            "remote command",
        )
        for forbidden in forbidden_terms:
            self.assertNotIn(forbidden, neighbor_content)

    def test_b1c_measurement_bindings_and_content_freeze(self) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        for question_id, expected in self.B1C_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], "drone_operations")
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-18")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["correct_choice"], expected["correct_choice"])
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(question["source_locator"], expected["source_locator"])
            self.assertIn(
                "verification_state=author_source_verified",
                question["notes_internal"],
            )
            self.assertIn("independent_reviewed=false", question["notes_internal"])
            self.assertIn(
                "subject_matter_expert_reviewed=false",
                question["notes_internal"],
            )
            self.assertIn("release_approved=false", question["notes_internal"])
            for note in expected["notes"]:
                self.assertIn(note, question["notes_internal"])

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(registry["notes"], self.B1C_REGISTRY_NOTES[question_id])

        for question_id, fields in self.B1C_CONTENT_FREEZE_EXPECTATIONS.items():
            question = question_by_id[question_id]
            for field, expected_text in fields.items():
                self.assertEqual(question[field], expected_text)

        vs_019 = question_by_id["DRONE-Q-000021"]
        self.assertIn(
            "ホバリングが可能な回転翼航空機（マルチローター）",
            vs_019["question"],
        )
        self.assertIn("5.2.2(4)", vs_019["source_locator"])
        self.assertIn("4.1.4(1)", vs_019["source_locator"])

        vs_012 = question_by_id["DRONE-Q-000022"]
        self.assertNotIn("操作上のエラーが生じた", vs_012["question"])

        vs_014 = question_by_id["DRONE-Q-000024"]
        self.assertIn("機材不具合", vs_014["question"])
        self.assertNotIn("操縦者の疲労という", vs_014["question"])

    def test_b2a_measurement_bindings_and_content_freeze(self) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        for question_id, expected in self.B2A_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], expected["unit_id"])
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-18")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["correct_choice"], expected["correct_choice"])
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(question["source_locator"], expected["source_locator"])
            self.assertIn(
                "verification_state=author_source_verified",
                question["notes_internal"],
            )
            self.assertIn("independent_reviewed=false", question["notes_internal"])
            self.assertIn(
                "subject_matter_expert_reviewed=false",
                question["notes_internal"],
            )
            self.assertIn("release_approved=false", question["notes_internal"])
            for note in expected["notes"]:
                self.assertIn(note, question["notes_internal"])

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(registry["notes"], self.B2A_REGISTRY_NOTES[question_id])

        for question_id, fields in self.B2A_CONTENT_FREEZE_EXPECTATIONS.items():
            question = question_by_id[question_id]
            for field, expected_text in fields.items():
                self.assertEqual(question[field], expected_text)

        for observed_id, held_out_id, kt_id, counterbalance in (
            self.B2A_PAIR_EXPECTATIONS
        ):
            observed_notes = question_by_id[observed_id]["notes_internal"]
            held_out_notes = question_by_id[held_out_id]["notes_internal"]
            self.assertIn("primary_role=BREADTH_OBSERVED", observed_notes)
            self.assertIn("primary_role=BREADTH_HELDOUT", held_out_notes)
            for notes in (observed_notes, held_out_notes):
                self.assertIn(f"kt_id={kt_id}", notes)
                self.assertIn(f"counterbalance={counterbalance}", notes)

        vs_032 = question_by_id["DRONE-Q-000031"]
        vs_032_content = " ".join(
            vs_032[field]
            for field in (
                "question",
                "choice1",
                "choice2",
                "choice3",
                "explanation",
            )
        )
        for leaked_condition in ("第三者の立入管理", "30m", "十分な強度"):
            self.assertNotIn(leaked_condition, vs_032_content)

        vs_030 = question_by_id["DRONE-Q-000027"]
        self.assertIn(
            "他の規制対象空域や飛行方法には該当しないものとすると",
            vs_030["question"],
        )
        self.assertIn(
            "その他の空域・飛行方法の規制は別途判定する",
            vs_030["explanation"],
        )
        vs_030_metadata = {
            key: value
            for item in vs_030["notes_internal"].split(";")
            if "=" in item
            for key, value in (item.strip().split("=", 1),)
        }
        self.assertEqual(
            vs_030_metadata["additional_authority"], "MLIT_NOTICE_435"
        )
        self.assertEqual(vs_030_metadata["notice_promulgated"], "2026-03-31")
        self.assertEqual(vs_030_metadata["mlit_web_announcement"], "2026-06-30")
        self.assertNotEqual(
            vs_030_metadata["notice_promulgated"],
            vs_030_metadata["mlit_web_announcement"],
        )

    def test_b2b_measurement_bindings_and_content_freeze(self) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        for question_id, expected in self.B2B_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], expected["unit_id"])
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-18")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["correct_choice"], expected["correct_choice"])
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(question["source_locator"], expected["source_locator"])
            self.assertIn(
                "verification_state=author_source_verified",
                question["notes_internal"],
            )
            self.assertIn("independent_reviewed=false", question["notes_internal"])
            self.assertIn(
                "subject_matter_expert_reviewed=false",
                question["notes_internal"],
            )
            self.assertIn("release_approved=false", question["notes_internal"])
            for note in expected["notes"]:
                self.assertIn(note, question["notes_internal"])

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(registry["notes"], self.B2B_REGISTRY_NOTES[question_id])

        for question_id, fields in self.B2B_CONTENT_FREEZE_EXPECTATIONS.items():
            question = question_by_id[question_id]
            for field, expected_text in fields.items():
                self.assertEqual(question[field], expected_text)

        existing_hb5 = question_by_id["DRONE-Q-000003"]
        for field, expected_text in self.HB5_EXISTING_FREEZE_EXPECTATION.items():
            self.assertEqual(existing_hb5[field], expected_text)
        self.assertEqual(
            registry_by_id["DRONE-Q-000003"]["notes"],
            "VS-027; permanent ID; pre-release",
        )
        self.assertNotIn("counterbalance=", existing_hb5["notes_internal"])

        for (
            observed_id,
            held_out_id,
            kt_id,
            observed_family,
            held_out_family,
        ) in self.B2B_PAIR_EXPECTATIONS:
            observed_notes = question_by_id[observed_id]["notes_internal"]
            held_out_notes = question_by_id[held_out_id]["notes_internal"]
            self.assertIn("primary_role=BREADTH_OBSERVED", observed_notes)
            self.assertIn("primary_role=BREADTH_HELDOUT", held_out_notes)
            self.assertIn(f"kt_id={kt_id}", observed_notes)
            self.assertIn(f"kt_id={kt_id}", held_out_notes)
            self.assertIn(f"family={observed_family}", observed_notes)
            self.assertIn(f"family={held_out_family}", held_out_notes)
            self.assertIn("counterbalance=YES", held_out_notes)
            if observed_id != "DRONE-Q-000003":
                self.assertIn("counterbalance=YES", observed_notes)

        def content(question_id: str) -> str:
            question = question_by_id[question_id]
            return " ".join(
                question[field]
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "explanation",
                )
            )

        vs_034 = question_by_id["DRONE-Q-000034"]
        for choice_field in ("choice1", "choice2", "choice3"):
            self.assertIn(
                "操縦者との適切なコミュニケーション",
                vs_034[choice_field],
            )
        for forbidden in (
            "アルコール",
            "飲酒",
            "残存アルコール",
            "酒気",
            "薬物",
            "sleep",
            "睡眠",
            "TEM",
            "CRM",
        ):
            self.assertNotIn(forbidden.casefold(), content("DRONE-Q-000034").casefold())

        for question_id in ("DRONE-Q-000035", "DRONE-Q-000036"):
            for forbidden in (
                "温度",
                "低温",
                "高温",
                "バッテリー",
                "battery",
                "thermal",
                "熱環境",
                "energy margin",
            ):
                self.assertNotIn(forbidden.casefold(), content(question_id).casefold())

        for forbidden in ("最大瞬間風速", "10分間の平均風速"):
            self.assertNotIn(forbidden, content("DRONE-Q-000035"))
        for forbidden in ("ビル風", "高層建物", "建物群", "地形"):
            self.assertNotIn(forbidden, content("DRONE-Q-000036"))

        vs_029 = question_by_id["DRONE-Q-000037"]
        self.assertEqual(
            vs_029["choice3"],
            "飛行経路全体を把握し、安全を確認できる補助者を配置する",
        )
        self.assertNotIn(
            "安全を確認できる位置に補助者を配置する",
            vs_029["choice3"],
        )
        for forbidden in ("機体の位置", "異常の有無", "telemetry", "GNSS"):
            self.assertNotIn(
                forbidden.casefold(),
                content("DRONE-Q-000037").casefold(),
            )
        for forbidden in (
            "飛行経路全体",
            "障害物",
            "補助者とのcommunication",
        ):
            self.assertNotIn(
                forbidden.casefold(),
                content("DRONE-Q-000038").casefold(),
            )

        for question_id in self.B2B_CONTENT_FREEZE_EXPECTATIONS:
            for forbidden in ("〔一等〕", "[一等]"):
                self.assertNotIn(forbidden, content(question_id))

        for question_id in ("DRONE-Q-000037", "DRONE-Q-000038"):
            for forbidden in (
                "通信断",
                "GNSS failure",
                "battery failure",
                "RTH",
                "自動帰還",
                "自動着陸",
                "hover on failure",
                "failsafe",
                "フェイルセーフ",
            ):
                self.assertNotIn(
                    forbidden.casefold(),
                    content(question_id).casefold(),
                )

    def test_b3a_clean_sentinel_metadata_content_and_regressions(self) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        for question_id, expected in self.B3A_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], expected["unit_id"])
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-19")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(question["notes_internal"], expected["notes_internal"])
            metadata = {
                key: value
                for item in question["notes_internal"].split(";")
                if "=" in item
                for key, value in (item.strip().split("=", 1),)
            }
            self.assertEqual(metadata["slot_id"], expected["slot_id"])
            self.assertEqual(metadata["primary_role"], expected["primary_role"])
            self.assertEqual(metadata["kt_id"], expected["kt_id"])
            self.assertEqual(metadata["family"], expected["family"])
            self.assertEqual(metadata["verification_state"], "author_source_verified")
            self.assertEqual(metadata["independent_reviewed"], "false")
            self.assertEqual(metadata["subject_matter_expert_reviewed"], "false")
            self.assertEqual(metadata["release_approved"], "false")

            for field, expected_text in expected["content"].items():
                self.assertEqual(question[field], expected_text)

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(registry["notes"], self.B3A_REGISTRY_NOTES[question_id])

        def content(question_id: str) -> str:
            question = question_by_id[question_id]
            return " ".join(
                question[field]
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "explanation",
                )
            )

        for forbidden in (
            "飛行日誌",
            "日常点検記録",
            "点検整備記録",
            "充電60%",
            "60%",
            "膨ら",
            "事故報告",
        ):
            self.assertNotIn(forbidden, content("DRONE-Q-000039"))

        for forbidden in (
            "罰則",
            "行政処分",
            "血中アルコール",
            "呼気アルコール",
            "依存症",
            "必ず",
            "義務",
            "mandatory",
        ):
            self.assertNotIn(
                forbidden.casefold(),
                content("DRONE-Q-000040").casefold(),
            )

        for existing_id in ("DRONE-Q-000003", "DRONE-Q-000034"):
            existing_notes = question_by_id[existing_id]["notes_internal"]
            for forbidden in (
                "slot_id=VS-042",
                "primary_role=UNKNOWN_SENTINEL",
                "kt_id=D3-T03-KT002",
                "family=US-F",
            ):
                self.assertNotIn(forbidden, existing_notes)

    def test_b3b_routed_sentinel_metadata_content_and_regressions(self) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        for question_id, expected in self.B3B_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], expected["unit_id"])
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-19")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(question["notes_internal"], expected["notes_internal"])
            metadata = {
                key: value
                for item in question["notes_internal"].split(";")
                if "=" in item
                for key, value in (item.strip().split("=", 1),)
            }
            self.assertEqual(metadata["slot_id"], expected["slot_id"])
            self.assertEqual(metadata["primary_role"], expected["primary_role"])
            self.assertEqual(metadata["kt_id"], expected["kt_id"])
            self.assertEqual(metadata["family"], expected["family"])
            self.assertEqual(metadata["verification_state"], "author_source_verified")
            self.assertEqual(metadata["independent_reviewed"], "false")
            self.assertEqual(metadata["subject_matter_expert_reviewed"], "false")
            self.assertEqual(metadata["release_approved"], "false")

            for field, expected_text in expected["content"].items():
                self.assertEqual(question[field], expected_text)

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(registry["notes"], self.B3B_REGISTRY_NOTES[question_id])

        magnetic = question_by_id["DRONE-Q-000043"]
        magnetic_correct_proposition = " ".join(
            magnetic[field] for field in ("choice1", "explanation")
        )
        for required in (
            "地磁気を検出して方位を取得",
            "GNSS機能やメインコントローラーに認識",
        ):
            self.assertIn(required, magnetic_correct_proposition)
        for forbidden in (
            "磁気干渉の強さを測定",
            "再キャリブレーション",
            "キャリブレーション失敗",
            "方位誤差",
            "メーカー",
        ):
            self.assertNotIn(forbidden, magnetic_correct_proposition)

        def content(question_id: str) -> str:
            question = question_by_id[question_id]
            return " ".join(
                question[field]
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "explanation",
                )
            )

        for forbidden in ("現在指定されている緊急用務空域", "dynamic snapshot"):
            self.assertNotIn(forbidden, content("DRONE-Q-000041"))
        for forbidden in ("DIPS", "飛行計画通報"):
            self.assertNotIn(forbidden, content("DRONE-Q-000042"))
        self.assertNotIn("事故発生後", content("DRONE-Q-000044"))
        for forbidden in ("battery chemistry", "バッテリー化学"):
            self.assertNotIn(forbidden, content("DRONE-Q-000045"))

    def test_b4_d1_coverage_metadata_content_and_semantic_regressions(self) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        for question_id, expected in self.B4_D1_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], "drone_rules")
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-19")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")

            for field in (
                "question",
                "choice1",
                "choice2",
                "choice3",
                "correct_choice",
                "explanation",
                "source_locator",
            ):
                self.assertEqual(question[field], expected[field])

            metadata = {
                key: value
                for item in question["notes_internal"].split(";")
                if "=" in item
                for key, value in (item.strip().split("=", 1),)
            }
            self.assertEqual(metadata["slot_id"], expected["slot_id"])
            self.assertEqual(metadata["verification_state"], "author_source_verified")
            self.assertEqual(metadata["primary_role"], "COVERAGE")
            self.assertEqual(metadata["kt_id"], expected["kt_id"])
            self.assertEqual(metadata["coverage"], expected["coverage"])
            self.assertEqual(metadata["independent_reviewed"], "false")
            self.assertEqual(metadata["subject_matter_expert_reviewed"], "false")
            self.assertEqual(metadata["release_approved"], "false")
            if "supporting_authority" in expected:
                self.assertEqual(
                    metadata["supporting_authority"],
                    expected["supporting_authority"],
                )
            else:
                self.assertNotIn("supporting_authority", metadata)

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(
                registry["notes"],
                f'{expected["slot_id"]}; B4 D1 {expected["coverage"]}; '
                "COVERAGE; permanent ID; pre-release",
            )

        correct_distribution = {
            answer: sum(
                expected["correct_choice"] == answer
                for expected in self.B4_D1_EXPECTATIONS.values()
            )
            for answer in ("A", "B", "C")
        }
        self.assertEqual(correct_distribution, {"A": 8, "B": 5, "C": 1})

        def content(question_id: str) -> str:
            question = question_by_id[question_id]
            return " ".join(
                question[field]
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "explanation",
                )
            )

        cov_01_correct = " ".join(
            question_by_id["DRONE-Q-000046"][field]
            for field in ("choice1", "explanation")
        )
        for required in ("75g＋30g＝105g", "無人航空機に該当"):
            self.assertIn(required, cov_01_correct)
        self.assertNotIn("緊急用務空域", content("DRONE-Q-000046"))

        self.assertIn(
            "カテゴリーII-B飛行であることが確認済み",
            question_by_id["DRONE-Q-000049"]["question"],
        )

        cov_05_correct = question_by_id["DRONE-Q-000050"]["choice1"]
        for required in ("夜間", "目視外", "物件投下"):
            self.assertIn(required, cov_05_correct)
        for forbidden in ("飛行日誌", "飛行記録", "日常点検記録", "点検整備記録"):
            self.assertNotIn(forbidden, content("DRONE-Q-000050"))

        cov_08_correct = " ".join(
            question_by_id["DRONE-Q-000053"][field]
            for field in ("choice2", "explanation")
        )
        for required in ("通報した飛行計画に従", "安全確保のためやむを得ない"):
            self.assertIn(required, cov_08_correct)
        for forbidden in ("飛行日誌", "飛行記録", "日常点検記録", "点検整備記録"):
            self.assertNotIn(forbidden, content("DRONE-Q-000053"))

        cov_09_correct = " ".join(
            question_by_id["DRONE-Q-000054"][field]
            for field in ("question", "choice2", "explanation")
        )
        for required in ("特定航空用機器", "パラグライダー"):
            self.assertIn(required, cov_09_correct)
        for forbidden in ("100g未満", "緊急用務空域"):
            self.assertNotIn(forbidden, content("DRONE-Q-000054"))

        for required in ("Red Zone", "Yellow Zone", "1,000m"):
            self.assertIn(required, content("DRONE-Q-000055"))

        cov_12_correct = question_by_id["DRONE-Q-000057"]["choice1"]
        for required in (
            "Pは無線局免許等・無線従事者資格とも不要",
            "Qは無線局免許を要し",
            "第三級陸上特殊無線技士以上",
        ):
            self.assertIn(required, cov_12_correct)

        cov_13_correct = " ".join(
            question_by_id["DRONE-Q-000058"][field]
            for field in ("choice3", "explanation")
        )
        for required in ("航空法以外", "地方公共団体の条例"):
            self.assertIn(required, cov_13_correct)

        cov_14_correct = " ".join(
            question_by_id["DRONE-Q-000059"][field]
            for field in ("choice2", "explanation")
        )
        for required in ("法令等に基づく規制ではな", "飛行前"):
            self.assertIn(required, cov_14_correct)
        self.assertNotIn("緊急用務空域", content("DRONE-Q-000059"))

    def test_b5_d2a_coverage_metadata_content_and_semantic_regressions(
        self,
    ) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        expected_mapping = {
            expected["slot_id"]: question_id
            for question_id, expected in self.B5_D2A_EXPECTATIONS.items()
        }
        self.assertEqual(
            expected_mapping,
            {
                "VS-059": "DRONE-Q-000060",
                "VS-060": "DRONE-Q-000061",
                "VS-061": "DRONE-Q-000062",
                "VS-062": "DRONE-Q-000063",
                "VS-063": "DRONE-Q-000064",
                "VS-064": "DRONE-Q-000065",
                "VS-065": "DRONE-Q-000066",
                "VS-066": "DRONE-Q-000067",
                "VS-067": "DRONE-Q-000068",
                "VS-068": "DRONE-Q-000069",
            },
        )

        for question_id, expected in self.B5_D2A_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], "drone_systems")
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-19")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")

            for field in (
                "question",
                "choice1",
                "choice2",
                "choice3",
                "correct_choice",
                "explanation",
                "source_locator",
            ):
                self.assertEqual(question[field], expected[field])

            metadata = {
                key: value
                for item in question["notes_internal"].split(";")
                if "=" in item
                for key, value in (item.strip().split("=", 1),)
            }
            self.assertEqual(metadata["slot_id"], expected["slot_id"])
            self.assertEqual(metadata["verification_state"], "author_source_verified")
            self.assertEqual(metadata["primary_role"], "COVERAGE")
            self.assertEqual(metadata["kt_id"], expected["kt_id"])
            self.assertEqual(metadata["coverage"], expected["coverage"])
            self.assertEqual(metadata["independent_reviewed"], "false")
            self.assertEqual(metadata["subject_matter_expert_reviewed"], "false")
            self.assertEqual(metadata["release_approved"], "false")

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(
                registry["notes"],
                f'{expected["slot_id"]}; B5 D2-A {expected["coverage"]}; '
                "COVERAGE; permanent ID; pre-release",
            )

        correct_distribution = {
            answer: sum(
                expected["correct_choice"] == answer
                for expected in self.B5_D2A_EXPECTATIONS.values()
            )
            for answer in ("A", "B", "C")
        }
        self.assertEqual(correct_distribution, {"A": 8, "B": 2, "C": 0})

        def content(question_id: str) -> str:
            question = question_by_id[question_id]
            return " ".join(
                question[field]
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "explanation",
                )
            )

        def correct_and_explanation(question_id: str) -> str:
            question = question_by_id[question_id]
            correct_field = f'choice{"ABC".index(question["correct_choice"]) + 1}'
            return " ".join((question[correct_field], question["explanation"]))

        cov_16_correct = correct_and_explanation("DRONE-Q-000061")
        for required in ("スワッシュプレート", "ローター回転面", "ローターピッチ角"):
            self.assertIn(required, cov_16_correct)
        for forbidden in ("ヨーを制御", "反トルクを相殺"):
            self.assertNotIn(forbidden, cov_16_correct)

        cov_17_correct = correct_and_explanation("DRONE-Q-000062")
        for required in (
            "右側のローターの回転数を下げ",
            "左側のローターの回転数を上げ",
        ):
            self.assertIn(required, cov_17_correct)
        for forbidden in ("受信機", "メインコントローラー", "ジャイロセンサ"):
            self.assertNotIn(forbidden, content("DRONE-Q-000062"))

        for required in ("ビジョンセンサー", "夜間", "衝突回避"):
            self.assertIn(required, content("DRONE-Q-000063"))
        for forbidden in ("すべてのセンサー", "GNSSは夜間"):
            self.assertNotIn(forbidden, content("DRONE-Q-000063"))

        cov_19_correct = correct_and_explanation("DRONE-Q-000064")
        for required in ("搭載カメラ", "速度", "地上で把握"):
            self.assertIn(required, content("DRONE-Q-000064"))
        for forbidden in (
            "既存itemと分離するため",
            "primary state variable",
            "最も重要",
            "補助者",
        ):
            self.assertNotIn(forbidden, cov_19_correct)
        self.assertNotIn("位置と異常の有無", cov_19_correct)
        self.assertNotIn("failsafe", cov_19_correct)

        for required in ("無線通信が断絶", "自動的に戻る", "位置を維持"):
            self.assertIn(required, content("DRONE-Q-000065"))
        for forbidden in (
            "always RTH",
            "必ず自動帰還",
            "specific return altitude",
        ):
            self.assertNotIn(forbidden, content("DRONE-Q-000065"))

        for required in ("揚力", "重力", "推力", "抗力"):
            self.assertIn(required, content("DRONE-Q-000066"))
        for forbidden in ("4.3.5", "計算式"):
            self.assertNotIn(forbidden, content("DRONE-Q-000066"))

        for required in (
            "過度に大きな迎角",
            "流れが剥離",
            "揚力が減少",
            "抗力が増大",
            "失速",
        ):
            self.assertIn(required, content("DRONE-Q-000067"))
        self.assertNotIn("迎角を増やすと直ちに失速", content("DRONE-Q-000067"))

        for required in ("一般的な回転翼航空機", "反トルク", "テールローター", "ヨー"):
            self.assertIn(required, content("DRONE-Q-000068"))
        self.assertNotIn("すべてのヘリコプター", content("DRONE-Q-000068"))
        self.assertNotIn("スワッシュプレート", content("DRONE-Q-000068"))

        for required in ("同じ重量", "重心位置", "安定性", "飛行性能", "運動性能"):
            self.assertIn(required, content("DRONE-Q-000069"))
        for forbidden in ("release mechanism", "numerical CG calculation"):
            self.assertNotIn(forbidden, content("DRONE-Q-000069"))

    def test_b6_d2b_coverage_metadata_content_and_semantic_regressions(
        self,
    ) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        expected_mapping = {
            expected["slot_id"]: question_id
            for question_id, expected in self.B6_D2B_EXPECTATIONS.items()
        }
        self.assertEqual(
            expected_mapping,
            {
                "VS-070": "DRONE-Q-000070",
                "VS-071": "DRONE-Q-000071",
                "VS-072": "DRONE-Q-000072",
                "VS-073": "DRONE-Q-000073",
                "VS-074": "DRONE-Q-000074",
                "VS-075": "DRONE-Q-000075",
                "VS-076": "DRONE-Q-000076",
                "VS-077": "DRONE-Q-000077",
                "VS-078": "DRONE-Q-000078",
                "VS-079": "DRONE-Q-000079",
            },
        )

        for question_id, expected in self.B6_D2B_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], "drone_systems")
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-19")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")

            for field in (
                "question",
                "choice1",
                "choice2",
                "choice3",
                "correct_choice",
                "explanation",
                "source_locator",
            ):
                self.assertEqual(question[field], expected[field])

            metadata = {
                key: value
                for item in question["notes_internal"].split(";")
                if "=" in item
                for key, value in (item.strip().split("=", 1),)
            }
            self.assertEqual(metadata["slot_id"], expected["slot_id"])
            self.assertEqual(metadata["verification_state"], "author_source_verified")
            self.assertEqual(metadata["primary_role"], "COVERAGE")
            self.assertEqual(metadata["kt_id"], expected["kt_id"])
            self.assertEqual(metadata["coverage"], expected["coverage"])
            self.assertEqual(metadata["independent_reviewed"], "false")
            self.assertEqual(metadata["subject_matter_expert_reviewed"], "false")
            self.assertEqual(metadata["release_approved"], "false")

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(
                registry["notes"],
                f'{expected["slot_id"]}; B6 D2-B {expected["coverage"]}; '
                "COVERAGE; permanent ID; pre-release",
            )

        correct_distribution = {
            answer: sum(
                expected["correct_choice"] == answer
                for expected in self.B6_D2B_EXPECTATIONS.values()
            )
            for answer in ("A", "B", "C")
        }
        self.assertEqual(correct_distribution, {"A": 4, "B": 4, "C": 2})

        def content(question_id: str) -> str:
            question = question_by_id[question_id]
            return " ".join(
                question[field]
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "explanation",
                )
            )

        def correct_and_explanation(question_id: str) -> str:
            question = question_by_id[question_id]
            correct_field = f'choice{"ABC".index(question["correct_choice"]) + 1}'
            return " ".join((question[correct_field], question["explanation"]))

        cov_26 = content("DRONE-Q-000070")
        for required in (
            "IMU",
            "3軸",
            "ジャイロセンサ",
            "加速度センサ",
            "角速度",
            "加速度",
        ):
            self.assertIn(required, cov_26)
        for forbidden in (
            "フライトコントロールシステムが姿勢制御",
            "磁気キャリブレーション",
        ):
            self.assertNotIn(forbidden, cov_26)

        cov_27 = content("DRONE-Q-000071")
        for required in ("ESC", "モーター", "回転数", "ローター", "揚力", "推力"):
            self.assertIn(required, cov_27)
        for forbidden in ("送信機", "受信機", "メインコントローラー", "ジャイロセンサ"):
            self.assertNotIn(forbidden, cov_27)

        cov_28 = content("DRONE-Q-000072")
        for required in ("LiPo", "短絡", "発火する可能性"):
            self.assertIn(required, cov_28)
        for forbidden in ("60%程度", "低温環境", "飛行可能時間"):
            self.assertNotIn(forbidden, cov_28)
        self.assertNotIn(
            "膨張したら交換",
            correct_and_explanation("DRONE-Q-000072"),
        )

        cov_29 = content("DRONE-Q-000073")
        for required in ("意図せず", "落下しない構造", "搭載方法", "投下手順"):
            self.assertIn(required, cov_29)
        for forbidden in ("重心位置", "安定性", "飛行性能", "運動性能"):
            self.assertNotIn(forbidden, cov_29)

        cov_30 = content("DRONE-Q-000074")
        for required in ("周波数が低く", "波長が長い", "回折", "障害物"):
            self.assertIn(required, cov_30)
        for forbidden in ("マルチパス", "無線局免許", "無線従事者"):
            self.assertNotIn(forbidden, cov_30)

        cov_31 = content("DRONE-Q-000075")
        for required in (
            "反射",
            "屈折",
            "複数の経路",
            "到達時間",
            "電波が弱く",
            "一時的に操縦不能",
        ):
            self.assertIn(required, cov_31)
        cov_31_answer = correct_and_explanation("DRONE-Q-000075")
        for required in ("電波が弱く", "一時的に操縦不能"):
            self.assertIn(required, cov_31_answer)
        for forbidden in ("GNSS測位精度", "Waypoint"):
            self.assertNotIn(forbidden, cov_31)

        cov_32 = content("DRONE-Q-000076")
        for required in ("鉄", "電流", "地磁気", "姿勢", "進行方向"):
            self.assertIn(required, cov_32)
        for forbidden in (
            "磁気キャリブレーション",
            "再キャリブレーション",
            "飛行場所の地磁気を検出して方位を取得",
            "GNSS機能やメインコントローラーに認識",
        ):
            self.assertNotIn(forbidden, cov_32)

        cov_33 = content("DRONE-Q-000077")
        for required in ("最低4個以上", "人工衛星", "同時", "距離", "位置"):
            self.assertIn(required, cov_33)
        for forbidden in ("マルチパス", "Waypoint"):
            self.assertNotIn(forbidden, cov_33)

        cov_34 = content("DRONE-Q-000078")
        for required in (
            "電動機",
            "飛行前後",
            "一定期間",
            "総飛行時間",
            "メーカー",
            "整備点検",
        ):
            self.assertIn(required, cov_34)
        for forbidden in ("専門の整備業者", "60%程度", "膨張", "運航終了後点検"):
            self.assertNotIn(forbidden, cov_34)

        cov_35 = content("DRONE-Q-000079")
        for required in ("エンジン", "十分な知識と技能がない", "専門の整備業者"):
            self.assertIn(required, cov_35)
        self.assertNotIn(
            "すべてのエンジン整備は専門の整備業者に依頼する",
            cov_35,
        )

    def test_b7_d3_coverage_metadata_content_and_semantic_regressions(
        self,
    ) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        expected_mapping = {
            expected["slot_id"]: question_id
            for question_id, expected in self.B7_D3_EXPECTATIONS.items()
        }
        self.assertEqual(
            expected_mapping,
            {
                "VS-080": "DRONE-Q-000080",
                "VS-081": "DRONE-Q-000081",
                "VS-082": "DRONE-Q-000082",
                "VS-083": "DRONE-Q-000083",
                "VS-084": "DRONE-Q-000084",
                "VS-085": "DRONE-Q-000085",
                "VS-086": "DRONE-Q-000086",
                "VS-087": "DRONE-Q-000087",
                "VS-088": "DRONE-Q-000088",
                "VS-089": "DRONE-Q-000089",
            },
        )

        for question_id, expected in self.B7_D3_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], "drone_operations")
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-19")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")

            for field in (
                "question",
                "choice1",
                "choice2",
                "choice3",
                "correct_choice",
                "explanation",
                "source_locator",
            ):
                self.assertEqual(question[field], expected[field])

            metadata = {
                key: value
                for item in question["notes_internal"].split(";")
                if "=" in item
                for key, value in (item.strip().split("=", 1),)
            }
            self.assertEqual(metadata["slot_id"], expected["slot_id"])
            self.assertEqual(metadata["verification_state"], "author_source_verified")
            self.assertEqual(metadata["primary_role"], "COVERAGE")
            self.assertEqual(metadata["kt_id"], expected["kt_id"])
            self.assertEqual(metadata["coverage"], expected["coverage"])
            self.assertEqual(metadata["independent_reviewed"], "false")
            self.assertEqual(metadata["subject_matter_expert_reviewed"], "false")
            self.assertEqual(metadata["release_approved"], "false")

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(
                registry["notes"],
                f'{expected["slot_id"]}; B7 D3 {expected["coverage"]}; '
                "COVERAGE; permanent ID; pre-release",
            )

        cov_39_metadata = {
            key: value
            for item in question_by_id["DRONE-Q-000083"]["notes_internal"].split(";")
            if "=" in item
            for key, value in (item.strip().split("=", 1),)
        }
        self.assertEqual(cov_39_metadata["sentinel_neighbor"], "US-B")
        self.assertEqual(
            cov_39_metadata["administration_route"],
            "after_us_b_sentinel_response",
        )

        correct_distribution = {
            answer: sum(
                expected["correct_choice"] == answer
                for expected in self.B7_D3_EXPECTATIONS.values()
            )
            for answer in ("A", "B", "C")
        }
        self.assertEqual(correct_distribution, {"A": 5, "B": 3, "C": 2})

        def content(question_id: str) -> str:
            question = question_by_id[question_id]
            return " ".join(
                question[field]
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "explanation",
                )
            )

        def correct_and_explanation(question_id: str) -> str:
            question = question_by_id[question_id]
            correct_field = f'choice{"ABC".index(question["correct_choice"]) + 1}'
            return " ".join((question[correct_field], question["explanation"]))

        cov_36 = content("DRONE-Q-000080")
        for required in (
            "必要な装置",
            "許可・承認",
            "機体登録",
            "有効期間",
            "最終確認",
        ):
            self.assertIn(required, cov_36)
        cov_36_answer = correct_and_explanation("DRONE-Q-000080")
        for forbidden in (
            "緊急着陸地点",
            "alternate landing",
            "発生頻度",
            "結果の重大性",
        ):
            self.assertNotIn(forbidden, cov_36_answer)

        cov_37 = content("DRONE-Q-000081")
        for required in (
            "機体",
            "バッテリー",
            "通信",
            "推進",
            "電源",
            "自動制御",
            "正常",
        ):
            self.assertIn(required, cov_37)
        cov_37_answer = correct_and_explanation("DRONE-Q-000081")
        for forbidden in ("運航終了後", "安全な保管", "総飛行時間"):
            self.assertNotIn(forbidden, cov_37_answer)

        cov_38 = content("DRONE-Q-000082")
        for required in (
            "許可・承認が必要",
            "申請",
            "審査",
            "許可・承認を得てから",
        ):
            self.assertIn(required, cov_38)
        for forbidden in ("UI button name", "screen path"):
            self.assertNotIn(forbidden.casefold(), cov_38.casefold())
        self.assertIn("既に確認済み", question_by_id["DRONE-Q-000082"]["question"])

        cov_39 = content("DRONE-Q-000083")
        for required in ("飛行計画", "通報済み", "更新", "飛行開始日時まで"):
            self.assertIn(required, cov_39)
        for forbidden in ("飛行日誌", "飛行記録", "日常点検記録", "点検整備記録"):
            self.assertNotIn(forbidden, cov_39)

        cov_40 = content("DRONE-Q-000084")
        for required in ("無人航空機本体", "遠隔操縦", "適切に管理", "盗難"):
            self.assertIn(required, cov_40)
        for forbidden in ("Red Zone", "Yellow Zone", "暗号化方式", "firmware"):
            self.assertNotIn(forbidden.casefold(), cov_40.casefold())

        cov_41 = content("DRONE-Q-000085")
        for required in (
            "マルチローター",
            "降下",
            "ボルテックス・リング・ステート",
            "水平方向",
        ):
            self.assertIn(required, cov_41)
        for forbidden in (
            "自動操縦から手動操縦",
            "切り替え直後",
            "ホバリングで安定性",
        ):
            self.assertNotIn(forbidden, cov_41)

        cov_42 = content("DRONE-Q-000086")
        for required in ("高い再現性", "自動操縦", "細かな操作", "手動操縦"):
            self.assertIn(required, cov_42)
        for forbidden in ("手動操縦へ切り替える", "失速に備える", "切替直後"):
            self.assertNotIn(forbidden, cov_42)

        cov_43 = content("DRONE-Q-000087")
        for required in ("人の安全", "電源を切る", "プロペラ", "不用意に近づかない"):
            self.assertIn(required, cov_43)
        for forbidden in ("国土交通大臣への報告", "緊急着陸地点", "alternate landing"):
            self.assertNotIn(forbidden, cov_43)

        cov_44 = content("DRONE-Q-000088")
        for required in (
            "technical skill",
            "人的resource",
            "hardware",
            "information",
            "総合的に活用",
        ):
            self.assertIn(required, cov_44)
        for forbidden in ("Threat", "Error", "UAS"):
            self.assertNotIn(forbidden, cov_44)

        cov_45 = content("DRONE-Q-000089")
        for required in (
            "補助者",
            "人数",
            "配置",
            "担当範囲",
            "役割",
            "異常運航時",
            "連絡方法",
            "あらかじめ",
        ):
            self.assertIn(required, cov_45)
        for forbidden in (
            "飛行経路全体を把握",
            "位置と異常の有無",
            "緊急着陸地点への誘導",
            "alternate landing site",
            "Threat",
            "Error",
            "UAS",
        ):
            self.assertNotIn(forbidden, cov_45)

    def test_unregistered_drone_id_is_rejected(self) -> None:
        fieldnames, rows = self._read_csv(self.questions_path)
        rows[0]["question_id"] = "DRONE-Q-999999"
        self._write_csv(self.questions_path, fieldnames, rows)

        self.assertIn("unregistered_question_id", self._error_codes())

    def test_retired_drone_id_reuse_is_rejected(self) -> None:
        fieldnames, rows = self._read_csv(self.registry_path)
        rows[0]["status"] = "retired"
        rows[0]["retired_at"] = "2026-08-18"
        self._write_csv(self.registry_path, fieldnames, rows)

        self.assertIn("retired_id_reuse", self._error_codes())

    def test_drone_bank_requires_explicit_identity(self) -> None:
        metadata_path = self.bank / "authoring" / "bank.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        metadata["question_identity_policy"] = "legacy_hash_v1"
        metadata_path.write_text(
            json.dumps(metadata, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )

        self.assertIn("identity_policy_not_explicit", self._error_codes())

    def test_drone_generation_is_deterministic_and_drafts_stay_out(self) -> None:
        first = build_generated_files(load_bank_inputs(self.bank))
        second = build_generated_files(load_bank_inputs(self.bank))
        self.assertEqual(first, second)

        write_generated_files(self.bank)
        checked = validate_bank(self.bank, check_generated=True)
        self.assertTrue(checked.is_valid, [str(issue) for issue in checked.issues])

        runtime = json.loads(
            (self.bank / "generated" / "drone_second_class_bank.json").read_text(
                encoding="utf-8"
            )
        )
        manifest = json.loads(
            (self.bank / "generated" / "bank_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(runtime["decks"], [])
        self.assertEqual(manifest["question_count"], 0)

    def test_qualification_fixture_remains_valid(self) -> None:
        fixture = REPOSITORY_ROOT / "question_banks" / "qualification_fixture"
        result = validate_bank(fixture, check_generated=True)
        self.assertTrue(result.is_valid, [str(issue) for issue in result.issues])


if __name__ == "__main__":
    unittest.main()
