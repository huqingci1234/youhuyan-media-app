import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../models/tvbox_config_entry.dart';
import '../repositories/tvbox_config_repository.dart';
import '../services/tvbox_config_import_service.dart';
import '../services/tvbox_config_validator.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  TvBoxConfigRepository? _repository;
  TvBoxConfigImportService? _importService;
  List<TvBoxConfigEntry> _configs = const [];
  bool _initializing = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final repository = await TvBoxConfigRepository.openForCurrentPlatform();
      final configs = await repository.listConfigs();
      if (!mounted) {
        await repository.close();
        return;
      }
      setState(() {
        _repository = repository;
        _importService = TvBoxConfigImportService(repository: repository);
        _configs = configs;
        _initializing = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(error);
          _initializing = false;
        });
      }
    }
  }

  Future<void> _reloadConfigs() async {
    final repository = _repository;
    if (repository == null) return;
    final configs = await repository.listConfigs();
    if (mounted) setState(() => _configs = configs);
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy || _importService == null || _repository == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await action();
      await _reloadConfigs();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importRemote() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '请先输入 HTTPS 配置地址');
      return;
    }

    await _perform(() async {
      final entry = await _importService!.importRemote(url: url);
      _urlController.clear();
      _showMessage('已添加配置：' + entry.name);
    });
  }

  Future<void> _importLocalFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;

      final length = file.lengthSync() ?? await file.length();
      if (length > TvBoxConfigValidator.maxDocumentBytes) {
        setState(() => _error = '本地 JSON 文件超过 2 MiB 限制');
        return;
      }

      await _perform(() async {
        final entry = await _importService!.importLocalStream(
          fileName: file.name,
          bytes: file.readAsByteStream(),
        );
        _showMessage('已导入本地配置：' + entry.name);
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _setDefault(TvBoxConfigEntry entry) async {
    await _perform(() async {
      await _repository!.setDefaultConfig(entry.id);
      _showMessage('默认接口已切换为：' + entry.name);
    });
  }

  Future<void> _refresh(TvBoxConfigEntry entry) async {
    await _perform(() async {
      await _importService!.refreshRemote(entry.id);
      _showMessage('刷新成功：' + entry.name);
    });
  }

  Future<void> _editUrl(TvBoxConfigEntry entry) async {
    final controller = TextEditingController(text: entry.sourceUrl ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('修改配置地址'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: '新的 HTTPS JSON 地址',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('验证并保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;

    await _perform(() async {
      await _importService!.updateRemote(
        id: entry.id,
        url: value,
        name: entry.name,
      );
      _showMessage('新地址验证成功，配置已更新');
    });
  }

  Future<void> _rename(TvBoxConfigEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名配置'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '配置名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;

    await _perform(() async {
      await _repository!.renameConfig(entry.id, value);
    });
  }

  Future<void> _delete(TvBoxConfigEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除接口？'),
        content: Text('将删除本地保存的「' + entry.name + '」配置缓存。收藏和观看历史不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _perform(() async {
      await _repository!.deleteConfig(entry.id);
      _showMessage('配置已删除');
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _friendlyError(Object error) {
    var message = error.toString();
    for (final prefix in ['FormatException: ', 'Bad state: ', 'StateError: ']) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length);
      }
    }
    return message;
  }

  String _statusText(ConfigLastStatus status) {
    return switch (status) {
      ConfigLastStatus.never => '未刷新',
      ConfigLastStatus.success => '验证成功',
      ConfigLastStatus.error => '上次尝试失败',
    };
  }

  String _dateText(DateTime? value) {
    if (value == null) return '暂无';
    return value.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _repository?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('配置管理', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          '仅导入并读取 JSON 数据；不会执行 spider、远程脚本或 JAR，也不会下载未知插件。',
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _urlController,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'HTTPS 配置地址',
            hintText: 'https://example.com/config.json',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _importRemote,
              icon: const Icon(Icons.add_link),
              label: const Text('添加远程接口'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importLocalFile,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('导入本地 JSON'),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 6),
          const Text('正在验证并保存…', style: TextStyle(color: Colors.white60)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text('已保存的接口', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Text(_configs.length.toString() + ' 个', style: const TextStyle(color: Colors.white60)),
          ],
        ),
        const SizedBox(height: 10),
        if (_configs.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('还没有配置。可粘贴你拥有或获授权的 HTTPS JSON 地址，或从本地选择 JSON 文件。'),
            ),
          )
        else
          for (final entry in _configs) _configCard(entry),
        const SizedBox(height: 24),
        const Divider(),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.workspace_premium_outlined),
          title: Text('会员计划'),
          subtitle: Text('基础版永久免费 · VIP 半年 ¥39.9 · 一年 ¥69.9（服务端核销尚未接入）'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.devices_outlined),
          title: Text('设备数量'),
          subtitle: Text('VIP 计划最多绑定 3 台设备（功能开发中）'),
        ),
      ],
    );
  }

  Widget _configCard(TvBoxConfigEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.name,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                if (entry.isDefault)
                  const Chip(
                    avatar: Icon(Icons.check_circle, size: 16),
                    label: Text('默认接口'),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              entry.sourceUrl ?? '本地 JSON 文件',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('站点 ' + entry.siteCount.toString()),
                Text('直播 ' + entry.liveCount.toString()),
                Text('解析 ' + entry.parseCount.toString()),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _statusText(entry.lastStatus) + ' · 上次成功：' + _dateText(entry.lastSuccessAt),
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (entry.lastError != null && entry.lastError!.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                '错误：' + entry.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!entry.isDefault)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _setDefault(entry),
                    icon: const Icon(Icons.star_outline),
                    label: const Text('设为默认'),
                  ),
                if (entry.sourceType == ConfigSourceType.remoteUrl) ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _refresh(entry),
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _editUrl(entry),
                    icon: const Icon(Icons.edit_link),
                    label: const Text('修改地址'),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _rename(entry),
                  icon: const Icon(Icons.drive_file_rename_outline),
                  label: const Text('重命名'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : () => _delete(entry),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
