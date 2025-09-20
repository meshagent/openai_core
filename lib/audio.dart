import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import 'common.dart';
import 'exceptions.dart';
import 'openai_client.dart';
import 'sse_client.dart';

extension AudioAPI on OpenAIClient {
  /// Generates TTS audio from text (`/audio/speech`).
  ///
  /// ```dart
  /// final bytes = await client.createSpeech(
  ///   input: 'Hello world',
  ///   model: 'gpt-4o-mini-tts',
  ///   voice: 'nova',
  ///   responseFormat: 'mp3',
  /// );
  /// await File('hello.mp3').writeAsBytes(bytes);
  /// ```
  ///
  /// Throws [OpenAIRequestException] on HTTP ≠ 200.
  Future<Uint8List> createSpeech({
    /// The text to convert (≤ 4096 chars).
    required String input,

    /// TTS model: `tts-1`, `tts-1-hd`, `gpt-4o-mini-tts`, …
    required SpeechModel model,

    /// Voice name: alloy, ash, ballad, coral, echo, fable, onyx,
    /// nova, sage, shimmer, verse.
    required SpeechVoice voice,

    /// Extra voice instructions (ignored by tts-1 / tts-1-hd).
    String? instructions,

    /// Audio container: mp3 (default), opus, aac, flac, wav, pcm.
    SpeechResponseFormat? responseFormat,

    /// Playback speed 0.25 – 4.0 (default = 1.0).
    num? speed,

    /// Streaming container: audio (default) or sse.
    /// **Note:** `sse` is *not* supported by tts-1 / tts-1-hd.
    String? streamFormat,
  }) async {
    final resp = await postJson('/audio/speech', {
      'input': input,
      'model': model.toJson(),
      'voice': voice.toJson(),
      if (instructions != null) 'instructions': instructions,
      if (responseFormat != null) 'response_format': responseFormat.toJson(),
      if (speed != null) 'speed': speed,
      if (streamFormat != null) 'stream_format': streamFormat,
    });

    if (resp.statusCode == 200) {
      // The endpoint returns audio bytes with a Content-Type like audio/mpeg.
      return resp.bodyBytes;
    } else {
      // Let your existing error helper turn the HTTP response
      // into a typed OpenAIRequestException.
      throw OpenAIRequestException.fromHttpResponse(resp);
    }
  }

  /// Create TTS *and* stream it back chunk-by-chunk as SSE.
  ///
  /// ```dart
  /// final stream = await client.streamSpeech(
  ///   input: 'Hello there!',
  ///   model: 'gpt-4o-mini-tts',
  ///   voice: 'nova',
  ///   responseFormat: 'mp3',
  /// );
  ///
  /// await for (final ev in stream.events) {
  ///   switch (ev) {
  ///     case SpeechAudioDelta():
  ///       audioSink.add(ev.audioBytes);                // play or save
  ///     case SpeechAudioDone():
  ///       print('done: ${ev.usage}');
  ///   }
  /// }
  /// ```
  Future<SpeechStream> streamSpeechEvents({
    required String input,
    required SpeechModel model,
    required SpeechVoice voice,
    String? instructions,
    SpeechResponseFormat? responseFormat, // mp3 (default), opus, aac, flac, wav, pcm
    num? speed, // 0.25 – 4.0   (default 1.0)
    /// Leave as `"sse"` (the default here) unless you want raw audio frames.
    String streamFormat = 'sse',

    /// To receive `transcript.*` events include `"logprobs"` here.
    List<String>? include,
  }) async {
    final sse = streamJson('/audio/speech', {
      'stream': true, // tells the endpoint we want SSE
      'input': input,
      'model': model.toJson(),
      'voice': voice.toJson(),
      if (instructions != null) 'instructions': instructions,
      if (responseFormat != null) 'response_format': responseFormat.toJson(),
      if (speed != null) 'speed': speed,
      'stream_format': streamFormat, // default here = "sse"
      if (include != null) 'include': include,
    });

    return SpeechStream(sse);
  }

