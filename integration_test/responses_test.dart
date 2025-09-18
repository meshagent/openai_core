// test/integration/response_api_test.dart
@Timeout(Duration(minutes: 3)) // responses can stream for a bit
import 'dart:io';
import 'package:test/test.dart';

import '../lib/common.dart';
import '../lib/openai_client.dart'; // core SDK
import '../lib/responses.dart';
import 'dart:convert';

void main() {
  // ---------------------------------------------------------------------------
  // 0. Setup / tear-down
  // ---------------------------------------------------------------------------
  final apiKey = Platform.environment['OPENAI_API_KEY'];

  if (apiKey == null || apiKey.isEmpty) {
    // Skip the whole file when no key is available.
    print('⚠️  OPENAI_API_KEY not set – skipping integration tests.');
    return;
  }

  late OpenAIClient client;

  setUpAll(() {
    client = OpenAIClient(apiKey: apiKey);
  });

  tearDownAll(() async => client.close());

  // ---------------------------------------------------------------------------
  // createResponse – synchronous, non-streaming
  // ---------------------------------------------------------------------------
  test('createResponse returns completed response with text output', () async {
    final response = await client.createResponse(
      model: ChatModel.gpt4o, // any Responses-enabled model
      input: const ResponseInputText('Say hello'), // super cheap prompt
      text: const TextFormatText(), // ask for plain text
    );

    expect(response.error, isNull);
    expect(response.status, anyOf(['completed', 'in_progress', 'queued']));
    expect(response.outputText, isNotNull);
    expect(response.outputText?.toLowerCase(), contains('hello'));
  });

  // ---------------------------------------------------------------------------
  // streamResponse – SSE streaming / event parsing
  // ---------------------------------------------------------------------------
  test('streamResponse yields events through to response.completed', () async {
    final stream = await client.streamResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText('Count to 3'),
      text: const TextFormatText(),
    );

    final buffer = StringBuffer();
    ResponseCompleted? completedEvt;

    await for (final evt in stream.events) {
      switch (evt) {
        case ResponseOutputTextDelta(:final delta):
          buffer.write(delta);
          break;
        case ResponseOutputTextDone(:final text):
          buffer.write(text); // just in case the API jumps straight to done
          break;
        case ResponseCompleted():
          completedEvt = evt;
        default:
          // ignore every other event type for this smoke-test
          break;
      }
    }

    await stream.close();

    expect(completedEvt, isNotNull, reason: 'No response.completed event seen');
    final finalText = buffer.toString().toLowerCase();
    expect(
        (finalText.contains('1') || finalText.contains('one')) &&
            (finalText.contains('2') || finalText.contains('two')) &&
            (finalText.contains('3') || finalText.contains('three')),
        isTrue,
        reason: 'Expected the model to count to three, got: "$finalText"');
  });

// ---------------------------------------------------------------------------
// createResponse – image-generation, non-streaming
// ---------------------------------------------------------------------------
  test('createResponse returns an image_generation_call result', () async {
    final response = await client.createResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText('Generate a simple blue square.'),
      // Force the model to pick the image-generation tool
      toolChoice: const ToolChoiceImageGeneration(),
      tools: const [
        // Keep all options “auto” so defaults work on any account
        ImageGenerationTool(
          imageOutputFormat: ImageOutputFormat.png,
          imageOutputSize: ImageOutputSize.square1024,
        ),
      ],
    );

    // Basic sanity checks ------------------------------------------------------
    expect(response.error, isNull);
    expect(response.status, anyOf(['completed', 'in_progress', 'queued']));

    // When the response is completed we should have at least one image item ----
    if (response.status == 'completed') {
      final imgItems =
          response.output?.whereType<ImageGenerationCall>().toList() ?? [];
      expect(imgItems, isNotEmpty,
          reason:
              'Expected at least one image_generation_call in Response.output');

      final img = imgItems.first;
      expect(img.status, ImageGenerationCallStatus.completed);
      expect(img.resultBase64, isNotNull,
          reason: 'No base-64 payload returned for the completed image.');
      // The payload should be non-trivial (a minimal guard against empty strings)
      expect(img.resultBase64!.length, greaterThan(100));
    }
  });

