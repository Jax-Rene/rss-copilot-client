import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/article_queries.dart';
import '../core/formatters.dart';
import '../core/reading_metrics.dart';
import '../data/api/api_client.dart';
import '../data/api/api_exception.dart';
import '../models/app_section.dart';
import '../models/entry_record.dart';
import '../models/feed_source.dart';
import '../models/reader_preferences.dart';
import '../models/session_data.dart';
import '../models/settings_bundle.dart';
import '../models/snapshot.dart';
import '../repositories/rss_repository.dart';

typedef EntrySourceFilterOption = ({
  int entryCount,
  String? sourceIconUrl,
  int sourceId,
  String sourceName,
  int unreadCount,
});

typedef EntryFolderFilterOption = ({
  int entryCount,
  String folder,
  int unreadCount,
});

enum SourceSaveAction { add, update }

class SourceRefreshAfterSaveException implements Exception {
  const SourceRefreshAfterSaveException({
    required this.action,
    required this.source,
    required this.cause,
  });

  final SourceSaveAction action;
  final FeedSource source;
  final Object cause;
}

class OpmlImportSyncAfterSuccessException implements Exception {
  const OpmlImportSyncAfterSuccessException({
    required this.result,
    required this.cause,
  });

  final OpmlImportResult result;
  final Object cause;
}

class AppState {
  const AppState({
    required this.initialized,
    required this.busy,
    required this.isOnline,
    required this.pendingSyncCount,
    required this.pendingSyncDescription,
    required this.session,
    required this.snapshot,
    required this.section,
    required this.settingsSection,
    required this.selectedSourceId,
    required this.entrySourceFilterId,
    required this.entryFolderFilter,
    required this.entrySortOrder,
    required this.selectedEntryId,
    required this.unreadOnly,
    required this.inProgressOnly,
    required this.searchQuery,
    required this.showTranslations,
    required this.readerPreferences,
    required this.errorMessage,
  });

  const AppState.initial()
    : initialized = false,
      busy = false,
      isOnline = false,
      pendingSyncCount = 0,
      pendingSyncDescription = '',
      session = null,
      snapshot = const AppSnapshot.empty(),
      section = AppSection.feed,
      settingsSection = SettingsSection.ai,
      selectedSourceId = null,
      entrySourceFilterId = null,
      entryFolderFilter = null,
      entrySortOrder = EntrySortOrder.newestFirst,
      selectedEntryId = null,
      unreadOnly = false,
      inProgressOnly = false,
      searchQuery = '',
      showTranslations = true,
      readerPreferences = ReaderPreferences.defaultPreferences,
      errorMessage = null;

  final bool initialized;
  final bool busy;
  final bool isOnline;
  final int pendingSyncCount;
  final String pendingSyncDescription;
  final SessionData? session;
  final AppSnapshot snapshot;
  final AppSection section;
  final SettingsSection settingsSection;
  final int? selectedSourceId;
  final int? entrySourceFilterId;
  final String? entryFolderFilter;
  final EntrySortOrder entrySortOrder;
  final int? selectedEntryId;
  final bool unreadOnly;
  final bool inProgressOnly;
  final String searchQuery;
  final bool showTranslations;
  final ReaderPreferences readerPreferences;
  final String? errorMessage;

  bool get isAuthenticated => session != null;

  AppThemeMode get effectiveThemeMode =>
      session?.themeOverride ?? snapshot.settings.appearance.themeMode;

