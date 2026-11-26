import 'package:flutter_test/flutter_test.dart';
import 'package:youhuyan_media/services/tvbox_media_response_parser.dart';

void main() {
  const parser = TvBoxMediaResponseParser();

  test('parses a common top-level list and pagination metadata', () {
    final page = parser.parsePage(r'''
    {
      "code": 1,
      "msg": "ok",
      "page": "2",
      "pagecount": "5",
      "limit": "20",
      "total": "96",
      "list": [
        {
          "vod_id": 101,
          "vod_name": "测试电影",
          "vod_pic": "https://media.example/cover.jpg",
          "vod_remarks": "高清",
          "vod_year": "2026",
          "type_name": "电影",
          "vod_content": "仅用于解析器测试",
          "vod_score": 8.6,
          "type_id": 3
        },
        {
          "id": "series-2",
          "title": "测试剧集",
          "category": "剧集"
        }
      ]
    }
    ''');

    expect(page.items, hasLength(2));
    expect(page.items.first.id, '101');
    expect(page.items.first.title, '测试电影');
    expect(page.items.first.coverUrl, 'https://media.example/cover.jpg');
    expect(page.items.first.remarks, '高清');
    expect(page.items.first.year, '2026');
    expect(page.items.first.category, '电影');
    expect(page.items.first.description, '仅用于解析器测试');
    expect(page.items.first.score, '8.6');
    expect(page.items.first.typeId, 3);
    expect(page.currentPage, 2);
    expect(page.pageCount, 5);
    expect(page.pageSize, 20);
    expect(page.totalCount, 96);
    expect(page.hasNextPage, isTrue);
  });

  test('parses nested data.list and supports a terminal page', () {
    final page = parser.parsePage(r'''
    {
      "data": {
        "page": 4,
        "page_count": 4,
        "page_size": 10,
        "totalCount": 30,
        "list": [{"id": "last", "name": "最后一页"}]
      }
    }
    ''');

    expect(page.items.single.id, 'last');
    expect(page.currentPage, 4);
    expect(page.pageCount, 4);
    expect(page.pageSize, 10);
    expect(page.totalCount, 30);
    expect(page.hasNextPage, isFalse);
  });

  test('accepts an empty data array as a valid no-results response', () {
    final page = parser.parsePage(r'{"data": [], "page": 1, "pagecount": 1}');
    expect(page.items, isEmpty);
    expect(page.hasNextPage, isFalse);
  });

  test('skips malformed list entries but keeps valid metadata', () {
    final page = parser.parsePage(r'''
    {
      "list": [
        null,
        5,
        {"vod_name": "缺少 ID 但可用名称作为标识"},
        {"vod_id": "no-title"},
        {"vod_id": "ok", "vod_name": "有效条目"}
      ]
    }
    ''');

    expect(page.items, hasLength(2));
    expect(page.items[0].id, '缺少 ID 但可用名称作为标识');
    expect(page.items[1].id, 'ok');
  });

  test('parses detail metadata and inert multi-source episode labels', () {
    final detail = parser.parseDetail(r'''
    {
      "list": [{
        "vod_id": "movie-7",
        "vod_name": "详情测试影片",
        "vod_content": "剧情简介",
        "vod_director": "导演甲",
        "vod_actor": "演员甲、演员乙",
        "vod_area": "中国",
        "vod_lang": "普通话",
        "vod_play_from": "线路一$$$线路二",
        "vod_play_url": "第1集$https://media.example/one.m3u8#第2集$https://media.example/two.m3u8$$$高清$https://media.example/hd.m3u8"
      }]
    }
    ''');

    expect(detail.item.id, 'movie-7');
    expect(detail.item.title, '详情测试影片');
    expect(detail.item.description, '剧情简介');
    expect(detail.director, '导演甲');
    expect(detail.actors, '演员甲、演员乙');
    expect(detail.area, '中国');
    expect(detail.language, '普通话');
    expect(detail.playbackSources, hasLength(2));
    expect(detail.playbackSources.first.name, '线路一');
    expect(detail.playbackSources.first.episodes, hasLength(2));
    expect(detail.playbackSources.first.episodes.first.name, '第1集');
    expect(
      detail.playbackSources.first.episodes.first.url,
      'https://media.example/one.m3u8',
    );
    expect(detail.playbackSources.last.name, '线路二');
    expect(detail.playbackSources.last.episodes.single.name, '高清');
  });

  test('accepts a direct detail object without a list wrapper', () {
    final detail = parser.parseDetail(
      r'{"vod_id":"direct-1","vod_name":"直接返回详情"}',
    );
    expect(detail.item.id, 'direct-1');
    expect(detail.item.title, '直接返回详情');
    expect(detail.playbackSources, isEmpty);
  });

  test('rejects invalid JSON, wrong containers and missing detail items', () {
    expect(() => parser.parsePage('{bad'), throwsA(isA<FormatException>()));
    expect(() => parser.parsePage('[]'), throwsA(isA<FormatException>()));
    expect(
      () => parser.parsePage(r'{"list": "not-an-array"}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parser.parsePage(r'{"result": []}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parser.parseDetail(r'{"list": []}'),
      throwsA(isA<FormatException>()),
    );
  });
}
