// integration_test/codex_session_test.dart
//
// Be sure to set an `OPENAI_API_KEY` environment variable before running:
// $ OPENAI_API_KEY=sk-... dart test

import 'dart:io';

import 'package:test/test.dart';

import '../lib/common.dart';
import '../lib/openai_client.dart';
import '../lib/responses.dart';
import '../lib/responses_session.dart';

/// A minimal LocalShellToolHandler implementation that executes the requested
/// shell command locally and returns its stdout (and stderr if present).
class EchoLocalShellTool extends LocalShellToolHandler {
  EchoLocalShellTool() : super(metadata: const LocalShellTool());

  bool executed = false;

  @override
  Future<LocalShellCallOutput> onLocalShellToolCall(
      ResponsesSessionController controller, LocalShellCall call) async {
    executed = true;
    print(call.action.toJson());
    final cmd = call.action.command;
    final proc = await Process.run(
      cmd.first,
      cmd.skip(1).toList(),
      workingDirectory: call.action.workingDirectory,
      environment: call.action.env.isEmpty ? null : call.action.env,
      includeParentEnvironment: true,
    );

    final stdoutStr = (proc.stdout is String)
        ? (proc.stdout as String).trim()
        : String.fromCharCodes((proc.stdout as List<int>)).trim();
    final stderrStr = (proc.stderr is String)
        ? (proc.stderr as String).trim()
        : String.fromCharCodes((proc.stderr as List<int>)).trim();

    final combined = [stdoutStr, if (stderrStr.isNotEmpty) stderrStr]
        .where((s) => s.isNotEmpty)
        .join('\n');

    // Return the output item to the session so it can be
    // forwarded back to the API on the next turn.
    return call.output(
      combined,
      status: LocalShellCallStatus.completed,
    );
  }
}

void main() {
  test(
    'gpt-5-codex + ResponsesSessionController + LocalShellToolHandler (non streaming, not storing)',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail(
          'OPENAI_API_KEY must be set for this integration test. '
          'Set it in your shell before running `dart test`.',
        );
      }

      final client = OpenAIClient(apiKey: apiKey);

      final shellTool = EchoLocalShellTool();

      final session = ResponsesSessionController(
        client: client,
        tools: [shellTool],
        // Use the gpt-5-codex model via a raw ChatModel identifier.
        model: ChatModel.fromJson('gpt-5-codex'),
        // Let the controller iterate over SSE events and handle tool calls.
        stream: false,
        // Store conversation state on the server between rounds.
        store: false,
        input: const ResponseInputText(
          'Use the local shell to run `echo gpt-5-codex-session-test` and tell me what it output.',
        ),
      );

      bool sawShellCall = false;
      session.serverEvents.listen((evt) {
        if (evt is ResponseOutputItemDone && evt.item is LocalShellCall) {
          sawShellCall = true;
        }
      });

      final response = await session.nextResponse();
      client.close();

      // Basic assertions to demonstrate the tool round-trip occurred.
      expect(sawShellCall, isTrue,
          reason: 'Model did not emit a local_shell_call.');
      expect(shellTool.executed, isTrue,
          reason: 'LocalShellToolHandler was not invoked.');
      expect(response.error, isNull,
          reason: 'Final response had an error: ${response.error?.message}');
    },
  );

  test(
    'gpt-5-codex + ResponsesSessionController + LocalShellToolHandler (streaming, storing)',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail(
          'OPENAI_API_KEY must be set for this integration test. '
          'Set it in your shell before running `dart test`.',
        );
      }

      final client = OpenAIClient(apiKey: apiKey);

      final shellTool = EchoLocalShellTool();

      final session = ResponsesSessionController(
        client: client,
        tools: [shellTool],
        // Use the gpt-5-codex model via a raw ChatModel identifier.
        model: ChatModel.fromJson('gpt-5-codex'),
        // Let the controller iterate over SSE events and handle tool calls.
        stream: true,
        // Store conversation state on the server between rounds.
        store: true,
        input: const ResponseInputText(
          'Use the local shell to run `echo gpt-5-codex-session-test` and tell me what it output.',
        ),
      );

      bool sawShellCall = false;
      session.serverEvents.listen((evt) {
        if (evt is ResponseOutputItemDone && evt.item is LocalShellCall) {
          sawShellCall = true;
        }
      });

      final response = await session.nextResponse();
      client.close();

      // Basic assertions to demonstrate the tool round-trip occurred.
      expect(sawShellCall, isTrue,
          reason: 'Model did not emit a local_shell_call.');
      expect(shellTool.executed, isTrue,
          reason: 'LocalShellToolHandler was not invoked.');
      expect(response.error, isNull,
          reason: 'Final response had an error: ${response.error?.message}');
    },
  );
}
