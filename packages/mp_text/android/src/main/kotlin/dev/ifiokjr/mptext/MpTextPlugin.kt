package dev.ifiokjr.mptext

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.tasks.text.textproofreader.TextProofreader
import com.google.mediapipe.tasks.text.textproofreader.TextProofreaderResult
import com.google.mediapipe.tasks.text.textproofreader.TextProofreaderStreamingResult
import com.google.mediapipe.tasks.text.textsummarizer.TextSummarizer
import com.google.mediapipe.tasks.text.textsummarizer.TextSummarizerStreamingResult
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

/** Android implementation of the mobile-only MediaPipe text generation tasks. */
class MpTextPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private val nextHandle = AtomicLong(1)
    private val proofreaders = ConcurrentHashMap<Long, TextProofreader>()
    private val summarizers = ConcurrentHashMap<Long, TextSummarizer>()

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            when (call.method) {
                "proofreader.create" -> createProofreader(call, result)
                "proofreader.proofread" -> proofread(call, result)
                "proofreader.stream" -> proofreadStreaming(call, result)
                "proofreader.close" -> closeProofreader(call, result)
                "summarizer.create" -> createSummarizer(call, result)
                "summarizer.summarize" -> summarize(call, result)
                "summarizer.stream" -> summarizeStreaming(call, result)
                "summarizer.close" -> closeSummarizer(call, result)
                else -> result.notImplemented()
            }
        } catch (error: IllegalArgumentException) {
            result.error("invalid_argument", error.message, null)
        }
    }

    private fun createProofreader(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val modelPath = call.requiredString("modelPath")
        val maxTokens = call.optionalInt("maxTokens")
        executor.execute {
            try {
                val options = TextProofreader.TextProofreaderOptions.builder().setModelPath(modelPath)
                maxTokens?.let(options::setMaxNumTokens)
                val proofreader = TextProofreader.createFromOptions(applicationContext, options.build())
                val handle = nextHandle.getAndIncrement()
                proofreaders[handle] = proofreader
                result.successOnMain(handle)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun proofread(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val text = call.requiredString("text")
        val proofreader =
            proofreaders[handle]
                ?: throw IllegalArgumentException("Unknown TextProofreader handle: $handle")
        executor.execute {
            try {
                val output = proofreader.proofread(text)
                result.successOnMain(
                    mapOf(
                        "text" to output.proofreadText,
                        "corrections" to output.corrections.toDartCorrections(),
                    ),
                )
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun proofreadStreaming(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        requireEventSink()
        val handle = call.requiredLong("handle")
        val text = call.requiredString("text")
        val requestId = call.requiredString("requestId")
        val proofreader =
            proofreaders[handle]
                ?: throw IllegalArgumentException("Unknown TextProofreader handle: $handle")
        executor.execute {
            try {
                proofreader.proofreadStreaming(
                    text,
                    object : TextProofreader.ProofreaderResultCallback {
                        override fun onNext(value: TextProofreaderStreamingResult) {
                            emit(
                                mapOf(
                                    "kind" to "data",
                                    "requestId" to requestId,
                                    "text" to value.chunk,
                                    "isDone" to value.isDone,
                                    "corrections" to value.corrections?.toDartCorrections(),
                                ),
                            )
                        }

                        override fun onError(error: Throwable) {
                            emitError(requestId, error)
                        }

                        override fun onDone() {
                            emitDone(requestId)
                        }
                    },
                )
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun closeProofreader(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val proofreader =
            proofreaders.remove(handle)
                ?: throw IllegalArgumentException("Unknown TextProofreader handle: $handle")
        executor.execute {
            try {
                proofreader.close()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun createSummarizer(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val modelPath = call.requiredString("modelPath")
        val maxTokens = call.optionalInt("maxTokens")
        val mode =
            when (call.requiredString("mode")) {
                "tldr" -> TextSummarizer.TextSummarizerOptions.Mode.TLDR
                "keyPoints" -> TextSummarizer.TextSummarizerOptions.Mode.KEYPOINTS
                else -> throw IllegalArgumentException("Unknown TextSummarizer mode")
            }
        executor.execute {
            try {
                val options =
                    TextSummarizer.TextSummarizerOptions
                        .builder()
                        .setModelPath(modelPath)
                        .setMode(mode)
                maxTokens?.let(options::setMaxNumTokens)
                val summarizer = TextSummarizer.createFromOptions(applicationContext, options.build())
                val handle = nextHandle.getAndIncrement()
                summarizers[handle] = summarizer
                result.successOnMain(handle)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun summarize(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val text = call.requiredString("text")
        val summarizer =
            summarizers[handle]
                ?: throw IllegalArgumentException("Unknown TextSummarizer handle: $handle")
        executor.execute {
            try {
                result.successOnMain(mapOf("summary" to summarizer.summarize(text).summary))
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun summarizeStreaming(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        requireEventSink()
        val handle = call.requiredLong("handle")
        val text = call.requiredString("text")
        val requestId = call.requiredString("requestId")
        val summarizer =
            summarizers[handle]
                ?: throw IllegalArgumentException("Unknown TextSummarizer handle: $handle")
        executor.execute {
            try {
                summarizer.summarizeStreaming(
                    text,
                    object : TextSummarizer.SummarizationResultCallback {
                        override fun onNext(value: TextSummarizerStreamingResult) {
                            emit(
                                mapOf(
                                    "kind" to "data",
                                    "requestId" to requestId,
                                    "text" to value.chunk,
                                    "isDone" to value.isDone,
                                ),
                            )
                        }

                        override fun onError(error: Throwable) {
                            emitError(requestId, error)
                        }

                        override fun onDone() {
                            emitDone(requestId)
                        }
                    },
                )
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun closeSummarizer(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val summarizer =
            summarizers.remove(handle)
                ?: throw IllegalArgumentException("Unknown TextSummarizer handle: $handle")
        executor.execute {
            try {
                summarizer.close()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun requireEventSink() {
        requireNotNull(eventSink) { "Listen to the mp_text event channel before starting a stream" }
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun emitError(
        requestId: String,
        error: Throwable,
    ) {
        emit(
            mapOf(
                "kind" to "error",
                "requestId" to requestId,
                "code" to "internal",
                "message" to error.safeMessage(),
            ),
        )
    }

    private fun emitDone(requestId: String) {
        emit(mapOf("kind" to "done", "requestId" to requestId))
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink,
    ) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        val openProofreaders = proofreaders.values.toList()
        val openSummarizers = summarizers.values.toList()
        proofreaders.clear()
        summarizers.clear()
        executor.execute {
            openProofreaders.forEach { runCatching { it.close() } }
            openSummarizers.forEach { runCatching { it.close() } }
        }
        executor.shutdown()
    }

    private fun MethodCall.requiredString(name: String): String =
        argument<String>(name)?.takeIf { it.isNotEmpty() }
            ?: throw IllegalArgumentException("$name must be a non-empty string")

    private fun MethodCall.requiredLong(name: String): Long =
        argument<Number>(name)?.toLong()
            ?: throw IllegalArgumentException("$name must be an integer")

    private fun MethodCall.optionalInt(name: String): Int? = argument<Number>(name)?.toInt()

    private fun MethodChannel.Result.successOnMain(value: Any?) {
        mainHandler.post { success(value) }
    }

    private fun MethodChannel.Result.errorOnMain(error: Throwable) {
        mainHandler.post { error("internal", error.safeMessage(), null) }
    }

    private fun Throwable.safeMessage(): String = message ?: javaClass.simpleName

    private fun List<TextProofreaderResult.Correction>.toDartCorrections(): List<Map<String, String>> =
        map { correction ->
            mapOf(
                "type" to correction.type.name.lowercase(),
                "text" to correction.text,
            )
        }

    private companion object {
        const val METHOD_CHANNEL = "dev.ifiokjr.mp_text/methods"
        const val EVENT_CHANNEL = "dev.ifiokjr.mp_text/events"
    }
}
