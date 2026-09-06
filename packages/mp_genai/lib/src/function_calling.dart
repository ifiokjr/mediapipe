import 'package:meta/meta.dart';
import 'package:mp_core/mp_core.dart';

import 'json_value.dart';
import 'options.dart';
import 'runtime.dart';

/// Prompt format used by an on-device function-calling model.
enum FunctionCallingFormatter {
  /// Gemma instruction format.
  gemma,

  /// Llama instruction format.
  llama,

  /// Hammer function-calling format.
  hammer,
}

/// JSON Schema value types supported by the function-calling SDK.
enum FunctionSchemaType {
  /// A string value.
  string,

  /// A floating-point value.
  number,

  /// An integer value.
  integer,

  /// A boolean value.
  boolean,

  /// An array value.
  array,

  /// An object value.
  object,

  /// A null value.
  nullValue,
}

/// A function parameter or response schema.
@immutable
final class FunctionSchema {
  /// Creates a schema.
  FunctionSchema({
    required this.type,
    this.format,
    this.title,
    this.description,
    this.nullable = false,
    Iterable<String> enumValues = const <String>[],
    this.items,
    this.minItems,
    this.maxItems,
    Map<String, FunctionSchema> properties = const <String, FunctionSchema>{},
    Iterable<String> requiredProperties = const <String>[],
    this.minimum,
    this.maximum,
    Iterable<FunctionSchema> anyOf = const <FunctionSchema>[],
    Iterable<String> propertyOrdering = const <String>[],
  }) : enumValues = List<String>.unmodifiable(enumValues),
       properties = Map<String, FunctionSchema>.unmodifiable(properties),
       requiredProperties = List<String>.unmodifiable(requiredProperties),
       anyOf = List<FunctionSchema>.unmodifiable(anyOf),
       propertyOrdering = List<String>.unmodifiable(propertyOrdering) {
    if (type == FunctionSchemaType.array && items == null) {
      throw ArgumentError.value(items, 'items', 'is required for array schemas');
    }
    if (minItems != null && minItems! < 0) {
      throw ArgumentError.value(minItems, 'minItems', 'must not be negative');
    }
    if (maxItems != null && maxItems! < 0) {
      throw ArgumentError.value(maxItems, 'maxItems', 'must not be negative');
    }
    if (minItems != null && maxItems != null && minItems! > maxItems!) {
      throw ArgumentError.value(maxItems, 'maxItems', 'must not be below minItems');
    }
    if (minimum != null && maximum != null && minimum! > maximum!) {
      throw ArgumentError.value(maximum, 'maximum', 'must not be below minimum');
    }
    final Set<String> names = properties.keys.toSet();
    if (!names.containsAll(this.requiredProperties)) {
      throw ArgumentError.value(
        this.requiredProperties,
        'requiredProperties',
        'must refer to declared properties',
      );
    }
    if (!names.containsAll(this.propertyOrdering)) {
      throw ArgumentError.value(
        this.propertyOrdering,
        'propertyOrdering',
        'must refer to declared properties',
      );
    }
  }

  /// Schema value type.
  final FunctionSchemaType type;

  /// Optional format such as `date-time`.
  final String? format;

  /// Optional short title.
  final String? title;

  /// Optional model-facing description.
  final String? description;

  /// Whether a null value is accepted.
  final bool nullable;

  /// Allowed string values.
  final List<String> enumValues;

  /// Element schema for arrays.
  final FunctionSchema? items;

  /// Minimum array length.
  final int? minItems;

  /// Maximum array length.
  final int? maxItems;

  /// Named object properties.
  final Map<String, FunctionSchema> properties;

  /// Object properties that must be present.
  final List<String> requiredProperties;

  /// Inclusive numeric minimum.
  final double? minimum;

  /// Inclusive numeric maximum.
  final double? maximum;

  /// Alternative accepted schemas.
  final List<FunctionSchema> anyOf;

  /// Preferred object-property order in generated calls.
  final List<String> propertyOrdering;
}

/// One function made available to the model.
@immutable
final class FunctionDeclaration {
  /// Creates a function declaration.
  FunctionDeclaration({
    required this.name,
    required this.description,
    this.parameters,
    this.response,
  }) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
    if (description.trim().isEmpty) {
      throw ArgumentError.value(description, 'description', 'must not be empty');
    }
  }

  /// Stable function name.
  final String name;

  /// Model-facing function description.
  final String description;

  /// Function argument schema.
  final FunctionSchema? parameters;

  /// Function response schema.
  final FunctionSchema? response;
}

