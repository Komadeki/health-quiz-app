import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_quiz_app/utils/logger.dart';

enum TapAdvanceMode { oneTap, twoTap }

enum TextSize { small, medium, large }

class AppSettings with ChangeNotifier {
  // ===== defaults =====
  static const _dIsDark = false;
  static const _dTap = TapAdvanceMode.oneTap;
  static const _dText = TextSize.medium;
  static const _dRandom = true;
  static const _dSaveUnits = true; // 出題単元の選択状況を保存

  // ===== keys =====
  static const _kDark = 'settings.isDark';
  static const _kTap = 'settings.tapMode';
  static const _kText = 'settings.textSize';
  static const _kRandom = 'settings.randomize';
  static const _kSaveUnits = 'settings.saveUnitSelection';

  // ===== states =====
  bool _isDark = _dIsDark;
  TapAdvanceMode _tap = _dTap;
  TextSize _text = _dText;
  bool _random = _dRandom;
  bool _saveUnits = _dSaveUnits;

  // ===== getters =====
  bool get isDark => _isDark;
  TapAdvanceMode get tapMode => _tap;
  TextSize get textSize => _text;
  bool get randomize => _random;
  bool get saveUnitSelection => _saveUnits;

  double get textScaleFactor => switch (_text) {
    TextSize.small => 0.9,
    TextSize.medium => 1.0,
    TextSize.large => 1.15,
  };

  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  // ===== lifecycle =====
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _isDark = p.getBool(_kDark) ?? _dIsDark;
    _tap = TapAdvanceMode.values[p.getInt(_kTap) ?? _dTap.index];
    _text = TextSize.values[p.getInt(_kText) ?? _dText.index];
    _random = p.getBool(_kRandom) ?? _dRandom;
    _saveUnits = p.getBool(_kSaveUnits) ?? _dSaveUnits;
    notifyListeners();
  }

  Future<void> _save(
    void Function() apply,
    Future<bool> Function(SharedPreferences) persist,
  ) async {
    apply();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await persist(p);
  }

  // ===== setters =====
  Future<void> setDark(bool v) =>
      _save(() => _isDark = v, (p) => p.setBool(_kDark, v));

  Future<void> setTapMode(TapAdvanceMode v) =>
      _save(() => _tap = v, (p) => p.setInt(_kTap, v.index));

  Future<void> setTextSize(TextSize v) =>
      _save(() => _text = v, (p) => p.setInt(_kText, v.index));

  Future<void> setRandomize(bool v) =>
      _save(() => _random = v, (p) => p.setBool(_kRandom, v));

  /// 出題単元（UnitSelect / ミックス）の選択状況を保存するか
  /// OFFにした瞬間、保存済みの選択リストを削除
  Future<void> setSaveUnitSelection(bool v) =>
      _save(() => _saveUnits = v, (p) async {
        final ok = await p.setBool(_kSaveUnits, v);
        if (!v) {
          await p.remove('selected_units'); // UnitSelectScreen 用
          await p.remove('mixed_selected_units'); // MultiSelectScreen 用
          AppLog.d('🧹 [AppSettings] Cleared unit selection lists');
        }
        return ok;
      });

  // ===== reset =====
  Future<void> resetToDefaults() async {
    await _save(
      () {
        _isDark = _dIsDark;
        _tap = _dTap;
        _text = _dText;
        _random = _dRandom;
        _saveUnits = _dSaveUnits;
      },
      (p) async {
        await p.setBool(_kDark, _dIsDark);
        await p.setInt(_kTap, _dTap.index);
        await p.setInt(_kText, _dText.index);
        await p.setBool(_kRandom, _dRandom);
        await p.setBool(_kSaveUnits, _dSaveUnits);
        return true;
      },
    );
  }
}
