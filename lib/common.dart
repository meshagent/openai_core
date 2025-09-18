/// Token-usage breakdown returned by the API.
class Usage {
  /// Prompt tokens counted on input.
  final int? inputTokens;

  /// Tokens generated in the output.
  final int? outputTokens;

  /// Optional fine-grained breakdown by role or stream.
  final Map<String, int>? outputTokensBreakdown;

  /// Sum of all token counts.
  final int? totalTokens;

  const Usage({
    this.inputTokens,
    this.outputTokens,
    this.outputTokensBreakdown,
    this.totalTokens,
  });

  /// Serialise to JSON.
  Map<String, dynamic> toJson() => {
        if (inputTokens != null) 'input_tokens': inputTokens,
        if (outputTokens != null) 'output_tokens': outputTokens,
        if (outputTokensBreakdown != null) 'output_tokens_breakdown': outputTokensBreakdown,
        if (totalTokens != null) 'total_tokens': totalTokens,
      };

  /// Deserialise from JSON.
  factory Usage.fromJson(Map<String, dynamic> json) => Usage(
        inputTokens: json['input_tokens'] as int?,
        outputTokens: json['output_tokens'] as int?,
        outputTokensBreakdown: (json['output_tokens_breakdown'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as int)),
        totalTokens: json['total_tokens'] as int?,
      );

  @override
  String toString() => 'Usage(inputTokens: $inputTokens, outputTokens: $outputTokens, '
      'outputTokensBreakdown: $outputTokensBreakdown, totalTokens: $totalTokens)';
}

class TopLogProb {
  const TopLogProb({
    required this.bytes,
    required this.logprob,
    required this.token,
  });

  factory TopLogProb.fromJson(Map<String, dynamic> json) => TopLogProb(
        bytes: List<int>.from(json['bytes'] as List),
        logprob: (json['logprob'] as num),
        token: json['token'] as String,
      );

  final List<int> bytes;
  final num logprob;
  final String token;

  Map<String, dynamic> toJson() => {'bytes': bytes, 'logprob': logprob, 'token': token};
}

class LogProb {
  const LogProb({
    required this.bytes,
    required this.logprob,
    required this.token,
    this.topLogprobs,
  });

  factory LogProb.fromJson(Map<String, dynamic> json) => LogProb(
        bytes: List<int>.from(json['bytes'] as List),
        logprob: (json['logprob'] as num),
        token: json['token'] as String,
        topLogprobs: (json['top_logprobs'] as List?)?.cast<Map<String, dynamic>>().map(TopLogProb.fromJson).toList(),
      );

  final List<int> bytes;
  final num logprob;
  final String token;
  final List<TopLogProb>? topLogprobs;

  Map<String, dynamic> toJson() => {
        'bytes': bytes,
        'logprob': logprob,
        'token': token,
        'top_logprobs': topLogprobs == null ? null : topLogprobs!.map((e) => e.toJson()).toList(),
      };
}

// Shared trait so we don’t repeat the same helpers.
mixin JsonEnum {
  String get value;

  String toJson() => value;

  /// Generic parse helper used by every enum’s `fromJson`.
  static T fromJson<T extends JsonEnum>(Iterable<T> values, String raw) =>
      values.firstWhere((e) => e.value == raw, orElse: () => throw ArgumentError("Unexpected enum value encountered '$raw'"));
}

enum ChatModel with JsonEnum {
  // ── gpt-5 family ───────────────────────────────────────────────────────
  gpt5('gpt-5'),
  gpt5Mini('gpt-5-mini'),
  gpt5Nano('gpt-5-nano'),
  gpt5_2025_08_07('gpt-5-2025-08-07'),
  gpt5Mini_2025_08_07('gpt-5-mini-2025-08-07'),
  gpt5Nano_2025_08_07('gpt-5-nano-2025-08-07'),

  // ── 4.1 family ─────────────────────────────────────────────────────────
  gpt4_1('gpt-4.1'),
  gpt4_1Mini('gpt-4.1-mini'),
  gpt4_1Nano('gpt-4.1-nano'),
  gpt4_1_2025_04_14('gpt-4.1-2025-04-14'),
  gpt4_1Mini_2025_04_14('gpt-4.1-mini-2025-04-14'),
  gpt4_1Nano_2025_04_14('gpt-4.1-nano-2025-04-14'),

