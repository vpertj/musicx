import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musicx/main.dart';

void main() {
  testWidgets('App boots and shows home shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MusicxApp());
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
