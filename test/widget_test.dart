import 'package:flutter_test/flutter_test.dart';
import 'package:youhuyan_media/main.dart';

void main() {
  testWidgets('renders the Youhuyan home screen', (tester) async {
    await tester.pumpWidget(const YouhuyanApp());
    await tester.pumpAndSettle();

    expect(find.text('尤湖沿影视'), findsOneWidget);
    expect(find.text('内容频道'), findsOneWidget);
  });
}
