// ─────────────────────────────────────────────────────────────────────────────
// Files & Uploads — models
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/src/media_type.dart';
import 'package:mime/mime.dart';

import 'common.dart';
import 'exceptions.dart';
import 'openai_client.dart';

enum SortOrder with JsonEnum {
  asc('asc'),
  desc('desc');

  const SortOrder(this.value);
  final String value;

  static SortOrder fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

enum FilePurpose with JsonEnum {
  assistants('assistants'),
  batch('batch'),
  fineTune('fine-tune'),
  vision('vision'),
  userData('user_data'),
  evals('evals');

  const FilePurpose(this.value);
  final String value;

  static FilePurpose fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

class DeletionStatus {
  const DeletionStatus({
    required this.id,
    required this.object,
    required this.deleted,
  });

  factory DeletionStatus.fromJson(Map<String, dynamic> j) => DeletionStatus(
        id: j['id'] as String,
        object: j['object'] as String,
        deleted: j['deleted'] as bool,
      );

  final String id;
  final String object;
  final bool deleted;
}

/// `expires_after` payload for /files and /uploads (anchor="created_at", seconds within 1h..30d).
class FileExpiresAfter {
  const FileExpiresAfter({required this.anchor, required this.seconds});
  final String anchor; // "created_at"
  final int seconds; // 3600..2592000

  Map<String, dynamic> toJson() => {'anchor': anchor, 'seconds': seconds};
}

class OpenAIFile {
  const OpenAIFile({
    required this.id,
    required this.object,
    required this.bytes,
    required this.createdAt,
    required this.filename,
    required this.purpose,
  });

  factory OpenAIFile.fromJson(Map<String, dynamic> j) => OpenAIFile(
        id: j['id'] as String,
        object: j['object'] as String, // "file"
        bytes: (j['bytes'] as num).toInt(),
        createdAt: (j['created_at'] as num).toInt(),
        filename: j['filename'] as String,
        purpose: FilePurpose.fromJson(j['purpose']), // keep as raw string for forward-compat
      );

  final String id;
  final String object;
  final int bytes;
  final int createdAt;
  final String filename;
  final FilePurpose purpose;
}

class OpenAIFileList {
  const OpenAIFileList({
    required this.object,
    required this.data,
    required this.hasMore,
    this.firstId,
    this.lastId,
  });

  factory OpenAIFileList.fromJson(Map<String, dynamic> j) => OpenAIFileList(
        object: j['object'] as String, // "list"
        data: (j['data'] as List).cast<Map<String, dynamic>>().map(OpenAIFile.fromJson).toList(),
        hasMore: j['has_more'] as bool? ?? false,
        firstId: j['first_id'] as String?,
        lastId: j['last_id'] as String?,
      );

  final String object;
  final List<OpenAIFile> data;
  final bool hasMore;
  final String? firstId;
  final String? lastId;
}

class Upload {
  const Upload({
    required this.id,
    required this.object,
    required this.bytes,
    required this.createdAt,
    required this.filename,
    required this.purpose,
    required this.status,
    this.expiresAt,
    this.file,
  });

  factory Upload.fromJson(Map<String, dynamic> j) => Upload(
        id: j['id'] as String,
        object: j['object'] as String, // "upload"
        bytes: (j['bytes'] as num).toInt(),
        createdAt: (j['created_at'] as num).toInt(),
        filename: j['filename'] as String,
        purpose: FilePurpose.fromJson(j['purpose']),
        status: j['status'] as String, // pending | completed | cancelled
        expiresAt: (j['expires_at'] as num?)?.toInt(),
        file: j['file'] == null ? null : OpenAIFile.fromJson(j['file'] as Map<String, dynamic>),
      );

  final String id;
  final String object;
  final int bytes;
  final int createdAt;
  final String filename;
  final FilePurpose purpose;
  final String status; // pending | completed | cancelled
  final int? expiresAt;
  final OpenAIFile? file; // set when completed
}

class UploadPart {
  const UploadPart({
    required this.id,
    required this.object,
    required this.createdAt,
    required this.uploadId,
  });

  factory UploadPart.fromJson(Map<String, dynamic> j) => UploadPart(
        id: j['id'] as String,
        object: j['object'] as String, // "upload.part"
        createdAt: (j['created_at'] as num).toInt(),
        uploadId: j['upload_id'] as String,
      );

  final String id;
  final String object;
  final int createdAt;
  final String uploadId;
}

// ─────────────────────────────────────────────────────────────────────────────
// Files & Uploads — API
// ─────────────────────────────────────────────────────────────────────────────

extension FilesAPI on OpenAIClient {
  /* ── /files — upload (multipart), list, retrieve, delete, content ───────── */

