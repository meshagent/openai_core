/* ────────────────────────────────────────────────────────────────────────── */
/*  /images — generation · edit · variation                                  */
/* ────────────────────────────────────────────────────────────────────────── */

import 'dart:convert';
import 'dart:typed_data';

import 'package:openai/common.dart';
import 'package:openai/exceptions.dart';
import 'package:openai/openai_client.dart';
import 'package:openai/responses.dart';
import 'package:mime/mime.dart';

extension ImagesAPI on OpenAIClient {
  /* ── Generation (JSON body) ───────────────────────────────────────── */

  Future<ImagesResult> createImage({
    required String prompt,
    ImageGenerationBackground? background,
    String? model,
    ImageModeration? moderation,
    int? n,
    int? outputCompression,
    ImageOutputFormat? outputFormat,
    ImageOutputQuality? quality,
    ImageResponseFormat? responseFormat,
    ImageOutputSize? size,
    ImageStyle? style,
    String? user,
  }) async {
    final resp = await postJson('/images/generations', {
      'prompt': prompt,
      if (background != null) 'background': background.toJson(),
      if (model != null) 'model': model,
      if (moderation != null) 'moderation': moderation.toJson(),
      if (n != null) 'n': n,
      if (outputCompression != null) 'output_compression': outputCompression,
      if (outputFormat != null) 'output_format': outputFormat.toJson(),
      if (quality != null) 'quality': quality.toJson(),
      if (responseFormat != null) 'response_format': responseFormat.toJson(),
      if (size != null) 'size': size.toJson(),
      if (style != null) 'style': style.toJson(),
      if (user != null) 'user': user,
    });

    if (resp.statusCode == 200) {
      return ImagesResult.fromJson(jsonDecode(resp.body));
    }
    print(resp.body);
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /* ── Edit (multipart) ─────────────────────────────────────────────── */

  Future<ImagesResult> editImage({
    required List<Uint8List> imageBytes,
    required List<String> filenames,
    required String prompt,
    ImageGenerationBackground? background,
    Uint8List? maskBytes,
    String? maskFilename,
    String? model,
    int? n,
    int? outputCompression,
    ImageOutputFormat? outputFormat,
    ImageOutputQuality? quality,
    ImageResponseFormat? responseFormat,
    ImageOutputSize? size,
    String? user,
  }) async {
    final boundary = '----dart-openai-image-edit-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

    final fields = <String, String>{
      'prompt': prompt,
      if (background != null) 'background': background.toJson(),
      if (model != null) 'model': model,
      if (n != null) 'n': '$n',
      if (outputCompression != null) 'output_compression': '$outputCompression',
      if (outputFormat != null) 'output_format': outputFormat.toJson(),
      if (quality != null) 'quality': quality.toJson(),
      if (responseFormat != null) 'response_format': responseFormat.toJson(),
      if (size != null) 'size': size.toJson(),
      if (user != null) 'user': user,
    };

    final body = _buildMultipartBodyMultiple(
      boundary: boundary,
      files: [
        for (var i = 0; i < imageBytes.length; i++) _MultipartFileSpec(field: 'image', bytes: imageBytes[i], filename: filenames[i]),
        if (maskBytes != null) _MultipartFileSpec(field: 'mask', bytes: maskBytes, filename: maskFilename ?? 'mask.png'),
      ],
      fields: fields,
    );

    final resp = await httpClient.post(
      baseUrl.resolve('images/edits'),
      headers: getHeaders({'Content-Type': 'multipart/form-data; boundary=$boundary'}),
      body: body,
    );

    if (resp.statusCode == 200) {
      return ImagesResult.fromJson(jsonDecode(resp.body));
    }
    print(resp.body);
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /* ── Variation (multipart) ────────────────────────────────────────── */

  Future<ImagesResult> createImageVariation({
    required Uint8List imageBytes,
    required String filename,
    String? model,
    int? n,
    ImageResponseFormat? responseFormat,
    ImageOutputSize? size,
    String? user,
  }) async {
    final boundary = '----dart-openai-image-var-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

    final body = _buildMultipartBody(
      boundary: boundary,
      fileField: 'image',
      filename: filename,
      fileBytes: imageBytes,
      fields: {
        if (model != null) 'model': model,
        if (n != null) 'n': '$n',
        if (responseFormat != null) 'response_format': responseFormat.toJson(),
        if (size != null) 'size': size.toJson(),
        if (user != null) 'user': user,
      },
    );

    final resp = await httpClient.post(
      baseUrl.resolve('images/variations'),
      headers: getHeaders({'Content-Type': 'multipart/form-data; boundary=$boundary'}),
      body: body,
    );

    if (resp.statusCode == 200) {
      return ImagesResult.fromJson(jsonDecode(resp.body));
    }
    print(resp.body);
    throw OpenAIRequestException.fromHttpResponse(resp);
  }
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Result objects                                                           */
/* ────────────────────────────────────────────────────────────────────────── */

class ImagesResult {
  ImagesResult({
    required this.created,
    required this.data,
    this.usage,
  });

  factory ImagesResult.fromJson(Map<String, dynamic> json) => ImagesResult(
        created: json['created'] as int,
        data: (json['data'] as List).cast<Map<String, dynamic>>().map(ImageData.fromJson).toList(),
        usage: json['usage'] == null ? null : Usage.fromJson(json['usage'] as Map<String, dynamic>),
      );

  final int created; // Unix-seconds
  final List<ImageData> data; // all returned images
  final Usage? usage;
}

class ImageData {
  ImageData({
    this.b64Json,
    this.url,
    this.revisedPrompt,
  });

  factory ImageData.fromJson(Map<String, dynamic> j) => ImageData(
        b64Json: j['b64_json'] as String?,
        url: j['url'] as String?,
        revisedPrompt: j['revised_prompt'] as String?,
      );

  /// base-64 PNG/JPEG/WEBP (always for *gpt-image-1*, optional for others).
  final String? b64Json;

  /// HTTPS link (when `response_format=="url"` for DALL·E-2/3).
  final String? url;

  /// Only for DALL·E-3.
  final String? revisedPrompt;

  /// Convenience: decode `b64_json` if present.
  Uint8List? get bytes => b64Json == null ? null : base64Decode(b64Json!);
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Multipart helpers (re-use from transcription)                            */
/* ────────────────────────────────────────────────────────────────────────── */

class _MultipartFileSpec {
  const _MultipartFileSpec({
    required this.field,
    required this.bytes,
    required this.filename,
  });

  final String field;
  final Uint8List bytes;
  final String filename;
}

/// Single-file helper (already used by transcription).
Uint8List _buildMultipartBody({
  required String boundary,
  required String fileField,
  required String filename,
  required Uint8List fileBytes,
  required Map<String, String> fields,
}) =>
    _buildMultipartBodyMultiple(
      boundary: boundary,
      files: [_MultipartFileSpec(field: fileField, bytes: fileBytes, filename: filename)],
      fields: fields,
    );

/// Multi-file version (image-edit can take up to 16 source images).
Uint8List _buildMultipartBodyMultiple({
  required String boundary,
  required List<_MultipartFileSpec> files,
  required Map<String, String> fields,
}) {
  final crlf = '\r\n';
  final buffer = BytesBuilder();

  fields.forEach((name, value) {
    buffer
      ..add(utf8.encode('--$boundary$crlf'))
      ..add(utf8.encode('Content-Disposition: form-data; name="$name"$crlf$crlf$value$crlf'));
  });

  for (final f in files) {
    buffer
      ..add(utf8.encode('--$boundary$crlf'))
      ..add(utf8.encode('Content-Disposition: form-data; name="${f.field}"; filename="${f.filename}"$crlf'))
      ..add(utf8.encode('Content-Type: ${lookupMimeType(f.filename)}$crlf$crlf'))
      ..add(f.bytes)
      ..add(utf8.encode(crlf));
  }

  buffer.add(utf8.encode('--$boundary--$crlf'));
  return buffer.toBytes();
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  Image enums (match JsonEnum pattern used elsewhere)                     */
/* ────────────────────────────────────────────────────────────────────────── */

enum ImageResponseFormat with JsonEnum {
  url('url'),
  b64Json('b64_json');

  const ImageResponseFormat(this.value);
  final String value;

  static ImageResponseFormat fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

enum ImageStyle with JsonEnum {
  vivid('vivid'),
  natural('natural');

  const ImageStyle(this.value);
  final String value;

  static ImageStyle fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

/* ––– extend an existing enum –––––––––––––––––––––––––––––––––––––––––––– */
/*  Add “low” to ImageModeration                                            */
enum ImageModeration with JsonEnum {
  auto('auto'),
  low('low');

  const ImageModeration(this.value);
  final String value;

  static ImageModeration fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

/* ────────────────────────────────────────────────────────────────────────── */
/*  ImageGenerationModel (edit / variation endpoints)                        */
/* ────────────────────────────────────────────────────────────────────────── */

enum ImageGenerationModel with JsonEnum {
  /// Default for edits / variations.
  dallE2('dall-e-2'),

  /// Supports transparency, quality settings, etc.
  gptImage1('gpt-image-1');

  const ImageGenerationModel(this.value);
  final String value;

  static ImageGenerationModel fromJson(String raw) => JsonEnum.fromJson(values, raw);
}
