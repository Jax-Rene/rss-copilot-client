import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rss_copilot_client/app.dart';
import 'package:rss_copilot_client/src/data/local/local_store.dart';
import 'package:rss_copilot_client/src/state/providers.dart';

void main() {
  testWidgets('initializes local store and shows login page', (tester) async {
    final store = await LocalStore.inMemory();
    addTearDown(store.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const RssCopilotApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('RSS Copilot'), findsOneWidget);
    expect(find.text('登录到你的 RSS Copilot 服务端。'), findsOneWidget);
    expect(find.text('服务端地址'), findsOneWidget);
    expect(find.text('登录并初始化'), findsOneWidget);
  });
}
