import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/media_library_entry.dart';
import '../models/tvbox_config_entry.dart';
import '../services/tvbox_config_validator.dart';

class DuplicateConfigUrlException implements Exception {
  const DuplicateConfigUrlException();

  @override
  String toString() => '该配置地址已经添加，请勿重复导入';
}

/// SQLite repository for multiple TVBox JSON profiles.
///
/// A successfully validated JSON document is stored as the offline cache.
/// Refresh writes replace that cache inside one SQLite transaction. Failed
/// validation only updates error metadata and never overwrites cached_json.
///
/// Favorites and watch history are separate tables with no foreign key to
/// config_sources, so switching or deleting a config cannot clear them.
class TvBoxConfigRepository {
  factory TvBoxConfigRepository({
    required DatabaseFactory databaseFactory,
    required String databasePath,
    DateTime Function()? clock,
    TvBoxConfigValidator? validator,
  }) {
    return TvBoxConfigRepository._(
      databaseFactory,
      databasePath,
      clock ?? DateTime.now,
      validator ?? const TvBoxConfigValidator(),
    );
  }

  TvBoxConfigRepository._(
    this._databaseFactory,
    this._databasePath,
    this._clock,
    this._validator,
  );

  final DatabaseFactory _databaseFactory;
  final String _databasePath;
  final DateTime Function() _clock;
  final TvBoxConfigValidator _validator;

  Future<Database>? _databaseFuture;

  static Future<TvBoxConfigRepository> openForCurrentPlatform() async {
    if (kIsWeb) {
      throw UnsupportedError('当前 SQLite 数据层尚未启用 Web 版本');
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final databaseDirectory =
        Directory(path.join(supportDirectory.path, 'youhuyan'));
    await databaseDirectory.create(recursive: true);

    final DatabaseFactory factory;
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    } else {
      // sqflite supplies the native database factory on Android, iOS and macOS.
      factory = sqflite.databaseFactory;
    }

    return TvBoxConfigRepository(
      databaseFactory: factory,
      databasePath: path.join(databaseDirectory.path, 'youhuyan.db'),
    );
  }

