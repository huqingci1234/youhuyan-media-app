import 'package:flutter/material.dart';
import '../models/tvbox_config.dart';
import '../services/config_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  final _repository = ConfigRepository();
  TvBoxConfig? _config;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastUrl();
  }

  Future<void> _loadLastUrl() async {
    final value = await _repository.lastSuccessfulUrl();
    if (mounted && value != null) _urlController.text = value;
  }

  Future<void> _import() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await _repository.importFromUrl(_urlController.text);
      if (mounted) setState(() => _config = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('配置管理', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('仅导入并统计 JSON 配置数据；不会执行远程脚本、下载 JAR 或运行未知插件。',
            style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 18),
        TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'HTTPS 配置地址',
            hintText: 'https://example.com/config.json',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _import,
          icon: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined),
          label: Text(_loading ? '正在读取…' : '导入配置'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        if (_config != null) ...[
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_config!.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _StatRow(label: '影视站点', value: _config!.siteCount),
                  _StatRow(label: '直播分组/项目', value: _config!.liveCount),
                  _StatRow(label: '解析配置', value: _config!.parseCount),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Divider(),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.workspace_premium_outlined),
          title: Text('会员计划'),
          subtitle: Text('基础版永久免费 · VIP 半年 ¥39.9 · 一年 ¥69.9（尚未接入核销服务）'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.devices_outlined),
          title: Text('设备数量'),
          subtitle: Text('VIP 计划最多绑定 3 台设备（功能规划中）'),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text('$value', style: const TextStyle(fontWeight: FontWeight.bold))],
    ),
  );
}
