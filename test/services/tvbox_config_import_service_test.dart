import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:youhuyan_media/repositories/tvbox_config_repository.dart';
import 'package:youhuyan_media/services/tvbox_config_import_service.dart';

const validConfig = '''
{
  "name": "授权测试接口",
  "sites": [{"key": "demo", "name": "演示站点"}],
  "lives": [],
  "parses": []
}
''';

void main() {
  late TvBoxConfigRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    repository = TvBoxConfigRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
      clock: () => DateTime.utc(2026, 11, 22, 10, 0, 0),
    );
  });

  tearDown(() async {
    await repository.close();
  });

  TvBoxConfigImportService service(
    http.Client Function() factory, {
    Duration timeout = const Duration(seconds: 2),
  }) {
    return TvBoxConfigImportService(
      repository: repository,
      clientFactory: factory,
      requestTimeout: timeout,
    );
  }

  test('imports a valid remote HTTPS JSON config', () async {
    final importer = service(
      () => MockClient((request) async {
        expect(request.url.scheme, 'https');
        expect(request.followRedirects, isFalse);
        expect(request.headers['accept'], 'application/json');
        return http.Response(validConfig, 200);
      }),
    );

    final entry = await importer.importRemote(
      url: 'https://EXAMPLE.com:443/config.json#section',
    );

    expect(entry.sourceUrl, 'https://example.com/config.json');
    expect(entry.name, '授权测试接口');
    expect(entry.siteCount, 1);
    expect(entry.isDefault, isTrue);
  });

  test('rejects an HTTPS redirect that downgrades to HTTP', () async {
    final importer = service(
      () => MockClient((request) async => http.Response(
            '',
            302,
            headers: {'location': 'http://example.com/insecure.json'},
          )),
    );

    await expectLater(
      importer.importRemote(url: 'https://example.com/config.json'),
      throwsA(isA<FormatException>()),
    );
    expect(await repository.listConfigs(), isEmpty);
  });

  test('rejects non-200 responses without creating a config', () async {
    final importer = service(
      () => MockClient((request) async => http.Response('unavailable', 503)),
    );

    await expectLater(
      importer.importRemote(url: 'https://example.com/config.json'),
      throwsA(isA<StateError>()),
    );
    expect(await repository.listConfigs(), isEmpty);
  });

  test('rejects a response larger than 2 MiB before JSON parsing', () async {
    final oversized = List<int>.filled(
      TvBoxConfigImportService.maxDocumentBytes + 1,
      65,
    );
    final importer = service(
      () => MockClient((request) async => http.Response.bytes(oversized, 200)),
    );

    await expectLater(
      importer.importRemote(url: 'https://example.com/config.json'),
      throwsA(isA<FormatException>()),
    );
    expect(await repository.listConfigs(), isEmpty);
  });

  test('failed remote refresh preserves the successful offline cache', () async {
    final original = await repository.addConfig(
      rawJson: validConfig,
      sourceUrl: 'https://example.com/config.json',
    );
    final importer = service(
      () => MockClient((request) async => http.Response('server error', 502)),
    );

    await expectLater(
      importer.refreshRemote(original.id),
      throwsA(isA<StateError>()),
    );

    final afterFailure = await repository.getConfig(original.id);
    expect(afterFailure.cachedJson, original.cachedJson);
    expect(afterFailure.lastSuccessAt, original.lastSuccessAt);
    expect(afterFailure.lastStatus.name, 'error');
    expect(afterFailure.lastError, contains('502'));
  });

  test('imports a local JSON stream and enforces the same size limit', () async {
    final importer = service(() => MockClient((request) async {
          fail('A local import must not make a network request');
          return http.Response('', 500);
        }));

    final entry = await importer.importLocalStream(
      fileName: 'my-authorized-config.json',
      bytes: Stream<List<int>>.value(utf8.encode(validConfig)),
    );
    expect(entry.sourceUrl, isNull);
    expect(entry.name, 'my-authorized-config.json');
    expect(entry.siteCount, 1);

    await expectLater(
      importer.importLocalStream(
        fileName: 'too-large.json',
        bytes: Stream<List<int>>.value(
          List<int>.filled(TvBoxConfigImportService.maxDocumentBytes + 1, 65),
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await repository.listConfigs(), hasLength(1));
  });

  test('applies one total timeout to a stalled response', () async {
    final neverCompletes = Completer<http.Response>();
    final importer = service(
      () => MockClient((request) => neverCompletes.future),
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      importer.importRemote(url: 'https://example.com/config.json'),
      throwsA(isA<TimeoutException>()),
    );
    expect(await repository.listConfigs(), isEmpty);
  });
}