  Future<Stream<List<int>>> streamSpeechData({
    required String input,
    required SpeechModel model,
    required SpeechVoice voice,
    String? instructions,
    SpeechResponseFormat? responseFormat, // mp3 (default), opus, aac, flac, wav, pcm
    num? speed, // 0.25 – 4.0   (default 1.0)
    /// Leave as `"sse"` (the default here) unless you want raw audio frames.
    String streamFormat = 'sse',

    /// To receive `transcript.*` events include `"logprobs"` here.
    List<String>? include,
  }) async {
    return await streamJsonData('/audio/speech', {
      'stream': true, // tells the endpoint we want SSE
      'input': input,
      'model': model.toJson(),
      'voice': voice.toJson(),
      if (instructions != null) 'instructions': instructions,
      if (responseFormat != null) 'response_format': responseFormat.toJson(),
      if (speed != null) 'speed': speed,
      'stream_format': "audio", // default here = "sse"
      if (include != null) 'include': include,
    });
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*   /audio/transcriptions  –  Sync + Streaming helpers                      */
/* ────────────────────────────────────────────────────────────────────────── */

extension TranscriptionAPI on OpenAIClient {
  /* ── Non-streaming helper ─────────────────────────────────────────────── */

  /// Transcribe an audio file (blocking).
  ///
  /// ```dart
  /// final result = await client.createTranscription(
  ///   fileBytes: await File('speech.mp3').readAsBytes(),
  ///   filename: 'speech.mp3',
  ///   model: 'gpt-4o-mini-transcribe',
  ///   language: 'en',
  /// );
  ///
  /// print(result.text);                 // full transcript
  /// ```
  Future<TranscriptionResult> createTranscription({
    required Uint8List fileBytes,
    required String filename,
    required AudioModel model, // whisper-1, gpt-4o-transcribe…
    String? chunkingStrategy, // 'auto' | JSON string
    List<String>? include, // e.g. ['logprobs']
    String? language, // ISO-639-1
    String? prompt,
    AudioResponseFormat responseFormat = AudioResponseFormat.json, // json, text, srt, vtt, …
    num? temperature,
    List<String>? timestampGranularities, // ['word', 'segment']
  }) async {
    final url = baseUrl.resolve('audio/transcriptions');

    final req = http.MultipartRequest('POST', url)
      ..headers.addAll(getHeaders({}) ?? {})
      // – core fields –
      ..fields['model'] = model.toJson()
      ..fields['response_format'] = responseFormat.toJson()
      // – optional –
      .._maybeField('chunking_strategy', chunkingStrategy)
      .._maybeField('language', language)
      .._maybeField('prompt', prompt)
      .._maybeField('temperature', temperature?.toString())
      .._maybeJsonField('timestamp_granularities[]', timestampGranularities)
      .._maybeJsonField('include[]', include)
      // – audio file –
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
      ));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode == 200) {
      return TranscriptionResult.fromResponseBody(resp.body, responseFormat.toJson());
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /* ── Streaming helper (SSE) ───────────────────────────────────────────── */

  /// Transcribe an audio file and **stream** text deltas as SSE.
  ///
  /// Only supported by *gpt-4o-transcribe* and *gpt-4o-mini-transcribe* models.
  Future<TranscriptionStream> streamTranscription({
    required Uint8List fileBytes,
    required String filename,
    required AudioModel model,
    String? chunkingStrategy,
    List<String>? include,
    String? language,
    String? prompt,
    // Response format must be json for streaming models.
    AudioResponseFormat responseFormat = AudioResponseFormat.json,
    num? temperature,
    List<String>? timestampGranularities,
  }) async {
    final boundary = '----dart-openai-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

    // Build the multipart/form-data body manually so we can feed it to SseClient.
    final body = _buildMultipartBody(
      boundary: boundary,
      fileField: 'file',
      filename: filename,
      fileBytes: fileBytes,
      fields: {
        'model': model.toJson(),
        'stream': 'true',
        'response_format': responseFormat.toJson(),
        if (chunkingStrategy != null) 'chunking_strategy': chunkingStrategy,
        if (language != null) 'language': language,
        if (prompt != null) 'prompt': prompt,
        if (temperature != null) 'temperature': temperature.toString(),
        if (include != null)
          for (final i in include) 'include[]': i,
        if (timestampGranularities != null)
          for (final t in timestampGranularities) 'timestamp_granularities[]': t,
      },
    );

    final sse = SseClient(
      baseUrl.resolve('audio/transcriptions'),
      headers: getHeaders({
        'Content-Type': 'multipart/form-data; boundary=$boundary',
      }),
      httpClient: httpClient,
      body: body,
    );

    return TranscriptionStream(sse);
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Result wrapper (non-streaming)                                           */
/* ────────────────────────────────────────────────────────────────────────── */

class TranscriptionResult {
  const TranscriptionResult._({this.text, this.json});

  factory TranscriptionResult.fromResponseBody(String body, String responseFormat) {
    switch (responseFormat) {
      case 'json':
      case 'verbose_json':
        return TranscriptionResult._(
          json: jsonDecode(body) as Map<String, dynamic>,
        );
      default: // text, srt, vtt …
        return TranscriptionResult._(text: body);
    }
  }

  /// Present when `response_format` was *text, srt, vtt* …
  final String? text;

  /// Present when `response_format` was *json* or *verbose_json*.
  final Map<String, dynamic>? json;

  @override
  String toString() => text ?? jsonEncode(json);
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Streaming wrapper                                                        */
/* ────────────────────────────────────────────────────────────────────────── */

class TranscriptionStream {
  TranscriptionStream(this._client) {
    events = _client.stream.map((e) {
      final json = jsonDecode(e.data) as Map<String, dynamic>;
      return TranscriptEvent.fromJson(json); // cast helper
    });

    // Close when the terminal event arrives.
    events.where((ev) => ev is TranscriptTextDone).map(
          (_) async => await close(),
        );
  }

  late final Stream<TranscriptEvent> events; // only the transcript events
  final SseClient _client;

  Future<void> close() => _client.close();
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Minor helpers                                                            */
/* ────────────────────────────────────────────────────────────────────────── */

extension _MultipartFieldHelpers on http.MultipartRequest {
  void _maybeField(String name, String? value) {
    if (value != null) fields[name] = value;
  }

  // Encodes arrays as multiple fields with the trailing [] convention.
  void _maybeJsonField(String name, List<String>? values) {
    if (values == null) return;
    for (final v in values) fields[name] = v;
  }
}

/// Build a simple multipart/form-data body as bytes.
///
/// We do it by hand so we can feed the result to `SseClient`.
Uint8List _buildMultipartBody({
  required String boundary,
  required String fileField,
  required String filename,
  required Uint8List fileBytes,
  required Map<String, String> fields,
}) {
  final crlf = '\r\n';
  final buffer = BytesBuilder();

  // Regular fields
  fields.forEach((name, value) {
    buffer
      ..add(utf8.encode('--$boundary$crlf'))
      ..add(utf8.encode('Content-Disposition: form-data; name="$name"$crlf$crlf$value$crlf'));
  });

  // The audio file
  buffer
    ..add(utf8.encode('--$boundary$crlf'))
    ..add(utf8.encode('Content-Disposition: form-data; name="$fileField"; filename="$filename"$crlf'))
    ..add(utf8.encode('Content-Type: application/octet-stream$crlf$crlf'))
    ..add(fileBytes)
    ..add(utf8.encode(crlf));

  // Closing boundary
  buffer.add(utf8.encode('--$boundary--$crlf'));

  return buffer.toBytes();
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Streaming wrapper                                                        */
/* ────────────────────────────────────────────────────────────────────────── */

class SpeechStream {
  SpeechStream(this._client) {
    events = _client.stream.map((sse) {
      final json = jsonDecode(sse.data) as Map<String, dynamic>;
      return SpeechEvent.fromJson(json);
    });

    // Auto-close once we see the terminal event.
    events.where((e) => e is SpeechAudioDone || e is TranscriptTextDone).map((_) async => await close());
  }

  late final Stream<SpeechEvent> events;
  final SseClient _client;

  Future<void> close() => _client.close();
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Event model                                                              */
/* ────────────────────────────────────────────────────────────────────────── */

abstract class SpeechEvent {
  const SpeechEvent(this.type);
  final String type;

  Map<String, dynamic> toJson();

  factory SpeechEvent.fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'speech.audio.delta':
        return SpeechAudioDelta.fromJson(j);
      case 'speech.audio.done':
        return SpeechAudioDone.fromJson(j);
      default:
        throw ArgumentError('Unknown speech event type "${j['type']}"');
    }
  }
}

abstract class TranscriptEvent {
  const TranscriptEvent(this.type);
  final String type;

  Map<String, dynamic> toJson();

  factory TranscriptEvent.fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'transcript.text.delta':
        return TranscriptTextDelta.fromJson(j);
      case 'transcript.text.done':
        return TranscriptTextDone.fromJson(j);
      default:
        throw ArgumentError('Unknown speech event type "${j['type']}"');
    }
  }
}

/* ── Audio events ───────────────────────────────────────────────────────── */

class SpeechAudioDelta extends SpeechEvent {
  SpeechAudioDelta(this.audioB64)
      : audioBytes = base64Decode(audioB64),
        super('speech.audio.delta');

  factory SpeechAudioDelta.fromJson(Map<String, dynamic> j) => SpeechAudioDelta(j['audio'] as String);

  /// Raw base-64 (if you want to forward it unchanged).
  final String audioB64;

  /// Decoded audio bytes — ready for playback or saving.
  final Uint8List audioBytes;

  @override
  Map<String, dynamic> toJson() => {'type': type, 'audio': audioB64};
}

class SpeechAudioDone extends SpeechEvent {
  SpeechAudioDone({this.usage}) : super('speech.audio.done');

  factory SpeechAudioDone.fromJson(Map<String, dynamic> j) => SpeechAudioDone(
        usage: j['usage'] == null ? null : Usage.fromJson(j['usage'] as Map<String, dynamic>),
      );

  final Usage? usage;

  @override
  Map<String, dynamic> toJson() => {'type': type, if (usage != null) 'usage': usage!.toJson()};
}

/* ── Transcription events (optional) ────────────────────────────────────── */

class TranscriptTextDelta extends TranscriptEvent {
  TranscriptTextDelta({
    required this.delta,
    this.logprobs,
  }) : super('transcript.text.delta');

  factory TranscriptTextDelta.fromJson(Map<String, dynamic> j) => TranscriptTextDelta(
        delta: j['delta'] as String,
        logprobs: j['logprobs'] == null ? null : (j['logprobs'] as List?)?.cast<Map<String, dynamic>>().map(LogProb.fromJson).toList(),
      );

  final String delta;
  final List<LogProb>? logprobs;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'delta': delta,
        if (logprobs != null) 'logprobs': logprobs!.map((p) => p.toJson()).toList(),
      };
}

class TranscriptTextDone extends TranscriptEvent {
  TranscriptTextDone({
    required this.text,
    this.logprobs,
    this.usage,
  }) : super('transcript.text.done');

  factory TranscriptTextDone.fromJson(Map<String, dynamic> j) => TranscriptTextDone(
        text: j['text'] as String,
        logprobs: (j['logprobs'] as List?)?.cast<Map<String, dynamic>>().map(LogProb.fromJson).toList(),
        usage: j['usage'] == null ? null : Usage.fromJson(j['usage'] as Map<String, dynamic>),
      );

  final String text;
  final List<LogProb>? logprobs;
  final Usage? usage;

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'text': text,
        if (logprobs != null) 'logprobs': logprobs!.map((p) => p.toJson()).toList(),
        if (usage != null) 'usage': usage!.toJson(),
      };
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Audio transcription                                                       */
/* ────────────────────────────────────────────────────────────────────────── */

class AudioModel extends JsonEnum {
  static const whisper1 = AudioModel('whisper-1');
  static const gpt4oTranscribe = AudioModel('gpt-4o-transcribe');
  static const gpt4oMiniTranscribe = AudioModel('gpt-4o-mini-transcribe');

  const AudioModel(super.value);

  static AudioModel fromJson(String raw) => AudioModel(raw);
}
/* ────────────────────────────────────────────────────────────────────────── */
/*  AudioResponseFormat enum                                                 */
/* ────────────────────────────────────────────────────────────────────────── */

class AudioResponseFormat extends JsonEnum {
  static const json = AudioResponseFormat('json');
  static const text = AudioResponseFormat('text');
  static const srt = AudioResponseFormat('srt');
  static const verboseJson = AudioResponseFormat('verbose_json');
  static const vtt = AudioResponseFormat('vtt');

  const AudioResponseFormat(super.value);

  static AudioResponseFormat fromJson(String raw) => AudioResponseFormat(raw);
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Speech (TTS) models                                                      */
/* ────────────────────────────────────────────────────────────────────────── */

class SpeechModel extends JsonEnum {
  static const tts1 = SpeechModel('tts-1');
  static const tts1Hd = SpeechModel('tts-1-hd');
  static const gpt4oMiniTts = SpeechModel('gpt-4o-mini-tts');

  const SpeechModel(super.value);

  static SpeechModel fromJson(String raw) => SpeechModel(raw);
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  TTS voices & response-format enums                                       */
/* ────────────────────────────────────────────────────────────────────────── */

/// Built-in voice presets (TTS).
///
/// If OpenAI introduces additional voices later, callers can still pass a
/// plain `String` in the `voice:` parameter, but these enum values give you
/// compile-time safety for the known set.
class SpeechVoice extends JsonEnum {
  static const alloy = SpeechVoice('alloy');
  static const ash = SpeechVoice('ash');
  static const ballad = SpeechVoice('ballad');
  static const coral = SpeechVoice('coral');
  static const echo = SpeechVoice('echo');
  static const fable = SpeechVoice('fable');
  static const onyx = SpeechVoice('onyx');
  static const nova = SpeechVoice('nova');
  static const sage = SpeechVoice('sage');
  static const shimmer = SpeechVoice('shimmer');
  static const verse = SpeechVoice('verse');

  const SpeechVoice(super.value);

  static SpeechVoice fromJson(String raw) => SpeechVoice(raw);
}

/// Audio container for TTS output.
///
/// *Note:* `pcm` is typically a raw 16-bit mono stream; all others are
/// self-contained files.
class SpeechResponseFormat extends JsonEnum {
  static const mp3 = SpeechResponseFormat('mp3');
  static const opus = SpeechResponseFormat('opus');
  static const aac = SpeechResponseFormat('aac');
  static const flac = SpeechResponseFormat('flac');
  static const wav = SpeechResponseFormat('wav');
  static const pcm = SpeechResponseFormat('pcm');

  const SpeechResponseFormat(super.value);

  static SpeechResponseFormat fromJson(String raw) => SpeechResponseFormat(raw);
}