  Future<Database> get _database {
    return _databaseFuture ??= _databaseFactory.openDatabase(
      _databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          for (final statement in _schema) {
            await database.execute(statement);
          }
        },
      ),
    );
  }

  static const List<String> _schema = [
    '''
    CREATE TABLE config_sources (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      display_name TEXT NOT NULL,
      source_type TEXT NOT NULL
        CHECK (source_type IN ('remote_url', 'local_file')),
      source_url TEXT,
      normalized_url TEXT,
      cached_json TEXT NOT NULL,
      site_count INTEGER NOT NULL DEFAULT 0 CHECK (site_count >= 0),
      live_count INTEGER NOT NULL DEFAULT 0 CHECK (live_count >= 0),
      parse_count INTEGER NOT NULL DEFAULT 0 CHECK (parse_count >= 0),
      is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
      last_status TEXT NOT NULL DEFAULT 'success'
        CHECK (last_status IN ('never', 'success', 'error')),
      last_error TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_attempt_at TEXT,
      last_success_at TEXT
    )
    ''',
    '''
    CREATE UNIQUE INDEX idx_config_sources_normalized_url
    ON config_sources(normalized_url)
    WHERE normalized_url IS NOT NULL AND normalized_url <> ''
    ''',
    '''
    CREATE UNIQUE INDEX idx_config_sources_single_default
    ON config_sources(is_default)
    WHERE is_default = 1
    ''',
    '''
    CREATE TABLE favorites (
      media_key TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      item_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE watch_history (
      media_key TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      item_json TEXT NOT NULL,
      position_ms INTEGER NOT NULL DEFAULT 0 CHECK (position_ms >= 0),
      duration_ms INTEGER,
      updated_at TEXT NOT NULL
    )
    ''',
  ];

  Future<List<TvBoxConfigEntry>> listConfigs() async {
    final database = await _database;
    final rows = await database.query(
      'config_sources',
      orderBy: 'is_default DESC, display_name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(TvBoxConfigEntry.fromDatabaseRow).toList(growable: false);
  }

  Future<TvBoxConfigEntry?> getDefaultConfig() async {
    final database = await _database;
    final rows = await database.query(
      'config_sources',
      where: 'is_default = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TvBoxConfigEntry.fromDatabaseRow(rows.first);
  }

  Future<TvBoxConfigEntry> getConfig(int id) async {
    final database = await _database;
    final rows = await database.query(
      'config_sources',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('配置记录不存在');
    }
    return TvBoxConfigEntry.fromDatabaseRow(rows.first);
  }

  /// Adds a previously imported document. Pass sourceUrl for a remote profile;
  /// omit it for a local JSON file. The first profile becomes the default.
  Future<TvBoxConfigEntry> addConfig({
    required String rawJson,
    String? sourceUrl,
    String? name,
    bool makeDefault = false,
  }) async {
    final document = _validator.validate(rawJson, fallbackName: name);
    final normalizedUrl = _normalizeOptionalUrl(sourceUrl);
    final now = _nowIso();
    final database = await _database;

    final id = await database.transaction<int>((transaction) async {
      await _ensureUrlAvailable(transaction, normalizedUrl);

      final countRows = await transaction.rawQuery(
        'SELECT COUNT(*) AS profile_count FROM config_sources',
      );
      final profileCount = countRows.single['profile_count'] as int;
      final shouldBeDefault = makeDefault || profileCount == 0;

      if (shouldBeDefault) {
        await transaction.update(
          'config_sources',
          {'is_default': 0},
        );
      }

      return transaction.insert('config_sources', {
        'display_name': _displayName(name, document.documentName),
        'source_type': normalizedUrl == null ? 'local_file' : 'remote_url',
        'source_url': normalizedUrl,
        'normalized_url': normalizedUrl,
        'cached_json': document.rawJson,
        'site_count': document.siteCount,
        'live_count': document.liveCount,
        'parse_count': document.parseCount,
        'is_default': shouldBeDefault ? 1 : 0,
        'last_status': 'success',
        'last_error': null,
        'created_at': now,
        'updated_at': now,
        'last_attempt_at': null,
        'last_success_at': now,
      });
    });

    return getConfig(id);
  }

  /// Renaming does not change the source URL or cached JSON document.
  Future<TvBoxConfigEntry> renameConfig(int id, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', '配置名称不能为空');
    }

    final database = await _database;
    final changed = await database.update(
      'config_sources',
      {
        'display_name': trimmedName,
        'updated_at': _nowIso(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) {
      throw StateError('配置记录不存在');
    }
    return getConfig(id);
  }

  /// Updates a source URL only together with a freshly validated document.
  /// This prevents an edited URL from being treated as verified by itself.
  Future<TvBoxConfigEntry> updateConfig({
    required int id,
    required String rawJson,
    required String? sourceUrl,
    String? name,
  }) async {
    final document = _validator.validate(rawJson, fallbackName: name);
    final normalizedUrl = _normalizeOptionalUrl(sourceUrl);
    final database = await _database;
    final now = _nowIso();

    await database.transaction((transaction) async {
      final current = await transaction.query(
        'config_sources',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (current.isEmpty) {
        throw StateError('配置记录不存在');
      }

      await _ensureUrlAvailable(
        transaction,
        normalizedUrl,
        exceptId: id,
      );

      await transaction.update(
        'config_sources',
        {
          'display_name': _displayName(name, document.documentName),
          'source_type':
              normalizedUrl == null ? 'local_file' : 'remote_url',
          'source_url': normalizedUrl,
          'normalized_url': normalizedUrl,
          'cached_json': document.rawJson,
          'site_count': document.siteCount,
          'live_count': document.liveCount,
          'parse_count': document.parseCount,
          'last_status': 'success',
          'last_error': null,
          'updated_at': now,
          'last_attempt_at': now,
          'last_success_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    return getConfig(id);
  }

  /// Atomically replaces the offline cache after the new JSON is validated.
  ///
  /// On validation failure, the old document and last-success timestamp stay
  /// intact; only the latest attempt status and error message are recorded.
  Future<TvBoxConfigEntry> refreshWithContent({
    required int id,
    required String rawJson,
  }) async {
    final ValidatedTvBoxDocument document;
    try {
      document = _validator.validate(rawJson);
    } on FormatException catch (error) {
      await recordRefreshFailure(id, error.message.toString());
      rethrow;
    }

    final database = await _database;
    final now = _nowIso();

    await database.transaction((transaction) async {
      final changed = await transaction.update(
        'config_sources',
        {
          'cached_json': document.rawJson,
          'site_count': document.siteCount,
          'live_count': document.liveCount,
          'parse_count': document.parseCount,
          'last_status': 'success',
          'last_error': null,
          'updated_at': now,
          'last_attempt_at': now,
          'last_success_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed != 1) {
        throw StateError('配置记录不存在');
      }
    });

    return getConfig(id);
  }

  /// Records a failed network or validation attempt without touching cache data.
  Future<void> recordRefreshFailure(int id, String error) async {
    final database = await _database;
    final message = error.trim().isEmpty ? '刷新失败' : error.trim();
    final now = _nowIso();
    final changed = await database.update(
      'config_sources',
      {
        'last_status': 'error',
        'last_error': message.length > 1000
            ? message.substring(0, 1000)
            : message,
        'updated_at': now,
        'last_attempt_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) {
      throw StateError('配置记录不存在');
    }
  }

  Future<TvBoxConfigEntry> setDefaultConfig(int id) async {
    final database = await _database;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'config_sources',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('配置记录不存在');
      }

      await transaction.update(
        'config_sources',
        {'is_default': 0},
      );
      await transaction.update(
        'config_sources',
        {'is_default': 1, 'updated_at': _nowIso()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    return getConfig(id);
  }

  Future<void> deleteConfig(int id) async {
    final database = await _database;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'config_sources',
        columns: ['is_default'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final wasDefault = (rows.single['is_default'] as int) == 1;
      await transaction.delete(
        'config_sources',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (wasDefault) {
        final candidates = await transaction.query(
          'config_sources',
          columns: ['id'],
          orderBy: 'created_at ASC, id ASC',
          limit: 1,
        );
        if (candidates.isNotEmpty) {
          await transaction.update(
            'config_sources',
            {'is_default': 1},
            where: 'id = ?',
            whereArgs: [candidates.single['id']],
          );
        }
      }
    });
  }


  /// Saves a favorite independently from all config sources.
  ///
  /// Use a stable, namespaced key such as "siteKey:itemId" so two sites with
  /// overlapping IDs do not overwrite one another.
  Future<FavoriteEntry> saveFavorite({
    required String mediaKey,
    required String title,
    required String itemJson,
  }) async {
    final key = _validateMediaKey(mediaKey);
    final safeTitle = _validateMediaTitle(title);
    _validateMediaJson(itemJson);

    final database = await _database;
    final now = _nowIso();
    await database.transaction((transaction) async {
      final existing = await transaction.query(
        'favorites',
        columns: ['media_key'],
        where: 'media_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (existing.isEmpty) {
        await transaction.insert('favorites', {
          'media_key': key,
          'title': safeTitle,
          'item_json': itemJson,
          'created_at': now,
        });
      } else {
        // Keep the original created_at when refreshing a saved favorite.
        await transaction.update(
          'favorites',
          {'title': safeTitle, 'item_json': itemJson},
          where: 'media_key = ?',
          whereArgs: [key],
        );
      }
    });

    final saved = await getFavorite(key);
    if (saved == null) throw StateError('收藏保存后无法读取');
    return saved;
  }

  Future<FavoriteEntry?> getFavorite(String mediaKey) async {
    final key = _validateMediaKey(mediaKey);
    final database = await _database;
    final rows = await database.query(
      'favorites',
      where: 'media_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : FavoriteEntry.fromDatabaseRow(rows.single);
  }

  Future<bool> isFavorite(String mediaKey) async =>
      (await getFavorite(mediaKey)) != null;

  Future<List<FavoriteEntry>> listFavorites() async {
    final database = await _database;
    final rows = await database.query(
      'favorites',
      orderBy: 'created_at DESC, media_key COLLATE NOCASE ASC',
    );
    return rows
        .map(FavoriteEntry.fromDatabaseRow)
        .toList(growable: false);
  }

  Future<void> removeFavorite(String mediaKey) async {
    final key = _validateMediaKey(mediaKey);
    final database = await _database;
    await database.delete(
      'favorites',
      where: 'media_key = ?',
      whereArgs: [key],
    );
  }

  /// Stores the latest playback position without tying the item to a config ID.
  /// If a known duration is exceeded, position is clamped to that duration.
  Future<WatchHistoryEntry> saveWatchProgress({
    required String mediaKey,
    required String title,
    required String itemJson,
    required int positionMs,
    required int? durationMs,
  }) async {
    final key = _validateMediaKey(mediaKey);
    final safeTitle = _validateMediaTitle(title);
    _validateMediaJson(itemJson);
    if (positionMs < 0) {
      throw ArgumentError.value(positionMs, 'positionMs', '播放进度不能小于 0');
    }
    if (durationMs != null && durationMs < 0) {
      throw ArgumentError.value(durationMs, 'durationMs', '视频时长不能小于 0');
    }

    final safePosition = durationMs != null &&
            durationMs > 0 &&
            positionMs > durationMs
        ? durationMs
        : positionMs;
    final database = await _database;
    final now = _nowIso();

    await database.transaction((transaction) async {
      final existing = await transaction.query(
        'watch_history',
        columns: ['media_key'],
        where: 'media_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      final values = {
        'title': safeTitle,
        'item_json': itemJson,
        'position_ms': safePosition,
        'duration_ms': durationMs,
        'updated_at': now,
      };
      if (existing.isEmpty) {
        await transaction.insert('watch_history', {
          'media_key': key,
          ...values,
        });
      } else {
        await transaction.update(
          'watch_history',
          values,
          where: 'media_key = ?',
          whereArgs: [key],
        );
      }
    });

    final saved = await getWatchHistoryEntry(key);
    if (saved == null) throw StateError('播放记录保存后无法读取');
    return saved;
  }

  Future<WatchHistoryEntry?> getWatchHistoryEntry(String mediaKey) async {
    final key = _validateMediaKey(mediaKey);
    final database = await _database;
    final rows = await database.query(
      'watch_history',
      where: 'media_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : WatchHistoryEntry.fromDatabaseRow(rows.single);
  }

  Future<List<WatchHistoryEntry>> listWatchHistory({int limit = 100}) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', '历史记录条数必须在 1 到 1000 之间');
    }
    final database = await _database;
    final rows = await database.query(
      'watch_history',
      orderBy: 'updated_at DESC, media_key COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows
        .map(WatchHistoryEntry.fromDatabaseRow)
        .toList(growable: false);
  }

  Future<void> removeWatchHistory(String mediaKey) async {
    final key = _validateMediaKey(mediaKey);
    final database = await _database;
    await database.delete(
      'watch_history',
      where: 'media_key = ?',
      whereArgs: [key],
    );
  }

  Future<void> clearWatchHistory() async {
    final database = await _database;
    await database.delete('watch_history');
  }

  String _validateMediaKey(String mediaKey) {
    final value = mediaKey.trim();
    if (value.isEmpty || value.length > 512) {
      throw ArgumentError.value(mediaKey, 'mediaKey', '媒体标识不能为空且不能超过 512 个字符');
    }
    return value;
  }

  String _validateMediaTitle(String title) {
    final value = title.trim();
    if (value.isEmpty || value.length > 512) {
      throw ArgumentError.value(title, 'title', '媒体标题不能为空且不能超过 512 个字符');
    }
    return value;
  }

  void _validateMediaJson(String itemJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(itemJson);
    } on FormatException {
      throw const FormatException('媒体快照不是有效 JSON');
    }
    if (decoded is! Map) {
      throw const FormatException('媒体快照必须是 JSON 对象');
    }
  }

  Future<void> close() async {
    final opening = _databaseFuture;
    _databaseFuture = null;
    if (opening != null) {
      await (await opening).close();
    }
  }

  String? _normalizeOptionalUrl(String? sourceUrl) {
    if (sourceUrl == null || sourceUrl.trim().isEmpty) return null;
    return _validator.normalizeHttpsUrl(sourceUrl);
  }

  String _displayName(String? requestedName, String documentName) {
    final value = requestedName?.trim();
    return value != null && value.isNotEmpty ? value : documentName;
  }

  String _nowIso() => _clock().toUtc().toIso8601String();

  Future<void> _ensureUrlAvailable(
    DatabaseExecutor executor,
    String? normalizedUrl, {
    int? exceptId,
  }) async {
    if (normalizedUrl == null) return;

    final where = exceptId == null
        ? 'normalized_url = ?'
        : 'normalized_url = ? AND id != ?';
    final arguments = exceptId == null
        ? [normalizedUrl]
        : [normalizedUrl, exceptId];

    final rows = await executor.query(
      'config_sources',
      columns: ['id'],
      where: where,
      whereArgs: arguments,
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw const DuplicateConfigUrlException();
    }
  }
}
