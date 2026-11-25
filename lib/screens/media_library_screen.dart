import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/media_library_entry.dart';
import '../repositories/tvbox_config_repository.dart';

enum MediaLibraryMode { favorites, history }

class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({
    super.key,
    required this.mode,
    this.repositoryLoader,
  });

  final MediaLibraryMode mode;
  final Future<TvBoxConfigRepository> Function()? repositoryLoader;

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  TvBoxConfigRepository? _repository;
  List<FavoriteEntry> _favorites = const [];
  List<WatchHistoryEntry> _history = const [];
  bool _loading = true;
  String? _error;

  bool get _showFavorites => widget.mode == MediaLibraryMode.favorites;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    final repository = _repository;
    if (repository != null) {
      unawaited(repository.close());
    }
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      var repository = _repository;
      if (repository == null) {
        final loader = widget.repositoryLoader ??
            TvBoxConfigRepository.openForCurrentPlatform;
        repository = await loader();
        _repository = repository;
      }

      final favorites = _showFavorites
          ? await repository.listFavorites()
          : const <FavoriteEntry>[];
      final history = _showFavorites
          ? const <WatchHistoryEntry>[]
          : await repository.listWatchHistory();

      if (!mounted) return;
      setState(() {
        _favorites = favorites;
        _history = history;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
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

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _removeFavorite(FavoriteEntry entry) async {
    final confirmed = await _confirm(
      title: '取消收藏',
      message: '确定从收藏列表移除「${entry.title}」吗？',
      confirmLabel: '移除',
    );
    if (!confirmed || !mounted) return;

    try {
      await _repository!.removeFavorite(entry.mediaKey);
      await _load(showLoading: false);
      if (mounted) _showMessage('已取消收藏');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _removeHistory(WatchHistoryEntry entry) async {
    final confirmed = await _confirm(
      title: '删除观看记录',
      message: '确定删除「${entry.title}」的观看记录吗？',
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) return;

    try {
      await _repository!.removeWatchHistory(entry.mediaKey);
      await _load(showLoading: false);
      if (mounted) _showMessage('观看记录已删除');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _clearHistory() async {
    if (_history.isEmpty) return;
    final confirmed = await _confirm(
      title: '清空观看历史',
      message: '这只会清除观看记录，不会影响收藏或接口配置。',
      confirmLabel: '清空历史',
    );
    if (!confirmed || !mounted) return;

    try {
      await _repository!.clearWatchHistory();
      await _load(showLoading: false);
      if (mounted) _showMessage('观看历史已清空');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _showFavorites ? '我的收藏' : '观看历史';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (!_showFavorites)
                IconButton(
                  tooltip: '清空观看历史',
                  onPressed: _loading || _history.isEmpty ? null : _clearHistory,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              IconButton(
                tooltip: '刷新列表',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('读取本地记录失败'),
                subtitle: Text(_error!),
                trailing: IconButton(
                  tooltip: '重试',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _emptyState(
                      icon: Icons.storage_outlined,
                      title: '暂时无法读取本地记录',
                      message: '检查应用存储权限或重新打开页面后重试。',
                    )
                  : _showFavorites
                      ? _buildFavorites()
                      : _buildHistory(),
        ),
      ],
    );
  }

  Widget _buildFavorites() {
    if (_favorites.isEmpty) {
      return _emptyState(
        icon: Icons.bookmark_border,
        title: '还没有收藏内容',
        message: '收藏的数据会保存在本机；切换或删除接口不会清除收藏。',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      itemCount: _favorites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = _favorites[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.bookmark),
            ),
            title: Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '标识：${entry.mediaKey}\n收藏于 ${_formatDate(entry.createdAt)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: '取消收藏',
              onPressed: () => _removeFavorite(entry),
              icon: const Icon(Icons.bookmark_remove_outlined),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return _emptyState(
        icon: Icons.history,
        title: '还没有观看记录',
        message: '播放器接入后，播放进度会自动保存在这里。',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = _history[index];
        final duration = entry.durationMs;
        final progress = entry.progressFraction;
        final progressLabel = duration == null || duration <= 0
            ? '时长未知'
            : '${(progress! * 100).round()}%';

        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            child: Row(
              children: [
                const CircleAvatar(
                  child: Icon(Icons.play_circle_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDuration(entry.positionMs)} / ${duration == null ? '时长未知' : _formatDuration(duration)} · $progressLabel',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '最近更新：${_formatDate(entry.updatedAt)}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '删除观看记录',
                  onPressed: () => _removeHistory(entry),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState({
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
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
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

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  String _formatDuration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainder = seconds % 60;
    final minuteText = minutes.toString().padLeft(2, '0');
    final secondText = remainder.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minuteText:$secondText';
    }
    return '$minuteText:$secondText';
  }
}
