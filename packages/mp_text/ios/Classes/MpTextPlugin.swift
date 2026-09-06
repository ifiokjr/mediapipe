import Flutter
import MediaPipeTasksText
import UIKit

/// iOS bridge for MediaPipe's mobile-only text generation tasks.
public final class MpTextPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "dev.ifiokjr.mp_text/methods"
  private static let eventChannelName = "dev.ifiokjr.mp_text/events"

  private let worker = DispatchQueue(
    label: "dev.ifiokjr.mp_text.worker",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let lock = NSLock()
  private var nextHandle: Int64 = 1
  private var proofreaders: [Int64: TextProofreader] = [:]
  private var summarizers: [Int64: TextSummarizer] = [:]
  private var eventSink: FlutterEventSink?
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = MpTextPlugin()
    instance.methodChannel = methodChannel
    instance.eventChannel = eventChannel
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "proofreader.create":
        try createProofreader(call, result: result)
      case "proofreader.proofread":
        try proofread(call, result: result)
      case "proofreader.stream":
        try proofreadStreaming(call, result: result)
      case "proofreader.close":
        try closeProofreader(call, result: result)
      case "summarizer.create":
        try createSummarizer(call, result: result)
      case "summarizer.summarize":
        try summarize(call, result: result)
      case "summarizer.stream":
        try summarizeStreaming(call, result: result)
      case "summarizer.close":
        try closeSummarizer(call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(flutterError(error, code: "invalid_argument"))
    }
  }

  private func createProofreader(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws
  {
    let arguments = try call.argumentsMap()
    let modelPath = try arguments.requiredString("modelPath")
    let maxTokens = arguments.optionalInt("maxTokens")
    worker.async { [weak self] in
      guard let self else { return }
      do {
        let options = TextProofreaderOptions()
        options.baseOptions.modelAssetPath = modelPath
        if let maxTokens { options.maxTokens = maxTokens }
        let proofreader = try TextProofreader(options: options)
        let handle = withLock {
          let handle = self.nextHandle
          self.nextHandle += 1
          self.proofreaders[handle] = proofreader
          return handle
        }
        complete(result, value: handle)
      } catch {
        complete(result, error: error)
      }
    }
  }

  private func proofread(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    let arguments = try call.argumentsMap()
    let handle = try arguments.requiredInt64("handle")
    let text = try arguments.requiredString("text")
    guard let proofreader = withLock({ proofreaders[handle] }) else {
      throw PluginError.invalidArgument("Unknown TextProofreader handle: \(handle)")
    }
    worker.async { [weak self] in
      guard let self else { return }
      do {
        let output = try proofreader.proofread(text: text)
        complete(
          result,
          value: [
            "text": output.proofreadText,
            "corrections": output.corrections.map(correctionMap),
          ]
        )
      } catch {
        complete(result, error: error)
      }
    }
  }

  private func proofreadStreaming(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) throws {
    try requireEventSink()
    let arguments = try call.argumentsMap()
    let handle = try arguments.requiredInt64("handle")
    let text = try arguments.requiredString("text")
    let requestId = try arguments.requiredString("requestId")
    guard let proofreader = withLock({ proofreaders[handle] }) else {
      throw PluginError.invalidArgument("Unknown TextProofreader handle: \(handle)")
    }
    worker.async { [weak self] in
      guard let self else { return }
      do {
        try proofreader.proofreadStreaming(text: text) { [weak self] output, error in
          guard let self else { return }
          if let error {
            emitError(requestId: requestId, error: error)
            return
          }
          guard let output else { return }
          emit([
            "kind": "data",
            "requestId": requestId,
            "text": output.chunk,
            "isDone": output.done,
            "corrections": output.corrections?.map(correctionMap) as Any,
          ])
          if output.done { emitDone(requestId: requestId) }
        }
        complete(result, value: nil)
      } catch {
        complete(result, error: error)
      }
    }
  }

  private func closeProofreader(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    let handle = try call.argumentsMap().requiredInt64("handle")
    guard let proofreader = withLock({ proofreaders.removeValue(forKey: handle) }) else {
      throw PluginError.invalidArgument("Unknown TextProofreader handle: \(handle)")
    }
    worker.async { [weak self] in
      guard let self else { return }
      do {
        try proofreader.close()
        complete(result, value: nil)
      } catch {
        complete(result, error: error)
      }
    }
  }

  private func createSummarizer(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    let arguments = try call.argumentsMap()
    let modelPath = try arguments.requiredString("modelPath")
    let maxTokens = arguments.optionalInt("maxTokens")
    let mode: TextSummarizerMode
    switch try arguments.requiredString("mode") {
    case "tldr": mode = .tldr
    case "keyPoints": mode = .keyPoints
    default: throw PluginError.invalidArgument("Unknown TextSummarizer mode")
    }
    worker.async { [weak self] in
      guard let self else { return }
      do {
        let options = TextSummarizerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.mode = mode
        if let maxTokens { options.maxTokens = maxTokens }
        let summarizer = try TextSummarizer(options: options)
        let handle = withLock {
          let handle = self.nextHandle
          self.nextHandle += 1
          self.summarizers[handle] = summarizer
          return handle
        }
        complete(result, value: handle)
      } catch {
        complete(result, error: error)
      }
    }
  }

  private func summarize(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    let arguments = try call.argumentsMap()
    let handle = try arguments.requiredInt64("handle")
    let text = try arguments.requiredString("text")
    guard let summarizer = withLock({ summarizers[handle] }) else {
      throw PluginError.invalidArgument("Unknown TextSummarizer handle: \(handle)")
    }
    worker.async { [weak self] in
      guard let self else { return }
      do {
        complete(result, value: ["summary": try summarizer.summarize(text: text).summary])
      } catch {
        complete(result, error: error)
      }
    }
  }

  private func summarizeStreaming(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) throws {
    try requireEventSink()
    let arguments = try call.argumentsMap()
    let handle = try arguments.requiredInt64("handle")
    let text = try arguments.requiredString("text")
    let requestId = try arguments.requiredString("requestId")
    guard let summarizer = withLock({ summarizers[handle] }) else {
      throw PluginError.invalidArgument("Unknown TextSummarizer handle: \(handle)")
    }
    worker.async { [weak self] in
      guard let self else { return }
      do {
        try summarizer.summarizeStreaming(text: text) { [weak self] output, error in
          guard let self else { return }
          if let error {
            emitError(requestId: requestId, error: error)
            return
          }
          guard let output else { return }
          emit([
            "kind": "data",
            "requestId": requestId,
            "text": output.chunk,
            "isDone": output.done,
          ])
          if output.done { emitDone(requestId: requestId) }
        }
        complete(result, value: nil)
      } catch {
        complete(result, error: error)
      }
    }
  }

  private func closeSummarizer(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
    let handle = try call.argumentsMap().requiredInt64("handle")
    guard let summarizer = withLock({ summarizers.removeValue(forKey: handle) }) else {
      throw PluginError.invalidArgument("Unknown TextSummarizer handle: \(handle)")
    }
    worker.async { [weak self] in
      guard let self else { return }
      do {
        try summarizer.close()
        complete(result, value: nil)
      } catch {
        complete(result, error: error)
      }
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    withLock { eventSink = events }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    withLock { eventSink = nil }
    return nil
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    methodChannel?.setMethodCallHandler(nil)
    eventChannel?.setStreamHandler(nil)
    let openTasks = withLock { () -> ([TextProofreader], [TextSummarizer]) in
      let tasks = (Array(proofreaders.values), Array(summarizers.values))
      proofreaders.removeAll()
      summarizers.removeAll()
      eventSink = nil
      return tasks
    }
    worker.async {
      for task in openTasks.0 { try? task.close() }
      for task in openTasks.1 { try? task.close() }
    }
  }

  private func requireEventSink() throws {
    guard withLock({ eventSink != nil }) else {
      throw PluginError.invalidArgument(
        "Listen to the mp_text event channel before starting a stream")
    }
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let sink = withLock { self.eventSink }
      sink?(event)
    }
  }

  private func emitError(requestId: String, error: Error) {
    emit([
      "kind": "error",
      "requestId": requestId,
      "code": "internal",
      "message": error.localizedDescription,
    ])
  }

  private func emitDone(requestId: String) {
    emit(["kind": "done", "requestId": requestId])
  }

  private func complete(_ result: @escaping FlutterResult, value: Any?) {
    DispatchQueue.main.async { result(value) }
  }

  private func complete(_ result: @escaping FlutterResult, error: Error) {
    DispatchQueue.main.async { result(self.flutterError(error, code: "internal")) }
  }

  private func flutterError(_ error: Error, code: String) -> FlutterError {
    FlutterError(code: code, message: error.localizedDescription, details: nil)
  }

  private func correctionMap(_ correction: Correction) -> [String: String] {
    let type: String
    switch correction.type {
    case .same: type = "same"
    case .insertion: type = "insertion"
    case .deletion: type = "deletion"
    @unknown default: type = "unknown"
    }
    return ["type": type, "text": correction.text]
  }

  private func withLock<T>(_ operation: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return operation()
  }
}

private enum PluginError: LocalizedError {
  case invalidArgument(String)

  var errorDescription: String? {
    switch self {
    case .invalidArgument(let message): return message
    }
  }
}

extension FlutterMethodCall {
  fileprivate func argumentsMap() throws -> [String: Any] {
    guard let value = arguments as? [String: Any] else {
      throw PluginError.invalidArgument("Arguments must be a map")
    }
    return value
  }
}

extension Dictionary where Key == String, Value == Any {
  fileprivate func requiredString(_ key: String) throws -> String {
    guard let value = self[key] as? String, !value.isEmpty else {
      throw PluginError.invalidArgument("\(key) must be a non-empty string")
    }
    return value
  }

  fileprivate func requiredInt64(_ key: String) throws -> Int64 {
    guard let value = self[key] as? NSNumber else {
      throw PluginError.invalidArgument("\(key) must be an integer")
    }
    return value.int64Value
  }

  fileprivate func optionalInt(_ key: String) -> Int? {
    (self[key] as? NSNumber)?.intValue
  }
}
