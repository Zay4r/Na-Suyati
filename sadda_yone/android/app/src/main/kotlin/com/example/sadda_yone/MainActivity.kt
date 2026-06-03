package com.example.sadda_yone

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "sadda_yone/audio_player"
    private var audioTrack: AudioTrack? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playPcm" -> {
                        val bytes = call.argument<ByteArray>("bytes")!!
                        val sampleRate = call.argument<Int>("sampleRate")!!
                        thread {
                            playPcm(bytes, sampleRate)
                            result.success(null)
                        }
                    }
                    "stopPcm" -> {
                        audioTrack?.stop()
                        audioTrack?.release()
                        audioTrack = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playPcm(bytes: ByteArray, sampleRate: Int) {
        audioTrack?.stop()
        audioTrack?.release()

        val bufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        audioTrack?.play()

        val chunkSize = 4096
        var offset = 0
        while (offset < bytes.size) {
            val end = minOf(offset + chunkSize, bytes.size)
            audioTrack?.write(bytes, offset, end - offset)
            offset = end
        }

        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
    }
}
