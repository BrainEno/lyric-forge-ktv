import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/core/theme/app_appearance.dart';
import 'package:lyric_forge_ktv/core/theme/app_palette.dart';

/// A store whose load and save finish when the test says so, and can fail.
class _ScriptedStore implements AppearanceStore {
  Completer<AppThemeVariant?>? pendingLoad;
  Object? loadError;
  Object? saveError;
  final List<AppThemeVariant> saved = [];

  @override
  Future<AppThemeVariant?> load() {
    final error = loadError;
    if (error != null) return Future.error(error);
    final pending = pendingLoad;
    if (pending != null) return pending.future;
    return Future.value(null);
  }

  @override
  Future<void> save(AppThemeVariant variant) async {
    final error = saveError;
    if (error != null) throw error;
    saved.add(variant);
  }
}

void main() {
  group('a new controller', () {
    test('opens on the fallback theme, not yet restored', () {
      final controller = AppAppearanceController(
        store: MemoryAppearanceStore(),
      );
      expect(controller.variant, AppThemeVariant.dark);
      expect(controller.palette, same(AppPalette.dark));
      expect(controller.restored, isFalse);
      expect(controller.saveError, isNull);
    });

    test('can open on another theme', () {
      final controller = AppAppearanceController(
        store: MemoryAppearanceStore(),
        initial: AppThemeVariant.light,
      );
      expect(controller.variant, AppThemeVariant.light);
      expect(controller.palette, same(AppPalette.light));
    });
  });

  group('restore', () {
    test('switches to the saved theme and notifies', () async {
      final controller = AppAppearanceController(
        store: MemoryAppearanceStore(AppThemeVariant.light),
      );
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.restore();

      expect(controller.variant, AppThemeVariant.light);
      expect(controller.restored, isTrue);
      expect(notified, 1);
    });

    test('keeps the fallback when nothing is saved', () async {
      final controller = AppAppearanceController(
        store: MemoryAppearanceStore(),
      );
      await controller.restore();
      expect(controller.variant, AppThemeVariant.dark);
      expect(controller.restored, isTrue);
    });

    test('keeps the fallback when the store fails to load', () async {
      final store = _ScriptedStore()..loadError = StateError('disk');
      final controller = AppAppearanceController(store: store);

      await controller.restore();

      expect(controller.variant, AppThemeVariant.dark);
      expect(controller.restored, isTrue);
    });

    test('does not save what it read back', () async {
      final store = MemoryAppearanceStore(AppThemeVariant.light);
      final controller = AppAppearanceController(store: store);
      await controller.restore();
      expect(store.saves, 0);
    });

    test('a pick made while loading wins over the file', () async {
      final store = _ScriptedStore()
        ..pendingLoad = Completer<AppThemeVariant?>();
      final controller = AppAppearanceController(store: store);

      final restoring = controller.restore();
      await controller.select(AppThemeVariant.light);
      store.pendingLoad!.complete(AppThemeVariant.dark);
      await restoring;

      expect(controller.variant, AppThemeVariant.light);
      expect(controller.restored, isTrue);
      expect(store.saved, [AppThemeVariant.light]);
    });

    test('the file wins when the user picked nothing meanwhile', () async {
      final store = _ScriptedStore()
        ..pendingLoad = Completer<AppThemeVariant?>();
      final controller = AppAppearanceController(store: store);

      final restoring = controller.restore();
      expect(controller.restored, isFalse);
      store.pendingLoad!.complete(AppThemeVariant.light);
      await restoring;

      expect(controller.variant, AppThemeVariant.light);
    });
  });

  group('select', () {
    test('switches, notifies once and saves', () async {
      final store = MemoryAppearanceStore();
      final controller = AppAppearanceController(store: store);
      final seen = <AppThemeVariant>[];
      controller.addListener(() => seen.add(controller.variant));

      final saved = await controller.select(AppThemeVariant.light);

      expect(saved, isTrue);
      expect(controller.variant, AppThemeVariant.light);
      expect(seen, [AppThemeVariant.light]);
      expect(store.saved, AppThemeVariant.light);
      expect(store.saves, 1);
    });

    test('notifies before the save finishes', () async {
      final store = _ScriptedStore();
      final controller = AppAppearanceController(store: store);
      var notifiedBeforeSave = false;
      controller.addListener(() => notifiedBeforeSave = store.saved.isEmpty);

      await controller.select(AppThemeVariant.light);

      expect(notifiedBeforeSave, isTrue);
    });

    test('picking the theme in use saves without notifying', () async {
      final store = MemoryAppearanceStore();
      final controller = AppAppearanceController(store: store);
      var notified = 0;
      controller.addListener(() => notified++);

      await controller.select(AppThemeVariant.dark);

      expect(notified, 0);
      expect(store.saved, AppThemeVariant.dark);
    });

    test('switches back and forth', () async {
      final store = MemoryAppearanceStore();
      final controller = AppAppearanceController(store: store);

      await controller.select(AppThemeVariant.light);
      await controller.select(AppThemeVariant.dark);
      await controller.select(AppThemeVariant.light);

      expect(controller.variant, AppThemeVariant.light);
      expect(store.saves, 3);
    });

    test('a failed save keeps the theme and reports the error', () async {
      final store = _ScriptedStore()..saveError = const FileSystemLike();
      final controller = AppAppearanceController(store: store);
      var notified = 0;
      controller.addListener(() => notified++);

      final saved = await controller.select(AppThemeVariant.light);

      expect(saved, isFalse);
      expect(controller.variant, AppThemeVariant.light);
      expect(controller.saveError, isA<FileSystemLike>());
      // Once for the switch, once for the error.
      expect(notified, 2);
    });

    test('a later successful save clears the error', () async {
      final store = _ScriptedStore()..saveError = const FileSystemLike();
      final controller = AppAppearanceController(store: store);
      await controller.select(AppThemeVariant.light);

      store.saveError = null;
      final saved = await controller.select(AppThemeVariant.light);

      expect(saved, isTrue);
      expect(controller.saveError, isNull);
      expect(store.saved, [AppThemeVariant.light]);
    });

    test('switching again clears a stale error right away', () async {
      final store = _ScriptedStore()..saveError = const FileSystemLike();
      final controller = AppAppearanceController(store: store);
      await controller.select(AppThemeVariant.light);
      expect(controller.saveError, isNotNull);

      store.saveError = null;
      Object? errorWhenSwitched = const FileSystemLike();
      void listener() => errorWhenSwitched = controller.saveError;
      controller.addListener(listener);
      await controller.select(AppThemeVariant.dark);
      controller.removeListener(listener);

      expect(errorWhenSwitched, isNull);
      expect(controller.variant, AppThemeVariant.dark);
    });
  });

  group('MemoryAppearanceStore', () {
    test('starts with what it was given', () async {
      expect(await MemoryAppearanceStore().load(), isNull);
      expect(
        await MemoryAppearanceStore(AppThemeVariant.light).load(),
        AppThemeVariant.light,
      );
    });

    test('remembers saves and counts them', () async {
      final store = MemoryAppearanceStore();
      await store.save(AppThemeVariant.light);
      await store.save(AppThemeVariant.dark);
      expect(await store.load(), AppThemeVariant.dark);
      expect(store.saves, 2);
    });
  });
}

/// Stands in for a file system error without touching the disk.
class FileSystemLike implements Exception {
  const FileSystemLike();
}