  // ── o4 family ──────────────────────────────────────────────────────────
  o4Mini('o4-mini'),
  o4Mini_2025_04_16('o4-mini-2025-04-16'),

  // ── o3 family ──────────────────────────────────────────────────────────
  o3('o3'),
  o3_2025_04_16('o3-2025-04-16'),
  o3Mini('o3-mini'),
  o3Mini_2025_01_31('o3-mini-2025-01-31'),

  // ── o1 family ──────────────────────────────────────────────────────────
  o1('o1'),
  o1_2024_12_17('o1-2024-12-17'),
  o1Preview('o1-preview'),
  o1Preview_2024_09_12('o1-preview-2024-09-12'),
  o1Mini('o1-mini'),
  o1Mini_2024_09_12('o1-mini-2024-09-12'),

  // ── gpt-4o family ──────────────────────────────────────────────────────
  gpt4o('gpt-4o'),
  gpt4o_2024_11_20('gpt-4o-2024-11-20'),
  gpt4o_2024_08_06('gpt-4o-2024-08-06'),
  gpt4o_2024_05_13('gpt-4o-2024-05-13'),

  // audio / search previews
  gpt4oAudioPreview('gpt-4o-audio-preview'),
  gpt4oAudioPreview_2024_10_01('gpt-4o-audio-preview-2024-10-01'),
  gpt4oAudioPreview_2024_12_17('gpt-4o-audio-preview-2024-12-17'),
  gpt4oAudioPreview_2025_06_03('gpt-4o-audio-preview-2025-06-03'),
  gpt4oMiniAudioPreview('gpt-4o-mini-audio-preview'),
  gpt4oMiniAudioPreview_2024_12_17('gpt-4o-mini-audio-preview-2024-12-17'),
  gpt4oSearchPreview('gpt-4o-search-preview'),
  gpt4oMiniSearchPreview('gpt-4o-mini-search-preview'),
  gpt4oSearchPreview_2025_03_11('gpt-4o-search-preview-2025-03-11'),
  gpt4oMiniSearchPreview_2025_03_11('gpt-4o-mini-search-preview-2025-03-11'),

  // convenience alias
  chatgpt4oLatest('chatgpt-4o-latest'),
  gpt5ChatLatest('gpt-5-chat-latest'),

  // ── Codex mini ─────────────────────────────────────────────────────────
  codexMiniLatest('codex-mini-latest'),

  // ── 4o-mini mainline ───────────────────────────────────────────────────
  gpt4oMini('gpt-4o-mini'),
  gpt4oMini_2024_07_18('gpt-4o-mini-2024-07-18'),

  // ── GPT-4 Turbo / Vision / Preview line ────────────────────────────────
  gpt4Turbo('gpt-4-turbo'),
  gpt4Turbo_2024_04_09('gpt-4-turbo-2024-04-09'),
  gpt4_0125Preview('gpt-4-0125-preview'),
  gpt4TurboPreview('gpt-4-turbo-preview'),
  gpt4_1106Preview('gpt-4-1106-preview'),
  gpt4VisionPreview('gpt-4-vision-preview'),

  // ── GPT-4 (legacy) ─────────────────────────────────────────────────────
  gpt4('gpt-4'),
  gpt4_0314('gpt-4-0314'),
  gpt4_0613('gpt-4-0613'),
  gpt4_32k('gpt-4-32k'),
  gpt4_32k_0314('gpt-4-32k-0314'),
  gpt4_32k_0613('gpt-4-32k-0613'),

  // ── GPT-3.5 Turbo family ───────────────────────────────────────────────
  gpt35Turbo('gpt-3.5-turbo'),
  gpt35Turbo16k('gpt-3.5-turbo-16k'),
  gpt35Turbo_0301('gpt-3.5-turbo-0301'),
  gpt35Turbo_0613('gpt-3.5-turbo-0613'),
  gpt35Turbo_1106('gpt-3.5-turbo-1106'),
  gpt35Turbo_0125('gpt-3.5-turbo-0125'),
  gpt35Turbo16k_0613('gpt-3.5-turbo-16k-0613'),

  computerUsePreview_2025_03_11('computer-use-preview-2025-03-11'),
  computerUsePreview('computer-use-preview');

  const ChatModel(this.value);
  final String value;

  static ChatModel fromJson(String raw) => JsonEnum.fromJson(values, raw);
}
