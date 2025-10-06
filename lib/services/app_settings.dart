import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TapAdvanceMode { oneTap, twoTap }
enum TextSize { small, medium, large }

class AppSettings with ChangeNotifier {
  // defaults
  static const _dIsDark = false;
  static const _dTap = TapAdvanceMode.oneTap;
  static const _dSavePrev = true;
  static const _dText = TextSize.medium;
  static const _dRandom = true;

  // keys
  static const _kDark = 'settings.isDark';
  static const _kTap = 'settings.tapMode';
  static const _kSavePrev = 'settings.savePrevSelection';
  static const _kText = 'settings.textSize';
  static const _kRandom = 'settings.randomize';

  bool _isDark = _dIsDark;
  TapAdvanceMode _tap = _dTap;
  bool _savePrev = _dSavePrev;
  TextSize _text = _dText;
  bool _random = _dRandom;

  bool get isDark => _isDark;
  TapAdvanceMode get tapMode => _tap;
  bool get savePrevSelection => _savePrev;
  TextSize get textSize => _text;
  bool get randomize => _random;

  double get textScaleFactor => switch (_text) {
        TextSize.small => 0.9,
        TextSize.medium => 1.0,
        TextSize.large => 1.15,
      };
  ThemeMode get themeMode => _isDark ? ThemeMode.dark : ThemeMode.light;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _isDark   = p.getBool(_kDark) ?? _dIsDark;
    _tap      = TapAdvanceMode.values[p.getInt(_kTap) ?? _dTap.index];
    _savePrev = p.getBool(_kSavePrev) ?? _dSavePrev;
    _text     = TextSize.values[p.getInt(_kText) ?? _dText.index];
    _random   = p.getBool(_kRandom) ?? _dRandom;
    notifyListeners();
  }

  Future<void> _save(void Function() apply, Future<bool> Function(SharedPreferences) persist) async {
    apply();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await persist(p);
  }

  Future<void> setDark(bool v) => _save(() => _isDark = v, (p) => p.setBool(_kDark, v));
  Future<void> setTapMode(TapAdvanceMode v) => _save(() => _tap = v, (p) => p.setInt(_kTap, v.index));
  Future<void> setSavePrevSelection(bool v) => _save(() => _savePrev = v, (p) => p.setBool(_kSavePrev, v));
  Future<void> setTextSize(TextSize v) => _save(() => _text = v, (p) => p.setInt(_kText, v.index));
  Future<void> setRandomize(bool v) => _save(() => _random = v, (p) => p.setBool(_kRandom, v));

  Future<void> resetToDefaults() async {
    await _save(() {
      _isDark = _dIsDark;
      _tap = _dTap;
      _savePrev = _dSavePrev;
      _text = _dText;
      _random = _dRandom;
    }, (p) async {
      await p.setBool(_kDark, _dIsDark);
      await p.setInt(_kTap, _dTap.index);
      await p.setBool(_kSavePrev, _dSavePrev);
      await p.setInt(_kText, _dText.index);
      await p.setBool(_kRandom, _dRandom);
      return true;
    });
  }
}
