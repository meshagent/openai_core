// ─────────────────────────────────────────────────────────────────────────────
// Vector Stores — end‑to‑end integration test
// Requires: OPENAI_API_KEY in env. Optional: OPENAI_BASE_URL
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

// Import your local library units, same style as your other tests.
// If you split models into separate files, keep these imports aligned with your project.
import '../lib/files.dart';
import '../lib/openai_client.dart';
import '../lib/vector_stores.dart';
import '../lib/responses.dart';

/// Uploads a small text file to /v1/files and returns the File ID (e.g. "file_...").
Future<String> _uploadTextFile(
    OpenAIClient client, String filename, String text) async {
  final upload = await client.uploadFileBytes(
      purpose: FilePurpose.userData,
      fileBytes: utf8.encode(text),
      filename: filename);
  return upload.id;
}

/// Polls until the given condition returns `true` or times out.
Future<T> _pollUntil<T>({
  required Future<T> Function() get,
  required bool Function(T) isDone,
  Duration timeout = const Duration(minutes: 2),
  Duration interval = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  T last;
  while (true) {
    last = await get();
    if (isDone(last)) return last;
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for condition', timeout);
    }
    await Future.delayed(interval);
  }
}

void main() {
  final hasKey = Platform.environment.containsKey('OPENAI_API_KEY');

  group('Vector Stores API (integration)', () {
    late OpenAIClient client;

    setUpAll(() {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      final baseUrl = Platform.environment['OPENAI_BASE_URL'] ??
          'https://api.openai.com/v1/';
      client = OpenAIClient(apiKey: apiKey, baseUrl: baseUrl);
    });

    tearDownAll(() {
      client.close();
    });

    test('end‑to‑end vector store flow', () async {
      // ── 1) Create a vector store
      final store = await client.createVectorStore(
        name: 'SDK E2E – Vector Store',
        metadata: {'suite': 'vector_store_e2e', 'lang': 'en'},
      );

      expect(store.id, startsWith('vs_'));
      expect(store.object, equals('vector_store'));
      expect(store.name, contains('E2E'));

      // Always clean up, even if assertions below fail.
      Future<void> cleanup() async {
        try {
          await client.deleteVectorStore(store.id);
        } catch (_) {
          // swallow; cleanup best-effort
        }
      }

      try {
        // ── 2) List & retrieve

        VectorStoreList listed =
            VectorStoreList(object: "", data: [], hasMore: false);
        for (var i = 0; i < 10; i++) {
          listed = await client.listVectorStores(limit: 10);

          if (listed.data.length > 0) {
            break;
          }

          await Future.delayed(Duration(seconds: 1));
        }
        expect(listed.data.any((s) => s.id == store.id), isTrue,
            reason:
                'Created store should appear in list ${listed.data.length} ${listed.data.map((x) => x.toJson()).join("\n")}');

        final fetched = await client.retrieveVectorStore(store.id);
        expect(fetched.id, equals(store.id));

        // ── 3) Modify store
        final renamed = await client.modifyVectorStore(
          store.id,
          name: 'SDK E2E – Vector Store v2',
          metadata: {'suite': 'vector_store_e2e', 'version': '2'},
        );
        expect(renamed.name, endsWith('v2'));

        // ── 4) Upload 2 small text files
        final fileId1 = await _uploadTextFile(
          client,
          'return_policy.txt',
          'Our return policy allows returns within 30 days if items are unused.',
        );
        final fileId2 = await _uploadTextFile(
          client,
          'shipping_info.txt',
          'Standard shipping delivers within 5 business days inside the continental US.',
        );

        // ── 5) Attach the first file to the store
        final vsFile1 = await client.createVectorStoreFile(
          vectorStoreId: store.id,
          fileId: fileId1,
          attributes: {
            'author': 'SDK-Test',
            'doc': 'return_policy',
            'version': 1
          },
        );
        expect(vsFile1.id, isNotEmpty);

        // ── 6) Wait for the file to be indexed (status: completed)
        final vsFile1Done = await _pollUntil(
          get: () => client.retrieveVectorStoreFile(
              vectorStoreId: store.id, fileId: vsFile1.id),
          isDone: (f) => (f.status?.toJson() ?? '') == 'completed',
          timeout: const Duration(minutes: 3),
          interval: const Duration(seconds: 2),
        );
        expect(vsFile1Done.status?.toJson(), 'completed');

        // ── 7) Retrieve parsed file content
        final content1 = await client.retrieveVectorStoreFileContent(
            vectorStoreId: store.id, fileId: vsFile1.id);
        final combinedText = jsonEncode(content1);
        expect(combinedText, contains('return policy'));

        // ── 8) Search the vector store
        final searchResults = await client.searchVectorStore(
          store.id,
          query: 'What is the return policy?',
          rankingOptions:
              const RankingOptions(ranker: 'auto', scoreThreshold: 0),
          rewriteQuery: true,
        );
        expect(searchResults.data, isNotEmpty,
            reason: 'Search should return at least one chunk');
        expect(searchResults.data.first.score, greaterThanOrEqualTo(0));

        // ── 9) Update file attributes
        final updatedVsFile1 = await client.updateVectorStoreFileAttributes(
          vectorStoreId: store.id,
          fileId: vsFile1.id,
          attributes: {
            'author': 'SDK-Test',
            'doc': 'return_policy',
            'version_int': 2,
            'published': true
          },
        );
        expect(updatedVsFile1.attributes?['version_int'], 2);
        expect(updatedVsFile1.attributes?['published'], true);

        // ── 10) Create a file batch with the second file
        final batch = await client.createVectorStoreFileBatch(
          vectorStoreId: store.id,
          fileIds: [fileId2],
          attributes: {'source': 'unit_test_batch'},
        );
        expect(batch.id, startsWith('vsfb_'));

        // ── 11) Wait for batch completion
        final batchDone = await _pollUntil(
          get: () => client.retrieveVectorStoreFileBatch(
              vectorStoreId: store.id, batchId: batch.id),
          isDone: (b) => b.status.toJson() == 'completed',
          timeout: const Duration(minutes: 3),
          interval: const Duration(seconds: 2),
        );
        expect(batchDone.fileCounts.completed, greaterThanOrEqualTo(1));

        // ── 12) List files in the batch
        final batchFiles = await client.listVectorStoreFilesInBatch(
          vectorStoreId: store.id,
          batchId: batch.id,
          order: SortOrder.asc,
        );
        expect(batchFiles.data.length, greaterThanOrEqualTo(1));

        // ── 13) List all completed files in the store
        final completedFiles = await client.listVectorStoreFiles(store.id,
            filter: 'completed', order: SortOrder.asc);
        final allFileIds = completedFiles.data.map((f) => f.id).toSet();
        expect(allFileIds.contains(vsFile1.id), isTrue,
            reason: 'Attached file should be present in completed list');

        // ── 14) Search again for shipping to make sure the batch file was indexed
        final search2 = await client.searchVectorStore(store.id,
            query: 'How long does standard shipping take?');
        expect(
          search2.data.any((r) =>
              r.content.any((c) => c.text.toLowerCase().contains('shipping'))),
          isTrue,
        );

        // ── 15) Delete one file and then the store (cleanup inside try/finally)
        final delFile = await client.deleteVectorStoreFile(
            vectorStoreId: store.id, fileId: vsFile1.id);
        expect(delFile.deleted, isTrue);

        final delStore = await client.deleteVectorStore(store.id);
        expect(delStore.deleted, isTrue);
      } finally {
        // If we didn’t reach the explicit delete above due to an early failure,
        // ensure the store is removed to avoid leaking resources.
        await cleanup();
      }
    }, skip: !hasKey, timeout: const Timeout(Duration(minutes: 6)));
  }, skip: !hasKey);
}
