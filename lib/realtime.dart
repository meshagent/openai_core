// ──────────────────────────────────────────────────────────────────────────
//  Realtime session helpers (/realtime/sessions & /realtime/transcription…)
// ──────────────────────────────────────────────────────────────────────────

// ── Small enums / value types ─────────────────────────────────────────────
import 'dart:async';
import 'dart:convert';

import 'package:http_parser/http_parser.dart';

import 'audio.dart';
import 'common.dart';
import 'exceptions.dart';
import 'openai_client.dart';
import 'responses.dart';
import 'package:http/http.dart' as http;

class NoiseReductionType extends JsonEnum {
  static const nearField = NoiseReductionType('near_field');
  static const farField = NoiseReductionType('far_field');

  const NoiseReductionType(super.value);

  static NoiseReductionType fromJson(String raw) => NoiseReductionType(raw);
}

class TurnDetectionType extends JsonEnum {
  static const serverVad = TurnDetectionType('server_vad');
  static const semanticVad = TurnDetectionType('semantic_vad');

  const TurnDetectionType(super.value);
  static TurnDetectionType fromJson(String raw) => TurnDetectionType(raw);
}

class Eagerness extends JsonEnum {
  static const low = Eagerness('low');
  static const medium = Eagerness('medium');
  static const high = Eagerness('high');
  static const auto = Eagerness('auto');

  const Eagerness(super.value);

  static Eagerness fromJson(String raw) => Eagerness(raw);
}

class Modality extends JsonEnum {
  static const audio = Modality('audio');
  static const text = Modality('text');

  const Modality(super.value);

  static Modality fromJson(String raw) => Modality(raw);
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
    this.idleTimeoutMs,
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
  final int? idleTimeoutMs;

  Map<String, dynamic> toJson() => {
        'type': type.toJson(),
        if (threshold != null) 'threshold': threshold,
        if (prefixPaddingMs != null) 'prefix_padding_ms': prefixPaddingMs,
        if (silenceDurationMs != null) 'silence_duration_ms': silenceDurationMs,
        if (eagerness != null) 'eagerness': eagerness!.toJson(),
        if (createResponse != null) 'create_response': createResponse,
        if (interruptResponse != null) 'interrupt_response': interruptResponse,
        if (idleTimeoutMs != null) 'idle_timeout_ms': idleTimeoutMs,
      };
}

class RealtimeSessionType extends JsonEnum {
  const RealtimeSessionType(super.value);

  static RealtimeSessionType fromJson(String raw) => RealtimeSessionType(raw);

  static const realtime = RealtimeSessionType('realtime');
  static const transcription = RealtimeSessionType('transcription');
}

/// Realtime-capable, low-latency models (WebSocket / /realtime/* APIs).
class RealtimeModel extends JsonEnum {
  /// GA speech-in/speech-out model.
  static const gptRealtime = RealtimeModel('gpt-realtime');

  /// Public preview model (speech + text).
  static const gpt4oRealtimePreview = RealtimeModel('gpt-4o-realtime-preview');

  static const gpt4oRealtimePreview_2025_06_03 = RealtimeModel("gpt-4o-realtime-preview-2025-06-03");

  /// Same architecture, but text-only and slightly cheaper.
  static const gpt4oRealtimeMiniPreview = RealtimeModel('gpt-4o-realtime-mini-preview');

  const RealtimeModel(super.value);

  /// Parses the wire value or throws if it’s an unknown model string.
  static RealtimeModel fromJson(String raw) => RealtimeModel(raw);
}

/// Result of POST /v1/realtime/calls
///
/// - [sdpAnswer] is the raw SDP answer returned in the response body.
/// - [callId] (if available) is parsed from the `Location` header, which
///   the server sets to `/v1/realtime/calls/<call_id>`.
class CreateRealtimeCallResponse {
  CreateRealtimeCallResponse({
    required this.sdpAnswer,
    this.callId,
    this.location,
  });

  /// The SDP answer returned by the server.
  final String sdpAnswer;

  /// Unique call ID (parsed from the `Location` response header), if present.
  final String? callId;

  /// The full `Location` header as a URI, if present.
  final Uri? location;
}

abstract class RealtimeTruncation {
  const RealtimeTruncation();

  dynamic toJson();

  factory RealtimeTruncation.fromJson(dynamic raw) {
    if (raw is String) {
      if (raw == 'auto') return const RealtimeTruncationAuto();
      if (raw == 'disabled') return const RealtimeTruncationDisabled();
    }
    if (raw is Map<String, dynamic>) {
      if (raw['type'] == 'retention_ratio') {
        return RealtimeTruncationRatio.fromJson(raw);
      }
    }
    // Fallback or error for unknown types
    throw ArgumentError('Unexpected RealtimeTruncation value: $raw');
  }
}

class RealtimeTruncationAuto extends RealtimeTruncation {
  const RealtimeTruncationAuto();
  @override
  dynamic toJson() {
    return "auto";
  }
}

class RealtimeTruncationDisabled extends RealtimeTruncation {
  const RealtimeTruncationDisabled();
  @override
  dynamic toJson() {
    return "disabled";
  }
}

class RealtimeTruncationRatio extends RealtimeTruncation {
  const RealtimeTruncationRatio({required this.ratio});

  factory RealtimeTruncationRatio.fromJson(Map<String, dynamic> json) {
    return RealtimeTruncationRatio(
      ratio: (json['retention_ratio'] as num).toDouble(),
    );
  }

  final double ratio;

  @override
  dynamic toJson() {
    return {
      "type": "retention_ratio",
      "retention_ratio": ratio,
    };
  }
}

