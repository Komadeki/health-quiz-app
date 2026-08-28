from __future__ import annotations

import csv
import json
import sys
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "tooling" / "question_bank"))

from expansion import validate_expansion_batch  # noqa: E402


EARLY_EXPECTED = {
    "E1-B2-HH-C001": "EISEI1-Q-000001",
    "E1-B2-HH-C002": "EISEI1-Q-000002",
    "E1-B2-LH-C001": "EISEI1-Q-000003",
    "E1-B2-LH-C002": "EISEI1-Q-000004",
    "E1-B3-LH-C001": "EISEI1-Q-000005",
    "E1-B4-LH-C002": "EISEI1-Q-000006",
    "E1-B4-LH-C004": "EISEI1-Q-000007",
}
B6_EXPECTED = {"E1-B6-HH-C001": "EISEI1-Q-000008"}
B7_EXPECTED = {
    "E1-B7-LH-C001": "EISEI1-Q-000009",
    "E1-B7-LH-C002": "EISEI1-Q-000010",
}
B8_EXPECTED = {
    "E1-B8-HH-C001": "EISEI1-Q-000011",
    "E1-B8-HH-C002": "EISEI1-Q-000012",
    "E1-B8-LH-C001": "EISEI1-Q-000013",
}
B9_EXPECTED = {
    "E1-B9-LH-C001": "EISEI1-Q-000014",
    "E1-B9-LH-C002": "EISEI1-Q-000015",
    "E1-B9-LH-C003": "EISEI1-Q-000016",
}
B10_EXPECTED = {
    "E1-B10-HH-C001": "EISEI1-Q-000017",
    "E1-B10-HH-C002": "EISEI1-Q-000018",
    "E1-B10-LH-C001": "EISEI1-Q-000019",
    "E1-B10-LH-C002": "EISEI1-Q-000020",
    "E1-B10-LH-C003": "EISEI1-Q-000021",
    "E1-B10-LH-C004": "EISEI1-Q-000022",
}
B11_EXPECTED = {
    "E1-B11-LG-C001": "EISEI1-Q-000023",
    "E1-B11-LG-C002": "EISEI1-Q-000024",
    "E1-B11-LG-C003": "EISEI1-Q-000025",
}
B12_EXPECTED = {"E1-B12-HH-C001": "EISEI1-Q-000026", "E1-B12-HH-C002": "EISEI1-Q-000027", "E1-B12-HH-C003": "EISEI1-Q-000028"}
B13_EXPECTED = {"E1-B13-HG-C001": "EISEI1-Q-000029", "E1-B13-HG-C002": "EISEI1-Q-000030"}
B14_EXPECTED = {"E1-B14-PH-C001": "EISEI1-Q-000031", "E1-B14-PH-C002": "EISEI1-Q-000032"}
B15_EXPECTED = {"E1-B15-HH-C001": "EISEI1-Q-000033", "E1-B15-HH-C002": "EISEI1-Q-000034"}
B16_EXPECTED = {
    "E1-B16-HG-C001": "EISEI1-Q-000035",
    "E1-B16-HH-C001": "EISEI1-Q-000036",
    "E1-B16-HH-C002": "EISEI1-Q-000037",
    "E1-B16-HH-C003": "EISEI1-Q-000038",
}
B17_EXPECTED = {"E1-B17-PH-C001": "EISEI1-Q-000039"}
B18_EXPECTED = {f"E1-B18-PH-C00{index}": f"EISEI1-Q-0000{39 + index}" for index in range(1, 8)}
B19_EXPECTED = {f"E1-B19-LG-C00{index}": f"EISEI1-Q-0000{46 + index}" for index in range(1, 5)}
B20_EXPECTED = {f"E1-B20-HG-C00{index}": f"EISEI1-Q-0000{50 + index}" for index in range(1, 5)}
B21_EXPECTED = {f"E1-B21-HH-C00{index}": f"EISEI1-Q-0000{54 + index}" for index in range(1, 6)}
B22_EXPECTED = {f"E1-B22-PH-C00{index}": f"EISEI1-Q-0000{59 + index}" for index in range(1, 6)}
B23_EXPECTED = {f"E1-B23-HG-C00{index}": f"EISEI1-Q-0000{64 + index}" for index in range(1, 6)}
B24_EXPECTED = {f"E1-B24-LG-C00{index}": f"EISEI1-Q-0000{69 + index}" for index in range(1, 5)}
B25_EXPECTED = {f"E1-B25-LH-C00{index}": f"EISEI1-Q-0000{73 + index}" for index in range(1, 4)}
B26_EXPECTED = {f"E1-B26-PH-C00{index}": f"EISEI1-Q-0000{76 + index}" for index in range(1, 6)}
B27_EXPECTED = {f"E1-B27-LG-C00{index}": f"EISEI1-Q-0000{81 + index}" for index in range(1, 5)}
B28_EXPECTED = {f"E1-B28-HG-C00{index}": f"EISEI1-Q-0000{85 + index}" for index in range(1, 5)}
B29_EXPECTED = {f"E1-B29-LH-C00{index}": f"EISEI1-Q-0000{89 + index}" for index in range(1, 6)}
B30_EXPECTED = {f"E1-B30-HH-C00{index}": f"EISEI1-Q-0000{94 + index}" for index in range(1, 4)}
B31_EXPECTED = {f"E1-B31-PH-C00{index}": f"EISEI1-Q-{97 + index:06d}" for index in range(1, 4)}
B32_EXPECTED = {f"E1-B32-PH-C00{index}": f"EISEI1-Q-{100 + index:06d}" for index in range(1, 6)}
B33_EXPECTED = {f"E1-B33-LG-C00{index}": f"EISEI1-Q-{105 + index:06d}" for index in range(1, 6)}
B34_EXPECTED = {f"E1-B34-HG-C00{index}": f"EISEI1-Q-{110 + index:06d}" for index in range(1, 6)}
ALL_EXPECTED = {
    **EARLY_EXPECTED,
    **B6_EXPECTED,
    **B7_EXPECTED,
    **B8_EXPECTED,
    **B9_EXPECTED,
    **B10_EXPECTED,
    **B11_EXPECTED,
    **B12_EXPECTED,
    **B13_EXPECTED,
    **B14_EXPECTED,
    **B15_EXPECTED,
    **B16_EXPECTED,
    **B17_EXPECTED,
    **B18_EXPECTED,
    **B19_EXPECTED,
    **B20_EXPECTED,
    **B21_EXPECTED,
    **B22_EXPECTED,
    **B23_EXPECTED,
    **B24_EXPECTED,
    **B25_EXPECTED,
    **B26_EXPECTED,
    **B27_EXPECTED,
    **B28_EXPECTED,
    **B29_EXPECTED,
    **B30_EXPECTED,
    **B31_EXPECTED,
    **B32_EXPECTED,
    **B33_EXPECTED,
    **B34_EXPECTED,
}
EXPECTED_VERIFICATION_SOURCES = {
    "EISEI1-Q-000001": "E1-MHLW-CHEM-RA",
    "EISEI1-Q-000002": "E1-MHLW-RPE-2023",
    "EISEI1-Q-000003": "E1-LAW-ORGANIC",
    "EISEI1-Q-000004": "E1-LAW-OXYGEN",
    "EISEI1-Q-000005": "E1-LAW-OXYGEN",
    "EISEI1-Q-000006": "E1-LAW-IONIZING",
    "EISEI1-Q-000007": "E1-LAW-SPEC-CHEM",
    "EISEI1-Q-000008": "E1-MHLW-RPE-2023",
    "EISEI1-Q-000009": "E1-LAW-SPEC-CHEM",
    "EISEI1-Q-000010": "E1-LAW-ASBESTOS",
    "EISEI1-Q-000011": "E1-MHLW-DUST-PREVENTION",
    "EISEI1-Q-000012": "E1-MHLW-CHEMICAL-HAZARDS",
    "EISEI1-Q-000013": "E1-MHLW-WORKENV-EVALUATION",
    "EISEI1-Q-000014": "E1-LAW-ASR",
    "EISEI1-Q-000015": "E1-LAW-LEAD",
    "EISEI1-Q-000016": "E1-LAW-DUST",
    "EISEI1-Q-000017": "E1-MHLW-BIOLOGICAL-MONITORING",
    "EISEI1-Q-000018": "E1-MHLW-NOISE-2023",
    "EISEI1-Q-000019": "E1-LAW-ASR",
    "EISEI1-Q-000020": "E1-LAW-DUST",
    "EISEI1-Q-000021": "E1-LAW-OXYGEN",
    "EISEI1-Q-000022": "E1-LAW-LSL",
    "EISEI1-Q-000023": "E1-LAW-ASL",
    "EISEI1-Q-000024": "E1-LAW-ASR",
    "EISEI1-Q-000025": "E1-LAW-ASL",
    "EISEI1-Q-000026": "E1-MHLW-BIOLOGICAL-MONITORING",
    "EISEI1-Q-000027": "E1-MHLW-BIOLOGICAL-MONITORING",
    "EISEI1-Q-000028": "E1-MHLW-BIOLOGICAL-MONITORING",
    "EISEI1-Q-000029": "E1-MHLW-MENTAL-HEALTH",
    "EISEI1-Q-000030": "E1-LAW-ASL",
    "EISEI1-Q-000031": "E1-MHLW-EHEALTH-SLEEP",
    "EISEI1-Q-000032": "E1-MHLW-EHEALTH-SLEEP",
    "EISEI1-Q-000033": "E1-MHLW-VIBRATION",
    "EISEI1-Q-000034": "E1-MHLW-RADIATION-LASER",
    "EISEI1-Q-000035": "E1-MHLW-OCCUPATIONAL-HYGIENE",
    "EISEI1-Q-000036": "E1-MHLW-CHEMICAL-HAZARDS",
    "EISEI1-Q-000037": "E1-MHLW-RADIATION-LASER",
    "EISEI1-Q-000038": "E1-MHLW-HEAT",
    "EISEI1-Q-000039": "E1-NHLBI-LUNGS",
    "EISEI1-Q-000040": "E1-NHLBI-LUNGS",
    "EISEI1-Q-000041": "E1-NHLBI-LUNGS",
    "EISEI1-Q-000042": "E1-NHLBI-HEART",
    "EISEI1-Q-000043": "E1-NIDDK-KIDNEYS",
    "EISEI1-Q-000044": "E1-NIDDK-KIDNEYS",
    "EISEI1-Q-000045": "E1-NHLBI-LUNGS",
    "EISEI1-Q-000046": "E1-NHLBI-LUNGS",
    "EISEI1-Q-000047": "E1-LAW-ASL",
    "EISEI1-Q-000048": "E1-LAW-ASL",
    "EISEI1-Q-000049": "E1-LAW-ASR",
    "EISEI1-Q-000050": "E1-LAW-ASR",
    "EISEI1-Q-000051": "E1-LAW-ASR",
    "EISEI1-Q-000052": "E1-LAW-ASL",
    "EISEI1-Q-000053": "E1-LAW-ASL",
    "EISEI1-Q-000054": "E1-MHLW-MENTAL-HEALTH",
    "EISEI1-Q-000055": "E1-MHLW-NOISE-2023",
    "EISEI1-Q-000056": "E1-MHLW-NOISE-2023",
    "EISEI1-Q-000057": "E1-MHLW-HEAT",
    "EISEI1-Q-000058": "E1-MHLW-VIBRATION",
    "EISEI1-Q-000059": "E1-MHLW-CHEMICAL-HAZARDS",
    "EISEI1-Q-000060": "E1-NHLBI-HEART",
    "EISEI1-Q-000061": "E1-NHLBI-HEART",
    "EISEI1-Q-000062": "E1-NHLBI-HEART",
    "EISEI1-Q-000063": "E1-NIDDK-KIDNEYS",
    "EISEI1-Q-000064": "E1-NIDDK-KIDNEYS",
    "EISEI1-Q-000065": "E1-LAW-ASR",
    "EISEI1-Q-000066": "E1-LAW-ASR",
    "EISEI1-Q-000067": "E1-LAW-ASR",
    "EISEI1-Q-000068": "E1-LAW-ASR",
    "EISEI1-Q-000069": "E1-LAW-ASL",
    "EISEI1-Q-000070": "E1-LAW-ASR",
    "EISEI1-Q-000071": "E1-LAW-ASL",
    "EISEI1-Q-000072": "E1-LAW-ASR",
    "EISEI1-Q-000073": "E1-LAW-ASR",
    "EISEI1-Q-000074": "E1-LAW-ORGANIC",
    "EISEI1-Q-000075": "E1-LAW-SPEC-CHEM",
    "EISEI1-Q-000076": "E1-LAW-ASBESTOS",
    "EISEI1-Q-000077": "E1-NHLBI-BLOOD",
    "EISEI1-Q-000078": "E1-NHLBI-BLOOD",
    "EISEI1-Q-000079": "E1-NHLBI-BLOOD",
    "EISEI1-Q-000080": "E1-NHLBI-BLOOD",
    "EISEI1-Q-000081": "E1-NIDDK-KIDNEYS",
    "EISEI1-Q-000082": "E1-LAW-ASR",
    "EISEI1-Q-000083": "E1-LAW-ASL",
    "EISEI1-Q-000084": "E1-LAW-ASL",
    "EISEI1-Q-000085": "E1-LAW-ASL",
    "EISEI1-Q-000086": "E1-LAW-ASR",
    "EISEI1-Q-000087": "E1-LAW-ASL",
    "EISEI1-Q-000088": "E1-LAW-ASL",
    "EISEI1-Q-000089": "E1-LAW-ASL",
    "EISEI1-Q-000090": "E1-LAW-ORGANIC",
    "EISEI1-Q-000091": "E1-LAW-SPEC-CHEM",
    "EISEI1-Q-000092": "E1-LAW-LEAD",
    "EISEI1-Q-000093": "E1-LAW-ASBESTOS",
    "EISEI1-Q-000094": "E1-LAW-OXYGEN",
    "EISEI1-Q-000095": "E1-MHLW-VIBRATION",
    "EISEI1-Q-000096": "E1-MHLW-HEAT",
    "EISEI1-Q-000097": "E1-MHLW-CHEMICAL-HAZARDS",
    "EISEI1-Q-000098": "E1-NIDDK-KIDNEYS",
    "EISEI1-Q-000099": "E1-NIDDK-KIDNEYS",
    "EISEI1-Q-000100": "E1-NHLBI-HEART",
    "EISEI1-Q-000101": "E1-NIDDK-DIGESTIVE",
    "EISEI1-Q-000102": "E1-NIDDK-DIGESTIVE",
    "EISEI1-Q-000103": "E1-NIDDK-DIGESTIVE",
    "EISEI1-Q-000104": "E1-NIDDK-DIGESTIVE",
    "EISEI1-Q-000105": "E1-NIDDK-DIGESTIVE",
    "EISEI1-Q-000106": "E1-LAW-ASR",
    "EISEI1-Q-000107": "E1-LAW-ASR",
    "EISEI1-Q-000108": "E1-LAW-ASL",
    "EISEI1-Q-000109": "E1-LAW-ASL",
    "EISEI1-Q-000110": "E1-LAW-ASR",
    "EISEI1-Q-000111": "E1-LAW-ASR",
    "EISEI1-Q-000112": "E1-LAW-ASR",
    "EISEI1-Q-000113": "E1-LAW-ASR",
    "EISEI1-Q-000114": "E1-LAW-ASR",
    "EISEI1-Q-000115": "E1-LAW-ASR",
}


