import "package:http/http.dart" as http;
import "dart:convert";

/// ────────────────────────────────────────────────────────────────
///  Base class
/// ────────────────────────────────────────────────────────────────
abstract class OpenAIException implements Exception {
  const OpenAIException({required this.message});
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// ────────────────────────────────────────────────────────────────
///  HTTP / request-level errors (non-2xx).
/// ────────────────────────────────────────────────────────────────
class OpenAIRequestException extends OpenAIException {
  const OpenAIRequestException({
    required super.message,
    required this.statusCode,
    this.code,
    this.param,
    this.bodyPreview,
  });

  final int statusCode; // HTTP status
  final String? code; // OpenAI error.code (e.g. "rate_limit_exceeded")
  final String? param; // parameter that failed validation, if any
  final String? bodyPreview; // first N bytes when body wasn’t JSON

  @override
  String toString() {
    return "OpenAIRequestException: statusCode $statusCode, code: $code, param: $param, body: $bodyPreview";
  }

  /* Factory that inspects the HTTP response / JSON body */
  static Future<OpenAIRequestException> fromHttpResponse(http.Response r) async {
    try {
      final obj = jsonDecode(r.body) as Map<String, dynamic>;
      if (obj.containsKey('error') && obj['error'] is Map) {
        final err = obj['error'] as Map;
        return _subclassForCode(
          status: r.statusCode,
          code: err['code'] as String?,
          message: err['message'] as String? ?? 'Unknown OpenAI error',
          param: err['param'] as String?,
        );
      }
    } catch (_) {/* fall through if body wasn’t JSON */}
    // Non-JSON: keep a short preview so logs stay readable.
    final preview = r.body.length > 300 ? '${r.body.substring(0, 300)}…' : r.body;
    return _subclassForCode(
      status: r.statusCode,
      code: null,
      message: 'HTTP ${r.statusCode}',
      param: null,
      bodyPreview: preview,
    );
  }

  /* Decides which concrete subclass to return. */
  static OpenAIRequestException _subclassForCode({
    required int status,
    required String? code,
    required String message,
    String? param,
    String? bodyPreview,
  }) {
    // Match either HTTP status or OpenAI error.code.
    if (status == 401 || code == 'invalid_api_key') {
      return OpenAIAuthenticationException(message: message, statusCode: status, code: code, param: param);
    }
    if (status == 429 || code == 'rate_limit_exceeded') {
      return OpenAIRateLimitException(message: message, statusCode: status, code: code, param: param);
    }
    if (status >= 500) {
      return OpenAIServiceException(message: message, statusCode: status, code: code, param: param);
    }
    return OpenAIRequestException(message: message, statusCode: status, code: code, param: param, bodyPreview: bodyPreview);
  }
}

/// ────────────────────────────────────────────────────────────────
///  Concrete specialisations
/// ────────────────────────────────────────────────────────────────
class OpenAIAuthenticationException extends OpenAIRequestException {
  OpenAIAuthenticationException({required super.message, required super.statusCode, super.code, super.param});
}

class OpenAIRateLimitException extends OpenAIRequestException {
  OpenAIRateLimitException({required super.message, required super.statusCode, super.code, super.param});
}

class OpenAIServiceException extends OpenAIRequestException {
  OpenAIServiceException({required super.message, required super.statusCode, super.code, super.param});
}
