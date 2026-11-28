import 'package:material_ui/material_ui.dart';

import 'catalog_screen.dart';
import 'media_library_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _HomeContent(
        onOpenSettings: () => setState(() => _tab = 4),
        onOpenHistory: () => setState(() => _tab = 3),
      ),
      _tab == 1 ? const CatalogScreen() : const SizedBox.shrink(),
      _tab == 2
          ? const MediaLibraryScreen(mode: MediaLibraryMode.favorites)
          : const SizedBox.shrink(),
      _tab == 3
          ? const MediaLibraryScreen(mode: MediaLibraryMode.history)
          : const SizedBox.shrink(),
      _tab == 4 ? const SettingsScreen() : const SizedBox.shrink(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '尤湖沿影视',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '设置',
            onPressed: () => setState(() => _tab = 4),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: '资源',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: '收藏',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: '历史',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.onOpenSettings,
    required this.onOpenHistory,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFF394A9C), Color(0xFF202943)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WELCOME',
                style: TextStyle(letterSpacing: 2, color: Colors.white70),
              ),
              SizedBox(height: 12),
              Text(
                '发现喜欢的\n精彩内容',
                style: TextStyle(
                  fontSize: 27,
                  height: 1.25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '尤湖沿影视 · 让观影更简单',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          '内容频道',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _CategoryChip(icon: Icons.movie_outlined, label: '电影'),
            _CategoryChip(icon: Icons.live_tv_outlined, label: '电视剧'),
            _CategoryChip(icon: Icons.theater_comedy_outlined, label: '综艺'),
            _CategoryChip(icon: Icons.animation_outlined, label: '动漫'),
            _CategoryChip(icon: Icons.sensors, label: '直播'),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.history)),
            title: const Text('继续观看'),
            subtitle: const Text('查看最近保存的观看记录和播放进度'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenHistory,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.link)),
            title: const Text('导入影视配置'),
            subtitle: const Text('添加你拥有或获授权的 HTTPS JSON 配置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenSettings,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '当前为开发预览版；资源目录已接入，影视详情、站点检索 API 和实际播放器仍在开发中。观看历史页面目前展示本地保存的进度，尚不能直接续播。',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      );
}
