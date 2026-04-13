// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cipher_safety/main.dart';

void main() {
  testWidgets('renders listener screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const CipherSafetyApp(
        autoConnect: false,
        enableForegroundService: false,
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) {
          if (widget is! Image) return false;
          final ImageProvider provider = widget.image;
          if (provider is! AssetImage) return false;
          return provider.assetName == 'assets/images/cipher-safety-logotxt.png';
        },
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Subject:'), findsOneWidget);
  });
}
