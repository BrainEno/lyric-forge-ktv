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
      'lib/features/transcription/presentation/widgets/'
      'transcription_queue_panel.dart',
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
    expect(queuePanel, contains('required this.setupDependencies'));
    expect(queuePanel, contains('dependencies: setupDependencies'));
    expect(
      router,
      contains('assembleTranscriptionImportDependencies(services)'),
    );
  });

  test('remote media library receives explicit dependencies', () {
    final screen = File(
      'lib/features/transfer/presentation/screens/'
      'remote_media_library_screen.dart',
    ).readAsStringSync();
    final assembly = File('lib/app/screen_assembly.dart').readAsStringSync();

    expect(screen, isNot(contains('AppServices')));
    expect(screen, contains('required this.dependencies'));
    expect(assembly, contains('services.mediaHubClientService'));
    expect(assembly, contains('services.mediaHubConnectionStore'));
  });

  test(
    'dashboard dependencies are assembled and the retired sharing screen stays unreachable',
    () {
      final dashboard = File(
        'lib/features/home/presentation/screens/dashboard_screen.dart',
      ).readAsStringSync();
      final router = File('lib/app/app_router.dart').readAsStringSync();
      final assembly = File('lib/app/home_assembly.dart').readAsStringSync();
      final legacySharing = File(
        'lib/features/transfer/presentation/screens/'
        'desktop_media_sharing_screen.dart',
      );

      expect(dashboard, isNot(contains('AppServices')));
      expect(dashboard, contains('required this.dependencies'));
      expect(router, contains('assembleDashboardDependencies(services)'));
      expect(assembly, contains('services.transcriptionSettingsStore'));
      expect(legacySharing.existsSync(), isFalse);
      expect(router, contains('DesktopMediaTransferHubV2Screen('));
      expect(router, isNot(contains('DesktopMediaSharingScreen')));
    },
  );
  test(
    'active transfer surfaces are assembled; legacy transfer screens stay retired',
    () {
      final router = File('lib/app/app_router.dart').readAsStringSync();
      final assembly = File(
        'lib/app/transfer_assembly.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/features/transfer/presentation/screens/'
        'mobile_remote_library_shell.dart',
      ).readAsStringSync();
      const screens = <String>[
        'lib/features/transfer/presentation/screens/'
            'desktop_media_transfer_hub_v2_screen.dart',
        'lib/features/transfer/presentation/screens/'
            'mobile_media_transfer_hub_screen.dart',
        'lib/features/transfer/presentation/screens/'
            'mobile_remote_library_shell.dart',
        'lib/features/transfer/presentation/screens/'
            'mobile_remote_music_library_screen.dart',
        'lib/features/transfer/presentation/screens/'
            'mobile_remote_grouped_library_screen.dart',
        'lib/features/transfer/presentation/screens/'
            'mobile_download_manager_screen.dart',
      ];
      for (final path in screens) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('AppServices')));
        expect(source, contains('required this.dependencies'));
      }

      expect(router, contains('assembleDesktopMediaHubDependencies(services)'));
      expect(
        router,
        contains('assembleMobileMediaTransferDependencies(services)'),
      );
      expect(
        router,
        contains('assembleMobileRemoteLibraryDependencies(services)'),
      );
      expect(shell, contains('dependencies: widget.dependencies'));
      expect(assembly, contains('services.mediaShareCatalog'));
      expect(assembly, contains('services.mediaTransferQueueService'));
      expect(
        File(
          'lib/features/transfer/presentation/screens/'
          'cross_device_media_library_screen.dart',
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          'lib/features/transfer/presentation/screens/'
          'desktop_media_transfer_hub_screen.dart',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('remaining ASR consumers receive dependencies from app assembly', () {
    final configDialog = File(
      'lib/features/transcription/presentation/widgets/'
      'transcription_config_dialog.dart',
    ).readAsStringSync();
    final runtimeSetup = File(
      'lib/features/transcription/presentation/widgets/'
      'asr_runtime_setup_dialog.dart',
    ).readAsStringSync();
    final queueBar = File(
      'lib/features/transcription/presentation/widgets/'
      'global_transcription_queue_bar.dart',
    ).readAsStringSync();
    final settingsSection = File(
      'lib/features/settings/presentation/widgets/'
      'ai_transcription_settings_section.dart',
    ).readAsStringSync();
    final smokeCard = File(
      'lib/features/settings/presentation/widgets/'
      'asr_end_to_end_smoke_test_card.dart',
    ).readAsStringSync();
    final settingsScreen = File(
      'lib/features/settings/presentation/screens/settings_screen.dart',
    ).readAsStringSync();
    final app = File('lib/app/app.dart').readAsStringSync();
    final router = File('lib/app/app_router.dart').readAsStringSync();
    final assembly = File(
      'lib/app/transcription_assembly.dart',
    ).readAsStringSync();

    for (final source in [
      configDialog,
      runtimeSetup,
      queueBar,
      settingsSection,
      smokeCard,
    ]) {
      expect(source, isNot(contains('AppServices.instance')));
    }
    expect(configDialog, contains('required this.dependencies'));
    expect(runtimeSetup, contains('required this.dependencies'));
    expect(queueBar, contains('required this.queue'));
    expect(settingsSection, contains('required this.dependencies'));
    expect(smokeCard, contains('required this.smokeTestService'));
    expect(settingsScreen, contains('required this.dependencies'));
    expect(router, contains('assembleSettingsScreenDependencies(services)'));
    expect(app, contains('queue: services.transcriptionQueue'));
    expect(assembly, contains('services.asrRuntimeManager'));
    expect(assembly, contains('services.asrStoragePreflightService'));
    expect(assembly, contains('services.asrManagedStorageService'));
    expect(assembly, contains('services.asrEndToEndSmokeTestService'));
  });
}
