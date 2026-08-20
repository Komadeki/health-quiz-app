import 'package:quiz_engine/quiz_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../generated/app_manifest.g.dart';
import 'production_session.dart';

abstract interface class DroneSessionStore {
  Future<DroneQuizSession?> load();
  Future<void> save(DroneQuizSession session);
  Future<void> clear();
}

final class SharedPreferencesDroneSessionStore implements DroneSessionStore {
  const SharedPreferencesDroneSessionStore();

  static const _key = 'drone_second_class.active_session.v1';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<DroneQuizSession?> load() async {
    final preferences = await _preferences;
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    final session = DroneQuizSession.decode(raw);
    if (session == null) await preferences.remove(_key);
    return session;
  }

  @override
  Future<void> save(DroneQuizSession session) async {
    await (await _preferences).setString(_key, session.encode());
  }

  @override
  Future<void> clear() async {
    await (await _preferences).remove(_key);
  }
}

final class DroneEntitlementCache implements EntitlementCache {
  const DroneEntitlementCache();

  static const _key = 'drone_second_class.entitlement.full_unlock.v1';

  Future<SharedPreferences> get _preferences => SharedPreferences.getInstance();

  @override
  Future<EntitlementSnapshot> load() async {
    final unlocked = (await _preferences).getBool(_key) ?? false;
    return EntitlementSnapshot(
      ownedProductIds: unlocked
          ? {GeneratedAppManifest.productCatalog.fullUnlockProductId!}
          : const <String>{},
    );
  }

  @override
  Future<EntitlementSnapshot> merge(EntitlementSnapshot additions) async {
    final productId = GeneratedAppManifest.productCatalog.fullUnlockProductId!;
    if (additions.ownedProductIds.contains(productId)) {
      await (await _preferences).setBool(_key, true);
    }
    return load();
  }
}
