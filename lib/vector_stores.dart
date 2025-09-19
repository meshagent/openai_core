/* ── Common helpers ───────────────────────────────────────────────────────── */

import 'dart:convert';

import 'common.dart';
import 'openai_client.dart';
import 'responses.dart';
import 'exceptions.dart';
import 'files.dart';

/* ── Expiration policy ───────────────────────────────────────────────────── */

class ExpiresAfter {
  const ExpiresAfter({required this.anchor, required this.days});

  factory ExpiresAfter.fromJson(Map<String, dynamic> j) => ExpiresAfter(anchor: j['anchor'] as String, days: j['days'] as int);

  final String anchor; // supported: "last_active_at"
  final int days;

  Map<String, dynamic> toJson() => {'anchor': anchor, 'days': days};
}

/* ── Chunking strategy (requests & reads) ─────────────────────────────────── */

abstract class ChunkingStrategy {
  const ChunkingStrategy();
  Map<String, dynamic> toJson();

  factory ChunkingStrategy.fromJson(Map<String, dynamic> j) {
    final type = j['type'] as String? ?? 'other';
    if (type == 'static') {
      final s = j['static'] as Map?;
      return StaticChunkingStrategy(
        maxChunkSizeTokens: (s?['max_chunk_size_tokens'] as num?)?.toInt(),
        chunkOverlapTokens: (s?['chunk_overlap_tokens'] as num?)?.toInt(),
      );
    }
    if (type == 'auto') return const AutoChunkingStrategy();
    return const OtherChunkingStrategy();
  }
}

/// Request/response variant: { "type":"auto" }
class AutoChunkingStrategy extends ChunkingStrategy {
  const AutoChunkingStrategy();
  @override
  Map<String, dynamic> toJson() => {'type': 'auto'};
}

/// Request/response variant:
/// { "type":"static", "static": { "max_chunk_size_tokens": 800, "chunk_overlap_tokens": 400 } }
class StaticChunkingStrategy extends ChunkingStrategy {
  const StaticChunkingStrategy({
    this.maxChunkSizeTokens = 800,
    this.chunkOverlapTokens = 400,
  });

  final int? maxChunkSizeTokens;
  final int? chunkOverlapTokens;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'static',
        'static': {
          if (maxChunkSizeTokens != null) 'max_chunk_size_tokens': maxChunkSizeTokens,
          if (chunkOverlapTokens != null) 'chunk_overlap_tokens': chunkOverlapTokens,
        }
      };
}

/// Response-only fallback when server returns unknown/legacy shape.
class OtherChunkingStrategy extends ChunkingStrategy {
  const OtherChunkingStrategy();
  @override
  Map<String, dynamic> toJson() => {'type': 'other'};
}

/* ── Vector Store objects ─────────────────────────────────────────────────── */

enum VectorStoreStatus with JsonEnum {
  expired('expired'),
  inProgress('in_progress'),
  completed('completed');

  const VectorStoreStatus(this.value);
  final String value;
  static VectorStoreStatus fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

class VectorStoreFileCounts {
  const VectorStoreFileCounts({
    required this.inProgress,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.total,
  });

  factory VectorStoreFileCounts.fromJson(Map<String, dynamic> j) => VectorStoreFileCounts(
        inProgress: j['in_progress'] as int? ?? 0,
        completed: j['completed'] as int? ?? 0,
        failed: j['failed'] as int? ?? 0,
        cancelled: j['cancelled'] as int? ?? 0,
        total: j['total'] as int? ?? 0,
      );

  final int inProgress, completed, failed, cancelled, total;

  Map<String, dynamic> toJson() => {
        'in_progress': inProgress,
        'completed': completed,
        'failed': failed,
        'cancelled': cancelled,
        'total': total,
      };
}

class VectorStore {
  const VectorStore({
    required this.id,
    required this.object,
    required this.createdAt,
    this.usageBytes,
    this.lastActiveAt,
    this.lastUsedAt,
    this.name,
    this.status,
    this.fileCounts,
    this.expiresAfter,
    this.expiresAt,
    this.metadata,
    this.bytes,
  });

