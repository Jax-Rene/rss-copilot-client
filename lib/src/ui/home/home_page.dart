import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_theme.dart';
import '../../core/diagnostic_redaction.dart' as diagnostic_redaction;
import '../../core/formatters.dart';
import '../../core/html_markdown.dart';
import '../../core/language_tag.dart';
import '../../core/reading_metrics.dart';
import '../../core/search_query.dart';
import '../../core/source_health.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_exception.dart';
import '../../models/app_section.dart';
import '../../models/entry_record.dart';
import '../../models/feed_source.dart';
import '../../models/reader_preferences.dart';
import '../../models/settings_bundle.dart';
import '../../state/app_controller.dart';
import '../../state/providers.dart';
import 'responsive_home_shell.dart';
import 'widgets/ai_settings_form.dart';
import 'widgets/article_detail_view.dart';

const String _refreshAllNetworkMessage = '当前网络不可用，已切换为离线阅读模式，可稍后重试刷新订阅源';
const String _refreshAllTimeoutMessage = '刷新订阅源请求超时，请稍后重试';
const String _refreshSourceNetworkMessage = '当前网络不可用，已切换为离线阅读模式，可稍后重试刷新此源';
const String _refreshSourceTimeoutMessage = '刷新此源请求超时，请稍后重试';
const String _refreshIssueSourcesNetworkMessage =
    '当前网络不可用，已切换为离线阅读模式，可稍后重试待处理订阅源';
const String _refreshIssueSourcesTimeoutMessage = '重试待处理订阅源请求超时，请稍后重试';
const String _refreshVisibleSourcesNetworkMessage =
    '当前网络不可用，已切换为离线阅读模式，可稍后重试刷新当前筛选订阅源';
const String _refreshVisibleSourcesTimeoutMessage = '刷新当前筛选订阅源请求超时，请稍后重试';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final FocusNode _shortcutFocusNode = FocusNode(debugLabel: 'home-shortcuts');
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'home-search');
  VoidCallback? _searchEscapeHandler;

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final state = controller.state;
    final theme = Theme.of(context);

    final message = state.errorMessage;
    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleShortcut(event, controller),
      child: Scaffold(
        body: ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: SafeArea(
            child: Column(
              children: [
                if (message != null)
                  MaterialBanner(
                    content: Text(message),
                    actions: [
                      if (state.isAuthenticated && !state.isOnline)
                        TextButton.icon(
                          key: const ValueKey<String>(
                            'retry-sync-banner-action',
                          ),
                          onPressed: state.busy
                              ? null
                              : () => unawaited(
                                  _syncNowWithFeedback(context, controller),
                                ),
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('重试同步'),
                        ),
                      TextButton(
                        onPressed: controller.clearError,
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                Expanded(
                  child: ResponsiveHomeShell(
                    navigationPane: _DesktopSidebar(controller: controller),
                    listPane: _DesktopListPane(
                      controller: controller,
                      searchFocusNode: _searchFocusNode,
                      onSearchEscapeHandlerChanged: _setSearchEscapeHandler,
                    ),
                    detailPane: _DesktopDetailPane(controller: controller),
                    mobileBody: _MobileHomeBody(
                      controller: controller,
                      searchFocusNode: _searchFocusNode,
                      onSearchEscapeHandlerChanged: _setSearchEscapeHandler,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setSearchEscapeHandler(VoidCallback? handler) {
    _searchEscapeHandler = handler;
  }

  KeyEventResult _handleShortcut(KeyEvent event, AppController controller) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape &&
        _searchEscapeHandler != null &&
        (controller.state.section == AppSection.sources ||
            controller.state.section == AppSection.sourceEntries)) {
      _searchEscapeHandler!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape &&
        _entrySearchOrFiltersCanHandleEscape(controller)) {
      _handleEntrySearchOrFiltersEscape(controller);
      return KeyEventResult.handled;
    }
    if (_hasEditableFocus()) {
      if (key == LogicalKeyboardKey.escape) {
        controller.setSearchQuery('');
        _shortcutFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final hardwareKeyboard = HardwareKeyboard.instance;
    if (hardwareKeyboard.isMetaPressed ||
        hardwareKeyboard.isControlPressed ||
        hardwareKeyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.slash) {
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      controller.setSearchQuery('');
      _shortcutFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH && hardwareKeyboard.isShiftPressed) {
      unawaited(controller.selectFirstUnreadEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH) {
      _showShortcutHelpDialog(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      unawaited(_showAddSourceShortcut(controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      unawaited(_showImportOpmlShortcut(controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      unawaited(_exportOpmlShortcut(controller));
      return KeyEventResult.handled;
    }
    if (_selectSectionShortcut(key, controller)) {
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ && hardwareKeyboard.isShiftPressed) {
      unawaited(controller.selectNextUnreadEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK && hardwareKeyboard.isShiftPressed) {
      unawaited(controller.selectPreviousUnreadEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyJ) {
      unawaited(controller.selectNextEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyK) {
      unawaited(controller.selectPreviousEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      unawaited(controller.selectFirstEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      unawaited(controller.selectLastEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.keyO) {
      unawaited(controller.openSelectedEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyV) {
      unawaited(_openOriginalLink(context, controller.selectedEntry));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC && hardwareKeyboard.isShiftPressed) {
      unawaited(_copyArticleSummary(context, controller.selectedEntry));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      unawaited(_copyOriginalLink(context, controller.selectedEntry));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyQ && hardwareKeyboard.isShiftPressed) {
      unawaited(_copyArticleNote(context, controller.selectedEntry));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyQ) {
      unawaited(_copyArticleCitation(context, controller.selectedEntry));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      unawaited(_reprocessSelectedAi(controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT && hardwareKeyboard.isShiftPressed) {
      unawaited(_copyArticleTranslations(context, controller.selectedEntry));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      controller.toggleTranslations(!controller.state.showTranslations);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal) {
      _updateReaderTypography(
        controller,
        (preferences) =>
            preferences.copyWith(fontSize: preferences.fontSize + 1),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus) {
      _updateReaderTypography(
        controller,
        (preferences) =>
            preferences.copyWith(fontSize: preferences.fontSize - 1),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketRight) {
      _updateReaderTypography(
        controller,
        (preferences) =>
            preferences.copyWith(lineHeight: preferences.lineHeight + 0.1),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketLeft) {
      _updateReaderTypography(
        controller,
        (preferences) =>
            preferences.copyWith(lineHeight: preferences.lineHeight - 0.1),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyW) {
      _cycleReaderWidth(controller);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0) {
      _updateReaderTypography(
        controller,
        (_) => ReaderPreferences.defaultPreferences.copyWith(
          entrySortOrder: controller.state.readerPreferences.entrySortOrder,
          entryQueueFilter: controller.state.readerPreferences.entryQueueFilter,
          entryListDensity: controller.state.readerPreferences.entryListDensity,
          sourceListSortOrder:
              controller.state.readerPreferences.sourceListSortOrder,
          collapsedEntryDateSections:
              controller.state.readerPreferences.collapsedEntryDateSections,
          collapsedSourceFolders:
              controller.state.readerPreferences.collapsedSourceFolders,
          showTranslations: controller.state.readerPreferences.showTranslations,
        ),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      unawaited(_toggleSelectedSavedWithUndo(context, controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL && hardwareKeyboard.isShiftPressed) {
      unawaited(controller.selectLastUnreadEntry());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL) {
      unawaited(_saveForLaterAndContinue(controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      unawaited(_toggleSelectedReadWithUndo(context, controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyE) {
      unawaited(_markReadThroughSelection(controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyA) {
      unawaited(_markVisibleRead(controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX) {
      unawaited(_moveSelectedToNoise(controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      unawaited(_finishSelectedAndOpenNextWithUndo(context, controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyU) {
      controller.toggleUnreadOnly(!controller.state.unreadOnly);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      controller.toggleInProgressOnly(!controller.state.inProgressOnly);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      _cycleEntrySortOrder(controller);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD && hardwareKeyboard.isShiftPressed) {
      _toggleSelectedEntryDateSectionCollapsed(controller);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD) {
      final nextDensity =
          controller.state.readerPreferences.entryListDensity ==
              EntryListDensity.compact
          ? EntryListDensity.comfortable
          : EntryListDensity.compact;
      controller.setEntryListDensity(nextDensity);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyR) {
      unawaited(_refreshCurrentScope(controller));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY) {
      unawaited(_syncNow(controller));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  bool _entrySearchOrFiltersCanHandleEscape(AppController controller) {
    final state = controller.state;
    final entrySection =
        state.section == AppSection.feed ||
        state.section == AppSection.saved ||
        state.section == AppSection.noise ||
        state.section == AppSection.sourceEntries;
    if (!entrySection) {
      return false;
    }
    return state.searchQuery.trim().isNotEmpty ||
        state.unreadOnly ||
        state.inProgressOnly ||
        state.entrySourceFilterId != null ||
        state.entryFolderFilter != null;
  }

  void _handleEntrySearchOrFiltersEscape(AppController controller) {
    final state = controller.state;
    if (state.searchQuery.trim().isNotEmpty) {
      controller.setSearchQuery('');
      return;
    }

    if (state.unreadOnly) {
      controller.toggleUnreadOnly(false);
    } else if (state.inProgressOnly) {
      controller.toggleInProgressOnly(false);
    }

    if (state.entrySourceFilterId != null) {
      controller.setEntrySourceFilter(null);
    }
    if (state.entryFolderFilter != null) {
      controller.setEntryFolderFilter(null);
    }
  }

  void _updateReaderTypography(
    AppController controller,
    ReaderPreferences Function(ReaderPreferences preferences) update,
  ) {
    unawaited(
      controller.setReaderPreferences(
        update(controller.state.readerPreferences),
      ),
    );
  }

  bool _selectSectionShortcut(
    LogicalKeyboardKey key,
    AppController controller,
  ) {
    final section = switch (key) {
      LogicalKeyboardKey.digit1 => AppSection.feed,
      LogicalKeyboardKey.digit2 => AppSection.saved,
      LogicalKeyboardKey.digit3 => AppSection.noise,
      LogicalKeyboardKey.digit4 => AppSection.sources,
      LogicalKeyboardKey.digit5 => AppSection.settings,
      LogicalKeyboardKey.digit6 => AppSection.account,
      _ => null,
    };
    if (section == null) {
      return false;
    }
    controller.selectSection(section);
    return true;
  }

  void _cycleReaderWidth(AppController controller) {
    _updateReaderTypography(controller, (preferences) {
      final nextWidth = switch (preferences.width) {
        ReaderWidth.narrow => ReaderWidth.comfortable,
        ReaderWidth.comfortable => ReaderWidth.wide,
        ReaderWidth.wide => ReaderWidth.narrow,
      };
      return preferences.copyWith(width: nextWidth);
    });
  }

  void _cycleEntrySortOrder(AppController controller) {
    final nextSortOrder = switch (controller.state.entrySortOrder) {
      EntrySortOrder.newestFirst => EntrySortOrder.oldestFirst,
      EntrySortOrder.oldestFirst => EntrySortOrder.shortestFirst,
      EntrySortOrder.shortestFirst => EntrySortOrder.longestFirst,
      EntrySortOrder.longestFirst => EntrySortOrder.newestFirst,
    };
    controller.setEntrySortOrder(nextSortOrder);
  }

  void _toggleSelectedEntryDateSectionCollapsed(AppController controller) {
    final entry = controller.selectedEntry;
    if (entry == null) {
      _showReaderSnackBar(context, '当前没有选中文章');
      return;
    }

    final sectionKey = AppFormatters.dayKey(entry.publishedAt);
    final sectionLabel = AppFormatters.daySection(entry.publishedAt);
    final collapsedSections = controller
        .state
        .readerPreferences
        .collapsedEntryDateSections
        .toSet();
    final collapsed = collapsedSections.add(sectionKey);
    if (!collapsed) {
      collapsedSections.remove(sectionKey);
    }
    controller.setCollapsedEntryDateSections(collapsedSections);
    _showReaderSnackBar(
      context,
      collapsed ? '已折叠 $sectionLabel' : '已展开 $sectionLabel',
    );
  }

  bool _hasEditableFocus() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    return focusedContext.widget is EditableText ||
        focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<bool> _runShortcutAction(
    Future<void> Function() action, {
    String Function(ApiException error)? apiErrorMessage,
    String networkErrorMessage = '离线状态下不支持写操作',
    String timeoutMessage = '请求超时，请稍后重试。',
  }) async {
    try {
      await action();
      return true;
    } on NetworkException {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(networkErrorMessage)));
      return false;
    } on ApiException catch (error) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage?.call(error) ?? _entryActionApiErrorMessage(error),
          ),
        ),
      );
      return false;
    } on TimeoutException {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(timeoutMessage)));
      return false;
    }
  }

  Future<T?> _runShortcutValue<T>(
    Future<T> Function() action, {
    String Function(ApiException error)? apiErrorMessage,
    String networkErrorMessage = '离线状态下不支持写操作',
    String timeoutMessage = '请求超时，请稍后重试。',
  }) async {
    try {
      return await action();
    } on NetworkException {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(networkErrorMessage)));
      return null;
    } on ApiException catch (error) {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage?.call(error) ?? _entryActionApiErrorMessage(error),
          ),
        ),
      );
      return null;
    } on TimeoutException {
      if (!mounted) {
        return null;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(timeoutMessage)));
      return null;
    }
  }

  Future<void> _markReadThroughSelection(AppController controller) async {
    final entryIds = controller.visibleUnreadEntryIdsThroughSelection;
    if (entryIds.isEmpty) {
      _showReaderSnackBar(context, '当前没有需要标记已读的文章');
      return;
    }

    final wasOffline = !controller.state.isOnline;
    final succeeded = await _runShortcutAction(
      () => controller.markEntriesRead(entryIds),
    );
    if (!succeeded || !mounted) {
      return;
    }

    final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已将 ${entryIds.length} 篇标记为已读'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            _dismissCurrentReaderSnackBar(context);
            unawaited(
              _runShortcutAction(
                () => _undoMarkedRead(
                  controller,
                  entryIds,
                  wasOffline: wasOffline,
                ),
              ),
            );
          },
        ),
      ),
    );
    _trackReaderSnackBar(snackBarController, hasUndo: true);
  }

  Future<void> _reprocessSelectedAi(AppController controller) async {
    final entry = controller.selectedEntry;
    if (entry == null) {
      _showReaderSnackBar(context, '当前没有选中文章');
      return;
    }
    if (!_canReprocessEntryAi(entry.aiProcessingState)) {
      _showReaderSnackBar(context, '当前文章不需要重试 AI');
      return;
    }

    final succeeded = await _runShortcutAction(controller.reprocessSelectedAi);
    if (succeeded && mounted) {
      _showReaderSnackBar(context, 'AI 已重新加入处理队列');
    }
  }

  Future<void> _markVisibleRead(AppController controller) async {
    final entryIds = controller.visibleUnreadEntryIds;
    if (entryIds.isEmpty) {
      _showReaderSnackBar(context, '当前列表没有未读文章');
      return;
    }

    final wasOffline = !controller.state.isOnline;
    final succeeded = await _runShortcutAction(
      () => controller.markEntriesRead(entryIds),
    );
    if (!succeeded || !mounted) {
      return;
    }

    final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已将当前 ${entryIds.length} 篇标记为已读'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            _dismissCurrentReaderSnackBar(context);
            unawaited(
              _runShortcutAction(
                () => _undoMarkedRead(
                  controller,
                  entryIds,
                  wasOffline: wasOffline,
                ),
              ),
            );
          },
        ),
      ),
    );
    _trackReaderSnackBar(snackBarController, hasUndo: true);
  }

  Future<void> _saveForLaterAndContinue(AppController controller) async {
    final entry = controller.selectedEntry;
    if (entry == null) {
      _showReaderSnackBar(context, '当前没有选中文章');
      return;
    }
    final wasRead = entry.isRead;
    final wasSaved = entry.isSaved;
    final wasOffline = !controller.state.isOnline;

    final succeeded = await _runShortcutAction(
      controller.saveSelectedForLaterAndOpenNext,
    );
    if (!succeeded || !mounted) {
      return;
    }

    final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已加入稍后读'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            _dismissCurrentReaderSnackBar(context);
            unawaited(
              _runShortcutAction(() async {
                if (!wasSaved) {
                  await (wasOffline
                      ? controller.queueEntrySavedState(entry.id, wasSaved)
                      : controller.toggleEntrySaved(entry.id));
                }
                if (!wasRead) {
                  await _undoMarkedRead(controller, [
                    entry.id,
                  ], wasOffline: wasOffline);
                }
              }),
            );
          },
        ),
      ),
    );
    _trackReaderSnackBar(snackBarController, hasUndo: true);
  }

  Future<void> _moveSelectedToNoise(AppController controller) async {
    final entry = controller.selectedEntry;
    if (entry == null) {
      _showReaderSnackBar(context, '当前没有选中文章');
      return;
    }
    if (entry.isNoise) {
      _showReaderSnackBar(context, '当前文章已在噪音箱');
      return;
    }
    final wasOffline = !controller.state.isOnline;

    final succeeded = await _runShortcutAction(
      controller.moveSelectedToNoiseAndOpenNext,
    );
    if (!succeeded || !mounted) {
      return;
    }

    final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已移入噪音箱'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            _dismissCurrentReaderSnackBar(context);
            unawaited(
              _runShortcutAction(
                () => _undoToggledNoise(
                  controller,
                  entry,
                  wasOffline: wasOffline,
                ),
              ),
            );
          },
        ),
      ),
    );
    _trackReaderSnackBar(snackBarController, hasUndo: true);
  }

  Future<void> _refreshCurrentScope(AppController controller) async {
    final sourceId = controller.state.section == AppSection.sourceEntries
        ? controller.state.selectedSourceId
        : controller.state.entrySourceFilterId;
    if (sourceId != null) {
      final result = await _runShortcutValue(
        () => controller.refreshSource(sourceId),
        apiErrorMessage: _sourceRefreshApiErrorMessage,
        networkErrorMessage: _refreshSourceNetworkMessage,
        timeoutMessage: _refreshSourceTimeoutMessage,
      );
      if (result != null && mounted) {
        _showReaderSnackBar(
          context,
          _refreshCurrentSourceAcceptedMessage(result),
        );
      }
      return;
    }
    final folder = controller.state.entryFolderFilter;
    if (folder != null) {
      final sourceIds = controller.state.snapshot.sources
          .where(
            (source) => source.enabled && _sourceFolderName(source) == folder,
          )
          .map((source) => source.id)
          .toList(growable: false);
      final result = await _runShortcutValue(
        () => controller.refreshSources(sourceIds),
        apiErrorMessage: _sourceRefreshApiErrorMessage,
        networkErrorMessage: _refreshVisibleSourcesNetworkMessage,
        timeoutMessage: _refreshVisibleSourcesTimeoutMessage,
      );
      if (result != null && mounted) {
        _showReaderSnackBar(
          context,
          _refreshCurrentFolderAcceptedMessage(result),
        );
      }
      return;
    }
    final result = await _runShortcutValue(
      controller.refreshAll,
      apiErrorMessage: _sourceRefreshApiErrorMessage,
      networkErrorMessage: _refreshAllNetworkMessage,
      timeoutMessage: _refreshAllTimeoutMessage,
    );
    if (result != null && mounted) {
      _showReaderSnackBar(context, _refreshAllAcceptedMessage(result));
    }
  }

  Future<void> _syncNow(AppController controller) async {
    await _syncNowWithFeedback(context, controller);
  }

  Future<void> _showAddSourceShortcut(AppController controller) async {
    controller.selectSection(AppSection.sources);
    await _showAddSourceDialog(context, controller);
  }

  Future<void> _showImportOpmlShortcut(AppController controller) async {
    controller.selectSection(AppSection.sources);
    await _showImportOpmlDialog(context, controller);
  }

  Future<void> _exportOpmlShortcut(AppController controller) async {
    controller.selectSection(AppSection.sources);
    await _copyExportedOpml(context, controller);
  }
}

String _sourceFolderName(FeedSource source) {
  final folder = source.folder.trim();
  return folder.isEmpty ? defaultSourceFolder : folder;
}

String _sourceRefreshAfterSaveMessage(SourceRefreshAfterSaveException error) {
  final prefix = switch (error.action) {
    SourceSaveAction.add => '已添加订阅源',
    SourceSaveAction.update => '已更新订阅源',
  };
  return switch (error.cause) {
    TimeoutException() => '$prefix，但刷新请求超时，请稍后重试',
    NetworkException() => '$prefix，但当前网络不可用，可稍后手动刷新',
    ApiException apiError =>
      '$prefix，但${_sourceRefreshApiErrorMessage(apiError)}',
    _ => '$prefix，但刷新失败，请稍后重试',
  };
}

String _sourceRefreshApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  final message = error.message;
  if (message.startsWith('rss refresh failed: HTTP ')) {
    final status = message.substring('rss refresh failed: HTTP '.length);
    return _sourceHttpFailureMessage('刷新失败', status);
  }
  if (message.startsWith('rss source is unreachable: HTTP ')) {
    final status = message.substring('rss source is unreachable: HTTP '.length);
    return _sourceHttpFailureMessage('刷新失败', status);
  }
  if (message.startsWith('invalid rss feed:')) {
    return '刷新失败：这个地址返回的内容不是有效 Feed';
  }
  if (message == 'too many feed sources to refresh') {
    return '刷新失败：一次最多刷新 100 个订阅源，请缩小筛选范围后重试';
  }
  return _apiFailureMessage('刷新失败', error);
}

String _sourceSaveApiErrorMessage(ApiException error, SourceSaveAction action) {
  final prefix = switch (action) {
    SourceSaveAction.add => '添加失败',
    SourceSaveAction.update => '更新失败',
  };
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  final message = error.message;
  if (error.statusCode == 409 || error.code == 'CONFLICT') {
    return '$prefix：这个 Feed 已经在订阅列表里';
  }
  if (message == 'invalid url') {
    return '$prefix：URL 无效，请输入 http(s) 地址或域名';
  }
  if (message == 'rss feed could not be discovered') {
    return '$prefix：没有在这个页面发现可用 RSS/Atom/JSON Feed';
  }
  if (message.startsWith('rss source is unreachable: HTTP ')) {
    final status = message.substring('rss source is unreachable: HTTP '.length);
    return _sourceHttpFailureMessage(prefix, status);
  }
  if (message.startsWith('invalid rss feed:')) {
    return '$prefix：这个地址返回的内容不是有效 Feed';
  }
  return _apiFailureMessage(prefix, error);
}

String _sourceHttpFailureMessage(String prefix, String rawStatus) {
  final status = rawStatus.trim();
  return switch (status) {
    '401' || '403' => '$prefix：源站限制抓取（HTTP $status），可在浏览器打开原站或更换 Feed 地址',
    '404' || '410' => '$prefix：Feed 地址可能已失效（HTTP $status），请重新发现或编辑订阅源 URL',
    '429' => '$prefix：源站限流（HTTP $status），请稍后重试',
    _ when status.startsWith('5') => '$prefix：源站服务异常（HTTP $status），请稍后重试',
    _ => '$prefix：订阅源暂时无法访问（HTTP $status）',
  };
}

String _sourceDeleteApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  if (error.isNotFound) {
    return '删除失败：订阅源已在服务端删除，请刷新同步本地列表';
  }
  if (error.isBadRequest) {
    return '删除失败：订阅源状态异常，请刷新后重试';
  }
  return _apiFailureMessage('删除失败', error);
}

String _refreshAllAcceptedMessage(RefreshAcceptedResult result) {
  if (result.acceptedCount <= 0) {
    if (result.skippedCount > 0) {
      return '没有订阅源被服务端接收，跳过 ${result.skippedCount} 个不可用源';
    }
    return '没有可刷新的启用订阅源';
  }
  if (result.skippedCount > 0) {
    return '已请求刷新 ${result.acceptedCount} 个订阅源，跳过 ${result.skippedCount} 个不可用源';
  }
  return '已请求刷新 ${result.acceptedCount} 个订阅源';
}

String _refreshCurrentSourceAcceptedMessage(RefreshAcceptedResult result) {
  if (result.acceptedCount <= 0) {
    return '当前来源已停用，未发起刷新';
  }
  if (result.skippedCount > 0) {
    return '已请求刷新 ${result.acceptedCount} 个当前来源，跳过 ${result.skippedCount} 个不可用源';
  }
  return '已请求刷新 ${result.acceptedCount} 个当前来源';
}

String _refreshCurrentFolderAcceptedMessage(RefreshAcceptedResult result) {
  return _refreshScopedSourcesAcceptedMessage(
    result: result,
    scopeName: '当前文件夹',
    emptyMessage: '当前文件夹没有可刷新的启用订阅源',
  );
}

String _refreshScopedSourcesAcceptedMessage({
  required RefreshAcceptedResult result,
  required String scopeName,
  required String emptyMessage,
}) {
  if (result.acceptedCount <= 0) {
    if (result.requestedCount > 0) {
      if (result.skippedCount > 0) {
        final remainingCount = result.requestedCount - result.skippedCount;
        final remainingMessage = remainingCount > 0 ? '，其余可能已删除或停用' : '';
        return '$scopeName没有订阅源被服务端接收，跳过 ${result.skippedCount} 个不可用源$remainingMessage';
      }
      return '$scopeName的 ${result.requestedCount} 个订阅源未被服务端接收，可能已删除或停用';
    }
    return emptyMessage;
  }

  if (result.skippedCount > 0) {
    return '已请求刷新 ${result.acceptedCount} 个$scopeName订阅源，跳过 ${result.skippedCount} 个不可用源';
  }
  return '已请求刷新 ${result.acceptedCount} 个$scopeName订阅源';
}

String _refreshSourceAcceptedMessage(
  RefreshAcceptedResult result,
  FeedSource source,
) {
  final sourceName = _redactDiagnosticText(source.name);
  if (result.acceptedCount <= 0) {
    return '订阅源已停用，未发起刷新：$sourceName';
  }
  if (result.skippedCount > 0) {
    return '已请求刷新 ${result.acceptedCount} 个订阅源，跳过 ${result.skippedCount} 个不可用源：$sourceName';
  }
  return '已请求刷新 ${result.acceptedCount} 个订阅源：$sourceName';
}

String _refreshIssueSourcesAcceptedMessage(RefreshAcceptedResult result) {
  return _refreshScopedSourcesAcceptedMessage(
    result: result,
    scopeName: '待处理',
    emptyMessage: '没有可刷新的待处理订阅源',
  );
}

String _refreshVisibleSourcesAcceptedMessage(RefreshAcceptedResult result) {
  return _refreshScopedSourcesAcceptedMessage(
    result: result,
    scopeName: '当前筛选',
    emptyMessage: '当前筛选没有可刷新的启用订阅源',
  );
}

Future<void> _showAddSourceDialog(
  BuildContext context,
  AppController controller,
) async {
  final result = await showDialog<({String rssUrl, String folder})>(
    context: context,
    builder: (context) => _AddSourceDialog(
      folderSuggestions: _sourceFolderSuggestions(
        controller.state.snapshot.sources,
      ),
    ),
  );

  if (result == null || result.rssUrl.isEmpty || !context.mounted) {
    return;
  }

  try {
    await controller.addSource(result.rssUrl, folder: result.folder);
  } on SourceRefreshAfterSaveException catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_sourceRefreshAfterSaveMessage(error))),
    );
  } on ApiException catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_sourceSaveApiErrorMessage(error, SourceSaveAction.add)),
      ),
    );
  } on NetworkException {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前网络不可用，已切换为离线阅读模式，可稍后重试添加订阅源')),
    );
  } on TimeoutException {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('添加请求超时，请稍后重试')));
  }
}

String _opmlImportSyncAfterSuccessMessage(
  OpmlImportSyncAfterSuccessException error,
) {
  final imported = _opmlImportResultSummary(
    error.result,
    includeTrailingStop: false,
  );
  return switch (error.cause) {
    TimeoutException() => '$imported，但同步请求超时，请稍后刷新',
    NetworkException() => '$imported，但当前网络不可用，可稍后刷新',
    ApiException apiError =>
      '$imported，但${_opmlImportSyncApiErrorMessage(apiError)}',
    _ => '$imported，但同步失败，请稍后刷新',
  };
}

String _opmlImportApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  final message = error.message;
  if (message == 'invalid opml document') {
    return '导入失败：OPML 格式无效，请确认文件来自其他 RSS 阅读器导出';
  }
  if (message == 'request body is invalid') {
    return '导入失败：请求内容无法解析，请重新粘贴 OPML XML';
  }
  if (error.isPayloadTooLarge || message == 'opml document is too large') {
    return '导入失败：OPML 文件太大，请先在原阅读器分批导出后再导入';
  }
  if (message == 'opml contains too many subscriptions') {
    return '导入失败：一次导入的订阅源太多，请分批导入 OPML';
  }
  if (message == 'opml contains no rss subscriptions') {
    return '导入失败：这个 OPML 里没有可导入的 RSS 订阅源，请确认导出文件包含订阅条目';
  }
  return _apiFailureMessage('导入失败', error);
}

String _opmlImportSyncApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  final message = error.message;
  if (message.startsWith('rss refresh failed: HTTP ') ||
      message.startsWith('rss source is unreachable: HTTP ') ||
      message.startsWith('invalid rss feed:')) {
    return _sourceRefreshApiErrorMessage(error);
  }
  return _apiFailureMessage('同步失败', error);
}

