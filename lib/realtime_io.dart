import 'dart:convert';
import 'dart:io';

import 'openai_client.dart';
import 'realtime.dart';
import 'realtime_session_controller.dart';

extension RealtimeIO on OpenAIClient {
  Future<WebsocketRealtimeSessionController> createRealtimeWebsocket(
      {required String token, RealtimeModel model = RealtimeModel.gptRealtime, String? callId, String? orgId, String? projectId}) async {
    final url = baseUrl.resolve("realtime").replace(
        scheme: baseUrl.scheme.replaceFirst("http", "ws"),
        queryParameters: {if (callId != null) "callId": callId, "model": model.toJson()});

    final headers = getHeaders({});

    headers!["Authorization"] = "Bearer " + token;
    if (orgId != null) {
      headers["OpenAI-Organization"] = orgId;
    }
    if (projectId != null) {
      headers["OpenAI-Project"] = projectId;
    }

    final ws = await WebSocket.connect(url.toString(), headers: headers);

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
    webSocket.close();
  }

  void _eventLoop() async {
    await for (final event in webSocket) {
      serverEventsController.add(RealtimeEvent.fromJson(jsonDecode(event)));
    }
  }

  final WebSocket webSocket;

  @override
  void send(RealtimeEvent event) {
    webSocket.add(jsonEncode(event.toJson()));
    super.send(event);
  }
}
