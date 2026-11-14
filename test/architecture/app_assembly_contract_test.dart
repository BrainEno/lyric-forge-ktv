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
/// The numbers below are a freeze of the current migration state, not a target.
/// Fix the call site and lower the number in the same change; never raise it.
/// Step 1 (editor/review/app shell): 80 -> 72 calls in 37 -> 34 files. Step 2
/// (playback): 72 -> 54 calls in 34 -> 29 files. Step 3 (library): 54 -> 32
/// in 29 -> 19. Step 4 (project/import): 32 -> 16 in 19 -> 14. Step 5
/// (dashboard + retired legacy share screen): 16 -> 12 in 14 -> 12. Step 6
/// (active transfer screens injected, two dead screens retired): 12 -> 5 in
/// 12 -> 5 files. Step 7 (remaining ASR/settings/queue consumers injected):
/// 5 -> 0 in 5 -> 0 files.
const int _frozenSingletonFiles = 0;
const int _frozenSingletonCalls = 0;

final RegExp _importPattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
);
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

    test('features do not import the app assembly layer', () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib/features')) {
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
            'Features declare their dependencies; lib/app owns the registry, '
            'routing and assembly:\n${violations.join('\n')}',
      );
    });

    test('the service registry is not reached from lib/app itself', () {
      // Only `app.dart` (as the production fallback) and `main.dart` may hold
      // the singleton; the routing table and assemblers receive it.
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib/app')) {
        final path = _normalize(file);
        if (path == 'lib/app/app.dart' || path == 'lib/app/app_services.dart') {
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
            '(target: $_frozenSingletonFiles files after Phase 4.2). Migrate a '
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
      final proofreadingCoordinator = File(
        'lib/features/lyrics/presentation/controllers/lyric_editor_proofreading_coordinator.dart',
      ).readAsStringSync();
      expect(
        proofreadingCoordinator,
        contains('runner: dependencies.forcedAlignmentRunner'),
      );
      final lyricEditorAssembly = File('lib/app/lyric_editor_assembly.dart')
          .readAsStringSync();
      expect(
        lyricEditorAssembly,
        contains('projectProofreadEvidencePreviewer: evidenceLoader.preview'),
      );

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

    test('playback surfaces take their dependencies', () {
      const screens = <String>[
        'lib/features/player/presentation/screens/player_screen.dart',
        'lib/features/player/presentation/screens/now_playing_screen.dart',
        'lib/features/player/presentation/widgets/playback_lyrics_availability_sync.dart',
        'lib/features/player/presentation/widgets/now_playing_lyrics_project_action.dart',
        'lib/features/player/presentation/screens/immersive_ktv_screen.dart',
      ];
      for (final path in screens) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains('AppServices')),
          reason: '$path is routed with explicit dependencies.',
        );
      }

      final router = File('lib/app/app_router.dart').readAsStringSync();
      // The formatter decides where these wrap, so match the constructor and
      // the assembler separately.
      expect(router, contains('NowPlayingScreen('));
      expect(router, contains('assembleNowPlayingDependencies(services)'));
      expect(router, contains('assemblePlayerScreenDependencies(services)'));

      final assembly = File('lib/app/playback_assembly.dart')
          .readAsStringSync();
      expect(assembly, contains('PlaybackLyricsResolver('));
      expect(
        assembly,
        contains('pathCanonicalizer: services.audioPathCanonicalizer'),
      );

      // The app shell owns the one sync widget; it must build the resolver from
      // the services it was given, not from the singleton.
      final app = File('lib/app/app.dart').readAsStringSync();
      expect(app, contains('buildPlaybackLyricsResolver(services)'));

      // The KTV studio (microphone, recording, take history, audition channel)
      // is assembled here as well — the screen takes the bundle, it does not
      // build it. That is the difference between "recording code exists" and
      // "recording is reachable".
      expect(
        assembly,
        contains('microphoneService: services.ktvMicrophoneService'),
      );
      expect(
        assembly,
        contains('recordingService: services.ktvRecordingService'),
      );
      expect(
        assembly,
        contains('takeHistoryStore: services.ktvTakeHistoryStore'),
      );
      expect(
        assembly,
        contains('previewService: services.audioPreviewService'),
      );

      final immersive = File(
        'lib/features/player/presentation/screens/immersive_ktv_screen.dart',
      ).readAsStringSync();
      expect(immersive, contains('required this.dependencies'));
      expect(immersive, contains('KtvRecordingToolbar('));
      expect(immersive, contains('KtvTakeHistorySheet('));
    });

    test('the local library surfaces take their dependencies', () {
      const surfaces = <String>[
        'lib/features/player/presentation/screens/local_music_library_shell.dart',
        'lib/features/player/presentation/screens/local_library_explorer_screen.dart',
        'lib/features/player/presentation/screens/local_artist_album_browser_screen.dart',
        'lib/features/player/presentation/screens/local_collections_screen.dart',
        'lib/features/player/presentation/screens/quick_play_screen.dart',
        'lib/features/player/presentation/widgets/global_player_bar.dart',
        'lib/features/player/presentation/widgets/mobile_global_player_bar.dart',
        'lib/features/player/presentation/widgets/local_collection_actions.dart',
        'lib/features/player/presentation/widgets/local_media_metadata_dialog.dart',
        'lib/features/player/presentation/widgets/local_song_lyrics_import_action.dart',
        'lib/features/player/presentation/widgets/playback_queue_panel.dart',
        'lib/features/player/presentation/widgets/playback_queue_playlist_action.dart',
      ];
      for (final path in surfaces) {
        expect(
          File(path).readAsStringSync(),
          isNot(contains('AppServices.instance')),
          reason: '$path is handed its collaborators by the assembly layer.',
        );
      }

      // The bundle is built in lib/app and the routing table uses it for every
      // library route, so five sections and quick play share one object.
      final router = File('lib/app/app_router.dart').readAsStringSync();
      expect(router, contains('assembleLocalLibraryDependencies(services)'));
      expect(router, contains('_libraryShell('));

      final assembly = File('lib/app/local_library_assembly.dart')
          .readAsStringSync();
      for (final service in [
        'services.localMediaLibraryRepository',
        'services.localMediaCollectionRepository',
        'services.localMediaMetadataRepository',
        'services.playHistoryRepository',
        'services.localMediaRelinkService',
        'services.audioLibraryImportService',
        'services.playbackSessionService',
        'services.audioPlayerService',
        'services.lyricFileImportService',
      ]) {
        expect(
          assembly,
          contains(service),
          reason: '$service is assembled here',
        );
      }
      // One resolver for the whole app: importing lyrics writes the corrected
      // queue flag back through the session.
      expect(assembly, contains('buildPlaybackLyricsResolver(services)'));

      // The player bars are chrome, so the shell builds them rather than the
      // routing table — and must hand them the same bundle.
      final app = File('lib/app/app.dart').readAsStringSync();
      expect(
        app,
        contains('MobileGlobalPlayerBar(dependencies: localLibrary)'),
      );
      expect(app, contains('GlobalPlayerBar(dependencies: localLibrary)'));
    });

    test('the KTV surface has a single owner', () {
      // `_FullScreenKtvView` was replaced by `ImmersiveKtvScreen` but stayed in
      // player_screen.dart as unreachable code (~1,000 lines, three locator
      // lookups). A second fullscreen KTV surface is how the two playback
      // models drifted apart in the first place.
      final player = File(
        'lib/features/player/presentation/screens/player_screen.dart',
      ).readAsStringSync();
      expect(player, isNot(contains('_FullScreenKtvView')));
      expect(player, isNot(contains('KtvRecordingService')));

      final immersive = File(
        'lib/features/player/presentation/screens/immersive_ktv_screen.dart',
      );
      expect(immersive.existsSync(), isTrue);
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
        contains(
          'ReviewInboxScreen(projectRepository: services.projectRepository)',
        ),
      );

      final assembly = File('lib/app/lyric_editor_assembly.dart')
          .readAsStringSync();
      // The forced-alignment runner used to be inlined in the editor screen.
      expect(
        assembly,
        contains('services.qwenNativeTranscriptionService.alignReference'),
      );
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
