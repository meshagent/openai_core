# Dart OpenAI

A lightweight, idiomatic Dart client for the OpenAI API. It targets Dart 3+, works in CLI and Flutter apps, and supports the modern Responses API, streaming, embeddings, images, and text‑to‑speech.

## Features

- Responses API: create and stream model outputs
- Embeddings: generate vectors for text and tokens
- Images: generation, edits, and variations
- Audio (TTS): create speech or stream audio/events
- Simple HTTP client with pluggable base URL and headers

## Install

Add the package to your app. If this isn’t published yet, depend via path or git; otherwise use pub.

```yaml
dependencies:
  openai: ^0.0.1
```

Set an API key in your environment (recommended):

```bash
export OPENAI_API_KEY=sk-your-key
```

## Quick Start

```dart
import 'openai_client.dart';
import 'responses.dart';

Future<void> main() async {
  final client = OpenAIClient(apiKey: const String.fromEnvironment('OPENAI_API_KEY'));

  // Create a response (text)
  final res = await client.createResponse(
    model: ChatModel.gpt4o,
    input: const ResponseInputText('Write a short haiku about Dart.'),
    text: const TextFormatText(),
  );

  // Extract output text
  final msgs = res.output?.whereType<OutputMessage>() ?? [];
  final text = [
    for (final m in msgs)
      for (final c in m.content.whereType<OutputTextContent>()) c.text
  ].join('\n');

  print(text);
  client.close();
}
```

## Streaming Responses

```dart
import 'openai_client.dart';
import 'responses.dart';

Future<void> main() async {
  final client = OpenAIClient(apiKey: const String.fromEnvironment('OPENAI_API_KEY'));
  final stream = await client.streamResponse(
    model: ChatModel.gpt4o,
    input: const ResponseInputText('Stream a two-line poem about code.'),
    text: const TextFormatText(),
  );

  await for (final ev in stream.events) {
    if (ev is ResponseOutputTextDelta) stdout.write(ev.delta);
    if (ev is ResponseOutputTextDone) stdout.writeln();
    if (ev is ResponseCompleted) break;
  }

  await stream.close();
  client.close();
}
```

## Embeddings

```dart
import 'openai_client.dart';
import 'embeddings.dart';

Future<void> main() async {
  final client = OpenAIClient(apiKey: const String.fromEnvironment('OPENAI_API_KEY'));
  final result = await client.createEmbeddings(
    input: 'The food was delicious and the waiter…',
    model: EmbeddingModel.textEmbedding3Small,
  );
  print('dims: ${result.vectors.first.length}');
  client.close();
}
```

## Images

```dart
import 'openai_client.dart';
import 'images.dart';

Future<void> main() async {
  final client = OpenAIClient(apiKey: const String.fromEnvironment('OPENAI_API_KEY'));
  final img = await client.createImage(prompt: 'A cozy reading nook, watercolor style');
  final bytes = img.data.first.bytes!; // when b64_json is returned
  await File('nook.png').writeAsBytes(bytes);
  client.close();
}
```

## Audio (Text‑to‑Speech)

```dart
import 'openai_client.dart';
import 'audio.dart';

Future<void> main() async {
  final client = OpenAIClient(apiKey: const String.fromEnvironment('OPENAI_API_KEY'));
  final bytes = await client.createSpeech(
    input: 'Hello from Dart!',
    model: SpeechModel.gpt4oMiniTts,
    voice: SpeechVoice.nova,
  );
  await File('hello.mp3').writeAsBytes(bytes);
  client.close();
}
```

## Configuration

- Base URL: pass `baseUrl` to `OpenAIClient(...)` for custom endpoints.
- Headers: pass `headers` to add org/project scoping or Azure headers.
- Cleanup: call `client.close()` to release the underlying HTTP client.

## Notes

- This is an independent Dart implementation of the OpenAI API.