// ── Extensions on OpenAIClient ────────────────────────────────────────────
extension RealtimeAPI on OpenAIClient {
  /// Create a new Realtime API call over WebRTC and receive the **SDP answer**.
  ///
  /// Mirrors: POST /v1/realtime/calls
  ///
  /// Required:
  /// - [sdp] : the WebRTC SDP **offer** generated by the caller.
  ///
  /// Session configuration:
  /// - Provide either a full [sessionJson] that matches the API docs **or**
  ///   use the convenience params (same semantics as `createRealtimeClientSecret`).
  ///
  /// Notes:
  /// - `session.type` must be `"realtime"` for Realtime sessions (default here).
  /// - `outputModalities` cannot request both `"audio"` and `"text"` at once.
  /// - The response body is plain text (application/sdp) with the SDP **answer**.
  /// - The `Location` header includes the **call ID** for follow‑ups (monitoring
  ///   WebSocket, `/accept`, `/hangup`, etc.).
  Future<CreateRealtimeCallResponse> createCall({
    // SDP offer
    required String sdp,
    // Convenience fields (used only if `sessionJson` is null or empty)
    RealtimeSessionType type = RealtimeSessionType.realtime,
    RealtimeModel? model, // e.g., RealtimeModel.gptRealtime
    String? instructions,
    dynamic maxOutputTokens, // int | "inf"
    List<Modality>? outputModalities, // ["audio"] | ["text"]
    RealtimeSessionAudio? audio, // input/output audio config
    List<RealtimeFunctionTool>? tools,
    ToolChoice? toolChoice,
    Tracing? tracing, // "auto" or object
    List<String>? include, // e.g. ["item.input_audio_transcription.logprobs"]
    Map<String, dynamic>? prompt, // {id, variables?, version?}
    RealtimeTruncation? truncation, // "auto" or {type:"retention_ratio", retention_ratio:0.5}
    double? temperature,
  }) async {
    final session = <String, dynamic>{
      'type': type.toJson(),
      if (model != null) 'model': model.toJson(),
      if (instructions != null) 'instructions': instructions,
      if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
      if (outputModalities != null) 'output_modalities': outputModalities.map((m) => m.toJson()).toList(),
      if (tools != null) 'tools': tools.map((t) => t.toJson()).toList(),
      if (toolChoice != null) 'tool_choice': toolChoice.toJson(),
      if (tracing != null) 'tracing': tracing.toJson(),
      if (include != null) 'include': include,
      if (prompt != null) 'prompt': prompt,
      if (truncation != null) 'truncation': truncation.toJson(),
      if (audio != null) 'audio': audio.toJson(),
      if (temperature != null) 'temperature': temperature,
    };
    final request = http.MultipartRequest("POST", baseUrl.resolve("realtime/calls"))
      ..files.add(http.MultipartFile.fromBytes(
        "sdp",
        utf8.encode(sdp),
        contentType: MediaType("application", "sdp"),
      ))
      ..files.add(http.MultipartFile.fromBytes(
        "session",
        utf8.encode(jsonEncode(
          session,
        )),
        contentType: MediaType("application", "json"),
      ));

    request.headers.addAll(getHeaders({}) ?? {});

    final streamedResponse = await request.send();
    final res = await http.Response.fromStream(streamedResponse);

    // The spec returns 201 Created with the SDP **answer** in the body.
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw OpenAIRequestException.fromHttpResponse(res);
    }

    // Extract the Location header (case-insensitive) to get the call ID.
    String? locationHeader;
    res.headers.forEach((k, v) {
      if (k.toLowerCase() == 'location') locationHeader = v;
    });

    Uri? locationUri;
    String? callId;

    if (locationHeader != null && locationHeader!.isNotEmpty) {
      locationUri = Uri.tryParse(locationHeader!);

      // Try to parse `/v1/realtime/calls/<id>` regardless of absolute/relative form.
      final String path = locationUri?.path ?? locationHeader!;
      final match = RegExp(r'/realtime/calls/([^/?#]+)').firstMatch(path);
      if (match != null) callId = match.group(1);
    }

