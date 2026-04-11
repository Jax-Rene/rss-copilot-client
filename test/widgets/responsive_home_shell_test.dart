import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_copilot_client/src/ui/home/responsive_home_shell.dart';

void main() {
  Widget wrapForSize(Widget child) {
    return MaterialApp(home: Scaffold(body: child));
  }

  testWidgets('uses the desktop scaffold on large screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapForSize(
        ResponsiveHomeShell(
          navigationPane: Container(key: const Key('nav')),
          listPane: Container(key: const Key('list')),
          detailPane: Container(key: const Key('detail')),
          mobileBody: Container(key: const Key('mobile')),
        ),
      ),
    );

    expect(find.byKey(const Key('desktop-shell')), findsOneWidget);
    expect(find.byKey(const Key('mobile-shell')), findsNothing);
  });

  testWidgets('uses the mobile scaffold on narrow screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapForSize(
        ResponsiveHomeShell(
          navigationPane: Container(key: const Key('nav')),
          listPane: Container(key: const Key('list')),
          detailPane: Container(key: const Key('detail')),
          mobileBody: Container(key: const Key('mobile')),
        ),
      ),
    );

    expect(find.byKey(const Key('mobile-shell')), findsOneWidget);
    expect(find.byKey(const Key('desktop-shell')), findsNothing);
  });
}
