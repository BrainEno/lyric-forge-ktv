import 'package:flutter/foundation.dart';

import 'app_palette.dart';

/// Where the chosen theme is remembered between launches.
abstract class AppearanceStore {
  /// The saved theme, or null when nothing (or nothing readable) is saved.
  Future<AppThemeVariant?> load();

  /// Remembers [variant]; may throw when the file cannot be written.
  Future<void> save(AppThemeVariant variant);
}

/// Keeps the choice for the life of the process only: the store of a shell
/// built without bootstrap, and of tests.
class MemoryAppearanceStore implements AppearanceStore {
  MemoryAppearanceStore([this.saved]);

  AppThemeVariant? saved;

  /// How many times [save] ran.
  int saves = 0;

  @override
  Future<AppThemeVariant?> load() async => saved;

  @override
  Future<void> save(AppThemeVariant variant) async {
    saves++;
    saved = variant;
  }
}

/// The theme the app is shown in (decision D-042).
///
/// 设置 › 外观 and the rail's theme button both call [select]; the app root
/// (`AppAppearanceHost`) listens, switches the palette `AppColors` reads and
/// rebuilds the screens. The choice is saved through the [AppearanceStore]
/// and read back by [restore] at launch.
class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController({
    required AppearanceStore store,
    AppThemeVariant initial = AppThemeVariant.fallback,
  }) : _store = store,
       _variant = initial;

  final AppearanceStore _store;
  AppThemeVariant _variant;
  bool _restored = false;
  bool _userChose = false;
  Object? _saveError;

  /// The theme in use.
  AppThemeVariant get variant => _variant;

  /// The palette of [variant].
  AppPalette get palette => _variant.palette;

  /// Whether [restore] has finished, whatever it found.
  bool get restored => _restored;

  /// Why the last [select] could not be saved, or null when it was. The
  /// theme still changes for this session.
  Object? get saveError => _saveError;

  /// Reads the saved theme and switches to it. A pick the user made while
  /// the file was still being read wins over the file.
  Future<void> restore() async {
    AppThemeVariant? saved;
    try {
      saved = await _store.load();
    } catch (_) {
      saved = null;
    }
    _restored = true;
    if (saved != null && !_userChose && saved != _variant) {
      _variant = saved;
    }
    notifyListeners();
  }

  /// Switches to [variant] and saves it. Returns whether it was saved.
  Future<bool> select(AppThemeVariant variant) async {
    _userChose = true;
    if (variant != _variant) {
      _variant = variant;
      _saveError = null;
      notifyListeners();
    }
    try {
      await _store.save(variant);
      if (_saveError != null) {
        _saveError = null;
        notifyListeners();
      }
      return true;
    } catch (error) {
      _saveError = error;
      notifyListeners();
      return false;
    }
  }
}
