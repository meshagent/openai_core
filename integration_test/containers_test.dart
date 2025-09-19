// test/containers_test.dart
//
// Be sure to set an `OPENAI_API_KEY` environment variable before running:
// $ OPENAI_API_KEY=sk-... dart test

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/openai_client.dart';
import '../lib/containers.dart';

void main() {
  group('Containers API', () {
    test(
      'create → retrieve → list → delete container',
      timeout: const Timeout(Duration(minutes: 2)),
      () async {
        final apiKey = Platform.environment['OPENAI_API_KEY'];
        if (apiKey == null || apiKey.isEmpty) {
          fail(
            'OPENAI_API_KEY must be set for this integration test. '
            'Set it in your shell before running `dart test`.',
          );
        }

        final client = OpenAIClient(apiKey: apiKey);
        Container? created;
        try {
          // ——— create ———
          final name =
              'Test Container ${DateTime.now().millisecondsSinceEpoch}';
          created = await client.createContainer(
            name: name,
            expiresAfter:
                ContainerExpiresAfter(anchor: 'last_active_at', minutes: 20),
          );

          // ——— assertions: create ———
          expect(created.id, isNotEmpty,
              reason: 'Container id must be present.');
          expect(created.object, equals('container'));
          expect(created.name, equals(name));
          expect(created.status, isNotEmpty,
              reason: 'Container status should be present.');

          // ——— retrieve ———
          final retrieved = await client.retrieveContainer(created.id);

          // ——— assertions: retrieve ———
          expect(retrieved.id, equals(created.id));
          expect(retrieved.name, equals(name));

          // ——— list (with light polling for consistency) ———
          bool found = false;
          for (var i = 0; i < 3; i++) {
            final list = await client.listContainers(limit: 50, order: 'desc');
            expect(list.object, equals('list'));
            if (list.data.any((c) => c.id == created!.id)) {
              found = true;
              break;
            }
            // tiny backoff; helps avoid flakiness on fresh objects
            await Future.delayed(const Duration(seconds: 1));
          }
          expect(found, isTrue,
              reason: 'Newly created container should appear in list().');
        } finally {
          // ——— cleanup ———
          if (created != null) {
            try {
              final del = await client.deleteContainer(created.id);
              expect(del.deleted, isTrue,
                  reason: 'Container should delete cleanly.');
            } catch (_) {
              // Swallow: best-effort cleanup.
            }
          }
          client.close();
        }
      },
    );

    test(
      'container files: upload (multipart) → list → retrieve → content & stream → delete',
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        final apiKey = Platform.environment['OPENAI_API_KEY'];
        if (apiKey == null || apiKey.isEmpty) {
          fail(
            'OPENAI_API_KEY must be set for this integration test. '
            'Set it in your shell before running `dart test`.',
          );
        }

        final client = OpenAIClient(apiKey: apiKey);

        Container? container;
        ContainerFile? cfile;

        try {
          // ——— create container ———
          final name =
              'File Container ${DateTime.now().millisecondsSinceEpoch}';
          container = await client.createContainer(
            name: name,
            expiresAfter:
                ContainerExpiresAfter(anchor: 'last_active_at', minutes: 20),
          );

          // ——— prepare a local test file (already present in repo) ———
          // Re-use the same asset your other tests use.
          final srcPath = 'integration_test/desktop.jpg';
          final src = File(srcPath);
          if (!await src.exists()) {
            fail('Test asset not found at $srcPath');
          }
          final srcBytes = await src.readAsBytes();
          expect(srcBytes.lengthInBytes, greaterThan(10 * 1024),
              reason: 'Fixture looks too small.');

          // ——— upload file (multipart) ———
          cfile = await client.createContainerFile(
            containerId: container.id,
            bytes: srcBytes,
            filename: 'desktop.jpg',
          );

          // ——— assertions: createContainerFile ———
          expect(cfile.id, isNotEmpty);
          expect(cfile.object, equals('container.file'));
          expect(cfile.containerId, equals(container.id));
          expect(cfile.bytes, greaterThan(10 * 1024));
          expect(cfile.path, isNotEmpty,
              reason: 'Path inside container should be set.');

          // ——— list files (light polling) ———
          bool found = false;
          for (var i = 0; i < 3; i++) {
            final list = await client.listContainerFiles(container.id,
                limit: 50, order: 'desc');
            expect(list.object, equals('list'));
            if (list.data.any((f) => f.id == cfile!.id)) {
              found = true;
              break;
            }
            await Future.delayed(const Duration(seconds: 1));
          }
          expect(found, isTrue,
              reason: 'Uploaded container file should appear in list().');

          // ——— retrieve file metadata ———
          final meta =
              await client.retrieveContainerFile(container.id, cfile.id);
          expect(meta.id, equals(cfile.id));
          expect(meta.containerId, equals(container.id));
          expect(meta.bytes, equals(cfile.bytes));

          // ——— fetch content (bytes) ———
          final content =
              await client.retrieveContainerFileContent(container.id, cfile.id);
          expect(content.lengthInBytes, equals(meta.bytes),
              reason: 'Downloaded bytes should match server-reported size.');

          // Sanity check: JPEG magic number (FF D8 …)
          expect(content[0], equals(0xFF));
          expect(content[1], equals(0xD8));

          // ——— stream content and compare ———
          final builder = BytesBuilder(copy: false);
          await for (final chunk
              in client.streamContainerFileContent(container.id, cfile.id)) {
            builder.add(chunk);
          }
          final streamed = builder.toBytes();
          expect(streamed.lengthInBytes, equals(content.lengthInBytes));
          // Compare first/last 16 bytes to avoid giant equality diff noise.
          final head = content.sublist(0, 16);
          final headStream = streamed.sublist(0, 16);
          final tail = content.sublist(content.length - 16);
          final tailStream = streamed.sublist(streamed.length - 16);
          expect(base64Encode(headStream), equals(base64Encode(head)));
          expect(base64Encode(tailStream), equals(base64Encode(tail)));

          // ——— delete file ———
          final deleted =
              await client.deleteContainerFile(container.id, cfile.id);
          expect(deleted.deleted, isTrue,
              reason: 'Container file should delete cleanly.');
        } finally {
          // ——— cleanup ———
          try {
            if (container != null) {
              // Best-effort: container deletion will also clean any leftover files.
              final del = await client.deleteContainer(container.id);
              expect(del.deleted, isTrue);
            }
          } catch (_) {
            // Ignore: best-effort cleanup.
          }
          client.close();
        }
      },
    );
  });
}
