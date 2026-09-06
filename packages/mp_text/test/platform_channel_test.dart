import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mp_core/mp_core.dart';
import 'package:mp_text/mp_text.dart';

const MethodChannel _methods = MethodChannel('dev.ifiokjr.mp_text/methods');
const MethodChannel _events = MethodChannel('dev.ifiokjr.mp_text/events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final List<MethodCall> calls = <MethodCall>[];
  String? materializedModelPath;
  var sendMalformedStream = false;
  Completer<void>? allowStreamDone;

  setUp(() {
    calls.clear();
    materializedModelPath = null;
    sendMalformedStream = false;
    allowStreamDone = null;
    messenger.setMockMethodCallHandler(_events, (MethodCall call) async => null);
    messenger.setMockMethodCallHandler(_methods, (MethodCall call) async {
      calls.add(call);
      final Map<Object?, Object?> arguments = call.arguments! as Map<Object?, Object?>;
      switch (call.method) {
        case 'proofreader.create':
          materializedModelPath = arguments['modelPath']! as String;
          expect(File(materializedModelPath!).existsSync(), isTrue);
          return 7;
        case 'proofreader.proofread':
          return <String, Object?>{
            'text': 'Corrected text.',
            'corrections': <Object?>[
              <String, Object?>{'type': 'same', 'text': 'Corrected text'},
              <String, Object?>{'type': 'insertion', 'text': '.'},
            ],
          };
        case 'proofreader.stream':
          final String requestId = arguments['requestId']! as String;
          unawaited(
            Future<void>(() async {
              if (sendMalformedStream) {
                await _sendEvent(messenger, <String, Object?>{
                  'kind': 'data',
                  'requestId': requestId,
                  'text': 7,
                  'isDone': false,
                });
                await allowStreamDone!.future;
                await _sendEvent(messenger, <String, Object?>{
                  'kind': 'done',
                  'requestId': requestId,
                });
                return;
              }
              await _sendEvent(messenger, <String, Object?>{
                'kind': 'data',
                'requestId': requestId,
                'text': 'Corrected ',
                'isDone': false,
              });
              await _sendEvent(messenger, <String, Object?>{
                'kind': 'data',
                'requestId': requestId,
                'text': 'text.',
                'isDone': true,
                'corrections': <Object?>[
                  <String, Object?>{'type': 'same', 'text': 'Corrected text'},
                  <String, Object?>{'type': 'insertion', 'text': '.'},
                ],
              });
              await _sendEvent(messenger, <String, Object?>{
                'kind': 'done',
                'requestId': requestId,
              });
            }),
          );
          return null;
        case 'proofreader.close':
          return null;
        case 'summarizer.create':
          return 8;
        case 'summarizer.summarize':
          return <String, Object?>{'summary': 'Summary.'};
        case 'summarizer.close':
          return null;
      }
      throw PlatformException(code: 'unimplemented', message: call.method);
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMethodCallHandler(_events, null);
  });

  test('proofreader materializes bytes and converts platform results', () async {
    final TextProofreader proofreader = await TextProofreader.create(
      TextProofreaderOptions(
        baseOptions: BaseOptions(
          modelAsset: ModelAsset.bytes(
            Uint8List.fromList(<int>[1, 2, 3]),
            name: 'proofreader.litertlm',
          ),
        ),
        maxTokens: 512,
      ),
    );

    final TextProofreaderResult result = await proofreader.proofread('Text');
    await proofreader.close();

    expect(result.text, 'Corrected text.');
    expect(result.corrections.last.type, TextCorrectionType.insertion);
    expect(calls.map((MethodCall call) => call.method), <String>[
      'proofreader.create',
      'proofreader.proofread',
      'proofreader.close',
    ]);
    final Map<Object?, Object?> createArguments = calls.first.arguments! as Map<Object?, Object?>;
    expect(createArguments['maxTokens'], 512);
    expect(File(materializedModelPath!).existsSync(), isFalse);
  });

  test('summarizer forwards mode and parses the result', () async {
    final Directory directory = Directory.systemTemp.createTempSync('mp_text_test_');
    final File model = File('${directory.path}${Platform.pathSeparator}summary.litertlm')
      ..writeAsBytesSync(<int>[1]);
    addTearDown(() => directory.deleteSync(recursive: true));

    final TextSummarizer summarizer = await TextSummarizer.create(
      TextSummarizerOptions(
        baseOptions: BaseOptions(modelAsset: ModelAsset.path(model.path)),
        mode: TextSummarizerMode.tldr,
      ),
    );

    final TextSummarizerResult result = await summarizer.summarize('Long text');
    await summarizer.close();

    expect(result.summary, 'Summary.');
    final Map<Object?, Object?> createArguments = calls.first.arguments! as Map<Object?, Object?>;
    expect(createArguments['mode'], 'tldr');
    expect(createArguments['modelPath'], model.absolute.path);
  });

  test('proofreader converts platform stream events in order', () async {
    final Directory directory = Directory.systemTemp.createTempSync('mp_text_test_');
    final File model = File('${directory.path}${Platform.pathSeparator}proofread.litertlm')
      ..writeAsBytesSync(<int>[1]);
    addTearDown(() => directory.deleteSync(recursive: true));
    final TextProofreader proofreader = await TextProofreader.create(
      TextProofreaderOptions(baseOptions: BaseOptions(modelAsset: ModelAsset.path(model.path))),
    );

    final List<TextProofreaderChunk> chunks = await proofreader.proofreadStreaming('Text').toList();
    await proofreader.close();

    expect(chunks.map((TextProofreaderChunk chunk) => chunk.text), <String>['Corrected ', 'text.']);
    expect(chunks.last.isDone, isTrue);
    expect(chunks.last.corrections.last.type, TextCorrectionType.insertion);
  });

  test('stream conversion errors do not release the native operation early', () async {
    sendMalformedStream = true;
    allowStreamDone = Completer<void>();
    final Directory directory = Directory.systemTemp.createTempSync('mp_text_test_');
    final File model = File('${directory.path}${Platform.pathSeparator}proofread.litertlm')
      ..writeAsBytesSync(<int>[1]);
    addTearDown(() => directory.deleteSync(recursive: true));
    final TextProofreader proofreader = await TextProofreader.create(
      TextProofreaderOptions(baseOptions: BaseOptions(modelAsset: ModelAsset.path(model.path))),
    );

    await expectLater(proofreader.proofreadStreaming('Text'), emitsError(isA<MpException>()));
    var closeCompleted = false;
    final Future<void> close = proofreader.close().then((_) => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(closeCompleted, isFalse);
    allowStreamDone!.complete();
    await close.timeout(const Duration(seconds: 1));
    expect(closeCompleted, isTrue);
  });
}

Future<void> _sendEvent(TestDefaultBinaryMessenger messenger, Map<String, Object?> event) async {
  await messenger.handlePlatformMessage(
    _events.name,
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    null,
  );
}
