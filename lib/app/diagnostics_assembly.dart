import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/diagnostics/app_diagnostics.dart';
import '../core/diagnostics/diagnostics_report.dart';
import '../features/player/domain/repositories/local_media_library_repository.dart';
import '../features/player/domain/services/ktv_microphone_service.dart';
import '../features/project/domain/repositories/project_repository.dart';
import '../features/transcription/domain/models/transcription_models.dart';
import '../features/transcription/domain/services/asr_runtime_manager.dart';
import '../features/transcription/domain/services/transcription_settings_store.dart';

/// Diagnostics live next to the rest of the app's support data, in their own
/// folder so "clear diagnostics" can never touch user content.
AppDiagnostics createAppDiagnostics() => AppDiagnostics(
  directory: () async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}diagnostics');
  },
);

/// Feature sections of the diagnostics report.
///
/// Each one reports state and counts only. Project names, song titles,
/// lyrics and audio never enter the report; paths are reduced by the
/// redactor (`~` instead of the home directory).
void registerAppDiagnosticsSections(
  AppDiagnostics diagnostics, {
  required TranscriptionSettingsStore settingsStore,
  required AsrRuntimeManager runtimeManager,
  required KtvMicrophoneService microphoneService,
  required ProjectRepository projectRepository,
  required LocalMediaLibraryRepository libraryRepository,
}) {
  diagnostics
    ..registerSection(
      DiagnosticsSection(
        id: 'asr',
        title: '本地识别运行环境',
        // Inspecting checks files and may hash a model; give it time.
        timeout: const Duration(seconds: 20),
        collect: () => collectAsrDiagnostics(
          settingsStore: settingsStore,
          runtimeManager: runtimeManager,
        ),
      ),
    )
    ..registerSection(
      DiagnosticsSection(
        id: 'ktv',
        title: 'KTV 麦克风',
        collect: () async => collectKtvMicrophoneDiagnostics(microphoneService),
      ),
    )
    ..registerSection(
      DiagnosticsSection(
        id: 'library',
        title: '资料库规模',
        collect: () => collectLibraryDiagnostics(
          projectRepository: projectRepository,
          libraryRepository: libraryRepository,
        ),
      ),
    );
}

Future<Map<String, Object?>> collectAsrDiagnostics({
  required TranscriptionSettingsStore settingsStore,
  required AsrRuntimeManager runtimeManager,
}) async {
  final config = await settingsStore.load();
  if (config == null) {
    return {'configured': false, 'installing': runtimeManager.isInstalling};
  }
  final status = await runtimeManager.inspect(config);
  final hardware = status.profile.hardware;
  return {
    'configured': true,
    'mode': config.mode.name,
    'profile': status.profile.profile.name,
    'profileLabel': status.profile.label,
    'language': config.language,
    'engineOrder': config.engineOrder.name,
    'decodingProfile': config.whisperDecodingProfile.id,
    'qwenDevice': config.qwenDevice,
    'qwenDtype': config.qwenDtype,
    'ready': status.isReady,
    'baselineReady': status.isBaselineReady,
    'installing': runtimeManager.isInstalling,
    'managedRoot': status.managedRoot,
    'hardware': {
      'os': hardware.operatingSystem,
      'arch': hardware.architecture,
      if (hardware.cpuName != null) 'cpu': hardware.cpuName,
      if (hardware.gpuName != null) 'gpu': hardware.gpuName,
      if (hardware.gpuMemoryMb != null) 'gpuMemoryMb': hardware.gpuMemoryMb,
      if (hardware.systemMemoryMb != null)
        'systemMemoryMb': hardware.systemMemoryMb,
    },
    'components': [
      for (final component in status.components)
        {
          'component': component.component.name,
          'state': component.state.name,
          if (component.detail.trim().isNotEmpty) 'detail': component.detail,
        },
    ],
  };
}

Map<String, Object?> collectKtvMicrophoneDiagnostics(
  KtvMicrophoneService microphoneService,
) {
  final state = microphoneService.currentState;
  final selected = state.selectedInputDevice;
  return {
    'inputDevices': state.inputDevices.length,
    // The device label helps tell a USB interface from a built-in mic;
    // the platform id is an opaque handle and is left out.
    'selectedDevice':
        selected?.label ?? (state.inputDevices.isEmpty ? null : '系统默认'),
    'monitoring': state.isMonitoring,
    'permissionDenied': state.permissionDenied,
    'micGain': double.parse(state.micGain.toStringAsFixed(2)),
    'monitorDelayMs': state.monitorDelay.inMilliseconds,
    'engineLatencyMs': state.engineLatency?.inMilliseconds,
    if (state.error != null) 'error': state.error,
  };
}

Future<Map<String, Object?>> collectLibraryDiagnostics({
  required ProjectRepository projectRepository,
  required LocalMediaLibraryRepository libraryRepository,
}) async {
  final projects = await projectRepository.getAllProjects();
  final entries = await libraryRepository.getAll();
  final roots = await libraryRepository.getRoots();
  return {
    'projects': projects.length,
    'libraryEntries': entries.length,
    'libraryRoots': roots.length,
  };
}