  factory VectorStore.fromJson(Map<String, dynamic> j) => VectorStore(
        id: j['id'] as String,
        object: j['object'] as String,
        createdAt: j['created_at'] as int,
        usageBytes: (j['usage_bytes'] as num?)?.toInt(),
        lastActiveAt: (j['last_active_at'] as num?)?.toInt(),
        lastUsedAt: (j['last_used_at'] as num?)?.toInt(),
        name: j['name'] as String?,
        status: j['status'] == null ? null : VectorStoreStatus.fromJson(j['status'] as String),
        fileCounts: j['file_counts'] == null ? null : VectorStoreFileCounts.fromJson(j['file_counts'] as Map<String, dynamic>),
        expiresAfter: j['expires_after'] == null ? null : ExpiresAfter.fromJson(j['expires_after'] as Map<String, dynamic>),
        expiresAt: (j['expires_at'] as num?)?.toInt(),
        metadata: (j['metadata'] as Map?)?.cast<String, dynamic>(),
        bytes: (j['bytes'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "object": object,
      "created_at": createdAt,
      "usage_bytes": usageBytes,
      "last_active_at": lastActiveAt,
      "last_used_at": lastUsedAt,
      "name": name,
      "status": status,
      if (fileCounts != null) "file_counts": fileCounts?.toJson(),
      if (expiresAfter != null) "expires_after": expiresAfter?.toJson(),
      "expires_at": expiresAt,
      "metadata": metadata,
      "bytes": bytes,
    };
  }

  final String id;
  final String object; // "vector_store"
  final int createdAt;

  final int? usageBytes;
  final int? lastActiveAt;
  final int? lastUsedAt;
  final String? name;
  final VectorStoreStatus? status;
  final VectorStoreFileCounts? fileCounts;
  final ExpiresAfter? expiresAfter;
  final int? expiresAt;
  final Map<String, dynamic>? metadata;
  final int? bytes;
}

class VectorStoreList {
  const VectorStoreList({
    required this.object,
    required this.data,
    required this.hasMore,
    this.firstId,
    this.lastId,
  });

  factory VectorStoreList.fromJson(Map<String, dynamic> j) => VectorStoreList(
        object: j['object'] as String,
        data: (j['data'] as List).cast<Map<String, dynamic>>().map(VectorStore.fromJson).toList(),
        hasMore: j['has_more'] as bool? ?? false,
        firstId: j['first_id'] as String?,
        lastId: j['last_id'] as String?,
      );

  final String object; // "list"
  final List<VectorStore> data;
  final bool hasMore;
  final String? firstId;
  final String? lastId;
}

/* ── Vector Store files ──────────────────────────────────────────────────── */

enum VectorStoreFileStatus with JsonEnum {
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled'),
  failed('failed');

  const VectorStoreFileStatus(this.value);
  final String value;
  static VectorStoreFileStatus fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

class VectorStoreFileError {
  const VectorStoreFileError({required this.code, required this.message});

  factory VectorStoreFileError.fromJson(Map<String, dynamic> j) =>
      VectorStoreFileError(code: j['code'] as String, message: j['message'] as String);

  final String code; // server_error | rate_limit_exceeded
  final String message;
}

class VectorStoreFile {
  const VectorStoreFile({
    required this.id,
    required this.object,
    required this.createdAt,
    required this.vectorStoreId,
    this.usageBytes,
    this.status,
    this.lastError,
    this.chunkingStrategy,
    this.attributes,
  });

  factory VectorStoreFile.fromJson(Map<String, dynamic> j) => VectorStoreFile(
        id: j['id'] as String,
        object: j['object'] as String, // "vector_store.file"
        createdAt: j['created_at'] as int,
        vectorStoreId: j['vector_store_id'] as String,
        usageBytes: (j['usage_bytes'] as num?)?.toInt(),
        status: j['status'] == null ? null : VectorStoreFileStatus.fromJson(j['status'] as String),
        lastError: j['last_error'] == null ? null : VectorStoreFileError.fromJson(j['last_error'] as Map<String, dynamic>),
        chunkingStrategy: j['chunking_strategy'] == null ? null : ChunkingStrategy.fromJson(j['chunking_strategy'] as Map<String, dynamic>),
        attributes: (j['attributes'] as Map?)?.cast<String, dynamic>(),
      );

  final String id;
  final String object;
  final int createdAt;
  final String vectorStoreId;
  final int? usageBytes;
  final VectorStoreFileStatus? status;
  final VectorStoreFileError? lastError;
  final ChunkingStrategy? chunkingStrategy;
  final Map<String, dynamic>? attributes;
}

class VectorStoreFileList {
  const VectorStoreFileList({
    required this.object,
    required this.data,
    required this.hasMore,
    this.firstId,
    this.lastId,
  });

  factory VectorStoreFileList.fromJson(Map<String, dynamic> j) => VectorStoreFileList(
        object: j['object'] as String,
        data: (j['data'] as List).cast<Map<String, dynamic>>().map(VectorStoreFile.fromJson).toList(),
        hasMore: j['has_more'] as bool? ?? false,
        firstId: j['first_id'] as String?,
        lastId: j['last_id'] as String?,
      );

