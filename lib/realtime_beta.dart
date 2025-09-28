import 'dart:async';
import 'dart:convert';

import 'package:openai_core/common.dart';

import 'openai_client.dart';

import 'realtime.dart';

import 'audio.dart';
import 'exceptions.dart';
import 'responses.dart';

extension BetaRealtimeAPI on OpenAIClient {
  Future<String> getRealtimeSDP({required RealtimeModel model, required String sdp, required String ephemeralKey}) async {
    final sdpResponse = await postText(
      "/realtime?model=${model.toJson()}",
      sdp,
      headers: {"Content-Type": "application/sdp"},
    );

    return sdpResponse.body;
  }

  /* Create /realtime/sessions */
  Future<BetaRealtimeSession> createRealtimeSession({
    // ── Core params ──────────────────────────────────────────────────────
    RealtimeModel? model,
    List<Modality> modalities = const [Modality.audio, Modality.text],
    String? instructions,
    SpeechVoice? voice,
    BetaAudioFormat inputAudioFormat = BetaAudioFormat.pcm16,
    BetaAudioFormat outputAudioFormat = BetaAudioFormat.pcm16,
    InputAudioTranscription? inputAudioTranscription,
    NoiseReduction? inputAudioNoiseReduction,
    TurnDetection? turnDetection,
    List<RealtimeFunctionTool>? tools,
    ToolChoice? toolChoice,
    num? temperature,
    int? maxResponseOutputTokens,
    num? speed,
    Tracing? tracing, // "auto", Map<String,dynamic>, or null
    // ── Client-secret options ───────────────────────────────────────────
    String? clientSecretAnchor, // created_at
    int? clientSecretSeconds, // 10 – 7200
  }) async {
    Map<String, dynamic> payload = {
      if (model != null) 'model': model.toJson(),
      'modalities': modalities.map((m) => m.toJson()).toList(),
      if (instructions != null) 'instructions': instructions,
      if (voice != null) 'voice': voice.toJson(),
      if (inputAudioFormat != BetaAudioFormat.pcm16) 'input_audio_format': inputAudioFormat.toJson(),
      if (outputAudioFormat != BetaAudioFormat.pcm16) 'output_audio_format': outputAudioFormat.toJson(),
      if (inputAudioTranscription != null) 'input_audio_transcription': inputAudioTranscription.toJson(),
      if (inputAudioNoiseReduction != null) 'input_audio_noise_reduction': inputAudioNoiseReduction.toJson(),
      if (turnDetection != null) 'turn_detection': turnDetection.toJson(),
      if (tools != null) 'tools': tools.map((t) => t.toJson()).toList(),
      if (toolChoice != null) 'tool_choice': toolChoice.toJson(),
      if (temperature != null) 'temperature': temperature,
      if (maxResponseOutputTokens != null) 'max_response_output_tokens': maxResponseOutputTokens,
      if (speed != null) 'speed': speed,
      if (tracing != null) 'tracing': tracing.toJson(),
      // client_secret nested block
      if (clientSecretAnchor != null || clientSecretSeconds != null)
        'client_secret': {
          if (clientSecretAnchor != null || clientSecretSeconds != null)
            'expires_after': {
              if (clientSecretAnchor != null) 'anchor': clientSecretAnchor,
              if (clientSecretSeconds != null) 'seconds': clientSecretSeconds,
            },
        },
    };

    final res = await postJson('/realtime/sessions', payload);
    if (res.statusCode == 200) {
      return BetaRealtimeSession.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

/* Create /realtime/transcription_sessions */
  Future<RealtimeTranscriptionSession> createRealtimeTranscriptionSession({
    //List<Modality> modalities = const [Modality.audio, Modality.text],
    BetaAudioFormat inputAudioFormat = BetaAudioFormat.pcm16,
    InputAudioTranscription? inputAudioTranscription,
    NoiseReduction? inputAudioNoiseReduction,
    TurnDetection? turnDetection,
    List<String>? include,
    // client-secret
    String? clientSecretAnchor,
    int? clientSecretSeconds,
  }) async {
    final payload = {
      //'modalities': modalities.map((m) => m.toJson()).toList(),
      if (inputAudioFormat != BetaAudioFormat.pcm16) 'input_audio_format': inputAudioFormat.toJson(),
      if (inputAudioTranscription != null) 'input_audio_transcription': inputAudioTranscription.toJson(),
      if (inputAudioNoiseReduction != null) 'input_audio_noise_reduction': inputAudioNoiseReduction.toJson(),
      if (turnDetection != null) 'turn_detection': turnDetection.toJson(),
      if (include != null) 'include': include,
      if (clientSecretAnchor != null || clientSecretSeconds != null)
        'client_secret': {
          'expires_after': {
            if (clientSecretAnchor != null) 'anchor': clientSecretAnchor,
            if (clientSecretSeconds != null) 'seconds': clientSecretSeconds,
          }
        },
    };

    final res = await postJson('/realtime/transcription_sessions', payload);
    if (res.statusCode == 200) {
      return RealtimeTranscriptionSession.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }
}

/// Transcription-only realtime session.
class RealtimeTranscriptionSession extends BetaRealtimeSession {
  RealtimeTranscriptionSession({
    required super.id,
    //required super.modalities,
    super.inputAudioFormat,
    super.inputAudioTranscription,
    super.turnDetection,
    super.clientSecret,
  }) : super(object: "realtime.transcription_session");

  factory RealtimeTranscriptionSession.fromJson(Map<String, dynamic> j) => RealtimeTranscriptionSession(
        id: j['id'],
        //modalities: (j['modalities'] as List).map((m) => Modality.fromJson(m)).toList(),
        inputAudioFormat: j['input_audio_format'] == null ? null : BetaAudioFormat.fromJson(j['input_audio_format']),
        inputAudioTranscription:
            j['input_audio_transcription'] == null ? null : InputAudioTranscription.fromJson(j['input_audio_transcription']),
        turnDetection: TurnDetection.fromJson(j['turn_detection']),
        clientSecret: j['client_secret'] == null ? null : ClientSecret.fromJson(j['client_secret']),
      );
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “transcription_session.updated” – server → client                        */
/* ────────────────────────────────────────────────────────────────────────── */

class TranscriptionSessionUpdatedEvent extends RealtimeEvent {
  TranscriptionSessionUpdatedEvent({
    required this.eventId,
    required this.session,
  }) : super('transcription_session.updated');

  factory TranscriptionSessionUpdatedEvent.fromJson(Map<String, dynamic> j) => TranscriptionSessionUpdatedEvent(
        eventId: j['event_id'] as String,
        session: RealtimeTranscriptionSession.fromJson(j['session'] as Map<String, dynamic>),
      );

  final String eventId;
  final RealtimeTranscriptionSession session;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'session': session.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “transcription_session.update” – client → server                         */
/* ────────────────────────────────────────────────────────────────────────── */

/// Update a *transcription-only* realtime session.
///
/// The server replies with **`transcription_session.updated`** containing the
/// full, effective configuration.
class TranscriptionSessionUpdateEvent extends RealtimeEvent {
  TranscriptionSessionUpdateEvent({
    this.eventId,
    required this.session,
  }) : super('transcription_session.update');

  /* ---------- factory (JSON → object) ---------- */
  factory TranscriptionSessionUpdateEvent.fromJson(Map<String, dynamic> j) => TranscriptionSessionUpdateEvent(
        eventId: j['event_id'],
        session: RealtimeTranscriptionSession.fromJson(
          j['session'] as Map<String, dynamic>,
        ),
      );

  /* ---------- data ---------- */
  final String? eventId; // optional client correlation ID
  final RealtimeTranscriptionSession session; // new config to apply

  /* ---------- object → JSON ---------- */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "transcription_session.update"
        if (eventId != null) 'event_id': eventId,
        'session': session.toJson(),
      };
}

class BetaAudioFormat extends JsonEnum {
  static const pcm16 = BetaAudioFormat('pcm16');
  static const g711Ulaw = BetaAudioFormat('g711_ulaw');
  static const g711Alaw = BetaAudioFormat('g711_alaw');

  const BetaAudioFormat(super.value);
  static BetaAudioFormat fromJson(String raw) => BetaAudioFormat(raw);
}

/// Full assistant session (speech + text etc.)
class BetaRealtimeSession extends BaseRealtimeSession {
  BetaRealtimeSession({
    required super.id,
    super.model,
    this.modalities,
    super.instructions,
    this.voice,
    this.inputAudioFormat,
    this.outputAudioFormat,
    this.inputAudioTranscription,
    this.turnDetection,
    super.tools,
    super.toolChoice,
    super.temperature,
    this.maxResponseOutputTokens,
    this.speed,
    super.tracing,
    this.clientSecret,
    super.object = 'realtime.session',
  });

  final dynamic maxResponseOutputTokens;
  final List<Modality>? modalities;
  final num? speed;
  final ClientSecret? clientSecret;

  final SpeechVoice? voice;
  final BetaAudioFormat? inputAudioFormat;
  final BetaAudioFormat? outputAudioFormat;
  final InputAudioTranscription? inputAudioTranscription;
  final TurnDetection? turnDetection;

  BetaRealtimeSession copyWith(
      {String? id,
      String? object,
      List<Modality>? modalities,
      RealtimeModel? model,
      String? instructions,
      SpeechVoice? voice,
      BetaAudioFormat? inputAudioFormat,
      BetaAudioFormat? outputAudioFormat,
      InputAudioTranscription? inputAudioTranscription,
      TurnDetection? turnDetection,
      List<RealtimeFunctionTool>? tools,
      ToolChoice? toolChoice,
      num? temperature,
      num? speed,
      dynamic maxResponseOutputTokens,
      Tracing? tracing,
      ClientSecret? clientSecret}) {
    return BetaRealtimeSession(
      id: id ?? this.id,
      modalities: modalities ?? this.modalities,
      instructions: instructions ?? this.instructions,
      voice: voice ?? this.voice,
      inputAudioFormat: inputAudioFormat ?? this.inputAudioFormat,
      outputAudioFormat: outputAudioFormat ?? this.outputAudioFormat,
      inputAudioTranscription: inputAudioTranscription ?? this.inputAudioTranscription,
      turnDetection: turnDetection ?? this.turnDetection,
      tools: tools ?? this.tools,
      toolChoice: toolChoice ?? this.toolChoice,
      temperature: temperature ?? this.temperature,
      maxResponseOutputTokens: maxResponseOutputTokens ?? this.maxResponseOutputTokens,
      speed: speed ?? this.speed,
      tracing: tracing ?? this.tracing,
      clientSecret: clientSecret ?? this.clientSecret,
    );
  }

  factory BetaRealtimeSession.fromJson(Map<String, dynamic> j) => BetaRealtimeSession(
        id: j['id'],
        model: RealtimeModel.fromJson(j['model']),
        modalities: (j['modalities'] as List).map((m) => Modality.fromJson(m)).toList(),
        instructions: j['instructions'],
        voice: j['voice'] == null ? null : SpeechVoice.fromJson(j['voice']),
        inputAudioFormat: j['input_audio_format'] == null ? null : BetaAudioFormat.fromJson(j['input_audio_format']),
        outputAudioFormat: j['output_audio_format'] == null ? null : BetaAudioFormat.fromJson(j['output_audio_format']),
        inputAudioTranscription:
            j['input_audio_transcription'] == null ? null : InputAudioTranscription.fromJson(j['input_audio_transcription']),
        turnDetection: TurnDetection.fromJson(j['turn_detection']),
        tools: (j['tools'] as List).cast<Map<String, dynamic>>().map(RealtimeFunctionTool.fromJson).toList(),
        toolChoice: j['tool_choice'] == null ? null : ToolChoice.fromJson(j['tool_choice']),
        temperature: (j['temperature'] as num?)?.toDouble(),
        maxResponseOutputTokens: j['max_response_output_tokens'],
        speed: (j['speed'] as num?)?.toDouble(),
        tracing: j['tracing'] == null ? null : Tracing.fromJson(j['tracing']),
        clientSecret: j['client_secret'] == null ? null : ClientSecret.fromJson(j['client_secret']),
      );

  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (voice != null) 'voice': voice!.toJson(),
        if (inputAudioFormat != null) 'input_audio_format': inputAudioFormat!.toJson(),
        if (outputAudioFormat != null) 'output_audio_format': outputAudioFormat!.toJson(),
        if (inputAudioTranscription != null) 'input_audio_transcription': inputAudioTranscription!.toJson(),
        if (turnDetection != null) 'turn_detection': turnDetection == null ? null : turnDetection!.toJson(),
        "modalities": modalities?.map((e) => e.toJson()).toList()
      };
}

/// Full assistant session (speech + text etc.)
class BetaRealtimeSessionUpdate {
  BetaRealtimeSessionUpdate(
      {this.model,
      this.modalities,
      this.instructions,
      this.voice,
      this.inputAudioFormat,
      this.outputAudioFormat,
      this.inputAudioTranscription,
      this.turnDetection,
      this.tools,
      this.toolChoice,
      this.temperature,
      this.maxResponseOutputTokens,
      this.speed,
      this.tracing,
      this.clientSecret,
      this.type});

  final String? type;

  final List<Modality>? modalities;

  final RealtimeModel? model;

  final String? instructions;
  final SpeechVoice? voice;
  final AudioFormat? inputAudioFormat;
  final AudioFormat? outputAudioFormat;
  final InputAudioTranscription? inputAudioTranscription;
  final TurnDetection? turnDetection;
  final List<RealtimeFunctionTool>? tools;
  final ToolChoice? toolChoice;
  final num? temperature, speed;
  final dynamic maxResponseOutputTokens;
  final Tracing? tracing;
  final ClientSecret? clientSecret;

  factory BetaRealtimeSessionUpdate.fromJson(Map<String, dynamic> j) => BetaRealtimeSessionUpdate(
        model: RealtimeModel.fromJson(j['model']),
        modalities: (j['modalities'] as List).map((m) => Modality.fromJson(m)).toList(),
        instructions: j['instructions'],
        voice: j['voice'] == null ? null : SpeechVoice.fromJson(j['voice']),
        inputAudioFormat: j['input_audio_format'] == null ? null : AudioFormat.fromJson(j['input_audio_format']),
        outputAudioFormat: j['output_audio_format'] == null ? null : AudioFormat.fromJson(j['output_audio_format']),
        inputAudioTranscription:
            j['input_audio_transcription'] == null ? null : InputAudioTranscription.fromJson(j['input_audio_transcription']),
        turnDetection: TurnDetection.fromJson(j['turn_detection']),
        tools: (j['tools'] as List).cast<Map<String, dynamic>>().map(RealtimeFunctionTool.fromJson).toList(),
        toolChoice: j['tool_choice'] == null ? null : ToolChoice.fromJson(j['tool_choice']),
        temperature: (j['temperature'] as num?)?.toDouble(),
        maxResponseOutputTokens: j['max_response_output_tokens'],
        speed: (j['speed'] as num?)?.toDouble(),
        tracing: j['tracing'] == null ? null : Tracing.fromJson(j['tracing']),
        clientSecret: j['client_secret'] == null ? null : ClientSecret.fromJson(j['client_secret']),
      );

  Map<String, dynamic> toJson() => {
        if (modalities != null) "modalities": modalities!.map((e) => e.toJson()).toList(),
        if (model != null) 'model': model?.toJson(),
        if (instructions != null) 'instructions': instructions,
        if (voice != null) 'voice': voice!.toJson(),
        if (inputAudioFormat != null) 'input_audio_format': inputAudioFormat!.toJson(),
        if (outputAudioFormat != null) 'output_audio_format': outputAudioFormat!.toJson(),
        if (inputAudioTranscription != null) 'input_audio_transcription': inputAudioTranscription!.toJson(),
        if (turnDetection != null) 'turn_detection': turnDetection == null ? null : turnDetection!.toJson(),
        if (tools != null) 'tools': tools!.map((t) => t.toJson()).toList(),
        if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
        if (temperature != null) 'temperature': temperature,
        if (maxResponseOutputTokens != null) 'max_response_output_tokens': maxResponseOutputTokens,
        if (speed != null) 'speed': speed,
        if (tracing != null) 'tracing': tracing?.toJson(),
        if (clientSecret != null) 'client_secret': clientSecret!.toJson(),
      };
}

/// Client → server event that *requests* the update.
class BetaSessionUpdateEvent extends RealtimeEvent {
  BetaSessionUpdateEvent({
    this.eventId,
    required this.session,
  }) : super('session.update');

  factory BetaSessionUpdateEvent.fromJson(Map<String, dynamic> j) => BetaSessionUpdateEvent(
        eventId: j['event_id'],
        session: BetaRealtimeSessionUpdate.fromJson(j['session'] as Map<String, dynamic>),
      );

  final String? eventId; // optional client-generated correlation ID
  final BetaRealtimeSessionUpdate session;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (eventId != null) 'event_id': eventId,
        'session': session.toJson(),
      };
}

class BetaSessionUpdatedEvent extends RealtimeEvent {
  BetaSessionUpdatedEvent({
    this.eventId,
    required this.session,
  }) : super('session.updated');

  factory BetaSessionUpdatedEvent.fromJson(Map<String, dynamic> j) => BetaSessionUpdatedEvent(
        eventId: j['event_id'],
        session: BetaRealtimeSession.fromJson(j['session'] as Map<String, dynamic>),
      );

  final String? eventId; // optional client-generated correlation ID
  final BetaRealtimeSession session;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (eventId != null) 'event_id': eventId,
        'session': session.toJson(),
      };
}

class BetaSessionCreatedEvent extends RealtimeEvent {
  BetaSessionCreatedEvent({
    this.eventId,
    required this.session,
  }) : super('session.created');

  factory BetaSessionCreatedEvent.fromJson(Map<String, dynamic> j) => BetaSessionCreatedEvent(
        eventId: j['event_id'],
        session: BetaRealtimeSession.fromJson(j['session'] as Map<String, dynamic>),
      );

  final String? eventId; // optional client-generated correlation ID
  final BetaRealtimeSession session;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (eventId != null) 'event_id': eventId,
        'session': session.toJson(),
      };
}

final betaEventOverrides = {
  'session.update': (Map<String, dynamic> j) => BetaSessionUpdateEvent.fromJson(j),
  'session.updated': (Map<String, dynamic> j) => BetaSessionUpdatedEvent.fromJson(j),
  'session.created': (Map<String, dynamic> j) => BetaSessionCreatedEvent.fromJson(j),
  'transcription_session.update': (Map<String, dynamic> j) => TranscriptionSessionUpdateEvent.fromJson(j),
};
