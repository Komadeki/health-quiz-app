from pathlib import Path

path = Path('packages/qualification_app/lib/src/production_app.dart')
text = path.read_text(encoding='utf-8')
bad = "$attemptCount回答\n'"
good = "$attemptCount回答\\n'"
count = text.count(bad)
if count != 2:
    raise SystemExit(f'expected 2 broken newline strings, found {count}')
path.write_text(text.replace(bad, good), encoding='utf-8')
