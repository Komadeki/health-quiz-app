from pathlib import Path

path = Path('packages/qualification_app/test/production_widget_test.dart')
text = path.read_text(encoding='utf-8')
old = "    expect(find.text('買い切り Fixture'), findsOneWidget);\n"
new = """    final unlockSheet = find.byKey(const Key('mock-exam-unlock-sheet'));
    expect(
      find.descendant(of: unlockSheet, matching: find.text('買い切り Fixture')),
      findsOneWidget,
    );
"""
if text.count(old) != 1:
    raise SystemExit(f'expected exactly one unscoped price assertion, found {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
