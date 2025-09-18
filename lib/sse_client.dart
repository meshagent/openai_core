import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Simple SSE client for Dart or Flutter (dart:io).
class SseClient {
  final Uri uri;
  final String method;
  final Map<String, String>? headers;
  final Uint8List? body;
  final http.Client httpClient;
  final StreamController<SseEvent> _controller = StreamController<SseEvent>.broadcast();

  SseClient(this.uri, {this.method = "POST", this.headers = const {}, required this.httpClient, this.body}) {
    _connect();
  }

  /// Subscribe to Server-Sent Events.
  Stream<SseEvent> get stream => _controller.stream;

  /// Close the connection and controller.
  Future<void> close() async {
    try {
      await _sub?.cancel();
    } on Object {}

    await _controller.close();
  }

  StreamSubscription<String>? _sub;

  /* ─────────────────────────────────────────────────────────────── */
  void _connect() async {
    final req = http.Request(method, uri)..headers.addAll({'Accept': 'text/event-stream', if (headers != null) ...headers!});

    if (body != null) {
      req.bodyBytes = body!;
    }

    final res = await httpClient.send(req);

    if (res.statusCode != 200) {
      _controller.addError(
        StateError(
          'SSE handshake failed: '
          'HTTP ${res.statusCode}',
        ),
      );
      await close();
      return;
    }

    _sub = res.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
      (chunk) {
        final line = chunk.trim();

        final parsed = _parseEvent(line);

        if (parsed != null) {
          if (parsed.data == "[DONE]") {
            return;
          }
          _controller.add(parsed);
        } else {}
      },
      onError: _controller.addError,
      onDone: close,
      cancelOnError: true,
    );
  }

  /* ─────────────────────────────────────────────────────────────── */
  SseEvent? _parseEvent(String raw) {
    String? event;
    final dataLines = <String>[];

    for (final line in const LineSplitter().convert(raw)) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
    }

    if (dataLines.isEmpty) return null;
    return SseEvent(event ?? 'message', dataLines.join('\n'));
  }
}

/// Strongly-typed wrapper around an SSE message.
class SseEvent {
  final String type;
  final String data;
  const SseEvent(this.type, this.data);

  @override
  String toString() => 'SseEvent(type: $type, data: $data)';
}