def read_rows(path: Path) -> dict[str, dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return {
            row["candidate_id"] if "candidates" in path.name else row["question_id"]: row
            for row in csv.DictReader(handle)
        }


class Eisei1ReadyForIdIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bank = REPOSITORY_ROOT / "question_banks" / "eisei1"
        self.authoring = self.bank / "authoring"

    def test_integrated_inventory_is_contiguous_through_q115(self) -> None:
        questions = read_rows(self.authoring / "questions.csv")
        registry = read_rows(self.authoring / "question_id_registry.csv")
        self.assertEqual(set(ALL_EXPECTED.values()), set(questions))
        self.assertEqual(set(ALL_EXPECTED.values()), set(registry))

    def test_integrated_batches_bind_exactly_to_canonical_rows(self) -> None:
        questions = read_rows(self.authoring / "questions.csv")
        registry = read_rows(self.authoring / "question_id_registry.csv")
        for batch_name, mapping in (
            ("batch_002", {k: v for k, v in EARLY_EXPECTED.items() if k.startswith("E1-B2-")}),
            ("batch_003", {"E1-B3-LH-C001": "EISEI1-Q-000005"}),
            ("batch_004", {k: v for k, v in EARLY_EXPECTED.items() if k.startswith("E1-B4-")}),
            ("batch_006", B6_EXPECTED),
            ("batch_007", B7_EXPECTED),
            ("batch_008", B8_EXPECTED),
            ("batch_009", B9_EXPECTED),
            ("batch_010", B10_EXPECTED),
            ("batch_011", B11_EXPECTED),
            ("batch_012", B12_EXPECTED),
            ("batch_013", B13_EXPECTED),
            ("batch_014", B14_EXPECTED),
            ("batch_015", B15_EXPECTED),
            ("batch_016", B16_EXPECTED),
            ("batch_017", B17_EXPECTED),
            ("batch_018", B18_EXPECTED),
            ("batch_019", B19_EXPECTED),
            ("batch_020", B20_EXPECTED),
            ("batch_021", B21_EXPECTED),
            ("batch_022", B22_EXPECTED),
            ("batch_023", B23_EXPECTED),
            ("batch_024", B24_EXPECTED),
            ("batch_025", B25_EXPECTED),
            ("batch_026", B26_EXPECTED),
            ("batch_027", B27_EXPECTED),
            ("batch_028", B28_EXPECTED),
            ("batch_029", B29_EXPECTED),
            ("batch_030", B30_EXPECTED),
            ("batch_031", B31_EXPECTED),
            ("batch_032", B32_EXPECTED),
            ("batch_033", B33_EXPECTED),
            ("batch_034", B34_EXPECTED),
        ):
            batch = self.authoring / "batches" / batch_name
            candidates = read_rows(batch / "candidates.csv")
            for candidate_id, question_id in mapping.items():
                candidate = candidates[candidate_id]
                question = questions[question_id]
                self.assertEqual("INTEGRATED", candidate["state"])
                self.assertEqual(question_id, candidate["permanent_question_id"])
                self.assertEqual("used", registry[question_id]["status"])
                self.assertEqual("draft", question["status"])
                self.assertEqual("1", question["question_version"])
                self.assertEqual("eisei1_exam", question["deck_id"])
                self.assertEqual(candidate["unit_id"], question["unit_id"])
                self.assertEqual("2", question["difficulty"])
                self.assertEqual("3", question["importance"])
                self.assertEqual("false", question["is_free"])
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "choice4",
                    "choice5",
                    "explanation",
                    "source_id",
                    "source_locator",
                ):
                    self.assertEqual(candidate[field], question[field])
                self.assertEqual(candidate["proposed_correct"], question["correct_choice"])

    def test_q1_q115_are_source_verified_and_pre_release(self) -> None:
        verifications = json.loads(
            (self.authoring / "source_verifications.json").read_text(encoding="utf-8")
        )["verifications"]
        self.assertEqual(set(EXPECTED_VERIFICATION_SOURCES), {row["question_id"] for row in verifications})
        for row in verifications:
            self.assertEqual(EXPECTED_VERIFICATION_SOURCES[row["question_id"]], row["source_id"])
            self.assertEqual("author_source_verified", row["verification_state"])
            expected_date = "2026-08-27" if int(row["question_id"].rsplit("-", 1)[1]) <= 10 else "2026-08-28"
            self.assertEqual(expected_date, row["verified_at"])
        self.assertEqual([], json.loads((self.authoring / "released_questions.json").read_text(encoding="utf-8"))["released_questions"])
        self.assertEqual([], json.loads((self.bank / "generated" / "eisei1_bank.json").read_text(encoding="utf-8"))["decks"])

    def test_q1_q16_are_bound_to_their_accepted_knowledge_targets(self) -> None:
        coverage = json.loads((self.authoring / "coverage.json").read_text(encoding="utf-8"))
        actual = {
            row["question_id"]: row["knowledge_target_id"]
            for row in coverage["question_bindings"]
        }
        expected = {}
        for batch_name in (
            "batch_002",
            "batch_003",
            "batch_004",
            "batch_006",
            "batch_007",
            "batch_008",
            "batch_009",
            "batch_010",
            "batch_011",
            "batch_012",
            "batch_013",
            "batch_014",
            "batch_015",
            "batch_016",
            "batch_017",
            "batch_018",
            "batch_019",
            "batch_020",
            "batch_021",
            "batch_022",
            "batch_023",
            "batch_024",
            "batch_025",
            "batch_026",
            "batch_027",
            "batch_028",
            "batch_029",
            "batch_030",
            "batch_031",
            "batch_032",
            "batch_033",
            "batch_034",
        ):
            candidates = read_rows(self.authoring / "batches" / batch_name / "candidates.csv")
            expected.update({
                row["permanent_question_id"]: row["knowledge_target_id"]
                for row in candidates.values()
                if row["permanent_question_id"]
            })
        self.assertEqual(expected, actual)

    def test_all_touched_expansion_batches_validate(self) -> None:
        for batch_name in ("batch_002", "batch_003", "batch_004", "batch_006", "batch_007", "batch_008", "batch_009", "batch_010", "batch_011", "batch_012", "batch_013", "batch_014", "batch_015", "batch_016", "batch_017", "batch_018", "batch_019", "batch_020", "batch_021", "batch_022", "batch_023", "batch_024", "batch_025", "batch_026", "batch_027", "batch_028", "batch_029", "batch_030", "batch_031", "batch_032", "batch_033", "batch_034"):
            self.assertEqual([], validate_expansion_batch(self.authoring / "batches" / batch_name))


if __name__ == "__main__":
    unittest.main()
