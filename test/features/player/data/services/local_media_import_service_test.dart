import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyric_forge_ktv/features/player/data/services/local_media_import_service.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/media_audio_extractor.dart';
import 'package:lyric_forge_ktv/features/player/domain/services/media_import_service.dart';

class _FakeExtractor implements MediaAudioExtractor {
  final calls = <(String, String)>[];
  MediaAudioExtractionException? failure;

  @override
  Future<ExtractedAudio> extractAudio({
    required String inputPath,
    required String outputPath,
  }) async {
    calls.add((inputPath, outputPath));
    final error = failure;
    if (error != null) throw error;
    await File(outputPath).writeAsBytes(List.filled(16, 1));
    return ExtractedAudio(
      path: outputPath,
      duration: const Duration(seconds: 3),
    );
  }
}

void main() {
  late Directory temp;
  late Directory picked;
  late Directory library;
  late _FakeExtractor extractor;
  late List<List<String>> sunk;
  late int cleanUps;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('media_import_test');
    picked = await Directory('${temp.path}/picked').create();
    library = await Directory('${temp.path}/Imported Audio').create();
    extractor = _FakeExtractor();
    sunk = [];
    cleanUps = 0;
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<PickedMediaFile> pickedFile(String name, {int bytes = 32}) async {
    final file = File('${picked.path}/$name');
    await file.writeAsBytes(List.filled(bytes, 7));
    return PickedMediaFile(name: name, path: file.path);
  }

  LocalMediaImportService service(
    List<PickedMediaFile>? files, {
    bool supportsVideo = true,
  }) => LocalMediaImportService(
    extractor: extractor,
    onImported: (paths) async => sunk.add(paths),
    pick: (_) async => files,
    importDirectory: () async => library,
    cleanUpPickerFiles: () async => cleanUps++,
    supportsVideo: supportsVideo,
  );

  test('classifies files by extension', () {
    expect(mediaImportKindOf('/a/song.MP3'), MediaImportKind.audio);
    expect(mediaImportKindOf('clip.mov'), MediaImportKind.video);
    expect(mediaImportKindOf('clip.webm'), MediaImportKind.video);
    expect(mediaImportKindOf('notes.txt'), MediaImportKind.unsupported);
    expect(mediaImportKindOf('noextension'), MediaImportKind.unsupported);
    expect(mediaImportKindOf('/dir.mp3/file'), MediaImportKind.unsupported);
  });

  test(
    'audio is copied into the import folder and added to the library',
    () async {
      final song = await pickedFile('晴天.mp3');
      final result = await service([song]).importMedia(MediaImportSource.files);

      expect(result.importedPaths, ['${library.path}/晴天.mp3']);
      expect(File(result.importedPaths.single).existsSync(), isTrue);
      expect(result.extractedFromVideo, 0);
      expect(result.failures, isEmpty);
      expect(sunk, [result.importedPaths]);
      expect(cleanUps, 1);
    },
  );

  test('the same song picked twice is kept once', () async {
    final song = await pickedFile('晴天.mp3');
    await service([song]).importMedia(MediaImportSource.files);
    final again = await service([song]).importMedia(MediaImportSource.files);

    expect(again.importedPaths, ['${library.path}/晴天.mp3']);
    expect(library.listSync(), hasLength(1));
  });

  test('a different file with a taken name gets a numbered name', () async {
    await File('${library.path}/晴天.mp3').writeAsBytes([1, 2, 3]);
    final song = await pickedFile('晴天.mp3', bytes: 64);
    final result = await service([song]).importMedia(MediaImportSource.files);

    expect(result.importedPaths, ['${library.path}/晴天 (2).mp3']);
  });

  test('a video is turned into an m4a next to the songs', () async {
    final video = await pickedFile('演唱会.MOV');
    final steps = <MediaImportProgress>[];
    final result = await service([
      video,
    ]).importMedia(MediaImportSource.photoLibrary, onProgress: steps.add);

    expect(result.importedPaths, ['${library.path}/演唱会.m4a']);
    expect(result.extractedFromVideo, 1);
    expect(extractor.calls.single.$1, video.path);
    expect(steps.single.phase, MediaImportPhase.extracting);
    expect(steps.single.total, 1);
    // The video itself is not kept.
    expect(library.listSync().map((entry) => entry.path), [
      '${library.path}/演唱会.m4a',
    ]);
  });

  test('a video without sound is reported, the rest still imports', () async {
    final video = await pickedFile('silent.mp4');
    final song = await pickedFile('song.m4a');
    extractor.failure = const MediaAudioExtractionException(
      MediaAudioExtractionException.noAudio,
    );
    final result = await service([
      video,
      song,
    ]).importMedia(MediaImportSource.files);

    expect(result.importedPaths, ['${library.path}/song.m4a']);
    expect(result.failures.single.name, 'silent.mp4');
    expect(result.failures.single.reason, '这个视频没有声音');
    expect(File('${library.path}/silent.m4a').existsSync(), isFalse);
    expect(sunk.single, ['${library.path}/song.m4a']);
  });

  test('unsupported files and platforms are reported', () async {
    final text = await pickedFile('notes.txt');
    final video = await pickedFile('clip.mp4');
    final result = await service([
      text,
      video,
    ], supportsVideo: false).importMedia(MediaImportSource.files);

    expect(result.importedPaths, isEmpty);
    expect(result.failures.map((failure) => failure.reason), [
      '不支持的文件格式',
      '这台设备暂不支持从视频提取声音',
    ]);
    expect(sunk, isEmpty);
  });

  test('cancelling the picker imports nothing', () async {
    final result = await service(null).importMedia(MediaImportSource.files);
    expect(result.cancelled, isTrue);
    expect(sunk, isEmpty);
  });

  test('file names are made safe and unique', () async {
    expect(
      LocalMediaImportService.safeFileName('a/b:c?.mp3', fallback: 'x'),
      'b_c_.mp3',
    );
    expect(LocalMediaImportService.safeFileName('  ', fallback: 'x'), 'x');
    await File('${library.path}/a.m4a').writeAsBytes([1]);
    await File('${library.path}/a (2).m4a').writeAsBytes([1]);
    final unique = await LocalMediaImportService.uniqueFile(library, 'a.m4a');
    expect(unique.path, '${library.path}/a (3).m4a');
  });
}