/// A group of function declarations supplied to the model.
@immutable
final class FunctionTool {
  /// Creates a tool.
  FunctionTool(Iterable<FunctionDeclaration> declarations)
    : declarations = List<FunctionDeclaration>.unmodifiable(declarations) {
    if (this.declarations.isEmpty) {
      throw ArgumentError.value(this.declarations, 'declarations', 'must not be empty');
    }
    final Set<String> names = <String>{};
    for (final FunctionDeclaration declaration in this.declarations) {
      if (!names.add(declaration.name)) {
        throw ArgumentError.value(
          declaration.name,
          'declarations',
          'contains a duplicate function name',
        );
      }
    }
  }

  /// Functions contained by this tool.
  final List<FunctionDeclaration> declarations;
}

/// One structured function request produced by the model.
@immutable
final class FunctionCall {
  /// Creates a function call.
  FunctionCall({required this.name, Map<String, Object?> arguments = const <String, Object?>{}})
    : arguments = copyJsonObject(arguments) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
  }

  /// Declared function name.
  final String name;

  /// Model-generated arguments.
  ///
  /// These values are untrusted input. Validate them against application rules
  /// before invoking any function.
  final Map<String, Object?> arguments;
}

/// Application-provided output for a preceding [FunctionCall].
@immutable
final class FunctionResponse {
  /// Creates a function response.
  FunctionResponse({required this.name, Map<String, Object?> response = const <String, Object?>{}})
    : response = copyJsonObject(response) {
    if (name.trim().isEmpty) throw ArgumentError.value(name, 'name', 'must not be empty');
  }

  /// Function name.
  final String name;

  /// JSON-compatible response object.
  final Map<String, Object?> response;
}

/// One part of a [GenAiContent] message.
@immutable
sealed class GenAiPart {
  const GenAiPart();
}

/// Plain text content.
@immutable
final class GenAiTextPart extends GenAiPart {
  /// Creates a text part.
  const GenAiTextPart(this.text);

  /// Text content.
  final String text;
}

/// A model-generated function call.
@immutable
final class GenAiFunctionCallPart extends GenAiPart {
  /// Creates a function-call part.
  const GenAiFunctionCallPart(this.call);

  /// Structured function call.
  final FunctionCall call;
}

/// An application-provided function result.
@immutable
final class GenAiFunctionResponsePart extends GenAiPart {
  /// Creates a function-response part.
  const GenAiFunctionResponsePart(this.response);

  /// Structured function result.
  final FunctionResponse response;
}

/// A role-labelled function-calling message.
@immutable
final class GenAiContent {
  /// Creates content from [parts].
  GenAiContent({required this.role, required Iterable<GenAiPart> parts})
    : parts = List<GenAiPart>.unmodifiable(parts) {
    if (role.trim().isEmpty) throw ArgumentError.value(role, 'role', 'must not be empty');
    if (this.parts.isEmpty) throw ArgumentError.value(this.parts, 'parts', 'must not be empty');
  }

  /// Creates a single text message.
  factory GenAiContent.text({required String role, required String text}) =>
      GenAiContent(role: role, parts: <GenAiPart>[GenAiTextPart(text)]);

  /// Message role, normally `user`, `model`, `system`, or `function`.
  final String role;

  /// Ordered message parts.
  final List<GenAiPart> parts;
}

/// One candidate returned by a function-calling model.
@immutable
final class GenAiCandidate {
  /// Creates a response candidate.
  const GenAiCandidate(this.content);

  /// Candidate content.
  final GenAiContent content;
}

/// Structured output from a function-calling request.
@immutable
final class GenerateContentResponse {
  /// Creates a response.
  GenerateContentResponse(Iterable<GenAiCandidate> candidates)
    : candidates = List<GenAiCandidate>.unmodifiable(candidates);

  /// Returned candidates.
  final List<GenAiCandidate> candidates;
}

/// Result returned after rewinding one chat exchange.
@immutable
final class ChatRewindResult {
  /// Creates a rewind result.
  const ChatRewindResult({required this.lastSent, required this.lastReceived});

  /// Removed request.
  final GenAiContent lastSent;

  /// Removed model response.
  final GenAiContent lastReceived;
}

/// Constrained-decoding mode for a chat session.
@immutable
sealed class FunctionCallingConstraint {
  const FunctionCallingConstraint();
}

/// Require a tool call and no free text.
@immutable
final class ToolCallOnlyConstraint extends FunctionCallingConstraint {
  /// Creates a tool-call-only constraint.
  const ToolCallOnlyConstraint({this.prefix = '', this.suffix = ''});

  /// Text prepended to the constrained section.
  final String prefix;

  /// Text appended to the constrained section.
  final String suffix;
}

/// Allow free text followed optionally by a tool call.
@immutable
final class TextAndOrConstraint extends FunctionCallingConstraint {
  /// Creates a text-and-or constraint.
  const TextAndOrConstraint({
    this.stopPhrasePrefix = '',
    this.stopPhraseSuffix = '',
    this.constraintSuffix = '',
  });

  /// Prefix of the phrase that ends the free-text section.
  final String stopPhrasePrefix;

