@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rss_copilot_client/src/data/local/local_store_web.dart';
import 'package:rss_copilot_client/src/models/auth_user.dart';
import 'package:rss_copilot_client/src/models/session_data.dart';

void main() {
  test('opens browser local store and persists session data', () async {
    final firstStore = await openDefaultLocalStore();
    addTearDown(firstStore.close);

    const session = SessionData(
      token: 'web-token',
      baseUrl: 'http://localhost:8080',
      user: AuthUser(
        id: 42,
        email: 'web@example.com',
        displayName: 'Web Reader',
      ),
      lastServerTime: null,
      themeOverride: null,
    );
    await firstStore.saveSession(session);
    await firstStore.close();

    final secondStore = await openDefaultLocalStore();
    addTearDown(secondStore.close);

    final restored = await secondStore.loadSession();
    expect(restored?.token, session.token);
    expect(restored?.baseUrl, session.baseUrl);
    expect(restored?.user.id, session.user.id);
    expect(restored?.user.email, session.user.email);
    expect(restored?.user.displayName, session.user.displayName);
    await secondStore.clearAll();
  });

  test('falls back to memory when browser storage is unavailable', () async {
    final store = await openWebLocalStoreWithFallback(
      () => Future.error(StateError('IndexedDB unavailable')),
      timeout: const Duration(milliseconds: 1),
    );
    addTearDown(store.close);

    const session = SessionData(
      token: 'fallback-token',
      baseUrl: 'http://localhost:8080',
      user: AuthUser(
        id: 7,
        email: 'fallback@example.com',
        displayName: 'Fallback Reader',
      ),
      lastServerTime: null,
      themeOverride: null,
    );

    await store.saveSession(session);
    final restored = await store.loadSession();

    expect(restored?.token, session.token);
    expect(restored?.user.email, session.user.email);
  });
}
