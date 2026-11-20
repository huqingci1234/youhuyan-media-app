class TvBoxConfig {
  const TvBoxConfig({
    required this.name,
    required this.siteCount,
    required this.liveCount,
    required this.parseCount,
    required this.raw,
  });

  final String name;
  final int siteCount;
  final int liveCount;
  final int parseCount;
  final Map<String, dynamic> raw;

  factory TvBoxConfig.fromJson(Map<String, dynamic> json) {
    int count(dynamic value) => value is List ? value.length : 0;
    final nameValue = json['name'];
    return TvBoxConfig(
      name: nameValue is String && nameValue.trim().isNotEmpty
          ? nameValue.trim()
          : '未命名配置',
      siteCount: count(json['sites']),
      liveCount: count(json['lives']),
      parseCount: count(json['parses']),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }
}