  AppState copyWith({
    bool? initialized,
    bool? busy,
    bool? isOnline,
    int? pendingSyncCount,
    String? pendingSyncDescription,
    SessionData? session,
    bool clearSession = false,
    AppSnapshot? snapshot,
    AppSection? section,
    SettingsSection? settingsSection,
    int? selectedSourceId,
    bool clearSelectedSource = false,
    int? entrySourceFilterId,
    bool clearEntrySourceFilter = false,
    String? entryFolderFilter,
    bool clearEntryFolderFilter = false,
    EntrySortOrder? entrySortOrder,
    int? selectedEntryId,
    bool clearSelectedEntry = false,
    bool? unreadOnly,
    bool? inProgressOnly,
    String? searchQuery,
    bool? showTranslations,
    ReaderPreferences? readerPreferences,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return AppState(
      initialized: initialized ?? this.initialized,
      busy: busy ?? this.busy,
      isOnline: isOnline ?? this.isOnline,
      pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
      pendingSyncDescription:
          pendingSyncDescription ?? this.pendingSyncDescription,
      session: clearSession ? null : session ?? this.session,
      snapshot: snapshot ?? this.snapshot,
      section: section ?? this.section,
      settingsSection: settingsSection ?? this.settingsSection,
      selectedSourceId: clearSelectedSource
          ? null
          : selectedSourceId ?? this.selectedSourceId,
      entrySourceFilterId: clearEntrySourceFilter
          ? null
          : entrySourceFilterId ?? this.entrySourceFilterId,
      entryFolderFilter: clearEntryFolderFilter
          ? null
          : entryFolderFilter ?? this.entryFolderFilter,
      entrySortOrder: entrySortOrder ?? this.entrySortOrder,
      selectedEntryId: clearSelectedEntry
          ? null
          : selectedEntryId ?? this.selectedEntryId,
      unreadOnly: unreadOnly ?? this.unreadOnly,
      inProgressOnly: inProgressOnly ?? this.inProgressOnly,
      searchQuery: searchQuery ?? this.searchQuery,
      showTranslations: showTranslations ?? this.showTranslations,
      readerPreferences: readerPreferences ?? this.readerPreferences,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

class _EntrySourceFilterCounter {
  _EntrySourceFilterCounter(this.sourceId, this.sourceName);

  final int sourceId;
  final String sourceName;
  String? sourceIconUrl;
  int entryCount = 0;
  int unreadCount = 0;
}

class _EntryFolderFilterCounter {
  _EntryFolderFilterCounter(this.folder);

  final String folder;
  int entryCount = 0;
  int unreadCount = 0;
}

class AppController extends ChangeNotifier {
  AppController({required this.repository});

  static const double _readingCompleteProgress = 0.98;

  final RssRepository repository;

  AppState _state = const AppState.initial();
  AppState get state => _state;

  Timer? _syncTimer;
  Timer? _searchTimer;
  Future<void>? _syncInFlightFuture;
  bool _disposed = false;
  final Map<int, Timer> _readingProgressTimers = <int, Timer>{};
  final Map<int, double> _pendingReadingProgress = <int, double>{};
  final Map<int, Future<void>> _pendingReadingProgressPersists =
      <int, Future<void>>{};
  Future<void> _readerPreferencesSave = Future<void>.value();

  List<EntryRecord> get visibleEntries => _resolveEntries();

  List<EntryRecord> get _navigableEntries {
    final collapsedDateSections =
        _state.readerPreferences.collapsedEntryDateSections;
    if (collapsedDateSections.isEmpty) {
      return visibleEntries;
    }

    final collapsedDateSectionSet = collapsedDateSections.toSet();
    return visibleEntries
        .where(
          (entry) => !collapsedDateSectionSet.contains(
            AppFormatters.dayKey(entry.publishedAt),
          ),
        )
        .toList(growable: false);
  }

  List<EntryRecord> get queueFilterBaseEntries =>
      _resolveEntries(applyQueueFilters: false, applySort: false);

  List<EntryRecord> get sourceFilterBaseEntries =>
      _resolveEntries(applyScopeFilters: false, applySort: false);

  List<EntryFolderFilterOption> get entryFolderFilterOptions {
    final counters = <String, _EntryFolderFilterCounter>{};
    for (final entry in sourceFilterBaseEntries) {
      final folder = _folderNameForEntry(entry);
      final counter = counters.putIfAbsent(
        folder,
        () => _EntryFolderFilterCounter(folder),
      );
      counter.entryCount += 1;
      if (!entry.isRead) {
        counter.unreadCount += 1;
      }
    }

    final options = [
      for (final counter in counters.values)
        (
          folder: counter.folder,
          entryCount: counter.entryCount,
          unreadCount: counter.unreadCount,
        ),
    ];
    options.sort((left, right) {
      final unreadComparison = right.unreadCount.compareTo(left.unreadCount);
      if (unreadComparison != 0) {
        return unreadComparison;
      }
      final countComparison = right.entryCount.compareTo(left.entryCount);
      if (countComparison != 0) {
        return countComparison;
      }
      return left.folder.compareTo(right.folder);
    });
    return options;
  }

  List<EntrySourceFilterOption> get entrySourceFilterOptions {
    final counters = <int, _EntrySourceFilterCounter>{};
    for (final entry in sourceFilterBaseEntries) {
      final activeFolder = _state.entryFolderFilter;
      if (activeFolder != null && _folderNameForEntry(entry) != activeFolder) {
        continue;
      }
      final counter = counters.putIfAbsent(
        entry.sourceId,
        () => _EntrySourceFilterCounter(entry.sourceId, entry.sourceName),
      );
      counter.sourceIconUrl ??= _sourceIconUrlForEntry(entry);
      counter.entryCount += 1;
      if (!entry.isRead) {
        counter.unreadCount += 1;
      }
    }

    final options = [
      for (final counter in counters.values)
        (
          sourceId: counter.sourceId,
          sourceName: counter.sourceName,
          sourceIconUrl: counter.sourceIconUrl,
          entryCount: counter.entryCount,
          unreadCount: counter.unreadCount,
        ),
    ];
    options.sort((left, right) {
      final unreadComparison = right.unreadCount.compareTo(left.unreadCount);
      if (unreadComparison != 0) {
        return unreadComparison;
      }
      final countComparison = right.entryCount.compareTo(left.entryCount);
      if (countComparison != 0) {
        return countComparison;
      }
      return left.sourceName.compareTo(right.sourceName);
    });
    return options;
  }

  List<EntryRecord> _resolveEntries({
    bool applyScopeFilters = true,
    bool applyQueueFilters = true,
    bool applySort = true,
  }) {
    final entries = ArticleQueries.resolve(
      snapshot: _state.snapshot,
      section: _state.section,
      unreadOnly: applyQueueFilters && _state.unreadOnly,
      inProgressOnly: applyQueueFilters && _state.inProgressOnly,
      searchQuery: _state.searchQuery,
      selectedSourceId: _state.selectedSourceId,
      sourceFilterId: applyScopeFilters ? _state.entrySourceFilterId : null,
      folderFilter: applyScopeFilters ? _state.entryFolderFilter : null,
    );
    return applySort ? _sortEntries(entries) : entries;
  }

  String _folderNameForEntry(EntryRecord entry) {
    final folder = _state.snapshot.sourceById(entry.sourceId)?.folder.trim();
    return folder == null || folder.isEmpty ? defaultSourceFolder : folder;
  }

  String? _sourceIconUrlForEntry(EntryRecord entry) {
    final entryIconUrl = entry.sourceIconUrl?.trim();
    if (entryIconUrl != null && entryIconUrl.isNotEmpty) {
      return entryIconUrl;
    }
    final sourceIconUrl = _state.snapshot
        .sourceById(entry.sourceId)
        ?.iconUrl
        ?.trim();
    return sourceIconUrl == null || sourceIconUrl.isEmpty
        ? null
        : sourceIconUrl;
  }

  String _normalizeFolderName(String folder) {
    final folderName = folder.trim();
    return folderName.isEmpty ? defaultSourceFolder : folderName;
  }

  List<EntryRecord> _sortEntries(List<EntryRecord> entries) {
    final sorted = entries.toList(growable: false);
    sorted.sort((left, right) {
      final primaryComparison = switch (_state.entrySortOrder) {
        EntrySortOrder.newestFirst => right.publishedAt.compareTo(
          left.publishedAt,
        ),
        EntrySortOrder.oldestFirst => left.publishedAt.compareTo(
          right.publishedAt,
        ),
        EntrySortOrder.shortestFirst => ReadingMetrics.estimateReadingMinutes(
          left,
        ).compareTo(ReadingMetrics.estimateReadingMinutes(right)),
        EntrySortOrder.longestFirst => ReadingMetrics.estimateReadingMinutes(
          right,
        ).compareTo(ReadingMetrics.estimateReadingMinutes(left)),
      };
      if (primaryComparison != 0) {
        return primaryComparison;
      }

      final dateComparison = right.publishedAt.compareTo(left.publishedAt);
      if (dateComparison != 0) {
        return dateComparison;
      }

      return switch (_state.entrySortOrder) {
        EntrySortOrder.newestFirst => right.id.compareTo(left.id),
        EntrySortOrder.oldestFirst ||
        EntrySortOrder.shortestFirst ||
        EntrySortOrder.longestFirst => left.id.compareTo(right.id),
      };
    });
    return sorted;
  }

  EntryRecord? get selectedEntry {
    final selectedEntryId = _state.selectedEntryId;
    if (selectedEntryId == null) {
      return null;
    }

    return _state.snapshot.entries[selectedEntryId];
  }

  FeedSource? get selectedSource {
    final selectedSourceId = _state.selectedSourceId;
    if (selectedSourceId == null) {
      return null;
    }

    return _state.snapshot.sourceById(selectedSourceId);
  }

  bool get canLoadMoreEntries {
    final key = _currentListKey();
    return key != null && _state.snapshot.hasMore(key);
  }

  int get visibleUnreadCount {
    return _navigableEntries.where((entry) => !entry.isRead).length;
  }

  int get queueFilterUnreadCount {
    return queueFilterBaseEntries.where((entry) => !entry.isRead).length;
  }

  int get queueFilterInProgressCount {
    return queueFilterBaseEntries.where((entry) => entry.isInProgress).length;
  }

  int unreadCountForSection(AppSection section) {
    return ArticleQueries.resolve(
      snapshot: _state.snapshot,
      section: section,
      unreadOnly: true,
      selectedSourceId: section == AppSection.sourceEntries
          ? _state.selectedSourceId
          : null,
    ).length;
  }

  List<int> get visibleUnreadEntryIds {
    return _navigableEntries
        .where((entry) => !entry.isRead)
        .map((entry) => entry.id)
        .toList(growable: false);
  }

  List<int> get visibleUnreadEntryIdsThroughSelection {
    final entries = _navigableEntries;
    final selectedEntryId = _state.selectedEntryId;
    if (entries.isEmpty || selectedEntryId == null) {
      return const <int>[];
    }

    final selectedIndex = entries.indexWhere(
      (entry) => entry.id == selectedEntryId,
    );
    if (selectedIndex == -1) {
      return const <int>[];
    }

    return entries
        .take(selectedIndex + 1)
        .where((entry) => !entry.isRead)
        .map((entry) => entry.id)
        .toList(growable: false);
  }

  bool get hasNextQueueEntry {
    return _nextQueueEntry(_navigableEntries, _state.selectedEntryId) != null;
  }

  String get readingQueueStatusText {
    final entries = _navigableEntries;
    if (entries.isEmpty) {
      return '0/0';
    }

    final selectedIndex = entries.indexWhere(
      (entry) => entry.id == _state.selectedEntryId,
    );
    final position = selectedIndex == -1 ? 0 : selectedIndex + 1;
    return '$position/${entries.length} · $visibleUnreadCount 未读';
  }

  Future<void> initialize() async {
    if (_state.initialized) {
      return;
    }

    final session = await repository.loadSession();
    final snapshot = await repository.loadSnapshot();
    final readerPreferences = await repository.loadReaderPreferences();
    final pendingSyncStatus = await repository.pendingEntryActionStatus();
    final restoredSection = _restorableSection(readerPreferences);
    _state = _state.copyWith(
      initialized: true,
      session: session,
      snapshot: snapshot,
      readerPreferences: readerPreferences,
      section: restoredSection,
      selectedSourceId: restoredSection == AppSection.sourceEntries
          ? readerPreferences.lastSelectedSourceId
          : null,
      clearSelectedSource: restoredSection != AppSection.sourceEntries,
      selectedEntryId: readerPreferences.lastSelectedEntryId,
      clearSelectedEntry: readerPreferences.lastSelectedEntryId == null,
      entrySourceFilterId: readerPreferences.lastEntrySourceFilterId,
      clearEntrySourceFilter: readerPreferences.lastEntrySourceFilterId == null,
      entryFolderFilter: readerPreferences.lastEntryFolderFilter,
      clearEntryFolderFilter: readerPreferences.lastEntryFolderFilter == null,
      entrySortOrder: readerPreferences.entrySortOrder,
      unreadOnly: readerPreferences.entryQueueFilter == EntryQueueFilter.unread,
      inProgressOnly:
          readerPreferences.entryQueueFilter == EntryQueueFilter.inProgress,
      showTranslations: readerPreferences.showTranslations,
      pendingSyncCount: pendingSyncStatus.count,
      pendingSyncDescription: pendingSyncStatus.description,
      isOnline: session != null,
    );
    _ensureSelection();
    _persistReadingContext();
    notifyListeners();

    if (session != null) {
      _startSyncTimer();
      unawaited(_restoreRemoteState());
    }
  }

  Future<void> login({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    _setBusy(true);
    try {
      await repository.login(
        baseUrl: baseUrl,
        email: email,
        password: password,
      );
      await _reloadFromStore(
        section: AppSection.feed,
        isOnline: true,
        preserveSelection: false,
      );
      _startSyncTimer();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    _setBusy(true);
    try {
      await repository.logout();
      _state = const AppState.initial().copyWith(initialized: true);
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  void selectSection(AppSection section) {
    final previousSection = _state.section;
    final nextSectionIsReading = _isRestorableReadingSection(section);
    if (_isRestorableReadingSection(previousSection) && !nextSectionIsReading) {
      _persistReadingContext();
    }
    final clearEntryScopeFilters =
        _isRestorableReadingSection(previousSection) &&
        nextSectionIsReading &&
        section != previousSection;
    _state = _state.copyWith(
      section: section,
      clearSelectedSource:
          section != AppSection.sourceEntries && section != AppSection.sources,
      clearSelectedEntry:
          section == AppSection.sources ||
          section == AppSection.settings ||
          section == AppSection.account,
      clearEntrySourceFilter: clearEntryScopeFilters,
      clearEntryFolderFilter: clearEntryScopeFilters,
    );
    if (section == AppSection.sources) {
      _state = _state.copyWith(clearSelectedSource: true);
    }
    _ensureSelection();
    _scheduleRemoteSearch();
    if (nextSectionIsReading) {
      _persistReadingContext();
    }
    notifyListeners();
  }

  Future<void> openSource(int sourceId) async {
    _state = _state.copyWith(
      section: AppSection.sourceEntries,
      selectedSourceId: sourceId,
      clearSelectedEntry: true,
      clearEntrySourceFilter: true,
      clearEntryFolderFilter: true,
    );
    _persistReadingContext();
    notifyListeners();

    if (_state.isOnline) {
      try {
        await repository.loadSourceEntries(sourceId);
        await _reloadFromStore(
          section: AppSection.sourceEntries,
          selectedSourceId: sourceId,
          preserveSelection: false,
          isOnline: true,
        );
        _scheduleRemoteSearch();
      } on ApiException catch (error) {
        if (error.isNotFound) {
          await _handleMissingSource();
          return;
        }
        await _handleError(error);
      } on NetworkException catch (error) {
        await _handleError(error);
      } on TimeoutException catch (error) {
        await _handleError(error);
      }
    } else {
      _ensureSelection();
      _scheduleRemoteSearch();
      _persistReadingContext();
      notifyListeners();
    }
  }

  void backToSourceList() {
    _state = _state.copyWith(
      section: AppSection.sources,
      clearSelectedSource: true,
      clearSelectedEntry: true,
      clearEntrySourceFilter: true,
    );
    _persistReadingContext();
    notifyListeners();
  }

  Future<void> openEntry(int entryId) async {
    _state = _state.copyWith(selectedEntryId: entryId);
    _persistReadingContext();
    notifyListeners();

    if (!_state.isOnline) {
      final entry = _state.snapshot.entries[entryId];
      if (entry != null && !entry.isRead) {
        await repository.queueReadState(entryId, true);
        await _reloadFromStore(selectedEntryId: entryId, isOnline: false);
      }
      return;
    }

    try {
      await repository.fetchEntryDetail(entryId, markRead: true);
      await _reloadFromStore(selectedEntryId: entryId, isOnline: true);
    } on ApiException catch (error) {
      if (error.isNotFound) {
        await _handleMissingEntry();
        return;
      }
      await _handleError(error);
    } on NetworkException {
      final entry = _state.snapshot.entries[entryId];
      if (entry != null && !entry.isRead) {
        await repository.queueReadState(entryId, true);
      }
      await _reloadFromStore(selectedEntryId: entryId, isOnline: false);
      _showOfflineQueuedWriteMessage();
    } on TimeoutException {
      final entry = _state.snapshot.entries[entryId];
      if (entry != null && !entry.isRead) {
        await repository.queueReadState(entryId, true);
      }
      await _reloadFromStore(selectedEntryId: entryId, isOnline: false);
      _showOfflineQueuedWriteMessage();
    }
  }

  Future<void> _handleMissingEntry() async {
    await _reloadFromStore(
      selectedEntryId: null,
      preserveSelection: false,
      isOnline: true,
    );
    if (_disposed) {
      return;
    }
    _state = _state.copyWith(errorMessage: '文章已在服务端删除，已从本地移除。');
    notifyListeners();
  }

  Future<void> openSelectedEntry() async {
    final entryId = _state.selectedEntryId;
    if (entryId == null) {
      return;
    }
    await openEntry(entryId);
  }

  Future<void> selectNextEntry() => _selectAdjacentEntry(1);

  Future<void> selectPreviousEntry() => _selectAdjacentEntry(-1);

  Future<void> selectNextUnreadEntry() => _selectAdjacentUnreadEntry(1);

  Future<void> selectPreviousUnreadEntry() => _selectAdjacentUnreadEntry(-1);

  Future<void> selectFirstUnreadEntry() =>
      _selectBoundaryUnreadEntry(first: true);

  Future<void> selectLastUnreadEntry() =>
      _selectBoundaryUnreadEntry(first: false);

  Future<void> selectFirstEntry() => _selectBoundaryEntry(first: true);

  Future<void> selectLastEntry() => _selectBoundaryEntry(first: false);

  Future<RefreshAcceptedResult> refreshAll() async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      final result = await repository.refreshAllAndPoll();
      await _reloadFromStore(isOnline: true);
      return result;
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> syncNow() async {
    if (!_state.isAuthenticated) {
      return;
    }

    final inFlight = _syncInFlightFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final syncCompleter = Completer<void>();
    _syncInFlightFuture = syncCompleter.future;
    _setBusy(true);
    try {
      await repository.sync();
      await _reloadFromStore(isOnline: true);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        await _refreshPendingSyncCount();
      }
      await _handleError(error);
    } on NetworkException catch (error) {
      await _refreshPendingSyncCount();
      await _handleError(error);
    } on TimeoutException catch (error) {
      await _refreshPendingSyncCount();
      await _handleError(error);
    } finally {
      _syncInFlightFuture = null;
      syncCompleter.complete();
      _setBusy(false);
    }
  }

  Future<void> handleAppResume() => syncNow();

  Future<void> loadMoreEntries() async {
    final key = _currentListKey();
    if (key == null || !_state.snapshot.hasMore(key)) {
      return;
    }

    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.loadMoreEntries(key);
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: true,
      );
    } on ApiException catch (error) {
      if (error.isNotFound &&
          _state.section == AppSection.sourceEntries &&
          _state.selectedSourceId != null) {
        await _handleMissingSource();
        throw _missingSourceApiException();
      }
      if (error.isNotFound && _isCurrentSourceFilterListKey(key)) {
        await _handleMissingSourceFilter(_state.section);
        throw _missingSourceFilterApiException();
      }
      if (error.isNotFound && _isCurrentFolderFilterListKey(key)) {
        await _handleMissingFolderFilter();
        throw _missingFolderFilterApiException();
      }
      if (_isInvalidPaginationCursor(error)) {
        await _reloadFromStore(
          section: _state.section,
          selectedSourceId: _state.selectedSourceId,
          selectedEntryId: _state.selectedEntryId,
          isOnline: true,
        );
      }
      rethrow;
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error, timeoutMessage: '加载历史文章超时，请稍后重试。');
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  void toggleUnreadOnly(bool value) {
    _setEntryQueueFilter(
      value ? EntryQueueFilter.unread : EntryQueueFilter.all,
    );
  }

  void toggleInProgressOnly(bool value) {
    _setEntryQueueFilter(
      value ? EntryQueueFilter.inProgress : EntryQueueFilter.all,
    );
  }

  void setSearchQuery(String value) {
    _state = _state.copyWith(searchQuery: value);
    _ensureSelection();
    _scheduleRemoteSearch();
    _persistReadingContext();
    notifyListeners();
  }

  void setEntrySourceFilter(int? sourceId) {
    _state = _state.copyWith(
      entrySourceFilterId: sourceId,
      clearEntrySourceFilter: sourceId == null,
      clearEntryFolderFilter: sourceId != null,
    );
    _ensureSelection();
    _persistReadingContext();
    notifyListeners();

    if (!_state.isOnline || sourceId == null) {
      return;
    }

    if (_state.searchQuery.trim().isNotEmpty) {
      _scheduleRemoteSearch();
      return;
    }

    final key = _currentListKey();
    if (key != null) {
      unawaited(
        _loadRemoteListSnapshot(key, _state.section, _state.selectedSourceId),
      );
    }
  }

  void setEntryFolderFilter(String? folder) {
    final normalizedFolder = _normalizeFolderName(folder ?? '');
    final hasFolder = folder != null && folder.trim().isNotEmpty;
    _state = _state.copyWith(
      entryFolderFilter: hasFolder ? normalizedFolder : null,
      clearEntryFolderFilter: !hasFolder,
      clearEntrySourceFilter: hasFolder,
    );
    _ensureSelection();
    _persistReadingContext();
    notifyListeners();

    if (!_state.isOnline) {
      return;
    }

    if (_state.searchQuery.trim().isNotEmpty) {
      _scheduleRemoteSearch();
      return;
    }

    final key = _currentListKey();
    if (hasFolder && key != null) {
      unawaited(
        _loadRemoteListSnapshot(key, _state.section, _state.selectedSourceId),
      );
    }
  }

  void setEntrySortOrder(EntrySortOrder sortOrder) {
    if (_state.entrySortOrder == sortOrder) {
      return;
    }
    final preferences = _preferencesWithReadingContext(
      _state.readerPreferences.copyWith(entrySortOrder: sortOrder),
    );
    _state = _state.copyWith(
      entrySortOrder: sortOrder,
      readerPreferences: preferences,
    );
    _ensureSelection();
    notifyListeners();
    unawaited(_saveReaderPreferences(preferences));
  }

  void setEntryListDensity(EntryListDensity density) {
    if (_state.readerPreferences.entryListDensity == density) {
      return;
    }

    final preferences = _preferencesWithReadingContext(
      _state.readerPreferences.copyWith(entryListDensity: density),
    );
    _state = _state.copyWith(readerPreferences: preferences);
    notifyListeners();
    unawaited(_saveReaderPreferences(preferences));
  }

  void setSourceListSortOrder(SourceListSortOrder sortOrder) {
    if (_state.readerPreferences.sourceListSortOrder == sortOrder) {
      return;
    }

    final preferences = _preferencesWithReadingContext(
      _state.readerPreferences.copyWith(sourceListSortOrder: sortOrder),
    );
    _state = _state.copyWith(readerPreferences: preferences);
    notifyListeners();
    unawaited(_saveReaderPreferences(preferences));
  }

  void setCollapsedSourceFolders(Iterable<String> folders) {
    final normalized =
        folders
            .map((folder) => folder.trim())
            .where((folder) => folder.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort(
            (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
          );
    if (listEquals(
      _state.readerPreferences.collapsedSourceFolders,
      normalized,
    )) {
      return;
    }

    final preferences = _preferencesWithReadingContext(
      _state.readerPreferences.copyWith(collapsedSourceFolders: normalized),
    );
    _state = _state.copyWith(readerPreferences: preferences);
    notifyListeners();
    unawaited(_saveReaderPreferences(preferences));
  }

  void setCollapsedEntryDateSections(Iterable<String> sectionKeys) {
    final normalized =
        sectionKeys
            .map((sectionKey) => sectionKey.trim())
            .where((sectionKey) => sectionKey.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (listEquals(
      _state.readerPreferences.collapsedEntryDateSections,
      normalized,
    )) {
      return;
    }

    final preferences = _preferencesWithReadingContext(
      _state.readerPreferences.copyWith(collapsedEntryDateSections: normalized),
    );
    _state = _state.copyWith(readerPreferences: preferences);
    _ensureSelection();
    notifyListeners();
    unawaited(_saveReaderPreferences(preferences));
  }

  void _setEntryQueueFilter(EntryQueueFilter filter) {
    final unreadOnly = filter == EntryQueueFilter.unread;
    final inProgressOnly = filter == EntryQueueFilter.inProgress;
    if (_state.readerPreferences.entryQueueFilter == filter &&
        _state.unreadOnly == unreadOnly &&
        _state.inProgressOnly == inProgressOnly) {
      return;
    }

    final basePreferences = _state.readerPreferences.copyWith(
      entryQueueFilter: filter,
    );
    _state = _state.copyWith(
      unreadOnly: unreadOnly,
      inProgressOnly: inProgressOnly,
      readerPreferences: basePreferences,
    );
    _ensureSelection();
    final preferences = _preferencesWithReadingContext(basePreferences);
    _state = _state.copyWith(readerPreferences: preferences);
    notifyListeners();
    if (_state.isOnline && unreadOnly) {
      if (_state.searchQuery.trim().isNotEmpty) {
        _scheduleRemoteSearch();
      } else {
        final key = _currentListKey();
        if (key != null) {
          unawaited(
            _loadRemoteListSnapshot(
              key,
              _state.section,
              _state.selectedSourceId,
            ),
          );
        }
      }
    }
    unawaited(_saveReaderPreferences(preferences));
  }

  void toggleTranslations(bool value) {
    if (_state.showTranslations == value &&
        _state.readerPreferences.showTranslations == value) {
      return;
    }
    final preferences = _preferencesWithReadingContext(
      _state.readerPreferences.copyWith(showTranslations: value),
    );
    _state = _state.copyWith(
      showTranslations: value,
      readerPreferences: preferences,
    );
    notifyListeners();
    unawaited(_saveReaderPreferences(preferences));
  }

  Future<void> setReaderPreferences(ReaderPreferences preferences) async {
    final nextPreferences = _preferencesWithReadingContext(preferences);
    await _saveReaderPreferences(nextPreferences);
    _state = _state.copyWith(
      readerPreferences: nextPreferences,
      showTranslations: nextPreferences.showTranslations,
    );
    notifyListeners();
  }

  void updateReadingProgress(int entryId, double progress) {
    final entry = _state.snapshot.entries[entryId];
    if (entry == null) {
      return;
    }

    final normalizedProgress = _normalizeReadingProgress(progress);
    if (entry.isRead && !_isReadingComplete(normalizedProgress)) {
      return;
    }
    if ((entry.readingProgress - normalizedProgress).abs() < 0.015 &&
        !_isReadingComplete(normalizedProgress)) {
      return;
    }

    _state = _state.copyWith(
      snapshot: _snapshotWithReadingProgress(entry, normalizedProgress),
    );
    notifyListeners();
    final persistFuture = _chainReadingProgressPersist(
      entryId,
      normalizedProgress,
    );
    _pendingReadingProgressPersists[entryId] = persistFuture;
    unawaited(persistFuture);

    if (!_state.isOnline) {
      return;
    }

    _pendingReadingProgress[entryId] = normalizedProgress;
    _readingProgressTimers[entryId]?.cancel();
    _readingProgressTimers[entryId] = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_flushReadingProgress(entryId)),
    );
  }

  Future<void> markSelectedUnread() async {
    final entryId = _state.selectedEntryId;
    if (entryId == null) {
      return;
    }

    var queuedAfterTransientFailure = false;
    if (_state.isOnline) {
      try {
        await repository.markUnread(entryId);
      } on NetworkException {
        await repository.queueReadState(entryId, false);
        queuedAfterTransientFailure = true;
      } on TimeoutException {
        await repository.queueReadState(entryId, false);
        queuedAfterTransientFailure = true;
      }
    } else {
      await repository.queueReadState(entryId, false);
    }
    await _reloadFromStore(
      selectedEntryId: entryId,
      isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
    );
    if (queuedAfterTransientFailure) {
      _showOfflineQueuedWriteMessage();
    }
  }

  Future<void> toggleSelectedRead() async {
    final entry = selectedEntry;
    if (entry == null) {
      return;
    }

    await toggleEntryRead(entry.id);
  }

  Future<void> toggleSelectedSaved() async {
    final entry = selectedEntry;
    if (entry == null) {
      return;
    }

    await toggleEntrySaved(entry.id);
  }

  Future<void> toggleSelectedNoise() async {
    final entry = selectedEntry;
    if (entry == null) {
      return;
    }

    await toggleEntryNoise(entry.id);
  }

  Future<void> reprocessSelectedAi() async {
    final entry = selectedEntry;
    if (entry == null) {
      return;
    }

    await reprocessEntryAi(entry.id);
  }

  Future<void> reprocessEntryAi(int entryId) async {
    final entry = _state.snapshot.entries[entryId];
    if (entry == null ||
        entry.aiProcessingState == EntryAiProcessingState.none ||
        entry.aiProcessingState == EntryAiProcessingState.pending) {
      return;
    }

    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.reprocessEntryAi(entry.id);
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: true,
      );
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> toggleEntryRead(int entryId) async {
    final entry = _state.snapshot.entries[entryId];
    if (entry == null) {
      return;
    }

    final nextReadState = !entry.isRead;
    var queuedAfterTransientFailure = false;
    if (_state.isOnline) {
      try {
        if (nextReadState) {
          await repository.markRead(entry.id);
        } else {
          await repository.markUnread(entry.id);
        }
      } on ApiException catch (error) {
        if (error.isNotFound) {
          await _handleMissingEntry();
        }
        rethrow;
      } on NetworkException {
        await repository.queueReadState(entry.id, nextReadState);
        queuedAfterTransientFailure = true;
      } on TimeoutException {
        await repository.queueReadState(entry.id, nextReadState);
        queuedAfterTransientFailure = true;
      }
    } else {
      await repository.queueReadState(entry.id, nextReadState);
    }
    await _reloadFromStore(
      section: _state.section,
      selectedSourceId: _state.selectedSourceId,
      selectedEntryId: _state.selectedEntryId,
      isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
    );
    if (queuedAfterTransientFailure) {
      _showOfflineQueuedWriteMessage();
    }
  }

  Future<void> toggleEntrySaved(int entryId) async {
    final entry = _state.snapshot.entries[entryId];
    if (entry == null) {
      return;
    }

    final nextSavedState = !entry.isSaved;
    var queuedAfterTransientFailure = false;
    if (_state.isOnline) {
      try {
        await repository.setSaved(entry.id, nextSavedState);
      } on NetworkException {
        await repository.queueSavedState(entry.id, nextSavedState);
        queuedAfterTransientFailure = true;
      } on TimeoutException {
        await repository.queueSavedState(entry.id, nextSavedState);
        queuedAfterTransientFailure = true;
      }
    } else {
      await repository.queueSavedState(entry.id, nextSavedState);
    }
    await _reloadFromStore(
      section: _state.section,
      selectedSourceId: _state.selectedSourceId,
      selectedEntryId: _state.selectedEntryId,
      isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
    );
    if (queuedAfterTransientFailure) {
      _showOfflineQueuedWriteMessage();
    }
  }

  Future<void> saveSelectedForLaterAndOpenNext() async {
    final entry = selectedEntry;
    if (entry == null) {
      return;
    }

    var target = _nextQueueEntry(_navigableEntries, entry.id);
    if (target == null && _state.isOnline && canLoadMoreEntries) {
      await loadMoreEntries();
      target = _nextQueueEntry(_navigableEntries, entry.id);
    }

    _setBusy(true);
    try {
      var queuedAfterTransientFailure = false;
      if (_state.isOnline) {
        try {
          if (!entry.isSaved) {
            await repository.setSaved(entry.id, true);
          }
          if (!entry.isRead) {
            await repository.markRead(entry.id);
          }
          if (target != null) {
            await repository.fetchEntryDetail(target.id, markRead: true);
          }
        } on NetworkException {
          await _queueSaveForLaterAndContinue(entry, target);
          queuedAfterTransientFailure = true;
        } on TimeoutException {
          await _queueSaveForLaterAndContinue(entry, target);
          queuedAfterTransientFailure = true;
        }
      } else {
        await _queueSaveForLaterAndContinue(entry, target);
      }
      await _reloadFromStore(
        selectedEntryId: target?.id ?? entry.id,
        isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
      );
      if (queuedAfterTransientFailure) {
        _showOfflineQueuedWriteMessage();
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> toggleEntryNoise(int entryId) async {
    final entry = _state.snapshot.entries[entryId];
    if (entry == null) {
      return;
    }

    _setBusy(true);
    try {
      var queuedAfterTransientFailure = false;
      if (_state.isOnline) {
        try {
          await repository.setEntryNoise(entry.id, !entry.isNoise);
        } on NetworkException {
          await repository.queueNoiseState(entry.id, !entry.isNoise);
          queuedAfterTransientFailure = true;
        } on TimeoutException {
          await repository.queueNoiseState(entry.id, !entry.isNoise);
          queuedAfterTransientFailure = true;
        }
      } else {
        await repository.queueNoiseState(entry.id, !entry.isNoise);
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
      );
      if (queuedAfterTransientFailure) {
        _showOfflineQueuedWriteMessage();
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> moveSelectedToNoiseAndOpenNext() async {
    final entry = selectedEntry;
    if (entry == null || entry.isNoise) {
      return;
    }

    var target = _nextQueueEntry(_navigableEntries, entry.id);
    if (target == null && _state.isOnline && canLoadMoreEntries) {
      await loadMoreEntries();
      target = _nextQueueEntry(_navigableEntries, entry.id);
    }

    _setBusy(true);
    try {
      var queuedAfterTransientFailure = false;
      if (_state.isOnline) {
        try {
          await repository.setEntryNoise(entry.id, true);
          if (target != null) {
            await repository.fetchEntryDetail(target.id, markRead: true);
          }
        } on NetworkException {
          await _queueMoveToNoiseAndContinue(entry, target);
          queuedAfterTransientFailure = true;
        } on TimeoutException {
          await _queueMoveToNoiseAndContinue(entry, target);
          queuedAfterTransientFailure = true;
        }
      } else {
        await _queueMoveToNoiseAndContinue(entry, target);
      }
      await _reloadFromStore(
        selectedEntryId: target?.id,
        isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
      );
      if (queuedAfterTransientFailure) {
        _showOfflineQueuedWriteMessage();
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> finishSelectedAndOpenNext() async {
    final entry = selectedEntry;
    if (entry == null) {
      return;
    }

    var target = _nextQueueEntry(_navigableEntries, entry.id);
    if (target == null && _state.isOnline && canLoadMoreEntries) {
      await loadMoreEntries();
      target = _nextQueueEntry(_navigableEntries, entry.id);
    }

    _setBusy(true);
    try {
      var queuedAfterTransientFailure = false;
      if (_state.isOnline) {
        try {
          if (!entry.isRead) {
            await repository.markRead(entry.id);
          }
          if (target != null) {
            await repository.fetchEntryDetail(target.id, markRead: true);
          }
        } on NetworkException {
          await _queueFinishAndContinue(entry, target);
          queuedAfterTransientFailure = true;
        } on TimeoutException {
          await _queueFinishAndContinue(entry, target);
          queuedAfterTransientFailure = true;
        }
      } else {
        await _queueFinishAndContinue(entry, target);
      }
      await _reloadFromStore(
        selectedEntryId: target?.id ?? entry.id,
        isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
      );
      if (queuedAfterTransientFailure) {
        _showOfflineQueuedWriteMessage();
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _queueSaveForLaterAndContinue(
    EntryRecord entry,
    EntryRecord? target,
  ) async {
    if (!entry.isSaved) {
      await repository.queueSavedState(entry.id, true);
    }
    await _queueCurrentAndTargetRead(entry, target);
  }

  Future<void> _queueMoveToNoiseAndContinue(
    EntryRecord entry,
    EntryRecord? target,
  ) async {
    await repository.queueNoiseState(entry.id, true);
    if (target != null && !target.isRead) {
      await repository.queueReadState(target.id, true);
    }
  }

  Future<void> _queueFinishAndContinue(
    EntryRecord entry,
    EntryRecord? target,
  ) async {
    await _queueCurrentAndTargetRead(entry, target);
  }

  Future<void> _queueCurrentAndTargetRead(
    EntryRecord entry,
    EntryRecord? target,
  ) async {
    if (!entry.isRead) {
      await repository.queueReadState(entry.id, true);
    }
    if (target != null && !target.isRead) {
      await repository.queueReadState(target.id, true);
    }
  }

  Future<void> markAllRead() async {
    final view = switch (_state.section) {
      AppSection.feed => EntryView.feed,
      AppSection.noise => EntryView.noise,
      AppSection.saved => EntryView.saved,
      AppSection.sourceEntries => null,
      AppSection.sources || AppSection.settings || AppSection.account => null,
    };

    if (_state.section == AppSection.sourceEntries &&
        _state.selectedSourceId != null) {
      await markSourceRead(_state.selectedSourceId!);
      return;
    }

    if (view == null) {
      return;
    }

    _setBusy(true);
    try {
      if (_state.isOnline) {
        await repository.markAllRead(view);
      } else {
        await repository.queueEntriesRead(visibleUnreadEntryIds);
      }
      await _reloadFromStore(isOnline: _state.isOnline);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> markSourceRead(int sourceId) async {
    _setBusy(true);
    try {
      if (_state.isOnline) {
        try {
          await repository.markSourceRead(sourceId);
        } on ApiException catch (error) {
          if (error.isNotFound) {
            await _handleMissingSource();
            throw _missingSourceApiException();
          }
          rethrow;
        }
      } else {
        await repository.queueEntriesRead(
          _cachedUnreadEntryIdsForSource(sourceId),
        );
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: _state.isOnline,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> markFolderRead(String folder) async {
    final folderName = _normalizeFolderName(folder);
    _setBusy(true);
    try {
      if (_state.isOnline) {
        try {
          await repository.markFolderRead(folderName);
        } on ApiException catch (error) {
          if (error.isNotFound && _state.entryFolderFilter == folderName) {
            await _handleMissingFolderFilter();
          }
          rethrow;
        }
      } else {
        await repository.queueEntriesRead(
          _cachedUnreadEntryIdsForFolder(folderName),
        );
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: _state.isOnline,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> markVisibleRead() async {
    await markEntriesRead(visibleUnreadEntryIds);
  }

  Future<void> markEntriesRead(List<int> entryIds) async {
    final normalizedEntryIds = _normalizeEntryIds(entryIds);
    if (normalizedEntryIds.isEmpty) {
      return;
    }

    _setBusy(true);
    try {
      var queuedAfterTransientFailure = false;
      if (_state.isOnline) {
        try {
          await repository.markEntriesRead(normalizedEntryIds);
        } on NetworkException {
          await repository.queueEntriesRead(normalizedEntryIds);
          queuedAfterTransientFailure = true;
        } on TimeoutException {
          await repository.queueEntriesRead(normalizedEntryIds);
          queuedAfterTransientFailure = true;
        }
      } else {
        await repository.queueEntriesRead(normalizedEntryIds);
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
      );
      if (queuedAfterTransientFailure) {
        _showOfflineQueuedWriteMessage();
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> markEntriesUnread(List<int> entryIds) async {
    final normalizedEntryIds = _normalizeEntryIds(entryIds);
    if (normalizedEntryIds.isEmpty) {
      return;
    }

    _setBusy(true);
    try {
      var queuedAfterTransientFailure = false;
      var removedStaleEntries = false;
      for (final entryId in normalizedEntryIds) {
        if (_state.isOnline) {
          try {
            await repository.markUnread(entryId);
          } on ApiException catch (error) {
            if (!error.isNotFound) {
              rethrow;
            }
            removedStaleEntries = true;
          } on NetworkException {
            await repository.queueReadState(entryId, false);
            queuedAfterTransientFailure = true;
          } on TimeoutException {
            await repository.queueReadState(entryId, false);
            queuedAfterTransientFailure = true;
          }
        } else {
          await repository.queueReadState(entryId, false);
        }
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: queuedAfterTransientFailure ? false : _state.isOnline,
      );
      if (queuedAfterTransientFailure) {
        _showOfflineQueuedWriteMessage();
      }
      if (removedStaleEntries) {
        _state = _state.copyWith(errorMessage: '部分文章已在服务端删除，已从本地移除。');
        notifyListeners();
      }
    } finally {
      _setBusy(false);
    }
  }

  Future<void> queueEntriesUnread(List<int> entryIds) async {
    final normalizedEntryIds = _normalizeEntryIds(entryIds);
    if (normalizedEntryIds.isEmpty) {
      return;
    }

    _setBusy(true);
    try {
      for (final entryId in normalizedEntryIds) {
        await repository.queueReadState(entryId, false);
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: _state.isOnline,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> queueEntryReadState(int entryId, bool isRead) async {
    if (entryId <= 0) {
      return;
    }

    _setBusy(true);
    try {
      await repository.queueReadState(entryId, isRead);
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: _state.isOnline,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> queueEntrySavedState(int entryId, bool isSaved) async {
    if (entryId <= 0) {
      return;
    }

    _setBusy(true);
    try {
      await repository.queueSavedState(entryId, isSaved);
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: _state.isOnline,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> queueEntryNoiseState(int entryId, bool isNoise) async {
    if (entryId <= 0) {
      return;
    }

    _setBusy(true);
    try {
      await repository.queueNoiseState(entryId, isNoise);
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: _state.isOnline,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> addSource(String rssUrl, {String? folder}) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      final source = await repository.addSource(rssUrl, folder: folder);
      await _reloadFromStore(
        section: AppSection.sourceEntries,
        selectedSourceId: source.id,
        isOnline: true,
        preserveSelection: false,
      );
      try {
        await repository.refreshSourceAndPoll(source.id);
      } on Object catch (error, stackTrace) {
        await _recordConnectivityLoss(error);
        _throwSourceRefreshAfterSave(
          action: SourceSaveAction.add,
          source: source,
          cause: error,
          stackTrace: stackTrace,
        );
      }
      await repository.loadSourceEntries(source.id);
      await _reloadFromStore(
        section: AppSection.sourceEntries,
        selectedSourceId: source.id,
        isOnline: true,
        preserveSelection: false,
      );
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> updateSource(FeedSource source) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      final updatedSource = await repository.updateSource(source);
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: true,
      );
      if (updatedSource.enabled) {
        try {
          await repository.refreshSourceAndPoll(updatedSource.id);
        } on Object catch (error, stackTrace) {
          await _recordConnectivityLoss(error);
          _throwSourceRefreshAfterSave(
            action: SourceSaveAction.update,
            source: updatedSource,
            cause: error,
            stackTrace: stackTrace,
          );
        }
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: true,
      );
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<RefreshAcceptedResult> refreshSource(int sourceId) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      final RefreshAcceptedResult result;
      try {
        result = await repository.refreshSourceAndPoll(sourceId);
      } on ApiException catch (error) {
        if (error.isNotFound) {
          await _handleMissingSource();
          throw _missingSourceApiException();
        }
        rethrow;
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: true,
      );
      return result;
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<RefreshAcceptedResult> refreshSources(Iterable<int> sourceIds) async {
    final normalizedSourceIds = <int>[];
    final seenSourceIds = <int>{};
    for (final sourceId in sourceIds) {
      if (seenSourceIds.add(sourceId)) {
        normalizedSourceIds.add(sourceId);
      }
    }
    if (normalizedSourceIds.isEmpty) {
      return const RefreshAcceptedResult(
        accepted: true,
        acceptedCount: 0,
        requestedCount: 0,
        skippedCount: 0,
      );
    }

    _requireOnlineWrite();
    _setBusy(true);
    try {
      final currentListKey = _currentListKey();
      final currentSection = _state.section;
      final currentSourceId = _state.selectedSourceId;
      final result = await repository.refreshSourcesAndPoll(
        normalizedSourceIds,
      );
      if (currentListKey != null) {
        await _loadRemoteListSnapshot(
          currentListKey,
          currentSection,
          currentSourceId,
        );
      }
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: _state.isOnline,
      );
      return result;
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> deleteSource(int sourceId) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.deleteSource(sourceId);
      await _reloadFromStore(
        section: AppSection.sources,
        preserveSelection: false,
        isOnline: true,
      );
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<String> exportOpml() async {
    _setBusy(true);
    try {
      return await repository.exportOpml();
    } finally {
      _setBusy(false);
    }
  }

  Future<OpmlImportResult> importOpml(
    String opml, {
    required bool refreshAfterImport,
  }) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      final result = await repository.importOpml(
        opml,
        refreshAfterImport: refreshAfterImport,
      );
      await _reloadFromStore(
        section: AppSection.sources,
        preserveSelection: false,
        isOnline: true,
      );
      return result;
    } on OpmlImportSyncException catch (error) {
      await _reloadFromStore(
        section: AppSection.sources,
        preserveSelection: false,
        isOnline:
            error.cause is! NetworkException &&
            error.cause is! TimeoutException,
      );
      throw OpmlImportSyncAfterSuccessException(
        result: error.result,
        cause: error.cause,
      );
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> saveAiSettings({
    required AiSettings settings,
    String? rawApiKey,
    bool clearApiKey = false,
  }) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.updateAiSettings(
        current: settings,
        rawApiKey: rawApiKey,
        clearApiKey: clearApiKey,
      );
      await _reloadFromStore(isOnline: true);
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> saveAppearanceSettings(AppThemeMode themeMode) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.updateAppearanceSettings(themeMode);
      await repository.setThemeOverride(null);
      await _reloadFromStore(isOnline: true);
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> saveFeedSettings(String defaultLanguage) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.updateFeedSettings(defaultLanguage);
      await _reloadFromStore(isOnline: true);
    } on NetworkException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } on TimeoutException catch (error) {
      await _recordConnectivityLoss(error);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> setThemeOverride(AppThemeMode? mode) async {
    await repository.setThemeOverride(mode);
    final session = await repository.loadSession();
    _state = _state.copyWith(session: session);
    notifyListeners();
  }

  void changeSettingsSection(SettingsSection section) {
    _state = _state.copyWith(settingsSection: section);
    notifyListeners();
  }

  void clearError() {
    _state = _state.copyWith(clearErrorMessage: true);
    notifyListeners();
  }

  void _setBusy(bool value) {
    _state = _state.copyWith(busy: value);
    notifyListeners();
  }

  Future<void> _restoreRemoteState() async {
    if (_syncInFlightFuture != null) {
      return;
    }

    final syncCompleter = Completer<void>();
    _syncInFlightFuture = syncCompleter.future;
    _setBusy(true);
    try {
      await repository.verifySession();
      await repository.sync();
      await _reloadFromStore(isOnline: true);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        await _refreshPendingSyncCount();
      }
      await _handleError(error);
    } on NetworkException catch (error) {
      await _refreshPendingSyncCount();
      await _handleError(error);
    } on TimeoutException catch (error) {
      await _refreshPendingSyncCount();
      await _handleError(error);
    } finally {
      _syncInFlightFuture = null;
      syncCompleter.complete();
      _setBusy(false);
    }
  }

  Future<void> _reloadFromStore({
    AppSection? section,
    int? selectedSourceId,
    int? selectedEntryId,
    bool preserveSelection = true,
    bool? isOnline,
  }) async {
    final session = await repository.loadSession();
    final snapshot = await repository.loadSnapshot();
    final pendingSyncStatus = await repository.pendingEntryActionStatus();
    if (_disposed) {
      return;
    }
    _state = _state.copyWith(
      session: session,
      snapshot: snapshot,
      pendingSyncCount: pendingSyncStatus.count,
      pendingSyncDescription: pendingSyncStatus.description,
      section: section ?? _state.section,
      selectedSourceId: preserveSelection
          ? selectedSourceId ?? _state.selectedSourceId
          : selectedSourceId,
      clearSelectedSource: !preserveSelection && selectedSourceId == null,
      selectedEntryId: preserveSelection
          ? selectedEntryId ?? _state.selectedEntryId
          : selectedEntryId,
      clearSelectedEntry: !preserveSelection && selectedEntryId == null,
      isOnline: isOnline ?? _state.isOnline,
      clearErrorMessage: true,
    );
    _ensureSelection();
    _persistReadingContext();
    notifyListeners();
  }

  void _ensureSelection() {
    _ensureSelectedSource();
    _ensureEntryScopeFilters();
    final visibleIds = _navigableEntries
        .map((entry) => entry.id)
        .toList(growable: false);
    final selectedEntryId = _state.selectedEntryId;
    if (selectedEntryId != null && visibleIds.contains(selectedEntryId)) {
      return;
    }

    final shouldClearEntry =
        _state.section == AppSection.sources ||
        _state.section == AppSection.settings ||
        _state.section == AppSection.account;
    _state = _state.copyWith(
      selectedEntryId: shouldClearEntry || visibleIds.isEmpty
          ? null
          : visibleIds.first,
      clearSelectedEntry: shouldClearEntry || visibleIds.isEmpty,
    );
  }

  void _ensureSelectedSource() {
    if (_state.section != AppSection.sourceEntries) {
      return;
    }

    final selectedSourceId = _state.selectedSourceId;
    final hasSelectedSource =
        selectedSourceId != null &&
        _state.snapshot.sourceById(selectedSourceId) != null;
    if (hasSelectedSource) {
      return;
    }

    _state = _state.copyWith(
      section: AppSection.feed,
      clearSelectedSource: true,
      clearSelectedEntry: true,
    );
  }

  void _ensureEntryScopeFilters() {
    final filterableSection =
        _state.section == AppSection.feed ||
        _state.section == AppSection.saved ||
        _state.section == AppSection.noise;

    final folderFilter = _state.entryFolderFilter;
    if (folderFilter != null) {
      if (!filterableSection) {
        return;
      }
      final hasFolder = _state.snapshot.sources.any(
        (source) => _normalizeFolderName(source.folder) == folderFilter,
      );
      if (!hasFolder) {
        _state = _state.copyWith(clearEntryFolderFilter: true);
      }
    }

    final sourceFilterId = _state.entrySourceFilterId;
    if (sourceFilterId == null) {
      return;
    }

    if (!filterableSection) {
      return;
    }

    final hasSource = _state.snapshot.sourceById(sourceFilterId) != null;
    if (!hasSource) {
      _state = _state.copyWith(clearEntrySourceFilter: true);
    }
  }

  ReaderPreferences _preferencesWithReadingContext(ReaderPreferences base) {
    final section = _isRestorableReadingSection(_state.section)
        ? _state.section
        : null;
    final sourceFilterId = _state.entrySourceFilterId;

    return base.copyWith(
      lastSection: section?.name,
      lastSelectedSourceId: section == AppSection.sourceEntries
          ? _state.selectedSourceId
          : null,
      lastSelectedEntryId: section == null ? null : _state.selectedEntryId,
      lastEntrySourceFilterId: section == null ? null : sourceFilterId,
      lastEntryFolderFilter: section == null || sourceFilterId != null
          ? null
          : _state.entryFolderFilter,
    );
  }

  void _persistReadingContext() {
    final preferences = _preferencesWithReadingContext(
      _state.readerPreferences,
    );
    _state = _state.copyWith(readerPreferences: preferences);
    unawaited(_saveReaderPreferences(preferences));
  }

  Future<void> _saveReaderPreferences(ReaderPreferences preferences) {
    final previous = _readerPreferencesSave.catchError(
      (Object error, StackTrace stackTrace) {},
    );
    final next = previous.then((_) async {
      if (_disposed) {
        return;
      }
      await repository.saveReaderPreferences(preferences);
    });
    _readerPreferencesSave = next.catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      if (_disposed) {
        return;
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
    return _readerPreferencesSave;
  }

  AppSection _restorableSection(ReaderPreferences preferences) {
    final sectionName = preferences.lastSection;
    if (sectionName == null) {
      return AppSection.feed;
    }

    for (final section in AppSection.values) {
      if (section.name != sectionName) {
        continue;
      }
      if (section == AppSection.sourceEntries &&
          preferences.lastSelectedSourceId == null) {
        return AppSection.feed;
      }
      return _isRestorableReadingSection(section) ? section : AppSection.feed;
    }

    return AppSection.feed;
  }

  Future<void> _selectBoundaryEntry({required bool first}) async {
    final entries = _navigableEntries;
    if (entries.isEmpty) {
      return;
    }

    final targetEntry = first ? entries.first : entries.last;
    if (targetEntry.id == _state.selectedEntryId) {
      return;
    }

    await openEntry(targetEntry.id);
  }

  Future<void> _selectBoundaryUnreadEntry({required bool first}) async {
    final unreadEntries = _navigableEntries
        .where((entry) => !entry.isRead)
        .toList(growable: false);
    if (unreadEntries.isEmpty) {
      return;
    }

    final targetEntry = first ? unreadEntries.first : unreadEntries.last;
    if (targetEntry.id == _state.selectedEntryId) {
      return;
    }

    await openEntry(targetEntry.id);
  }

  bool _isRestorableReadingSection(AppSection section) {
    return section == AppSection.feed ||
        section == AppSection.noise ||
        section == AppSection.saved ||
        section == AppSection.sourceEntries;
  }

  Future<void> _selectAdjacentEntry(int delta) async {
    final entries = _navigableEntries;
    if (entries.isEmpty) {
      return;
    }

    final currentIndex = entries.indexWhere(
      (entry) => entry.id == _state.selectedEntryId,
    );
    final targetIndex = currentIndex == -1
        ? (delta > 0 ? 0 : entries.length - 1)
        : (currentIndex + delta).clamp(0, entries.length - 1);
    final targetEntry = entries[targetIndex];
    if (targetEntry.id == _state.selectedEntryId) {
      if (delta > 0 && _state.isOnline && canLoadMoreEntries) {
        await loadMoreEntries();
        final updatedEntries = _navigableEntries;
        final updatedCurrentIndex = updatedEntries.indexWhere(
          (entry) => entry.id == _state.selectedEntryId,
        );
        if (updatedCurrentIndex != -1 &&
            updatedCurrentIndex + 1 < updatedEntries.length) {
          await openEntry(updatedEntries[updatedCurrentIndex + 1].id);
        }
      }
      return;
    }

    await openEntry(targetEntry.id);
  }

  Future<void> _selectAdjacentUnreadEntry(int delta) async {
    var entries = _navigableEntries;
    if (entries.isEmpty) {
      return;
    }

    final currentIndex = entries.indexWhere(
      (entry) => entry.id == _state.selectedEntryId,
    );
    final startIndex = currentIndex == -1
        ? (delta > 0 ? -1 : entries.length)
        : currentIndex;
    final targetEntry = _findUnreadEntry(entries, startIndex, delta);
    if (targetEntry != null) {
      await openEntry(targetEntry.id);
      return;
    }

    if (delta <= 0 || !_state.isOnline || !canLoadMoreEntries) {
      return;
    }

    await loadMoreEntries();
    entries = _navigableEntries;
    final updatedCurrentIndex = entries.indexWhere(
      (entry) => entry.id == _state.selectedEntryId,
    );
    final nextTargetEntry = _findUnreadEntry(entries, updatedCurrentIndex, 1);
    if (nextTargetEntry != null) {
      await openEntry(nextTargetEntry.id);
    }
  }

  EntryRecord? _findUnreadEntry(
    List<EntryRecord> entries,
    int startIndex,
    int delta,
  ) {
    var index = startIndex + delta;
    while (index >= 0 && index < entries.length) {
      final entry = entries[index];
      if (!entry.isRead) {
        return entry;
      }
      index += delta;
    }
    return null;
  }

  EntryRecord? _nextQueueEntry(
    List<EntryRecord> entries,
    int? selectedEntryId,
  ) {
    if (entries.isEmpty) {
      return null;
    }

    final currentIndex = entries.indexWhere(
      (entry) => entry.id == selectedEntryId,
    );
    if (currentIndex == -1 || currentIndex == entries.length - 1) {
      return null;
    }

    for (var index = currentIndex + 1; index < entries.length; index += 1) {
      final entry = entries[index];
      if (!entry.isRead) {
        return entry;
      }
    }

    return entries[currentIndex + 1];
  }

  Future<void> _handleError(Object error) async {
    if (error is ApiException && error.isUnauthorized) {
      await repository.clearLocalData();
      _syncTimer?.cancel();
      _syncTimer = null;
      _state = const AppState.initial().copyWith(
        initialized: true,
        errorMessage: '登录状态已失效，请重新登录。',
      );
      notifyListeners();
      return;
    }

    final pendingSyncRetention = _pendingSyncRetentionMessage();
    final message = switch (error) {
      ApiException apiError => _apiErrorMessage(apiError, pendingSyncRetention),
      TimeoutException() => '请求超时，请稍后重试。$pendingSyncRetention',
      NetworkException() => '当前网络不可用，已切换为离线阅读模式。$pendingSyncRetention',
      _ => '发生了未预期错误。',
    };

    _state = _state.copyWith(
      isOnline: error is! NetworkException && error is! TimeoutException
          ? _state.isOnline
          : false,
      errorMessage: message,
    );
    notifyListeners();
  }

  String _apiErrorMessage(ApiException error, String pendingSyncRetention) {
    String withPendingSyncRetention(String message) {
      if (pendingSyncRetention.isEmpty) {
        return message;
      }
      return '$message$pendingSyncRetention';
    }

    if (error.isNotFound) {
      return withPendingSyncRetention('服务端内容已变化，请同步刷新后重试。');
    }
    if (error.isBadRequest) {
      return withPendingSyncRetention('请求内容已过期，请刷新后重试。');
    }
    if (error.statusCode >= 500) {
      return withPendingSyncRetention('服务端暂时不可用，请稍后重试。');
    }
    return withPendingSyncRetention('服务端返回异常，请稍后重试。');
  }

  String _pendingSyncRetentionMessage() {
    final pendingCount = _state.pendingSyncCount;
    if (pendingCount <= 0) {
      return '';
    }
    final description = _state.pendingSyncDescription.trim();
    final detail = description.isEmpty ? '' : '（$description）';
    return '待同步 $pendingCount 个动作$detail已保留在本机，恢复在线后可重试。';
  }

  void _showOfflineQueuedWriteMessage() {
    _state = _state.copyWith(
      isOnline: false,
      errorMessage: '当前网络不可用，已切换为离线阅读模式。${_pendingSyncRetentionMessage()}',
    );
    notifyListeners();
  }

  Future<void> _handleMissingSource() async {
    await _reloadFromStore(
      section: AppSection.sources,
      preserveSelection: false,
      isOnline: true,
    );
    if (_disposed) {
      return;
    }
    _state = _state.copyWith(
      section: AppSection.sources,
      clearSelectedSource: true,
      clearSelectedEntry: true,
      errorMessage: '订阅源已在服务端删除，已从本地移除。',
    );
    _persistReadingContext();
    notifyListeners();
  }

  Future<void> _handleMissingSourceFilter(AppSection section) async {
    await _reloadFromStore(section: section, isOnline: true);
    if (_disposed) {
      return;
    }
    _state = _state.copyWith(
      clearEntrySourceFilter: true,
      errorMessage: '订阅源已在服务端删除，已清除来源筛选。',
    );
    _ensureSelection();
    _persistReadingContext();
    notifyListeners();
  }

  Future<void> _handleMissingFolderFilter() async {
    await _reloadFromStore(
      section: _state.section,
      selectedSourceId: _state.selectedSourceId,
      selectedEntryId: _state.selectedEntryId,
      isOnline: true,
    );
    if (_disposed) {
      return;
    }
    _state = _state.copyWith(
      clearEntryFolderFilter: true,
      errorMessage: '文件夹范围已在服务端变化，已清除文件夹筛选。',
    );
    _ensureSelection();
    _persistReadingContext();
    notifyListeners();
  }

  bool _isCurrentSourceFilterListKey(ListKey key) {
    final sourceFilterId = _state.entrySourceFilterId;
    if (sourceFilterId == null) {
      return false;
    }
    return ListKey.isSourceScopedValue(key.value, {sourceFilterId});
  }

  bool _isCurrentFolderFilterListKey(ListKey key) {
    final folderFilter = _state.entryFolderFilter;
    if (folderFilter == null) {
      return false;
    }
    return ListKey.isFolderScopedValue(key.value, {folderFilter});
  }

  ApiException _missingSourceApiException() {
    return const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: '订阅源已在服务端删除，已从本地移除。',
    );
  }

  ApiException _missingSourceFilterApiException() {
    return const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: '订阅源已在服务端删除，已清除来源筛选。',
    );
  }

  ApiException _missingFolderFilterApiException() {
    return const ApiException(
      statusCode: 404,
      code: 'NOT_FOUND',
      message: '文件夹范围已在服务端变化，已清除文件夹筛选。',
    );
  }

  Future<void> _refreshPendingSyncCount() async {
    final pendingSyncStatus = await repository.pendingEntryActionStatus();
    if (_disposed) {
      return;
    }
    _state = _state.copyWith(
      pendingSyncCount: pendingSyncStatus.count,
      pendingSyncDescription: pendingSyncStatus.description,
    );
    notifyListeners();
  }

  Future<void> _recordConnectivityLoss(
    Object error, {
    String? timeoutMessage,
  }) async {
    if (error is! NetworkException && error is! TimeoutException) {
      return;
    }
    await _refreshPendingSyncCount();
    if (_disposed) {
      return;
    }
    final message = error is TimeoutException
        ? '${timeoutMessage ?? '请求超时，请稍后重试。'}${_pendingSyncRetentionMessage()}'
        : '当前网络不可用，已切换为离线阅读模式。${_pendingSyncRetentionMessage()}';
    _state = _state.copyWith(isOnline: false, errorMessage: message);
    notifyListeners();
  }

  bool _isInvalidPaginationCursor(ApiException error) {
    return error.isBadRequest && error.message == 'invalid pagination cursor';
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(syncNow());
    });
  }

  void _requireOnlineWrite() {
    if (!_state.isOnline) {
      throw const NetworkException('offline');
    }
  }

  Never _throwSourceRefreshAfterSave({
    required SourceSaveAction action,
    required FeedSource source,
    required Object cause,
    required StackTrace stackTrace,
  }) {
    if (cause is ApiException ||
        cause is NetworkException ||
        cause is TimeoutException) {
      throw SourceRefreshAfterSaveException(
        action: action,
        source: source,
        cause: cause,
      );
    }

    Error.throwWithStackTrace(cause, stackTrace);
  }

  ListKey? _currentListKey() {
    final searchKey = _currentSearchListKey();
    if (searchKey != null) {
      return searchKey;
    }

    final view = _entryViewForSection(_state.section);
    final sourceFilterId = _state.entrySourceFilterId;
    if (view != null && sourceFilterId != null) {
      return _state.unreadOnly
          ? ListKey.unreadSourceInView(view.wireValue, sourceFilterId)
          : ListKey.sourceInView(view.wireValue, sourceFilterId);
    }

    final folder = _state.entryFolderFilter;
    if (view != null && folder != null) {
      return _state.unreadOnly
          ? ListKey.unreadFolderInView(view.wireValue, folder)
          : ListKey.folderInView(view.wireValue, folder);
    }

    if (view != null && _state.unreadOnly) {
      return ListKey.unreadInView(view.wireValue);
    }

    return switch (_state.section) {
      AppSection.feed => ListKey.feed,
      AppSection.noise => ListKey.noise,
      AppSection.saved => ListKey.saved,
      AppSection.sourceEntries =>
        _state.selectedSourceId == null
            ? null
            : _state.unreadOnly
            ? ListKey.unreadSourceInView(
                EntryView.all.wireValue,
                _state.selectedSourceId!,
              )
            : ListKey.source(_state.selectedSourceId!),
      AppSection.sources || AppSection.settings || AppSection.account => null,
    };
  }

  ListKey? _currentSearchListKey() {
    final query = _state.searchQuery.trim();
    if (query.isEmpty) {
      return null;
    }

    final view = _entryViewForSection(_state.section);
    final sourceFilterId = _state.entrySourceFilterId;
    if (view != null && sourceFilterId != null) {
      return _state.unreadOnly
          ? ListKey.searchUnreadSourceInView(
              view.wireValue,
              sourceFilterId,
              query,
            )
          : ListKey.searchSourceInView(view.wireValue, sourceFilterId, query);
    }

    final folder = _state.entryFolderFilter;
    if (view != null) {
      return folder == null
          ? _state.unreadOnly
                ? ListKey.searchUnreadInView(view.wireValue, query)
                : ListKey.searchInView(view.wireValue, query)
          : _state.unreadOnly
          ? ListKey.searchUnreadFolderInView(view.wireValue, folder, query)
          : ListKey.searchFolderInView(view.wireValue, folder, query);
    }

    return switch (_state.section) {
      AppSection.sourceEntries =>
        _state.selectedSourceId == null
            ? null
            : _state.unreadOnly
            ? ListKey.searchUnreadSourceInView(
                EntryView.all.wireValue,
                _state.selectedSourceId!,
                query,
              )
            : ListKey.searchSource(_state.selectedSourceId!, query),
      AppSection.feed ||
      AppSection.noise ||
      AppSection.saved ||
      AppSection.sources ||
      AppSection.settings ||
      AppSection.account => null,
    };
  }

  EntryView? _entryViewForSection(AppSection section) {
    return switch (section) {
      AppSection.feed => EntryView.feed,
      AppSection.noise => EntryView.noise,
      AppSection.saved => EntryView.saved,
      AppSection.sourceEntries ||
      AppSection.sources ||
      AppSection.settings ||
      AppSection.account => null,
    };
  }

  void _scheduleRemoteSearch() {
    _searchTimer?.cancel();
    final key = _currentSearchListKey();
    if (key == null || !_state.isOnline) {
      return;
    }

    final section = _state.section;
    final selectedSourceId = _state.selectedSourceId;
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_loadRemoteListSnapshot(key, section, selectedSourceId));
    });
  }

  Future<void> _loadRemoteListSnapshot(
    ListKey key,
    AppSection section,
    int? selectedSourceId,
  ) async {
    if (!_state.isOnline || _currentListKey() != key) {
      return;
    }

    try {
      await repository.loadSearchEntries(key);
      if (_currentListKey() != key) {
        return;
      }
      await _reloadFromStore(
        section: section,
        selectedSourceId: selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: true,
      );
    } on ApiException catch (error) {
      if (error.isNotFound &&
          section == AppSection.sourceEntries &&
          selectedSourceId != null) {
        await _handleMissingSource();
        return;
      }
      if (error.isNotFound && _isCurrentSourceFilterListKey(key)) {
        await _handleMissingSourceFilter(section);
        return;
      }
      await _handleError(error);
    } on NetworkException catch (error) {
      await _handleError(error);
    } on TimeoutException catch (error) {
      await _handleError(error);
    }
  }

  Future<void> _flushReadingProgress(int entryId) async {
    _readingProgressTimers.remove(entryId);
    final progress = _pendingReadingProgress.remove(entryId);
    final persistFuture = _pendingReadingProgressPersists.remove(entryId);
    if (persistFuture != null) {
      await persistFuture;
    }
    if (progress == null || !_state.isOnline) {
      return;
    }

    try {
      await repository.flushPendingEntryActions();
      await _reloadFromStore(
        selectedEntryId: _state.selectedEntryId,
        isOnline: true,
      );
    } on ApiException catch (error) {
      await _handleError(error);
    } on NetworkException catch (error) {
      await repository.queueReadingProgress(entryId, progress);
      await _refreshPendingSyncCount();
      await _handleError(error);
    } on TimeoutException catch (error) {
      await repository.queueReadingProgress(entryId, progress);
      await _refreshPendingSyncCount();
      await _handleError(error);
    }
  }

  Future<void> _queueReadingProgressForSync(
    int entryId,
    double progress,
  ) async {
    try {
      await repository.queueReadingProgress(entryId, progress);
      await _refreshPendingSyncCount();
    } on ApiException catch (error) {
      await _handleError(error);
    } on NetworkException catch (error) {
      await _handleError(error);
    } on TimeoutException catch (error) {
      await _handleError(error);
    }
  }

  Future<void> _chainReadingProgressPersist(int entryId, double progress) {
    final previous = _pendingReadingProgressPersists[entryId];
    final next = (previous ?? Future<void>.value()).then(
      (_) => _queueReadingProgressForSync(entryId, progress),
    );
    next.whenComplete(() {
      if (_pendingReadingProgressPersists[entryId] == next) {
        _pendingReadingProgressPersists.remove(entryId);
      }
    });
    return next;
  }

  double _normalizeReadingProgress(double progress) {
    if (progress.isNaN || progress.isInfinite) {
      return 0;
    }
    return progress.clamp(0, 1).toDouble();
  }

  AppSnapshot _snapshotWithReadingProgress(
    EntryRecord entry,
    double normalizedProgress,
  ) {
    final marksRead = _isReadingComplete(normalizedProgress);
    final nextEntry = entry.copyWith(
      isRead: marksRead ? true : entry.isRead,
      readingProgress: marksRead ? 1 : normalizedProgress,
    );
    final shouldDecrementSourceUnread =
        marksRead && !entry.isRead && !entry.isNoise;
    return _state.snapshot.copyWith(
      entries: {..._state.snapshot.entries, entry.id: nextEntry},
      sources: shouldDecrementSourceUnread
          ? _state.snapshot.sources
                .map(
                  (source) => source.id == entry.sourceId
                      ? source.copyWith(
                          unreadCount: source.unreadCount > 0
                              ? source.unreadCount - 1
                              : 0,
                        )
                      : source,
                )
                .toList(growable: false)
          : _state.snapshot.sources,
    );
  }

  bool _isReadingComplete(double progress) {
    return progress >= _readingCompleteProgress;
  }

  List<int> _normalizeEntryIds(List<int> entryIds) {
    return entryIds
        .where((entryId) => entryId > 0)
        .toSet()
        .toList(growable: false);
  }

  List<int> _cachedUnreadEntryIdsForSource(int sourceId) {
    return _normalizeEntryIds(
      _state.snapshot.entries.values
          .where((entry) => entry.sourceId == sourceId && !entry.isRead)
          .map((entry) => entry.id)
          .toList(growable: false),
    );
  }

  List<int> _cachedUnreadEntryIdsForFolder(String folder) {
    final folderName = _normalizeFolderName(folder);
    final sourceIds = _state.snapshot.sources
        .where((source) => _normalizeFolderName(source.folder) == folderName)
        .map((source) => source.id)
        .toSet();
    if (sourceIds.isEmpty) {
      return const <int>[];
    }
    return _normalizeEntryIds(
      _state.snapshot.entries.values
          .where((entry) => sourceIds.contains(entry.sourceId) && !entry.isRead)
          .map((entry) => entry.id)
          .toList(growable: false),
    );
  }

  @override
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _syncTimer?.cancel();
    _searchTimer?.cancel();
    for (final timer in _readingProgressTimers.values) {
      timer.cancel();
    }
    _readingProgressTimers.clear();
    _pendingReadingProgress.clear();
    _pendingReadingProgressPersists.clear();
    _disposed = true;
    super.dispose();
  }
}
