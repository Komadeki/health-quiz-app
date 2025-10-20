import 'package:flutter/material.dart';
import 'review_cards_screen.dart';
import 'review_test_setup_screen.dart';

class ReviewMenuScreen extends StatelessWidget {
  const ReviewMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 単元カードのような質感
    BoxDecoration _unitLikeDecoration() => BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.18),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              offset: Offset(0, 2),
              color: Color(0x14000000),
            ),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('復習')),
      body: LayoutBuilder(
        builder: (context, c) {
          final double baseThird = c.maxHeight / 3;
          final double topArea = baseThird;
          const double gap = 16;
          final double cardH = (topArea - gap) / 2 * 1.8;

          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 🟩 見直しモードカード
                  SizedBox(
                    height: cardH,
                    width: double.infinity,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReviewCardsScreen()),
                      ),
                      child: Ink(
                        decoration: _unitLikeDecoration(),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                        child: Row(
                          children: [
                            Icon(Icons.style_outlined,
                                size: 40, color: theme.colorScheme.primary),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '見直しモード',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'これまでに間違えた問題カードを1枚ずつ見直しながら、'
                                    '答えと解説を確認して復習します。',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      height: 1.4,
                                      color: theme.colorScheme.onSurface.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: gap),

                  // 🟩 復習テストモードカード
                  SizedBox(
                    height: cardH,
                    width: double.infinity,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReviewTestSetupScreen(),
                        ),
                      ),
                      child: Ink(
                        decoration: _unitLikeDecoration(),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                        child: Row(
                          children: [
                            Icon(Icons.quiz_outlined,
                                size: 40, color: theme.colorScheme.primary),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '復習テストモード',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '誤答の多い問題を自動で選び、'
                                    '出現頻度の上位から10・20・30・50問を出題します。\n'
                                    '苦手を集中的に確認したいときにおすすめです。',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      height: 1.4,
                                      color: theme.colorScheme.onSurface.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
