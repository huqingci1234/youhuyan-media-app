import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/tvbox_media.dart';
import 'tvbox_media_response_parser.dart';

/// Fetches JSON from a site API that the user is authorized to access.
///
/// This is an explicit GET-only network layer. It accepts HTTPS endpoints,
/// rejects HTTPS-to-HTTP redirects, applies one total timeout and a strict
/// response-size cap, and delegates response-shape validation to the parser.
/// It never executes spider/script/JAR fields or follows playback URLs.
class TvBoxSiteApiClient {
  TvBoxSiteApiClient({
    http.Client Function()? clientFactory,
    TvBoxMediaResponseParser parser = const TvBoxMediaResponseParser(),
    this.requestTimeout = const Duration(seconds: 20),
    this.maxRedirects = 3,
    this.maxResponseBytes = 2 * 1024 * 1024,
  })  : _clientFactory = clientFactory ?? (() => http.Client()),
        _parser = parser {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
    if (maxRedirects < 0) {
      throw ArgumentError.value(maxRedirects, 'maxRedirects');
    }
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(maxResponseBytes, 'maxResponseBytes');
    }
  }

  final http.Client Function() _clientFactory;
  final TvBoxMediaResponseParser _parser;

  final Duration requestTimeout;
  final int maxRedirects;
  final int maxResponseBytes;

  /// Loads a page from an explicitly selected, user-authorized HTTPS API.
  ///
  /// The caller supplies endpoint-specific parameters such as ac=list, pg=1,
  /// wd=... or a category ID. Existing query parameters are kept.
  Future<TvBoxMediaPage> fetchPage({
    required String apiUrl,
    Map<String, String> queryParameters = const {},
  }) async {
    final rawJson = await _getJson(
      apiUrl: apiUrl,
      queryParameters: queryParameters,
    );
    return _parser.parsePage(rawJson);
  }

  /// Loads one detail response. The endpoint contract remains caller-owned.
  ///
  /// Playback source and episode URLs returned by the parser remain inert
  /// strings; this method does not open or validate those media URLs.
  Future<TvBoxMediaDetail> fetchDetail({
    required String apiUrl,
    Map<String, String> queryParameters = const {},
  }) async {
    final rawJson = await _getJson(
      apiUrl: apiUrl,
      queryParameters: queryParameters,
    );
    return _parser.parseDetail(rawJson);
  }

  Future<String> _getJson({
    required String apiUrl,
    required Map<String, String> queryParameters,
  }) async {
    var current = _buildRequestUri(apiUrl, queryParameters);
    final deadline = DateTime.now().add(requestTimeout);
    final client = _clientFactory();

    try {
      var redirects = 0;
      while (true) {
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';

        final response = await client.send(request).timeout(
          _remaining(deadline),
          onTimeout: () => throw TimeoutException(
            '影视站点 API 请求超过 ' +
                requestTimeout.inSeconds.toString() +
                ' 秒',
          ),
        );

        if (_isRedirect(response.statusCode)) {
          final location = response.headers['location'];
          await _cancelStream(response.stream);

          if (location == null || location.trim().isEmpty) {
            throw const FormatException('站点 API 返回了缺少目标地址的重定向');
          }
          if (redirects >= maxRedirects) {
            throw const FormatException('站点 API 重定向次数超过限制');
          }

          final target = current.resolve(location.trim());
          // Re-validate every redirect target; HTTPS downgrade is forbidden.
          current = _normalizeHttpsUri(target.toString());
          redirects++;
          continue;
        }

        if (response.statusCode != 200) {
          await _cancelStream(response.stream);
          throw StateError('站点 API 返回 HTTP ' + response.statusCode.toString());
        }

        final declaredLength = response.contentLength;
        if (declaredLength != null && declaredLength > maxResponseBytes) {
          await _cancelStream(response.stream);
          throw FormatException(
            '站点 API 响应超过 ' + maxResponseBytes.toString() + ' 字节限制',
          );
        }

        final bytes = await _readLimitedStream(response.stream, deadline);
        try {
          return utf8.decode(bytes, allowMalformed: false);
        } on FormatException catch (error) {
          throw FormatException('站点 API 响应不是有效 UTF-8：' + error.message);
        }
      }
    } finally {
      client.close();
    }
  }

  Uri _buildRequestUri(
    String input,
    Map<String, String> queryParameters,
  ) {
    final uri = _normalizeHttpsUri(input);
    if (queryParameters.isEmpty) return uri;

    final merged = <String, String>{...uri.queryParameters};
    for (final entry in queryParameters.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        throw const FormatException('站点 API 查询参数名称不能为空');
      }
      merged[key] = entry.value;
    }
    return uri.replace(queryParameters: merged).removeFragment();
  }

  Uri _normalizeHttpsUri(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('站点 API 只允许有效的 HTTPS 地址');
    }

    return uri
        .replace(
          scheme: 'https',
          host: uri.host.toLowerCase(),
          port: uri.port == 443 ? null : uri.port,
        )
        .removeFragment()
        .normalizePath();
  }

  bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  Future<List<int>> _readLimitedStream(
    Stream<List<int>> stream,
    DateTime deadline,
  ) async {
    final iterator = StreamIterator<List<int>>(stream);
    final builder = BytesBuilder(copy: false);
    var totalBytes = 0;

    try {
      while (true) {
        final hasNext = await iterator.moveNext().timeout(
          _remaining(deadline),
          onTimeout: () => throw TimeoutException(
            '读取站点 API 响应超过 ' +
                requestTimeout.inSeconds.toString() +
                ' 秒',
          ),
        );
        if (!hasNext) break;

        final chunk = iterator.current;
        totalBytes += chunk.length;
        if (totalBytes > maxResponseBytes) {
          throw FormatException(
            '站点 API 响应超过 ' + maxResponseBytes.toString() + ' 字节限制',
          );
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      await iterator.cancel();
    }
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        '站点 API 请求超过 ' +
            requestTimeout.inSeconds.toString() +
            ' 秒',
      );
    }
    return remaining;
  }

  Future<void> _cancelStream(Stream<List<int>> stream) async {
    final subscription = stream.listen((_) {});
    await subscription.cancel();
  }
}
