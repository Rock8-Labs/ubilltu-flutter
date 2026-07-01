import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubilltu_example/main.dart';

void main() {
  testWidgets('renders the sign-in screen', (tester) async {
    await tester.pumpWidget(const UbilltuExampleApp());

    expect(find.text('ubilltu SDK example'), findsOneWidget);
    expect(find.text('Storefront slug'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
  });
}
