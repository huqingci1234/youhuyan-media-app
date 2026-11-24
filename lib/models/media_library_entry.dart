class FavoriteEntry {
  const FavoriteEntry({
    required this.mediaKey,
    required this.title,
    required this.itemJson,
    required this.createdAt,
  });

  final String mediaKey;
  final String title;
  final String itemJson;
  final DateTime createdAt;

  factory FavoriteEntry.fromDatabaseRow(Map<String, Object?> row) {
    return FavoriteEntry(
      mediaKey: row['media_key'] as String,
      title: row['title'] as String,
      itemJson: row['item_json'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }
}

class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.mediaKey,
    required this.title,
    required this.itemJson,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  final String mediaKey;
  final String title;
  final String itemJson;
  final int positionMs;
  final int? durationMs;
  final DateTime updatedAt;

  double? get progressFraction {
    final duration = durationMs;
    if (duration == null || duration <= 0) return null;
    return (positionMs / duration).clamp(0.0, 1.0).toDouble();
  }

  factory WatchHistoryEntry.fromDatabaseRow(Map<String, Object?> row) {
    final duration = row['duration_ms'];
    return WatchHistoryEntry(
      mediaKey: row['media_key'] as String,
      title: row['title'] as String,
      itemJson: row['item_json'] as String,
      positionMs: row['position_ms'] as int,
      durationMs: duration is int ? duration : null,
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
    );
  }
}
