// test/embeddings_test.dart
//
// Verifies that createEmbeddings() returns a non-empty vector and sane usage.
//
// $ OPENAI_API_KEY=sk-... dart test test/embeddings_test.dart

import 'dart:io';
import 'package:test/test.dart';
import 'package:openai/openai_client.dart';

import 'package:openai/embeddings.dart'; // where createEmbeddings() lives

void main() {
  test('createEmbeddings returns a valid vector (float format)', () async {
    final apiKey = Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      fail('Set OPENAI_API_KEY before running this test.');
    }

    final client = OpenAIClient(apiKey: apiKey);

    // --------------- call the embeddings endpoint -----------------
    final res = await client.createEmbeddings(
      input: 'The food was delicious and the waiter …',
      model:
          EmbeddingModel.textEmbedding3Small, // or ada-002 if not yet enabled
      encodingFormat: 'float',
      user: 'embeddings-integ-test',
    );

    client.close();

    // ---------------------- assertions ----------------------------
    // We asked for a single string, so expect exactly one embedding.
    expect(res.embeddings.length, equals(1));

    final vec = res.embeddings.first.vector;
    // Typical sizes: 1536 (ada-002), 1024, 512, etc.  > 100 is safe.
    expect(vec.length, greaterThan(100),
        reason: 'Vector length seems too small for a text embedding.');

    // Each element should be a finite double.
    expect(vec.every((v) => v.isFinite), isTrue,
        reason: 'Vector contains non-finite values.');

    // Usage metadata should be present and sensible.
    expect(res.usage, isNotNull);
    expect(res.usage!.totalTokens, greaterThan(0));
  });
}
