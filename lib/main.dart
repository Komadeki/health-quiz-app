// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/quiz_screen.dart';
import 'services/deck_loader.dart';
import 'models/deck.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Quiz',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool loading = false;
  String? error;

  Future<void> _start() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      // JSON からデッキを読み込み（DeckLoader のファイル一覧に基づく）
      final loader = DeckLoader();
      final List<Deck> decks = await loader.loadAll();

      if (decks.isEmpty) {
        throw Exception('デッキが見つかりませんでした（assets/decks/ を確認してください）');
      }

      // ひとまず先頭のデッキで開始（複数化したら一覧画面に発展させればOK）
      final deck = decks.first;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => QuizScreen(deck: deck)),
      );
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('保健クイズアプリ（試作）')),
      body: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (error != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '読み込みエラー: $error',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    onPressed: _start,
                    child: const Text('クイズを始める（JSON）'),
                  ),
                ],
              ),
      ),
    );
  }
}
