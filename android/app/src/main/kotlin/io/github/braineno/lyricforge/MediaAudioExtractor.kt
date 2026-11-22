package io.github.braineno.lyricforge

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

/**
 * Copies the AAC sound track of a video into an `.m4a` file without
 * re-encoding (decision D-056). Dart side: `MethodChannelMediaAudioExtractor`.
 */
object MediaAudioExtractor {
    private const val CHANNEL = "io.github.braineno.lyricforge/media_audio"

    private class ExtractionError(val code: String, message: String) : Exception(message)

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "extractAudio") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val input = call.argument<String>("input")
            val output = call.argument<String>("output")
            if (input == null || output == null) {
                result.error("export-failed", "input and output are required", null)
                return@setMethodCallHandler
            }
            val main = Handler(Looper.getMainLooper())
            Thread {
                try {
                    val durationMs = extract(input, output)
                    val reply = HashMap<String, Any>()
                    reply["path"] = output
                    if (durationMs != null && durationMs > 0) reply["durationMs"] = durationMs
                    main.post { result.success(reply) }
                } catch (error: ExtractionError) {
                    File(output).delete()
                    main.post { result.error(error.code, error.message, null) }
                } catch (error: Exception) {
                    File(output).delete()
                    main.post { result.error("export-failed", error.message ?: error.toString(), null) }
                }
            }.start()
        }
    }

    private fun extract(input: String, output: String): Long? {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var started = false
        try {
            extractor.setDataSource(input)
            var trackIndex = -1
            var format: MediaFormat? = null
            for (index in 0 until extractor.trackCount) {
                val candidate = extractor.getTrackFormat(index)
                val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = index
                    format = candidate
                    break
                }
            }
            if (trackIndex < 0 || format == null) {
                throw ExtractionError("no-audio", "这个视频没有声音")
            }
            val mime = format.getString(MediaFormat.KEY_MIME)
            if (mime != MediaFormat.MIMETYPE_AUDIO_AAC) {
                throw ExtractionError("unsupported-codec", "音轨格式 $mime 暂不支持")
            }
            extractor.selectTrack(trackIndex)
            File(output).delete()
            val writer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = writer
            val outputTrack = writer.addTrack(format)
            writer.start()
            started = true

            val maxInput = if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
            } else {
                0
            }
            val buffer = ByteBuffer.allocate(maxOf(maxInput, 512 * 1024))
            val info = MediaCodec.BufferInfo()
            while (true) {
                buffer.clear()
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                info.offset = 0
                info.size = size
                info.presentationTimeUs = extractor.sampleTime
                info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                }
                writer.writeSampleData(outputTrack, buffer, info)
                extractor.advance()
            }
            writer.stop()
            started = false
            return if (format.containsKey(MediaFormat.KEY_DURATION)) {
                format.getLong(MediaFormat.KEY_DURATION) / 1000
            } else {
                null
            }
        } finally {
            try {
                if (started) muxer?.stop()
            } catch (ignored: Exception) {
                // Already failing; the partial file is deleted by the caller.
            }
            try {
                muxer?.release()
            } catch (ignored: Exception) {
                // Releasing a broken muxer can throw; nothing else to free.
            }
            extractor.release()
        }
    }
}
