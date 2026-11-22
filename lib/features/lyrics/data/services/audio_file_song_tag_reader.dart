import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../../domain/online/song_tags.dart';

/// Reads the title, artist, album and length from an audio file's tags for
/// the online lyric search (D-055).
///
/// Cover art is not decoded and nothing is written: this only answers "what
/// does the file say the song is". Unreadable or untagged files give null.
Future<SongTags?> readAudioFileSongTags(String audioPath) async {
  final file = File(audioPath);
  if (!await file.exists()) return null;
  try {
    final metadata = readMetadata(file, getImage: false);
    final tags = SongTags(
      title: _clean(metadata.title),
      artist: _clean(metadata.artist),
      album: _clean(metadata.album),
      duration: metadata.duration,
    );
    return tags.isEmpty ? null : tags;
  } on Object {
    // Formats the reader does not know, or a damaged header: the search
    // simply goes ahead with the project name.
    return null;
  }
}

String? _clean(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