    return CreateRealtimeCallResponse(
      sdpAnswer: res.body, // plain text SDP answer
      callId: callId,
      location: locationUri,
    );
  }

  /// Accept an incoming SIP call and configure the realtime session that will handle it.
  ///
  /// Mirrors POST /v1/realtime/calls/{call_id}/accept
  ///
  /// Notes:
  /// - `sessionType` must be "realtime" per API (kept configurable for symmetry).
  /// - If you set [outputModalities] to [Modality.text], the model will respond with text only.
  /// - Audio formats are translated to the Calls wire format:
  ///     pcm16 → {type:"audio/pcm", rate:24000}, g711_ulaw → audio/pcmu, g711_alaw → audio/pcma
  Future<void> acceptCall({
    required String callId,
    String sessionType = 'realtime',
    RealtimeModel? model,
    String? instructions,
    List<Modality>? outputModalities, // Calls key: output_modalities
    RealtimeSessionAudio? audio,
    // Tools & guidance
    List<RealtimeFunctionTool>? tools,
    ToolChoice? toolChoice,
    dynamic maxOutputTokens, // int | "inf"
    List<String>? include, // e.g. ["item.input_audio_transcription.logprobs"]
    Tracing? tracing, // "auto" or object
    Map<String, dynamic>? prompt, // {id, variables?, version?}
    dynamic truncation, // "auto" or {type:"retention_ratio", retention_ratio:0.5}
  }) async {
    final payload = <String, dynamic>{
      'type': sessionType, // must be "realtime"
      if (model != null) 'model': model.toJson(),
      if (instructions != null) 'instructions': instructions,
      if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
      if (outputModalities != null) 'output_modalities': outputModalities.map((m) => m.toJson()).toList(),
      if (tools != null) 'tools': tools.map((t) => t.toJson()).toList(),
      if (toolChoice != null) 'tool_choice': toolChoice.toJson(),
      if (include != null) 'include': include,
      if (tracing != null) 'tracing': tracing.toJson(),
      if (prompt != null) 'prompt': prompt,
      if (truncation != null) 'truncation': truncation,
      if (audio != null) 'audio': audio.toJson(),
    };

    final res = await postJson('/realtime/calls/$callId/accept', payload);
    if (res.statusCode != 200) {
      throw OpenAIRequestException.fromHttpResponse(res);
    }
  }

  /// Reject an incoming call with an optional SIP status code.
  /// Default server behavior is 603 (Decline) if statusCode is omitted.
  ///
  /// POST /v1/realtime/calls/{call_id}/reject
  Future<void> rejectCall({
    required String callId,
    int? statusCode, // e.g. 486 (Busy Here), 603 (Decline)
  }) async {
    final body = <String, dynamic>{};
    if (statusCode != null) body['status_code'] = statusCode;

    final res = await postJson('/realtime/calls/$callId/reject', body);
    if (res.statusCode != 200) {
      throw OpenAIRequestException.fromHttpResponse(res);
    }
  }

  /// Transfer an active SIP call to another destination (SIP REFER).
  ///
  /// POST /v1/realtime/calls/{call_id}/refer
  Future<void> referCall({
    required String callId,
    required String targetUri, // e.g. "tel:+14155550123" or "sip:agent@example.com"
  }) async {
    final res = await postJson('/realtime/calls/$callId/refer', {'target_uri': targetUri});
    if (res.statusCode != 200) {
      throw OpenAIRequestException.fromHttpResponse(res);
    }
  }

  /// Hang up an active realtime call (SIP or WebRTC).
  ///
  /// POST /v1/realtime/calls/{call_id}/hangup
  Future<void> hangupCall({required String callId}) async {
    final res = await postJson('/realtime/calls/$callId/hangup', const {});
    if (res.statusCode != 200) {
      throw OpenAIRequestException.fromHttpResponse(res);
    }
  }

  /// Create an ephemeral client secret (ek_...) with an associated session config.
  ///
  /// POST /v1/realtime/client_secrets
  ///
  /// You can either:
  ///  - pass a fully-formed `sessionJson` that matches the docs; or
  ///  - use the convenience arguments to build a typical minimal config.
  ///
  /// Notes:
  ///  - `expiresAfterSeconds` must be 10–7200 (defaults to 600s server-side).
  ///  - `session` must contain a `type`: "realtime" or "transcription".
  Future<CreateRealtimeClientSecretResponse> createRealtimeClientSecret({
    // Expiration policy
    int? expiresAfterSeconds, // 10..7200 (2h). Server default: 600 (10min)
    String expiresAfterAnchor = 'created_at',

    // Provide a fully-formed session payload if you need full control.
    Map<String, dynamic>? sessionJson,

    // --- Convenience fields to build a minimal session quickly ---
    // (Used only when `sessionJson` is null)
    String sessionType = 'realtime', // "realtime" | "transcription"
    String? model, // e.g. RealtimeModel.gptRealtime.toJson()
    List<Modality>? outputModalities, // e.g. [Modality.audio] or [Modality.text]
    // Audio convenience
    AudioFormat? inputAudioFormat,
    AudioFormat? outputAudioFormat,
    SpeechVoice? voice,
    num? speed,
    // Guidance & tools
    String? instructions,
    dynamic maxOutputTokens, // int | "inf"
    List<RealtimeFunctionTool>? tools,
    ToolChoice? toolChoice,
    Tracing? tracing,
    // Detection/transcription knobs
    TurnDetection? turnDetection,
    NoiseReduction? inputAudioNoiseReduction,
    InputAudioTranscription? inputAudioTranscription, // for transcription sessions
    List<String>? include, // e.g. ["item.input_audio_transcription.logprobs"]
  }) async {
    if (expiresAfterSeconds != null && (expiresAfterSeconds < 10 || expiresAfterSeconds > 7200)) {
      throw ArgumentError('expiresAfterSeconds must be between 10 and 7200 seconds.');
    }

    // Build payload
    final payload = <String, dynamic>{};

    if (expiresAfterSeconds != null || expiresAfterAnchor != 'created_at') {
      payload['expires_after'] = {
        'anchor': expiresAfterAnchor,
        if (expiresAfterSeconds != null) 'seconds': expiresAfterSeconds,
      };
    }

    // Assemble `session` block
    Map<String, dynamic> session = sessionJson ?? {};
    if (session.isEmpty) {
      // Minimal session using convenience params
      session = {'type': sessionType};
      if (model != null) session['model'] = model;
      if (instructions != null) session['instructions'] = instructions;
      if (maxOutputTokens != null) session['max_output_tokens'] = maxOutputTokens;
      if (tools != null) session['tools'] = tools.map((t) => t.toJson()).toList();
      if (toolChoice != null) session['tool_choice'] = toolChoice.toJson();
      if (tracing != null) session['tracing'] = tracing.toJson();
      if (turnDetection != null) session['turn_detection'] = turnDetection.toJson();

      // Modalities: For realtime sessions, server defaults to ["audio"].
      // You may set ["text"] to disable audio output (cannot request both).
      if (outputModalities != null && sessionType == 'realtime') {
        session['output_modalities'] = outputModalities.map((m) => m.toJson()).toList();
      }

      // Audio block
      final audio = <String, dynamic>{};

      // Input sub-block (both session types)
      final input = <String, dynamic>{};
      if (inputAudioFormat != null) input['format'] = inputAudioFormat.toJson();
      if (inputAudioNoiseReduction != null) {
        input['noise_reduction'] = inputAudioNoiseReduction.toJson();
      }
      if (input.isNotEmpty) audio['input'] = input;

      if (sessionType == 'realtime') {
        // Output sub-block only exists on realtime sessions
        final output = <String, dynamic>{};
        if (outputAudioFormat != null) output['format'] = outputAudioFormat.toJson();
        if (voice != null) output['voice'] = voice.toJson();
        if (speed != null) output['speed'] = speed;
        if (output.isNotEmpty) audio['output'] = output;
      } else {
        // Transcription-only session extras
        if (include != null) session['include'] = include;
        if (inputAudioTranscription != null) {
          audio['transcription'] = inputAudioTranscription.toJson();
        }
      }

      if (audio.isNotEmpty) session['audio'] = audio;
    }

    payload['session'] = session;

    final res = await postJson('/realtime/client_secrets', payload);

    // The reference returns 201 Created (but accept 200 just in case).
    if (res.statusCode == 201 || res.statusCode == 200) {
      return CreateRealtimeClientSecretResponse.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }
}

abstract class RealtimeTool {
  const RealtimeTool();

  Map<String, dynamic> toJson();

  static RealtimeTool fromJson(Map<String, dynamic> j) {
    return switch (j["type"]) {
      "mcp" => RealtimeMcpTool.fromJson(j),
      "function" => RealtimeFunctionTool.fromJson(j),
      _ => throw ArgumentError("unexpected tool type ${j['type']}"),
    };
  }
}

class RealtimeMcpTool extends RealtimeTool {
  const RealtimeMcpTool({
    required this.serverLabel,
    required this.serverUrl,
    this.serverDescription,
    this.allowedTools,
    this.headers,
    this.requireApproval,
  });