  /// Upload a file from raw bytes.
  ///
  /// [purpose] one of:
  ///  - assistants, batch, fine-tune, vision, user_data, evals
  ///  - (system may also return assistants_output, batch_output, fine-tune-results)
  ///
  /// Use [expiresAfter] to set a TTL (e.g. for batch). If provided, this is sent
  /// as form fields: `expires_after[anchor]` and `expires_after[seconds]`.
  Future<OpenAIFile> uploadFileBytes({
    required FilePurpose purpose,
    required Uint8List fileBytes,
    required String filename,
    FileExpiresAfter? expiresAfter,
    String? mimeType, // optional; will be inferred if not provided
  }) async {
    final uri = baseUrl.resolve('files');
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(getHeaders({}) ?? {})
      ..fields['purpose'] = purpose.toJson();

    if (expiresAfter != null) {
      req.fields['expires_after[anchor]'] = expiresAfter.anchor;
      req.fields['expires_after[seconds]'] = expiresAfter.seconds.toString();
    }

    final contentType = mimeType ?? (lookupMimeType(filename) ?? 'application/octet-stream');
    req.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename, contentType: MediaType.parse(contentType)));

    final streamed = await httpClient.send(req);
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 200) {
      return OpenAIFile.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /// List files (optionally filter by purpose, paginate, and order).
  Future<OpenAIFileList> listFiles({
    String? after,
    int? limit, // 1..10000
    SortOrder? order, // asc | desc
    String? purpose, // e.g. "assistants"
  }) async {
    final qp = <String, String>{
      if (after != null) 'after': after,
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order.toJson(),
      if (purpose != null) 'purpose': purpose,
    };

    final url = baseUrl.resolve('files').replace(queryParameters: qp.isEmpty ? null : qp);
    final res = await httpClient.get(url, headers: getHeaders({}) ?? {});
    if (res.statusCode == 200) {
      return OpenAIFileList.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /// Retrieve a single file’s metadata.
  Future<OpenAIFile> retrieveFile(String fileId) async {
    final url = baseUrl.resolve('files/$fileId');
    final res = await httpClient.get(url, headers: getHeaders({}) ?? {});
    if (res.statusCode == 200) {
      return OpenAIFile.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /// Delete a file. Returns deletion status: {id, object:"file", deleted:true}
  Future<DeletionStatus> deleteFile(String fileId) async {
    final url = baseUrl.resolve('files/$fileId');
    final res = await httpClient.delete(url, headers: getHeaders({}) ?? {});
    if (res.statusCode == 200) {
      return DeletionStatus.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /// Download file contents as bytes. Caller can persist them as needed.
  Future<Uint8List> retrieveFileContent(String fileId) async {
    final url = baseUrl.resolve('files/$fileId/content');
    final res = await httpClient.get(url, headers: getHeaders({}) ?? {});
    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Raw content; do not jsonDecode.
      return res.bodyBytes;
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /* ── /uploads — large multi‑part uploads (up to 8 GB) ──────────────────── */

  /// Create an Upload session for large files (multipart).
  Future<Upload> createUpload({
    required int bytes,
    required String filename,
    required String mimeType,
    required FilePurpose purpose, // e.g. "fine-tune", "assistants", "vision"
    FileExpiresAfter? expiresAfter, // optional TTL
  }) async {
    final body = <String, dynamic>{
      'bytes': bytes,
      'filename': filename,
      'mime_type': mimeType,
      'purpose': purpose.toJson(),
      if (expiresAfter != null) 'expires_after': expiresAfter.toJson(),
    };

    final res = await postJson('/uploads', body);
    if (res.statusCode == 200) {
      return Upload.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /// Add a part (<= 64 MB) to an Upload.
  Future<UploadPart> addUploadPart({
    required String uploadId,
    required Uint8List data,
  }) async {
    final uri = baseUrl.resolve('uploads/$uploadId/parts');

    // Use multipart form field named "data".
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(getHeaders({}) ?? {})
      ..files.add(http.MultipartFile.fromBytes(
        'data',
        data,
        filename: 'part.bin',
        contentType: MediaType.parse('application/octet-stream'),
      ));

    final streamed = await httpClient.send(req);
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 200) {
      return UploadPart.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /// Complete an Upload by specifying the ordered list of part IDs.
  /// Optionally pass an MD5 checksum of the entire file to verify integrity.
  Future<Upload> completeUpload({
    required String uploadId,
    required List<String> partIds,
    String? md5,
  }) async {
    final res = await postJson('/uploads/$uploadId/complete', {
      'part_ids': partIds,
      if (md5 != null) 'md5': md5,
    });

    if (res.statusCode == 200) {
      return Upload.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /// Cancel an Upload. No further parts may be added after cancellation.
  Future<Upload> cancelUpload(String uploadId) async {
    final url = baseUrl.resolve('uploads/$uploadId/cancel');
    final res = await httpClient.post(url, headers: getHeaders({}) ?? {});
    if (res.statusCode == 200) {
      return Upload.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }
}
