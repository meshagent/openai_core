// containers.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'exceptions.dart';
import 'openai_client.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Data models
/// ─────────────────────────────────────────────────────────────────────────

class ContainerExpiresAfter {
  const ContainerExpiresAfter({
    required this.anchor,
    this.minutes,
  });

  /// Reference point for expiration (e.g., "last_active_at").
  final String anchor;

  /// Number of minutes after `anchor` when the container expires.
  final int? minutes;

  Map<String, dynamic> toJson() => {
        'anchor': anchor,
        if (minutes != null) 'minutes': minutes,
      };

  factory ContainerExpiresAfter.fromJson(Map<String, dynamic> j) => ContainerExpiresAfter(
        anchor: j['anchor'] as String,
        minutes: (j['minutes'] as num?)?.toInt(),
      );
}

class Container {
  const Container({
    required this.id,
    required this.object,
    required this.createdAt,
    required this.status,
    this.expiresAfter,
    this.lastActiveAt,
    required this.name,
  });

  final String id;
  final String object; // "container"
  final int createdAt; // epoch seconds
  final String status; // e.g. "running"
  final ContainerExpiresAfter? expiresAfter;
  final int? lastActiveAt; // epoch seconds
  final String name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'object': object,
        'created_at': createdAt,
        'status': status,
        if (expiresAfter != null) 'expires_after': expiresAfter!.toJson(),
        if (lastActiveAt != null) 'last_active_at': lastActiveAt,
        'name': name,
      };

  factory Container.fromJson(Map<String, dynamic> j) => Container(
        id: j['id'] as String,
        object: j['object'] as String,
        createdAt: (j['created_at'] as num).toInt(),
        status: j['status'] as String,
        expiresAfter: j['expires_after'] == null ? null : ContainerExpiresAfter.fromJson(j['expires_after'] as Map<String, dynamic>),
        lastActiveAt: (j['last_active_at'] as num?)?.toInt(),
        name: j['name'] as String,
      );

  @override
  String toString() => 'Container(id: $id, name: $name, status: $status)';
}

class ContainerList {
  const ContainerList({
    required this.object,
    required this.data,
    this.firstId,
    this.lastId,
    required this.hasMore,
  });

  final String object; // "list"
  final List<Container> data;
  final String? firstId;
  final String? lastId;
  final bool hasMore;

  Map<String, dynamic> toJson() => {
        'object': object,
        'data': data.map((e) => e.toJson()).toList(),
        if (firstId != null) 'first_id': firstId,
        if (lastId != null) 'last_id': lastId,
        'has_more': hasMore,
      };