// ---------------------------------------------------------------------------
// streamResponse – image-generation, SSE streaming
// ---------------------------------------------------------------------------
  test('streamResponse streams image_generation events until completion',
      () async {
    final stream = await client.streamResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText('A red triangle on a white background.'),
      toolChoice: const ToolChoiceImageGeneration(),
      tools: const [ImageGenerationTool(partialImages: 1)],
    );

    ResponseImageGenerationCallCompleted? completedEvt;
    int partialImages = 0;

    await for (final evt in stream.events) {
      switch (evt) {
        case ResponseImageGenerationCallPartialImage():
          partialImages += 1; // count any progressive previews
          break;
        case ResponseImageGenerationCallCompleted():
          completedEvt = evt;
          break;
        default:
          // Ignore other event types for this smoke-test
          break;
      }
    }
    await stream.close();

    // The stream **must** finish with a completed event ------------------------
    expect(completedEvt, isNotNull,
        reason: 'Did not receive image_generation_call.completed');
    expect(partialImages, greaterThanOrEqualTo(0)); // zero-or-more partials ok
  });

// ---------------------------------------------------------------------------
// createResponse – web_search_preview, non-streaming
// ---------------------------------------------------------------------------
  test('createResponse performs a web search call', () async {
    final response = await client.createResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText(
        'Search the web for the birthplace of Ada Lovelace.',
      ),

      // Require the model to use the web-search tool we supply
      toolChoice: const ToolChoiceRequired(),
      tools: const [
        WebSearchPreviewTool(), // defaults are fine for the smoke-test
      ],
    );

    // Baseline sanity checks ---------------------------------------------------
    expect(response.error, isNull,
        reason: 'The call failed: ${response.error?.message}');
    expect(response.status, anyOf(['completed', 'in_progress', 'queued']));

    // If generation is already finished, validate that at least one
    // web_search_call item exists and was marked completed ---------------
    if (response.status == 'completed') {
      final wsItems =
          response.output?.whereType<WebSearchCall>().toList() ?? [];
      expect(wsItems, isNotEmpty,
          reason: 'No web_search_call item found in Response.output');

      final first = wsItems.first;
      expect(first.status, WebSearchToolCallStatus.completed);
    }
  });

// ---------------------------------------------------------------------------
// streamResponse – web_search_preview, SSE streaming
// ---------------------------------------------------------------------------
  test('streamResponse streams web_search events through completion', () async {
    final stream = await client.streamResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText(
        'Use web search to find the tallest mountain on Earth.',
      ),
      toolChoice: const ToolChoiceRequired(),
      tools: const [WebSearchPreviewTool()],
    );

    ResponseWebSearchCallCompleted? completedEvt;

    await for (final evt in stream.events) {
      switch (evt) {
        case ResponseWebSearchCallCompleted():
          completedEvt = evt;
          break;
        // Ignore everything else for this simple verification
        default:
          break;
      }
    }
    await stream.close();

    // The stream *must* give us a completed event ------------------------------
    expect(completedEvt, isNotNull,
        reason: 'Did not receive web_search_call.completed in the stream');
  });

// ---------------------------------------------------------------------------
// createResponse – MCP list-tools (non-streaming)
// ---------------------------------------------------------------------------
  test('createResponse lists DeepWiki MCP tools', () async {
    final response = await client.createResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText(
        'List the available MCP tools on the DeepWiki server.',
      ),
      toolChoice: const ToolChoiceRequired(),
      tools: const [
        McpTool(
          serverLabel: 'deepwiki',
          serverUrl: 'https://mcp.deepwiki.com/mcp',
          requireApproval: MCPToolApprovalNever(),
        ),
      ],
    );

    // Basic API sanity --------------------------------------------------------
    expect(response.error, isNull,
        reason: 'Call failed: ${response.error?.message}');
    expect(response.status, anyOf(['completed', 'in_progress', 'queued']));

    // If already finished, ensure we received a list-tools item ---------------
    if (response.status == 'completed') {
      final listTools =
          response.output?.whereType<McpListTools>().toList() ?? [];
      expect(listTools, isNotEmpty,
          reason: 'No mcp_list_tools item came back from DeepWiki.');
      expect(listTools.first.serverLabel, equals('deepwiki'));
      expect(listTools.first.tools, isNotEmpty,
          reason: 'DeepWiki returned an empty tool list.');
    }
  });

