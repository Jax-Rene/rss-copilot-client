import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import 'local_store.dart';

Future<LocalStore> openDefaultLocalStore() async {
  final directory = await getApplicationSupportDirectory();
  final databasePath = path.join(directory.path, 'rss_copilot_client.db');
  return LocalStore.openWithFactory(databaseFactoryIo, databasePath);
}
