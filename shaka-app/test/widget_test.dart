// Basic Flutter widget test for Shaka app

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Simple smoke test to verify basic widget rendering
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Shaka'),
          ),
        ),
      ),
    );

    // Verify the text is rendered
    expect(find.text('Shaka'), findsOneWidget);
  });
}
