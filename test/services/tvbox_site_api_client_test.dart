import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:youhuyan_media/services/tvbox_site_api_client.dart';

void main() {
  TvBoxSiteApiClient client(
    http.Client Function() factory, {
    Duration timeout = const Duration(seconds: 2),
    int maxResponseBytes = 2 * 1024 * 1024,
    int maxRedirects = 3,
  }) {
    return TvBoxSiteApiClient(
      clientFactory: factory,
      requestTimeout: timeout,
      maxResponseBytes: maxResponseBytes,
      maxRedirects: maxRedirects,
    );
  }

  test('fetches a page over HTTPS and preserves existing query parameters',
      () async {
    final api = client(
      () => MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'example.com');
        expect(request.url.queryParameters['token'], 'demo');
        expect(request.url.queryParameters['ac'], 'list');
        expect(request.url.queryParameters['pg'], '2');
        expect(request.followRedirects, isFalse);
        expect(request.headers['accept'], 'application/json');

        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'page': 2,
            'pagecount': 3,
            'list': [
              {'vod_id': 7, 'vod_name': '仅作网络层测试的影片'},
            ],
          })),
          200,
        );
      }),
    );

    final page = await api.fetchPage(
      apiUrl: 'https://EXAMPLE.com:443/api.php?token=demo#ignored',
      queryParameters: const {'ac': 'list', 'pg': '2'},
    );

    expect(page.items.single.id, '7');
    expect(page.items.single.title, '仅作网络层测试的影片');
    expect(page.currentPage, 2);
    expect(page.hasNextPage, isTrue);
  });

  test('parses detail JSON while leaving playback URLs as inert strings',
      () async {
    final api = client(
      () => MockClient((request) async => http.Response.bytes(
            utf8.encode(jsonEncode({
              'data': {
                'vod_id': 'detail-1',
                'vod_name': '详情测试',
                'vod_play_from': '授权测试线路',
                'vod_play_url':
                    '第1集\$https://media.example/episode.m3u8',
              },
            })),
            200,
          )),
    );

    final detail = await api.fetchDetail(
      apiUrl: 'https://example.com/api.php',
      queryParameters: const {'ac': 'detail', 'ids': 'detail-1'},
    );

    expect(detail.item.id, 'detail-1');
    expect(detail.item.title, '详情测试');
    expect(detail.playbackSources.single.episodes.single.url,
        'https://media.example/episode.m3u8');
  });

  test('rejects HTTP URLs and user-info URLs before creating a client',
      () async {
    var clientCreated = false;
    final api = client(() {
      clientCreated = true;
      return MockClient((request) async => http.Response('{}', 200));
    });

    await expectLater(
      api.fetchPage(apiUrl: 'http://example.com/api'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      api.fetchPage(apiUrl: 'https://user:password@example.com/api'),
      throwsA(isA<FormatException>()),
    );
    expect(clientCreated, isFalse);
  });

  test('rejects an HTTPS redirect that downgrades to HTTP', () async {
    var requests = 0;
    final api = client(
      () => MockClient((request) async {
        requests++;
        return http.Response(
          '',
          302,
          headers: {'location': 'http://example.com/insecure.json'},
        );
      }),
    );

    await expectLater(
      api.fetchPage(apiUrl: 'https://example.com/api'),
      throwsA(isA<FormatException>()),
    );
    expect(requests, 1);
  });

  test('follows a bounded HTTPS redirect and validates the final JSON', () async {
    final requestedHosts = <String>[];
    final api = client(
      () => MockClient((request) async {
        requestedHosts.add(request.url.host);
        if (requestedHosts.length == 1) {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://cdn.example.com/catalog.json'},
          );
        }
        return http.Response('{"list":[]}', 200);
      }),
    );

    final page = await api.fetchPage(
      apiUrl: 'https://example.com/catalog.json',
    );

    expect(requestedHosts, ['example.com', 'cdn.example.com']);
    expect(page.items, isEmpty);
  });

  test('rejects non-200 HTTP status codes', () async {
    final api = client(
      () => MockClient((request) async => http.Response('unavailable', 503)),
    );

    await expectLater(
      api.fetchPage(apiUrl: 'https://example.com/api'),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects responses exceeding the configured byte limit', () async {
    final api = client(
      () => MockClient((request) async => http.Response.bytes(
            utf8.encode('{"list":[]}'),
            200,
          )),
      maxResponseBytes: 8,
    );

    await expectLater(
      api.fetchPage(apiUrl: 'https://example.com/api'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid JSON and valid JSON with an unsupported shape',
      () async {
    final invalidJson = client(
      () => MockClient((request) async => http.Response('{bad', 200)),
    );
    await expectLater(
      invalidJson.fetchPage(apiUrl: 'https://example.com/api'),
      throwsA(isA<FormatException>()),
    );

    final wrongShape = client(
      () => MockClient((request) async =>
          http.Response('{"message":"error"}', 200)),
    );
    await expectLater(
      wrongShape.fetchPage(apiUrl: 'https://example.com/api'),
      throwsA(isA<FormatException>()),
    );
  });

  test('applies one total timeout to a stalled response', () async {
    final neverCompletes = Completer<http.Response>();
    final api = client(
      () => MockClient((request) => neverCompletes.future),
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      api.fetchPage(apiUrl: 'https://example.com/api'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
