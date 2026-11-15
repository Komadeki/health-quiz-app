"""Validate the authored exam pack and export a reviewable question ledger."""
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
TYPES = ('choice', 'fill', 'true_false', 'short_answer')


def audit(output):
    bank = json.loads((APP / 'assets/exam/exam_pack_v1.json').read_text())
    questions = bank['questions']
    units = {}
    for file in (APP / 'assets/decks').glob('*.json'):
        for unit in json.loads(file.read_text())['units']:
            units[unit['id']] = unit.get('title', unit.get('name', unit['id']))
    assert len(units) == 46
    assert len(questions) == 736
    assert len({q['id'] for q in questions}) == len(questions)
    assert len({q['question'] for q in questions}) == len(questions)
    counts = collections.defaultdict(collections.Counter)
    for q in questions:
        assert q['unitId'] in units, q['id']
        assert q['requiresExamPack'] is True and q['isPremium'] is False, q['id']
        assert q['explanation'].strip() and q['question'].strip(), q['id']
        assert q['type'] in TYPES and q['contentReview'] == 'editorial_reviewed_round2'
        counts[q['unitId']][q['type']] += 1
        if q['type'] == 'choice':
            assert len(q['choices']) == len(set(q['choices'])) == 4, q['id']
            assert 0 <= int(q['answer']) < 4, q['id']
        elif q['type'] == 'true_false':
            assert q['answer'] in ('○', '×'), q['id']
        elif q['type'] == 'fill':
            assert q['question'].count('（　）') == 1, q['id']
        if '英字' in q['question'] or '英語の頭文字' in q['question']:
            assert not q['acceptedAnswers'], q['id']
    assert set(counts) == set(units)
    for unit, counter in counts.items():
        assert counter == dict.fromkeys(TYPES, 4), (unit, counter)
    output.mkdir(parents=True, exist_ok=True)
    with (output / 'question-review-736.csv').open('w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'unit', 'type', 'question', 'choices', 'answer',
                         'acceptedAnswers', 'explanation', 'referenceUrls', 'review'])
        for q in questions:
            answer = q['choices'][int(q['answer'])] if q['type'] == 'choice' else q['answer']
            writer.writerow([q['id'], units[q['unitId']], q['type'], q['question'],
                             ' / '.join(q.get('choices', [])), answer,
                             ' / '.join(q['acceptedAnswers']), q['explanation'],
                             ' '.join(q['referenceUrls']), 'AI editorial round 2; not human sign-off'])
    result = {
        'questions': len(questions), 'units': len(units), 'questionsPerUnit': 16,
        'questionsPerTypePerUnit': 4,
        'types': dict(collections.Counter(q['type'] for q in questions)),
        'withPrimaryReferenceUrls': sum(bool(q['referenceUrls']) for q in questions),
        'allQuestionsIndividuallyPrimaryVerified': False,
        'humanContentSignOff': False,
        'free40Sha256': hashlib.sha256((APP / 'assets/exam/exam_questions_v1.json').read_bytes()).hexdigest(),
        'packSha256': hashlib.sha256((APP / 'assets/exam/exam_pack_v1.json').read_bytes()).hexdigest(),
    }
    (output / 'content-audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    audit(parser.parse_args().output)
