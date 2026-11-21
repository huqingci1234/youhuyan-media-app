import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:youhuyan_media/models/tvbox_config_entry.dart';
import 'package:youhuyan_media/repositories/tvbox_config_repository.dart';

const validDocumentA = '''
{
  "name": "测试接口 A",
  "sites": [{"key": "site-a", "name": "测试站点"}],
  "lives": [],
  "parses": []
}
''';

const validDocumentB = '''
{
  "name": "测试接口 B",
  "sites": [],
  "lives": [{"name": "测试直播", "channels": []}],
  "parses": []
}
''';

const emptyDocument = '''
{
  "name": "空配置",
  "sites": [],
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
      clock: () => DateTime.utc(2026, 11, 21, 2, 0, 0),
    );
  });

  tearDown(() async {
    await repository.close();
  });

  test('supports multiple profiles and exactly one default', () async {
    final first = await repository.addConfig(
      rawJson: validDocumentA,
      sourceUrl: 'https://example.com/a.json',
    );
    final second = await repository.addConfig(
      rawJson: validDocumentB,
      sourceUrl: 'https://example.com/b.json',
    );

    expect(first.isDefault, isTrue);
    expect(second.isDefault, isFalse);

    final selected = await repository.setDefaultConfig(second.id);
    final profiles = await repository.listConfigs();
    final defaults = profiles.where((profile) => profile.isDefault).toList();

    expect(selected.id, second.id);
    expect(defaults, hasLength(1));
    expect(defaults.single.id, second.id);
    expect((await repository.getDefaultConfig())?.id, second.id);
  });

  test('rejects duplicate HTTPS URLs after normalization', () async {
    await repository.addConfig(
      rawJson: validDocumentA,
      sourceUrl: 'https://EXAMPLE.com:443/config/../config.json#section',
    );

    await expectLater(
      repository.addConfig(
        rawJson: validDocumentB,
        sourceUrl: 'https://example.com/config.json',
      ),
      throwsA(isA<DuplicateConfigUrlException>()),
    );
  });

  test('failed refresh preserves the last successful cached document', () async {
    final original = await repository.addConfig(
      rawJson: validDocumentA,
      sourceUrl: 'https://example.com/config.json',
    );

    await expectLater(
      repository.refreshWithContent(
        id: original.id,
        rawJson: emptyDocument,
      ),
      throwsA(isA<FormatException>()),
    );

    final afterFailure = await repository.getConfig(original.id);
    expect(afterFailure.cachedJson, original.cachedJson);
    expect(afterFailure.siteCount, original.siteCount);
    expect(afterFailure.lastSuccessAt, original.lastSuccessAt);
    expect(afterFailure.lastStatus, ConfigLastStatus.error);
    expect(afterFailure.lastError, isNotNull);
    expect(afterFailure.lastAttemptAt, isNotNull);
  });

  test('URL edit requires a valid document and rejects another profile URL',
      () async {
    final first = await repository.addConfig(
      rawJson: validDocumentA,
      sourceUrl: 'https://example.com/a.json',
    );
    final second = await repository.addConfig(
      rawJson: validDocumentB,
      sourceUrl: 'https://example.com/b.json',
    );

    await expectLater(
      repository.updateConfig(
        id: first.id,
        rawJson: validDocumentA,
        sourceUrl: 'https://example.com/b.json',
      ),
      throwsA(isA<DuplicateConfigUrlException>()),
    );

    final unchanged = await repository.getConfig(first.id);
    expect(unchanged.sourceUrl, 'https://example.com/a.json');
    expect((await repository.getConfig(second.id)).sourceUrl,
        'https://example.com/b.json');
  });

  test('deleting the default promotes the earliest remaining profile',
      () async {
    final first = await repository.addConfig(
      rawJson: validDocumentA,
      sourceUrl: 'https://example.com/a.json',
    );
    final second = await repository.addConfig(
      rawJson: validDocumentB,
      sourceUrl: 'https://example.com/b.json',
    );

    await repository.deleteConfig(first.id);

    final remaining = await repository.listConfigs();
    expect(remaining, hasLength(1));
    expect(remaining.single.id, second.id);
    expect(remaining.single.isDefault, isTrue);
  });

  test('local JSON imports do not require a remote URL', () async {
    final entry = await repository.addConfig(
      rawJson: validDocumentA,
      name: '本地导入',
    );

    expect(entry.sourceType, ConfigSourceType.localFile);
    expect(entry.sourceUrl, isNull);
    expect(entry.name, '本地导入');
  });
}
