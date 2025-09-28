import 'dart:convert';

import 'openai_client.dart';
import 'realtime.dart';
import 'realtime_session_controller.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

extension RealtimeWebSocket on OpenAIClient {
  Future<WebsocketRealtimeSessionController> createRealtimeWebsocket(
      {required String token, RealtimeModel model = RealtimeModel.gptRealtime, String? callId, String? orgId, String? projectId}) async {
    final url = baseUrl.resolve("realtime").replace(
        scheme: baseUrl.scheme.replaceFirst("http", "ws"),
        queryParameters: {if (callId != null) "callId": callId, "model": model.toJson()});

    final headers = getHeaders({});

    headers!["Authorization"] = "Bearer " + token;

    final ws = await WebSocketChannel.connect(url, protocols: [
      "realtime",
      // Auth
      "openai-insecure-api-key." + token,
      if (orgId != null) "openai-organization." + orgId,
      if (projectId != null) "openai-project." + projectId,
    ]);

    return WebsocketRealtimeSessionController(webSocket: ws, initialTools: []);
  }
}

class WebsocketRealtimeSessionController extends RealtimeSessionController {
  WebsocketRealtimeSessionController({required this.webSocket, super.initialTools}) {
    _eventLoop();
  }

  @override
  void dispose() {
    super.dispose();
    webSocket.sink.close();
  }

  void _eventLoop() async {
    await for (final event in webSocket.stream) {
      serverEventsController.add(RealtimeEvent.fromJson(jsonDecode(event)));
    }
  }

  final WebSocketChannel webSocket;

  @override
  void send(RealtimeEvent event) {
    webSocket.sink.add(jsonEncode(event.toJson()));
    super.send(event);
  }
}
