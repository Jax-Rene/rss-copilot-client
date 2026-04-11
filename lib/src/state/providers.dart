import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/local/local_store.dart';
import '../repositories/rss_repository.dart';
import 'app_controller.dart';

final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden in main()');
});

final rssRepositoryProvider = Provider<RssRepository>((ref) {
  return RssRepository(store: ref.watch(localStoreProvider));
});

final appControllerProvider = ChangeNotifierProvider<AppController>((ref) {
  return AppController(repository: ref.watch(rssRepositoryProvider));
});