  final String object; // "list"
  final List<VectorStoreFile> data;
  final bool hasMore;
  final String? firstId;
  final String? lastId;
}

/* ── Vector Store file batches ───────────────────────────────────────────── */

enum VectorStoreFileBatchStatus with JsonEnum {
  inProgress('in_progress'),
  completed('completed'),
  cancelled('cancelled'),
  failed('failed');

  const VectorStoreFileBatchStatus(this.value);
  final String value;
  static VectorStoreFileBatchStatus fromJson(String raw) => JsonEnum.fromJson(values, raw);
}

class VectorStoreFileBatch {
  const VectorStoreFileBatch({
    required this.id,
    required this.object,
    required this.createdAt,
    required this.vectorStoreId,
    required this.status,
    required this.fileCounts,
  });

  factory VectorStoreFileBatch.fromJson(Map<String, dynamic> j) => VectorStoreFileBatch(
        id: j['id'] as String,
        object: j['object'] as String, // "vector_store.file_batch"
        createdAt: j['created_at'] as int,
        vectorStoreId: j['vector_store_id'] as String,
        status: VectorStoreFileBatchStatus.fromJson(j['status'] as String),
        fileCounts: VectorStoreFileCounts.fromJson(j['file_counts'] as Map<String, dynamic>),
      );

  final String id;
  final String object;
  final int createdAt;
  final String vectorStoreId;
  final VectorStoreFileBatchStatus status;
  final VectorStoreFileCounts fileCounts;
}

class VectorStoreFileBatchFilesList {
  const VectorStoreFileBatchFilesList({
    required this.object,
    required this.data,
    required this.hasMore,
    this.firstId,
    this.lastId,
  });

  factory VectorStoreFileBatchFilesList.fromJson(Map<String, dynamic> j) => VectorStoreFileBatchFilesList(
        object: j['object'] as String,
        data: (j['data'] as List).cast<Map<String, dynamic>>().map(VectorStoreFile.fromJson).toList(),
        hasMore: j['has_more'] as bool? ?? false,
        firstId: j['first_id'] as String?,
        lastId: j['last_id'] as String?,
      );

  final String object; // "list"
  final List<VectorStoreFile> data;
  final bool hasMore;
  final String? firstId;
  final String? lastId;
}

/* ── Vector Store search results ─────────────────────────────────────────── */

class VectorStoreSearchContent {
  const VectorStoreSearchContent.text(this.text) : type = 'text';

  factory VectorStoreSearchContent.fromJson(Map<String, dynamic> j) {
    final t = j['type'] as String? ?? 'text';
    if (t == 'text') return VectorStoreSearchContent.text(j['text'] as String);
    return VectorStoreSearchContent.text((j['text'] ?? '').toString());
  }

  final String type;
  final String text;

  Map<String, dynamic> toJson() => {'type': type, 'text': text};
}

class VectorStoreSearchResult {
  const VectorStoreSearchResult({
    required this.fileId,
    required this.filename,
    required this.score,
    required this.content,
    this.attributes,
  });

  factory VectorStoreSearchResult.fromJson(Map<String, dynamic> j) => VectorStoreSearchResult(
        fileId: j['file_id'] as String,
        filename: j['filename'] as String,
        score: (j['score'] as num?)?.toDouble() ?? 0.0,
        attributes: (j['attributes'] as Map?)?.cast<String, dynamic>(),
        content: (j['content'] as List).cast<Map<String, dynamic>>().map(VectorStoreSearchContent.fromJson).toList(),
      );

  final String fileId;
  final String filename;
  final double score;
  final Map<String, dynamic>? attributes;
  final List<VectorStoreSearchContent> content;
}

class VectorStoreSearchResultsPage {
  const VectorStoreSearchResultsPage({
    required this.object,
    required this.searchQuery,
    required this.data,
    required this.hasMore,
    this.nextPage,
  });

  factory VectorStoreSearchResultsPage.fromJson(Map<String, dynamic> j) => VectorStoreSearchResultsPage(
        object: j['object'] as String,
        searchQuery: j['search_query'],
        data: (j['data'] as List).cast<Map<String, dynamic>>().map(VectorStoreSearchResult.fromJson).toList(),
        hasMore: j['has_more'] as bool? ?? false,
        nextPage: j['next_page'],
      );

