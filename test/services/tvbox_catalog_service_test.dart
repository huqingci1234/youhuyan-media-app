import 'package:flutter_test/flutter_test.dart';

import 'package:youhuyan_media/services/tvbox_catalog_service.dart';

const sampleDocument = '''
{
  "name": "授权测试源",
  "sites": [
    {
      "key": "movie_demo",
      "name": "电影演示站",
      "api": "https://example.invalid/api",
      "type": 3,
      "searchable": 1,
      "quickSearch": true,
      "filterable": "1"
    },
    {"key": "series_demo", "name": "剧集演示站", "searchable": 0},
    {"api": "https://example.invalid/ignored"}
  ],
  "lives": [
    {
      "name": "央视频道",
      "type": 0,
      "url": "https://example.invalid/live.m3u",
      "channels": [
        {"name": "CCTV-1 综合", "url": "https://example.invalid/cctv1.m3u8", "number": 1},
        {"title": "CCTV-5 体育", "url": "https://example.invalid/cctv5.m3u8", "number": "5"}
      ]
    },
    {
      "name": "地方频道",
      "channels": ["上海新闻", "本地生活"]
    },
    {"url": "https://example.invalid/live2.m3u"}
  ]
}
''';

void main() {
  const service = TvBoxCatalogService();

  test('maps common site metadata without executing API fields', () {
    final catalog = service.parseDocument(
      configId: 7,
      configName: '本地授权源',
      rawJson: sampleDocument,
    );

    expect(catalog.configId, 7);
    expect(catalog.configName, '本地授权源');
    expect(catalog.sites, hasLength(2));
    expect(catalog.sites.first.name, '电影演示站');
    expect(catalog.sites.first.api, 'https://example.invalid/api');
    expect(catalog.sites.first.searchable, isTrue);
    expect(catalog.sites.first.quickSearch, isTrue);
    expect(catalog.sites.first.filterable, isTrue);
  });

  test('maps inline live groups and channels but ignores external playlist body', () {
    final catalog = service.parseDocument(
      configId: 1,
      configName: '直播测试',
      rawJson: sampleDocument,
    );

    expect(catalog.liveGroups, hasLength(3));
    expect(catalog.liveChannelCount, 4);
    expect(catalog.liveGroups.first.channels.first.name, 'CCTV-1 综合');
    expect(catalog.liveGroups.first.channels.last.number, 5);
    expect(catalog.liveGroups.last.channels, isEmpty);
    expect(catalog.liveGroups.last.sourceUrl,
        'https://example.invalid/live2.m3u');
  });

  test('searches sites by display name or key case-insensitively', () {
    final catalog = service.parseDocument(
      configId: 1,
      configName: '搜索测试',
      rawJson: sampleDocument,
    );

    expect(catalog.searchSites('电影'), hasLength(1));
    expect(catalog.searchSites('SERIES_DEMO'), hasLength(1));
    expect(catalog.searchSites('not-found'), isEmpty);
  });

  test('searches live groups and individual channel names', () {
    final catalog = service.parseDocument(
      configId: 1,
      configName: '搜索测试',
      rawJson: sampleDocument,
    );

    final groupMatches = catalog.searchLiveGroups('央视频道');
    expect(groupMatches, hasLength(1));
    expect(groupMatches.single.channels, hasLength(2));

    final channelMatches = catalog.searchLiveGroups('cctv-5');
    expect(channelMatches, hasLength(1));
    expect(channelMatches.single.name, '央视频道');
    expect(channelMatches.single.channels, hasLength(1));
    expect(channelMatches.single.channels.single.name, 'CCTV-5 体育');
  });

  test('rejects wrong top-level or array structures', () {
    expect(
      () => service.parseDocument(
        configId: 1,
        configName: '坏配置',
        rawJson: '[]',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => service.parseDocument(
        configId: 1,
        configName: '坏配置',
        rawJson: '{"sites": "not-an-array"}',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
