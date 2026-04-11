import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/article_queries.dart';
import '../data/api/api_client.dart';
import '../data/api/api_exception.dart';
import '../models/app_section.dart';
import '../models/entry_record.dart';
import '../models/feed_source.dart';
import '../models/session_data.dart';
import '../models/settings_bundle.dart';
import '../models/snapshot.dart';
import '../repositories/rss_repository.dart';

class AppState {
  const AppState({
    required this.initialized,
    required this.busy,
    required this.isOnline,
    required this.session,
    required this.snapshot,
    required this.section,
    required this.settingsSection,
    required this.selectedSourceId,
    required this.selectedEntryId,
    required this.unreadOnly,
    required this.showTranslations,
    required this.errorMessage,
  });

  const AppState.initial()
    : initialized = false,
      busy = false,
      isOnline = false,
      session = null,
      snapshot = const AppSnapshot.empty(),
      section = AppSection.feed,
      settingsSection = SettingsSection.ai,
      selectedSourceId = null,
      selectedEntryId = null,
      unreadOnly = false,
      showTranslations = true,
      errorMessage = null;

  final bool initialized;
  final bool busy;
  final bool isOnline;
  final SessionData? session;
  final AppSnapshot snapshot;
  final AppSection section;
  final SettingsSection settingsSection;
  final int? selectedSourceId;
  final int? selectedEntryId;
  final bool unreadOnly;
  final bool showTranslations;
  final String? errorMessage;

  bool get isAuthenticated => session != null;

  AppThemeMode get effectiveThemeMode =>
      session?.themeOverride ?? snapshot.settings.appearance.themeMode;

  AppState copyWith({
    bool? initialized,
    bool? busy,
    bool? isOnline,
    SessionData? session,
    bool clearSession = false,
    AppSnapshot? snapshot,
    AppSection? section,
    SettingsSection? settingsSection,
    int? selectedSourceId,
    bool clearSelectedSource = false,
    int? selectedEntryId,
    bool clearSelectedEntry = false,
    bool? unreadOnly,
    bool? showTranslations,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return AppState(
      initialized: initialized ?? this.initialized,
      busy: busy ?? this.busy,
      isOnline: isOnline ?? this.isOnline,
      session: clearSession ? null : session ?? this.session,
      snapshot: snapshot ?? this.snapshot,
      section: section ?? this.section,
      settingsSection: settingsSection ?? this.settingsSection,
      selectedSourceId: clearSelectedSource
          ? null
          : selectedSourceId ?? this.selectedSourceId,
      selectedEntryId: clearSelectedEntry
          ? null
          : selectedEntryId ?? this.selectedEntryId,
      unreadOnly: unreadOnly ?? this.unreadOnly,
      showTranslations: showTranslations ?? this.showTranslations,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
    );
  }
}

class AppController extends ChangeNotifier {
  AppController({required this.repository});

  final RssRepository repository;

  AppState _state = const AppState.initial();
  AppState get state => _state;

  Timer? _syncTimer;
  bool _syncInFlight = false;

  List<EntryRecord> get visibleEntries {
    return ArticleQueries.resolve(
      snapshot: _state.snapshot,
      section: _state.section,
      unreadOnly: _state.unreadOnly,
      selectedSourceId: _state.selectedSourceId,
    );
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

  Future<void> initialize() async {
    if (_state.initialized) {
      return;
    }

    final session = await repository.loadSession();
    final snapshot = await repository.loadSnapshot();
    _state = _state.copyWith(
      initialized: true,
      session: session,
      snapshot: snapshot,
      isOnline: session != null,
    );
    _ensureSelection();
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
    _state = _state.copyWith(
      section: section,
      clearSelectedSource:
          section != AppSection.sourceEntries && section != AppSection.sources,
      clearSelectedEntry:
          section == AppSection.sources ||
          section == AppSection.settings ||
          section == AppSection.account,
    );
    if (section == AppSection.sources) {
      _state = _state.copyWith(clearSelectedSource: true);
    }
    _ensureSelection();
    notifyListeners();
  }

  Future<void> openSource(int sourceId) async {
    _state = _state.copyWith(
      section: AppSection.sourceEntries,
      selectedSourceId: sourceId,
      clearSelectedEntry: true,
    );
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
      } on ApiException catch (error) {
        await _handleError(error);
      } on SocketException catch (error) {
        await _handleError(error);
      } on TimeoutException catch (error) {
        await _handleError(error);
      }
    } else {
      _ensureSelection();
      notifyListeners();
    }
  }

