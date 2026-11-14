import 'dart:io';

/// Copies [store] to a new sibling file named
/// `<store>.incomplete-<timestamp>.json` and verifies the copy byte for byte
/// before returning its path.
///
/// Used before a partly readable store is rewritten with its readable records,
/// so the unreadable rows stay recoverable by hand instead of relying on the
/// single rolling `.bak` sidecar that the next write would replace (#439).
Future<String> preserveIncompleteStoreCopy(
  File store, {
  DateTime Function() clock = DateTime.now,
}) async {
  if (!await store.exists()) {
    throw FileSystemException(
      'The store file to preserve no longer exists',
      store.path,
    );
  }
  final stamp = _timestamp(clock());
  var candidate = File('${store.path}.incomplete-$stamp.json');
  var suffix = 2;
  while (await candidate.exists()) {
    candidate = File('${store.path}.incomplete-$stamp-$suffix.json');
    suffix += 1;
  }

  await store.copy(candidate.path);
  final original = await store.readAsBytes();
  final copied = await candidate.readAsBytes();
  if (!_sameBytes(original, copied)) {
    try {
      await candidate.delete();
    } on FileSystemException {
      // Leave a mismatched copy rather than hide the verification failure.
    }
    throw FileSystemException(
      'The preserved copy does not match the original store',
      candidate.path,
    );
  }
  return candidate.path;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

String _timestamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  return '${local.year}${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
}
