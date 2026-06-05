import 'package:sembast/sembast_memory.dart';

import '../../core/search_query.dart';
import '../../models/entry_detail.dart';
import '../../models/entry_list_item.dart';
import '../../models/entry_page_cursor.dart';
import '../../models/entry_record.dart';
import '../../models/feed_source.dart';
import '../../models/pending_entry_action.dart';
import '../../models/reader_preferences.dart';
import '../../models/session_data.dart';
import '../../models/settings_bundle.dart';
import '../../models/snapshot.dart';

class LocalStore {
  LocalStore._(this._database);

  static int _inMemorySequence = 0;

  final Database _database;

  final StoreRef<String, Map<String, dynamic>> _metaStore =
      stringMapStoreFactory.store('meta');
  final StoreRef<int, Map<String, dynamic>> _sourceStore = intMapStoreFactory
      .store('sources');
  final StoreRef<int, Map<String, dynamic>> _entryStore = intMapStoreFactory
      .store('entries');
  final StoreRef<String, Map<String, dynamic>> _listStore =
      stringMapStoreFactory.store('lists');
  final StoreRef<String, Map<String, dynamic>> _pendingEntryActionStore =
      stringMapStoreFactory.store('pending_entry_actions');

  static Future<LocalStore> openWithFactory(
    DatabaseFactory factory,
    String databasePath,
  ) async {
    final database = await factory.openDatabase(databasePath);
    return LocalStore._(database);
  }

  static Future<LocalStore> inMemory() async {
    final sequence = _inMemorySequence++;
    final nonce = identityHashCode(Object());
    final database = await databaseFactoryMemory.openDatabase(
      'rss-copilot-test-${DateTime.now().microsecondsSinceEpoch}-$sequence-$nonce',
    );
    return LocalStore._(database);
  }

  Future<void> close() => _database.close();

