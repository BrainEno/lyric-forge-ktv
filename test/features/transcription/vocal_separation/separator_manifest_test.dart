import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/transcription/data/services/separator_manifest.dart';

const _sha = 'aa11bb22cc33dd44ee55ff6600778899aa11bb22cc33dd44ee55ff6600778899';

/// The manifest exactly as `build-vocal-separator.yml` writes it.
Map<String, Object?> _manifest({
  Object? schemaVersion = 1,
  Object? revision = 'htdemucs-ft-vocals-onnx-v1',
  Object? executable = 'bin/lyricforge-separator.exe',
  Object? modelFile = 'models/htdemucs_ft_vocals.onnx',
  Object? bytes = 168000000,
  Object? sha256 = _sha,
  Object? vocalsIndex = 3,
  Object? providers = const ['dml', 'cpu'],
}) => {
  'schemaVersion': schemaVersion,
  'separatorRevision': revision,
  'platform': 'windows-x64',
  'executable': executable,
  'providers': providers,
  'model': {
    'file': modelFile,
    'bytes': bytes,
    'sha256': sha256,
    'sources': ['drums', 'bass', 'other', 'vocals'],
    'vocalsIndex': vocalsIndex,
    'sampleRate': 44100,
  },
  'onnxRuntime': '1.22.0',
  'directML': '1.15.4',
  'demucsOnnxRevision': '81fa1920bd2b5aa2a39d0f95b35b5e1b8b17a1c0',
  'builtAt': '2026-11-18T08:00:00.0000000Z',
};

SeparatorManifest _parse(Map<String, Object?> json) =>
    SeparatorManifest.parse(jsonEncode(json));

void main() {
  group('SeparatorManifest.parse', () {
    test('reads the manifest the release workflow writes', () {
      final manifest = _parse(_manifest());
      expect(manifest.separatorRevision, 'htdemucs-ft-vocals-onnx-v1');
      expect(manifest.platform, 'windows-x64');
      expect(manifest.executable, 'bin/lyricforge-separator.exe');
      expect(manifest.modelFile, 'models/htdemucs_ft_vocals.onnx');
      expect(manifest.modelBytes, 168000000);
      expect(manifest.modelSha256, _sha);
      expect(manifest.vocalsIndex, 3);
      expect(manifest.providers, ['dml', 'cpu']);
    });

    test('tolerates the byte-order mark Windows PowerShell may add', () {
      final manifest = SeparatorManifest.parse(
        '\uFEFF${jsonEncode(_manifest())}',
      );
      expect(manifest.vocalsIndex, 3);
    });

    test('normalises an upper-case digest and backslash paths', () {
      final manifest = _parse(
        _manifest(
          sha256: _sha.toUpperCase(),
          executable: r'bin\lyricforge-separator.exe',
        ),
      );
      expect(manifest.modelSha256, _sha);
      expect(manifest.executable, 'bin/lyricforge-separator.exe');
    });

    test('ignores provider entries that are not strings', () {
      final manifest = _parse(_manifest(providers: ['dml', 7, null, 'cpu']));
      expect(manifest.providers, ['dml', 'cpu']);
      expect(_parse(_manifest(providers: 'dml')).providers, isEmpty);
    });

    test('rejects text that is not a JSON object', () {
      expect(
        () => SeparatorManifest.parse('not json'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => SeparatorManifest.parse('[1, 2]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unknown schema version', () {
      for (final version in [null, 0, 2, '1']) {
        expect(
          () => _parse(_manifest(schemaVersion: version)),
          throwsA(isA<FormatException>()),
          reason: 'schemaVersion $version',
        );
      }
    });

    test('requires a model entry with a positive size', () {
      expect(
        () => _parse(_manifest()..remove('model')),
        throwsA(isA<FormatException>()),
      );
      for (final bytes in [null, 0, -1, 1.5, '100']) {
        expect(
          () => _parse(_manifest(bytes: bytes)),
          throwsA(isA<FormatException>()),
          reason: 'bytes $bytes',
        );
      }
    });

    test('requires a well-formed SHA-256 digest', () {
      for (final sha in [null, '', 'abc', '${_sha}00', 'g' * 64]) {
        expect(
          () => _parse(_manifest(sha256: sha)),
          throwsA(isA<FormatException>()),
          reason: 'sha256 $sha',
        );
      }
    });

    test('requires a plausible vocals index', () {
      for (final index in [null, -1, 16, '3', 3.0]) {
        expect(
          () => _parse(_manifest(vocalsIndex: index)),
          throwsA(isA<FormatException>()),
          reason: 'vocalsIndex $index',
        );
      }
      expect(_parse(_manifest(vocalsIndex: 0)).vocalsIndex, 0);
    });

    test('requires the revision and the executable', () {
      for (final manifest in [
        _manifest(revision: null),
        _manifest(revision: '  '),
        _manifest(executable: null),
        _manifest(modelFile: ''),
      ]) {
        expect(() => _parse(manifest), throwsA(isA<FormatException>()));
      }
    });

    test('keeps every path inside the bundle', () {
      for (final path in [
        '/usr/bin/sh',
        r'C:\Windows\System32\cmd.exe',
        'c:/evil.exe',
        '../outside.exe',
        'bin/../../outside.exe',
        r'bin\..\..\outside.exe',
        'bin//double.exe',
        'bin/',
      ]) {
        expect(
          () => _parse(_manifest(executable: path)),
          throwsA(isA<FormatException>()),
          reason: path,
        );
        expect(
          () => _parse(_manifest(modelFile: path)),
          throwsA(isA<FormatException>()),
          reason: path,
        );
      }
    });
  });
}