String _opmlImportSuccessMessage(
  OpmlImportResult result, {
  required bool refreshAfterImport,
}) {
  return _opmlImportResultSummary(result, refreshRequested: refreshAfterImport);
}

String _opmlImportResultSummary(
  OpmlImportResult result, {
  bool refreshRequested = true,
  bool includeTrailingStop = true,
}) {
  final parts = <String>[
    result.importedCount > 0 ? '已导入 ${result.importedCount} 个订阅源' : '没有导入新订阅源',
  ];
  if (result.skippedCount > 0) {
    parts.add('跳过 ${result.skippedCount} 个重复、缺少 xmlUrl 或 URL 无效的条目');
  }
  if (refreshRequested) {
    if (result.refreshAcceptedCount > 0) {
      parts.add('已开始刷新 ${result.refreshAcceptedCount} 个订阅源');
    } else {
      parts.add('没有新增订阅源需要刷新');
    }
  }
  final message = parts.join('，');
  return includeTrailingStop ? '$message。' : message;
}

Future<void> _showImportOpmlDialog(
  BuildContext context,
  AppController controller,
) async {
  final request =
      await showDialog<({String opml, bool refreshAfterImport})>(
        context: context,
        builder: (context) => const _ImportOpmlDialog(),
      ) ??
      (opml: '', refreshAfterImport: false);

  if (request.opml.isEmpty || !context.mounted) {
    return;
  }

  try {
    final result = await controller.importOpml(
      request.opml,
      refreshAfterImport: request.refreshAfterImport,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _opmlImportSuccessMessage(
            result,
            refreshAfterImport: request.refreshAfterImport,
          ),
        ),
      ),
    );
  } on OpmlImportSyncAfterSuccessException catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_opmlImportSyncAfterSuccessMessage(error))),
    );
  } on ApiException catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_opmlImportApiErrorMessage(error))));
  } on NetworkException {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前网络不可用，已切换为离线阅读模式，可稍后重试导入 OPML')),
    );
  } on TimeoutException {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('导入请求超时，请稍后重试')));
  }
}

Future<void> _copyExportedOpml(
  BuildContext context,
  AppController controller,
) async {
  try {
    final opml = await controller.exportOpml();
    await Clipboard.setData(ClipboardData(text: opml));
    if (!context.mounted) {
      return;
    }
    _showReaderSnackBar(context, 'OPML 已复制，可粘贴到其他阅读器', preserveCurrent: true);
  } on ApiException catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_opmlExportApiErrorMessage(error))));
  } on NetworkException {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('OPML 导出使用本地缓存，但当前缓存读取失败')));
  } on TimeoutException {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('导出请求超时，请稍后重试')));
  }
}

String _opmlExportApiErrorMessage(ApiException error) {
  if (error.isUnauthorized) {
    return '导出失败：登录状态已失效，请重新登录后再导出 OPML';
  }
  if (error.isNotFound) {
    return '导出失败：服务端暂时没有可导出的订阅列表，请同步刷新后重试';
  }
  if (error.statusCode >= 500) {
    return '导出失败：服务端暂时无法生成 OPML，请稍后重试';
  }
  return _apiFailureMessage('导出失败', error);
}

Future<void> _openOriginalLink(BuildContext context, EntryRecord? entry) async {
  await _openExternalLink(
    context,
    entry?.link,
    unavailableMessage: '原文链接不可用',
    failureMessage: '无法打开原文链接',
  );
}

Future<void> _openContentLink(BuildContext context, String url) async {
  await _openExternalLink(
    context,
    url,
    unavailableMessage: '正文链接不可用',
    failureMessage: '无法打开正文链接',
  );
}

Future<void> _openExternalLink(
  BuildContext context,
  String? link, {
  required String unavailableMessage,
  required String failureMessage,
}) async {
  final uri = _externalLinkUri(link);
  if (uri == null) {
    _showReaderSnackBar(context, unavailableMessage);
    return;
  }

  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _showReaderSnackBar(context, failureMessage);
    }
  } on PlatformException {
    if (!context.mounted) {
      return;
    }
    _showReaderSnackBar(context, failureMessage);
  }
}

Future<void> _copyOriginalLink(BuildContext context, EntryRecord? entry) async {
  final link = entry?.link.trim();
  if (link == null || link.isEmpty) {
    _showReaderSnackBar(context, '原文链接不可用');
    return;
  }

  await Clipboard.setData(ClipboardData(text: link));
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(context, '已复制原文链接', preserveCurrent: true);
}

Future<void> _copyArticleCitation(
  BuildContext context,
  EntryRecord? entry,
) async {
  final link = entry?.link.trim();
  if (entry == null || link == null || link.isEmpty) {
    _showReaderSnackBar(context, '原文链接不可用');
    return;
  }

  final escapedTitle = entry.title
      .trim()
      .replaceAll('\\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
  await Clipboard.setData(ClipboardData(text: '[$escapedTitle]($link)'));
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(context, '已复制文章引用', preserveCurrent: true);
}

Future<void> _copyArticleSummary(
  BuildContext context,
  EntryRecord? entry,
) async {
  final summary = entry?.summary?.trim();
  if (entry == null || summary == null || summary.isEmpty) {
    _showReaderSnackBar(context, '当前文章没有 AI 总结');
    return;
  }

  await Clipboard.setData(
    ClipboardData(text: '${entry.title.trim()}\n\n$summary'),
  );
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(context, '已复制 AI 总结', preserveCurrent: true);
}

Future<void> _copyArticleTranslations(
  BuildContext context,
  EntryRecord? entry,
) async {
  final segments = entry?.translationSegments ?? const [];
  if (entry == null || segments.isEmpty) {
    _showReaderSnackBar(context, '当前文章没有双语译文');
    return;
  }

  final parts = <String>[entry.title.trim()];
  for (final segment in segments) {
    final source = segment.source.trim();
    final translation = segment.translation.trim();
    if (source.isEmpty && translation.isEmpty) {
      continue;
    }
    parts
      ..add(source)
      ..add(translation);
  }

  if (parts.length == 1) {
    _showReaderSnackBar(context, '当前文章没有双语译文');
    return;
  }

  await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(context, '已复制双语译文', preserveCurrent: true);
}

Future<void> _copyArticleNote(BuildContext context, EntryRecord? entry) async {
  if (entry == null) {
    _showReaderSnackBar(context, '当前没有可复制的文章');
    return;
  }

  final title = entry.title.trim();
  final link = entry.link.trim();
  final summary = entry.summary?.trim();
  final metadata = _articleNoteMetadata(entry);
  final coverMarkdown = _articleNoteCoverMarkdown(entry);
  final parts = <String>[
    '# ${title.isEmpty ? '未命名文章' : title}',
    if (link.isNotEmpty) '[打开原文]($link)',
    if (metadata.isNotEmpty) ...['## 元信息', metadata.join('\n')],
    ?coverMarkdown,
    if (summary != null && summary.isNotEmpty) ...['## AI 总结', summary],
  ];
  final bodyMarkdown = htmlToMarkdown(entry.contentHtml ?? '');
  if (bodyMarkdown.isNotEmpty) {
    parts
      ..add('## 正文')
      ..add(bodyMarkdown);
  }

  final bilingualParts = <String>[];
  for (final segment in entry.translationSegments) {
    final source = segment.source.trim();
    final translation = segment.translation.trim();
    if (source.isEmpty && translation.isEmpty) {
      continue;
    }
    bilingualParts
      ..add(source)
      ..add(translation);
  }
  if (bilingualParts.isNotEmpty) {
    parts
      ..add('## 双语摘录')
      ..add(bilingualParts.join('\n\n'));
  }

  await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(context, '已复制阅读笔记', preserveCurrent: true);
}

List<String> _articleNoteMetadata(EntryRecord entry) {
  final sourceName = entry.sourceName.trim();
  final redactedSourceName = _redactDiagnosticText(sourceName);
  final author = entry.author?.trim();
  return [
    if (sourceName.isNotEmpty) '- 来源：$redactedSourceName',
    if (author != null && author.isNotEmpty) '- 作者：$author',
    '- 发布时间：${_articleNoteUtcDate(entry.publishedAt)}',
    if (_hasPartialReadingProgress(entry)) ...[
      '- 阅读进度：${(entry.readingProgress * 100).round()}%',
      '- ${_articleNoteRemainingReadingTimeLabel(entry)}',
    ],
  ];
}

bool _hasPartialReadingProgress(EntryRecord entry) {
  return entry.readingProgress > 0.02 && entry.readingProgress < 0.98;
}

String _articleNoteRemainingReadingTimeLabel(EntryRecord entry) {
  final totalMinutes = ReadingMetrics.estimateReadingMinutes(entry);
  final progress = entry.readingProgress.clamp(0, 1).toDouble();
  final remainingMinutes = (totalMinutes * (1 - progress)).ceil().clamp(
    1,
    totalMinutes,
  );
  return '剩余 ${ReadingMetrics.durationLabel(remainingMinutes)}';
}

String? _articleNoteCoverMarkdown(EntryRecord entry) {
  final coverImageUrl = entry.coverImageUrl?.trim();
  if (coverImageUrl == null || coverImageUrl.isEmpty) {
    return null;
  }
  return '![封面图]($coverImageUrl)';
}

String _articleNoteUtcDate(DateTime value) {
  final utc = value.toUtc();
  final date = [
    utc.year.toString().padLeft(4, '0'),
    utc.month.toString().padLeft(2, '0'),
    utc.day.toString().padLeft(2, '0'),
  ].join('-');
  final time = [
    utc.hour.toString().padLeft(2, '0'),
    utc.minute.toString().padLeft(2, '0'),
  ].join(':');
  return '$date $time UTC';
}

Uri? _externalLinkUri(String? rawLink) {
  final link = rawLink?.trim();
  if (link == null || link.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(link);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return uri;
}

bool _readerSnackBarHasUndo = false;
int _readerSnackBarGeneration = 0;

void _showReaderSnackBar(
  BuildContext context,
  String message, {
  bool preserveCurrent = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final shouldPreserveCurrent = preserveCurrent && _readerSnackBarHasUndo;
  if (!shouldPreserveCurrent) {
    messenger.removeCurrentSnackBar();
    messenger.clearSnackBars();
    _readerSnackBarHasUndo = false;
  }
  final controller = messenger.showSnackBar(SnackBar(content: Text(message)));
  if (!shouldPreserveCurrent) {
    _trackReaderSnackBar(controller, hasUndo: false);
  }
}

void _dismissCurrentReaderSnackBar(BuildContext context) {
  _readerSnackBarHasUndo = false;
  _readerSnackBarGeneration += 1;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
}

void _trackReaderSnackBar(
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller, {
  required bool hasUndo,
}) {
  _readerSnackBarHasUndo = hasUndo;
  final generation = ++_readerSnackBarGeneration;
  unawaited(
    controller.closed.then((_) {
      if (_readerSnackBarGeneration == generation) {
        _readerSnackBarHasUndo = false;
      }
    }),
  );
}

Future<void> _runReaderAction(
  BuildContext context,
  Future<void> Function() action, {
  VoidCallback? onSuccess,
  String Function(ApiException error)? apiErrorMessage,
  String networkErrorMessage = '离线状态下不支持写操作',
  String timeoutMessage = '请求超时，请稍后重试。',
}) async {
  try {
    await action();
    if (!context.mounted) {
      return;
    }
    onSuccess?.call();
  } on NetworkException {
    if (!context.mounted) {
      return;
    }
    _showReaderSnackBar(context, networkErrorMessage);
  } on ApiException catch (error) {
    if (!context.mounted) {
      return;
    }
    _showReaderSnackBar(
      context,
      apiErrorMessage?.call(error) ?? _entryActionApiErrorMessage(error),
    );
  } on TimeoutException {
    if (!context.mounted) {
      return;
    }
    _showReaderSnackBar(context, timeoutMessage);
  }
}

Future<void> _finishSelectedAndOpenNextWithUndo(
  BuildContext context,
  AppController controller,
) async {
  final wasOffline = !controller.state.isOnline;
  final beforeUnreadEntryIds = controller.state.snapshot.entries.values
      .where((entry) => !entry.isRead)
      .map((entry) => entry.id)
      .toSet();

  await _runReaderAction(
    context,
    controller.finishSelectedAndOpenNext,
    onSuccess: () {
      if (!context.mounted) {
        return;
      }
      final changedEntryIds = beforeUnreadEntryIds
          .where(
            (entryId) =>
                controller.state.snapshot.entries[entryId]?.isRead == true,
          )
          .toList(growable: false);
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.clearSnackBars();
      final snackBarController = messenger.showSnackBar(
        SnackBar(
          content: Text(changedEntryIds.isEmpty ? '已打开下一篇' : '已读完并打开下一篇'),
          action: changedEntryIds.isEmpty
              ? null
              : SnackBarAction(
                  label: '撤销',
                  onPressed: () {
                    if (!context.mounted) {
                      return;
                    }
                    _dismissCurrentReaderSnackBar(context);
                    unawaited(
                      _runReaderAction(
                        context,
                        () => _undoMarkedRead(
                          controller,
                          changedEntryIds,
                          wasOffline: wasOffline,
                        ),
                      ),
                    );
                  },
                ),
        ),
      );
      _trackReaderSnackBar(
        snackBarController,
        hasUndo: changedEntryIds.isNotEmpty,
      );
    },
  );
}

Future<void> _toggleSelectedReadWithUndo(
  BuildContext context,
  AppController controller,
) async {
  final entry = controller.selectedEntry;
  if (entry == null) {
    _showReaderSnackBar(context, '当前没有选中文章');
    return;
  }
  final wasOffline = !controller.state.isOnline;
  await _runReaderAction(
    context,
    controller.toggleSelectedRead,
    onSuccess: () => _showReaderUndoSnackBar(
      context,
      message: entry.isRead ? '已标记未读' : '已标记已读',
      undoAction: () =>
          _undoToggledRead(controller, entry, wasOffline: wasOffline),
    ),
  );
}

Future<void> _toggleSelectedSavedWithUndo(
  BuildContext context,
  AppController controller,
) async {
  final entry = controller.selectedEntry;
  if (entry == null) {
    _showReaderSnackBar(context, '当前没有选中文章');
    return;
  }
  final wasOffline = !controller.state.isOnline;
  await _runReaderAction(
    context,
    controller.toggleSelectedSaved,
    onSuccess: () => _showReaderUndoSnackBar(
      context,
      message: entry.isSaved ? '已移出稍后读' : '已加入稍后读',
      undoAction: () =>
          _undoToggledSaved(controller, entry, wasOffline: wasOffline),
    ),
  );
}

Future<void> _toggleSelectedNoiseWithUndo(
  BuildContext context,
  AppController controller,
) async {
  final entry = controller.selectedEntry;
  if (entry == null) {
    _showReaderSnackBar(context, '当前没有选中文章');
    return;
  }
  final wasOffline = !controller.state.isOnline;
  await _runReaderAction(
    context,
    controller.toggleSelectedNoise,
    onSuccess: () => _showReaderUndoSnackBar(
      context,
      message: entry.isNoise ? '已恢复 Feed' : '已移入噪音箱',
      undoAction: () =>
          _undoToggledNoise(controller, entry, wasOffline: wasOffline),
    ),
  );
}

void _showReaderUndoSnackBar(
  BuildContext context, {
  required String message,
  required Future<void> Function() undoAction,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.removeCurrentSnackBar();
  messenger.clearSnackBars();
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () {
          if (!context.mounted) {
            return;
          }
          _dismissCurrentReaderSnackBar(context);
          unawaited(_runReaderAction(context, undoAction));
        },
      ),
    ),
  );
  _trackReaderSnackBar(controller, hasUndo: true);
}

String _entryActionApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  if (error.isNotFound) {
    return '操作失败：文章已在服务端删除，请同步后重试';
  }
  if (error.isBadRequest) {
    return '操作失败：当前文章状态已变化，请刷新后重试';
  }
  return _apiFailureMessage('操作失败', error);
}

String _aiSettingsApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  final message = error.message;
  if (message == 'provider is not supported') {
    return 'AI 设置保存失败：当前服务端不支持这个 AI Provider，请刷新后重试';
  }
  if (error.isBadRequest) {
    return 'AI 设置保存失败：配置内容不合法，请检查后重试';
  }
  return _apiFailureMessage('AI 设置保存失败', error);
}

String _appearanceSettingsApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  final message = error.message;
  if (message == 'themeMode must be SYSTEM, LIGHT, or DARK') {
    return '外观设置保存失败：服务端不支持这个主题值，请刷新后重试';
  }
  if (error.isBadRequest) {
    return '外观设置保存失败：设置内容不合法，请刷新后重试';
  }
  return _apiFailureMessage('外观设置保存失败', error);
}

String _feedSettingsApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  final message = error.message;
  if (message == 'invalid default language') {
    return '默认语言保存失败：请输入有效的 BCP 47 语言标签';
  }
  if (error.isBadRequest) {
    return '默认语言保存失败：服务端暂时无法接受这个语言，请稍后重试';
  }
  return _apiFailureMessage('默认语言保存失败', error);
}

Future<void> _syncNowWithFeedback(
  BuildContext context,
  AppController controller,
) async {
  if (controller.state.busy) {
    return;
  }
  final pendingCountBeforeSync = controller.state.pendingSyncCount;
  final pendingDescriptionBeforeSync = controller.state.pendingSyncDescription;
  await controller.syncNow();
  if (!context.mounted || controller.state.errorMessage != null) {
    return;
  }
  _showReaderSnackBar(
    context,
    _syncSuccessMessage(pendingCountBeforeSync, pendingDescriptionBeforeSync),
  );
}

String _syncSuccessMessage(int pendingCount, String pendingDescription) {
  if (pendingCount <= 0) {
    return '已同步最新变化';
  }
  final description = _redactDiagnosticText(
    pendingDescription,
    emptyPlaceholder: '',
  ).trim();
  final detail = description.isEmpty ? '' : '：$description';
  return '已同步 $pendingCount 个待处理动作$detail';
}

String _syncActionLabelForState(AppState state) {
  return state.pendingSyncCount > 0 ? '同步待处理动作' : '拉取最新变化';
}

Future<void> _refreshSelectedEntryBodyWithFeedback(
  BuildContext context,
  AppController controller,
) async {
  await controller.openSelectedEntry();
  if (!context.mounted || controller.state.errorMessage != null) {
    return;
  }
  final contentHtml = controller.selectedEntry?.contentHtml?.trim();
  final message = contentHtml == null || contentHtml.isEmpty
      ? '正文仍未同步，可稍后重试或打开原文'
      : '正文已同步最新内容';
  _showReaderSnackBar(context, message);
}

Future<T?> _runReaderValue<T>(
  BuildContext context,
  Future<T> Function() action, {
  String Function(ApiException error)? apiErrorMessage,
  String networkErrorMessage = '离线状态下不支持写操作',
  String timeoutMessage = '请求超时，请稍后重试。',
}) async {
  try {
    return await action();
  } on NetworkException {
    if (!context.mounted) {
      return null;
    }
    _showReaderSnackBar(context, networkErrorMessage);
    return null;
  } on ApiException catch (error) {
    if (!context.mounted) {
      return null;
    }
    _showReaderSnackBar(
      context,
      apiErrorMessage?.call(error) ?? _entryActionApiErrorMessage(error),
    );
    return null;
  } on TimeoutException {
    if (!context.mounted) {
      return null;
    }
    _showReaderSnackBar(context, timeoutMessage);
    return null;
  }
}

Future<void> _undoMarkedRead(
  AppController controller,
  List<int> entryIds, {
  required bool wasOffline,
}) {
  return wasOffline
      ? controller.queueEntriesUnread(entryIds)
      : controller.markEntriesUnread(entryIds);
}

Future<void> _undoToggledRead(
  AppController controller,
  EntryRecord entry, {
  required bool wasOffline,
}) {
  return wasOffline
      ? controller.queueEntryReadState(entry.id, entry.isRead)
      : controller.toggleEntryRead(entry.id);
}

Future<void> _undoToggledSaved(
  AppController controller,
  EntryRecord entry, {
  required bool wasOffline,
}) {
  return wasOffline
      ? controller.queueEntrySavedState(entry.id, entry.isSaved)
      : controller.toggleEntrySaved(entry.id);
}

Future<void> _undoToggledNoise(
  AppController controller,
  EntryRecord entry, {
  required bool wasOffline,
}) {
  return wasOffline
      ? controller.queueEntryNoiseState(entry.id, entry.isNoise)
      : controller.toggleEntryNoise(entry.id);
}

