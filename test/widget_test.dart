// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:health_quiz_app/main.dart';
import 'package:health_quiz_app/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'App builds smoke test (idle, no settle)',
    (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider(create: (_) => AppSettings())],
          child: const MyApp(),
        ),
      );

      // 1フレーム描画して、初期化で積まれた microtask/timer を軽く消化
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.idle();

      // 立ち上がっていることだけ確認（画面特定は Key を付けて行うとより堅牢）
      expect(find.byType(MaterialApp), findsOneWidget);

      // テスト終了直前にもう一度ドレイン（pending timers 対策）
      addTearDown(() async {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.idle();
      });
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