// ---------------------------------------------------------------------------
// streamResponse – MCP list-tools (SSE streaming)
// ---------------------------------------------------------------------------
  test('streamResponse streams DeepWiki MCP list-tools events', () async {
    final stream = await client.streamResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText(
        'List all MCP tools provided by the DeepWiki server.',
      ),
      toolChoice: const ToolChoiceRequired(),
      tools: const [
        McpTool(
          serverLabel: 'deepwiki',
          serverUrl: 'https://mcp.deepwiki.com/mcp',
          requireApproval: MCPToolApprovalNever(),
        ),
      ],
    );

    ResponseMcpListToolsCompleted? completedEvt;

    await for (final evt in stream.events) {
      switch (evt) {
        case ResponseMcpListToolsCompleted():
          completedEvt = evt;
          break;
        default:
          // ignore other event kinds
          break;
      }
    }
    await stream.close();

    // The streaming session must yield a completed list-tools event ----------
    expect(completedEvt, isNotNull,
        reason: 'Did not receive mcp_list_tools.completed from DeepWiki.');
  });

// ---------------------------------------------------------------------------
// createResponse – code_interpreter with auto-container
// ---------------------------------------------------------------------------
  test('createResponse executes code_interpreter 6 × 7 ⇒ 42', () async {
    final response = await client.createResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText(
        'Use the code interpreter to compute and print 6 * 7.',
      ),
      toolChoice: const ToolChoiceCodeInterpreter(), // force the CI tool
      tools: const [
        CodeInterpreterTool(
          container: CodeInterpreterContainerAuto(), // "auto" container
        ),
      ],
    );

    // Basic sanity ------------------------------------------------------------
    expect(response.error, isNull,
        reason: 'Call failed: ${response.error?.message}');
    expect(response.status, anyOf(['completed', 'in_progress', 'queued']));

    if (response.status == 'completed') {
      final ciItems =
          response.output?.whereType<CodeInterpreterCall>().toList() ?? [];
      expect(ciItems, isNotEmpty,
          reason: 'No code_interpreter_call item returned.');

      final first = ciItems.first;
      expect(first.status, CodeInterpreterToolCallStatus.completed);
    }
  });

// ---------------------------------------------------------------------------
// streamResponse – code_interpreter with auto-container
// ---------------------------------------------------------------------------
  test('streamResponse streams code_interpreter output until completion',
      () async {
    final stream = await client.streamResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText(
        'Run Python in the code interpreter to print(40 + 2).',
      ),
      toolChoice: const ToolChoiceCodeInterpreter(),
      tools: const [
        CodeInterpreterTool(
          container: CodeInterpreterContainerAuto(),
        ),
      ],
    );

    CodeInterpreterCall? completedCi;

    await for (final evt in stream.events) {
      switch (evt) {
        case ResponseOutputItemDone(:final item)
            when item is CodeInterpreterCall &&
                item.status == CodeInterpreterToolCallStatus.completed:
          completedCi = item;
          break;
        default:
          // ignore everything else
          break;
      }
    }
    await stream.close();

    // Must have seen a completed CI call --------------------------------------
    expect(completedCi, isNotNull,
        reason: 'Completed code_interpreter_call never arrived.');
  });