  factory ContainerList.fromJson(Map<String, dynamic> j) => ContainerList(
        object: j['object'] as String,
        data: (j['data'] as List).cast<Map<String, dynamic>>().map(Container.fromJson).toList(),
        firstId: j['first_id'] as String?,
        lastId: j['last_id'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ContainerDeleted {
  const ContainerDeleted({
    required this.id,
    required this.object, // "container.deleted"
    required this.deleted,
  });

  final String id;
  final String object;
  final bool deleted;

  Map<String, dynamic> toJson() => {'id': id, 'object': object, 'deleted': deleted};

  factory ContainerDeleted.fromJson(Map<String, dynamic> j) => ContainerDeleted(
        id: j['id'] as String,
        object: j['object'] as String,
        deleted: j['deleted'] as bool,
      );
}

class ContainerFile {
  const ContainerFile({
    required this.id,
    required this.object, // "container.file"
    required this.createdAt,
    required this.bytes,
    required this.containerId,
    required this.path,
    required this.source, // "user" | "assistant" | ...
  });

  final String id;
  final String object;
  final int createdAt;
  final int bytes;
  final String containerId;
  final String path;
  final String source;

  Map<String, dynamic> toJson() => {
        'id': id,
        'object': object,
        'created_at': createdAt,
        'bytes': bytes,
        'container_id': containerId,
        'path': path,
        'source': source,
      };

  factory ContainerFile.fromJson(Map<String, dynamic> j) => ContainerFile(
        id: j['id'] as String,
        object: j['object'] as String,
        createdAt: (j['created_at'] as num).toInt(),
        bytes: (j['bytes'] as num).toInt(),
        containerId: j['container_id'] as String,
        path: j['path'] as String,
        source: j['source'] as String,
      );
}

class ContainerFileList {
  const ContainerFileList({
    required this.object, // "list"
    required this.data,
    this.firstId,
    this.lastId,
    required this.hasMore,
  });

  final String object;
  final List<ContainerFile> data;
  final String? firstId;
  final String? lastId;
  final bool hasMore;

  Map<String, dynamic> toJson() => {
        'object': object,
        'data': data.map((e) => e.toJson()).toList(),
        if (firstId != null) 'first_id': firstId,
        if (lastId != null) 'last_id': lastId,
        'has_more': hasMore,
      };

  factory ContainerFileList.fromJson(Map<String, dynamic> j) => ContainerFileList(
        object: j['object'] as String,
        data: (j['data'] as List).cast<Map<String, dynamic>>().map(ContainerFile.fromJson).toList(),
        firstId: j['first_id'] as String?,
        lastId: j['last_id'] as String?,
        hasMore: j['has_more'] as bool? ?? false,
      );
}

class ContainerFileDeleted {
  const ContainerFileDeleted({
    required this.id,
    required this.object, // "container.file.deleted"
    required this.deleted,
  });

  final String id;
  final String object;
  final bool deleted;

  Map<String, dynamic> toJson() => {'id': id, 'object': object, 'deleted': deleted};

  factory ContainerFileDeleted.fromJson(Map<String, dynamic> j) => ContainerFileDeleted(
        id: j['id'] as String,
        object: j['object'] as String,
        deleted: j['deleted'] as bool,
      );
}

/// ─────────────────────────────────────────────────────────────────────────
/// API surface
/// ─────────────────────────────────────────────────────────────────────────

extension ContainersAPI on OpenAIClient {
  // Helper to resolve a relative API path
  Uri _resolve(String path, [Map<String, String>? query]) {
    final relative = path.startsWith('/') ? path.substring(1) : path;
    final base = baseUrl.resolve(relative);
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: {
      ...base.queryParameters,
      ...query,
    });
  }

  /// Create a container.
  ///
  /// ```dart
  /// final container = await client.createContainer(
  ///   name: 'My Container',
  ///   expiresAfter: ContainerExpiresAfter(anchor: 'last_active_at', minutes: 20),
  ///   fileIds: ['file_abc123'], // optional
  /// );
  /// ```
  Future<Container> createContainer({
    required String name,
    ContainerExpiresAfter? expiresAfter,
    List<String>? fileIds,
  }) async {
    final resp = await postJson('/containers', {
      'name': name,
      if (expiresAfter != null) 'expires_after': expiresAfter.toJson(),
      if (fileIds != null) 'file_ids': fileIds,
    });

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return Container.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /// List containers (paginated).
  ///
  /// [order] is `"asc"` or `"desc"` (default server-side is `"desc"`).
  Future<ContainerList> listContainers({
    String? after,
    int? limit,
    String? order,
  }) async {
    final url = _resolve('/containers', {
      if (after != null) 'after': after,
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order,
    });

    final resp = await httpClient.get(url, headers: getHeaders({}) ?? {});
    if (resp.statusCode == 200) {
      return ContainerList.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /// Retrieve a single container by ID.
  Future<Container> retrieveContainer(String containerId) async {
    final resp = await httpClient.get(
      _resolve('/containers/$containerId'),
      headers: getHeaders({}) ?? {},
    );
    if (resp.statusCode == 200) {
      return Container.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /// Delete a container by ID.
  Future<ContainerDeleted> deleteContainer(String containerId) async {
    final resp = await httpClient.delete(
      _resolve('/containers/$containerId'),
      headers: getHeaders({}) ?? {},
    );
    if (resp.statusCode == 200) {
      return ContainerDeleted.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /// Create a container file either by uploading raw bytes (multipart)
  /// **or** by referencing an existing OpenAI File with [fileId].
  ///
  /// Exactly one of ([bytes] + [filename]) or [fileId] must be provided.
  ///
  /// ```dart
  /// // via file_id:
  /// await client.createContainerFile(containerId: cid, fileId: 'file_abc123');
  ///
  /// // via upload:
  /// await client.createContainerFile(containerId: cid, bytes: data, filename: 'example.txt');
  /// ```
  Future<ContainerFile> createContainerFile({
    required String containerId,
    Uint8List? bytes,
    String? filename,
    String? fileId,
  }) async {
    if ((bytes == null || filename == null) && fileId == null) {
      throw ArgumentError('Provide either (bytes + filename) or fileId.');
    }
    if ((bytes != null || filename != null) && fileId != null) {
      throw ArgumentError('Provide only one of (bytes + filename) OR fileId, not both.');
    }

    // JSON route with file_id
    if (fileId != null) {
      final resp = await postJson('/containers/$containerId/files', {'file_id': fileId});
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return ContainerFile.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
      throw OpenAIRequestException.fromHttpResponse(resp);
    }

    // Multipart upload route
    final url = _resolve('/containers/$containerId/files');
    final req = http.MultipartRequest('POST', url)
      ..headers.addAll(getHeaders({}) ?? {})
      ..files.add(http.MultipartFile.fromBytes('file', bytes!, filename: filename));

    final streamed = await httpClient.send(req);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 200 && streamed.statusCode < 300) {
      return ContainerFile.fromJson(jsonDecode(body) as Map<String, dynamic>);
    }
    // Synthesize an http.Response for consistent exception handling.
    final asResponse = http.Response(body, streamed.statusCode, headers: streamed.headers, reasonPhrase: streamed.reasonPhrase);
    throw OpenAIRequestException.fromHttpResponse(asResponse);
  }

  /// List files inside a container (paginated).
  Future<ContainerFileList> listContainerFiles(
    String containerId, {
    String? after,
    int? limit,
    String? order,
  }) async {
    final url = _resolve('/containers/$containerId/files', {
      if (after != null) 'after': after,
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order,
    });

    final resp = await httpClient.get(url, headers: getHeaders({}) ?? {});
    if (resp.statusCode == 200) {
      return ContainerFileList.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /// Retrieve a single container file’s metadata.
  Future<ContainerFile> retrieveContainerFile(String containerId, String fileId) async {
    final resp = await httpClient.get(
      _resolve('/containers/$containerId/files/$fileId'),
      headers: getHeaders({}) ?? {},
    );
    if (resp.statusCode == 200) {
      return ContainerFile.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /// Download the container file content as bytes.
  Future<Uint8List> retrieveContainerFileContent(String containerId, String fileId) async {
    final resp = await httpClient.get(
      _resolve('/containers/$containerId/files/$fileId/content'),
      headers: getHeaders({}) ?? {},
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return resp.bodyBytes;
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /// Stream the container file content as chunks (useful for large files).
  Stream<Uint8List> streamContainerFileContent(String containerId, String fileId) async* {
    final req = http.Request('GET', _resolve('/containers/$containerId/files/$fileId/content'))..headers.addAll(getHeaders({}) ?? {});
    final res = await httpClient.send(req);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = await res.stream.bytesToString();
      throw OpenAIRequestException(statusCode: res.statusCode, message: res.reasonPhrase ?? 'request failed', bodyPreview: body);
    }

    await for (final chunk in res.stream) {
      yield Uint8List.fromList(chunk);
    }
  }

  /// Delete a container file by ID.
  Future<ContainerFileDeleted> deleteContainerFile(String containerId, String fileId) async {
    final resp = await httpClient.delete(
      _resolve('/containers/$containerId/files/$fileId'),
      headers: getHeaders({}) ?? {},
    );
    if (resp.statusCode == 200) {
      return ContainerFileDeleted.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }
}
