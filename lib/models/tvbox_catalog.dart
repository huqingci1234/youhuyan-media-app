class TvBoxSite {
  const TvBoxSite({
    required this.key,
    required this.name,
    required this.api,
    required this.type,
    required this.searchable,
    required this.quickSearch,
    required this.filterable,
  });

  final String key;
  final String name;

  /// Kept as inert metadata. The catalog layer never requests or executes it.
  final String? api;
  final int? type;
  final bool searchable;
  final bool quickSearch;
  final bool filterable;
}

class TvBoxLiveChannel {
  const TvBoxLiveChannel({
    required this.name,
    required this.url,
    required this.number,
  });

  final String name;

  /// Kept as inert metadata; playback/network access is not implemented here.
  final String? url;
  final int? number;
}

class TvBoxLiveGroup {
  const TvBoxLiveGroup({
    required this.name,
    required this.type,
    required this.sourceUrl,
    required this.channels,
  });

  final String name;
  final int? type;

  /// External playlist URLs are not fetched by this catalog parser.
  final String? sourceUrl;
  final List<TvBoxLiveChannel> channels;

  TvBoxLiveGroup withChannels(List<TvBoxLiveChannel> value) {
    return TvBoxLiveGroup(
      name: name,
      type: type,
      sourceUrl: sourceUrl,
      channels: List.unmodifiable(value),
    );
  }
}

class TvBoxCatalogSnapshot {
  const TvBoxCatalogSnapshot({
    required this.configId,
    required this.configName,
    required this.sites,
    required this.liveGroups,
  });

  final int configId;
  final String configName;
  final List<TvBoxSite> sites;
  final List<TvBoxLiveGroup> liveGroups;

  int get liveChannelCount =>
      liveGroups.fold<int>(0, (total, group) => total + group.channels.length);

  List<TvBoxSite> searchSites(String input) {
    final query = input.trim().toLowerCase();
    if (query.isEmpty) return sites;
    return sites
        .where((site) =>
            site.name.toLowerCase().contains(query) ||
            site.key.toLowerCase().contains(query))
        .toList(growable: false);
  }

  /// A query matching a group keeps all of its channels. A query matching a
  /// channel returns only those matching channels within the matching group.
  List<TvBoxLiveGroup> searchLiveGroups(String input) {
    final query = input.trim().toLowerCase();
    if (query.isEmpty) return liveGroups;

    final matches = <TvBoxLiveGroup>[];
    for (final group in liveGroups) {
      if (group.name.toLowerCase().contains(query)) {
        matches.add(group);
        continue;
      }

      final channels = group.channels
          .where((channel) => channel.name.toLowerCase().contains(query))
          .toList(growable: false);
      if (channels.isNotEmpty) {
        matches.add(group.withChannels(channels));
      }
    }
    return matches;
  }
}