  Future<void> clearAll() async {
    await _metaStore.delete(_database);
    await _sourceStore.delete(_database);
    await _entryStore.delete(_database);
    await _listStore.delete(_database);
    await _pendingEntryActionStore.delete(_database);
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

  Future<void> replaceRemoteSnapshot({
    required SettingsBundle settings,
    required List<FeedSource> sources,
    required List<EntryDetail> entries,
  }) async {
    await _database.transaction((txn) async {
      await _metaStore.record('settings').put(txn, settings.toJson());
      await _sourceStore.delete(txn);
      await _entryStore.delete(txn);
      await _listStore.delete(txn);

      for (final source in sources) {
        await _sourceStore.record(source.id).put(txn, source.toJson());
      }
      final records = <EntryRecord>[];
      for (final entry in entries) {
        final record = entry.toRecord();
        records.add(record);
        await _entryStore.record(entry.id).put(txn, record.toJson());
      }
      records.sort(_compareEntriesNewestFirst);

      Future<void> putList(
        ListKey key,
        Iterable<EntryRecord> listEntries,
      ) async {
        await _listStore.record(key.value).put(txn, <String, dynamic>{
          'ids': listEntries.map((entry) => entry.id).toList(growable: false),
          'hasMore': false,
          'nextCursor': null,
        });
      }

      await putList(ListKey.all, records);
      await putList(ListKey.feed, records.where((entry) => !entry.isNoise));
      await putList(ListKey.noise, records.where((entry) => entry.isNoise));
      await putList(ListKey.saved, records.where((entry) => entry.isSaved));
    });
  }

  Future<void> saveReaderPreferences(ReaderPreferences preferences) async {
    await _metaStore
        .record('readerPreferences')
        .put(_database, preferences.toJson());
  }

  Future<ReaderPreferences> loadReaderPreferences() async {
    final payload = await _metaStore.record('readerPreferences').get(_database);
    if (payload == null) {
      return ReaderPreferences.defaultPreferences;
    }

    return ReaderPreferences.fromJson(payload);
  }

  Future<void> upsertSources(List<FeedSource> sources) async {
    if (sources.isEmpty) {
      return;
    }

    final transaction = _database.transaction((txn) async {
      final sourceSnapshots = await _sourceStore.find(txn);
      final existingSources = <int, FeedSource>{
        for (final sourceSnapshot in sourceSnapshots)
          sourceSnapshot.key: FeedSource.fromJson(sourceSnapshot.value),
      };
      final changedOldFolders = <String>{};
      final foldersAfterUpdate = <String>{};
      final incomingSources = <int, FeedSource>{
        for (final source in sources) source.id: source,
      };
      for (final existingSource in existingSources.values) {
        final incomingSource = incomingSources[existingSource.id];
        if (incomingSource == null) {
          foldersAfterUpdate.add(_normalizedFolder(existingSource));
          continue;
        }
        final oldFolder = _normalizedFolder(existingSource);
        final newFolder = _normalizedFolder(incomingSource);
        foldersAfterUpdate.add(newFolder);
        if (oldFolder != newFolder) {
          changedOldFolders.add(oldFolder);
        }
      }
      for (final source in sources) {
        if (!existingSources.containsKey(source.id)) {
          foldersAfterUpdate.add(_normalizedFolder(source));
        }
      }
      final orphanedFolders = changedOldFolders.difference(foldersAfterUpdate);
      final resetSourceIds = <int>{};

      for (final source in sources) {
        final previousSource = existingSources[source.id];
        await _sourceStore.record(source.id).put(txn, source.toJson());
        final rssUrlChanged =
            previousSource != null && previousSource.rssUrl != source.rssUrl;
        final preservesEntriesForRefreshRedirect =
            rssUrlChanged && source.lastFetchedAt != null && !source.hasError;
        if (rssUrlChanged && !preservesEntriesForRefreshRedirect) {
          resetSourceIds.add(source.id);
          continue;
        }
        final shouldReconcileEntries =
            previousSource == null ||
            previousSource.name != source.name ||
            previousSource.iconUrl != source.iconUrl ||
            _normalizedFolder(previousSource) != _normalizedFolder(source);
        if (!shouldReconcileEntries) {
          continue;
        }

        final entrySnapshots = await _entryStore.find(txn);
        for (final entrySnapshot in entrySnapshots) {
          final entry = EntryRecord.fromJson(entrySnapshot.value);
          if (entry.sourceId != source.id) {
            continue;
          }

          final nextEntry =
              entry.sourceName == source.name &&
                  entry.sourceIconUrl == source.iconUrl
              ? entry
              : entry.copyWith(
                  sourceName: source.name,
                  sourceIconUrl: source.iconUrl,
                  clearSourceIconUrl: source.iconUrl == null,
                );
          if (nextEntry.sourceName != entry.sourceName ||
              nextEntry.sourceIconUrl != entry.sourceIconUrl) {
            await _entryStore.record(nextEntry.id).put(txn, nextEntry.toJson());
          }
          await _reconcileEntryInCachedLists(txn, nextEntry, source);
        }
      }

      final resetEntryIds = <int>[];
      if (resetSourceIds.isNotEmpty) {
        final entrySnapshots = await _entryStore.find(txn);
        for (final entrySnapshot in entrySnapshots) {
          final entry = EntryRecord.fromJson(entrySnapshot.value);
          if (resetSourceIds.contains(entry.sourceId)) {
            resetEntryIds.add(entrySnapshot.key);
            await _entryStore.record(entrySnapshot.key).delete(txn);
          }
        }
        await _deletePendingEntryActionsForEntryIds(txn, resetEntryIds.toSet());
      }

      if (orphanedFolders.isNotEmpty) {
        final listSnapshots = await _listStore.find(txn);
        for (final listSnapshot in listSnapshots) {
          final shouldDeleteSourceList = ListKey.isSourceScopedValue(
            listSnapshot.key,
            resetSourceIds,
          );
          final shouldDeleteFolderList = ListKey.isFolderScopedValue(
            listSnapshot.key,
            orphanedFolders,
          );
          if (shouldDeleteSourceList || shouldDeleteFolderList) {
            await _listStore.record(listSnapshot.key).delete(txn);
            continue;
          }
          if (resetEntryIds.isNotEmpty) {
            final ids =
                ((listSnapshot.value['ids'] as List<dynamic>?) ??
                        const <dynamic>[])
                    .whereType<int>()
                    .where((id) => !resetEntryIds.contains(id))
                    .toList(growable: false);
            await _listStore.record(listSnapshot.key).put(
              txn,
              <String, dynamic>{...listSnapshot.value, 'ids': ids},
            );
          }
        }
      } else if (resetSourceIds.isNotEmpty) {
        final listSnapshots = await _listStore.find(txn);
        for (final listSnapshot in listSnapshots) {
          if (ListKey.isSourceScopedValue(listSnapshot.key, resetSourceIds)) {
            await _listStore.record(listSnapshot.key).delete(txn);
            continue;
          }
          final ids =
              ((listSnapshot.value['ids'] as List<dynamic>?) ??
                      const <dynamic>[])
                  .whereType<int>()
                  .where((id) => !resetEntryIds.contains(id))
                  .toList(growable: false);
          await _listStore.record(listSnapshot.key).put(txn, <String, dynamic>{
            ...listSnapshot.value,
            'ids': ids,
          });
        }
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

        final sourcePayload = await _sourceStore
            .record(nextRecord.sourceId)
            .get(txn);
        final source = sourcePayload == null
            ? null
            : FeedSource.fromJson(sourcePayload);
        await _reconcileEntryInCachedLists(txn, nextRecord, source);
      }
    });
  }

  Future<void> upsertEntryRecord(EntryRecord record) async {
    await _entryStore.record(record.id).put(_database, record.toJson());
  }

  Future<void> setEntrySaved(int entryId, bool isSaved) async {
    await _database.transaction((txn) async {
      final payload = await _entryStore.record(entryId).get(txn);
      if (payload == null) {
        return;
      }

      final current = EntryRecord.fromJson(payload);
      final nextRecord = current.copyWith(isSaved: isSaved);
      await _entryStore.record(entryId).put(txn, nextRecord.toJson());

      final sourcePayload = await _sourceStore
          .record(current.sourceId)
          .get(txn);
      final source = sourcePayload == null
          ? null
          : FeedSource.fromJson(sourcePayload);

      Future<void> removeFromList(String key) async {
        final listPayload = await _listStore.record(key).get(txn);
        if (listPayload == null) {
          return;
        }
        final ids =
            ((listPayload['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => id != entryId)
                .toList(growable: false);
        await _listStore.record(key).put(txn, <String, dynamic>{
          'ids': ids,
          'hasMore': listPayload['hasMore'] as bool? ?? false,
          'nextCursor': listPayload['nextCursor'],
        });
      }

      Future<void> addToSortedList(String key) async {
        final listPayload = await _listStore.record(key).get(txn);
        if (listPayload == null) {
          return;
        }
        final ids =
            ((listPayload['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => id != entryId)
                .toList(growable: true)
              ..add(entryId);
        final entries = <EntryRecord>[];
        for (final id in ids) {
          final entryPayload = await _entryStore.record(id).get(txn);
          if (entryPayload != null) {
            entries.add(EntryRecord.fromJson(entryPayload));
          }
        }
        entries.sort(_compareEntriesNewestFirst);
        await _listStore.record(key).put(txn, <String, dynamic>{
          'ids': entries.map((entry) => entry.id).toList(growable: false),
          'hasMore': listPayload['hasMore'] as bool? ?? false,
          'nextCursor': listPayload['nextCursor'],
        });
      }

      final listSnapshots = await _listStore.find(txn);
      var hasSavedList = false;
      for (final listSnapshot in listSnapshots) {
        final key = listSnapshot.key;
        if (!_isScopedViewListKey(key, 'saved')) {
          continue;
        }
        hasSavedList = hasSavedList || key == ListKey.saved.value;
        if (_shouldContainViewList(key, 'saved', nextRecord, source)) {
          await addToSortedList(key);
        } else {
          await removeFromList(key);
        }
      }

      if (isSaved && !hasSavedList) {
        await _listStore.record(ListKey.saved.value).put(txn, <String, dynamic>{
          'ids': [entryId],
          'hasMore': false,
          'nextCursor': null,
        });
      }
    });
  }

  Future<void> setEntryReadState(int entryId, bool isRead) async {
    await _database.transaction((txn) async {
      final payload = await _entryStore.record(entryId).get(txn);
      if (payload == null) {
        return;
      }

      final current = EntryRecord.fromJson(payload);
      final nextRecord = current.copyWith(
        isRead: isRead,
        readingProgress: isRead ? 1 : 0,
      );
      await _entryStore.record(entryId).put(txn, nextRecord.toJson());

      final sourcePayload = await _sourceStore
          .record(current.sourceId)
          .get(txn);
      final source = sourcePayload == null
          ? null
          : FeedSource.fromJson(sourcePayload);

      Future<void> removeFromList(String key) async {
        final listPayload = await _listStore.record(key).get(txn);
        if (listPayload == null) {
          return;
        }
        final ids =
            ((listPayload['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => id != entryId)
                .toList(growable: false);
        await _listStore.record(key).put(txn, <String, dynamic>{
          'ids': ids,
          'hasMore': listPayload['hasMore'] as bool? ?? false,
          'nextCursor': listPayload['nextCursor'],
        });
      }

      Future<void> addToSortedList(String key) async {
        final listPayload = await _listStore.record(key).get(txn);
        if (listPayload == null) {
          return;
        }
        final ids =
            ((listPayload['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => id != entryId)
                .toList(growable: true)
              ..add(entryId);
        final entries = <EntryRecord>[];
        for (final id in ids) {
          final entryPayload = await _entryStore.record(id).get(txn);
          if (entryPayload != null) {
            entries.add(EntryRecord.fromJson(entryPayload));
          }
        }
        entries.sort(_compareEntriesNewestFirst);
        await _listStore.record(key).put(txn, <String, dynamic>{
          'ids': entries.map((entry) => entry.id).toList(growable: false),
          'hasMore': listPayload['hasMore'] as bool? ?? false,
          'nextCursor': listPayload['nextCursor'],
        });
      }

      final listSnapshots = await _listStore.find(txn);
      for (final listSnapshot in listSnapshots) {
        final key = listSnapshot.key;
        if (!_isUnreadListKey(key)) {
          continue;
        }
        if (isRead) {
          await removeFromList(key);
        } else if (_shouldContainUnreadList(key, nextRecord, source)) {
          await addToSortedList(key);
        }
      }
    });
  }

  Future<void> setEntryNoise(int entryId, bool isNoise) async {
    await _database.transaction((txn) async {
      final payload = await _entryStore.record(entryId).get(txn);
      if (payload == null) {
        return;
      }

      final current = EntryRecord.fromJson(payload);
      final nextRecord = isNoise
          ? current.copyWith(
              isNoise: true,
              filterReason: current.filterReason ?? '手动移入噪音箱',
            )
          : current.copyWith(isNoise: false, clearFilterReason: true);
      await _entryStore.record(entryId).put(txn, nextRecord.toJson());

      final sourcePayload = await _sourceStore
          .record(current.sourceId)
          .get(txn);
      final source = sourcePayload == null
          ? null
          : FeedSource.fromJson(sourcePayload);

      if (current.isNoise != isNoise && !current.isRead && source != null) {
        final nextUnreadCount = isNoise
            ? (source.unreadCount - 1).clamp(0, 1 << 31).toInt()
            : source.unreadCount + 1;
        await _sourceStore
            .record(source.id)
            .put(txn, source.copyWith(unreadCount: nextUnreadCount).toJson());
      }

      Future<void> removeFromList(String key) async {
        final listPayload = await _listStore.record(key).get(txn);
        if (listPayload == null) {
          return;
        }
        final ids =
            ((listPayload['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => id != entryId)
                .toList(growable: false);
        await _listStore.record(key).put(txn, <String, dynamic>{
          'ids': ids,
          'hasMore': listPayload['hasMore'] as bool? ?? false,
          'nextCursor': listPayload['nextCursor'],
        });
      }

      Future<void> addToSortedList(String key) async {
        final listPayload = await _listStore.record(key).get(txn);
        if (listPayload == null) {
          return;
        }
        final ids =
            ((listPayload['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => id != entryId)
                .toList(growable: true)
              ..add(entryId);
        final entries = <EntryRecord>[];
        for (final id in ids) {
          final entryPayload = await _entryStore.record(id).get(txn);
          if (entryPayload != null) {
            entries.add(EntryRecord.fromJson(entryPayload));
          }
        }
        entries.sort(_compareEntriesNewestFirst);
        await _listStore.record(key).put(txn, <String, dynamic>{
          'ids': entries.map((entry) => entry.id).toList(growable: false),
          'hasMore': listPayload['hasMore'] as bool? ?? false,
          'nextCursor': listPayload['nextCursor'],
        });
      }

      final listSnapshots = await _listStore.find(txn);
      for (final listSnapshot in listSnapshots) {
        final key = listSnapshot.key;
        final view = _isScopedViewListKey(key, 'feed')
            ? 'feed'
            : _isScopedViewListKey(key, 'noise')
            ? 'noise'
            : null;
        if (view == null) {
          continue;
        }

        if (_shouldContainViewList(key, view, nextRecord, source)) {
          await addToSortedList(key);
        } else {
          await removeFromList(key);
        }
      }
    });
  }

  Future<void> setEntryAiProcessingPending(int entryId) async {
    await _database.transaction((txn) async {
      final payload = await _entryStore.record(entryId).get(txn);
      if (payload == null) {
        return;
      }

      final record = EntryRecord.fromJson(payload).copyWith(
        filterStatus: 'PENDING',
        summaryStatus: 'PENDING',
        translationStatus: 'PENDING',
      );
      await _entryStore.record(entryId).put(txn, record.toJson());
    });
  }

  Future<void> setReadingProgress(int entryId, double progress) async {
    await _database.transaction((txn) async {
      final payload = await _entryStore.record(entryId).get(txn);
      if (payload == null) {
        return;
      }

      final record = EntryRecord.fromJson(
        payload,
      ).copyWith(readingProgress: progress);
      await _entryStore.record(entryId).put(txn, record.toJson());
    });
  }

  Future<void> savePendingEntryAction(PendingEntryAction action) async {
    await _pendingEntryActionStore
        .record(action.key)
        .put(_database, action.toJson());
  }

  Future<List<PendingEntryAction>> loadPendingEntryActions() async {
    final snapshots = await _pendingEntryActionStore.find(_database);
    final actions =
        snapshots
            .map((snapshot) => PendingEntryAction.fromJson(snapshot.value))
            .where((action) => action.entryId > 0)
            .toList(growable: false)
          ..sort((left, right) {
            final updatedCompare = left.updatedAtMicros.compareTo(
              right.updatedAtMicros,
            );
            if (updatedCompare != 0) {
              return updatedCompare;
            }
            return left.key.compareTo(right.key);
          });
    return actions;
  }

  Future<void> deletePendingEntryActions(
    Iterable<PendingEntryAction> actions,
  ) async {
    await _database.transaction((txn) async {
      for (final action in actions) {
        final record = _pendingEntryActionStore.record(action.key);
        final payload = await record.get(txn);
        if (payload == null) {
          continue;
        }
        final currentAction = PendingEntryAction.fromJson(payload);
        if (_samePendingActionVersion(currentAction, action)) {
          await record.delete(txn);
        }
      }
    });
  }

  Future<void> deletePendingEntryActionsFor(
    PendingEntryActionType type,
    Iterable<int> entryIds,
  ) async {
    final normalizedEntryIds = entryIds.where((id) => id > 0).toSet();
    if (normalizedEntryIds.isEmpty) {
      return;
    }

    await _database.transaction((txn) async {
      for (final entryId in normalizedEntryIds) {
        await _pendingEntryActionStore
            .record(PendingEntryAction.keyFor(type, entryId))
            .delete(txn);
      }
    });
  }

  bool _samePendingActionVersion(
    PendingEntryAction left,
    PendingEntryAction right,
  ) {
    return left.type == right.type &&
        left.entryId == right.entryId &&
        left.updatedAtMicros == right.updatedAtMicros &&
        left.boolValue == right.boolValue &&
        left.doubleValue == right.doubleValue;
  }

  Future<EntryRecord?> loadEntry(int id) async {
    final payload = await _entryStore.record(id).get(_database);
    if (payload == null) {
      return null;
    }

    return EntryRecord.fromJson(payload);
  }

  Future<void> applyListSnapshot(
    ListKey key,
    List<EntryListItem> items, {
    bool append = false,
    bool hasMore = false,
    EntryPageCursor? nextCursor,
  }) async {
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

      final previousIds = append
          ? (((await _listStore.record(key.value).get(txn))?['ids']
                        as List<dynamic>?) ??
                    const <dynamic>[])
                .whereType<int>()
                .toList(growable: true)
          : <int>[];
      final seenIds = previousIds.toSet();
      final nextIds = <int>[
        ...previousIds,
        for (final item in items)
          if (seenIds.add(item.id)) item.id,
      ];

      await _listStore.record(key.value).put(txn, <String, dynamic>{
        'ids': nextIds,
        'hasMore': hasMore,
        'nextCursor': nextCursor?.toJson(),
      });
    });
  }

  Future<void> clearListPagination(ListKey key) async {
    await _database.transaction((txn) async {
      final payload = await _listStore.record(key.value).get(txn);
      if (payload == null) {
        return;
      }
      await _listStore.record(key.value).put(txn, <String, dynamic>{
        'ids': ((payload['ids'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<int>()
            .toList(growable: false),
        'hasMore': false,
        'nextCursor': null,
      });
    });
  }

  Future<void> deleteSources(List<int> sourceIds) async {
    if (sourceIds.isEmpty) {
      return;
    }

    final sourceIdSet = sourceIds.toSet();
    await _database.transaction((txn) async {
      final sourceSnapshots = await _sourceStore.find(txn);
      final deletedFolders = <String>{};
      final remainingFolders = <String>{};
      for (final sourceSnapshot in sourceSnapshots) {
        final source = FeedSource.fromJson(sourceSnapshot.value);
        final folder = _normalizedFolder(source);
        if (sourceIdSet.contains(source.id)) {
          deletedFolders.add(folder);
        } else {
          remainingFolders.add(folder);
        }
      }
      final orphanedFolders = deletedFolders.difference(remainingFolders);

      for (final sourceId in sourceIds) {
        await _sourceStore.record(sourceId).delete(txn);
      }

      final entrySnapshots = await _entryStore.find(txn);
      final deletedEntryIds = <int>[];
      for (final snapshot in entrySnapshots) {
        final entry = EntryRecord.fromJson(snapshot.value);
        if (sourceIdSet.contains(entry.sourceId)) {
          deletedEntryIds.add(snapshot.key);
          await _entryStore.record(snapshot.key).delete(txn);
        }
      }
      await _deletePendingEntryActionsForEntryIds(txn, deletedEntryIds.toSet());

      final listSnapshots = await _listStore.find(txn);
      for (final listSnapshot in listSnapshots) {
        final shouldDeleteSourceList = ListKey.isSourceScopedValue(
          listSnapshot.key,
          sourceIdSet,
        );
        final shouldDeleteFolderList = ListKey.isFolderScopedValue(
          listSnapshot.key,
          orphanedFolders,
        );
        if (shouldDeleteSourceList || shouldDeleteFolderList) {
          await _listStore.record(listSnapshot.key).delete(txn);
          continue;
        }

        final ids =
            ((listSnapshot.value['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => !deletedEntryIds.contains(id))
                .toList(growable: false);
        await _listStore.record(listSnapshot.key).put(txn, <String, dynamic>{
          ...listSnapshot.value,
          'ids': ids,
        });
      }
    });
  }

  Future<void> deleteEntries(List<int> entryIds) async {
    final entryIdSet = entryIds.where((id) => id > 0).toSet();
    if (entryIdSet.isEmpty) {
      return;
    }

    await _database.transaction((txn) async {
      final deletedEntryIds = <int>{};
      final unreadDeltasBySource = <int, int>{};
      for (final entryId in entryIdSet) {
        final payload = await _entryStore.record(entryId).get(txn);
        if (payload == null) {
          continue;
        }
        final entry = EntryRecord.fromJson(payload);
        deletedEntryIds.add(entryId);
        if (!entry.isRead) {
          unreadDeltasBySource.update(
            entry.sourceId,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
        await _entryStore.record(entryId).delete(txn);
      }
      if (deletedEntryIds.isEmpty) {
        return;
      }

      await _deletePendingEntryActionsForEntryIds(txn, deletedEntryIds);

      final listSnapshots = await _listStore.find(txn);
      for (final listSnapshot in listSnapshots) {
        final ids =
            ((listSnapshot.value['ids'] as List<dynamic>?) ?? const <dynamic>[])
                .whereType<int>()
                .where((id) => !deletedEntryIds.contains(id))
                .toList(growable: false);
        await _listStore.record(listSnapshot.key).put(txn, <String, dynamic>{
          ...listSnapshot.value,
          'ids': ids,
        });
      }

      for (final MapEntry(key: sourceId, value: unreadDelta)
          in unreadDeltasBySource.entries) {
        final payload = await _sourceStore.record(sourceId).get(txn);
        if (payload == null) {
          continue;
        }
        final source = FeedSource.fromJson(payload);
        final unreadCount = source.unreadCount - unreadDelta;
        await _sourceStore
            .record(sourceId)
            .put(
              txn,
              source
                  .copyWith(unreadCount: unreadCount < 0 ? 0 : unreadCount)
                  .toJson(),
            );
      }
    });
  }

  Future<void> _deletePendingEntryActionsForEntryIds(
    DatabaseClient client,
    Set<int> entryIds,
  ) async {
    if (entryIds.isEmpty) {
      return;
    }

    final snapshots = await _pendingEntryActionStore.find(client);
    for (final snapshot in snapshots) {
      final action = PendingEntryAction.fromJson(snapshot.value);
      if (entryIds.contains(action.entryId)) {
        await _pendingEntryActionStore.record(snapshot.key).delete(client);
      }
    }
  }

  bool _isScopedViewListKey(String key, String view) {
    return key == view ||
        key.startsWith('folder:view:$view:') ||
        key.startsWith('source:view:$view:') ||
        key.startsWith('unread:view:$view') ||
        key.startsWith('unread:folder:$view:') ||
        key.startsWith('unread:source-view:$view:') ||
        key.startsWith('search:view:$view:') ||
        key.startsWith('search:folder:$view:') ||
        key.startsWith('search:source-view:$view:') ||
        key.startsWith('search:unread-view:$view:') ||
        key.startsWith('search:unread-folder:$view:') ||
        key.startsWith('search:unread-source-view:$view:');
  }

  Future<void> _reconcileEntryInCachedLists(
    DatabaseClient client,
    EntryRecord entry,
    FeedSource? source,
  ) async {
    Future<void> removeFromList(String key) async {
      final listPayload = await _listStore.record(key).get(client);
      if (listPayload == null) {
        return;
      }
      final ids = ((listPayload['ids'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<int>()
          .where((id) => id != entry.id)
          .toList(growable: false);
      await _listStore.record(key).put(client, <String, dynamic>{
        'ids': ids,
        'hasMore': listPayload['hasMore'] as bool? ?? false,
        'nextCursor': listPayload['nextCursor'],
      });
    }

    Future<void> addToSortedList(String key) async {
      final listPayload = await _listStore.record(key).get(client);
      if (listPayload == null) {
        return;
      }
      final ids =
          ((listPayload['ids'] as List<dynamic>?) ?? const <dynamic>[])
              .whereType<int>()
              .where((id) => id != entry.id)
              .toList(growable: true)
            ..add(entry.id);
      final entries = <EntryRecord>[];
      for (final id in ids) {
        final entryPayload = await _entryStore.record(id).get(client);
        if (entryPayload != null) {
          entries.add(EntryRecord.fromJson(entryPayload));
        }
      }
      entries.sort(_compareEntriesNewestFirst);
      await _listStore.record(key).put(client, <String, dynamic>{
        'ids': entries.map((entry) => entry.id).toList(growable: false),
        'hasMore': listPayload['hasMore'] as bool? ?? false,
        'nextCursor': listPayload['nextCursor'],
      });
    }

    final listSnapshots = await _listStore.find(client);
    for (final listSnapshot in listSnapshots) {
      final key = listSnapshot.key;
      final view = _viewForScopedListKey(key);
      final shouldContain = view == null
          ? _shouldContainSourceList(key, entry)
          : _shouldContainViewList(key, view, entry, source);
      if (shouldContain == null) {
        continue;
      }

      if (shouldContain) {
        await addToSortedList(key);
      } else {
        await removeFromList(key);
      }
    }
  }

  String? _viewForScopedListKey(String key) {
    for (final view in const ['feed', 'noise', 'saved', 'all']) {
      if (_isScopedViewListKey(key, view)) {
        return view;
      }
    }
    return null;
  }

  bool? _shouldContainSourceList(String key, EntryRecord entry) {
    if (key.startsWith('source:') && !key.startsWith('source:view:')) {
      final sourceId = int.tryParse(key.substring('source:'.length));
      return sourceId == entry.sourceId;
    }

    if (key.startsWith('search:source:')) {
      final parts = key.substring('search:source:'.length).split(':');
      if (parts.length < 2) {
        return false;
      }
      final sourceId = int.tryParse(parts[0]);
      final query = Uri.decodeComponent(parts[1]);
      return sourceId == entry.sourceId && _matchesSearch(entry, query);
    }

    return null;
  }

  bool _shouldContainViewList(
    String key,
    String view,
    EntryRecord entry,
    FeedSource? source,
  ) {
    if (key == view) {
      return _matchesView(entry, view);
    }

    if (key == 'unread:view:$view') {
      return !entry.isRead && _matchesView(entry, view);
    }

    if (key.startsWith('unread:folder:$view:')) {
      final folder = Uri.decodeComponent(
        key.substring('unread:folder:$view:'.length),
      );
      return !entry.isRead &&
          _matchesView(entry, view) &&
          _normalizedFolder(source) == folder;
    }

    if (key.startsWith('unread:source-view:$view:')) {
      final sourceId = int.tryParse(
        key.substring('unread:source-view:$view:'.length),
      );
      return !entry.isRead &&
          _matchesView(entry, view) &&
          sourceId == entry.sourceId;
    }

    if (key.startsWith('search:unread-view:$view:')) {
      final query = Uri.decodeComponent(
        key.substring('search:unread-view:$view:'.length),
      );
      return !entry.isRead &&
          _matchesView(entry, view) &&
          _matchesSearch(entry, query);
    }

    if (key.startsWith('search:unread-folder:$view:')) {
      final parts = key
          .substring('search:unread-folder:$view:'.length)
          .split(':');
      if (parts.length < 2) {
        return false;
      }
      final folder = Uri.decodeComponent(parts[0]);
      final query = Uri.decodeComponent(parts[1]);
      return !entry.isRead &&
          _matchesView(entry, view) &&
          _normalizedFolder(source) == folder &&
          _matchesSearch(entry, query);
    }

    if (key.startsWith('search:unread-source-view:$view:')) {
      final parts = key
          .substring('search:unread-source-view:$view:'.length)
          .split(':');
      if (parts.length < 2) {
        return false;
      }
      final sourceId = int.tryParse(parts[0]);
      final query = Uri.decodeComponent(parts[1]);
      return !entry.isRead &&
          _matchesView(entry, view) &&
          sourceId == entry.sourceId &&
          _matchesSearch(entry, query);
    }

    if (key.startsWith('folder:view:$view:')) {
      final folder = Uri.decodeComponent(
        key.substring('folder:view:$view:'.length),
      );
      return _matchesView(entry, view) && _normalizedFolder(source) == folder;
    }

    if (key.startsWith('source:view:$view:')) {
      final sourceId = int.tryParse(key.substring('source:view:$view:'.length));
      return _matchesView(entry, view) && sourceId == entry.sourceId;
    }

    if (key.startsWith('search:view:$view:')) {
      final query = Uri.decodeComponent(
        key.substring('search:view:$view:'.length),
      );
      return _matchesView(entry, view) && _matchesSearch(entry, query);
    }

    if (key.startsWith('search:folder:$view:')) {
      final parts = key.substring('search:folder:$view:'.length).split(':');
      if (parts.length < 2) {
        return false;
      }
      final folder = Uri.decodeComponent(parts[0]);
      final query = Uri.decodeComponent(parts[1]);
      return _matchesView(entry, view) &&
          _normalizedFolder(source) == folder &&
          _matchesSearch(entry, query);
    }

    if (key.startsWith('search:source-view:$view:')) {
      final parts = key
          .substring('search:source-view:$view:'.length)
          .split(':');
      if (parts.length < 2) {
        return false;
      }
      final sourceId = int.tryParse(parts[0]);
      final query = Uri.decodeComponent(parts[1]);
      return _matchesView(entry, view) &&
          sourceId == entry.sourceId &&
          _matchesSearch(entry, query);
    }

    return false;
  }

  bool _isUnreadListKey(String key) {
    return key.startsWith('unread:') || key.startsWith('search:unread-');
  }

  bool _shouldContainUnreadList(
    String key,
    EntryRecord entry,
    FeedSource? source,
  ) {
    if (entry.isRead) {
      return false;
    }

    if (key.startsWith('unread:view:')) {
      final view = key.substring('unread:view:'.length);
      return _matchesView(entry, view);
    }

    if (key.startsWith('unread:source-view:')) {
      final parts = key.substring('unread:source-view:'.length).split(':');
      if (parts.length < 2) {
        return false;
      }
      final sourceId = int.tryParse(parts[1]);
      return sourceId == entry.sourceId && _matchesView(entry, parts[0]);
    }

    if (key.startsWith('unread:folder:')) {
      final parts = key.substring('unread:folder:'.length).split(':');
      if (parts.length < 2) {
        return false;
      }
      final folder = Uri.decodeComponent(parts[1]);
      return _normalizedFolder(source) == folder &&
          _matchesView(entry, parts[0]);
    }

    if (key.startsWith('search:unread-view:')) {
      final parts = key.substring('search:unread-view:'.length).split(':');
      if (parts.length < 2) {
        return false;
      }
      final query = Uri.decodeComponent(parts[1]);
      return _matchesView(entry, parts[0]) && _matchesSearch(entry, query);
    }

    if (key.startsWith('search:unread-source-view:')) {
      final parts = key
          .substring('search:unread-source-view:'.length)
          .split(':');
      if (parts.length < 3) {
        return false;
      }
      final sourceId = int.tryParse(parts[1]);
      final query = Uri.decodeComponent(parts[2]);
      return sourceId == entry.sourceId &&
          _matchesView(entry, parts[0]) &&
          _matchesSearch(entry, query);
    }

    if (key.startsWith('search:unread-folder:')) {
      final parts = key.substring('search:unread-folder:'.length).split(':');
      if (parts.length < 3) {
        return false;
      }
      final folder = Uri.decodeComponent(parts[1]);
      final query = Uri.decodeComponent(parts[2]);
      return _normalizedFolder(source) == folder &&
          _matchesView(entry, parts[0]) &&
          _matchesSearch(entry, query);
    }

    return false;
  }

  bool _matchesView(EntryRecord entry, String view) {
    return switch (view) {
      'feed' => !entry.isNoise,
      'noise' => entry.isNoise,
      'saved' => entry.isSaved,
      'all' => true,
      _ => false,
    };
  }

  bool _matchesSearch(EntryRecord entry, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final tokens = searchQueryTokens(normalizedQuery);
    final searchableText = [
      entry.title,
      entry.sourceName,
      entry.author,
      entry.link,
      entry.summary,
      entry.filterReason,
      entry.contentHtml,
      ...entry.translationSegments.expand(
        (segment) => [segment.source, segment.translation],
      ),
    ].whereType<String>().join('\n').toLowerCase();
    return tokens.every(searchableText.contains);
  }

  String _normalizedFolder(FeedSource? source) {
    final folder = source?.folder.trim();
    return folder == null || folder.isEmpty ? defaultSourceFolder : folder;
  }

  int _compareEntriesNewestFirst(EntryRecord left, EntryRecord right) {
    final publishedCompare = right.publishedAt.compareTo(left.publishedAt);
    if (publishedCompare != 0) {
      return publishedCompare;
    }
    return right.id.compareTo(left.id);
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
                left.folder.toLowerCase() == right.folder.toLowerCase()
                ? left.name.toLowerCase().compareTo(right.name.toLowerCase())
                : left.folder.toLowerCase().compareTo(
                    right.folder.toLowerCase(),
                  ),
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
    final hasMore = <String, bool>{
      for (final snapshot in listSnapshots)
        snapshot.key: snapshot.value['hasMore'] as bool? ?? false,
    };
    final cursors = <String, EntryPageCursor>{
      for (final snapshot in listSnapshots)
        if (snapshot.value['nextCursor'] is Map<String, dynamic>)
          snapshot.key: EntryPageCursor.fromJson(
            snapshot.value['nextCursor'] as Map<String, dynamic>,
          ),
    };

    return AppSnapshot(
      sources: sources,
      settings: settings,
      entries: entries,
      listSnapshots: lists,
      listHasMore: hasMore,
      listCursors: cursors,
    );
  }
}
