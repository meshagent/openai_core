// test/event_loop_function_tool_test.dart
//
// Be sure to set an `OPENAI_API_KEY` environment variable before running:
// $ OPENAI_API_KEY=sk-... dart test

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';

import '../lib/common.dart';
import '../lib/responses.dart';
import '../lib/openai_client.dart';
import '../lib/event_loop.dart';

class WeatherTool extends FunctionToolHandler {
  bool handlerCalled = false;

  WeatherTool()
      : super(
            metadata: FunctionTool(
                name: 'get_current_temperature',
                description:
                    'Returns the current temperature in Celsius for a given city.',
                strict: true,
                parameters: {
              'type': 'object',
              'additionalProperties': false,
              'properties': {
                'city': {'type': 'string', 'description': 'Name of the city'}
              },
              'required': ['city']
            }));

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    handlerCalled = true;
    final city = arguments['city'] as String;
    final tempC = 22;
    return jsonEncode({'city': city, 'temp_c': tempC});
  }
}

class DontCallTool extends FunctionToolHandler {
  bool handlerCalled = false;

  DontCallTool()
      : super(
            metadata: FunctionTool(
                name: 'dont_call_this_tool',
                description: 'always fails. do not ever call this function.',
                strict: true,
                parameters: {
              'type': 'object',
              'additionalProperties': false,
              'properties': {},
              'required': []
            }));

  @override
  Future<String> execute(Map<String, dynamic> arguments) async {
    return "";
  }
}

class DummyImageGenerationToolHandler extends ImageGenerationToolHandler {
  DummyImageGenerationToolHandler({required super.metadata});

  @override
  Future<void> onImageGenerationCall(
      ResponseImageGenerationCallEvent e) async {}
}

