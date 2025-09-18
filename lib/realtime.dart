// ──────────────────────────────────────────────────────────────────────────
//  Realtime session helpers (/realtime/sessions & /realtime/transcription…)
// ──────────────────────────────────────────────────────────────────────────

// ── Small enums / value types ─────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';

import 'audio.dart';
import 'common.dart';
import 'exceptions.dart';
import 'openai_client.dart';
import 'responses.dart';

enum AudioFormat with JsonEnum {
  pcm16('pcm16'),
  g711Ulaw('g711_ulaw'),
  g711Alaw('g711_alaw');

  const AudioFormat(this.value);
  final String value;
  static AudioFormat fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

enum NoiseReductionType with JsonEnum {
  nearField('near_field'),
  farField('far_field');

  const NoiseReductionType(this.value);
  final String value;
  static NoiseReductionType fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

enum TurnDetectionType with JsonEnum {
  serverVad('server_vad'),
  semanticVad('semantic_vad');

  const TurnDetectionType(this.value);
  final String value;
  static TurnDetectionType fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

enum Eagerness with JsonEnum {
  low('low'),
  medium('medium'),
  high('high'),
  auto_('auto');

  const Eagerness(this.value);
  final String value;
  static Eagerness fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

enum Modality with JsonEnum {
  audio('audio'),
  text('text');

  const Modality(this.value);
  final String value;
  static Modality fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

// ── VO object wrappers ───────────────────────────────────────────────────
class ClientSecret {
  const ClientSecret({required this.value, required this.expiresAt});
  factory ClientSecret.fromJson(Map<String, dynamic> j) => ClientSecret(value: j['value'], expiresAt: j['expires_at']);
  final String value; // "ek_abc123"
  final int expiresAt; // epoch-seconds
  Map<String, dynamic> toJson() => {'value': value, 'expires_at': expiresAt};
}

class NoiseReduction {
  const NoiseReduction({required this.type});
  factory NoiseReduction.fromJson(Map<String, dynamic> j) => NoiseReduction(type: NoiseReductionType.fromJson(j['type']));
  final NoiseReductionType type;
  Map<String, dynamic> toJson() => {'type': type.toJson()};
}

class InputAudioTranscription {
  const InputAudioTranscription({this.model, this.language, this.prompt});
  factory InputAudioTranscription.fromJson(Map<String, dynamic> j) => InputAudioTranscription(
        model: AudioModel.fromJson(j['model']),
        language: j['language'],
        prompt: j['prompt'],
      );
  final AudioModel? model, language, prompt;
  Map<String, dynamic> toJson() => {'model': model, 'language': language, 'prompt': prompt}..removeWhere((k, v) => v == null);
}

class TurnDetection {
  const TurnDetection({
    required this.type,
    this.threshold,
    this.prefixPaddingMs,
    this.silenceDurationMs,
    this.eagerness,
    this.createResponse,
    this.interruptResponse,
  });

  factory TurnDetection.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const TurnDetection(type: TurnDetectionType.serverVad);
    return TurnDetection(
      type: TurnDetectionType.fromJson(j['type']),
      threshold: (j['threshold'] as num?)?.toDouble(),
      prefixPaddingMs: j['prefix_padding_ms'],
      silenceDurationMs: j['silence_duration_ms'],
      eagerness: j['eagerness'] == null ? null : Eagerness.fromJson(j['eagerness']),
      createResponse: j['create_response'],
      interruptResponse: j['interrupt_response'],
    );
  }

  final TurnDetectionType type;
  final double? threshold;
  final int? prefixPaddingMs, silenceDurationMs;
  final Eagerness? eagerness;
  final bool? createResponse, interruptResponse;

  Map<String, dynamic> toJson() => {
        'type': type.toJson(),
        if (threshold != null) 'threshold': threshold,
        if (prefixPaddingMs != null) 'prefix_padding_ms': prefixPaddingMs,
        if (silenceDurationMs != null) 'silence_duration_ms': silenceDurationMs,
        if (eagerness != null) 'eagerness': eagerness!.toJson(),
        if (createResponse != null) 'create_response': createResponse,
        if (interruptResponse != null) 'interrupt_response': interruptResponse,
      };
}

// ── Session base & concrete shapes ───────────────────────────────────────
abstract class BaseRealtimeSession {
  const BaseRealtimeSession({
    required this.id,
    required this.object,
    this.model,
    this.instructions,
    this.voice,
    this.inputAudioFormat,
    this.outputAudioFormat,
    this.inputAudioTranscription,
    this.turnDetection,
    this.tools = const [],
    this.toolChoice,
    this.temperature,
    this.maxResponseOutputTokens,
    this.speed,
    this.tracing,
    this.clientSecret,
  });

  factory BaseRealtimeSession.fromJson(Map<String, dynamic> j) {
    switch (j['object']) {
      case 'realtime.session':
        return RealtimeSession.fromJson(j);
      case 'realtime.transcription_session':
        return RealtimeTranscriptionSession.fromJson(j);
      default:
        throw ArgumentError('Unknown session object ${j['object']}');
    }
  }

  final String id;
  final String object; // realtime.session | realtime.transcription_session
  final RealtimeModel? model;

  final String? instructions;
  final SpeechVoice? voice;
  final AudioFormat? inputAudioFormat;
  final AudioFormat? outputAudioFormat;
  final InputAudioTranscription? inputAudioTranscription;
  final TurnDetection? turnDetection;
  final List<RealtimeFunctionTool> tools;
  final ToolChoice? toolChoice;
  final num? temperature, speed;
  final dynamic maxResponseOutputTokens;
  final Tracing? tracing;
  final ClientSecret? clientSecret;

  Map<String, dynamic> _common() => {
        'id': id,
        'object': object,
        if (model != null) 'model': model?.toJson(),
        if (instructions != null) 'instructions': instructions,
        if (voice != null) 'voice': voice!.toJson(),
        if (inputAudioFormat != null) 'input_audio_format': inputAudioFormat!.toJson(),
        if (outputAudioFormat != null) 'output_audio_format': outputAudioFormat!.toJson(),
        if (inputAudioTranscription != null) 'input_audio_transcription': inputAudioTranscription!.toJson(),
        if (turnDetection != null) 'turn_detection': turnDetection == null ? null : turnDetection!.toJson(),
        'tools': tools.map((t) => t.toJson()).toList(),
        if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
        if (temperature != null) 'temperature': temperature,
        if (maxResponseOutputTokens != null) 'max_response_output_tokens': maxResponseOutputTokens,
        if (speed != null) 'speed': speed,
        if (tracing != null) 'tracing': tracing?.toJson(),
        if (clientSecret != null) 'client_secret': clientSecret!.toJson(),
      };
}

/// Full assistant session (speech + text etc.)
class RealtimeSession extends BaseRealtimeSession {
  RealtimeSession({
    required super.id,
    super.model,
    required this.modalities,
    super.instructions,
    super.voice,
    super.inputAudioFormat,
    super.outputAudioFormat,
    super.inputAudioTranscription,
    super.turnDetection,
    super.tools,
    super.toolChoice,
    super.temperature,
    super.maxResponseOutputTokens,
    super.speed,
    super.tracing,
    super.clientSecret,
  }) : super(object: 'realtime.session');

  final List<Modality> modalities;

