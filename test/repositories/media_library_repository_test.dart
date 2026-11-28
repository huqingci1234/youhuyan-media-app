import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:youhuyan_media/repositories/tvbox_config_repository.dart';

const _configA = '''
{
  "name": "接口 A",
  "sites": [{"key": "a", "name": "站点 A"}],
  "lives": [],
  "parses": []
}
''';

const _configB = '''
{
  "name": "接口 B",
  "sites": [{"key": "b", "name": "站点 B"}],
  "lives": [{"name": "直播 B", "channels": []}],
  "parses": []
}
''';

void main() {
  late TvBoxConfigRepository repository;
  var now = DateTime.utc(2026, 11, 24, 2);

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    now = DateTime.utc(2026, 11, 24, 2);
    repository = TvBoxConfigRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
      clock: () => now,
    );
  });

  tearDown(() async {
    await repository.close();
  });

  test('favorites are upserted without resetting their creation time', () async {
    final first = await repository.saveFavorite(
      mediaKey: 'site-a:item-01',
      title: '电影一',
      itemJson: '{"id":"item-01","type":"movie"}',
    );

    now = now.add(const Duration(hours: 1));
    final updated = await repository.saveFavorite(
      mediaKey: 'site-a:item-01',
      title: '电影一（更新）',
      itemJson: '{"id":"item-01","type":"movie","year":2026}',
    );

    expect(updated.title, '电影一（更新）');
    expect(updated.createdAt, first.createdAt);
    expect(await repository.listFavorites(), hasLength(1));
    expect(await repository.isFavorite('site-a:item-01'), isTrue);

    await repository.removeFavorite('site-a:item-01');
    expect(await repository.isFavorite('site-a:item-01'), isFalse);
  });

  test('watch progress updates one row and clamps position to duration',
      () async {
    final first = await repository.saveWatchProgress(
      mediaKey: 'site-a:item-02',
      title: '连续剧第二集',
      itemJson: '{"id":"item-02","episode":2}',
      positionMs: 120000,
      durationMs: 1800000,
    );
    expect(first.positionMs, 120000);
    expect(first.progressFraction, closeTo(120000 / 1800000, 0.000001));

    now = now.add(const Duration(minutes: 5));
    final updated = await repository.saveWatchProgress(
      mediaKey: 'site-a:item-02',
      title: '连续剧第二集',
      itemJson: '{"id":"item-02","episode":2}',
      positionMs: 2000000,
      durationMs: 1800000,
    );

    expect(updated.positionMs, 1800000);
    expect(updated.progressFraction, 1);
    expect(updated.updatedAt.isAfter(first.updatedAt), isTrue);
    expect(await repository.listWatchHistory(), hasLength(1));
  });

  test('favorites and history survive config switching and deletion', () async {
    final first = await repository.addConfig(
      rawJson: _configA,
      sourceUrl: 'https://example.com/a.json',
    );
    final second = await repository.addConfig(
      rawJson: _configB,
      sourceUrl: 'https://example.com/b.json',
    );

    await repository.saveFavorite(
      mediaKey: 'site-a:movie-100',
      title: '收藏电影',
      itemJson: '{"id":"movie-100"}',
    );
    await repository.saveWatchProgress(
      mediaKey: 'site-b:series-200-s01e01',
      title: '观看中的剧集',
      itemJson: '{"id":"series-200","season":1,"episode":1}',
      positionMs: 456000,
      durationMs: 2400000,
    );

    await repository.setDefaultConfig(second.id);
    await repository.deleteConfig(first.id);
    expect((await repository.getDefaultConfig())?.id, second.id);

    await repository.deleteConfig(second.id);
    expect(await repository.getDefaultConfig(), isNull);

    final favorites = await repository.listFavorites();
    final history = await repository.listWatchHistory();
    expect(favorites.map((item) => item.mediaKey), ['site-a:movie-100']);
    expect(history.map((item) => item.mediaKey), ['site-b:series-200-s01e01']);
    expect((await repository.getFavorite('site-a:movie-100'))?.title, '收藏电影');
    expect(
      (await repository.getWatchHistoryEntry('site-b:series-200-s01e01'))
          ?.positionMs,
      456000,
    );
  });

  test('rejects invalid media snapshots and negative playback positions',
      () async {
    await expectLater(
      repository.saveFavorite(
        mediaKey: 'site-a:bad',
        title: '坏数据',
        itemJson: 'not-json',
      ),
      throwsA(isA<FormatException>()),
    );

    await expectLater(
      repository.saveWatchProgress(
        mediaKey: 'site-a:bad',
        title: '负数进度',
        itemJson: '{"id":"bad"}',
        positionMs: -1,
        durationMs: 100,
      ),
      throwsArgumentError,
    );
    expect(await repository.listFavorites(), isEmpty);
    expect(await repository.listWatchHistory(), isEmpty);
  });

  test('can remove one history row or clear all history without touching favorites',
      () async {
    await repository.saveFavorite(
      mediaKey: 'site-a:movie-1',
      title: '收藏',
      itemJson: '{"id":1}',
    );
    await repository.saveWatchProgress(
      mediaKey: 'site-a:movie-1',
      title: '观看记录一',
      itemJson: '{"id":1}',
      positionMs: 1000,
      durationMs: 5000,
    );
    await repository.saveWatchProgress(
      mediaKey: 'site-b:movie-2',
      title: '观看记录二',
      itemJson: '{"id":2}',
      positionMs: 2000,
      durationMs: 6000,
    );

    await repository.removeWatchHistory('site-a:movie-1');
    expect(await repository.listWatchHistory(), hasLength(1));
    await repository.clearWatchHistory();
    expect(await repository.listWatchHistory(), isEmpty);
    expect(await repository.listFavorites(), hasLength(1));
  });

  test('limits history page size', () async {
    await expectLater(
      repository.listWatchHistory(limit: 0),
      throwsArgumentError,
    );
    await expectLater(
      repository.listWatchHistory(limit: 1001),
      throwsArgumentError,
    );
  });
}
