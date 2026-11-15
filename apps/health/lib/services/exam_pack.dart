import 'package:quiz_engine/quiz_engine.dart' as engine;
import 'purchase_store.dart';

/// Independent non-consumable; never grants legacy deck or Pro rights.
const examPackProductId = 'exam_pack_unlock';

Future<bool> handleExamPackPurchase(
  engine.PurchaseResult result,
  engine.PurchaseGateway gateway,
) async {
  if (result.productId != examPackProductId) return false;
  if (result.status == engine.PurchaseResultStatus.purchased ||
      result.status == engine.PurchaseResultStatus.restored) {
    await PurchaseStore.setExamPackOwned(true);
  }
  if (result.pendingCompletePurchase &&
      result.status != engine.PurchaseResultStatus.pending) {
    await gateway.complete(result);
  }
  return true;
}