  final String object; // "vector_store.search_results.page"
  final dynamic searchQuery;
  final List<VectorStoreSearchResult> data;
  final bool hasMore;
  final dynamic nextPage; // token or null
}

// ─────────────────────────────────────────────────────────────────────────────
// Vector Stores — API
// Add as an extension next to your other API extensions (ResponsesAPI, ImagesAPI).
// ─────────────────────────────────────────────────────────────────────────────

extension VectorStoresAPI on OpenAIClient {
  static const _betaHeader = {'OpenAI-Beta': 'assistants=v2'};

  /* ── Vector Stores ───────────────────────────────────────────────────── */

  Future<VectorStore> createVectorStore({
    String? name,
    List<String>? fileIds,
    Map<String, String>? metadata,
    ExpiresAfter? expiresAfter,
    ChunkingStrategy? chunkingStrategy, // only applies if fileIds is non-empty
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (fileIds != null && fileIds.isNotEmpty) 'file_ids': fileIds,
      if (metadata != null) 'metadata': metadata,
      if (expiresAfter != null) 'expires_after': expiresAfter.toJson(),
      if (chunkingStrategy != null) 'chunking_strategy': chunkingStrategy.toJson(),
    };

    final resp = await postJson('/vector_stores', body, headers: _betaHeader);
    if (resp.statusCode == 200) {
      return VectorStore.fromJson(jsonDecode(resp.body));
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  Future<VectorStoreList> listVectorStores({
    String? after,
    String? before,
    int? limit,
    SortOrder? order,
  }) async {
    final qp = <String, String>{
      if (after != null) 'after': after,
      if (before != null) 'before': before,
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order.toJson(),
    };

    final url = baseUrl.resolve('vector_stores').replace(queryParameters: qp.isEmpty ? null : qp);

    final res = await httpClient.get(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return VectorStoreList.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  Future<VectorStore> retrieveVectorStore(String vectorStoreId) async {
    final url = baseUrl.resolve('vector_stores/$vectorStoreId');
    final res = await httpClient.get(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return VectorStore.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  Future<VectorStore> modifyVectorStore(
    String vectorStoreId, {
    String? name,
    Map<String, String>? metadata,
    ExpiresAfter? expiresAfter, // pass null to clear: use expiresAfterNull=true
    bool expiresAfterNull = false,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (metadata != null) 'metadata': metadata,
      if (expiresAfterNull) 'expires_after': null,
      if (expiresAfter != null) 'expires_after': expiresAfter.toJson(),
    };

    final resp = await postJson('/vector_stores/$vectorStoreId', body, headers: _betaHeader);
    if (resp.statusCode == 200) {
      return VectorStore.fromJson(jsonDecode(resp.body));
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  Future<DeletionStatus> deleteVectorStore(String vectorStoreId) async {
    final url = baseUrl.resolve('vector_stores/$vectorStoreId');
    final res = await httpClient.delete(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return DeletionStatus.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /* ── Vector Store Search ────────────────────────────────────────────── */

  Future<VectorStoreSearchResultsPage> searchVectorStore(
    String vectorStoreId, {
    required dynamic query, // String or List<String>
    FileSearchFilter? filters,
    int? maxNumResults, // 1..50 (defaults to 10)
    RankingOptions? rankingOptions,
    bool? rewriteQuery,
  }) async {
    final body = <String, dynamic>{
      'query': query,
      if (filters != null) 'filters': filters.toJson(),
      if (maxNumResults != null) 'max_num_results': maxNumResults,
      if (rankingOptions != null) 'ranking_options': rankingOptions.toJson(),
      if (rewriteQuery != null) 'rewrite_query': rewriteQuery,
    };

    final resp = await postJson('/vector_stores/$vectorStoreId/search', body, headers: _betaHeader);
    if (resp.statusCode == 200) {
      return VectorStoreSearchResultsPage.fromJson(jsonDecode(resp.body));
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  /* ── Vector Store Files ─────────────────────────────────────────────── */

  Future<VectorStoreFile> createVectorStoreFile({
    required String vectorStoreId,
    required String fileId,
    Map<String, dynamic>? attributes, // string/number/boolean allowed
    ChunkingStrategy? chunkingStrategy,
  }) async {
    final body = <String, dynamic>{
      'file_id': fileId,
      if (attributes != null) 'attributes': attributes,
      if (chunkingStrategy != null) 'chunking_strategy': chunkingStrategy.toJson(),
    };

    final resp = await postJson('/vector_stores/$vectorStoreId/files', body, headers: _betaHeader);
    if (resp.statusCode == 200) {
      return VectorStoreFile.fromJson(jsonDecode(resp.body));
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  Future<VectorStoreFileList> listVectorStoreFiles(
    String vectorStoreId, {
    String? filter, // in_progress | completed | failed | cancelled
    String? after,
    String? before,
    int? limit,
    SortOrder? order,
  }) async {
    final qp = <String, String>{
      if (filter != null) 'filter': filter,
      if (after != null) 'after': after,
      if (before != null) 'before': before,
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order.toJson(),
    };

    final url = baseUrl.resolve('vector_stores/$vectorStoreId/files').replace(queryParameters: qp.isEmpty ? null : qp);

    final res = await httpClient.get(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return VectorStoreFileList.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  Future<VectorStoreFile> retrieveVectorStoreFile({
    required String vectorStoreId,
    required String fileId,
  }) async {
    final url = baseUrl.resolve('vector_stores/$vectorStoreId/files/$fileId');
    final res = await httpClient.get(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return VectorStoreFile.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  Future<Map<String, dynamic>> retrieveVectorStoreFileContent({
    required String vectorStoreId,
    required String fileId,
  }) async {
    final url = baseUrl.resolve('vector_stores/$vectorStoreId/files/$fileId/content');
    final res = await httpClient.get(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  Future<VectorStoreFile> updateVectorStoreFileAttributes({
    required String vectorStoreId,
    required String fileId,
    required Map<String, dynamic> attributes, // string/number/boolean
  }) async {
    final resp = await postJson(
      '/vector_stores/$vectorStoreId/files/$fileId',
      {'attributes': attributes},
      headers: _betaHeader,
    );
    if (resp.statusCode == 200) {
      return VectorStoreFile.fromJson(jsonDecode(resp.body));
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  Future<DeletionStatus> deleteVectorStoreFile({
    required String vectorStoreId,
    required String fileId,
  }) async {
    final url = baseUrl.resolve('vector_stores/$vectorStoreId/files/$fileId');
    final res = await httpClient.delete(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return DeletionStatus.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  /* ── Vector Store File Batches ──────────────────────────────────────── */

  Future<VectorStoreFileBatch> createVectorStoreFileBatch({
    required String vectorStoreId,
    required List<String> fileIds,
    Map<String, dynamic>? attributes,
    ChunkingStrategy? chunkingStrategy,
  }) async {
    final body = <String, dynamic>{
      'file_ids': fileIds,
      if (attributes != null) 'attributes': attributes,
      if (chunkingStrategy != null) 'chunking_strategy': chunkingStrategy.toJson(),
    };

    final resp = await postJson('/vector_stores/$vectorStoreId/file_batches', body, headers: _betaHeader);
    if (resp.statusCode == 200) {
      return VectorStoreFileBatch.fromJson(jsonDecode(resp.body));
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  Future<VectorStoreFileBatch> retrieveVectorStoreFileBatch({
    required String vectorStoreId,
    required String batchId,
  }) async {
    final url = baseUrl.resolve('vector_stores/$vectorStoreId/file_batches/$batchId');
    final res = await httpClient.get(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return VectorStoreFileBatch.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }

  Future<VectorStoreFileBatch> cancelVectorStoreFileBatch({
    required String vectorStoreId,
    required String batchId,
  }) async {
    final resp = await httpClient.post(
      baseUrl.resolve('vector_stores/$vectorStoreId/file_batches/$batchId/cancel'),
      headers: getHeaders({..._betaHeader}) ?? {},
    );
    if (resp.statusCode == 200) {
      return VectorStoreFileBatch.fromJson(jsonDecode(resp.body));
    }
    throw OpenAIRequestException.fromHttpResponse(resp);
  }

  Future<VectorStoreFileBatchFilesList> listVectorStoreFilesInBatch({
    required String vectorStoreId,
    required String batchId,
    String? filter, // in_progress | completed | failed | cancelled
    String? after,
    String? before,
    int? limit,
    SortOrder? order,
  }) async {
    final qp = <String, String>{
      if (filter != null) 'filter': filter,
      if (after != null) 'after': after,
      if (before != null) 'before': before,
      if (limit != null) 'limit': '$limit',
      if (order != null) 'order': order.toJson(),
    };

    final url =
        baseUrl.resolve('vector_stores/$vectorStoreId/file_batches/$batchId/files').replace(queryParameters: qp.isEmpty ? null : qp);

    final res = await httpClient.get(url, headers: getHeaders({..._betaHeader}) ?? {});
    if (res.statusCode == 200) {
      return VectorStoreFileBatchFilesList.fromJson(jsonDecode(res.body));
    }
    throw OpenAIRequestException.fromHttpResponse(res);
  }
}
