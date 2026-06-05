import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'src/data/local/local_store_stub.dart'
    if (dart.library.io) 'src/data/local/local_store_io.dart'
    if (dart.library.js_interop) 'src/data/local/local_store_web.dart';
import 'src/state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localStore = await openDefaultLocalStore();
  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(localStore)],
      child: const RssCopilotApp(),
    ),
  );
}
