import 'dart:convert';

class ValidatedTvBoxDocument {
  const ValidatedTvBoxDocument({
    required this.rawJson,
    required this.documentName,
    required this.siteCount,
    required this.liveCount,
    required this.parseCount,
  });

  final String rawJson;
  final String documentName;
  final int siteCount;
  final int liveCount;
  final int parseCount;
}

/// Performs structural validation only. Imported fields remain inert data;
/// this validator never executes spider expressions, scripts, or JAR files.
class TvBoxConfigValidator {
  const TvBoxConfigValidator();

  static const int maxDocumentBytes = 2 * 1024 * 1024;

  ValidatedTvBoxDocument validate(
    String rawJson, {
    String? fallbackName,
  }) {
    if (rawJson.trim().isEmpty) {
      throw const FormatException('配置文件为空');
    }

    if (utf8.encode(rawJson).length > maxDocumentBytes) {
      throw const FormatException('配置文件超过 2 MiB 大小限制');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error) {
      throw FormatException('JSON 格式无效：' + error.message.toString());
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('配置顶层必须是 JSON 对象');
    }

    final siteCount = _arrayLength(decoded, 'sites');
    final liveCount = _arrayLength(decoded, 'lives');
    final parseCount = _arrayLength(decoded, 'parses');

    if (siteCount == 0 && liveCount == 0) {
      throw const FormatException('配置中没有可识别的站点或直播列表');
    }

    final sourceName = decoded['name'];
    final suppliedName = fallbackName?.trim();
    final documentName = sourceName is String && sourceName.trim().isNotEmpty
        ? sourceName.trim()
        : (suppliedName != null && suppliedName.isNotEmpty
            ? suppliedName
            : '未命名配置');

    return ValidatedTvBoxDocument(
      rawJson: rawJson,
      documentName: documentName,
      siteCount: siteCount,
      liveCount: liveCount,
      parseCount: parseCount,
    );
  }

  String normalizeHttpsUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('远程配置只接受有效的 HTTPS 地址');
    }

    final normalized = uri
        .replace(
          scheme: 'https',
          host: uri.host.toLowerCase(),
          port: uri.port == 443 ? null : uri.port,
          fragment: '',
        )
        .normalizePath();

    return normalized.toString();
  }

  int _arrayLength(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return 0;
    if (value is! List) {
      throw FormatException('配置字段 $key 必须是数组');
    }
    return value.length;
  }
}
