import 'dart:io';
import 'dart:typed_data';

import '../../../../core/diagnostics/app_logger.dart';
import '../../../../core/diagnostics/operation_timings.dart';
import '../../../../core/diagnostics/process_memory.dart';
import '../../domain/models/transcription_degradation.dart';
import '../../domain/models/transcription_models.dart';
import '../../domain/services/transcription_service.dart';

/// Measures every recognition run and logs its outcome without changing it.
///
/// The sample carries the song length read from the normalised WAV, so the
/// diagnostics report shows a real-time factor per engine mode: the number
/// that tells whether a 5-minute song takes 2 or 20 minutes on this machine.
/// Only metadata is recorded (mode, language, line count, failure kind,
/// process memory); lyric text and paths are not.
class TimedTranscriptionService implements TranscriptionService {
  TimedTranscriptionService({
    required TranscriptionService delegate,
    required OperationTimings timings,
    AppLogger? logger,
    Future<Duration?> Function(String path)? mediaDurationOf,
    Map<String, Object?> Function()? memoryProbe,
  }) : _delegate = delegate,
       _timings = timings,
       _logger = logger ?? appLog,
       _mediaDurationOf = mediaDurationOf ?? readPcmWavDuration,
       _memoryProbe = memoryProbe ?? processMemoryAttributes;

  static const String operation = 'transcription.transcribe';
  static const String logTag = 'transcription';

  final TranscriptionService _delegate;
  final OperationTimings _timings;
  final AppLogger _logger;
  final Future<Duration?> Function(String path) _mediaDurationOf;
  final Map<String, Object?> Function() _memoryProbe;

  @override
  Stream<TranscriptionProgress> get progressStream => _delegate.progressStream;

  @override
  bool get isRunning => _delegate.isRunning;

  @override
  Future<TranscriptionResult> transcribe(TranscriptionRequest request) async {
    final config = request.config;
    final attributes = <String, Object?>{
      'mode': config.mode.name,
      'language': config.language,
      'decodingProfile': config.whisperDecodingProfile.id,
    };
    _logger.info(
      logTag,
      'Recognition started (mode ${config.mode.name}, '
      'language ${config.language})',
    );
    final span = _timings.start(operation);
    final TranscriptionResult result;
    try {
      result = await _delegate.transcribe(request);
    } on TranscriptionException catch (error, stackTrace) {
      final cancelled = error.kind == TranscriptionFailureKind.cancelled;
      span.finish(
        outcome: cancelled
            ? OperationOutcome.cancelled
            : OperationOutcome.failure,
        attributes: {...attributes, 'failureKind': error.kind.name},
      );
      if (cancelled) {
        _logger.info(logTag, 'Recognition cancelled');
      } else {
        _logger.warning(
          logTag,
          'Recognition failed (${error.kind.name}): ${error.message}'
          '${_detailsSuffix(error.details)}',
          stackTrace: stackTrace,
        );
      }
      rethrow;
    } catch (error, stackTrace) {
      span.finish(
        outcome: OperationOutcome.failure,
        attributes: {...attributes, 'failureKind': 'unexpected'},
      );
      _logger.error(
        logTag,
        'Recognition failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    Duration? media;
    try {
      media = await _mediaDurationOf(result.normalizedAudioPath);
    } catch (_) {
      media = null;
    }
    final metadata = result.lyrics.metadata;
    final sample = span.finish(
      mediaDuration: media,
      attributes: {
        ...attributes,
        'detectedLanguage': result.detectedLanguage,
        'lines': result.lyrics.lines.length,
        if (metadata['primaryEngine'] is String)
          'primaryEngine': metadata['primaryEngine'],
        if (TranscriptionQualityMetadata.isDegraded(metadata)) 'degraded': true,
        if (TranscriptionQualityMetadata.reasonOf(metadata) case final reason?)
          'degradationReason': reason.name,
        ..._memoryProbe(),
      },
    );
    _logger.info(
      logTag,
      'Recognition finished: ${result.lyrics.lines.length} lines'
      '${sample?.realTimeFactor == null ? '' : ', RTF ${sample!.realTimeFactor!.toStringAsFixed(2)}'}',
    );
    return result;
  }

  @override
  Future<void> cancel() => _delegate.cancel();

  @override
  Future<void> dispose() => _delegate.dispose();
}

/// A failure's `details` (exit code, stderr tail), capped so one engine dump
/// cannot flood the log. The logger redacts it with the message.
String _detailsSuffix(String? details) {
  final text = details?.trim();
  if (text == null || text.isEmpty) return '';
  const limit = 600;
  return text.length <= limit
      ? ' — $text'
      : ' — ${text.substring(text.length - limit)}';
}

/// Duration of a PCM WAV file from its `fmt ` and `data` chunks, or null if
/// the file is missing or not a WAV this reader understands. Reads only the
/// header, never the samples.
Future<Duration?> readPcmWavDuration(String path) async {
  if (path.isEmpty) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  final handle = await file.open();
  try {
    final header = await handle.read(4096);
    return pcmWavDurationFromHeader(header, fileLength: await file.length());
  } finally {
    await handle.close();
  }
}

/// Parses a RIFF/WAVE header. [fileLength] caps a `data` chunk whose size is
/// written as 0 or 0xFFFFFFFF by streaming encoders.
Duration? pcmWavDurationFromHeader(Uint8List header, {int? fileLength}) {
  if (header.length < 12) return null;
  final bytes = ByteData.sublistView(header);
  String tag(int offset) =>
      String.fromCharCodes(header.sublist(offset, offset + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
  int? byteRate;
  var offset = 12;
  while (offset + 8 <= header.length) {
    final id = tag(offset);
    final size = bytes.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ' && body + 16 <= header.length) {
      byteRate = bytes.getUint32(body + 8, Endian.little);
    } else if (id == 'data') {
      final rate = byteRate;
      if (rate == null || rate <= 0) return null;
      var dataBytes = size;
      if (fileLength != null) {
        final available = fileLength - body;
        if (dataBytes == 0 || dataBytes == 0xFFFFFFFF || dataBytes > available) {
          dataBytes = available;
        }
      }
      if (dataBytes <= 0) return null;
      return Duration(microseconds: (dataBytes * 1000000) ~/ rate);
    }
    // Chunks are word aligned.
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  return null;
}
