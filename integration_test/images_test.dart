// test/image_generation_test.dart
import 'dart:typed_data';
import 'dart:io';
import 'package:test/test.dart';

import '../lib/responses.dart';
import '../lib/openai_client.dart';
import '../lib/images.dart'; // where createImage lives

void main() {
  test('createImage returns image bytes', () async {
    final key = Platform.environment['OPENAI_API_KEY']!;
    final client = OpenAIClient(apiKey: key);

    final res = await client.createImage(
      prompt: 'A simple blue circle on a white background',
      model: 'gpt-image-1',
      outputFormat: ImageOutputFormat.jpeg,
      size: ImageOutputSize.square1024,
      n: 1,
    );

    client.close();

    // -------- assertions ----------
    expect(res.data.length, equals(1));

    Uint8List bytes = res.data.first.bytes!;
    expect(bytes.lengthInBytes, greaterThan(20 * 1024),
        reason: 'Image payload looks too small.');
  });

  test(
    'editImage returns modified image',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final key = Platform.environment['OPENAI_API_KEY']!;
      final client = OpenAIClient(apiKey: key);

      final imageBytes =
          await File('integration_test/desktop.jpg').readAsBytes();

      final res = await client.editImage(
          imageBytes: [imageBytes],
          filenames: ['base.jpg'],
          prompt: 'Add a small red heart in the top-left corner',
          model: 'gpt-image-1', // supported for edits
          outputFormat: ImageOutputFormat.jpeg,
          size: ImageOutputSize.square1024);

      client.close();

      Uint8List bytes = res.data.first.bytes!;
      expect(bytes.lengthInBytes, greaterThan(20 * 1024));
    },
  );

  test(
    'createImageVariation returns two distinct images',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final key = Platform.environment['OPENAI_API_KEY']!;
      final client = OpenAIClient(apiKey: key);

      final src = await File('integration_test/desktop.png').readAsBytes();

      final res = await client.createImageVariation(
        imageBytes: src,
        filename: 'variation.png',
        n: 2,
        model: 'dall-e-2',
        responseFormat: ImageResponseFormat.b64Json,
        size: ImageOutputSize.square1024,
      );

      client.close();

      // ------------ assertions -------------
      expect(res.data.length, equals(2));

      final bytes1 = res.data[0].bytes!;

      final bytes2 = res.data[1].bytes!;

      expect(bytes1.lengthInBytes, greaterThan(10 * 1024));
      expect(bytes2.lengthInBytes, greaterThan(10 * 1024));
      expect(bytes1, isNot(equals(bytes2)),
          reason: 'Variation images should differ.');
    },
  );
}
