import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

import '../../models/entry_detail.dart';
import '../../models/entry_list_item.dart';
import '../../models/entry_record.dart';
import '../../models/feed_source.dart';
import '../../models/session_data.dart';
import '../../models/settings_bundle.dart';
import '../../models/snapshot.dart';

class LocalStore {
  LocalStore._(this._database);

  final Database _database;

  final StoreRef<String, Map<String, dynamic>> _metaStore =
      stringMapStoreFactory.store('meta');
  final StoreRef<int, Map<String, dynamic>> _sourceStore = intMapStoreFactory
      .store('sources');
  final StoreRef<int, Map<String, dynamic>> _entryStore = intMapStoreFactory
      .store('entries');
  final StoreRef<String, Map<String, dynamic>> _listStore =
      stringMapStoreFactory.store('lists');

  static Future<LocalStore> openAtPath(String databasePath) async {
    final database = await databaseFactoryIo.openDatabase(databasePath);
    return LocalStore._(database);
  }

  static Future<LocalStore> inMemory() async {
    final database = await databaseFactoryMemory.openDatabase(
      'rss-copilot-test-${DateTime.now().microsecondsSinceEpoch}',
    );
    return LocalStore._(database);
  }

  Future<void> close() => _database.close();

  Future<void> clearAll() async {
    await _metaStore.delete(_database);
    await _sourceStore.delete(_database);
    await _entryStore.delete(_database);
    await _listStore.delete(_database);
  }

  Future<void> saveSession(SessionData? session) async {
    final record = _metaStore.record('session');
    if (session == null) {
      await record.delete(_database);
      return;
    }

    await record.put(_database, session.toJson());
  }

  Future<SessionData?> loadSession() async {
    final payload = await _metaStore.record('session').get(_database);
    if (payload == null) {
      return null;
    }

    return SessionData.fromJson(payload);
  }

  Future<void> saveSettings(SettingsBundle settings) async {
    await _metaStore.record('settings').put(_database, settings.toJson());
  }

  Future<SettingsBundle> loadSettings() async {
    final payload = await _metaStore.record('settings').get(_database);
    if (payload == null) {
      return const SettingsBundle.empty();
    }

    return SettingsBundle.fromJson(payload);
  }

  Future<void> upsertSources(List<FeedSource> sources) async {
    if (sources.isEmpty) {
      return;
    }

    final transaction = _database.transaction((txn) async {
      for (final source in sources) {
        await _sourceStore.record(source.id).put(txn, source.toJson());
      }
    });
    await transaction;
  }

  Future<void> upsertEntryDetails(List<EntryDetail> details) async {
    if (details.isEmpty) {
      return;
    }

    await _database.transaction((txn) async {
      for (final detail in details) {
        final previous = await _entryStore.record(detail.id).get(txn);
        final previousRecord = previous == null
            ? null
            : EntryRecord.fromJson(previous);
        final nextRecord = detail.toRecord(previous: previousRecord);
        await _entryStore.record(detail.id).put(txn, nextRecord.toJson());
      }
    });
  }

  Future<void> upsertEntryRecord(EntryRecord record) async {
    await _entryStore.record(record.id).put(_database, record.toJson());
  }

  Future<EntryRecord?> loadEntry(int id) async {
    final payload = await _entryStore.record(id).get(_database);
    if (payload == null) {
      return null;
    }

    return EntryRecord.fromJson(payload);
  }

  Future<void> applyListSnapshot(ListKey key, List<EntryListItem> items) async {
    await _database.transaction((txn) async {
      for (final item in items) {
        final previous = await _entryStore.record(item.id).get(txn);
        final previousRecord = previous == null
            ? null
            : EntryRecord.fromJson(previous);
        await _entryStore
            .record(item.id)
            .put(txn, item.toRecord(previous: previousRecord).toJson());
      }

      await _listStore.record(key.value).put(txn, <String, dynamic>{
        'ids': items.map((item) => item.id).toList(growable: false),
      });
    });
  }

  Future<void> deleteSources(List<int> sourceIds) async {
    if (sourceIds.isEmpty) {
      return;
    }

    await _database.transaction((txn) async {
      for (final sourceId in sourceIds) {
        await _sourceStore.record(sourceId).delete(txn);
      }

      final entrySnapshots = await _entryStore.find(txn);
      final deletedEntryIds = <int>[];
      for (final snapshot in entrySnapshots) {
        final entry = EntryRecord.fromJson(snapshot.value);
        if (sourceIds.contains(entry.sourceId)) {
          deletedEntryIds.add(snapshot.key);
          await _entryStore.record(snapshot.key).delete(txn);
        }
      }

      final listSnapshots = await _listStore.find(txn);
      for (final listSnapshot in listSnapshots) {
        final ids =
            ((listSnapshot.value['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => !deletedEntryIds.contains(id))
                .toList(growable: false);
        final shouldDeleteSourceList = sourceIds.any(
          (sourceId) => listSnapshot.key == ListKey.source(sourceId).value,
        );
        if (shouldDeleteSourceList) {
          await _listStore.record(listSnapshot.key).delete(txn);
        } else {
          await _listStore.record(listSnapshot.key).put(txn, <String, dynamic>{
            'ids': ids,
          });
        }
      }
    });
  }

  Future<AppSnapshot> loadSnapshot() async {
    final settings = await loadSettings();
    final sourceSnapshots = await _sourceStore.find(_database);
    final entrySnapshots = await _entryStore.find(_database);
    final listSnapshots = await _listStore.find(_database);

    final sources =
        sourceSnapshots
            .map((snapshot) => FeedSource.fromJson(snapshot.value))
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.name.toLowerCase().compareTo(right.name.toLowerCase()),
          );
    final entries = <int, EntryRecord>{
      for (final snapshot in entrySnapshots)
        snapshot.key: EntryRecord.fromJson(snapshot.value),
    };
    final lists = <String, List<int>>{
      for (final snapshot in listSnapshots)
        snapshot.key:
            ((snapshot.value['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .toList(growable: false),
    };

    return AppSnapshot(
      sources: sources,
      settings: settings,
      entries: entries,
      listSnapshots: lists,
    );
  }
}
