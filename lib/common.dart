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
class JsonEnum {
  const JsonEnum(this.value);

  final String value;

  String toJson() => value;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType == runtimeType && other is JsonEnum) {
      return value == other.value;
    }
    return false;
  }

  @override
  int get hashCode => value.hashCode;
}

class ChatModel extends JsonEnum {
  // ── gpt-5 family ───────────────────────────────────────────────────────
  static const gpt5 = ChatModel('gpt-5');
  static const gpt5Mini = ChatModel('gpt-5-mini');
  static const gpt5Nano = ChatModel('gpt-5-nano');
  static const gpt5_2025_08_07 = ChatModel('gpt-5-2025-08-07');
  static const gpt5Mini_2025_08_07 = ChatModel('gpt-5-mini-2025-08-07');
  static const gpt5Nano_2025_08_07 = ChatModel('gpt-5-nano-2025-08-07');

  // ── 4.1 family ─────────────────────────────────────────────────────────
  static const gpt4_1 = ChatModel('gpt-4.1');
  static const gpt4_1Mini = ChatModel('gpt-4.1-mini');
  static const gpt4_1Nano = ChatModel('gpt-4.1-nano');
  static const gpt4_1_2025_04_14 = ChatModel('gpt-4.1-2025-04-14');
  static const gpt4_1Mini_2025_04_14 = ChatModel('gpt-4.1-mini-2025-04-14');
  static const gpt4_1Nano_2025_04_14 = ChatModel('gpt-4.1-nano-2025-04-14');

  // ── o4 family ──────────────────────────────────────────────────────────
  static const o4Mini = ChatModel('o4-mini');
  static const o4Mini_2025_04_16 = ChatModel('o4-mini-2025-04-16');

  // ── o3 family ──────────────────────────────────────────────────────────
  static const o3 = ChatModel('o3');
  static const o3_2025_04_16 = ChatModel('o3-2025-04-16');
  static const o3Mini = ChatModel('o3-mini');
  static const o3Mini_2025_01_31 = ChatModel('o3-mini-2025-01-31');

  // ── o1 family ──────────────────────────────────────────────────────────
  static const o1 = ChatModel('o1');
  static const o1_2024_12_17 = ChatModel('o1-2024-12-17');
  static const o1Preview = ChatModel('o1-preview');
  static const o1Preview_2024_09_12 = ChatModel('o1-preview-2024-09-12');
  static const o1Mini = ChatModel('o1-mini');
  static const o1Mini_2024_09_12 = ChatModel('o1-mini-2024-09-12');

  // ── gpt-4o family ──────────────────────────────────────────────────────
  static const gpt4o = ChatModel('gpt-4o');
  static const gpt4o_2024_11_20 = ChatModel('gpt-4o-2024-11-20');
  static const gpt4o_2024_08_06 = ChatModel('gpt-4o-2024-08-06');
  static const gpt4o_2024_05_13 = ChatModel('gpt-4o-2024-05-13');

  // audio / search previews
  static const gpt4oAudioPreview = ChatModel('gpt-4o-audio-preview');
  static const gpt4oAudioPreview_2024_10_01 = ChatModel('gpt-4o-audio-preview-2024-10-01');
  static const gpt4oAudioPreview_2024_12_17 = ChatModel('gpt-4o-audio-preview-2024-12-17');
  static const gpt4oAudioPreview_2025_06_03 = ChatModel('gpt-4o-audio-preview-2025-06-03');
  static const gpt4oMiniAudioPreview = ChatModel('gpt-4o-mini-audio-preview');
  static const gpt4oMiniAudioPreview_2024_12_17 = ChatModel('gpt-4o-mini-audio-preview-2024-12-17');
  static const gpt4oSearchPreview = ChatModel('gpt-4o-search-preview');
  static const gpt4oMiniSearchPreview = ChatModel('gpt-4o-mini-search-preview');
  static const gpt4oSearchPreview_2025_03_11 = ChatModel('gpt-4o-search-preview-2025-03-11');
  static const gpt4oMiniSearchPreview_2025_03_11 = ChatModel('gpt-4o-mini-search-preview-2025-03-11');

  // convenience alias
  static const chatgpt4oLatest = ChatModel('chatgpt-4o-latest');
  static const gpt5ChatLatest = ChatModel('gpt-5-chat-latest');

  // ── Codex mini ─────────────────────────────────────────────────────────
  static const codexMiniLatest = ChatModel('codex-mini-latest');

  // ── 4o-mini mainline ───────────────────────────────────────────────────
  static const gpt4oMini = ChatModel('gpt-4o-mini');
  static const gpt4oMini_2024_07_18 = ChatModel('gpt-4o-mini-2024-07-18');

  // ── GPT-4 Turbo / Vision / Preview line ────────────────────────────────
  static const gpt4Turbo = ChatModel('gpt-4-turbo');
  static const gpt4Turbo_2024_04_09 = ChatModel('gpt-4-turbo-2024-04-09');
  static const gpt4_0125Preview = ChatModel('gpt-4-0125-preview');
  static const gpt4TurboPreview = ChatModel('gpt-4-turbo-preview');
  static const gpt4_1106Preview = ChatModel('gpt-4-1106-preview');
  static const gpt4VisionPreview = ChatModel('gpt-4-vision-preview');

  // ── GPT-4 (legacy) ─────────────────────────────────────────────────────
  static const gpt4 = ChatModel('gpt-4');
  static const gpt4_0314 = ChatModel('gpt-4-0314');
  static const gpt4_0613 = ChatModel('gpt-4-0613');
  static const gpt4_32k = ChatModel('gpt-4-32k');
  static const gpt4_32k_0314 = ChatModel('gpt-4-32k-0314');
  static const gpt4_32k_0613 = ChatModel('gpt-4-32k-0613');

  // ── GPT-3.5 Turbo family ───────────────────────────────────────────────
  static const gpt35Turbo = ChatModel('gpt-3.5-turbo');
  static const gpt35Turbo16k = ChatModel('gpt-3.5-turbo-16k');
  static const gpt35Turbo_0301 = ChatModel('gpt-3.5-turbo-0301');
  static const gpt35Turbo_0613 = ChatModel('gpt-3.5-turbo-0613');
  static const gpt35Turbo_1106 = ChatModel('gpt-3.5-turbo-1106');
  static const gpt35Turbo_0125 = ChatModel('gpt-3.5-turbo-0125');
  static const gpt35Turbo16k_0613 = ChatModel('gpt-3.5-turbo-16k-0613');

  static const computerUsePreview_2025_03_11 = ChatModel('computer-use-preview-2025-03-11');
  static const computerUsePreview = ChatModel('computer-use-preview');

  const ChatModel(super.value);

  static ChatModel fromJson(String raw) => ChatModel(raw);
}
