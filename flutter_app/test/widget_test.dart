import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:antigravity_mobile/main.dart';
import 'package:antigravity_mobile/views/home_scaffold.dart';

void main() {
  testWidgets('AntigravityApp launches without exceptions', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const ProviderScope(
        child: AntigravityApp(),
      ),
    );
    await tester.pump();

    // Verify app rendered cleanly
    expect(find.byType(AntigravityApp), findsOneWidget);
  });

  testWidgets('HomeScaffold renders navigation tabs and topbar cleanly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: HomeScaffold(),
        ),
      ),
    );
    await tester.pump();

    // Verify navigation tabs
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('15-Fleet'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);

    // Verify topbar actions
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });
}
