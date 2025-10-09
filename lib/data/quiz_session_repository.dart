import '../models/quiz_session.dart';

abstract class QuizSessionRepository {
  Future<void> save(QuizSession s);
  Future<QuizSession?> loadActive(); // isFinished=false のものを返す
  Future<void> clear();              // active を消す
}
