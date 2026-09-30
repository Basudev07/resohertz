package com.resohertz.resohertz

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val permissionChannelName = "com.resohertz/microphone"
    private val audioStreamChannelName = "com.resohertz/audio_stream"
    private val storageChannelName = "com.resohertz/storage"
    private val audioFeedbackChannelName = "com.resohertz/audio_feedback"
    private val recordAudioRequestCode = 1001

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var inTunePlayer: MediaPlayer? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    @Volatile
    private var feedbackMuteUntilMs: Long = 0L

    // Audio capture state
    private var audioRecord: AudioRecord? = null
    @Volatile
    private var isRecording = false
    private var recordingThread: Thread? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var audioEventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Permission & Hardware query MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermission" -> {
                        val granted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    }
                    "requestPermission" -> {
                        val alreadyGranted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        if (alreadyGranted) {
                            result.success(true)
                        } else {
                            if (pendingPermissionResult != null) {
                                result.error(
                                    "CONCURRENT_REQUEST",
                                    "Permission request already in progress",
                                    null
                                )
                            } else {
                                pendingPermissionResult = result
                                ActivityCompat.requestPermissions(
                                    this,
                                    arrayOf(Manifest.permission.RECORD_AUDIO),
                                    recordAudioRequestCode
                                )
                            }
                        }
                    }
                    "initializeMicrophone" -> {
                        val sampleRate = ((call.argument<Any>("sampleRate")) as? Number)?.toInt() ?: 44100
                        val channelConfig = AudioFormat.CHANNEL_IN_MONO
                        val audioFormat = AudioFormat.ENCODING_PCM_16BIT

                        try {
                            val minBufferSize = AudioRecord.getMinBufferSize(
                                sampleRate,
                                channelConfig,
                                audioFormat
                            )
                            if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
                                result.success(
                                    mapOf(
                                        "isAvailable" to false,
                                        "sampleRate" to sampleRate,
                                        "minBufferSize" to minBufferSize,
                                        "error" to "UNSUPPORTED_CONFIGURATION"
                                    )
                                )
                            } else {
                                result.success(
                                    mapOf(
                                        "isAvailable" to true,
                                        "sampleRate" to sampleRate,
                                        "minBufferSize" to minBufferSize,
                                        "error" to null
                                    )
                                )
                            }
                        } catch (e: Exception) {
                            result.success(
                                mapOf(
                                    "isAvailable" to false,
                                    "sampleRate" to sampleRate,
                                    "minBufferSize" to 0,
                                    "error" to e.localizedMessage
                                )
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Custom Tunings Local Storage MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannelName)
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("resohertz_prefs", Context.MODE_PRIVATE)
                when (call.method) {
                    "saveCustomTunings" -> {
                        val json = call.argument<String>("json")
                        prefs.edit().putString("custom_tunings", json).apply()
                        result.success(true)
                    }
                    "loadCustomTunings" -> {
                        val json = prefs.getString("custom_tunings", null)
                        result.success(json)
                    }
                    "clearCustomTunings" -> {
                        prefs.edit().remove("custom_tunings").apply()
                        result.success(true)
                    }
                    "saveSettings" -> {
                        val json = call.argument<String>("json")
                        prefs.edit().putString("app_settings", json).apply()
                        result.success(true)
                    }
                    "loadSettings" -> {
                        val json = prefs.getString("app_settings", null)
                        result.success(json)
                    }
                    "clearSettings" -> {
                        prefs.edit().remove("app_settings").apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // In-tune Audio Feedback MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioFeedbackChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playInTuneSound" -> {
                        val durationMs = playInTuneSound()
                        result.success(durationMs)
                    }
                    else -> result.notImplemented()
                }
            }

        // Raw Audio PCM stream EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, audioStreamChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audioEventSink = events
                    startAudioCapture(arguments, events)
                }

                override fun onCancel(arguments: Any?) {
                    stopAudioCapture()
                    audioEventSink = null
                }
            })
    }

    private fun startAudioCapture(arguments: Any?, events: EventChannel.EventSink?) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            events?.error("PERMISSION_DENIED", "Microphone permission is required to capture audio", null)
            return
        }

        if (isRecording) {
            stopAudioCapture()
        }

        val sampleRate = ((arguments as? Map<*, *>)?.get("sampleRate") as? Number)?.toInt() ?: 44100
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)

        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            events?.error("UNSUPPORTED_CONFIGURATION", "Audio hardware does not support configuration", null)
            return
        }

        // Ensure buffer size is at least 4096 bytes (2048 16-bit samples)
        val bufferSize = maxOf(minBufferSize * 2, 4096)

        try {
            var record: AudioRecord? = null
            try {
                // VOICE_RECOGNITION disables hardware AGC and aggressive noise-boosting in quiet rooms
                record = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )
            } catch (e: Exception) {
                record = null
            }

            if (record == null || record.state != AudioRecord.STATE_INITIALIZED) {
                record?.release()
                record = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    sampleRate,
                    channelConfig,
                    audioFormat,
                    bufferSize
                )
            }

            if (record.state != AudioRecord.STATE_INITIALIZED) {
                record.release()
                events?.error("INIT_FAILED", "AudioRecord failed to initialize", null)
                return
            }

            record.startRecording()
            if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                record.release()
                events?.error("START_FAILED", "AudioRecord failed to start recording", null)
                return
            }

            audioRecord = record
            isRecording = true

            // Activate hardware AcousticEchoCanceler if supported by device audio HAL
            if (AcousticEchoCanceler.isAvailable()) {
                try {
                    echoCanceler = AcousticEchoCanceler.create(record.audioSessionId)?.apply {
                        enabled = true
                    }
                } catch (e: Exception) {
                    // OEM hardware fallback
                }
            }

            recordingThread = Thread({
                // Fixed buffer: 2048 16-bit samples = 4096 bytes
                val chunkSizeBytes = 4096
                val buffer = ByteArray(chunkSizeBytes)

                while (isRecording) {
                    val bytesRead = record.read(buffer, 0, buffer.size)
                    if (bytesRead > 0 && isRecording) {
                        val isMutedByFeedback = SystemClock.elapsedRealtime() < feedbackMuteUntilMs
                        // If feedback chime is sounding through the speaker, mute microphone chunk with zeros
                        // so the pitch detector doesn't pick up the phone's own speaker and enter infinite resonance!
                        val chunk = if (isMutedByFeedback) {
                            ByteArray(bytesRead)
                        } else {
                            buffer.copyOf(bytesRead)
                        }
                        mainHandler.post {
                            if (isRecording) {
                                audioEventSink?.success(chunk)
                            }
                        }
                    } else if (bytesRead < 0) {
                        mainHandler.post {
                            if (isRecording) {
                                audioEventSink?.error(
                                    "READ_ERROR",
                                    "AudioRecord.read returned error code: $bytesRead",
                                    null
                                )
                            }
                        }
                        break
                    }
                }
            }, "ResoHertzAudioCapture")

            recordingThread?.start()
        } catch (e: Exception) {
            events?.error("CAPTURE_ERROR", e.localizedMessage, null)
            stopAudioCapture()
        }
    }

    private fun stopAudioCapture() {
        isRecording = false
        try {
            recordingThread?.interrupt()
            recordingThread?.join(300)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        recordingThread = null

        try {
            audioRecord?.let { record ->
                if (record.state == AudioRecord.STATE_INITIALIZED) {
                    if (record.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        record.stop()
                    }
                }
                record.release()
            }
        } catch (e: Exception) {
            // Safe cleanup
        }
        audioRecord = null

        try {
            echoCanceler?.release()
            echoCanceler = null
        } catch (e: Exception) {
            // Safe cleanup
        }
    }

    private fun playInTuneSound(): Long {
        try {
            val assetLookupKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("lib/audio/success.mp3")
            val assetDescriptor = assets.openFd(assetLookupKey)
            inTunePlayer?.release()
            val player = MediaPlayer()
            inTunePlayer = player
            player.setDataSource(
                assetDescriptor.fileDescriptor,
                assetDescriptor.startOffset,
                assetDescriptor.length
            )
            assetDescriptor.close()
            player.prepare()
            val soundDurationMs = player.duration.toLong().coerceAtLeast(1000L)
            // Suppress microphone chunk transmission during speaker output plus acoustic decay window
            feedbackMuteUntilMs = SystemClock.elapsedRealtime() + soundDurationMs + 300L
            player.start()
            player.setOnCompletionListener { mp ->
                mp.release()
                if (inTunePlayer == mp) {
                    inTunePlayer = null
                }
            }
            return soundDurationMs
        } catch (e: Exception) {
            // Safe handling if asset not present or audio output busy
            return 1200L
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == recordAudioRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    override fun onPause() {
        super.onPause()
        stopAudioCapture()
        try {
            inTunePlayer?.release()
        } catch (e: Exception) {}
        inTunePlayer = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopAudioCapture()
        try {
            inTunePlayer?.release()
        } catch (e: Exception) {}
        inTunePlayer = null
        pendingPermissionResult = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
