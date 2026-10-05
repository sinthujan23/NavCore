import 'package:flutter_test/flutter_test.dart';
import 'package:nexnav_mobile/main.dart';

void main() {
  testWidgets('NexNav mobile app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NexNavApp());
    expect(find.byType(NexNavApp), findsOneWidget);
  });
}
