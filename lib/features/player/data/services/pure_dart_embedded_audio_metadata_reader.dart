import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/embedded_audio_metadata.dart';
import '../../domain/services/embedded_audio_metadata_reader.dart';

class PureDartEmbeddedAudioMetadataReader
    implements EmbeddedAudioMetadataReader {
  final Directory? rootDirectory;

  const PureDartEmbeddedAudioMetadataReader({this.rootDirectory});

  @override
  Future<EmbeddedAudioMetadata> read(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw FileSystemException('Audio file does not exist', sourcePath);
    }

    final stat = await file.stat();
    final metadata = readMetadata(file, getImage: true);
    final picture = _preferredPicture(metadata.pictures);
    final artworkPath = picture == null
        ? null
        : await _persistArtwork(
            sourcePath: file.absolute.path,
            bytes: picture.bytes,
            mimeType: picture.mimetype,
          );

    return EmbeddedAudioMetadata(
      sourcePath: file.absolute.path,
      title: _clean(metadata.title),
      artist: _clean(metadata.artist),
      album: _clean(metadata.album),
      artworkPath: artworkPath,
      genres: metadata.genres
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
      trackNumber: metadata.trackNumber,
      year: metadata.year?.year,
      duration: metadata.duration,
      sourceSizeBytes: stat.size,
      sourceModifiedAt: stat.modified,
      scannedAt: DateTime.now(),
    );
  }

  Picture? _preferredPicture(List<Picture> pictures) {
    if (pictures.isEmpty) return null;
    for (final picture in pictures) {
      if (picture.pictureType == PictureType.coverFront) return picture;
    }
    return pictures.first;
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<Directory> _artworkDirectory() async {
    if (rootDirectory != null) {
      final directory = Directory(
        rootDirectory!.path + Platform.pathSeparator + 'EmbeddedArtwork',
      );
      await directory.create(recursive: true);
      return directory;
    }

    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      support.path +
          Platform.pathSeparator +
          'LyricForge' +
          Platform.pathSeparator +
          'Data' +
          Platform.pathSeparator +
          'EmbeddedArtwork',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String?> _persistArtwork({
    required String sourcePath,
    required List<int> bytes,
    required String mimeType,
  }) async {
    if (bytes.isEmpty) return null;
    final directory = await _artworkDirectory();
    final extension = _imageExtension(mimeType);
    final file = File(
      directory.path +
          Platform.pathSeparator +
          '${_stablePathHash(sourcePath)}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  String _imageExtension(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/bmp':
        return 'bmp';
      case 'image/jpeg':
      case 'image/jpg':
      default:
        return 'jpg';
    }
  }

  String _stablePathHash(String value) {
    var hash = 0xcbf29ce484222325;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