  RealtimeSession copyWith(
      {String? id,
      String? object,
      List<Modality>? modalities,
      RealtimeModel? model,
      String? instructions,
      SpeechVoice? voice,
      AudioFormat? inputAudioFormat,
      AudioFormat? outputAudioFormat,
      InputAudioTranscription? inputAudioTranscription,
      TurnDetection? turnDetection,
      List<RealtimeFunctionTool>? tools,
      ToolChoice? toolChoice,
      num? temperature,
      num? speed,
      dynamic maxResponseOutputTokens,
      Tracing? tracing,
      ClientSecret? clientSecret}) {
    return RealtimeSession(
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

  factory RealtimeSession.fromJson(Map<String, dynamic> j) => RealtimeSession(
        id: j['id'],
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

  Map<String, dynamic> toJson() => {..._common(), "modalities": modalities.map((e) => e.toJson()).toList()};
}

/// Full assistant session (speech + text etc.)
class RealtimeSessionUpdate {
  RealtimeSessionUpdate({
    this.model,
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
  });

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

  factory RealtimeSessionUpdate.fromJson(Map<String, dynamic> j) => RealtimeSessionUpdate(
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

/// Transcription-only realtime session.
class RealtimeTranscriptionSession extends BaseRealtimeSession {
  RealtimeTranscriptionSession({
    required super.id,
    //required super.modalities,
    super.inputAudioFormat,
    super.inputAudioTranscription,
    super.turnDetection,
    super.clientSecret,
  }) : super(object: 'realtime.transcription_session');

  factory RealtimeTranscriptionSession.fromJson(Map<String, dynamic> j) => RealtimeTranscriptionSession(
        id: j['id'],
        //modalities: (j['modalities'] as List).map((m) => Modality.fromJson(m)).toList(),
        inputAudioFormat: j['input_audio_format'] == null ? null : AudioFormat.fromJson(j['input_audio_format']),
        inputAudioTranscription:
            j['input_audio_transcription'] == null ? null : InputAudioTranscription.fromJson(j['input_audio_transcription']),
        turnDetection: TurnDetection.fromJson(j['turn_detection']),
        clientSecret: j['client_secret'] == null ? null : ClientSecret.fromJson(j['client_secret']),
      );

  Map<String, dynamic> toJson() => _common();
}

/// Realtime-capable, low-latency models (WebSocket / /realtime/* APIs).
enum RealtimeModel with JsonEnum {
  /// Public preview model (speech + text).
  gpt4oRealtimePreview('gpt-4o-realtime-preview'),

  gpt4oRealtimePreview_2025_06_03("gpt-4o-realtime-preview-2025-06-03"),

  /// Same architecture, but text-only and slightly cheaper.
  gpt4oRealtimeMiniPreview('gpt-4o-realtime-mini-preview');

  const RealtimeModel(this.value);
  final String value;

  /// Parses the wire value or throws if it’s an unknown model string.
  static RealtimeModel fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

// ── Extensions on OpenAIClient ────────────────────────────────────────────
extension RealtimeAPI on OpenAIClient {
  Future<String> getRealtimeSDP({required RealtimeModel model, required String sdp, required String ephemeralKey}) async {
    final sdpResponse = await postText(
      "/realtime?model=${model.toJson()}",
      sdp,
      headers: {"Content-Type": "application/sdp"},
    );

    return sdpResponse.body;
  }

  /* Create /realtime/sessions */
  Future<RealtimeSession> createRealtimeSession({
    // ── Core params ──────────────────────────────────────────────────────
    RealtimeModel? model,
    List<Modality> modalities = const [Modality.audio, Modality.text],
    String? instructions,
    SpeechVoice? voice,
    AudioFormat inputAudioFormat = AudioFormat.pcm16,
    AudioFormat outputAudioFormat = AudioFormat.pcm16,
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
      if (inputAudioFormat != AudioFormat.pcm16) 'input_audio_format': inputAudioFormat.toJson(),
      if (outputAudioFormat != AudioFormat.pcm16) 'output_audio_format': outputAudioFormat.toJson(),
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
      return RealtimeSession.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /* Create /realtime/transcription_sessions */
  Future<RealtimeTranscriptionSession> createRealtimeTranscriptionSession({
    //List<Modality> modalities = const [Modality.audio, Modality.text],
    AudioFormat inputAudioFormat = AudioFormat.pcm16,
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
      if (inputAudioFormat != AudioFormat.pcm16) 'input_audio_format': inputAudioFormat.toJson(),
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

/// — function_tool
class RealtimeFunctionTool {
  RealtimeFunctionTool({
    required this.name,
    required this.parameters,
    this.description,
  });

  final String name;
  final Map<String, dynamic> parameters;
  final String? description;

  factory RealtimeFunctionTool.fromJson(Map<String, dynamic> json) {
    return RealtimeFunctionTool(
      name: json['name'] as String,
      parameters: Map<String, dynamic>.from(json['parameters'] as Map),
      description: json['description'] as String?,
    );
  }
  Map<String, dynamic> toJson() => {
        'type': 'function',
        'name': name,
        'parameters': parameters,
        if (description != null) 'description': description,
      };
}

abstract class Tracing {
  const Tracing();

  /// Serialise back to the wire-shape (`"auto"` or an object).
  dynamic toJson();

  /// Parse whatever the server returned (`null`, `"auto"` or `{…}`).
  factory Tracing.fromJson(dynamic raw) {
    if (raw == null) return const TracingDisabled();
    if (raw is String && raw == 'auto') return const TracingAuto();
    if (raw is Map<String, dynamic>) {
      return TracingDetailed(
        workflowName: raw['workflow_name'],
        groupId: raw['group_id'],
        metadata: raw['metadata']?.cast<String, dynamic>(),
      );
    }
    throw ArgumentError('Unexpected tracing value: $raw');
  }
}

/// Explicitly disabled.
class TracingDisabled extends Tracing {
  const TracingDisabled();
  @override
  dynamic toJson() => null;
}

/// Simple “use defaults” mode (`"auto"`).
class TracingAuto extends Tracing {
  const TracingAuto();
  @override
  String toJson() => 'auto';
}

/// Fully-specified config object.
class TracingDetailed extends Tracing {
  const TracingDetailed({
    this.workflowName,
    this.groupId,
    this.metadata,
  });

  final String? workflowName; // tracing.workflow_name
  final String? groupId; // tracing.group_id
  final Map<String, dynamic>? metadata; // tracing.metadata

  @override
  Map<String, dynamic> toJson() => {
        if (workflowName != null) 'workflow_name': workflowName,
        if (groupId != null) 'group_id': groupId,
        if (metadata != null) 'metadata': metadata,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Realtime “session.update” event                                          */
/* ────────────────────────────────────────────────────────────────────────── */

/// Base for every inbound / outbound realtime event.
/// (You said this already exists – keeping a stub for context.)
abstract class RealtimeEvent {
  const RealtimeEvent(this.type);
  final String type;

  Map<String, dynamic> toJson();

  /// Parse an arbitrary WebSocket JSON payload into the specific `RealtimeEvent`
  /// implementation for that `type`. Throws if the `type` is missing or unknown.
  static RealtimeEvent fromJson(Map<String, dynamic> j) {
    final String type = j['type'] as String? ?? (throw ArgumentError('RealtimeEvent JSON is missing a "type" field'));

    switch (type) {
      /* ── client → server ─────────────────────────────────────────────── */
      case 'session.update':
        return SessionUpdateEvent.fromJson(j);
      case 'input_audio_buffer.append':
        return InputAudioBufferAppendEvent.fromJson(j);
      case 'input_audio_buffer.commit':
        return InputAudioBufferCommitEvent.fromJson(j);
      case 'input_audio_buffer.clear':
        return InputAudioBufferClearEvent.fromJson(j);
      case 'conversation.item.create':
        return RealtimeConversationItemCreateEvent.fromJson(j);
      case 'conversation.item.retrieve':
        return RealtimeConversationItemRetrieveEvent.fromJson(j);
      case 'conversation.item.truncate':
        return RealtimeConversationItemTruncateEvent.fromJson(j);
      case 'conversation.item.delete':
        return RealtimeConversationItemDeleteEvent.fromJson(j);
      case 'response.create':
        return RealtimeResponseCreateEvent.fromJson(j);
      case 'transcription_session.update':
        return TranscriptionSessionUpdateEvent.fromJson(j);
      case 'output_audio_buffer.clear':
        return OutputAudioBufferClearEvent.fromJson(j);

      /* ── server → client : session-level ─────────────────────────────── */
      case 'session.created':
        return SessionCreatedEvent.fromJson(j);
      case 'session.updated':
        return SessionUpdatedEvent.fromJson(j);
      case 'transcription_session.updated':
        return TranscriptionSessionUpdatedEvent.fromJson(j);
      case 'rate_limits.updated':
        return RateLimitsUpdatedEvent.fromJson(j);

      /* ── server → client : conversation-level ────────────────────────── */
      case 'conversation.created':
        return ConversationCreatedEvent.fromJson(j);
      case 'conversation.item.created':
        return ConversationItemCreatedEvent.fromJson(j);
      case 'conversation.item.retrieved':
        return ConversationItemRetrievedEvent.fromJson(j);
      case 'conversation.item.input_audio_transcription.completed':
        return ConversationItemInputAudioTranscriptionCompletedEvent.fromJson(j);
      case 'conversation.item.input_audio_transcription.delta':
        return ConversationItemInputAudioTranscriptionDeltaEvent.fromJson(j);
      case 'conversation.item.input_audio_transcription.failed':
        return ConversationItemInputAudioTranscriptionFailedEvent.fromJson(j);
      case 'conversation.item.truncated':
        return ConversationItemTruncatedEvent.fromJson(j);
      case 'conversation.item.deleted':
        return ConversationItemDeletedEvent.fromJson(j);

      /* ── server → client : input-audio buffer ────────────────────────── */
      case 'input_audio_buffer.committed':
        return InputAudioBufferCommittedEvent.fromJson(j);
      case 'input_audio_buffer.cleared':
        return InputAudioBufferClearedEvent.fromJson(j);
      case 'input_audio_buffer.speech_started':
        return InputAudioBufferSpeechStartedEvent.fromJson(j);

      /* ── server → client : response-level ────────────────────────────── */

      case 'response.created':
        return RealtimeResponseCreateEvent.fromJson(j);
      case 'response.done':
        return RealtimeResponseDoneEvent.fromJson(j);
      case 'response.cancelled':
        return RealtimeResponseCancelledEvent.fromJson(j);

      case 'response.output_item.added':
        return RealtimeResponseOutputItemAddedEvent.fromJson(j);
      case 'response.output_item.done':
        return RealtimeResponseOutputItemDoneEvent.fromJson(j);

      case 'response.content_part.added':
        return RealtimeResponseContentPartAddedEvent.fromJson(j);
      case 'response.content_part.done':
        return RealtimeResponseContentPartDoneEvent.fromJson(j);

      case 'response.text.delta':
        return RealtimeResponseTextDeltaEvent.fromJson(j);
      case 'response.text.done':
        return RealtimeResponseTextDoneEvent.fromJson(j);

      case 'response.audio_transcript.delta':
        return RealtimeResponseAudioTranscriptDeltaEvent.fromJson(j);
      case 'response.audio_transcript.done':
        return RealtimeResponseAudioTranscriptDoneEvent.fromJson(j);

      case 'response.audio.delta':
        return RealtimeResponseAudioDeltaEvent.fromJson(j);
      case 'response.audio.done':
        return RealtimeResponseAudioDoneEvent.fromJson(j);

      case 'response.function_call_arguments.delta':
        return RealtimeResponseFunctionCallArgumentsDeltaEvent.fromJson(j);
      case 'response.function_call_arguments.done':
        return RealtimeResponseFunctionCallArgumentsDoneEvent.fromJson(j);

      /* ── server → client : WebRTC audio-buffer events ────────────────── */
      case 'output_audio_buffer.started':
        return OutputAudioBufferStartedEvent.fromJson(j);
      case 'output_audio_buffer.stopped':
        return OutputAudioBufferStoppedEvent.fromJson(j);
      case 'output_audio_buffer.cleared':
        return OutputAudioBufferClearedEvent.fromJson(j);

      case 'input_audio_buffer.speech_stopped':
        return InputAudioBufferSpeechStoppedEvent.fromJson(j);

      /* ── server → client : generic error ─────────────────────────────── */
      case 'error':
        return ErrorEvent.fromJson(j);

      /* ── unknown / future-proofing ───────────────────────────────────── */
      default:
        throw ArgumentError('Unknown realtime event type "$type"');
    }
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Item-level events: retrieve · truncate · delete                          */
/* ────────────────────────────────────────────────────────────────────────── */

/// Retrieve a single item (server → returns `conversation.item.retrieved`).
class RealtimeConversationItemRetrieveEvent extends RealtimeEvent {
  RealtimeConversationItemRetrieveEvent({
    required this.itemId,
    this.eventId,
  }) : super('conversation.item.retrieve');

  factory RealtimeConversationItemRetrieveEvent.fromJson(Map<String, dynamic> j) => RealtimeConversationItemRetrieveEvent(
        itemId: j['item_id'],
        eventId: j['event_id'],
      );

  final String itemId;
  final String? eventId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "conversation.item.retrieve"
        'item_id': itemId,
        if (eventId != null) 'event_id': eventId,
      };
}

/// Truncate already-sent assistant audio (→ `conversation.item.truncated`).
class RealtimeConversationItemTruncateEvent extends RealtimeEvent {
  RealtimeConversationItemTruncateEvent({
    required this.itemId,
    required this.audioEndMs,
    this.contentIndex = 0,
    this.eventId,
  })  : assert(audioEndMs >= 0),
        super('conversation.item.truncate');

  factory RealtimeConversationItemTruncateEvent.fromJson(Map<String, dynamic> j) => RealtimeConversationItemTruncateEvent(
        itemId: j['item_id'],
        audioEndMs: j['audio_end_ms'],
        contentIndex: j['content_index'] ?? 0,
        eventId: j['event_id'],
      );

  final String itemId;
  final int contentIndex; // always 0 per spec
  final int audioEndMs; // inclusive ms to keep
  final String? eventId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "conversation.item.truncate"
        'item_id': itemId,
        'content_index': contentIndex,
        'audio_end_ms': audioEndMs,
        if (eventId != null) 'event_id': eventId,
      };
}

/// Delete an item from the conversation (→ `conversation.item.deleted`).
class RealtimeConversationItemDeleteEvent extends RealtimeEvent {
  RealtimeConversationItemDeleteEvent({
    required this.itemId,
    this.eventId,
  }) : super('conversation.item.delete');

  factory RealtimeConversationItemDeleteEvent.fromJson(Map<String, dynamic> j) => RealtimeConversationItemDeleteEvent(
        itemId: j['item_id'],
        eventId: j['event_id'],
      );

  final String itemId;
  final String? eventId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "conversation.item.delete"
        'item_id': itemId,
        if (eventId != null) 'event_id': eventId,
      };
}

/// Client → server event that *requests* the update.
class SessionUpdateEvent extends RealtimeEvent {
  SessionUpdateEvent({
    this.eventId,
    required this.session,
  }) : super('session.update');

  factory SessionUpdateEvent.fromJson(Map<String, dynamic> j) => SessionUpdateEvent(
        eventId: j['event_id'],
        session: RealtimeSessionUpdate.fromJson(j['session'] as Map<String, dynamic>),
      );

  final String? eventId; // optional client-generated correlation ID
  final RealtimeSessionUpdate session;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (eventId != null) 'event_id': eventId,
        'session': session.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “input_audio_buffer.append” – client → server                            */
/* ────────────────────────────────────────────────────────────────────────── */

/// Send base-64 audio bytes to the server-side buffer.
///
/// *No confirmation is returned* – the server consumes the data silently.
class InputAudioBufferAppendEvent extends RealtimeEvent {
  InputAudioBufferAppendEvent({
    required this.audioB64,
    this.eventId,
  }) : super('input_audio_buffer.append') {
    _checkSize(audioB64);
  }

  factory InputAudioBufferAppendEvent.fromJson(Map<String, dynamic> j) => InputAudioBufferAppendEvent(
        audioB64: j['audio'] as String,
        eventId: j['event_id'] as String?,
      );

  /// Base-64 encoded audio chunk (≤ 15 MiB once decoded).
  final String audioB64;

  /// Optional client-side correlation ID.
  final String? eventId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "input_audio_buffer.append"
        'audio': audioB64,
        if (eventId != null) 'event_id': eventId,
      };

  /* ───────────── private helpers ───────────── */

  /// RFC 2045: 4 bytes of b64 → 3 bytes of binary.
  /// 15 MiB  = 15 * 1024 * 1024 ≈ 15  * 1 048 576 = 15 728 640 bytes
  /// Encoded size limit  = ceil(15 728 640 / 3) × 4 = 20 971 520 chars
  static const int _maxB64Len = 20971520;

  void _checkSize(String b64) {
    if (b64.length > _maxB64Len) {
      throw ArgumentError(
        'audio payload exceeds 15 MiB limit (base-64 length ${b64.length} > $_maxB64Len)',
      );
    }
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “input_audio_buffer.commit” & “…clear” events                            */
/* ────────────────────────────────────────────────────────────────────────── */

/// Commit the current input-audio buffer.
///
/// *The server replies with* **`input_audio_buffer.committed`**.
class InputAudioBufferCommitEvent extends RealtimeEvent {
  InputAudioBufferCommitEvent({this.eventId}) : super('input_audio_buffer.commit');

  factory InputAudioBufferCommitEvent.fromJson(Map<String, dynamic> j) => InputAudioBufferCommitEvent(eventId: j['event_id']);

  final String? eventId; // optional client-generated correlation ID

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "input_audio_buffer.commit"
        if (eventId != null) 'event_id': eventId,
      };
}

/// Clear (discard) any audio currently in the buffer.
///
/// *The server replies with* **`input_audio_buffer.cleared`**.
class InputAudioBufferClearEvent extends RealtimeEvent {
  InputAudioBufferClearEvent({this.eventId}) : super('input_audio_buffer.clear');

  factory InputAudioBufferClearEvent.fromJson(Map<String, dynamic> j) => InputAudioBufferClearEvent(eventId: j['event_id']);

  final String? eventId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "input_audio_buffer.clear"
        if (eventId != null) 'event_id': eventId,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.item.create” – client → server                             */
/* ────────────────────────────────────────────────────────────────────────── */

/* ── Item content helpers (message bodies) ──────────────────────────────── */

abstract class RealtimeMessageContent {
  const RealtimeMessageContent(this.type);

  final String type; // input_text, input_audio, text, item_reference

  Map<String, dynamic> toJson();

  static RealtimeMessageContent fromJson(Map<String, dynamic> c) {
    switch (c['type']) {
      case 'input_text':
        return RealtimeInputText(c['text']);
      case 'text':
        return RealtimeText(c['text']);
      case 'input_audio':
        return RealtimeInputAudio(
          audioB64: c['audio'],
          transcript: c['transcript'],
        );
      case 'audio':
        return AudioMessageContent(
          audioB64: c['audio'],
          transcript: c['transcript'],
        );
      case 'item_reference':
        return RealtimeItemReferenceMessageContent(c['id']);
      default:
        throw ArgumentError('Unknown content type "${c['type']}"');
    }
  }
}

/* ─── concrete content types ────────────────────────────────────────────── */

class RealtimeInputText extends RealtimeMessageContent {
  RealtimeInputText(this.text) : super('input_text');
  final String text;
  @override
  Map<String, dynamic> toJson() => {'type': type, 'text': text};
}

class RealtimeText extends RealtimeMessageContent {
  RealtimeText(this.text) : super('text');
  final String text;
  @override
  Map<String, dynamic> toJson() => {'type': type, 'text': text};
}

class RealtimeInputAudio extends RealtimeMessageContent {
  RealtimeInputAudio({required this.audioB64, required this.transcript}) : super('input_audio');
  final String? audioB64;
  final String? transcript;
  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'audio': audioB64,
        if (transcript != null) 'transcript': transcript,
      };
}

class RealtimeItemReferenceMessageContent extends RealtimeMessageContent {
  RealtimeItemReferenceMessageContent(this.itemId) : super('item_reference');
  final String itemId;
  @override
  Map<String, dynamic> toJson() => {'type': type, 'id': itemId};
}

/* ── Item models (message / fn-call / fn-output) ────────────────────────── */

abstract class RealtimeConversationItem {
  const RealtimeConversationItem(this.type);

  final String type; // message, function_call, function_call_output

  static RealtimeConversationItem fromJson(Map<String, dynamic> m) {
    /* ---------- local helper – clone of the parser you already use -------- */
    switch (m['type']) {
      case 'message':
        return RealtimeMessageItem(
          id: m['id'],
          role: m['role'],
          status: m['status'] ?? 'completed',
          content: (m['content'] as List)
              .map<RealtimeMessageContent>((m) => RealtimeMessageContent.fromJson(m as Map<String, dynamic>))
              .toList(),
        );
      case 'function_call':
        return RealtimeFunctionCall(
          id: m['id'],
          name: m['name'],
          arguments: m['arguments'],
          callId: m['call_id'],
          status: m['status'] ?? 'in_progress',
        );
      case 'function_call_output':
        return RealtimeFunctionCallOutput(
          id: m['id'],
          callId: m['call_id'],
          output: m['output'],
          status: m['status'] ?? 'completed',
        );
      default:
        throw ArgumentError('Unknown item type "${m['type']}"');
    }
  }

  Map<String, dynamic> toJson();
}

/* ─── concrete item shapes ──────────────────────────────────────────────── */

class RealtimeMessageItem extends RealtimeConversationItem {
  RealtimeMessageItem({
    this.id,
    required this.role,
    required this.content,
    required this.status,
  }) : super('message');

  final String? id;
  final String role;
  final List<RealtimeMessageContent> content;
  final String? status;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (id != null) 'id': id,
        'role': role,
        'content': content.map((c) => c.toJson()).toList(),
        if (status != null) 'status': status,
      };
}

class RealtimeFunctionCall extends RealtimeConversationItem {
  RealtimeFunctionCall({
    this.id,
    required this.name,
    required this.arguments,
    required this.callId,
    required this.status,
  }) : super('function_call');

  final String? id;
  final String name;
  final String arguments;
  final String callId;
  final String status;

  RealtimeFunctionCallOutput output(String output, {String? status}) {
    return RealtimeFunctionCallOutput(callId: callId, output: output, status: status);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (id != null) 'id': id,
        'name': name,
        'arguments': arguments,
        'call_id': callId,
        'status': status,
      };
}

class RealtimeFunctionCallOutput extends RealtimeConversationItem {
  RealtimeFunctionCallOutput({
    this.id,
    required this.callId,
    required this.output,
    required this.status,
  }) : super('function_call_output');

  final String? id;
  final String callId;
  final String output;
  final String? status;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (id != null) 'id': id,
        'call_id': callId,
        'output': output,
        if (status != null) 'status': status,
      };
}

/* ───────────────────────────────────────────────────────────────────────── */

/// Client → server event that inserts a new item into the conversation.
///
/// The server responds with **`conversation.item.created`** (or an error).

class RealtimeConversationItemCreateEvent extends RealtimeEvent {
  RealtimeConversationItemCreateEvent({
    this.eventId,
    required this.item,
    this.previousItemId,
  }) : super('conversation.item.create');

  /* ---------- NEW  factory ------------- */
  factory RealtimeConversationItemCreateEvent.fromJson(Map<String, dynamic> j) => RealtimeConversationItemCreateEvent(
        eventId: j['event_id'],
        previousItemId: j['previous_item_id'],
        item: RealtimeConversationItem.fromJson(j['item'] as Map<String, dynamic>),
      );

  // ── data ───────────────────────────────────────────────────────────────
  final String? eventId;
  final RealtimeConversationItem item;
  final String? previousItemId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (eventId != null) 'event_id': eventId,
        'item': item.toJson(),
        if (previousItemId != null) 'previous_item_id': previousItemId,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.create”  –  trigger model inference                            */
/* ────────────────────────────────────────────────────────────────────────── */

/// Per-request inference parameters (override session defaults **only**
/// for this single response).
class RealtimeResponse {
  RealtimeResponse({
    this.conversation, // "auto" | "none"
    this.input, // custom prompt context
    this.instructions,
    this.maxResponseOutputTokens, // int | "inf"
    this.metadata,
    this.modalities,
    this.outputAudioFormat,
    this.temperature,
    this.toolChoice,
    this.tools,
    this.voice,
  });

  /* ---------- factory fromJson ---------- */
  factory RealtimeResponse.fromJson(Map<String, dynamic> j) => RealtimeResponse(
        conversation: j['conversation'],
        input: j['input'] == null
            ? null
            : (j['input'] as List)
                .map<RealtimeConversationItem>((m) => RealtimeConversationItem.fromJson(m as Map<String, dynamic>))
                .toList(),
        instructions: j['instructions'],
        maxResponseOutputTokens: j['max_response_output_tokens'],
        metadata: j['metadata']?.cast<String, dynamic>(),
        modalities:
            j['modalities'] == null ? null : (j['modalities'] as List).map<Modality>((m) => Modality.fromJson(m as String)).toList(),
        outputAudioFormat: j['output_audio_format'] == null ? null : AudioFormat.fromJson(j['output_audio_format']),
        temperature: (j['temperature'] as num?)?.toDouble(),
        toolChoice: j['tool_choice'] == null ? null : ToolChoice.fromJson(j['tool_choice']),
        tools: j['tools'] == null ? null : (j['tools'] as List).cast<Map<String, dynamic>>().map(RealtimeFunctionTool.fromJson).toList(),
        voice: j['voice'] == null ? null : SpeechVoice.fromJson(j['voice']),
      );

  /* ---------- data ---------- */
  final String? conversation; // "auto" | "none"
  final List<RealtimeConversationItem>? input; // custom context
  final String? instructions;
  final dynamic maxResponseOutputTokens; // int | "inf"
  final Map<String, dynamic>? metadata; // ≤16 kv-pairs
  final List<Modality>? modalities;
  final AudioFormat? outputAudioFormat;
  final num? temperature;
  final ToolChoice? toolChoice;
  final List<RealtimeFunctionTool>? tools;
  final SpeechVoice? voice;

  /* ---------- serialise ---------- */
  Map<String, dynamic> toJson() => {
        if (conversation != null) 'conversation': conversation,
        if (input != null) 'input': input!.map((i) => i.toJson()).toList(),
        if (instructions != null) 'instructions': instructions,
        if (maxResponseOutputTokens != null) 'max_response_output_tokens': maxResponseOutputTokens,
        if (metadata != null) 'metadata': metadata,
        if (modalities != null) 'modalities': modalities!.map((m) => m.toJson()).toList(),
        if (outputAudioFormat != null) 'output_audio_format': outputAudioFormat!.toJson(),
        if (temperature != null) 'temperature': temperature,
        if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
        if (tools != null) 'tools': tools!.map((t) => t.toJson()).toList(),
        if (voice != null) 'voice': voice!.toJson(),
      };
}

/* ───────────────────────────────────────────────────────────────────────── */

/// Client → server event that *requests* a new assistant Response.
/// The server replies with:
///   response.created → …items… → response.done
class RealtimeResponseCreateEvent extends RealtimeEvent {
  RealtimeResponseCreateEvent({
    this.eventId,
    required this.response,
  }) : super('response.create');

  /* ---------- factory ---------- */
  factory RealtimeResponseCreateEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseCreateEvent(
        eventId: j['event_id'],
        response: RealtimeResponse.fromJson(j['response'] as Map<String, dynamic>),
      );

  /* ---------- data ---------- */
  final String? eventId;
  final RealtimeResponse response;

  /* ---------- serialise ---------- */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "response.create"
        if (eventId != null) 'event_id': eventId,
        'response': response.toJson(),
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

/* ────────────────────────────────────────────────────────────────────────── */
/*  “output_audio_buffer.clear” – client → server (WebRTC only)              */
/* ────────────────────────────────────────────────────────────────────────── */

/// Stop (truncate) the *currently-playing* assistant audio.
///
/// Best practice: emit **`response.cancel`** first so the model stops
/// generating; then send this event to discard what’s already buffered.
/// The server responds with **`output_audio_buffer.cleared`** (or an error).
class OutputAudioBufferClearEvent extends RealtimeEvent {
  OutputAudioBufferClearEvent({this.eventId}) : super('output_audio_buffer.clear');

  /* ---------- factory (JSON → object) ---------- */
  factory OutputAudioBufferClearEvent.fromJson(Map<String, dynamic> j) => OutputAudioBufferClearEvent(eventId: j['event_id']);

  /* ---------- data ---------- */
  final String? eventId; // optional client-generated correlation ID

  /* ---------- object → JSON ---------- */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "output_audio_buffer.clear"
        if (eventId != null) 'event_id': eventId,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “error” – server → client                                                */
/* ────────────────────────────────────────────────────────────────────────── */

/* ---------- error details payload ---------- */
class RealtimeErrorInfo {
  const RealtimeErrorInfo({
    required this.message,
    required this.type,
    this.code,
    this.clientEventId,
    this.param,
  });

  /* factory constructor (JSON → object) */
  factory RealtimeErrorInfo.fromJson(Map<String, dynamic> j) => RealtimeErrorInfo(
        message: j['message'],
        type: j['type'],
        code: j['code'],
        clientEventId: j['event_id'],
        param: j['param'],
      );

  final String message; // human-readable description
  final String type; // e.g. "invalid_request_error", "server_error"
  final String? code; // optional error code
  final String? clientEventId; // event_id of *client* message (if applicable)
  final String? param; // parameter name (if applicable)

  Map<String, dynamic> toJson() => {
        'message': message,
        'type': type,
        'code': code,
        'event_id': clientEventId,
        'param': param,
      }..removeWhere((_, v) => v == null);
}

/* ---------- error event ---------- */
class ErrorEvent extends RealtimeEvent {
  ErrorEvent({
    required this.eventId, // server-side event id
    required this.error, // detailed error info
  }) : super('error');

  /* factory (JSON → object) */
  factory ErrorEvent.fromJson(Map<String, dynamic> j) => ErrorEvent(
        eventId: j['event_id'],
        error: RealtimeErrorInfo.fromJson(j['error'] as Map<String, dynamic>),
      );

  final String eventId; // unique server event ID
  final RealtimeErrorInfo error; // error payload

  /* object → JSON */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "error"
        'event_id': eventId,
        'error': error.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “session.created” – server → client                                      */
/* ────────────────────────────────────────────────────────────────────────── */

class SessionCreatedEvent extends RealtimeEvent {
  SessionCreatedEvent({
    required this.eventId,
    required this.session,
  }) : super('session.created');

  /* factory (JSON → object) */
  factory SessionCreatedEvent.fromJson(Map<String, dynamic> j) => SessionCreatedEvent(
        eventId: j['event_id'],
        session: RealtimeSession.fromJson(j['session'] as Map<String, dynamic>),
      );

  final String eventId; // unique server event ID
  final RealtimeSession session; // default session configuration

  /* object → JSON */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "session.created"
        'event_id': eventId,
        'session': session.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “session.updated” – server → client                                      */
/* ────────────────────────────────────────────────────────────────────────── */

class SessionUpdatedEvent extends RealtimeEvent {
  SessionUpdatedEvent({
    required this.eventId,
    required this.session,
  }) : super('session.updated');

  /* JSON → object */
  factory SessionUpdatedEvent.fromJson(Map<String, dynamic> j) => SessionUpdatedEvent(
        eventId: j['event_id'],
        session: RealtimeSession.fromJson(j['session'] as Map<String, dynamic>),
      );

  final String eventId; // unique server event ID
  final RealtimeSession session; // full effective configuration after update

  /* object → JSON */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "session.updated"
        'event_id': eventId,
        'session': session.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Conversation resource (minimal wrapper)                                  */
/* ────────────────────────────────────────────────────────────────────────── */

class Conversation {
  Conversation({required this.id}) : object = 'realtime.conversation';

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(id: j['id'] as String);

  final String id;
  final String object; // always "realtime.conversation"

  Map<String, dynamic> toJson() => {'id': id, 'object': object};
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.created” – server → client                                 */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationCreatedEvent extends RealtimeEvent {
  ConversationCreatedEvent({
    required this.eventId,
    required this.conversation,
  }) : super('conversation.created');

  factory ConversationCreatedEvent.fromJson(Map<String, dynamic> j) => ConversationCreatedEvent(
        eventId: j['event_id'] as String,
        conversation: Conversation.fromJson(j['conversation'] as Map<String, dynamic>),
      );

  final String eventId; // unique server-generated ID
  final Conversation conversation;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "conversation.created"
        'event_id': eventId,
        'conversation': conversation.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.item.created” – server → client                            */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemCreatedEvent extends RealtimeEvent {
  ConversationItemCreatedEvent({
    required this.eventId,
    required this.item,
    this.previousItemId,
  }) : super('conversation.item.created');

  factory ConversationItemCreatedEvent.fromJson(Map<String, dynamic> j) => ConversationItemCreatedEvent(
        eventId: j['event_id'] as String,
        previousItemId: j['previous_item_id'] as String?,
        item: RealtimeConversationItem.fromJson(j['item'] as Map<String, dynamic>),
      );

  final String eventId;
  final String? previousItemId;
  final RealtimeConversationItem item;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "conversation.item.created"
        'event_id': eventId,
        if (previousItemId != null) 'previous_item_id': previousItemId,
        'item': item.toJson(),
      };
}
/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.item.retrieved” – server → client                          */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemRetrievedEvent extends RealtimeEvent {
  ConversationItemRetrievedEvent({
    required this.eventId,
    required this.item,
  }) : super('conversation.item.retrieved');

  factory ConversationItemRetrievedEvent.fromJson(Map<String, dynamic> j) => ConversationItemRetrievedEvent(
        eventId: j['event_id'] as String,
        item: RealtimeConversationItem.fromJson(j['item'] as Map<String, dynamic>),
      );

  final String eventId;
  final RealtimeConversationItem item;

  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "conversation.item.retrieved"
        'event_id': eventId,
        'item': item.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.item.input_audio_transcription.completed” – server event   */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemInputAudioTranscriptionCompletedEvent extends RealtimeEvent {
  ConversationItemInputAudioTranscriptionCompletedEvent({
    required this.eventId,
    required this.itemId,
    required this.contentIndex,
    required this.transcript,
    this.logprobs,
  }) : super('conversation.item.input_audio_transcription.completed');

  factory ConversationItemInputAudioTranscriptionCompletedEvent.fromJson(Map<String, dynamic> j) =>
      ConversationItemInputAudioTranscriptionCompletedEvent(
        eventId: j['event_id'] as String,
        itemId: j['item_id'] as String,
        contentIndex: j['content_index'] as int,
        transcript: j['transcript'] as String,
        logprobs: j['logprobs'] == null ? null : LogProbs.fromJson(j['logprobs']),
      );

  /// Unique server-generated ID for this event.
  final String eventId;

  /// ID of the user-message item that contained the original audio.
  final String itemId;

  /// Index of the audio content part inside the message (always 0 today).
  final int contentIndex;

  /// The ASR transcript of the audio buffer.
  final String transcript;

  /// Optional per-token / per-word log-probabilities (see `common.dart`).
  final LogProbs? logprobs;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        'content_index': contentIndex,
        'transcript': transcript,
        if (logprobs != null) 'logprobs': logprobs!.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.item.input_audio_transcription.delta” – server event       */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemInputAudioTranscriptionDeltaEvent extends RealtimeEvent {
  ConversationItemInputAudioTranscriptionDeltaEvent({
    required this.eventId,
    required this.itemId,
    required this.contentIndex,
    required this.delta,
    this.logprobs,
  }) : super('conversation.item.input_audio_transcription.delta');

  factory ConversationItemInputAudioTranscriptionDeltaEvent.fromJson(Map<String, dynamic> j) =>
      ConversationItemInputAudioTranscriptionDeltaEvent(
        eventId: j['event_id'] as String,
        itemId: j['item_id'] as String,
        contentIndex: j['content_index'] as int,
        delta: j['delta'] as String,
        logprobs: j['logprobs'] == null ? null : LogProbs.fromJson(j['logprobs']),
      );

  final String eventId;
  final String itemId;
  final int contentIndex;
  final String delta; // incremental ASR text
  final LogProbs? logprobs; // optional token probs

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        'content_index': contentIndex,
        'delta': delta,
        if (logprobs != null) 'logprobs': logprobs!.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.item.input_audio_transcription.failed” – server event      */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemInputAudioTranscriptionFailedEvent extends RealtimeEvent {
  ConversationItemInputAudioTranscriptionFailedEvent({
    required this.eventId,
    required this.itemId,
    required this.contentIndex,
    required this.error,
  }) : super('conversation.item.input_audio_transcription.failed');

  factory ConversationItemInputAudioTranscriptionFailedEvent.fromJson(Map<String, dynamic> j) =>
      ConversationItemInputAudioTranscriptionFailedEvent(
        eventId: j['event_id'] as String,
        itemId: j['item_id'] as String,
        contentIndex: j['content_index'] as int,
        error: RealtimeErrorInfo.fromJson(j['error'] as Map<String, dynamic>),
      );

  final String eventId;
  final String itemId;
  final int contentIndex;
  final RealtimeErrorInfo error; // the same shape used in the generic ErrorEvent

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        'content_index': contentIndex,
        'error': error.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.item.truncated” – server event                             */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemTruncatedEvent extends RealtimeEvent {
  ConversationItemTruncatedEvent({
    required this.eventId,
    required this.itemId,
    required this.contentIndex,
    required this.audioEndMs,
  }) : super('conversation.item.truncated');

  factory ConversationItemTruncatedEvent.fromJson(Map<String, dynamic> j) => ConversationItemTruncatedEvent(
        eventId: j['event_id'] as String,
        itemId: j['item_id'] as String,
        contentIndex: j['content_index'] as int,
        audioEndMs: j['audio_end_ms'] as int,
      );

  final String eventId;
  final String itemId;
  final int contentIndex;
  final int audioEndMs; // inclusive truncation point (ms)

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        'content_index': contentIndex,
        'audio_end_ms': audioEndMs,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “conversation.item.deleted” – server event                               */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemDeletedEvent extends RealtimeEvent {
  ConversationItemDeletedEvent({
    required this.eventId,
    required this.itemId,
  }) : super('conversation.item.deleted');

  factory ConversationItemDeletedEvent.fromJson(Map<String, dynamic> j) => ConversationItemDeletedEvent(
        eventId: j['event_id'] as String,
        itemId: j['item_id'] as String,
      );

  final String eventId;
  final String itemId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “input_audio_buffer.committed” – server event                            */
/* ────────────────────────────────────────────────────────────────────────── */

class InputAudioBufferCommittedEvent extends RealtimeEvent {
  InputAudioBufferCommittedEvent({
    required this.eventId,
    required this.itemId,
    this.previousItemId,
  }) : super('input_audio_buffer.committed');

  factory InputAudioBufferCommittedEvent.fromJson(Map<String, dynamic> j) => InputAudioBufferCommittedEvent(
        eventId: j['event_id'] as String,
        itemId: j['item_id'] as String,
        previousItemId: j['previous_item_id'] as String?,
      );

  final String eventId; // unique server event-ID
  final String itemId; // user message that will be created
  final String? previousItemId; // insertion point (could be null)

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        if (previousItemId != null) 'previous_item_id': previousItemId,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “input_audio_buffer.cleared” – server event                              */
/* ────────────────────────────────────────────────────────────────────────── */

class InputAudioBufferClearedEvent extends RealtimeEvent {
  InputAudioBufferClearedEvent({required this.eventId}) : super('input_audio_buffer.cleared');

  factory InputAudioBufferClearedEvent.fromJson(Map<String, dynamic> j) => InputAudioBufferClearedEvent(eventId: j['event_id'] as String);

  final String eventId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “input_audio_buffer.speech_started” – server event (Server-VAD mode)     */
/* ────────────────────────────────────────────────────────────────────────── */

class InputAudioBufferSpeechStartedEvent extends RealtimeEvent {
  InputAudioBufferSpeechStartedEvent({
    required this.eventId,
    required this.itemId,
    required this.audioStartMs,
  }) : super('input_audio_buffer.speech_started');

  factory InputAudioBufferSpeechStartedEvent.fromJson(Map<String, dynamic> j) => InputAudioBufferSpeechStartedEvent(
        eventId: j['event_id'] as String,
        itemId: j['item_id'] as String,
        audioStartMs: j['audio_start_ms'] as int,
      );

  final String eventId;
  final String itemId; // the future user-message ID
  final int audioStartMs; // ms offset where speech began

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        'audio_start_ms': audioStartMs,
      };
}

/* ───────────────────────────────────────────────────────────────────────── */

class RealtimeResponseCreatedEvent extends RealtimeEvent {
  RealtimeResponseCreatedEvent({
    this.eventId,
    required this.response,
  }) : super('response.created');

  /* ---------- factory ---------- */
  factory RealtimeResponseCreatedEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseCreatedEvent(
        eventId: j['event_id'],
        response: RealtimeResponse.fromJson(j['response'] as Map<String, dynamic>),
      );

  /* ---------- data ---------- */
  final String? eventId;
  final RealtimeResponse response;

  /* ---------- serialise ---------- */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "response.create"
        if (eventId != null) 'event_id': eventId,
        'response': response.toJson(),
      };
}

class RealtimeResponseCancelledEvent extends RealtimeEvent {
  RealtimeResponseCancelledEvent({
    this.eventId,
    required this.response,
  }) : super('response.create');

  /* ---------- factory ---------- */
  factory RealtimeResponseCancelledEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseCancelledEvent(
        eventId: j['event_id'],
        response: RealtimeResponse.fromJson(j['response'] as Map<String, dynamic>),
      );

  /* ---------- data ---------- */
  final String? eventId;
  final RealtimeResponse response;

  /* ---------- serialise ---------- */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "response.create"
        if (eventId != null) 'event_id': eventId,
        'response': response.toJson(),
      };
}

class RealtimeResponseDoneEvent extends RealtimeEvent {
  RealtimeResponseDoneEvent({
    this.eventId,
    required this.response,
  }) : super('response.done');

  /* ---------- factory ---------- */
  factory RealtimeResponseDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseDoneEvent(
        eventId: j['event_id'],
        response: RealtimeResponse.fromJson(j['response'] as Map<String, dynamic>),
      );

  /* ---------- data ---------- */
  final String? eventId;
  final RealtimeResponse response;

  /* ---------- serialise ---------- */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "response.create"
        if (eventId != null) 'event_id': eventId,
        'response': response.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.output_item.added” – server event                              */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseOutputItemAddedEvent extends RealtimeEvent {
  RealtimeResponseOutputItemAddedEvent({
    required this.eventId,
    required this.responseId,
    required this.outputIndex,
    required this.item,
  }) : super('response.output_item.added');

  factory RealtimeResponseOutputItemAddedEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseOutputItemAddedEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        outputIndex: j['output_index'] as int,
        item: RealtimeConversationItem.fromJson(j['item'] as Map<String, dynamic>),
      );

  final String eventId;
  final String responseId;
  final int outputIndex;
  final RealtimeConversationItem item;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'output_index': outputIndex,
        'item': item.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.output_item.done” – server event                               */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseOutputItemDoneEvent extends RealtimeEvent {
  RealtimeResponseOutputItemDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.outputIndex,
    required this.item,
  }) : super('response.output_item.done');

  factory RealtimeResponseOutputItemDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseOutputItemDoneEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        outputIndex: j['output_index'] as int,
        item: RealtimeConversationItem.fromJson(j['item'] as Map<String, dynamic>),
      );

  final String eventId;
  final String responseId;
  final int outputIndex;
  final RealtimeConversationItem item;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'output_index': outputIndex,
        'item': item.toJson(),
      };
}

/* ─── new content type for assistant-audio ─────────────────────────────── */

class AudioMessageContent extends RealtimeMessageContent {
  AudioMessageContent({required this.audioB64, this.transcript}) : super('audio');

  final String? audioB64; // base-64 PCM/G.711 payload
  final String? transcript; // optional ASR transcript

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'audio': audioB64,
        if (transcript != null) 'transcript': transcript,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.content_part.added” – server event                              */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseContentPartAddedEvent extends RealtimeEvent {
  RealtimeResponseContentPartAddedEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.part,
  }) : super('response.content_part.added');

  factory RealtimeResponseContentPartAddedEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseContentPartAddedEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
        part: RealtimeMessageContent.fromJson(j['part'] as Map<String, dynamic>),
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final RealtimeMessageContent part;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'part': part.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.content_part.done” – server event                              */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseContentPartDoneEvent extends RealtimeEvent {
  RealtimeResponseContentPartDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.part,
  }) : super('response.content_part.done');

  factory RealtimeResponseContentPartDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseContentPartDoneEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
        part: RealtimeMessageContent.fromJson(j['part'] as Map<String, dynamic>),
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final RealtimeMessageContent part;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'part': part.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.text.delta” – server event                                     */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseTextDeltaEvent extends RealtimeEvent {
  RealtimeResponseTextDeltaEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
  }) : super('response.text.delta');

  factory RealtimeResponseTextDeltaEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseTextDeltaEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
        delta: j['delta'] as String,
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String delta;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'delta': delta,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.text.done” – server event                                      */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseTextDoneEvent extends RealtimeEvent {
  RealtimeResponseTextDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.text,
  }) : super('response.text.done');

  factory RealtimeResponseTextDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseTextDoneEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
        text: j['text'] as String,
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String text;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'text': text,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.audio_transcript.delta” – server event                         */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseAudioTranscriptDeltaEvent extends RealtimeEvent {
  RealtimeResponseAudioTranscriptDeltaEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
  }) : super('response.audio_transcript.delta');

  factory RealtimeResponseAudioTranscriptDeltaEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseAudioTranscriptDeltaEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
        delta: j['delta'] as String,
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String delta;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'delta': delta,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.audio_transcript.done” – server event                          */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseAudioTranscriptDoneEvent extends RealtimeEvent {
  RealtimeResponseAudioTranscriptDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.transcript,
  }) : super('response.audio_transcript.done');

  factory RealtimeResponseAudioTranscriptDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseAudioTranscriptDoneEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
        transcript: j['transcript'] as String,
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String transcript;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'transcript': transcript,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.audio.delta” – server event                                    */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseAudioDeltaEvent extends RealtimeEvent {
  RealtimeResponseAudioDeltaEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta, // base-64 audio chunk
  }) : super('response.audio.delta');

  factory RealtimeResponseAudioDeltaEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseAudioDeltaEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
        delta: j['delta'] as String,
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final int contentIndex;
  final String delta; // base-64-encoded audio data delta

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
        'delta': delta,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.audio.done” – server event                                     */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseAudioDoneEvent extends RealtimeEvent {
  RealtimeResponseAudioDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
  }) : super('response.audio.done');

  factory RealtimeResponseAudioDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseAudioDoneEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        contentIndex: j['content_index'] as int,
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final int contentIndex;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'content_index': contentIndex,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.function_call_arguments.delta” – server event                  */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseFunctionCallArgumentsDeltaEvent extends RealtimeEvent {
  RealtimeResponseFunctionCallArgumentsDeltaEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.callId,
    required this.delta, // incremental JSON-string fragment
  }) : super('response.function_call_arguments.delta');

  factory RealtimeResponseFunctionCallArgumentsDeltaEvent.fromJson(Map<String, dynamic> j) =>
      RealtimeResponseFunctionCallArgumentsDeltaEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        callId: j['call_id'] as String,
        delta: j['delta'] as String,
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final String callId;
  final String delta; // partial args JSON

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'call_id': callId,
        'delta': delta,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “response.function_call_arguments.done” – server event                   */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseFunctionCallArgumentsDoneEvent extends RealtimeEvent {
  RealtimeResponseFunctionCallArgumentsDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.callId,
    required this.argumentsJson, // final arguments JSON string
  }) : super('response.function_call_arguments.done');

  factory RealtimeResponseFunctionCallArgumentsDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseFunctionCallArgumentsDoneEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
        itemId: j['item_id'] as String,
        outputIndex: j['output_index'] as int,
        callId: j['call_id'] as String,
        argumentsJson: j['arguments'] as String,
      );

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final String callId;
  final String argumentsJson; // complete args JSON

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'call_id': callId,
        'arguments': argumentsJson,
      };
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
/*  “rate_limits.updated” – server → client                                  */
/* ────────────────────────────────────────────────────────────────────────── */

/// Helpful little DTO for each list element; keeps unknown keys intact.
class RateLimit {
  RateLimit(this.data);

  factory RateLimit.fromJson(Map<String, dynamic> j) => RateLimit(j);

  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => data;
}

class RateLimitsUpdatedEvent extends RealtimeEvent {
  RateLimitsUpdatedEvent({
    required this.eventId,
    required this.rateLimits,
  }) : super('rate_limits.updated');

  factory RateLimitsUpdatedEvent.fromJson(Map<String, dynamic> j) => RateLimitsUpdatedEvent(
        eventId: j['event_id'] as String,
        rateLimits: (j['rate_limits'] as List).cast<Map<String, dynamic>>().map(RateLimit.fromJson).toList(),
      );

  final String eventId;
  final List<RateLimit> rateLimits;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'rate_limits': rateLimits.map((rl) => rl.toJson()).toList(),
      };
}

/// Base class that keeps the shared fields (event_id + response_id)
/// for the three `output_audio_buffer.*` server events.
///
/// You don’t have to use this base class, but it keeps things DRY. If you
/// prefer three completely separate classes (as with some earlier events),
/// just copy-paste the two fields + `toJson` into each concrete class.
abstract class _OutputAudioBufferEvent extends RealtimeEvent {
  const _OutputAudioBufferEvent(super.type, {required this.eventId, required this.responseId});

  final String eventId;
  final String responseId;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
      };
}

/* ── output_audio_buffer.started ───────────────────────────────────────── */

class OutputAudioBufferStartedEvent extends _OutputAudioBufferEvent {
  OutputAudioBufferStartedEvent({
    required String eventId,
    required String responseId,
  }) : super('output_audio_buffer.started', eventId: eventId, responseId: responseId);

  factory OutputAudioBufferStartedEvent.fromJson(Map<String, dynamic> j) => OutputAudioBufferStartedEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
      );
}

/* ── output_audio_buffer.stopped ───────────────────────────────────────── */

class OutputAudioBufferStoppedEvent extends _OutputAudioBufferEvent {
  OutputAudioBufferStoppedEvent({
    required String eventId,
    required String responseId,
  }) : super('output_audio_buffer.stopped', eventId: eventId, responseId: responseId);

  factory OutputAudioBufferStoppedEvent.fromJson(Map<String, dynamic> j) => OutputAudioBufferStoppedEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
      );
}

/* ── output_audio_buffer.cleared ───────────────────────────────────────── */

class OutputAudioBufferClearedEvent extends _OutputAudioBufferEvent {
  OutputAudioBufferClearedEvent({
    required String eventId,
    required String responseId,
  }) : super('output_audio_buffer.cleared', eventId: eventId, responseId: responseId);

  factory OutputAudioBufferClearedEvent.fromJson(Map<String, dynamic> j) => OutputAudioBufferClearedEvent(
        eventId: j['event_id'] as String,
        responseId: j['response_id'] as String,
      );
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  “input_audio_buffer.speech_stopped” (server → client)  */
/* ────────────────────────────────────────────────────────────────────────── */

class InputAudioBufferSpeechStoppedEvent extends RealtimeEvent {
  InputAudioBufferSpeechStoppedEvent({
    required this.audioEndMs,
    required this.itemId,
    required this.eventId,
  }) : super('input_audio_buffer.speech_stopped');

  factory InputAudioBufferSpeechStoppedEvent.fromJson(Map<String, dynamic> j) => InputAudioBufferSpeechStoppedEvent(
        audioEndMs: j['audio_end_ms'] as int,
        itemId: j['item_id'] as String,
        eventId: j['event_id'] as String,
      );

  final int audioEndMs; // when speech ended
  final String itemId; // user-message item created
  final String eventId; // server-generated event id

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'audio_end_ms': audioEndMs,
        'item_id': itemId,
      };
}