// ---------------------------------------------------------------------------
// createResponse – include(model-reasoning) non-streaming
// ---------------------------------------------------------------------------
  test('createResponse returns reasoning output item', () async {
    final response = await client.createResponse(
      model: ChatModel.o4Mini,
      input: const ResponseInputText(
        'Write me some code to simulate gravity in python on the sun.',
      ),

      // Ask the API to surface its reasoning
      include: const ['reasoning.encrypted_content'],
      store: false,
      reasoning: const ReasoningOptions(
        effort: ReasoningEffort.medium,
        summary: ReasoningDetail.detailed,
      ),
    );

    // Basic sanity ------------------------------------------------------------
    expect(response.error, isNull,
        reason: 'Call failed: ${response.error?.message}');
    expect(response.status, anyOf(['completed', 'in_progress', 'queued']));

    if (response.status == 'completed') {
      final reasonItems =
          response.output?.whereType<Reasoning>().toList() ?? [];
      expect(reasonItems, isNotEmpty,
          reason: 'No reasoning output present in the final Response.');
    }
  });

// ---------------------------------------------------------------------------
// streamResponse – reasoning.delta / reasoning.done
// ---------------------------------------------------------------------------
  test('streamResponse emits reasoning.delta events until reasoning.done',
      () async {
    final stream = await client.streamResponse(
      store: false,
      model: ChatModel.o4Mini,
      input: const ResponseInputText(
        'Write me some code to simulate gravity in python on the sun.',
      ),
      include: const ['reasoning.encrypted_content'],
      reasoning: const ReasoningOptions(
        effort: ReasoningEffort.medium,
        summary: ReasoningDetail.detailed,
      ),
    );

    int deltaCount = 0;

    await for (final evt in stream.events) {
      switch (evt) {
        case ResponseReasoningDelta():
          deltaCount += 1;
          break;
        case ResponseReasoningSummaryTextDelta():
          deltaCount += 1;
          break;
        default:
          // ignore other kinds
          break;
      }
    }
    await stream.close();

    // Assertions --------------------------------------------------------------
    expect(deltaCount, greaterThan(0),
        reason: 'No reasoning.delta events were observed.');
  });

// ────────────────────────────────────────────────────────────────────────────
// createResponse – local_shell round-trip (non-streaming)
// ────────────────────────────────────────────────────────────────────────────
  test('createResponse→run shell→send output back (non-streaming)', () async {
    // ❶ Ask the model to run echo …
    final first = await client.createResponse(
      model: ChatModel.codexMiniLatest,
      input: const ResponseInputText(
        'Run the command `echo hello-from-shell` in the local shell.',
      ),
      toolChoice: const ToolChoiceRequired(),
      tools: const [LocalShellTool()],
    );

    expect(first.error, isNull);
    final callItem = first.output?.whereType<LocalShellCall>().firstWhere(
          (_) => true,
          orElse: () => throw TestFailure('No local_shell_call item returned.'),
        );

    // ❷ Execute the command that the model requested
    final cmd = callItem!.action.command;
    final proc = await Process.run(cmd.first, cmd.skip(1).toList());
    final stdoutStr = (proc.stdout as String).trim();

    // ❸ Create the output item we’ll feed back to the API
    final outputItem = LocalShellCallOutput(
      callId: callItem.callId,
      output: stdoutStr,
      status: LocalShellCallStatus.completed,
    );

    // ❹ Send a follow-up Responses call so the model can continue
    final followUp = await client.createResponse(
      model: ChatModel.codexMiniLatest,
      previousResponseId: first.id,
      input: ResponseInputItems([outputItem]),
    );

    // ❺ Basic assertions on the second round-trip
    expect(followUp.error, isNull,
        reason: 'Follow-up failed: ${followUp.error?.message}');
    expect(followUp.status, anyOf(['completed', 'in_progress', 'queued']));
  });

