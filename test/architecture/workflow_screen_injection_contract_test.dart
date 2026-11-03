import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project detail takes its services from app assembly', () {
    final screen = File(
      'lib/features/project/presentation/screens/project_detail_screen.dart',
    ).readAsStringSync();
    final router = File('lib/app/app_router.dart').readAsStringSync();
    final assembly = File('lib/app/screen_assembly.dart').readAsStringSync();

    expect(screen, isNot(contains('AppServices')));
    expect(screen, contains('required this.dependencies'));
    expect(router, contains('assembleProjectDetailDependencies(services)'));
    expect(assembly, contains('services.projectTranscriptionWorkflow'));
  });

  test('import screens and queue recovery share explicit dependencies', () {
    final ready = File(
      'lib/features/import/presentation/screens/'
      'transcription_ready_import_screen.dart',
    ).readAsStringSync();
    final importing = File(
      'lib/features/import/presentation/screens/import_audio_screen.dart',
    ).readAsStringSync();
    final queuePanel = File(
      'lib/features/transcription/presentation/widgets/transcription_queue_panel.dart',
    ).readAsStringSync();
    final router = File('lib/app/app_router.dart').readAsStringSync();

    expect(ready, isNot(contains('AppServices')));
    expect(importing, isNot(contains('AppServices')));
    expect(queuePanel, isNot(contains('AppServices')));
    expect(
      ready,
      contains('ImportAudioScreen(dependencies: widget.dependencies)'),
    );
    expect(importing, contains('required this.dependencies'));
    expect(queuePanel, contains('required this.settingsStore'));
    expect(queuePanel, contains('required this.runtimeManager'));
    expect(
      router,
      contains('assembleTranscriptionImportDependencies(services)'),
    );
  });

  test('remote media library receives explicit dependencies', () {
    final screen = File(
      'lib/features/transfer/presentation/screens/remote_media_library_screen.dart',
    ).readAsStringSync();
    final assembly = File('lib/app/screen_assembly.dart').readAsStringSync();

    expect(screen, isNot(contains('AppServices')));
    expect(screen, contains('required this.dependencies'));
    expect(assembly, contains('services.mediaHubClientService'));
    expect(assembly, contains('services.mediaHubConnectionStore'));
  });
}
