import 'dart:async';

import 'package:sembast_web/sembast_web.dart';

import 'local_store.dart';

Future<LocalStore> openDefaultLocalStore() async {
  return openWebLocalStoreWithFallback(
    () =>
        LocalStore.openWithFactory(databaseFactoryWeb, 'rss_copilot_client.db'),
  );
}

Future<LocalStore> openWebLocalStoreWithFallback(
  Future<LocalStore> Function() openPrimary, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    return await openPrimary().timeout(timeout);
  } catch (_) {
    return LocalStore.inMemory();
  }
}