// ────────────────────────────────────────────────────────────────────────────
// streamResponse – local_shell round-trip (streaming)
// ────────────────────────────────────────────────────────────────────────────
  test('streamResponse→run shell→send output back', () async {
    // ❶ Start the streamed session
    final stream = await client.streamResponse(
      model: ChatModel.codexMiniLatest,
      input: const ResponseInputText(
        'Use the local shell to run `echo streamed-shell-test`',
      ),
      toolChoice: const ToolChoiceRequired(),
      tools: const [LocalShellTool()],
    );

    LocalShellCall? callItem;
    ResponseCompleted? completed;

    // ❷ Find the completed shell-call request in the event stream
    await for (final evt in stream.events) {
      if (evt is ResponseOutputItemDone &&
          evt.item is LocalShellCall &&
          (evt.item as LocalShellCall).status ==
              LocalShellCallStatus.completed) {
        callItem = evt.item as LocalShellCall;
      }

      if (evt is ResponseCompleted) {
        completed = evt;
      }
    }
    await stream.close();

    expect(callItem, isNotNull,
        reason: 'Did not observe a completed local_shell_call in the stream.');

    // ❸ Run the requested command
    final cmd = callItem!.action.command;
    final proc = await Process.run(cmd.first, cmd.skip(1).toList());
    final stdoutStr = (proc.stdout as String).trim();

    // ❹ Build & send the tool-output follow-up
    final outputItem = LocalShellCallOutput(
      callId: callItem.callId,
      output: stdoutStr,
      status: LocalShellCallStatus.completed,
    );

    final followUp = await client.createResponse(
      model: ChatModel.codexMiniLatest,
      previousResponseId:
          completed!.response.id, // response ID equals first stream ID
      input: ResponseInputItems([outputItem]),
    );

    // ❺ Assertions on the follow-up
    expect(followUp.error, isNull,
        reason: 'Follow-up failed: ${followUp.error?.message}');
    expect(followUp.status, anyOf(['completed', 'in_progress', 'queued']));
  });

// ---------------------------------------------------------------------------
// createResponse → run add_two_ints locally → send output back
// ---------------------------------------------------------------------------
  test('function_tool round-trip (non-streaming)', () async {
    /* ❶ Ask the model to call the function */
    final first = await client.createResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText(
        'Please call `add_two_ints` with a = 2 and b = 3.',
      ),
      toolChoice: const ToolChoiceFunction(name: 'add_two_ints'),
      tools: const [
        FunctionTool(
          name: 'add_two_ints',
          parameters: {
            'type': 'object',
            'properties': {
              'a': {'type': 'integer'},
              'b': {'type': 'integer'}
            },
            'required': ['a', 'b']
          },
        ),
      ],
    );

    expect(first.error, isNull,
        reason: 'Initial call failed: ${first.error?.message}');

    /* ❷ Find the FunctionCall item and compute the result */
    final call = first.output?.whereType<FunctionCall>().firstWhere(
          (_) => true,
          orElse: () => throw TestFailure('No function_call emitted.'),
        );

    final argMap = jsonDecode(call!.arguments) as Map<String, dynamic>;
    final int a = argMap['a'] as int;
    final int b = argMap['b'] as int;
    final int sum = a + b;

    /* ❸ Build the FunctionCallOutput item */
    final outputItem = FunctionCallOutput(
      callId: call.callId,
      output: jsonEncode({'result': sum}),
      status: FunctionToolCallStatus.completed,
    );

    /* ❹ Send follow-up so the model can continue */
    final followUp = await client.createResponse(
      model: ChatModel.gpt4o,
      previousResponseId: first.id,
      input: ResponseInputItems([outputItem]),
    );

    /* ❺ Basic assertions on the follow-up */
    expect(followUp.error, isNull,
        reason: 'Follow-up failed: ${followUp.error?.message}');
    expect(followUp.status, anyOf(['completed', 'in_progress', 'queued']));
  });

