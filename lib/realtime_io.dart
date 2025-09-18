import 'dart:convert';
import 'dart:io';

import 'package:openai/audio.dart';
import 'package:openai/openai_client.dart';
import 'package:openai/realtime.dart';
import 'package:openai/realtime_session_controller.dart';
import 'package:openai/responses.dart';

extension RealtimeIO on OpenAIClient {
  Future<WebsocketRealtimeSessionController> createRealtimeSessionWebSocket(
      {required RealtimeModel model,
      List<Modality> modalities = const [Modality.audio, Modality.text],
      String? instructions,
      SpeechVoice? voice,
      AudioFormat inputAudioFormat = AudioFormat.pcm16,
      AudioFormat outputAudioFormat = AudioFormat.pcm16,
      InputAudioTranscription? inputAudioTranscription,
      NoiseReduction? inputAudioNoiseReduction,
      TurnDetection? turnDetection,
      ToolChoice? toolChoice,
      num? temperature,
      int? maxResponseOutputTokens,
      num? speed,
      Tracing? tracing, // "auto", Map<String,dynamic>, or null
      // ── Client-secret options ───────────────────────────────────────────
      String? clientSecretAnchor, // created_at
      int? clientSecretSeconds, // 10 – 7200
      List<RealtimeFunctionToolHandler>? initialTools}) async {
    final session = await createRealtimeSession(
        model: model,
        modalities: modalities,
        instructions: instructions,
        voice: voice,
        inputAudioFormat: inputAudioFormat,
        outputAudioFormat: outputAudioFormat,
        inputAudioTranscription: inputAudioTranscription,
        inputAudioNoiseReduction: inputAudioNoiseReduction,
        turnDetection: turnDetection,
        toolChoice: toolChoice,
        temperature: temperature,
        maxResponseOutputTokens: maxResponseOutputTokens,
        speed: speed,
        tracing: tracing,
        clientSecretAnchor: clientSecretAnchor,
        clientSecretSeconds: clientSecretSeconds,
        tools: [...(initialTools?.map((e) => e.metadata) ?? [])]);

    final url = baseUrl.resolve("realtime").replace(scheme: baseUrl.scheme.replaceFirst("http", "ws"));

    final headers = getHeaders({
      "OpenAI-Beta": "realtime=v1",
    });

    headers!["Authorization"] = "Bearer " + session.clientSecret!.value;

    final ws = await WebSocket.connect("$url?model=${model.toJson()}", headers: headers);

    return WebsocketRealtimeSessionController(webSocket: ws, initialTools: initialTools);
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
      print(event);
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
