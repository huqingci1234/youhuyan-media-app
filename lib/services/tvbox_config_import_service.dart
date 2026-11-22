import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/tvbox_config_entry.dart';
import '../repositories/tvbox_config_repository.dart';
import 'tvbox_config_validator.dart';

/// Imports user-owned or otherwise authorized TVBox JSON as inert data.
///
/// Remote URLs must use HTTPS. Redirects are checked at every hop, responses
/// are bounded to 2 MiB, and both connection and body consumption share one
/// deadline. No imported spider, script, JAR, or plugin is ever executed.
class TvBoxConfigImportService {
  TvBoxConfigImportService({
    required TvBoxConfigRepository repository,
    TvBoxConfigValidator validator = const TvBoxConfigValidator(),
    http.Client Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 20),
  })  : _repository = repository,
        _validator = validator,
        _clientFactory = clientFactory ?? http.Client.new;

  final TvBoxConfigRepository _repository;
  final TvBoxConfigValidator _validator;
  final http.Client Function() _clientFactory;
  final Duration requestTimeout;

  static const int maxRedirects = 3;
  static const int maxDocumentBytes = TvBoxConfigValidator.maxDocumentBytes;

  Future<TvBoxConfigEntry> importRemote({
    required String url,
    String? name,
    bool makeDefault = false,
  }) async {
    final normalizedUrl = _validator.normalizeHttpsUrl(url);
    final rawJson = await _downloadJson(normalizedUrl);
    return _repository.addConfig(
      rawJson: rawJson,
      sourceUrl: normalizedUrl,
      name: name,
      makeDefault: makeDefault,
    );
  }

  Future<TvBoxConfigEntry> refreshRemote(int id) async {
    final current = await _repository.getConfig(id);
    final url = current.sourceUrl;
    if (url == null) {
      throw StateError('本地 JSON 文件没有远程地址，不能在线刷新');
    }

    final String rawJson;
    try {
      rawJson = await _downloadJson(url);
    } catch (error) {
      await _repository.recordRefreshFailure(id, _errorMessage(error));
      rethrow;
    }

    // The repository validates again and performs the cache replacement in a
    // SQLite transaction. The last good cache remains available offline.
    return _repository.refreshWithContent(id: id, rawJson: rawJson);
  }

  Future<TvBoxConfigEntry> updateRemote({
    required int id,
    required String url,
    String? name,
  }) async {
    final normalizedUrl = _validator.normalizeHttpsUrl(url);
    final rawJson = await _downloadJson(normalizedUrl);
    return _repository.updateConfig(
      id: id,
      rawJson: rawJson,
      sourceUrl: normalizedUrl,
      name: name,
    );
  }

  Future<TvBoxConfigEntry> importLocalStream({
    required String fileName,
    required Stream<List<int>> bytes,
  }) async {
    final deadline = DateTime.now().add(requestTimeout);
    final content = await _readLimitedStream(bytes, deadline);
    final rawJson = utf8.decode(content, allowMalformed: false);
    _validator.validate(rawJson, fallbackName: fileName);
    return _repository.addConfig(rawJson: rawJson, name: fileName);
  }

  Future<String> _downloadJson(String input) async {
    var current = Uri.parse(_validator.normalizeHttpsUrl(input));
    final deadline = DateTime.now().add(requestTimeout);
    final client = _clientFactory();

    try {
      var redirects = 0;
      while (true) {
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';

        final response = await client
            .send(request)
            .timeout(_remaining(deadline), onTimeout: () {
          throw TimeoutException(
            '配置下载超过 ' + requestTimeout.inSeconds.toString() + ' 秒',
          );
        });

        if (response.isRedirect) {
          final location = response.headers['location'];
          await _cancelStream(response.stream);
          if (location == null || location.trim().isEmpty) {
            throw const FormatException('配置服务器返回了没有目标地址的重定向');
          }
          if (redirects >= maxRedirects) {
            throw const FormatException('配置地址重定向次数过多');
          }

          // Revalidate the resolved target. HTTPS-to-HTTP downgrade redirects
          // are deliberately rejected.
          final target = current.resolve(location.trim());
          current = Uri.parse(_validator.normalizeHttpsUrl(target.toString()));
          redirects++;
          continue;
        }

        if (response.statusCode != 200) {
          await _cancelStream(response.stream);
          throw StateError('配置服务器返回 HTTP ' + response.statusCode.toString());
        }

        if (response.contentLength > maxDocumentBytes) {
          await _cancelStream(response.stream);
          throw const FormatException('远程配置超过 2 MiB 大小限制');
        }

        final content = await _readLimitedStream(response.stream, deadline);
        final rawJson = utf8.decode(content, allowMalformed: false);
        _validator.validate(rawJson);
        return rawJson;
      }
    } finally {
      client.close();
    }
  }

  Future<Uint8List> _readLimitedStream(
    Stream<List<int>> stream,
    DateTime deadline,
  ) async {
    final iterator = StreamIterator<List<int>>(stream);
    final builder = BytesBuilder(copy: false);
    var totalBytes = 0;

    try {
      while (true) {
        final remaining = _remaining(deadline);
        final hasNext = await iterator.moveNext().timeout(
          remaining,
          onTimeout: () {
            throw TimeoutException(
              '读取配置超过 ' + requestTimeout.inSeconds.toString() + ' 秒',
            );
          },
        );
        if (!hasNext) break;

        final chunk = iterator.current;
        totalBytes += chunk.length;
        if (totalBytes > maxDocumentBytes) {
          throw const FormatException('配置文件超过 2 MiB 大小限制');
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
        '配置读取超过 ' + requestTimeout.inSeconds.toString() + ' 秒',
      );
    }
    return remaining;
  }

  Future<void> _cancelStream(Stream<List<int>> stream) async {
    final subscription = stream.listen((_) {});
    await subscription.cancel();
  }

  String _errorMessage(Object error) {
    final message = error.toString();
    return message.length > 1000 ? message.substring(0, 1000) : message;
  }
}
