import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/main.dart';

void main() {
  testWidgets('App boots and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicxApp());
    expect(find.text('MusicX'), findsOneWidget);
  });
}