  final String serverLabel;
  final String serverUrl;
  final String? serverDescription;
  final List<String>? allowedTools;
  final Map<String, String>? headers;
  final MCPToolApproval? requireApproval;

  factory RealtimeMcpTool.fromJson(Map<String, dynamic> json) {
    return RealtimeMcpTool(
      serverLabel: json['server_label'] as String,
      serverUrl: json['server_url'] as String,
      serverDescription: json['server_description'] as String?,
      allowedTools: (json['allowed_tools'] as List?)?.cast<String>(),
      headers: (json['headers'] as Map?)?.cast<String, String>(),
      requireApproval: json['require_approval'] == null ? null : MCPToolApproval.fromJson(json['require_approval']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'mcp',
        'server_label': serverLabel,
        'server_url': serverUrl,
        'server_description': serverDescription,
        if (headers != null) 'headers': headers,
        if (allowedTools != null) 'allowed_tools': allowedTools,
        if (requireApproval != null) 'require_approval': requireApproval!.toJson(),
      };
}

/// — function_tool
class RealtimeFunctionTool extends RealtimeTool {
  const RealtimeFunctionTool({
    required this.name,
    required this.parameters,
    this.description,
  });

  bool matches(RealtimeFunctionTool tool) {
    return tool.name == this.name;
  }

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

      case 'output_audio_buffer.clear':
        return OutputAudioBufferClearEvent.fromJson(j);

      /* ── server → client : session-level ─────────────────────────────── */
      case 'session.created':
        return SessionCreatedEvent.fromJson(j);
      case 'session.updated':
        return SessionUpdatedEvent.fromJson(j);

      case 'rate_limits.updated':
        return RateLimitsUpdatedEvent.fromJson(j);

      /* ── server → client : conversation-level ────────────────────────── */
      case 'conversation.created':
        return ConversationCreatedEvent.fromJson(j);
      case 'conversation.item.created':
        return ConversationItemCreatedEvent.fromJson(j);
      case 'conversation.item.done':
        return ConversationItemDoneEvent.fromJson(j);
      case 'conversation.item.added':
        return ConversationItemAddedEvent.fromJson(j);
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
        return RealtimeErrorEvent.fromJson(j);

      /* ── server → client : response-level (MCP) ─────────────────────────── */
      case 'response.mcp_call_arguments.delta':
        return RealtimeResponseMcpCallArgumentsDeltaEvent.fromJson(j);
      case 'response.mcp_call_arguments.done':
        return RealtimeResponseMcpCallArgumentsDoneEvent.fromJson(j);

      case 'response.mcp_call.in_progress':
        return RealtimeResponseMcpCallInProgressEvent.fromJson(j);
      case 'response.mcp_call.completed':
        return RealtimeResponseMcpCallCompletedEvent.fromJson(j);
      case 'response.mcp_call.failed':
        return RealtimeResponseMcpCallFailedEvent.fromJson(j);

      /* ── server → client : mcp_list_tools lifecycle ─────────────────────── */
      case 'mcp_list_tools.in_progress':
        return McpListToolsInProgressEvent.fromJson(j);
      case 'mcp_list_tools.completed':
        return McpListToolsCompletedEvent.fromJson(j);
      case 'mcp_list_tools.failed':
        return McpListToolsFailedEvent.fromJson(j);

      /* ── server → client : response-level (output_* variants) ─────────── */
      case 'response.output_text.delta':
        return RealtimeResponseOutputTextDeltaEvent.fromJson(j);
      case 'response.output_text.done':
        return RealtimeResponseOutputTextDoneEvent.fromJson(j);

      case 'response.output_audio_transcript.delta':
        return RealtimeResponseOutputAudioTranscriptDeltaEvent.fromJson(j);
      case 'response.output_audio_transcript.done':
        return RealtimeResponseOutputAudioTranscriptDoneEvent.fromJson(j);

      case 'response.output_audio.delta':
        return RealtimeResponseOutputAudioDeltaEvent.fromJson(j);
      case 'response.output_audio.done':
        return RealtimeResponseOutputAudioDoneEvent.fromJson(j);

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
        session: RealtimeSession.fromJson(j['session'] as Map<String, dynamic>),
      );

  final String? eventId; // optional client-generated correlation ID
  final RealtimeSession session;

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
      case 'output_text':
        return RealtimeOutputText(text: c['text'], type: c['type']);
      case 'input_audio':
        return RealtimeInputAudio(
          audioB64: c['audio'],
          transcript: c['transcript'],
        );

      case 'audio':
      case 'output_audio':
        return RealtimeOutputAudio(
          audioB64: c['audio'],
          transcript: c['transcript'],
          type: c['type'],
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

class RealtimeOutputText extends RealtimeMessageContent {
  RealtimeOutputText({required this.text, String type = 'output_text'}) : super(type);
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

  /* ---------- factory ------------- */
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

class ResponseAudioOutputOptions {
  const ResponseAudioOutputOptions({
    this.format,
    this.voice,
  });

  factory ResponseAudioOutputOptions.fromJson(Map<String, dynamic> json) {
    return ResponseAudioOutputOptions(
      format: json['format'] == null ? null : AudioFormat.fromJson(json['format']),
      voice: json['voice'] == null ? null : SpeechVoice.fromJson(json['voice']),
    );
  }

  final AudioFormat? format;
  final SpeechVoice? voice;

  Map<String, dynamic> toJson() => {
        if (format != null) 'format': format!.toJson(),
        if (voice != null) 'voice': voice!.toJson(),
      };
}

class ResponseAudioOptions {
  const ResponseAudioOptions({
    this.output,
  });

  factory ResponseAudioOptions.fromJson(Map<String, dynamic> json) {
    return ResponseAudioOptions(
      output: json['output'] == null ? null : ResponseAudioOutputOptions.fromJson(json['output']),
    );
  }

  final ResponseAudioOutputOptions? output;

  Map<String, dynamic> toJson() => {
        if (output != null) 'output': output!.toJson(),
      };
}

/// Per-request inference parameters (override session defaults **only**
/// for this single response).
class RealtimeResponseOptions {
  RealtimeResponseOptions({
    this.conversation, // "auto" | "none"
    this.input, // custom prompt context
    this.instructions,
    this.maxOutputTokens, // int | "inf"
    this.metadata,
    this.outputModalities,
    this.audio,
    this.prompt,
    this.toolChoice,
    this.tools,
  });

  /* ---------- factory fromJson ---------- */
  factory RealtimeResponseOptions.fromJson(Map<String, dynamic> j) => RealtimeResponseOptions(
        conversation: j['conversation'],
        input: j['input'] == null
            ? null
            : (j['input'] as List)
                .map<RealtimeConversationItem>((m) => RealtimeConversationItem.fromJson(m as Map<String, dynamic>))
                .toList(),
        instructions: j['instructions'],
        maxOutputTokens: j['max_output_tokens'],
        metadata: j['metadata']?.cast<String, dynamic>(),
        outputModalities: j['output_modalities'] == null
            ? null
            : (j['output_modalities'] as List).map<Modality>((m) => Modality.fromJson(m as String)).toList(),
        audio: j['audio'] == null ? null : ResponseAudioOptions.fromJson(j['audio']),
        prompt: j['prompt'] == null ? null : Prompt.fromJson(j['prompt']),
        toolChoice: j['tool_choice'] == null ? null : ToolChoice.fromJson(j['tool_choice']),
        tools: j['tools'] == null ? null : (j['tools'] as List).cast<Map<String, dynamic>>().map(RealtimeTool.fromJson).toList(),
      );

  /* ---------- data ---------- */
  final String? conversation; // "auto" | "none"
  final List<RealtimeConversationItem>? input; // custom context
  final String? instructions;
  final dynamic maxOutputTokens; // int | "inf"
  final Map<String, dynamic>? metadata; // ≤16 kv-pairs
  final List<Modality>? outputModalities;
  final ResponseAudioOptions? audio;
  final Prompt? prompt;
  final ToolChoice? toolChoice;
  final List<RealtimeTool>? tools;

  /* ---------- serialise ---------- */
  Map<String, dynamic> toJson() => {
        if (conversation != null) 'conversation': conversation,
        if (input != null) 'input': input!.map((i) => i.toJson()).toList(),
        if (instructions != null) 'instructions': instructions,
        if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
        if (metadata != null) 'metadata': metadata,
        if (outputModalities != null) 'output_modalities': outputModalities!.map((m) => m.toJson()).toList(),
        if (audio != null) 'audio': audio!.toJson(),
        if (prompt != null) 'prompt': prompt!.toJson(),
        if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
        if (tools != null) 'tools': tools!.map((t) => t.toJson()).toList(),
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
        response: RealtimeResponseOptions.fromJson(j['response'] as Map<String, dynamic>),
      );

  /* ---------- data ---------- */
  final String? eventId;
  final RealtimeResponseOptions response;

  /* ---------- serialise ---------- */
  @override
  Map<String, dynamic> toJson() => {
        'type': type, // "response.create"
        if (eventId != null) 'event_id': eventId,
        'response': response.toJson(),
      };
}

class RealtimeResponseStatusDetailsError {
  const RealtimeResponseStatusDetailsError({this.type, this.code});

  factory RealtimeResponseStatusDetailsError.fromJson(Map<String, dynamic> json) {
    return RealtimeResponseStatusDetailsError(
      type: json['type'] as String?,
      code: json['code'] as String?,
    );
  }

  final String? type;
  final String? code;

  Map<String, dynamic> toJson() => {
        if (type != null) 'type': type,
        if (code != null) 'code': code,
      };
}

class RealtimeResponseStatusDetails {
  const RealtimeResponseStatusDetails({this.type, this.reason, this.error});

  factory RealtimeResponseStatusDetails.fromJson(Map<String, dynamic> json) {
    return RealtimeResponseStatusDetails(
      type: json['type'] as String?,
      reason: json['reason'] as String?,
      error: json['error'] == null ? null : RealtimeResponseStatusDetailsError.fromJson(json['error']),
    );
  }

  final String? type;
  final String? reason;
  final RealtimeResponseStatusDetailsError? error;

  Map<String, dynamic> toJson() => {
        if (type != null) 'type': type,
        if (reason != null) 'reason': reason,
        if (error != null) 'error': error!.toJson(),
      };
}

class RealtimeResponse {
  const RealtimeResponse({
    required this.id,
    required this.object,
    this.status,
    this.statusDetails,
    this.output,
    this.metadata,
    this.audio,
    this.usage,
    this.conversationId,
    this.outputModalities,
    this.maxOutputTokens,
  });

  factory RealtimeResponse.fromJson(Map<String, dynamic> json) {
    return RealtimeResponse(
      id: json['id'] as String,
      object: json['object'] as String,
      status: json['status'] as String?,
      statusDetails: json['status_details'] == null ? null : RealtimeResponseStatusDetails.fromJson(json['status_details']),
      output: (json['output'] as List?)?.map((item) => RealtimeConversationItem.fromJson(item)).toList(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      audio: json['audio'] == null ? null : ResponseAudioOptions.fromJson(json['audio']),
      usage: json['usage'] == null ? null : Usage.fromJson(json['usage']),
      conversationId: json['conversation_id'] as String?,
      outputModalities: (json['output_modalities'] as List?)?.map((m) => Modality.fromJson(m)).toList(),
      maxOutputTokens: json['max_output_tokens'],
    );
  }

  final String id;
  final String object;
  final String? status;
  final RealtimeResponseStatusDetails? statusDetails;
  final List<RealtimeConversationItem>? output;
  final Map<String, dynamic>? metadata;
  final ResponseAudioOptions? audio;
  final Usage? usage;
  final String? conversationId;
  final List<Modality>? outputModalities;
  final dynamic maxOutputTokens;

  Map<String, dynamic> toJson() => {
        'id': id,
        'object': object,
        if (status != null) 'status': status,
        if (statusDetails != null) 'status_details': statusDetails!.toJson(),
        if (output != null) 'output': output!.map((item) => item.toJson()).toList(),
        if (metadata != null) 'metadata': metadata,
        if (audio != null) 'audio': audio!.toJson(),
        if (usage != null) 'usage': usage!.toJson(),
        if (conversationId != null) 'conversation_id': conversationId,
        if (outputModalities != null) 'output_modalities': outputModalities!.map((m) => m.toJson()).toList(),
        if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
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
class RealtimeErrorEvent extends RealtimeEvent {
  RealtimeErrorEvent({
    required this.eventId, // server-side event id
    required this.error, // detailed error info
  }) : super('error');

  /* factory (JSON → object) */
  factory RealtimeErrorEvent.fromJson(Map<String, dynamic> j) => RealtimeErrorEvent(
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
/*  “conversation.item.added – server → client                            */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemAddedEvent extends RealtimeEvent {
  ConversationItemAddedEvent({
    required this.eventId,
    required this.item,
    this.previousItemId,
  }) : super('conversation.item.created');

  factory ConversationItemAddedEvent.fromJson(Map<String, dynamic> j) => ConversationItemAddedEvent(
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
/*  “conversation.item.done – server → client                            */
/* ────────────────────────────────────────────────────────────────────────── */

class ConversationItemDoneEvent extends RealtimeEvent {
  ConversationItemDoneEvent({
    required this.eventId,
    required this.item,
    this.previousItemId,
  }) : super('conversation.item.done');

  factory ConversationItemDoneEvent.fromJson(Map<String, dynamic> j) => ConversationItemDoneEvent(
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
        'type': type, // "response.created"
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
        response: RealtimeResponseOptions.fromJson(j['response'] as Map<String, dynamic>),
      );

  /* ---------- data ---------- */
  final String? eventId;
  final RealtimeResponseOptions response;

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
        'type': type, // "response.done"
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

/* ─── content type for assistant-audio ─────────────────────────────── */

class RealtimeOutputAudio extends RealtimeMessageContent {
  RealtimeOutputAudio({required this.audioB64, this.transcript, String type = "output_audio"}) : super(type);

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

/// Result of POST /v1/realtime/client_secrets
class CreateRealtimeClientSecretResponse {
  CreateRealtimeClientSecretResponse({
    required this.value, // "ek_abc123"
    required this.expiresAt, // epoch-seconds
    required this.session, // effective session object
  });

  final String value;
  final int expiresAt;
  final RealtimeSession session;

  factory CreateRealtimeClientSecretResponse.fromJson(Map<String, dynamic> j) {
    // Be lenient: support both top-level {value, expires_at} and nested {client_secret:{…}}
    final String? value = (j['value'] as String?) ?? (j['client_secret'] is Map ? (j['client_secret']['value'] as String?) : null);
    final int? expiresAt = (j['expires_at'] as int?) ?? (j['client_secret'] is Map ? (j['client_secret']['expires_at'] as int?) : null);

    if (value == null || expiresAt == null) {
      throw FormatException('Unexpected client secret response: missing value/expires_at.');
    }
    final sessionJson = j['session'];
    if (sessionJson is! Map<String, dynamic>) {
      throw FormatException('Unexpected client secret response: missing session.');
    }

    return CreateRealtimeClientSecretResponse(
      value: value,
      expiresAt: expiresAt,
      session: RealtimeSession.fromJson(sessionJson),
    );
  }

  Map<String, dynamic> toJson() => {'value': value, 'expires_at': expiresAt, 'session': session.toJson()};
}

// ── Session base & concrete shapes ───────────────────────────────────────
abstract class BaseRealtimeSession {
  const BaseRealtimeSession({
    required this.id,
    required this.object,
    this.model,
    this.instructions,
    this.tools,
    this.toolChoice,
    this.temperature,
    this.tracing,
  });

  final String? id;
  final String? object; // realtime.session | realtime.transcription_session
  final RealtimeModel? model;

  final String? instructions;

  final List<RealtimeFunctionTool>? tools;
  final ToolChoice? toolChoice;
  final Tracing? tracing;

  final num? temperature;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (object != null) 'object': object,
        if (model != null) 'model': model?.toJson(),
        if (instructions != null) 'instructions': instructions,
        'tools': tools?.map((t) => t.toJson()).toList(),
        if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
        if (temperature != null) 'temperature': temperature,
        if (tracing != null) 'tracing': tracing?.toJson(),
      };
}

/// Full assistant session (speech + text etc.)
class RealtimeSession extends BaseRealtimeSession {
  RealtimeSession({
    super.id,
    super.model,
    this.outputModalities,
    this.audio,
    super.instructions,
    super.tools,
    super.toolChoice,
    super.temperature,
    this.maxOutputTokens,
    super.tracing,
    this.truncation,
    this.prompt,
  }) : super(object: 'realtime.session');

  final dynamic maxOutputTokens;

  final List<Modality>? outputModalities;
  final RealtimeSessionAudio? audio;
  final RealtimeTruncation? truncation;
  final Prompt? prompt;

  RealtimeSession copyWith({
    String? id,
    String? object,
    List<Modality>? outputModalities,
    RealtimeModel? model,
    RealtimeSessionAudio? audio,
    String? instructions,
    List<RealtimeFunctionTool>? tools,
    ToolChoice? toolChoice,
    num? temperature,
    dynamic maxOutputTokens,
    Tracing? tracing,
    RealtimeTruncation? truncation,
    Prompt? prompt,
  }) {
    return RealtimeSession(
      id: id ?? this.id,
      outputModalities: outputModalities ?? this.outputModalities,
      instructions: instructions ?? this.instructions,
      audio: audio ?? this.audio,
      tools: tools ?? this.tools,
      toolChoice: toolChoice ?? this.toolChoice,
      temperature: temperature ?? this.temperature,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      tracing: tracing ?? this.tracing,
      truncation: truncation ?? this.truncation,
      prompt: prompt ?? this.prompt,
    );
  }

  factory RealtimeSession.fromJson(Map<String, dynamic> j) => RealtimeSession(
        id: j['id'],
        model: j["model"] == null ? null : RealtimeModel.fromJson(j['model']),
        outputModalities:
            j["output_modalities"] == null ? null : (j['output_modalities'] as List).map((m) => Modality.fromJson(m)).toList(),
        audio: j["audio"] == null ? null : RealtimeSessionAudio.fromJson(j['audio']),
        instructions: j['instructions'],
        tools: j["tools"] == null ? null : (j['tools'] as List).cast<Map<String, dynamic>>().map(RealtimeFunctionTool.fromJson).toList(),
        toolChoice: j["tool_choice"] == null
            ? null
            : j['tool_choice'] == null
                ? null
                : ToolChoice.fromJson(j['tool_choice']),
        temperature: j["temperature"] == null ? null : (j['temperature'] as num?)?.toDouble(),
        maxOutputTokens: j["max_output_tokens"] == null ? null : j['max_output_tokens'],
        tracing: j['tracing'] == null ? null : Tracing.fromJson(j['tracing']),
        truncation: j['truncation'] == null ? null : RealtimeTruncation.fromJson(j['truncation']),
        prompt: j['prompt'] == null ? null : Prompt.fromJson(j['prompt']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
      if (outputModalities != null) "output_modalities": outputModalities!.map((e) => e.toJson()).toList(),
      if (truncation != null) 'truncation': truncation!.toJson(),
      if (prompt != null) 'prompt': prompt!.toJson(),
    });
}

class RealtimeSessionAudio {
  RealtimeSessionAudio({this.input, this.output});

  final RealtimeSessionAudioInput? input;
  final RealtimeSessionAudioOutput? output;

  static RealtimeSessionAudio fromJson(Map<String, dynamic> j) {
    return RealtimeSessionAudio(
      input: j['input'] == null ? null : RealtimeSessionAudioInput.fromJson(j['input']),
      output: j['output'] == null ? null : RealtimeSessionAudioOutput.fromJson(j['output']),
    );
  }

  Map<String, dynamic> toJson() {
    return {if (input != null) "input": input?.toJson(), if (output != null) "output": output?.toJson()};
  }
}

class RealtimeSessionAudioInput {
  RealtimeSessionAudioInput({this.format, this.noiseReduction, this.transcription, this.turnDetection});

  final AudioFormat? format;
  final NoiseReduction? noiseReduction;
  final InputAudioTranscription? transcription;
  final TurnDetection? turnDetection;

  Map<String, dynamic> toJson() {
    return {
      if (format != null) "format": format?.toJson(),
      if (noiseReduction != null) "noise_reduction": noiseReduction?.toJson(),
      if (transcription != null) "transcription": transcription?.toJson(),
      if (turnDetection != null) "turn_detection": turnDetection?.toJson(),
    };
  }

  static RealtimeSessionAudioInput fromJson(Map<String, dynamic> j) {
    return RealtimeSessionAudioInput(
      format: j['format'] == null ? null : AudioFormat.fromJson(j['format']),
      noiseReduction: j['noise_reduction'] == null ? null : NoiseReduction.fromJson(j['noise_reduction']),
      turnDetection: j['turn_detection'] == null ? null : TurnDetection.fromJson(j['turn_detection']),
      transcription: j['transcription'] == null ? null : InputAudioTranscription.fromJson(j['input_audio_transcription']),
    );
  }
}

class RealtimeSessionAudioOutput {
  const RealtimeSessionAudioOutput({this.format, this.speed, this.voice});

  final AudioFormat? format;
  final double? speed;
  final SpeechVoice? voice;

  Map<String, dynamic> toJson() {
    return {
      if (format != null) "format": format?.toJson(),
      if (speed != null) "speed": speed,
      if (voice != null) "voice": voice?.toJson(),
    };
  }

  static RealtimeSessionAudioOutput fromJson(Map<String, dynamic> j) {
    return RealtimeSessionAudioOutput(
      voice: j['voice'] == null ? null : SpeechVoice.fromJson(j['voice']),
      format: j['format'] == null ? null : AudioFormat.fromJson(j['format']),
      speed: (j['speed'] as num?)?.toDouble(),
    );
  }
}

class AudioFormat {
  const AudioFormat(this.type);

  final String type;

  Map<String, dynamic> toJson() {
    return {"type": type};
  }

  static AudioFormat fromJson(Map<String, dynamic> j) {
    return switch (j['type']) {
      'audio/pcm' => AudioFormatPcm.fromJson(j),
      'audio/pcmu' => AudioFormatPcmu(),
      'audio/pcma' => AudioFormatPcma(),
      _ => AudioFormat(j['type'])
    };
  }
}

class AudioFormatPcm extends AudioFormat {
  const AudioFormatPcm({this.rate = 24000}) : super("audio/pcm");

  final int? rate;

  @override
  Map<String, dynamic> toJson() {
    return {
      "type": type,
      if (rate != null) "rate": rate,
    };
  }

  static AudioFormatPcm fromJson(Map<String, dynamic> json) {
    return AudioFormatPcm(rate: (json['rate'] as num?)?.toInt());
  }
}

class AudioFormatPcmu extends AudioFormat {
  const AudioFormatPcmu() : super("audio/pcmu");
}

class AudioFormatPcma extends AudioFormat {
  const AudioFormatPcma() : super("audio/pcma");
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  MCP response-call events                                                 */
/*  - response.mcp_call_arguments.delta                                      */
/*  - response.mcp_call_arguments.done                                       */
/*  - response.mcp_call.in_progress|completed|failed                         */
/* ────────────────────────────────────────────────────────────────────────── */

/// Server → client: incremental JSON-string fragment of MCP tool-call args.
class RealtimeResponseMcpCallArgumentsDeltaEvent extends RealtimeEvent {
  RealtimeResponseMcpCallArgumentsDeltaEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.delta,
    this.obfuscation,
  }) : super('response.mcp_call_arguments.delta');

  factory RealtimeResponseMcpCallArgumentsDeltaEvent.fromJson(Map<String, dynamic> j) {
    return RealtimeResponseMcpCallArgumentsDeltaEvent(
      eventId: j['event_id'] as String,
      responseId: j['response_id'] as String,
      itemId: j['item_id'] as String,
      outputIndex: j['output_index'] as int,
      delta: j['delta'] as String,
      obfuscation: j['obfuscation'] as String?,
    );
  }

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;
  final String delta;

  /// If present, indicates the delta text was obfuscated.
  final String? obfuscation;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'delta': delta,
        if (obfuscation != null) 'obfuscation': obfuscation,
      };
}

/// Server → client: final JSON-encoded arguments for the MCP tool call.
class RealtimeResponseMcpCallArgumentsDoneEvent extends RealtimeEvent {
  RealtimeResponseMcpCallArgumentsDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.argumentsJson,
  }) : super('response.mcp_call_arguments.done');

  factory RealtimeResponseMcpCallArgumentsDoneEvent.fromJson(Map<String, dynamic> j) {
    return RealtimeResponseMcpCallArgumentsDoneEvent(
      eventId: j['event_id'] as String,
      responseId: j['response_id'] as String,
      itemId: j['item_id'] as String,
      outputIndex: j['output_index'] as int,
      argumentsJson: j['arguments'] as String,
    );
  }

  final String eventId;
  final String responseId;
  final String itemId;
  final int outputIndex;

  /// Final JSON-encoded arguments string.
  final String argumentsJson;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'response_id': responseId,
        'item_id': itemId,
        'output_index': outputIndex,
        'arguments': argumentsJson,
      };
}

/// Server → client: MCP tool call has started and is in progress.
class RealtimeResponseMcpCallInProgressEvent extends RealtimeEvent {
  RealtimeResponseMcpCallInProgressEvent({
    required this.eventId,
    required this.itemId,
    required this.outputIndex,
  }) : super('response.mcp_call.in_progress');

  factory RealtimeResponseMcpCallInProgressEvent.fromJson(Map<String, dynamic> j) {
    return RealtimeResponseMcpCallInProgressEvent(
      eventId: j['event_id'] as String,
      itemId: j['item_id'] as String,
      outputIndex: j['output_index'] as int,
    );
  }

  final String eventId;
  final String itemId;
  final int outputIndex;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        'output_index': outputIndex,
      };
}

/// Server → client: MCP tool call completed successfully.
class RealtimeResponseMcpCallCompletedEvent extends RealtimeEvent {
  RealtimeResponseMcpCallCompletedEvent({
    required this.eventId,
    required this.itemId,
    required this.outputIndex,
  }) : super('response.mcp_call.completed');

  factory RealtimeResponseMcpCallCompletedEvent.fromJson(Map<String, dynamic> j) {
    return RealtimeResponseMcpCallCompletedEvent(
      eventId: j['event_id'] as String,
      itemId: j['item_id'] as String,
      outputIndex: j['output_index'] as int,
    );
  }

  final String eventId;
  final String itemId;
  final int outputIndex;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        'output_index': outputIndex,
      };
}

/// Server → client: MCP tool call failed.
class RealtimeResponseMcpCallFailedEvent extends RealtimeEvent {
  RealtimeResponseMcpCallFailedEvent({
    required this.eventId,
    required this.itemId,
    required this.outputIndex,
  }) : super('response.mcp_call.failed');

  factory RealtimeResponseMcpCallFailedEvent.fromJson(Map<String, dynamic> j) {
    return RealtimeResponseMcpCallFailedEvent(
      eventId: j['event_id'] as String,
      itemId: j['item_id'] as String,
      outputIndex: j['output_index'] as int,
    );
  }

  final String eventId;
  final String itemId;
  final int outputIndex;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'event_id': eventId,
        'item_id': itemId,
        'output_index': outputIndex,
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  MCP tools listing lifecycle                                              */
/*  - mcp_list_tools.in_progress|completed|failed                            */
/* ────────────────────────────────────────────────────────────────────────── */

/// Server → client: listing MCP tools is in progress for an item.
class McpListToolsInProgressEvent extends RealtimeEvent {
  McpListToolsInProgressEvent({
    required this.eventId,
    required this.itemId,
  }) : super('mcp_list_tools.in_progress');

  factory McpListToolsInProgressEvent.fromJson(Map<String, dynamic> j) => McpListToolsInProgressEvent(
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

/// Server → client: listing MCP tools completed for an item.
class McpListToolsCompletedEvent extends RealtimeEvent {
  McpListToolsCompletedEvent({
    required this.eventId,
    required this.itemId,
  }) : super('mcp_list_tools.completed');

  factory McpListToolsCompletedEvent.fromJson(Map<String, dynamic> j) => McpListToolsCompletedEvent(
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

/// Server → client: listing MCP tools failed for an item.
class McpListToolsFailedEvent extends RealtimeEvent {
  McpListToolsFailedEvent({
    required this.eventId,
    required this.itemId,
  }) : super('mcp_list_tools.failed');

  factory McpListToolsFailedEvent.fromJson(Map<String, dynamic> j) => McpListToolsFailedEvent(
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
/*  “response.output_text.delta” – server event                               */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseOutputTextDeltaEvent extends RealtimeEvent {
  RealtimeResponseOutputTextDeltaEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
  }) : super('response.output_text.delta');

  factory RealtimeResponseOutputTextDeltaEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseOutputTextDeltaEvent(
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
/*  “response.output_text.done” – server event                                */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseOutputTextDoneEvent extends RealtimeEvent {
  RealtimeResponseOutputTextDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.text,
  }) : super('response.output_text.done');

  factory RealtimeResponseOutputTextDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseOutputTextDoneEvent(
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
/*  “response.output_audio_transcript.delta” – server event                   */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseOutputAudioTranscriptDeltaEvent extends RealtimeEvent {
  RealtimeResponseOutputAudioTranscriptDeltaEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
  }) : super('response.output_audio_transcript.delta');

  factory RealtimeResponseOutputAudioTranscriptDeltaEvent.fromJson(Map<String, dynamic> j) =>
      RealtimeResponseOutputAudioTranscriptDeltaEvent(
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
/*  “response.output_audio_transcript.done” – server event                    */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseOutputAudioTranscriptDoneEvent extends RealtimeEvent {
  RealtimeResponseOutputAudioTranscriptDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.transcript,
  }) : super('response.output_audio_transcript.done');

  factory RealtimeResponseOutputAudioTranscriptDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseOutputAudioTranscriptDoneEvent(
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
/*  “response.output_audio.delta” – server event                              */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseOutputAudioDeltaEvent extends RealtimeEvent {
  RealtimeResponseOutputAudioDeltaEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
    required this.delta,
  }) : super('response.output_audio.delta');

  factory RealtimeResponseOutputAudioDeltaEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseOutputAudioDeltaEvent(
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
  final String delta; // base64-encoded audio data delta

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
/*  “response.output_audio.done” – server event                               */
/* ────────────────────────────────────────────────────────────────────────── */

class RealtimeResponseOutputAudioDoneEvent extends RealtimeEvent {
  RealtimeResponseOutputAudioDoneEvent({
    required this.eventId,
    required this.responseId,
    required this.itemId,
    required this.outputIndex,
    required this.contentIndex,
  }) : super('response.output_audio.done');

  factory RealtimeResponseOutputAudioDoneEvent.fromJson(Map<String, dynamic> j) => RealtimeResponseOutputAudioDoneEvent(
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