void main() {
  test(
      'EventLoop invokes a FunctionTool and executes its handler when not streaming and not storing',
      () async {
    final apiKey = Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      fail(
        'OPENAI_API_KEY must be set for this integration test. '
        'Set it in your shell before running `dart test`.',
      );
    }

    final client = OpenAIClient(apiKey: apiKey);

    final tool = WeatherTool();
    final abort = DontCallTool();

    final session = ResponseSession(
        client: client,
        tools: [tool, abort],
        // Tell the model it *must* use the tool.
        model: ChatModel.gpt4o, // or any model that supports tool calls
        store: false,
        stream: false,
        input: const ResponseInputText(
            'What is the current temperature in Paris?'));

    final response = await session.nextResponse();

    client.close();

    // ——— Assertions ———
    expect(abort.handlerCalled, isFalse,
        reason: 'FunctionTool handler should not have been executed.');

    // ——— Assertions ———
    expect(tool.handlerCalled, isTrue,
        reason: 'FunctionTool handler should have been executed.');

    // Optionally check that the tool’s synthetic answer made it back.
    expect(response.outputText, contains('22'),
        reason: 'The final answer should reference the temperature.');
  });

  test(
      'EventLoop invokes a FunctionTool and executes its handler when not streaming and storing',
      () async {
    final apiKey = Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      fail(
        'OPENAI_API_KEY must be set for this integration test. '
        'Set it in your shell before running `dart test`.',
      );
    }

    final client = OpenAIClient(apiKey: apiKey);

    final tool = WeatherTool();

    final session = ResponseSession(
        client: client,
        tools: [tool],
        // Tell the model it *must* use the tool.
        model: ChatModel.gpt4o, // or any model that supports tool calls
        store: true,
        stream: false,
        input: const ResponseInputText(
            'What is the current temperature in Paris?'));

    final response = await session.nextResponse();

    client.close();

    // ——— Assertions ———
    expect(tool.handlerCalled, isTrue,
        reason: 'FunctionTool handler should have been executed.');

    // Optionally check that the tool’s synthetic answer made it back.
    expect(response.outputText, contains('22'),
        reason: 'The final answer should reference the temperature.');
  });

  test(
      'EventLoop invokes a FunctionTool and executes its handler when streaming and not storing)',
      () async {
    final apiKey = Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      fail(
        'OPENAI_API_KEY must be set for this integration test. '
        'Set it in your shell before running `dart test`.',
      );
    }

    final client = OpenAIClient(apiKey: apiKey);

    var tool = WeatherTool();

    final session = ResponseSession(
        client: client,
        tools: [tool],
        model: ChatModel.gpt4o, // or any model that supports tool calls
        store: false,
        stream: true,
        input: const ResponseInputText(
            'What is the current temperature in Paris?'));

    final response = await session.nextResponse();
    client.close();

    // ——— Assertions ———
    expect(tool.handlerCalled, isTrue,
        reason: 'FunctionTool handler should have been executed.');

    // Optionally check that the tool’s synthetic answer made it back.
    expect(response.outputText, contains('22'),
        reason: 'The final answer should reference the temperature.');
  });

  test(
      'EventLoop invokes a FunctionTool and executes its handler when streaming and storing)',
      () async {
    final apiKey = Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      fail(
        'OPENAI_API_KEY must be set for this integration test. '
        'Set it in your shell before running `dart test`.',
      );
    }

    final client = OpenAIClient(apiKey: apiKey);

    var tool = WeatherTool();

    final session = ResponseSession(
        client: client,
        tools: [tool],
        model: ChatModel.gpt4o, // or any model that supports tool calls
        store: true,
        stream: true,
        input: const ResponseInputText(
            'What is the current temperature in Paris?'));

    final response = await session.nextResponse();
    client.close();

    // ——— Assertions ———
    expect(tool.handlerCalled, isTrue,
        reason: 'FunctionTool handler should have been executed.');

    // Optionally check that the tool’s synthetic answer made it back.
    expect(response.outputText, contains('22'),
        reason: 'The final answer should reference the temperature.');
  });

  test(
    'EventLoop completes an image_generation tool call',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('Set OPENAI_API_KEY in your environment to run this test.');
      }

      final client = OpenAIClient(apiKey: apiKey);

      final session = ResponseSession(
          client: client,
          tools: [
            DummyImageGenerationToolHandler(
                metadata: ImageGenerationTool(
              quality: ImageOutputQuality.medium,
              imageOutputSize: ImageOutputSize.square1024,
            ))
          ],
          toolChoice: const ToolChoiceImageGeneration(),
          model: ChatModel.gpt4o,
          store: true,
          stream: false,
          input: const ResponseInputText("make me an image of a cat"));

      final response = await session.nextResponse(false);
      client.close();

      final imgCall = response.output!
          .whereType<ImageGenerationCall>()
          .firstWhere((_) => true,
              orElse: () => throw StateError(
                  'No ImageGenerationCall found in response.output'));

      expect(imgCall.status, ImageGenerationCallStatus.completed,
          reason: 'Image generation should have completed.');

      // 2. The base-64 payload should decode to non-empty bytes.
      expect(imgCall.resultBase64, isNotNull,
          reason: 'ImageGenerationCall.resultBase64 should be populated.');

      Uint8List bytes = Uint8List(0);
      expect(() => bytes = base64Decode(imgCall.resultBase64!), returnsNormally,
          reason: 'resultBase64 must be valid base-64.');

      expect(bytes.lengthInBytes, greaterThan(10 * 1024),
          reason: 'Returned image seems too small to be a real PNG/JPEG.');
    },
  );

  test(
    'EventLoop completes an image_generation tool call',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('Set OPENAI_API_KEY in your environment to run this test.');
      }

      final client = OpenAIClient(apiKey: apiKey);

      final session = ResponseSession(
          client: client,
          tools: [
            DummyImageGenerationToolHandler(
                metadata: const ImageGenerationTool(
              partialImages: 1,
              quality: ImageOutputQuality.medium,
              imageOutputSize: ImageOutputSize.square1024,
            ))
          ],
          toolChoice: const ToolChoiceImageGeneration(),
          model: ChatModel.gpt4o,
          store: true,
          stream: true,
          input: const ResponseInputText("make me an image of a cat"));

      bool partialReceived = false;

      session.serverEvents.listen((e) {
        if (e is ResponseImageGenerationCallPartialImage) {
          partialReceived = true;
        }
      });
      final response = await session.nextResponse(false);

      client.close();

      expect(partialReceived, true,
          reason: "Partial image should have been recieved");

      // ───── Assertions ─────
      // 1. ImageGenerationCall must be present.
      final imgCall = response.output!
          .whereType<ImageGenerationCall>()
          .firstWhere((_) => true,
              orElse: () => throw StateError(
                  'No ImageGenerationCall found in response.output'));

      expect(imgCall.status, ImageGenerationCallStatus.completed,
          reason: 'Image generation should have completed.');

      // 2. The base-64 payload should decode to non-empty bytes.
      expect(imgCall.resultBase64, isNotNull,
          reason: 'ImageGenerationCall.resultBase64 should be populated.');

      Uint8List bytes = Uint8List(0);
      expect(() => bytes = base64Decode(imgCall.resultBase64!), returnsNormally,
          reason: 'resultBase64 must be valid base-64.');

      expect(bytes.lengthInBytes, greaterThan(10 * 1024),
          reason: 'Returned image seems too small to be a real PNG/JPEG.');
    },
  );

  test(
    'GPT-4o recognises a stop-sign screenshot',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('Set OPENAI_API_KEY in your shell before running this test.');
      }

      final client = OpenAIClient(apiKey: apiKey);

      // Pretend we took a screenshot and saved it at some URL
      final file = File("integration_test/desktop.jpg");
      final imageUrl =
          "data:image/jpeg;base64,${base64Encode(await file.readAsBytes())}";

      // Build the mixed-modal user message: image + text prompt.
      final visionInput = ResponseInputItems([
        InputMessage(
          role: 'user',
          content: [
            InputImageContent(
              detail: ImageDetail.auto,
              imageUrl: imageUrl,
            ),
            const InputTextContent(text: 'What is in this image?')
          ],
        ),
      ]);

      final session = ResponseSession(
        client: client,
        model: ChatModel.gpt4o, // any GPT-4o variant that supports vision
        stream: false, // easier: single blocking call, no SSE
      )..input = visionInput;

      final response = await session.nextResponse(false);
      client.close();

      final description = response.outputText;
      expect(
        description,
        isNotNull,
        reason: 'Model returned no textual description.',
      );

      expect(
        description!.toLowerCase(),
        allOf(contains('desktop')),
        reason: 'GPT-4o should identify screenshot as a desktop.',
      );
    },
  );
}
