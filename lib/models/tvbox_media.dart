/// Typed media metadata parsed from a user-authorized TVBox JSON API.
///
/// Playback URLs are retained as inert strings. This model does not make
/// network requests, resolve playlists, or execute remote code.
class TvBoxMediaItem {
  const TvBoxMediaItem({
    required this.id,
    required this.title,
    this.coverUrl,
    this.remarks,
    this.year,
    this.category,
    this.description,
    this.score,
    this.typeId,
  });

  final String id;
  final String title;
  final String? coverUrl;
  final String? remarks;
  final String? year;
  final String? category;
  final String? description;
  final String? score;
  final int? typeId;
}

/// A single page returned by a JSON media API.
class TvBoxMediaPage {
  const TvBoxMediaPage({
    required this.items,
    this.currentPage,
    this.pageCount,
    this.pageSize,
    this.totalCount,
  });

  final List<TvBoxMediaItem> items;
  final int? currentPage;
  final int? pageCount;
  final int? pageSize;
  final int? totalCount;

  bool get hasNextPage =>
      currentPage != null &&
      pageCount != null &&
      currentPage! < pageCount!;
}

/// Detail metadata and parsed episode labels for a single media item.
///
/// The episode URLs remain untrusted data until a future playback layer
/// applies its own HTTPS, redirect, and content-type checks.
class TvBoxMediaDetail {
  const TvBoxMediaDetail({
    required this.item,
    required this.playbackSources,
    this.director,
    this.actors,
    this.area,
    this.language,
  });

  final TvBoxMediaItem item;
  final String? director;
  final String? actors;
  final String? area;
  final String? language;
  final List<TvBoxPlaybackSource> playbackSources;
}

class TvBoxPlaybackSource {
  const TvBoxPlaybackSource({
    required this.name,
    required this.episodes,
  });

  final String name;
  final List<TvBoxPlaybackEpisode> episodes;
}

class TvBoxPlaybackEpisode {
  const TvBoxPlaybackEpisode({
    required this.name,
    required this.url,
  });

  final String name;

  /// Inert metadata only. Never pass this directly to a player.
  final String url;
}
