import 'dart:convert';

import '../models/tvbox_media.dart';

/// Parses common TVBox/MacCMS-style JSON list and detail responses.
///
/// Supported list containers are top-level `list`, top-level `data` arrays,
/// and `data.list`. Unknown fields are ignored. No remote field is executed.
class TvBoxMediaResponseParser {
  const TvBoxMediaResponseParser();

  TvBoxMediaPage parsePage(String rawJson) {
    final decoded = _decode(rawJson);
    final root = _asStringMap(decoded);
    if (root == null) {
      throw const FormatException('影视接口响应顶层必须是 JSON 对象');
    }

    final data = _asStringMap(root['data']);
    final rawItems = _extractList(root, data);
    final items = <TvBoxMediaItem>[];

    for (final value in rawItems) {
      final map = _asStringMap(value);
      if (map == null) continue;
      final item = _parseItem(map);
      if (item != null) items.add(item);
    }

    return TvBoxMediaPage(
      items: List.unmodifiable(items),
      currentPage: _firstInteger([root, data], const ['page', 'currentPage']),
      pageCount: _firstInteger(
        [root, data],
        const ['pagecount', 'page_count', 'pageCount', 'pages'],
      ),
      pageSize: _firstInteger(
        [root, data],
        const ['limit', 'pageSize', 'page_size', 'pagesize'],
      ),
      totalCount: _firstInteger([root, data], const ['total', 'totalCount']),
    );
  }

  TvBoxMediaDetail parseDetail(String rawJson) {
    final decoded = _decode(rawJson);
    final root = _asStringMap(decoded);
    if (root == null) {
      throw const FormatException('影视详情响应顶层必须是 JSON 对象');
    }

    final data = _asStringMap(root['data']);
    final rawItem = _extractFirstItem(root, data);
    if (rawItem == null) {
      throw const FormatException('影视详情接口没有返回有效项目');
    }

    final item = _parseItem(rawItem);
    if (item == null) {
      throw const FormatException('影视详情缺少有效的 ID 或名称');
    }

    return TvBoxMediaDetail(
      item: item,
      director: _firstText(rawItem, const ['vod_director', 'director']),
      actors: _firstText(rawItem, const ['vod_actor', 'actor', 'actors']),
      area: _firstText(rawItem, const ['vod_area', 'area']),
      language: _firstText(rawItem, const ['vod_lang', 'language', 'lang']),
      playbackSources: _parsePlaybackSources(rawItem),
    );
  }

  Object? _decode(String rawJson) {
    try {
      return jsonDecode(rawJson);
    } on FormatException catch (error) {
      throw FormatException('影视接口 JSON 格式无效：${error.message}');
    }
  }

  List<Object?> _extractList(
    Map<String, Object?> root,
    Map<String, Object?>? data,
  ) {
    final rootList = root['list'];
    if (rootList != null) {
      if (rootList is! List) {
        throw const FormatException('影视接口字段 list 必须是数组');
      }
      return rootList.cast<Object?>();
    }

    final dataValue = root['data'];
    if (dataValue is List) return dataValue.cast<Object?>();

    final nestedList = data?['list'];
    if (nestedList is List) return nestedList.cast<Object?>();
    if (nestedList != null) {
      throw const FormatException('影视接口字段 data.list 必须是数组');
    }

    throw const FormatException('影视接口响应缺少 list 或 data 列表');
  }

  Map<String, Object?>? _extractFirstItem(
    Map<String, Object?> root,
    Map<String, Object?>? data,
  ) {
    final rootList = root['list'];
    if (rootList is List && rootList.isNotEmpty) {
      return _asStringMap(rootList.first);
    }

    final dataValue = root['data'];
    if (dataValue is List && dataValue.isNotEmpty) {
      return _asStringMap(dataValue.first);
    }

    final nestedList = data?['list'];
    if (nestedList is List && nestedList.isNotEmpty) {
      return _asStringMap(nestedList.first);
    }

    if (_looksLikeMedia(root)) return root;
    if (data != null && _looksLikeMedia(data)) return data;
    return null;
  }

  bool _looksLikeMedia(Map<String, Object?> map) {
    return _firstText(map, const ['vod_name', 'name', 'title']) != null;
  }

  TvBoxMediaItem? _parseItem(Map<String, Object?> map) {
    final title = _firstText(map, const ['vod_name', 'name', 'title']);
    if (title == null) return null;

    final id = _firstText(map, const ['vod_id', 'id', 'ids', 'key']) ?? title;
    return TvBoxMediaItem(
      id: id,
      title: title,
      coverUrl: _firstText(
        map,
        const ['vod_pic', 'pic', 'cover', 'thumbnail', 'image'],
      ),
      remarks: _firstText(
        map,
        const ['vod_remarks', 'remarks', 'note', 'state'],
      ),
      year: _firstText(map, const ['vod_year', 'year']),
      category: _firstText(
        map,
        const ['type_name', 'category', 'category_name'],
      ),
      description: _firstText(
        map,
        const ['vod_content', 'content', 'description', 'des'],
      ),
      score: _firstText(map, const ['vod_score', 'score', 'douban_score']),
      typeId: _firstInteger([map], const ['type_id', 'typeId']),
    );
  }

  List<TvBoxPlaybackSource> _parsePlaybackSources(
    Map<String, Object?> map,
  ) {
    final rawNames = _firstText(map, const ['vod_play_from', 'play_from']);
    final rawUrls = _firstText(map, const ['vod_play_url', 'play_url']);
    if (rawUrls == null) return const [];

    final names = rawNames?.split(r'$$$') ?? const <String>[];
    final urlGroups = rawUrls.split(r'$$$');
    final sources = <TvBoxPlaybackSource>[];

    for (var index = 0; index < urlGroups.length; index++) {
      final episodes = _parseEpisodeGroup(urlGroups[index]);
      if (episodes.isEmpty) continue;

      final sourceName = index < names.length && names[index].trim().isNotEmpty
          ? names[index].trim()
          : '播放源 ${index + 1}';
      sources.add(TvBoxPlaybackSource(
        name: sourceName,
        episodes: List.unmodifiable(episodes),
      ));
    }

    return List.unmodifiable(sources);
  }

  List<TvBoxPlaybackEpisode> _parseEpisodeGroup(String rawGroup) {
    final episodes = <TvBoxPlaybackEpisode>[];
    final values = rawGroup.split('#');

    for (var index = 0; index < values.length; index++) {
      final value = values[index].trim();
      if (value.isEmpty) continue;

      final separator = value.indexOf(r'$');
      final name = separator < 0
          ? '第${index + 1}集'
          : value.substring(0, separator).trim();
      final url = separator < 0
          ? value
          : value.substring(separator + 1).trim();
      if (url.isEmpty) continue;

      episodes.add(TvBoxPlaybackEpisode(
        name: name.isEmpty ? '第${index + 1}集' : name,
        url: url,
      ));
    }

    return episodes;
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

  String? _firstText(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num) return value.toString();
    }
    return null;
  }

  int? _firstInteger(
    List<Map<String, Object?>?> maps,
    List<String> keys,
  ) {
    for (final map in maps) {
      if (map == null) continue;
      for (final key in keys) {
        final value = map[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }
}
