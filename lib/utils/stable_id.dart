// lib/utils/stable_id.dart
import 'package:quiz_engine/quiz_engine.dart';

import '../quiz_app_definition.dart';

const _legacyQuestionIdentity = LegacyHashQuestionIdentityV1();

/// 出題前の「元の選択肢順」のカードから安定IDを返す。
///
/// 現行の高校保健は LegacyHashQuestionIdentityV1 で従来ハッシュを維持し、
/// 保存済み履歴・途中セッションとの互換性を壊さない。
/// 新規資格アプリは ExplicitQuestionIdentityV1 で永久IDを必須にする。
String stableIdForOriginal(QuizCard c) =>
    currentQuizApp.questionIdentityPolicy.stableIdFor(c);

/// 旧方式の内容ハッシュ。互換確認・移行用途で利用する。
String legacyStableIdForOriginal(QuizCard c) =>
    _legacyQuestionIdentity.stableIdFor(c);

String stableIdFromStrings(String question, List<String> choices) =>
    _legacyQuestionIdentity.stableIdFromStrings(question, choices);
