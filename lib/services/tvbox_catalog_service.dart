import 'dart:convert';

import '../models/tvbox_config_entry.dart';
import '../models/tvbox_catalog.dart';

/// Maps the safe, already-cached TVBox JSON document into display metadata.
///
/// This service deliberately does not call site APIs, load remote playlists,
/// execute spiders/scripts, or download JAR/live.txt files.
class TvBoxCatalogService {
  const TvBoxCatalogService();

  TvBoxCatalogSnapshot parseEntry(TvBoxConfigEntry entry) {
    return parseDocument(
      configId: entry.id,
      configName: entry.name,
      rawJson: entry.cachedJson,
    );
  }

  TvBoxCatalogSnapshot parseDocument({
    required int configId,
    required String configName,
    required String rawJson,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error) {
      throw FormatException('配置缓存 JSON 无法读取：${error.message}');
    }

    if (decoded is! Map) {
      throw const FormatException('配置缓存顶层必须是 JSON 对象');
    }

    final sitesRaw = _readArray(decoded, 'sites');
    final livesRaw = _readArray(decoded, 'lives');

    final sites = <TvBoxSite>[];
    for (final value in sitesRaw) {
      final item = _asStringMap(value);
      if (item == null) continue;

      final key = _firstString(item, const ['key', 'id', 'siteKey']);
      final name = _firstString(item, const ['name', 'title']);
      if ((key == null || key.isEmpty) && (name == null || name.isEmpty)) {
        continue;
      }

      sites.add(TvBoxSite(
        key: key ?? name!,
        name: name ?? key!,
        api: _firstString(item, const ['api', 'url']),
        type: _integer(item['type']),
        searchable: _enabled(item['searchable']),
        quickSearch: _enabled(item['quickSearch']),
        filterable: _enabled(item['filterable']),
      ));
    }

    final liveGroups = <TvBoxLiveGroup>[];
    for (var index = 0; index < livesRaw.length; index++) {
      final item = _asStringMap(livesRaw[index]);
      if (item == null) continue;

      final sourceUrl = _firstString(item, const ['url', 'source']);
      final groupName = _firstString(item, const ['name', 'title']);
      final channelValues = _firstArray(item, const ['channels', 'items']);
      final channels = <TvBoxLiveChannel>[];

      for (final channelValue in channelValues) {
        final channel = _parseChannel(channelValue);
        if (channel != null) channels.add(channel);
      }

      if ((groupName == null || groupName.isEmpty) &&
          sourceUrl == null &&
          channels.isEmpty) {
        continue;
      }

      liveGroups.add(TvBoxLiveGroup(
        name: groupName?.isNotEmpty == true ? groupName! : '直播分组 ${index + 1}',
        type: _integer(item['type']),
        sourceUrl: sourceUrl,
        channels: List.unmodifiable(channels),
      ));
    }

    return TvBoxCatalogSnapshot(
      configId: configId,
      configName: configName,
      sites: List.unmodifiable(sites),
      liveGroups: List.unmodifiable(liveGroups),
    );
  }

  List<Object?> _readArray(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return const [];
    if (value is! List) {
      throw FormatException('配置字段 $key 必须是数组');
    }
    return value.cast<Object?>();
  }

  List<Object?> _firstArray(
    Map<String, Object?> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) return value.cast<Object?>();
    }
    return const [];
  }

  Map<String, Object?>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is String) {
        result[entry.key as String] = entry.value;
      }
    }
    return result;
  }

  String? _firstString(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  TvBoxLiveChannel? _parseChannel(Object? value) {
    if (value is String) {
      final name = value.trim();
      if (name.isEmpty) return null;
      return TvBoxLiveChannel(name: name, url: null, number: null);
    }

    final map = _asStringMap(value);
    if (map == null) return null;
    final name = _firstString(map, const ['name', 'title', 'channel']);
    if (name == null) return null;

    return TvBoxLiveChannel(
      name: name,
      url: _firstString(map, const ['url', 'playUrl']),
      number: _integer(map['number'] ?? map['no'] ?? map['index']),
    );
  }

  int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  bool _enabled(Object? value) {
    if (value is bool) return value;
    if (value is num) return value > 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' ||
          normalized == 'true' ||
          normalized == 'yes';
    }
    return false;
  }
}