void _showShortcutHelpDialog(BuildContext context) {
  final shortcutGroups = [
    (
      title: '导航与搜索',
      shortcuts: [
        (keys: 'J / ↓', action: '下一篇'),
        (keys: 'K / ↑', action: '上一篇'),
        (keys: 'Shift+J / K', action: '跳到下一篇 / 上一篇未读'),
        (keys: 'Home / End', action: '跳到首尾'),
        (keys: 'Shift+H / L', action: '跳到首篇 / 末篇未读'),
        (keys: 'Enter / O', action: '打开正文并标记已读'),
        (keys: '1-6', action: '切换主要入口'),
        (keys: '/', action: '搜索'),
        (keys: 'Esc', action: '清空当前搜索 / 筛选'),
      ],
    ),
    (
      title: '阅读处理',
      shortcuts: [
        (keys: 'S', action: '稍后读'),
        (keys: 'L', action: '稍后读并继续'),
        (keys: 'M', action: '已读 / 未读'),
        (keys: 'E', action: '处理到当前'),
        (keys: 'A', action: '当前列表已读'),
        (keys: 'X', action: '移入噪音箱并继续'),
        (keys: 'N', action: '读完下一篇'),
        (keys: 'U', action: '只看未读'),
        (keys: 'P', action: '继续阅读'),
        (keys: 'Z', action: '切换队列排序'),
        (keys: 'D', action: '切换列表密度'),
        (keys: 'Shift+D', action: '折叠当前日期'),
      ],
    ),
    (
      title: '复制与 AI',
      shortcuts: [
        (keys: 'V', action: '打开原文'),
        (keys: 'C', action: '复制原文链接'),
        (keys: 'Shift+C', action: '复制 AI 总结'),
        (keys: 'Q', action: '复制文章引用'),
        (keys: 'Shift+Q', action: '复制阅读笔记'),
        (keys: 'I', action: '重试 AI'),
        (keys: 'T', action: '双语翻译'),
        (keys: 'Shift+T', action: '复制双语译文'),
      ],
    ),
    (
      title: '排版',
      shortcuts: [
        (keys: '= / -', action: '调整字号'),
        (keys: '[ / ]', action: '调整行距'),
        (keys: 'W', action: '切换正文宽度'),
        (keys: '0', action: '恢复默认排版'),
      ],
    ),
    (
      title: '订阅与同步',
      shortcuts: [
        (keys: 'G', action: '添加订阅源'),
        (keys: 'B', action: '导入 OPML'),
        (keys: 'F', action: '导出 OPML'),
        (keys: 'R', action: '刷新当前范围 / 全部'),
        (keys: 'Y', action: '同步待处理动作 / 拉取最新变化'),
        (keys: 'H', action: '打开帮助面板'),
      ],
    ),
  ];

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey<String>('shortcut-help-dialog'),
      title: const Text('快捷键帮助'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final group in shortcutGroups) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    group.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (final shortcut in group.shortcuts)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 116,
                                  child: Text(
                                    shortcut.keys,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Expanded(child: Text(shortcut.action)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Key _unreadBadgeKey(String surface, AppSection section) {
  return ValueKey<String>('$surface-${section.name}-unread-badge');
}

class _NavigationIconWithBadge extends StatelessWidget {
  const _NavigationIconWithBadge({
    required this.icon,
    required this.count,
    required this.badgeKey,
  });

  final IconData icon;
  final int count;
  final Key badgeKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon),
          if (count > 0)
            Positioned(
              top: -2,
              right: 0,
              child: _UnreadBadge(key: badgeKey, count: count),
            ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count > 99 ? '99+' : count.toString();
    return Semantics(
      label: '$label 篇未读',
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: EdgeInsets.symmetric(horizontal: label.length > 1 ? 5 : 0),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: theme.colorScheme.error,
          shape: const StadiumBorder(),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onError,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final totalUnread = state.snapshot.sources.fold<int>(
      0,
      (sum, source) => sum + source.unreadCount,
    );
    final items =
        <({AppSection section, IconData icon, String label, int unreadCount})>[
          (
            section: AppSection.feed,
            icon: Icons.article_outlined,
            label: 'Feed',
            unreadCount: controller.unreadCountForSection(AppSection.feed),
          ),
          (
            section: AppSection.saved,
            icon: Icons.bookmark_border_rounded,
            label: '稍后读',
            unreadCount: controller.unreadCountForSection(AppSection.saved),
          ),
          (
            section: AppSection.noise,
            icon: Icons.filter_alt_outlined,
            label: '噪音箱',
            unreadCount: controller.unreadCountForSection(AppSection.noise),
          ),
          (
            section: AppSection.sources,
            icon: Icons.rss_feed_rounded,
            label: '订阅源',
            unreadCount: 0,
          ),
          (
            section: AppSection.settings,
            icon: Icons.tune_rounded,
            label: '设置',
            unreadCount: 0,
          ),
          (
            section: AppSection.account,
            icon: Icons.person_outline_rounded,
            label: '账号',
            unreadCount: 0,
          ),
        ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            alignment: Alignment.center,
            child: Text(
              totalUnread.toString(),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 20),
          for (final item in items) ...[
            _SidebarButton(
              selected:
                  state.section == item.section ||
                  (item.section == AppSection.sources &&
                      state.section == AppSection.sourceEntries),
              icon: item.icon,
              label: item.label,
              unreadCount: item.unreadCount,
              badgeKey: _unreadBadgeKey('desktop', item.section),
              onTap: () => controller.selectSection(item.section),
            ),
            const SizedBox(height: 10),
          ],
          const Spacer(),
          IconButton(
            key: const ValueKey<String>('desktop-shortcut-help-button'),
            tooltip: '快捷键',
            onPressed: () => _showShortcutHelpDialog(context),
            icon: const Icon(Icons.keyboard_alt_outlined),
          ),
          IconButton(
            key: const ValueKey<String>('desktop-sync-button'),
            tooltip: _syncActionLabelForState(state),
            onPressed: state.busy
                ? null
                : () => unawaited(_syncNowWithFeedback(context, controller)),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.unreadCount,
    required this.badgeKey,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final int unreadCount;
  final Key badgeKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                _NavigationIconWithBadge(
                  icon: icon,
                  count: unreadCount,
                  badgeKey: badgeKey,
                ),
                const SizedBox(height: 4),
                Text(label, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopListPane extends StatelessWidget {
  const _DesktopListPane({
    required this.controller,
    required this.searchFocusNode,
    required this.onSearchEscapeHandlerChanged,
  });

  final AppController controller;
  final FocusNode searchFocusNode;
  final ValueChanged<VoidCallback?> onSearchEscapeHandlerChanged;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.section == AppSection.settings) {
      return _SettingsMenu(controller: controller);
    }
    if (state.section == AppSection.account) {
      return _AccountMenu(controller: controller);
    }
    if (state.section == AppSection.sources) {
      return _SourceListPane(
        controller: controller,
        mobile: false,
        searchFocusNode: searchFocusNode,
        onSearchEscapeHandlerChanged: onSearchEscapeHandlerChanged,
      );
    }
    return _EntryListPane(
      controller: controller,
      mobile: false,
      searchFocusNode: searchFocusNode,
    );
  }
}

class _DesktopDetailPane extends StatelessWidget {
  const _DesktopDetailPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state.section == AppSection.settings) {
      return _SettingsDetailPane(controller: controller);
    }
    if (state.section == AppSection.account) {
      return _AccountDetailPane(controller: controller);
    }
    if (state.section == AppSection.sources) {
      return Center(
        child: Text(
          '选择一个订阅源，进入该源的文章流。',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }
    final selectedEntry = controller.selectedEntry;
    return ArticleDetailView(
      entry: selectedEntry,
      sourceIconUrl: selectedEntry == null
          ? null
          : selectedEntry.sourceIconUrl ??
                state.snapshot.sourceById(selectedEntry.sourceId)?.iconUrl,
      showTranslations: state.showTranslations,
      busy: state.busy,
      isOnline: state.isOnline,
      queueStatus: controller.readingQueueStatusText,
      hasNextQueueEntry: controller.hasNextQueueEntry,
      readerPreferences: state.readerPreferences,
      onToggleTranslations: controller.toggleTranslations,
      onReaderPreferencesChanged: (preferences) {
        unawaited(controller.setReaderPreferences(preferences));
      },
      onReadingProgressChanged: (progress) {
        final entryId = controller.selectedEntry?.id;
        if (entryId != null) {
          controller.updateReadingProgress(entryId, progress);
        }
      },
      onOpenOriginal: () =>
          _openOriginalLink(context, controller.selectedEntry),
      onOpenContentLink: (url) => _openContentLink(context, url),
      onCopyLink: () => _copyOriginalLink(context, controller.selectedEntry),
      onCopyCitation: () =>
          _copyArticleCitation(context, controller.selectedEntry),
      onCopySummary: () =>
          _copyArticleSummary(context, controller.selectedEntry),
      onCopyTranslations: () =>
          _copyArticleTranslations(context, controller.selectedEntry),
      onCopyNote: () => _copyArticleNote(context, controller.selectedEntry),
      onToggleRead: () => _toggleSelectedReadWithUndo(context, controller),
      onToggleSaved: () => _toggleSelectedSavedWithUndo(context, controller),
      onToggleNoise: () => _toggleSelectedNoiseWithUndo(context, controller),
      onReprocessAi: () => _runReaderAction(
        context,
        controller.reprocessSelectedAi,
        onSuccess: () => _showReaderSnackBar(context, 'AI 已重新加入处理队列'),
      ),
      onRefreshEntry: () =>
          _refreshSelectedEntryBodyWithFeedback(context, controller),
      onFinishAndOpenNext: () =>
          _finishSelectedAndOpenNextWithUndo(context, controller),
    );
  }
}

class _MobileHomeBody extends StatefulWidget {
  const _MobileHomeBody({
    required this.controller,
    required this.searchFocusNode,
    required this.onSearchEscapeHandlerChanged,
  });

  final AppController controller;
  final FocusNode searchFocusNode;
  final ValueChanged<VoidCallback?> onSearchEscapeHandlerChanged;

  @override
  State<_MobileHomeBody> createState() => _MobileHomeBodyState();
}

class _MobileHomeBodyState extends State<_MobileHomeBody> {
  int _indexForSection(AppSection section) {
    return switch (section) {
      AppSection.feed => 0,
      AppSection.saved => 1,
      AppSection.noise => 2,
      AppSection.sources || AppSection.sourceEntries => 3,
      AppSection.settings || AppSection.account => 4,
    };
  }

  AppSection _sectionForIndex(int index) {
    return switch (index) {
      0 => AppSection.feed,
      1 => AppSection.saved,
      2 => AppSection.noise,
      3 => AppSection.sources,
      _ => AppSection.settings,
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state;
    final currentIndex = _indexForSection(state.section);
    final feedUnreadCount = controller.unreadCountForSection(AppSection.feed);
    final savedUnreadCount = controller.unreadCountForSection(AppSection.saved);
    final noiseUnreadCount = controller.unreadCountForSection(AppSection.noise);
    return Scaffold(
      body: switch (state.section) {
        AppSection.feed ||
        AppSection.saved ||
        AppSection.noise ||
        AppSection.sourceEntries => _EntryListPane(
          controller: controller,
          mobile: true,
          searchFocusNode: widget.searchFocusNode,
        ),
        AppSection.sources => _SourceListPane(
          controller: controller,
          mobile: true,
          searchFocusNode: widget.searchFocusNode,
          onSearchEscapeHandlerChanged: widget.onSearchEscapeHandlerChanged,
        ),
        AppSection.settings ||
        AppSection.account => _MobileSettingsPane(controller: controller),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) =>
            controller.selectSection(_sectionForIndex(index)),
        destinations: [
          NavigationDestination(
            icon: _NavigationIconWithBadge(
              icon: Icons.article_outlined,
              count: feedUnreadCount,
              badgeKey: _unreadBadgeKey('mobile', AppSection.feed),
            ),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: _NavigationIconWithBadge(
              icon: Icons.bookmark_border_rounded,
              count: savedUnreadCount,
              badgeKey: _unreadBadgeKey('mobile', AppSection.saved),
            ),
            selectedIcon: _NavigationIconWithBadge(
              icon: Icons.bookmark_rounded,
              count: savedUnreadCount,
              badgeKey: _unreadBadgeKey('mobile-selected', AppSection.saved),
            ),
            label: '稍后读',
          ),
          NavigationDestination(
            icon: _NavigationIconWithBadge(
              icon: Icons.filter_alt_outlined,
              count: noiseUnreadCount,
              badgeKey: _unreadBadgeKey('mobile', AppSection.noise),
            ),
            label: '噪音箱',
          ),
          NavigationDestination(
            icon: Icon(Icons.rss_feed_rounded),
            label: '订阅源',
          ),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: '设置'),
        ],
      ),
    );
  }
}

class _MobileSettingsPane extends StatelessWidget {
  const _MobileSettingsPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  ChoiceChip(
                    key: const ValueKey<String>('mobile-settings-account'),
                    selected: state.section == AppSection.account,
                    avatar: const Icon(Icons.person_outline_rounded, size: 16),
                    label: const Text('账号'),
                    onSelected: (_) =>
                        controller.selectSection(AppSection.account),
                  ),
                  const SizedBox(width: 8),
                  for (final section in SettingsSection.values) ...[
                    ChoiceChip(
                      key: ValueKey<String>(
                        'mobile-settings-section-${section.name}',
                      ),
                      selected:
                          state.section == AppSection.settings &&
                          state.settingsSection == section,
                      avatar: Icon(_settingsSectionIcon(section), size: 16),
                      label: Text(section.label),
                      onSelected: (_) {
                        controller.selectSection(AppSection.settings);
                        controller.changeSettingsSection(section);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: state.section == AppSection.account
              ? _AccountDetailPane(controller: controller)
              : _SettingsDetailPane(controller: controller),
        ),
      ],
    );
  }
}

IconData _settingsSectionIcon(SettingsSection section) {
  return switch (section) {
    SettingsSection.ai => Icons.auto_awesome_rounded,
    SettingsSection.appearance => Icons.palette_outlined,
    SettingsSection.feeds => Icons.rss_feed_rounded,
    SettingsSection.about => Icons.info_outline_rounded,
  };
}

class _EntryListPane extends StatelessWidget {
  const _EntryListPane({
    required this.controller,
    required this.mobile,
    required this.searchFocusNode,
  });

  final AppController controller;
  final bool mobile;
  final FocusNode searchFocusNode;

  Future<void> _showActionError(
    BuildContext context,
    Future<void> Function() action, {
    VoidCallback? onSuccess,
    String Function(ApiException error)? apiErrorMessage,
    String networkErrorMessage = '离线状态下不支持写操作',
    String timeoutMessage = '请求超时，请稍后重试。',
    bool showTimeoutSnackBar = true,
  }) async {
    try {
      await action();
      if (!context.mounted) {
        return;
      }
      onSuccess?.call();
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(networkErrorMessage)));
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage?.call(error) ?? _entryActionApiErrorMessage(error),
          ),
        ),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      if (!showTimeoutSnackBar) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(timeoutMessage)));
    }
  }

  Future<T?> _showActionValue<T>(
    BuildContext context,
    Future<T> Function() action, {
    String Function(ApiException error)? apiErrorMessage,
    String networkErrorMessage = '离线状态下不支持写操作',
    String timeoutMessage = '请求超时，请稍后重试。',
  }) async {
    try {
      return await action();
    } on NetworkException {
      if (!context.mounted) {
        return null;
      }
      _showReaderSnackBar(context, networkErrorMessage);
      return null;
    } on ApiException catch (error) {
      if (!context.mounted) {
        return null;
      }
      _showReaderSnackBar(
        context,
        apiErrorMessage?.call(error) ?? _entryActionApiErrorMessage(error),
      );
      return null;
    } on TimeoutException {
      if (!context.mounted) {
        return null;
      }
      _showReaderSnackBar(context, timeoutMessage);
      return null;
    }
  }

  Future<void> _refreshAllWithFeedback(BuildContext context) async {
    final result = await _showActionValue<RefreshAcceptedResult>(
      context,
      controller.refreshAll,
      apiErrorMessage: _sourceRefreshApiErrorMessage,
      networkErrorMessage: _refreshAllNetworkMessage,
      timeoutMessage: _refreshAllTimeoutMessage,
    );
    if (!context.mounted || result == null) {
      return;
    }
    _showReaderSnackBar(context, _refreshAllAcceptedMessage(result));
  }

  Future<void> _refreshSourceWithFeedback(
    BuildContext context,
    FeedSource source,
  ) async {
    final result = await _showActionValue<RefreshAcceptedResult>(
      context,
      () => controller.refreshSource(source.id),
      apiErrorMessage: _sourceRefreshApiErrorMessage,
      networkErrorMessage: _refreshSourceNetworkMessage,
      timeoutMessage: _refreshSourceTimeoutMessage,
    );
    if (!context.mounted || result == null) {
      return;
    }
    _showReaderSnackBar(context, _refreshSourceAcceptedMessage(result, source));
  }

  Future<void> _refreshCurrentListWithFeedback(BuildContext context) async {
    final state = controller.state;
    final sourceId = state.section == AppSection.sourceEntries
        ? state.selectedSourceId
        : state.entrySourceFilterId;
    if (sourceId != null) {
      final result = await _showActionValue<RefreshAcceptedResult>(
        context,
        () => controller.refreshSource(sourceId),
        apiErrorMessage: _sourceRefreshApiErrorMessage,
        networkErrorMessage: _refreshSourceNetworkMessage,
        timeoutMessage: _refreshSourceTimeoutMessage,
      );
      if (!context.mounted || result == null) {
        return;
      }
      _showReaderSnackBar(
        context,
        _refreshCurrentSourceAcceptedMessage(result),
      );
      return;
    }

    final folder = state.entryFolderFilter;
    if (folder != null) {
      final sourceIds = state.snapshot.sources
          .where(
            (source) => source.enabled && _sourceFolderName(source) == folder,
          )
          .map((source) => source.id)
          .toList(growable: false);
      final result = await _showActionValue<RefreshAcceptedResult>(
        context,
        () => controller.refreshSources(sourceIds),
        apiErrorMessage: _sourceRefreshApiErrorMessage,
        networkErrorMessage: _refreshVisibleSourcesNetworkMessage,
        timeoutMessage: _refreshVisibleSourcesTimeoutMessage,
      );
      if (!context.mounted || result == null) {
        return;
      }
      _showReaderSnackBar(
        context,
        _refreshCurrentFolderAcceptedMessage(result),
      );
      return;
    }

    await _refreshAllWithFeedback(context);
  }

  bool _refreshTargetsCurrentScope() {
    final state = controller.state;
    return state.section == AppSection.sourceEntries ||
        state.entrySourceFilterId != null ||
        state.entryFolderFilter != null;
  }

  String _refreshCurrentListLabel() {
    return _refreshTargetsCurrentScope() ? '刷新当前范围' : '刷新全部';
  }

  bool _hasActiveEntryFilters({bool includeSearch = true}) {
    final state = controller.state;
    return (includeSearch && state.searchQuery.trim().isNotEmpty) ||
        state.unreadOnly ||
        state.inProgressOnly ||
        state.entrySourceFilterId != null ||
        state.entryFolderFilter != null;
  }

  void _clearEntrySearchAndFilters() {
    final state = controller.state;
    if (state.searchQuery.trim().isNotEmpty) {
      controller.setSearchQuery('');
    }
    if (state.unreadOnly) {
      controller.toggleUnreadOnly(false);
    }
    if (state.inProgressOnly) {
      controller.toggleInProgressOnly(false);
    }
    if (state.entrySourceFilterId != null) {
      controller.setEntrySourceFilter(null);
    }
    if (state.entryFolderFilter != null) {
      controller.setEntryFolderFilter(null);
    }
  }

  void _showUndoSnackBar(
    BuildContext context, {
    required String message,
    required Future<void> Function() undoAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (!context.mounted) {
              return;
            }
            _dismissCurrentReaderSnackBar(context);
            unawaited(_showActionError(context, undoAction));
          },
        ),
      ),
    );
    _trackReaderSnackBar(controller, hasUndo: true);
  }

  PopupMenuButton<String> _buildSourcePageActions(
    BuildContext context,
    FeedSource source,
  ) {
    return PopupMenuButton<String>(
      key: const ValueKey<String>('source-page-source-actions'),
      tooltip: '订阅源操作',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (value) {
        switch (value) {
          case 'mark-source-read':
            unawaited(_markSourceRead(context, source));
          case 'refresh':
            unawaited(_refreshSourceWithFeedback(context, source));
          case 'copy-rss-url':
            unawaited(_copySourceRssUrl(context, source));
          case 'copy-source-diagnostics':
            unawaited(_copySourceDiagnostics(context, source));
          case 'open-site':
            unawaited(_openSourceSite(context, source));
          case 'toggle-enabled':
            unawaited(_toggleSourceEnabled(context, source));
          case 'edit':
            unawaited(_showEditSourceDialog(context, source));
          case 'delete':
            unawaited(_deleteSource(context, source));
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'mark-source-read',
          enabled: source.unreadCount > 0,
          child: const Text('标记此源已读'),
        ),
        const PopupMenuItem(value: 'refresh', child: Text('刷新此源')),
        const PopupMenuItem(value: 'copy-rss-url', child: Text('复制 Feed URL')),
        const PopupMenuItem(
          value: 'copy-source-diagnostics',
          child: Text('复制源诊断'),
        ),
        PopupMenuItem(
          value: 'open-site',
          enabled: (source.siteUrl ?? '').trim().isNotEmpty,
          child: const Text('打开站点'),
        ),
        PopupMenuItem(
          value: 'toggle-enabled',
          child: Text(source.enabled ? '停用自动抓取' : '启用自动抓取'),
        ),
        const PopupMenuItem(value: 'edit', child: Text('编辑订阅源')),
        const PopupMenuItem(value: 'delete', child: Text('删除订阅源')),
      ],
    );
  }

  Future<void> _deleteSource(BuildContext context, FeedSource source) async {
    final sourceName = _redactDiagnosticText(source.name);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除订阅源'),
            content: Text('删除 $sourceName 后，该源历史文章也会一并从本地清理。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      await controller.deleteSource(source.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 $sourceName')));
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceDeleteApiErrorMessage(error))),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前网络不可用，已切换为离线阅读模式，可稍后重试删除订阅源')),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除请求超时，请稍后重试')));
    }
  }

  Future<void> _showEditSourceDialog(
    BuildContext context,
    FeedSource source,
  ) async {
    final updated = await showDialog<FeedSource>(
      context: context,
      builder: (context) => _EditSourceDialog(
        source: source,
        folderSuggestions: _sourceFolderSuggestions(
          controller.state.snapshot.sources,
        ),
      ),
    );

    if (updated == null || !context.mounted) {
      return;
    }

    try {
      await controller.updateSource(updated);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已更新订阅源')));
    } on SourceRefreshAfterSaveException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceRefreshAfterSaveMessage(error))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sourceSaveApiErrorMessage(error, SourceSaveAction.update),
          ),
        ),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前网络不可用，已切换为离线阅读模式，可稍后重试编辑订阅源')),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('编辑请求超时，请稍后重试')));
    }
  }

  Future<void> _toggleSourceEnabled(
    BuildContext context,
    FeedSource source,
  ) async {
    final enabled = !source.enabled;
    final sourceName = _redactDiagnosticText(source.name);
    try {
      await controller.updateSource(source.copyWith(enabled: enabled));
      if (!context.mounted) {
        return;
      }
      _showReaderSnackBar(
        context,
        enabled ? '已启用 $sourceName' : '已停用 $sourceName',
      );
    } on SourceRefreshAfterSaveException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceRefreshAfterSaveMessage(error))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sourceSaveApiErrorMessage(error, SourceSaveAction.update),
          ),
        ),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下无法修改订阅源')));
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('修改请求超时，请稍后重试')));
    }
  }

  Future<void> _markSourceRead(BuildContext context, FeedSource source) async {
    final wasOffline = !controller.state.isOnline;
    final cachedUnreadEntryIds = _cachedUnreadEntryIdsForSource(source.id);
    final confirmed = await _confirmBulkSourceRead(
      context,
      title: '标记订阅源已读',
      message: _bulkReadConfirmMessage(
        _redactDiagnosticText(source.name),
        totalUnreadCount: source.unreadCount,
        cachedUnreadCount: cachedUnreadEntryIds.length,
        wasOffline: wasOffline,
      ),
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      await controller.markSourceRead(source.id);
      if (!context.mounted) {
        return;
      }
      _showBulkReadSuccessSnackBar(
        context,
        scopeName: _redactDiagnosticText(source.name),
        totalUnreadCount: source.unreadCount,
        wasOffline: wasOffline,
        cachedUnreadEntryIds: cachedUnreadEntryIds,
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_bulkReadApiErrorMessage(error))));
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下无法批量标记已读')));
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('批量标记请求超时，请稍后重试')));
    }
  }

  String _bulkReadApiErrorMessage(ApiException error) {
    final authMessage = _authExpiredApiErrorMessage(error);
    if (authMessage != null) {
      return authMessage;
    }
    if (error.isNotFound) {
      return '批量标记失败：阅读范围已变化，请同步刷新后重试';
    }
    if (error.isBadRequest) {
      return '批量标记失败：当前阅读范围无法处理，请同步刷新后重试';
    }
    return _apiFailureMessage('批量标记失败', error);
  }

  String _bulkReadConfirmMessage(
    String scopeName, {
    required int totalUnreadCount,
    required int cachedUnreadCount,
    required bool wasOffline,
  }) {
    if (!wasOffline) {
      return '$scopeName 的 $totalUnreadCount 篇未读文章会标记为已读。';
    }
    if (cachedUnreadCount == 0) {
      return '离线时 $scopeName 暂无已缓存未读文章可标记；恢复在线后可处理全部未读。';
    }
    return '离线时仅会将 $scopeName 已缓存的 $cachedUnreadCount 篇未读文章加入待同步。';
  }

  void _showBulkReadSuccessSnackBar(
    BuildContext context, {
    required String scopeName,
    required int totalUnreadCount,
    required bool wasOffline,
    required List<int> cachedUnreadEntryIds,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final canUndo = wasOffline
        ? cachedUnreadEntryIds.isNotEmpty
        : cachedUnreadEntryIds.isNotEmpty &&
              cachedUnreadEntryIds.length == totalUnreadCount;
    final snackBarController = messenger.showSnackBar(
      SnackBar(
        content: Text(
          wasOffline
              ? _offlineQueuedReadMessage(
                  scopeName,
                  cachedUnreadEntryIds.length,
                )
              : '已将 $scopeName 标记为已读',
        ),
        action: canUndo
            ? SnackBarAction(
                label: '撤销',
                onPressed: () {
                  _dismissCurrentReaderSnackBar(context);
                  unawaited(
                    _undoBulkRead(
                      context,
                      cachedUnreadEntryIds,
                      wasOffline: wasOffline,
                    ),
                  );
                },
              )
            : null,
      ),
    );
    _trackReaderSnackBar(snackBarController, hasUndo: canUndo);
  }

  Future<void> _undoBulkRead(
    BuildContext context,
    List<int> entryIds, {
    required bool wasOffline,
  }) async {
    try {
      if (wasOffline) {
        await controller.queueEntriesUnread(entryIds);
      } else {
        await controller.markEntriesUnread(entryIds);
      }
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下不支持写操作')));
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_entryActionApiErrorMessage(error))),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请求超时，请稍后重试。')));
    }
  }

  List<int> _cachedUnreadEntryIdsForSource(int sourceId) {
    return controller.state.snapshot.entries.values
        .where((entry) => entry.sourceId == sourceId && !entry.isRead)
        .map((entry) => entry.id)
        .toList(growable: false);
  }

  String _offlineQueuedReadMessage(String scopeName, int cachedUnreadCount) {
    if (cachedUnreadCount == 0) {
      return '$scopeName 暂无已缓存未读文章可离线标记';
    }
    return '已将 $scopeName 的 $cachedUnreadCount 篇已缓存文章加入待同步';
  }

  Future<bool> _confirmBulkSourceRead(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openMobileDetail(
    BuildContext context,
    EntryRecord entry,
  ) async {
    await controller.openEntry(entry.id);
    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Consumer(
          builder: (context, ref, _) {
            final latestController = ref.watch(appControllerProvider);
            final selectedEntry = latestController.selectedEntry;
            final sourceIconUrl = selectedEntry == null
                ? null
                : selectedEntry.sourceIconUrl ??
                      latestController.state.snapshot
                          .sourceById(selectedEntry.sourceId)
                          ?.iconUrl;
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  _redactDiagnosticText(
                    selectedEntry?.sourceName ?? entry.sourceName,
                  ),
                ),
              ),
              body: ArticleDetailView(
                entry: selectedEntry,
                sourceIconUrl: sourceIconUrl,
                showTranslations: latestController.state.showTranslations,
                busy: latestController.state.busy,
                isOnline: latestController.state.isOnline,
                queueStatus: latestController.readingQueueStatusText,
                hasNextQueueEntry: latestController.hasNextQueueEntry,
                readerPreferences: latestController.state.readerPreferences,
                onToggleTranslations: latestController.toggleTranslations,
                onReaderPreferencesChanged: (preferences) {
                  unawaited(latestController.setReaderPreferences(preferences));
                },
                onReadingProgressChanged: (progress) {
                  final entryId = latestController.selectedEntry?.id;
                  if (entryId != null) {
                    latestController.updateReadingProgress(entryId, progress);
                  }
                },
                onOpenOriginal: () =>
                    _openOriginalLink(context, latestController.selectedEntry),
                onOpenContentLink: (url) => _openContentLink(context, url),
                onCopyLink: () =>
                    _copyOriginalLink(context, latestController.selectedEntry),
                onCopyCitation: () => _copyArticleCitation(
                  context,
                  latestController.selectedEntry,
                ),
                onCopySummary: () => _copyArticleSummary(
                  context,
                  latestController.selectedEntry,
                ),
                onCopyTranslations: () => _copyArticleTranslations(
                  context,
                  latestController.selectedEntry,
                ),
                onCopyNote: () =>
                    _copyArticleNote(context, latestController.selectedEntry),
                onToggleRead: () =>
                    _toggleSelectedReadWithUndo(context, latestController),
                onToggleSaved: () =>
                    _toggleSelectedSavedWithUndo(context, latestController),
                onToggleNoise: () =>
                    _toggleSelectedNoiseWithUndo(context, latestController),
                onReprocessAi: () => _runReaderAction(
                  context,
                  latestController.reprocessSelectedAi,
                  onSuccess: () => _showReaderSnackBar(context, 'AI 已重新加入处理队列'),
                ),
                onRefreshEntry: () => _refreshSelectedEntryBodyWithFeedback(
                  context,
                  latestController,
                ),
                onFinishAndOpenNext: () => _finishSelectedAndOpenNextWithUndo(
                  context,
                  latestController,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmMarkRead(
    BuildContext context, {
    required String title,
    required String message,
    required List<int> entryIds,
  }) async {
    if (entryIds.isEmpty) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !context.mounted) {
      return;
    }

    final wasOffline = !controller.state.isOnline;
    await _showActionError(
      context,
      () => controller.markEntriesRead(entryIds),
      onSuccess: () {
        final snackBarController = ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已将 ${entryIds.length} 篇标记为已读'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () {
                if (!context.mounted) {
                  return;
                }
                _dismissCurrentReaderSnackBar(context);
                unawaited(
                  _showActionError(
                    context,
                    () => _undoMarkedRead(
                      controller,
                      entryIds,
                      wasOffline: wasOffline,
                    ),
                  ),
                );
              },
            ),
          ),
        );
        _trackReaderSnackBar(snackBarController, hasUndo: true);
      },
    );
  }

  Future<void> _confirmMarkVisibleRead(BuildContext context) {
    final entryIds = controller.visibleUnreadEntryIds;
    return _confirmMarkRead(
      context,
      title: '标记当前已读',
      message: '当前可见的 ${entryIds.length} 篇未读文章会标记为已读。',
      entryIds: entryIds,
    );
  }

  void _toggleEntryDateSectionCollapsed(String sectionKey) {
    final collapsedSections = controller
        .state
        .readerPreferences
        .collapsedEntryDateSections
        .toSet();
    if (!collapsedSections.add(sectionKey)) {
      collapsedSections.remove(sectionKey);
    }
    controller.setCollapsedEntryDateSections(collapsedSections);
  }

  String _entryTileSemanticsLabel(EntryRecord entry) {
    final parts = <String>[
      '文章',
      entry.title,
      '来源 ${_redactDiagnosticText(entry.sourceName)}',
      entry.isRead ? '已读' : '未读',
    ];

    if (entry.isSaved) {
      parts.add('稍后读');
    }
    if (entry.isNoise) {
      parts.add('噪音箱');
    }

    final readingProgress = entry.readingProgress.clamp(0, 1).toDouble();
    if (entry.isInProgress) {
      parts.add('阅读进度 ${(readingProgress * 100).round()}%');
      final remainingMinutes = ReadingMetrics.estimateRemainingReadingMinutes(
        entry,
      );
      if (remainingMinutes > 0) {
        parts.add(ReadingMetrics.remainingReadingTimeLabel(entry));
      }
    } else {
      parts.add(ReadingMetrics.readingTimeLabel(entry));
    }

    parts.add('点击打开');
    return parts.join('，');
  }

  Widget _buildEntryTile(
    BuildContext context, {
    required EntryRecord entry,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final compact =
        controller.state.readerPreferences.entryListDensity ==
        EntryListDensity.compact;
    final hasCover = (entry.coverImageUrl ?? '').trim().isNotEmpty;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: entry.isRead ? FontWeight.w600 : FontWeight.w800,
      height: compact ? 1.18 : 1.25,
    );
    final readingProgress = entry.readingProgress.clamp(0, 1).toDouble();
    final readingProgressPercent = (readingProgress * 100).round();
    final remainingReadingMinutes =
        ReadingMetrics.estimateRemainingReadingMinutes(entry);
    final readingProgressLabel = remainingReadingMinutes > 0
        ? '${entry.title} 阅读进度，${ReadingMetrics.remainingReadingTimeLabel(entry)}'
        : '${entry.title} 阅读进度';
    final sourceIconUrl =
        entry.sourceIconUrl ??
        controller.state.snapshot.sourceById(entry.sourceId)?.iconUrl;

    return Semantics(
      key: ValueKey<String>('entry-card-${entry.id}-semantics'),
      button: true,
      selected: selected && !mobile,
      label: _entryTileSemanticsLabel(entry),
      child: Card(
        color: selected && !mobile
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.54)
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: () => mobile
              ? _openMobileDetail(context, entry)
              : controller.openEntry(entry.id),
          child: Padding(
            padding: EdgeInsets.all(compact ? 10 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasCover) ...[
                  _EntryCoverImage(
                    imageUrl: entry.coverImageUrl!,
                    compact: mobile || compact,
                  ),
                  SizedBox(width: compact ? 10 : 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              entry.title,
                              maxLines: compact ? 2 : 3,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          ),
                          if (!entry.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, top: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (entry.isSaved) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.bookmark_rounded,
                              size: 16,
                              color: theme.colorScheme.secondary,
                            ),
                          ],
                          const SizedBox(width: 6),
                          _EntryQuickActions(
                            entry: entry,
                            busy: controller.state.busy,
                            compactActions: mobile || compact,
                            showReprocessAi: _canReprocessEntryAi(
                              entry.aiProcessingState,
                            ),
                            onToggleSaved: () {
                              final wasOffline = !controller.state.isOnline;
                              unawaited(
                                _showActionError(
                                  context,
                                  () => controller.toggleEntrySaved(entry.id),
                                  onSuccess: () {
                                    _showUndoSnackBar(
                                      context,
                                      message: entry.isSaved
                                          ? '已移出稍后读'
                                          : '已加入稍后读',
                                      undoAction: () => _undoToggledSaved(
                                        controller,
                                        entry,
                                        wasOffline: wasOffline,
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                            onToggleRead: () {
                              final wasOffline = !controller.state.isOnline;
                              unawaited(
                                _showActionError(
                                  context,
                                  () => controller.toggleEntryRead(entry.id),
                                  onSuccess: () {
                                    _showUndoSnackBar(
                                      context,
                                      message: entry.isRead ? '已标记未读' : '已标记已读',
                                      undoAction: () => _undoToggledRead(
                                        controller,
                                        entry,
                                        wasOffline: wasOffline,
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                            onToggleNoise: () {
                              final wasOffline = !controller.state.isOnline;
                              unawaited(
                                _showActionError(
                                  context,
                                  () => controller.toggleEntryNoise(entry.id),
                                  onSuccess: () {
                                    _showUndoSnackBar(
                                      context,
                                      message: entry.isNoise
                                          ? '已恢复 Feed'
                                          : '已移入噪音箱',
                                      undoAction: () => _undoToggledNoise(
                                        controller,
                                        entry,
                                        wasOffline: wasOffline,
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                            onOpenOriginal: () {
                              unawaited(_openOriginalLink(context, entry));
                            },
                            onCopyLink: () {
                              unawaited(_copyOriginalLink(context, entry));
                            },
                            onCopyCitation: () {
                              unawaited(_copyArticleCitation(context, entry));
                            },
                            onCopyNote: () {
                              unawaited(_copyArticleNote(context, entry));
                            },
                            onReprocessAi: controller.state.isOnline
                                ? () {
                                    unawaited(
                                      _showActionError(
                                        context,
                                        () => controller.reprocessEntryAi(
                                          entry.id,
                                        ),
                                        onSuccess: () => _showReaderSnackBar(
                                          context,
                                          'AI 已重新加入处理队列',
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 6 : 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _EntrySourceLabel(
                            sourceName: _redactDiagnosticText(entry.sourceName),
                            iconUrl: sourceIconUrl,
                            imageKey: ValueKey<String>(
                              'entry-source-icon-${entry.id}',
                            ),
                            fallbackKey: ValueKey<String>(
                              'entry-source-icon-fallback-${entry.id}',
                            ),
                          ),
                          if ((entry.author ?? '').trim().isNotEmpty)
                            _MetaBadge(
                              icon: Icons.person_outline_rounded,
                              label: entry.author!.trim(),
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          Text(
                            AppFormatters.listDate(entry.publishedAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          _MetaBadge(
                            icon: Icons.schedule_rounded,
                            label: entry.isInProgress
                                ? ReadingMetrics.remainingReadingTimeLabel(
                                    entry,
                                  )
                                : ReadingMetrics.readingTimeLabel(entry),
                            color: theme.colorScheme.secondary,
                          ),
                          if (entry.isNoise)
                            _MetaBadge(
                              icon: Icons.block_rounded,
                              label: '噪音',
                              color: theme.colorScheme.error,
                            ),
                          if (entry.foreign)
                            _MetaBadge(
                              icon: Icons.translate_rounded,
                              label: '外文',
                              color: theme.colorScheme.tertiary,
                            ),
                          if (entry.aiProcessingState !=
                              EntryAiProcessingState.none)
                            _MetaBadge(
                              icon: _entryAiProcessingIcon(
                                entry.aiProcessingState,
                              ),
                              label: _entryAiProcessingLabel(
                                entry.aiProcessingState,
                              ),
                              color: _entryAiProcessingColor(
                                theme,
                                entry.aiProcessingState,
                              ),
                            ),
                        ],
                      ),
                      if (!compact &&
                          (entry.summary ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          entry.summary!,
                          maxLines: hasCover ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: entry.isRead ? 0.74 : 0.9,
                            ),
                          ),
                        ),
                      ],
                      if (readingProgress > 0.02 && readingProgress < 0.98) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: readingProgress,
                            minHeight: 3,
                            semanticsLabel: readingProgressLabel,
                            semanticsValue: '$readingProgressPercent',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final state = controller.state;
    if (state.searchQuery.trim().isNotEmpty) {
      final hasStackedFilters = _hasActiveEntryFilters(includeSearch: false);
      return _EntryEmptyState(
        icon: Icons.search_off_rounded,
        title: '没有匹配的文章',
        actionIcon: Icons.close_rounded,
        actionLabel: '清空搜索',
        onAction: () => controller.setSearchQuery(''),
        secondaryActionIcon: hasStackedFilters
            ? Icons.filter_alt_off_rounded
            : Icons.refresh_rounded,
        secondaryActionLabel: hasStackedFilters ? '清空全部筛选' : '刷新当前范围',
        onSecondaryAction: hasStackedFilters
            ? _clearEntrySearchAndFilters
            : state.busy || !state.isOnline
            ? null
            : () => unawaited(_refreshCurrentListWithFeedback(context)),
        tertiaryActionIcon: hasStackedFilters ? Icons.refresh_rounded : null,
        tertiaryActionLabel: hasStackedFilters ? '刷新当前范围' : null,
        onTertiaryAction: hasStackedFilters && !state.busy && state.isOnline
            ? () => unawaited(_refreshCurrentListWithFeedback(context))
            : null,
      );
    }

    if (state.inProgressOnly) {
      return _EntryEmptyState(
        icon: Icons.auto_stories_outlined,
        title: '没有读到一半的文章',
        actionIcon: Icons.all_inbox_rounded,
        actionLabel: '查看全部',
        onAction: () => controller.toggleInProgressOnly(false),
      );
    }

    if (state.unreadOnly) {
      return _EntryEmptyState(
        icon: Icons.mark_email_read_outlined,
        title: '没有未读文章',
        actionIcon: Icons.all_inbox_rounded,
        actionLabel: '查看全部',
        onAction: () => controller.toggleUnreadOnly(false),
        secondaryActionIcon: Icons.refresh_rounded,
        secondaryActionLabel: '刷新当前范围',
        onSecondaryAction: state.busy || !state.isOnline
            ? null
            : () => unawaited(_refreshCurrentListWithFeedback(context)),
      );
    }

    if (state.entrySourceFilterId != null) {
      return _EntryEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '这个来源当前没有文章',
        actionIcon: Icons.all_inbox_rounded,
        actionLabel: '查看全部来源',
        onAction: () => controller.setEntrySourceFilter(null),
        secondaryActionIcon: Icons.refresh_rounded,
        secondaryActionLabel: '刷新当前范围',
        onSecondaryAction: state.busy || !state.isOnline
            ? null
            : () => unawaited(_refreshCurrentListWithFeedback(context)),
      );
    }

    if (state.entryFolderFilter != null) {
      return _EntryEmptyState(
        icon: Icons.folder_off_outlined,
        title: '这个文件夹当前没有文章',
        actionIcon: Icons.all_inbox_rounded,
        actionLabel: '查看全部文件夹',
        onAction: () => controller.setEntryFolderFilter(null),
        secondaryActionIcon: Icons.refresh_rounded,
        secondaryActionLabel: '刷新当前范围',
        onSecondaryAction: state.busy || !state.isOnline
            ? null
            : () => unawaited(_refreshCurrentListWithFeedback(context)),
      );
    }

    if (state.snapshot.sources.isEmpty) {
      return _EntryEmptyState(
        icon: Icons.rss_feed_rounded,
        title: '还没有订阅源',
        actionIcon: Icons.add_rounded,
        actionLabel: '管理订阅源',
        onAction: () => controller.selectSection(AppSection.sources),
      );
    }

    final selectedSource = controller.selectedSource;
    if (state.section == AppSection.sourceEntries && selectedSource != null) {
      return _EntryEmptyState(
        icon: Icons.rss_feed_rounded,
        title: '这个订阅源还没有文章',
        actionIcon: Icons.refresh_rounded,
        actionLabel: '刷新此源',
        onAction: state.busy || !state.isOnline
            ? null
            : () => unawaited(
                _refreshSourceWithFeedback(context, selectedSource),
              ),
      );
    }

    if (state.section == AppSection.saved) {
      return _EntryEmptyState(
        icon: Icons.bookmark_border_rounded,
        title: '还没有稍后读文章',
        actionIcon: Icons.article_outlined,
        actionLabel: '回到 Feed',
        onAction: () => controller.selectSection(AppSection.feed),
      );
    }

    if (state.section == AppSection.noise) {
      return _EntryEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: '噪音箱是空的',
        actionIcon: Icons.article_outlined,
        actionLabel: '回到 Feed',
        onAction: () => controller.selectSection(AppSection.feed),
      );
    }

    return _EntryEmptyState(
      icon: Icons.rss_feed_rounded,
      title: '当前没有可展示的文章',
      actionIcon: Icons.refresh_rounded,
      actionLabel: '刷新全部',
      onAction: state.busy || !state.isOnline
          ? null
          : () => unawaited(_refreshAllWithFeedback(context)),
    );
  }

  Widget _buildSourceFilterBar(BuildContext context) {
    final sourceOptions = controller.entrySourceFilterOptions;
    final folderOptions = controller.entryFolderFilterOptions;
    if (sourceOptions.length <= 1 && folderOptions.length <= 1) {
      return const SizedBox.shrink();
    }

    final totalEntries = controller.sourceFilterBaseEntries.length;
    final totalUnread = controller.sourceFilterBaseEntries.fold<int>(
      0,
      (sum, entry) => entry.isRead ? sum : sum + 1,
    );
    return _SourceFilterBar(
      sourceOptions: sourceOptions,
      folderOptions: folderOptions,
      activeSourceId: controller.state.entrySourceFilterId,
      activeFolder: controller.state.entryFolderFilter,
      totalEntryCount: totalEntries,
      totalUnreadCount: totalUnread,
      onSourceSelected: controller.setEntrySourceFilter,
      onFolderSelected: controller.setEntryFolderFilter,
    );
  }

  Widget _buildQueueFilterBar(BuildContext context) {
    final state = controller.state;
    final unreadCount = controller.queueFilterUnreadCount;
    final inProgressCount = controller.queueFilterInProgressCount;
    if (unreadCount == 0 &&
        inProgressCount == 0 &&
        !state.unreadOnly &&
        !state.inProgressOnly) {
      return const SizedBox.shrink();
    }

    return _QueueFilterBar(
      unreadOnly: state.unreadOnly,
      inProgressOnly: state.inProgressOnly,
      unreadCount: unreadCount,
      inProgressCount: inProgressCount,
      onUnreadChanged: state.busy ? null : controller.toggleUnreadOnly,
      onInProgressChanged: state.busy ? null : controller.toggleInProgressOnly,
    );
  }

  Widget _buildSortOrderControl(BuildContext context) {
    if (controller.visibleEntries.length <= 1 &&
        controller.sourceFilterBaseEntries.length <= 1) {
      return const SizedBox.shrink();
    }

    return _EntrySortOrderControl(
      value: controller.state.entrySortOrder,
      onChanged: controller.setEntrySortOrder,
    );
  }

  Widget _buildListDensityControl(BuildContext context) {
    if (controller.visibleEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    return _EntryListDensityControl(
      value: controller.state.readerPreferences.entryListDensity,
      onChanged: controller.setEntryListDensity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final entries = controller.visibleEntries;
    final canLoadMore = controller.canLoadMoreEntries;
    final collapsedEntryDateSections = state
        .readerPreferences
        .collapsedEntryDateSections
        .toSet();
    final rows = _entryListRows(
      entries,
      canLoadMore: canLoadMore,
      collapsedDateSections: collapsedEntryDateSections,
    );
    final title = switch (state.section) {
      AppSection.feed => 'Feed 流',
      AppSection.saved => '稍后读',
      AppSection.noise => '噪音箱',
      AppSection.sourceEntries =>
        controller.selectedSource == null
            ? '订阅源文章'
            : _redactDiagnosticText(controller.selectedSource!.name),
      _ => state.section.title,
    };
    final selectedSource = controller.selectedSource;

    final listView = ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          _EntryDateHeaderRow(
            :final sectionKey,
            :final label,
            :final entryCount,
            :final unreadCount,
            :final unreadEntryIds,
            :final collapsed,
          ) =>
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
              child: _EntryDateHeader(
                sectionKey: sectionKey,
                label: label,
                entryCount: entryCount,
                unreadCount: unreadCount,
                collapsed: collapsed,
                onToggleCollapsed: () =>
                    _toggleEntryDateSectionCollapsed(sectionKey),
                onMarkRead: state.busy || unreadCount == 0
                    ? null
                    : () => _confirmMarkRead(
                        context,
                        title: '标记本组已读',
                        message: '$label 的 $unreadCount 篇未读文章会标记为已读。',
                        entryIds: unreadEntryIds,
                      ),
              ),
            ),
          _EntryTileRow(:final entry) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildEntryTile(
              context,
              entry: entry,
              selected: state.selectedEntryId == entry.id,
            ),
          ),
          _EntryLoadMoreRow(:final loadedCount) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: _EntryLoadMoreButton(
                loadedCount: loadedCount,
                busy: state.busy,
                onPressed: () => _showActionError(
                  context,
                  () => controller.loadMoreEntries(),
                  apiErrorMessage: _loadMoreEntriesApiErrorMessage,
                  networkErrorMessage: '离线状态下无法加载历史文章',
                  timeoutMessage: '加载历史文章超时，请稍后重试。',
                  showTimeoutSnackBar: false,
                ),
              ),
            ),
          ),
        };
      },
    );

    if (mobile) {
      return Column(
        children: [
          AppBar(
            leading: state.section == AppSection.sourceEntries
                ? IconButton(
                    key: const ValueKey<String>('mobile-source-back-button'),
                    tooltip: '返回订阅源列表',
                    onPressed: controller.backToSourceList,
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
            title: Text(title),
            actions: [
              IconButton(
                tooltip: state.unreadOnly ? '查看全部文章' : '只看未读',
                onPressed: state.busy
                    ? null
                    : () => controller.toggleUnreadOnly(!state.unreadOnly),
                icon: Icon(
                  state.unreadOnly
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                ),
              ),
              IconButton(
                tooltip: '标记当前已读',
                onPressed: state.busy || controller.visibleUnreadCount == 0
                    ? null
                    : () => _confirmMarkVisibleRead(context),
                icon: const Icon(Icons.done_all_rounded),
              ),
              IconButton(
                key: const ValueKey<String>('entry-refresh-all-button'),
                tooltip: _refreshCurrentListLabel(),
                onPressed: state.busy
                    ? null
                    : () => unawaited(_refreshCurrentListWithFeedback(context)),
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (state.section == AppSection.sourceEntries)
                IconButton(
                  key: const ValueKey<String>('source-page-copy-diagnostics'),
                  tooltip: '复制阅读诊断',
                  onPressed: () =>
                      unawaited(_copyDiagnostics(context, controller)),
                  icon: const Icon(Icons.bug_report_rounded),
                ),
              if (state.section == AppSection.sourceEntries &&
                  selectedSource != null)
                _buildSourcePageActions(context, selectedSource),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: _SyncStatusPill(
                    busy: state.busy,
                    isOnline: state.isOnline,
                    pendingCount: state.pendingSyncCount,
                    pendingDescription: state.pendingSyncDescription,
                    entryCount: entries.length,
                    lastSyncedAt: state.session?.lastServerTime,
                    onSyncNow: state.busy || !state.isOnline
                        ? null
                        : () => unawaited(
                            _syncNowWithFeedback(context, controller),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                if (selectedSource != null) ...[
                  _SourcePageHealthBanner(
                    source: selectedSource,
                    onRefresh: state.busy || !state.isOnline
                        ? null
                        : () => unawaited(
                            _refreshSourceWithFeedback(context, selectedSource),
                          ),
                    onToggleEnabled: state.busy || !state.isOnline
                        ? null
                        : () => unawaited(
                            _toggleSourceEnabled(context, selectedSource),
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextFormField(
                  key: ValueKey('mobile-search-${state.searchQuery.isEmpty}'),
                  focusNode: searchFocusNode,
                  initialValue: state.searchQuery,
                  onChanged: controller.setSearchQuery,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: state.searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清空搜索',
                            onPressed: () => controller.setSearchQuery(''),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    hintText: '搜索标题、来源、摘要或正文，最多 8 个关键词',
                  ),
                ),
              ],
            ),
          ),
          _QueueWorkloadStrip(
            entries: entries,
            hasMore: canLoadMore,
            collapsedDateSections: collapsedEntryDateSections,
            onExpandCollapsedDates: collapsedEntryDateSections.isEmpty
                ? null
                : () => controller.setCollapsedEntryDateSections(const []),
            onShowUnread:
                state.busy ||
                    state.unreadOnly ||
                    entries.every((entry) => entry.isRead)
                ? null
                : () => controller.toggleUnreadOnly(true),
            onShowInProgress:
                state.busy ||
                    state.inProgressOnly ||
                    entries.every((entry) => !entry.isInProgress)
                ? null
                : () => controller.toggleInProgressOnly(true),
            onLoadMore: state.busy || !canLoadMore
                ? null
                : () => _showActionError(
                    context,
                    () => controller.loadMoreEntries(),
                    apiErrorMessage: _loadMoreEntriesApiErrorMessage,
                    networkErrorMessage: '离线状态下无法加载历史文章',
                    timeoutMessage: '加载历史文章超时，请稍后重试。',
                    showTimeoutSnackBar: false,
                  ),
          ),
          const SizedBox(height: 8),
          _buildQueueFilterBar(context),
          _buildSourceFilterBar(context),
          const SizedBox(height: 8),
          _buildSortOrderControl(context),
          const SizedBox(height: 8),
          _buildListDensityControl(context),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refreshCurrentListWithFeedback(context),
              child: entries.isEmpty && !canLoadMore
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        _buildEmptyState(context),
                      ],
                    )
                  : listView,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.section == AppSection.sourceEntries)
                TextButton.icon(
                  onPressed: controller.backToSourceList,
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('返回订阅源列表'),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _SyncStatusPill(
                    busy: state.busy,
                    isOnline: state.isOnline,
                    pendingCount: state.pendingSyncCount,
                    pendingDescription: state.pendingSyncDescription,
                    entryCount: entries.length,
                    lastSyncedAt: state.session?.lastServerTime,
                    onSyncNow: state.busy || !state.isOnline
                        ? null
                        : () => unawaited(
                            _syncNowWithFeedback(context, controller),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (selectedSource != null) ...[
                _SourcePageHealthBanner(
                  source: selectedSource,
                  onRefresh: state.busy || !state.isOnline
                      ? null
                      : () => unawaited(
                          _refreshSourceWithFeedback(context, selectedSource),
                        ),
                  onToggleEnabled: state.busy || !state.isOnline
                      ? null
                      : () => unawaited(
                          _toggleSourceEnabled(context, selectedSource),
                        ),
                ),
                const SizedBox(height: 10),
              ],
              TextFormField(
                key: ValueKey('desktop-search-${state.searchQuery.isEmpty}'),
                focusNode: searchFocusNode,
                initialValue: state.searchQuery,
                onChanged: controller.setSearchQuery,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: state.searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () => controller.setSearchQuery(''),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  hintText: '搜索标题、来源、摘要或正文，最多 8 个关键词',
                ),
              ),
              const SizedBox(height: 10),
              _QueueWorkloadStrip(
                entries: entries,
                hasMore: canLoadMore,
                collapsedDateSections: collapsedEntryDateSections,
                onExpandCollapsedDates: collapsedEntryDateSections.isEmpty
                    ? null
                    : () => controller.setCollapsedEntryDateSections(const []),
                onShowUnread:
                    state.busy ||
                        state.unreadOnly ||
                        entries.every((entry) => entry.isRead)
                    ? null
                    : () => controller.toggleUnreadOnly(true),
                onShowInProgress:
                    state.busy ||
                        state.inProgressOnly ||
                        entries.every((entry) => !entry.isInProgress)
                    ? null
                    : () => controller.toggleInProgressOnly(true),
                onLoadMore: state.busy || !canLoadMore
                    ? null
                    : () => _showActionError(
                        context,
                        () => controller.loadMoreEntries(),
                        apiErrorMessage: _loadMoreEntriesApiErrorMessage,
                        networkErrorMessage: '离线状态下无法加载历史文章',
                        timeoutMessage: '加载历史文章超时，请稍后重试。',
                        showTimeoutSnackBar: false,
                      ),
              ),
              const SizedBox(height: 10),
              _buildQueueFilterBar(context),
              const SizedBox(height: 10),
              _buildSourceFilterBar(context),
              const SizedBox(height: 10),
              _buildSortOrderControl(context),
              const SizedBox(height: 10),
              _buildListDensityControl(context),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey<String>('entry-refresh-all-button'),
                    onPressed: state.busy
                        ? null
                        : () => unawaited(
                            _refreshCurrentListWithFeedback(context),
                          ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_refreshCurrentListLabel()),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: state.busy || controller.visibleUnreadCount == 0
                        ? null
                        : () => _confirmMarkVisibleRead(context),
                    icon: const Icon(Icons.done_all_rounded),
                    label: const Text('标记当前已读'),
                  ),
                  if (state.section == AppSection.sourceEntries)
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>(
                        'source-page-copy-diagnostics',
                      ),
                      onPressed: () =>
                          unawaited(_copyDiagnostics(context, controller)),
                      icon: const Icon(Icons.bug_report_rounded),
                      label: const Text('复制阅读诊断'),
                    ),
                  if (state.section == AppSection.sourceEntries &&
                      selectedSource != null)
                    _buildSourcePageActions(context, selectedSource),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty && !canLoadMore
              ? Center(child: _buildEmptyState(context))
              : listView,
        ),
      ],
    );
  }
}

List<_EntryListRow> _entryListRows(
  List<EntryRecord> entries, {
  required bool canLoadMore,
  required Set<String> collapsedDateSections,
}) {
  final rows = <_EntryListRow>[];
  var currentKey = '';
  var currentLabel = '';
  var currentEntries = <EntryRecord>[];

  void flushCurrentSection() {
    if (currentEntries.isEmpty) {
      return;
    }

    final unreadEntryIds = currentEntries
        .where((entry) => !entry.isRead)
        .map((entry) => entry.id)
        .toList(growable: false);
    rows.add(
      _EntryDateHeaderRow(
        sectionKey: currentKey,
        label: currentLabel,
        entryCount: currentEntries.length,
        unreadCount: unreadEntryIds.length,
        unreadEntryIds: unreadEntryIds,
        collapsed: collapsedDateSections.contains(currentKey),
      ),
    );
    if (!collapsedDateSections.contains(currentKey)) {
      rows.addAll(currentEntries.map(_EntryTileRow.new));
    }
    currentEntries = <EntryRecord>[];
  }

  for (final entry in entries) {
    final key = AppFormatters.dayKey(entry.publishedAt);
    if (currentEntries.isNotEmpty && key != currentKey) {
      flushCurrentSection();
    }
    currentKey = key;
    currentLabel = AppFormatters.daySection(entry.publishedAt);
    currentEntries.add(entry);
  }
  flushCurrentSection();

  if (canLoadMore) {
    rows.add(_EntryLoadMoreRow(loadedCount: entries.length));
  }
  return rows;
}

sealed class _EntryListRow {
  const _EntryListRow();
}

class _EntryDateHeaderRow extends _EntryListRow {
  const _EntryDateHeaderRow({
    required this.sectionKey,
    required this.label,
    required this.entryCount,
    required this.unreadCount,
    required this.unreadEntryIds,
    required this.collapsed,
  });

  final String sectionKey;
  final String label;
  final int entryCount;
  final int unreadCount;
  final List<int> unreadEntryIds;
  final bool collapsed;
}

class _EntryTileRow extends _EntryListRow {
  const _EntryTileRow(this.entry);

  final EntryRecord entry;
}

class _EntryLoadMoreRow extends _EntryListRow {
  const _EntryLoadMoreRow({required this.loadedCount});

  final int loadedCount;
}

String _loadMoreEntriesApiErrorMessage(ApiException error) {
  final authMessage = _authExpiredApiErrorMessage(error);
  if (authMessage != null) {
    return authMessage;
  }
  if (error.isBadRequest && error.message == 'invalid pagination cursor') {
    return '历史分页已失效，已隐藏加载更多，请刷新当前列表后再试';
  }
  if (error.isNotFound &&
      (error.message == '订阅源已在服务端删除，已从本地移除。' ||
          error.message == '订阅源已在服务端删除，已清除来源筛选。' ||
          error.message == '文件夹范围已在服务端变化，已清除文件夹筛选。')) {
    return error.message;
  }
  if (error.isNotFound) {
    return '阅读范围已在服务端变化，已恢复到可用列表。';
  }
  return _apiFailureMessage('加载历史文章失败', error);
}

String? _authExpiredApiErrorMessage(ApiException error) {
  if (error.isUnauthorized) {
    return '登录状态已失效，请重新登录';
  }
  return null;
}

String _apiFailureMessage(String prefix, ApiException error) {
  return '$prefix：${_redactDiagnosticText(error.message)}';
}

class _EntryLoadMoreButton extends StatelessWidget {
  const _EntryLoadMoreButton({
    required this.loadedCount,
    required this.busy,
    required this.onPressed,
  });

  final int loadedCount;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final semanticsLabel = '历史文章分页，已加载 $loadedCount 篇，点击加载更多';
    return Semantics(
      key: const ValueKey<String>('entry-load-more-semantics'),
      button: true,
      enabled: !busy,
      label: semanticsLabel,
      child: Tooltip(
        message: '已加载 $loadedCount 篇，继续加载历史文章',
        child: FilledButton.tonalIcon(
          key: const ValueKey<String>('entry-load-more-button'),
          onPressed: busy ? null : onPressed,
          icon: const Icon(Icons.expand_more_rounded),
          label: const Text('加载更多'),
        ),
      ),
    );
  }
}

class _SourcePageHealthBanner extends StatelessWidget {
  const _SourcePageHealthBanner({
    required this.source,
    required this.onRefresh,
    required this.onToggleEnabled,
  });

  final FeedSource source;
  final VoidCallback? onRefresh;
  final VoidCallback? onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    final status = SourceHealthSummary.statusFor(source, now: now);
    final statusDetail = _sourceStatusDetail(source, status);
    final lastFetchedLabel = source.lastFetchedAt == null
        ? '从未成功刷新'
        : '最近刷新 ${AppFormatters.listDate(source.lastFetchedAt!)}';
    final semanticsLabel = _sourcePageHealthSemanticsLabel(
      source,
      status: status,
      statusDetail: statusDetail,
      lastFetchedLabel: lastFetchedLabel,
    );

    return Semantics(
      key: const ValueKey<String>('source-page-health-banner-semantics'),
      container: true,
      label: semanticsLabel,
      child: Container(
        key: const ValueKey<String>('source-page-health-banner'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.55,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _SourceStatusBadge(status: status),
                _SourcePageMetaChip(
                  icon: Icons.folder_outlined,
                  label: _redactDiagnosticText(_sourceFolderName(source)),
                ),
                _SourcePageMetaChip(
                  icon: Icons.mark_email_unread_outlined,
                  label: '${source.unreadCount} 未读',
                ),
                _SourcePageMetaChip(
                  icon: Icons.update_rounded,
                  label: lastFetchedLabel,
                ),
              ],
            ),
            if (statusDetail != null && statusDetail.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                statusDetail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: status == SourceHealthStatus.error
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  key: const ValueKey<String>('source-page-health-refresh'),
                  avatar: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('刷新此源'),
                  onPressed: onRefresh,
                ),
                if (!source.enabled)
                  ActionChip(
                    key: const ValueKey<String>('source-page-health-enable'),
                    avatar: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 16,
                    ),
                    label: const Text('启用自动抓取'),
                    onPressed: onToggleEnabled,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcePageMetaChip extends StatelessWidget {
  const _SourcePageMetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxWidth = (MediaQuery.sizeOf(context).width - 48).clamp(
      120.0,
      280.0,
    );
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _sourcePageHealthSemanticsLabel(
  FeedSource source, {
  required SourceHealthStatus status,
  required String? statusDetail,
  required String lastFetchedLabel,
}) {
  final parts = <String>[
    '当前订阅源健康摘要',
    _redactDiagnosticText(source.name),
    '文件夹 ${_redactDiagnosticText(_sourceFolderName(source))}',
    '${source.unreadCount} 篇未读',
    '健康状态 ${_sourceHealthStatusLabel(status)}',
    lastFetchedLabel,
  ];

  final detail = statusDetail?.trim();
  if (detail != null && detail.isNotEmpty) {
    parts.add(detail);
  }
  parts.add(source.enabled ? '可自动抓取' : '自动抓取已停用');
  return parts.join('，');
}

class _QueueWorkloadStrip extends StatelessWidget {
  const _QueueWorkloadStrip({
    required this.entries,
    required this.hasMore,
    required this.collapsedDateSections,
    required this.onExpandCollapsedDates,
    required this.onShowUnread,
    required this.onShowInProgress,
    required this.onLoadMore,
  });

  final List<EntryRecord> entries;
  final bool hasMore;
  final Set<String> collapsedDateSections;
  final VoidCallback? onExpandCollapsedDates;
  final VoidCallback? onShowUnread;
  final VoidCallback? onShowInProgress;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty && !hasMore) {
      return const SizedBox.shrink();
    }

    final unreadEntries = entries
        .where((entry) => !entry.isRead)
        .toList(growable: false);
    final inProgressEntries = entries
        .where((entry) => entry.isInProgress)
        .toList(growable: false);
    final collapsedEntries = collapsedDateSections.isEmpty
        ? const <EntryRecord>[]
        : entries
              .where(
                (entry) => collapsedDateSections.contains(
                  AppFormatters.dayKey(entry.publishedAt),
                ),
              )
              .toList(growable: false);
    final unreadMinutes = ReadingMetrics.estimateRemainingTotalMinutes(
      unreadEntries,
    );
    final unreadTimeLabel = unreadEntries.isEmpty
        ? '未读清空'
        : '未读剩余约 ${ReadingMetrics.durationLabel(unreadMinutes)}';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _QueueWorkloadChip(
            icon: Icons.view_list_outlined,
            label: '${entries.length} 篇当前列表',
          ),
          if (collapsedEntries.isNotEmpty) ...[
            const SizedBox(width: 8),
            _QueueWorkloadChip(
              icon: Icons.unfold_less_rounded,
              label: '${collapsedEntries.length} 已折叠',
              tooltip: '展开所有折叠日期',
              onPressed: onExpandCollapsedDates,
            ),
          ],
          const SizedBox(width: 8),
          _QueueWorkloadChip(
            actionKey: const ValueKey<String>('queue-workload-unread'),
            icon: Icons.mark_email_unread_outlined,
            label: '${unreadEntries.length} 未读',
            tooltip: '只看未读文章',
            onPressed: unreadEntries.isEmpty ? null : onShowUnread,
          ),
          const SizedBox(width: 8),
          _QueueWorkloadChip(
            icon: Icons.schedule_rounded,
            label: unreadTimeLabel,
          ),
          if (inProgressEntries.isNotEmpty) ...[
            const SizedBox(width: 8),
            _QueueWorkloadChip(
              actionKey: const ValueKey<String>('queue-workload-in-progress'),
              icon: Icons.auto_stories_outlined,
              label: '${inProgressEntries.length} 继续读',
              tooltip: '只看继续阅读',
              onPressed: onShowInProgress,
            ),
          ],
          if (hasMore) ...[
            const SizedBox(width: 8),
            _QueueWorkloadChip(
              actionKey: const ValueKey<String>('queue-workload-load-more'),
              icon: Icons.history_rounded,
              label: '还有历史',
              tooltip: '加载更多历史文章',
              onPressed: onLoadMore,
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueWorkloadChip extends StatelessWidget {
  const _QueueWorkloadChip({
    required this.icon,
    required this.label,
    this.actionKey,
    this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final Key? actionKey;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    final content = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: enabled
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.65)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(
          color: enabled
              ? theme.colorScheme.primary.withValues(alpha: 0.22)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: enabled
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: enabled
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    if (!enabled) {
      return content;
    }

    return ActionChip(
      key: actionKey ?? const ValueKey<String>('queue-expand-collapsed-dates'),
      tooltip: tooltip ?? label,
      avatar: Icon(icon, size: 16, color: theme.colorScheme.onPrimaryContainer),
      label: Text(label),
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.w800,
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: theme.colorScheme.primary.withValues(alpha: 0.22),
      ),
      backgroundColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.65,
      ),
      onPressed: onPressed,
    );
  }
}

class _QueueFilterBar extends StatelessWidget {
  const _QueueFilterBar({
    required this.unreadOnly,
    required this.inProgressOnly,
    required this.unreadCount,
    required this.inProgressCount,
    required this.onUnreadChanged,
    required this.onInProgressChanged,
  });

  final bool unreadOnly;
  final bool inProgressOnly;
  final int unreadCount;
  final int inProgressCount;
  final ValueChanged<bool>? onUnreadChanged;
  final ValueChanged<bool>? onInProgressChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _QueueFilterChip(
            key: const ValueKey<String>('queue-filter-unread'),
            selected: unreadOnly,
            icon: Icons.mark_email_unread_outlined,
            label: '未读 · $unreadCount',
            semanticsLabel: _queueFilterSemanticsLabel(
              '未读',
              count: unreadCount,
              selected: unreadOnly,
            ),
            onSelected: onUnreadChanged,
          ),
          const SizedBox(width: 8),
          _QueueFilterChip(
            key: const ValueKey<String>('queue-filter-in-progress'),
            selected: inProgressOnly,
            icon: Icons.auto_stories_outlined,
            label: '继续阅读 · $inProgressCount',
            semanticsLabel: _queueFilterSemanticsLabel(
              '继续阅读',
              count: inProgressCount,
              selected: inProgressOnly,
            ),
            onSelected: onInProgressChanged,
          ),
        ],
      ),
    );
  }
}

class _QueueFilterChip extends StatelessWidget {
  const _QueueFilterChip({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.semanticsLabel,
    required this.onSelected,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final String semanticsLabel;
  final ValueChanged<bool>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onSelected != null,
      selected: selected,
      label: semanticsLabel,
      child: FilterChip(
        selected: selected,
        avatar: Icon(icon, size: 16),
        label: Text(label),
        onSelected: onSelected,
      ),
    );
  }
}

String _queueFilterSemanticsLabel(
  String name, {
  required int count,
  required bool selected,
}) {
  final state = selected ? '当前筛选' : '点击筛选';
  return '阅读队列过滤，$name，$count 篇文章，$state';
}

class _SourceFilterBar extends StatelessWidget {
  const _SourceFilterBar({
    required this.sourceOptions,
    required this.folderOptions,
    required this.activeSourceId,
    required this.activeFolder,
    required this.totalEntryCount,
    required this.totalUnreadCount,
    required this.onSourceSelected,
    required this.onFolderSelected,
  });

  final List<EntrySourceFilterOption> sourceOptions;
  final List<EntryFolderFilterOption> folderOptions;
  final int? activeSourceId;
  final String? activeFolder;
  final int totalEntryCount;
  final int totalUnreadCount;
  final ValueChanged<int?> onSourceSelected;
  final ValueChanged<String?> onFolderSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          _SourceFilterChip(
            key: const ValueKey<String>('source-filter-all'),
            selected: activeSourceId == null && activeFolder == null,
            label: _sourceFilterLabel(
              '全部来源',
              unreadCount: totalUnreadCount,
              entryCount: totalEntryCount,
            ),
            semanticsLabel: _sourceFilterSemanticsLabel(
              '全部来源',
              unreadCount: totalUnreadCount,
              entryCount: totalEntryCount,
              selected: activeSourceId == null && activeFolder == null,
            ),
            fallbackIcon: Icons.inbox_rounded,
            onSelected: () {
              onFolderSelected(null);
              onSourceSelected(null);
            },
          ),
          for (final option in folderOptions) ...[
            const SizedBox(width: 8),
            _SourceFilterChip(
              key: ValueKey<String>('folder-filter-${option.folder}'),
              selected: activeFolder == option.folder,
              label: _sourceFilterLabel(
                _redactDiagnosticText(option.folder),
                unreadCount: option.unreadCount,
                entryCount: option.entryCount,
              ),
              semanticsLabel: _sourceFilterSemanticsLabel(
                _redactDiagnosticText(option.folder),
                unreadCount: option.unreadCount,
                entryCount: option.entryCount,
                selected: activeFolder == option.folder,
                scope: '文件夹',
              ),
              fallbackIcon: Icons.folder_rounded,
              onSelected: () => onFolderSelected(
                activeFolder == option.folder ? null : option.folder,
              ),
            ),
          ],
          for (final option in sourceOptions) ...[
            const SizedBox(width: 8),
            _SourceFilterChip(
              key: ValueKey<String>('source-filter-${option.sourceId}'),
              selected:
                  activeFolder == null && activeSourceId == option.sourceId,
              sourceIconUrl: option.sourceIconUrl,
              sourceId: option.sourceId,
              label: _sourceFilterLabel(
                _redactDiagnosticText(option.sourceName),
                unreadCount: option.unreadCount,
                entryCount: option.entryCount,
              ),
              semanticsLabel: _sourceFilterSemanticsLabel(
                _redactDiagnosticText(option.sourceName),
                unreadCount: option.unreadCount,
                entryCount: option.entryCount,
                selected:
                    activeFolder == null && activeSourceId == option.sourceId,
                scope: '来源',
              ),
              onSelected: () => onSourceSelected(
                activeSourceId == option.sourceId ? null : option.sourceId,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceFilterChip extends StatelessWidget {
  const _SourceFilterChip({
    super.key,
    required this.selected,
    required this.label,
    required this.semanticsLabel,
    required this.onSelected,
    this.fallbackIcon = Icons.rss_feed_rounded,
    this.sourceIconUrl,
    this.sourceId,
  });

  final bool selected;
  final String label;
  final String semanticsLabel;
  final VoidCallback onSelected;
  final IconData fallbackIcon;
  final String? sourceIconUrl;
  final int? sourceId;

  @override
  Widget build(BuildContext context) {
    final sourceId = this.sourceId;
    return Semantics(
      button: true,
      enabled: true,
      selected: selected,
      label: semanticsLabel,
      child: ChoiceChip(
        selected: selected,
        avatar: sourceId == null
            ? Icon(selected ? Icons.check_rounded : fallbackIcon, size: 16)
            : _EntrySourceIcon(
                imageUrl: sourceIconUrl,
                imageKey: ValueKey<String>('source-filter-icon-$sourceId'),
                fallbackKey: ValueKey<String>(
                  'source-filter-icon-fallback-$sourceId',
                ),
              ),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _EntrySortOrderControl extends StatelessWidget {
  const _EntrySortOrderControl({required this.value, required this.onChanged});

  final EntrySortOrder value;
  final ValueChanged<EntrySortOrder> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey<String>('entry-sort-control-semantics'),
      label: '阅读队列排序，当前${_entrySortOrderLabel(value)}',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: SegmentedButton<EntrySortOrder>(
          showSelectedIcon: false,
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.single),
          segments: const [
            ButtonSegment<EntrySortOrder>(
              value: EntrySortOrder.newestFirst,
              icon: Icon(Icons.south_rounded, size: 16),
              label: Text(
                '新到旧',
                key: ValueKey<String>('entry-sort-newest-first'),
              ),
            ),
            ButtonSegment<EntrySortOrder>(
              value: EntrySortOrder.oldestFirst,
              icon: Icon(Icons.north_rounded, size: 16),
              label: Text(
                '旧到新',
                key: ValueKey<String>('entry-sort-oldest-first'),
              ),
            ),
            ButtonSegment<EntrySortOrder>(
              value: EntrySortOrder.shortestFirst,
              icon: Icon(Icons.short_text_rounded, size: 16),
              label: Text(
                '短文优先',
                key: ValueKey<String>('entry-sort-shortest-first'),
              ),
            ),
            ButtonSegment<EntrySortOrder>(
              value: EntrySortOrder.longestFirst,
              icon: Icon(Icons.subject_rounded, size: 16),
              label: Text(
                '长文优先',
                key: ValueKey<String>('entry-sort-longest-first'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _entrySortOrderLabel(EntrySortOrder value) {
  return switch (value) {
    EntrySortOrder.newestFirst => '新到旧',
    EntrySortOrder.oldestFirst => '旧到新',
    EntrySortOrder.shortestFirst => '短文优先',
    EntrySortOrder.longestFirst => '长文优先',
  };
}

class _EntryListDensityControl extends StatelessWidget {
  const _EntryListDensityControl({
    required this.value,
    required this.onChanged,
  });

  final EntryListDensity value;
  final ValueChanged<EntryListDensity> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey<String>('entry-density-control-semantics'),
      label: '文章列表密度，当前${_entryListDensityLabel(value)}',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: SegmentedButton<EntryListDensity>(
          showSelectedIcon: false,
          selected: {value},
          onSelectionChanged: (selection) => onChanged(selection.single),
          segments: const [
            ButtonSegment<EntryListDensity>(
              value: EntryListDensity.comfortable,
              icon: Icon(Icons.view_stream_rounded, size: 16),
              label: Text(
                '舒适',
                key: ValueKey<String>('entry-density-comfortable'),
              ),
            ),
            ButtonSegment<EntryListDensity>(
              value: EntryListDensity.compact,
              icon: Icon(Icons.view_headline_rounded, size: 16),
              label: Text('紧凑', key: ValueKey<String>('entry-density-compact')),
            ),
          ],
        ),
      ),
    );
  }
}

String _entryListDensityLabel(EntryListDensity value) {
  return switch (value) {
    EntryListDensity.comfortable => '舒适',
    EntryListDensity.compact => '紧凑',
  };
}

String _sourceFilterLabel(
  String sourceName, {
  required int unreadCount,
  required int entryCount,
}) {
  return unreadCount > 0
      ? '$sourceName · $unreadCount/$entryCount'
      : '$sourceName · $entryCount';
}

String _sourceFilterSemanticsLabel(
  String name, {
  required int unreadCount,
  required int entryCount,
  required bool selected,
  String scope = '全部',
}) {
  final state = selected ? '当前筛选' : '点击筛选';
  return '阅读队列$scope筛选，$name，$entryCount 篇文章，$unreadCount 篇未读，$state';
}

class _EntryDateHeader extends StatelessWidget {
  const _EntryDateHeader({
    required this.sectionKey,
    required this.label,
    required this.entryCount,
    required this.unreadCount,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onMarkRead,
  });

  final String sectionKey;
  final String label;
  final int entryCount;
  final int unreadCount;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: ValueKey<String>('date-section-$sectionKey-semantics'),
      container: true,
      label:
          '日期分组，$label，$entryCount 篇文章，$unreadCount 篇未读，${collapsed ? '已折叠' : '已展开'}',
      child: Row(
        children: [
          SizedBox.square(
            dimension: 34,
            child: IconButton(
              key: ValueKey<String>('date-section-$sectionKey-toggle'),
              tooltip: collapsed ? '展开 $label' : '折叠 $label',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: onToggleCollapsed,
              icon: Icon(
                collapsed
                    ? Icons.chevron_right_rounded
                    : Icons.expand_more_rounded,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.calendar_today_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$entryCount 篇 · $unreadCount 未读',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 34,
            child: IconButton(
              key: ValueKey<String>('date-section-$sectionKey-mark-read'),
              tooltip: _dateSectionMarkReadTooltip(label, unreadCount),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: onMarkRead,
              icon: const Icon(Icons.done_all_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

String _dateSectionMarkReadTooltip(String label, int unreadCount) {
  if (unreadCount == 0) {
    return '$label 没有未读文章';
  }
  return '将 $label 的 $unreadCount 篇未读文章标记已读';
}

class _EntryEmptyState extends StatelessWidget {
  const _EntryEmptyState({
    required this.icon,
    required this.title,
    required this.actionIcon,
    required this.actionLabel,
    required this.onAction,
    this.secondaryActionIcon,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.tertiaryActionIcon,
    this.tertiaryActionLabel,
    this.onTertiaryAction,
  });

  final IconData icon;
  final String title;
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback? onAction;
  final IconData? secondaryActionIcon;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final IconData? tertiaryActionIcon;
  final String? tertiaryActionLabel;
  final VoidCallback? onTertiaryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 34, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: Icon(actionIcon),
                label: Text(actionLabel),
              ),
              if (secondaryActionIcon != null && secondaryActionLabel != null)
                OutlinedButton.icon(
                  onPressed: onSecondaryAction,
                  icon: Icon(secondaryActionIcon),
                  label: Text(secondaryActionLabel!),
                ),
              if (tertiaryActionIcon != null && tertiaryActionLabel != null)
                OutlinedButton.icon(
                  onPressed: onTertiaryAction,
                  icon: Icon(tertiaryActionIcon),
                  label: Text(tertiaryActionLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryQuickActions extends StatelessWidget {
  const _EntryQuickActions({
    required this.entry,
    required this.busy,
    required this.compactActions,
    required this.showReprocessAi,
    required this.onToggleSaved,
    required this.onToggleRead,
    required this.onToggleNoise,
    required this.onOpenOriginal,
    required this.onCopyLink,
    required this.onCopyCitation,
    required this.onCopyNote,
    required this.onReprocessAi,
  });

  final EntryRecord entry;
  final bool busy;
  final bool compactActions;
  final bool showReprocessAi;
  final VoidCallback onToggleSaved;
  final VoidCallback onToggleRead;
  final VoidCallback onToggleNoise;
  final VoidCallback onOpenOriginal;
  final VoidCallback onCopyLink;
  final VoidCallback onCopyCitation;
  final VoidCallback onCopyNote;
  final VoidCallback? onReprocessAi;

  @override
  Widget build(BuildContext context) {
    final primaryActions = [
      _EntryQuickActionButton(
        tooltip: entry.isSaved ? '取消收藏' : '稍后读',
        icon: entry.isSaved
            ? Icons.bookmark_rounded
            : Icons.bookmark_add_outlined,
        onPressed: busy ? null : onToggleSaved,
      ),
      _EntryQuickActionButton(
        tooltip: entry.isRead ? '标记未读' : '标记已读',
        icon: entry.isRead
            ? Icons.mark_email_unread_outlined
            : Icons.mark_email_read_outlined,
        onPressed: busy ? null : onToggleRead,
      ),
      _EntryQuickActionButton(
        tooltip: entry.isNoise ? '恢复 Feed' : '移入噪音箱',
        icon: entry.isNoise ? Icons.move_to_inbox_rounded : Icons.block_rounded,
        onPressed: busy ? null : onToggleNoise,
      ),
    ];

    if (compactActions) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...primaryActions,
          _EntryMoreActionMenu(
            showReprocessAi: showReprocessAi,
            onOpenOriginal: onOpenOriginal,
            onCopyLink: onCopyLink,
            onCopyCitation: onCopyCitation,
            onCopyNote: onCopyNote,
            onReprocessAi: busy ? null : onReprocessAi,
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...primaryActions,
        _EntryQuickActionButton(
          tooltip: '打开原文',
          icon: Icons.open_in_new_rounded,
          onPressed: onOpenOriginal,
        ),
        _EntryQuickActionButton(
          tooltip: '复制链接',
          icon: Icons.link_rounded,
          onPressed: onCopyLink,
        ),
        _EntryQuickActionButton(
          tooltip: '复制引用',
          icon: Icons.format_quote_rounded,
          onPressed: onCopyCitation,
        ),
        _EntryQuickActionButton(
          tooltip: '复制笔记',
          icon: Icons.note_add_outlined,
          onPressed: onCopyNote,
        ),
        if (showReprocessAi)
          _EntryQuickActionButton(
            tooltip: '重试 AI',
            icon: Icons.auto_awesome_rounded,
            onPressed: busy ? null : onReprocessAi,
          ),
      ],
    );
  }
}

class _EntryMoreActionMenu extends StatelessWidget {
  const _EntryMoreActionMenu({
    required this.showReprocessAi,
    required this.onOpenOriginal,
    required this.onCopyLink,
    required this.onCopyCitation,
    required this.onCopyNote,
    required this.onReprocessAi,
  });

  final bool showReprocessAi;
  final VoidCallback onOpenOriginal;
  final VoidCallback onCopyLink;
  final VoidCallback onCopyCitation;
  final VoidCallback onCopyNote;
  final VoidCallback? onReprocessAi;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: PopupMenuButton<_EntryMoreAction>(
        tooltip: '更多操作',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_horiz_rounded, size: 18),
        onSelected: (action) {
          switch (action) {
            case _EntryMoreAction.openOriginal:
              onOpenOriginal();
              break;
            case _EntryMoreAction.copyLink:
              onCopyLink();
              break;
            case _EntryMoreAction.copyCitation:
              onCopyCitation();
              break;
            case _EntryMoreAction.copyNote:
              onCopyNote();
              break;
            case _EntryMoreAction.reprocessAi:
              onReprocessAi?.call();
              break;
          }
        },
        itemBuilder: (context) => [
          _entryMoreActionItem(
            _EntryMoreAction.openOriginal,
            Icons.open_in_new_rounded,
            '打开原文',
          ),
          _entryMoreActionItem(
            _EntryMoreAction.copyLink,
            Icons.link_rounded,
            '复制链接',
          ),
          _entryMoreActionItem(
            _EntryMoreAction.copyCitation,
            Icons.format_quote_rounded,
            '复制引用',
          ),
          _entryMoreActionItem(
            _EntryMoreAction.copyNote,
            Icons.note_add_outlined,
            '复制笔记',
          ),
          if (showReprocessAi)
            PopupMenuItem<_EntryMoreAction>(
              value: _EntryMoreAction.reprocessAi,
              enabled: onReprocessAi != null,
              child: const _EntryMoreActionLabel(
                icon: Icons.auto_awesome_rounded,
                label: '重试 AI',
              ),
            ),
        ],
      ),
    );
  }
}

enum _EntryMoreAction {
  openOriginal,
  copyLink,
  copyCitation,
  copyNote,
  reprocessAi,
}

PopupMenuItem<_EntryMoreAction> _entryMoreActionItem(
  _EntryMoreAction value,
  IconData icon,
  String label,
) {
  return PopupMenuItem<_EntryMoreAction>(
    value: value,
    child: _EntryMoreActionLabel(icon: icon, label: label),
  );
}

class _EntryMoreActionLabel extends StatelessWidget {
  const _EntryMoreActionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}

class _EntryQuickActionButton extends StatelessWidget {
  const _EntryQuickActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class _EntryCoverImage extends StatelessWidget {
  const _EntryCoverImage({required this.imageUrl, required this.compact});

  final String imageUrl;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? const Size(72, 54) : const Size(84, 64);
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        imageUrl,
        width: size.width,
        height: size.height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size.width,
          height: size.height,
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            Icons.image_not_supported_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EntrySourceLabel extends StatelessWidget {
  const _EntrySourceLabel({
    required this.sourceName,
    required this.iconUrl,
    required this.imageKey,
    required this.fallbackKey,
  });

  final String sourceName;
  final String? iconUrl;
  final Key imageKey;
  final Key fallbackKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final normalizedIconUrl = iconUrl?.trim();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _EntrySourceIcon(
          imageUrl: normalizedIconUrl == null || normalizedIconUrl.isEmpty
              ? null
              : normalizedIconUrl,
          imageKey: imageKey,
          fallbackKey: fallbackKey,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            sourceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _EntrySourceIcon extends StatelessWidget {
  const _EntrySourceIcon({
    required this.imageUrl,
    required this.imageKey,
    required this.fallbackKey,
  });

  final String? imageUrl;
  final Key imageKey;
  final Key fallbackKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return Icon(
        Icons.rss_feed_rounded,
        key: fallbackKey,
        size: 13,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.network(
        url,
        key: imageKey,
        width: 14,
        height: 14,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Icon(
          Icons.rss_feed_rounded,
          key: fallbackKey,
          size: 13,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

IconData _entryAiProcessingIcon(EntryAiProcessingState state) {
  return switch (state) {
    EntryAiProcessingState.pending => Icons.auto_awesome_rounded,
    EntryAiProcessingState.failed => Icons.error_outline_rounded,
    EntryAiProcessingState.skipped => Icons.auto_awesome_outlined,
    EntryAiProcessingState.none => Icons.auto_awesome_outlined,
  };
}

String _entryAiProcessingLabel(EntryAiProcessingState state) {
  return switch (state) {
    EntryAiProcessingState.pending => 'AI 处理中',
    EntryAiProcessingState.failed => 'AI 失败',
    EntryAiProcessingState.skipped => 'AI 已跳过',
    EntryAiProcessingState.none => 'AI',
  };
}

Color _entryAiProcessingColor(ThemeData theme, EntryAiProcessingState state) {
  return switch (state) {
    EntryAiProcessingState.pending => theme.colorScheme.primary,
    EntryAiProcessingState.failed => theme.colorScheme.error,
    EntryAiProcessingState.skipped => theme.colorScheme.onSurfaceVariant,
    EntryAiProcessingState.none => theme.colorScheme.onSurfaceVariant,
  };
}

bool _canReprocessEntryAi(EntryAiProcessingState state) {
  return state == EntryAiProcessingState.failed ||
      state == EntryAiProcessingState.skipped;
}

class _SyncStatusPill extends StatelessWidget {
  const _SyncStatusPill({
    required this.busy,
    required this.isOnline,
    required this.pendingCount,
    required this.pendingDescription,
    required this.entryCount,
    required this.lastSyncedAt,
    required this.onSyncNow,
  });

  final bool busy;
  final bool isOnline;
  final int pendingCount;
  final String pendingDescription;
  final int entryCount;
  final DateTime? lastSyncedAt;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    final String label;
    final safePendingDescription = _redactDiagnosticText(
      pendingDescription,
      emptyPlaceholder: '',
    );
    final pendingVisualDetail = safePendingDescription.isEmpty
        ? ''
        : ' · $safePendingDescription';
    final IconData icon;
    if (busy) {
      color = theme.colorScheme.primary;
      label = pendingCount > 0
          ? '同步中 · $pendingCount$pendingVisualDetail'
          : '同步中';
      icon = Icons.sync_rounded;
    } else if (pendingCount > 0) {
      color = isOnline ? theme.colorScheme.tertiary : theme.colorScheme.error;
      label = '待同步 $pendingCount$pendingVisualDetail';
      icon = Icons.cloud_upload_outlined;
    } else if (isOnline) {
      color = theme.colorScheme.secondary;
      label = lastSyncedAt == null
          ? '$entryCount 篇'
          : '已同步 ${AppFormatters.listDate(lastSyncedAt!)}';
      icon = Icons.cloud_done_outlined;
    } else {
      color = theme.colorScheme.error;
      label = '离线';
      icon = Icons.cloud_off_outlined;
    }

    final canTap = !busy && isOnline && onSyncNow != null;
    final pendingDetail = safePendingDescription.isEmpty
        ? ''
        : '，$safePendingDescription';
    final offlinePendingRetention = !isOnline && pendingCount > 0
        ? '，已保留在本机，恢复在线后可重试'
        : '';
    final busyPendingDetail = busy && pendingCount > 0
        ? '，待同步 $pendingCount$pendingDetail'
        : pendingDetail;
    final semanticsStatusLabel = busy
        ? '同步中'
        : pendingCount > 0
        ? '待同步 $pendingCount'
        : label;
    final tapActionLabel = pendingCount > 0 ? '同步待处理动作' : '拉取最新变化';
    final semanticsLabel = canTap
        ? '同步状态，$semanticsStatusLabel$pendingDetail，点击$tapActionLabel'
        : '同步状态，$semanticsStatusLabel$busyPendingDetail$offlinePendingRetention';
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width < 600 ? 180 : 280,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (!canTap) {
      return Semantics(
        key: const ValueKey<String>('sync-status-pill'),
        label: semanticsLabel,
        child: pill,
      );
    }
    return Semantics(
      key: const ValueKey<String>('sync-status-pill'),
      button: true,
      enabled: true,
      label: semanticsLabel,
      onTap: onSyncNow,
      child: Tooltip(
        message: pendingCount > 0 && safePendingDescription.isNotEmpty
            ? '同步待处理动作：$safePendingDescription'
            : pendingCount > 0
            ? '同步待处理动作'
            : '拉取最新变化',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onSyncNow,
          child: pill,
        ),
      ),
    );
  }
}

class _SourceListPane extends StatefulWidget {
  const _SourceListPane({
    required this.controller,
    required this.mobile,
    required this.searchFocusNode,
    required this.onSearchEscapeHandlerChanged,
  });

  final AppController controller;
  final bool mobile;
  final FocusNode searchFocusNode;
  final ValueChanged<VoidCallback?> onSearchEscapeHandlerChanged;

  @override
  State<_SourceListPane> createState() => _SourceListPaneState();
}

class _SourceListPaneState extends State<_SourceListPane> {
  final TextEditingController _sourceSearchController = TextEditingController();
  String _sourceSearchQuery = '';
  _SourceListFilter _sourceListFilter = _SourceListFilter.all;

  AppController get controller => widget.controller;
  bool get mobile => widget.mobile;

  @override
  void initState() {
    super.initState();
    _sourceSearchController.addListener(_handleSourceSearchChanged);
    widget.onSearchEscapeHandlerChanged(_handleSourceSearchEscape);
  }

  @override
  void didUpdateWidget(covariant _SourceListPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onSearchEscapeHandlerChanged !=
        widget.onSearchEscapeHandlerChanged) {
      oldWidget.onSearchEscapeHandlerChanged(null);
      widget.onSearchEscapeHandlerChanged(_handleSourceSearchEscape);
    }
  }

  @override
  void dispose() {
    widget.onSearchEscapeHandlerChanged(null);
    _sourceSearchController.removeListener(_handleSourceSearchChanged);
    _sourceSearchController.dispose();
    super.dispose();
  }

  void _handleSourceSearchChanged() {
    final nextQuery = _sourceSearchController.text;
    if (nextQuery == _sourceSearchQuery) {
      return;
    }
    setState(() {
      _sourceSearchQuery = nextQuery;
    });
  }

  void _clearSourceSearch() {
    _sourceSearchController.clear();
  }

  void _setSourceListFilter(_SourceListFilter filter) {
    if (filter == _sourceListFilter) {
      return;
    }
    setState(() {
      _sourceListFilter = filter;
    });
  }

  void _clearSourceFilters() {
    _sourceSearchController.clear();
    final sourceListSortOrder =
        controller.state.readerPreferences.sourceListSortOrder;
    if (_sourceListFilter == _SourceListFilter.all &&
        sourceListSortOrder == SourceListSortOrder.original) {
      return;
    }
    setState(() {
      _sourceListFilter = _SourceListFilter.all;
    });
    controller.setSourceListSortOrder(SourceListSortOrder.original);
  }

  void _handleSourceSearchEscape() {
    if (_sourceSearchController.text.trim().isNotEmpty) {
      _clearSourceSearch();
      return;
    }
    final sourceListSortOrder =
        controller.state.readerPreferences.sourceListSortOrder;
    if (_sourceListFilter != _SourceListFilter.all ||
        sourceListSortOrder != SourceListSortOrder.original) {
      _clearSourceFilters();
      return;
    }
    widget.searchFocusNode.unfocus();
  }

  void _setSourceListSort(SourceListSortOrder sort) =>
      controller.setSourceListSortOrder(sort);

  void _toggleSourceFolderCollapsed(String folder) {
    final collapsedFolders = controller
        .state
        .readerPreferences
        .collapsedSourceFolders
        .toSet();
    if (!collapsedFolders.add(folder)) {
      collapsedFolders.remove(folder);
    }
    controller.setCollapsedSourceFolders(collapsedFolders);
  }

  void _expandCollapsedSourceFolders() {
    controller.setCollapsedSourceFolders(const <String>[]);
  }

  String _sourceRefreshAfterSaveMessage(SourceRefreshAfterSaveException error) {
    final prefix = switch (error.action) {
      SourceSaveAction.add => '已添加订阅源',
      SourceSaveAction.update => '已更新订阅源',
    };
    return switch (error.cause) {
      TimeoutException() => '$prefix，但刷新请求超时，请稍后重试',
      NetworkException() => '$prefix，但当前网络不可用，可稍后手动刷新',
      ApiException apiError =>
        '$prefix，但${_sourceRefreshApiErrorMessage(apiError)}',
      _ => '$prefix，但刷新失败，请稍后重试',
    };
  }

  String _opmlImportSyncAfterSuccessMessage(
    OpmlImportSyncAfterSuccessException error,
  ) {
    final imported = _opmlImportResultSummary(
      error.result,
      includeTrailingStop: false,
    );
    return switch (error.cause) {
      TimeoutException() => '$imported，但同步请求超时，请稍后刷新',
      NetworkException() => '$imported，但当前网络不可用，可稍后刷新',
      ApiException apiError =>
        '$imported，但${_opmlImportSyncApiErrorMessage(apiError)}',
      _ => '$imported，但同步失败，请稍后刷新',
    };
  }

  String _opmlImportSuccessMessage(
    OpmlImportResult result, {
    required bool refreshAfterImport,
  }) {
    return _opmlImportResultSummary(
      result,
      refreshRequested: refreshAfterImport,
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final result = await showDialog<({String rssUrl, String folder})>(
      context: context,
      builder: (context) => _AddSourceDialog(
        folderSuggestions: _sourceFolderSuggestions(
          controller.state.snapshot.sources,
        ),
      ),
    );

    if (result == null || result.rssUrl.isEmpty || !context.mounted) {
      return;
    }

    try {
      await controller.addSource(result.rssUrl, folder: result.folder);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已添加订阅源')));
    } on SourceRefreshAfterSaveException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceRefreshAfterSaveMessage(error))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sourceSaveApiErrorMessage(error, SourceSaveAction.add),
          ),
        ),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前网络不可用，已切换为离线阅读模式，可稍后重试添加订阅源')),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('添加请求超时，请稍后重试')));
    }
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final request =
        await showDialog<({String opml, bool refreshAfterImport})>(
          context: context,
          builder: (context) => const _ImportOpmlDialog(),
        ) ??
        (opml: '', refreshAfterImport: false);

    if (request.opml.isEmpty || !context.mounted) {
      return;
    }

    try {
      final result = await controller.importOpml(
        request.opml,
        refreshAfterImport: request.refreshAfterImport,
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _opmlImportSuccessMessage(
              result,
              refreshAfterImport: request.refreshAfterImport,
            ),
          ),
        ),
      );
    } on OpmlImportSyncAfterSuccessException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_opmlImportSyncAfterSuccessMessage(error))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_opmlImportApiErrorMessage(error))),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前网络不可用，已切换为离线阅读模式，可稍后重试导入 OPML')),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导入请求超时，请稍后重试')));
    }
  }

  Future<void> _exportOpml(BuildContext context) =>
      _copyExportedOpml(context, controller);

  Future<void> _showEditDialog(BuildContext context, FeedSource source) async {
    final updated = await showDialog<FeedSource>(
      context: context,
      builder: (context) => _EditSourceDialog(
        source: source,
        folderSuggestions: _sourceFolderSuggestions(
          controller.state.snapshot.sources,
        ),
      ),
    );

    if (updated == null || !context.mounted) {
      return;
    }

    try {
      await controller.updateSource(updated);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已更新订阅源')));
    } on SourceRefreshAfterSaveException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceRefreshAfterSaveMessage(error))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sourceSaveApiErrorMessage(error, SourceSaveAction.update),
          ),
        ),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前网络不可用，已切换为离线阅读模式，可稍后重试编辑订阅源')),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('编辑请求超时，请稍后重试')));
    }
  }

  Future<void> _deleteSource(BuildContext context, FeedSource source) async {
    final sourceName = _redactDiagnosticText(source.name);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除订阅源'),
            content: Text('删除 $sourceName 后，该源历史文章也会一并从本地清理。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      await controller.deleteSource(source.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 $sourceName')));
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceDeleteApiErrorMessage(error))),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前网络不可用，已切换为离线阅读模式，可稍后重试删除订阅源')),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除请求超时，请稍后重试')));
    }
  }

  Future<void> _refreshAllSources(BuildContext context) async {
    final result = await _runReaderValue<RefreshAcceptedResult>(
      context,
      controller.refreshAll,
      apiErrorMessage: _sourceRefreshApiErrorMessage,
      networkErrorMessage: _refreshAllNetworkMessage,
      timeoutMessage: _refreshAllTimeoutMessage,
    );
    if (!context.mounted || result == null) {
      return;
    }
    _showReaderSnackBar(context, _refreshAllAcceptedMessage(result));
  }

  Future<void> _refreshSource(BuildContext context, FeedSource source) async {
    try {
      final result = await controller.refreshSource(source.id);
      if (!context.mounted) {
        return;
      }
      _showReaderSnackBar(
        context,
        _refreshSourceAcceptedMessage(result, source),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceRefreshApiErrorMessage(error))),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_refreshSourceNetworkMessage)),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_refreshSourceTimeoutMessage)),
      );
    }
  }

  Future<void> _toggleSourceEnabled(
    BuildContext context,
    FeedSource source,
  ) async {
    final enabled = !source.enabled;
    final sourceName = _redactDiagnosticText(source.name);
    try {
      await controller.updateSource(source.copyWith(enabled: enabled));
      if (!context.mounted) {
        return;
      }
      _showReaderSnackBar(
        context,
        enabled ? '已启用 $sourceName' : '已停用 $sourceName',
      );
    } on SourceRefreshAfterSaveException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceRefreshAfterSaveMessage(error))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sourceSaveApiErrorMessage(error, SourceSaveAction.update),
          ),
        ),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下无法修改订阅源')));
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('修改请求超时，请稍后重试')));
    }
  }

  Future<void> _refreshIssueSources(
    BuildContext context,
    List<int> sourceIds,
  ) async {
    if (sourceIds.isEmpty) {
      return;
    }

    try {
      final result = await controller.refreshSources(sourceIds);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_refreshIssueSourcesAcceptedMessage(result))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceRefreshApiErrorMessage(error))),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_refreshIssueSourcesNetworkMessage)),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_refreshIssueSourcesTimeoutMessage)),
      );
    }
  }

  Future<void> _refreshVisibleSources(
    BuildContext context,
    List<int> sourceIds,
  ) async {
    if (sourceIds.isEmpty) {
      return;
    }

    try {
      final result = await controller.refreshSources(sourceIds);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_refreshVisibleSourcesAcceptedMessage(result))),
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sourceRefreshApiErrorMessage(error))),
      );
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_refreshVisibleSourcesNetworkMessage)),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_refreshVisibleSourcesTimeoutMessage)),
      );
    }
  }

  Future<void> _markSourceRead(BuildContext context, FeedSource source) async {
    final wasOffline = !controller.state.isOnline;
    final cachedUnreadEntryIds = _cachedUnreadEntryIdsForSource(source.id);
    final confirmed = await _confirmBulkSourceRead(
      context,
      title: '标记订阅源已读',
      message: _bulkReadConfirmMessage(
        _redactDiagnosticText(source.name),
        totalUnreadCount: source.unreadCount,
        cachedUnreadCount: cachedUnreadEntryIds.length,
        wasOffline: wasOffline,
      ),
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      await controller.markSourceRead(source.id);
      if (!context.mounted) {
        return;
      }
      _showBulkReadSuccessSnackBar(
        context,
        scopeName: _redactDiagnosticText(source.name),
        totalUnreadCount: source.unreadCount,
        wasOffline: wasOffline,
        cachedUnreadEntryIds: cachedUnreadEntryIds,
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_bulkReadApiErrorMessage(error))));
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下无法批量标记已读')));
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('批量标记请求超时，请稍后重试')));
    }
  }

  Future<void> _markFolderRead(
    BuildContext context,
    String folder,
    int unreadCount,
  ) async {
    final wasOffline = !controller.state.isOnline;
    final cachedUnreadEntryIds = _cachedUnreadEntryIdsForFolder(folder);
    final confirmed = await _confirmBulkSourceRead(
      context,
      title: '标记文件夹已读',
      message: _bulkReadConfirmMessage(
        _redactDiagnosticText(folder),
        totalUnreadCount: unreadCount,
        cachedUnreadCount: cachedUnreadEntryIds.length,
        wasOffline: wasOffline,
      ),
    );
    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      await controller.markFolderRead(folder);
      if (!context.mounted) {
        return;
      }
      _showBulkReadSuccessSnackBar(
        context,
        scopeName: _redactDiagnosticText(folder),
        totalUnreadCount: unreadCount,
        wasOffline: wasOffline,
        cachedUnreadEntryIds: cachedUnreadEntryIds,
      );
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_bulkReadApiErrorMessage(error))));
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下无法批量标记已读')));
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('批量标记请求超时，请稍后重试')));
    }
  }

  String _bulkReadApiErrorMessage(ApiException error) {
    final authMessage = _authExpiredApiErrorMessage(error);
    if (authMessage != null) {
      return authMessage;
    }
    if (error.isNotFound) {
      return '批量标记失败：阅读范围已变化，请同步刷新后重试';
    }
    if (error.isBadRequest) {
      return '批量标记失败：当前阅读范围无法处理，请同步刷新后重试';
    }
    return _apiFailureMessage('批量标记失败', error);
  }

  String _bulkReadConfirmMessage(
    String scopeName, {
    required int totalUnreadCount,
    required int cachedUnreadCount,
    required bool wasOffline,
  }) {
    if (!wasOffline) {
      return '$scopeName 的 $totalUnreadCount 篇未读文章会标记为已读。';
    }
    if (cachedUnreadCount == 0) {
      return '离线时 $scopeName 暂无已缓存未读文章可标记；恢复在线后可处理全部未读。';
    }
    return '离线时仅会将 $scopeName 已缓存的 $cachedUnreadCount 篇未读文章加入待同步。';
  }

  void _showBulkReadSuccessSnackBar(
    BuildContext context, {
    required String scopeName,
    required int totalUnreadCount,
    required bool wasOffline,
    required List<int> cachedUnreadEntryIds,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final canUndo = wasOffline
        ? cachedUnreadEntryIds.isNotEmpty
        : cachedUnreadEntryIds.isNotEmpty &&
              cachedUnreadEntryIds.length == totalUnreadCount;
    final snackBarController = messenger.showSnackBar(
      SnackBar(
        content: Text(
          wasOffline
              ? _offlineQueuedReadMessage(
                  scopeName,
                  cachedUnreadEntryIds.length,
                )
              : '已将 $scopeName 标记为已读',
        ),
        action: canUndo
            ? SnackBarAction(
                label: '撤销',
                onPressed: () {
                  _dismissCurrentReaderSnackBar(context);
                  unawaited(
                    _undoBulkRead(
                      context,
                      cachedUnreadEntryIds,
                      wasOffline: wasOffline,
                    ),
                  );
                },
              )
            : null,
      ),
    );
    _trackReaderSnackBar(snackBarController, hasUndo: canUndo);
  }

  Future<void> _undoBulkRead(
    BuildContext context,
    List<int> entryIds, {
    required bool wasOffline,
  }) async {
    try {
      if (wasOffline) {
        await controller.queueEntriesUnread(entryIds);
      } else {
        await controller.markEntriesUnread(entryIds);
      }
    } on NetworkException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('离线状态下不支持写操作')));
    } on ApiException catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_entryActionApiErrorMessage(error))),
      );
    } on TimeoutException {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请求超时，请稍后重试。')));
    }
  }

  List<int> _cachedUnreadEntryIdsForSource(int sourceId) {
    return controller.state.snapshot.entries.values
        .where((entry) => entry.sourceId == sourceId && !entry.isRead)
        .map((entry) => entry.id)
        .toList(growable: false);
  }

  List<int> _cachedUnreadEntryIdsForFolder(String folder) {
    final folderName = folder.trim().isEmpty
        ? defaultSourceFolder
        : folder.trim();
    final sourceIds = controller.state.snapshot.sources
        .where((source) => _sourceFolderName(source) == folderName)
        .map((source) => source.id)
        .toSet();
    return controller.state.snapshot.entries.values
        .where((entry) => sourceIds.contains(entry.sourceId) && !entry.isRead)
        .map((entry) => entry.id)
        .toList(growable: false);
  }

  String _offlineQueuedReadMessage(String scopeName, int cachedUnreadCount) {
    if (cachedUnreadCount == 0) {
      return '$scopeName 暂无已缓存未读文章可离线标记';
    }
    return '已将 $scopeName 的 $cachedUnreadCount 篇已缓存文章加入待同步';
  }

  Future<bool> _confirmBulkSourceRead(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final sources = state.snapshot.sources;
    final sourceQuery = _sourceSearchQuery.trim();
    final sourceListSortOrder = state.readerPreferences.sourceListSortOrder;
    final now = DateTime.now().toUtc();
    final searchedSources = _filterSources(sources, sourceQuery);
    final filteredSources = _filterSourcesByListFilter(
      searchedSources,
      _sourceListFilter,
      now: now,
    );
    final hasActiveSourceSearch = sourceQuery.isNotEmpty;
    final hasActiveVisibleSourceScope =
        hasActiveSourceSearch || _sourceListFilter != _SourceListFilter.all;
    final sortedSources = _sortSources(
      filteredSources,
      sourceListSortOrder,
      now: now,
    );
    final sourceGroups = _groupSources(sortedSources);
    final health = SourceHealthSummary.fromSources(filteredSources, now: now);
    final filterCounts = _SourceListFilterCounts.fromSources(
      searchedSources,
      now: now,
    );
    final visibleSourceIds = _enabledSourceIds(filteredSources);
    final retryIssueSourceIds = _retryableIssueSourceIds(
      filteredSources,
      now: now,
    );
    final issueSources = _issueSources(filteredSources, now: now);
    final collapsedSourceFolders = state
        .readerPreferences
        .collapsedSourceFolders
        .toSet();
    final collapsedGroups = sourceGroups
        .where((group) => collapsedSourceFolders.contains(group.folder))
        .toList(growable: false);

    final content = sources.isEmpty
        ? ListView(
            padding: const EdgeInsets.fromLTRB(16, 96, 16, 24),
            children: [
              _SourceEmptyState(
                busy: state.busy,
                onAdd: () => _showAddDialog(context),
                onImport: () => _showImportDialog(context),
              ),
            ],
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _SourceSearchField(
                controller: _sourceSearchController,
                focusNode: widget.searchFocusNode,
                resultCount: filteredSources.length,
                totalCount: sources.length,
                hasActiveFilter:
                    _sourceListFilter != _SourceListFilter.all ||
                    sourceListSortOrder != SourceListSortOrder.original,
                onClear: _clearSourceSearch,
                onClearFilters: _clearSourceFilters,
              ),
              const SizedBox(height: 10),
              _SourceListFilterBar(
                selected: _sourceListFilter,
                counts: filterCounts,
                onSelected: _setSourceListFilter,
              ),
              const SizedBox(height: 10),
              _SourceListSortBar(
                selected: sourceListSortOrder,
                onSelected: _setSourceListSort,
              ),
              const SizedBox(height: 12),
              _SourceHealthPanel(
                summary: health,
                selectedFilter: _sourceListFilter,
                visibleRefreshCount: hasActiveVisibleSourceScope
                    ? visibleSourceIds.length
                    : 0,
                retryIssueCount: retryIssueSourceIds.length,
                issueSourceCount: issueSources.length,
                onSelectFilter: _setSourceListFilter,
                onClearFilter: _sourceListFilter == _SourceListFilter.all
                    ? null
                    : () => _setSourceListFilter(_SourceListFilter.all),
                onRefreshVisible:
                    state.busy ||
                        !hasActiveVisibleSourceScope ||
                        visibleSourceIds.isEmpty
                    ? null
                    : () => unawaited(
                        _refreshVisibleSources(context, visibleSourceIds),
                      ),
                onRetryIssues: state.busy || retryIssueSourceIds.isEmpty
                    ? null
                    : () => unawaited(
                        _refreshIssueSources(context, retryIssueSourceIds),
                      ),
                onCopyDiagnostics: issueSources.isEmpty
                    ? null
                    : () => unawaited(
                        _copySourceDiagnosticsBatch(context, issueSources),
                      ),
              ),
              if (collapsedGroups.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SourceFolderOverviewStrip(
                  folderCount: sourceGroups.length,
                  sourceCount: filteredSources.length,
                  unreadSourceCount: filteredSources
                      .where((source) => source.unreadCount > 0)
                      .length,
                  collapsedSourceCount: collapsedGroups.fold<int>(
                    0,
                    (sum, group) => sum + group.sources.length,
                  ),
                  collapsedUnreadCount: collapsedGroups.fold<int>(
                    0,
                    (sum, group) =>
                        sum +
                        group.sources.fold<int>(
                          0,
                          (groupSum, source) => groupSum + source.unreadCount,
                        ),
                  ),
                  onExpandCollapsedSources: collapsedGroups.isEmpty
                      ? null
                      : _expandCollapsedSourceFolders,
                ),
              ],
              const SizedBox(height: 12),
              if (filteredSources.isEmpty)
                _SourceSearchEmptyState(
                  onClear: _clearSourceFilters,
                  onAdd: state.busy ? null : () => _showAddDialog(context),
                  onImport: state.busy
                      ? null
                      : () => _showImportDialog(context),
                )
              else
                for (final group in sourceGroups) ...[
                  _SourceFolderHeader(
                    folder: group.folder,
                    sourceCount: group.sources.length,
                    unreadCount: group.sources.fold<int>(
                      0,
                      (sum, source) => sum + source.unreadCount,
                    ),
                    collapsed: collapsedSourceFolders.contains(group.folder),
                    onToggleCollapsed: () =>
                        _toggleSourceFolderCollapsed(group.folder),
                    onMarkRead: state.busy
                        ? null
                        : () => unawaited(
                            _markFolderRead(
                              context,
                              group.folder,
                              group.sources.fold<int>(
                                0,
                                (sum, source) => sum + source.unreadCount,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  if (!collapsedSourceFolders.contains(group.folder))
                    for (final source in group.sources) ...[
                      _buildSourceCard(context, source, now: now),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 8),
                ],
            ],
          );

    if (mobile) {
      return Column(
        children: [
          AppBar(
            title: const Text('订阅源'),
            actions: [
              IconButton(
                key: const ValueKey<String>('source-refresh-all-button'),
                onPressed: state.busy
                    ? null
                    : () => unawaited(_refreshAllSources(context)),
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                key: const ValueKey<String>('source-import-button'),
                tooltip: '导入 OPML',
                onPressed: state.busy ? null : () => _showImportDialog(context),
                icon: const Icon(Icons.upload_file_rounded),
              ),
              IconButton(
                key: const ValueKey<String>('source-export-button'),
                tooltip: '导出 OPML',
                onPressed: state.busy ? null : () => _exportOpml(context),
                icon: const Icon(Icons.download_rounded),
              ),
              IconButton(
                onPressed: state.busy ? null : () => _showAddDialog(context),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refreshAllSources(context),
              child: content,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '订阅源',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey<String>('source-refresh-all-button'),
                onPressed: state.busy
                    ? null
                    : () => unawaited(_refreshAllSources(context)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新全部'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const ValueKey<String>('source-add-button'),
                onPressed: state.busy ? null : () => _showAddDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const ValueKey<String>('source-import-button'),
                onPressed: state.busy ? null : () => _showImportDialog(context),
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('导入'),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey<String>('source-export-button'),
                tooltip: '导出 OPML',
                onPressed: state.busy ? null : () => _exportOpml(context),
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  List<({String folder, List<FeedSource> sources})> _groupSources(
    List<FeedSource> sources,
  ) {
    final groups = <String, List<FeedSource>>{};
    for (final source in sources) {
      final folder = source.folder.trim().isEmpty
          ? defaultSourceFolder
          : source.folder.trim();
      groups.putIfAbsent(folder, () => <FeedSource>[]).add(source);
    }

    return [
      for (final entry in groups.entries)
        (folder: entry.key, sources: entry.value),
    ];
  }

  Widget _buildSourceCard(
    BuildContext context,
    FeedSource source, {
    required DateTime now,
  }) {
    final status = SourceHealthSummary.statusFor(source, now: now);
    final statusDetail = _sourceStatusDetail(source, status);
    return Semantics(
      key: ValueKey<String>('source-card-${source.id}-semantics'),
      button: true,
      enabled: true,
      label: _sourceCardSemanticsLabel(
        source,
        status: status,
        statusDetail: statusDetail,
      ),
      child: Card(
        key: ValueKey<String>('source-card-${source.id}'),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          onTap: () => controller.openSource(source.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _SourceAvatar(source: source, status: status),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _redactDiagnosticText(source.name),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _redactDiagnosticUrl(source.rssUrl),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _SourceStatusBadge(status: status),
                          Text(
                            source.lastFetchedAt == null
                                ? '从未刷新'
                                : '最近刷新 ${AppFormatters.listDate(source.lastFetchedAt!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      if (statusDetail != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          statusDetail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: status == SourceHealthStatus.error
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${source.unreadCount}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PopupMenuButton<String>(
                      key: ValueKey<String>('source-menu-${source.id}'),
                      onSelected: (value) {
                        switch (value) {
                          case 'mark-read':
                            unawaited(_markSourceRead(context, source));
                          case 'refresh':
                            unawaited(_refreshSource(context, source));
                          case 'copy-rss-url':
                            unawaited(_copySourceRssUrl(context, source));
                          case 'copy-diagnostics':
                            unawaited(_copySourceDiagnostics(context, source));
                          case 'open-site':
                            unawaited(_openSourceSite(context, source));
                          case 'toggle-enabled':
                            unawaited(_toggleSourceEnabled(context, source));
                          case 'edit':
                            unawaited(_showEditDialog(context, source));
                          case 'delete':
                            unawaited(_deleteSource(context, source));
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'mark-read',
                          enabled: source.unreadCount > 0,
                          child: const Text('标记已读'),
                        ),
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Text('刷新'),
                        ),
                        const PopupMenuItem(
                          value: 'copy-rss-url',
                          child: Text('复制 Feed URL'),
                        ),
                        const PopupMenuItem(
                          value: 'copy-diagnostics',
                          child: Text('复制诊断信息'),
                        ),
                        PopupMenuItem(
                          value: 'open-site',
                          enabled: (source.siteUrl ?? '').trim().isNotEmpty,
                          child: const Text('打开站点'),
                        ),
                        PopupMenuItem(
                          value: 'toggle-enabled',
                          child: Text(source.enabled ? '停用自动抓取' : '启用自动抓取'),
                        ),
                        const PopupMenuItem(value: 'edit', child: Text('编辑')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _copySourceRssUrl(BuildContext context, FeedSource source) async {
  await Clipboard.setData(ClipboardData(text: source.rssUrl));
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(
    context,
    '已复制 ${_redactDiagnosticText(source.name)} 的 Feed URL',
    preserveCurrent: true,
  );
}

Future<void> _copySourceDiagnostics(
  BuildContext context,
  FeedSource source,
) async {
  await Clipboard.setData(ClipboardData(text: _sourceDiagnostics(source)));
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(
    context,
    '已复制 ${_redactDiagnosticText(source.name)} 的诊断信息',
    preserveCurrent: true,
  );
}

Future<void> _copySourceDiagnosticsBatch(
  BuildContext context,
  List<FeedSource> sources,
) async {
  await Clipboard.setData(
    ClipboardData(text: _sourceDiagnosticsBatch(sources)),
  );
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(
    context,
    '已复制 ${sources.length} 个问题源的诊断信息',
    preserveCurrent: true,
  );
}

Future<void> _openSourceSite(BuildContext context, FeedSource source) async {
  await _openExternalLink(
    context,
    source.siteUrl,
    unavailableMessage: '站点链接不可用',
    failureMessage: '无法打开站点链接',
  );
}

String _sourceDiagnostics(FeedSource source) {
  final status = SourceHealthSummary.statusFor(
    source,
    now: DateTime.now().toUtc(),
  );
  return [
    'RSS Copilot Source Diagnostics',
    'Name: ${_redactDiagnosticText(source.name)}',
    'Folder: ${_redactDiagnosticText(source.folder)}',
    'Feed URL: ${_redactDiagnosticUrl(source.rssUrl)}',
    'Site URL: ${_redactDiagnosticUrl(source.siteUrl)}',
    'Enabled: ${source.enabled}',
    'Health: ${_sourceHealthStatusLabel(status)}',
    'Unread: ${source.unreadCount}',
    'Last fetched: ${source.lastFetchedAt?.toUtc().toIso8601String() ?? '-'}',
    'Last error at: ${source.lastErrorAt?.toUtc().toIso8601String() ?? '-'}',
    'Last error: ${_redactDiagnosticText(source.lastErrorMessage)}',
    'Suggested action: ${_sourceDiagnosticsSuggestedAction(source, status)}',
  ].join('\n');
}

String _sourceDiagnosticsBatch(List<FeedSource> sources) {
  return [
    'RSS Copilot Source Diagnostics Batch',
    'Issue sources: ${sources.length}',
    for (final source in sources) ...['', _sourceDiagnostics(source)],
  ].join('\n');
}

String _redactDiagnosticUrl(String? value) {
  return diagnostic_redaction.redactDiagnosticUrl(value);
}

String _redactDiagnosticText(String? value, {String emptyPlaceholder = '-'}) {
  return diagnostic_redaction.redactDiagnosticText(
    value,
    emptyPlaceholder: emptyPlaceholder,
  );
}

String? _sourceStatusDetail(FeedSource source, SourceHealthStatus status) {
  return switch (status) {
    SourceHealthStatus.healthy => null,
    SourceHealthStatus.disabled => '已停用自动抓取',
    SourceHealthStatus.error => _sourceErrorDetail(source),
    SourceHealthStatus.stale =>
      source.lastFetchedAt == null ? '尚未成功刷新' : '超过 24 小时未刷新',
  };
}

String _sourceDiagnosticsSuggestedAction(
  FeedSource source,
  SourceHealthStatus status,
) {
  return switch (status) {
    SourceHealthStatus.healthy => '无需处理；如文章缺失可手动刷新此源',
    SourceHealthStatus.disabled => '如仍需接收新文章，请启用自动抓取后刷新此源',
    SourceHealthStatus.stale =>
      source.lastFetchedAt == null
          ? '尚未成功刷新；请手动刷新此源并检查返回结果'
          : '超过 24 小时未刷新；请手动刷新此源',
    SourceHealthStatus.error =>
      _sourceTroubleshootingHint(source.lastErrorMessage) ??
          '查看最近错误并手动刷新；如果持续失败，请检查 Feed URL',
  };
}

String _sourceCardSemanticsLabel(
  FeedSource source, {
  required SourceHealthStatus status,
  required String? statusDetail,
}) {
  final parts = <String>[
    '订阅源',
    _redactDiagnosticText(source.name),
    '文件夹 ${_redactDiagnosticText(_sourceFolderName(source))}',
    '${source.unreadCount} 篇未读',
    '健康状态 ${_sourceHealthStatusLabel(status)}',
    source.lastFetchedAt == null
        ? '从未刷新'
        : '最近刷新 ${AppFormatters.listDate(source.lastFetchedAt!)}',
  ];

  parts.addAll(
    _sourceCardStatusDetailSemantics(
      source,
      status: status,
      statusDetail: statusDetail,
    ),
  );

  parts.add('点击打开该源文章流');
  return parts.join('，');
}

List<String> _sourceCardStatusDetailSemantics(
  FeedSource source, {
  required SourceHealthStatus status,
  required String? statusDetail,
}) {
  if (status == SourceHealthStatus.error) {
    final message = source.lastErrorMessage?.trim();
    return [
      if (message != null && message.isNotEmpty)
        '错误：${_redactDiagnosticText(message)}'
      else
        '最近刷新失败',
      if (source.lastErrorAt != null)
        AppFormatters.listDate(source.lastErrorAt!),
      if (_sourceTroubleshootingHint(message) case final hint?) '建议：$hint',
    ];
  }

  final detail = statusDetail?.trim();
  if (detail == null || detail.isEmpty) {
    return const [];
  }
  return [_redactDiagnosticText(detail)];
}

String _sourceErrorDetail(FeedSource source) {
  final message = source.lastErrorMessage?.trim();
  final hint = _sourceTroubleshootingHint(message);
  final pieces = <String>[
    if (message != null && message.isNotEmpty)
      '错误：${_redactDiagnosticText(message)}'
    else
      '最近刷新失败',
    if (source.lastErrorAt != null) AppFormatters.listDate(source.lastErrorAt!),
    if (hint != null) '建议：$hint',
  ];
  return pieces.join(' · ');
}

String? _sourceTroubleshootingHint(String? rawMessage) {
  final message = rawMessage?.trim();
  if (message == null || message.isEmpty) {
    return null;
  }
  final lower = message.toLowerCase();
  if (lower.contains('timed out') || lower.contains('timeout')) {
    return '稍后重试；如果持续超时，检查源站是否可访问';
  }
  if (lower.contains('could not be resolved') ||
      lower.contains('unknownhost')) {
    return '检查 Feed 域名是否拼写正确或是否已失效';
  }
  if (lower.contains('connection failed') ||
      lower.contains('connection refused')) {
    return '源站拒绝连接，稍后重试或确认 Feed URL 是否仍开放';
  }
  if (lower.contains('tls') ||
      lower.contains('ssl') ||
      lower.contains('certificate')) {
    return '源站证书或 HTTPS 握手异常，可尝试打开原站确认';
  }
  if (lower.contains('response decode') ||
      lower.contains('decompression') ||
      lower.contains('incorrect header')) {
    return '源站响应格式异常，可稍后重试或更换 Feed 地址';
  }
  final httpStatus = RegExp(r'http\s+(\d{3})').firstMatch(lower)?.group(1);
  if (httpStatus == null) {
    return null;
  }
  return switch (httpStatus) {
    '401' || '403' => '源站可能限制抓取；可在浏览器打开原站或更换 Feed 地址',
    '404' || '410' => 'Feed 地址可能已失效；请重新发现或编辑订阅源 URL',
    '429' => '源站限流；稍后重试',
    _ when httpStatus.startsWith('5') => '源站服务异常；稍后重试',
    _ => null,
  };
}

String _sourceHealthStatusLabel(SourceHealthStatus status) {
  return switch (status) {
    SourceHealthStatus.healthy => '正常',
    SourceHealthStatus.disabled => '已停用',
    SourceHealthStatus.error => '抓取异常',
    SourceHealthStatus.stale => '待刷新',
  };
}

List<FeedSource> _filterSources(List<FeedSource> sources, String query) {
  final tokens = searchQueryTokens(query);
  if (tokens.isEmpty) {
    return sources;
  }

  return sources
      .where((source) {
        final searchableText = [
          source.name,
          source.folder,
          source.rssUrl,
          source.siteUrl ?? '',
          source.lastErrorMessage ?? '',
        ].join('\n').toLowerCase();
        return tokens.every(searchableText.contains);
      })
      .toList(growable: false);
}

List<FeedSource> _issueSources(
  List<FeedSource> sources, {
  required DateTime now,
}) {
  return sources
      .where(
        (source) =>
            SourceHealthSummary.statusFor(source, now: now) !=
            SourceHealthStatus.healthy,
      )
      .toList(growable: false);
}

List<int> _enabledSourceIds(List<FeedSource> sources) {
  return [
    for (final source in sources)
      if (source.enabled) source.id,
  ];
}

List<FeedSource> _filterSourcesByListFilter(
  List<FeedSource> sources,
  _SourceListFilter filter, {
  required DateTime now,
}) {
  if (filter == _SourceListFilter.all) {
    return sources;
  }

  return sources
      .where((source) => _sourceMatchesListFilter(source, filter, now: now))
      .toList(growable: false);
}

bool _sourceMatchesListFilter(
  FeedSource source,
  _SourceListFilter filter, {
  required DateTime now,
}) {
  final status = SourceHealthSummary.statusFor(source, now: now);
  return switch (filter) {
    _SourceListFilter.all => true,
    _SourceListFilter.unread => source.unreadCount > 0,
    _SourceListFilter.issues => status != SourceHealthStatus.healthy,
    _SourceListFilter.error => status == SourceHealthStatus.error,
    _SourceListFilter.stale => status == SourceHealthStatus.stale,
    _SourceListFilter.disabled => status == SourceHealthStatus.disabled,
  };
}

List<int> _retryableIssueSourceIds(
  List<FeedSource> sources, {
  required DateTime now,
}) {
  return [
    for (final source in sources)
      if (_sourceHasRetryableIssue(source, now: now)) source.id,
  ];
}

bool _sourceHasRetryableIssue(FeedSource source, {required DateTime now}) {
  final status = SourceHealthSummary.statusFor(source, now: now);
  return status == SourceHealthStatus.error ||
      status == SourceHealthStatus.stale;
}

class _ImportOpmlDialog extends StatefulWidget {
  const _ImportOpmlDialog();

  @override
  State<_ImportOpmlDialog> createState() => _ImportOpmlDialogState();
}

class _ImportOpmlDialogState extends State<_ImportOpmlDialog> {
  final _formKey = GlobalKey<FormState>();
  final _opmlController = TextEditingController();
  bool _refreshAfterImport = true;

  @override
  void dispose() {
    _opmlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AlertDialog(
        title: const Text('导入 OPML'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey<String>('source-import-opml-field'),
                controller: _opmlController,
                minLines: 8,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'OPML XML',
                  alignLabelWithHint: true,
                ),
                validator: (value) => _requiredTextField(value, 'OPML'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('source-import-paste-opml'),
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded),
                  label: const Text('从剪贴板粘贴'),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const ValueKey<String>('source-import-refresh-checkbox'),
                contentPadding: EdgeInsets.zero,
                value: _refreshAfterImport,
                title: const Text('导入后刷新文章'),
                subtitle: const Text('适合刚从其他阅读器迁移，服务端会异步拉取新文章。'),
                onChanged: (value) {
                  setState(() {
                    _refreshAfterImport = value ?? true;
                  });
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '重复订阅、缺少 xmlUrl 或 URL 无效的条目会被跳过并计数。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            key: const ValueKey<String>('source-import-submit'),
            onPressed: _submit,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('导入'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop((
      opml: _opmlController.text.trim(),
      refreshAfterImport: _refreshAfterImport,
    ));
  }

  Future<void> _pasteFromClipboard() async {
    final clipboard = await Clipboard.getData('text/plain');
    final text = clipboard?.text?.trim();
    if (!mounted) {
      return;
    }
    if (text == null || text.isEmpty) {
      _showReaderSnackBar(context, '剪贴板没有 OPML 内容');
      return;
    }
    _opmlController.text = text;
  }
}

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog({required this.folderSuggestions});

  final List<String> folderSuggestions;

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _folderController = TextEditingController(text: defaultSourceFolder);

  @override
  void dispose() {
    _urlController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AlertDialog(
        title: const Text('添加订阅源'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey<String>('source-add-url-field'),
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Feed 或网站 URL',
                  hintText: 'example.com/feed.json',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    _requiredFeedUrlField(value, 'Feed 或网站 URL'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('source-add-folder-field'),
                controller: _folderController,
                decoration: const InputDecoration(
                  labelText: '文件夹',
                  hintText: defaultSourceFolder,
                ),
              ),
              _SourceFolderSuggestionChips(
                keyPrefix: 'source-add-folder-suggestion',
                controller: _folderController,
                folders: widget.folderSuggestions,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('source-add-submit'),
            onPressed: _submit,
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop((
      rssUrl: _urlController.text.trim(),
      folder: _folderController.text.trim().isEmpty
          ? defaultSourceFolder
          : _folderController.text.trim(),
    ));
  }
}

class _EditSourceDialog extends StatefulWidget {
  const _EditSourceDialog({
    required this.source,
    required this.folderSuggestions,
  });

  final FeedSource source;
  final List<String> folderSuggestions;

  @override
  State<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends State<_EditSourceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _folderController;
  late final TextEditingController _rssUrlController;
  late final TextEditingController _iconUrlController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.source.name);
    _folderController = TextEditingController(text: widget.source.folder);
    _rssUrlController = TextEditingController(text: widget.source.rssUrl);
    _iconUrlController = TextEditingController(
      text: widget.source.iconUrl ?? '',
    );
    _enabled = widget.source.enabled;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _folderController.dispose();
    _rssUrlController.dispose();
    _iconUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AlertDialog(
        title: const Text('编辑订阅源'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey<String>('source-edit-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: '名称'),
                textInputAction: TextInputAction.next,
                validator: (value) => _requiredTextField(value, '名称'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('source-edit-folder-field'),
                controller: _folderController,
                decoration: const InputDecoration(
                  labelText: '文件夹',
                  hintText: defaultSourceFolder,
                ),
                textInputAction: TextInputAction.next,
              ),
              _SourceFolderSuggestionChips(
                keyPrefix: 'source-edit-folder-suggestion',
                controller: _folderController,
                folders: widget.folderSuggestions,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('source-edit-rss-url-field'),
                controller: _rssUrlController,
                decoration: const InputDecoration(
                  labelText: 'Feed 或网站 URL',
                  hintText: 'example.com/feed.json',
                ),
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    _requiredFeedUrlField(value, 'Feed 或网站 URL'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey<String>('source-edit-icon-url-field'),
                controller: _iconUrlController,
                decoration: const InputDecoration(labelText: '图标 URL'),
                validator: (value) => _optionalHttpUrlField(value, '图标 URL'),
              ),
              const SizedBox(height: 10),
              _SourceIconPreview(controller: _iconUrlController),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _enabled,
                title: const Text('启用自动抓取'),
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('source-edit-submit'),
            onPressed: _submit,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(
      widget.source.copyWith(
        name: _nameController.text.trim(),
        folder: _folderController.text.trim().isEmpty
            ? defaultSourceFolder
            : _folderController.text.trim(),
        rssUrl: _rssUrlController.text.trim(),
        iconUrl: _iconUrlController.text.trim().isEmpty
            ? null
            : _iconUrlController.text.trim(),
        clearIconUrl: _iconUrlController.text.trim().isEmpty,
        enabled: _enabled,
      ),
    );
  }
}

class _SourceIconPreview extends StatelessWidget {
  const _SourceIconPreview({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final iconUrl = value.text.trim();
        return Row(
          children: [
            Container(
              key: const ValueKey<String>('source-edit-icon-preview'),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: iconUrl.isEmpty
                  ? Icon(
                      Icons.rss_feed_rounded,
                      key: const ValueKey<String>(
                        'source-edit-icon-preview-fallback',
                      ),
                      size: 20,
                    )
                  : Image.network(
                      iconUrl,
                      key: const ValueKey<String>(
                        'source-edit-icon-preview-image',
                      ),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Icon(
                        Icons.rss_feed_rounded,
                        key: const ValueKey<String>(
                          'source-edit-icon-preview-fallback',
                        ),
                        size: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                iconUrl.isEmpty ? '使用默认 RSS 图标' : '当前图标预览',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SourceFolderSuggestionChips extends StatelessWidget {
  const _SourceFolderSuggestionChips({
    required this.keyPrefix,
    required this.controller,
    required this.folders,
  });

  final String keyPrefix;
  final TextEditingController controller;
  final List<String> folders;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final current = _normalizeSourceFolderName(value.text);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final folder in folders)
                  ChoiceChip(
                    key: ValueKey<String>('$keyPrefix-$folder'),
                    selected: current == folder,
                    label: Text(_redactDiagnosticText(folder)),
                    avatar: const Icon(Icons.folder_outlined, size: 16),
                    onSelected: (_) {
                      controller.text = folder;
                      controller.selection = TextSelection.collapsed(
                        offset: folder.length,
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

List<String> _sourceFolderSuggestions(List<FeedSource> sources) {
  final folders = <String>{
    defaultSourceFolder,
    for (final source in sources) _normalizeSourceFolderName(source.folder),
  }.toList(growable: false);
  folders.sort((left, right) {
    if (left == defaultSourceFolder) {
      return right == defaultSourceFolder ? 0 : -1;
    }
    if (right == defaultSourceFolder) {
      return 1;
    }
    return left.toLowerCase().compareTo(right.toLowerCase());
  });
  return folders;
}

String _normalizeSourceFolderName(String folder) {
  final normalized = folder.trim();
  return normalized.isEmpty ? defaultSourceFolder : normalized;
}

String? _requiredTextField(String? value, String label) {
  return value == null || value.trim().isEmpty ? '$label 不能为空' : null;
}

String? _requiredFeedUrlField(String? value, String label) {
  final requiredError = _requiredTextField(value, label);
  if (requiredError != null) {
    return requiredError;
  }
  return _validateFeedUrl(value!.trim(), label);
}

String? _optionalHttpUrlField(String? value, String label) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return null;
  }
  return _validateHttpUrl(trimmed, label);
}

String? _validateFeedUrl(String value, String label) {
  if (value.contains('://')) {
    return _validateHttpUrl(value, label);
  }
  if (_looksLikeSchemeLessUrl(value)) {
    return null;
  }
  return '$label 请输入 http(s) URL 或域名 URL';
}

String? _validateHttpUrl(String value, String label) {
  final uri = Uri.tryParse(value);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null ||
      !uri.hasAuthority ||
      (scheme != 'http' && scheme != 'https')) {
    return '$label 请输入 http(s) URL';
  }
  return null;
}

bool _looksLikeSchemeLessUrl(String value) {
  if (value.contains(' ') || value.contains('@')) {
    return false;
  }
  final host = _schemeLessHost(value);
  if (host == null || host.isEmpty) {
    return false;
  }
  final normalizedHost = host.toLowerCase();
  return normalizedHost == 'localhost' ||
      normalizedHost.contains('.') ||
      normalizedHost.contains(':');
}

String? _schemeLessHost(String value) {
  var url = value.trim();
  if (url.startsWith('//')) {
    url = url.substring(2);
  }
  var endIndex = url.length;
  for (final delimiter in ['/', '?', '#']) {
    final delimiterIndex = url.indexOf(delimiter);
    if (delimiterIndex >= 0 && delimiterIndex < endIndex) {
      endIndex = delimiterIndex;
    }
  }

  final authority = url.substring(0, endIndex);
  if (authority.startsWith('[')) {
    final bracketIndex = authority.indexOf(']');
    return bracketIndex > 0 ? authority.substring(1, bracketIndex) : null;
  }
  final firstColonIndex = authority.indexOf(':');
  if (firstColonIndex >= 0 && firstColonIndex == authority.lastIndexOf(':')) {
    final port = authority.substring(firstColonIndex + 1);
    if (port.isEmpty || int.tryParse(port) == null) {
      return null;
    }
    return authority.substring(0, firstColonIndex);
  }
  return authority;
}

enum _SourceListFilter { all, unread, issues, error, stale, disabled }

List<FeedSource> _sortSources(
  List<FeedSource> sources,
  SourceListSortOrder sort, {
  required DateTime now,
}) {
  final sorted = [...sources];
  switch (sort) {
    case SourceListSortOrder.original:
      return sorted;
    case SourceListSortOrder.unread:
      sorted.sort(
        (left, right) =>
            _compareSourceUnread(left, right) ??
            _compareSourceNames(left, right) ??
            left.id.compareTo(right.id),
      );
    case SourceListSortOrder.health:
      sorted.sort(
        (left, right) =>
            _compareSourceHealth(left, right, now: now) ??
            _compareSourceUnread(left, right) ??
            _compareSourceNames(left, right) ??
            left.id.compareTo(right.id),
      );
    case SourceListSortOrder.name:
      sorted.sort(
        (left, right) =>
            _compareSourceNames(left, right) ?? left.id.compareTo(right.id),
      );
  }
  return sorted;
}

int? _compareSourceUnread(FeedSource left, FeedSource right) {
  final result = right.unreadCount.compareTo(left.unreadCount);
  return result == 0 ? null : result;
}

int? _compareSourceNames(FeedSource left, FeedSource right) {
  final result = left.name.toLowerCase().compareTo(right.name.toLowerCase());
  return result == 0 ? null : result;
}

int? _compareSourceHealth(
  FeedSource left,
  FeedSource right, {
  required DateTime now,
}) {
  final leftRank = _sourceHealthSortRank(
    SourceHealthSummary.statusFor(left, now: now),
  );
  final rightRank = _sourceHealthSortRank(
    SourceHealthSummary.statusFor(right, now: now),
  );
  final result = leftRank.compareTo(rightRank);
  return result == 0 ? null : result;
}

int _sourceHealthSortRank(SourceHealthStatus status) {
  return switch (status) {
    SourceHealthStatus.error => 0,
    SourceHealthStatus.stale => 1,
    SourceHealthStatus.disabled => 2,
    SourceHealthStatus.healthy => 3,
  };
}

class _SourceListFilterCounts {
  const _SourceListFilterCounts({
    required this.total,
    required this.unread,
    required this.issues,
    required this.error,
    required this.stale,
    required this.disabled,
  });

  final int total;
  final int unread;
  final int issues;
  final int error;
  final int stale;
  final int disabled;

  factory _SourceListFilterCounts.fromSources(
    List<FeedSource> sources, {
    required DateTime now,
  }) {
    var unread = 0;
    var issues = 0;
    var error = 0;
    var stale = 0;
    var disabled = 0;

    for (final source in sources) {
      if (source.unreadCount > 0) {
        unread += 1;
      }
      switch (SourceHealthSummary.statusFor(source, now: now)) {
        case SourceHealthStatus.healthy:
          break;
        case SourceHealthStatus.disabled:
          disabled += 1;
          issues += 1;
        case SourceHealthStatus.error:
          error += 1;
          issues += 1;
        case SourceHealthStatus.stale:
          stale += 1;
          issues += 1;
      }
    }

    return _SourceListFilterCounts(
      total: sources.length,
      unread: unread,
      issues: issues,
      error: error,
      stale: stale,
      disabled: disabled,
    );
  }

  int countFor(_SourceListFilter filter) {
    return switch (filter) {
      _SourceListFilter.all => total,
      _SourceListFilter.unread => unread,
      _SourceListFilter.issues => issues,
      _SourceListFilter.error => error,
      _SourceListFilter.stale => stale,
      _SourceListFilter.disabled => disabled,
    };
  }
}

class _SourceListFilterBar extends StatelessWidget {
  const _SourceListFilterBar({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final _SourceListFilter selected;
  final _SourceListFilterCounts counts;
  final ValueChanged<_SourceListFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in _SourceListFilter.values)
          FilterChip(
            key: ValueKey<String>('source-list-filter-${filter.name}'),
            selected: selected == filter,
            avatar: Icon(_sourceListFilterIcon(filter), size: 16),
            label: Text(
              '${_sourceListFilterLabel(filter)} ${counts.countFor(filter)}',
            ),
            onSelected: (_) => onSelected(filter),
          ),
      ],
    );
  }
}

String _sourceListFilterLabel(_SourceListFilter filter) {
  return switch (filter) {
    _SourceListFilter.all => '全部',
    _SourceListFilter.unread => '有未读',
    _SourceListFilter.issues => '待处理',
    _SourceListFilter.error => '报错',
    _SourceListFilter.stale => '待刷新',
    _SourceListFilter.disabled => '停用',
  };
}

IconData _sourceListFilterIcon(_SourceListFilter filter) {
  return switch (filter) {
    _SourceListFilter.all => Icons.rss_feed_rounded,
    _SourceListFilter.unread => Icons.mark_email_unread_outlined,
    _SourceListFilter.issues => Icons.priority_high_rounded,
    _SourceListFilter.error => Icons.error_outline_rounded,
    _SourceListFilter.stale => Icons.update_rounded,
    _SourceListFilter.disabled => Icons.pause_circle_outline_rounded,
  };
}

class _SourceListSortBar extends StatelessWidget {
  const _SourceListSortBar({required this.selected, required this.onSelected});

  final SourceListSortOrder selected;
  final ValueChanged<SourceListSortOrder> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('排序', style: Theme.of(context).textTheme.labelLarge),
        for (final sort in SourceListSortOrder.values)
          ChoiceChip(
            key: ValueKey<String>('source-list-sort-${sort.name}'),
            selected: selected == sort,
            avatar: Icon(_sourceListSortIcon(sort), size: 16),
            label: Text(_sourceListSortLabel(sort)),
            onSelected: (_) => onSelected(sort),
          ),
      ],
    );
  }
}

String _sourceListSortLabel(SourceListSortOrder sort) {
  return switch (sort) {
    SourceListSortOrder.original => '默认',
    SourceListSortOrder.unread => '未读优先',
    SourceListSortOrder.health => '问题优先',
    SourceListSortOrder.name => '名称',
  };
}

IconData _sourceListSortIcon(SourceListSortOrder sort) {
  return switch (sort) {
    SourceListSortOrder.original => Icons.reorder_rounded,
    SourceListSortOrder.unread => Icons.mark_email_unread_outlined,
    SourceListSortOrder.health => Icons.priority_high_rounded,
    SourceListSortOrder.name => Icons.sort_by_alpha_rounded,
  };
}

class _SourceSearchField extends StatelessWidget {
  const _SourceSearchField({
    required this.controller,
    required this.focusNode,
    required this.resultCount,
    required this.totalCount,
    required this.hasActiveFilter,
    required this.onClear,
    required this.onClearFilters,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int resultCount;
  final int totalCount;
  final bool hasActiveFilter;
  final VoidCallback onClear;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.trim().isNotEmpty;
    final filtered = hasQuery || hasActiveFilter;
    return TextField(
      key: const ValueKey<String>('source-search-field'),
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: hasQuery
            ? IconButton(
                key: const ValueKey<String>('source-search-clear'),
                tooltip: '清空搜索',
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
              )
            : hasActiveFilter
            ? IconButton(
                key: const ValueKey<String>('source-search-clear-filters'),
                tooltip: '清空筛选',
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_rounded),
              )
            : null,
        labelText: '查找订阅源',
        hintText: '名称、文件夹或 URL，最多 8 个关键词',
        helperText: filtered
            ? '$resultCount / $totalCount 个匹配'
            : '$totalCount 个订阅源',
      ),
    );
  }
}

class _SourceSearchEmptyState extends StatelessWidget {
  const _SourceSearchEmptyState({
    required this.onClear,
    required this.onAdd,
    required this.onImport,
  });

  final VoidCallback onClear;
  final VoidCallback? onAdd;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 36,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            '没有匹配的订阅源',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const ValueKey<String>('source-search-empty-clear'),
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
                label: const Text('清空筛选'),
              ),
              OutlinedButton.icon(
                key: const ValueKey<String>('source-search-empty-add'),
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加订阅源'),
              ),
              OutlinedButton.icon(
                key: const ValueKey<String>('source-search-empty-import'),
                onPressed: onImport,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('导入 OPML'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceEmptyState extends StatelessWidget {
  const _SourceEmptyState({
    required this.busy,
    required this.onAdd,
    required this.onImport,
  });

  final bool busy;
  final VoidCallback onAdd;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rss_feed_rounded,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              '还没有订阅源',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '添加一个 Feed 或网站 URL，或从其他阅读器导入 OPML。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  key: const ValueKey<String>('source-empty-add-button'),
                  onPressed: busy ? null : onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('添加订阅源'),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey<String>('source-empty-import-button'),
                  onPressed: busy ? null : onImport,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('导入 OPML'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceHealthPanel extends StatelessWidget {
  const _SourceHealthPanel({
    required this.summary,
    required this.selectedFilter,
    required this.visibleRefreshCount,
    required this.retryIssueCount,
    required this.issueSourceCount,
    required this.onSelectFilter,
    this.onClearFilter,
    required this.onRefreshVisible,
    required this.onRetryIssues,
    required this.onCopyDiagnostics,
  });

  final SourceHealthSummary summary;
  final _SourceListFilter selectedFilter;
  final int visibleRefreshCount;
  final int retryIssueCount;
  final int issueSourceCount;
  final ValueChanged<_SourceListFilter> onSelectFilter;
  final VoidCallback? onClearFilter;
  final VoidCallback? onRefreshVisible;
  final VoidCallback? onRetryIssues;
  final VoidCallback? onCopyDiagnostics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintColor = summary.hasIssues
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.monitor_heart_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '订阅源健康',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (onClearFilter != null) ...[
                  IconButton(
                    key: const ValueKey<String>('source-health-clear-filter'),
                    tooltip: '清空健康筛选',
                    onPressed: onClearFilter,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    icon: const Icon(Icons.filter_alt_off_rounded),
                  ),
                  const SizedBox(width: 4),
                ],
                if (visibleRefreshCount > 0) ...[
                  IconButton(
                    key: const ValueKey<String>(
                      'source-health-refresh-visible',
                    ),
                    tooltip: '刷新当前筛选',
                    onPressed: onRefreshVisible,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  '${summary.totalCount} 个源 · ${summary.totalUnreadCount} 未读',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SourceHealthMetric(
                  key: const ValueKey<String>('source-health-metric-unread'),
                  label: '未读积压',
                  count: summary.totalUnreadCount,
                  icon: Icons.mark_email_unread_outlined,
                  color: theme.colorScheme.secondary,
                  selected: selectedFilter == _SourceListFilter.unread,
                  tooltip: '查看有未读的订阅源',
                  onTap: summary.totalUnreadCount == 0
                      ? null
                      : () => onSelectFilter(_SourceListFilter.unread),
                ),
                _SourceHealthMetric(
                  key: const ValueKey<String>('source-health-metric-healthy'),
                  label: '正常',
                  count: summary.healthyCount,
                  icon: Icons.check_circle_outline_rounded,
                  color: theme.colorScheme.primary,
                ),
                _SourceHealthMetric(
                  key: const ValueKey<String>('source-health-metric-error'),
                  label: '报错',
                  count: summary.errorCount,
                  icon: Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                  selected: selectedFilter == _SourceListFilter.error,
                  tooltip: '查看报错订阅源',
                  onTap: summary.errorCount == 0
                      ? null
                      : () => onSelectFilter(_SourceListFilter.error),
                ),
                _SourceHealthMetric(
                  key: const ValueKey<String>('source-health-metric-stale'),
                  label: '待刷新',
                  count: summary.staleCount,
                  icon: Icons.update_rounded,
                  color: theme.colorScheme.tertiary,
                  selected: selectedFilter == _SourceListFilter.stale,
                  tooltip: '查看待刷新订阅源',
                  onTap: summary.staleCount == 0
                      ? null
                      : () => onSelectFilter(_SourceListFilter.stale),
                ),
                _SourceHealthMetric(
                  key: const ValueKey<String>('source-health-metric-disabled'),
                  label: '停用',
                  count: summary.disabledCount,
                  icon: Icons.pause_circle_outline_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  selected: selectedFilter == _SourceListFilter.disabled,
                  tooltip: '查看停用订阅源',
                  onTap: summary.disabledCount == 0
                      ? null
                      : () => onSelectFilter(_SourceListFilter.disabled),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _sourceHealthMessage(summary),
              style: theme.textTheme.bodySmall?.copyWith(
                color: hintColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (retryIssueCount > 0 || issueSourceCount > 0) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (retryIssueCount > 0)
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>('source-health-retry-issues'),
                      onPressed: onRetryIssues,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text('重试待处理 $retryIssueCount'),
                    ),
                  if (issueSourceCount > 0)
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>(
                        'source-health-copy-diagnostics',
                      ),
                      onPressed: onCopyDiagnostics,
                      icon: const Icon(Icons.assignment_outlined, size: 18),
                      label: Text('复制问题诊断 $issueSourceCount'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _sourceHealthMessage(SourceHealthSummary summary) {
  if (summary.totalCount == 0) {
    return '当前筛选没有订阅源。';
  }
  if (!summary.hasIssues) {
    return '全部订阅源都在 24 小时内成功刷新。';
  }

  final retryableCount = summary.errorCount + summary.staleCount;
  if (retryableCount > 0 && summary.disabledCount > 0) {
    return '优先重试报错和待刷新源；停用源需手动启用后才会自动抓取。';
  }
  if (retryableCount > 0) {
    return '优先处理报错和超过 24 小时未刷新的订阅源。';
  }
  return '当前筛选内有停用订阅源，不会自动抓取。';
}

class _SourceFolderOverviewStrip extends StatelessWidget {
  const _SourceFolderOverviewStrip({
    required this.folderCount,
    required this.sourceCount,
    required this.unreadSourceCount,
    required this.collapsedSourceCount,
    required this.collapsedUnreadCount,
    required this.onExpandCollapsedSources,
  });

  final int folderCount;
  final int sourceCount;
  final int unreadSourceCount;
  final int collapsedSourceCount;
  final int collapsedUnreadCount;
  final VoidCallback? onExpandCollapsedSources;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          _QueueWorkloadChip(
            icon: Icons.folder_outlined,
            label: '$folderCount 个文件夹',
          ),
          const SizedBox(width: 8),
          _QueueWorkloadChip(
            icon: Icons.rss_feed_rounded,
            label: '$sourceCount 个订阅源',
          ),
          const SizedBox(width: 8),
          _QueueWorkloadChip(
            icon: Icons.mark_email_unread_outlined,
            label: '$unreadSourceCount 个有未读',
          ),
          if (collapsedSourceCount > 0) ...[
            const SizedBox(width: 8),
            _QueueWorkloadChip(
              actionKey: const ValueKey<String>(
                'source-expand-collapsed-folders',
              ),
              icon: Icons.unfold_less_rounded,
              label: '$collapsedSourceCount 已折叠源',
              tooltip: collapsedUnreadCount > 0
                  ? '展开所有折叠文件夹，包含 $collapsedUnreadCount 篇未读'
                  : '展开所有折叠文件夹',
              onPressed: onExpandCollapsedSources,
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceHealthMetric extends StatelessWidget {
  const _SourceHealthMetric({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    this.selected = false,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = selected
        ? color.withValues(alpha: 0.75)
        : color.withValues(alpha: 0.22);
    final backgroundColor = selected
        ? color.withValues(alpha: 0.16)
        : color.withValues(alpha: 0.1);
    final metric = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$label $count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(label: '订阅源健康指标，$label $count', child: metric);
    }
    final semanticsLabel = selected
        ? '订阅源健康指标，$label $count，当前筛选'
        : '订阅源健康指标，$label $count，点击筛选';
    final interactiveMetric = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: metric,
      ),
    );
    if (tooltip == null) {
      return Semantics(
        button: true,
        enabled: true,
        label: semanticsLabel,
        onTap: onTap,
        child: interactiveMetric,
      );
    }
    return Semantics(
      button: true,
      enabled: true,
      label: semanticsLabel,
      onTap: onTap,
      child: Tooltip(message: tooltip!, child: interactiveMetric),
    );
  }
}

class _SourceStatusBadge extends StatelessWidget {
  const _SourceStatusBadge({required this.status});

  final SourceHealthStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon, color) = switch (status) {
      SourceHealthStatus.healthy => (
        '正常',
        Icons.check_circle_outline_rounded,
        theme.colorScheme.primary,
      ),
      SourceHealthStatus.disabled => (
        '已停用',
        Icons.pause_circle_outline_rounded,
        theme.colorScheme.onSurfaceVariant,
      ),
      SourceHealthStatus.error => (
        '抓取异常',
        Icons.error_outline_rounded,
        theme.colorScheme.error,
      ),
      SourceHealthStatus.stale => (
        '待刷新',
        Icons.update_rounded,
        theme.colorScheme.tertiary,
      ),
    };

    return Semantics(
      label: '订阅源健康状态，$label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceFolderHeader extends StatelessWidget {
  const _SourceFolderHeader({
    required this.folder,
    required this.sourceCount,
    required this.unreadCount,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onMarkRead,
  });

  final String folder;
  final int sourceCount;
  final int unreadCount;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 8),
      child: Row(
        children: [
          IconButton(
            key: ValueKey<String>('source-folder-toggle-$folder'),
            tooltip: collapsed ? '展开文件夹' : '折叠文件夹',
            onPressed: onToggleCollapsed,
            icon: Icon(
              collapsed
                  ? Icons.chevron_right_rounded
                  : Icons.expand_more_rounded,
            ),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.folder_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _redactDiagnosticText(folder),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '$sourceCount 个订阅源 · $unreadCount 未读',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '标记文件夹已读',
            onPressed: unreadCount == 0 ? null : onMarkRead,
            icon: const Icon(Icons.done_all_rounded),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SourceAvatar extends StatelessWidget {
  const _SourceAvatar({required this.source, required this.status});

  final FeedSource source;
  final SourceHealthStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconUrl = source.iconUrl?.trim();
    final icon = switch (status) {
      SourceHealthStatus.healthy => Icons.rss_feed_rounded,
      SourceHealthStatus.disabled => Icons.pause_circle_outline_rounded,
      SourceHealthStatus.error => Icons.error_outline_rounded,
      SourceHealthStatus.stale => Icons.update_rounded,
    };
    final statusColor = switch (status) {
      SourceHealthStatus.healthy => theme.colorScheme.primary,
      SourceHealthStatus.disabled => theme.colorScheme.onSurfaceVariant,
      SourceHealthStatus.error => theme.colorScheme.error,
      SourceHealthStatus.stale => theme.colorScheme.tertiary,
    };

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: iconUrl == null || iconUrl.isEmpty
              ? Icon(icon, size: 20)
              : Image.network(
                  iconUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(icon, size: 20),
                ),
        ),
        if (status != SourceHealthStatus.healthy)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SettingsMenu extends StatelessWidget {
  const _SettingsMenu({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final section in SettingsSection.values) ...[
          Material(
            color: state.settingsSection == section
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: () => controller.changeSettingsSection(section),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  section.label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: state.settingsSection == section
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                    fontWeight: state.settingsSection == section
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SettingsDetailPane extends StatelessWidget {
  const _SettingsDetailPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final settings = state.snapshot.settings;
    return switch (state.settingsSection) {
      SettingsSection.ai => AiSettingsForm(
        settings: settings.ai,
        busy: state.busy,
        onSave: (nextSettings, {rawApiKey, required clearApiKey}) =>
            _runReaderAction(
              context,
              () => controller.saveAiSettings(
                settings: nextSettings,
                rawApiKey: rawApiKey,
                clearApiKey: clearApiKey,
              ),
              onSuccess: () => _showReaderSnackBar(context, 'AI 设置已保存'),
              apiErrorMessage: _aiSettingsApiErrorMessage,
              networkErrorMessage: '当前网络不可用，已切换为离线阅读模式，可稍后重试保存 AI 设置',
              timeoutMessage: 'AI 设置保存请求超时，请稍后重试',
            ),
      ),
      SettingsSection.appearance => _AppearancePane(controller: controller),
      SettingsSection.feeds => _FeedsPane(controller: controller),
      SettingsSection.about => _AboutPane(controller: controller),
    };
  }
}

class _AppearancePane extends StatelessWidget {
  const _AppearancePane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final serverThemeMode = state.snapshot.settings.appearance.themeMode;
    final localOverride = state.session?.themeOverride;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '外观',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Text('所有设备', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<AppThemeMode>(
          key: const ValueKey<String>('server-theme-mode-segmented-button'),
          segments: const [
            ButtonSegment<AppThemeMode>(
              value: AppThemeMode.system,
              icon: Icon(Icons.contrast_rounded),
              label: Text('系统'),
            ),
            ButtonSegment<AppThemeMode>(
              value: AppThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('浅色'),
            ),
            ButtonSegment<AppThemeMode>(
              value: AppThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('深色'),
            ),
          ],
          selected: {serverThemeMode},
          onSelectionChanged: state.busy
              ? null
              : (values) => unawaited(
                  _runReaderAction(
                    context,
                    () => controller.saveAppearanceSettings(values.first),
                    onSuccess: () => _showReaderSnackBar(context, '外观设置已保存'),
                    apiErrorMessage: _appearanceSettingsApiErrorMessage,
                    networkErrorMessage: '当前网络不可用，已切换为离线阅读模式，可稍后重试保存外观设置',
                    timeoutMessage: '外观设置保存请求超时，请稍后重试',
                  ),
                ),
        ),
        const SizedBox(height: 18),
        Text('本机覆盖', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<AppThemeMode?>(
          key: const ValueKey<String>('theme-override-segmented-button'),
          segments: const [
            ButtonSegment<AppThemeMode?>(
              value: null,
              icon: Icon(Icons.cloud_sync_outlined),
              label: Text('跟随'),
            ),
            ButtonSegment<AppThemeMode?>(
              value: AppThemeMode.system,
              icon: Icon(Icons.contrast_rounded),
              label: Text('系统'),
            ),
            ButtonSegment<AppThemeMode?>(
              value: AppThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('浅色'),
            ),
            ButtonSegment<AppThemeMode?>(
              value: AppThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('深色'),
            ),
          ],
          selected: <AppThemeMode?>{localOverride},
          onSelectionChanged: (values) =>
              controller.setThemeOverride(values.first),
        ),
        const SizedBox(height: 16),
        Text(
          '当前：${_themeModeLabel(state.effectiveThemeMode)} · 服务端：${_themeModeLabel(serverThemeMode)}',
        ),
      ],
    );
  }
}

String _themeModeLabel(AppThemeMode mode) {
  return switch (mode) {
    AppThemeMode.system => '系统',
    AppThemeMode.light => '浅色',
    AppThemeMode.dark => '深色',
  };
}

class _FeedsPane extends StatefulWidget {
  const _FeedsPane({required this.controller});

  final AppController controller;

  @override
  State<_FeedsPane> createState() => _FeedsPaneState();
}

class _FeedsPaneState extends State<_FeedsPane> {
  final TextEditingController _languageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _languageController.text = _currentDefaultLanguage;
  }

  @override
  void didUpdateWidget(covariant _FeedsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _currentDefaultLanguage;
    if (_languageController.text != current) {
      _languageController.text = current;
    }
  }

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  String get _currentDefaultLanguage =>
      widget.controller.state.snapshot.settings.feeds.defaultLanguage;

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final settings = state.snapshot.settings;
    final quickLanguages = _feedQuickLanguages(settings.feeds.defaultLanguage);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '订阅',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Text('默认语言', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          key: const ValueKey<String>('feed-default-language-segmented-button'),
          showSelectedIcon: false,
          segments: [
            for (final option in quickLanguages)
              ButtonSegment(value: option.value, label: Text(option.label)),
          ],
          selected: {settings.feeds.defaultLanguage},
          onSelectionChanged: state.busy
              ? null
              : (values) => unawaited(
                  _runReaderAction(
                    context,
                    () => widget.controller.saveFeedSettings(values.first),
                    onSuccess: () => _showReaderSnackBar(context, '默认语言已保存'),
                    apiErrorMessage: _feedSettingsApiErrorMessage,
                    networkErrorMessage: '当前网络不可用，已切换为离线阅读模式，可稍后重试保存默认语言',
                    timeoutMessage: '默认语言保存请求超时，请稍后重试',
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text('当前默认语言：${settings.feeds.defaultLanguage}'),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey<String>('feed-custom-language-field'),
                controller: _languageController,
                decoration: const InputDecoration(
                  labelText: '自定义语言',
                  hintText: '例如 fr-FR',
                  helperText: '使用 BCP 47 语言标签',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: state.busy ? null : (_) => _saveCustomLanguage(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const ValueKey<String>('feed-custom-language-save'),
              onPressed: state.busy ? null : _saveCustomLanguage,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('刷新策略'),
          subtitle: Text(settings.feeds.refreshPolicyDescription),
        ),
      ],
    );
  }

  void _saveCustomLanguage() {
    final validationError = validateLanguageTag(
      _languageController.text,
      '默认语言',
    );
    if (validationError != null) {
      _showReaderSnackBar(context, validationError);
      return;
    }
    final language = normalizeLanguageTag(_languageController.text);
    unawaited(
      _runReaderAction(
        context,
        () => widget.controller.saveFeedSettings(language),
        onSuccess: () => _showReaderSnackBar(context, '默认语言已保存'),
        apiErrorMessage: _feedSettingsApiErrorMessage,
        networkErrorMessage: '当前网络不可用，已切换为离线阅读模式，可稍后重试保存默认语言',
        timeoutMessage: '默认语言保存请求超时，请稍后重试',
      ),
    );
  }
}

List<({String value, String label})> _feedQuickLanguages(String current) {
  const common = [
    (value: 'zh-CN', label: '中文'),
    (value: 'en-US', label: 'English'),
    (value: 'ja-JP', label: '日本語'),
  ];
  if (common.any((option) => option.value == current)) {
    return common;
  }
  return [...common, (value: current, label: current)];
}

class _AboutPane extends StatelessWidget {
  const _AboutPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.state.session;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '关于',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('当前账号'),
          subtitle: Text(session?.user.email ?? '-'),
        ),
        ListTile(
          title: const Text('服务端地址'),
          subtitle: Text(_redactDiagnosticUrl(session?.baseUrl)),
        ),
        ListTile(
          title: const Text('最近同步游标'),
          subtitle: Text(session?.lastServerTime?.toIso8601String() ?? '-'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey<String>('about-copy-diagnostics'),
          onPressed: () => unawaited(_copyDiagnostics(context, controller)),
          icon: const Icon(Icons.content_copy_rounded),
          label: const Text('复制诊断信息'),
        ),
      ],
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final email = controller.state.session?.user.email ?? '-';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Material(
          color: Colors.transparent,
          child: ListTile(title: Text(email)),
        ),
        const SizedBox(height: 8),
        const Material(
          color: Colors.transparent,
          child: ListTile(title: Text('支持登出和查看当前服务器信息')),
        ),
      ],
    );
  }
}

class _AccountDetailPane extends StatelessWidget {
  const _AccountDetailPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.state.session;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '账号',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('邮箱'),
          subtitle: Text(session?.user.email ?? '-'),
        ),
        ListTile(
          title: const Text('显示名称'),
          subtitle: Text(session?.user.displayName ?? '-'),
        ),
        ListTile(
          title: const Text('服务端'),
          subtitle: Text(_redactDiagnosticUrl(session?.baseUrl)),
          trailing: IconButton(
            tooltip: '复制服务端地址',
            onPressed: session == null
                ? null
                : () => unawaited(_copyServerAddress(context, session.baseUrl)),
            icon: const Icon(Icons.copy_rounded),
          ),
        ),
        ListTile(
          title: const Text('诊断信息'),
          subtitle: const Text('复制账号、同步、订阅源和阅读状态'),
          trailing: IconButton(
            key: const ValueKey<String>('account-copy-diagnostics'),
            tooltip: '复制诊断信息',
            onPressed: () => unawaited(_copyDiagnostics(context, controller)),
            icon: const Icon(Icons.assignment_outlined),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: controller.state.busy
              ? null
              : () => unawaited(_confirmLogout(context, controller)),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}

Future<void> _confirmLogout(
  BuildContext context,
  AppController controller,
) async {
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('退出登录？'),
          content: const Text('本机离线缓存和会话将被清除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('退出登录'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) {
    return;
  }
  await _runReaderAction(context, controller.logout);
}

Future<void> _copyServerAddress(BuildContext context, String baseUrl) async {
  await Clipboard.setData(
    ClipboardData(text: diagnostic_redaction.redactDiagnosticUrl(baseUrl)),
  );
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(context, '已复制服务端地址', preserveCurrent: true);
}

Future<void> _copyDiagnostics(
  BuildContext context,
  AppController controller,
) async {
  await Clipboard.setData(ClipboardData(text: _readerDiagnostics(controller)));
  if (!context.mounted) {
    return;
  }
  _showReaderSnackBar(context, '已复制诊断信息', preserveCurrent: true);
}

String _readerDiagnostics(AppController controller) {
  final state = controller.state;
  final snapshot = state.snapshot;
  final settings = snapshot.settings;
  final session = state.session;
  final sources = snapshot.sources;
  final sourceHealth = SourceHealthSummary.fromSources(
    sources,
    now: DateTime.now().toUtc(),
  );
  final sourceIssues = _readerDiagnosticSourceIssues(sources);
  final localTheme = session?.themeOverride?.wireValue ?? 'FOLLOW';
  final lastServerTime = session?.lastServerTime?.toUtc().toIso8601String();
  final searchQuery = normalizeSearchQuery(state.searchQuery);
  final preferences = state.readerPreferences;
  final readingScope = _readerDiagnosticScope(controller);
  final sourceLines = _readerDiagnosticSourceLines(controller);

  return [
    'RSS Copilot Diagnostics',
    'Account: ${_redactDiagnosticText(session?.user.email ?? settings.account.email)}',
    'Display name: ${_redactDiagnosticText(session?.user.displayName ?? settings.account.displayName)}',
    'Server: ${_redactDiagnosticUrl(session?.baseUrl)}',
    'Online: ${state.isOnline}',
    'Pending sync: ${state.pendingSyncCount}',
    'Pending sync detail: ${_redactDiagnosticText(state.pendingSyncDescription)}',
    'Last server time: ${lastServerTime ?? '-'}',
    'Section: ${state.section.title}',
    'Reading scope: ${_redactDiagnosticText(readingScope)}',
    ...sourceLines,
    'Search: ${_redactDiagnosticText(searchQuery)}',
    'Unread only: ${state.unreadOnly}',
    'Continue reading only: ${state.inProgressOnly}',
    'Sources: ${sourceHealth.totalCount} total, ${sourceHealth.healthyCount} healthy, ${sourceHealth.errorCount} error, ${sourceHealth.staleCount} stale, ${sourceHealth.disabledCount} disabled',
    'Source issues: $sourceIssues',
    'Unread: feed ${controller.unreadCountForSection(AppSection.feed)}, saved ${controller.unreadCountForSection(AppSection.saved)}, noise ${controller.unreadCountForSection(AppSection.noise)}',
    'Visible: ${controller.visibleEntries.length} entries, ${controller.visibleUnreadCount} unread',
    'Theme: server ${settings.appearance.themeMode.wireValue}, local $localTheme, effective ${state.effectiveThemeMode.wireValue}',
    'Language: ${settings.feeds.defaultLanguage}',
    'Reader: font ${preferences.fontSize.toStringAsFixed(1)}, line ${preferences.lineHeight.toStringAsFixed(2)}, width ${preferences.width.name}, sort ${preferences.entrySortOrder.name}, queue ${preferences.entryQueueFilter.name}, density ${preferences.entryListDensity.name}, sourceSort ${preferences.sourceListSortOrder.name}, translations ${preferences.showTranslations}',
    'Collapsed dates: ${_diagnosticList(preferences.collapsedEntryDateSections)}',
    'Collapsed source folders: ${_diagnosticList(preferences.collapsedSourceFolders)}',
    'AI: provider ${settings.ai.provider}, configured ${settings.ai.configured}, output ${settings.ai.outputLanguage}, summary ${settings.ai.autoSummaryEnabled}, translation ${settings.ai.autoTranslationEnabled}',
  ].join('\n');
}

String _readerDiagnosticSourceIssues(List<FeedSource> sources) {
  final now = DateTime.now().toUtc();
  final issueSources = [
    for (final source in sources)
      (source: source, status: SourceHealthSummary.statusFor(source, now: now)),
  ].where((item) => item.status != SourceHealthStatus.healthy).toList();

  if (issueSources.isEmpty) {
    return '-';
  }

  const maxIssueSources = 5;
  final issueSummaries = issueSources.take(maxIssueSources).map((item) {
    final source = item.source;
    final status = item.status;
    return [
      '${_redactDiagnosticText(source.name)} (#${source.id})',
      _sourceHealthStatusLabel(status),
      _sourceDiagnosticsSuggestedAction(source, status),
    ].join(' · ');
  }).toList();
  final remainingCount = issueSources.length - issueSummaries.length;
  if (remainingCount > 0) {
    issueSummaries.add('+$remainingCount more');
  }
  return issueSummaries.join('; ');
}

List<String> _readerDiagnosticSourceLines(AppController controller) {
  final state = controller.state;
  if (state.section != AppSection.sourceEntries) {
    return const [];
  }
  final source = controller.selectedSource;
  if (source == null) {
    return const ['Source: -'];
  }

  final status = SourceHealthSummary.statusFor(
    source,
    now: DateTime.now().toUtc(),
  );
  return [
    'Source: ${_redactDiagnosticText(source.name)} (#${source.id})',
    'Source folder: ${_redactDiagnosticText(source.folder)}',
    'Source feed URL: ${_redactDiagnosticUrl(source.rssUrl)}',
    'Source site URL: ${_redactDiagnosticUrl(source.siteUrl)}',
    'Source enabled: ${source.enabled}',
    'Source health: ${_sourceHealthStatusLabel(status)}',
    'Source unread: ${source.unreadCount}',
    'Source last fetched: ${source.lastFetchedAt?.toUtc().toIso8601String() ?? '-'}',
    'Source last error: ${_redactDiagnosticText(source.lastErrorMessage)}',
    'Source suggested action: ${_sourceDiagnosticsSuggestedAction(source, status)}',
  ];
}

String _diagnosticList(List<String> values) {
  if (values.isEmpty) {
    return '-';
  }
  return values.map(_redactDiagnosticText).join(', ');
}

String _readerDiagnosticScope(AppController controller) {
  final state = controller.state;
  if (state.section == AppSection.sourceEntries) {
    final source = controller.selectedSource;
    final sourceId = state.selectedSourceId;
    if (source != null) {
      return 'source page ${source.name} (#${source.id})';
    }
    return sourceId == null ? 'source page -' : 'source page #$sourceId';
  }

  final sourceFilterId = state.entrySourceFilterId;
  if (sourceFilterId != null) {
    final source = state.snapshot.sourceById(sourceFilterId);
    return source == null
        ? 'source filter #$sourceFilterId'
        : 'source filter ${source.name} (#$sourceFilterId)';
  }

  final folder = state.entryFolderFilter;
  if (folder != null && folder.isNotEmpty) {
    return 'folder filter $folder';
  }

  return 'all';
}
