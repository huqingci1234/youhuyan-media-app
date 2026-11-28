import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:youhuyan_media/repositories/tvbox_config_repository.dart';
import 'package:youhuyan_media/screens/media_library_screen.dart';

Future<void> _pumpUntilText(
  WidgetTester tester,
  String text, {
  int maxAttempts = 40,
}) async {
  final finder = find.text(text);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('在有限等待时间内未出现文本：$text');
}

void main() {
  late TvBoxConfigRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() {
    repository = TvBoxConfigRepository(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
    );
  });

  tearDown(() async {
    await repository.close();
  });

  testWidgets('shows persisted favorites and removes a selected item',
      (tester) async {
    await repository.saveFavorite(
      mediaKey: 'site-a:movie-01',
      title: '珍藏电影',
      itemJson: '{"id":"movie-01","type":"movie"}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaLibraryScreen(
            mode: MediaLibraryMode.favorites,
            repositoryLoader: () async => repository,
          ),
        ),
      ),
    );
    await _pumpUntilText(tester, '珍藏电影');

    expect(find.text('珍藏电影'), findsOneWidget);

    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    expect(find.text('确定从收藏列表移除「珍藏电影」吗？'), findsOneWidget);

    await tester.tap(find.text('移除'));
    await _pumpUntilText(tester, '还没有收藏内容');

    expect(find.text('珍藏电影'), findsNothing);
    expect(find.text('还没有收藏内容'), findsOneWidget);
  });

  testWidgets('shows saved watch progress and clears history separately',
      (tester) async {
    await repository.saveFavorite(
      mediaKey: 'site-a:movie-02',
      title: '保留的收藏',
      itemJson: '{"id":"movie-02"}',
    );
    await repository.saveWatchProgress(
      mediaKey: 'site-a:episode-01',
      title: '正在追的剧集',
      itemJson: '{"id":"episode-01"}',
      positionMs: 90000,
      durationMs: 600000,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaLibraryScreen(
            mode: MediaLibraryMode.history,
            repositoryLoader: () async => repository,
          ),
        ),
      ),
    );
    await _pumpUntilText(tester, '正在追的剧集');

    expect(find.text('正在追的剧集'), findsOneWidget);
    expect(find.text('01:30 / 10:00 · 15%'), findsOneWidget);

    await tester.tap(find.byTooltip('清空观看历史'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空历史'));
    await _pumpUntilText(tester, '还没有观看记录');

    expect(find.text('还没有观看记录'), findsOneWidget);
    expect(await repository.listFavorites(), hasLength(1));
    expect(await repository.listWatchHistory(), isEmpty);
  });
}
