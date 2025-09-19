// ─────────────────────────────────────────────────────────────────────────────
// Files API — integration tests
// Requires: OPENAI_API_KEY in env. Optional: OPENAI_BASE_URL
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/openai_client.dart';
import '../lib/files.dart';

// If your Files API is split into its own file (e.g. files.dart), make sure it’s
// imported by your library so these symbols are visible from here.
// The tests assume the FilesAPI extension is compiled in.

void main() {
  final hasKey = Platform.environment.containsKey('OPENAI_API_KEY');

  group('Files API (integration)', () {
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

    test('simple /files flow: upload(list/retrieve/content/delete)', () async {
      // ── 1) Prepare small text payload
      final payload = 'id,name\n1,Ada\n2,Grace\n';
      final bytes = Uint8List.fromList(utf8.encode(payload));

      // ── 2) Upload file (purpose: user_data is broadly allowed)
      final up = await client.uploadFileBytes(
        purpose: FilePurpose.userData,
        fileBytes: bytes,
        filename: 'contacts.csv',
        // Optional TTL example:
        // expiresAfter: FileExpiresAfter(anchor: 'created_at', seconds: 7 * 24 * 3600),
      );

      // Ensure cleanup even if later assertions fail
      Future<void> cleanup() async {
        try {
          await client.deleteFile(up.id);
        } catch (_) {}
      }

      try {
        expect(up.id, startsWith('file-'));
        expect(up.object, equals('file'));
        expect(up.filename, equals('contacts.csv'));
        expect(up.purpose, FilePurpose.userData);

        // ── 3) List files (optionally filter by purpose)
        final listed = await client.listFiles(limit: 50, purpose: 'user_data');
        expect(listed.data.any((f) => f.id == up.id), isTrue,
            reason: 'Uploaded file should appear in list');

        // ── 4) Retrieve metadata
        final meta = await client.retrieveFile(up.id);
        expect(meta.id, equals(up.id));
        expect(meta.filename, equals('contacts.csv'));
        expect(meta.bytes, greaterThan(0));
      } finally {
        // ── 6) Delete
        final del = await client.deleteFile(up.id);
        expect(del.deleted, isTrue);
        await cleanup();
      }
    }, skip: !hasKey, timeout: const Timeout(Duration(minutes: 2)));

    test(
        'large /uploads flow: create → add parts → complete → verify file → delete',
        () async {
      // Prepare a moderately small buffer, split into multiple parts (<=64MB; we’ll use tiny parts)
      final text = List.generate(8192, (i) => 'line_$i')
          .join('\n'); // ~> a few hundred KB
      final data = Uint8List.fromList(utf8.encode(text));
      final chunkSize =
          16 * 1024; // 16 KB parts for the test (well under 64 MB)

      // ── 1) Create upload session
      final upload = await client.createUpload(
        bytes: data.length,
        filename: 'large_test.txt',
        mimeType: 'text/plain',
        purpose: FilePurpose.userData,
        // Optional TTL:
        // expiresAfter: FileExpiresAfter(anchor: 'created_at', seconds: 3600),
      );
      expect(upload.status, equals('pending'));
      expect(upload.id, startsWith('upload_'));

      // Ensure cleanup for the created file after completion
      String? createdFileId;
      Future<void> cleanup() async {
        if (createdFileId != null) {
          try {
            final del = await client.deleteFile(createdFileId);
            expect(del.deleted, isTrue);
          } catch (_) {}
        }
      }

      try {
        // ── 2) Add parts in order
        final partIds = <String>[];
        for (int offset = 0; offset < data.length; offset += chunkSize) {
          final end = (offset + chunkSize < data.length)
              ? offset + chunkSize
              : data.length;
          final part = await client.addUploadPart(
              uploadId: upload.id, data: data.sublist(offset, end));
          expect(part.id, startsWith('part_'));
          partIds.add(part.id);
        }
        expect(partIds, isNotEmpty);

        // ── 3) Complete upload with ordered part IDs
        final completed =
            await client.completeUpload(uploadId: upload.id, partIds: partIds);
        expect(completed.status, equals('completed'));
        expect(completed.file, isNotNull);
        expect(completed.file!.id, startsWith('file-'));
        expect(completed.file!.filename, equals('large_test.txt'));
        createdFileId = completed.file!.id;

        // ── 4) Verify: retrieve metadata & content
        final meta = await client.retrieveFile(createdFileId);
        expect(meta.bytes, equals(data.length));
      } finally {
        await cleanup();
      }
    }, skip: !hasKey, timeout: const Timeout(Duration(minutes: 3)));

    test('cancel /uploads: create → cancel (no file created)', () async {
      final small = Uint8List.fromList(
          utf8.encode('temporary upload that will be cancelled'));
      final up = await client.createUpload(
        bytes: small.length,
        filename: 'cancel_me.txt',
        mimeType: 'text/plain',
        purpose: FilePurpose.userData,
      );
      expect(up.status, equals('pending'));

      final cancelled = await client.cancelUpload(up.id);
      expect(cancelled.status, equals('cancelled'));

      // No file should be created on cancel
      expect(cancelled.file, isNull);
    }, skip: !hasKey, timeout: const Timeout(Duration(minutes: 1)));
  }, skip: !hasKey);
}
