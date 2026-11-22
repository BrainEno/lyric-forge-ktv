/// Song names from file names (decision D-058).
///
/// A video picked from the iPhone's photo library reaches the app under a
/// name the system made up — `image_20312602-F017-4D87-A99C-F527F145A697_
/// 1795329754.mov` — and a song without a title tag is shown by its file
/// name, so the listening home used to show that string as the song's title.
library;

final RegExp _uuid = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
  caseSensitive: false,
);

/// The words pickers put around the number they make up.
const Set<String> _pickerWords = {'image', 'video', 'trim', 'img', 'vid'};

/// Names such as `image_<uuid>_<digits>`, `<uuid>`, `trim.<uuid>` or a bare
/// long number: made up by a picker, not chosen by anyone.
bool isGeneratedMediaName(String stem) {
  final name = stem.trim();
  if (name.isEmpty) return true;
  if (_uuid.hasMatch(name)) return true;
  return RegExp(r'^\d{9,}$').hasMatch(name);
}

/// [stem] without its picker-made parts, or null when nothing readable is
/// left: `image_<uuid>_<digits>` gives null, `周杰伦 - 晴天` stays.
String? readableMediaName(String stem) {
  final name = stem.trim();
  if (!isGeneratedMediaName(name)) return name.isEmpty ? null : name;
  final rest = name
      .replaceAll(_uuid, ' ')
      .replaceAll(RegExp(r'(?<![0-9])[0-9]{6,}(?![0-9])'), ' ')
      .replaceAll(RegExp(r'[_.\-\s]+'), ' ')
      .trim()
      .split(' ')
      .where((word) => !_pickerWords.contains(word.toLowerCase()))
      .join(' ');
  // A stray letter is no name either.
  return rest.length < 2 ? null : rest;
}

/// The title shown for a song without a title tag: its file name without the
/// folder and extension, and 未命名歌曲 for a picker-made name.
String songTitleFromPath(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return readableMediaName(stem) ?? untitledSongTitle;
}

const String untitledSongTitle = '未命名歌曲';

/// The file name an imported file is kept under: the picked name, unless a
/// picker made it up, then 「导入的视频 2026-11-18 14.46」 (or 音频), which
/// reads as a title until the user gives it one.
String importedMediaStem(
  String pickedStem, {
  required bool video,
  required DateTime now,
}) {
  final readable = readableMediaName(pickedStem);
  if (readable != null) return readable;
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}.${two(now.minute)}';
  return '${video ? '导入的视频' : '导入的音频'} $stamp';
}
