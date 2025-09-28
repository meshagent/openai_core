import "dart:typed_data";

import "package:http/http.dart";
import "exceptions.dart";
import "sse_client.dart";
import "dart:convert";

class OpenAIClient {
  OpenAIClient({this.apiKey, String baseUrl = "https://api.openai.com/v1/", this.headers, Client? httpClient}) {
    this.baseUrl = Uri.parse(baseUrl);

    if (httpClient == null) {
      httpClient = Client.new();
    }
    this.httpClient = httpClient;
  }

  String? apiKey;
  final Map<String, String>? headers;
  late final Uri baseUrl;
  late final Client httpClient;

  Map<String, String>? getHeaders(Map<String, String> extra) {
    var headers = {
      if (this.headers != null) ...this.headers!,
      ...extra,
    };
    headers["Authorization"] = "Bearer ${apiKey}";
    return headers;
  }

  Future<Response> postText(String path, String body, {Map<String, String>? headers}) async {
    if (path.startsWith("/")) {
      path = path.substring(1);
    }
    final url = baseUrl.resolve(path);
    final bodyText = body;

    final request = Request("POST", url);
    request.body = bodyText;
    request.headers.addAll(getHeaders(headers ?? {})!);

    final stream = await httpClient.send(request);
    return await Response.fromStream(stream);
  }

  Future<Response> postJson(String path, Map<String, dynamic> body, {String? contentType, Map<String, String>? headers}) async {
    if (path.startsWith("/")) {
      path = path.substring(1);
    }
    final url = baseUrl.resolve(path);
    final bodyText = jsonEncode(body);
    return httpClient.post(url,
        headers: getHeaders({"content-type": contentType ?? "application/json", if (headers != null) ...headers}), body: bodyText);
  }

  SseClient streamJson(String path, Map<String, dynamic> body, {Map<String, String>? headers}) {
    if (path.startsWith("/")) {
      path = path.substring(1);
    }
    final json = utf8.encode(jsonEncode(body));
    final client = SseClient(baseUrl.resolve(path),
        headers: getHeaders({"content-type": "application/json", if (headers != null) ...headers}), httpClient: httpClient, body: json);
    return client;
  }

  /// POST a JSON body and expose the (chunked) response body as a byte stream.
  Stream<Uint8List> streamJsonData(String path, Map<String, dynamic> body, {Map<String, dynamic>? headers}) async* {
    // Clean up the relative path without mutating the parameter (parameters are
    // final in Dart).
    final relative = path.startsWith('/') ? path.substring(1) : path;
    final url = baseUrl.resolve(relative);

    // Build a streamed HTTP request.
    final req = Request('POST', url)
      ..headers.addAll(getHeaders({'Content-Type': 'application/json', if (headers != null) ...headers}) ?? {})
      ..body = jsonEncode(body);

    final res = await httpClient.send(req);

    // Fail fast on non-2xx.
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw OpenAIRequestException(
        statusCode: res.statusCode,
        message: res.reasonPhrase ?? "request failed",
      );
    }

    // Pipe the server’s chunked body to the caller.
    await for (final chunk in res.stream) {
      yield Uint8List.fromList(chunk);
    }
  }

  void close() {
    httpClient.close();
  }
}
