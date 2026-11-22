package io.github.braineno.lyricforge

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaAudioExtractor.register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
