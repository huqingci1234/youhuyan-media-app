enum ConfigSourceType {
  remoteUrl,
  localFile;

  String get databaseValue => switch (this) {
        ConfigSourceType.remoteUrl => 'remote_url',
        ConfigSourceType.localFile => 'local_file',
      };

  static ConfigSourceType fromDatabase(String? value) {
    return value == 'remote_url'
        ? ConfigSourceType.remoteUrl
        : ConfigSourceType.localFile;
  }
}

enum ConfigLastStatus {
  never,
  success,
  error;

  String get databaseValue => switch (this) {
        ConfigLastStatus.never => 'never',
        ConfigLastStatus.success => 'success',
        ConfigLastStatus.error => 'error',
      };

  static ConfigLastStatus fromDatabase(String? value) {
    return switch (value) {
      'success' => ConfigLastStatus.success,
      'error' => ConfigLastStatus.error,
      _ => ConfigLastStatus.never,
    };
  }
}

/// A locally cached, validated TVBox JSON source.
///
/// The cached document is data only. This model deliberately exposes no
/// mechanism for executing spiders, JAR files, scripts, or remote plugins.
class TvBoxConfigEntry {
  const TvBoxConfigEntry({
    required this.id,
    required this.name,
    required this.sourceType,
    required this.sourceUrl,
    required this.cachedJson,
    required this.siteCount,
    required this.liveCount,
    required this.parseCount,
    required this.isDefault,
    required this.lastStatus,
    required this.createdAt,
    required this.updatedAt,
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.lastError,
  });

  final int id;
  final String name;
  final ConfigSourceType sourceType;
  final String? sourceUrl;
  final String cachedJson;
  final int siteCount;
  final int liveCount;
  final int parseCount;
  final bool isDefault;
  final ConfigLastStatus lastStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final String? lastError;

  factory TvBoxConfigEntry.fromDatabaseRow(Map<String, Object?> row) {
    DateTime requiredDate(String key) =>
        DateTime.parse(row[key] as String).toUtc();

    DateTime? optionalDate(String key) {
      final value = row[key];
      return value is String ? DateTime.tryParse(value)?.toUtc() : null;
    }

    return TvBoxConfigEntry(
      id: row['id'] as int,
      name: row['display_name'] as String,
      sourceType:
          ConfigSourceType.fromDatabase(row['source_type'] as String?),
      sourceUrl: row['source_url'] as String?,
      cachedJson: row['cached_json'] as String,
      siteCount: row['site_count'] as int,
      liveCount: row['live_count'] as int,
      parseCount: row['parse_count'] as int,
      isDefault: (row['is_default'] as int) == 1,
      lastStatus:
          ConfigLastStatus.fromDatabase(row['last_status'] as String?),
      createdAt: requiredDate('created_at'),
      updatedAt: requiredDate('updated_at'),
      lastAttemptAt: optionalDate('last_attempt_at'),
      lastSuccessAt: optionalDate('last_success_at'),
      lastError: row['last_error'] as String?,
    );
  }
}
