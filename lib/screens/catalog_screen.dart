import 'package:material_ui/material_ui.dart';

import '../models/tvbox_catalog.dart';
import '../repositories/tvbox_config_repository.dart';
import '../services/tvbox_catalog_service.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  TvBoxConfigRepository? _repository;
  TvBoxCatalogSnapshot? _catalog;
  bool _loading = true;
  String? _error;
  int _section = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repository = _repository ??
          await TvBoxConfigRepository.openForCurrentPlatform();
      _repository = repository;
      final entry = await repository.getDefaultConfig();

      if (!mounted) return;
      setState(() {
        _catalog = entry == null
            ? null
            : const TvBoxCatalogService().parseEntry(entry);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  String _friendlyError(Object error) {
    var message = error.toString();
    for (final prefix in ['FormatException: ', 'StateError: ']) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length);
      }
    }
    return message;
  }

  void _showSiteDetails(TvBoxSite site) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(site.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('站点标识：${site.key}'),
            const SizedBox(height: 8),
            Text('类型：${site.type?.toString() ?? '未指定'}'),
            Text('支持搜索：${site.searchable ? '是' : '否'}'),
            Text('快捷搜索：${site.quickSearch ? '是' : '否'}'),
            Text('筛选：${site.filterable ? '是' : '否'}'),
            const SizedBox(height: 10),
            const Text(
              '站点 API 地址仅作为配置数据保存；当前版本不会执行 spider 或自动请求远程接口。',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _repository?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final query = _searchController.text;
    final sites = catalog?.searchSites(query) ?? const <TvBoxSite>[];
    final groups =
        catalog?.searchLiveGroups(query) ?? const <TvBoxLiveGroup>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '接口资源目录',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: '重新读取默认接口缓存',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (catalog != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '当前接口：${catalog.configName} · ${catalog.sites.length} 个站点 · ${catalog.liveGroups.length} 个直播分组 · ${catalog.liveChannelCount} 个内嵌频道',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: TextField(
            controller: _searchController,
            enabled: !_loading && catalog != null,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索站点名称、标识或直播频道',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment<int>(
                value: 0,
                icon: const Icon(Icons.language),
                label: Text('站点源 ${catalog?.sites.length ?? 0}'),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: const Icon(Icons.live_tv),
                label: Text('直播 ${catalog?.liveChannelCount ?? 0}'),
              ),
            ],
            selected: <int>{_section},
            onSelectionChanged: _loading
                ? null
                : (values) => setState(() => _section = values.first),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _messageState(
                      icon: Icons.error_outline,
                      title: '读取接口缓存失败',
                      message: _error!,
                    )
                  : catalog == null
                      ? _messageState(
                          icon: Icons.link_off,
                          title: '还没有默认接口',
                          message: '先到「我的 → 配置管理」导入你拥有或获授权的 JSON 配置。',
                        )
                      : _section == 0
                          ? _buildSites(sites)
                          : _buildLiveGroups(groups),
        ),
      ],
    );
  }

  Widget _buildSites(List<TvBoxSite> sites) {
    if (sites.isEmpty) {
      return _messageState(
        icon: Icons.search_off,
        title: '没有匹配的站点',
        message: '检查关键词，或切换到其他接口。',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      itemCount: sites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final site = sites[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.public)),
            title: Text(site.name),
            subtitle: Text(
              '${site.key} · ${site.searchable ? '支持搜索' : '未声明搜索'} · ${site.filterable ? '支持筛选' : '未声明筛选'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.info_outline),
            onTap: () => _showSiteDetails(site),
          ),
        );
      },
    );
  }

  Widget _buildLiveGroups(List<TvBoxLiveGroup> groups) {
    if (groups.isEmpty) {
      return _messageState(
        icon: Icons.live_tv,
        title: '没有匹配的直播分组',
        message: '检查关键词，或确认配置中是否包含 lives 数据。',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final group = groups[index];
        return Card(
          child: ExpansionTile(
            leading: const Icon(Icons.live_tv_outlined),
            title: Text(group.name),
            subtitle: Text(
              group.channels.isEmpty
                  ? '配置包含直播源地址；当前版本不自动下载 live.txt 或远程播放列表'
                  : '${group.channels.length} 个频道（仅展示 JSON 内嵌元数据）',
            ),
            children: [
              if (group.channels.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '外部播放列表暂不读取，避免未经验证的远程内容或脚本被自动执行。',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ),
                )
              else
                for (final channel in group.channels)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.tv, size: 18),
                    title: Text(channel.name),
                    trailing: channel.number == null
                        ? null
                        : Text(channel.number.toString()),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: Colors.white38),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}
