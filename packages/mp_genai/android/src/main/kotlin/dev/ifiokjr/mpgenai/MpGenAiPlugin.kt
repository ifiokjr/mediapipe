package dev.ifiokjr.mpgenai

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import com.google.ai.edge.localagents.core.proto.Content
import com.google.ai.edge.localagents.core.proto.FunctionCall
import com.google.ai.edge.localagents.core.proto.FunctionDeclaration
import com.google.ai.edge.localagents.core.proto.FunctionResponse
import com.google.ai.edge.localagents.core.proto.GenerateContentResponse
import com.google.ai.edge.localagents.core.proto.Part
import com.google.ai.edge.localagents.core.proto.Schema
import com.google.ai.edge.localagents.core.proto.Tool
import com.google.ai.edge.localagents.core.proto.Type
import com.google.ai.edge.localagents.fc.ChatSession
import com.google.ai.edge.localagents.fc.GemmaFormatter
import com.google.ai.edge.localagents.fc.GenerativeModel
import com.google.ai.edge.localagents.fc.HammerFormatter
import com.google.ai.edge.localagents.fc.LlamaFormatter
import com.google.ai.edge.localagents.fc.LlmInferenceBackend
import com.google.ai.edge.localagents.fc.ModelFormatter
import com.google.ai.edge.localagents.fc.ModelFormatterOptions
import com.google.ai.edge.localagents.fc.proto.ConstraintOptions
import com.google.ai.edge.localagents.rag.chains.ChainConfig
import com.google.ai.edge.localagents.rag.chains.RetrievalAndInferenceChain
import com.google.ai.edge.localagents.rag.memory.ColumnConfig
import com.google.ai.edge.localagents.rag.memory.DefaultSemanticTextMemory
import com.google.ai.edge.localagents.rag.memory.DefaultVectorStore
import com.google.ai.edge.localagents.rag.memory.SqliteVectorStore
import com.google.ai.edge.localagents.rag.memory.TableConfig
import com.google.ai.edge.localagents.rag.memory.VectorStore
import com.google.ai.edge.localagents.rag.models.AsyncProgressListener
import com.google.ai.edge.localagents.rag.models.Embedder
import com.google.ai.edge.localagents.rag.models.GeckoEmbeddingModel
import com.google.ai.edge.localagents.rag.models.GemmaEmbeddingModel
import com.google.ai.edge.localagents.rag.models.LanguageModelResponse
import com.google.ai.edge.localagents.rag.models.MediaPipeLlmBackend
import com.google.ai.edge.localagents.rag.prompt.PromptBuilder
import com.google.ai.edge.localagents.rag.retrieval.RetrievalConfig
import com.google.ai.edge.localagents.rag.retrieval.RetrievalRequest
import com.google.ai.edge.localagents.rag.retrieval.RetrievalResponse
import com.google.ai.edge.localagents.rag.retrieval.SemanticDataEntry
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.FutureCallback
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.MoreExecutors
import com.google.mediapipe.framework.image.BitmapExtractor
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.genai.llminference.AudioModelOptions
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import com.google.mediapipe.tasks.genai.llminference.ProgressListener
import com.google.mediapipe.tasks.genai.llminference.PromptTemplates
import com.google.mediapipe.tasks.genai.llminference.VisionModelOptions
import com.google.mediapipe.tasks.vision.imagegenerator.ImageGenerator
import com.google.mediapipe.tasks.vision.imagegenerator.ImageGeneratorResult
import com.google.protobuf.ListValue
import com.google.protobuf.NullValue
import com.google.protobuf.Struct
import com.google.protobuf.Value
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Optional
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/** Android bridge for MediaPipe Tasks GenAI. */
class MpGenAiPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var applicationContext: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private val nextHandle = AtomicLong(1)
    private val engines = ConcurrentHashMap<Long, LlmInference>()
    private val sessions = ConcurrentHashMap<Long, LlmInferenceSession>()
    private val imageGenerators = ConcurrentHashMap<Long, ImageGenerator>()
    private val functionModels = ConcurrentHashMap<Long, FunctionModelHolder>()
    private val functionChats = ConcurrentHashMap<Long, FunctionChatHolder>()
    private val ragPipelines = ConcurrentHashMap<Long, RagPipelineHolder>()

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
                "llm.create" -> createLlm(call, result)
                "llm.createSession" -> createSession(call, result)
                "llm.sizeInTokens" -> sizeInTokens(call, result)
                "llm.sessionSizeInTokens" -> sessionSizeInTokens(call, result)
                "llm.addQuery" -> addQuery(call, result)
                "llm.addImage" -> addImage(call, result)
                "llm.addAudio" -> addAudio(call, result)
                "llm.generate" -> generate(call, result)
                "llm.cancel" -> cancel(call, result)
                "llm.cloneSession" -> cloneSession(call, result)
                "llm.updateSession" -> updateSession(call, result)
                "llm.closeSession" -> closeSession(call, result)
                "llm.close" -> closeLlm(call, result)
                "imageGenerator.create" -> createImageGenerator(call, result)
                "imageGenerator.generate" -> generateImage(call, result)
                "imageGenerator.setInputs" -> setImageGeneratorInputs(call, result)
                "imageGenerator.execute" -> executeImageGenerator(call, result)
                "imageGenerator.createConditionImage" -> createConditionImage(call, result)
                "imageGenerator.close" -> closeImageGenerator(call, result)
                "functionCalling.create" -> createFunctionModel(call, result)
                "functionCalling.generateContent" -> generateFunctionContent(call, result)
                "functionCalling.startChat" -> startFunctionChat(call, result)
                "functionCalling.sendMessage" -> sendFunctionMessage(call, result)
                "functionCalling.rewind" -> rewindFunctionChat(call, result)
                "functionCalling.history" -> functionChatHistory(call, result)
                "functionCalling.last" -> lastFunctionContent(call, result)
                "functionCalling.cloneChat" -> cloneFunctionChat(call, result)
                "functionCalling.enableConstraint" -> enableFunctionConstraint(call, result)
                "functionCalling.disableConstraint" -> disableFunctionConstraint(call, result)
                "functionCalling.closeChat" -> closeFunctionChat(call, result)
                "functionCalling.close" -> closeFunctionModel(call, result)
                "rag.create" -> createRagPipeline(call, result)
                "rag.record" -> recordRagDocument(call, result)
                "rag.recordAll" -> recordRagDocuments(call, result)
                "rag.retrieve" -> retrieveRagDocuments(call, result)
                "rag.generate" -> generateRagResponse(call, result)
                "rag.generateStreaming" -> generateRagResponseStreaming(call, result)
                "rag.close" -> closeRagPipeline(call, result)
                else -> result.notImplemented()
            }
        } catch (error: IllegalArgumentException) {
            result.error("invalid_argument", error.message, null)
        }
    }

    private fun createLlm(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val options = call.llmOptions()
        executor.execute {
            try {
                val engine = LlmInference.createFromOptions(applicationContext, options)
                val handle = nextHandle.getAndIncrement()
                engines[handle] = engine
                result.successOnMain(handle)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun createSession(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val engine = call.requiredEngine()
        val options = call.sessionOptions()
        executor.execute {
            try {
                val session = LlmInferenceSession.createFromOptions(engine, options)
                val handle = nextHandle.getAndIncrement()
                sessions[handle] = session
                result.successOnMain(handle)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun sizeInTokens(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val engine = call.requiredEngine()
        val text = call.requiredString("text")
        executor.execute {
            try {
                result.successOnMain(engine.sizeInTokens(text))
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun sessionSizeInTokens(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val session = call.requiredSession()
        val text = call.requiredString("text")
        executor.execute {
            try {
                result.successOnMain(session.sizeInTokens(text))
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun addQuery(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val session = call.requiredSession()
        val text = call.requiredString("text")
        executor.execute {
            try {
                session.addQueryChunk(text)
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun addImage(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val session = call.requiredSession()
        val width = call.requiredInt("width")
        val height = call.requiredInt("height")
        val format = call.requiredString("format")
        val data =
            call.argument<ByteArray>("data")
                ?: throw IllegalArgumentException("data must be a byte array")
        val bitmap = data.toBitmap(width, height, format)
        executor.execute {
            val image = BitmapImageBuilder(bitmap).build()
            try {
                session.addImage(image)
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            } finally {
                image.close()
                bitmap.recycle()
            }
        }
    }

    private fun addAudio(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val session = call.requiredSession()
        val data =
            call.argument<ByteArray>("data")
                ?: throw IllegalArgumentException("data must be a byte array")
        require(data.isNotEmpty()) { "data must not be empty" }
        executor.execute {
            try {
                session.addAudio(data)
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun generate(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        requireEventSink()
        val session = call.requiredSession()
        val requestId = call.requiredString("requestId")
        executor.execute {
            try {
                val terminal = AtomicBoolean(false)
                val future =
                    session.generateResponseAsync(
                        ProgressListener<String> { chunk, done ->
                            emit(
                                mapOf(
                                    "kind" to "data",
                                    "requestId" to requestId,
                                    "text" to chunk,
                                    "isDone" to done,
                                ),
                            )
                            if (done && terminal.compareAndSet(false, true)) {
                                emitDone(requestId)
                            }
                        },
                    )
                Futures.addCallback(
                    future,
                    object : FutureCallback<String> {
                        override fun onSuccess(value: String?) {
                            if (terminal.compareAndSet(false, true)) emitDone(requestId)
                        }

                        override fun onFailure(error: Throwable) {
                            if (terminal.compareAndSet(false, true)) emitError(requestId, error)
                        }
                    },
                    MoreExecutors.directExecutor(),
                )
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun cancel(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val session = call.requiredSession()
        executor.execute {
            try {
                session.cancelGenerateResponseAsync()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun cloneSession(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val session = call.requiredSession()
        executor.execute {
            try {
                val clone = session.cloneSession()
                val handle = nextHandle.getAndIncrement()
                sessions[handle] = clone
                result.successOnMain(handle)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun updateSession(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val session = call.requiredSession()
        val topK = call.requiredInt("topK")
        val topP = call.requiredDouble("topP").toFloat()
        val temperature = call.requiredDouble("temperature").toFloat()
        val randomSeed = call.requiredInt("randomSeed")
        executor.execute {
            try {
                session.updateSessionOptions { builder ->
                    builder
                        .setTopK(topK)
                        .setTopP(topP)
                        .setTemperature(temperature)
                        .setRandomSeed(randomSeed)
                        .build()
                }
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun closeSession(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val session =
            sessions.remove(handle)
                ?: throw IllegalArgumentException("Unknown LlmSession handle: $handle")
        executor.execute {
            try {
                session.close()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun closeLlm(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val engine =
            engines.remove(handle)
                ?: throw IllegalArgumentException("Unknown LlmInference handle: $handle")
        executor.execute {
            try {
                engine.close()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun createImageGenerator(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val options =
            ImageGenerator.ImageGeneratorOptions
                .builder()
                .setImageGeneratorModelDirectory(call.requiredString("modelDirectory"))
                .setModelType(ImageGenerator.ImageGeneratorOptions.ModelType.SD_1)
        call.optionalString("loraWeightsPath")?.let(options::setLoraWeightsFilePath)
        val conditions = call.imageGeneratorConditionOptions()
        executor.execute {
            try {
                val generator =
                    if (conditions == null) {
                        ImageGenerator.createFromOptions(applicationContext, options.build())
                    } else {
                        ImageGenerator.createFromOptions(
                            applicationContext,
                            options.build(),
                            conditions,
                        )
                    }
                val handle = nextHandle.getAndIncrement()
                imageGenerators[handle] = generator
                result.successOnMain(handle)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun generateImage(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val generator = call.requiredImageGenerator()
        val prompt = call.requiredString("prompt")
        val iterations = call.requiredInt("iterations")
        val seed = call.requiredInt("seed")
        val conditionType = call.optionalConditionType()
        val ownedImage = call.optionalImage()
        require((conditionType == null) == (ownedImage == null)) {
            "conditionType and image must be provided together"
        }
        executor.execute {
            try {
                val output =
                    if (conditionType == null || ownedImage == null) {
                        generator.generate(prompt, iterations, seed)
                    } else {
                        generator.generate(
                            prompt,
                            ownedImage.image,
                            conditionType,
                            iterations,
                            seed,
                        )
                    }
                result.successOnMain(output.toDartResult())
            } catch (error: Throwable) {
                result.errorOnMain(error)
            } finally {
                ownedImage?.close()
            }
        }
    }

    private fun setImageGeneratorInputs(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val generator = call.requiredImageGenerator()
        val prompt = call.requiredString("prompt")
        val iterations = call.requiredInt("iterations")
        val seed = call.requiredInt("seed")
        val conditionType = call.optionalConditionType()
        val ownedImage = call.optionalImage()
        require((conditionType == null) == (ownedImage == null)) {
            "conditionType and image must be provided together"
        }
        executor.execute {
            try {
                if (conditionType == null || ownedImage == null) {
                    generator.setInputs(prompt, iterations, seed)
                } else {
                    generator.setInputs(
                        prompt,
                        ownedImage.image,
                        conditionType,
                        iterations,
                        seed,
                    )
                }
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            } finally {
                ownedImage?.close()
            }
        }
    }

    private fun executeImageGenerator(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val generator = call.requiredImageGenerator()
        val showResult = call.requiredBoolean("showResult")
        executor.execute {
            try {
                result.successOnMain(generator.execute(showResult)?.toDartResult())
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun createConditionImage(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val generator = call.requiredImageGenerator()
        val conditionType = call.requiredConditionType()
        val ownedImage = call.requiredImage()
        executor.execute {
            try {
                val output = generator.createConditionImage(ownedImage.image, conditionType)
                try {
                    result.successOnMain(output.toDartImage())
                } finally {
                    output.close()
                }
            } catch (error: Throwable) {
                result.errorOnMain(error)
            } finally {
                ownedImage.close()
            }
        }
    }

    private fun closeImageGenerator(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val generator =
            imageGenerators.remove(handle)
                ?: throw IllegalArgumentException("Unknown ImageGenerator handle: $handle")
        executor.execute {
            try {
                generator.close()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun createFunctionModel(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val llmOptions = call.llmOptions()
        val sessionOptions = call.sessionOptions()
        val formatterOptions =
            ModelFormatterOptions
                .builder()
                .setAddPromptTemplate(call.requiredBoolean("addPromptTemplate"))
                .build()
        val formatter: ModelFormatter =
            when (call.requiredString("formatter")) {
                "gemma" -> GemmaFormatter(formatterOptions)
                "llama" -> LlamaFormatter(formatterOptions)
                "hammer" -> HammerFormatter(formatterOptions)
                else -> throw IllegalArgumentException("Unknown function-calling formatter")
            }
        val systemInstruction = call.argument<Map<String, Any?>>("systemInstruction")?.toContent()
        val tools =
            call
                .argument<List<Map<String, Any?>>>("tools")
                ?.map { it.toTool() }
                .orEmpty()
        executor.execute {
            var inference: LlmInference? = null
            var backend: LlmInferenceBackend? = null
            try {
                inference = LlmInference.createFromOptions(applicationContext, llmOptions)
                val initializedBackend = LlmInferenceBackend(inference, sessionOptions, formatter)
                backend = initializedBackend
                val model =
                    when {
                        tools.isNotEmpty() ->
                            GenerativeModel(
                                initializedBackend,
                                systemInstruction ?: Content.getDefaultInstance(),
                                tools,
                            )
                        systemInstruction != null ->
                            GenerativeModel(initializedBackend, systemInstruction)
                        else -> GenerativeModel(initializedBackend)
                    }
                val handle = nextHandle.getAndIncrement()
                functionModels[handle] = FunctionModelHolder(model, initializedBackend)
                result.successOnMain(handle)
            } catch (error: Throwable) {
                if (backend == null) {
                    runCatching { inference?.close() }
                } else {
                    runCatching { backend.close() }
                }
                result.errorOnMain(error)
            }
        }
    }

    private fun generateFunctionContent(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val model = call.requiredFunctionModel().model
        val contents =
            call
                .argument<List<Map<String, Any?>>>("contents")
                ?.map { it.toContent() }
                ?: throw IllegalArgumentException("contents must be a list")
        executor.execute {
            try {
                result.successOnMain(model.generateContent(contents).toDartResponse())
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun startFunctionChat(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val modelHandle = call.requiredLong("handle")
        val model =
            functionModels[modelHandle]
                ?: throw IllegalArgumentException("Unknown GenerativeModel handle: $modelHandle")
        executor.execute {
            try {
                val chat = model.model.startChat()
                val handle = nextHandle.getAndIncrement()
                functionChats[handle] = FunctionChatHolder(chat, modelHandle)
                result.successOnMain(handle)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun sendFunctionMessage(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val chat = call.requiredFunctionChat().chat
        val content = call.requiredMap("content").toContent()
        executor.execute {
            try {
                result.successOnMain(chat.sendMessage(content).toDartResponse())
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun rewindFunctionChat(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val chat = call.requiredFunctionChat().chat
        executor.execute {
            try {
                val rewind = requireNotNull(chat.rewind()) { "The chat has no exchange to rewind" }
                result.successOnMain(
                    mapOf(
                        "lastSent" to rewind.lastSent().toDartContent(),
                        "lastReceived" to rewind.lastReceived().toDartContent(),
                    ),
                )
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun functionChatHistory(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val chat = call.requiredFunctionChat().chat
        executor.execute {
            try {
                result.successOnMain(chat.history.map { it.toDartContent() })
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun lastFunctionContent(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val chat = call.requiredFunctionChat().chat
        executor.execute {
            try {
                val last = requireNotNull(chat.last) { "The chat history is empty" }
                result.successOnMain(last.toDartContent())
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun cloneFunctionChat(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val original = call.requiredFunctionChat()
        executor.execute {
            try {
                val clone = original.chat.clone()
                val handle = nextHandle.getAndIncrement()
                functionChats[handle] = FunctionChatHolder(clone, original.modelHandle)
                result.successOnMain(handle)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun enableFunctionConstraint(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val chat = call.requiredFunctionChat().chat
        val constraint = call.requiredMap("constraint").toConstraintOptions()
        executor.execute {
            try {
                chat.enableConstraint(constraint)
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun disableFunctionConstraint(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val chat = call.requiredFunctionChat().chat
        executor.execute {
            try {
                chat.disableConstraint()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun closeFunctionChat(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val chat =
            functionChats.remove(handle)
                ?: throw IllegalArgumentException("Unknown FunctionCallingChat handle: $handle")
        executor.execute {
            try {
                chat.chat.close()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun closeFunctionModel(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val model =
            functionModels.remove(handle)
                ?: throw IllegalArgumentException("Unknown GenerativeModel handle: $handle")
        val chats =
            functionChats.entries
                .filter { it.value.modelHandle == handle }
                .mapNotNull { entry -> functionChats.remove(entry.key)?.chat }
        executor.execute {
            try {
                chats.forEach(ChatSession::close)
                model.backend.close()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun createRagPipeline(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val llmOptions = call.llmOptions()
        val sessionOptions = call.sessionOptions()
        val embeddingOptions = call.requiredMap("embedding")
        val vectorStoreOptions = call.requiredMap("vectorStore")
        val promptTemplate = call.requiredString("promptTemplate")
        executor.execute {
            var languageModel: MediaPipeLlmBackend? = null
            try {
                val embedder: Embedder<String> = embeddingOptions.toEmbedder()
                val vectorStore: VectorStore<String> = vectorStoreOptions.toVectorStore()
                val memory = DefaultSemanticTextMemory(vectorStore, embedder)
                languageModel = MediaPipeLlmBackend(applicationContext, llmOptions, sessionOptions)
                check(languageModel.initialize().get()) { "MediaPipe could not initialize the RAG LLM" }
                val chain =
                    RetrievalAndInferenceChain(
                        ChainConfig.create(
                            languageModel,
                            PromptBuilder(promptTemplate),
                            memory,
                        ),
                    )
                val handle = nextHandle.getAndIncrement()
                ragPipelines[handle] = RagPipelineHolder(memory, chain, languageModel)
                result.successOnMain(handle)
            } catch (error: Throwable) {
                runCatching { languageModel?.close() }
                result.errorOnMain(error)
            }
        }
    }

    private fun recordRagDocument(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val pipeline = call.requiredRagPipeline()
        val document = call.requiredMap("document").toSemanticDataEntry()
        executor.execute {
            try {
                result.successOnMain(
                    requireNotNull(pipeline.memory.recordMemoryEntry(document).get()),
                )
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun recordRagDocuments(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val pipeline = call.requiredRagPipeline()
        val documents =
            call
                .argument<List<Map<String, Any?>>>("documents")
                ?.map { it.toSemanticDataEntry() }
                ?: throw IllegalArgumentException("documents must be a list")
        executor.execute {
            try {
                result.successOnMain(
                    requireNotNull(
                        pipeline.memory
                            .recordBatchedMemoryEntries(ImmutableList.copyOf(documents))
                            .get(),
                    ),
                )
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun retrieveRagDocuments(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val pipeline = call.requiredRagPipeline()
        val request = call.ragRetrievalRequest()
        executor.execute {
            try {
                val response = requireNotNull(pipeline.memory.retrieveResults(request).get())
                result.successOnMain(response.toDartEntities())
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun generateRagResponse(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val pipeline = call.requiredRagPipeline()
        val request = call.ragRetrievalRequest()
        executor.execute {
            try {
                val response = requireNotNull(pipeline.chain.invoke(request).get())
                result.successOnMain(response.text)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun generateRagResponseStreaming(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        requireEventSink()
        val pipeline = call.requiredRagPipeline()
        val request = call.ragRetrievalRequest()
        val requestId = call.requiredString("requestId")
        executor.execute {
            try {
                val terminal = AtomicBoolean(false)
                val future =
                    pipeline.chain.invoke(
                        request,
                        AsyncProgressListener<LanguageModelResponse> { response, done ->
                            emit(
                                mapOf(
                                    "kind" to "data",
                                    "requestId" to requestId,
                                    "text" to response.text,
                                    "isDone" to done,
                                ),
                            )
                            if (done && terminal.compareAndSet(false, true)) emitDone(requestId)
                        },
                    )
                Futures.addCallback(
                    future,
                    object : FutureCallback<LanguageModelResponse> {
                        override fun onSuccess(value: LanguageModelResponse?) {
                            if (terminal.compareAndSet(false, true)) emitDone(requestId)
                        }

                        override fun onFailure(error: Throwable) {
                            if (terminal.compareAndSet(false, true)) emitError(requestId, error)
                        }
                    },
                    MoreExecutors.directExecutor(),
                )
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
    }

    private fun closeRagPipeline(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val handle = call.requiredLong("handle")
        val pipeline =
            ragPipelines.remove(handle)
                ?: throw IllegalArgumentException("Unknown RagPipeline handle: $handle")
        executor.execute {
            try {
                pipeline.languageModel.close()
                result.successOnMain(null)
            } catch (error: Throwable) {
                result.errorOnMain(error)
            }
        }
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
        val openSessions = sessions.values.toList()
        val openEngines = engines.values.toList()
        val openImageGenerators = imageGenerators.values.toList()
        val openFunctionChats = functionChats.values.map(FunctionChatHolder::chat)
        val openFunctionModels = functionModels.values.map(FunctionModelHolder::backend)
        val openRagPipelines = ragPipelines.values.map(RagPipelineHolder::languageModel)
        sessions.clear()
        engines.clear()
        imageGenerators.clear()
        functionChats.clear()
        functionModels.clear()
        ragPipelines.clear()
        executor.execute {
            openSessions.forEach { runCatching { it.cancelGenerateResponseAsync() } }
            openSessions.forEach { runCatching { it.close() } }
            openEngines.forEach { runCatching { it.close() } }
            openImageGenerators.forEach { runCatching { it.close() } }
            openFunctionChats.forEach { runCatching { it.close() } }
            openFunctionModels.forEach { runCatching { it.close() } }
            openRagPipelines.forEach { runCatching { it.close() } }
        }
        executor.shutdown()
    }

    private fun requireEventSink() {
        requireNotNull(eventSink) { "Listen to the mp_genai event channel before generating" }
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
                "code" to if (error is java.util.concurrent.CancellationException) "cancelled" else "internal",
                "message" to error.safeMessage(),
            ),
        )
    }

    private fun emitDone(requestId: String) {
        emit(mapOf("kind" to "done", "requestId" to requestId))
    }

    private fun MethodCall.requiredEngine(): LlmInference {
        val handle = requiredLong("handle")
        return engines[handle]
            ?: throw IllegalArgumentException("Unknown LlmInference handle: $handle")
    }

    private fun MethodCall.requiredSession(): LlmInferenceSession {
        val handle = requiredLong("handle")
        return sessions[handle]
            ?: throw IllegalArgumentException("Unknown LlmSession handle: $handle")
    }

    private fun MethodCall.requiredImageGenerator(): ImageGenerator {
        val handle = requiredLong("handle")
        return imageGenerators[handle]
            ?: throw IllegalArgumentException("Unknown ImageGenerator handle: $handle")
    }

    private fun MethodCall.requiredFunctionModel(): FunctionModelHolder {
        val handle = requiredLong("handle")
        return functionModels[handle]
            ?: throw IllegalArgumentException("Unknown GenerativeModel handle: $handle")
    }

    private fun MethodCall.requiredFunctionChat(): FunctionChatHolder {
        val handle = requiredLong("handle")
        return functionChats[handle]
            ?: throw IllegalArgumentException("Unknown FunctionCallingChat handle: $handle")
    }

    private fun MethodCall.requiredRagPipeline(): RagPipelineHolder {
        val handle = requiredLong("handle")
        return ragPipelines[handle]
            ?: throw IllegalArgumentException("Unknown RagPipeline handle: $handle")
    }

    private fun Map<String, Any?>.toEmbedder(): Embedder<String> {
        val modelPath = requiredString("modelPath")
        val tokenizerPath = optionalStringValue("tokenizerPath")
        val useGpu = requiredBoolean("useGpu")
        return when (requiredString("kind")) {
            "gecko" -> GeckoEmbeddingModel(modelPath, Optional.ofNullable(tokenizerPath), useGpu)
            "gemma" ->
                GemmaEmbeddingModel(
                    modelPath,
                    requireNotNull(tokenizerPath) { "Gemma embedding requires tokenizerPath" },
                    useGpu,
                )
            else -> throw IllegalArgumentException("Unknown RAG embedding model")
        }
    }

    private fun Map<String, Any?>.toVectorStore(): VectorStore<String> =
        when (requiredString("kind")) {
            "memory" -> DefaultVectorStore()
            "sqlite" -> {
                val dimensions = requiredInt("embeddingDimensions")
                val databasePath = requiredString("databasePath")
                val tableName = optionalStringValue("tableName")
                val textColumnName = optionalStringValue("textColumnName")
                val embeddingsColumnName = optionalStringValue("embeddingsColumnName")
                val rawColumns =
                    this["columns"] as? List<Map<String, Any?>>
                        ?: throw IllegalArgumentException("vectorStore.columns must be a list")
                if (tableName == null && textColumnName == null && embeddingsColumnName == null) {
                    SqliteVectorStore(dimensions, databasePath)
                } else {
                    val columns = rawColumns.map { it.toSqliteColumn() }
                    SqliteVectorStore(
                        dimensions,
                        databasePath,
                        requireNotNull(textColumnName),
                        requireNotNull(embeddingsColumnName),
                        TableConfig
                            .builder()
                            .setName(requireNotNull(tableName))
                            .setColumns(ImmutableList.copyOf(columns))
                            .build(),
                    )
                }
            }
            else -> throw IllegalArgumentException("Unknown RAG vector store")
        }

    private fun Map<String, Any?>.toSqliteColumn(): ColumnConfig =
        ColumnConfig
            .builder()
            .setName(requiredString("name"))
            .setSqlType(requiredString("sqlType"))
            .setKeyType(
                when (requiredString("keyType")) {
                    "none" -> ColumnConfig.KeyType.DEFAULT_NOT_KEY
                    "primary" -> ColumnConfig.KeyType.PRIMARY_KEY
                    else -> throw IllegalArgumentException("Unknown SQLite key type")
                },
            ).setAutoIncrement(requiredBoolean("autoIncrement"))
            .setIsNullable(requiredBoolean("nullable"))
            .build()

    private fun Map<String, Any?>.toSemanticDataEntry(): SemanticDataEntry<String> =
        SemanticDataEntry.create(
            requiredString("text"),
            requiredMapValue("metadata"),
            Optional.ofNullable(optionalStringValue("embeddingText")),
        )

    private fun MethodCall.ragRetrievalRequest(): RetrievalRequest<String> =
        RetrievalRequest.create(
            requiredString("query"),
            RetrievalConfig.create(
                requiredInt("topK"),
                requiredDouble("minSimilarityScore").toFloat(),
                when (requiredString("task")) {
                    "unspecified" -> RetrievalConfig.TaskType.TASK_UNSPECIFIED
                    "retrievalQuery" -> RetrievalConfig.TaskType.RETRIEVAL_QUERY
                    "questionAnswering" -> RetrievalConfig.TaskType.QUESTION_ANSWERING
                    "factVerification" -> RetrievalConfig.TaskType.FACT_VERIFICATION
                    "codeRetrieval" -> RetrievalConfig.TaskType.CODE_RETRIEVAL
                    else -> throw IllegalArgumentException("Unknown RAG retrieval task")
                },
            ),
        )

    private fun RetrievalResponse<String>.toDartEntities(): List<Map<String, Any?>> =
        entities.map { entity ->
            mapOf(
                "text" to entity.data,
                "embedding" to entity.embeddings.map(Number::toDouble),
                "metadata" to entity.metadata,
            )
        }

    private fun MethodCall.llmOptions(): LlmInference.LlmInferenceOptions {
        val options =
            LlmInference.LlmInferenceOptions
                .builder()
                .setModelPath(requiredString("modelPath"))
                .setMaxTokens(requiredInt("maxTokens"))
                .setMaxTopK(requiredInt("maxTopK"))
                .setMaxNumImages(requiredInt("maxNumImages"))
                .setSupportedLoraRanks(requiredIntList("supportedLoraRanks"))
                .setPreferredBackend(preferredBackend())
        val visionEncoder = optionalString("visionEncoderPath")
        val visionAdapter = optionalString("visionAdapterPath")
        if (visionEncoder != null || visionAdapter != null) {
            val vision = VisionModelOptions.builder()
            visionEncoder?.let(vision::setEncoderPath)
            visionAdapter?.let(vision::setAdapterPath)
            options.setVisionModelOptions(vision.build())
        }
        optionalInt("maxAudioSequenceLength")?.let { maxLength ->
            options.setAudioModelOptions(
                AudioModelOptions.builder().setMaxAudioSequenceLength(maxLength).build(),
            )
        }
        return options.build()
    }

    private fun MethodCall.imageGeneratorConditionOptions(): ImageGenerator.ConditionOptions? {
        val face = argument<Map<String, Any?>>("faceCondition")
        val edge = argument<Map<String, Any?>>("edgeCondition")
        val depth = argument<Map<String, Any?>>("depthCondition")
        if (face == null && edge == null && depth == null) return null
        val builder = ImageGenerator.ConditionOptions.builder()
        face?.let { values ->
            builder.setFaceConditionOptions(
                ImageGenerator.ConditionOptions.FaceConditionOptions
                    .builder()
                    .setPluginModelBaseOptions(values.requiredBaseOptions("pluginModelPath"))
                    .setFaceModelBaseOptions(values.requiredBaseOptions("faceModelPath"))
                    .setMinFaceDetectionConfidence(
                        values.requiredDouble("minFaceDetectionConfidence").toFloat(),
                    ).setMinFacePresenceConfidence(
                        values.requiredDouble("minFacePresenceConfidence").toFloat(),
                    ).build(),
            )
        }
        edge?.let { values ->
            builder.setEdgeConditionOptions(
                ImageGenerator.ConditionOptions.EdgeConditionOptions
                    .builder()
                    .setPluginModelBaseOptions(values.requiredBaseOptions("pluginModelPath"))
                    .setThreshold1(values.requiredDouble("threshold1").toFloat())
                    .setThreshold2(values.requiredDouble("threshold2").toFloat())
                    .setApertureSize(values.requiredInt("apertureSize"))
                    .setL2Gradient(values.requiredBoolean("l2Gradient"))
                    .build(),
            )
        }
        depth?.let { values ->
            builder.setDepthConditionOptions(
                ImageGenerator.ConditionOptions.DepthConditionOptions
                    .builder()
                    .setPluginModelBaseOptions(values.requiredBaseOptions("pluginModelPath"))
                    .setDepthModelBaseOptions(values.requiredBaseOptions("depthModelPath"))
                    .build(),
            )
        }
        return builder.build()
    }

    private fun MethodCall.optionalConditionType(): ImageGenerator.ConditionOptions.ConditionType? =
        optionalString("conditionType")?.toConditionType()

    private fun MethodCall.requiredConditionType(): ImageGenerator.ConditionOptions.ConditionType =
        requiredString("conditionType").toConditionType()

    private fun String.toConditionType(): ImageGenerator.ConditionOptions.ConditionType =
        when (this) {
            "face" -> ImageGenerator.ConditionOptions.ConditionType.FACE
            "edge" -> ImageGenerator.ConditionOptions.ConditionType.EDGE
            "depth" -> ImageGenerator.ConditionOptions.ConditionType.DEPTH
            else -> throw IllegalArgumentException("Unknown conditionType: $this")
        }

    private fun MethodCall.optionalImage(): OwnedMpImage? = argument<Map<String, Any?>>("image")?.toOwnedMpImage()

    private fun MethodCall.requiredImage(): OwnedMpImage =
        argument<Map<String, Any?>>("image")?.toOwnedMpImage()
            ?: throw IllegalArgumentException("image must be a map")

    private fun MethodCall.preferredBackend(): LlmInference.Backend =
        when (requiredString("preferredBackend")) {
            "defaultBackend" -> LlmInference.Backend.DEFAULT
            "cpu" -> LlmInference.Backend.CPU
            "gpu" -> LlmInference.Backend.GPU
            else -> throw IllegalArgumentException("Unknown preferredBackend")
        }

    private fun MethodCall.sessionOptions(): LlmInferenceSession.LlmInferenceSessionOptions {
        val builder =
            LlmInferenceSession.LlmInferenceSessionOptions
                .builder()
                .setTopK(requiredInt("topK"))
                .setTopP(requiredDouble("topP").toFloat())
                .setTemperature(requiredDouble("temperature").toFloat())
                .setRandomSeed(requiredInt("randomSeed"))
        optionalString("loraPath")?.let(builder::setLoraPath)
        argument<Number>("constraintHandle")?.toLong()?.let(builder::setConstraintHandle)
        if (hasArgument("includeTokenCostCalculator")) {
            builder.setGraphOptions(
                GraphOptions
                    .builder()
                    .setIncludeTokenCostCalculator(requiredBoolean("includeTokenCostCalculator"))
                    .setEnableVisionModality(requiredBoolean("enableVisionModality"))
                    .setEnableAudioModality(requiredBoolean("enableAudioModality"))
                    .build(),
            )
        }
        argument<Map<String, Any?>>("promptTemplates")?.let { values ->
            builder.setPromptTemplates(
                PromptTemplates
                    .builder()
                    .setUserPrefix(values.requiredString("userPrefix"))
                    .setUserSuffix(values.requiredString("userSuffix"))
                    .setModelPrefix(values.requiredString("modelPrefix"))
                    .setModelSuffix(values.requiredString("modelSuffix"))
                    .setSystemPrefix(values.requiredString("systemPrefix"))
                    .setSystemSuffix(values.requiredString("systemSuffix"))
                    .build(),
            )
        }
        return builder.build()
    }

    private fun MethodCall.requiredString(name: String): String =
        argument<String>(name)?.takeIf { it.isNotEmpty() }
            ?: throw IllegalArgumentException("$name must be a non-empty string")

    private fun MethodCall.optionalString(name: String): String? = argument<String>(name)?.takeIf { it.isNotEmpty() }

    private fun MethodCall.requiredLong(name: String): Long =
        argument<Number>(name)?.toLong()
            ?: throw IllegalArgumentException("$name must be an integer")

    private fun MethodCall.requiredInt(name: String): Int =
        argument<Number>(name)?.toInt()
            ?: throw IllegalArgumentException("$name must be an integer")

    private fun MethodCall.optionalInt(name: String): Int? = argument<Number>(name)?.toInt()

    private fun MethodCall.requiredDouble(name: String): Double =
        argument<Number>(name)?.toDouble()
            ?: throw IllegalArgumentException("$name must be a number")

    private fun MethodCall.requiredBoolean(name: String): Boolean =
        argument<Boolean>(name)
            ?: throw IllegalArgumentException("$name must be a boolean")

    private fun MethodCall.requiredIntList(name: String): List<Int> =
        argument<List<Number>>(name)?.map(Number::toInt)
            ?: throw IllegalArgumentException("$name must be an integer list")

    private fun MethodCall.requiredMap(name: String): Map<String, Any?> =
        argument<Map<String, Any?>>(name)
            ?: throw IllegalArgumentException("$name must be a map")

    private fun Map<String, Any?>.requiredString(name: String): String =
        this[name] as? String
            ?: throw IllegalArgumentException("$name must be a string")

    private fun Map<String, Any?>.requiredInt(name: String): Int =
        (this[name] as? Number)?.toInt()
            ?: throw IllegalArgumentException("$name must be an integer")

    private fun Map<String, Any?>.requiredDouble(name: String): Double =
        (this[name] as? Number)?.toDouble()
            ?: throw IllegalArgumentException("$name must be a number")

    private fun Map<String, Any?>.requiredBoolean(name: String): Boolean =
        this[name] as? Boolean
            ?: throw IllegalArgumentException("$name must be a boolean")

    private fun Map<String, Any?>.requiredBaseOptions(name: String) =
        com.google.mediapipe.tasks.core.BaseOptions
            .builder()
            .setModelAssetPath(requiredString(name))
            .build()

    private fun Map<String, Any?>.toOwnedMpImage(): OwnedMpImage {
        val data =
            this["data"] as? ByteArray
                ?: throw IllegalArgumentException("image.data must be a byte array")
        val bitmap =
            data.toBitmap(
                requiredInt("width"),
                requiredInt("height"),
                requiredString("format"),
            )
        return OwnedMpImage(BitmapImageBuilder(bitmap).build(), bitmap)
    }

    private fun Map<String, Any?>.toContent(): Content {
        val parts =
            this["parts"] as? List<Map<String, Any?>>
                ?: throw IllegalArgumentException("content.parts must be a list")
        val builder = Content.newBuilder().setRole(requiredString("role"))
        parts.forEach { builder.addParts(it.toPart()) }
        return builder.build()
    }

    private fun Map<String, Any?>.toPart(): Part {
        val builder = Part.newBuilder()
        when (requiredString("kind")) {
            "text" -> builder.setText(requiredString("text"))
            "functionCall" ->
                builder.setFunctionCall(
                    FunctionCall
                        .newBuilder()
                        .setName(requiredString("name"))
                        .setArgs(requiredMapValue("value").toStruct())
                        .build(),
                )
            "functionResponse" ->
                builder.setFunctionResponse(
                    FunctionResponse
                        .newBuilder()
                        .setName(requiredString("name"))
                        .setResponse(requiredMapValue("value").toStruct())
                        .build(),
                )
            else -> throw IllegalArgumentException("Unknown function content part")
        }
        return builder.build()
    }

    private fun Map<String, Any?>.toTool(): Tool {
        val declarations =
            this["declarations"] as? List<Map<String, Any?>>
                ?: throw IllegalArgumentException("tool.declarations must be a list")
        return Tool
            .newBuilder()
            .addAllFunctionDeclarations(declarations.map { it.toDeclaration() })
            .build()
    }

    private fun Map<String, Any?>.toDeclaration(): FunctionDeclaration {
        val builder =
            FunctionDeclaration
                .newBuilder()
                .setName(requiredString("name"))
                .setDescription(requiredString("description"))
        (this["parameters"] as? Map<String, Any?>)?.let { builder.setParameters(it.toSchema()) }
        (this["response"] as? Map<String, Any?>)?.let { builder.setResponse(it.toSchema()) }
        return builder.build()
    }

    private fun Map<String, Any?>.toSchema(): Schema {
        val builder =
            Schema
                .newBuilder()
                .setType(requiredString("type").toSchemaType())
                .setNullable(requiredBoolean("nullable"))
                .addAllEnum(requiredStringList("enumValues"))
                .addAllRequired(requiredStringList("requiredProperties"))
                .addAllPropertyOrdering(requiredStringList("propertyOrdering"))
        optionalStringValue("format")?.let(builder::setFormat)
        optionalStringValue("title")?.let(builder::setTitle)
        optionalStringValue("description")?.let(builder::setDescription)
        (this["items"] as? Map<String, Any?>)?.let { builder.setItems(it.toSchema()) }
        optionalLong("minItems")?.let(builder::setMinItems)
        optionalLong("maxItems")?.let(builder::setMaxItems)
        optionalDouble("minimum")?.let(builder::setMinimum)
        optionalDouble("maximum")?.let(builder::setMaximum)
        val properties =
            this["properties"] as? Map<String, Map<String, Any?>>
                ?: throw IllegalArgumentException("schema.properties must be a map")
        properties.forEach { (name, schema) -> builder.putProperties(name, schema.toSchema()) }
        val anyOf =
            this["anyOf"] as? List<Map<String, Any?>>
                ?: throw IllegalArgumentException("schema.anyOf must be a list")
        builder.addAllAnyOf(anyOf.map { it.toSchema() })
        return builder.build()
    }

    private fun String.toSchemaType(): Type =
        when (this) {
            "string" -> Type.STRING
            "number" -> Type.NUMBER
            "integer" -> Type.INTEGER
            "boolean" -> Type.BOOLEAN
            "array" -> Type.ARRAY
            "object" -> Type.OBJECT
            "nullValue" -> Type.NULL
            else -> throw IllegalArgumentException("Unknown function schema type: $this")
        }

    private fun Map<String, Any?>.toConstraintOptions(): ConstraintOptions {
        val builder = ConstraintOptions.newBuilder()
        when (requiredString("kind")) {
            "toolCallOnly" ->
                builder.setToolCallOnly(
                    ConstraintOptions.ToolCallOnly
                        .newBuilder()
                        .setConstraintPrefix(requiredStringValue("prefix"))
                        .setConstraintSuffix(requiredStringValue("suffix")),
                )
            "textAndOr" ->
                builder.setTextAndOr(
                    ConstraintOptions.TextAndOr
                        .newBuilder()
                        .setStopPhrasePrefix(requiredStringValue("stopPhrasePrefix"))
                        .setStopPhraseSuffix(requiredStringValue("stopPhraseSuffix"))
                        .setConstraintSuffix(requiredStringValue("constraintSuffix")),
                )
            "textUntil" ->
                builder.setTextUntil(
                    ConstraintOptions.TextUntil
                        .newBuilder()
                        .setStopPhrase(requiredString("stopPhrase"))
                        .setConstraintSuffix(requiredStringValue("constraintSuffix")),
                )
            else -> throw IllegalArgumentException("Unknown function-calling constraint")
        }
        return builder.build()
    }

    private fun GenerateContentResponse.toDartResponse(): Map<String, Any> =
        mapOf("candidates" to candidatesList.map { it.content.toDartContent() })

    private fun Content.toDartContent(): Map<String, Any> =
        mapOf(
            "role" to role,
            "parts" to partsList.map { it.toDartPart() },
        )

    private fun Part.toDartPart(): Map<String, Any?> =
        when (dataCase) {
            Part.DataCase.TEXT -> mapOf("kind" to "text", "text" to text)
            Part.DataCase.FUNCTION_CALL ->
                mapOf(
                    "kind" to "functionCall",
                    "name" to functionCall.name,
                    "value" to functionCall.args.toDartMap(),
                )
            Part.DataCase.FUNCTION_RESPONSE ->
                mapOf(
                    "kind" to "functionResponse",
                    "name" to functionResponse.name,
                    "value" to functionResponse.response.toDartMap(),
                )
            else -> throw IllegalStateException("MediaPipe returned an empty content part")
        }

    private fun Map<String, Any?>.requiredMapValue(name: String): Map<String, Any?> =
        this[name] as? Map<String, Any?>
            ?: throw IllegalArgumentException("$name must be a map")

    private fun Map<String, Any?>.requiredStringValue(name: String): String =
        this[name] as? String
            ?: throw IllegalArgumentException("$name must be a string")

    private fun Map<String, Any?>.optionalStringValue(name: String): String? = this[name] as? String

    private fun Map<String, Any?>.requiredStringList(name: String): List<String> =
        this[name] as? List<String>
            ?: throw IllegalArgumentException("$name must be a string list")

    private fun Map<String, Any?>.optionalLong(name: String): Long? = (this[name] as? Number)?.toLong()

    private fun Map<String, Any?>.optionalDouble(name: String): Double? = (this[name] as? Number)?.toDouble()

    private fun Map<String, Any?>.toStruct(): Struct {
        val builder = Struct.newBuilder()
        forEach { (name, value) -> builder.putFields(name, value.toProtoValue()) }
        return builder.build()
    }

    private fun Any?.toProtoValue(): Value {
        val builder = Value.newBuilder()
        when (this) {
            null -> builder.setNullValue(NullValue.NULL_VALUE)
            is Boolean -> builder.setBoolValue(this)
            is String -> builder.setStringValue(this)
            is Number -> builder.setNumberValue(toDouble())
            is List<*> ->
                builder.setListValue(
                    ListValue.newBuilder().addAllValues(map { it.toProtoValue() }),
                )
            is Map<*, *> -> {
                val values =
                    entries.associate { entry ->
                        val key =
                            entry.key as? String
                                ?: throw IllegalArgumentException("JSON object keys must be strings")
                        key to entry.value
                    }
                builder.setStructValue(values.toStruct())
            }
            else -> throw IllegalArgumentException("Value is not JSON-compatible")
        }
        return builder.build()
    }

    private fun Struct.toDartMap(): Map<String, Any?> = fieldsMap.mapValues { it.value.toDartValue() }

    private fun Value.toDartValue(): Any? =
        when (kindCase) {
            Value.KindCase.NULL_VALUE -> null
            Value.KindCase.BOOL_VALUE -> boolValue
            Value.KindCase.STRING_VALUE -> stringValue
            Value.KindCase.NUMBER_VALUE -> numberValue
            Value.KindCase.LIST_VALUE -> listValue.valuesList.map { it.toDartValue() }
            Value.KindCase.STRUCT_VALUE -> structValue.toDartMap()
            else -> null
        }

    private fun MethodChannel.Result.successOnMain(value: Any?) {
        mainHandler.post { success(value) }
    }

    private fun MethodChannel.Result.errorOnMain(error: Throwable) {
        mainHandler.post { error("internal", error.safeMessage(), null) }
    }

    private fun Throwable.safeMessage(): String = message ?: javaClass.simpleName

    private fun ByteArray.toBitmap(
        width: Int,
        height: Int,
        format: String,
    ): Bitmap {
        require(width > 0 && height > 0) { "Image dimensions must be positive" }
        val channels =
            when (format) {
                "gray8" -> 1
                "srgb" -> 3
                "srgba" -> 4
                else -> throw IllegalArgumentException("Unsupported Android image format: $format")
            }
        require(size == width * height * channels) { "Image data has an invalid length" }
        val pixels = IntArray(width * height)
        for (index in pixels.indices) {
            val offset = index * channels
            val red: Int
            val green: Int
            val blue: Int
            val alpha: Int
            if (channels == 1) {
                red = this[offset].toInt() and 0xff
                green = red
                blue = red
                alpha = 0xff
            } else {
                red = this[offset].toInt() and 0xff
                green = this[offset + 1].toInt() and 0xff
                blue = this[offset + 2].toInt() and 0xff
                alpha = if (channels == 4) this[offset + 3].toInt() and 0xff else 0xff
            }
            pixels[index] = (alpha shl 24) or (red shl 16) or (green shl 8) or blue
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun MPImage.toDartImage(): Map<String, Any> {
        val bitmap = BitmapExtractor.extract(this)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val data = ByteArray(pixels.size * 4)
        for (index in pixels.indices) {
            val pixel = pixels[index]
            val offset = index * 4
            data[offset] = ((pixel shr 16) and 0xff).toByte()
            data[offset + 1] = ((pixel shr 8) and 0xff).toByte()
            data[offset + 2] = (pixel and 0xff).toByte()
            data[offset + 3] = ((pixel ushr 24) and 0xff).toByte()
        }
        return mapOf("width" to bitmap.width, "height" to bitmap.height, "data" to data)
    }

    private fun ImageGeneratorResult.toDartResult(): Map<String, Any?> {
        val generated = generatedImage()
        val condition = conditionImage().orElse(null)
        return try {
            mapOf(
                "generatedImage" to generated.toDartImage(),
                "conditionImage" to condition?.toDartImage(),
                "timestampMs" to timestampMs(),
            )
        } finally {
            generated.close()
            condition?.close()
        }
    }

    private companion object {
        const val METHOD_CHANNEL = "dev.ifiokjr.mp_genai/methods"
        const val EVENT_CHANNEL = "dev.ifiokjr.mp_genai/events"
    }

    private data class FunctionModelHolder(
        val model: GenerativeModel,
        val backend: LlmInferenceBackend,
    )

    private data class FunctionChatHolder(
        val chat: ChatSession,
        val modelHandle: Long,
    )

    private data class RagPipelineHolder(
        val memory: DefaultSemanticTextMemory,
        val chain: RetrievalAndInferenceChain,
        val languageModel: MediaPipeLlmBackend,
    )

    private data class OwnedMpImage(
        val image: MPImage,
        val bitmap: Bitmap,
    ) : AutoCloseable {
        override fun close() {
            image.close()
            bitmap.recycle()
        }
    }
}