  /// Suffix of the phrase that ends the free-text section.
  final String stopPhraseSuffix;

  /// Text appended to the constrained section.
  final String constraintSuffix;
}

/// Allow text until a stop phrase is produced.
@immutable
final class TextUntilConstraint extends FunctionCallingConstraint {
  /// Creates a text-until constraint.
  TextUntilConstraint({required this.stopPhrase, this.constraintSuffix = ''}) {
    if (stopPhrase.isEmpty) {
      throw ArgumentError.value(stopPhrase, 'stopPhrase', 'must not be empty');
    }
  }

  /// Phrase that ends free-text generation.
  final String stopPhrase;

  /// Text appended after the stop phrase.
  final String constraintSuffix;
}

/// Configuration for the Android function-calling SDK.
@immutable
final class GenerativeModelOptions {
  /// Creates function-calling model options.
  GenerativeModelOptions({
    required this.inferenceOptions,
    this.sessionOptions,
    this.formatter = FunctionCallingFormatter.gemma,
    this.addPromptTemplate = true,
    this.systemInstruction,
    Iterable<FunctionTool> tools = const <FunctionTool>[],
  }) : tools = List<FunctionTool>.unmodifiable(tools);

  /// Underlying MediaPipe LLM engine options.
  final LlmInferenceOptions inferenceOptions;

  /// Sampling options for function-calling sessions.
  final LlmSessionOptions? sessionOptions;

  /// Model prompt and response formatter.
  final FunctionCallingFormatter formatter;

  /// Whether the formatter should insert its prompt template.
  final bool addPromptTemplate;

  /// Optional system instruction.
  final GenAiContent? systemInstruction;

  /// Functions exposed to the model.
  final List<FunctionTool> tools;
}

/// On-device structured generation and function calling.
final class GenerativeModel implements MpTask {
  GenerativeModel._(this.options, this._backend);

  /// Options used to load the model.
  final GenerativeModelOptions options;

  final FunctionCallingBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('GenerativeModel');

  /// Loads a function-calling model using [runtime], or the Android adapter.
  static Future<GenerativeModel> create(
    GenerativeModelOptions options, {
    GenAiRuntime? runtime,
  }) async => GenerativeModel._(
    options,
    await (runtime ?? defaultGenAiRuntime).createGenerativeModel(options),
  );

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Generates structured content without retaining a conversation history.
  Future<GenerateContentResponse> generateContent(Iterable<GenAiContent> contents) {
    _lifecycle.ensureOpen();
    final List<GenAiContent> input = List<GenAiContent>.unmodifiable(contents);
    if (input.isEmpty) throw ArgumentError.value(input, 'contents', 'must not be empty');
    return _backend.generateContent(input);
  }

  /// Starts a stateful chat session.
  Future<FunctionCallingChat> startChat() async {
    _lifecycle.ensureOpen();
    return FunctionCallingChat._(await _backend.startChat());
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}

/// A stateful function-calling conversation.
final class FunctionCallingChat implements MpTask {
  FunctionCallingChat._(this._backend);

  final FunctionCallingChatBackend _backend;
  final TaskLifecycle _lifecycle = TaskLifecycle('FunctionCallingChat');

  @override
  bool get isClosed => _lifecycle.isClosed;

  /// Sends structured [content].
  Future<GenerateContentResponse> sendMessage(GenAiContent content) {
    _lifecycle.ensureOpen();
    return _backend.sendMessage(content);
  }

  /// Sends one user text message.
  Future<GenerateContentResponse> sendText(String text) =>
      sendMessage(GenAiContent.text(role: 'user', text: text));

  /// Removes and returns the most recent request-response exchange.
  Future<ChatRewindResult> rewind() {
    _lifecycle.ensureOpen();
    return _backend.rewind();
  }

  /// Returns a snapshot of the conversation history.
  Future<List<GenAiContent>> history() {
    _lifecycle.ensureOpen();
    return _backend.history();
  }

  /// Returns the most recent content entry.
  Future<GenAiContent> last() {
    _lifecycle.ensureOpen();
    return _backend.last();
  }

  /// Clones this conversation and its current history.
  Future<FunctionCallingChat> clone() async {
    _lifecycle.ensureOpen();
    return FunctionCallingChat._(await _backend.clone());
  }

  /// Enables constrained decoding for subsequent responses.
  Future<void> enableConstraint(FunctionCallingConstraint constraint) {
    _lifecycle.ensureOpen();
    return _backend.enableConstraint(constraint);
  }

  /// Disables constrained decoding.
  Future<void> disableConstraint() {
    _lifecycle.ensureOpen();
    return _backend.disableConstraint();
  }

  @override
  Future<void> close() async {
    if (!_lifecycle.markClosed()) return;
    await _backend.close();
  }
}
