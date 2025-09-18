import 'dart:convert';

import 'package:openai/common.dart';
import 'package:openai/exceptions.dart';
import 'package:openai/openai_client.dart';

/* ────────────────────────────────────────────────────────────────────────── */
/*   /embeddings — sync helper                                               */
/* ────────────────────────────────────────────────────────────────────────── */

extension EmbeddingsAPI on OpenAIClient {
  /// Create text embeddings.
  ///
  /// ```dart
  /// final res = await client.createEmbeddings(
  ///   input: 'The food was delicious and the waiter...',
  ///   model: 'text-embedding-3-small',
  /// );
  ///
  /// print(res.vectors.first.length);        // 1536, 1024, … depending on model
  /// ```
  ///
  /// For multiple inputs pass a `List<String>` (or `List<List<int>>` of tokens).
  Future<EmbeddingsResult> createEmbeddings({
    /// Single string · List<String> · List<List<int>>
    required dynamic input,

    /// e.g. text-embedding-3-large, ada-002, …
    required EmbeddingModel model,

    /// Target dimensionality (supported by text-embedding-3 + later).
    int? dimensions,

    /// `"float"` (default) or `"base64"`.
    String? encodingFormat,

    /// End-user identifier for abuse monitoring.
    String? user,
  }) async {
    final resp = await postJson('/embeddings', {
      'input': input,
      'model': model.toJson(),
      if (dimensions != null) 'dimensions': dimensions,
      if (encodingFormat != null) 'encoding_format': encodingFormat,
      if (user != null) 'user': user,
    });

    if (resp.statusCode == 200) {
      return EmbeddingsResult.fromJson(jsonDecode(resp.body));
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Result objects                                                           */
/* ────────────────────────────────────────────────────────────────────────── */

class EmbeddingsResult {
  const EmbeddingsResult({
    required this.data,
    required this.model,
    this.usage,
  });

  factory EmbeddingsResult.fromJson(Map<String, dynamic> json) => EmbeddingsResult(
        data: (json['data'] as List).cast<Map<String, dynamic>>().map(Embedding.fromJson).toList(),
        model: EmbeddingModel.fromJson(json['model']),
        usage: json['usage'] == null ? null : Usage.fromJson(json['usage'] as Map<String, dynamic>),
      );

  /// All returned embedding vectors, **in the same order as `input`.**
  List<Embedding> get embeddings => data;

  /// Convenience accessor: list of raw vectors (`List<double>`).
  List<List<double>> get vectors => [for (final e in data) e.vector];

  final List<Embedding> data;
  final EmbeddingModel model;
  final Usage? usage;
}

class Embedding {
  const Embedding({required this.vector, required this.index});

  factory Embedding.fromJson(Map<String, dynamic> json) => Embedding(
        vector: (json['embedding'] as List).cast<num>().map((n) => n.toDouble()).toList(),
        index: json['index'] as int,
      );

  /// The high-dimensional embedding.
  final List<double> vector;

  /// Position in the `input` list.
  final int index;
}

enum EmbeddingModel with JsonEnum {
  textEmbeddingAda002('text-embedding-ada-002'),
  textEmbedding3Small('text-embedding-3-small'),
  textEmbedding3Large('text-embedding-3-large');

  const EmbeddingModel(this.value);
  final String value;

  static EmbeddingModel fromJson(String raw) => JsonEnum.fromJson(values, raw);
}
