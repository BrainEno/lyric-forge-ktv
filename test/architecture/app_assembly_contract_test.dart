import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Assembly ratchet for Phase 4.2 (dependency injection in `lib/app/`).
///
/// Before 4.2 the app-wide singleton lived in `lib/core/services/` and every
/// screen could reach it from the layer below the assembly. Now:
///
///   * `lib/app/` holds assembly only — services, routing table, app widget,
///     and the per-screen dependency builders;
///   * `lib/core/` and features may not import the shell (`app.dart`,
///     `app_router.dart`, assemblers), so a screen can never grab the routing
///     table or construct its peers;
///   * the remaining `AppServices.instance` call sites are counted, and the
///     count only goes down as screens migrate to constructor injection.
///
/// The numbers below are a freeze of the 4.2 landing state, not a target. Fix
/// the call site and lower the number in the same change; never raise it.
const int _frozenSingletonFiles = 34;
const int _frozenSingletonCalls = 72;

/// The only part of `lib/app/` a feature may see, and only while it is still
/// on the singleton. Everything else in `lib/app/` is assembly.
const String _allowedAppImportForFeatures = 'lib/app/app_services.dart';

final RegExp _importPattern = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');
final RegExp _singletonPattern = RegExp(r'AppServices\s*\.\s*instance');

String _resolve(String uri, String importer) {
  const packagePrefix = 'package:lyric_forge_ktv/';
  if (uri.startsWith(packagePrefix)) {
    return 'lib/${uri.substring(packagePrefix.length)}';
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return uri;
  final parts = importer.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

List<File> _dartFilesUnder(String path) {
  return Directory(path)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _normalize(File file) => file.path.replaceAll('\\', '/');

/// Import targets of [file], resolved to repository paths where possible.
List<String> _importsOf(File file) {
  final importer = _normalize(file);
  return file
      .readAsLinesSync()
      .map(_importPattern.firstMatch)
      .whereType<RegExpMatch>()
      .map((match) => _resolve(match.group(1)!, importer))
      .toList();
}

void main() {
  group('App assembly contracts', () {
    test('core does not import the app assembly layer', () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib/core')) {
        for (final target in _importsOf(file)) {
          if (target.startsWith('lib/app/')) {
            violations.add('${_normalize(file)} -> $target');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'lib/core is the shared layer; assembly sits above it. Move the '
            'shared piece down to lib/core (as `Routes` already is) instead '
            'of importing lib/app from below:\n${violations.join('\n')}',
      );
    });

    test('features only see the service registry of lib/app', () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib/features')) {
        for (final target in _importsOf(file)) {
          if (target.startsWith('lib/app/') &&
              target != _allowedAppImportForFeatures) {
            violations.add('${_normalize(file)} -> $target');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'A feature must not import the app shell, the routing table or '
            'an assembler — that would let a screen construct its peers and '
            're-create the coupling 4.2 removed:\n${violations.join('\n')}',
      );
    });

    test('the service registry is not reached from lib/app itself', () {
      // Only `app.dart` (as the production fallback) and `main.dart` may hold
      // the singleton; the routing table and assemblers receive it.
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib/app')) {
        final path = _normalize(file);
        if (path == 'lib/app/app.dart' ||
            path == 'lib/app/app_services.dart') {
          continue;
        }
        if (_singletonPattern.hasMatch(file.readAsStringSync())) {
          offenders.add(path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Take `AppServices` as a constructor argument (as AppRouter does) '
            'so the wiring can be exercised with fakes:\n${offenders.join('\n')}',
      );
    });

    test('global singleton call sites only shrink', () {
      final files = <String>{};
      var calls = 0;
      for (final file in _dartFilesUnder('lib/features')) {
        for (final line in file.readAsLinesSync()) {
          // Skip comments: a doc mention is not a dependency.
          if (line.trimLeft().startsWith('//')) continue;
          final matches = _singletonPattern.allMatches(line).length;
          if (matches == 0) continue;
          files.add(_normalize(file));
          calls += matches;
        }
      }

      expect(
        calls,
        lessThanOrEqualTo(_frozenSingletonCalls),
        reason:
            'AppServices.instance now has $calls call sites in lib/features '
            '($_frozenSingletonFiles files frozen after Phase 4.2). Migrate a '
            'screen to constructor injection instead of adding another lookup.',
      );
      expect(
        files.length,
        lessThanOrEqualTo(_frozenSingletonFiles),
        reason:
            '${files.length} feature files still reach for the global '
            'services ($_frozenSingletonFiles frozen). Each migrated screen '
            'lowers this number.',
      );
    });

    test('lyric editor and review inbox take their dependencies', () {
      final editor = File(
        'lib/features/lyrics/presentation/screens/lyric_editor_screen.dart',
      ).readAsStringSync();
      expect(
        editor,
        isNot(contains('AppServices')),
        reason:
            'The editor is the first screen on constructor injection; it must '
            'not fall back to the singleton.',
      );
      expect(editor, contains('required this.dependencies'));
      expect(editor, contains('widget.dependencies.forcedAlignmentRunner'));

      final inbox = File(
        'lib/features/lyrics/presentation/screens/review_inbox_screen.dart',
      ).readAsStringSync();
      expect(
        inbox,
        isNot(contains('AppServices')),
        reason: 'The review inbox is routed with an explicit repository.',
      );
      expect(inbox, contains('required this.projectRepository'));
    });

    test('the routing table builds the editor dependencies', () {
      final router = File('lib/app/app_router.dart').readAsStringSync();
      expect(
        router,
        contains('dependencies: assembleLyricEditorDependencies(services)'),
        reason:
            'Assembly belongs in lib/app, so the route — not the screen — '
            'decides what the editor is made of.',
      );
      expect(
        router,
        contains('ReviewInboxScreen(projectRepository: services.projectRepository)'),
      );

      final assembly = File('lib/app/lyric_editor_assembly.dart').readAsStringSync();
      // The forced-alignment runner used to be inlined in the editor screen.
      expect(assembly, contains('services.qwenNativeTranscriptionService.alignReference'));
      expect(assembly, contains("throw Exception('尚未配置本地转写运行时。')"));
      expect(assembly, contains('AsrRuntimeComponent.qwenAligner'));
    });

    test('main.dart stays bootstrap-only', () {
      final main = File('lib/main.dart');
      final imports = _importsOf(main);
      expect(
        imports.where((target) => target.contains('/presentation/')),
        isEmpty,
        reason:
            'The process entry point builds services and runs the app; '
            'screens are reached through the routing table in lib/app.',
      );
      expect(imports, contains('lib/app/app.dart'));
      expect(imports, contains('lib/app/app_services.dart'));
      expect(
        main.readAsStringSync(),
        isNot(contains('MaterialApp(')),
        reason: 'The widget tree lives in lib/app/app.dart.',
      );
    });
  });
}
