// ──────────────────────────────────────────────────────────────────────────
// realtime_integration_test.dart
//
// Integration test – establishes a realtime WebSocket session against the
// live OpenAI endpoint and waits for the initial handshake events.
// ──────────────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:test/test.dart';
import '../lib/openai_client.dart';
import '../lib/realtime.dart'; // brings RealtimeEvent & friends
import '../lib/realtime_io.dart'; // the extension you pasted above

void main() {
  // Pull the API key from the environment – fail fast if it’s missing.
  final apiKey = Platform.environment['OPENAI_API_KEY'];

  if (apiKey == null || apiKey.isEmpty) {
    throw StateError(
      'Set the OPENAI_API_KEY environment variable before running this test.',
    );
  }

  group('Realtime WebSocket handshake (live)', () {
    late OpenAIClient client;
    late WebsocketRealtimeSessionController wsCtrl;

    setUp(() {
      client = OpenAIClient(
        apiKey: apiKey,
        // You can point at a different base URL if you have a proxy or a
        // dedicated testing stack. By default this is https://api.openai.com
      );
    });

    tearDown(() async {
      // Close the socket/stream nicely so subsequent tests aren’t affected.
      wsCtrl.dispose();
      client.close();
    });

    test(
      'receives session.created ➜ conversation.created',
      timeout: const Timeout(Duration(seconds: 20)), // generous, but finite
      () async {
        // 1. Dial the realtime socket (we use the public preview model here).
        wsCtrl = await client.createRealtimeWebsocket(
          token: apiKey,
          model: RealtimeModel.gpt4oRealtimePreview,
        );

        // 2. Listen for the very first two server-side events.
        final firstEvent = await wsCtrl.serverEvents.first;
        expect(firstEvent.type, equals('session.created'),
            reason: 'first server event should be session.created');

        // 3. Make sure the objects inside are well-formed.
        final sess = (firstEvent as SessionCreatedEvent).session;
        expect(sess.id, isNotEmpty);
        expect(sess.object, equals('realtime.session'));

        // 4. Make sure we can send commands over the wire
        wsCtrl.send(
          RealtimeResponseCreateEvent(
            response: RealtimeResponseOptions(
              input: [
                RealtimeMessageItem(
                  role: "user",
                  content: [RealtimeInputText("hi there")],
                  status: null,
                ),
              ],
            ),
          ),
        );

        await wsCtrl.serverEvents
            .firstWhere((x) => x is ConversationItemCreatedEvent);
      },
    );
  });
}
