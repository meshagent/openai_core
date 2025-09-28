import 'dart:io';

import 'realtime_beta.dart';
import 'realtime_io.dart';

import 'audio.dart';
import 'openai_client.dart';
import 'realtime.dart';
import 'realtime_session_controller.dart';
import 'responses.dart';

extension RealtimeIO on OpenAIClient {
  Future<WebsocketRealtimeSessionController> createRealtimeSessionWebSocket(
      {required RealtimeModel model,
      List<Modality> modalities = const [Modality.audio, Modality.text],
      String? instructions,
      SpeechVoice? voice,
      BetaAudioFormat inputAudioFormat = BetaAudioFormat.pcm16,
      BetaAudioFormat outputAudioFormat = BetaAudioFormat.pcm16,
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