  void backToSourceList() {
    _state = _state.copyWith(
      section: AppSection.sources,
      clearSelectedSource: true,
      clearSelectedEntry: true,
    );
    notifyListeners();
  }

  Future<void> openEntry(int entryId) async {
    _state = _state.copyWith(selectedEntryId: entryId);
    notifyListeners();

    if (!_state.isOnline) {
      return;
    }

    try {
      await repository.fetchEntryDetail(entryId, markRead: true);
      await _reloadFromStore(selectedEntryId: entryId, isOnline: true);
    } on ApiException catch (error) {
      await _handleError(error);
    } on SocketException catch (error) {
      await _handleError(error);
    } on TimeoutException catch (error) {
      await _handleError(error);
    }
  }

  Future<void> refreshAll() async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.refreshAllAndPoll();
      await _reloadFromStore(isOnline: true);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> syncNow() async {
    if (!_state.isAuthenticated || _syncInFlight) {
      return;
    }

    _syncInFlight = true;
    try {
      await repository.sync();
      await _reloadFromStore(isOnline: true);
    } on ApiException catch (error) {
      await _handleError(error);
    } on SocketException catch (error) {
      await _handleError(error);
    } on TimeoutException catch (error) {
      await _handleError(error);
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> handleAppResume() => syncNow();

  void toggleUnreadOnly(bool value) {
    _state = _state.copyWith(unreadOnly: value);
    _ensureSelection();
    notifyListeners();
  }

  void toggleTranslations(bool value) {
    _state = _state.copyWith(showTranslations: value);
    notifyListeners();
  }

  Future<void> markSelectedUnread() async {
    final entryId = _state.selectedEntryId;
    if (entryId == null) {
      return;
    }

    _requireOnlineWrite();
    await repository.markUnread(entryId);
    await _reloadFromStore(selectedEntryId: entryId, isOnline: true);
  }

  Future<void> markAllRead() async {
    _requireOnlineWrite();
    final view = switch (_state.section) {
      AppSection.feed => EntryView.feed,
      AppSection.noise => EntryView.noise,
      AppSection.sourceEntries ||
      AppSection.sources ||
      AppSection.settings ||
      AppSection.account => null,
    };

    if (view == null) {
      return;
    }

    await repository.markAllRead(view);
    await _reloadFromStore(isOnline: true);
  }

  Future<void> addSource(String rssUrl) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      final source = await repository.addSource(rssUrl);
      await repository.refreshAllAndPoll();
      await _reloadFromStore(
        section: AppSection.sourceEntries,
        selectedSourceId: source.id,
        isOnline: true,
        preserveSelection: false,
      );
      await repository.loadSourceEntries(source.id);
      await _reloadFromStore(
        section: AppSection.sourceEntries,
        selectedSourceId: source.id,
        isOnline: true,
        preserveSelection: false,
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> updateSource(FeedSource source) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.updateSource(source);
      await repository.refreshAllAndPoll();
      await _reloadFromStore(
        section: _state.section,
        selectedSourceId: _state.selectedSourceId,
        selectedEntryId: _state.selectedEntryId,
        isOnline: true,
      );
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
    } finally {
      _setBusy(false);
    }
  }

  Future<void> saveAiSettings({
    required AiSettings settings,
    String? rawApiKey,
  }) async {
    _requireOnlineWrite();
    _setBusy(true);
    try {
      await repository.updateAiSettings(
        current: settings,
        rawApiKey: rawApiKey,
      );
      await _reloadFromStore(isOnline: true);
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
    try {
      await repository.verifySession();
      await repository.sync();
      await _reloadFromStore(isOnline: true);
    } on ApiException catch (error) {
      await _handleError(error);
    } on SocketException catch (error) {
      await _handleError(error);
    } on TimeoutException catch (error) {
      await _handleError(error);
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
    _state = _state.copyWith(
      session: session,
      snapshot: snapshot,
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
    notifyListeners();
  }

  void _ensureSelection() {
    final visibleIds = visibleEntries
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

    final message = switch (error) {
      ApiException(:final message) => message,
      TimeoutException() => '请求超时，请稍后重试。',
      SocketException() => '当前网络不可用，已切换为离线阅读模式。',
      _ => '发生了未预期错误。',
    };

    _state = _state.copyWith(
      isOnline: error is! SocketException && error is! TimeoutException
          ? _state.isOnline
          : false,
      errorMessage: message,
    );
    notifyListeners();
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(syncNow());
    });
  }

  void _requireOnlineWrite() {
    if (!_state.isOnline) {
      throw const SocketException('offline');
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}