// ---------------------------------------------------------------------------
// streamResponse → run add_two_ints locally → send output back
// ---------------------------------------------------------------------------
  test('function_tool round-trip (streaming)', () async {
    /* ❶ Start the streamed session */
    final stream = await client.streamResponse(
      model: ChatModel.gpt4o,
      input: const ResponseInputText(
        'Invoke `add_two_ints` using a = 2 and b = 3.',
      ),
      toolChoice: const ToolChoiceFunction(name: 'add_two_ints'),
      tools: const [
        FunctionTool(
          name: 'add_two_ints',
          parameters: {
            'type': 'object',
            'properties': {
              'a': {'type': 'integer'},
              'b': {'type': 'integer'}
            },
            'required': ['a', 'b']
          },
        ),
      ],
    );

    ResponeFunctionCallArgumentsDone? argsDone;
    ResponseCompleted? completedEvt;
    FunctionCall? functionCall;

    /* ❷ Collect the arguments and the completed envelope */
    await for (final evt in stream.events) {
      switch (evt) {
        case ResponseOutputItemDone(item: FunctionCall()):
          functionCall = evt.item as FunctionCall;
        case ResponeFunctionCallArgumentsDone():
          argsDone = evt;
          break;
        case ResponseCompleted():
          completedEvt = evt;
          break;
        default:
          break;
      }
    }
    await stream.close();

    expect(argsDone, isNotNull,
        reason: 'No function_call_arguments.done received.');
    expect(completedEvt, isNotNull,
        reason: 'No response.completed event received.');

    /* ❸ Compute the result locally */
    final args = jsonDecode(argsDone!.arguments) as Map<String, dynamic>;
    final int a = args['a'] as int;
    final int b = args['b'] as int;
    final int sum = a + b;

    /* ❹ Build the FunctionCallOutput item */
    final outputItem = FunctionCallOutput(
      callId: functionCall!.callId, // same ID as the original function call
      output: jsonEncode({'result': sum}),
      status: FunctionToolCallStatus.completed,
    );

    /* ❺ Send follow-up using the ID from response.completed */
    final followUp = await client.createResponse(
      model: ChatModel.gpt4o,
      previousResponseId: completedEvt!.response.id,
      input: ResponseInputItems([outputItem]),
    );

    /* ❻ Verify follow-up accepted the tool output */
    expect(followUp.error, isNull,
        reason: 'Follow-up failed: ${followUp.error?.message}');
    expect(followUp.status, anyOf(['completed', 'in_progress', 'queued']));
  });

  // ---------------------------------------------------------------------------
  //  computer_call round-trip (non-streaming)
  // ---------------------------------------------------------------------------
  test('computer_call → run locally → send output back', () async {
    /* ❶ Ask the model to perform a computer action */
    final first = await client.createResponse(
      model: ChatModel.computerUsePreview,
      truncation: Truncation.auto,
      input: const ResponseInputText(
        'click the recycle bin',
      ),
      toolChoice: const ToolChoiceRequired(), // force tool use
      tools: const [
        ComputerUsePreviewTool(
          displayHeight: 670,
          displayWidth: 1192,
          environment: 'windows',
        ),
      ],
    );

    // Basic sanity on the first round ----------------------------------------
    expect(first.error, isNull,
        reason: 'Initial request failed: ${first.error?.message}');
    var compCall = first.output?.whereType<ComputerCall>().firstWhere(
          (_) => true,
          orElse: () =>
              throw TestFailure('Model did not emit a computer_call item.'),
        );

    // ❷ ‘Run’ the action locally (here we only log/pretend) -------------------
    final action = compCall!.action;
    expect(action is ComputerActionScreenshot, isTrue,
        reason: 'Expected a screenhot action from the model.');

    // Pretend we took a screenshot and saved it at some URL
    final file = File("integration_test/desktop.jpg");
    final fakeScreenshot =
        "data:image/jpeg;base64,${base64Encode(await file.readAsBytes())}";

    // ❸ Build the ComputerCallOutput to send back ----------------------------
    final outputItem = ComputerCallOutput(
      callId: compCall.callId,
      output: ComputerScreenshotOutput(imageUrl: fakeScreenshot), // tool result
      acknowledgedSafetyChecks: compCall.pendingSafetyChecks,
      status: ComputerResultStatus.completed,
    );

    // ❹ Call the Responses API again so the model can continue ----------------
    final followUp = await client.createResponse(
      model: ChatModel.computerUsePreview,
      truncation: Truncation.auto,
      previousResponseId: first.id,
      tools: [
        ComputerUsePreviewTool(
          displayHeight: 670,
          displayWidth: 1192,
          environment: 'windows',
        ),
      ],
      input: ResponseInputItems([outputItem]),
    );

    // ❺ Verify the follow-up was accepted -------------------------------------
    expect(followUp.error, isNull,
        reason: 'Follow-up failed: ${followUp.error?.message}');
    expect(followUp.status, anyOf(['completed', 'in_progress', 'queued']));

    /*
    compCall = followUp.output?.whereType<ComputerCall>().firstWhere(
          (_) => true,
          orElse: () =>
              throw TestFailure('Model did not emit a computer_call item.'),
        );
    final actionFollowup = compCall!.action;
    expect(actionFollowup is ComputerActionClick, isTrue,
        reason: 'Expected a click action from the model.');
    final click = actionFollowup as ComputerActionClick;
    expect(click.button, equals('left'));*/
  });

