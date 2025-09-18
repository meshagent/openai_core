import 'dart:io';
import 'package:test/test.dart';
import 'package:openai/openai_client.dart';
import 'package:openai/audio.dart'; // import where you added the helpers
import 'dart:typed_data';

void main() {
  test('Non-streaming transcription returns expected text', () async {
    final apiKey = Platform.environment['OPENAI_API_KEY']!;
    final client = OpenAIClient(apiKey: apiKey);

    final bytes = await File('integration_test/harvard.wav').readAsBytes();

    final result = await client.createTranscription(
      fileBytes: bytes,
      filename: 'harvard.wav',
      model: AudioModel.gpt4oMiniTranscribe,
      language: 'en',
      responseFormat:
          AudioResponseFormat.text, // plain text easiest for asserts
    );

    client.close();

    expect(result.text, isNotNull);
    // Harvard sentence #1 contains “smooth planks”.
    expect(result.text!.toLowerCase(), contains('stale smell'));
  });

  test(
    'Streaming transcription yields delta events and final done',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['OPENAI_API_KEY']!;
      final client = OpenAIClient(apiKey: apiKey);

      final bytes = await File('integration_test/harvard.wav').readAsBytes();

      final stream = await client.streamTranscription(
        fileBytes: bytes,
        filename: 'harvard.wav',
        model: AudioModel.gpt4oMiniTranscribe,
        language: 'en',
        include: ['logprobs'],
      );

      var deltaSeen = false;
      var doneText = '';

      await for (final ev in stream.events) {
        switch (ev) {
          case TranscriptTextDelta():
            deltaSeen = true;
          case TranscriptTextDone():
            doneText = ev.text;
        }
      }

      client.close();

      expect(deltaSeen, isTrue,
          reason: 'Should have received at least one delta event.');
      expect(doneText.toLowerCase(), contains('stale smell'));
    },
  );

  test('createSpeech returns non-empty binary audio', () async {
    final apiKey = Platform.environment['OPENAI_API_KEY']!;
    final client = OpenAIClient(apiKey: apiKey);

    final audio = await client.createSpeech(
      input: 'Testing one two three.',
      model: SpeechModel.gpt4oMiniTts,
      voice: SpeechVoice.nova,
      responseFormat: SpeechResponseFormat.mp3,
    );

    client.close();

    // Basic sanity checks on returned data.
    expect(audio.lengthInBytes, greaterThan(5 * 1024),
        reason: 'Audio payload seems suspiciously small.');
  });

  test(
    'streamSpeechEvents streams speach events and finishes audio.done',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('Set OPENAI_API_KEY in your shell before running this test.');
      }

      final client = OpenAIClient(apiKey: apiKey);

      // --------------- run the streaming TTS request -----------------
      final stream = await client.streamSpeechEvents(
        input: 'Streaming test: the quick brown fox jumps over the lazy dog.',
        model: SpeechModel.gpt4oMiniTts,
        voice: SpeechVoice.nova,
        responseFormat: SpeechResponseFormat.mp3,
        // stream_format defaults to "sse"
      );

      final bytesBuilder = BytesBuilder();
      var deltaSeen = false;
      var doneSeen = false;

      await for (final ev in stream.events) {
        switch (ev) {
          case SpeechAudioDelta():
            deltaSeen = true;
            bytesBuilder.add(ev.audioBytes); // gather decoded chunk
          case SpeechAudioDone():
            doneSeen = true;
        }
      }

      client.close();

      // -------------------- assertions ------------------------------
      expect(deltaSeen, isTrue,
          reason:
              'Should have received at least one speech.audio.delta event.');
      expect(doneSeen, isTrue,
          reason: 'Final audio.done event was not received.');

      final allBytes = bytesBuilder.toBytes();
      expect(allBytes.lengthInBytes, greaterThan(10 * 1024),
          reason: 'Combined audio payload looks too small for MP3 data.');
    },
  );

  test(
    'streamSpeechData streams binary audio',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        fail('Set OPENAI_API_KEY in your shell before running this test.');
      }

      final client = OpenAIClient(apiKey: apiKey);

      // --------------- run the streaming TTS request -----------------
      final stream = await client.streamSpeechData(
        input: 'Streaming test: the quick brown fox jumps over the lazy dog.',
        model: SpeechModel.gpt4oMiniTts,
        voice: SpeechVoice.nova,
        responseFormat: SpeechResponseFormat.mp3,
        // stream_format defaults to "sse"
      );

      final bytesBuilder = BytesBuilder();

      await for (final bytes in stream) {
        bytesBuilder.add(bytes);
      }

      client.close();

      final allBytes = bytesBuilder.toBytes();
      expect(allBytes.lengthInBytes, greaterThan(10 * 1024),
          reason: 'Combined audio payload looks too small for MP3 data.');
    },
  );
}