// ---------------------------------------------------------------------------
// computer_call round-trip (streaming)
// ---------------------------------------------------------------------------

  test('streamed computer_call → run locally → send output back', () async {
    /* ❶ Start the streamed session that should request a screenshot */
    final stream = await client.streamResponse(
      model: ChatModel.computerUsePreview,
      truncation: Truncation.auto,
      input: const ResponseInputText('take a screenshot'),
      toolChoice: const ToolChoiceRequired(),
      tools: const [
        ComputerUsePreviewTool(
          displayHeight: 670,
          displayWidth: 1192,
          environment: 'windows',
        ),
      ],
    );

    ComputerCall? compCall;
    ResponseCompleted? completedEvt;

    /* ❷ Listen for the computer_call and the completed envelope */
    await for (final evt in stream.events) {
      switch (evt) {
        case ResponseOutputItemAdded(:final item) when item is ComputerCall:
          compCall = item;
          break;
        case ResponseOutputItemDone(:final item) when item is ComputerCall:
          compCall = item;
          break;
        case ResponseCompleted():
          completedEvt = evt;
          break;
        default:
          break; // ignore everything else
      }
    }
    await stream.close();

    /* ❸ Basic assertions on what the model requested */
    expect(compCall, isNotNull,
        reason: 'No computer_call item appeared in the stream.');
    expect(completedEvt, isNotNull,
        reason: 'No response.completed event was observed.');

    final action = compCall!.action;
    expect(action is ComputerActionScreenshot, isTrue,
        reason: 'Expected the first action to be a screenshot.');

    /* ❹ Fake running the action locally (produce a JPEG → base64 URL) */
    final bytes = await File('integration_test/desktop.jpg').readAsBytes();
    final fakeScreenshot = 'data:image/jpeg;base64,${base64Encode(bytes)}';

    /* ❺ Build the tool-output item we’ll send back */
    final outputItem = ComputerCallOutput(
      callId: compCall.callId,
      output: ComputerScreenshotOutput(imageUrl: fakeScreenshot),
      acknowledgedSafetyChecks: compCall.pendingSafetyChecks,
      status: ComputerResultStatus.completed,
    );

    /* ❻ Follow-up Responses call so the model can continue */
    final followUp = await client.createResponse(
      model: ChatModel.computerUsePreview,
      truncation: Truncation.auto,
      previousResponseId: completedEvt!.response.id,
      tools: const [
        ComputerUsePreviewTool(
          displayHeight: 670,
          displayWidth: 1192,
          environment: 'windows',
        ),
      ],
      input: ResponseInputItems([outputItem]),
    );

    /* ❼ Verify follow-up accepted the output and asked for a click */
    expect(followUp.error, isNull,
        reason: 'Follow-up failed: ${followUp.error?.message}');
    expect(followUp.status, anyOf(['completed', 'in_progress', 'queued']));

    followUp.output?.whereType<ComputerCall>().firstWhere(
          (_) => true,
          orElse: () =>
              throw TestFailure('Model did not emit a second computer_call.'),
        );

/*
    final action2 = compCall2!.action;
    expect(action2 is ComputerActionClick, isTrue,
        reason: 'Expected a click action after sending the screenshot.');
    final click = action2 as ComputerActionClick;
    expect(click.button, equals('left'));*/
  });
}
